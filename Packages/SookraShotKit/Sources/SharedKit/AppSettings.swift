import Foundation

public enum ImageFormat: String, Sendable, CaseIterable {
    case png
    case jpeg
    case heic

    public var fileExtension: String { rawValue }
}

public enum OverlayCorner: String, Sendable, CaseIterable {
    case bottomLeft
    case bottomRight
    case topLeft
    case topRight
}

/// UserDefaults-backed app settings.
public struct AppSettings: Sendable {
    public static let shared = AppSettings()

    private var defaults: UserDefaults { .standard }

    public init() {}

    public var saveDirectory: URL {
        if let path = defaults.string(forKey: "saveDirectoryPath") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    public var imageFormat: ImageFormat {
        defaults.string(forKey: "imageFormat").flatMap(ImageFormat.init(rawValue:)) ?? .png
    }

    public var overlayCorner: OverlayCorner {
        defaults.string(forKey: "overlayCorner").flatMap(OverlayCorner.init(rawValue:)) ?? .bottomLeft
    }

    public var filenameTemplate: FilenameTemplate {
        defaults.string(forKey: "filenameTemplate").map(FilenameTemplate.init(pattern:)) ?? .default
    }

    public var openTrimEditorAfterRecording: Bool {
        defaults.bool(forKey: "openTrimEditorAfterRecording")
    }

    public var addClickEffectsToRecordings: Bool {
        defaults.bool(forKey: "addClickEffectsToRecordings")
    }

    public var beautifyBackground: String {
        defaults.string(forKey: "beautifyBackground") ?? "ocean"
    }

    public var beautifyFrame: String {
        defaults.string(forKey: "beautifyFrame") ?? "none"
    }

    public var smartFilenames: Bool {
        defaults.bool(forKey: "smartFilenames")
    }

    public var captureDelaySeconds: Int {
        defaults.integer(forKey: "captureDelaySeconds")
    }

    public var autoScrollScrollingCapture: Bool {
        defaults.bool(forKey: "autoScrollScrollingCapture")
    }
}
