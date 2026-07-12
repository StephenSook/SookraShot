import AVFoundation
import AppKit
import QuartzCore

/// Bakes recording effects into a finished video: click-highlight ripples,
/// auto-zoom toward click activity, and a keystroke caption overlay.
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

    private static let zoomScale: CGFloat = 1.7

    public init() {}

    @MainActor
    public func enhance(
        source: URL,
        clicks: [RecordingClick],
        keystrokes: [RecordingKeystroke],
        mapping: Mapping,
        showRipples: Bool,
        autoZoom: Bool,
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
        let overlayLayer = CALayer()      // ripples — zooms with the video
        overlayLayer.frame = parentLayer.bounds
        let hudLayer = CALayer()          // keystrokes — fixed, never zoomed
        hudLayer.frame = parentLayer.bounds
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(overlayLayer)
        parentLayer.addSublayer(hudLayer)

        if showRipples {
            for click in clicks {
                addRipple(for: click, mapping: mapping, videoSize: naturalSize, to: overlayLayer)
            }
        }

        if autoZoom, let zoom = zoomAnimation(clicks: clicks, mapping: mapping, videoSize: naturalSize, duration: duration.seconds) {
            videoLayer.add(zoom, forKey: "zoom")
            overlayLayer.add(zoom, forKey: "zoom")
        }

        addKeystrokeCaptions(keystrokes, videoSize: naturalSize, to: hudLayer)

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

    // MARK: - Auto-zoom

    /// A transform keyframe animation that eases in toward click activity, pans
    /// between clicks, and eases back out. Applied to both the video and ripple
    /// layers so they move together. nil if no clicks land inside the frame.
    private func zoomAnimation(clicks: [RecordingClick], mapping: Mapping, videoSize: CGSize, duration: TimeInterval) -> CAKeyframeAnimation? {
        let points = clicks.compactMap { click -> (time: Double, point: CGPoint)? in
            let p = videoPoint(for: click.location, mapping: mapping, videoSize: videoSize)
            guard p.x >= 0, p.y >= 0, p.x <= videoSize.width, p.y <= videoSize.height else { return nil }
            return (click.time, p)
        }
        guard !points.isEmpty, duration > 0 else { return nil }

        let lead = 0.35, hold = 1.1, trail = 0.5, step = 1.0 / 8.0
        let center = CGPoint(x: videoSize.width / 2, y: videoSize.height / 2)

        func bump(_ t: Double, _ tc: Double) -> Double {
            if t < tc - lead || t > tc + hold + trail { return 0 }
            if t < tc { return (t - (tc - lead)) / lead }
            if t <= tc + hold { return 1 }
            return 1 - (t - (tc + hold)) / trail
        }
        func smoothstep(_ a: Double) -> Double { a * a * (3 - 2 * a) }

        var times: [NSNumber] = []
        var values: [NSValue] = []
        var t = 0.0
        while t < duration {
            var amount = 0.0
            var target = center
            for pt in points {
                let b = bump(t, pt.time)
                if b > amount { amount = b; target = pt.point }
            }
            let scale = 1 + (Self.zoomScale - 1) * CGFloat(smoothstep(amount))
            values.append(NSValue(caTransform3D: zoomTransform(to: target, scale: scale, center: center)))
            times.append(NSNumber(value: t / duration))
            t += step
        }
        values.append(NSValue(caTransform3D: CATransform3DIdentity))
        times.append(1.0)

        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = values
        animation.keyTimes = times
        animation.calculationMode = .linear
        animation.duration = duration
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
        return animation
    }

    /// Scale about `p` for a layer whose anchor point is its center.
    private func zoomTransform(to p: CGPoint, scale k: CGFloat, center: CGPoint) -> CATransform3D {
        let fx = p.x - center.x
        let fy = p.y - center.y
        var t = CATransform3DIdentity
        t = CATransform3DTranslate(t, fx, fy, 0)
        t = CATransform3DScale(t, k, k, 1)
        t = CATransform3DTranslate(t, -fx, -fy, 0)
        return t
    }

    // MARK: - Ripples

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

    // MARK: - Keystroke overlay

    @MainActor
    private func addKeystrokeCaptions(_ keystrokes: [RecordingKeystroke], videoSize: CGSize, to hud: CALayer) {
        guard !keystrokes.isEmpty else { return }
        let sorted = keystrokes.sorted { $0.time < $1.time }

        struct Run { var start: Double; var end: Double; var text: String }
        var runs: [Run] = []
        for key in sorted {
            if var last = runs.last, key.time - last.end <= 0.8 {
                last.end = key.time
                last.text += key.display
                runs[runs.count - 1] = last
            } else {
                runs.append(Run(start: key.time, end: key.time, text: key.display))
            }
        }

        let fontSize = videoSize.height * 0.035
        for run in runs {
            addCaption(String(run.text.suffix(24)), fontSize: fontSize, videoSize: videoSize, start: run.start, end: run.end + 0.9, to: hud)
        }
    }

    @MainActor
    private func addCaption(_ text: String, fontSize: CGFloat, videoSize: CGSize, start: Double, end: Double, to hud: CALayer) {
        // CATextLayer renders unreliably inside AVVideoCompositionCoreAnimationTool,
        // so rasterize the text to an image and use it as layer contents.
        guard let (textImage, textSize) = captionTextImage(text, fontSize: fontSize) else { return }
        let padX = fontSize * 0.7, padY = fontSize * 0.4
        let boxWidth = min(textSize.width + padX * 2, videoSize.width * 0.95)
        let boxHeight = textSize.height + padY * 2

        let box = CALayer()
        box.frame = CGRect(x: (videoSize.width - boxWidth) / 2, y: videoSize.height * 0.06, width: boxWidth, height: boxHeight)
        box.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        box.cornerRadius = boxHeight / 2
        box.opacity = 0

        let label = CALayer()
        label.frame = CGRect(x: (boxWidth - textSize.width) / 2, y: (boxHeight - textSize.height) / 2, width: textSize.width, height: textSize.height)
        label.contents = textImage
        label.contentsGravity = .resizeAspect
        box.addSublayer(label)

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.0, 1.0, 1.0, 0.0]
        fade.keyTimes = [0, 0.12, 0.82, 1.0]
        fade.duration = max(end - start, 0.5) + 0.4
        fade.beginTime = AVCoreAnimationBeginTimeAtZero + start
        fade.isRemovedOnCompletion = false
        fade.fillMode = .forwards
        box.add(fade, forKey: "kfade")
        hud.addSublayer(box)
    }

    @MainActor
    private func captionTextImage(_ text: String, fontSize: CGFloat) -> (image: CGImage, size: CGSize)? {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white])
        let bounds = attributed.size()
        let logicalWidth = ceil(bounds.width), logicalHeight = ceil(bounds.height)
        guard logicalWidth > 0, logicalHeight > 0 else { return nil }

        let scale: CGFloat = 2
        guard let context = CGContext(
            data: nil, width: Int(logicalWidth * scale), height: Int(logicalHeight * scale),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.scaleBy(x: scale, y: scale)
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        attributed.draw(at: .zero)
        NSGraphicsContext.restoreGraphicsState()

        guard let image = context.makeImage() else { return nil }
        return (image, CGSize(width: logicalWidth, height: logicalHeight))
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
