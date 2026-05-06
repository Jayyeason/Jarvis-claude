import Foundation
import AppKit

@MainActor
class GatewayManager: ObservableObject {
    static let shared = GatewayManager()

    @Published var isReady = false
    @Published var isStarting = false

    private var process: Process?
    private var healthTimer: Timer?

    func start() {
        guard !isStarting else { return }
        isStarting = true
        Task { await launchPython() }
    }

    private func launchPython() async {
        let pythonPath = findPython()
        let gatewayPath = gatewayScriptPath()

        jlog("[GatewayManager] python=\(pythonPath) gateway=\(gatewayPath)")

        guard FileManager.default.fileExists(atPath: gatewayPath) else {
            jlog("[GatewayManager] ERROR: gateway.py not found at \(gatewayPath)")
            isStarting = false
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: pythonPath)
        proc.arguments = [gatewayPath]
        proc.currentDirectoryURL = URL(fileURLWithPath: gatewayPath).deletingLastPathComponent()

        // Capture stdout/stderr to log
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { fh in
            if let s = String(data: fh.availableData, encoding: .utf8), !s.isEmpty {
                jlog(s.trimmingCharacters(in: .newlines), file: .python)
            }
        }

        do {
            try proc.run()
            jlog("[GatewayManager] Python process started (pid=\(proc.processIdentifier))")
            jlog("[GatewayManager] Python process started (pid=\(proc.processIdentifier))", file: .python)
            self.process = proc
        } catch {
            jlog("[GatewayManager] ERROR: Failed to start Python: \(error)")
            isStarting = false
            return
        }

        await waitForReady()
    }

    private func waitForReady() async {
        for attempt in 0..<30 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if (try? await GatewayClient.shared.health()) == true {
                jlog("[GatewayManager] Gateway ready after \(attempt + 1) attempts")
                isReady = true
                isStarting = false
                await APIConfigStore.shared.loadFromGateway()
                startHealthMonitor()
                return
            }
            jlog("[GatewayManager] Waiting for gateway... attempt \(attempt + 1)")
        }
        jlog("[GatewayManager] ERROR: Gateway did not start in time")
        isStarting = false
    }

    private func startHealthMonitor() {
        healthTimer?.invalidate()
        healthTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let alive = (try? await GatewayClient.shared.health()) == true
                if !alive && self.isReady {
                    self.isReady = false
                    self.restart()
                }
            }
        }
    }

    private func restart() {
        jlog("[GatewayManager] Restarting gateway...")
        process?.terminate()
        process = nil
        isStarting = false
        Task { await launchPython() }
    }

    func stop() {
        healthTimer?.invalidate()
        process?.terminate()
        process = nil
        isReady = false
    }

    private func findPython() -> String {
        let candidates = [
            // conda Jarvis env (preferred — has all dependencies)
            "\(NSHomeDirectory())/miniconda3/envs/Jarvis/bin/python",
            "\(NSHomeDirectory())/anaconda3/envs/Jarvis/bin/python",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? "python3"
    }

    private func gatewayScriptPath() -> String {
        // Walk up from bundle until we find Python/gateway.py (works for both
        // DerivedData debug builds and a relocated .app)
        var url = URL(fileURLWithPath: Bundle.main.bundlePath)
        for _ in 0..<8 {
            let candidate = url.appendingPathComponent("Python/gateway.py")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.path
            }
            url = url.deletingLastPathComponent()
        }
        return FileManager.default.currentDirectoryPath + "/Python/gateway.py"
    }
}
