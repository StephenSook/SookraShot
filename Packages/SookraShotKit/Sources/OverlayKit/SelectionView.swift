import AppKit

/// Draw-only dimmed overlay for one display. Input comes from MouseCaptureTap
/// (via SelectionOverlayController), not from this view's own mouse handling —
/// that's the only way to reliably capture a drag over another app.
@MainActor
final class SelectionView: NSView {
    let screen: NSScreen

    /// Current selection rectangle in this view's coordinates (bottom-left
    /// origin), or nil when nothing is drawn on this screen.
    var selectionRect: NSRect? {
        didSet { needsDisplay = true }
    }

    init(screen: NSScreen) {
        self.screen = screen
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()

        guard let rect = selectionRect, rect.width > 0, rect.height > 0 else { return }
        rect.fill(using: .clear)
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: rect.insetBy(dx: -0.75, dy: -0.75))
        border.lineWidth = 1.5
        border.stroke()
        drawDimensionLabel(for: rect)
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
