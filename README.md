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
| Cmd+Shift+8 | Ask Claude about a selected region |

URL scheme: `sookrashot://capture-area`, `capture-fullscreen`, `capture-text`, `record-screen` (`?mic=1`), `stop-recording`, `scrolling-capture`, `ask-claude` — usable from Raycast, Shortcuts, or scripts.

## Ask Claude

Send any capture to Claude and get an answer in a floating panel: **explain / fix an error** from a screenshot of a terminal or stack trace, **extract it as Markdown**, turn a **screenshot into code** (SwiftUI or HTML), or **describe / translate / ask anything**. Trigger it with Cmd+Shift+8 (select a region), the sparkles button on a capture thumbnail, or `sookrashot://ask-claude`; a follow-up field lets you ask arbitrary questions about the same image.

Uses the Anthropic Messages API with Claude Fable 5 (falls back to Claude Opus 4.8 if a request is declined). Paste an [Anthropic API key](https://console.anthropic.com/settings/keys) in Settings > Ask Claude the first time; it is stored only in your macOS Keychain. Claude Fable 5 requires standard (non-zero) data retention on your Anthropic org.

## Roadmap

Self-timer, capture-previous-area, window-with-background beautify, recording trim editor, auto-scroll for scrolling capture (needs Accessibility permission), smart OCR filenames, cloud share to Backblaze B2, background removal, color sampler, Liquid Glass (`NSGlassEffectView`) panel styling.

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

Thin AppKit shell in `App/`; all logic in `Packages/SookraShotKit` as independent modules (CaptureKit, OverlayKit, QuickAccessKit, AnnotationKit, OCRKit, RecordingKit, ScrollCaptureKit, HotkeyKit, HistoryKit, PinKit, ExportKit, AIKit, SharedKit).

## Permissions

- **Screen Recording** — capturing pixels (ScreenCaptureKit).
- **Accessibility** — the drag-to-select overlay uses a session-level `CGEvent` tap so the selection works over any app; macOS gates event taps behind Accessibility. Granted once, prompted on first area capture.
- **Microphone** — only if mic audio is enabled for a recording.

Ask Claude is the only feature that touches the network: it sends the selected capture to the Anthropic API over HTTPS. Everything else is fully local.

Global hotkeys use Carbon `RegisterEventHotKey` and need no extra permission. Sign with a stable identity (a free Apple Development cert) so the Screen Recording and Accessibility grants persist across rebuilds.

## License

MIT. Uses [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (MIT). Scroll-stitching approach informed by [ScrollSnap](https://github.com/Brkgng/ScrollSnap) (MIT).
