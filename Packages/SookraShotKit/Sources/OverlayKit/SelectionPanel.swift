import AppKit

/// Full-screen transparent draw-only overlay for one display. It never handles
/// mouse events itself (ignoresMouseEvents = true); MouseCaptureTap drives the
/// selection. This is the only reliable way to capture a drag over another app.
@MainActor
final class SelectionPanel: NSPanel {
    let selectionView: SelectionView

    init(screen: NSScreen) {
        self.selectionView = SelectionView(screen: screen)
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        animationBehavior = .none
        ignoresMouseEvents = true // visual only; input comes from the event tap
        contentView = selectionView
        setFrame(screen.frame, display: true)
    }
}
