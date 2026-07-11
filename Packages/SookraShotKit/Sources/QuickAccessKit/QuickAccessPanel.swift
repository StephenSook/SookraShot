import AppKit
import SharedKit

/// Non-activating floating panel hosting the capture card stack.
/// Configured so it never steals focus from the app the user is working in.
@MainActor
final class QuickAccessPanel: NSPanel {
    private let stack = NSStackView()

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        becomesKeyOnlyIfNeeded = true

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        contentView = stack
    }

    override var canBecomeKey: Bool { false }

    func setCards(
        _ cards: [CaptureCardView],
        corner: OverlayCorner,
        on screen: NSScreen,
        animateNewest: Bool
    ) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for card in cards {
            stack.addArrangedSubview(card)
        }
        stack.layoutSubtreeIfNeeded()
        let size = stack.fittingSize

        let inset: CGFloat = 16
        let visible = screen.visibleFrame
        var origin = NSPoint.zero
        switch corner {
        case .bottomLeft:
            origin = NSPoint(x: visible.minX + inset, y: visible.minY + inset)
        case .bottomRight:
            origin = NSPoint(x: visible.maxX - size.width - inset, y: visible.minY + inset)
        case .topLeft:
            origin = NSPoint(x: visible.minX + inset, y: visible.maxY - size.height - inset)
        case .topRight:
            origin = NSPoint(x: visible.maxX - size.width - inset, y: visible.maxY - size.height - inset)
        }
        setFrame(NSRect(origin: origin, size: size), display: true)

        if animateNewest, let newest = cards.first {
            slideIn(newest, fromLeft: corner == .bottomLeft || corner == .topLeft)
        }
    }

    private func slideIn(_ card: CaptureCardView, fromLeft: Bool) {
        guard let layer = card.layer else { return }
        let offset = (card.fittingSize.width + 40) * (fromLeft ? -1 : 1)
        let spring = CASpringAnimation(keyPath: "transform.translation.x")
        spring.fromValue = offset
        spring.toValue = 0
        spring.stiffness = 280
        spring.damping = 24
        spring.mass = 1
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "slideIn")
    }
}
