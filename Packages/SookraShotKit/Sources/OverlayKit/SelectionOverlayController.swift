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

            // Genuinely activate the app and make the overlay key+main so it
            // holds key for the ENTIRE press-drag-release. A nonactivating
            // panel drops the drag stream after one event (proven by
            // instrumentation); only real activation keeps the key window
            // through the drag. Flip to .regular so an .accessory app is
            // actually allowed to take focus; restored in finish().
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            let mouse = NSEvent.mouseLocation
            let target = panels.first { NSMouseInRect(mouse, $0.frame, false) } ?? panels.first
            for panel in panels {
                panel.orderFrontRegardless()
            }
            target?.makeKeyAndOrderFront(nil)
            target?.makeMain()
            if let view = target?.contentView {
                target?.makeFirstResponder(view)
            }
        }
    }

    private func finish(with result: SelectionResult) {
        guard let continuation else { return }
        self.continuation = nil
        for panel in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()
        NSApp.setActivationPolicy(.accessory)
        previousApp?.activate()
        previousApp = nil
        continuation.resume(returning: result)
    }
}
