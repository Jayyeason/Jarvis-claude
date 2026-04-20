import AppKit

/// Minimal menu bar item — only provides a "Quit" entry.
/// All island logic lives in IslandWindowController.
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
        menu.addItem(NSMenuItem(title: "退出 Jarvis", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
