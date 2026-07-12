import AIKit
import AppKit
import BeautifyKit
import CloudShareKit
import HotkeyKit
import ServiceManagement
import SharedKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private static var shared: SettingsWindowController?

    static func present() {
        let controller = shared ?? SettingsWindowController()
        shared = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "SookraShot Settings"
        window.contentViewController = NSHostingController(rootView: SettingsRootView())
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}

private struct SettingsRootView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            HotkeySettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            AISettingsView()
                .tabItem { Label("Ask Claude", systemImage: "sparkles") }
            CloudShareSettingsView()
                .tabItem { Label("Cloud Share", systemImage: "link") }
        }
        .frame(width: 500, height: 380)
    }
}

private struct GeneralSettingsView: View {
    @AppStorage("imageFormat") private var imageFormat = ImageFormat.png.rawValue
    @AppStorage("overlayCorner") private var overlayCorner = OverlayCorner.bottomLeft.rawValue
    @AppStorage("saveDirectoryPath") private var saveDirectoryPath = ""
    @AppStorage("openTrimEditorAfterRecording") private var openTrimEditorAfterRecording = false
    @AppStorage("addClickEffectsToRecordings") private var addClickEffectsToRecordings = false
    @AppStorage("autoZoomRecordings") private var autoZoomRecordings = false
    @AppStorage("keystrokeOverlayRecordings") private var keystrokeOverlayRecordings = false
    @AppStorage("beautifyBackground") private var beautifyBackground = BeautifyBackground.ocean.rawValue
    @AppStorage("beautifyFrame") private var beautifyFrame = BeautifyFrame.none.rawValue
    @AppStorage("smartFilenames") private var smartFilenames = false
    @AppStorage("captureDelaySeconds") private var captureDelaySeconds = 0
    @AppStorage("autoScrollScrollingCapture") private var autoScrollScrollingCapture = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                LabeledContent("Save to") {
                    HStack {
                        Text(displayedSavePath)
                            .truncationMode(.middle)
                            .lineLimit(1)
                        Button("Choose…") { chooseSaveDirectory() }
                    }
                }
                Picker("Image format", selection: $imageFormat) {
                    ForEach(ImageFormat.allCases, id: \.rawValue) { format in
                        Text(format.rawValue.uppercased()).tag(format.rawValue)
                    }
                }
                Toggle("Name saved files from their text (OCR)", isOn: $smartFilenames)
                Picker("Self-timer (fullscreen)", selection: $captureDelaySeconds) {
                    Text("Off").tag(0)
                    Text("3 seconds").tag(3)
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                }
                Toggle("Auto-scroll during scrolling capture", isOn: $autoScrollScrollingCapture)
                Picker("Thumbnail corner", selection: $overlayCorner) {
                    Text("Bottom Left").tag(OverlayCorner.bottomLeft.rawValue)
                    Text("Bottom Right").tag(OverlayCorner.bottomRight.rawValue)
                    Text("Top Left").tag(OverlayCorner.topLeft.rawValue)
                    Text("Top Right").tag(OverlayCorner.topRight.rawValue)
                }
                Toggle("Open trim editor after recording", isOn: $openTrimEditorAfterRecording)
                Toggle("Add click ripples to recordings", isOn: $addClickEffectsToRecordings)
                Toggle("Auto-zoom to cursor in recordings", isOn: $autoZoomRecordings)
                Toggle("Show keystrokes in recordings", isOn: $keystrokeOverlayRecordings)
                Picker("Beautify background", selection: $beautifyBackground) {
                    ForEach(BeautifyBackground.allCases, id: \.rawValue) { background in
                        Text(background.title).tag(background.rawValue)
                    }
                }
                Picker("Beautify frame", selection: $beautifyFrame) {
                    ForEach(BeautifyFrame.allCases, id: \.rawValue) { frame in
                        Text(frame.title).tag(frame.rawValue)
                    }
                }
            }
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            NSLog("SookraShot launch-at-login toggle failed: \(error)")
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
            Section {
                Text("To let SookraShot own Cmd+Shift+3/4/5, turn off the system screenshot shortcuts in System Settings > Keyboard > Keyboard Shortcuts > Screenshots.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Open Keyboard Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(4)
    }

    private var displayedSavePath: String {
        saveDirectoryPath.isEmpty ? "~/Desktop" : (saveDirectoryPath as NSString).abbreviatingWithTildeInPath
    }

    private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            saveDirectoryPath = url.path
        }
    }
}

