import SwiftUI

/// The Ask Claude panel UI: a thumbnail, the four preset actions, a streaming
/// answer, and a free-form follow-up field. Shows an API-key entry card until a
/// key is stored.
struct AskClaudeView: View {
    @Bindable var model: AskClaudeModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.hasKey {
                actionBar
                Divider()
                answerArea
                Divider()
                footer
            } else {
                keyEntry
            }
        }
        .frame(minWidth: 460, minHeight: 440)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: model.thumbnail)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 120, maxHeight: 70)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            VStack(alignment: .leading, spacing: 2) {
                Text("Ask Claude")
                    .font(.headline)
                Text("About this capture")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            ForEach(AIAction.allCases) { action in
                Button {
                    model.run(action: action)
                } label: {
                    Label(action.title, systemImage: action.symbol)
                        .labelStyle(.iconOnly)
                        .frame(width: 26, height: 20)
                }
                .help(action.title)
                .buttonStyle(.bordered)
                .tint(model.selectedAction == action ? .accentColor : nil)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .disabled(model.isStreaming)
    }

    private var answerArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let errorText = model.errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                } else if model.refused, model.answer.isEmpty {
                    Label("Claude declined this request.", systemImage: "hand.raised")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else if model.answer.isEmpty, model.isStreaming {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Thinking…").foregroundStyle(.secondary)
                    }
                } else if model.answer.isEmpty {
                    Text("Pick an action above or ask a question below.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    Text(model.answer)
                        .font(model.selectedAction?.prefersMonospaced == true ? .system(.body, design: .monospaced) : .body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
        }
        .frame(minHeight: 180)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            TextField("Ask anything about this capture…", text: $model.followUp)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.ask() }
                .disabled(model.isStreaming)
            if model.isStreaming {
                Button("Stop") { model.cancel() }
            } else {
                Button("Ask") { model.ask() }
                    .keyboardShortcut(.return)
                    .disabled(model.followUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Button {
                model.copyAnswer()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy answer")
            .disabled(model.answer.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .bottomTrailing) {
            Text(model.modelLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.trailing, 12)
                .padding(.bottom, 2)
                .offset(y: 14)
        }
    }

    private var keyEntry: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add your Anthropic API key")
                .font(.headline)
            Text("Ask Claude sends the capture to the Anthropic API using Claude Fable 5. The key is stored in your macOS Keychain and never leaves this Mac otherwise.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("sk-ant-…", text: $model.keyDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.saveKey() }
            HStack {
                Link("Get a key at console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                    .font(.callout)
                Spacer()
                Button("Save Key") { model.saveKey() }
                    .keyboardShortcut(.return)
                    .disabled(model.keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Claude Fable 5 requires standard (non-zero) data retention on your Anthropic org.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(16)
    }
}
