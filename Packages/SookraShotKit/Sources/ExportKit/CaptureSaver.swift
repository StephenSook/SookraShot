import CoreGraphics
import Foundation
import SharedKit

public enum SaveError: Error {
    case encodingFailed
}

/// Writes captures into the configured save directory with the filename template.
public struct CaptureSaver: Sendable {
    private let encoder = ImageEncoder()

    public init() {}

    @discardableResult
    public func save(
        _ capture: DeliveredCapture,
        format: ImageFormat = AppSettings.shared.imageFormat,
        directory: URL = AppSettings.shared.saveDirectory,
        template: FilenameTemplate = AppSettings.shared.filenameTemplate,
        baseName: String? = nil
    ) throws -> URL {
        guard let data = encoder.data(from: capture.image, format: format) else {
            throw SaveError.encodingFailed
        }
        let base = baseName ?? template.filename(for: capture.capturedAt)
        var url = directory.appendingPathComponent(base).appendingPathExtension(format.fileExtension)
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory
                .appendingPathComponent("\(base) \(counter)")
                .appendingPathExtension(format.fileExtension)
            counter += 1
        }
        try data.write(to: url)
        return url
    }

    public func suggestedFilename(
        for capture: DeliveredCapture,
        format: ImageFormat = AppSettings.shared.imageFormat,
        template: FilenameTemplate = AppSettings.shared.filenameTemplate
    ) -> String {
        template.filename(for: capture.capturedAt) + "." + format.fileExtension
    }
}
