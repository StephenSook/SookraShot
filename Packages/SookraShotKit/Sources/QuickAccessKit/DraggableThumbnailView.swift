import AppKit
import ExportKit
import SharedKit
import UniformTypeIdentifiers

/// One dragged item that advertises the capture three ways at once, so it lands
/// in every kind of drop target: a concrete file URL (Finder, folders, browser
/// upload wells), inline PNG, and inline TIFF (text views, Mail/Notes/Slack
/// compose, image wells). A file-promise-only drag (the previous approach) only
/// satisfied receivers that implement promise reading, which is why dropping
/// into a text box did nothing.
final class CaptureDragWriter: NSObject, NSPasteboardWriting, @unchecked Sendable {
    let fileURL: URL
    let pngData: Data
    let tiffData: Data

    init(fileURL: URL, pngData: Data, tiffData: Data) {
        self.fileURL = fileURL
        self.pngData = pngData
        self.tiffData = tiffData
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.fileURL, .png, .tiff]
    }

    func writingOptions(
        forType type: NSPasteboard.PasteboardType,
        pasteboard: NSPasteboard
    ) -> NSPasteboard.WritingOptions {
        []
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type {
        case .fileURL: return (fileURL as NSURL).pasteboardPropertyList(forType: .fileURL)
        case .png: return pngData
        case .tiff: return tiffData
        default: return nil
        }
    }
}

/// Builds the drag payload for a capture: encodes PNG + TIFF and writes the PNG
/// to a uniquely-named temp file using the capture's suggested filename, so a
/// Finder/folder drop copies out a sensibly-named `.png`. Pure and reusable so
/// the pasteboard content can be unit-tested without a live drag.
enum CaptureDrag {
    static func makeWriter(for capture: DeliveredCapture) -> CaptureDragWriter? {
        guard let pngData = ImageEncoder().data(from: capture.image, format: .png) else { return nil }
        let rep = NSBitmapImageRep(cgImage: capture.image)
        let tiffData = rep.tiffRepresentation ?? pngData

        let filename = CaptureSaver().suggestedFilename(for: capture, format: .png)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SookraShotDrag", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appendingPathComponent(filename)
            try pngData.write(to: fileURL)
            return CaptureDragWriter(fileURL: fileURL, pngData: pngData, tiffData: tiffData)
        } catch {
            return nil
        }
    }
}

/// Thumbnail that can be dragged into any app. The drag carries a real PNG file
/// plus inline image data, so it drops into Finder, folders, upload fields, and
/// text/compose views alike.
@MainActor
final class DraggableThumbnailView: NSImageView, NSDraggingSource {
    private let capture: DeliveredCapture
    private var mouseDownLocation: NSPoint?
    /// The temp directory holding the current drag's eager PNG, removed when the
    /// session ends so captures never linger on disk after a canceled or
    /// image-only drop.
    private var activeDragDirectory: URL?

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

        guard let writer = CaptureDrag.makeWriter(for: capture) else { return }
        activeDragDirectory = writer.fileURL.deletingLastPathComponent()
        let item = NSDraggingItem(pasteboardWriter: writer)
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    nonisolated func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    /// A `.copy` receiver reads the file URL synchronously during the drop, which
    /// completes before the session ends, so removing the temp dir here is safe
    /// and keeps captures from accumulating in the temp directory.
    nonisolated func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        MainActor.assumeIsolated {
            if let directory = activeDragDirectory {
                try? FileManager.default.removeItem(at: directory)
                activeDragDirectory = nil
            }
        }
    }
}
