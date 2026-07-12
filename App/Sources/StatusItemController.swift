import AppKit

@MainActor
final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?
    private let coordinator: CaptureCoordinator
    private var isRecording = false

    init(coordinator: CaptureCoordinator) {
        self.coordinator = coordinator
        super.init()
        installStatusItem()
        // macOS 26 has open reports of third-party status items intermittently
        // vanishing; re-install if the button lost its window after a display change.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        refreshAppearance()
    }

    func setRecording(_ recording: Bool) {
        isRecording = recording
        refreshAppearance()
    }

    private func refreshAppearance() {
        guard let item = statusItem else { return }
        if let button = item.button {
            let symbol = isRecording ? "stop.circle.fill" : "camera.viewfinder"
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "SookraShot")
            image?.isTemplate = true
            button.image = image
        }
        item.menu = buildMenu()
    }

    @objc private func screenParametersChanged() {
        if statusItem?.button?.window == nil {
            statusItem = nil
            installStatusItem()
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // No keyEquivalents here — global hotkeys own the shortcuts; menu
        // equivalents would double-fire when the app is active.
        if isRecording {
            menu.addItem(actionItem("Stop Recording", #selector(stopRecording)))
            menu.addItem(.separator())
        } else {
            menu.addItem(actionItem("Capture Area", #selector(captureArea)))
            menu.addItem(actionItem("Capture Previous Area", #selector(capturePreviousArea)))
            menu.addItem(actionItem("Capture Fullscreen", #selector(captureFullscreen)))
            menu.addItem(actionItem("Capture Text (OCR)", #selector(captureText)))
            menu.addItem(actionItem("Scrolling Capture", #selector(scrollingCapture)))
            menu.addItem(actionItem("Ask Claude About a Capture", #selector(askClaude)))
            menu.addItem(actionItem("Share Capture as Link", #selector(shareToCloud)))
            menu.addItem(actionItem("Sample Color (hex)", #selector(sampleColor)))
            menu.addItem(.separator())
            menu.addItem(actionItem("Record Screen", #selector(recordScreen)))
            menu.addItem(actionItem("Record GIF", #selector(recordGIF)))
            menu.addItem(actionItem("Trim a Video…", #selector(trimVideo)))
            menu.addItem(.separator())
        }

        if !ScreenRecordingPermission.granted {
            menu.addItem(actionItem("Grant Screen Recording Access…", #selector(openScreenRecordingSettings)))
            menu.addItem(.separator())
        }

        menu.addItem(actionItem("Open History Folder", #selector(openHistory)))
        menu.addItem(actionItem("Close All Pins", #selector(closeAllPins)))
        menu.addItem(actionItem("Settings…", #selector(openSettings)))
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit SookraShot",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        return menu
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func captureArea() {
        coordinator.captureArea()
    }

    @objc private func capturePreviousArea() {
        coordinator.capturePreviousArea()
    }

    @objc private func sampleColor() {
        coordinator.sampleColor()
    }

    @objc private func captureFullscreen() {
        coordinator.captureFullscreen()
    }

    @objc private func captureText() {
        coordinator.captureText()
    }

    @objc private func recordScreen() {
        coordinator.recordScreen()
    }

    @objc private func scrollingCapture() {
        coordinator.scrollingCapture()
    }

    @objc private func askClaude() {
        coordinator.askClaudeArea()
    }

    @objc private func shareToCloud() {
        coordinator.shareToCloudArea()
    }

    @objc private func recordGIF() {
        coordinator.recordScreen(asGIF: true)
    }

    @objc private func trimVideo() {
        coordinator.openTrimEditor()
    }

    @objc private func stopRecording() {
        coordinator.stopRecording()
    }

    @objc private func openHistory() {
        NSWorkspace.shared.activateFileViewerSelecting([coordinator.historyDirectory])
    }

    @objc private func closeAllPins() {
        coordinator.closeAllPins()
    }

    @objc private func openSettings() {
        SettingsWindowController.present()
    }

    @objc private func openScreenRecordingSettings() {
        ScreenRecordingPermission.openSystemSettings()
    }
}
