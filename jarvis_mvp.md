# Jarvis MVP 文档 — 阶段一

> **目标**：跑通最小可用产品，验证核心链路  
> **范围**：灵动岛 UI + macOS 顶部菜单栏 + 云端 API 配置 + 截图识别 → 写入 Calendar/Reminder（含地点）  
> **不包含**：端侧模型推理、Heartbeat 主动提醒、Memory 体系、Self-Improving

---

## 1. MVP 目标定义

### 用一句话描述

用户按 `⌘⇧J` 截图，截图自动传给 AI，AI 识别时间地点事件，写入 macOS Calendar 或 Reminder，用户在灵动岛确认即可。

### 四个核心验收点

```
✅ 灵动岛胶囊常驻菜单栏，有 Jarvis 图标
✅ macOS 顶部菜单栏「模型 → 配置云端 API」触发 API 配置表单
✅ API 配置表单支持 13 个 Provider + 自定义，验证后展示可用模型列表
✅ ⌘⇧J 截图 → Agent 分析 → 弹出确认卡片（含地点）→ 用户确认 → 写入 Calendar/Reminder
```

---

## 2. 功能范围

### 包含（必须实现）

| 功能 | 说明 |
|------|------|
| 灵动岛胶囊 | 常驻菜单栏，静默态显示 Jarvis 图标 |
| Hover 展开 | 鼠标移入展开：截图按钮 + 设置按钮 + 当前模型名 |
| macOS 顶部菜单栏 | Jarvis / 操作 / 模型 三个菜单，含「配置云端 API...」入口 |
| API 配置面板 | 两个入口（灵动岛设置按钮 / 顶部菜单栏）打开同一个窗口 |
| 13 个 Provider + 自定义 | 参考 OpenClaw 官方体系 |
| 验证连接 | 配置 API 后验证并展示可用模型列表 |
| ⌘⇧J 截图 | 全局快捷键触发截图 |
| Agent 识别 | LLM 分析截图，判断日程/提醒，提取字段（含地点文字） |
| MapKit 地点搜索 | 识别到地点关键词时，搜索并让用户选择，写入坐标 |
| ConfirmationCard | 展示识别结果，用户确认/丢弃 |
| LocationPicker | 地点候选列表，用户点选后写入坐标 |
| EventKit 写入 | 用户确认后写入 Calendar（含坐标）或 Reminder |
| 写入成功反馈 | 胶囊短暂显示 ✓ |

### 不包含（MVP 后再做）

| 功能 | 原因 |
|------|------|
| 端侧模型推理 | 需要 MLX 配置，放 V1.0 |
| 模型下载/管理 | 依赖端侧推理，放 V1.0 |
| Heartbeat 主动提醒 | 独立功能，放 V1.0 |
| F2 信息补充表单 | MVP 先展示不完整信息，放 V1.0 |
| Memory/Soul 文件体系 | 无状态先跑通，放 V1.0 |
| Task List 面板 | 放 V1.0 |
| Onboarding 引导 | 放 V1.0 |

---

## 3. 架构（MVP 简化版）

```
Swift 进程
  ├── 灵动岛胶囊（NSStatusItem + Hover 展开）
  ├── macOS 顶部菜单栏（JarvisCommands）
  ├── API 配置面板（APISettingsPanel）    ← 菜单栏 & 灵动岛共用同一个窗口
  ├── CaptureManager（⌘⇧J 截图）
  ├── ConfirmationCard（确认写入）
  ├── LocationPicker（MapKit 地点候选）
  ├── GatewayManager（启动 Python）
  └── EventKitTool（写入日历/提醒，含坐标）

          ↕ HTTP localhost:8765

Python 进程
  ├── FastAPI Gateway（/chat, /health, /settings）
  ├── JarvisAgent（简化 ReAct，最多重试 2 次）
  └── CloudProvider（Anthropic SDK / OpenAI 兼容）
```

---

## 3.1 macOS 顶部菜单栏（MVP 精简版）

MVP 阶段只实现最必要的菜单项：

```
Jarvis
  关于 Jarvis
  ───────────
  退出 Jarvis    ⌘Q

操作
  截图识别       ⌘⇧J
  新建对话       ⌘N

模型
  配置云端 API...     ← 触发 APISettingsPanel 窗口
```

**Swift 实现**：

