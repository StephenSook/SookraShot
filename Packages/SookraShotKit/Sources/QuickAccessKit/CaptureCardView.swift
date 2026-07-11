import AppKit
import ExportKit
import SharedKit

/// One capture card: thumbnail plus Copy / Save / Annotate / dismiss actions.
@MainActor
final class CaptureCardView: NSView {
    enum Action {
        case copy
        case save
        case annotate
        case dismiss
    }

    let capture: DeliveredCapture
    private let onAction: @MainActor (CaptureCardView, Action) -> Void

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
        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.35
        layer?.shadowRadius = 12
        layer?.shadowOffset = CGSize(width: 0, height: -4)

        let thumbnail = DraggableThumbnailView(capture: capture)
        thumbnail.translatesAutoresizingMaskIntoConstraints = false

        let imageSize = thumbnailSize()

        let copyButton = actionButton("doc.on.doc", "Copy", .copy)
        let saveButton = actionButton("square.and.arrow.down", "Save", .save)
        let annotateButton = actionButton("pencil.tip.crop.circle", "Annotate", .annotate)
        let closeButton = actionButton("xmark", "Dismiss", .dismiss)

        let buttons = NSStackView(views: [copyButton, saveButton, annotateButton, NSView(), closeButton])
        buttons.orientation = .horizontal
        buttons.spacing = 6
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let content = NSStackView(views: [thumbnail, buttons])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 6
        content.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),

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
        case .dismiss: button.action = #selector(dismissTapped)
        }
        return button
    }

    @objc private func copyTapped() { onAction(self, .copy) }
    @objc private func saveTapped() { onAction(self, .save) }
    @objc private func annotateTapped() { onAction(self, .annotate) }
    @objc private func dismissTapped() { onAction(self, .dismiss) }
}
