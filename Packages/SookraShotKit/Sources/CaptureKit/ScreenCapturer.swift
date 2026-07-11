import CoreGraphics
import ScreenCaptureKit

public enum CaptureError: Error, Sendable {
    case displayNotFound
    case windowNotFound
}

/// Still-image capture via ScreenCaptureKit (`SCScreenshotManager`, macOS 14+).
public struct ScreenCapturer: Sendable {
    public init() {}

    /// Captures a rect given in display-local coordinates (origin top-left, points).
    public func captureRect(
        _ rectInDisplay: CGRect,
        displayID: CGDirectDisplayID,
        scale: CGFloat
    ) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows(in: content))
        let configuration = stillConfiguration(
            width: Int(rectInDisplay.width * scale),
            height: Int(rectInDisplay.height * scale)
        )
        configuration.sourceRect = rectInDisplay
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    /// Captures an entire display.
    public func captureDisplay(_ displayID: CGDirectDisplayID, scale: CGFloat) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows(in: content))
        let configuration = stillConfiguration(
            width: Int(CGFloat(display.width) * scale),
            height: Int(CGFloat(display.height) * scale)
        )
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    /// Captures a single window, preserving its alpha (rounded corners, no wallpaper bleed).
    public func captureWindow(windowID: CGWindowID, scale: CGFloat) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotFound
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = stillConfiguration(
            width: Int(window.frame.width * scale),
            height: Int(window.frame.height * scale)
        )
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    private func stillConfiguration(width: Int, height: Int) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = max(width, 1)
        configuration.height = max(height, 1)
        configuration.showsCursor = false
        configuration.captureResolution = .best
        return configuration
    }

    private func ownWindows(in content: SCShareableContent) -> [SCWindow] {
        let pid = ProcessInfo.processInfo.processIdentifier
        return content.windows.filter { $0.owningApplication?.processID == pid }
    }
}
