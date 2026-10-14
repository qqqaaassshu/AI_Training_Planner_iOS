import SwiftUI
import TrainingCore
import WidgetKit

/// 表盘复杂功能：今日进度与下一个任务。数据由手表 App 写到 App Group 共享目录
struct ComplicationEntry: TimelineEntry {
    let date: Date
    let summary: ComplicationSummary
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: Date(), summary: ComplicationSummary(done: 1, total: 3, nextTitle: "力量训练", nextTime: Date(), nextIsWorkout: true))
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        let snap = Self.load()
        completion(ComplicationEntry(date: Date(), summary: complicationSummary(plan: snap?.plan, records: snap?.records ?? [], now: Date())))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let snap = Self.load()
        let now = Date()
        let entries = complicationTimeline(plan: snap?.plan, records: snap?.records ?? [], now: now)
            .map { ComplicationEntry(date: $0.date, summary: $0.summary) }
        // 手表 App 数据变化时会主动刷新；这里兜底每 6 小时重新读取
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(6 * 3600))))
    }

    static func load() -> WatchSnapshot? {
        guard let url = WidgetShared.snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? WatchSnapshot.decode(data)
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    var body: some View {
        let s = entry.summary
        switch family {
        case .accessoryCircular:
            Gauge(value: s.fraction) {
                Image(systemName: "figure.strengthtraining.traditional")
            } currentValueLabel: {
                Text("\(s.done)/\(s.total)")
            }
            .gaugeStyle(.accessoryCircular)
        case .accessoryCorner:
            Image(systemName: s.nextIsWorkout ? "figure.strengthtraining.traditional" : "checkmark.circle")
                .widgetLabel {
                    Gauge(value: s.fraction) { Text("今日") }
                }
        case .accessoryInline:
            if let title = s.nextTitle, let t = s.nextTime {
                Text("\(t.formatted(date: .omitted, time: .shortened)) \(title)")
            } else {
                Text("今日 \(s.done)/\(s.total)")
            }
        default:
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: "figure.strengthtraining.traditional")
                    Text("今日 \(s.done)/\(s.total)").font(.headline)
                }
                if let title = s.nextTitle, let t = s.nextTime {
                    Text(title).lineLimit(1)
                    Text(t, style: .time).foregroundStyle(.secondary)
                } else {
                    Text(s.total == 0 ? "今天没有任务" : "今天的任务都处理完了").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@main
struct TrainingComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TrainingComplication", provider: ComplicationProvider()) { entry in
            ComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("训练计划")
        .description("今日进度与下一个任务")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
