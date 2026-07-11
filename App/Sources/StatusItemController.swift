import AppKit

@MainActor
final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?
    private let coordinator: CaptureCoordinator

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
        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "camera.viewfinder",
                accessibilityDescription: "SookraShot"
            )
            image?.isTemplate = true
            button.image = image
        }
        item.menu = buildMenu()
        statusItem = item
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
        menu.addItem(actionItem("Capture Area", #selector(captureArea)))
        menu.addItem(actionItem("Capture Fullscreen", #selector(captureFullscreen)))
        menu.addItem(actionItem("Capture Text (OCR)", #selector(captureText)))
        menu.addItem(.separator())

        if !ScreenRecordingPermission.granted {
            menu.addItem(actionItem("Grant Screen Recording Access…", #selector(openScreenRecordingSettings)))
            menu.addItem(.separator())
        }

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

    @objc private func captureFullscreen() {
        coordinator.captureFullscreen()
    }

    @objc private func captureText() {
        coordinator.captureText()
    }

    @objc private func openScreenRecordingSettings() {
        ScreenRecordingPermission.openSystemSettings()
    }
}
