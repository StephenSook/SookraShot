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

/// The clicks captured over one recording, plus its wall-clock length.
public struct RecordingEventLog: Sendable {
    public let clicks: [RecordingClick]
    public let duration: TimeInterval

    public init(clicks: [RecordingClick], duration: TimeInterval) {
        self.clicks = clicks
        self.duration = duration
    }
}

/// Records mouse-click times/positions during a recording so the enhancer can
/// add auto-zoom and click ripples afterwards. Uses a global mouse-down
/// monitor, which needs no extra permission (unlike a keyboard monitor). If the
/// monitor can't be installed, the log is simply empty and the video is
/// unaffected.
@MainActor
public final class RecordingInputMonitor {
    private var startTime: TimeInterval = 0
    private var clicks: [RecordingClick] = []
    private var monitor: Any?

    public init() {}

    public func start() {
        startTime = CACurrentMediaTime()
        clicks.removeAll()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.clicks.append(
                    RecordingClick(time: CACurrentMediaTime() - self.startTime, location: NSEvent.mouseLocation)
                )
            }
        }
    }

    public func stop() -> RecordingEventLog {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        let duration = CACurrentMediaTime() - startTime
        return RecordingEventLog(clicks: clicks, duration: duration)
    }
}
