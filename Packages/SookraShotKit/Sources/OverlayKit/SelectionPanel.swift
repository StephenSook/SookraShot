import AppKit

/// Full-screen transparent panel hosting the selection view on one display.
/// Non-activating so the app under capture keeps focus.
@MainActor
final class SelectionPanel: NSPanel {
    init(screen: NSScreen, snapper: WindowSnapper, onFinish: @escaping @MainActor (SelectionResult) -> Void) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        acceptsMouseMovedEvents = true
        contentView = SelectionView(screen: screen, snapper: snapper, onFinish: onFinish)
        setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { true }
}
