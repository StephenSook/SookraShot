import Foundation

/// One preset way to ask Claude about a capture. Each maps to a system/user
/// prompt pair sent alongside the image.
public enum AIAction: String, CaseIterable, Sendable, Identifiable {
    case explainError
    case extractMarkdown
    case screenshotToCode
    case describe

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .explainError: "Explain / fix error"
        case .extractMarkdown: "Extract as Markdown"
        case .screenshotToCode: "Screenshot to code"
        case .describe: "Describe / translate"
        }
    }

    public var symbol: String {
        switch self {
        case .explainError: "ladybug"
        case .extractMarkdown: "text.alignleft"
        case .screenshotToCode: "curlybraces"
        case .describe: "text.bubble"
        }
    }

    /// Code answers read better in a monospaced font.
    public var prefersMonospaced: Bool { self == .screenshotToCode }

    var systemPrompt: String? {
        switch self {
        case .explainError:
            "You are a senior software engineer helping a developer debug from a screenshot of a terminal, log, compiler output, or error dialog."
        case .extractMarkdown:
            "You transcribe screenshots into clean, faithful Markdown."
        case .screenshotToCode:
            "You are an expert macOS and front-end UI engineer who reproduces interfaces from screenshots."
        case .describe:
            nil
        }
    }

    var userPrompt: String {
        switch self {
        case .explainError:
            "This screenshot shows an error or failing output. Identify the specific error, explain the root cause in plain language, then give the concrete fix as commands or code. Lead with the fix."
        case .extractMarkdown:
            "Transcribe the content of this screenshot into clean, well-structured Markdown. Render tables as Markdown tables, code as fenced code blocks, and lists as Markdown lists. Output only the Markdown, with no commentary."
        case .screenshotToCode:
            "Recreate the UI in this screenshot as code. Default to a single self-contained SwiftUI view; if it is clearly a web page, use one self-contained HTML file with inline CSS instead. Match the layout, spacing, colors, and text as closely as you can. Start with a one-line note naming the framework you chose, then output the code in a single fenced code block."
        case .describe:
            "Describe what is shown in this screenshot. If any text is in a language other than English, also translate it to English."
        }
    }
}