```swift
// JarvisCommands.swift
struct JarvisCommands: Commands {
    var body: some Commands {
        // 操作菜单
        CommandMenu("操作") {
            Button("截图识别") {
                CaptureManager.shared.capture()
            }
            .keyboardShortcut("j", modifiers: [.command, .shift])

            Button("新建对话") {
                // MVP 暂时只触发截图，对话功能 V1.0 实现
                CaptureManager.shared.capture()
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        // 模型菜单
        CommandMenu("模型") {
            Button("配置云端 API...") {
                APISettingsWindowManager.shared.open()
            }
        }
    }
}

// APISettingsWindowManager.swift
// 统一管理 APISettingsPanel 窗口，保证只开一个
class APISettingsWindowManager {
    static let shared = APISettingsWindowManager()
    private var window: NSWindow?

    func open() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.title = "配置云端 API"
        w.contentView = NSHostingView(rootView: APISettingsPanel())
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}
```

灵动岛设置按钮同样调用 `APISettingsWindowManager.shared.open()`，保证两个入口打开同一个窗口，不会出现两个配置窗口同时存在的情况。

---

## 3.2 MapKit 地点搜索流程

```
Agent 识别到 location_keyword（如"国贸三期"）
    ↓
Swift 收到响应，发现 needs_location_pick: true
    ↓
调用 MKLocalSearch 搜索"国贸三期"
    ↓
弹出 LocationPicker（最多 5 个候选）
    ↓
用户点选一个地点
    ↓
ConfirmationCard 更新地点显示，记录坐标
    ↓
用户点击「写入」
    ↓
EventKitTool 写入 location 文字 + EKStructuredLocation 坐标
```

**MapKitTool.swift**：

```swift
import MapKit

class MapKitTool {
    static func search(keyword: String) async -> [LocationResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = keyword
        request.resultTypes = .pointOfInterest

        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            return response.mapItems.prefix(5).map { item in
                LocationResult(
                    name: item.name ?? keyword,
                    address: item.placemark.formattedAddress,
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude,
                    distance: item.placemark.location?.distance(from: CLLocation(
                        latitude: CLLocationManager().location?.coordinate.latitude ?? 39.9,
                        longitude: CLLocationManager().location?.coordinate.longitude ?? 116.4
                    ))
                )
            }
        } catch {
            return []
        }
    }
}

struct LocationResult: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let distance: CLLocationDistance?

    var distanceText: String {
        guard let d = distance else { return "" }
        return d < 1000 ? String(format: "%.0f m", d) : String(format: "%.1f km", d / 1000)
    }
}

extension MKPlacemark {
    var formattedAddress: String {
        [subLocality, locality, administrativeArea]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}
```

---

## 4. API 配置存储与 Swift → Python 通信

### 4.1 存储分层

API 配置涉及敏感数据和非敏感数据，分两个地方存：

```
敏感数据（API Key）
  → macOS Keychain
  → 只有 Swift 直接读写
  → Python 不直接访问 Keychain
  → Key 命名规则："jarvis.api_key.{provider_id}"
    例："jarvis.api_key.anthropic"
        "jarvis.api_key.openai"

非敏感数据（Provider ID、Model ID、Base URL）
  → ~/.jarvis/api_config.json
  → Swift 读写，Python 启动时由 Swift 主动推送（不直接读文件）
```

### 4.2 api_config.json 结构

```json
{
  "active_provider_id": "anthropic",
  "active_model_id": "claude-sonnet-4-5",
  "providers": {
    "anthropic": {
      "model_id": "claude-sonnet-4-5",
      "configured": true
    },
    "openai": {
      "model_id": "gpt-4o",
      "configured": true
    },
    "ollama": {
      "model_id": "qwen3:1.7b",
      "base_url": "http://localhost:11434",
      "configured": true
    },
    "custom": {
      "model_id": "my-model",
      "base_url": "https://my-endpoint.com/v1",
      "configured": true
    }
  }
}
```

API Key 不进这个文件，Keychain 单独存。

### 4.3 Swift APIConfigStore

