import Foundation

enum JarvisLogFile: String {
    case app = "app.log"
    case python = "python.log"
}

func jlog(_ msg: String, file: JarvisLogFile = .app) {
    let line = "[\(Date())] \(msg)\n"
    print(line, terminator: "")
    let logDir = jarvisLogDirectory()
    try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    let logFile = logDir.appendingPathComponent(file.rawValue)
    guard let data = line.data(using: .utf8) else { return }
    if FileManager.default.fileExists(atPath: logFile.path) {
        if let fh = try? FileHandle(forWritingTo: logFile) {
            fh.seekToEndOfFile(); fh.write(data); try? fh.close()
        }
    } else {
        try? data.write(to: logFile)
    }
}

func jlogPathDescription() -> String {
    jarvisLogDirectory().path
}

private func jarvisLogDirectory() -> URL {
    let fm = FileManager.default
    var url = URL(fileURLWithPath: Bundle.main.bundlePath)
    for _ in 0..<8 {
        let candidate = url.appendingPathComponent("Python/gateway.py")
        if fm.fileExists(atPath: candidate.path) {
            return url.appendingPathComponent(".logs")
        }
        url = url.deletingLastPathComponent()
    }
    let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
    if fm.fileExists(atPath: cwd.appendingPathComponent("Python/gateway.py").path) {
        return cwd.appendingPathComponent(".logs")
    }
    return URL(fileURLWithPath: "/Users/kk/Jarvis-claude/.logs")
}
