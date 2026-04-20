# Jarvis — CLAUDE.md

## 项目概述

macOS AI 效率助理，常驻顶栏，以灵动岛（Dynamic Island）形式呈现。
完整产品规格见 `jarvis_dev_doc.md`。

## 技术栈

- **Swift / AppKit + SwiftUI**：UI 层（`Jarvis/` 目录）
- **Python 3.11 / FastAPI**：Agent 层（`Python/` 目录），运行在 `localhost:8765`
- Python 环境：`~/miniconda3/envs/Jarvis/`

## 当前分支：`feat/UI`

### 灵动岛定位（核心问题）

目标：胶囊窗口完全覆盖刘海（notch），收起时透明融合，悬停时向下展开。

**刘海坐标（MacBook Pro 主屏）：**
- `auxiliaryTopLeftArea`: x=0, y=924, w=646, h=32
- `auxiliaryTopRightArea`: x=825, y=924, w=645, h=32
- 刘海 rect: x=646, y=924, **w=179, h=32**
- `screen.frame`: (0, 0, 1470, 956)

**关键实现：**
- `UnconstrainedPanel: NSPanel` — override `constrainFrameRect` 绕过 macOS 菜单栏限制
- Window level: `NSWindow.Level.statusBar + 1`
- 定位公式：`y = notchRect.maxY - size.height`（顶部对齐刘海顶部，向下扩展）

### Hover 方案（已落地）

**已解决：** 丢弃双 panel + `IslandTrackingView`，改用全局鼠标监听。

```swift
// IslandWindowController.startMouseTracking()
NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { ... checkHoverState() }
NSEvent.addLocalMonitorForEvents(matching: .mouseMoved)  { ... checkHoverState(); return event }
```

`checkHoverState()` 直接比对 `NSEvent.mouseLocation` vs `notchRect` / `panel.frame`，完全绕过 NSHostingView hit-testing。

**IslandCapsuleView 布局：**
- 收起态：透明（notch 自身是黑色）
- 展开态：`UnevenRoundedRectangle` 黑色胶囊填满整个 window（notch+52px）；按钮区用 `GeometryReader` 定位在 notch 以下

**右键退出菜单：** 由 `UnconstrainedPanel.rightMouseDown` 处理。

## 启动方式

```bash
# 构建
xcodebuild -project Jarvis/Jarvis.xcodeproj -scheme Jarvis -configuration Debug \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO

# 运行
open build/DerivedData/Build/Products/Debug/Jarvis.app

# 日志
tail -f ~/Library/Logs/Jarvis/gateway.log
```

## 文件结构（关键文件）

```
Jarvis/
  App/
    JarvisApp.swift          # AppDelegate，setup() 入口
    GatewayManager.swift     # 启动 Python gateway
    Logger.swift             # jlog() 写入 ~/Library/Logs/Jarvis/gateway.log
  UI/
    IslandWindowController.swift  # 核心：双 panel 架构
    IslandCapsuleView.swift       # SwiftUI 内容视图
    IslandPanel.swift             # UnconstrainedPanel 定义
Python/
  gateway.py                 # FastAPI server
jarvis_dev_doc.md            # 完整产品规格文档（v1.6）
```
