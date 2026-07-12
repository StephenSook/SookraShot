import SwiftUI

/// The cloud-share HUD: a spinner while uploading, the copied link on success,
/// an error with retry on failure, or a prompt to configure B2.
struct CloudShareView: View {
    @Bindable var model: CloudShareModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch model.state {
            case .uploading:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Uploading to Backblaze B2…")
                }
            case .done(let url):
                Label("Link copied to clipboard", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                Text(url.absoluteString)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Button {
                        model.copyLink()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    Button {
                        model.openLink()
                    } label: {
                        Label("Open", systemImage: "safari")
                    }
                    Spacer()
                }
            case .failed(let message):
                Label("Upload failed", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Retry") { model.start() }
                    Button("Settings…") { model.onOpenSettings?() }
                    Spacer()
                }
            case .notConfigured:
                Label("Backblaze B2 not set up", systemImage: "cloud")
                    .font(.headline)
                Text("Add your B2 application key, bucket, and region in Settings > Cloud Share to share captures as links.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Settings…") { model.onOpenSettings?() }
            }
        }
        .padding(16)
        .frame(width: 380, alignment: .leading)
    }
}
