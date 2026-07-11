import AppKit

/// Runs one interactive selection session across all displays.
@MainActor
public final class SelectionOverlayController {
    private var panels: [SelectionPanel] = []
    private var continuation: CheckedContinuation<SelectionResult, Never>?
    private var previousApp: NSRunningApplication?

    public init() {}

    public var isActive: Bool { continuation != nil }

    public func beginSelection() async -> SelectionResult {
        guard continuation == nil else { return .cancelled }
        previousApp = NSWorkspace.shared.frontmostApplication
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            let snapper = WindowSnapper()
            snapper.refresh()
            for screen in NSScreen.screens {
                let panel = SelectionPanel(screen: screen, snapper: snapper) { [weak self] result in
                    self?.finish(with: result)
                }
                panels.append(panel)
            }

            // Activate the app and make the overlay the key window BEFORE the
            // user clicks. A background (LSUIElement) app's overlay opens
            // inactive, so the first press is an app-activating click — and
            // macOS discards the drag that rides along with an activating
            // click, which is why area-select only worked over the (already
            // frontmost) desktop and never over another app like a browser.
            // With the app active and the panel key up front, the press is a
            // normal drag.
            NSApp.activate(ignoringOtherApps: true)
            let mouse = NSEvent.mouseLocation
            let target = panels.first { NSMouseInRect(mouse, $0.frame, false) } ?? panels.first
            for panel in panels {
                panel.orderFrontRegardless()
            }
            target?.makeKeyAndOrderFront(nil)
        }
    }

    private func finish(with result: SelectionResult) {
        guard let continuation else { return }
        self.continuation = nil
        for panel in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()
        // Return focus to whatever the user was in so copy/paste and drag-out
        // land in the right app.
        previousApp?.activate()
        previousApp = nil
        continuation.resume(returning: result)
    }
}
