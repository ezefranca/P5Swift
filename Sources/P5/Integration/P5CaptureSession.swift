import AVFoundation
import CoreImage
import Foundation

/// Preferred physical camera for a native capture session.
public enum P5CameraPosition: String, Sendable, Hashable, Codable, CaseIterable {
    /// Let AVFoundation choose the available camera.
    case unspecified
    /// Prefer a camera facing the user.
    case front
    /// Prefer a camera facing away from the user.
    case back

    var avPosition: AVCaptureDevice.Position {
        switch self {
        case .unspecified: .unspecified
        case .front: .front
        case .back: .back
        }
    }
}

/// Native capture quality presets with stable serialized names.
public enum P5CaptureQuality: String, Sendable, Hashable, Codable, CaseIterable {
    /// Low-bandwidth capture.
    case low
    /// Balanced default capture.
    case medium
    /// High-quality capture selected by the current device.
    case high
    /// 1280-by-720 high-definition capture where supported.
    case hd1280x720

    var sessionPreset: AVCaptureSession.Preset {
        switch self {
        case .low: .low
        case .medium: .medium
        case .high: .high
        case .hd1280x720: .hd1280x720
        }
    }
}

/// Immutable options for camera frames and optional microphone-backed recording.
public struct P5CaptureConfiguration: Sendable, Hashable, Codable {
    /// Preferred camera position.
    public let cameraPosition: P5CameraPosition
    /// Capture quality requested from AVFoundation.
    public let quality: P5CaptureQuality
    /// Whether movie recording should include a microphone input.
    public let includesAudio: Bool
    /// Whether AVFoundation may discard delayed preview frames.
    public let discardsLateVideoFrames: Bool

    /// Creates native capture options.
    public init(
        cameraPosition: P5CameraPosition = .unspecified,
        quality: P5CaptureQuality = .high,
        includesAudio: Bool = false,
        discardsLateVideoFrames: Bool = true
    ) {
        self.cameraPosition = cameraPosition
        self.quality = quality
        self.includesAudio = includesAudio
        self.discardsLateVideoFrames = discardsLateVideoFrames
    }
}

/// Lifecycle state of a ``P5CaptureSession``.
public enum P5CaptureSessionState: Sendable, Hashable, Codable {
    /// No capture has started yet.
    case idle
    /// Camera preview frames are running.
    case running
    /// Camera and optional microphone data are being recorded to a movie.
    case recording
    /// Capture was stopped explicitly or for app lifecycle safety.
    case stopped
    /// Native capture failed with a diagnostic reason.
    case failed(String)
}

/// One camera image with a monotonic media timestamp.
public struct P5CaptureFrame: @unchecked Sendable {
    /// Immutable native image captured from the camera.
    public let image: P5Image
    /// Presentation timestamp in seconds on AVFoundation's media timeline.
    public let timestamp: Double

    /// Creates a validated captured frame.
    ///
    /// - Precondition: `timestamp` is finite and nonnegative.
    public init(image: P5Image, timestamp: Double) {
        precondition(timestamp.isFinite && timestamp >= 0)
        self.image = image
        self.timestamp = timestamp
    }
}

/// Failures produced by native camera, microphone, and movie capture.
public enum P5CaptureError: Error, Sendable, Hashable, LocalizedError {
    /// No camera matched the requested position.
    case cameraUnavailable(P5CameraPosition)
    /// No microphone is available for an audio-enabled configuration.
    case microphoneUnavailable
    /// AVFoundation could not create a protected device input.
    case inputCreationFailed(P5MediaCaptureKind, String)
    /// The native session rejected an input.
    case cannotAddInput(P5MediaCaptureKind)
    /// The native session rejected a required output.
    case cannotAddOutput(String)
    /// An operation is not valid in the current lifecycle state.
    case invalidState(P5CaptureSessionState)
    /// Movie recording requires a local file URL.
    case recordingDestinationIsNotFileURL
    /// Movie recording never overwrites an existing destination.
    case recordingDestinationAlreadyExists
    /// A native preview sample could not be converted into an image.
    case frameConversionFailed
    /// AVFoundation failed to finish a movie recording.
    case recordingFailed(String)

