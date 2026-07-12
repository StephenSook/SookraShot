import AIKit
import AppKit
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
        }
        .frame(width: 500, height: 380)
    }
}

private struct GeneralSettingsView: View {
    @AppStorage("imageFormat") private var imageFormat = ImageFormat.png.rawValue
    @AppStorage("overlayCorner") private var overlayCorner = OverlayCorner.bottomLeft.rawValue
    @AppStorage("saveDirectoryPath") private var saveDirectoryPath = ""
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
                Picker("Thumbnail corner", selection: $overlayCorner) {
                    Text("Bottom Left").tag(OverlayCorner.bottomLeft.rawValue)
                    Text("Bottom Right").tag(OverlayCorner.bottomRight.rawValue)
                    Text("Top Left").tag(OverlayCorner.topLeft.rawValue)
                    Text("Top Right").tag(OverlayCorner.topRight.rawValue)
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
