import SwiftUI
import TrainingCore

/// 个人档案：写入 AI 系统提示词；每次保存记录变化，AI 能看到状态趋势
struct ProfileView: View {
    @Environment(TrainingStore.self) private var store
    @State private var profile = UserProfile()
    @State private var loaded = false

    var body: some View {
        Form {
            Section("基本信息") {
                LabeledContent("年龄段") {
                    TextField("例如 30-39", text: text(\.ageRange)).multilineTextAlignment(.trailing)
                }
                Picker("性别", selection: $profile.sex) {
                    Text("未填写").tag(Sex?.none)
                    ForEach(Sex.allCases, id: \.self) { Text($0.label).tag(Sex?.some($0)) }
                }
                number("身高", unit: "cm", \.heightCm)
                number("体重", unit: "kg", \.weightKg)
                Picker("训练经验", selection: $profile.experience) {
                    Text("未填写").tag(Experience?.none)
                    ForEach(Experience.allCases, id: \.self) { Text($0.label).tag(Experience?.some($0)) }
                }
            }
            Section("训练条件") {
                field("伤病与身体限制", "例如“右手腕恢复中，避免支撑”", \.injuries)
                field("可训练时间", "例如“工作日晚上 20 分钟”", \.availableTime)
                field("可用器械", "例如“弹力带、10kg 哑铃”", \.equipment)
            }
            Section("目标与偏好") {
                field("目标", "例如“睡好，恢复体能”", \.goals)
                field("偏好与其他", "喜欢或不喜欢的动作等", \.preferences)
            }
            Section {
                Button("保存") { store.saveProfile(profile) }
                    .disabled(diffProfile(before: store.state.profile, after: profile, at: "").isEmpty)
            } footer: {
                Text("档案会写进 AI 的系统提示词。未填写时，AI 会按保守的入门水平安排。")
            }
            if !store.state.profileHistory.isEmpty {
                Section("变更记录") {
                    ForEach(Array(store.state.profileHistory.suffix(20).reversed().enumerated()), id: \.offset) { _, c in
                        VStack(alignment: .leading) {
                            Text("\(c.field.label)：\(displayValue(c.field, c.from)) → \(displayValue(c.field, c.to))")
                            Text(Timestamp.localDate(of: c.at)?.description ?? c.at).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("个人档案")
        .onAppear {
            guard !loaded else { return }
            loaded = true
            profile = store.state.profile
        }
    }

    /// 多行文字字段：上方小标题，下方输入
    private func field(_ title: String, _ prompt: String, _ key: WritableKeyPath<UserProfile, String?>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(prompt, text: text(key), axis: .vertical)
        }
    }

    private func text(_ key: WritableKeyPath<UserProfile, String?>) -> Binding<String> {
        Binding(get: { profile[keyPath: key] ?? "" }, set: { profile[keyPath: key] = $0.isEmpty ? nil : $0 })
    }

    private func number(_ title: String, unit: String, _ key: WritableKeyPath<UserProfile, Double?>) -> some View {
        LabeledContent(title) {
            HStack {
                TextField("未填写", value: Binding(get: { profile[keyPath: key] }, set: { profile[keyPath: key] = $0 }), format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                Text(unit).foregroundStyle(.secondary)
            }
        }
    }
}
