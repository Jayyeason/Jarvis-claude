import AppKit
import Carbon
import Foundation

final class NotesTool {
    static let shared = NotesTool()

    private static let notesBundleID = "com.apple.Notes"

    private init() {}

    func createNote(title: String, content: String) async throws -> String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { throw NotesToolError.missingTitle }
        guard !cleanContent.isEmpty else { throw NotesToolError.missingContent }

        let normalizedTitle = cleanTitle.replacingOccurrences(of: "\n", with: " ")
        let body = Self.noteHTML(title: normalizedTitle, content: cleanContent)
        let safeBody = Self.appleScriptString(body)
        let script = """
        with timeout of 30 seconds
            tell application id "\(Self.notesBundleID)"
                activate
                set targetFolder to default folder of default account
                set createdNote to make new note at targetFolder with properties {body:"\(safeBody)"}
                return "ok"
            end tell
        end timeout
        """

        try await Self.ensureAutomationPermission()
        try await Self.runAppleScript(script)
        jlog("[NotesTool] created note title=\(normalizedTitle)")
        return normalizedTitle
    }

    private static func ensureAutomationPermission() async throws {
        try await ensureNotesRunning()

        let status = try await Task.detached(priority: .userInitiated) { () throws -> OSStatus in
            let target = NSAppleEventDescriptor(bundleIdentifier: notesBundleID)
            guard let aeDesc = target.aeDesc else {
                throw NotesToolError.appleScriptFailed("无法创建备忘录自动化权限请求。")
            }
            return AEDeterminePermissionToAutomateTarget(aeDesc, typeWildCard, typeWildCard, true)
        }.value

        guard status == noErr else {
            if status == errAEEventNotPermitted || status == errAEEventWouldRequireUserConsent {
                openAutomationSettings()
                throw NotesToolError.automationPermissionDenied
            }
            if status == procNotFound {
                throw NotesToolError.appleScriptFailed("备忘录未启动，请手动打开一次“备忘录”后再试。")
            }
            throw NotesToolError.appleScriptFailed("请求控制“备忘录”权限失败，系统错误码：\(status)。")
        }
    }

    private static func ensureNotesRunning() async throws {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: notesBundleID).isEmpty {
            return
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: notesBundleID) else {
            throw NotesToolError.appleScriptFailed("找不到 macOS 自带“备忘录”应用。")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.main.async {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }

        for _ in 0..<20 {
            if !NSRunningApplication.runningApplications(withBundleIdentifier: notesBundleID).isEmpty {
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw NotesToolError.appleScriptFailed("备忘录启动超时，请手动打开一次“备忘录”后再试。")
    }

    private static func openAutomationSettings() {
        DispatchQueue.main.async {
            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
            NSWorkspace.shared.open(url)
        }
    }

    private static func runAppleScript(_ source: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            guard let appleScript = NSAppleScript(source: source) else {
                throw NotesToolError.appleScriptFailed("无法创建备忘录写入脚本。")
            }
            var errorInfo: NSDictionary?
            _ = appleScript.executeAndReturnError(&errorInfo)
            if errorInfo != nil {
                throw NotesToolError.appleScriptFailed(Self.readableAppleScriptError(errorInfo))
            }
        }.value
    }

    private static func noteHTML(title: String, content: String) -> String {
        let escapedTitle = htmlEscaped(title)
        let escapedContent = content
            .components(separatedBy: .newlines)
            .map { htmlEscaped($0) }
            .joined(separator: "<br>")
        return "<h1>\(escapedTitle)</h1><div>\(escapedContent)</div>"
    }

    private static func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func appleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func readableAppleScriptError(_ errorInfo: NSDictionary?) -> String {
        let message = errorInfo?[NSAppleScript.errorMessage] as? String
        let brief = errorInfo?[NSAppleScript.errorBriefMessage] as? String
        let number = (errorInfo?[NSAppleScript.errorNumber] as? NSNumber)?.intValue
        let text = (message ?? brief ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if number == errAEEventNotPermitted {
            openAutomationSettings()
            return automationPermissionMessage
        }
        if number == -1712 {
            return "写入备忘录超时。若没有看到授权弹窗，请到“系统设置 > 隐私与安全性 > 自动化”，允许 Jarvis 控制“备忘录”；如果已经允许，请确认 Notes 没有卡在同步或弹窗状态。"
        }
        guard !text.isEmpty else { return "未知 AppleScript 错误" }
        if text.contains("-1743") || text.localizedCaseInsensitiveContains("not authorized") || text.localizedCaseInsensitiveContains("not permitted") {
            openAutomationSettings()
            return automationPermissionMessage
        }
        if text.localizedCaseInsensitiveContains("timed out") || text.contains("-1712") {
            return "写入备忘录超时。若没有看到授权弹窗，请到“系统设置 > 隐私与安全性 > 自动化”，允许 Jarvis 控制“备忘录”；如果已经允许，请确认 Notes 没有卡在同步或弹窗状态。"
        }
        if let number {
            return "\(text)（错误码：\(number)）"
        }
        return text
    }

    fileprivate static var automationPermissionMessage: String {
        "需要先授权 Jarvis 控制“备忘录”。我已尝试打开“系统设置 > 隐私与安全性 > 自动化”，请在 Jarvis 下勾选“备忘录”，然后重新发送一次。这个权限只需要授权一次。"
    }
}

enum NotesToolError: Error, LocalizedError {
    case missingTitle
    case missingContent
    case automationPermissionDenied
    case appleScriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingTitle:
            return "缺少备忘录标题"
        case .missingContent:
            return "缺少备忘录内容"
        case .automationPermissionDenied:
            return "写入备忘录失败：\(NotesTool.automationPermissionMessage)"
        case .appleScriptFailed(let message):
            return "写入备忘录失败：\(message)"
        }
    }
}
