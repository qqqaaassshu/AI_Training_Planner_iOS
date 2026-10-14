import SwiftUI

/// 0–10 评分。拖动时只更新显示，松手后才回调保存
struct ScoreSlider: View {
    let title: String
    let value: Int?
    var minLabel = "低"
    var maxLabel = "高"
    var hint: String?
    let onCommit: (Int) -> Void

    @State private var editing: Double?

    var body: some View {
        let shown = editing.map { Int($0.rounded()) } ?? value
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(shown.map(String.init) ?? "–").font(.headline).monospacedDigit().foregroundStyle(.tint)
            }
            Slider(
                value: Binding(get: { editing ?? Double(value ?? 0) }, set: { editing = $0 }),
                in: 0...10,
                step: 1
            ) { isEditing in
                if !isEditing, let v = editing {
                    onCommit(Int(v.rounded()))
                    editing = nil
                }
            }
            HStack {
                Text(minLabel)
                Spacer()
                Text(maxLabel)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            if let hint {
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(shown.map { "\($0) 分" } ?? "未填写")
        .accessibilityAdjustableAction { direction in
            let current = value ?? 0
            switch direction {
            case .increment: onCommit(min(10, current + 1))
            case .decrement: onCommit(max(0, current - 1))
            @unknown default: break
            }
        }
    }
}
