import Foundation

/// Events streamed back from a single vision request.
public enum AIStreamEvent: Sendable {
    /// The model that actually produced the answer (Fable 5, or the fallback).
    case servedModel(String)
    /// An incremental chunk of answer text.
    case textDelta(String)
    /// Safety classifiers declined the request.
    case refused
}

public struct AIClientError: LocalizedError, Sendable {
    public let message: String
    /// Set when the failure looks like the fallback beta isn't enabled, so the
    /// caller can retry the same request without it.
    let retryWithoutFallback: Bool

    init(message: String, retryWithoutFallback: Bool = false) {
        self.message = message
        self.retryWithoutFallback = retryWithoutFallback
    }

    public var errorDescription: String? { message }
}

/// Calls the Anthropic Messages API with an image + prompt and streams the
/// answer. Swift has no official Anthropic SDK, so this speaks the raw HTTPS
/// wire format via URLSession.
///
/// Model is Claude Fable 5: thinking is always on (the `thinking` field is
/// omitted), no sampling parameters, and safety classifiers can return
/// `stop_reason: "refusal"` on a 200. Server-side `fallbacks` to Opus 4.8 is
/// opted in by default; if the beta isn't enabled on the key, the request is
/// retried once without it.
public struct AnthropicVisionClient: Sendable {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-fable-5"
    private static let fallbackModel = "claude-opus-4-8"
    private static let apiVersion = "2023-06-01"
    private static let fallbackBeta = "server-side-fallback-2026-06-01"

    public init() {}

    public func stream(
        imageBase64: String,
        action: AIAction,
        customPrompt: String?,
        apiKey: String
    ) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    do {
                        try await run(
                            imageBase64: imageBase64, action: action, customPrompt: customPrompt,
                            apiKey: apiKey, useFallback: true, continuation: continuation
                        )
                    } catch let error as AIClientError where error.retryWithoutFallback {
                        try await run(
                            imageBase64: imageBase64, action: action, customPrompt: customPrompt,
                            apiKey: apiKey, useFallback: false, continuation: continuation
                        )
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        imageBase64: String,
        action: AIAction,
        customPrompt: String?,
        apiKey: String,
        useFallback: Bool,
        continuation: AsyncThrowingStream<AIStreamEvent, Error>.Continuation
    ) async throws {
        let request = try makeRequest(
            imageBase64: imageBase64, action: action, customPrompt: customPrompt,
            apiKey: apiKey, useFallback: useFallback
        )
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIClientError(message: "No response from Claude.")
        }
        guard http.statusCode == 200 else {
            throw await Self.readError(from: bytes, status: http.statusCode, usedFallback: useFallback)
        }

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            guard !payload.isEmpty,
                  let data = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String
            else { continue }

            switch type {
            case "message_start":
                if let message = event["message"] as? [String: Any],
                   let model = message["model"] as? String {
                    continuation.yield(.servedModel(model))
                }
            case "content_block_start":
                // A `fallback` block marks the switch to the fallback model.
                if let block = event["content_block"] as? [String: Any],
                   block["type"] as? String == "fallback",
                   let to = block["to"] as? [String: Any],
                   let model = to["model"] as? String {
                    continuation.yield(.servedModel(model))
                }
            case "content_block_delta":
                if let delta = event["delta"] as? [String: Any],
                   delta["type"] as? String == "text_delta",
                   let text = delta["text"] as? String {
                    continuation.yield(.textDelta(text))
                }
            case "message_delta":
                if let delta = event["delta"] as? [String: Any],
                   delta["stop_reason"] as? String == "refusal" {
                    continuation.yield(.refused)
                }
            case "error":
                let message = (event["error"] as? [String: Any])?["message"] as? String
                throw AIClientError(message: message ?? "Claude returned an error.")
            default:
                break
            }
        }
    }

    private func makeRequest(
        imageBase64: String,
        action: AIAction,
        customPrompt: String?,
        apiKey: String,
        useFallback: Bool
    ) throws -> URLRequest {
        let promptText = customPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCustomPrompt = !(promptText ?? "").isEmpty
        let effectivePrompt = hasCustomPrompt ? promptText! : action.userPrompt

        var body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 8192,
            "stream": true,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": imageBase64]],
                    ["type": "text", "text": effectivePrompt],
                ],
            ]],
        ]
        if useFallback {
            body["fallbacks"] = [["model": Self.fallbackModel]]
        }
        // A typed follow-up question overrides the action's own framing.
        if !hasCustomPrompt, let system = action.systemPrompt {
            body["system"] = system
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        if useFallback {
            request.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func readError(
        from bytes: URLSession.AsyncBytes,
        status: Int,
        usedFallback: Bool
    ) async -> AIClientError {
        var raw = Data()
        if let collected = try? await collect(bytes) { raw = collected }

        let parsed = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]
        let apiMessage = (parsed?["error"] as? [String: Any])?["message"] as? String

        let message = apiMessage ?? defaultMessage(for: status)
        let lower = message.lowercased()
        let looksLikeBeta = usedFallback && status == 400
            && (lower.contains("fallback") || lower.contains("beta"))
        return AIClientError(message: message, retryWithoutFallback: looksLikeBeta)
    }

    private static func collect(_ bytes: URLSession.AsyncBytes) async throws -> Data {
        var raw = Data()
        for try await byte in bytes {
            raw.append(byte)
            if raw.count > 64 * 1024 { break }
        }
        return raw
    }

    private static func defaultMessage(for status: Int) -> String {
        switch status {
        case 401: "Invalid API key (HTTP 401). Check your Anthropic API key in Settings."
        case 400: "Request rejected (HTTP 400). Claude Fable 5 requires standard (non-zero) data retention on your Anthropic org."
        case 429: "Rate limited (HTTP 429). Wait a moment and try again."
        case 529: "Claude is overloaded (HTTP 529). Try again shortly."
        default: "Claude request failed (HTTP \(status))."
        }
    }
}
