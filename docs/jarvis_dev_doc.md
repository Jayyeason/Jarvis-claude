# Jarvis — macOS AI 效率助理开发文档

> **版本**：v1.6  
> **目标读者**：AI 编码模型（Claude Code / Cursor / Copilot）  
> **开发范式**：Vibe Coding，由 AI 模型根据本文档生成代码  
> **v1.1**：F1 字段规格、时长选择面板、F7 主子任务规则、Tool Schema 更新  
> **v1.2**：模型存储路径改为 App Bundle、UI 动效改为 macOS 原生风格、SettingsView 表单化  
> **v1.3**：API Provider 扩展、验证后动态展示模型、明确区分顶部菜单栏与灵动岛  
> **v1.4**：API Provider 扩展至 14 个（OpenClaw 12 + Google + DeepSeek）  
> **v1.5**：灵动岛交互重设计、Memory 文件写入时机、训练路线附录 A  
> **v1.6**：新增备忘录 Tool（create_note / append_to_note，AppleScript 实现）、Memory 文件体系完整重构（soul/user/tools/heartbeat/learnings/errors/bootstrap 七文件单一职责）、分级注入策略（固定注入 + Tool 检索 + 系统内部读取）、soul.md 语气风格支持对话中修改  

---

## 目录

1. [产品概述](#1-产品概述)
2. [技术栈与平台](#2-技术栈与平台)
3. [整体架构](#3-整体架构)
4. [功能规格](#4-功能规格)
5. [Swift 层开发规格](#5-swift-层开发规格)
6. [Python 层开发规格](#6-python-层开发规格)
7. [模型管理规格](#7-模型管理规格)
8. [智能路由规格](#8-智能路由规格)
9. [Agent 框架规格](#9-agent-框架规格)
10. [Tool 规格](#10-tool-规格)
11. [Memory 与 Self-Improving 规格](#11-memory-与-self-improving-规格)
12. [通信协议规格](#12-通信协议规格)
13. [数据模型](#13-数据模型)
14. [文件结构](#14-文件结构)
15. [依赖清单](#15-依赖清单)
16. [权限声明](#16-权限声明)
17. [开发顺序建议](#17-开发顺序建议)

---

## 1. 产品概述

### 1.1 定位

Jarvis 是一个常驻 macOS 顶栏的 AI 效率助理，以灵动岛形式呈现。用户通过截图、快捷键或自然语言对话，让 Jarvis 理解意图并自动写入 macOS Calendar、Reminder 等系统。支持完全端侧运行（数据不出本机），同时允许用户配置云端 API 作为备用或主要推理引擎。

### 1.2 核心原则

- **隐私优先**：默认端侧推理，数据不上传
- **用户确认**：所有写入操作在用户确认后执行，主动触发行为只推通知
- **渐进增强**：无模型时提示下载，无云端 API 时提示配置，核心功能优雅降级
- **训练友好**：System Prompt 格式、Tool Call 格式从第一天固定，与未来训练数据格式完全一致

---

## 2. 技术栈与平台

### 2.1 语言与平台

| 层级 | 语言 | 框架/工具 |
|------|------|-----------|
| UI 层（Channel） | Swift 5.9+ | AppKit、SwiftUI、ScreenCaptureKit |
| Agent 层（Gateway） | Python 3.11+ | FastAPI、uvicorn、asyncio |
| 推理层（端侧） | Python | mlx-lm |
| 推理层（云端） | Python | httpx、anthropic SDK、openai SDK |
| 进程通信 | HTTP | localhost:8765 |

### 2.2 系统要求

- macOS 14.0+（Sonoma）
- Apple Silicon（M 系列芯片）
- 最低 8GB 统一内存（推荐 16GB）
- 分发方式：Homebrew（`brew install jarvis`）

### 2.3 不使用 App Store

无沙盒限制，可内嵌 Python 运行时，允许进程间通信。

---

## 3. 整体架构

### 3.1 双进程架构

```
┌─────────────────────────────────────────────────────┐
│                 Swift 进程（Channel 层）              │
│                                                     │
│  NSStatusItem 灵动岛  ←→  SwiftUI 面板              │
│  ScreenCaptureKit         ConfirmationCard          │
│  FormView（信息补充）      LocationPicker           │
│  IslandExpandView（主动）  SettingsView             │
│                                                     │
│  NativeActionExecutor：                             │
│    EventKit · MapKit · CoreData · Notifications    │
│                                                     │
│  GatewayManager：启动/监控 Python 进程              │
│  GatewayClient：HTTP 通信                           │
└─────────────────────┬───────────────────────────────┘
                      │
              HTTP localhost:8765
              延迟 < 50ms，占总时延 < 3%
                      │
┌─────────────────────▼───────────────────────────────┐
│                Python 进程（Gateway + Agent 层）      │
│                                                     │
│  FastAPI Gateway（入口）                             │
│  ├── JarvisAgent（ReAct Core）                      │
│  ├── Heartbeat Loop（主动触发，60s 间隔）            │
│  ├── MemoryManager（短期+长期记忆）                  │
│  ├── ModelRouter（智能路由决策）                     │
│  ├── ToolRouter（Tool 调度）                        │
│  ├── OutputValidator（格式验证+重试）                │
│  ├── WAL（写前日志）                                 │
│  ├── SelfImproving（学习模块）                       │
│  └── TrainingDataCollector（训练数据收集）           │
│                                                     │
│  LLMProvider（统一推理接口）：                       │
│    GemmaMLXProvider / Qwen3MLXProvider              │
│    ClaudeProvider / OpenAIProvider                  │
└─────────────────────────────────────────────────────┘
```

### 3.2 两条执行路径

**路径 A（用户主动触发）**
```
用户截图/文字 → GatewayClient → POST /chat
→ ModelRouter → LLMProvider → ReAct Core
→ ToolRouter → Swift NativeActionExecutor
→ 返回结果 → Swift UI 展示
```

**路径 B（系统定时触发）**
```
Heartbeat Loop（60s）→ 检查触发条件
→ ReAct Core（只读模式）
→ POST /expand_island → Swift IslandExpandView
→ 用户确认 → POST /confirm → 路径 A 执行
```

---

## 4. 功能规格

### 4.1 F1 截图日程识别与写入

**触发方式**：全局快捷键 `⌘+Shift+J`，或拖拽图片到灵动岛

**执行流程**：
1. CaptureManager 捕获截图，压缩为 JPEG（最大边 1024px，quality 0.85）
2. 图片 Base64 编码后通过 `POST /chat` 发给 Python
3. ModelRouter 判断路由（见第 8 节）
4. LLM 判断类型（日程 or 提醒事项）并识别所有字段
5. 如结束时间缺失（日程类型），返回 `needs_duration: true`，Swift 展示时长选择面板
6. 如地点识别到，调用 `search_location`，Swift 展示 LocationPicker
7. 返回 ConfirmationCard（含识别结果预览）
8. 用户确认后 Swift 调用 EventKit 写入

---

#### 4.1.1 日程 vs 提醒事项判断规则

LLM 根据以下规则判断写入 Calendar（日程）还是 Reminder（提醒事项）：

**判断为日程（Calendar）的信号**：
- 事件有持续时长或占用时间段
- 关键词：开会、面试、见面、吃饭、培训、上课、活动、出发、参加、约好

**判断为提醒事项（Reminder）的信号**：
- 事件只有截止时间，无持续时长
- 关键词：交、还、缴、提交、记得、别忘了、截止、ddl、deadline、发送、完成

**模糊情况**：默认判断为日程，LLM 可在 notes 字段补充说明

---

#### 4.1.2 日程字段规格（写入 Calendar）

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `event_type` | String | ✅ | — | 固定为 `"calendar"` |
| `title` | String | ✅ | — | 事件标题 |
| `start_time` | ISO8601 | ✅ | — | 开始时间，无法识别则触发 F2 追问 |
| `end_time` | ISO8601 | ⚠️ | 需追问 | 结束时间，**无法推断时不默认填写，触发时长选择面板** |
| `is_all_day` | Bool | — | `false` | 是否全天事件 |
| `location_keyword` | String | — | `null` | 识别到则触发 F3 地点搜索 |
| `latitude` | Double | — | `null` | F3 用户选择后填入 |
| `longitude` | Double | — | `null` | F3 用户选择后填入 |
| `recurrence` | String | — | `null` | 重复规则，见下方说明 |
| `alert_minutes` | Int | — | `30` | **默认提前 30 分钟提醒** |
| `travel_time_minutes` | Int | — | `null` | 行程时间（分钟），识别到则填入 |
| `attendees` | [String] | — | `[]` | 识别到则写入，识别不到不写 |
| `notes` | String | — | `null` | 见备注生成规则 |
| `needs_duration` | Bool | — | `false` | 为 true 时触发时长选择面板（不进入通用 F2 表单） |

**recurrence 取值**（遵循 EKRecurrenceRule 规范）：
```
null          → 不重复（默认）
"DAILY"       → 每天
"WEEKLY"      → 每周（同一天）
"WEEKLY:MO"   → 每周一（指定星期）
"WEEKLY:WE"   → 每周三
"MONTHLY"     → 每月（同一日）
"YEARLY"      → 每年
```

识别信号：用户说"以后每周三下午开会"→ `recurrence: "WEEKLY:WE"`

**时长选择面板规格**（`needs_duration: true` 时触发，替代 F2 通用表单）：
```
┌─────────────────────────────────┐
│ 📅 明天下午5点开会               │
│                                 │
│ 大概持续多久？                   │
│                                 │
│  [30分钟]  [1小时]  [1.5小时]   │
│  [2小时]   [自定义...]           │
│                                 │
│  ○ 不确定，先用1小时             │
└─────────────────────────────────┘
```
用户点选后，`end_time = start_time + 选择时长`，进入正常确认流程。

**alert_minutes 反馈机制**：
- 默认 30 分钟提醒
- 提醒触发时，灵动岛展示"提醒早了还是晚了？"按钮
- 用户点击反馈后，Self-Improving 模块记录偏好，逐步调整该用户的默认提醒时间
- 反馈数据格式：`{field: "alert_minutes", original: 30, feedback: "too_early" | "too_late" | "just_right"}`

**notes 生成规则**：
- 识别出截图中的额外信息（会议链接、议题、文件名等）→ 写入 notes
- 地点为户外场所（公园、球场、户外餐厅等）且当日/次日降雨概率 > 50% → 在 notes 追加"☂️ 注意：当天可能有雨，建议带伞"，并在早上 8 点触发一个提醒事项"带伞！{事件标题}"
- 无额外信息且无天气风险 → `notes: null`，不写入

---

#### 4.1.3 提醒事项字段规格（写入 Reminder）

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `event_type` | String | ✅ | — | 固定为 `"reminder"` |
| `title` | String | ✅ | — | 提醒标题 |
| `due_date` | ISO8601 date | — | `null` | 到期日期，识别到则填入 |
| `due_time` | ISO8601 time | — | `null` | 到期时间，识别到则填入（同时勾选"指定时间"） |
| `priority` | String | — | `"none"` | 见优先级规则 |
| `recurrence` | String | — | `null` | 重复规则，同日程字段取值 |
| `notes` | String | — | `null` | 见备注生成规则 |
| `flag` | Bool | — | `false` | 默认不标记旗帜 |
| `list` | String | — | `"提醒事项"` | 所属列表，默认系统默认列表 |
| `parent_task_title` | String | — | `null` | 若为拆分子任务，填写主任务标题（见 F7） |

**priority 规则**：
```
默认值：none（无优先级）

动态调整来源（任一触发）：
1. 语气信号：包含"紧急"、"重要"、"必须"、"ASAP" → high
2. 截止信号：包含"ddl"、"截止"、"deadline"、"今天必须" → medium
3. 用户反馈：用户在 ConfirmationCard 手动修改优先级 → Self-Improving 记录，下次类似任务自动提升
4. 每周整理：AI 分析历史任务，识别出某类任务用户总是手动调优先级 → 固化为规则
```

**recurrence 识别信号**：
- "以后每周三下班之前给我发工作文档" → `recurrence: "WEEKLY:WE"`，`due_time` 推断为下班时间（若用户设定了下班时间则使用，否则默认 18:00）

**notes 生成规则**：
- 识别出截图中的额外上下文信息 → 写入 notes
- 若为拆分任务的子任务 → notes 中写明主任务：`"主任务：{parent_task_title}"`
- 无额外信息 → `notes: null`，不写入

**flag 规则**：
- 默认 `false`
- 用户在 ConfirmationCard 中可手动勾选
- Self-Improving 记录用户打旗习惯，未来可主动建议

---

#### 4.1.4 识别结果 JSON 格式示例

```python
# 日程示例
{
    "event_type": "calendar",
    "title": "与王总开会",
    "start_time": "2026-04-15T17:00:00",
    "end_time": null,
    "needs_duration": True,
    "is_all_day": False,
    "location_keyword": "国贸三期",
    "recurrence": null,
    "alert_minutes": 30,
    "travel_time_minutes": null,
    "attendees": ["王总"],
    "notes": null
}

# 重复日程示例
{
    "event_type": "calendar",
    "title": "周三例会",
    "start_time": "2026-04-15T14:00:00",
    "end_time": "2026-04-15T15:00:00",
    "needs_duration": False,
    "recurrence": "WEEKLY:WE",
    "alert_minutes": 30,
    "attendees": [],
    "notes": null
}

# 提醒事项示例
{
    "event_type": "reminder",
    "title": "交期末PPT",
    "due_date": "2026-04-15",
    "due_time": "22:00:00",
    "priority": "medium",
    "recurrence": null,
    "notes": null,
    "flag": False,
    "list": "提醒事项",
    "parent_task_title": null
}
```

**错误处理**：识别失败时显示错误提示，提供手动输入入口

---

### 4.2 信息不完整时弹出表单 / 时长选择面板

**触发条件**：LLM 调用 `ask_clarification` Tool，或识别结果包含 `needs_duration: true`

#### 4.2.1 通用表单（FormView）

触发条件：`ask_clarification` Tool 被调用

**FormView 规格**：
- 已识别字段预填（灰色背景表示已填）
- 缺失字段高亮显示（黄色边框）
- 支持字段类型：文字输入、日期时间选择器、开关
- 用户填完点击「写入」后，数据通过 `POST /chat` 附带 `form_data` 字段返回

**缺失字段枚举**：
```
"time"      → 展示日期时间选择器
"title"     → 展示文本输入框
"location"  → 展示文本输入框（触发 F3）
```

#### 4.2.2 时长选择面板（DurationPickerView）

触发条件：识别结果 `needs_duration: true`（日程有开始时间但无法推断结束时间）

**不走通用 F2 表单，使用专属快捷按钮面板**：
```
┌─────────────────────────────────┐
│ 📅 [事件标题]                    │
│    [开始时间]                    │
│                                 │
│ 大概持续多久？                   │
│                                 │
│  [30分钟]  [1小时]  [1.5小时]   │
│  [2小时]   [自定义...]           │
│                                 │
│  ○ 不确定，先用1小时             │
└─────────────────────────────────┘
```
- 用户点选后：`end_time = start_time + duration`，进入正常确认流程
- 「自定义」点击后展示时间选择器
- 「不确定，先用1小时」：`end_time = start_time + 60min`，在 notes 中加注"时长待确认"

---

### 4.3 F3 地点识别与用户选择

**触发条件**：LLM 调用 `search_location` Tool，Python 返回 `needs_location_pick: true`

**Swift 侧执行**：
```swift
// 使用 MapKit MKLocalSearch 搜索
let request = MKLocalSearch.Request()
request.naturalLanguageQuery = keyword
request.region = MKCoordinateRegion(...)  // 以用户当前位置为中心

// 返回最多 5 个候选结果
```

**LocationPicker 规格**：
- 展示候选地点列表（名称、地址、距离）
- 用户点选后，坐标通过 `location_selected` 字段发回 Python
- 底部提供「手动输入地址」兜底
- Python 收到坐标后继续调用 `create_calendar_event`，将坐标写入 location 字段

---

### 4.4 F4 多日程识别与批量写入

**触发条件**：LLM 识别出多个日程，返回 `multiple_events: true`

**UI 规格**：
- 灵动岛展开列表，每行一个日程（标题+时间）
- 每行独立复选框，默认全选
- 底部「全部写入」和「取消」按钮
- 逐一写入，显示进度（如「3/5 已写入」）

---

### 4.5 F5 灵动岛自由对话

**触发方式**：点击灵动岛胶囊打开对话界面

**ConversationView 规格**：
- 输入框在底部，支持多行
- 消息气泡展示（用户右侧，Jarvis 左侧）
- 支持流式输出（逐 token 更新）
- 历史记录在会话期间保留，关闭后清空
- 支持功能：查询今日日程、修改事件、追问上下文

**会话管理**：
- `session_id` 由 Swift 生成（UUID），每次打开对话生成新 session
- Python 侧维护 session → messages 映射（内存，进程重启后清空）

---

### 4.6 F6 主动出击（Proactive）

**触发机制**：Python Heartbeat Loop 每 60 秒检查一次触发条件

**触发场景与时间**：

| 场景 | 触发时间 | 检查逻辑 |
|------|---------|---------|
| DDL 前提醒 | 每次 tick | 检查未来 30min 内是否有事件 |
| 天气感知 | 每天 07:30 | 检查天气 + 当日是否有外出事件 |
| 待办跟进 | 每天 18:00 | 检查今日到期未完成 Reminder |
| 日程前置准备 | 每天 21:00 | 检查明日是否有重要事件 |
| 周期性习惯 | 按用户 Cron | 用 croniter 匹配用户规则 |
| 习惯追踪 | 按用户 Cron | 询问习惯目标进度 |
| 每周整理 | 每周日 22:00 | AI 整理 learnings，更新 soul.md |

**所有主动触发的约束**：
- ReAct Core 运行在 `is_autonomous=True` 模式
- 只允许调用只读 Tool：`get_today_events`、`read_memory`、`get_weather`、`get_overdue_reminders`
- 可以调用 `send_notification`（发系统通知）
- **禁止**调用任何写入 Tool
- 用户必须确认后才能执行写入操作

**IslandExpandView 规格**：
```
┌─────────────────────────────┐
│  [图标] 标题                 │
│  正文内容（1-2行）           │
│                             │
│  [主操作按钮]  [稍后提醒]   │
└─────────────────────────────┘
```
- 稍后提醒：支持 15min / 30min / 1h
- 点击主操作：发送 `POST /confirm` 触发实际执行
- 自动收起：10 秒无操作后收起

**WAL 保护**：每次主动触发前写入 WAL，执行后更新状态，防止状态丢失

---

### 4.7 F7 复杂任务自动拆分

**触发条件**：LLM 识别到复杂任务，调用 `split_task` Tool

**核心规则**：
- 主任务本身写入 Reminder
- 每个子任务也独立写入 Reminder
- 子任务的 `due_date` 必须早于主任务的 `due_date`
- 子任务的 `notes` 字段写明主任务标题：`"主任务：{主任务标题}"`
- 子任务之间的 `due_date` 按执行顺序递增排列（最早完成的子任务 DDL 最靠前）

**写入顺序**：
1. 先写入所有子任务（Swift EventKit）
2. 再写入主任务，主任务 notes 中列出所有子任务标题

**示例**：
```
用户说："帮我准备下周五的产品发布会演讲"

主任务（Reminder）：
  title: "产品发布会演讲"
  due_date: 2026-04-24（下周五）
  due_time: null
  priority: "high"
  notes: "子任务：整理演讲提纲、制作PPT、彩排演练"

子任务1（Reminder）：
  title: "整理演讲提纲"
  due_date: 2026-04-21（周二）
  priority: "medium"
  notes: "主任务：产品发布会演讲"
  parent_task_title: "产品发布会演讲"

子任务2（Reminder）：
  title: "制作PPT"
  due_date: 2026-04-23（周四）
  priority: "medium"
  notes: "主任务：产品发布会演讲"
  parent_task_title: "产品发布会演讲"

子任务3（Reminder）：
  title: "彩排演练"
  due_date: 2026-04-24（周五上午）
  priority: "high"
  notes: "主任务：产品发布会演讲"
  parent_task_title: "产品发布会演讲"
```

**Python 侧执行**（`split_task` Tool）：
- LLM 在 Tool Call 的 `params` 中直接输出主任务和子任务完整字段
- ToolRouter 按顺序批量调用 `create_reminder` Tool（Swift 侧）
- 先写子任务，再写主任务

**展示**：ConfirmationCard 展示主任务 + 子任务列表，用户可删减任意子任务后确认

---

### 4.8 F8 用户习惯记忆

**触发条件**：用户输入包含以下信号时，LLM 调用 `save_memory` Tool：

意图预过滤（Python 规则匹配，辅助 LLM 判断）：
```python
MEMORY_TRIGGER_PATTERNS = [
    r"每(天|周|月|小时|隔\d+)",
    r"我(一般|习惯|喜欢|通常|偏好)",
    r"(以后|下次|总是|永远|默认|记住|记一下)",
    r"每.{0,10}(点|时)提醒",
    r"(帮我|提醒我).{0,5}(每|定期|定时)",
]
```

**存储结构**（CoreData，Swift 侧）：
```
Memory {
    id: UUID
    natural_language: String    // 用户原话
    type: Enum                  // recurring_reminder / preference / behavior_rule
    cron_expression: String?    // 周期性规则的 cron 表达式
    instruction: String         // 触发时给 AI 的指令
    active: Bool
    created_at: Date
    updated_at: Date
}
```

**模糊情况处理**：LLM 调用 `ask_clarification`，询问是一次性还是周期性

---

### 4.9 F9 Self-Improving（自我改进）

**学习来源**：

1. **用户修改识别结果**：Swift 在用户修改 ConfirmationCard 字段时，将 `user_action: "modified"` 和 `corrections: {...}` 附带在下一次请求中
2. **用户拒绝操作**：`user_action: "rejected"`
3. **每周 AI 整理**：Heartbeat Loop 每周日 22:00 触发

**本地文件**：
```
~/.jarvis/
├── memory.md       # 用户主动规则 + 固化偏好
├── learnings.md    # 近期纠正和拒绝（滚动窗口）
├── errors.md       # 识别错误记录
├── soul.md         # 每周整理的用户画像
└── wal.jsonl       # 写前日志
```

**固化规则**：同一字段被纠正 ≥ 3 次时，自动提升为 `memory.md` 中的永久规则

---

## 5. Swift 层开发规格

### 5.1 模块结构

```
Swift/
├── App/
│   ├── JarvisApp.swift          # App 入口，@main
│   └── GatewayManager.swift     # Python 进程管理
├── UI/
│   ├── StatusBarController.swift  # 灵动岛胶囊 + 右键菜单
│   ├── ConversationView.swift     # 对话界面（含底部工具栏）
│   ├── ConfirmationCard.swift     # 写入确认卡片
│   ├── FormView.swift             # 信息补充表单（F2）
│   ├── DurationPickerView.swift   # 时长选择面板（F1 结束时间）
│   ├── LocationPicker.swift       # 地点候选列表（F3）
│   ├── IslandExpandView.swift     # 主动提醒展开面板（F6）
│   ├── SettingsView.swift         # 设置页（含 API 配置表单）
│   ├── OnboardingView.swift       # 首次启动引导（模型选择下载）
│   └── Animations/
│       ├── JarvisAnimation.swift  # 全局动效参数
│       └── PressableStyle.swift   # 按压反馈样式
├── Gateway/
│   └── GatewayClient.swift
├── NativeActions/
│   ├── NativeActionExecutor.swift
│   ├── EventKitTool.swift
│   ├── MapKitTool.swift
│   ├── CoreDataTool.swift
│   └── NotificationTool.swift
├── Models/
│   ├── ModelManager.swift       # 模型下载/切换/卸载
│   └── ModelRegistry.swift      # 模型元数据（镜像 Python 侧）
│   └── Jarvis.xcdatamodeld     # CoreData 模型
└── Resources/
    └── Info.plist
```

### 5.2 GatewayManager

```swift
class GatewayManager: ObservableObject {
    @Published var isReady: Bool = false
    private var process: Process?
    private let port = 8765
    private let healthCheckInterval: TimeInterval = 1.0
    private let maxWaitSeconds: Int = 30

    func start() {
        // 1. 找到 bundle 内的 Python 可执行文件和 gateway.py
        // 2. 启动 Process，设置 executableURL 和 arguments
        // 3. 设置 terminationHandler（崩溃时自动重启）
        // 4. 轮询 GET /health 直到返回 200 或超时
        // 5. 设置 isReady = true
    }

    func stop() {
        process?.terminate()
        isReady = false
    }

    private func waitForGateway() async {
        for _ in 0..<maxWaitSeconds {
            if await checkHealth() {
                DispatchQueue.main.async { self.isReady = true }
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        // 超时处理：显示错误提示
    }
}
```

### 5.3 GatewayClient

```swift
class GatewayClient {
    private let baseURL = "http://localhost:8765"
    private let session = URLSession.shared

    // 主要接口
    func chat(request: ChatRequest) async throws -> ChatResponse
    func confirm(actionId: String) async throws -> ChatResponse
    func expandIsland(content: IslandContent) async throws
    func saveSettings(settings: JarvisSettings) async throws
    func switchModel(variant: ModelVariant) async throws
    func getHealth() async throws -> Bool

    // 错误处理
    // 超时：30 秒
    // 网络错误：显示错误提示，不崩溃
    // 5xx：重试 1 次，失败后提示用户
}
```

### 5.4 StatusBarController

```swift
class StatusBarController {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private var eventMonitor: EventMonitor?

    // 灵动岛状态
    enum IslandState {
        case idle           // 默认小胶囊
        case loading        // 推理中（动画）
        case conversation   // 对话展开
        case confirmation   // 确认卡片
        case form           // 信息补充表单
        case locationPick   // 地点选择
        case proactive      // 主动提醒
        case offline        // 离线模式角标
        case usingCloud     // 云端处理小云图标
    }

    func show(_ state: IslandState)
    func dismiss()
}
```

### 5.5 NativeActionExecutor

```swift
class NativeActionExecutor {
    // 接收 Python 返回的 actions 数组，逐一执行
    func execute(_ actions: [NativeAction]) async throws -> [ActionResult]

    // 根据 action.type 路由到对应 Tool
    private func route(_ action: NativeAction) async throws -> ActionResult {
        switch action.type {
        case "create_calendar_event":
            return try await EventKitTool.createEvent(params: action.params)
        case "create_reminder":
            return try await EventKitTool.createReminder(params: action.params)
        case "create_recurring_reminder":
            return try await EventKitTool.createRecurringReminder(params: action.params)
        case "get_today_events":
            return try await EventKitTool.getTodayEvents()
        case "check_calendar_conflict":
            return try await EventKitTool.checkConflict(params: action.params)
        case "get_overdue_reminders":
            return try await EventKitTool.getOverdueReminders()
        case "mark_reminder_done":
            return try await EventKitTool.markDone(params: action.params)
        case "snooze_reminder":
            return try await EventKitTool.snooze(params: action.params)
        case "search_location":
            return try await MapKitTool.search(params: action.params)
        case "save_memory":
            return try await CoreDataTool.saveMemory(params: action.params)
        case "read_memory":
            return try await CoreDataTool.readMemory(params: action.params)
        case "send_notification":
            return try await NotificationTool.send(params: action.params)
        case "create_note":
            return try await NotesTool.createNote(params: action.params)
        case "append_to_note":
            return try await NotesTool.appendToNote(params: action.params)
        default:
            throw ActionError.unknownActionType(action.type)
        }
    }
}
```

### 5.6 EventKitTool

```swift
class EventKitTool {
    private static let store = EKEventStore()

    static func requestAccess() async throws {
        // 申请 Calendar 和 Reminder 权限
        try await store.requestFullAccessToEvents()
        try await store.requestFullAccessToReminders()
    }

    static func createEvent(params: [String: Any]) async throws -> ActionResult {
        let event = EKEvent(eventStore: store)
        event.title = params["title"] as? String ?? ""
        event.startDate = ISO8601DateFormatter().date(from: params["start_time"] as? String ?? "")
        event.endDate = ISO8601DateFormatter().date(from: params["end_time"] as? String ?? "")
        event.location = params["location"] as? String

        // 如果有坐标，设置 structuredLocation
        if let lat = params["latitude"] as? Double,
           let lng = params["longitude"] as? Double {
            let structuredLocation = EKStructuredLocation(title: event.location ?? "")
            structuredLocation.geoLocation = CLLocation(latitude: lat, longitude: lng)
            event.structuredLocation = structuredLocation
        }

        if let notes = params["notes"] as? String {
            event.notes = notes
        }

        event.calendar = store.defaultCalendarForNewEvents
        try store.save(event, span: .thisEvent)
        return ActionResult(success: true, eventId: event.eventIdentifier)
    }

    // 其余方法类似实现...
}
```

### 5.6.1 NotesTool

```swift
// NativeActions/NotesTool.swift
// macOS Notes 没有公开 API，通过 AppleScript 实现

class NotesTool {

    // 新建备忘录
    static func createNote(params: [String: Any]) async throws -> ActionResult {
        let title   = params["title"]  as? String ?? "Jarvis 备忘"
        let content = params["content"] as? String ?? ""
        let folder  = params["folder"] as? String ?? "备忘录"

        // 转义单引号，防止 AppleScript 注入
        let safeTitle   = title.replacingOccurrences(of: "\"", with: "\\\"")
        let safeContent = content.replacingOccurrences(of: "\"", with: "\\\"")
        let safeFolder  = folder.replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Notes"
            activate
            if not (exists folder "\(safeFolder)") then
                make new folder with properties {name:"\(safeFolder)"}
            end if
            tell folder "\(safeFolder)"
                make new note with properties {name:"\(safeTitle)", body:"\(safeContent)"}
            end tell
        end tell
        """

        return try await runAppleScript(script, successMessage: "备忘录已创建：\(title)")
    }

    // 向已有备忘录追加内容
    static func appendToNote(params: [String: Any]) async throws -> ActionResult {
        let title   = params["title"]   as? String ?? ""
        let content = params["content"] as? String ?? ""

        let safeTitle   = title.replacingOccurrences(of: "\"", with: "\\\"")
        let safeContent = content.replacingOccurrences(of: "\"", with: "\\\"")

        // 先检查备忘录是否存在
        let checkScript = """
        tell application "Notes"
            set matchingNotes to every note whose name is "\(safeTitle)"
            return (count of matchingNotes) as string
        end tell
        """

        var checkError: NSDictionary?
        let checkResult = NSAppleScript(source: checkScript)?
            .executeAndReturnError(&checkError)
        let count = Int(checkResult?.stringValue ?? "0") ?? 0

        if count == 0 {
            // 找不到 → 新建
            return try await createNote(params: params)
        }

        let appendScript = """
        tell application "Notes"
            set targetNote to first note whose name is "\(safeTitle)"
            set body of targetNote to (body of targetNote) & "\n\(safeContent)"
        end tell
        """

        return try await runAppleScript(appendScript, successMessage: "已追加到：\(title)")
    }

    // AppleScript 执行工具方法
    private static func runAppleScript(
        _ source: String,
        successMessage: String
    ) async throws -> ActionResult {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let error = error {
                    continuation.resume(throwing: NoteError.appleScriptFailed(
                        error[NSAppleScript.errorMessage] as? String ?? "未知错误"
                    ))
                } else {
                    continuation.resume(returning: ActionResult(
                        success: true,
                        message: successMessage
                    ))
                }
            }
        }
    }
}

enum NoteError: Error {
    case appleScriptFailed(String)
}
```

**权限说明**：

macOS 上使用 AppleScript 操控 Notes 需要在 Info.plist 声明：

```xml
<key>NSAppleEventsUsageDescription</key>
<string>Jarvis 需要使用 AppleScript 将内容写入苹果备忘录。</string>
```

首次运行时系统会弹出授权提示，用户允许后永久生效。

设置页采用卡片式分区布局，每个区块独立展开/收起。整体风格简洁，与 macOS 系统设置一致。

---

#### 5.7.1 推理模式（快捷切换）

设置页顶部展示当前推理模式，支持三档快速切换：

```
推理模式
┌──────────┬──────────┬──────────┐
│  🖥 本地  │  ⚡ Auto  │  ☁ 云端  │
│  端侧优先  │ 智能路由  │  强制云端  │
└──────────┴──────────┴──────────┘
          当前：Auto（推荐）
```

选中项高亮，点击立即生效，实时保存到 UserDefaults。

---

#### 5.7.2 云端 API 配置（多 Provider 表单）

参考 OpenClaw 官方支持的 12 个 Provider 体系，Jarvis 在此基础上补充 Google Gemini 和 DeepSeek 两个主流选项，共 **14 个 Provider + 自定义端点**。界面采用左侧 Provider 列表 + 右侧配置表单的两栏布局。

---

**左侧 Provider 列表**：

```
云端 API

  已配置
  ────────────────
  ✅ Anthropic
  ✅ OpenAI

  主流云端
  ────────────────
     OpenAI
     Anthropic
     Google Gemini
     DeepSeek
     OpenRouter

  国内云端
  ────────────────
     Moonshot（月之暗面）
     MiniMax
     GLM（智谱）
     Z.AI

  企业/开发者
  ────────────────
     Amazon Bedrock
     Vercel AI Gateway
     Synthetic
     OpenCode Zen

  本地服务
  ────────────────
     Ollama

  自定义
  ────────────────
     自定义端点

  [+ 添加自定义 Provider]
```

用户点击任意 Provider 进入右侧配置表单，配置并验证后，Provider 图标前显示 ✅ 标记。

---

**右侧配置表单（以 Anthropic 为例）**：

```
┌──────────────────────────────────────┐
│  Anthropic                      ✅   │
├──────────────────────────────────────┤
│  API Key                             │
│  ┌────────────────────────────────┐  │
│  │ sk-ant-••••••••••••       [👁] │  │
│  └────────────────────────────────┘  │
│                                      │
│  已连接模型                           │
│  ┌────────────────────────────────┐  │
│  │ ● claude-sonnet-4-5     （推荐）│  │
│  │ ○ claude-haiku-4-5             │  │
│  │ ○ claude-opus-4-6              │  │
│  └────────────────────────────────┘  │
│  当前使用：claude-sonnet-4-5          │
│  支持视觉：✅                          │
│                                      │
│  [验证连接]  [删除配置]  [保存]        │
└──────────────────────────────────────┘
```

验证连接后自动展示：
- 已连接的可用模型列表（有 API 拉取则动态获取，否则用预设列表）
- 每个模型是否支持视觉（通过 1×1 测试图片自动探测）
- 用户选择默认使用的模型

---

**14 个 Provider 完整配置**：

```python
PROVIDER_CONFIGS = {
    # === 主流云端 ===
    "openai": {
        "display_name": "OpenAI",
        "category": "mainstream",
        "fields": ["api_key"],
        "api_key_prefix": "sk-",
        "base_url": "https://api.openai.com/v1",
        "docs_url": "https://platform.openai.com/",
        "default_model": "gpt-4o",
        "fetch_models_endpoint": "/models",
        "preset_models": [
            {"id": "gpt-4o",      "name": "GPT-4o",      "vision": True},
            {"id": "gpt-4o-mini", "name": "GPT-4o mini", "vision": True},
        ]
    },
    "anthropic": {
        "display_name": "Anthropic",
        "category": "mainstream",
        "fields": ["api_key"],
        "api_key_prefix": "sk-ant-",
        "base_url": "https://api.anthropic.com",
        "docs_url": "https://console.anthropic.com/",
        "default_model": "claude-sonnet-4-5",
        "fetch_models_endpoint": None,
        "preset_models": [
            {"id": "claude-sonnet-4-5", "name": "Claude Sonnet 4.5", "vision": True},
            {"id": "claude-haiku-4-5",  "name": "Claude Haiku 4.5",  "vision": True},
            {"id": "claude-opus-4-6",   "name": "Claude Opus 4.6",   "vision": True},
        ]
    },
    "google": {
        "display_name": "Google Gemini",
        "category": "mainstream",
        "fields": ["api_key"],
        "api_key_prefix": "AIza",
        "base_url": "https://generativelanguage.googleapis.com/v1beta",
        "docs_url": "https://aistudio.google.com/",
        "default_model": "gemini-2.0-flash",
        "preset_models": [
            {"id": "gemini-2.5-pro",   "name": "Gemini 2.5 Pro",   "vision": True},
            {"id": "gemini-2.0-flash", "name": "Gemini 2.0 Flash", "vision": True},
        ]
    },
    "deepseek": {
        "display_name": "DeepSeek",
        "category": "mainstream",
        "fields": ["api_key"],
        "base_url": "https://api.deepseek.com/v1",
        "docs_url": "https://platform.deepseek.com/",
        "default_model": "deepseek-chat",
        "preset_models": [
            {"id": "deepseek-chat",     "name": "DeepSeek V3",      "vision": False},
            {"id": "deepseek-reasoner", "name": "DeepSeek R1",      "vision": False},
        ]
    },
    "openrouter": {
        "display_name": "OpenRouter",
        "category": "mainstream",
        "fields": ["api_key"],
        "base_url": "https://openrouter.ai/api/v1",
        "docs_url": "https://openrouter.ai/",
        "default_model": "anthropic/claude-sonnet-4-5",
        "fetch_models_endpoint": "/models",
        "preset_models": []  # 数百个模型全部从 API 动态拉取
    },

    # === 国内云端 ===
    "moonshot": {
        "display_name": "Moonshot（月之暗面）",
        "category": "china",
        "fields": ["api_key"],
        "base_url": "https://api.moonshot.cn/v1",
        "docs_url": "https://platform.moonshot.cn/",
        "default_model": "moonshot-v1-8k",
        "preset_models": [
            {"id": "moonshot-v1-8k",    "name": "Moonshot v1 8K",   "vision": False},
            {"id": "moonshot-v1-32k",   "name": "Moonshot v1 32K",  "vision": False},
            {"id": "moonshot-v1-128k",  "name": "Moonshot v1 128K", "vision": False},
        ]
    },
    "minimax": {
        "display_name": "MiniMax",
        "category": "china",
        "fields": ["api_key"],
        "base_url": "https://api.minimax.chat/v1",
        "docs_url": "https://platform.minimax.chat/",
        "default_model": "MiniMax-Text-01",
        "preset_models": [
            {"id": "MiniMax-Text-01", "name": "MiniMax Text-01", "vision": False},
            {"id": "abab6.5s-chat",   "name": "MiniMax 6.5s",    "vision": False},
        ]
    },
    "glm": {
        "display_name": "GLM（智谱）",
        "category": "china",
        "fields": ["api_key"],
        "base_url": "https://open.bigmodel.cn/api/paas/v4",
        "docs_url": "https://open.bigmodel.cn/",
        "default_model": "glm-4-plus",
        "preset_models": [
            {"id": "glm-4-plus",      "name": "GLM-4 Plus",     "vision": False},
            {"id": "glm-4-0520",      "name": "GLM-4",          "vision": False},
            {"id": "glm-4v-plus",     "name": "GLM-4V Plus",    "vision": True},
        ]
    },
    "zai": {
        "display_name": "Z.AI",
        "category": "china",
        "fields": ["api_key"],
        "base_url": "https://api.z.ai/api/paas/v4",
        "docs_url": "https://z.ai/",
        "default_model": "glm-4-plus",
        "preset_models": [
            {"id": "glm-4-plus",   "name": "GLM-4 Plus",   "vision": False},
            {"id": "glm-4v-plus",  "name": "GLM-4V Plus",  "vision": True},
        ]
    },

    # === 企业/开发者 ===
    "bedrock": {
        "display_name": "Amazon Bedrock",
        "category": "enterprise",
        "fields": ["aws_access_key", "aws_secret_key", "region"],
        "docs_url": "https://aws.amazon.com/bedrock/",
        "default_model": "anthropic.claude-sonnet-4-5",
        "preset_models": [
            {"id": "anthropic.claude-sonnet-4-5", "name": "Claude Sonnet 4.5 (Bedrock)", "vision": True},
            {"id": "anthropic.claude-haiku-4-5",  "name": "Claude Haiku 4.5 (Bedrock)",  "vision": True},
        ],
        "note": "需要 AWS IAM 凭证，而非 API Key"
    },
    "vercel": {
        "display_name": "Vercel AI Gateway",
        "category": "enterprise",
        "fields": ["api_key", "base_url"],
        "docs_url": "https://vercel.com/ai-gateway",
        "default_model": "",
        "fetch_models_endpoint": "/models",
        "preset_models": []
    },
    "synthetic": {
        "display_name": "Synthetic",
        "category": "enterprise",
        "fields": ["api_key"],
        "base_url": "https://api.synthetic.new/v1",
        "docs_url": "https://synthetic.new/",
        "default_model": "",
        "fetch_models_endpoint": "/models",
        "preset_models": []
    },
    "opencode_zen": {
        "display_name": "OpenCode Zen",
        "category": "enterprise",
        "fields": ["api_key"],
        "base_url": "https://api.opencode.zen/v1",
        "docs_url": "https://opencode.zen/",
        "default_model": "",
        "preset_models": [],
        "note": "主要面向代码场景"
    },

    # === 本地服务 ===
    "ollama": {
        "display_name": "Ollama（本地服务）",
        "category": "local",
        "fields": ["base_url"],
        "base_url_default": "http://localhost:11434",
        "docs_url": "https://ollama.com/",
        "default_model": "",
        "fetch_models_endpoint": "/api/tags",
        "preset_models": []
    },

    # === 自定义 ===
    "custom": {
        "display_name": "自定义端点",
        "category": "custom",
        "fields": ["base_url", "api_key", "model_id"],
        "docs_url": None,
        "default_model": "",
        "fetch_models_endpoint": None,
        "preset_models": []
    }
}
```

---

**特殊 Provider 的表单差异**：

**Amazon Bedrock**（用 AWS 凭证，不是 API Key）：
```
┌──────────────────────────────────────┐
│  Amazon Bedrock                      │
├──────────────────────────────────────┤
│  AWS Access Key ID                   │
│  ┌────────────────────────────────┐  │
│  │ AKIA••••••••••••••••           │  │
│  └────────────────────────────────┘  │
│                                      │
│  AWS Secret Access Key               │
│  ┌────────────────────────────────┐  │
│  │ ••••••••••••••••••••••••••••  │  │
│  └────────────────────────────────┘  │
│                                      │
│  Region                              │
│  ┌────────────────────────────────┐  │
│  │ us-east-1                    ▾ │  │
│  └────────────────────────────────┘  │
└──────────────────────────────────────┘
```

**Ollama**（无 API Key，只填服务地址）：
```
┌──────────────────────────────────────┐
│  Ollama（本地服务）                   │
├──────────────────────────────────────┤
│  服务地址                             │
│  ┌────────────────────────────────┐  │
│  │ http://localhost:11434         │  │
│  └────────────────────────────────┘  │
│                                      │
│  [验证连接]                           │
│                                      │
│  检测到本地模型（3 个）：              │
│  ● gemma4:e4b                        │
│  ○ qwen3:1.7b                        │
│  ○ llama3.2:3b                       │
└──────────────────────────────────────┘
```

**OpenRouter**（模型太多，支持搜索）：
```
┌──────────────────────────────────────┐
│  OpenRouter                          │
├──────────────────────────────────────┤
│  API Key                             │
│  ┌────────────────────────────────┐  │
│  │ sk-or-••••••••••••             │  │
│  └────────────────────────────────┘  │
│                                      │
│  模型（300+ 个）                      │
│  ┌────────────────────────────────┐  │
│  │ 🔍 搜索模型...                 │  │
│  └────────────────────────────────┘  │
│  ● anthropic/claude-sonnet-4-5       │
│  ○ openai/gpt-4o                     │
│  ○ google/gemini-2.5-pro             │
│  ○ deepseek/deepseek-chat            │
│  ...                                 │
└──────────────────────────────────────┘
```

---

**Python 侧实现策略**：

统一用 `OpenAIProvider` 类处理除 Anthropic 和 Bedrock 外的所有 Provider（它们都兼容 OpenAI API）。Anthropic 用 `ClaudeProvider`，Bedrock 用 `BedrockProvider`（通过 boto3 SDK）。

```python
# providers/provider_factory.py
def create_provider(provider_id: str, config: dict) -> LLMProvider:
    if provider_id == "anthropic":
        return ClaudeProvider(
            api_key=config["api_key"],
            model=config["model"]
        )

    if provider_id == "bedrock":
        return BedrockProvider(
            aws_access_key=config["aws_access_key"],
            aws_secret_key=config["aws_secret_key"],
            region=config["region"],
            model=config["model"]
        )

    # 其他所有 Provider 都用 OpenAI 兼容格式
    provider_config = PROVIDER_CONFIGS[provider_id]
    return OpenAIProvider(
        api_key=config["api_key"],
        model=config["model"],
        base_url=config.get("base_url", provider_config.get("base_url"))
    )
```

---

**动态模型列表拉取**：

```python
async def fetch_available_models(provider_id: str, config: dict) -> list[dict]:
    provider_config = PROVIDER_CONFIGS[provider_id]

    # 没有 API endpoint，用预设列表
    if not provider_config.get("fetch_models_endpoint"):
        return provider_config["preset_models"]

    # 从 API 动态拉取
    base_url = config.get("base_url", provider_config.get("base_url"))
    endpoint = provider_config["fetch_models_endpoint"]

    async with httpx.AsyncClient() as client:
        headers = {}
        if "api_key" in config:
            headers["Authorization"] = f"Bearer {config['api_key']}"

        resp = await client.get(f"{base_url}{endpoint}", headers=headers, timeout=10)
        data = resp.json()

        # 解析模型列表（不同 Provider 格式不同）
        if provider_id == "ollama":
            return [{"id": m["name"], "name": m["name"], "vision": False}
                    for m in data.get("models", [])]
        else:
            # OpenAI 标准格式
            return [{"id": m["id"], "name": m.get("name", m["id"]), "vision": False}
                    for m in data.get("data", [])]
```

---

#### 5.7.3 截图处理策略

```
截图处理（当本地模型不支持视觉时）
● 本地 OCR → 当前模型（推荐，完全离线）
○ 自动切换到视觉模型
○ 发送给云端 API
```

---

#### 5.7.4 端侧模型管理

见第 7 节完整规格。

---

### 5.8 灵动岛交互设计（StatusBarController）

灵动岛胶囊与 macOS 顶部菜单栏**完全等高**，视觉上融为一体。不使用右键菜单，所有交互通过 hover 展开和点击完成。

---

#### 5.8.1 胶囊高度与图标

```swift
// 胶囊高度与 macOS 菜单栏齐平
let menuBarHeight = NSStatusBar.system.thickness  // 22pt 或 24pt
// 胶囊高度 = menuBarHeight
// 胶囊背景随系统深色/浅色模式自动适配

// Jarvis 图标：16×16pt 像素风格图标
// 类似 Claude logo 的简洁风格
// 深色模式：浅色图标
// 浅色模式：深色图标
// 此图标同时用于：灵动岛胶囊、Dock 图标、macOS 菜单栏图标
```

---

#### 5.8.2 常态（静默状态）

```
┌──────┐
│ [J✦] │    ← 只有 Jarvis 像素图标，极简
└──────┘
```

不占用多余空间，和其他菜单栏图标一样低调。

---

#### 5.8.3 鼠标 hover（展开悬停态）

鼠标移入胶囊区域后，胶囊平滑横向展开，露出功能按钮：

```
┌──────────────────────────────────────────────────────────────────┐
│ [J✦]  [💬 对话]  [📸]  [⚡Auto ▾]  [🧠 Qwen3 1.7B ▾]  [📋]    │
└──────────────────────────────────────────────────────────────────┘
```

各按钮功能：

| 按钮 | 功能 | 说明 |
|------|------|------|
| `[J✦]` | 图标 | 始终在最左，无点击行为 |
| `[💬 对话]` | 展开对话面板 | 点击后面板从胶囊下方展开 |
| `[📸]` | 截图识别 | 等同 ⌘⇧J |
| `[⚡Auto ▾]` | 推理模式切换 | 点击弹出下拉菜单 |
| `[🧠 Qwen3 1.7B ▾]` | 模型选择 | 点击弹出模型列表 |
| `[📋]` | Task List | 点击展开今日日程/待办列表 |

鼠标离开胶囊区域后，按钮收回，恢复只有图标的状态。展开/收回使用 `easeOut(0.2s)`，与 macOS 原生动效一致。

---

#### 5.8.4 推理模式下拉（⚡Auto ▾）

```
┌─────────────────────────┐
│  推理模式                │
│  ● Auto（智能路由）      │
│  ○ 端侧                 │
│  ○ 云端                 │
└─────────────────────────┘
```

选中项显示 ● 标记，切换后立即生效。通过 `@AppStorage("inference_mode")` 与设置页、macOS 菜单栏三处联动。

---

#### 5.8.5 模型选择下拉（🧠 Qwen3 1.7B ▾）

```
┌──────────────────────────────┐
│  端侧模型                    │
│  ● Qwen3 1.7B               │
│  ○ Gemma 4 E4B               │
│  ○ Qwen3 0.6B   ⬇ 未安装     │
│  ─────────────────           │
│  云端模型                    │
│  ○ claude-sonnet-4-5  (API)  │
│  ○ gpt-4o             (API) │
│  ○ deepseek-chat       (API) │
│  ─────────────────           │
│  ⚙️ 管理模型...              │
└──────────────────────────────┘
```

- 已安装的端侧模型和已配置的云端 API 模型都在这里
- 切换端侧模型时：按钮变为 `[🧠 加载中...]`，Python 卸载旧模型→加载新模型→完成后按钮更新为新模型名
- 切换云端模型时：立即切换，无等待
- 未安装的模型显示 `⬇ 未安装`，点击跳转到模型管理设置页
- `⚙️ 管理模型...`：打开设置页的模型管理区块

---

#### 5.8.6 对话展开态

```
┌──────────────────────────────────────────────────────────────────┐
│ [J✦]  [💬 对话]  [📸]  [⚡Auto ▾]  [🧠 Qwen3 1.7B ▾]  [📋]    │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Jarvis: 今天下午有一个会议在国贸三期                             │
│                                                                  │
│  You: 帮我加一个明天下午3点的开会                                 │
│                                                                  │
│  Jarvis: 大概持续多久？                                           │
│  [30分钟] [1小时] [1.5小时] [2小时]                              │
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────────┐    │
│  │ 输入消息... 支持粘贴或拖拽图片                           │    │
│  │                                                          │    │
│  │ [🖼️ screenshot.jpg  ✕]                                  │    │  ← 图片预览
│  └──────────────────────────────────────────────────────────┘    │
│                                                        [↵ 发送]  │
└──────────────────────────────────────────────────────────────────┘
```

**输入框支持图片输入**：
- `⌘V` 粘贴剪贴板中的图片
- 拖拽图片文件到输入框
- 添加后显示缩略图预览（文件名 + ✕ 移除按钮）
- 发送时图片压缩为 JPEG（最大边 1024px，quality 0.85）并 Base64 编码附带在请求中
- 图片进入后自动走 ModelRouter 的视觉路由

---

#### 5.8.7 Task List 展开态

```
┌──────────────────────────────────────────────────────────────────┐
│ [J✦]  [💬 对话]  [📸]  [⚡Auto ▾]  [🧠 Qwen3 1.7B ▾]  [📋]    │
├──────────────────────────────────────────────────────────────────┤
│  今日日程                                        4月18日 周五    │
│  ────────                                                        │
│  14:00 - 15:00   与王总开会     📍 国贸三期                      │
│  17:00 - 18:00   周三例会                                        │
│                                                                  │
│  待办事项                                                        │
│  ────────                                                        │
│  ☐  交期末PPT            截止 4/20 22:00      🟡 medium         │
│  ☐  买生日礼物           截止 4/22                               │
│  ☑  缴水电费             已完成               ────               │
│                                                                  │
│  [打开 Calendar]  [打开 Reminder]                                │
└──────────────────────────────────────────────────────────────────┘
```

- 日程和待办分区展示
- 待办项可直接点击 ☐ 标记完成（调用 `mark_reminder_done` Tool）
- 已完成项灰色显示
- 底部链接可打开 macOS 原生 Calendar / Reminder 应用

### 5.9 UI 动效与视觉规格

设计原则：**与 macOS 原生风格保持一致，克制而不花哨**。动效只用于帮助用户感知状态变化，不做炫技。参考 Spotlight、快速备忘录等苹果原生 popover 组件的交互方式。

---

#### 5.9.1 动效参数

```swift
enum JarvisAnimation {
    // 面板展开/收起，与 macOS popover 一致
    static let panel = Animation.easeOut(duration: 0.2)

    // 内容出现
    static let content = Animation.easeOut(duration: 0.15)

    // 按钮按压反馈
    static let press = Animation.easeOut(duration: 0.1)
}
```

---

#### 5.9.2 面板展开/收起

```swift
// 展开：面板从顶部向下展开，内容淡入
// 收起：内容淡出，面板向上收起
// 使用 easeOut，不过冲，不弹跳

withAnimation(JarvisAnimation.panel) {
    isExpanded = true
}
// 内容在面板展开完成后淡入（delay 0.05s）
```

**核心原则**：不做胶囊放大缩小、不做 3D 翻转、不做逐行错落淡入。面板就是自然地出现和消失，和系统 popover 行为一致。

---

#### 5.9.3 按钮交互反馈

```swift
struct JarvisButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(JarvisAnimation.press, value: configuration.isPressed)
    }
}
// 按压时透明度下降，松开恢复，简单直接
// 不做 scale 缩放，避免抖动感
```

---

#### 5.9.4 加载状态

推理进行中：输入框右侧显示系统原生 `ProgressView()`（旋转菊花），不做自定义动效。

---

#### 5.9.5 写入成功反馈

写入完成后，确认卡片淡出，灵动岛胶囊短暂显示 ✓ 图标后恢复正常。无声音、无震动。

---

#### 5.9.6 视觉规范

```swift
// 背景：NSVisualEffectView，material = .popover（与系统 popover 一致）
// 圆角：10pt（与 macOS 标准 popover 一致）
// 字体：.system（SF Pro），不引入任何自定义字体
// 颜色：全部使用语义颜色（.primary、.secondary、.accentColor）
//       跟随系统亮色/深色模式，不硬编码颜色值
// 间距：遵循 8pt 网格系统
// 面板宽度：固定 300pt，高度随内容自适应，最大 440pt（超出内部滚动）

// 推理状态指示（极简）
// 本地推理：无额外标记
// 云端推理：输入框右下角显示小云图标 ☁️（8pt，灰色）
// 离线模式：胶囊文字变灰
```

---

#### 5.9.7 实现要点

- 所有动效使用 SwiftUI 原生 `withAnimation`，不引入第三方动效库
- 检测 `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`，开启时跳过所有过渡动效
- 不做任何逐帧自定义动画，只用 SwiftUI 内置的 transition 和 animation

---

### 5.10 macOS 顶部菜单栏（Menu Bar）

> **注意**：这里指的是 macOS 屏幕最顶部的黑色菜单栏（显示 Apple 图标、应用名称、文件、编辑等的那一栏），不是灵动岛胶囊本身的右键菜单。
>
> 灵动岛胶囊的右键菜单见 5.8 节。

macOS 应用在顶部菜单栏注册自己的菜单项，用户不展开任何面板就能通过菜单栏操作 Jarvis。

---

#### 5.10.1 菜单结构

```
Jarvis（App 菜单，最左侧）
├── 关于 Jarvis
├── ──────────────
├── 偏好设置...            ⌘,
└── 退出 Jarvis            ⌘Q

操作
├── 截图识别               ⌘⇧J
└── 新建对话               ⌘N

推理模式
├── ✓ 智能路由（Auto）     ⌘1   ← 当前选中项显示 ✓
├──   仅本地               ⌘2
└──   仅云端               ⌘3

模型
├── 管理端侧模型...
└── 配置云端 API...

帮助
├── 使用指南
└── 报告问题...
```

---

#### 5.10.2 Swift 实现

```swift
// JarvisApp.swift
@main
struct JarvisApp: App {
    var body: some Scene {
        // 状态栏图标（无主窗口 App）
        MenuBarExtra("Jarvis", systemImage: "sparkles") {
            StatusBarMenuView()
        }
        .menuBarExtraStyle(.window)

        // 偏好设置窗口（⌘, 打开）
        Settings {
            SettingsView()
        }
    }
}

// JarvisCommands.swift — 注册到顶部菜单栏
struct JarvisCommands: Commands {
    @AppStorage("inference_mode") var inferenceMode = "smart"

    var body: some Commands {
        // 「操作」菜单
        CommandMenu("操作") {
            Button("截图识别") {
                CaptureManager.shared.capture()
            }
            .keyboardShortcut("j", modifiers: [.command, .shift])

            Button("新建对话") {
                StatusBarController.shared.openConversation()
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        // 「推理模式」菜单
        CommandMenu("推理模式") {
            modeButton("智能路由（Auto）", value: "smart",        shortcut: "1")
            modeButton("仅本地",          value: "force_local",  shortcut: "2")
            modeButton("仅云端",          value: "force_cloud",  shortcut: "3")
        }

        // 「模型」菜单
        CommandMenu("模型") {
            Button("管理端侧模型...") {
                StatusBarController.shared.openModelManager()
            }
            Button("配置云端 API...") {
                StatusBarController.shared.openAPISettings()
            }
        }
    }

    @ViewBuilder
    private func modeButton(_ label: String, value: String, shortcut: String) -> some View {
        Button {
            inferenceMode = value
        } label: {
            // 当前选中项在菜单里自动显示 ✓（macOS 标准行为）
            Text(label)
        }
        .keyboardShortcut(KeyEquivalent(shortcut.first!), modifiers: .command)
        // 通过 @AppStorage 自动标记选中状态
    }
}
```

---

#### 5.10.3 状态三处联动

推理模式的修改通过 `@AppStorage("inference_mode")` 自动同步：

```
macOS 顶部菜单栏「推理模式」
        ↕  @AppStorage 自动同步
灵动岛对话底部工具栏模式按钮
        ↕  @AppStorage 自动同步
设置页推理模式分段控件
```

三处任意一处修改，其他两处立即反映，无需手动通知。

---

#### 5.10.4 偏好设置窗口（⌘,）

`Settings { SettingsView() }` 会自动在 macOS 中注册标准的偏好设置窗口，支持 ⌘, 快捷键打开，符合 macOS 应用规范。设置窗口独立于灵动岛面板，是标准的单独窗口。

---

## 6. Python 层开发规格

### 6.1 模块结构

```
Python/
├── gateway.py                  # FastAPI 入口
├── agent/
│   ├── jarvis_agent.py         # ReAct Core
│   ├── heartbeat.py            # Heartbeat Loop
│   ├── memory_manager.py       # 记忆管理
│   ├── model_router.py         # 智能路由
│   ├── tool_router.py          # Tool 调度
│   ├── output_validator.py     # 格式验证
│   ├── wal.py                  # 写前日志
│   ├── self_improving.py       # 学习模块
│   └── training_collector.py   # 训练数据收集
├── providers/
│   ├── base.py                 # LLMProvider 抽象基类
│   ├── gemma_mlx.py            # Gemma 4 E2B/E4B
│   ├── qwen3_mlx.py            # Qwen3 0.6B/1.7B
│   ├── claude.py               # Anthropic API
│   └── openai_compat.py        # OpenAI 兼容 API
├── tools/
│   ├── definitions.py          # 所有 Tool 的 JSON Schema
│   ├── split_task.py           # 纯 Python 执行的 Tool
│   └── weather_provider.py     # 天气数据
└── requirements.txt
```

### 6.2 Gateway（FastAPI）

```python
# gateway.py
from fastapi import FastAPI
from contextlib import asynccontextmanager
import asyncio

app = FastAPI()

@asynccontextmanager
async def lifespan(app: FastAPI):
    # 启动时初始化 Agent、加载模型、启动 Heartbeat Loop
    await agent_runner.start()
    asyncio.create_task(heartbeat.start())
    yield
    # 关闭时清理资源
    await agent_runner.stop()

app = FastAPI(lifespan=lifespan)

@app.get("/health")
async def health():
    return {"status": "ok", "model": model_manager.active_model_name}

@app.post("/chat")
async def chat(req: ChatRequest) -> ChatResponse:
    """
    处理用户主动触发的请求
    req 包含：message, image(base64), session_id,
             form_data, location_selected, user_action, corrections
    """
    return await agent_runner.handle_user_input(req)

@app.post("/confirm")
async def confirm(req: ConfirmRequest) -> ChatResponse:
    """
    用户确认主动提醒后，执行实际操作
    req 包含：action_id, user_choice
    """
    return await agent_runner.handle_confirmation(req)

@app.post("/action_result")
async def action_result(req: ActionResultRequest):
    """
    Swift 执行原生操作后回传结果
    req 包含：action_type, success, result, error
    """
    await agent_runner.handle_action_result(req)

@app.post("/settings")
async def update_settings(req: SettingsRequest):
    """
    更新用户配置（推理模式、API Key、模型选择等）
    """
    await settings_manager.update(req)
    return {"status": "ok"}

@app.post("/model/switch")
async def switch_model(req: SwitchModelRequest):
    """
    切换端侧模型
    req 包含：variant (qwen3-0.6b / qwen3-1.7b / gemma4-e2b / gemma4-e4b)
    """
    await model_manager.switch_to(req.variant)
    return {"status": "ok"}

@app.post("/expand_island")
async def expand_island(req: IslandExpandRequest):
    """
    Heartbeat Loop 触发主动展开灵动岛
    通知 Swift 展开面板
    """
    # 通过 Swift 的回调接口（或 WebSocket）推送
    await swift_callback.push(req)
```

### 6.3 LLMProvider 基类

```python
# providers/base.py
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Optional

@dataclass
class Message:
    role: str           # "system" / "user" / "assistant" / "tool"
    content: str
    tool_call_id: Optional[str] = None

@dataclass
class ToolCall:
    name: str
    params: dict
    call_id: str

@dataclass
class LLMResponse:
    text: str
    tool_call: Optional[ToolCall] = None
    finish_reason: str = "stop"     # "stop" / "tool_calls" / "length"
    retry_count: int = 0

class LLMProvider(ABC):
    @abstractmethod
    async def chat(
        self,
        messages: list[Message],
        tools: list[dict],          # Tool JSON Schema 列表
        image: Optional[str] = None  # Base64 编码图片
    ) -> LLMResponse:
        pass

    @property
    @abstractmethod
    def supports_vision(self) -> bool:
        pass

    @property
    @abstractmethod
    def provider_name(self) -> str:
        pass

    @property
    @abstractmethod
    def model_name(self) -> str:
        pass
```

### 6.4 GemmaMLXProvider

```python
# providers/gemma_mlx.py
from mlx_lm import load, generate
from mlx_lm.utils import generate_step
from .base import LLMProvider, LLMResponse, Message
import json

class GemmaMLXProvider(LLMProvider):
    def __init__(self, model_path: str):
        self.model, self.tokenizer = load(model_path)
        self._model_name = model_path.split("/")[-1]

    @property
    def supports_vision(self) -> bool:
        return "e2b" in self._model_name.lower() or "e4b" in self._model_name.lower()

    @property
    def provider_name(self) -> str:
        return "local_mlx"

    @property
    def model_name(self) -> str:
        return self._model_name

    async def chat(self, messages, tools, image=None) -> LLMResponse:
        # 构建 prompt（Gemma 4 chat template）
        prompt = self._build_prompt(messages, tools, image)

        # MLX 推理
        response_text = generate(
            self.model,
            self.tokenizer,
            prompt=prompt,
            max_tokens=1024,
            verbose=False
        )

        # 解析 Tool Call
        return self._parse_response(response_text)

    def _build_prompt(self, messages, tools, image):
        # 按照 Gemma 4 chat template 构建
        # 如果有图片且支持视觉，将图片 token 插入 prompt
        pass

    def _parse_response(self, text: str) -> LLMResponse:
        # 尝试解析 JSON Tool Call
        # 如果是纯文本则返回文本响应
        try:
            parsed = json.loads(text.strip())
            if "tool" in parsed:
                return LLMResponse(
                    text="",
                    tool_call=ToolCall(
                        name=parsed["tool"],
                        params=parsed.get("params", {}),
                        call_id=str(uuid4())
                    )
                )
        except json.JSONDecodeError:
            pass
        return LLMResponse(text=text)
```

### 6.5 Qwen3MLXProvider

```python
# providers/qwen3_mlx.py
# 与 GemmaMLXProvider 结构相同，区别：
# 1. supports_vision 始终返回 False
# 2. 使用 Qwen3 chat template
# 3. 支持 thinking mode（可配置）

class Qwen3MLXProvider(LLMProvider):
    def __init__(self, model_path: str, enable_thinking: bool = False):
        self.model, self.tokenizer = load(model_path)
        self.enable_thinking = enable_thinking
        self._model_name = model_path.split("/")[-1]

    @property
    def supports_vision(self) -> bool:
        return False

    # thinking mode 仅在 enable_thinking=True 且任务明确需要时使用
    # 日程识别等简单任务关闭，复杂推理任务开启
```

### 6.6 ClaudeProvider

```python
# providers/claude.py
import anthropic
import base64
from .base import LLMProvider, LLMResponse, Message

class ClaudeProvider(LLMProvider):
    SUPPORTED_MODELS = [
        "claude-sonnet-4-5",
        "claude-haiku-4-5",
        "claude-opus-4-6",
    ]

    def __init__(self, api_key: str, model: str = "claude-sonnet-4-5"):
        self.client = anthropic.AsyncAnthropic(api_key=api_key)
        self._model = model
        self._supports_vision = True  # 所有 Claude 模型支持视觉

    @property
    def supports_vision(self) -> bool:
        return self._supports_vision

    async def chat(self, messages, tools, image=None) -> LLMResponse:
        # 构建 Anthropic API 格式的 messages
        anthropic_messages = self._convert_messages(messages, image)
        anthropic_tools = self._convert_tools(tools)

        response = await self.client.messages.create(
            model=self._model,
            max_tokens=1024,
            messages=anthropic_messages,
            tools=anthropic_tools if tools else []
        )

        return self._parse_response(response)
```

### 6.7 OpenAIProvider

```python
# providers/openai_compat.py
# 支持 OpenAI API 和任意 OpenAI 兼容端点
# 自动探测视觉能力（通过发送测试图片）

class OpenAIProvider(LLMProvider):
    def __init__(
        self,
        api_key: str,
        model: str = "gpt-4o",
        base_url: str = "https://api.openai.com/v1"
    ):
        from openai import AsyncOpenAI
        self.client = AsyncOpenAI(api_key=api_key, base_url=base_url)
        self._model = model
        self._supports_vision = None  # 待探测

    async def probe_vision_capability(self) -> bool:
        """用户保存配置时静默调用，发送 1x1 像素测试图探测视觉支持"""
        try:
            test_image = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
            await self.client.chat.completions.create(
                model=self._model,
                messages=[{
                    "role": "user",
                    "content": [
                        {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{test_image}"}},
                        {"type": "text", "text": "ok"}
                    ]
                }],
                max_tokens=5
            )
            self._supports_vision = True
        except Exception:
            self._supports_vision = False
        return self._supports_vision
```

---

## 7. 模型管理规格

### 7.1 支持的模型

```python
# providers/model_registry.py

SUPPORTED_MODELS = {
    "qwen3-0.6b": {
        "display_name": "Qwen3 0.6B",
        "description": "极致轻量，速度最快，适合 8GB Mac",
        "disk_gb": 0.4,
        "ram_gb": 1.0,
        "supports_vision": False,
        "tool_call_score": 0.880,
        "context_length": 32768,
        "min_ram_gb": 8,
        "speed_tier": "fastest",    # fastest / fast / medium
        "recommended_for": ["8gb_mac"],
        "mlx_repo": "mlx-community/Qwen3-0.6B-4bit",
        "provider_class": "Qwen3MLXProvider"
    },
    "qwen3-1.7b": {
        "display_name": "Qwen3 1.7B",
        "description": "Tool Call 最高分（0.960），文字任务首选",
        "disk_gb": 1.0,
        "ram_gb": 2.0,
        "supports_vision": False,
        "tool_call_score": 0.960,
        "context_length": 32768,
        "min_ram_gb": 8,
        "speed_tier": "fast",
        "recommended_for": ["8gb_mac", "text_only"],
        "mlx_repo": "mlx-community/Qwen3-1.7B-4bit",
        "provider_class": "Qwen3MLXProvider"
    },
    "gemma4-e2b": {
        "display_name": "Gemma 4 E2B",
        "description": "支持截图视觉理解，8GB Mac 可用",
        "disk_gb": 1.3,
        "ram_gb": 2.5,
        "supports_vision": True,
        "tool_call_score": 0.820,
        "context_length": 131072,
        "min_ram_gb": 8,
        "speed_tier": "fast",
        "recommended_for": ["8gb_mac", "vision"],
        "mlx_repo": "mlx-community/gemma-4-E2B-it-4bit",
        "provider_class": "GemmaMLXProvider"
    },
    "gemma4-e4b": {
        "display_name": "Gemma 4 E4B",
        "description": "视觉+Tool Call 综合最强，推荐 16GB Mac",
        "disk_gb": 6.3,
        "ram_gb": 7.5,
        "supports_vision": True,
        "tool_call_score": 0.900,
        "context_length": 131072,
        "min_ram_gb": 16,
        "speed_tier": "medium",
        "recommended_for": ["16gb_mac", "vision", "best_quality"],
        "mlx_repo": "mlx-community/gemma-4-E4B-it-4bit",
        "provider_class": "GemmaMLXProvider"
    }
}
```

### 7.2 ModelManager（Swift 侧）

```swift
// Models/ModelManager.swift
@Observable
class ModelManager {
    var installedModels: [ModelVariant] = []
    var activeModel: ModelVariant?
    var downloadingModel: ModelVariant?
    var downloadProgress: Double = 0     // 0.0 ~ 1.0
    var downloadState: DownloadState = .idle

    enum DownloadState {
        case idle, downloading, paused, installing, completed, failed(Error)
    }

    // 检测系统内存，返回推荐模型
    func recommendedModel() -> String {
        let ramGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        let freeDisk = getFreeDiskSpace()

        if ramGB >= 16 && freeDisk > 7 {
            return "gemma4-e4b"
        } else if ramGB >= 8 && freeDisk > 2 {
            return "gemma4-e2b"
        } else {
            return "qwen3-1.7b"
        }
    }

    // 下载模型
    // 使用 URLSession 下载，支持断点续传
    // 下载到 ~/.jarvis/models/{variant}/
    // 下载完成后验证 SHA256
    // 验证通过后通知 Python 切换模型
    func downloadModel(_ variant: String) async throws

    // 切换模型（通知 Python Gateway）
    func switchModel(to variant: String) async throws {
        try await gatewayClient.switchModel(variant: variant)
        activeModel = installedModels.first { $0.id == variant }
        UserDefaults.standard.set(variant, forKey: "active_model")
    }

    // 卸载模型
    func uninstallModel(_ variant: String) async throws {
        let modelPath = modelsDirectory.appendingPathComponent(variant)
        try FileManager.default.removeItem(at: modelPath)
        installedModels.removeAll { $0.id == variant }

        // 如果卸载的是当前模型，提示用户选择其他模型
        if activeModel?.id == variant {
            activeModel = nil
            // 通知 Python 卸载模型
            try await gatewayClient.unloadModel()
        }
    }

    // 磁盘和内存检查
    func canInstall(_ variant: String) -> InstallCheckResult {
        guard let meta = SUPPORTED_MODELS[variant] else {
            return .failed("未知模型")
        }
        let freeDisk = getFreeDiskSpace()
        let totalRAM = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)

        if freeDisk < Int64(meta.diskGB * 1024 * 1024 * 1024) {
            return .insufficientDisk(needed: meta.diskGB, available: Double(freeDisk) / 1e9)
        }
        if totalRAM < meta.minRAMGB {
            return .insufficientRAM(needed: meta.minRAMGB, available: Int(totalRAM))
        }
        return .ok
    }
}
```

### 7.3 模型存储路径

模型文件存储在 App Bundle 内的 `models/` 目录下，而非用户 Home 目录。这样便于打包分发，用户无需关心文件位置。

```
Jarvis.app/
└── Contents/
    └── Resources/
        └── models/                  # 模型文件根目录
            ├── qwen3-0.6b/          # Qwen3 0.6B MLX 格式
            │   ├── config.json
            │   ├── tokenizer.json
            │   └── model.safetensors
            ├── qwen3-1.7b/
            ├── gemma4-e2b/
            └── gemma4-e4b/
```

**路径获取方式（Swift）**：
```swift
// 获取 App bundle 内的 models 目录
let modelsDir = Bundle.main.resourceURL!.appendingPathComponent("models")

// 某个模型的路径
let modelPath = modelsDir.appendingPathComponent("gemma4-e4b")

// Python 侧通过启动参数获取路径
// GatewayManager 启动 Python 时传入 --models-dir 参数
process.arguments = [gatewayPath, "--port", "8765", "--models-dir", modelsDir.path]
```

**Python 侧接收**：
```python
# gateway.py 启动参数
import argparse
parser = argparse.ArgumentParser()
parser.add_argument("--models-dir", required=True)
args = parser.parse_args()
MODELS_DIR = Path(args.models_dir)
```

**下载行为**：
- 用户首次安装时，App Bundle 内 `models/` 为空目录（或只有占位文件）
- 用户在 Onboarding 或 SettingsView 选择下载模型时，下载到 `models/{variant}/`
- 下载完成后验证 SHA256，通知 Python 加载
- 卸载模型：删除对应子目录，Python 侧卸载已加载的模型

### 7.4 Python 侧 ModelManager

```python
# agent/model_manager.py
import gc
from mlx_lm import load

class ModelManager:
    def __init__(self):
        self.current_provider = None
        self.current_variant = None

    async def load_model(self, variant: str, model_path: str):
        """加载指定模型，卸载当前模型"""
        # 卸载当前模型，释放内存
        if self.current_provider:
            del self.current_provider
            gc.collect()

        meta = SUPPORTED_MODELS[variant]
        provider_class = get_provider_class(meta["provider_class"])
        self.current_provider = provider_class(model_path)
        self.current_variant = variant

    async def unload(self):
        """卸载当前模型"""
        if self.current_provider:
            del self.current_provider
            gc.collect()
            self.current_provider = None
            self.current_variant = None

    def get_active_provider(self):
        return self.current_provider

    def active_supports_vision(self) -> bool:
        if not self.current_provider:
            return False
        return self.current_provider.supports_vision
```

---

## 8. 智能路由规格

### 8.1 完整决策树

```python
# agent/model_router.py

class ModelRouter:

    async def route(self, input: AgentInput) -> RoutingResult:

        # 第一层：用户强制模式
        mode = self.settings.inference_mode
        if mode == "force_local":
            return await self._route_local(input)
        if mode == "force_cloud":
            return await self._route_cloud(input)
        # mode == "smart"：进入智能路由

        # 第二层：网络检查
        if not await self._is_online():
            return RoutingResult(
                provider=self.model_manager.get_active_provider(),
                mode="local_offline"
            )

        # 第三层：输入类型路由
        if input.has_image:
            return await self._route_vision(input)
        else:
            return await self._route_text(input)

    async def _route_vision(self, input: AgentInput) -> RoutingResult:
        active = self.model_manager.get_active_provider()

        # 有本地视觉模型
        if active and active.supports_vision:
            return RoutingResult(
                provider=active,
                image=input.image,
                mode="local_vision"
            )

        # 本地模型不支持视觉
        if active and not active.supports_vision:
            strategy = self.settings.vision_fallback_strategy

            if strategy == "ocr_then_local":
                # 本地 OCR → 文字 → 当前模型
                ocr_text = await self._run_ocr(input.image)
                return RoutingResult(
                    provider=active,
                    message=self._build_ocr_message(ocr_text, input.message),
                    image=None,
                    mode="local_ocr_fallback"
                )

            elif strategy == "auto_switch_vision":
                # 切换到已安装的视觉模型
                vision_provider = self._get_installed_vision_provider()
                if vision_provider:
                    return RoutingResult(
                        provider=vision_provider,
                        image=input.image,
                        mode="switched_vision_model"
                    )
                # 没有安装视觉模型，降级到 OCR
                ocr_text = await self._run_ocr(input.image)
                return RoutingResult(
                    provider=active,
                    message=self._build_ocr_message(ocr_text, input.message),
                    image=None,
                    mode="local_ocr_fallback_no_vision_model"
                )

            elif strategy == "cloud":
                return await self._route_to_cloud_with_image(input)

        # 没有本地模型
        return await self._route_to_cloud_with_image(input)

    async def _route_to_cloud_with_image(self, input: AgentInput) -> RoutingResult:
        cloud = self._get_cloud_provider()
        if cloud and cloud.supports_vision:
            return RoutingResult(provider=cloud, image=input.image, mode="cloud_vision")

        # 云端不支持视觉，OCR 降级
        ocr_text = await self._run_ocr(input.image)
        return RoutingResult(
            provider=cloud,
            message=self._build_ocr_message(ocr_text, input.message),
            image=None,
            mode="cloud_ocr_fallback"
        )

    async def _route_text(self, input: AgentInput) -> RoutingResult:
        active = self.model_manager.get_active_provider()

        # 第四层：难度预判
        difficulty = self._estimate_difficulty(input)
        cloud = self._get_cloud_provider()

        if difficulty == Difficulty.HIGH and cloud:
            return RoutingResult(provider=cloud, mode="cloud_difficult_task")

        # 第五层：端侧执行（由 JarvisAgent 处理 fallback）
        if active:
            return RoutingResult(
                provider=active,
                mode="local_text",
                allow_cloud_fallback=cloud is not None
            )

        # 没有本地模型
        if cloud:
            return RoutingResult(provider=cloud, mode="cloud_no_local_model")

        raise NoProviderAvailableError("没有可用的推理模型，请下载端侧模型或配置云端 API")

    def _estimate_difficulty(self, input: AgentInput) -> Difficulty:
        """事前难度预判，基于输入特征评分"""
        score = 0

        # 输入长度
        if len(input.message) > 200:
            score += 1
        if len(input.message) > 500:
            score += 1

        # 多任务信号
        multi_task_signals = ["另外", "还有", "同时", "以及", "第一", "第二", "还需要"]
        if any(s in input.message for s in multi_task_signals):
            score += 2

        # 规划拆解信号
        complex_signals = ["帮我规划", "拆分", "分解", "制定计划", "怎么做", "步骤", "安排"]
        if any(s in input.message for s in complex_signals):
            score += 2

        # 模糊时间
        vague_time = ["最近", "尽快", "有空", "方便的时候", "下次", "某天"]
        if any(s in input.message for s in vague_time):
            score += 1

        # 多轮对话深度
        if input.turn_count >= 3:
            score += 1
        if input.turn_count >= 5:
            score += 1

        if score >= 5:
            return Difficulty.HIGH
        elif score >= 2:
            return Difficulty.MEDIUM
        else:
            return Difficulty.LOW

    async def _run_ocr(self, image_base64: str) -> str:
        """
        使用苹果 Vision Framework 进行本地 OCR
        通过 Swift GatewayClient 的 /ocr 接口调用
        返回识别出的文字
        """
        # Swift 侧实现 VNRecognizeTextRequest
        # 支持中英文混排、手写体识别
        result = await self.swift_callback.run_ocr(image_base64)
        return result.text

    def _build_ocr_message(self, ocr_text: str, original_message: str) -> str:
        return f"""以下是从截图中提取的文字内容（图片已通过 OCR 转为文字处理）：

{ocr_text}

{f'用户补充说明：{original_message}' if original_message else ''}"""
```

### 8.2 OCR 端点（Swift 侧）

```swift
// 在 GatewayClient 中添加 OCR 端点
// Swift 侧通过 Vision Framework 执行 OCR，结果返回给 Python

func runOCR(imageBase64: String) async throws -> OCRResult {
    guard let imageData = Data(base64Encoded: imageBase64),
          let nsImage = NSImage(data: imageData),
          let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
        throw OCRError.invalidImage
    }

    return try await withCheckedThrowingContinuation { continuation in
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                continuation.resume(throwing: error)
                return
            }
            let text = (request.results as? [VNRecognizedTextObservation] ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            continuation.resume(returning: OCRResult(text: text))
        }
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.recognitionLevel = .accurate

        let handler = VNImageRequestHandler(cgImage: cgImage)
        try? handler.perform([request])
    }
}
```

---

## 9. Agent 框架规格

### 9.1 System Prompt 模板（固定格式）

> **重要**：此格式从第一天起固定，未来训练数据必须与此格式完全一致，不得随意修改占位符名称或结构。

```python
SYSTEM_PROMPT_TEMPLATE = """你是 Jarvis，用户的 macOS AI 助理，常驻在屏幕顶部的灵动岛。

## 用户规则（必须严格遵守，优先级最高）
{memory}

## 用户偏好（从历史交互中学到的）
{learnings}

## 用户画像
{soul}

## 今日日程
{today_events}

## 当前时间
{current_time}

## 工作原则
- 识别到地点时，必须先调用 search_location 获取坐标，再写入日历
- 写入日历前必须调用 check_conflict 检查时间冲突
- 信息缺失时调用 ask_clarification，列出缺失字段
- 用户描述周期性规则或偏好时，调用 save_memory 记录
- 自主触发模式（is_autonomous）：只能读取数据和发通知，禁止写入任何数据
- 回复简洁，用一句话确认结果，不啰嗦

## 可用工具
{tool_descriptions}

## 输出格式
Tool Call 时输出 JSON：
{{"thinking": "简短的推理过程", "tool": "tool_name", "params": {{...}}}}

直接回复时输出纯文本。
"""
```

### 9.2 JarvisAgent（ReAct Core）

```python
# agent/jarvis_agent.py

class JarvisAgent:
    MAX_TURNS = 3
    MAX_VALIDATOR_RETRIES = 2

    def __init__(
        self,
        model_manager: ModelManager,
        model_router: ModelRouter,
        tool_router: ToolRouter,
        memory_manager: MemoryManager,
        output_validator: OutputValidator,
        training_collector: TrainingDataCollector,
        self_improving: SelfImproving
    ):
        self.model_manager = model_manager
        self.model_router = model_router
        self.tool_router = tool_router
        self.memory_manager = memory_manager
        self.validator = output_validator
        self.collector = training_collector
        self.self_improving = self_improving

        # session_id → messages 列表（短期记忆）
        self.sessions: dict[str, list[Message]] = {}

    async def run(
        self,
        input: AgentInput,
        is_autonomous: bool = False
    ) -> AgentResponse:

        # 处理 F9：记录用户修改/拒绝
        if input.user_action == "modified" and input.corrections:
            await self.self_improving.record_correction(
                original=input.original_result,
                corrected=input.corrections
            )
        elif input.user_action == "rejected":
            await self.self_improving.record_rejection(input.last_action)

        # 构建上下文
        context = await self.memory_manager.load_context(input.session_id)
        system_prompt = self._build_system_prompt(context)
        messages = self._build_messages(input, context, system_prompt)

        # 获取路由
        routing = await self.model_router.route(input)
        provider = routing.provider

        # 收集训练数据：记录本次请求开始
        sample_id = self.collector.start_sample(input, system_prompt)

        # ReAct 循环
        for turn in range(self.MAX_TURNS):
            # LLM 推理
            response = await provider.chat(
                messages=messages,
                tools=TOOL_SCHEMAS,
                image=routing.image if turn == 0 else None
            )

            # 格式验证 + 重试
            validated = await self.validator.validate_and_fix(
                response=response,
                provider=provider,
                messages=messages,
                max_retries=self.MAX_VALIDATOR_RETRIES
            )

            # 质量差且有云端可用 → Fallback
            if not validated.ok and routing.allow_cloud_fallback:
                cloud_provider = self.model_router.get_cloud_provider()
                if cloud_provider:
                    response = await cloud_provider.chat(
                        messages=messages,
                        tools=TOOL_SCHEMAS,
                        image=routing.image if turn == 0 else None
                    )
                    validated = await self.validator.validate_and_fix(
                        response=response,
                        provider=cloud_provider,
                        messages=messages,
                        max_retries=1
                    )

            # 没有 Tool Call → 直接回复
            if not validated.tool_call:
                self.collector.finish_sample(sample_id, messages, "direct_reply")
                return AgentResponse(reply=validated.text)

            tool_name = validated.tool_call.name
            tool_params = validated.tool_call.params

            # 自主模式下检查 Tool 权限
            if is_autonomous and tool_name not in AUTONOMOUS_ALLOWED_TOOLS:
                return AgentResponse(
                    reply=f"建议执行：{tool_name}，等待用户确认",
                    suggested_action={"type": tool_name, "params": tool_params},
                    requires_confirmation=True
                )

            # ask_clarification → 暂停，等用户填表单
            if tool_name == "ask_clarification":
                return AgentResponse(
                    needs_form=True,
                    missing_fields=tool_params.get("fields", []),
                    prefilled=tool_params.get("prefilled", {}),
                    question=tool_params.get("question", "")
                )

            # 执行 Tool（Swift 原生或 Python 本地）
            tool_result = await self.tool_router.execute(
                tool_name=tool_name,
                params=tool_params,
                session_id=input.session_id
            )

            # 将结果反馈给 LLM
            messages.append(Message(
                role="tool",
                content=json.dumps(tool_result, ensure_ascii=False),
                tool_call_id=validated.tool_call.call_id
            ))

            # 记录到对话历史
            if input.session_id in self.sessions:
                self.sessions[input.session_id].extend([
                    Message(role="assistant", content=validated.raw_text),
                    Message(role="tool", content=json.dumps(tool_result))
                ])

        self.collector.finish_sample(sample_id, messages, "max_turns_reached")
        return AgentResponse(reply="操作已完成")

    def _build_system_prompt(self, context: AgentContext) -> str:
        return SYSTEM_PROMPT_TEMPLATE.format(
            memory=context.memory or "暂无",
            learnings=context.learnings or "暂无",
            soul=context.soul or "暂无",
            today_events=context.today_events or "今日无日程",
            current_time=datetime.now().strftime("%Y年%m月%d日 %H:%M %A"),
            tool_descriptions=format_tool_descriptions(TOOL_SCHEMAS)
        )

    def _build_messages(
        self,
        input: AgentInput,
        context: AgentContext,
        system_prompt: str
    ) -> list[Message]:
        messages = [Message(role="system", content=system_prompt)]

        # 加入历史对话
        if input.session_id in self.sessions:
            messages.extend(self.sessions[input.session_id])

        # 构建当前用户消息
        user_content = input.message
        if input.form_data:
            user_content += f"\n\n用户补充的表单数据：{json.dumps(input.form_data, ensure_ascii=False)}"
        if input.location_selected:
            user_content += f"\n\n用户选择的地点：{json.dumps(input.location_selected, ensure_ascii=False)}"

        messages.append(Message(role="user", content=user_content))
        return messages
```

### 9.3 OutputValidator

```python
# agent/output_validator.py

VALID_TOOLS = [
    "create_calendar_event", "create_reminder", "create_recurring_reminder",
    "get_today_events", "check_calendar_conflict", "get_overdue_reminders",
    "mark_reminder_done", "snooze_reminder", "search_location",
    "split_task", "get_weather", "save_memory", "read_memory",
    "ask_clarification", "send_notification"
]

REQUIRED_PARAMS = {
    "create_calendar_event": ["title", "start_time"],
    "create_reminder": ["title"],
    "create_recurring_reminder": ["title", "cron_expression"],
    "search_location": ["keyword"],
    "ask_clarification": ["question", "fields"],
    "save_memory": ["natural_language", "type"],
    "send_notification": ["title", "body"],
    # 其他 Tool 的必填参数...
}

UNCERTAINTY_PHRASES = [
    "我不确定", "我无法", "抱歉我不能", "超出我的能力",
    "I cannot", "I'm not sure", "I don't know"
]

class OutputValidator:

    async def validate_and_fix(
        self,
        response: LLMResponse,
        provider: LLMProvider,
        messages: list[Message],
        max_retries: int = 2
    ) -> ValidationResult:

        for attempt in range(max_retries + 1):
            result = self._validate(response)
            if result.ok:
                return result

            if attempt < max_retries:
                # 将错误反馈给模型重试
                error_feedback = Message(
                    role="user",
                    content=f"上次输出格式有误（{result.error}），请重新输出正确的 JSON 格式。"
                )
                retry_messages = messages + [error_feedback]
                response = await provider.chat(
                    messages=retry_messages,
                    tools=[],  # 重试时不传 tools，避免混淆
                    image=None
                )
            else:
                # 记录为训练负样本
                result.failed = True
                return result

        return ValidationResult(ok=False, error="重试次数耗尽")

    def _validate(self, response: LLMResponse) -> ValidationResult:
        text = response.text.strip()

        # 检查是否表达不确定
        if any(p in text for p in UNCERTAINTY_PHRASES):
            return ValidationResult(
                ok=False,
                error="模型表达了不确定性",
                is_poor_quality=True
            )

        # 尝试解析 JSON
        try:
            # 提取 JSON 块（可能有前缀文字）
            json_match = re.search(r'\{.*\}', text, re.DOTALL)
            if not json_match:
                return ValidationResult(ok=True, text=text)  # 纯文本回复

            parsed = json.loads(json_match.group())

            if "tool" not in parsed:
                return ValidationResult(ok=True, text=text)  # 纯文本

            tool_name = parsed["tool"]
            params = parsed.get("params", {})

            # 验证 Tool 名称
            if tool_name not in VALID_TOOLS:
                return ValidationResult(
                    ok=False,
                    error=f"未知 Tool：{tool_name}，有效 Tool 为：{VALID_TOOLS}"
                )

            # 验证必填参数
            required = REQUIRED_PARAMS.get(tool_name, [])
            missing = [k for k in required if k not in params]
            if missing:
                return ValidationResult(
                    ok=False,
                    error=f"Tool {tool_name} 缺少必填参数：{missing}"
                )

            return ValidationResult(
                ok=True,
                tool_call=ToolCall(
                    name=tool_name,
                    params=params,
                    call_id=str(uuid4())
                ),
                raw_text=text
            )

        except json.JSONDecodeError as e:
            return ValidationResult(ok=False, error=f"JSON 解析失败：{e}")
```

### 9.4 Heartbeat Loop

```python
# agent/heartbeat.py
from croniter import croniter
import asyncio
from datetime import datetime

AUTONOMOUS_ALLOWED_TOOLS = [
    "get_today_events",
    "read_memory",
    "send_notification",
    "get_weather",
    "get_overdue_reminders"
]

class HeartbeatLoop:

    def __init__(self, agent: JarvisAgent, memory_manager: MemoryManager,
                 swift_callback, wal: WAL):
        self.agent = agent
        self.memory = memory_manager
        self.swift = swift_callback
        self.wal = wal
        self.interval = 60  # 秒

    async def start(self):
        while True:
            try:
                await self.tick()
            except Exception as e:
                logging.error(f"Heartbeat tick error: {e}")
            await asyncio.sleep(self.interval)

    async def tick(self):
        now = datetime.now()
        await self._check_upcoming_events(now)
        await self._check_weather_alert(now)
        await self._check_overdue_todos(now)
        await self._check_event_preparation(now)
        await self._check_recurring_rules(now)
        await self._check_habit_tracking(now)
        await self._check_weekly_consolidation(now)

    async def _check_upcoming_events(self, now: datetime):
        """检查 30 分钟内是否有日历事件"""
        events = await self.swift.get_today_events()
        for event in events:
            minutes_until = (event.start - now).total_seconds() / 60
            if 29 < minutes_until < 31:  # 30分钟 ±1 分钟容差
                await self._trigger(
                    trigger_type="event_reminder",
                    instruction=f"""
                    用户在 30 分钟后有事件：{event.title}
                    开始时间：{event.start.strftime('%H:%M')}
                    地点：{event.location or '无'}
                    请生成简洁的提醒，包含事件信息和建议。
                    """,
                    action_id=f"event_{event.id}_{now.date()}"
                )

    async def _check_weather_alert(self, now: datetime):
        """每天 07:30 检查天气，必要时推送提醒"""
        if now.hour == 7 and 29 < now.minute < 31:
            await self._trigger(
                trigger_type="weather_alert",
                instruction="""
                请先调用 get_weather 获取今日天气，
                再调用 get_today_events 查看是否有外出安排，
                综合判断是否需要提醒用户带伞或加衣，
                如需提醒则调用 send_notification。
                """,
                action_id=f"weather_{now.date()}"
            )

    # 注意：带伞提醒事项（Reminder）的创建时机：
    # F1 识别日程时，如果地点为户外 AND 当日/次日降雨概率 > 50%
    # Python 侧在写入日程的同时，额外调用 create_reminder：
    # {
    #   "title": "带伞！{event.title}",
    #   "due_date": event_date,
    #   "due_time": "08:00",     # 当天早上8点提醒
    #   "notes": f"当日降雨概率 {rain_probability}%，{event.title} 在户外"
    # }
    # 并在日程的 notes 中追加："☂️ 注意：当天可能有雨，建议带伞"

    async def _check_overdue_todos(self, now: datetime):
        """每天 18:00 检查到期未完成任务"""
        if now.hour == 18 and 0 <= now.minute < 1:
            await self._trigger(
                trigger_type="todo_followup",
                instruction="""
                请调用 get_overdue_reminders 获取今日到期未完成的提醒，
                如果有未完成任务，逐一询问用户是否完成。
                """,
                action_id=f"todos_{now.date()}"
            )

    async def _check_event_preparation(self, now: datetime):
        """每天 21:00 提醒明日重要事项准备"""
        if now.hour == 21 and 0 <= now.minute < 1:
            await self._trigger(
                trigger_type="preparation_reminder",
                instruction="""
                请调用 get_today_events 查看明日日程（传入明天日期），
                如果有重要事件，生成准备建议并通知用户。
                """,
                action_id=f"prep_{now.date()}"
            )

    async def _check_recurring_rules(self, now: datetime):
        """检查用户自定义的周期性规则"""
        rules = await self.memory.get_active_recurring_rules()
        for rule in rules:
            cron = croniter(rule.cron_expression, now)
            last_trigger = cron.get_prev(datetime)
            seconds_ago = (now - last_trigger).total_seconds()
            if seconds_ago < self.interval:
                await self._trigger(
                    trigger_type="recurring_rule",
                    instruction=rule.instruction,
                    action_id=f"rule_{rule.id}_{now.strftime('%Y%m%d%H%M')}"
                )

    async def _check_weekly_consolidation(self, now: datetime):
        """每周日 22:00 整理 learnings"""
        if now.weekday() == 6 and now.hour == 22 and 0 <= now.minute < 1:
            await self.agent.self_improving.weekly_consolidation()

    async def _trigger(self, trigger_type: str, instruction: str, action_id: str):
        """执行主动触发，写 WAL，运行 ReAct（只读模式），通知 Swift"""
        # 幂等检查：同一 action_id 当天只触发一次
        if await self.wal.is_triggered_today(action_id):
            return

        await self.wal.before_action(action_id, trigger_type, instruction)

        input = AgentInput(
            message=instruction,
            session_id=f"heartbeat_{action_id}",
            is_autonomous=True
        )

        response = await self.agent.run(input, is_autonomous=True)

        # 通知 Swift 展开灵动岛
        await self.swift.expand_island({
            "type": trigger_type,
            "action_id": action_id,
            "title": self._get_title(trigger_type),
            "body": response.reply,
            "suggested_actions": response.suggested_action,
            "requires_confirmation": response.requires_confirmation
        })

        await self.wal.after_action(action_id, "pushed")
```

---

## 10. Tool 规格

### 10.1 Tool JSON Schema 定义

```python
# tools/definitions.py

TOOL_SCHEMAS = [
    {
        "name": "create_calendar_event",
        "description": """创建日历事件（Calendar）。适用于有持续时长的日程事件。
        使用场景：开会、面试、见面、吃饭、培训、上课、活动等占用时间段的事件。
        注意1：如果有地点信息，必须先调用 search_location 获取坐标，再调用本工具。
        注意2：调用前先用 check_conflict 检查是否有时间冲突。
        注意3：end_time 无法推断时，不要自行填写，返回 needs_duration=true 让用户选择时长。
        注意4：recurrence 仅在用户明确说"以后每周X"等重复信号时填写，否则为 null。
        不要用于：无持续时长的截止型任务（用 create_reminder）。""",
        "parameters": {
            "type": "object",
            "properties": {
                "title": {"type": "string", "description": "事件标题"},
                "start_time": {"type": "string", "description": "开始时间，ISO8601 格式，如 2026-04-18T14:00:00"},
                "end_time": {"type": "string", "description": "结束时间，ISO8601 格式。无法推断时设为 null，同时 needs_duration=true"},
                "needs_duration": {"type": "boolean", "description": "end_time 无法推断时设为 true，触发 Swift 展示时长选择面板"},
                "is_all_day": {"type": "boolean", "description": "是否全天事件，默认 false"},
                "location_keyword": {"type": "string", "description": "地点关键词，识别到则触发 search_location，识别不到则不填"},
                "latitude": {"type": "number", "description": "纬度，来自 search_location 结果，用户选择地点后填入"},
                "longitude": {"type": "number", "description": "经度，来自 search_location 结果，用户选择地点后填入"},
                "recurrence": {
                    "type": "string",
                    "description": "重复规则。默认 null（不重复）。仅在用户明确描述重复时填写。取值：DAILY/WEEKLY/WEEKLY:MO/WEEKLY:TU/WEEKLY:WE/WEEKLY:TH/WEEKLY:FR/WEEKLY:SA/WEEKLY:SU/MONTHLY/YEARLY"
                },
                "alert_minutes": {"type": "integer", "description": "提前提醒分钟数，默认 30。用户可通过提醒反馈调整"},
                "travel_time_minutes": {"type": "integer", "description": "行程时间（分钟），识别到则填入，识别不到则不填"},
                "attendees": {"type": "array", "items": {"type": "string"}, "description": "参与人列表，识别到则写入，识别不到则不填"},
                "notes": {"type": "string", "description": "备注。写入截图中识别到的额外信息（议题、链接等）。地点为户外且当日降雨概率>50%时追加带伞提醒。无额外信息则不填"}
            },
            "required": ["title", "start_time"]
        }
    },
    {
        "name": "create_reminder",
        "description": """创建提醒事项（Reminder）。适用于截止型任务，无持续时长。
        使用场景：交PPT、还书、缴费、提交文件、打电话等有截止时间的任务，以及任务拆分的子任务。
        注意：priority 默认 none，包含"紧急/重要/必须"信号时设为 high，包含"ddl/截止/deadline"信号时设为 medium。
        注意：若为拆分子任务，notes 中写明主任务标题，parent_task_title 填写主任务标题。
        注意：子任务的 due_date 必须早于主任务的 due_date。
        不要用于：有持续时长的日程事件（用 create_calendar_event）。
        不要用于：周期性任务（用 create_recurring_reminder）。""",
        "parameters": {
            "type": "object",
            "properties": {
                "title": {"type": "string", "description": "提醒标题"},
                "due_date": {"type": "string", "description": "到期日期，ISO8601 date 格式 YYYY-MM-DD（可选）"},
                "due_time": {"type": "string", "description": "到期时间，HH:MM 格式（可选，有值时自动勾选指定时间）"},
                "priority": {
                    "type": "string",
                    "enum": ["none", "low", "medium", "high"],
                    "description": "优先级。默认 none。动态规则：含紧急/重要/必须→high，含ddl/截止/deadline→medium"
                },
                "recurrence": {
                    "type": "string",
                    "description": "重复规则，默认 null（不重复）。仅用户明确描述重复时填写，取值同日程字段"
                },
                "notes": {"type": "string", "description": "备注。写入额外上下文信息。若为子任务则写：主任务：{主任务标题}。无额外信息则不填"},
                "flag": {"type": "boolean", "description": "是否标记旗帜，默认 false"},
                "list": {"type": "string", "description": "所属列表，默认'提醒事项'"},
                "parent_task_title": {"type": "string", "description": "若为拆分子任务，填写主任务标题；否则不填"}
            },
            "required": ["title"]
        }
    },
    {
        "name": "create_recurring_reminder",
        "description": """创建周期性提醒。
        使用场景：用户说"每天/每周/每小时/以后每周X..."等明确周期性的任务。
        示例：每天喝水、每周发周报、每小时站起来活动、每周三下班前发工作文档。
        注意：due_time 如果用户说"下班前"等模糊表达，使用用户设置的下班时间，未设置则默认 18:00。""",
        "parameters": {
            "type": "object",
            "properties": {
                "title": {"type": "string", "description": "提醒标题"},
                "cron_expression": {"type": "string", "description": "标准 cron 表达式，如 '0 21 * * *' 表示每天21点，'0 18 * * 3' 表示每周三18点"},
                "due_time": {"type": "string", "description": "触发时间 HH:MM（可选，与 cron 二选一）"},
                "instruction": {"type": "string", "description": "触发时给 Jarvis 的执行指令"},
                "notes": {"type": "string", "description": "备注（可选）"},
                "priority": {
                    "type": "string",
                    "enum": ["none", "low", "medium", "high"],
                    "description": "优先级，默认 none"
                }
            },
            "required": ["title", "cron_expression"]
        }
    },
    {
        "name": "get_today_events",
        "description": """获取指定日期的日历事件和提醒列表。
        使用场景：用户询问今天/明天的安排，或主动检查日程。
        默认返回今天的事件，可传入日期参数获取其他日期。""",
        "parameters": {
            "type": "object",
            "properties": {
                "date": {"type": "string", "description": "日期，ISO8601 格式（可选，默认今天）"}
            }
        }
    },
    {
        "name": "check_calendar_conflict",
        "description": """检查指定时间段是否与已有日历事件冲突。
        使用场景：在创建日历事件之前调用，防止时间重叠。
        必须在 create_calendar_event 之前调用。""",
        "parameters": {
            "type": "object",
            "properties": {
                "start_time": {"type": "string", "description": "开始时间，ISO8601 格式"},
                "end_time": {"type": "string", "description": "结束时间，ISO8601 格式"}
            },
            "required": ["start_time", "end_time"]
        }
    },
    {
        "name": "get_overdue_reminders",
        "description": "获取今日到期但尚未完成的提醒事项列表。用于跟进待办任务。",
        "parameters": {"type": "object", "properties": {}}
    },
    {
        "name": "mark_reminder_done",
        "description": "将指定提醒标记为已完成。",
        "parameters": {
            "type": "object",
            "properties": {
                "reminder_id": {"type": "string", "description": "提醒的唯一标识符"}
            },
            "required": ["reminder_id"]
        }
    },
    {
        "name": "snooze_reminder",
        "description": "推迟提醒到指定时间后再次提醒。",
        "parameters": {
            "type": "object",
            "properties": {
                "reminder_id": {"type": "string", "description": "提醒的唯一标识符"},
                "delay_minutes": {"type": "integer", "description": "推迟分钟数，如 15、30、60"}
            },
            "required": ["reminder_id", "delay_minutes"]
        }
    },
    {
        "name": "search_location",
        "description": """搜索地点，获取坐标信息。
        使用场景：识别到地点名称时，必须先调用此工具获取坐标，再写入日历。
        返回候选地点列表，Swift 会展示给用户选择。
        不要跳过此步骤直接填写地点名称。""",
        "parameters": {
            "type": "object",
            "properties": {
                "keyword": {"type": "string", "description": "地点名称或地址关键词"}
            },
            "required": ["keyword"]
        }
    },
    {
        "name": "split_task",
        "description": """将复杂任务拆分为主任务 + 多个子任务，全部写入 Reminder。
        使用场景：用户描述了一个包含多个步骤或阶段的复杂任务。
        核心规则：
        1. 主任务本身也写入 Reminder（is_main_task=true）
        2. 子任务 due_date 必须早于主任务 due_date，按执行顺序递增排列
        3. 子任务 notes 中必须写明主任务标题：'主任务：{主任务标题}'
        4. 主任务 notes 中列出所有子任务标题
        5. 写入顺序：先写所有子任务，再写主任务
        执行方：Python ToolRouter 批量调用 create_reminder Tool（Swift 侧）""",
        "parameters": {
            "type": "object",
            "properties": {
                "main_task": {
                    "type": "object",
                    "description": "主任务",
                    "properties": {
                        "title": {"type": "string"},
                        "due_date": {"type": "string", "description": "主任务截止日期 YYYY-MM-DD"},
                        "due_time": {"type": "string", "description": "截止时间 HH:MM（可选）"},
                        "priority": {"type": "string", "enum": ["none", "low", "medium", "high"]},
                        "notes": {"type": "string", "description": "自动填入：列出所有子任务标题"}
                    },
                    "required": ["title"]
                },
                "subtasks": {
                    "type": "array",
                    "description": "子任务列表，due_date 必须早于主任务，按执行顺序排列",
                    "items": {
                        "type": "object",
                        "properties": {
                            "title": {"type": "string"},
                            "due_date": {"type": "string", "description": "子任务截止日期 YYYY-MM-DD，必须 <= 主任务 due_date"},
                            "due_time": {"type": "string", "description": "截止时间 HH:MM（可选）"},
                            "priority": {"type": "string", "enum": ["none", "low", "medium", "high"]},
                            "notes": {"type": "string", "description": "自动填入：主任务：{主任务标题}"}
                        },
                        "required": ["title"]
                    }
                }
            },
            "required": ["main_task", "subtasks"]
        }
    },
    {
        "name": "get_weather",
        "description": "获取今日天气信息，用于天气感知提醒。",
        "parameters": {
            "type": "object",
            "properties": {
                "location": {"type": "string", "description": "城市名称（可选，默认使用用户设置的位置）"}
            }
        }
    },
    {
        "name": "save_memory",
        "description": """保存用户的个性化规则或偏好到长期记忆。
        使用场景（满足任一即调用）：
        - 用户描述周期性习惯（每天/每周/每小时...）
        - 用户描述个人偏好（我一般/我习惯/我喜欢...）
        - 用户要求记住某个规则（以后/默认/总是/记住...）
        不要用于：普通的一次性日程创建请求。""",
        "parameters": {
            "type": "object",
            "properties": {
                "natural_language": {"type": "string", "description": "用户的原始描述"},
                "type": {
                    "type": "string",
                    "enum": ["recurring_reminder", "preference", "behavior_rule"],
                    "description": "规则类型"
                },
                "cron_expression": {"type": "string", "description": "如果是周期性提醒，提供 cron 表达式"},
                "instruction": {"type": "string", "description": "触发时给 Jarvis 的执行指令"}
            },
            "required": ["natural_language", "type"]
        }
    },
    {
        "name": "read_memory",
        "description": "从长期记忆中检索与当前任务相关的用户规则和偏好。",
        "parameters": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "检索关键词"}
            },
            "required": ["query"]
        }
    },
    {
        "name": "ask_clarification",
        "description": """向用户追问缺失的信息，展开表单让用户补充。
        使用场景：识别到必填信息（时间、标题等）缺失时调用。
        会暂停当前流程，等待用户通过表单补充信息后继续。
        不要过度追问，只问真正必要的字段。""",
        "parameters": {
            "type": "object",
            "properties": {
                "question": {"type": "string", "description": "向用户提问的内容"},
                "fields": {
                    "type": "array",
                    "items": {"type": "string", "enum": ["time", "title", "location", "duration"]},
                    "description": "缺失的字段列表"
                },
                "prefilled": {
                    "type": "object",
                    "description": "已识别的字段和值（用于预填表单）"
                }
            },
            "required": ["question", "fields"]
        }
    },
    {
        "name": "send_notification",
        "description": """发送系统通知。
        使用场景：主动提醒用户（仅在 is_autonomous 模式下自动调用）。
        在用户主动触发模式下，优先通过灵动岛界面展示，而非发通知。""",
        "parameters": {
            "type": "object",
            "properties": {
                "title": {"type": "string", "description": "通知标题"},
                "body": {"type": "string", "description": "通知正文"},
                "delay_seconds": {"type": "integer", "description": "延迟发送秒数（可选，默认 0）"}
            },
            "required": ["title", "body"]
        }
    },
    {
        "name": "create_note",
        "description": """在苹果备忘录（Notes）中新建一条笔记。

        判断原则（三件套互斥）：
        · 有明确时间段 → create_calendar_event
        · 有截止时间/任务性质 → create_reminder
        · 需要保存但无时间属性 → create_note

        使用场景：用户想保存没有时间维度的内容，例如：
        · 联系方式、网址、账号信息
        · 会议要点、想法、灵感
        · 截图中的菜谱、说明书、文字内容
        · 用户明确说"记一下"、"存一下"、"备忘"

        不要主动建议用户用备忘录。
        只在用户明确表达记录/保存意图，且内容无时间属性时调用。""",
        "parameters": {
            "type": "object",
            "properties": {
                "title": {"type": "string", "description": "备忘录标题，简洁概括内容"},
                "content": {"type": "string", "description": "备忘录正文，保留截图或用户描述中的完整信息"},
                "folder": {"type": "string", "description": "存入的文件夹名称，默认'备忘录'。如用户提到特定分类（如'工作'、'学习'）则填写对应文件夹名"}
            },
            "required": ["title", "content"]
        }
    },
    {
        "name": "append_to_note",
        "description": """向苹果备忘录中已有的笔记追加内容。

        使用场景：用户有一个持续更新的笔记，想追加新内容，例如：
        · "加到我的购物清单里"
        · "追加到会议记录"
        · "加到今天的日记里"

        注意：如果找不到指定标题的备忘录，改为调用 create_note 新建。""",
        "parameters": {
            "type": "object",
            "properties": {
                "title": {"type": "string", "description": "要追加内容的备忘录标题"},
                "content": {"type": "string", "description": "要追加的内容，自动在末尾换行追加"}
            },
            "required": ["title", "content"]
        }
    }
]

# 自主触发模式允许调用的 Tool
AUTONOMOUS_ALLOWED_TOOLS = [
    "get_today_events",
    "read_memory",
    "send_notification",
    "get_weather",
    "get_overdue_reminders"
]
```

### 10.2 ToolRouter

```python
# agent/tool_router.py

class ToolRouter:

    def __init__(self, swift_client):
        self.swift = swift_client

    async def execute(
        self,
        tool_name: str,
        params: dict,
        session_id: str
    ) -> dict:
        """路由 Tool 调用到对应执行方"""

        # Python 侧直接执行的 Tool
        if tool_name == "split_task":
            return await self._split_task(params)

        if tool_name == "get_weather":
            return await self._get_weather(params)

        # 需要 Swift 执行的 Tool（调用 Swift NativeActionExecutor）
        swift_tools = [
            "create_calendar_event", "create_reminder", "create_recurring_reminder",
            "get_today_events", "check_calendar_conflict", "get_overdue_reminders",
            "mark_reminder_done", "snooze_reminder", "search_location",
            "save_memory", "read_memory", "ask_clarification", "send_notification",
            "create_note", "append_to_note"
        ]

        if tool_name in swift_tools:
            result = await self.swift.execute_action({
                "type": tool_name,
                "params": params,
                "session_id": session_id
            })
            return result

        raise ValueError(f"未知 Tool：{tool_name}")

    async def _get_weather(self, params: dict) -> dict:
        """调用 wttr.in 免费天气 API（无需 API Key）"""
        import httpx
        location = params.get("location", "auto")
        async with httpx.AsyncClient() as client:
            resp = await client.get(
                f"https://wttr.in/{location}?format=j1",
                timeout=10
            )
            data = resp.json()
            current = data["current_condition"][0]
            return {
                "temperature": current["temp_C"],
                "feels_like": current["FeelsLikeC"],
                "weather": current["weatherDesc"][0]["value"],
                "rain_probability": current.get("precipMM", "0"),
                "humidity": current["humidity"]
            }

    async def _split_task(self, params: dict) -> dict:
        """
        任务拆分执行逻辑：
        1. 先批量写入所有子任务（子任务 due_date 早于主任务）
        2. 更新主任务 notes，列出所有子任务标题
        3. 最后写入主任务
        """
        main_task = params.get("main_task", {})
        subtasks = params.get("subtasks", [])

        # 自动补充子任务的 notes（写明主任务）
        for subtask in subtasks:
            if not subtask.get("notes"):
                subtask["notes"] = f"主任务：{main_task['title']}"
            elif "主任务" not in subtask.get("notes", ""):
                subtask["notes"] = f"主任务：{main_task['title']}\n{subtask['notes']}"

        # 先写所有子任务
        subtask_titles = []
        created_subtasks = []
        for subtask in subtasks:
            result = await self.swift.execute_action({
                "type": "create_reminder",
                "params": {
                    "title": subtask["title"],
                    "due_date": subtask.get("due_date"),
                    "due_time": subtask.get("due_time"),
                    "priority": subtask.get("priority", "medium"),
                    "notes": subtask.get("notes"),
                    "parent_task_title": main_task["title"]
                }
            })
            subtask_titles.append(subtask["title"])
            created_subtasks.append(result)

        # 主任务 notes 列出所有子任务
        main_notes = f"子任务：{' | '.join(subtask_titles)}"
        if main_task.get("notes"):
            main_notes = f"{main_task['notes']}\n{main_notes}"

        # 最后写主任务
        main_result = await self.swift.execute_action({
            "type": "create_reminder",
            "params": {
                "title": main_task["title"],
                "due_date": main_task.get("due_date"),
                "due_time": main_task.get("due_time"),
                "priority": main_task.get("priority", "medium"),
                "notes": main_notes,
                "flag": main_task.get("flag", False)
            }
        })

        return {
            "created_main": 1,
            "created_subtasks": len(created_subtasks),
            "main_task": main_task["title"],
            "subtasks": subtask_titles
        }
```

---

## 11. Memory 与 Self-Improving 规格

### 11.1 用户记忆文件体系

Jarvis 借鉴 OpenClaw 的工作区文件体系，每个文件职责单一，不混合。所有文件存储在 `~/.jarvis/` 目录下，分三种注入方式：固定注入、Tool 检索、系统内部读取。

---

#### 11.1.1 文件职责（单一，不混合）

```
~/.jarvis/
├── soul.md        职责：Jarvis 自身人设（固定部分）+ 用户选择的语气风格
│                  对应：OpenClaw SOUL.md
│                  单一原则：只放 Jarvis 是谁、怎么说话，不放用户信息
│
├── user.md        职责：用户信息 + 用户规则 + AI 每周提炼的用户偏好摘要
│                  对应：OpenClaw USER.md
│                  单一原则：只放用户相关内容，不放 Jarvis 人设
│
├── tools.md       职责：工具使用规则和约束
│                  对应：OpenClaw TOOLS.md
│                  单一原则：只放工具相关规则，不放其他内容
│
├── heartbeat.md   职责：心跳检查清单（用户可自定义周期任务）
│                  对应：OpenClaw HEARTBEAT.md
│                  单一原则：只放 Heartbeat Loop 需要执行的检查项
│
├── learnings.md   职责：从交互中观察到的纠正/拒绝原始记录
│                  对应：OpenClaw 无直接对应
│                  单一原则：只存原始观察数据，不做决策
│
├── errors.md      职责：识别错误日志
│                  对应：OpenClaw 无直接对应
│                  单一原则：只存错误记录，防止重复犯错
│
├── bootstrap.md   职责：首次启动引导脚本（一次性）
│                  对应：OpenClaw BOOTSTRAP.md
│                  单一原则：内容固定，不允许用户修改内容，但可重置运行状态
│
└── wal.jsonl      职责：主动触发写前日志，防止状态丢失
```

---

#### 11.1.2 注入方式（分级加载）

```
第一级：每次固定注入（精简，合计约 350 tokens）
  soul.md          全量注入
  user.md          全量注入（目标控制在 200 tokens 以内）
  tools.md         全量注入（目标控制在 150 tokens 以内）

第二级：Tool 按需检索（不主动注入，模型判断需要时调用）
  learnings.md     → 模型调用 read_memory Tool 检索
                     适用：模型需要参考历史经验时
                     不适用：每次都全量注入（内容会随时间增长）

第三级：系统内部读取（不经过模型）
  heartbeat.md     → Heartbeat Loop 直接读取，不注入对话上下文
  errors.md        → OutputValidator 失败时参考，不注入对话
  wal.jsonl        → WAL 模块直接读写，不注入对话
  bootstrap.md     → 仅 Onboarding 一次性读取，完成后废弃
```

---

#### 11.1.3 各文件内容规范

**soul.md（目标 150 tokens）**

```markdown
# soul.md

## Jarvis 核心边界（不可修改）
- 所有写入操作必须用户确认后才执行
- 自主触发时只读取数据，禁止写入
- 信息不足时主动追问，不猜测用户意图

## 语气风格（用户可通过对话或设置页修改）
语气：简洁直接
回复长度：一句话确认结果
称呼用户：[用户名]
特殊风格：无
```

**user.md（目标 200 tokens）**

```markdown
# user.md

## 基本信息
称呼：小明 | 城市：北京 | 时区：UTC+8
工作时间：09:00-18:00，周一到周五

## 日历与提醒偏好
工作日历：Work | 个人日历：Personal
会议默认时长：90分钟 | 提醒提前：15分钟

## 周期性规则
- 每天 21:00 取快递提醒
- 每小时喝水提醒

## 用户偏好（AI 每周提炼，2-3条）
最后更新：2026-04-20
- 偏好简洁提醒，不喜欢啰嗦
- 下午开会居多，上午倾向独立工作
```

**tools.md（目标 150 tokens）**

```markdown
# tools.md

## 工具优先级
- 识别到地点 → 必须先调用 search_location，再写日历
- 写日历前 → 必须先调用 check_conflict
- 有时间 → create_calendar_event
- 有截止无持续 → create_reminder
- 需保存无时间 → create_note

## 自主模式限制
只允许：get_today_events / read_memory / get_weather
        get_overdue_reminders / send_notification

## 截图处理
当前策略：本地 OCR → 当前模型（隐私优先）
```

**heartbeat.md（目标 100 tokens）**

```markdown
# heartbeat.md

## 每次 tick（60秒）
- 检查30分钟内事件 → 提醒
- 检查用户周期性规则

## 固定时间
- 07:30 天气 + 外出计划
- 18:00 到期未完成任务跟进
- 21:00 明日重要事项提醒

## 每周
- 周日 22:00 整理 learnings，更新 user.md 偏好摘要
```

---

#### 11.1.4 各文件写入时机

| 文件 | 写入时机 | 触发方 | 更新方式 |
|------|---------|--------|---------|
| soul.md 核心边界 | 发布时一次 | 开发者 | 不自动更新 |
| soul.md 语气风格 | 用户设置/对话修改 | save_style Tool / 设置页 | 覆盖对应行 |
| user.md 基本信息 | Onboarding 首次 | bootstrap 引导 | 覆盖写入 |
| user.md 周期性规则 | 用户说出规则时 | save_memory Tool | 追加 |
| user.md 偏好摘要 | 每周日 22:00 | weekly_consolidation | 覆盖摘要部分 |
| tools.md 固定规则 | 发布时 | 开发者 | 不自动更新 |
| tools.md 截图策略 | 用户修改设置 | 设置页保存 | 更新对应行 |
| heartbeat.md | Onboarding + 规则变更 | 系统 + 用户 | 追加/修改 |
| learnings.md | 用户每次纠正/拒绝 | SelfImproving | 立即追加 |
| errors.md | 验证失败/Fallback | OutputValidator | 立即追加 |
| wal.jsonl | 每次主动触发前后 | WAL 模块 | 追加+更新 |
| bootstrap.md | 发布时 | 开发者 | 不修改内容 |

---

#### 11.1.5 soul.md 和 user.md 的修改权限

| 内容 | 用户可读 | 用户可改 | 修改方式 |
|------|---------|---------|---------|
| soul.md 核心边界 | ❌ | ❌ | 不开放 |
| soul.md 语气风格 | ✅ | ✅ | 对话直接说 / 设置页选择 |
| user.md 基本信息 | ✅ | ✅ | 对话直接说 / 设置页修改 |
| user.md 周期性规则 | ✅ | ✅ | 对话直接说（save_memory） |
| user.md 偏好摘要 | ✅ | ❌ | AI 自动生成，不允许手改 |
| bootstrap.md 内容 | ❌ | ❌ | 不开放 |
| bootstrap 运行状态 | ✅ | ✅ | 设置页可重置重新引导 |

**对话中修改语气风格示例**：

```
用户："你能不能说话温和一点"
Jarvis → 调用 save_style Tool → 更新 soul.md 语气行
Jarvis 下一条回复立即用新风格

用户："叫我 Alex 就好"
Jarvis → 调用 save_style Tool → 更新 user.md 称呼行
```

**边界保护**：

```
用户："以后不用问我确认，直接写入就行"
Jarvis："为了数据安全，写入操作需要你确认，这个无法关闭。
        不过我可以让确认步骤更简洁，减少操作摩擦。"
→ 核心边界不变，但可以优化确认体验
```

---

#### 11.1.2 各文件的写入和更新时机

**memory.md — 用户规则与永久偏好**

| 写入时机 | 触发方 | 操作 |
|---------|--------|------|
| 用户主动说规则（"每天9点提醒取快递"） | LLM 调用 `save_memory` Tool → Python MemoryManager | 追加一条规则 |
| 同一字段被用户纠正 ≥3 次 | Python SelfImproving.record_correction() | 追加一条固化偏好 |
| 每周日 22:00 整理 | Python SelfImproving.weekly_consolidation() | 追加 AI 提炼出的永久规则 |
| **更新频率** | **低，可能几天一次** | |

**learnings.md — 近期纠正和拒绝记录**

| 写入时机 | 触发方 | 操作 |
|---------|--------|------|
| 用户修改了 ConfirmationCard 字段 | Python SelfImproving.record_correction() | 立即追加一条记录 |
| 用户拒绝了 Jarvis 的操作 | Python SelfImproving.record_rejection() | 立即追加一条记录 |
| **清理时机** | 每周日 22:00 weekly_consolidation | 保留最近 7 天，删除更早记录 |
| **更新频率** | **高，每次交互都可能写入** | |

**errors.md — 识别错误日志**

| 写入时机 | 触发方 | 操作 |
|---------|--------|------|
| Tool Call JSON 格式验证失败 | Python OutputValidator | 立即追加 |
| 模型输出了不确定性表达（"我不确定"） | Python OutputValidator | 立即追加 |
| 端侧推理失败，Cloud Fallback 触发 | Python ModelRouter | 立即追加（记录失败原因） |
| **清理时机** | 每周日 22:00 整理 | 保留最近 30 天 |
| **更新频率** | **中，取决于模型质量** | |

**soul.md — 用户行为画像**

| 写入时机 | 触发方 | 操作 |
|---------|--------|------|
| 每周日 22:00 | Python SelfImproving.weekly_consolidation() | **全量覆盖**（不是追加） |
| AI 分析 learnings.md + errors.md | ReAct Core（自主模式） | 输出完整的用户画像文本 |
| **更新频率** | **每周一次** | |

**wal.jsonl — 写前日志**

| 写入时机 | 触发方 | 操作 |
|---------|--------|------|
| Heartbeat Loop 每次主动触发前 | Python WAL.before_action() | 追加一条 pending 记录 |
| 主动触发执行完成后 | Python WAL.after_action() | 更新该条记录状态为 completed |
| App 启动时 | Python WAL.get_pending_actions() | 检查有无上次崩溃遗留的 pending 任务 |
| **清理时机** | 保留最近 7 天 | |
| **更新频率** | **高，每次主动触发写一条** | |

---

### 11.2 MemoryManager

```python
# agent/memory_manager.py
from pathlib import Path
from dataclasses import dataclass

JARVIS_DIR = Path.home() / ".jarvis"

@dataclass
class AgentContext:
    memory: str          # memory.md 内容
    learnings: str       # learnings.md 内容（近期，截断到最近 50 条）
    soul: str            # soul.md 内容
    today_events: str    # 今日日程（格式化文字）
    recurring_rules: list  # 激活的周期性规则

class MemoryManager:

    def __init__(self, swift_client):
        self.swift = swift_client
        JARVIS_DIR.mkdir(exist_ok=True)
        for f in ["memory.md", "learnings.md", "errors.md", "soul.md"]:
            (JARVIS_DIR / f).touch(exist_ok=True)

    async def load_context(self, session_id: str) -> AgentContext:
        memory = self._read_file("memory.md")
        learnings = self._read_recent_learnings(max_entries=50)
        soul = self._read_file("soul.md")

        # 今日日程由 Swift 提供
        events = await self.swift.get_today_events()
        today_events = self._format_events(events)

        # 激活的周期性规则
        rules = await self.swift.get_active_memories()

        return AgentContext(
            memory=memory,
            learnings=learnings,
            soul=soul,
            today_events=today_events,
            recurring_rules=rules
        )

    async def get_active_recurring_rules(self) -> list:
        return await self.swift.get_active_memories(type="recurring_reminder")

    def _read_file(self, filename: str) -> str:
        path = JARVIS_DIR / filename
        return path.read_text(encoding="utf-8") if path.exists() else ""

    def _read_recent_learnings(self, max_entries: int = 50) -> str:
        """读取最近 N 条 learnings"""
        content = self._read_file("learnings.md")
        entries = content.split("\n## ")[1:]  # 按时间戳分割
        recent = entries[-max_entries:] if len(entries) > max_entries else entries
        return "\n## ".join(recent) if recent else ""
```

### 11.2 SelfImproving

```python
# agent/self_improving.py

class SelfImproving:

    def __init__(self, memory_manager: MemoryManager, agent: JarvisAgent):
        self.memory = memory_manager
        self.agent = agent
        self.correction_counts: dict = {}  # field → {value → count}

    async def record_correction(self, original: dict, corrected: dict):
        """用户修改了识别结果时记录"""
        for field, new_value in corrected.items():
            if original.get(field) != new_value:
                entry = f"""
## {datetime.now().strftime('%Y-%m-%d %H:%M')}
- 类型：correction
- 字段：{field}
- 原始：{original.get(field, '空')}
- 修正：{new_value}
"""
                await self._append_to("learnings.md", entry)

                # 统计纠正次数
                key = f"{field}:{new_value}"
                self.correction_counts[key] = self.correction_counts.get(key, 0) + 1

                # 超过 3 次，提升为永久规则
                if self.correction_counts[key] >= 3:
                    await self._promote_to_memory(field, new_value)

    async def record_rejection(self, action: dict):
        """用户拒绝了操作时记录"""
        entry = f"""
## {datetime.now().strftime('%Y-%m-%d %H:%M')}
- 类型：rejection
- 操作：{action.get('type', '未知')}
- 参数：{json.dumps(action.get('params', {}), ensure_ascii=False)}
"""
        await self._append_to("learnings.md", entry)

    async def record_error(self, error_type: str, detail: str):
        """记录识别错误"""
        entry = f"""
## {datetime.now().strftime('%Y-%m-%d %H:%M')}
- 错误类型：{error_type}
- 详情：{detail}
"""
        await self._append_to("errors.md", entry)

    async def weekly_consolidation(self):
        """每周日 22:00 整理 learnings，更新 soul.md"""
        learnings = self.memory._read_file("learnings.md")
        errors = self.memory._read_file("errors.md")

        if not learnings and not errors:
            return

        instruction = f"""以下是 Jarvis 过去一周从用户交互中记录的学习数据：

【用户纠正记录】
{learnings[-3000:] if len(learnings) > 3000 else learnings}

【识别错误记录】
{errors[-2000:] if len(errors) > 2000 else errors}

请分析以上数据，输出以下格式（严格遵守）：

永久规则：
- [规则1]
- [规则2]

注意事项：
- [注意1]
- [注意2]

用户画像：
[一段话描述用户的行为特征和偏好]
"""
        input = AgentInput(message=instruction, session_id="weekly_consolidation")
        result = await self.agent.run(input, is_autonomous=True)

        # 更新 soul.md
        soul_content = f"""# 用户画像（更新于 {datetime.now().strftime('%Y-%m-%d')}）

{result.reply}
"""
        (JARVIS_DIR / "soul.md").write_text(soul_content, encoding="utf-8")

        # 清理已整理的 learnings（保留最近 7 天）
        await self._prune_old_learnings(days=7)

    async def _promote_to_memory(self, field: str, value: str):
        """将高频纠正提升为永久规则"""
        rule = f"- 用户偏好：{field} 默认使用 '{value}'\n"
        await self._append_to("memory.md", rule)

    async def _append_to(self, filename: str, content: str):
        path = JARVIS_DIR / filename
        with open(path, "a", encoding="utf-8") as f:
            f.write(content)

    async def _prune_old_learnings(self, days: int = 7):
        """保留最近 N 天的 learnings"""
        from datetime import timedelta
        cutoff = datetime.now() - timedelta(days=days)
        content = self.memory._read_file("learnings.md")
        # 按时间戳过滤，保留 cutoff 之后的条目
        # 实现省略，基本逻辑：解析 ## YYYY-MM-DD 时间戳，过滤旧条目
```

### 11.3 WAL（写前日志）

```python
# agent/wal.py
import json
from pathlib import Path
from datetime import datetime, date

WAL_PATH = Path.home() / ".jarvis" / "wal.jsonl"

class WAL:

    async def before_action(self, action_id: str, trigger_type: str, instruction: str):
        entry = {
            "action_id": action_id,
            "trigger_type": trigger_type,
            "instruction": instruction[:200],  # 截断，防止文件过大
            "status": "pending",
            "timestamp": datetime.now().isoformat()
        }
        await self._append(entry)

    async def after_action(self, action_id: str, status: str):
        # 更新已有条目的状态
        lines = WAL_PATH.read_text().splitlines() if WAL_PATH.exists() else []
        updated = []
        for line in lines:
            try:
                entry = json.loads(line)
                if entry["action_id"] == action_id:
                    entry["status"] = status
                    entry["completed_at"] = datetime.now().isoformat()
                updated.append(json.dumps(entry, ensure_ascii=False))
            except json.JSONDecodeError:
                updated.append(line)
        WAL_PATH.write_text("\n".join(updated))

    async def is_triggered_today(self, action_id: str) -> bool:
        """幂等检查：今天是否已触发过此 action"""
        if not WAL_PATH.exists():
            return False
        today = date.today().isoformat()
        for line in WAL_PATH.read_text().splitlines():
            try:
                entry = json.loads(line)
                if (entry["action_id"] == action_id and
                        entry["timestamp"].startswith(today)):
                    return True
            except json.JSONDecodeError:
                continue
        return False

    async def get_pending_actions(self) -> list:
        """启动时检查未完成的 pending 任务（用于崩溃恢复）"""
        if not WAL_PATH.exists():
            return []
        pending = []
        for line in WAL_PATH.read_text().splitlines():
            try:
                entry = json.loads(line)
                if entry["status"] == "pending":
                    pending.append(entry)
            except json.JSONDecodeError:
                continue
        return pending

    async def _append(self, entry: dict):
        WAL_PATH.parent.mkdir(exist_ok=True)
        with open(WAL_PATH, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
```

### 11.4 TrainingDataCollector

```python
# agent/training_collector.py

TRAINING_DIR = Path.home() / ".jarvis" / "training"

class TrainingDataCollector:

    def start_sample(self, input: AgentInput, system_prompt: str) -> str:
        """开始记录一个训练样本，返回 sample_id"""
        sample_id = str(uuid4())
        self._pending[sample_id] = {
            "id": sample_id,
            "timestamp": datetime.now().isoformat(),
            "input_message": input.message[:500],
            "has_image": input.has_image,
            "session_id": input.session_id,
            "system_prompt_hash": hashlib.md5(system_prompt.encode()).hexdigest()
        }
        return sample_id

    def finish_sample(
        self,
        sample_id: str,
        messages: list[Message],
        outcome: str,          # "accepted" / "rejected" / "modified" / "direct_reply" / "max_turns_reached"
        corrections: dict = None
    ):
        if sample_id not in self._pending:
            return

        sample = self._pending.pop(sample_id)
        sample.update({
            "messages": [{"role": m.role, "content": m.content} for m in messages],
            "outcome": outcome,
            "corrections": corrections,
            "tool_calls": self._extract_tool_calls(messages)
        })

        # 按日期分目录存储
        today_dir = TRAINING_DIR / datetime.now().strftime("%Y-%m-%d")
        today_dir.mkdir(parents=True, exist_ok=True)
        samples_file = today_dir / "samples.jsonl"

        with open(samples_file, "a", encoding="utf-8") as f:
            f.write(json.dumps(sample, ensure_ascii=False) + "\n")

    def _extract_tool_calls(self, messages: list[Message]) -> list:
        tool_calls = []
        for m in messages:
            if m.role == "assistant":
                try:
                    parsed = json.loads(m.content)
                    if "tool" in parsed:
                        tool_calls.append({
                            "tool": parsed["tool"],
                            "params": parsed.get("params", {})
                        })
                except json.JSONDecodeError:
                    pass
        return tool_calls
```

---

## 12. 通信协议规格

### 12.1 Swift → Python 请求格式

```typescript
// POST /chat
interface ChatRequest {
    message: string;           // 用户文字输入（可为空字符串）
    image?: string;            // Base64 编码的 JPEG 图片（可选）
    session_id: string;        // 会话 UUID，每次打开对话生成

    // F2 表单补充数据（可选）
    form_data?: {
        time?: string;         // ISO8601
        title?: string;
        location?: string;
        duration?: number;     // 分钟
    };

    // F3 用户选择的地点（可选）
    location_selected?: {
        name: string;
        address: string;
        latitude: number;
        longitude: number;
    };

    // F9 用户操作反馈（可选）
    user_action?: "accepted" | "modified" | "rejected";
    original_result?: object;  // 用户修改前的识别结果
    corrections?: object;      // 用户修改后的值
}
```

### 12.2 Python → Swift 响应格式

```typescript
// ChatResponse
interface ChatResponse {
    reply: string;             // 给用户的文字回复

    // 需要 Swift 执行的原生操作列表
    actions?: NativeAction[];

    // F2 信息补充表单
    needs_form?: boolean;
    missing_fields?: ("time" | "title" | "location" | "duration")[];
    prefilled?: object;        // 已识别的字段值
    question?: string;         // 追问内容

    // F3 地点选择
    needs_location_pick?: boolean;
    location_keyword?: string; // 传给 MapKit 搜索

    // F6 主动提醒
    expand_island?: boolean;
    island_content?: IslandContent;
    requires_confirmation?: boolean;
    action_id?: string;        // 用于确认请求

    // 路由信息（调试用）
    routing_mode?: string;
}

interface NativeAction {
    type: string;              // Tool 名称
    params: object;            // Tool 参数
    action_id?: string;        // 用于追踪
}

interface IslandContent {
    type: string;              // trigger_type
    title: string;
    body: string;
    primary_button?: string;   // 主操作按钮文字
    snooze_options?: number[]; // 稍后提醒分钟数 [15, 30, 60]
}
```

### 12.3 Swift → Python 原生操作结果回传

```typescript
// POST /action_result
interface ActionResultRequest {
    action_id: string;
    action_type: string;
    success: boolean;
    result?: object;           // 成功时的结果数据
    error?: string;            // 失败时的错误信息
}
```

### 12.4 HTTP 通信规范

- **协议**：HTTP/1.1
- **地址**：`http://localhost:8765`
- **超时**：请求超时 30 秒
- **重试**：5xx 错误重试 1 次
- **图片压缩**：截图在 Swift 侧压缩为 JPEG，最大边 1024px，quality=0.85，再 Base64 编码
- **字符集**：UTF-8

---

## 13. 数据模型

### 13.1 CoreData 模型（Swift）

```
// Memory Entity
Memory {
    id: UUID (primaryKey)
    naturalLanguage: String    // 用户原话
    type: String               // recurring_reminder / preference / behavior_rule
    cronExpression: String?    // cron 表达式（周期性规则）
    instruction: String?       // 触发时的指令
    active: Bool               // 是否激活
    createdAt: Date
    updatedAt: Date
}
```

### 13.2 UserDefaults 存储

```swift
// 推理模式
"inference_mode": String       // "smart" / "force_local" / "force_cloud"

// 视觉 fallback 策略
"vision_fallback": String      // "ocr_then_local" / "auto_switch_vision" / "cloud"

// 当前激活的端侧模型
"active_model": String         // "qwen3-0.6b" / "qwen3-1.7b" / "gemma4-e2b" / "gemma4-e4b"

// 云端 API 提供商
"cloud_provider": String       // "anthropic" / "openai" / "custom"

// 云端模型名称
"cloud_model": String          // "claude-sonnet-4-5" 等
```

### 13.3 Keychain 存储

```swift
// 云端 API Key（安全存储）
Key: "jarvis.api_key.anthropic"    Value: String
Key: "jarvis.api_key.openai"       Value: String
Key: "jarvis.api_key.custom"       Value: String
Key: "jarvis.api_base_url.custom"  Value: String
```

### 13.4 AgentInput 数据类

```python
@dataclass
class AgentInput:
    message: str
    session_id: str
    image: Optional[str] = None          # Base64 JPEG
    form_data: Optional[dict] = None
    location_selected: Optional[dict] = None
    user_action: Optional[str] = None    # "accepted" / "modified" / "rejected"
    original_result: Optional[dict] = None
    corrections: Optional[dict] = None
    turn_count: int = 0                  # 当前会话对话轮数
    is_autonomous: bool = False

    @property
    def has_image(self) -> bool:
        return self.image is not None and len(self.image) > 0
```

---

## 14. 文件结构

```
Jarvis/                              # 项目根目录
├── Swift/                           # Xcode 项目
│   ├── Jarvis.xcodeproj/
│   ├── App/
│   │   ├── JarvisApp.swift
│   │   └── GatewayManager.swift
│   ├── UI/
│   │   ├── StatusBarController.swift  # 灵动岛胶囊 + 右键菜单 + 快捷按钮
│   │   ├── ConversationView.swift     # 对话界面 + 底部工具栏（模式切换）
│   │   ├── ConfirmationCard.swift     # 写入确认卡片
│   │   ├── FormView.swift             # 信息补充表单（F2）
│   │   ├── DurationPickerView.swift   # 时长选择面板（F1 无结束时间）
│   │   ├── LocationPicker.swift       # 地点候选列表（F3）
│   │   ├── IslandExpandView.swift     # 主动提醒面板（F6）
│   │   ├── SettingsView.swift         # 设置页（含 API 配置表单）
│   │   ├── OnboardingView.swift       # 首次启动引导
│   │   └── Animations/
│   │       ├── JarvisAnimation.swift  # 全局动效参数定义
│   │       └── PressableStyle.swift   # 按压反馈 ButtonStyle
│   ├── Gateway/
│   │   └── GatewayClient.swift
│   ├── NativeActions/
│   │   ├── NativeActionExecutor.swift
│   │   ├── EventKitTool.swift
│   │   ├── MapKitTool.swift
│   │   ├── CoreDataTool.swift
│   │   ├── NotificationTool.swift
│   │   └── NotesTool.swift          # AppleScript → 苹果备忘录
│   ├── Models/
│   │   ├── ModelManager.swift
│   │   ├── ModelRegistry.swift
│   │   └── Jarvis.xcdatamodeld
│   └── Info.plist
│
├── Python/                          # Gateway + Agent
│   ├── gateway.py
│   ├── agent/
│   │   ├── __init__.py
│   │   ├── jarvis_agent.py
│   │   ├── heartbeat.py
│   │   ├── memory_manager.py
│   │   ├── model_router.py
│   │   ├── tool_router.py
│   │   ├── output_validator.py
│   │   ├── wal.py
│   │   ├── self_improving.py
│   │   └── training_collector.py
│   ├── providers/
│   │   ├── __init__.py
│   │   ├── base.py                 # LLMProvider 抽象基类
│   │   ├── provider_factory.py     # 根据 provider_id 创建对应 Provider
│   │   ├── provider_configs.py     # 14 个 Provider 的配置字典
│   │   ├── gemma_mlx.py            # Gemma 4 E2B/E4B 端侧
│   │   ├── qwen3_mlx.py            # Qwen3 0.6B/1.7B 端侧
│   │   ├── claude.py               # Anthropic API（独立实现）
│   │   ├── bedrock.py              # Amazon Bedrock（boto3 SDK）
│   │   └── openai_compat.py        # OpenAI 兼容 API 统一处理（12 个 Provider）
│   ├── tools/
│   │   ├── __init__.py
│   │   ├── definitions.py
│   │   ├── split_task.py
│   │   └── weather_provider.py
│   └── requirements.txt
│
└── README.md

# App Bundle 内模型目录（打包后）
Jarvis.app/Contents/Resources/
└── models/                          # 端侧模型文件（下载后存放于此）
    ├── qwen3-0.6b/
    ├── qwen3-1.7b/
    ├── gemma4-e2b/
    └── gemma4-e4b/

# 运行时数据目录（用户 Home 下）
~/.jarvis/
├── soul.md          # Jarvis 人设（固定）+ 用户语气风格偏好
├── user.md          # 用户信息、规则、AI 偏好摘要
├── tools.md         # 工具使用规则
├── heartbeat.md     # 心跳检查清单
├── learnings.md     # 近期纠正记录（自动积累，Tool 检索）
├── errors.md        # 错误记录（自动积累，系统内部读取）
├── bootstrap.md     # 首次启动引导（一次性）
├── wal.jsonl        # 写前日志
└── training/
    └── YYYY-MM-DD/
        └── samples.jsonl
```

---

## 15. 依赖清单

### 15.1 Swift（Swift Package Manager）

```swift
// Package.swift dependencies
dependencies: [
    .package(
        url: "https://github.com/nicklockwood/KeyboardShortcuts",
        from: "2.0.0"
    )
]
// 其余全部使用苹果原生框架：
// AppKit, SwiftUI, EventKit, MapKit, ScreenCaptureKit,
// UserNotifications, CoreData, Security, Vision, CoreLocation
```

### 15.2 Python（requirements.txt）

```
# 推理
mlx-lm>=0.22.0

# Web 框架
fastapi>=0.115.0
uvicorn>=0.30.0

# HTTP 客户端（用于通用 API 调用 + 天气 API）
httpx>=0.27.0

# 云端 API SDK
anthropic>=0.34.0     # Anthropic Claude（独立实现）
openai>=1.45.0        # OpenAI + 12 个 OpenAI 兼容 Provider
boto3>=1.35.0         # Amazon Bedrock（用 AWS SDK）

# 工具
croniter>=2.0.0     # Cron 表达式解析
pillow>=10.0.0      # 图片处理
python-multipart>=0.0.9

# 类型提示
pydantic>=2.8.0
```

---

## 16. 权限声明

在 `Info.plist` 中声明以下权限（必须提供用途描述，否则 macOS 拒绝授权）：

```xml
<key>NSCalendarsUsageDescription</key>
<string>Jarvis 需要访问日历，以便将识别的日程自动写入 Calendar。</string>

<key>NSCalendarsWriteOnlyAccessUsageDescription</key>
<string>Jarvis 需要向日历写入事件。</string>

<key>NSRemindersUsageDescription</key>
<string>Jarvis 需要访问提醒事项，以便创建和管理您的待办任务。</string>

<key>NSContactsUsageDescription</key>
<string>Jarvis 需要访问联系人，以便识别日程中的参与人信息。</string>

<key>NSScreenCaptureUsageDescription</key>
<string>Jarvis 需要截图权限，以便识别屏幕上的日程信息。</string>

<key>NSUserNotificationsUsageDescription</key>
<string>Jarvis 需要发送通知，以便在重要时刻主动提醒您。</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>Jarvis 需要位置信息，以便在天气提醒中使用当前城市。</string>

<key>NSAppleEventsUsageDescription</key>
<string>Jarvis 需要使用 AppleScript 将内容写入苹果备忘录。</string>
```

---

## 17. 开发顺序建议

按照以下顺序开发，每个阶段验证通过后再进入下一阶段：

### 阶段 1：基础链路验证（MVP 核心）

目标：跑通"截图 → 识别 → 确认 → 写入日历"完整链路

```
1. Python Gateway 骨架（FastAPI + /health + /chat 端点）
2. GemmaMLXProvider 或 Qwen3MLXProvider（选一个先实现）
3. 最简单的 ReAct Core（不含 Heartbeat、Memory、Self-Improving）
4. Tool 定义（definitions.py）
5. ToolRouter（只实现 create_calendar_event 和 search_location）
6. Swift GatewayManager（启动 Python 进程，健康检查）
7. Swift GatewayClient（/chat 请求）
8. Swift CaptureManager（快捷键 + 截图）
9. Swift NativeActionExecutor + EventKitTool（create_calendar_event）
10. Swift MapKitTool（search_location）
11. Swift ConfirmationCard（展示结果，用户确认）
12. Swift StatusBarController（最简版，能展开/收起即可）

验收标准：用户按 ⌘+Shift+J 截图，灵动岛展示识别结果，用户点确认，
          Calendar 中出现对应事件。
```

### 阶段 2：完善 MVP 功能

```
13. F2 FormView（信息补充表单）
14. F3 LocationPicker（地点候选列表）
15. F4 多日程批量写入
16. OutputValidator（格式验证 + 重试）
17. ModelRouter（基础版：有无本地模型 + OCR 降级）
18. MemoryManager（基础版：读取 memory.md 注入 Prompt）

验收标准：F1~F4 全部可用，模型路由基本生效。
```

### 阶段 3：效率功能

```
19. F5 ConversationView（自由对话）
20. Heartbeat Loop（基础版：DDL 提醒 + 周期性规则）
21. F6 IslandExpandView（主动提醒面板）
22. F8 save_memory Tool + Memory 写入
23. WAL 写前日志

验收标准：用户说"每天9点提醒取快递"，次日 9 点灵动岛主动弹出。
```

### 阶段 4：完整智能路由 + Self-Improving

```
24. 完整 ModelRouter（难度预判 + 质量检测 Fallback）
25. 云端 API 支持（ClaudeProvider + OpenAIProvider）
26. ModelManager（下载/切换/卸载 + SettingsView）
27. SelfImproving 模块
28. TrainingDataCollector
29. F9 周度整理（Heartbeat + weekly_consolidation）
30. F7 split_task Tool

验收标准：所有 F1~F9 功能可用，智能路由正常切换，用户纠正会被记录。
```

### 阶段 5：打包与分发

```
31. 将 Python 虚拟环境打包进 App Bundle
32. Homebrew Formula 编写
33. 首次启动 Onboarding 界面（模型选择 + 下载）
34. 错误处理与用户友好提示完善
35. 性能优化（模型温启动缓存）
```

---

## 附录 A：模型训练路线（当前不实现，仅作规划）

> **重要**：本章节描述的训练流程在 MVP 和 V1.0 阶段**不需要实现**。TrainingDataCollector 在产品上线后持续收集数据，待积累足够样本后再执行训练。本章节的目的是让 System Prompt 格式、Tool Call 格式从第一天起与训练数据格式保持一致，避免未来训练时需要重新适配。

---

### A.1 TrainingDataCollector 工作原理

收集器在每次用户交互时自动记录一个完整训练样本：

```python
# 一个完整的训练样本
{
    "id": "sample_001",
    "timestamp": "2026-04-18T14:30:00",

    # 输入侧
    "system_prompt_hash": "md5_of_system_prompt",
    "user_message": "明天下午3点开会",
    "has_image": False,

    # 模型输出侧
    "tool_calls": [
        {"tool": "create_calendar_event", "params": {"title": "开会", "start_time": "...", "needs_duration": true}}
    ],

    # 用户反馈（最关键的标签）
    "outcome": "modified",
    "corrections": {"title": "部门周会"},

    # 元数据
    "model": "qwen3-1.7b",
    "routing_mode": "local_text",
    "turn_count": 1
}
```

**收集时机与标签**：

| 用户行为 | outcome 标签 | 训练用途 |
|---------|-------------|---------|
| 点击确认写入 | `"accepted"` | SFT chosen 样本 / DPO chosen |
| 修改字段后写入 | `"modified"` | SFT（用修改后的版本）/ DPO chosen+rejected 对 |
| 点击取消/拒绝 | `"rejected"` | DPO rejected 样本 |
| 模型输出格式错误 | `"format_error"` | GRPO 负样本 |
| 直接文字回复 | `"direct_reply"` | SFT 对话样本 |

**存储位置**：`~/.jarvis/training/YYYY-MM-DD/samples.jsonl`

---

### A.2 阶段 1：冷启动数据生成（SFT 前）

> **前置条件**：产品 MVP 已跑通，System Prompt 和 Tool Schema 已确定不再大改

用 GPT-4o 或 Claude 作为 Teacher 模型批量生成训练数据：

```python
# scripts/generate_training_data.py
# 用强模型批量生成 Jarvis 场景的训练数据

SCENARIOS = [
    # F1 日程识别
    {"input": "明天下午3点开会", "expected_tool": "create_calendar_event"},
    {"input": "周五前交论文",    "expected_tool": "create_reminder"},
    {"input": "以后每周三开例会", "expected_tool": "create_calendar_event",
     "expected_params": {"recurrence": "WEEKLY:WE"}},
    # F8 记忆
    {"input": "我一般开会都是90分钟", "expected_tool": "save_memory"},
    {"input": "记住我的工作日历叫 Work", "expected_tool": "save_memory"},
    # 不该调用 Tool 的场景
    {"input": "今天天气怎么样？", "expected_tool": None},
    {"input": "你好", "expected_tool": None},
    # ... 覆盖 F1-F9 所有场景
]

for scenario in SCENARIOS:
    # 让 Teacher 生成 20 个措辞变体
    variants = teacher.generate_variants(scenario, count=20)
    for v in variants:
        sample = teacher.generate_tool_call(v, system_prompt=JARVIS_SYSTEM_PROMPT, tools=TOOL_SCHEMAS)
        save_to_jsonl(sample)

# 目标：5000-10000 条高质量训练数据
# 成本：GPT-4o ~$15-30，Claude ~$20-40
```

---

### A.3 阶段 2：SFT 监督微调

> **前置条件**：阶段 1 数据已生成，或 TrainingDataCollector 已积累 200+ 条真实数据

```python
# scripts/sft_train.py
from unsloth import FastLanguageModel

# 加载基础模型
model, tokenizer = FastLanguageModel.from_pretrained(
    model_name="Qwen/Qwen3-1.7B",
    max_seq_length=4096,
    load_in_4bit=True
)

# LoRA 微调（只调 Adapter 权重，不改基础权重）
model = FastLanguageModel.get_peft_model(
    model,
    r=16,
    lora_alpha=16,
    target_modules=["q_proj", "k_proj", "v_proj", "o_proj"],
)

# 训练数据格式与运行时 System Prompt 完全一致
# 输入 = System Prompt + User Message
# 输出 = Tool Call JSON
training_data = load_jsonl("training_data/sft_data.jsonl")

trainer = SFTTrainer(
    model=model,
    train_dataset=training_data,
    max_seq_length=4096,
    num_train_epochs=3,
    per_device_train_batch_size=4,
    learning_rate=2e-5,
)
trainer.train()

# 导出为 MLX 格式
# mlx_lm.convert --hf-path ./sft_output --mlx-path ./jarvis-qwen3-1.7b-sft

# 硬件需求：M4 16GB 本机可跑
# 训练时间：约 2-4 小时
# 预期效果：Tool Call 准确率 ~80% → ~92%
```

---

### A.4 阶段 3：GRPO 强化学习

> **前置条件**：SFT 模型已可用，需要进一步提升格式准确率

```python
# scripts/grpo_train.py
# 用可程序验证的奖励函数（不需要人工标注）

def reward_function(output: str) -> float:
    score = 0.0

    # JSON 格式正确
    try:
        parsed = json.loads(output)
        score += 1.0
    except json.JSONDecodeError:
        return -2.0  # 格式错误重罚

    # Tool 名称合法
    if parsed.get("tool") in VALID_TOOLS:
        score += 1.0
    else:
        score -= 1.0

    # 必填参数完整
    tool = parsed.get("tool")
    params = parsed.get("params", {})
    required = REQUIRED_PARAMS.get(tool, [])
    if all(k in params for k in required):
        score += 1.0
    else:
        score -= 0.5

    # 时间格式正确（ISO8601）
    if "start_time" in params:
        try:
            datetime.fromisoformat(params["start_time"])
            score += 0.5
        except ValueError:
            score -= 0.5

    return score

# 所有奖励信号可程序验证，零人工标注成本
# 预期效果：准确率 ~92% → ~95%+
```

---

### A.5 阶段 4：DPO 偏好对齐（上线后）

> **前置条件**：TrainingDataCollector 已积累 500+ 条 accepted/modified/rejected 真实数据

```python
# scripts/dpo_train.py
# 使用 TrainingDataCollector 自动收集的真实用户数据

# DPO 训练数据格式
# 来自 outcome="modified" 的样本：
dpo_sample = {
    "prompt": "System Prompt + 明天下午3点开会",
    "chosen":   '{"tool": "create_calendar_event", "params": {"title": "部门周会", ...}}',
    "rejected": '{"tool": "create_calendar_event", "params": {"title": "开会", ...}}'
}
# 用户把"开会"改成了"部门周会" → 模型学会更具体地命名

from trl import DPOTrainer
dpo_trainer = DPOTrainer(
    model=model,
    ref_model=ref_model,
    train_dataset=dpo_data,
    beta=0.1,
)
dpo_trainer.train()

# 这一步让模型越来越符合这个特定用户的习惯
# 随着使用时间增长，效果持续提升
```

---

### A.6 蒸馏（Distillation）

蒸馏是阶段 1 + 阶段 2 的组合，本质上就是用 Teacher 生成数据再对 Student 做 SFT：

```
Teacher 模型（GPT-4o / Claude Sonnet）
    ↓ 生成 5000-10000 条训练数据
Student 模型（Qwen3 1.7B）
    ↓ SFT 微调
Jarvis 专用模型
    ↓ 部署到 App Bundle models/ 目录
端侧运行
```

蒸馏的优势是训练数据质量高（Teacher 模型能力强），Student 模型虽然参数少但在 Jarvis 特定场景下表现可以接近 Teacher。

---

### A.7 训练时间线

```
开发期间（现在）：
  ✅ TrainingDataCollector 代码准备好
  ✅ System Prompt + Tool Schema 格式固定
  ❌ 不做任何训练
  → 用 Prompt 规则 + 通用模型跑 MVP

MVP 上线后 1-2 周：
  积累 200+ 条真实用户交互
  执行阶段 1：生成冷启动数据（$30）
  执行阶段 2：SFT 微调 Qwen3 1.7B（4小时本机）
  → 替换通用模型，System Prompt 规则开始精简

上线后 1-2 个月：
  积累 1000+ 条用户数据
  执行阶段 3：GRPO 强化学习
  → Tool Call 准确率推到 95%+

上线后 3 个月+：
  积累 500+ 条 chosen/rejected 对
  执行阶段 4：DPO 偏好对齐
  → 模型越来越懂这个用户
```

---

## 附录 B：常见问题

**Q：Python 进程崩溃怎么办？**  
A：GatewayManager 的 `terminationHandler` 检测到进程退出后自动重启，Swift 侧显示"重新连接中"状态。

**Q：端侧模型加载很慢？**  
A：实现温启动策略：首次触发后将模型保持在内存中，30 分钟无操作后释放。GatewayManager 启动时显示"正在加载模型"状态。

**Q：如何防止重复触发主动提醒？**  
A：WAL 的 `is_triggered_today` 方法做幂等检查，同一 `action_id` 当天只触发一次。

**Q：用户同时打开多个会话怎么办？**  
A：每个 ConversationView 有独立的 `session_id`，Python 侧为每个 session 维护独立的 messages 历史。

**Q：模型推理时灵动岛如何响应？**  
A：推理期间输入框右侧显示系统原生 ProgressView，不响应新的截图输入，但允许用户取消当前请求。

**Q：训练数据如何使用？**  
A：`~/.jarvis/training/` 目录下的 `samples.jsonl` 文件直接用于未来的 SFT 微调，格式已与 System Prompt 对齐，无需额外转换。详见附录 A。

---

*文档版本：v1.5 | 最后更新：2026-04*