    /// A localized description suitable for diagnostics and user interfaces.
    public var errorDescription: String? {
        switch self {
        case .cameraUnavailable(let position):
            "No camera is available for the requested '\(position.rawValue)' position."
        case .microphoneUnavailable:
            "No microphone is available for this capture session."
        case .inputCreationFailed(let kind, let reason):
            "The \(kind.rawValue) input could not be created: \(reason)"
        case .cannotAddInput(let kind):
            "The native session rejected the \(kind.rawValue) input."
        case .cannotAddOutput(let name):
            "The native session rejected the \(name) output."
        case .invalidState(let state):
            "The capture operation is invalid while the session is '\(state)'."
        case .recordingDestinationIsNotFileURL:
            "Movie capture requires a local file URL."
        case .recordingDestinationAlreadyExists:
            "Movie capture does not overwrite an existing destination."
        case .frameConversionFailed:
            "The native camera sample could not be converted into an image."
        case .recordingFailed(let reason):
            "The native movie recording failed: \(reason)"
        }
    }
}

/// Main-actor lifecycle manager for camera frames and optional microphone movie recording.
@MainActor
public final class P5CaptureSession {
    /// Immutable capture options.
    public let configuration: P5CaptureConfiguration
    /// Current lifecycle state.
    public private(set) var state = P5CaptureSessionState.idle
    /// Most recently delivered camera frame.
    public private(set) var latestFrame: P5CaptureFrame?
    /// Called on the main actor for every converted preview frame.
    public var frameCaptured: (@MainActor @Sendable (P5CaptureFrame) -> Void)?
    /// Called on the main actor after a recording finishes or fails.
    public var recordingFinished: (@MainActor @Sendable (Result<URL, any Error>) -> Void)?
    /// Called on the main actor after each lifecycle transition.
    public var stateChanged: (@MainActor @Sendable (P5CaptureSessionState) -> Void)?

    private let authorization: P5MediaAuthorization
    private let backend: any P5CaptureBackend
    private var isConfigured = false
    private var recordingContinuation: CheckedContinuation<URL, any Error>?

    /// Creates a hardware-backed capture session without starting or prompting.
    public convenience init(configuration: P5CaptureConfiguration = P5CaptureConfiguration()) {
        self.init(
            configuration: configuration,
            authorization: P5MediaAuthorization(),
            backend: P5NativeCaptureBackend()
        )
    }

    init(
        configuration: P5CaptureConfiguration,
        authorization: P5MediaAuthorization,
        backend: any P5CaptureBackend
    ) {
        self.configuration = configuration
        self.authorization = authorization
        self.backend = backend
    }

    /// Starts camera preview delivery after verifying existing authorization.
    ///
    /// This method never requests permission. Call
    /// ``P5MediaAuthorization/requestAuthorization(for:)`` from a user action first.
    public func start() async throws {
        guard state == .idle || state == .stopped else {
            throw P5CaptureError.invalidState(state)
        }
        try authorization.requireAuthorization(for: .camera)
        if configuration.includesAudio {
            try authorization.requireAuthorization(for: .microphone)
        }
        try Task.checkCancellation()
        if isConfigured == false {
            do {
                try await backend.configure(
                    configuration: configuration,
                    frameHandler: { [weak self] result in
                        Task { @MainActor in self?.receiveFrame(result) }
                    },
                    recordingHandler: { [weak self] result in
                        Task { @MainActor in self?.receiveRecording(result) }
                    }
                )
                isConfigured = true
            } catch {
                transition(to: .failed(error.localizedDescription))
                throw error
            }
        }
        do {
            try await backend.startRunning()
            transition(to: .running)
        } catch {
            await backend.stopRunning()
            transition(to: .failed(error.localizedDescription))
            throw error
        }
    }

    /// Stops preview delivery while retaining configuration for a later restart.
    public func stop() async throws {
        guard state == .running || state == .stopped else {
            throw P5CaptureError.invalidState(state)
        }
        if state == .running {
            await backend.stopRunning()
            transition(to: .stopped)
        }
    }

