import SwiftUI
import Photos

struct PreviewAsset: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}

struct SwipeCard<Content: View>: View {
    let content: Content
    let choose: (Bool) -> Void
    let preview: () -> Void
    @GestureState private var drag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content.clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(alignment: drag < 0 ? .topLeading : .topTrailing) {
                if abs(drag) > 24 {
                    Text(drag < 0 ? "TO BIN" : "KEEP").font(.headline.bold()).padding(12)
                        .foregroundStyle(Color.asphalt).background(Color.track, in: Capsule()).padding(12)
                }
            }
            .rotationEffect(.degrees(reduceMotion ? 0 : Double(drag)/34))
            .offset(x: reduceMotion ? 0 : drag * 0.72)
            .contentShape(Rectangle()).onTapGesture(perform: preview)
            .gesture(DragGesture(minimumDistance: 18)
                .updating($drag) { value, state, _ in state = value.translation.width }
                .onEnded { value in
                    let x = value.translation.width
                    if abs(x) > 65 && abs(x) > abs(value.translation.height) { choose(x > 0) }
                })
            .accessibilityElement(children: .ignore).accessibilityLabel("Photo card")
            .accessibilityIdentifier("photoCard")
            .accessibilityAddTraits(.isButton).accessibilityAction { preview() }
            .accessibilityAction(named: "To bin") { choose(false) }
            .accessibilityAction(named: "Keep") { choose(true) }
    }
}

struct ReviewControls: View {
    let choose: (Bool) -> Void
    var body: some View {
        HStack(spacing: 10) {
            Button { choose(false) } label: { label("To bin", "arrow.left", active: false) }
                .accessibilityIdentifier("queuePhoto")
            Button { choose(true) } label: { label("Keep", "arrow.right", active: true) }
                .accessibilityIdentifier("keepPhoto")
        }.buttonStyle(.plain)
    }
    private func label(_ title: String, _ icon: String, active: Bool) -> some View {
        Label(title, systemImage: icon).font(.headline).frame(maxWidth: .infinity)
            .padding(.vertical, 16).foregroundStyle(active ? Color.asphalt : .white)
            .background(active ? Color.track : .lane, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ReviewScreen: View {
    let month: Month
    let openBin: () -> Void
    @EnvironmentObject private var library: Library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var history: [(id: String, keep: Bool)] = []
    @State private var preview: PreviewAsset?

    var body: some View {
        let batch = library.round(month)
        let pending = batch.filter { library.decision($0.localIdentifier) == nil }
        let done = batch.count - pending.count
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        TimingLabel("ROUND / \(month.name)").foregroundStyle(Color.track)
                        Spacer()
                        Text("\(done) / \(batch.count)").font(.headline.monospacedDigit())
                            .contentTransition(.numericText()).accessibilityIdentifier("roundProgress")
                    }
                    ProgressView(value: Double(done), total: Double(max(1,batch.count))).tint(.track)
                    if let asset = pending.first {
                        if let date = asset.creationDate {
                            Text(date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "en_US"))))
                                .font(.title2.bold())
                        }
                        SwipeCard(content: AssetImage(asset: asset, pixels: 1400, fit: true),
                                  choose: { choose(asset, keep: $0) }, preview: { preview = PreviewAsset(asset: asset) })
                            .frame(height: max(205, geo.size.height - 240))
                            .transition(.asymmetric(insertion: .scale(scale: 0.97).combined(with: .opacity), removal: .opacity))
                            .id(asset.localIdentifier)
                        HStack {
                            Label(asset.mediaSubtypes.contains(.photoLive) ? "Live Photo" : "Photo",
                                  systemImage: asset.mediaSubtypes.contains(.photoLive) ? "livephoto" : "photo")
                            Spacer()
                            if asset.isFavorite { Label("Favorite", systemImage: "heart.fill") }
                        }.font(.caption).foregroundStyle(.secondary)
                        ReviewControls { choose(asset, keep: $0) }
                    } else if !library.hasAccess {
                        Text("Photo access changed").font(.title.bold())
                        Button("Back to home") { dismiss() }
                    } else {
                        Image(systemName: "flag.checkered").font(.system(size: 42)).foregroundStyle(Color.track)
                        Text("Round complete").font(.largeTitle.bold())
                        let queued = batch.filter { library.decision($0.localIdentifier) == false }.count
                        Text("Kept: \(done - queued)   ·   In bin: \(queued)").font(.headline)
                        Button(action: openBin) { ActionLabel(title: "Review bin", icon: "tray") }.buttonStyle(.plain)
                        if library.reviewed(month) < library.assets(in: month).count {
                            Button("Next 20 photos") { start(whole: false) }
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        Button("Back to home") { dismiss() }.frame(maxWidth: .infinity, minHeight: 44)
                    }
                    if let last = history.last, library.decision(last.id) == last.keep {
                        Button { library.undo(last.id, expected: last.keep); history.removeLast() } label: {
                            Label("Undo swipe", systemImage: "arrow.uturn.backward")
                        }.font(.subheadline).frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("undoSwipe")
                    }
                }.animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: pending.first?.localIdentifier)
                    .padding(18).frame(maxWidth: 580)
            }.frame(maxWidth: .infinity)
        }
        .background(Color.asphalt).navigationTitle(month.name).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button(action: openBin) { Image(systemName: "tray") }
                .accessibilityLabel("Review bin").accessibilityIdentifier("reviewBin")
            Menu {
                Button("Review the rest of this month") { start(whole: true) }
            } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Round options")
        }
        .sheet(item: $preview) { PhotoPreview(asset: $0.asset) }
    }
    private func start(whole: Bool) { history.removeAll(); library.begin(month, whole: whole, newRound: true) }
    private func choose(_ asset: PHAsset, keep: Bool) {
        if library.decide(asset, keep: keep) {
            history.append((asset.localIdentifier, keep))
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}

struct PracticeScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var choices: [Bool] = []
    private let names = ["The stadium", "The bend", "Finish line"]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TimingLabel("PRACTICE  /  \(choices.count) OF 3").foregroundStyle(Color.track)
            if choices.count < 3 {
                Text("Swipe left to queue. Swipe right to keep.").font(.title2.bold())
                SwipeCard(content: ZStack {
                    Color.lane
                    TrackMark().rotationEffect(.degrees(Double(choices.count) * 65))
                    VStack { Spacer(); Text(names[choices.count]).font(.largeTitle.bold()).padding() }
                }, choose: choose, preview: {})
                ReviewControls(choose: choose)
            } else {
                Text("Round complete").font(.largeTitle.bold())
                Text("Kept: \(choices.filter { $0 }.count)   ·   In bin: \(choices.filter { !$0 }.count)")
                Button { dismiss() } label: { ActionLabel(title: "Back to home") }.buttonStyle(.plain)
            }
            if !choices.isEmpty { Button("Undo swipe") { choices.removeLast() }.padding(.vertical, 8) }
        }.padding(20).frame(maxHeight: .infinity).background(Color.asphalt)
            .navigationTitle("Practice").navigationBarTitleDisplayMode(.inline)
    }
    private func choose(_ keep: Bool) { if choices.count < 3 { choices.append(keep) } }
}
