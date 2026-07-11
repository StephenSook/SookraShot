import AppKit

/// Draws the dimmed overlay, tracks drag-selection and window hover-snap.
@MainActor
final class SelectionView: NSView {
    private let screen: NSScreen
    private let snapper: WindowSnapper
    private let onFinish: @MainActor (SelectionResult) -> Void

    private var dragStart: NSPoint?
    private var dragRect: NSRect?
    private var hoveredWindow: SnapWindow?

    init(screen: NSScreen, snapper: WindowSnapper, onFinish: @escaping @MainActor (SelectionResult) -> Void) {
        self.screen = screen
        self.snapper = snapper
        self.onFinish = onFinish
        super.init(frame: screen.frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseMoved, .activeAlways],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: - Mouse

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        guard dragStart == nil else { return }
        let screenPoint = screenPoint(from: event)
        hoveredWindow = snapper.window(at: screenPoint)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        dragRect = nil
    }

    override func mouseDragged(with event: NSEvent) {
        NSCursor.crosshair.set()
        guard let start = dragStart else { return }
        let current = convert(event.locationInWindow, from: nil)
        dragRect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStart = nil
            dragRect = nil
        }
        if let rect = dragRect, rect.width > 4, rect.height > 4 {
            finishArea(with: rect)
        } else if let snapped = hoveredWindow {
            onFinish(.window(windowID: snapped.windowID, scale: screen.backingScaleFactor))
        } else {
            onFinish(.cancelled)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            onFinish(.cancelled)
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - Geometry

    private func screenPoint(from event: NSEvent) -> NSPoint {
        let viewPoint = convert(event.locationInWindow, from: nil)
        return NSPoint(x: viewPoint.x + screen.frame.minX, y: viewPoint.y + screen.frame.minY)
    }

    private func finishArea(with viewRect: NSRect) {
        guard let displayID = screen.displayID else {
            onFinish(.cancelled)
            return
        }
        // View coords share the screen's size with origin at the screen's bottom-left.
        // Convert to display-local coords with origin top-left for sourceRect.
        let rectInDisplay = CGRect(
            x: viewRect.minX,
            y: screen.frame.height - viewRect.maxY,
            width: viewRect.width,
            height: viewRect.height
        )
        onFinish(.area(displayID: displayID, rectInDisplay: rectInDisplay, scale: screen.backingScaleFactor))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()

        let highlight = currentHighlightRect()
        if let highlight {
            highlight.fill(using: .clear)
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: highlight.insetBy(dx: -0.75, dy: -0.75))
            border.lineWidth = 1.5
            border.stroke()
            drawDimensionLabel(for: highlight)
        }
    }

    private func currentHighlightRect() -> NSRect? {
        if let dragRect {
            return dragRect
        }
        if let hoveredWindow {
            // Convert Cocoa global frame to view coords on this screen.
            let local = NSRect(
                x: hoveredWindow.frame.minX - screen.frame.minX,
                y: hoveredWindow.frame.minY - screen.frame.minY,
                width: hoveredWindow.frame.width,
                height: hoveredWindow.frame.height
            )
            return local.intersection(bounds)
        }
        return nil
    }

    private func drawDimensionLabel(for rect: NSRect) {
        let scale = screen.backingScaleFactor
        let text = "\(Int(rect.width * scale)) × \(Int(rect.height * scale))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        let padding: CGFloat = 5
        var origin = NSPoint(x: rect.midX - size.width / 2, y: rect.minY - size.height - 8)
        if origin.y < 4 {
            origin.y = rect.minY + 8
        }
        let background = NSRect(
            x: origin.x - padding,
            y: origin.y - padding / 2,
            width: size.width + padding * 2,
            height: size.height + padding
        )
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: background, xRadius: 4, yRadius: 4).fill()
        text.draw(at: origin, withAttributes: attributes)
    }
}