    /// Begins asynchronous movie recording to a new local file.
    public func startRecording(to url: URL) throws {
        guard state == .running else {
            throw P5CaptureError.invalidState(state)
        }
        guard url.isFileURL else {
            throw P5CaptureError.recordingDestinationIsNotFileURL
        }
        guard FileManager.default.fileExists(atPath: url.path) == false else {
            throw P5CaptureError.recordingDestinationAlreadyExists
        }
        try backend.startRecording(to: url)
        transition(to: .recording)
    }

    /// Stops the active recording and waits for AVFoundation to finish the file.
    public func stopRecording() async throws -> URL {
        guard state == .recording, recordingContinuation == nil else {
            throw P5CaptureError.invalidState(state)
        }
        return try await withCheckedThrowingContinuation { continuation in
            recordingContinuation = continuation
            backend.stopRecording()
        }
    }

    /// Stops protected resources when the host application leaves its active scene.
    ///
    /// Returning to the active state never restarts capture implicitly.
    public func scenePhaseChanged(to phase: P5ScenePhase) async throws {
        guard phase != .active else { return }
        if state == .recording {
            _ = try await stopRecording()
        }
        if state == .running {
            try await stop()
        }
    }

    private func receiveFrame(_ result: Result<P5CaptureFrame, any Error>) {
        switch result {
        case .success(let frame):
            latestFrame = frame
            frameCaptured?(frame)
        case .failure(let error):
            Task { await backend.stopRunning() }
            transition(to: .failed(error.localizedDescription))
        }
    }

    private func receiveRecording(_ result: Result<URL, any Error>) {
        recordingFinished?(result)
        let continuation = recordingContinuation
        recordingContinuation = nil
        switch result {
        case .success(let url):
            transition(to: .running)
            continuation?.resume(returning: url)
        case .failure(let error):
            Task { await backend.stopRunning() }
            transition(to: .failed(error.localizedDescription))
            continuation?.resume(throwing: error)
        }
    }

    private func transition(to state: P5CaptureSessionState) {
        self.state = state
        stateChanged?(state)
    }
}

protocol P5CaptureBackend: Sendable {
    func configure(
        configuration: P5CaptureConfiguration,
        frameHandler: @escaping @Sendable (Result<P5CaptureFrame, any Error>) -> Void,
        recordingHandler: @escaping @Sendable (Result<URL, any Error>) -> Void
    ) async throws
    func startRunning() async throws
    func stopRunning() async
    func startRecording(to url: URL) throws
    func stopRecording()
}

final class P5NativeCaptureBackend: @unchecked Sendable, P5CaptureBackend {
    private let runtime: P5CaptureRuntime
    private let session: AVCaptureSession
    private let videoOutput: AVCaptureVideoDataOutput
    private let movieOutput: AVCaptureMovieFileOutput
    private let delegate: P5CaptureDelegate
    private let sessionQueue = DispatchQueue(label: "dev.p5swift.capture.session")
    private let outputQueue = DispatchQueue(label: "dev.p5swift.capture.frames")

    init(runtime: P5CaptureRuntime = P5CaptureRuntime()) {
        self.runtime = runtime
        session = runtime.makeSession()
        videoOutput = runtime.makeVideoOutput()
        movieOutput = runtime.makeMovieOutput()
        delegate = P5CaptureDelegate(decoder: runtime.frameDecoder)
    }

