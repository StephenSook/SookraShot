import AIKit
import AnnotationKit
import AppKit
import CaptureKit
import CloudShareKit
import OCRKit
import HistoryKit
import OverlayKit
import PinKit
import QuickAccessKit
import RecordingKit
import ScrollCaptureKit
import SharedKit
import UniformTypeIdentifiers

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
    private let cloudShareHUD = CloudShareHUDController()
    private let inputMonitor = RecordingInputMonitor()
    private let enhancer = RecordingEnhancer()
    private var effectsMapping: RecordingEnhancer.Mapping?
    private var lastArea: (displayID: CGDirectDisplayID, rect: CGRect, scale: CGFloat)?

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
        quickAccess.onShareLink = { [weak self] capture in
            self?.shareToCloud(about: capture)
        }
        cloudShareHUD.onOpenSettings = {
            SettingsWindowController.present()
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
        let image = await session.run(
            displayID: displayID, rectInDisplay: rectInDisplay, scale: scale,
            autoScroll: AppSettings.shared.autoScrollScrollingCapture
        )
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
        let target = RecordingTarget.display(displayID, scale: screen.backingScaleFactor)
        beginEffectsCapture(for: target)
        Task {
            do {
                try await recorder.start(target: target, captureMicrophone: captureMicrophone)
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
                if AppSettings.shared.openTrimEditorAfterRecording, destination.pathExtension == "mp4" {
                    TrimEditorWindowController.present(url: destination)
                } else {
                    NSWorkspace.shared.activateFileViewerSelecting([destination])
                }
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
        if !asGIF { beginEffectsCapture(for: target) }
        do {
            try await recorder.start(target: target)
        } catch {
            NSLog("SookraShot recording start failed: \(error)")
            NSSound.beep()
        }
    }

    // MARK: - Click effects

    /// Start capturing clicks for post-recording ripples, when enabled and the
    /// target has a stable coordinate mapping (display or area, not a window).
    private func beginEffectsCapture(for target: RecordingTarget) {
        let settings = AppSettings.shared
        let anyEffect = settings.addClickEffectsToRecordings
            || settings.autoZoomRecordings
            || settings.keystrokeOverlayRecordings
        guard anyEffect, let mapping = mappingContext(for: target) else {
            effectsMapping = nil
            return
        }
        effectsMapping = mapping
        inputMonitor.start(captureKeystrokes: settings.keystrokeOverlayRecordings)
    }

    private func mappingContext(for target: RecordingTarget) -> RecordingEnhancer.Mapping? {
        switch target {
        case .display(let displayID, _):
            guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else { return nil }
            return RecordingEnhancer.Mapping(regionOriginGlobal: screen.frame.origin, regionSizeGlobal: screen.frame.size)
        case .area(let displayID, let rect, _):
            guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else { return nil }
            // rect is display-local top-left points; convert to a global bottom-left region.
            let originBL = CGPoint(x: screen.frame.minX + rect.minX, y: screen.frame.maxY - rect.maxY)
            return RecordingEnhancer.Mapping(regionOriginGlobal: originBL, regionSizeGlobal: rect.size)
        case .window:
            return nil
        }
    }

    /// Pick a video file and open it in the trim editor.
    func openTrimEditor() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.directoryURL = AppSettings.shared.saveDirectory
        panel.prompt = "Trim"
        if panel.runModal() == .OK, let url = panel.url {
            TrimEditorWindowController.present(url: url)
        }
    }

    private func finalizeRecording(tempURL: URL) async throws -> URL {
        let settings = AppSettings.shared
        let base = settings.filenameTemplate.filename(for: Date())

        // Always drain the click monitor if it was started, so it never leaks.
        let clickLog = effectsMapping != nil ? inputMonitor.stop() : nil
        let mapping = effectsMapping
        effectsMapping = nil

        if exportAsGIF {
            let destination = uniqueURL(base: base, ext: "gif", in: settings.saveDirectory)
            try await GIFExporter().exportGIF(from: tempURL, to: destination)
            try? FileManager.default.removeItem(at: tempURL)
            return destination
        }

        if let mapping, let clickLog {
            let showRipples = settings.addClickEffectsToRecordings
            let autoZoom = settings.autoZoomRecordings
            let hasWork = (!clickLog.clicks.isEmpty && (showRipples || autoZoom)) || !clickLog.keystrokes.isEmpty
            if hasWork {
                do {
                    let enhanced = try await enhancer.enhance(
                        source: tempURL, clicks: clickLog.clicks, keystrokes: clickLog.keystrokes,
                        mapping: mapping, showRipples: showRipples, autoZoom: autoZoom,
                        toDirectory: settings.saveDirectory, baseName: base
                    )
                    try? FileManager.default.removeItem(at: tempURL)
                    return enhanced
                } catch {
                    NSLog("SookraShot recording enhance failed, saving raw: \(error)")
                }
            }
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

    // MARK: - Cloud share

    /// Upload an existing capture to Backblaze B2 and show the link HUD.
    func shareToCloud(about capture: DeliveredCapture) {
        cloudShareHUD.present(capture)
    }

    /// Select a region, then upload it to Backblaze B2.
    func shareToCloudArea() {
        guard !overlay.isActive else { return }
        Task { await runShareToCloudArea() }
    }

    private func runShareToCloudArea() async {
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
            shareToCloud(about: capture)
        } catch {
            NSLog("SookraShot cloud-share capture failed: \(error)")
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

    /// Re-capture the last selected area without showing the overlay again.
    func capturePreviousArea() {
        guard let last = lastArea, !overlay.isActive else {
            NSSound.beep()
            return
        }
        Task {
            do {
                let image = try await capturer.captureRect(last.rect, displayID: last.displayID, scale: last.scale)
                deliver(image, displayID: last.displayID)
            } catch {
                NSLog("SookraShot capture previous area failed: \(error)")
                NSSound.beep()
            }
        }
    }

    /// Native eyedropper: pick a screen pixel and copy its hex to the clipboard.
    func sampleColor() {
        NSColorSampler().show { color in
            Task { @MainActor in
                guard let color = color?.usingColorSpace(.sRGB) else { return }
                let hex = HexColor.string(
                    red: Double(color.redComponent),
                    green: Double(color.greenComponent),
                    blue: Double(color.blueComponent)
                )
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(hex, forType: .string)
            }
        }
    }

    private func runAreaSelection() async {
        let result = await overlay.beginSelection()
        do {
            switch result {
            case .area(let displayID, let rectInDisplay, let scale):
                lastArea = (displayID, rectInDisplay, scale)
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
        let delay = AppSettings.shared.captureDelaySeconds
        if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
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
