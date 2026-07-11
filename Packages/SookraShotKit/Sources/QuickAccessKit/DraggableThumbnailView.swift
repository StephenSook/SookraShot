import AppKit
import ExportKit
import SharedKit
import UniformTypeIdentifiers

/// Thumbnail that can be dragged into any app. Uses an NSFilePromiseProvider,
/// so the PNG is only rendered to disk when a drop actually happens.
@MainActor
final class DraggableThumbnailView: NSImageView, NSDraggingSource {
    private let capture: DeliveredCapture
    private var mouseDownLocation: NSPoint?

    init(capture: DeliveredCapture) {
        self.capture = capture
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

    /// The Quick Access panel is a non-activating background-app window, so the
    /// first click that starts a drag-out lands while another app is frontmost.
    /// Same first-mouse rule as the selection overlay: accept it so the drag
    /// begins on the first click instead of just activating the window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation else { return }
        let current = convert(event.locationInWindow, from: nil)
        guard hypot(current.x - start.x, current.y - start.y) > 4 else { return }
        mouseDownLocation = nil

        let provider = NSFilePromiseProvider(
            fileType: UTType.png.identifier,
            delegate: CapturePromiseDelegate(capture: capture)
        )
        let item = NSDraggingItem(pasteboardWriter: provider)
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    nonisolated func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }
}

/// Fulfils the file promise off-main when the drop lands.
final class CapturePromiseDelegate: NSObject, NSFilePromiseProviderDelegate, @unchecked Sendable {
    private let capture: DeliveredCapture
    private let workQueue = OperationQueue()

    init(capture: DeliveredCapture) {
        self.capture = capture
    }

    func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        CaptureSaver().suggestedFilename(for: capture, format: .png)
    }

    func operationQueue(for provider: NSFilePromiseProvider) -> OperationQueue {
        workQueue
    }

    func filePromiseProvider(
        _ provider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let data = ImageEncoder().data(from: capture.image, format: .png) else {
            completionHandler(SaveError.encodingFailed)
            return
        }
        do {
            try data.write(to: url)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
}
