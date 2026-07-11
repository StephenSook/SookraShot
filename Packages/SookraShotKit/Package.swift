// swift-tools-version: 6.0
import PackageDescription

let modules = [
    "SharedKit",
    "CaptureKit",
    "OverlayKit",
    "QuickAccessKit",
    "AnnotationKit",
    "OCRKit",
    "RecordingKit",
    "ScrollCaptureKit",
    "HotkeyKit",
    "HistoryKit",
    "PinKit",
    "ExportKit",
]

let package = Package(
    name: "SookraShotKit",
    platforms: [.macOS("26.0")],
    products: modules.map { .library(name: $0, targets: [$0]) },
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0")
    ],
    targets: modules.map { name -> Target in
        var dependencies: [Target.Dependency] = name == "SharedKit" ? [] : ["SharedKit"]
        if name == "HotkeyKit" {
            dependencies.append(.product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"))
        }
        if name == "QuickAccessKit" {
            dependencies.append(contentsOf: ["ExportKit", "OCRKit"])
        }
        if name == "AnnotationKit" {
            dependencies.append(contentsOf: ["ExportKit", "OCRKit"])
        }
        return .target(name: name, dependencies: dependencies)
    } + [
        .testTarget(name: "SharedKitTests", dependencies: ["SharedKit"]),
        .testTarget(name: "OCRKitTests", dependencies: ["OCRKit"]),
        .testTarget(name: "AnnotationKitTests", dependencies: ["AnnotationKit"]),
        .testTarget(name: "RecordingKitTests", dependencies: ["RecordingKit"]),
    ]
)
