import AppKit

@MainActor
final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?

    override init() {
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

        for title in ["Capture Area", "Capture Window", "Capture Fullscreen"] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())

        if !ScreenRecordingPermission.granted {
            let permissionItem = NSMenuItem(
                title: "Grant Screen Recording Access…",
                action: #selector(openScreenRecordingSettings),
                keyEquivalent: ""
            )
            permissionItem.target = self
            menu.addItem(permissionItem)
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

    @objc private func openScreenRecordingSettings() {
        ScreenRecordingPermission.openSystemSettings()
    }
}
