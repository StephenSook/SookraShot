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
| Cmd+Shift+9 | Share a selected region as a link (Backblaze B2) |
| Cmd+Shift+0 | Sample a screen color (copies hex) |

URL scheme: `sookrashot://capture-area`, `capture-fullscreen`, `capture-text`, `record-screen` (`?mic=1`), `stop-recording`, `scrolling-capture`, `ask-claude`, `cloud-share`, `sample-color`, `capture-previous-area` — usable from Raycast, Shortcuts, or scripts.

Other conveniences: **Capture Previous Area** re-shoots the last region without the overlay; a **self-timer** (Settings > General) delays a fullscreen capture; **Copy as Markdown code** on a thumbnail wraps the OCR'd text in a fenced code block; and turning on **Name saved files from their text** derives filenames from a capture's content. The Quick Access panel uses macOS 26 Liquid Glass.

Recordings can be trimmed: pick **Trim a Video…** from the menu bar (or turn on "Open trim editor after recording" in Settings) to open a clip in the native QuickTime-style trim UI and export the selected range.

Turn on **Add click ripples to recordings** in Settings to bake an animated highlight at every mouse click into display and area recordings (great for demo videos). Auto-zoom to the cursor and a keystroke overlay are planned follow-ups.

## Ask Claude

Send any capture to Claude and get an answer in a floating panel: **explain / fix an error** from a screenshot of a terminal or stack trace, **extract it as Markdown**, turn a **screenshot into code** (SwiftUI or HTML), or **describe / translate / ask anything**. Trigger it with Cmd+Shift+8 (select a region), the sparkles button on a capture thumbnail, or `sookrashot://ask-claude`; a follow-up field lets you ask arbitrary questions about the same image.

Uses the Anthropic Messages API with Claude Fable 5 (falls back to Claude Opus 4.8 if a request is declined). Paste an [Anthropic API key](https://console.anthropic.com/settings/keys) in Settings > Ask Claude the first time; it is stored only in your macOS Keychain. Claude Fable 5 requires standard (non-zero) data retention on your Anthropic org.

## Cloud share (Backblaze B2)

Upload a capture to your own Backblaze B2 bucket and get a link on the clipboard: Cmd+Shift+9 (select a region), the link button on a capture thumbnail, or `sookrashot://cloud-share`. This is a self-hosted replacement for a paid screenshot cloud, using infrastructure you already own.

B2's S3-compatible API is signed with AWS Signature V4 (all local, no third-party SDK). In Settings > Cloud Share, add your B2 application key ID + key (stored in the Keychain), the bucket name, and the region from the bucket's S3 endpoint (`s3.<region>.backblazeb2.com`). Links are presigned with a configurable expiry by default, or plain public URLs if the bucket is public.

## Beautify and safe share

Two more buttons on the Quick Access thumbnail:

- **Beautify** composites the capture onto a padded gradient background with a shadow and rounded corners, for social/chat posts. Pick the gradient and an optional macOS-window or browser frame in Settings > General.
- **Redact & copy** (safe share) runs OCR to find secrets and PII (API keys, emails, tokens, card numbers) plus faces, blacks those regions out, and copies the redacted image. All on-device.
- **Remove background** cuts the foreground subject out to a transparent PNG (Vision's foreground instance mask, on-device); save it as PNG to keep the transparency.

## Roadmap

Recording auto-zoom to cursor + keystroke overlay.

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

Thin AppKit shell in `App/`; all logic in `Packages/SookraShotKit` as independent modules (CaptureKit, OverlayKit, QuickAccessKit, AnnotationKit, OCRKit, RecordingKit, ScrollCaptureKit, HotkeyKit, HistoryKit, PinKit, ExportKit, AIKit, CloudShareKit, BeautifyKit, SharedKit).

## Permissions

- **Screen Recording** — capturing pixels (ScreenCaptureKit).
- **Accessibility** — the drag-to-select overlay uses a session-level `CGEvent` tap so the selection works over any app; macOS gates event taps behind Accessibility. Granted once, prompted on first area capture.
- **Microphone** — only if mic audio is enabled for a recording.

Only two features touch the network, both over HTTPS: Ask Claude sends a capture to the Anthropic API, and Cloud Share uploads a capture to your Backblaze B2 bucket. Everything else is fully local.

Global hotkeys use Carbon `RegisterEventHotKey` and need no extra permission. Sign with a stable identity (a free Apple Development cert) so the Screen Recording and Accessibility grants persist across rebuilds.

## License

MIT. Uses [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (MIT). Scroll-stitching approach informed by [ScrollSnap](https://github.com/Brkgng/ScrollSnap) (MIT).
