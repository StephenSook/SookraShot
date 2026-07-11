import AppKit

/// Editor canvas: shows the base image aspect-fit and captures tool gestures.
@MainActor
final class AnnotationCanvasView: NSView {
    let document: AnnotationDocument
    var activeTool: AnnotationTool = .arrow
    var activeColor: RGBAColor = .annotationRed
    var onDocumentChange: (@MainActor () -> Void)?

    private let renderer = AnnotationRenderer()
    private var inProgress: Annotation?
    private var pencilPoints: [CGPoint] = []
    private var counterValue = 1
    private var textEditor: NSTextField?

    init(document: AnnotationDocument) {
        self.document = document
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Geometry

    /// Where the image lands inside the view (aspect-fit, view points).
    private var imageFrame: NSRect {
        let size = document.imageSize
        guard size.width > 0, size.height > 0, bounds.width > 8, bounds.height > 8 else { return .zero }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = NSSize(width: size.width * scale, height: size.height * scale)
        return NSRect(
            x: (bounds.width - fitted.width) / 2,
            y: (bounds.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    private func imagePoint(from event: NSEvent) -> CGPoint {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let frame = imageFrame
        guard frame.width > 0 else { return .zero }
        let scale = document.imageSize.width / frame.width
        return CGPoint(
            x: (viewPoint.x - frame.minX) * scale,
            y: (viewPoint.y - frame.minY) * scale
        )
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        commitTextEditorIfNeeded()
        let point = imagePoint(from: event)
        switch activeTool {
        case .text:
            presentTextEditor(at: point, viewPoint: convert(event.locationInWindow, from: nil))
        case .counter:
            document.add(
                Annotation(kind: .counter(counterValue), start: point, end: point, color: activeColor)
            )
            counterValue += 1
            documentChanged()
        case .pencil, .highlighter:
            pencilPoints = [point]
        default:
            inProgress = Annotation(kind: activeTool.kind, start: point, end: point, color: toolColor())
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = imagePoint(from: event)
        switch activeTool {
        case .pencil, .highlighter:
            pencilPoints.append(point)
        default:
            inProgress?.end = point
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch activeTool {
        case .pencil, .highlighter:
            if pencilPoints.count > 1 {
                let kind: Annotation.Kind = activeTool == .pencil
                    ? .pencil(pencilPoints) : .highlighter(pencilPoints)
                document.add(
                    Annotation(
                        kind: kind,
                        start: pencilPoints.first ?? .zero,
                        end: pencilPoints.last ?? .zero,
                        color: toolColor()
                    )
                )
                documentChanged()
            }
            pencilPoints = []
        case .text, .counter:
            break
        default:
            if var annotation = inProgress {
                annotation.end = imagePoint(from: event)
                if annotation.boundingRect.width > 3 || annotation.boundingRect.height > 3 {
                    document.add(annotation)
                    documentChanged()
                }
            }
            inProgress = nil
        }
        needsDisplay = true
    }

    // MARK: - Text tool

    private func presentTextEditor(at imagePoint: CGPoint, viewPoint: NSPoint) {
        let field = NSTextField(frame: NSRect(x: viewPoint.x, y: viewPoint.y, width: 220, height: 28))
        field.placeholderString = "Text"
        field.font = .systemFont(ofSize: 16, weight: .semibold)
        field.target = self
        field.action = #selector(textCommitted(_:))
        addSubview(field)
        window?.makeFirstResponder(field)
        textEditor = field
        field.tag = 0
        pendingTextPoint = imagePoint
    }

    private var pendingTextPoint: CGPoint = .zero

    @objc private func textCommitted(_ sender: NSTextField) {
        commitTextEditorIfNeeded()
    }

    private func commitTextEditorIfNeeded() {
        guard let field = textEditor else { return }
        let value = field.stringValue
        field.removeFromSuperview()
        textEditor = nil
        guard !value.isEmpty else { return }
        document.add(
            Annotation(kind: .text(value), start: pendingTextPoint, end: pendingTextPoint, color: activeColor)
        )
        documentChanged()
        needsDisplay = true
    }

    private func toolColor() -> RGBAColor {
        activeTool == .highlighter ? .highlighterYellow : activeColor
    }

    private func documentChanged() {
        onDocumentChange?()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let frame = imageFrame
        guard frame.width > 0 else { return }

        context.saveGState()
        context.draw(document.baseImage, in: frame)

        // Map image pixel space onto the fitted frame for annotation drawing.
        context.translateBy(x: frame.minX, y: frame.minY)
        let scale = frame.width / document.imageSize.width
        context.scaleBy(x: scale, y: scale)

        renderer.draw(document.annotations, of: document, in: context)

        var preview: [Annotation] = []
        if let inProgress {
            preview.append(inProgress)
        }
        if pencilPoints.count > 1 {
            let kind: Annotation.Kind = activeTool == .pencil
                ? .pencil(pencilPoints) : .highlighter(pencilPoints)
            preview.append(
                Annotation(
                    kind: kind,
                    start: pencilPoints.first ?? .zero,
                    end: pencilPoints.last ?? .zero,
                    color: toolColor()
                )
            )
        }
        renderer.draw(preview, of: document, in: context)
        context.restoreGState()
    }
}

public enum AnnotationTool: String, CaseIterable, Sendable {
    case arrow
    case rect
    case filledRect
    case ellipse
    case line
    case pencil
    case highlighter
    case text
    case counter
    case blur
    case pixelate

    var kind: Annotation.Kind {
        switch self {
        case .arrow: .arrow
        case .rect: .rect
        case .filledRect: .filledRect
        case .ellipse: .ellipse
        case .line: .line
        case .pencil: .pencil([])
        case .highlighter: .highlighter([])
        case .text: .text("")
        case .counter: .counter(0)
        case .blur: .blur
        case .pixelate: .pixelate
        }
    }

    public var symbolName: String {
        switch self {
        case .arrow: "arrow.up.right"
        case .rect: "rectangle"
        case .filledRect: "rectangle.fill"
        case .ellipse: "circle"
        case .line: "line.diagonal"
        case .pencil: "pencil"
        case .highlighter: "highlighter"
        case .text: "textformat"
        case .counter: "1.circle"
        case .blur: "drop"
        case .pixelate: "mosaic"
        }
    }

    public var tooltip: String {
        switch self {
        case .arrow: "Arrow"
        case .rect: "Rectangle"
        case .filledRect: "Filled rectangle"
        case .ellipse: "Ellipse"
        case .line: "Line"
        case .pencil: "Pencil"
        case .highlighter: "Highlighter"
        case .text: "Text"
        case .counter: "Counter"
        case .blur: "Blur"
        case .pixelate: "Pixelate"
        }
    }
}
