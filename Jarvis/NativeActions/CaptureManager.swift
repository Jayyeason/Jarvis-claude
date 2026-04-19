import Foundation
import AppKit
import ScreenCaptureKit

@MainActor
class CaptureManager {
    static let shared = CaptureManager()

    var onCaptureComplete: ((ChatResponse) -> Void)?
    var onCaptureStart: (() -> Void)?
    var onCaptureError: ((String) -> Void)?

    @Published var isCapturing = false

    func capture() {
        guard !isCapturing else { return }
        isCapturing = true
        onCaptureStart?()
        Task { await performCapture() }
    }

    private func performCapture() async {
        defer { isCapturing = false }

        do {
            let image = try await captureScreen()
            let base64 = try compressToJPEG(image)
            let req = ChatRequest(message: "", image: base64, sessionId: UUID().uuidString)
            let response = try await GatewayClient.shared.chat(req)
            onCaptureComplete?(response)
        } catch {
            onCaptureError?(error.localizedDescription)
        }
    }

    private func captureScreen() async throws -> NSImage {
        // Request permission check
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw NSError(domain: "Capture", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display found"])
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    private func compressToJPEG(_ image: NSImage) throws -> String {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            throw NSError(domain: "Capture", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot create bitmap"])
        }

        // Resize to max 1024px on longest side
        let maxSide: CGFloat = 1024
        let w = CGFloat(bitmap.pixelsWide)
        let h = CGFloat(bitmap.pixelsHigh)
        let scale = max(w, h) > maxSide ? maxSide / max(w, h) : 1.0
        let newSize = NSSize(width: w * scale, height: h * scale)

        let resized = NSImage(size: newSize)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        resized.unlockFocus()

        guard let resizedTiff = resized.tiffRepresentation,
              let resizedBitmap = NSBitmapImageRep(data: resizedTiff),
              let jpeg = resizedBitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            throw NSError(domain: "Capture", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot compress JPEG"])
        }

        return jpeg.base64EncodedString()
    }
}