```swift
// Store/APIConfigStore.swift
import Foundation
import Combine

class APIConfigStore: ObservableObject {
    static let shared = APIConfigStore()

    // 当前激活的 Provider
    @Published var activeProviderId: String?
    @Published var activeModelId: String?

    // 所有已配置的 Provider
    @Published var configurations: [String: ProviderConfig] = [:]

    // 灵动岛显示用
    var activeDisplayName: String? {
        guard let pid = activeProviderId,
              let mid = activeModelId else { return nil }
        let providerName = PROVIDER_DISPLAY_NAMES[pid] ?? pid
        return "\(providerName) / \(mid)"
    }

    private let configURL: URL = {
        let jarvisDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".jarvis")
        try? FileManager.default.createDirectory(at: jarvisDir,
            withIntermediateDirectories: true)
        return jarvisDir.appendingPathComponent("api_config.json")
    }()

    // MARK: - 读写 api_config.json

    func load() {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(APIConfig.self, from: data) else {
            return
        }
        activeProviderId = config.activeProviderId
        activeModelId    = config.activeModelId
        configurations   = config.providers
    }

    func save() {
        let config = APIConfig(
            activeProviderId: activeProviderId,
            activeModelId:    activeModelId,
            providers:        configurations
        )
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: configURL)
        }
    }

    // MARK: - Keychain 操作

    func saveAPIKey(_ key: String, for providerId: String) {
        KeychainHelper.save(key, for: "jarvis.api_key.\(providerId)")
    }

    func loadAPIKey(for providerId: String) -> String? {
        KeychainHelper.load("jarvis.api_key.\(providerId)")
    }

    func deleteAPIKey(for providerId: String) {
        KeychainHelper.delete("jarvis.api_key.\(providerId)")
    }

    // MARK: - 激活 Provider（保存 + 通知 Python）

    func activate(providerId: String, modelId: String, baseUrl: String? = nil) async throws {
        // 1. 更新本地状态
        await MainActor.run {
            activeProviderId = providerId
            activeModelId    = modelId
            configurations[providerId]?.modelId = modelId
        }

        // 2. 持久化到 api_config.json
        save()

        // 3. 通知 Python 切换 Provider（从 Keychain 取 API Key 一并发送）
        let apiKey = loadAPIKey(for: providerId) ?? ""
        let req = SettingsRequest(
            providerId: providerId,
            modelId:    modelId,
            apiKey:     apiKey,
            baseUrl:    baseUrl
        )
        try await GatewayClient.shared.updateSettings(req)
    }
}

// 数据模型
struct APIConfig: Codable {
    var activeProviderId: String?
    var activeModelId:    String?
    var providers: [String: ProviderConfig]
}

struct ProviderConfig: Codable {
    var modelId:    String
    var baseUrl:    String?
    var configured: Bool
}

struct SettingsRequest: Codable {
    let providerId: String
    let modelId:    String
    let apiKey:     String
    let baseUrl:    String?
}
```

### 4.4 Keychain 工具

```swift
// Store/KeychainHelper.swift
import Security
import Foundation

enum KeychainHelper {
    static func save(_ value: String, for key: String) {
        let data = value.data(using: .utf8)!
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecValueData:   data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(_ key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrAccount:      key,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    static func delete(_ key: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

### 4.5 GatewayClient /settings 端点

```swift
// Gateway/GatewayClient.swift（新增 updateSettings 方法）

func updateSettings(_ req: SettingsRequest) async throws {
    let url = URL(string: "http://127.0.0.1:8765/settings")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(req)
    request.timeoutInterval = 10

    let (_, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw GatewayError.settingsUpdateFailed
    }
}
```

### 4.6 Python /settings 端点

```python
# gateway.py 新增

from pydantic import BaseModel
from typing import Optional

class SettingsRequest(BaseModel):
    provider_id: str
    model_id:    str
    api_key:     str
    base_url:    Optional[str] = None

@app.post("/settings")
async def update_settings(req: SettingsRequest):
    """Swift 切换 Provider 时调用，Python 重建 Provider 实例"""
    try:
        provider = create_provider(
            provider_id=req.provider_id,
            config={
                "api_key":  req.api_key,
                "model":    req.model_id,
                "base_url": req.base_url,
            }
        )
        # 存入 app.state，后续 /chat 使用
        app.state.active_provider    = provider
        app.state.active_provider_id = req.provider_id
        app.state.active_model_id    = req.model_id

        return {"status": "ok", "provider": req.provider_id, "model": req.model_id}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@app.post("/chat")
async def chat(req: ChatRequest):
    # 检查是否已配置 Provider
    if not hasattr(app.state, "active_provider") or app.state.active_provider is None:
        return ChatResponse(
            reply="请先配置云端 API",
            error="no_provider"
        )
    try:
        response = await agent.run(
            message=req.message,
            image=req.image,
            session_id=req.session_id,
            provider=app.state.active_provider  # 使用当前激活的 Provider
        )
        return response
    except Exception as e:
        return ChatResponse(reply="识别失败，请重试", error=str(e))
