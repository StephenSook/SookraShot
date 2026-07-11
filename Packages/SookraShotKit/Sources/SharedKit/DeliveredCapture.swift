import CoreGraphics
import Foundation

/// A finished capture travelling from CaptureKit to UI surfaces.
/// CGImage is immutable; the struct is safe to pass across actors.
public struct DeliveredCapture: @unchecked Sendable, Identifiable {
    public let id: UUID
    public let image: CGImage
    public let capturedAt: Date
    public let displayID: CGDirectDisplayID?

    public init(image: CGImage, capturedAt: Date = Date(), displayID: CGDirectDisplayID? = nil) {
        self.id = UUID()
        self.image = image
        self.capturedAt = capturedAt
        self.displayID = displayID
    }
}
