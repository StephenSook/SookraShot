import AppKit

/// Runs one interactive selection session across all displays.
@MainActor
public final class SelectionOverlayController {
    private var panels: [SelectionPanel] = []
    private var continuation: CheckedContinuation<SelectionResult, Never>?

    public init() {}

    public var isActive: Bool { continuation != nil }

    public func beginSelection() async -> SelectionResult {
        guard continuation == nil else { return .cancelled }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            let snapper = WindowSnapper()
            snapper.refresh()
            for screen in NSScreen.screens {
                let panel = SelectionPanel(screen: screen, snapper: snapper) { [weak self] result in
                    self?.finish(with: result)
                }
                panel.orderFrontRegardless()
                panels.append(panel)
            }
            // Key window follows the mouse's screen so ESC lands where the user is.
            let mouse = NSEvent.mouseLocation
            let target = panels.first { NSMouseInRect(mouse, $0.frame, false) } ?? panels.first
            target?.makeKey()
        }
    }

    private func finish(with result: SelectionResult) {
        guard let continuation else { return }
        self.continuation = nil
        for panel in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()
        continuation.resume(returning: result)
    }
}
