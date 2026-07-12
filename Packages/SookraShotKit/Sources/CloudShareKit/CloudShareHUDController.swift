import AppKit
import SharedKit
import SwiftUI

/// Owns the floating cloud-share HUD panel and kicks off the upload.
@MainActor
public final class CloudShareHUDController {
    private var panel: NSPanel?

    /// Set by the app so the HUD's "Settings…" buttons can open the window.
    public var onOpenSettings: (() -> Void)?

    public init() {}

    public func present(_ capture: DeliveredCapture) {
        let model = CloudShareModel(capture: capture)
        model.onOpenSettings = { [weak self] in self?.onOpenSettings?() }
        let hosting = NSHostingController(rootView: CloudShareView(model: model))
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentViewController = hosting
        position(panel, for: capture)
        panel.makeKeyAndOrderFront(nil)
        model.start()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 160),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Cloud Share"
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
