import CoreGraphics
import Foundation

public enum AppendOutcome: Sendable, Equatable {
    case appended(newRows: Int)
    case noNewContent
    case lowConfidence
}

/// Incrementally stitches scroll-capture frames into one tall image.
///
/// Each frame is the same screen region after the user scrolled down. The
/// stitcher finds the vertical offset `d` where `newFrame[0 ..< h-d]` matches
/// `previousFrame[d ..< h]` (two-stage SAD search: coarse on a downsampled
/// grayscale, then refined at full resolution) and appends the bottom `d` rows.
public final class ScrollStitcher {
    private var previousFrame: CGImage?
    private var slices: [CGImage] = []
    private var totalHeight = 0
    private var width = 0

    /// Minimum row overlap demanded between consecutive frames.
    private let minimumOverlap = 40
    /// Normalized mean-absolute-difference above this is a failed match.
    private let confidenceThreshold = 12.0

    public init() {}

    public func start(with firstFrame: CGImage) {
        previousFrame = firstFrame
        slices = [firstFrame]
        totalHeight = firstFrame.height
        width = firstFrame.width
    }

    public func append(_ frame: CGImage) -> AppendOutcome {
        guard let previous = previousFrame, frame.width == width else {
            start(with: frame)
            return .appended(newRows: frame.height)
        }

        guard let previousGray = GrayscaleImage(image: previous),
              let currentGray = GrayscaleImage(image: frame) else {
            return .lowConfidence
        }

        guard let offset = findScrollOffset(previous: previousGray, current: currentGray) else {
            return .lowConfidence
        }
        if offset == 0 {
            return .noNewContent
        }

        // New content is the bottom `offset` rows of the incoming frame.
        // CGImage cropping uses a top-left origin.
        let newRowsRect = CGRect(
            x: 0,
            y: CGFloat(frame.height - offset),
            width: CGFloat(width),
            height: CGFloat(offset)
        )
        guard let slice = frame.cropping(to: newRowsRect) else {
            return .lowConfidence
        }
        slices.append(slice)
        totalHeight += offset
        previousFrame = frame
        return .appended(newRows: offset)
    }

    /// Composites all slices into the final tall image.
    public func finish() -> CGImage? {
        guard !slices.isEmpty else { return nil }
        guard let context = CGContext(
            data: nil,
            width: width,
            height: totalHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        // CG origin is bottom-left; first slice belongs at the top.
        var y = CGFloat(totalHeight)
        for slice in slices {
            y -= CGFloat(slice.height)
            context.draw(slice, in: CGRect(x: 0, y: y, width: CGFloat(width), height: CGFloat(slice.height)))
        }
        return context.makeImage()
    }

    // MARK: - Offset search

    private func findScrollOffset(previous: GrayscaleImage, current: GrayscaleImage) -> Int? {
        let height = min(previous.height, current.height)
        let maxOffset = height - minimumOverlap
        guard maxOffset > 0 else { return nil }

        let coarseFactor = 8
        let previousCoarse = previous.downsampled(by: coarseFactor)
        let currentCoarse = current.downsampled(by: coarseFactor)

        var bestCoarse = 0
        var bestCoarseCost = Double.greatestFiniteMagnitude
        for offset in 0...(maxOffset / coarseFactor) {
            let cost = Self.overlapCost(previous: previousCoarse, current: currentCoarse, offset: offset)
            if cost < bestCoarseCost {
                bestCoarseCost = cost
                bestCoarse = offset
            }
        }

        var bestOffset = bestCoarse * coarseFactor
        var bestCost = Double.greatestFiniteMagnitude
        let low = max(0, bestCoarse * coarseFactor - coarseFactor)
        let high = min(maxOffset, bestCoarse * coarseFactor + coarseFactor)
        for offset in low...high {
            let cost = Self.overlapCost(previous: previous, current: current, offset: offset)
            if cost < bestCost {
                bestCost = cost
                bestOffset = offset
            }
        }

        guard bestCost < confidenceThreshold else { return nil }
        return bestOffset
    }

    /// Mean absolute difference between previous[offset...] and current[0...],
    /// sampled on a grid for speed.
    private static func overlapCost(previous: GrayscaleImage, current: GrayscaleImage, offset: Int) -> Double {
        let overlapRows = min(previous.height - offset, current.height)
        guard overlapRows > 8 else { return .greatestFiniteMagnitude }

        let rowStride = max(overlapRows / 64, 1)
        let colStride = max(previous.width / 96, 1)
        var total = 0
        var samples = 0
        var row = 0
        while row < overlapRows {
            let previousRowBase = (row + offset) * previous.width
            let currentRowBase = row * current.width
            var col = 0
            while col < previous.width {
                let difference = Int(previous.pixels[previousRowBase + col]) - Int(current.pixels[currentRowBase + col])
                total += abs(difference)
                samples += 1
                col += colStride
            }
            row += rowStride
        }
        guard samples > 0 else { return .greatestFiniteMagnitude }
        return Double(total) / Double(samples)
    }
}

/// 8-bit grayscale pixel buffer extracted from a CGImage (top-left origin).
struct GrayscaleImage {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init?(image: CGImage) {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let result: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard result else { return nil }
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    private init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Box-filtered downsample. Averaging (not point-sampling) keeps the SAD
    /// cost landscape smooth for offsets that are not multiples of `factor`,
    /// so the coarse search still dips near the true offset.
    func downsampled(by factor: Int) -> GrayscaleImage {
        guard factor > 1 else { return self }
        let newWidth = max(width / factor, 1)
        let newHeight = max(height / factor, 1)
        var result = [UInt8](repeating: 0, count: newWidth * newHeight)
        for row in 0..<newHeight {
            for col in 0..<newWidth {
                var sum = 0
                for dy in 0..<factor {
                    let sourceRow = (row * factor + dy) * width
                    for dx in 0..<factor {
                        sum += Int(pixels[sourceRow + col * factor + dx])
                    }
                }
                result[row * newWidth + col] = UInt8(sum / (factor * factor))
            }
        }
        return GrayscaleImage(width: newWidth, height: newHeight, pixels: result)
    }
}