    func configure(
        configuration: P5CaptureConfiguration,
        frameHandler: @escaping @Sendable (Result<P5CaptureFrame, any Error>) -> Void,
        recordingHandler: @escaping @Sendable (Result<URL, any Error>) -> Void
    ) async throws {
        try await onSessionQueue {
            self.delegate.frameHandler = frameHandler
            self.delegate.recordingHandler = recordingHandler
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }
            self.session.sessionPreset = configuration.quality.sessionPreset

            guard
                let camera = self.runtime.cameraDevice(
                    .video,
                    configuration.cameraPosition.avPosition
                )
            else {
                throw P5CaptureError.cameraUnavailable(configuration.cameraPosition)
            }
            try self.addInput(for: camera, kind: .camera)
            if configuration.includesAudio {
                guard let microphone = self.runtime.microphoneDevice(.audio) else {
                    throw P5CaptureError.microphoneUnavailable
                }
                try self.addInput(for: microphone, kind: .microphone)
            }

            self.videoOutput.alwaysDiscardsLateVideoFrames =
                configuration.discardsLateVideoFrames
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            self.videoOutput.setSampleBufferDelegate(self.delegate, queue: self.outputQueue)
            guard self.session.canAddOutput(self.videoOutput) else {
                throw P5CaptureError.cannotAddOutput("video-frame")
            }
            self.session.addOutput(self.videoOutput)
            guard self.session.canAddOutput(self.movieOutput) else {
                throw P5CaptureError.cannotAddOutput("movie")
            }
            self.session.addOutput(self.movieOutput)
        }
    }

    func startRunning() async throws {
        try Task.checkCancellation()
        try await onSessionQueue { self.session.startRunning() }
        try Task.checkCancellation()
    }

    func stopRunning() async {
        try? await onSessionQueue { self.session.stopRunning() }
    }

    func startRecording(to url: URL) throws {
        movieOutput.startRecording(to: url, recordingDelegate: delegate)
    }

    func stopRecording() {
        movieOutput.stopRecording()
    }

    private func addInput(for device: AVCaptureDevice, kind: P5MediaCaptureKind) throws {
        let input: AVCaptureDeviceInput
        do {
            input = try runtime.makeInput(device)
        } catch {
            throw P5CaptureError.inputCreationFailed(kind, error.localizedDescription)
        }
        guard session.canAddInput(input) else {
            throw P5CaptureError.cannotAddInput(kind)
        }
        session.addInput(input)
    }

    private func onSessionQueue<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                continuation.resume(with: Result(catching: operation))
            }
        }
    }
}

struct P5CaptureRuntime: @unchecked Sendable {
    var makeSession: () -> AVCaptureSession = AVCaptureSession.init
    var makeVideoOutput: () -> AVCaptureVideoDataOutput = AVCaptureVideoDataOutput.init
    var makeMovieOutput: () -> AVCaptureMovieFileOutput = AVCaptureMovieFileOutput.init
    var cameraDevice: (AVMediaType, AVCaptureDevice.Position) -> AVCaptureDevice? = {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: $0, position: $1)
    }
    var microphoneDevice: (AVMediaType) -> AVCaptureDevice? = AVCaptureDevice.default(for:)
    var makeInput: (AVCaptureDevice) throws -> AVCaptureDeviceInput = AVCaptureDeviceInput.init
    var frameDecoder = P5CaptureFrameDecoder()
}

final class P5CaptureDelegate: NSObject, @unchecked Sendable,
    AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureFileOutputRecordingDelegate
{
    var frameHandler: (@Sendable (Result<P5CaptureFrame, any Error>) -> Void)?
    var recordingHandler: (@Sendable (Result<URL, any Error>) -> Void)?
    private let decoder: P5CaptureFrameDecoder

    init(decoder: P5CaptureFrameDecoder) {
        self.decoder = decoder
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        frameHandler?(Result { try decoder.decode(sampleBuffer) })
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: (any Error)?
    ) {
        if let error,
            (error as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool != true
        {
            recordingHandler?(.failure(P5CaptureError.recordingFailed(error.localizedDescription)))
        } else {
            recordingHandler?(.success(outputFileURL))
        }
    }
}

struct P5CaptureFrameDecoder: @unchecked Sendable {
    var imageBuffer: (CMSampleBuffer) -> CVImageBuffer? = CMSampleBufferGetImageBuffer
    var presentationTime: (CMSampleBuffer) -> CMTime = CMSampleBufferGetPresentationTimeStamp
    var makeImage: (CVImageBuffer) -> CGImage? = {
        CIContext().createCGImage(
            CIImage(cvImageBuffer: $0), from: CIImage(cvImageBuffer: $0).extent)
    }

    func decode(_ sampleBuffer: CMSampleBuffer) throws -> P5CaptureFrame {
        guard let imageBuffer = imageBuffer(sampleBuffer), let cgImage = makeImage(imageBuffer)
        else {
            throw P5CaptureError.frameConversionFailed
        }
        let timestamp = presentationTime(sampleBuffer).seconds
        guard timestamp.isFinite && timestamp >= 0 else {
            throw P5CaptureError.frameConversionFailed
        }
        return P5CaptureFrame(image: P5Image(cgImage: cgImage), timestamp: timestamp)
    }
}
