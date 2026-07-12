import AVFoundation
import Foundation

public struct TrimError: LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { message }
}

/// Exports a time range of a video to a new file. Uses the highest-quality
/// preset so cuts land on the chosen frame rather than the nearest keyframe.
public struct VideoTrimmer: Sendable {
    public init() {}

    public func export(
        source: URL,
        timeRange: CMTimeRange,
        toDirectory directory: URL,
        baseName: String
    ) async throws -> URL {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw TrimError(message: "Trimming is not available for this video.")
        }
        session.timeRange = timeRange

        let fileType: AVFileType = session.supportedFileTypes.contains(.mp4) ? .mp4 : .mov
        let ext = fileType == .mp4 ? "mp4" : "mov"
        let destination = uniqueURL(base: baseName, ext: ext, in: directory)

        try await session.export(to: destination, as: fileType)
        return destination
    }

    private func uniqueURL(base: String, ext: String, in directory: URL) -> URL {
        var url = directory.appendingPathComponent(base).appendingPathExtension(ext)
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(base) \(counter)").appendingPathExtension(ext)
            counter += 1
        }
        return url
    }
}
