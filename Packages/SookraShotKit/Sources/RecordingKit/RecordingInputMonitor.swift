import AppKit
import QuartzCore

/// One click captured during a recording, timed from the recording start.
public struct RecordingClick: Sendable {
    public let time: TimeInterval
    /// Global screen location in Cocoa (bottom-left origin) points.
    public let location: CGPoint

    public init(time: TimeInterval, location: CGPoint) {
        self.time = time
        self.location = location
    }
}

/// One key press captured during a recording, as a display string (e.g. "⌘C").
public struct RecordingKeystroke: Sendable {
    public let time: TimeInterval
    public let display: String

    public init(time: TimeInterval, display: String) {
        self.time = time
        self.display = display
    }

    /// Builds a compact display string from a key event's fields (pure, so it
    /// can be unit-tested without an NSEvent).
    public static func displayString(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        characters: String?
    ) -> String? {
        var prefix = ""
        if modifiers.contains(.control) { prefix += "⌃" }
        if modifiers.contains(.option) { prefix += "⌥" }
        if modifiers.contains(.shift) { prefix += "⇧" }
        if modifiers.contains(.command) { prefix += "⌘" }

        let special: [UInt16: String] = [
            36: "⏎", 76: "⏎", 48: "⇥", 49: "␣", 51: "⌫", 117: "⌦",
            53: "⎋", 123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        let key: String
        if let symbol = special[keyCode] {
            key = symbol
        } else {
            let text = (characters ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            key = text.count == 1 ? text.uppercased() : text
        }
        return prefix + key
    }
}

/// The clicks and keystrokes captured over one recording, plus its length.
public struct RecordingEventLog: Sendable {
    public let clicks: [RecordingClick]
    public let keystrokes: [RecordingKeystroke]
    public let duration: TimeInterval

    public init(clicks: [RecordingClick], keystrokes: [RecordingKeystroke], duration: TimeInterval) {
        self.clicks = clicks
        self.keystrokes = keystrokes
        self.duration = duration
    }
}

/// Records mouse clicks (and optionally keystrokes) during a recording so the
/// enhancer can add auto-zoom, click ripples, and a keystroke overlay. Uses
/// global `NSEvent` monitors, which need only the Accessibility grant already
/// held for the selection tap. If a monitor can't install, its log is empty and
/// the video is unaffected.
@MainActor
public final class RecordingInputMonitor {
    private var startTime: TimeInterval = 0
    private var clicks: [RecordingClick] = []
    private var keystrokes: [RecordingKeystroke] = []
    private var mouseMonitor: Any?
    private var keyMonitor: Any?

    public init() {}

    public func start(captureKeystrokes: Bool = false) {
        removeMonitors()  // clear any prior run so tokens are never leaked
        startTime = CACurrentMediaTime()
        clicks.removeAll()
        keystrokes.removeAll()

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.clicks.append(
                    RecordingClick(time: CACurrentMediaTime() - self.startTime, location: NSEvent.mouseLocation)
                )
            }
        }

        guard captureKeystrokes else { return }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let display = RecordingKeystroke.displayString(
                    keyCode: event.keyCode, modifiers: event.modifierFlags, characters: event.charactersIgnoringModifiers
                ) else { return }
                self.keystrokes.append(RecordingKeystroke(time: CACurrentMediaTime() - self.startTime, display: display))
            }
        }
    }

    public func stop() -> RecordingEventLog {
        removeMonitors()
        let duration = CACurrentMediaTime() - startTime
        return RecordingEventLog(clicks: clicks, keystrokes: keystrokes, duration: duration)
    }

    private func removeMonitors() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        mouseMonitor = nil
        keyMonitor = nil
    }
}
