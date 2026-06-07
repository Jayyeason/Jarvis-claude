import SwiftUI

struct JarvisCommands: Commands {
    var body: some Commands {
        CommandMenu("操作") {
            Button("截图识别") {
                CaptureManager.shared.capture()
            }
            .keyboardShortcut("j", modifiers: [.command, .shift])

            Button("新建对话") {
                CaptureManager.shared.capture()
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandMenu("模型") {
            Button("管理端侧模型...") {
                ModelManagerWindowManager.shared.open()
            }

            Button("配置云端 API...") {
                APISettingsWindowManager.shared.open()
            }
        }
    }
}
