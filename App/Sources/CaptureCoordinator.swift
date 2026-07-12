import AIKit
import AnnotationKit
import AppKit
import CaptureKit
import OCRKit
import HistoryKit
import OverlayKit
import PinKit
import QuickAccessKit
import RecordingKit
import ScrollCaptureKit
import SharedKit

/// Routes capture triggers (menu, hotkeys, URL scheme) through selection and capture.
@MainActor
final class CaptureCoordinator {
    private let capturer = ScreenCapturer()
    private let overlay = SelectionOverlayController()
    private let quickAccess = QuickAccessController()
    private let recorder = ScreenRecorder()
    private var exportAsGIF = false
    private var scrollSession: ScrollCaptureSession?
    private let pins = PinController()
    private let history = HistoryStore()
    private let askClaudePanel = AskClaudePanelController()

    var onRecordingStateChange: (@MainActor (Bool) -> Void)? {
        get { recorder.onStateChange }
        set { recorder.onStateChange = newValue }
    }

    var isRecording: Bool { recorder.isRecording }

    init() {
        quickAccess.onAnnotate = { capture in
            AnnotationEditorWindowController.present(capture: capture)
        }
        quickAccess.onPin = { [weak self] capture in
            self?.pins.pin(capture)
        }
        quickAccess.onAskClaude = { [weak self] capture in
            self?.askClaude(about: capture)
        }
    }

    var historyDirectory: URL { history.directory }

    func closeAllPins() {
        pins.closeAll()
    }

    /// The mouse tap needs Accessibility. Trigger the system prompt (adds
    /// SookraShot to the Accessibility list and offers to open System Settings).
    private func showAccessibilityAlert() {
        SelectionOverlayController.requestPermission()
    }

    // MARK: - Scrolling capture

    /// Select a region, then capture-and-stitch while the user scrolls.
    func scrollingCapture() {
        guard !overlay.isActive, scrollSession == nil, !recorder.isRecording else { return }
        Task { await runScrollCapture() }
    }

    private func runScrollCapture() async {
        let result = await overlay.beginSelection()
        if case .permissionRequired = result { showAccessibilityAlert(); return }
        guard case .area(let displayID, let rectInDisplay, let scale) = result else { return }
        let session = ScrollCaptureSession()
        scrollSession = session
        let image = await session.run(displayID: displayID, rectInDisplay: rectInDisplay, scale: scale)
        scrollSession = nil
        if let image {
            deliver(image, displayID: displayID)
        }
    }

    // MARK: - Recording

    /// Select an area/window, then record it.
    func recordScreen(asGIF: Bool = false) {
        guard !recorder.isRecording, !overlay.isActive else { return }
        Task { await runRecordSelection(asGIF: asGIF) }
    }

    /// Records the display under the mouse — URL-scheme entry, no selection UI.
    func recordDisplayUnderMouse(captureMicrophone: Bool = false) {
        guard !recorder.isRecording else { return }
        guard let screen = screenUnderMouse(), let displayID = screen.displayID else { return }
        exportAsGIF = false
        Task {
            do {
                try await recorder.start(
                    target: .display(displayID, scale: screen.backingScaleFactor),
                    captureMicrophone: captureMicrophone
                )
            } catch {
                NSLog("SookraShot recording start failed: \(error)")
                NSSound.beep()
            }
        }
    }

    func stopRecording() {
        guard recorder.isRecording else { return }
        Task {
            do {
                let tempURL = try await recorder.stop()
                let destination = try await finalizeRecording(tempURL: tempURL)
                NSLog("SookraShot recording saved: \(destination.path)")
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch {
                NSLog("SookraShot recording stop failed: \(error)")
                NSSound.beep()
            }
        }
    }

    private func runRecordSelection(asGIF: Bool) async {
        let result = await overlay.beginSelection()
        let target: RecordingTarget
        switch result {
        case .area(let displayID, let rectInDisplay, let scale):
            target = .area(displayID: displayID, rectInDisplay: rectInDisplay, scale: scale)
        case .window(let windowID, let scale):
            target = .window(windowID, scale: scale)
        case .permissionRequired:
            showAccessibilityAlert()
            return
        case .cancelled:
            return
        }
        exportAsGIF = asGIF
        do {
            try await recorder.start(target: target)
        } catch {
            NSLog("SookraShot recording start failed: \(error)")
            NSSound.beep()
        }
    }

    private func finalizeRecording(tempURL: URL) async throws -> URL {
        let settings = AppSettings.shared
        let base = settings.filenameTemplate.filename(for: Date())
        if exportAsGIF {
            let destination = uniqueURL(base: base, ext: "gif", in: settings.saveDirectory)
            try await GIFExporter().exportGIF(from: tempURL, to: destination)
            try? FileManager.default.removeItem(at: tempURL)
            return destination
        }
        let destination = uniqueURL(base: base, ext: "mp4", in: settings.saveDirectory)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }

    private func uniqueURL(base: String, ext: String, in directory: URL) -> URL {
        var url = directory.appendingPathComponent(base).appendingPathExtension(ext)
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(base) \(counter)").appendingPathExtension(ext)
            counter += 1
        }
        return url
    }