```

### 4.7 Python 重启后状态恢复

Python 进程重启后内存清空，由 GatewayManager 在健康检查通过后主动推送当前配置：

```swift
// App/GatewayManager.swift

class GatewayManager {
    static let shared = GatewayManager()

    func start() {
        // 启动 Python 进程...
        // 轮询 /health，就绪后调用 onReady()
        waitForReady { self.onReady() }
    }

    private func onReady() {
        // 从本地读取上次的激活配置，推送给 Python
        let store = APIConfigStore.shared
        store.load()  // 从 api_config.json 读取

        guard let providerId = store.activeProviderId,
              let modelId    = store.activeModelId else {
            // 未配置过，等用户去设置
            return
        }

        let apiKey  = store.loadAPIKey(for: providerId) ?? ""
        let baseUrl = store.configurations[providerId]?.baseUrl

        Task {
            let req = SettingsRequest(
                providerId: providerId,
                modelId:    modelId,
                apiKey:     apiKey,
                baseUrl:    baseUrl
            )
            try? await GatewayClient.shared.updateSettings(req)
        }
    }
}
```

### 4.8 切换 API 完整流程

```
用户在 APISettingsPanel 填写 API Key，点击「保存」
        ↓
Swift:
  1. saveAPIKey(apiKey, for: providerId)   → Keychain
  2. 发送验证请求（POST /verify），Python 测试连接
  3. 拉取可用模型列表展示给用户
        ↓
用户选择默认模型，点击「使用此配置」
        ↓
Swift APIConfigStore.activate(providerId, modelId):
  1. 更新内存 activeProviderId / activeModelId
  2. 写入 api_config.json（不含 API Key）
  3. POST /settings { provider_id, model_id, api_key, base_url }
        ↓
Python 收到，create_provider() 初始化 Provider 实例
存入 app.state.active_provider
        ↓
Python 返回 { "status": "ok" }
        ↓
Swift 灵动岛胶囊更新显示：
  "Anthropic / claude-sonnet-4-5"
```

---

## 5. API Provider 配置（13 个 + 自定义）

### Provider 完整列表

```python
PROVIDER_CONFIGS = {
    # 主流云端
    "openai":       { "display_name": "OpenAI",
                      "base_url": "https://api.openai.com/v1",
                      "fields": ["api_key"],
                      "preset_models": ["gpt-4o", "gpt-4o-mini"],
                      "vision_models": ["gpt-4o", "gpt-4o-mini"] },

    "anthropic":    { "display_name": "Anthropic",
                      "fields": ["api_key"],
                      "preset_models": ["claude-sonnet-4-5","claude-haiku-4-5","claude-opus-4-6"],
                      "vision_models": ["claude-sonnet-4-5","claude-haiku-4-5","claude-opus-4-6"],
                      "use_sdk": True },

    "openrouter":   { "display_name": "OpenRouter",
                      "base_url": "https://openrouter.ai/api/v1",
                      "fields": ["api_key"],
                      "fetch_models_from_api": True },

    # 国内云端
    "moonshot":     { "display_name": "Moonshot（月之暗面）",
                      "base_url": "https://api.moonshot.cn/v1",
                      "fields": ["api_key"],
                      "preset_models": ["moonshot-v1-8k","moonshot-v1-32k","moonshot-v1-128k"] },

    "minimax":      { "display_name": "MiniMax",
                      "base_url": "https://api.minimax.chat/v1",
                      "fields": ["api_key"],
                      "preset_models": ["MiniMax-Text-01","abab6.5s-chat"] },

    "glm":          { "display_name": "GLM（智谱）",
                      "base_url": "https://open.bigmodel.cn/api/paas/v4",
                      "fields": ["api_key"],
                      "preset_models": ["glm-4-plus","glm-4-0520","glm-4v-plus"],
                      "vision_models": ["glm-4v-plus"] },

    "zai":          { "display_name": "Z.AI",
                      "base_url": "https://api.z.ai/api/paas/v4",
                      "fields": ["api_key"],
                      "preset_models": ["glm-4-plus","glm-4v-plus"] },

    # 企业/开发者
    "bedrock":      { "display_name": "Amazon Bedrock",
                      "fields": ["aws_access_key","aws_secret_key","region"],
                      "preset_models": ["anthropic.claude-sonnet-4-5"],
                      "note": "需要 AWS IAM 凭证，使用 boto3 SDK" },

    "vercel":       { "display_name": "Vercel AI Gateway",
                      "fields": ["api_key","base_url"],
                      "fetch_models_from_api": True },

    "synthetic":    { "display_name": "Synthetic",
                      "base_url": "https://api.synthetic.new/v1",
                      "fields": ["api_key"],
                      "fetch_models_from_api": True },

    "opencode_zen": { "display_name": "OpenCode Zen",
                      "base_url": "https://api.opencode.zen/v1",
                      "fields": ["api_key"] },

    # 本地服务
    "ollama":       { "display_name": "Ollama（本地服务）",
                      "base_url_default": "http://localhost:11434",
                      "fields": ["base_url"],
                      "fetch_models_endpoint": "/api/tags" },

    # 自定义
    "custom":       { "display_name": "自定义端点",
                      "fields": ["base_url","api_key","model_id"] },
}
```

### 实现策略

```
Anthropic → 使用 anthropic SDK（独立实现 ClaudeProvider）
其他 12 个 → 全部使用 openai SDK + 对应 base_url（OpenAICompatProvider）
Bedrock → 使用 boto3 SDK（BedrockProvider，MVP 可以最后实现）
```

---

## 5. System Prompt（识别核心）

```
你是 Jarvis，用户的 macOS AI 效率助理。

