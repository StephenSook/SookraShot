import AnnotationKit
import AppKit
import CaptureKit
import OCRKit
import OverlayKit
import QuickAccessKit
import SharedKit

/// Routes capture triggers (menu, hotkeys, URL scheme) through selection and capture.
@MainActor
final class CaptureCoordinator {
    private let capturer = ScreenCapturer()
    private let overlay = SelectionOverlayController()
    private let quickAccess = QuickAccessController()

    init() {
        quickAccess.onAnnotate = { capture in
            AnnotationEditorWindowController.present(capture: capture)
        }
    }

    func captureArea() {
        guard !overlay.isActive else { return }
        Task { await runAreaSelection() }
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
        quickAccess.present(capture)
    }
}
