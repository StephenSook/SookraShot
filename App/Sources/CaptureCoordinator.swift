import AppKit
import CaptureKit
import OverlayKit
import SharedKit

/// Routes capture triggers (menu, hotkeys, URL scheme) through selection and capture.
@MainActor
final class CaptureCoordinator {
    private let capturer = ScreenCapturer()
    private let overlay = SelectionOverlayController()

    func captureArea() {
        guard !overlay.isActive else { return }
        Task { await runAreaSelection() }
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
                deliver(image)
            case .window(let windowID, let scale):
                let image = try await capturer.captureWindow(windowID: windowID, scale: scale)
                deliver(image)
            case .cancelled:
                break
            }
        } catch {
            NSLog("SookraShot capture failed: \(error)")
            NSSound.beep()
        }
    }

    private func runFullscreen() async {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen, let displayID = screen.displayID else { return }
        do {
            let image = try await capturer.captureDisplay(displayID, scale: screen.backingScaleFactor)
            deliver(image)
        } catch {
            NSLog("SookraShot fullscreen capture failed: \(error)")
            NSSound.beep()
        }
    }

    /// Phase 2 replaces this sink with the Quick Access overlay.
    private func deliver(_ image: CGImage) {
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)

        let name = FilenameTemplate.default.filename(for: Date()) + ".png"
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let url = desktop.appendingPathComponent(name)
        do {
            try data.write(to: url)
            NSLog("SookraShot saved capture: \(url.path)")
        } catch {
            NSLog("SookraShot save failed: \(error)")
        }
    }
}
