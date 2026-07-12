import AppKit
import SharedKit
import SwiftUI

/// Owns the floating Ask Claude panel. Non-activating so it never steals focus
/// from the app you just captured, but it can become key when you click it so
/// the text fields work.
@MainActor
public final class AskClaudePanelController {
    private var panel: NSPanel?

    public init() {}

    public func present(_ capture: DeliveredCapture) {
        let model = AskClaudeModel(capture: capture)
        let hosting = NSHostingController(rootView: AskClaudeView(model: model))
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentViewController = hosting
        position(panel, for: capture)
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 480),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Ask Claude"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    private func position(_ panel: NSPanel, for capture: DeliveredCapture) {
        guard let frame = screen(for: capture.displayID)?.visibleFrame else {
            panel.center()
            return
        }
        let size = panel.frame.size
        let origin = NSPoint(x: frame.maxX - size.width - 24, y: frame.maxY - size.height - 24)
        panel.setFrameOrigin(origin)
    }

    private func screen(for displayID: CGDirectDisplayID?) -> NSScreen? {
        guard let displayID else { return NSScreen.main }
        let match = NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }
        return match ?? NSScreen.main
    }
}
