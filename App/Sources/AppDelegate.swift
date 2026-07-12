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
        let statusController = StatusItemController(coordinator: coordinator)
        statusItemController = statusController
        coordinator.onRecordingStateChange = { isRecording in
            statusController.setRecording(isRecording)
        }
        ScreenRecordingPermission.requestIfNeeded()

        hotkeyCenter.onActivate { action in
            switch action {
            case .captureArea, .allInOne:
                coordinator.captureArea()
            case .captureFullscreen:
                coordinator.captureFullscreen()
            case .captureText:
                coordinator.captureText()
            case .recordScreen:
                if coordinator.isRecording {
                    coordinator.stopRecording()
                } else {
                    coordinator.recordScreen()
                }
            case .scrollingCapture:
                coordinator.scrollingCapture()
            case .askClaude:
                coordinator.askClaudeArea()
            case .cloudShare:
                coordinator.shareToCloudArea()
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
            case "capture-text":
                coordinator.captureText()
            case "record-screen":
                let micRequested = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.contains { $0.name == "mic" && $0.value == "1" } ?? false
                coordinator.recordDisplayUnderMouse(captureMicrophone: micRequested)
            case "stop-recording":
                coordinator.stopRecording()
            case "scrolling-capture":
                coordinator.scrollingCapture()
            case "ask-claude":
                coordinator.askClaudeArea()
            case "cloud-share":
                coordinator.shareToCloudArea()
            default:
                NSLog("SookraShot: unhandled URL \(url.absoluteString)")
            }
        }
    }
}
