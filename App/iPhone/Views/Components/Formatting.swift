import SwiftUI
import TrainingCore

extension LocalDate {
    /// 当天正午（设备时区），用于显示
    var noon: Date { date(atHour: 12, minute: 0, in: .current) ?? Date() }

    /// “10月14日 星期三”
    var longText: String {
        noon.formatted(.dateTime.month(.wide).day().weekday(.wide).locale(Locale(identifier: "zh_CN")))
    }

    /// “10月14日 周三”
    var shortText: String {
        noon.formatted(.dateTime.month(.abbreviated).day().weekday(.abbreviated).locale(Locale(identifier: "zh_CN")))
    }
}

extension RecordStatus {
    var color: Color {
        switch self {
        case .completed: return .green
        case .partial: return .mint
        case .skipped: return .secondary
        case .snoozed: return .orange
        }
    }

    var symbol: String {
        switch self {
        case .completed: return "checkmark.circle.fill"
        case .partial: return "circle.dashed"
        case .skipped: return "forward.circle"
        case .snoozed: return "clock"
        }
    }
}

extension SetSummary {
    /// “3×10 @10kg” / “3×30秒”
    var targetText: String { formatExerciseTarget(sets: sets, reps: reps, durationSec: durationSec, weightKg: weightKg) }
}

/// 只读展示组记录
struct SetListView: View {
    let sets: [SetLog]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(summarizeSets(sets), id: \.exerciseId) { s in
                HStack {
                    Text(s.name).foregroundStyle(.secondary)
                    Spacer()
                    Text(s.targetText).monospacedDigit().foregroundStyle(.green)
                }
                .font(.caption)
            }
        }
    }
}