用户会发给你截图，你需要识别其中的日程或任务信息。

## 判断规则
- 有持续时长（开会、吃饭、面试、课程）→ 日程（event_type: "calendar"）
- 有截止时间的任务（交作业、缴费、提交）→ 提醒事项（event_type: "reminder"）
- 无法识别 → event_type: null

## 输出格式（只输出 JSON，不要其他文字）

日程：
{
  "event_type": "calendar",
  "title": "事件标题",
  "start_time": "2026-04-18T14:00:00",
  "end_time": "2026-04-18T15:00:00",
  "needs_duration": false,
  "location": "地点（识别不到则省略）",
  "notes": "备注（识别不到则省略）"
}

说明：end_time 无法推断时省略并设 needs_duration: true

提醒事项：
{
  "event_type": "reminder",
  "title": "任务标题",
  "due_date": "2026-04-20",
  "due_time": "22:00",
  "notes": "备注（识别不到则省略）"
}

无法识别：
{
  "event_type": null,
  "reply": "这张截图中没有识别到日程或任务信息"
}
```

---

## 7. 数据流

### 7.1 截图识别写入

```
⌘⇧J 按下
    ↓
CaptureManager 截图
  SCScreenshotManager 截全屏
  JPEG 压缩（max 1024px，quality 0.85）
  Base64 编码
    ↓
POST http://localhost:8765/chat
  { message: "", image: base64, session_id: UUID }
    ↓
Python JarvisAgent（使用 app.state.active_provider）
  System Prompt + 图片 → CloudProvider
  解析 JSON（最多重试 2 次）
    ↓
ChatResponse
  { event_type, title, start_time, end_time,
    due_date, due_time, location, notes, needs_duration }
    ↓
Swift ConfirmationCard 展示
  如有 location → MapKitTool 搜索 → LocationPicker 让用户选择
    ↓
用户点击「写入」
    ↓
EventKitTool.createEvent()（含坐标）或 createReminder()
    ↓
写入成功 → 胶囊显示 ✓，卡片淡出
```

### 7.2 API 配置与切换

```
用户填写 API Key，点击「保存」
    ↓
Swift:
  API Key → Keychain（key: "jarvis.api_key.{provider_id}"）
  POST /verify → Python 测试连接，返回可用模型列表
  展示模型列表给用户
    ↓
用户选择模型，点击「使用此配置」
    ↓
Swift APIConfigStore.activate():
  内存更新 activeProviderId / activeModelId
  写入 ~/.jarvis/api_config.json（不含 API Key）
  POST /settings { provider_id, model_id, api_key, base_url }
    ↓
Python:
  create_provider() 初始化 Provider 实例
  存入 app.state.active_provider
  返回 { "status": "ok" }
    ↓
Swift 灵动岛胶囊更新显示当前模型名

### 7.3 Python 重启状态恢复

