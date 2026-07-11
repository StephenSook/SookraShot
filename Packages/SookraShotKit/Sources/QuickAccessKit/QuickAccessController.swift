import AppKit
import ExportKit
import SharedKit

/// Owns the floating Quick Access panel: presents capture cards in the
/// configured screen corner, stacking newest on top.
@MainActor
public final class QuickAccessController {
    private var panel: QuickAccessPanel?
    private var cards: [CaptureCardView] = []
    private let saver = CaptureSaver()

    public var onAnnotate: (@MainActor (DeliveredCapture) -> Void)?

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
        case .save:
            do {
                try saver.save(card.capture)
                remove(card)
            } catch {
                NSLog("SookraShot save failed: \(error)")
                NSSound.beep()
            }
        case .annotate:
            onAnnotate?(card.capture)
            remove(card)
        case .dismiss:
            remove(card)
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
