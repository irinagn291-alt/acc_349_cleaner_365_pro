# fastlane 2.232's language list stops at the 2020 set. It has no sl-SI,
# bn-BD, ur-PK, or the India locales Apple added later. Deliverfile sets
# ignore_language_directory_validation so an unknown folder does not abort
# the lane — Loader still drops that folder, so the locale is created on
# App Store Connect and then left with no metadata and no screenshots.
# Register the codes before screenshots and metadata are collected.
if defined?(Deliver::Languages::ALL_LANGUAGES)
  store_locales = %w[
    bn-BD gu-IN kn-IN ml-IN mr-IN or-IN pa-IN sl-SI ta-IN te-IN ur-PK
  ]
  current = Deliver::Languages::ALL_LANGUAGES
  missing = store_locales.reject { |code| current.any? { |have| have.to_s.casecmp?(code) } }
  unless missing.empty?
    Deliver::Languages.send(:remove_const, :ALL_LANGUAGES)
    Deliver::Languages.const_set(:ALL_LANGUAGES, current.to_a + missing)
  end
end

# fastlane#30094 — gem on Bitrise (2.232–2.238) re-uploads the set because
# Apple has not published sourceFileChecksum yet. Official fix is merged to
# master, not released. Same wait + delete-before-retry as PR 30150.

require "timeout"

# Spaceship otherwise waits up to 20 minutes for each failed reservation,
# before deliver's own processing timeout even starts.
ENV["SPACESHIP_SCREENSHOT_UPLOAD_TIMEOUT"] ||= "2"

module GFDeliverScreenshotFix
  def upload(options, screenshots)
    # Bound the whole screenshot phase, including queue workers, Apple 500s,
    # processing and retries. The per-processing timeout alone cannot do that.
    Timeout.timeout(15 * 60) { super }
  rescue Timeout::Error
    FastlaneCore::UI.user_error!("App Store screenshot upload timed out after 15 minutes. Apple may still be processing uploaded files. Retry Upload listing when Apple responds.")
  end

  def upload_screenshots(localizations, screenshots_per_language, timeout_seconds, tries: 2)
    super(localizations, screenshots_per_language, timeout_seconds, tries: [tries, 2].min)
  end

  def wait_for_complete(iterator, timeout_seconds)
    start_time = Time.now
    loop do
      number_of_screenshots_missing_checksum = 0
      states = iterator.each_app_screenshot.map { |_, _, app_screenshot| app_screenshot }.each_with_object({}) do |app_screenshot, hash|
        state = app_screenshot.asset_delivery_state["state"]
        hash[state] ||= 0
        hash[state] += 1
        number_of_screenshots_missing_checksum += 1 if state == "COMPLETE" && app_screenshot.source_file_checksum.nil?
      end

      is_processing = states.fetch("UPLOAD_COMPLETE", 0) > 0 || number_of_screenshots_missing_checksum > 0
      return states unless is_processing

      if Time.now - start_time > timeout_seconds
        FastlaneCore::UI.important("Screenshot upload reached the timeout limit of #{timeout_seconds} seconds. We'll now retry uploading the screenshots that couldn't be uploaded in time.")
        return states
      end

      if number_of_screenshots_missing_checksum > 0
        FastlaneCore::UI.verbose("There are still incomplete screenshots - #{states}, missing checksum: #{number_of_screenshots_missing_checksum}")
      else
        FastlaneCore::UI.verbose("There are still incomplete screenshots - #{states}")
      end
      sleep(5)
    end
  end

  def retry_upload_screenshots_if_needed(iterator, states, number_of_screenshots, tries, timeout_seconds, localizations, screenshots_per_language)
    is_failure = states.fetch("FAILED", 0) > 0
    is_processing = states.fetch("UPLOAD_COMPLETE", 0) > 0
    is_missing_screenshot = !screenshots_per_language.empty? && !verify_local_screenshots_are_uploaded(iterator, screenshots_per_language)
    return unless is_failure || is_missing_screenshot || is_processing

    if tries.zero?
      iterator.each_app_screenshot.select { |_, _, app_screenshot| app_screenshot.error? }.each do |localization, _, app_screenshot|
        FastlaneCore::UI.error("#{app_screenshot.file_name} for #{localization.locale} has error(s) - #{app_screenshot.error_messages.join(', ')}")
      end
      incomplete_screenshot_count = states.except("COMPLETE").reduce(0) { |sum, (k, v)| sum + v }
      FastlaneCore::UI.user_error!("Failed verification of all screenshots uploaded... #{incomplete_screenshot_count} incomplete screenshot(s) still exist")
    else
      FastlaneCore::UI.error("Failed to upload all screenshots... Tries remaining: #{tries}")
      iterator.each_app_screenshot do |_, _, app_screenshot|
        app_screenshot.delete! unless app_screenshot.complete? && !app_screenshot.source_file_checksum.nil?
      end
      upload_screenshots(localizations, screenshots_per_language, timeout_seconds, tries: tries)
    end
  end
end

Deliver::UploadScreenshots.prepend(GFDeliverScreenshotFix)
