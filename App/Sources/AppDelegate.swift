import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController()
        ScreenRecordingPermission.requestIfNeeded()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // sookrashot:// URL scheme — routed once capture actions exist.
        for url in urls {
            NSLog("SookraShot URL received: \(url.absoluteString)")
        }
    }
}
