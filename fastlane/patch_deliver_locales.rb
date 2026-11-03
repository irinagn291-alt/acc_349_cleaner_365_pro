# Managed by gambling-factory. English source copy and stale locale folders
# may remain on disk, but only the Task's languages may reach App Store Connect.
require "json"

module GFDeliverLocales
  def self.load(path)
    @locales = nil
    codes = JSON.parse(File.read(path))
    unless codes.is_a?(Array) && !codes.empty? && codes.all? { |code| code.is_a?(String) && code.match?(/\A[a-z]{2,3}(?:-[A-Za-z0-9]+)*\z/) }
      raise "Invalid Task locales in #{path}; set the Task's primary language before uploading."
    end
    @locales = codes.uniq.freeze
  end

  def self.locales
    raise "No Task locales configured; refusing to upload with default languages." unless @locales
    @locales.dup
  end

  def self.restrict_options(options)
    allowed = locales
    options[:languages] = allowed
    keys = Deliver::UploadMetadata::LOCALISED_VERSION_VALUES.keys + Deliver::UploadMetadata::LOCALISED_APP_VALUES.keys
    keys.each do |key|
      value = options[key]
      options[key] = value.select { |code, _| allowed.include?(code.to_s) } if value.is_a?(Hash)
    end
  end

  def self.select_localizations(rows)
    allowed = locales
    rows.select { |row| allowed.include?(row.locale) }
  end
end

module GFDeliverLocaleFolders
  def language_folders(root, ignore_validation, expand_sub_folders = false)
    allowed = GFDeliverLocales.locales
    super.select { |folder| allowed.include?(folder.language) }
         .sort_by { |folder| allowed.index(folder.language) }
  end
end
Deliver::Loader.singleton_class.prepend(GFDeliverLocaleFolders)

module GFDeliverMetadataLocales
  def load_from_filesystem
    GFDeliverLocales.restrict_options(options)
    super
    GFDeliverLocales.restrict_options(options)
  end

  def detect_languages
    GFDeliverLocales.locales
  end

  def upload
    GFDeliverLocales.restrict_options(options)
    super
  end
end
Deliver::UploadMetadata.prepend(GFDeliverMetadataLocales)

module GFDeliverRunnerLocales
  def upload_metadata
    result = super
    return result if options[:skip_metadata]

    # Wait for metadata AND screenshots before changing primary. Only edit
    # the pending version/info; published versions are never pruned here.
    allowed = GFDeliverLocales.locales
    app = Deliver.cache[:app]
    platform = Spaceship::ConnectAPI::Platform.map(options[:platform])
    version = app.get_edit_app_store_version(platform: platform)
    info = app.fetch_edit_app_info
    raise "Cannot reconcile Task locales without an editable App Store version and App Info." unless version && info
    version_rows = version.get_app_store_version_localizations
    info_rows = info.get_app_info_localizations
    missing = (allowed - version_rows.map(&:locale)) | (allowed - info_rows.map(&:locale))
    raise "Task locales missing after upload: #{missing.join(', ')}" unless missing.empty?

    primary = allowed.first
    if app.primary_locale != primary
      app.update(attributes: { primaryLocale: primary })
      app.primary_locale = primary
      FastlaneCore::UI.message("Primary language from the Task: #{primary}")
    end
    (version_rows + info_rows).each do |localization|
      next if allowed.include?(localization.locale)
      localization.delete!
      FastlaneCore::UI.message("Removed localization outside the Task: #{localization.locale}")
    end
    result
  end
end
Deliver::Runner.prepend(GFDeliverRunnerLocales)

module GFDeliverScreenshotLocales
  def upload(options, screenshots)
    allowed = GFDeliverLocales.locales
    super(options, screenshots.select { |shot| allowed.include?(shot.language) })
  end

  def upload_screenshots(localizations, screenshots_per_language, timeout_seconds, tries: 5)
    allowed = GFDeliverLocales.locales
    super(GFDeliverLocales.select_localizations(localizations),
          screenshots_per_language.select { |code, _| allowed.include?(code) },
          timeout_seconds, tries: tries)
  end

  def delete_screenshots(localizations, screenshots_per_language, tries: 5)
    super(GFDeliverLocales.select_localizations(localizations), screenshots_per_language, tries: tries)
  end

  def sort_screenshots(localizations)
    super(GFDeliverLocales.select_localizations(localizations))
  end
end
Deliver::UploadScreenshots.prepend(GFDeliverScreenshotLocales)
