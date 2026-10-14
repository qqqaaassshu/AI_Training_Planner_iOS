import Foundation
import Testing
@testable import TrainingCore

@Suite("profile") struct ProfileTests {
    @Test("diffProfile 只记录真正变化的字段，空白视为未填写") func diff() {
        let changes = diffProfile(
            before: UserProfile(weightKg: 72, injuries: "手腕恢复中", goals: "  "),
            after: UserProfile(weightKg: 70.5, injuries: "手腕恢复中", equipment: "弹力带", goals: ""),
            at: "2026-10-14T00:00:00Z"
        )
        #expect(changes == [
            ProfileChange(at: "2026-10-14T00:00:00Z", field: .weightKg, from: .number(72), to: .number(70.5)),
            ProfileChange(at: "2026-10-14T00:00:00Z", field: .equipment, to: .string("弹力带")),
        ])
    }

    @Test("清空字段也记录") func cleared() {
        #expect(diffProfile(before: UserProfile(injuries: "膝盖不适"), after: UserProfile(), at: "t")
            == [ProfileChange(at: "t", field: .injuries, from: .string("膝盖不适"))])
    }

    @Test("提示词格式：省略未填项，枚举转中文") func promptFormat() {
        let text = formatProfileForPrompt(UserProfile(weightKg: 70, experience: .beginner, injuries: "手腕恢复中"))
        #expect(text == "- 体重：70kg\n- 训练经验：入门（偶尔训练）\n- 伤病与身体限制：手腕恢复中")
        #expect(formatProfileForPrompt(UserProfile()).contains("未填写档案"))
        #expect(UserProfile(goals: " ").isEmpty)
    }

    @Test("ProfileChange 的数值编码为数字") func encoding() throws {
        let json = try JSONValue(encoding: ProfileChange(at: "t", field: .weightKg, from: .number(72), to: .number(70.5)))
        #expect(json == ["at": "t", "field": "weight_kg", "from": 72, "to": 70.5])
    }
}
