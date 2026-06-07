import AppKit

/// Menu bar entry for configuration and app-level actions.
@MainActor
class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!

    override init() {
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "j.circle.fill", accessibilityDescription: "Jarvis")
            button.image?.isTemplate = true
            button.action = #selector(showMenu)
            button.target = self
        }
    }

    @objc private func showMenu() {
        let menu = NSMenu()
        let modelItem = NSMenuItem(title: "管理端侧模型...", action: #selector(openModelManager), keyEquivalent: "")
        modelItem.target = self
        menu.addItem(modelItem)
        let apiItem = NSMenuItem(title: "配置云端 API...", action: #selector(openAPISettings), keyEquivalent: "")
        apiItem.target = self
        menu.addItem(apiItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "退出 Jarvis", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openModelManager() {
        ModelManagerWindowManager.shared.open()
    }

    @objc private func openAPISettings() {
        APISettingsWindowManager.shared.open()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
