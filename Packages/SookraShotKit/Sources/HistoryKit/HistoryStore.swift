import Foundation
import ExportKit
import SharedKit

/// Keeps a rolling on-disk history of captures (30 days) in Application Support.
public struct HistoryStore: Sendable {
    public static let retentionDays = 30

    private let encoder = ImageEncoder()

    public init() {}

    public var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SookraShot/History", isDirectory: true)
    }

    /// Writes the capture into history and prunes expired entries.
    public func record(_ capture: DeliveredCapture) {
        let directory = self.directory
        let image = capture.image
        let capturedAt = capture.capturedAt
        Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                guard let data = ImageEncoder().data(from: image, format: .png) else { return }
                let stamp = ISO8601DateFormatter().string(from: capturedAt)
                    .replacingOccurrences(of: ":", with: ".")
                let url = directory.appendingPathComponent("Capture \(stamp).png")
                try data.write(to: url)
                prune(in: directory)
            } catch {
                NSLog("SookraShot history write failed: \(error)")
            }
        }
    }

    public func recentFiles(limit: Int = 10) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        )) ?? []
        return contents
            .filter { $0.pathExtension == "png" }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }
            .prefix(limit)
            .map { $0 }
    }
}

private func prune(in directory: URL) {
    let cutoff = Date().addingTimeInterval(-Double(HistoryStore.retentionDays) * 86400)
    let contents = (try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: .skipsHiddenFiles
    )) ?? []
    for url in contents {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantFuture
        if modified < cutoff {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
