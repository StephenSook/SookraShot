import AppKit
import ApplicationServices
import CoreGraphics

/// Captures mouse (and Esc) at the session level so region selection works over
/// ANY app, regardless of which app is active.
///
/// A window-based overlay cannot reliably grab the drag from a menu-bar
/// (.accessory) app on macOS 14+: the OS only routes the continuous drag to the
/// genuinely-active app, and a background app can't reliably become active over
/// a normal app. A CGEvent tap sidesteps this entirely. Left mouse down/drag/up
/// are CONSUMED during selection so the app underneath never reacts (no stray
/// link clicks or text selection). Requires Accessibility permission.
@MainActor
final class MouseCaptureTap {
    enum Event: Sendable {
        case down(CGPoint)     // Cocoa global (bottom-left origin)
        case dragged(CGPoint)
        case up(CGPoint)
        case cancel            // Esc
    }

    // Accessed from the tap callback (runs on the main runloop this is created on).
    nonisolated(unsafe) private var tap: CFMachPort?
    nonisolated(unsafe) private var source: CFRunLoopSource?
    private nonisolated let onEvent: @Sendable (Event) -> Void
    private nonisolated let mainDisplayHeight: CGFloat

    init(onEvent: @escaping @Sendable (Event) -> Void) {
        self.onEvent = onEvent
        // CGEvent uses a top-left origin off the main display; Cocoa uses
        // bottom-left. Flip around the main display's height.
        self.mainDisplayHeight = NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height
            ?? NSScreen.main?.frame.height ?? 0
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([key: kCFBooleanTrue as Any] as CFDictionary)
    }

    /// Starts the tap. Returns false if permission is missing (tapCreate fails).
    func start() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<MouseCaptureTap>.fromOpaque(refcon).takeUnretainedValue()
                return tap.handle(type: type, event: event)
            },
            userInfo: refcon
        ) else {
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        tap = nil
        source = nil
    }

    // Runs on the main runloop (source added on main). Returns nil to consume.
    private nonisolated func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            if event.getIntegerValueField(.keyboardEventKeycode) == 53 { // Esc
                onEvent(.cancel)
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        let cocoa = CGPoint(x: event.location.x, y: mainDisplayHeight - event.location.y)
        switch type {
        case .leftMouseDown:
            onEvent(.down(cocoa))
            return nil
        case .leftMouseDragged:
            onEvent(.dragged(cocoa))
            return nil
        case .leftMouseUp:
            onEvent(.up(cocoa))
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
