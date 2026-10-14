# AI Training Planner · iPhone / Apple Watch

原生 SwiftUI 版本（iOS 17 / watchOS 10）。需求、数据格式与测试用例的参考来源是网页原型仓库
[`qqqaaassshu/AI_Training_Planner`](https://github.com/qqqaaassshu/AI_Training_Planner)
（`docs/ios-plan.md`、`docs/data-model.md`、`src/app/utils/__tests__/`）。

## 目录

| 位置 | 内容 |
|---|---|
| `project.yml` | Xcode 工程配置（XcodeGen） |
| `App/iPhone` | iPhone App（SwiftUI + SwiftData） |
| `App/iPhoneTests` | App 测试（SwiftData 读写） |
| `App/Watch` | Watch App（随 iPhone App 一起安装） |
| `App/WatchTests` | 手表 App 测试 |
| `App/WatchWidgets` | 表盘复杂功能（WidgetKit 扩展，随手表 App 安装） |
| `Packages/TrainingCore` | iPhone 与 Watch 共用的核心逻辑（Swift Package，无 UI 依赖，Linux 上可测试） |
| `scripts/install-swift-linux.sh` | 在 Linux 云端会话安装 Swift 工具链 |


## 阶段

| 阶段 | 内容 | 状态 |
|---|---|---|
| 1 | `TrainingCore`：模型、日期、统计、版本对比、自然语言解析、校验、AI 提示词与服务适配、提醒排程逻辑，连同测试 | ✅ |
| 2 | iPhone：导入计划、今日任务、逐个动作打勾、历史；SwiftData | 代码完成，待在 Mac 上试用 |
| 3 | Watch：逐组训练、休息倒计时、表冠、HKWorkoutSession、WatchConnectivity、三层提醒 | 代码完成，待真机验证 |
| 4 | AI 分析、个人档案、通知操作（完成/稍后）、表盘复杂功能 | 代码完成，待真机验证 |

## 在 Mac 上打开 iPhone App

需要 Xcode 16 或更新版本。

```
brew install xcodegen      # 只需安装一次
xcodegen generate          # 每次拉取代码后运行，生成 AITrainingPlanner.xcodeproj
open AITrainingPlanner.xcodeproj
```

- 模拟器：选择任意 iPhone 模拟器，点运行即可。
- 真机：在 iPhone 与 Watch 两个 target 的 Signing & Capabilities 里选择你的开发团队，并把 Bundle Identifier 改成自己的：iPhone 为 `com.你的名字.aitrainingplanner`，Watch 为 `com.你的名字.aitrainingplanner.watchkitapp`，同时把 `project.yml` 里 `WKCompanionAppBundleIdentifier` 改成 iPhone 的标识。
- 手表 App 与表盘复杂功能通过 App Group 共享数据：把 `group.com.example.aitrainingplanner`（`project.yml` 与 `App/Watch/Services/WidgetShared.swift`）改成自己的组，并在两个 target 的 App Groups 能力里勾选；表盘扩展的 Bundle Identifier 为 `<手表 App 的标识>.widgets`。
- 手表 App 用到 HealthKit 与时效性通知（Time Sensitive Notifications）能力；个人免费账号可能无法签名其中某些能力，遇到签名错误时把报错发给我。

Xcode 工程由 `project.yml` 生成，不提交到仓库；增删文件后重新运行 `xcodegen generate`。

### iPhone App（第 2 阶段）

| 页面 | 内容 |
|---|---|
| 今日 | 当天任务与完成进度、今日疲劳；任务详情里逐个动作打勾、调整实际组数/次数/时长/重量、疼痛评分与备注，然后完成（或保存进度）、延后、跳过（选原因）。中途退出会保存草稿 |
| 记录 | 按日期列出执行记录与疲劳，顶部统计；点开可补录动作与备注，左滑删除 |
| 计划 | 当前计划概要与任务；导入（粘贴 JSON 或自然语言、从文件导入、载入示例），导入前预览错误、未识别的行和相对当前版本的变化；版本历史，可查看每版变化并切换当前版本 |

数据存储：SwiftData 里每条数据保存为 TrainingCore 模型的 JSON（与网页原型、AI、手表同步的格式相同），逻辑都在 TrainingCore（`Session/`）。

### Watch App（第 3 阶段）

| 功能 | 内容 |
|---|---|
| 今日 | 当天任务；点训练开始逐组训练，习惯可完成、稍后 10 分钟、跳过（选原因） |
| 逐组训练 | 显示动作与第几组；表冠或 ± 调整次数/时长；完成本组 → 休息倒计时，结束时震动；中途结束时已完成的组保存为部分完成；训练进度在 App 被系统结束后可恢复 |
| HealthKit | 训练中用 `HKWorkoutSession` 保持后台运行，结束后保存一次体能训练到健康 App，记录里带 `health_workout_id` |
| 同步 | iPhone 在计划或记录变化时发送当前计划与最近 7 天记录（`updateApplicationContext`）；手表的记录排队发回（`transferUserInfo`），同一任务同一天以较新的为准 |
| 提醒状态 | 通知与时效性通知是否开启、待发提醒数、下一次强提醒；列出不会震动的情况 |

三层提醒（`docs/ios-plan.md` 的硬性要求）：

1. **本地通知（主力）**：手表按 `ReminderScheduler` 的结果增量更新待发通知（`interruptionLevel = .timeSensitive`），并按 `refreshBy` 安排后台刷新续排；打开 App、收到手机同步、完成任务后也会重排。iPhone 不安排提醒。
2. **强提醒**：下一次训练用智能闹钟会话（`WKExtendedRuntimeSession.start(at:)`），到点反复震动，直到点“开始”或“稍后 10 分钟”。只能在前台安排，所以每次打开 App 时重排；到点时如果任务已完成就不响。
3. **训练中**：组间休息结束时 `WKInterfaceDevice.play` 震动。

需要真机验证的地方：

- 智能闹钟会话在 App 重启后拿不到之前安排的会话引用，新会话可能排不上；旧会话到点时会检查任务是否还需要提醒。
- 后台刷新的时间由系统决定，可能晚于 `refreshBy`；默认每天至少续排一次，窗口为 7 天。

### 第 4 阶段

| 位置 | 内容 |
|---|---|
| iPhone · AI 页 | 本地安全提醒（不依赖 AI）；选分析类型、填补充说明，通过当前服务分析（首次需同意上传数据），或复制提示词给任意 AI 再粘贴回复；分析详情显示总结、发现与建议计划的变化，接受后生成新版本（来源 AI 建议） |
| iPhone · AI 设置 | 多个服务（Anthropic、OpenAI、DeepSeek、通义千问、Kimi、智谱、豆包、Ollama、自定义），API Key 存钥匙串，测试连接；数据上传同意；每周自动复盘（距上次满 7 天时打开 App 自动运行） |
| iPhone · 个人档案 | 写入 AI 系统提示词；每次保存记录变化 |
| Watch · 通知操作 | 训练提醒“开始训练 / 稍后 10 分钟”，习惯提醒“完成 / 稍后 10 分钟”，不用打开 App |
| Watch · 表盘复杂功能 | 圆形、矩形、行内、角落四种样式：今日进度与下一个任务；到点后切换到下一个，午夜换天 |

## TrainingCore

```
cd Packages/TrainingCore
swift test
```

| 文件 | 对应原型 | 内容 |
|---|---|---|
| `Models/*` | `types.ts` | Codable 模型，JSON 字段名与原型一致（snake_case，`schema_version` 2.0） |
| `Support/LocalDate.swift` | `utils/date.ts` | 本地日期 YYYY-MM-DD，纯算术运算；`weekday` 0 = 周日 |
| `Logic/Schedule.swift`、`Statistics.swift`、`Sets.swift`、`Versions.swift` | `utils/plan.ts` | 日程与周数、统计口径、组记录、`reconcileIds`、版本对比 |
| `Logic/Validation.swift` | `utils/validate.ts` | 基于原始 JSON 校验，返回带路径的全部错误；`extractJSON` |
| `Logic/NaturalLanguageImport.swift` | `utils/nlImport.ts` | “深蹲3组10次” → 计划 |
| `Logic/ProfileLogic.swift` | `utils/profile.ts` | 档案对比、提示词格式 |
| `AI/AnalysisInput.swift`、`Prompt.swift` | `utils/analysis.ts` | 本地安全规则、分析输入、提示词（`promptVersion = 2`，文字与原型逐字一致）、回复解析 |
| `AI/Presets.swift`、`Providers.swift`、`RunAnalysis.swift` | `utils/ai/*` | 服务预设；Anthropic Messages API（HTTP，`fallbacks: "default"`）与 OpenAI 兼容接口；超时、重试、错误提示 |
| `Models/PersistedState.swift` | `utils/storage.ts` | 导入网页原型的 localStorage 状态，旧版 AI 设置迁移 |
| `Reminders/ReminderScheduler.swift` | （新增） | 提醒排程，见下 |
| `Resources/*.schema.json` | `schema/*.schema.json` | JSON Schema，写入提示词 |

与原型的差异：

- 时间戳（`*_at`）保持 ISO 8601 字符串，便于与原型和 AI 交换的 JSON 逐字一致；`Timestamp` 负责生成与解析。
- 输出给 AI 的 JSON 键名排序（`sortedKeys`），提示词稳定、便于缓存。
- 网络错误提示去掉了浏览器“跨域”相关说明；Ollama 提示改为填写电脑的局域网地址。
- `AIClient` 的 HTTP 传输层可替换（`HTTPTransport`），测试不访问网络。

### 提醒排程（手表到点必须震动）

`ReminderScheduler.schedule(plan:records:snoozes:now:policy:)` 是纯函数，返回：

- `notifications`：应处于待发状态的本地通知（第 1 层，Watch 用 `UNUserNotificationCenter` 安排，`interruptionLevel = .timeSensitive`）。
  只排未来 `horizonDays`（默认 7）天，按时间排序，截断到 64 − `reservedSlots`（默认 4）条。
  已完成、部分完成、跳过的任务不再提醒；延后（snoozed）的仍提醒；`ReminderSnooze` 覆盖同一任务同一天的提醒时间。
  通知 id 为 `atp.reminder.<taskId>.<YYYY-MM-DD>`，`fingerprint` 存入 userInfo。
- `strongAlarm`：下一次训练（workout），在 36 小时内时给出，用于 `WKExtendedRuntimeSession.start(at:)`（第 2 层，须在前台安排）。
- `refreshBy`：最晚重排时间（后台刷新用）：默认 24 小时；名额被截断时提前到用掉一半名额的时刻。

`ReminderScheduler.diff(desired:pending:)` 对比系统里已有的待发通知，只移除不再需要的、只添加新增或内容变化的，且不碰其他 id 的通知。

## 持续集成

`.github/workflows/ci.yml`：每次推送到 main 或提交 PR 时：Linux 上运行 `swift test`；macOS（Xcode）上运行 TrainingCore 测试并编译 iOS 与 watchOS 模拟器版本；生成 Xcode 工程，在 iOS 模拟器上编译 iPhone App（含手表 App）并运行 App 测试，检查手表 App 已嵌入；在 watchOS 模拟器上运行手表 App 测试。

## 在 Linux 云端会话运行测试

```
sudo ./scripts/install-swift-linux.sh   # 或直接以 root 运行
cd Packages/TrainingCore && swift test
```

脚本优先从 `download.swift.org` 下载工具链；该域名被网络策略拦截时，改从 Docker Hub 拉取官方 `swift` 镜像并复制工具链。
