# SookraShot

Native macOS screenshot and screen-recording suite. Menu-bar app, built with Swift 6 (AppKit shell, SwiftUI views), ScreenCaptureKit, Vision, and AVFoundation. Personal tool for macOS 26 (Tahoe).

Capture area / window / fullscreen, get a floating corner thumbnail with instant Copy / Save / Annotate / Pin / drag-and-drop, plus OCR text capture (with auto-redaction of secrets and PII), MP4/GIF recording, scrolling capture, pinned screenshots, 30-day capture history, and a settings window with remappable global shortcuts.

## Usage

Default shortcuts (remap in Settings; disable the system ones in System Settings > Keyboard > Keyboard Shortcuts > Screenshots so SookraShot owns them):

| Shortcut | Action |
|---|---|
| Cmd+Shift+3 | Capture fullscreen |
| Cmd+Shift+4 | Capture area / click a window |
| Cmd+Shift+5 | All-in-one |
| Cmd+Shift+2 | Capture text (OCR to clipboard) |
| Cmd+Shift+6 | Record screen (press again to stop) |
| Cmd+Shift+7 | Scrolling capture |

URL scheme: `sookrashot://capture-area`, `capture-fullscreen`, `capture-text`, `record-screen` (`?mic=1`), `stop-recording`, `scrolling-capture` — usable from Raycast, Shortcuts, or scripts.

## Roadmap

Self-timer, capture-previous-area, window-with-background beautify, recording trim editor, auto-scroll for scrolling capture (needs Accessibility permission), smart OCR filenames, send-to-Claude, background removal, color sampler, Liquid Glass (`NSGlassEffectView`) panel styling.

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