    func captureArea() {
        guard !overlay.isActive else { return }
        Task { await runAreaSelection() }
    }

    // MARK: - Ask Claude

    /// Open the Ask Claude answer panel for an existing capture.
    func askClaude(about capture: DeliveredCapture) {
        askClaudePanel.present(capture)
    }

    /// Select a region, then open the Ask Claude panel for it.
    func askClaudeArea() {
        guard !overlay.isActive else { return }
        Task { await runAskClaudeArea() }
    }

    private func runAskClaudeArea() async {
        let result = await overlay.beginSelection()
        do {
            let image: CGImage
            let displayID: CGDirectDisplayID?
            switch result {
            case .area(let id, let rectInDisplay, let scale):
                image = try await capturer.captureRect(rectInDisplay, displayID: id, scale: scale)
                displayID = id
            case .window(let windowID, let scale):
                image = try await capturer.captureWindow(windowID: windowID, scale: scale)
                displayID = screenUnderMouse()?.displayID
            case .permissionRequired:
                showAccessibilityAlert()
                return
            case .cancelled:
                return
            }
            let capture = DeliveredCapture(image: image, displayID: displayID)
            history.record(capture)
            askClaude(about: capture)
        } catch {
            NSLog("SookraShot ask-claude capture failed: \(error)")
            NSSound.beep()
        }
    }

    /// OCR flow: select region, recognize on-device, put text on the clipboard.
    func captureText() {
        guard !overlay.isActive else { return }
        Task { await runCaptureText() }
    }

    private func runCaptureText() async {
        let result = await overlay.beginSelection()
        do {
            let image: CGImage
            switch result {
            case .area(let displayID, let rectInDisplay, let scale):
                image = try await capturer.captureRect(rectInDisplay, displayID: displayID, scale: scale)
            case .window(let windowID, let scale):
                image = try await capturer.captureWindow(windowID: windowID, scale: scale)
            case .permissionRequired:
                showAccessibilityAlert()
                return
            case .cancelled:
                return
            }
            let recognized = try await TextRecognizer().recognizeText(in: image)
            let text = recognized.fullText
            guard !text.isEmpty else {
                NSSound.beep()
                return
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        } catch {
            NSLog("SookraShot capture text failed: \(error)")
            NSSound.beep()
        }
    }

    func captureFullscreen() {
        Task { await runFullscreen() }
    }

    private func runAreaSelection() async {
        let result = await overlay.beginSelection()
        do {
            switch result {
            case .area(let displayID, let rectInDisplay, let scale):
                let image = try await capturer.captureRect(rectInDisplay, displayID: displayID, scale: scale)
                deliver(image, displayID: displayID)
            case .window(let windowID, let scale):
                let image = try await capturer.captureWindow(windowID: windowID, scale: scale)
                deliver(image, displayID: screenUnderMouse()?.displayID)
            case .permissionRequired:
                showAccessibilityAlert()
            case .cancelled:
                break
            }
        } catch {
            NSLog("SookraShot capture failed: \(error)")
            NSSound.beep()
        }
    }

    private func runFullscreen() async {
        guard let screen = screenUnderMouse(), let displayID = screen.displayID else { return }
        do {
            let image = try await capturer.captureDisplay(displayID, scale: screen.backingScaleFactor)
            deliver(image, displayID: displayID)
        } catch {
            NSLog("SookraShot fullscreen capture failed: \(error)")
            NSSound.beep()
        }
    }

    private func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    private func deliver(_ image: CGImage, displayID: CGDirectDisplayID?) {
        let capture = DeliveredCapture(image: image, displayID: displayID)
        history.record(capture)
        quickAccess.present(capture)
    }
}
