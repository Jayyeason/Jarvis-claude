# Jarvis

灵动岛版 macOS AI 效率助理。截图识别日程/任务，一键写入 Calendar 和 Reminders。

## 功能

- 菜单栏灵动岛胶囊，Hover 展开显示操作按钮
- `⌘⇧J` 全局截图识别日程/任务
- 支持 13 个云端 API Provider + 自定义端点
- 识别结果写入 macOS Calendar / Reminders（含地点坐标）
- MapKit 地点候选列表

## 架构

```
Swift 进程（UI + 原生 API 层）
  ↕ HTTP localhost:8765
Python 进程（Agent + LLM 层）
```

## 开发环境配置

### 依赖

- macOS 13+，Xcode 15+，xcodegen（`brew install xcodegen`）
- Python 3.11+

### 1. Python 后端

创建虚拟环境并安装依赖：

```bash
cd Python
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

启动后端（每次开发前激活环境）：

```bash
source Python/.venv/bin/activate
python Python/gateway.py
```

后端默认监听 `http://localhost:8765`。

### 2. Swift 前端

```bash
make build   # 编译
make run     # 编译 + 启动
```

或者一条命令同时启动前后端：

```bash
make dev
```

### 3. 配置 API Key

首次运行后，点击灵动岛胶囊展开 → 右侧齿轮图标 → 配置云端 API Key。

## 快捷键

| 快捷键 | 功能 |
|--------|------|
| `⌘⇧J` | 截图识别 |
| `⌘Q` | 退出（右键灵动岛） |

## 依赖

**Swift**: AppKit, SwiftUI, ScreenCaptureKit, EventKit, MapKit, CoreLocation, Security  
**Python**: fastapi, uvicorn, anthropic, openai, httpx, pydantic

## 文档

详细设计文档见 [`docs/`](docs/) 目录。
