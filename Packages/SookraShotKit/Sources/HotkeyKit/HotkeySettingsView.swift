import KeyboardShortcuts
import SwiftUI

/// Shortcut recorders for every global action, embedded in the Settings window.
public struct HotkeySettingsView: View {
    public init() {}

    public var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Capture Fullscreen", name: .captureFullscreen)
            KeyboardShortcuts.Recorder("Capture Area / Window", name: .captureArea)
            KeyboardShortcuts.Recorder("All-In-One", name: .allInOne)
            KeyboardShortcuts.Recorder("Capture Text (OCR)", name: .captureText)
            KeyboardShortcuts.Recorder("Record Screen", name: .recordScreen)
            KeyboardShortcuts.Recorder("Scrolling Capture", name: .scrollingCapture)
            KeyboardShortcuts.Recorder("Ask Claude", name: .askClaude)
            KeyboardShortcuts.Recorder("Share as Link (B2)", name: .cloudShare)
            KeyboardShortcuts.Recorder("Sample Color (hex)", name: .sampleColor)
        }
        .padding(20)
    }
}
