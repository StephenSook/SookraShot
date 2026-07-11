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
    targets: modules.map { name in
        .target(
            name: name,
            dependencies: name == "SharedKit" ? [] : ["SharedKit"]
        )
    } + [
        .testTarget(name: "SharedKitTests", dependencies: ["SharedKit"])
    ]
)
