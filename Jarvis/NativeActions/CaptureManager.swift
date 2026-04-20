import Foundation
import AppKit
import Vision

@MainActor
class CaptureManager {
    static let shared = CaptureManager()

    var onCaptureComplete: ((ChatResponse) -> Void)?
    var onCaptureStart: (() -> Void)?
    var onCaptureError: ((String) -> Void)?

    private var isCapturing = false

    func capture() {
        guard !isCapturing else { return }
        isCapturing = true
        Task { await performCapture() }
    }

    private func performCapture() async {
        defer { isCapturing = false }

        do {
            jlog("[Capture] Starting interactive region capture")
            let image = try await captureRegion()
            jlog("[Capture] Region captured")
            onCaptureStart?()

            // Check if active model supports vision
            let supportsVision = (try? await GatewayClient.shared.getConfig())?.activeModelVision ?? false
            jlog("[Capture] Model vision support: \(supportsVision)")

            let req: ChatRequest
            if supportsVision {
                let base64 = try compressToJPEG(image)
                jlog("[Capture] Sending image (base64 size=\(base64.count))")
                req = ChatRequest(message: "", image: base64, sessionId: UUID().uuidString)
            } else {
                let text = try await ocrText(from: image)
                jlog("[Capture] OCR result: \(text.prefix(100))")
                req = ChatRequest(message: text, image: nil, sessionId: UUID().uuidString)
            }

            let response = try await GatewayClient.shared.chat(req)
            jlog("[Capture] Got response: event_type=\(response.eventType ?? "nil") error=\(response.error ?? "none")")
            onCaptureComplete?(response)
        } catch CaptureError.cancelled {
            jlog("[Capture] User cancelled")
        } catch {
            jlog("[Capture] ERROR: \(error)")
            onCaptureError?(error.localizedDescription)
        }
    }

    // Interactive region selection via screencapture -i -s
    private func captureRegion() async throws -> NSImage {
        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis_\(UUID().uuidString).png")

        return try await withCheckedThrowingContinuation { continuation in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            proc.arguments = ["-i", "-s", "-x", tmpFile.path]
            proc.terminationHandler = { p in
                guard p.terminationStatus == 0,
                      FileManager.default.fileExists(atPath: tmpFile.path),
                      let image = NSImage(contentsOf: tmpFile) else {
                    try? FileManager.default.removeItem(at: tmpFile)
                    continuation.resume(throwing: CaptureError.cancelled)
                    return
                }
                try? FileManager.default.removeItem(at: tmpFile)
                continuation.resume(returning: image)
            }
            do { try proc.run() } catch { continuation.resume(throwing: error) }
        }
    }

    // Vision framework OCR
    private func ocrText(from image: NSImage) async throws -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw CaptureError.ocrFailed
        }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { req, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let text = (req.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text.isEmpty ? "（截图中未识别到文字）" : text)
            }
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            request.recognitionLevel = .accurate
            let handler = VNImageRequestHandler(cgImage: cgImage)
            do { try handler.perform([request]) } catch { continuation.resume(throwing: error) }
        }
    }

    private func compressToJPEG(_ image: NSImage) throws -> String {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            throw CaptureError.compressionFailed
        }
        let maxSide: CGFloat = 1024
        let w = CGFloat(bitmap.pixelsWide), h = CGFloat(bitmap.pixelsHigh)
        let scale = max(w, h) > maxSide ? maxSide / max(w, h) : 1.0
        let newSize = NSSize(width: w * scale, height: h * scale)

        let resized = NSImage(size: newSize)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1.0)
        resized.unlockFocus()

        guard let rt = resized.tiffRepresentation,
              let rb = NSBitmapImageRep(data: rt),
              let jpeg = rb.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            throw CaptureError.compressionFailed
        }
        return jpeg.base64EncodedString()
    }
}

enum CaptureError: Error, LocalizedError {
    case cancelled, compressionFailed, ocrFailed
    var errorDescription: String? {
        switch self {
        case .cancelled:         return "截图已取消"
        case .compressionFailed: return "图片压缩失败"
        case .ocrFailed:         return "OCR 失败"
        }
    }
}
