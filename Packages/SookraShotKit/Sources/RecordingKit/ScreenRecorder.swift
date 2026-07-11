import AVFoundation
import AppKit
import ScreenCaptureKit
import SharedKit

public enum RecordingError: Error, Sendable {
    case displayNotFound
    case windowNotFound
    case alreadyRecording
    case notRecording
}

public enum RecordingTarget: Sendable {
    case display(CGDirectDisplayID, scale: CGFloat)
    case area(displayID: CGDirectDisplayID, rectInDisplay: CGRect, scale: CGFloat)
    case window(CGWindowID, scale: CGFloat)
}

/// MP4 screen recording via SCStream + SCRecordingOutput (macOS 15+ path).
/// System audio is captured by default; microphone only when opted in.
@MainActor
public final class ScreenRecorder: NSObject {
    public private(set) var isRecording = false

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var outputURL: URL?
    private var finishContinuation: CheckedContinuation<URL, Error>?

    public var onStateChange: (@MainActor (Bool) -> Void)?

    override public init() {
        super.init()
    }

    public func start(
        target: RecordingTarget,
        captureSystemAudio: Bool = true,
        captureMicrophone: Bool = false
    ) async throws {
        guard !isRecording else { throw RecordingError.alreadyRecording }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == ownPID }

        let filter: SCContentFilter
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = true
        configuration.capturesAudio = captureSystemAudio
        configuration.captureMicrophone = captureMicrophone
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)

        switch target {
        case .display(let displayID, let scale):
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw RecordingError.displayNotFound
            }
            filter = SCContentFilter(display: display, excludingWindows: ownWindows)
            configuration.width = Int(CGFloat(display.width) * scale)
            configuration.height = Int(CGFloat(display.height) * scale)
        case .area(let displayID, let rect, let scale):
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw RecordingError.displayNotFound
            }
            filter = SCContentFilter(display: display, excludingWindows: ownWindows)
            configuration.sourceRect = rect
            configuration.width = Int(rect.width * scale)
            configuration.height = Int(rect.height * scale)
        case .window(let windowID, let scale):
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw RecordingError.windowNotFound
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            configuration.width = Int(window.frame.width * scale)
            configuration.height = Int(window.frame.height * scale)
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SookraShot-recording-\(UUID().uuidString)")
            .appendingPathExtension("mp4")

        let outputConfiguration = SCRecordingOutputConfiguration()
        outputConfiguration.outputURL = url
        outputConfiguration.outputFileType = .mp4
        outputConfiguration.videoCodecType = .h264

        let output = SCRecordingOutput(configuration: outputConfiguration, delegate: self)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addRecordingOutput(output)
        try await stream.startCapture()

        self.stream = stream
        self.recordingOutput = output
        self.outputURL = url
        isRecording = true
        onStateChange?(true)
    }

    /// Stops the recording and returns the finished temp-file URL.
    public func stop() async throws -> URL {
        guard isRecording, let stream else { throw RecordingError.notRecording }

        return try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation
            Task {
                do {
                    try await stream.stopCapture()
                } catch {
                    // stopCapture errors surface here if the recording delegate never fires.
                    self.finish(.failure(error))
                }
            }
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard let continuation = finishContinuation else { return }
        finishContinuation = nil
        stream = nil
        recordingOutput = nil
        isRecording = false
        onStateChange?(false)
        switch result {
        case .success(let url):
            continuation.resume(returning: url)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

extension ScreenRecorder: SCRecordingOutputDelegate {
    public nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            if let url = self.outputURL {
                self.finish(.success(url))
            }
        }
    }

    public nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in
            self.finish(.failure(error))
        }
    }
}

extension ScreenRecorder: SCStreamDelegate {
    public nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            self.finish(.failure(error))
        }
    }
}