```
Python 进程崩溃或重启
    ↓
GatewayManager 检测到（/health 轮询失败）
    ↓
GatewayManager 重新启动 Python 进程
    ↓
/health 再次返回 200
    ↓
GatewayManager.onReady():
  从 api_config.json 读取 activeProviderId / activeModelId
  从 Keychain 读取 API Key
  POST /settings 推送给 Python，恢复 Provider 实例
    ↓
Python 恢复正常，用户无感知
```

---

## 8. 文件结构

```
Jarvis/
├── Swift/
│   ├── App/
│   │   ├── JarvisApp.swift              # @main，注册 JarvisCommands
│   │   └── GatewayManager.swift         # 启动 Python，onReady() 恢复配置
│   ├── UI/
│   │   ├── StatusBarController.swift    # NSStatusItem，hover 管理
│   │   ├── IslandPanel.swift            # Hover 展开面板（SwiftUI）
│   │   ├── ConfirmationCard.swift       # 识别结果确认卡片
│   │   ├── LocationPicker.swift         # MapKit 地点候选列表
│   │   └── APISettingsPanel.swift       # API 配置双栏面板
│   ├── Commands/
│   │   ├── JarvisCommands.swift         # macOS 顶部菜单栏
│   │   └── APISettingsWindowManager.swift  # 统一管理 API 配置窗口（单例）
│   ├── Gateway/
│   │   └── GatewayClient.swift          # HTTP 封装（/chat, /settings, /verify）
│   ├── NativeActions/
│   │   ├── CaptureManager.swift         # ScreenCaptureKit + 快捷键
│   │   ├── EventKitTool.swift           # Calendar / Reminder 写入（含坐标）
│   │   └── MapKitTool.swift             # MKLocalSearch 地点搜索
│   ├── Store/
│   │   ├── APIConfigStore.swift         # Provider 配置状态管理
│   │   │                               # 负责：内存状态 / api_config.json / Keychain / 通知 Python
│   │   └── KeychainHelper.swift         # Keychain 读写封装
│   ├── Models/
│   │   ├── ChatRequest.swift
│   │   ├── ChatResponse.swift
│   │   ├── SettingsRequest.swift        # POST /settings 请求体
│   │   ├── RecognitionResult.swift
│   │   └── LocationResult.swift
│   └── Info.plist
│
├── Python/
│   ├── gateway.py                       # FastAPI（/health, /chat, /settings, /verify）
│   ├── agent/
│   │   └── jarvis_agent.py
│   ├── providers/
│   │   ├── base.py
│   │   ├── claude.py
│   │   ├── openai_compat.py
│   │   ├── provider_factory.py
│   │   └── provider_configs.py
│   └── requirements.txt
│
└── ~/.jarvis/
    └── api_config.json                  # 非敏感配置（Provider ID、Model ID、Base URL）
                                         # API Key 在 Keychain，不在此文件
```

---

## 8. 依赖清单

**Swift（SPM）**：
```
KeyboardShortcuts    全局快捷键注册
原生框架：AppKit, SwiftUI, ScreenCaptureKit,
          EventKit, MapKit, CoreLocation, Security
```

**Python（requirements.txt）**：
```
fastapi>=0.115.0
uvicorn>=0.30.0
anthropic>=0.34.0
openai>=1.45.0
httpx>=0.27.0
pydantic>=2.8.0
```

**Info.plist 权限**：
```xml
NSCalendarsUsageDescription
NSRemindersUsageDescription
NSScreenCaptureUsageDescription
NSLocationWhenInUseUsageDescription
```

---

## 9. 验收标准

**灵动岛**：
- 常驻菜单栏，Hover 展开显示截图按钮和设置按钮
- 当前 API 配置名称显示在胶囊（未配置显示"未配置 API"）

**macOS 顶部菜单栏**：
- 显示「Jarvis / 操作 / 模型」三个菜单
- 「操作 → 截图识别 ⌘⇧J」与全局快捷键等效
- 「模型 → 配置云端 API...」打开 APISettingsPanel 窗口
- 灵动岛设置按钮与菜单栏入口打开同一个窗口，不重复

**API 配置**：
- 13 个 Provider + 自定义端点可见可配置
- API Key 加密存入 Keychain
- 验证成功显示可用模型列表
- 可选择默认模型并激活

