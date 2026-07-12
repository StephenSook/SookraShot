import AppKit
import CaptureKit
import SharedKit

/// Interactive scrolling-capture session: repeatedly captures the selected
/// region while the user scrolls, stitching frames live. A small HUD offers
/// Done / Cancel. The HUD is our own window, so ScreenCapturer's own-window
/// exclusion keeps it out of the frames.
@MainActor
public final class ScrollCaptureSession {
    private let capturer = ScreenCapturer()
    private let stitcher = ScrollStitcher()
    private var hud: ScrollHUDPanel?
    private var captureTask: Task<Void, Never>?
    private var completion: CheckedContinuation<CGImage?, Never>?
    private var frameCount = 0

    private static let frameInterval: Duration = .milliseconds(350)
    private static let maxFrames = 200
    /// Consecutive frames with no new content before auto-scroll assumes the
    /// end of the page.
    private static let autoStallLimit = 3

    public init() {}

    /// Runs the session; resolves with the stitched image, or nil on cancel.
    /// With `autoScroll`, the session scrolls the region itself and stops at the
    /// end of the content instead of waiting for the user to scroll.
    public func run(
        displayID: CGDirectDisplayID,
        rectInDisplay: CGRect,
        scale: CGFloat,
        autoScroll: Bool = false
    ) async -> CGImage? {
        await withCheckedContinuation { continuation in
            completion = continuation
            presentHUD(displayID: displayID, rectInDisplay: rectInDisplay)
            captureTask = Task { [weak self] in
                await self?.captureLoop(displayID: displayID, rectInDisplay: rectInDisplay, scale: scale, autoScroll: autoScroll)
            }
        }
    }

    private func captureLoop(displayID: CGDirectDisplayID, rectInDisplay: CGRect, scale: CGFloat, autoScroll: Bool) async {
        var isFirst = true
        var stalls = 0
        let scrollPoint = autoScroll ? globalCenter(displayID: displayID, rectInDisplay: rectInDisplay) : nil
        let scrollDelta = Int32(-(rectInDisplay.height * 0.82))

        while !Task.isCancelled, frameCount < Self.maxFrames {
            do {
                let frame = try await capturer.captureRect(rectInDisplay, displayID: displayID, scale: scale)
                if isFirst {
                    stitcher.start(with: frame)
                    isFirst = false
                } else {
                    switch stitcher.append(frame) {
                    case .appended:
                        frameCount += 1
                        hud?.update(frames: frameCount)
                        stalls = 0
                    case .noNewContent, .lowConfidence:
                        if autoScroll { stalls += 1 }
                    }
                }
            } catch {
                NSLog("SookraShot scroll frame failed: \(error)")
            }

            if autoScroll {
                if stalls >= Self.autoStallLimit { break }
                if let scrollPoint { postScroll(at: scrollPoint, delta: scrollDelta) }
            }
            try? await Task.sleep(for: Self.frameInterval)
        }

        if autoScroll {
            finish(cancelled: false)
        }
    }

    /// Region center in global (top-left origin) display coordinates.
    private func globalCenter(displayID: CGDirectDisplayID, rectInDisplay: CGRect) -> CGPoint {
        let bounds = CGDisplayBounds(displayID)
        return CGPoint(x: bounds.minX + rectInDisplay.midX, y: bounds.minY + rectInDisplay.midY)
    }

    /// Posts a scroll-wheel event over the region (needs the Accessibility grant
    /// we already have for the selection tap).
    private func postScroll(at point: CGPoint, delta: Int32) {
        CGWarpMouseCursorPosition(point)
        if let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0) {
            event.post(tap: .cgSessionEventTap)
        }
    }

    private func presentHUD(displayID: CGDirectDisplayID, rectInDisplay: CGRect) {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        } ?? NSScreen.main
        guard let screen else { return }

        // Display-local top-left rect -> Cocoa global coords.
        let selectionBottomY = screen.frame.maxY - rectInDisplay.maxY
        let selectionMidX = screen.frame.minX + rectInDisplay.midX

        let hud = ScrollHUDPanel(
            onDone: { [weak self] in self?.finish(cancelled: false) },
            onCancel: { [weak self] in self?.finish(cancelled: true) }
        )
        var origin = NSPoint(x: selectionMidX - hud.frame.width / 2, y: selectionBottomY - hud.frame.height - 12)
        let visible = screen.visibleFrame
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - hud.frame.width - 8)
        origin.y = max(origin.y, visible.minY + 8)
        hud.setFrameOrigin(origin)
        hud.orderFrontRegardless()
        self.hud = hud
    }

    private func finish(cancelled: Bool) {
        captureTask?.cancel()
        captureTask = nil
        hud?.orderOut(nil)
        hud = nil
        let image = cancelled ? nil : stitcher.finish()
        completion?.resume(returning: image)
        completion = nil
    }
}

/// Small non-activating control panel shown under the selection.
@MainActor
final class ScrollHUDPanel: NSPanel {
    private let framesLabel = NSTextField(labelWithString: "Scroll the content…")

    init(onDone: @escaping @MainActor () -> Void, onCancel: @escaping @MainActor () -> Void) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        let background = NSVisualEffectView(frame: contentRect(forFrameRect: frame))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10

        framesLabel.font = .systemFont(ofSize: 11)
        framesLabel.textColor = .secondaryLabelColor

        let doneButton = NSButton(title: "Done", target: nil, action: nil)
        doneButton.bezelStyle = .push
        doneButton.controlSize = .small
        doneButton.keyEquivalent = "\r"
        let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
        cancelButton.bezelStyle = .push
        cancelButton.controlSize = .small

        self.doneHandler = onDone
        self.cancelHandler = onCancel
        doneButton.target = self
        doneButton.action = #selector(doneTapped)
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)

        let stack = NSStackView(views: [framesLabel, cancelButton, doneButton])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        stack.frame = background.bounds
        stack.autoresizingMask = [.width, .height]
        background.addSubview(stack)
        contentView = background
    }

    private var doneHandler: (@MainActor () -> Void)?
    private var cancelHandler: (@MainActor () -> Void)?

    @objc private func doneTapped() { doneHandler?() }
    @objc private func cancelTapped() { cancelHandler?() }

    func update(frames: Int) {
        framesLabel.stringValue = "Captured \(frames) segments"
    }
}
