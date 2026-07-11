import AppKit

/// Full-screen transparent overlay window hosting the selection view on one
/// display.
///
/// A plain activating window (NOT a nonactivating panel) that becomes key AND
/// main. Instrumentation proved a nonactivating panel receives the mouseDown
/// but loses key the instant the drag starts (the app isn't truly active), so
/// the drag stream drops after one stray event. Genuine app activation
/// (.regular + activate in the controller) keeps this window key for the whole
/// press-drag-release, which is what actually delivers a continuous drag.
@MainActor
final class SelectionPanel: NSWindow {
    init(screen: NSScreen, snapper: WindowSnapper, onFinish: @escaping @MainActor (SelectionResult) -> Void) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
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
        acceptsMouseMovedEvents = true
        contentView = SelectionView(screen: screen, snapper: snapper, onFinish: onFinish)
        setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
