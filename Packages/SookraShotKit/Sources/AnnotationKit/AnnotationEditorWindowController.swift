import AppKit
import ExportKit
import OCRKit
import SharedKit

/// The annotate editor window: tool bar, canvas, undo/redo, redact, export.
@MainActor
public final class AnnotationEditorWindowController: NSWindowController, NSWindowDelegate {
    private let annotationDocument: AnnotationDocument
    private let capture: DeliveredCapture
    private let canvas: AnnotationCanvasView
    private let renderer = AnnotationRenderer()
    private let saver = CaptureSaver()
    private var toolButtons: [AnnotationTool: NSButton] = [:]
    private var colorWell: NSColorWell?

    /// Keeps the controller alive while its window is open.
    private static var activeControllers: [AnnotationEditorWindowController] = []

    public static func present(capture: DeliveredCapture) {
        let controller = AnnotationEditorWindowController(capture: capture)
        activeControllers.append(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private init(capture: DeliveredCapture) {
        self.capture = capture
        self.annotationDocument = AnnotationDocument(baseImage: capture.image)
        self.canvas = AnnotationCanvasView(document: annotationDocument)

        let imageSize = annotationDocument.imageSize
        let scale = min(1200 / imageSize.width, 800 / imageSize.height, 0.75)
        let contentSize = NSSize(
            width: max(imageSize.width * scale, 640),
            height: max(imageSize.height * scale + 48, 420)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SookraShot — Annotate"
        window.center()
        super.init(window: window)
        window.delegate = self
        buildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public func windowWillClose(_ notification: Notification) {
        Self.activeControllers.removeAll { $0 === self }
    }

    // MARK: - Layout

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        var toolViews: [NSView] = AnnotationTool.allCases.map { tool in
            let button = NSButton()
            button.bezelStyle = .accessoryBarAction
            button.setButtonType(.pushOnPushOff)
            button.title = ""
            button.image = NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: tool.tooltip)
            button.toolTip = tool.tooltip
            button.target = self
            button.action = #selector(toolSelected(_:))
            button.identifier = NSUserInterfaceItemIdentifier(tool.rawValue)
            toolButtons[tool] = button
            return button
        }
        toolButtons[.arrow]?.state = .on

        let well = NSColorWell(style: .minimal)
        well.color = NSColor(
            srgbRed: RGBAColor.annotationRed.red,
            green: RGBAColor.annotationRed.green,
            blue: RGBAColor.annotationRed.blue,
            alpha: 1
        )
        well.target = self
        well.action = #selector(colorChanged(_:))
        colorWell = well
        toolViews.append(well)

        toolViews.append(NSView())
        toolViews.append(pushButton("arrow.uturn.backward", "Undo (Cmd+Z)", #selector(undoTapped)))
        toolViews.append(pushButton("arrow.uturn.forward", "Redo (Shift+Cmd+Z)", #selector(redoTapped)))
        toolViews.append(pushButton("eye.slash", "Redact secrets and PII", #selector(redactTapped)))
        toolViews.append(pushButton("doc.on.doc", "Copy to clipboard", #selector(copyTapped)))
        toolViews.append(pushButton("square.and.arrow.down", "Save", #selector(saveTapped)))

        let toolbar = NSStackView(views: toolViews)
        toolbar.orientation = .horizontal
        toolbar.spacing = 6
        toolbar.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        canvas.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(toolbar)
        contentView.addSubview(canvas)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: contentView.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 44),

            canvas.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    private func pushButton(_ symbol: String, _ tooltip: String, _ action: Selector) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .accessoryBarAction
        button.title = ""
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.toolTip = tooltip
        button.target = self
        button.action = action
        return button
    }

    // MARK: - Actions

    @objc private func toolSelected(_ sender: NSButton) {
        guard let identifier = sender.identifier?.rawValue,
              let tool = AnnotationTool(rawValue: identifier) else { return }
        canvas.activeTool = tool
        for (buttonTool, button) in toolButtons {
            button.state = buttonTool == tool ? .on : .off
        }
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        let color = sender.color.usingColorSpace(.sRGB) ?? sender.color
        canvas.activeColor = RGBAColor(
            red: color.redComponent,
            green: color.greenComponent,
            blue: color.blueComponent,
            alpha: color.alphaComponent
        )
    }

    @objc private func undoTapped() {
        annotationDocument.undo()
        canvas.needsDisplay = true
    }

    @objc private func redoTapped() {
        annotationDocument.redo()
        canvas.needsDisplay = true
    }

    /// Auto-redact: OCR the base image, pixelate every secret/PII line box.
    @objc private func redactTapped() {
        Task { @MainActor in
            do {
                let recognized = try await TextRecognizer().recognizeText(in: annotationDocument.baseImage)
                let matches = SensitiveContentDetector().detect(in: recognized)
                let size = annotationDocument.imageSize
                let annotations = matches.map { match -> Annotation in
                    let box = match.boundingBox
                    let rect = CGRect(
                        x: box.minX * size.width,
                        y: box.minY * size.height,
                        width: box.width * size.width,
                        height: box.height * size.height
                    ).insetBy(dx: -6, dy: -6)
                    return Annotation(
                        kind: .pixelate,
                        start: rect.origin,
                        end: CGPoint(x: rect.maxX, y: rect.maxY)
                    )
                }
                if annotations.isEmpty {
                    NSSound.beep()
                } else {
                    annotationDocument.addAll(annotations)
                    canvas.needsDisplay = true
                }
            } catch {
                NSLog("SookraShot redact failed: \(error)")
                NSSound.beep()
            }
        }
    }

    @objc private func copyTapped() {
        guard let flattened = renderer.flatten(annotationDocument) else { return }
        PasteboardWriter.copy(DeliveredCapture(image: flattened, capturedAt: capture.capturedAt))
    }

    @objc private func saveTapped() {
        guard let flattened = renderer.flatten(annotationDocument) else { return }
        do {
            try saver.save(DeliveredCapture(image: flattened, capturedAt: capture.capturedAt))
            window?.close()
        } catch {
            NSLog("SookraShot annotate save failed: \(error)")
            NSSound.beep()
        }
    }

    // MARK: - Keyboard

    public override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
            if event.modifierFlags.contains(.shift) {
                redoTapped()
            } else {
                undoTapped()
            }
            return
        }
        super.keyDown(with: event)
    }
}
