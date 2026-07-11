import AppKit

/// Outcome of an interactive selection session.
public enum SelectionResult: Sendable {
    /// Rect is in display-local coordinates (origin top-left, points), ready for SCStreamConfiguration.sourceRect.
    case area(displayID: CGDirectDisplayID, rectInDisplay: CGRect, scale: CGFloat)
    case window(windowID: CGWindowID, scale: CGFloat)
    case cancelled
}

extension NSScreen {
    public var displayID: CGDirectDisplayID? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }
}
