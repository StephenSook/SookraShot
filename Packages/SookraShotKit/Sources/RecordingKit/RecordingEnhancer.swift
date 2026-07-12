import AVFoundation
import AppKit
import QuartzCore

/// Bakes click-highlight ripples into a finished recording. Auto-zoom and a
/// keystroke overlay are planned follow-ups.
public struct RecordingEnhancer: Sendable {
    /// Maps a global click position to the recorded region. Both values are in
    /// Cocoa global (bottom-left origin) points; the recorded region's own
    /// pixel size comes from the video file.
    public struct Mapping: Sendable {
        public let regionOriginGlobal: CGPoint
        public let regionSizeGlobal: CGSize

        public init(regionOriginGlobal: CGPoint, regionSizeGlobal: CGSize) {
            self.regionOriginGlobal = regionOriginGlobal
            self.regionSizeGlobal = regionSizeGlobal
        }
    }

    public init() {}

    @MainActor
    public func enhance(
        source: URL,
        clicks: [RecordingClick],
        mapping: Mapping,
        toDirectory directory: URL,
        baseName: String
    ) async throws -> URL {
        let asset = AVURLAsset(url: source)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw TrimError(message: "No video track to enhance.")
        }
        let duration = try await asset.load(.duration)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)

        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw TrimError(message: "Could not build the enhanced video.")
        }
        let fullRange = CMTimeRange(start: .zero, duration: duration)
        try compVideo.insertTimeRange(fullRange, of: videoTrack, at: .zero)
        compVideo.preferredTransform = preferredTransform

        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first,
           let compAudio = composition.addMutableTrack(
               withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try? compAudio.insertTimeRange(fullRange, of: audioTrack, at: .zero)
        }

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: naturalSize)
        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.bounds
        let overlayLayer = CALayer()
        overlayLayer.frame = parentLayer.bounds
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(overlayLayer)

        for click in clicks {
            addRipple(for: click, mapping: mapping, videoSize: naturalSize, to: overlayLayer)
        }

        // macOS 26 Configuration API (the mutable AVVideoComposition types are deprecated).
        var layerConfig = AVVideoCompositionLayerInstruction.Configuration(assetTrack: compVideo)
        layerConfig.setTransform(preferredTransform, at: .zero)
        let layerInstruction = AVVideoCompositionLayerInstruction(configuration: layerConfig)

        var instructionConfig = AVVideoCompositionInstruction.Configuration()
        instructionConfig.timeRange = fullRange
        instructionConfig.layerInstructions = [layerInstruction]
        let instruction = AVVideoCompositionInstruction(configuration: instructionConfig)

        let animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer, in: parentLayer
        )

        var compositionConfig = AVVideoComposition.Configuration()
        compositionConfig.renderSize = naturalSize
        compositionConfig.frameDuration = CMTime(value: 1, timescale: 60)
        compositionConfig.instructions = [instruction]
        compositionConfig.animationTool = animationTool
        let videoComposition = AVVideoComposition(configuration: compositionConfig)

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw TrimError(message: "Enhancing is not available for this video.")
        }
        session.videoComposition = videoComposition

        let fileType: AVFileType = session.supportedFileTypes.contains(.mp4) ? .mp4 : .mov
        let ext = fileType == .mp4 ? "mp4" : "mov"
        let destination = uniqueURL(base: baseName, ext: ext, in: directory)
        try await session.export(to: destination, as: fileType)
        return destination
    }

    private func videoPoint(for global: CGPoint, mapping: Mapping, videoSize: CGSize) -> CGPoint {
        let nx = (global.x - mapping.regionOriginGlobal.x) / mapping.regionSizeGlobal.width
        let ny = (global.y - mapping.regionOriginGlobal.y) / mapping.regionSizeGlobal.height
        return CGPoint(x: nx * videoSize.width, y: ny * videoSize.height)
    }

    @MainActor
    private func addRipple(for click: RecordingClick, mapping: Mapping, videoSize: CGSize, to overlay: CALayer) {
        let point = videoPoint(for: click.location, mapping: mapping, videoSize: videoSize)
        let margin: CGFloat = 4
        guard point.x > -margin, point.y > -margin,
              point.x < videoSize.width + margin, point.y < videoSize.height + margin
        else { return }

        let radius = max(videoSize.width, videoSize.height) * 0.045
        let ring = CAShapeLayer()
        ring.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
        ring.position = point
        ring.fillColor = NSColor.systemYellow.withAlphaComponent(0.18).cgColor
        ring.strokeColor = NSColor.systemYellow.cgColor
        ring.lineWidth = max(2, radius * 0.18)
        ring.opacity = 0

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.3, 1.0, 1.5]
        scale.keyTimes = [0, 0.55, 1]

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.0, 0.95, 0.0]
        fade.keyTimes = [0, 0.2, 1]

        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.6
        group.beginTime = AVCoreAnimationBeginTimeAtZero + click.time
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards

        ring.add(group, forKey: "ripple")
        overlay.addSublayer(ring)
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
