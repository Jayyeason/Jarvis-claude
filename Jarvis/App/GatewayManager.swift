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

        guard FileManager.default.fileExists(atPath: gatewayPath) else {
            print("[GatewayManager] gateway.py not found at \(gatewayPath)")
            isStarting = false
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: pythonPath)
        proc.arguments = [gatewayPath]
        proc.currentDirectoryURL = URL(fileURLWithPath: gatewayPath).deletingLastPathComponent()

        do {
            try proc.run()
            self.process = proc
        } catch {
            print("[GatewayManager] Failed to start Python: \(error)")
            isStarting = false
            return
        }

        await waitForReady()
    }

    private func waitForReady() async {
        for attempt in 0..<30 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if (try? await GatewayClient.shared.health()) == true {
                isReady = true
                isStarting = false
                // Python auto-restored config from disk; just sync display state
                await APIConfigStore.shared.loadFromGateway()
                startHealthMonitor()
                return
            }
            print("[GatewayManager] Waiting for gateway... attempt \(attempt + 1)")
        }
        print("[GatewayManager] Gateway did not start in time")
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
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? "python3"
    }

    private func gatewayScriptPath() -> String {
        let candidates = [
            Bundle.main.bundlePath + "/../../../../Python/gateway.py",
            Bundle.main.bundlePath + "/../Python/gateway.py",
            (Bundle.main.resourcePath ?? "") + "/Python/gateway.py",
        ]
        for path in candidates {
            let resolved = URL(fileURLWithPath: path).standardized.path
            if FileManager.default.fileExists(atPath: resolved) { return resolved }
        }
        return FileManager.default.currentDirectoryPath + "/Python/gateway.py"
    }
}
