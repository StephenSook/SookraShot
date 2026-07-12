import AppKit
import ExportKit
import SharedKit

/// One capture card: thumbnail plus the core Copy / Save / Annotate / Pin
/// actions, with the rest tucked into a "More" (⋯) menu so the toolbar stays
/// uncluttered.
@MainActor
final class CaptureCardView: NSView {
    enum Action {
        case copy
        case copyText
        case copyMarkdown
        case save
        case annotate
        case askClaude
        case shareLink
        case beautify
        case removeBackground
        case safeShare
        case pin
        case dismiss
    }

    let capture: DeliveredCapture
    private let onAction: @MainActor (CaptureCardView, Action) -> Void
    private var overflowMenu: NSMenu?

    private static let maxThumbnailWidth: CGFloat = 320
    private static let maxThumbnailHeight: CGFloat = 220

    init(capture: DeliveredCapture, onAction: @escaping @MainActor (CaptureCardView, Action) -> Void) {
        self.capture = capture
        self.onAction = onAction
        super.init(frame: .zero)
        wantsLayer = true
        buildContents()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    private func buildContents() {
        // Liquid Glass panel (macOS 26 Tahoe).
        let glass = NSGlassEffectView()
        glass.cornerRadius = 12
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)

        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.35
        layer?.shadowRadius = 12
        layer?.shadowOffset = CGSize(width: 0, height: -4)

        let thumbnail = DraggableThumbnailView(capture: capture)
        thumbnail.translatesAutoresizingMaskIntoConstraints = false

        let imageSize = thumbnailSize()

        // Core actions inline; everything else lives in the ⋯ menu.
        let copyButton = actionButton("doc.on.doc", "Copy", .copy)
        let saveButton = actionButton("square.and.arrow.down", "Save", .save)
        let annotateButton = actionButton("pencil.tip.crop.circle", "Annotate", .annotate)
        let moreButton = overflowButton()
        let pinButton = actionButton("pin", "Pin on top", .pin)
        let closeButton = actionButton("xmark", "Dismiss", .dismiss)

        let buttons = NSStackView(views: [copyButton, saveButton, annotateButton, moreButton, pinButton, NSView(), closeButton])
        buttons.orientation = .horizontal
        buttons.spacing = 6
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let content = NSStackView(views: [thumbnail, buttons])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 6
        content.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        content.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView = content

        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),

            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),

            thumbnail.widthAnchor.constraint(equalToConstant: imageSize.width),
            thumbnail.heightAnchor.constraint(equalToConstant: imageSize.height),
            buttons.widthAnchor.constraint(equalTo: thumbnail.widthAnchor),
        ])
    }

    private func thumbnailSize() -> NSSize {
        let width = CGFloat(capture.image.width)
        let height = CGFloat(capture.image.height)
        let scale = min(Self.maxThumbnailWidth / width, Self.maxThumbnailHeight / height, 1)
        return NSSize(width: max(width * scale, 120), height: max(height * scale, 60))
    }

    private func actionButton(_ symbol: String, _ tooltip: String, _ action: Action) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .accessoryBarAction
        button.isBordered = true
        button.title = ""
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.toolTip = tooltip
        button.target = self
        switch action {
        case .copy: button.action = #selector(copyTapped)
        case .save: button.action = #selector(saveTapped)
        case .annotate: button.action = #selector(annotateTapped)
        case .pin: button.action = #selector(pinTapped)
        case .dismiss: button.action = #selector(dismissTapped)
        default: break
        }
        return button
    }

    private func overflowButton() -> NSButton {
        let menu = NSMenu()
        addMenuItem(to: menu, "Copy text (OCR)", .copyText)
        addMenuItem(to: menu, "Copy as Markdown code", .copyMarkdown)
        menu.addItem(.separator())
        addMenuItem(to: menu, "Ask Claude", .askClaude)
        addMenuItem(to: menu, "Upload & copy link", .shareLink)
        menu.addItem(.separator())
        addMenuItem(to: menu, "Beautify", .beautify)
        addMenuItem(to: menu, "Remove background", .removeBackground)
        addMenuItem(to: menu, "Redact & copy (safe share)", .safeShare)
        overflowMenu = menu

        let button = NSButton()
        button.bezelStyle = .accessoryBarAction
        button.isBordered = true
        button.title = ""
        button.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More actions")
        button.toolTip = "More actions"
        button.target = self
        button.action = #selector(overflowTapped(_:))
        return button
    }

    private func addMenuItem(to menu: NSMenu, _ title: String, _ action: Action) {
        let item = NSMenuItem(title: title, action: #selector(overflowSelected(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = action
        menu.addItem(item)
    }

    @objc private func overflowTapped(_ sender: NSButton) {
        overflowMenu?.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc private func overflowSelected(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? Action else { return }
        onAction(self, action)
    }

    @objc private func copyTapped() { onAction(self, .copy) }
    @objc private func saveTapped() { onAction(self, .save) }
    @objc private func annotateTapped() { onAction(self, .annotate) }
    @objc private func pinTapped() { onAction(self, .pin) }
    @objc private func dismissTapped() { onAction(self, .dismiss) }
}
