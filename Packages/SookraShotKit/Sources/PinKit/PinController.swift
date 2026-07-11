import AppKit
import ExportKit
import SharedKit

/// Pinned always-on-top screenshots: draggable, scroll to change opacity,
/// double-click to close.
@MainActor
public final class PinController {
    private var pins: [PinPanel] = []

    public init() {}

    public func pin(_ capture: DeliveredCapture) {
        let panel = PinPanel(capture: capture) { [weak self] panel in
            self?.pins.removeAll { $0 === panel }
        }
        // Center on the mouse's screen, slightly offset per existing pin count.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let screen {
            let offset = CGFloat(pins.count % 6) * 24
            let origin = NSPoint(
                x: screen.visibleFrame.midX - panel.frame.width / 2 + offset,
                y: screen.visibleFrame.midY - panel.frame.height / 2 - offset
            )
            panel.setFrameOrigin(origin)
        }
        panel.orderFrontRegardless()
        pins.append(panel)
    }

    public func closeAll() {
        for pin in pins {
            pin.orderOut(nil)
        }
        pins.removeAll()
    }
}

@MainActor
final class PinPanel: NSPanel {
    private let onClose: @MainActor (PinPanel) -> Void
    private let capture: DeliveredCapture

    init(capture: DeliveredCapture, onClose: @escaping @MainActor (PinPanel) -> Void) {
        self.capture = capture
        self.onClose = onClose

        let maxSide: CGFloat = 480
        let width = CGFloat(capture.image.width)
        let height = CGFloat(capture.image.height)
        let scale = min(maxSide / width, maxSide / height, 0.5)
        let size = NSSize(width: max(width * scale, 100), height: max(height * scale, 60))

        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = true

        let imageView = PinImageView(capture: capture) { [weak self] in
            guard let self else { return }
            self.orderOut(nil)
            self.onClose(self)
        }
        imageView.frame = NSRect(origin: .zero, size: size)
        imageView.autoresizingMask = [.width, .height]
        contentView = imageView
    }

    override var canBecomeKey: Bool { false }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY / 300
        alphaValue = min(max(alphaValue - delta, 0.2), 1.0)
    }
}

@MainActor
private final class PinImageView: NSImageView {
    private let capture: DeliveredCapture
    private let onClose: @MainActor () -> Void

    init(capture: DeliveredCapture, onClose: @escaping @MainActor () -> Void) {
        self.capture = capture
        self.onClose = onClose
        super.init(frame: .zero)
        image = NSImage(cgImage: capture.image, size: .zero)
        imageScaling = .scaleProportionallyUpOrDown
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        unregisterDraggedTypes()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onClose()
            return
        }
        super.mouseDown(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        onClose()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let copyItem = NSMenuItem(title: "Copy", action: #selector(copyPin), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)
        let closeItem = NSMenuItem(title: "Close", action: #selector(closePin), keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)
        return menu
    }

    @objc private func copyPin() {
        PasteboardWriter.copy(capture)
    }

    @objc private func closePin() {
        onClose()
    }
}
