import AppKit

/// Runs one interactive selection session across all displays, driven by a
/// session-level mouse tap so the drag works over any app.
@MainActor
public final class SelectionOverlayController {
    private var panels: [SelectionPanel] = []
    private var continuation: CheckedContinuation<SelectionResult, Never>?
    private var tap: MouseCaptureTap?
    private var dragStart: CGPoint?          // Cocoa global (bottom-left origin)

    public init() {}

    public var isActive: Bool { continuation != nil }

    /// True if the app can run the mouse tap (Accessibility granted).
    public static var hasPermission: Bool { MouseCaptureTap.isTrusted }

    /// Opens the Accessibility prompt/pane so the user can grant permission.
    public static func requestPermission() { MouseCaptureTap.requestPermission() }

    public func beginSelection() async -> SelectionResult {
        guard continuation == nil else { return .cancelled }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation

            for screen in NSScreen.screens {
                let panel = SelectionPanel(screen: screen)
                panel.orderFrontRegardless()
                panels.append(panel)
            }
            NSCursor.crosshair.set()

            let tap = MouseCaptureTap { [weak self] event in
                // The tap fires on the main runloop; hop into the main actor.
                MainActor.assumeIsolated { self?.handle(event) }
            }
            if tap.start() {
                self.tap = tap
            } else {
                // No Accessibility permission — can't capture. Clean up and
                // report; the caller prompts the user.
                teardownPanels()
                self.continuation = nil
                continuation.resume(returning: .permissionRequired)
            }
        }
    }

    // MARK: - Tap events (points are Cocoa global, bottom-left origin)

    private func handle(_ event: MouseCaptureTap.Event) {
        switch event {
        case .down(let point):
            dragStart = point
            updateSelection(to: point)
        case .dragged(let point):
            updateSelection(to: point)
        case .up(let point):
            finishDrag(at: point)
        case .cancel:
            finish(with: .cancelled)
        }
    }

    private func updateSelection(to point: CGPoint) {
        guard let start = dragStart else { return }
        let globalRect = CGRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: abs(point.x - start.x),
            height: abs(point.y - start.y)
        )
        for panel in panels {
            let screen = panel.selectionView.screen
            let local = NSRect(
                x: globalRect.minX - screen.frame.minX,
                y: globalRect.minY - screen.frame.minY,
                width: globalRect.width,
                height: globalRect.height
            )
            panel.selectionView.selectionRect = local.intersection(panel.selectionView.bounds)
        }
        NSCursor.crosshair.set()
    }

    private func finishDrag(at point: CGPoint) {
        guard let start = dragStart else {
            finish(with: .cancelled)
            return
        }
        let globalRect = CGRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: abs(point.x - start.x),
            height: abs(point.y - start.y)
        )
        guard globalRect.width > 4, globalRect.height > 4,
              let screen = NSScreen.screens.first(where: { NSMouseInRect(NSPoint(x: globalRect.midX, y: globalRect.midY), $0.frame, false) })
                ?? NSScreen.screens.first(where: { $0.frame.intersects(globalRect) }),
              let displayID = screen.displayID else {
            finish(with: .cancelled)
            return
        }
        // Clamp to the screen, then convert Cocoa (bottom-left) to display-local
        // (top-left) for SCStreamConfiguration.sourceRect.
        let clamped = globalRect.intersection(screen.frame)
        let localX = clamped.minX - screen.frame.minX
        let localBottomY = clamped.minY - screen.frame.minY
        let rectInDisplay = CGRect(
            x: localX,
            y: screen.frame.height - localBottomY - clamped.height,
            width: clamped.width,
            height: clamped.height
        )
        finish(with: .area(displayID: displayID, rectInDisplay: rectInDisplay, scale: screen.backingScaleFactor))
    }

    private func finish(with result: SelectionResult) {
        guard let continuation else { return }
        self.continuation = nil
        tap?.stop()
        tap = nil
        dragStart = nil
        teardownPanels()
        continuation.resume(returning: result)
    }

    private func teardownPanels() {
        for panel in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()
    }
}
