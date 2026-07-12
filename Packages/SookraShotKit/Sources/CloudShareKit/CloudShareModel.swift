import AppKit
import ExportKit
import Observation
import SharedKit

/// Drives one cloud-share upload and its result HUD.
@MainActor
@Observable
public final class CloudShareModel {
    public enum State {
        case uploading
        case done(URL)
        case failed(String)
        case notConfigured
    }

    public let capture: DeliveredCapture
    var state: State = .uploading
    var onOpenSettings: (() -> Void)?

    private let uploader = B2Uploader()
    private var task: Task<Void, Never>?

    public init(capture: DeliveredCapture) {
        self.capture = capture
    }

    func start() {
        guard let config = B2Settings.current else {
            state = .notConfigured
            return
        }
        guard let png = ImageEncoder().data(from: capture.image, format: .png) else {
            state = .failed("Could not encode the capture.")
            return
        }
        task?.cancel()
        state = .uploading
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let url = try await self.uploader.upload(pngData: png, config: config)
                self.setClipboard(url.absoluteString)
                self.state = .done(url)
            } catch is CancellationError {
                // Superseded; leave state alone.
            } catch {
                self.state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    func copyLink() {
        if case .done(let url) = state {
            setClipboard(url.absoluteString)
        }
    }

    func openLink() {
        if case .done(let url) = state {
            NSWorkspace.shared.open(url)
        }
    }

    private func setClipboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}
