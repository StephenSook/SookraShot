import AppKit

struct SnapWindow {
    let windowID: CGWindowID
    /// Cocoa global coordinates (origin bottom-left of primary display).
    let frame: NSRect
}

/// Enumerates on-screen windows for hover-snap during selection.
/// Uses CGWindowListCopyWindowInfo — still available; only titles need extra TCC.
@MainActor
final class WindowSnapper {
    private(set) var windows: [SnapWindow] = []

    func refresh() {
        guard let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            windows = []
            return
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        windows = info.compactMap { entry in
            guard
                let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                let pid = entry[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                let number = entry[kCGWindowNumber as String] as? UInt32,
                let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                let cgRect = CGRect(dictionaryRepresentation: boundsDict),
                cgRect.width > 40, cgRect.height > 40
            else { return nil }
            let cocoaFrame = NSRect(
                x: cgRect.minX,
                y: primaryHeight - cgRect.maxY,
                width: cgRect.width,
                height: cgRect.height
            )
            return SnapWindow(windowID: CGWindowID(number), frame: cocoaFrame)
        }
    }

    /// Topmost window containing the point (list order is front-to-back).
    func window(at pointInScreen: NSPoint) -> SnapWindow? {
        windows.first { $0.frame.contains(pointInScreen) }
    }
}
