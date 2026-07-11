# SookraShot

Native macOS screenshot and screen-recording suite. Menu-bar app, built with Swift 6 (AppKit shell, SwiftUI views), ScreenCaptureKit, Vision, and AVFoundation. Personal tool for macOS 26 (Tahoe).

Capture area / window / fullscreen, get a floating corner thumbnail with instant Copy / Save / Annotate / drag-and-drop, plus OCR text capture, MP4/GIF recording, and scrolling capture.

## Build

Requirements: macOS 26+, Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
xcodebuild -project SookraShot.xcodeproj -scheme SookraShot -configuration Release build
```

Run tests for the core packages:

```sh
swift test --package-path Packages/SookraShotKit
```

## Architecture

Thin AppKit shell in `App/`; all logic in `Packages/SookraShotKit` as independent modules (CaptureKit, OverlayKit, QuickAccessKit, AnnotationKit, OCRKit, RecordingKit, ScrollCaptureKit, HotkeyKit, HistoryKit, PinKit, ExportKit, SharedKit).

## Permissions

Screen Recording (capture), Microphone (only if mic audio is enabled for recordings). Global hotkeys use Carbon `RegisterEventHotKey` and require no extra permissions.

## License

MIT. Uses [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (MIT). Scroll-stitching approach informed by [ScrollSnap](https://github.com/Brkgng/ScrollSnap) (MIT).
