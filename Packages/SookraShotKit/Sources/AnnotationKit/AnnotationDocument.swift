import CoreGraphics
import Foundation

/// Base image plus an editable annotation list with undo/redo.
/// Vector annotations stay editable until export flattens them.
public final class AnnotationDocument {
    public let baseImage: CGImage
    public private(set) var annotations: [Annotation] = []

    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []

    public init(baseImage: CGImage) {
        self.baseImage = baseImage
    }

    public var imageSize: CGSize {
        CGSize(width: baseImage.width, height: baseImage.height)
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public func add(_ annotation: Annotation) {
        pushUndoState()
        annotations.append(annotation)
    }

    public func addAll(_ newAnnotations: [Annotation]) {
        guard !newAnnotations.isEmpty else { return }
        pushUndoState()
        annotations.append(contentsOf: newAnnotations)
    }

    public func removeLast() {
        guard !annotations.isEmpty else { return }
        pushUndoState()
        annotations.removeLast()
    }

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
    }

    private func pushUndoState() {
        undoStack.append(annotations)
        redoStack.removeAll()
    }
}
