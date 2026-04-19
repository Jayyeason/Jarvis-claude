# Jarvis

灵动岛版 macOS AI 效率助理。

## 功能

- 菜单栏灵动岛胶囊，Hover 展开显示操作按钮
- `⌘⇧J` 全局截图识别日程/任务
- 支持 13 个云端 API Provider + 自定义端点
- 识别结果写入 macOS Calendar / Reminder（含地点坐标）
- MapKit 地点候选列表

## 架构

```
Swift 进程（UI 层）
  ↕ HTTP localhost:8765
Python 进程（Agent + LLM 层）
```

## 快速开始

### Python 后端

```bash
cd Python
pip install -r requirements.txt
python gateway.py
```

### Swift 应用

用 Xcode 打开 `Jarvis/Jarvis.xcodeproj`，编译运行。

首次运行需在「模型 → 配置云端 API...」配置 API Key。

## 快捷键

| 快捷键 | 功能 |
|--------|------|
| `⌘⇧J` | 截图识别 |
| `⌘,` | 设置（暂未实现） |
| `⌘Q` | 退出 |

## 依赖

**Swift**: AppKit, SwiftUI, ScreenCaptureKit, EventKit, MapKit, CoreLocation, Security  
**Python**: fastapi, uvicorn, anthropic, openai, httpx, pydantic