**截图识别写入（含地点）**：
- ⌘⇧J 全局生效（在任何 App 下）
- 推理中显示加载状态
- 日程/提醒类型识别正确
- ConfirmationCard 正确展示所有字段
- 识别到地点时弹出 LocationPicker 候选列表
- 用户选择地点后写入坐标，Calendar 可直接导航
- 写入 Calendar / Reminder 成功
- 边缘情况有友好错误提示

---

## 10. 开发顺序

```
Step 1   Python Gateway 骨架
         → gateway.py 启动
         → GET /health 返回 200
         → app.state.active_provider = None（初始无 Provider）

Step 2   云端 Provider 实现
         → claude.py（Anthropic SDK）
         → openai_compat.py（OpenAI SDK，覆盖其余 12 个 Provider）
         → provider_factory.py + provider_configs.py
         → 命令行直接调用 provider.chat() 验证 API 连通

Step 3   Python /settings 端点
         → POST /settings 接收 { provider_id, model_id, api_key, base_url }
         → create_provider() 初始化 Provider 实例存入 app.state
         → curl 测试：POST /settings → POST /chat 验证链路

Step 4   JarvisAgent 识别逻辑
         → jarvis_agent.py（System Prompt + JSON 解析）
         → 用测试图片验证识别结果正确

Step 5   Swift KeychainHelper + APIConfigStore
         → Keychain 读写（save / load / delete）
         → api_config.json 读写（load / save）
         → activate() 方法：更新内存 + 写 JSON + 调 /settings

Step 6   Swift GatewayManager
         → 启动 Python 进程（Process + stdin/stdout）
         → 轮询 /health，就绪后调 onReady()
         → onReady()：从 api_config.json + Keychain 读配置，POST /settings 恢复

Step 7   Swift GatewayClient
         → POST /chat 封装
         → POST /settings 封装
         → POST /verify 封装（验证 API Key + 拉取模型列表）

Step 8   CaptureManager
         → ⌘⇧J 全局快捷键（KeyboardShortcuts）
         → ScreenCaptureKit 截图 + JPEG 压缩 + Base64
         → 发给 GatewayClient.chat()

Step 9   StatusBarController + IslandPanel
         → 胶囊常驻菜单栏，Hover 展开/收起
         → 截图按钮触发 CaptureManager
         → 设置按钮触发 APISettingsWindowManager.open()
         → 胶囊显示当前模型名（APIConfigStore.activeDisplayName）

Step 10  APISettingsPanel + APISettingsWindowManager
         → 左侧 Provider 列表（13 个 + 自定义）
         → 右侧配置表单（随 Provider 类型变化字段）
         → 「保存」：
             API Key → Keychain
             POST /verify → 展示模型列表
         → 「使用此配置」：
             APIConfigStore.activate() → 写 JSON + POST /settings
             灵动岛胶囊更新显示
         → APISettingsWindowManager 保证同一时间只有一个窗口

Step 11  macOS 顶部菜单栏
         → JarvisCommands：操作菜单 + 模型菜单
         → 「截图识别 ⌘⇧J」触发 CaptureManager
         → 「配置云端 API...」触发 APISettingsWindowManager.open()
         → 与灵动岛设置按钮共用同一个窗口

Step 12  ConfirmationCard
         → 展示识别字段（标题/时间/地点/类型）
         → 地点字段：有值时触发 MapKit 搜索
         → 「写入」按钮触发 EventKitTool

Step 13  MapKitTool + LocationPicker
         → MKLocalSearch 搜索地点关键词
         → LocationPicker 展示候选（最多 5 个）
         → 用户点选后更新 ConfirmationCard，记录坐标

Step 14  EventKitTool
         → createEvent()（含 EKStructuredLocation 坐标）
         → createReminder()
         → 权限请求（首次调用时弹出系统授权）

Step 15  联调测试
         → 完整流程：⌘⇧J → 识别 → 地点选择 → 确认 → 写入
         → API 切换：配置新 Provider → 灵动岛更新 → 重新识别
         → Python 重启恢复：kill Python → 自动重启 → 配置自动恢复

Step 16  错误处理
         → 未配置 API：提示"请先配置云端 API"
         → 网络超时：提示重试
         → API Key 无效：显示具体错误
         → 识别失败：提示无法识别
         → 地点搜索无结果：使用文字地点（无坐标）
         → EventKit 权限被拒：引导用户授权
         → 截图权限被拒：引导用户在系统设置中授权
```

**预计开发时间（Claude Code 辅助）**：7-10 天
