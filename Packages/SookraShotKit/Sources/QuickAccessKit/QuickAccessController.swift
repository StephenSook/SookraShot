import AppKit
import BeautifyKit
import ExportKit
import OCRKit
import SharedKit

/// Owns the floating Quick Access panel: presents capture cards in the
/// configured screen corner, stacking newest on top.
@MainActor
public final class QuickAccessController {
    private var panel: QuickAccessPanel?
    private var cards: [CaptureCardView] = []
    private let saver = CaptureSaver()

    public var onAnnotate: (@MainActor (DeliveredCapture) -> Void)?
    public var onPin: (@MainActor (DeliveredCapture) -> Void)?
    public var onAskClaude: (@MainActor (DeliveredCapture) -> Void)?
    public var onShareLink: (@MainActor (DeliveredCapture) -> Void)?

    public init() {}

    public func present(_ capture: DeliveredCapture) {
        let card = CaptureCardView(capture: capture) { [weak self] card, action in
            self?.handle(action, for: card)
        }
        cards.insert(card, at: 0)
        layoutPanel(animateNewest: true)
    }

    // MARK: - Actions

    private func handle(_ action: CaptureCardView.Action, for card: CaptureCardView) {
        switch action {
        case .copy:
            PasteboardWriter.copy(card.capture)
            remove(card)
        case .copyText:
            copyRecognizedText(from: card, asMarkdown: false)
        case .copyMarkdown:
            copyRecognizedText(from: card, asMarkdown: true)
        case .save:
            saveCapture(card)
        case .annotate:
            onAnnotate?(card.capture)
            remove(card)
        case .askClaude:
            // Leave the card up — the answer panel is a separate surface.
            onAskClaude?(card.capture)
        case .shareLink:
            // Leave the card up — the upload HUD is a separate surface.
            onShareLink?(card.capture)
        case .beautify:
            beautify(card)
        case .safeShare:
            safeShare(from: card)
        case .pin:
            onPin?(card.capture)
            remove(card)
        case .dismiss:
            remove(card)
        }
    }

    private func beautify(_ card: CaptureCardView) {
        let background = BeautifyBackground(rawValue: AppSettings.shared.beautifyBackground) ?? .ocean
        let frame = BeautifyFrame(rawValue: AppSettings.shared.beautifyFrame) ?? .none
        guard let image = Beautifier().beautify(card.capture.image, background: background, frame: frame) else {
            NSSound.beep()
            return
        }
        // Present the beautified result as a new card so the original stays.
        present(DeliveredCapture(image: image, displayID: card.capture.displayID))
    }

    private func safeShare(from card: CaptureCardView) {
        Task { @MainActor [weak self] in
            do {
                let result = try await SafeShareRedactor().redact(card.capture.image)
                let redacted = DeliveredCapture(image: result.image, displayID: card.capture.displayID)
                PasteboardWriter.copy(redacted)
                self?.remove(card)
            } catch {
                NSLog("SookraShot safe share failed: \(error)")
                NSSound.beep()
            }
        }
    }

    private func copyRecognizedText(from card: CaptureCardView, asMarkdown: Bool) {
        Task { @MainActor [weak self] in
            do {
                let recognized = try await TextRecognizer().recognizeText(in: card.capture.image)
                let text = recognized.fullText
                guard !text.isEmpty else {
                    NSSound.beep()
                    return
                }
                let output = asMarkdown ? "```\n\(text)\n```" : text
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(output, forType: .string)
                self?.remove(card)
            } catch {
                NSLog("SookraShot OCR failed: \(error)")
                NSSound.beep()
            }
        }
    }

    private func saveCapture(_ card: CaptureCardView) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                var baseName: String?
                if AppSettings.shared.smartFilenames,
                   let recognized = try? await TextRecognizer().recognizeText(in: card.capture.image) {
                    baseName = SmartFilename.suggest(from: recognized)
                }
                try self.saver.save(card.capture, baseName: baseName)
                self.remove(card)
            } catch {
                NSLog("SookraShot save failed: \(error)")
                NSSound.beep()
            }
        }
    }

    private func remove(_ card: CaptureCardView) {
        cards.removeAll { $0 === card }
        layoutPanel(animateNewest: false)
    }

    // MARK: - Panel layout

    private func layoutPanel(animateNewest: Bool) {
        guard !cards.isEmpty else {
            panel?.orderOut(nil)
            panel = nil
            return
        }

        let screen = targetScreen()
        let corner = AppSettings.shared.overlayCorner
        let panel = panel ?? QuickAccessPanel()
        self.panel = panel
        panel.setCards(cards, corner: corner, on: screen, animateNewest: animateNewest)
        panel.orderFrontRegardless()
    }

    private func targetScreen() -> NSScreen {
        if let displayID = cards.first?.capture.displayID,
           let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }
}
