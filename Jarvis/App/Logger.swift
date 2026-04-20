import Foundation

func jlog(_ msg: String) {
    let line = "[\(Date())] \(msg)\n"
    print(line, terminator: "")
    let logDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Jarvis")
    try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    let logFile = logDir.appendingPathComponent("gateway.log")
    guard let data = line.data(using: .utf8) else { return }
    if FileManager.default.fileExists(atPath: logFile.path) {
        if let fh = try? FileHandle(forWritingTo: logFile) {
            fh.seekToEndOfFile(); fh.write(data); try? fh.close()
        }
    } else {
        try? data.write(to: logFile)
    }
}
