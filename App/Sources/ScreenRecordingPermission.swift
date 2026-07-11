import AppKit
import CoreGraphics

enum ScreenRecordingPermission {
    static var granted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the one-time system prompt when access was never requested.
    /// Later revocations require the user to flip the toggle in System Settings.
    static func requestIfNeeded() {
        guard !granted else { return }
        CGRequestScreenCaptureAccess()
    }

    static func openSystemSettings() {
        let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        if let url = URL(string: pane) {
            NSWorkspace.shared.open(url)
        }
    }
}