private struct AISettingsView: View {
    @State private var hasKey = KeychainStore.hasKey
    @State private var keyDraft = ""

    var body: some View {
        Form {
            Section("Anthropic API key") {
                if hasKey {
                    LabeledContent("Status") {
                        Label("A key is saved in your Keychain", systemImage: "checkmark.seal")
                            .foregroundStyle(.green)
                    }
                    Button("Remove Key", role: .destructive) {
                        KeychainStore.deleteAPIKey()
                        hasKey = false
                    }
                } else {
                    SecureField("sk-ant-…", text: $keyDraft)
                        .onSubmit(saveKey)
                    Button("Save Key") { saveKey() }
                        .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Link("Get a key at console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
            }
            Section {
                Text("Ask Claude (Cmd+Shift+8, the sparkles button on a thumbnail, or sookrashot://ask-claude) sends the capture to Claude Fable 5 to explain errors, extract Markdown, turn a screenshot into code, or answer any question about it. The key is stored only in your macOS Keychain.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Claude Fable 5 requires standard (non-zero) data retention on your Anthropic org.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding(4)
    }

    private func saveKey() {
        KeychainStore.setAPIKey(keyDraft)
        hasKey = KeychainStore.hasKey
        keyDraft = ""
    }
}

private struct CloudShareSettingsView: View {
    @AppStorage(B2Settings.Key.bucket) private var bucket = ""
    @AppStorage(B2Settings.Key.region) private var region = ""
    @AppStorage(B2Settings.Key.linkMode) private var linkMode = B2LinkMode.presigned.rawValue
    @AppStorage(B2Settings.Key.presignedHours) private var presignedHours = 168

    @State private var hasCredentials = B2CredentialStore.hasCredentials
    @State private var keyIDDraft = ""
    @State private var appKeyDraft = ""

    var body: some View {
        Form {
            Section("Backblaze B2 credentials") {
                if hasCredentials {
                    LabeledContent("Status") {
                        Label("Application key saved in your Keychain", systemImage: "checkmark.seal")
                            .foregroundStyle(.green)
                    }
                    Button("Remove Credentials", role: .destructive) {
                        B2CredentialStore.clear()
                        hasCredentials = false
                    }
                } else {
                    TextField("Key ID", text: $keyIDDraft)
                    SecureField("Application Key", text: $appKeyDraft)
                    Button("Save Credentials") { saveCredentials() }
                        .disabled(keyIDDraft.trimmingCharacters(in: .whitespaces).isEmpty
                            || appKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section("Bucket") {
                TextField("Bucket name", text: $bucket)
                TextField("Region (e.g. us-west-004)", text: $region)
                Picker("Link type", selection: $linkMode) {
                    Text("Presigned (private bucket)").tag(B2LinkMode.presigned.rawValue)
                    Text("Public URL (public bucket)").tag(B2LinkMode.publicURL.rawValue)
                }
                if linkMode == B2LinkMode.presigned.rawValue {
                    Stepper("Link expires after \(presignedHours) h", value: $presignedHours, in: 1...720, step: 24)
                }
            }
            Section {
                Text("Share as Link (Cmd+Shift+9, the link button on a thumbnail, or sookrashot://cloud-share) uploads a capture to your B2 bucket over the S3-compatible API and copies the link. Credentials are stored only in your macOS Keychain.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("The region is the one in your bucket's S3 endpoint (s3.<region>.backblazeb2.com).")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding(4)
    }

    private func saveCredentials() {
        B2CredentialStore.set(keyID: keyIDDraft, appKey: appKeyDraft)
        hasCredentials = B2CredentialStore.hasCredentials
        keyIDDraft = ""
        appKeyDraft = ""
    }
}
