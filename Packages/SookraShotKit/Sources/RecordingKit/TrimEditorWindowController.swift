import AVFoundation
import AVKit
import AppKit
import SharedKit

/// A simple trim window: plays the recording in an AVPlayerView and uses the
/// native QuickTime-style trimming UI, then exports the chosen range.
@MainActor
public final class TrimEditorWindowController: NSWindowController {
    private let sourceURL: URL
    private let player: AVPlayer
    private let playerView = AVPlayerView()
    private let trimmer = VideoTrimmer()
    private let statusLabel = NSTextField(labelWithString: "")
    private let trimButton = NSButton(title: "Start Trimming", target: nil, action: nil)
    private var statusObservation: NSKeyValueObservation?
    private var exportTask: Task<Void, Never>?

    public static func present(url: URL) {
        let controller = TrimEditorWindowController(url: url)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    public init(url: URL) {
        sourceURL = url
        player = AVPlayer(url: url)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Trim \(url.lastPathComponent)"
        window.center()
        super.init(window: window)
        buildUI()
        observeReadiness()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    private func buildUI() {
        playerView.player = player
        playerView.controlsStyle = .floating
        playerView.translatesAutoresizingMaskIntoConstraints = false

        trimButton.target = self
        trimButton.action = #selector(startTrimming)
        trimButton.isEnabled = false
        statusLabel.textColor = .secondaryLabelColor

        let bar = NSStackView(views: [trimButton, statusLabel, NSView()])
        bar.orientation = .horizontal
        bar.spacing = 12
        bar.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        bar.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(playerView)
        content.addSubview(bar)
        window?.contentView = content

        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: content.topAnchor),
            playerView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.topAnchor.constraint(equalTo: playerView.bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func observeReadiness() {
        statusObservation = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let ready = item.status == .readyToPlay
            Task { @MainActor in
                guard let self else { return }
                self.trimButton.isEnabled = ready && self.playerView.canBeginTrimming
                if ready, self.statusLabel.stringValue.isEmpty {
                    self.statusLabel.stringValue = "Drag the yellow handles, then click Trim."
                }
            }
        }
    }

    @objc private func startTrimming() {
        guard playerView.canBeginTrimming else {
            NSSound.beep()
            return
        }
        playerView.beginTrimming { [weak self] result in
            guard result == .okButton else { return }
            Task { @MainActor in
                guard let self, let item = self.player.currentItem else { return }
                self.export(item: item)
            }
        }
    }

    private func export(item: AVPlayerItem) {
        let start = item.reversePlaybackEndTime
        let end = item.forwardPlaybackEndTime
        let rangeStart = start.isNumeric ? start : .zero
        let rangeEnd = end.isNumeric ? end : item.duration
        guard rangeEnd > rangeStart else {
            NSSound.beep()
            return
        }
        let range = CMTimeRange(start: rangeStart, end: rangeEnd)

        trimButton.isEnabled = false
        statusLabel.stringValue = "Exporting trimmed clip…"
        let source = sourceURL

        exportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let directory = AppSettings.shared.saveDirectory
                let base = source.deletingPathExtension().lastPathComponent + " trimmed"
                let output = try await self.trimmer.export(
                    source: source, timeRange: range, toDirectory: directory, baseName: base
                )
                self.statusLabel.stringValue = "Saved \(output.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([output])
            } catch {
                self.statusLabel.stringValue = "Export failed."
                NSLog("SookraShot trim export failed: \(error)")
                NSSound.beep()
                self.trimButton.isEnabled = true
            }
        }
    }
}
