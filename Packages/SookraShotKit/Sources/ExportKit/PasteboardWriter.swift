import AppKit
import SharedKit

public enum PasteboardWriter {
    /// Puts the capture on the general pasteboard as PNG + TIFF flavors.
    @MainActor
    public static func copy(_ capture: DeliveredCapture) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let encoder = ImageEncoder()
        if let png = encoder.data(from: capture.image, format: .png) {
            pasteboard.setData(png, forType: .png)
        }
        let rep = NSBitmapImageRep(cgImage: capture.image)
        if let tiff = rep.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }
}
