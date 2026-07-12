import AppKit
import Observation
import SharedKit

/// Drives the Ask Claude panel: runs a preset action or a typed question about
/// one capture and streams the answer into observable state.
@MainActor
@Observable
public final class AskClaudeModel {
    public let capture: DeliveredCapture

    var answer: String = ""
    var isStreaming = false
    var refused = false
    var errorText: String?
    var servedModel: String?
    var selectedAction: AIAction?
    var followUp: String = ""
    var hasKey: Bool = KeychainStore.hasKey
    var keyDraft: String = ""

    private let client = AnthropicVisionClient()
    private var task: Task<Void, Never>?

    public init(capture: DeliveredCapture) {
        self.capture = capture
    }

    var thumbnail: NSImage {
        NSImage(cgImage: capture.image, size: NSSize(width: capture.image.width, height: capture.image.height))
    }

    var modelLabel: String {
        switch servedModel {
        case .some(let model) where model.contains("fable"): "Claude Fable 5"
        case .some(let model) where model.contains("opus"): "Claude Opus 4.8 (fallback)"
        case .some(let model): model
        case nil: "Claude Fable 5"
        }
    }

    func saveKey() {
        KeychainStore.setAPIKey(keyDraft)
        hasKey = KeychainStore.hasKey
        keyDraft = ""
    }

    func run(action: AIAction) {
        followUp = ""
        start(action: action, customPrompt: nil)
    }

    func ask() {
        let prompt = followUp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        start(action: .describe, customPrompt: prompt)
    }

    func cancel() {
        task?.cancel()
        isStreaming = false
    }

    func copyAnswer() {
        guard !answer.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(answer, forType: .string)
    }

    private func start(action: AIAction, customPrompt: String?) {
        guard let apiKey = KeychainStore.apiKey else {
            hasKey = false
            return
        }
        guard let imageBase64 = CaptureImageEncoder.base64PNG(from: capture.image) else {
            errorText = "Could not encode the capture."
            return
        }
        task?.cancel()
        selectedAction = action
        answer = ""
        errorText = nil
        refused = false
        servedModel = nil
        isStreaming = true

        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                for try await event in self.client.stream(
                    imageBase64: imageBase64, action: action, customPrompt: customPrompt, apiKey: apiKey
                ) {
                    switch event {
                    case .servedModel(let model): self.servedModel = model
                    case .textDelta(let text): self.answer += text
                    case .refused: self.refused = true
                    }
                }
            } catch is CancellationError {
                // Superseded by a newer request; leave state alone.
            } catch {
                self.errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            self.isStreaming = false
        }
    }
}
