import CoreGraphics
import Testing
@testable import AnnotationKit

@Suite struct AnnotationDocumentTests {
    private func makeBaseImage() -> CGImage {
        let context = CGContext(
            data: nil,
            width: 100,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        return context.makeImage()!
    }

    private func arrow() -> Annotation {
        Annotation(kind: .arrow, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 60, y: 60))
    }

    @Test func addThenUndoRestoresPreviousState() {
        let document = AnnotationDocument(baseImage: makeBaseImage())
        document.add(arrow())
        #expect(document.annotations.count == 1)
        document.undo()
        #expect(document.annotations.isEmpty)
    }

    @Test func redoReappliesUndoneChange() {
        let document = AnnotationDocument(baseImage: makeBaseImage())
        document.add(arrow())
        document.undo()
        document.redo()
        #expect(document.annotations.count == 1)
    }

    @Test func newChangeClearsRedoStack() {
        let document = AnnotationDocument(baseImage: makeBaseImage())
        document.add(arrow())
        document.undo()
        document.add(arrow())
        #expect(!document.canRedo)
        #expect(document.annotations.count == 1)
    }

    @Test func addAllIsSingleUndoStep() {
        let document = AnnotationDocument(baseImage: makeBaseImage())
        document.addAll([arrow(), arrow(), arrow()])
        #expect(document.annotations.count == 3)
        document.undo()
        #expect(document.annotations.isEmpty)
    }

    @Test func flattenProducesImageOfSameSize() {
        let document = AnnotationDocument(baseImage: makeBaseImage())
        document.add(arrow())
        document.add(
            Annotation(kind: .pixelate, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 80, y: 50))
        )
        let flattened = AnnotationRenderer().flatten(document)
        #expect(flattened?.width == 100)
        #expect(flattened?.height == 100)
    }
}
