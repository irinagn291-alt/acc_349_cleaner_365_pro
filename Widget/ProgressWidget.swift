import SwiftUI
import WidgetKit

struct SummaryEntry: TimelineEntry { let date: Date; let summary: ReviewSummary }
struct SummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry { SummaryEntry(date: Date(),summary: ReviewSummary()) }
    func getSnapshot(in context: Context,completion: @escaping (SummaryEntry)->Void) { completion(SummaryEntry(date: Date(),summary: .read())) }
    func getTimeline(in context: Context,completion: @escaping (Timeline<SummaryEntry>)->Void) { completion(Timeline(entries: [SummaryEntry(date: Date(),summary: .read())],policy: .after(Date().addingTimeInterval(3600)))) }
}
struct Cleaner365WidgetView: View {
    let entry: SummaryEntry
    @Environment(\.widgetFamily) var family
    var body: some View {
        VStack(alignment: .leading,spacing: 10) {
            HStack { Image(systemName: "flag.checkered"); Text("CLEANER / 365").font(.caption2.monospaced().bold()).lineLimit(1).minimumScaleFactor(0.78); Spacer(); Image(systemName: "arrow.up.right").font(.caption) }.foregroundStyle(Color(red: 0.81,green: 0.98,blue: 0.27))
            Spacer(minLength: 0)
            if entry.summary.updated == nil { Text("Your first\nround").font(.system(.title2,design: .rounded,weight: .semibold)); Text("Open Cleaner 365").font(.caption).foregroundStyle(.white.opacity(0.76)) }
            else {
                Text("\(entry.summary.reviewed)").font(.system(size: 34,weight: .semibold,design: .rounded)).minimumScaleFactor(0.6)
                Text("of \(entry.summary.total) photos reviewed").font(.caption).foregroundStyle(.white.opacity(0.76))
                if family == .systemMedium { Text("\(entry.summary.queued) in your review queue").font(.caption.weight(.medium)) }
                ProgressView(value: Double(entry.summary.reviewed),total: Double(max(entry.summary.total,1))).tint(Color(red: 0.81,green: 0.98,blue: 0.27))
            }
        }.foregroundStyle(.white).containerBackground(Color(red: 0.067,green: 0.075,blue: 0.074),for: .widget).widgetURL(URL(string: "cleaner365://review"))
    }
}
@main
struct Cleaner365Widget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Cleaner365Widget",provider: SummaryProvider()) { Cleaner365WidgetView(entry: $0).environment(\.locale,Locale(identifier: "en_US")) }.configurationDisplayName("Season progress").description("Your library review, at a glance.").supportedFamilies([.systemSmall,.systemMedium])
    }
}
