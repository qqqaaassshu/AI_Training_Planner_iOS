# AI Training Planner · iPhone / Apple Watch

原生 SwiftUI 版本（iOS 17 / watchOS 10）。需求、数据格式与测试用例的参考来源是网页原型仓库
[`qqqaaassshu/AI_Training_Planner`](https://github.com/qqqaaassshu/AI_Training_Planner)
（`docs/ios-plan.md`、`docs/data-model.md`、`src/app/utils/__tests__/`）。

## 目录

| 位置 | 内容 |
|---|---|
| `Packages/TrainingCore` | iPhone 与 Watch 共用的核心逻辑（Swift Package，无 UI 依赖，Linux 上可测试） |
| `scripts/install-swift-linux.sh` | 在 Linux 云端会话安装 Swift 工具链 |

App 工程（iPhone、Watch）在第 2、3 阶段加入，通过本地包依赖引用 `TrainingCore`。

## 阶段

| 阶段 | 内容 | 状态 |
|---|---|---|
| 1 | `TrainingCore`：模型、日期、统计、版本对比、自然语言解析、校验、AI 提示词与服务适配、提醒排程逻辑，连同测试 | ✅ |
| 2 | iPhone：导入计划、今日任务、逐个动作打勾、历史；SwiftData | |
| 3 | Watch：逐组训练、休息倒计时、表冠、HKWorkoutSession、WatchConnectivity、三层提醒 | |
| 4 | AI 分析、个人档案、通知操作（完成/稍后）、表盘复杂功能 | |

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

## 在 Linux 云端会话运行测试

```
sudo ./scripts/install-swift-linux.sh   # 或直接以 root 运行
cd Packages/TrainingCore && swift test
```

脚本优先从 `download.swift.org` 下载工具链；该域名被网络策略拦截时，改从 Docker Hub 拉取官方 `swift` 镜像并复制工具链。
