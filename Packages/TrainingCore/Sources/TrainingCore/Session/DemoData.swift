import Foundation

/// 演示数据：界面截图测试与 SwiftUI 预览用。日期都相对于“今天”，任何一天打开都有内容可看
public enum DemoData {
    /// 启动参数：带上它时 App 使用内存数据库并填入演示数据
    public static let launchArgument = "-ui-testing"

    public static var isActive: Bool { ProcessInfo.processInfo.arguments.contains(launchArgument) }

    /// 每天的训练 + 两个习惯
    public static func planInput(start: LocalDate) -> PlanInput {
        PlanInput(
            planName: "12周体能恢复计划",
            startDate: start,
            endDate: start.adding(days: 83),
            timezone: TimeZone.current.identifier,
            aiSummary: "改善睡眠，恢复手腕，提升体能",
            tasks: [
                PlanTask(id: "t1", title: "身体维护训练", type: .workout, schedule: .everyDay(at: "07:30"), exercises: [
                    Exercise(id: "e1", name: "深蹲", sets: 3, reps: 10, restSec: 60, cue: "膝盖对准脚尖"),
                    Exercise(id: "e2", name: "臀桥", sets: 3, reps: 12, restSec: 45),
                    Exercise(id: "e3", name: "平板支撑", sets: 3, durationSec: 30, restSec: 30),
                ]),
                PlanTask(id: "t2", title: "散步20分钟", type: .habit, schedule: .everyDay(at: "18:00")),
                PlanTask(id: "t3", title: "22:30准备睡觉", type: .habit, schedule: .everyDay(at: "22:30")),
            ]
        )
    }

    public static func state(today: LocalDate = .today(), now: Date = Date()) -> PersistedState {
        var s = PersistedState()
        let start = today.adding(days: -13)
        // V1：两周前导入
        s.addPlanVersion(createPlanVersion(planInput(start: start), existing: [], source: .jsonImport,
                                           now: now.addingTimeInterval(-13 * 86400)))
        // V2：一周前接受 AI 建议，臀桥加到 4 组
        var v2Input = planInput(start: start)
        v2Input.tasks[0].exercises![1].sets = 4
        v2Input.changeNote = "臀桥 3 组 → 4 组：上周完成率 100%，疼痛 ≤ 2"
        s.addPlanVersion(createPlanVersion(v2Input, existing: s.planVersions, source: .aiAnalysis,
                                           now: now.addingTimeInterval(-6 * 86400)))

        // 过去 6 天的记录
        let plan = s.currentPlan!
        for back in 1...6 {
            let day = today.adding(days: -back)
            let at = now.addingTimeInterval(-Double(back) * 86400)
            let workout = plan.tasks[0]
            switch back {
            case 2:
                s.record(RecordDraft(taskId: "t1", status: .skipped, skipReason: .noTime), date: day, now: at)
            case 4:
                let sets = expandSets(summaries(fromPlan: Array(workout.exercises!.prefix(2))), completedAt: Timestamp.string(from: at))
                s.record(RecordDraft(taskId: "t1", status: .partial, sets: sets, notes: "膝盖有点酸", painScore: 4), date: day, now: at)
            default:
                let sets = expandSets(summaries(fromPlan: workout.exercises!), completedAt: Timestamp.string(from: at))
                s.record(RecordDraft(taskId: "t1", status: .completed, sets: sets, painScore: back == 1 ? 2 : 1), date: day,
                         source: back.isMultiple(of: 3) ? .watch : .phone, now: at)
            }
            s.record(RecordDraft(taskId: "t2", status: back == 3 ? .skipped : .completed, skipReason: back == 3 ? .other : nil), date: day, now: at)
            s.record(RecordDraft(taskId: "t3", status: .completed), date: day, now: at)
            s.setDailyFatigue([3, 5, 4, 6, 3, 2][back - 1], date: day, now: at)
        }
        // 今天：散步已完成，疲劳 4
        s.record(RecordDraft(taskId: "t2", status: .completed, notes: "和家人一起"), date: today, now: now)
        s.setDailyFatigue(4, date: today, now: now)

        // 一条待处理的每周复盘，建议深蹲加到 4 组
        var suggested = v2Input
        suggested.tasks[0].exercises![0].sets = 4
        suggested.changeNote = "深蹲 3 组 → 4 组：近 7 天完成率 86%，疼痛平均 1.8，可以小步加量"
        s.addAnalysis(createAnalysis(
            AIAnalysisOutput(
                summary: "近 7 天完成 5 次训练，1 次因没时间跳过，完成率 86%。疼痛整体很低，第 4 天深蹲后膝盖有点酸（4 分），之后已恢复。",
                findings: [
                    Finding(level: .info, text: "坚持得很好，可以小步加量"),
                    Finding(level: .warn, text: "周中一次膝盖酸痛 4 分，深蹲时注意膝盖对准脚尖"),
                ],
                suggestedPlan: suggested
            ),
            kind: .weeklyReview, channel: .api, planVersionId: plan.id,
            range: DateRange(from: today.adding(days: -6), to: today), provider: "Anthropic Claude", model: "claude-opus-5-5",
            now: now.addingTimeInterval(-3600)
        ))

        s.saveProfile(UserProfile(ageRange: "30-39", weightKg: 72, experience: .beginner, injuries: "右手腕恢复中，避免支撑类动作",
                                  availableTime: "工作日早上 20 分钟", equipment: "弹力带、瑜伽垫", goals: "睡好，恢复体能"),
                      now: now.addingTimeInterval(-10 * 86400))
        var p = s.profile
        p.weightKg = 71
        s.saveProfile(p, now: now.addingTimeInterval(-2 * 86400))

        var service = createService(fromPreset: "anthropic")
        service.id = "demo-anthropic"
        s.upsertService(service)
        return s
    }

    /// 今天的训练草稿：第一个动作已打勾
    public static let draft = TaskDraft(doneIds: ["e1"], items: [])
}
