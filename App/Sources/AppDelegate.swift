import AppKit
import HotkeyKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var captureCoordinator: CaptureCoordinator?
    private let hotkeyCenter = HotkeyCenter()

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = CaptureCoordinator()
        captureCoordinator = coordinator
        statusItemController = StatusItemController(coordinator: coordinator)
        ScreenRecordingPermission.requestIfNeeded()

        hotkeyCenter.onActivate { action in
            switch action {
            case .captureArea, .allInOne:
                coordinator.captureArea()
            case .captureFullscreen:
                coordinator.captureFullscreen()
            case .captureText:
                // OCR arrives in Phase 3; area capture until then.
                coordinator.captureArea()
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let coordinator = captureCoordinator else { return }
        for url in urls {
            switch url.host() {
            case "capture-area":
                coordinator.captureArea()
            case "capture-fullscreen":
                coordinator.captureFullscreen()
            default:
                NSLog("SookraShot: unhandled URL \(url.absoluteString)")
            }
        }
    }
}
