import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ObjectiveC.runtime
import Testing

@testable import P5

@Suite("P5 native capture session", .serialized)
struct P5CaptureSessionTests {
    @Test("Capture configuration values map, serialize, and describe failures")
    func values() async throws {
        #expect(P5CameraPosition.unspecified.avPosition == .unspecified)
        #expect(P5CameraPosition.front.avPosition == .front)
        #expect(P5CameraPosition.back.avPosition == .back)
        #expect(P5CaptureQuality.low.sessionPreset == .low)
        #expect(P5CaptureQuality.medium.sessionPreset == .medium)
        #expect(P5CaptureQuality.high.sessionPreset == .high)
        #expect(P5CaptureQuality.hd1280x720.sessionPreset == .hd1280x720)

        let configurations = [
            P5CaptureConfiguration(),
            P5CaptureConfiguration(
                cameraPosition: .front,
                quality: .hd1280x720,
                includesAudio: true,
                discardsLateVideoFrames: false
            ),
        ]
        for configuration in configurations {
            #expect(
                try JSONDecoder().decode(
                    P5CaptureConfiguration.self,
                    from: JSONEncoder().encode(configuration)
                ) == configuration
            )
        }
        for state in [
            P5CaptureSessionState.idle,
            .running,
            .recording,
            .stopped,
            .failed("reason"),
        ] {
            #expect(
                try JSONDecoder().decode(
                    P5CaptureSessionState.self,
                    from: JSONEncoder().encode(state)
                ) == state
            )
        }

        let errors: [P5CaptureError] = [
            .cameraUnavailable(.back),
            .microphoneUnavailable,
            .inputCreationFailed(.camera, "reason"),
            .cannotAddInput(.microphone),
            .cannotAddOutput("movie"),
            .invalidState(.idle),
            .recordingDestinationIsNotFileURL,
            .recordingDestinationAlreadyExists,
            .frameConversionFailed,
            .recordingFailed("reason"),
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
        await MainActor.run { _ = P5CaptureSession() }
    }

    @Test("Preview, recording, restart, and scene lifecycle are ordered")
    @MainActor
    func lifecycle() async throws {
        let backend = FakeCaptureBackend()
        let state = CaptureObservation()
        let capture = Self.capture(backend: backend, includesAudio: true)
        capture.stateChanged = { state.states.append($0) }
        capture.frameCaptured = { state.frames.append($0) }
        capture.recordingFinished = { state.recordings.append($0) }

        try await capture.start()
        #expect(capture.state == .running)
        #expect(backend.configureCount == 1)
        #expect(backend.startCount == 1)
        #expect(backend.configuration?.includesAudio == true)
        await #expect(throws: P5CaptureError.invalidState(.running)) {
            try await capture.start()
        }

        let frame = try P5CaptureFrame(image: Self.image(), timestamp: 1.25)
        backend.frameHandler?(.success(frame))
        await Self.waitUntil { capture.latestFrame != nil }
        #expect(capture.latestFrame?.timestamp == 1.25)
        #expect(state.frames.count == 1)

        let movie = FileManager.default.temporaryDirectory.appendingPathComponent(
            "P5Capture-\(UUID().uuidString).mov"
        )
        try capture.startRecording(to: movie)
        #expect(capture.state == .recording)
        #expect(backend.recordingURL == movie)
        let stopRecording = Task { @MainActor in try await capture.stopRecording() }
        await Self.waitUntil { backend.stopRecordingCount == 1 }
        await #expect(throws: P5CaptureError.invalidState(.recording)) {
            _ = try await capture.stopRecording()
        }
        await #expect(throws: P5CaptureError.invalidState(.recording)) {
            try await capture.stop()
        }
        backend.recordingHandler?(.success(movie))
        #expect(try await stopRecording.value == movie)
        #expect(capture.state == .running)
        #expect(state.recordings.count == 1)

        try await capture.stop()
        try await capture.stop()
        #expect(capture.state == .stopped)
        #expect(backend.stopCount == 1)
        try await capture.start()
        #expect(backend.configureCount == 1)
        #expect(backend.startCount == 2)

        try await capture.scenePhaseChanged(to: .active)
        #expect(capture.state == .running)
        try await capture.scenePhaseChanged(to: .inactive)
        #expect(capture.state == .stopped)
        #expect(backend.stopCount == 2)
        #expect(state.states == [.running, .recording, .running, .stopped, .running, .stopped])
    }

    @Test("Recording lifecycle stops before protected resources leave the active scene")
    @MainActor
    func recordingSceneLifecycle() async throws {
        let backend = FakeCaptureBackend()
        let capture = Self.capture(backend: backend)
        try await capture.start()
        let movie = URL(fileURLWithPath: "/tmp/P5Scene-\(UUID().uuidString).mov")
        try capture.startRecording(to: movie)

        let lifecycle = Task { @MainActor in
            try await capture.scenePhaseChanged(to: .background)
        }
        await Self.waitUntil { backend.stopRecordingCount == 1 }
        backend.recordingHandler?(.success(movie))
        try await lifecycle.value
        #expect(capture.state == .stopped)
        #expect(backend.stopCount == 1)
    }

    @Test("Public capture validates authorization, state, destinations, and backend failures")
    @MainActor
    func publicFailures() async throws {
        let unauthorizedBackend = FakeCaptureBackend()
        let notDetermined = Self.capture(
            backend: unauthorizedBackend,
            cameraStatus: .notDetermined
        )
        await #expect(
            throws: P5MediaAuthorizationError.authorizationNotDetermined(.camera)
        ) {
            try await notDetermined.start()
        }
        #expect(unauthorizedBackend.configureCount == 0)

        let microphoneDenied = Self.capture(
            backend: FakeCaptureBackend(),
            includesAudio: true,
            microphoneStatus: .denied
        )
        await #expect(
            throws: P5MediaAuthorizationError.accessUnavailable(.microphone, .denied)
        ) {
            try await microphoneDenied.start()
        }

        let backend = FakeCaptureBackend()
        backend.configureError = StubError.configure
        let failedConfiguration = Self.capture(backend: backend)
        await #expect(throws: StubError.configure) {
            try await failedConfiguration.start()
        }
        #expect(failedConfiguration.state == .failed("configure"))

        let startBackend = FakeCaptureBackend()
        startBackend.startError = StubError.start
        let failedStart = Self.capture(backend: startBackend)
        await #expect(throws: StubError.start) { try await failedStart.start() }
        #expect(failedStart.state == .failed("start"))
        #expect(startBackend.stopCount == 1)

        let cancelledBackend = FakeCaptureBackend()
        let cancelledCapture = Self.capture(backend: cancelledBackend)
        let cancelled = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            try await cancelledCapture.start()
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }

        let invalid = Self.capture(backend: FakeCaptureBackend())
        await #expect(throws: P5CaptureError.invalidState(.idle)) {
            try await invalid.stop()
        }
        #expect(throws: P5CaptureError.invalidState(.idle)) {
            try invalid.startRecording(to: URL(fileURLWithPath: "/tmp/movie.mov"))
        }
        await #expect(throws: P5CaptureError.invalidState(.idle)) {
            _ = try await invalid.stopRecording()
        }
    }

    @Test("Recording and frame completion failures transition deterministically")
    @MainActor
    func completionFailures() async throws {
        let backend = FakeCaptureBackend()
        let capture = Self.capture(backend: backend)
        try await capture.start()

        #expect(throws: P5CaptureError.invalidState(.recording)) {
            try capture.startRecording(to: URL(fileURLWithPath: "/tmp/ignored.mov"))
            try capture.startRecording(to: URL(fileURLWithPath: "/tmp/second.mov"))
        }
        backend.recordingHandler?(.success(URL(fileURLWithPath: "/tmp/ignored.mov")))
        await Self.waitUntil { capture.state == .running }

        #expect(throws: P5CaptureError.recordingDestinationIsNotFileURL) {
            try capture.startRecording(to: URL(string: "https://example.com/movie.mov")!)
        }
        let existing = FileManager.default.temporaryDirectory.appendingPathComponent(
            "P5Existing-\(UUID().uuidString).mov"
        )
        try Data().write(to: existing)
        defer { try? FileManager.default.removeItem(at: existing) }
        #expect(throws: P5CaptureError.recordingDestinationAlreadyExists) {
            try capture.startRecording(to: existing)
        }

        backend.startRecordingError = StubError.recording
        #expect(throws: StubError.recording) {
            try capture.startRecording(to: URL(fileURLWithPath: "/tmp/failure.mov"))
        }
        backend.startRecordingError = nil

        let destination = URL(fileURLWithPath: "/tmp/final.mov")
        try capture.startRecording(to: destination)
        let stop = Task { @MainActor in try await capture.stopRecording() }
        await Self.waitUntil { backend.stopRecordingCount == 1 }
        backend.recordingHandler?(.failure(StubError.recording))
        await #expect(throws: StubError.recording) { _ = try await stop.value }
        #expect(capture.state == .failed("recording"))

        let frameBackend = FakeCaptureBackend()
        let frameCapture = Self.capture(backend: frameBackend)
        try await frameCapture.start()
        frameBackend.frameHandler?(.failure(StubError.frame))
        await Self.waitUntil { frameCapture.state == .failed("frame") }
        await Self.waitUntil { frameBackend.stopCount == 1 }
    }

    @Test("Native backend configures camera, optional microphone, outputs, and queues")
    func nativeBackend() async throws {
        let fakeSession = FakeAVCaptureSession()
        let nativeState = P5CaptureNativeState(session: fakeSession)
        let runtime = Self.runtime(state: nativeState)
        let backend = P5NativeCaptureBackend(runtime: runtime)
        let observation = CaptureObservation()

        try await backend.configure(
            configuration: P5CaptureConfiguration(includesAudio: true),
            frameHandler: { observation.frameResults.append($0) },
            recordingHandler: { observation.recordings.append($0) }
        )
        #expect(fakeSession.beginCount == 1)
        #expect(fakeSession.commitCount == 1)
        #expect(fakeSession.inputCount == 2)
        #expect(fakeSession.outputCount == 2)
        try await backend.startRunning()
        await backend.stopRunning()
        #expect(fakeSession.startCount == 1)
        #expect(fakeSession.stopCount == 1)
        let movie = URL(fileURLWithPath: "/tmp/native.mov")
        try backend.startRecording(to: movie)
        backend.stopRecording()
        #expect(nativeState.movieOutput.lastURL == movie)
        #expect(nativeState.movieOutput.stopCount == 1)

        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await backend.startRunning()
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
    }

    @Test("Native configuration reports every unavailable and rejected component")
    func nativeConfigurationFailures() async throws {
        let cameraMissing = P5CaptureNativeState()
        cameraMissing.hasCamera = false
        await Self.expectNativeError(.cameraUnavailable(.back), state: cameraMissing) {
            P5CaptureConfiguration(cameraPosition: .back)
        }

        let inputFailure = P5CaptureNativeState()
        inputFailure.inputError = StubError.input
        let inputBackend = P5NativeCaptureBackend(runtime: Self.runtime(state: inputFailure))
        await #expect(throws: P5CaptureError.self) {
            try await inputBackend.configure(
                configuration: P5CaptureConfiguration(),
                frameHandler: { _ in },
                recordingHandler: { _ in }
            )
        }

        let rejectedInput = P5CaptureNativeState()
        rejectedInput.session.rejectedInputIndex = 0
        await Self.expectNativeError(.cannotAddInput(.camera), state: rejectedInput)

        let rejectedMicrophone = P5CaptureNativeState()
        rejectedMicrophone.session.rejectedInputIndex = 1
        await Self.expectNativeError(
            .cannotAddInput(.microphone),
            state: rejectedMicrophone
        ) {
            P5CaptureConfiguration(includesAudio: true)
        }

        let microphoneMissing = P5CaptureNativeState()
        microphoneMissing.hasMicrophone = false
        await Self.expectNativeError(.microphoneUnavailable, state: microphoneMissing) {
            P5CaptureConfiguration(includesAudio: true)
        }

        let videoRejected = P5CaptureNativeState()
        videoRejected.session.rejectedOutputIndex = 0
        await Self.expectNativeError(.cannotAddOutput("video-frame"), state: videoRejected)

        let movieRejected = P5CaptureNativeState()
        movieRejected.session.rejectedOutputIndex = 1
        await Self.expectNativeError(.cannotAddOutput("movie"), state: movieRejected)
    }

    @Test("Frame decoding and delegate callbacks use real Core Video samples")
    func frameDecodingAndDelegate() async throws {
        let sample = try Self.sampleBuffer(timestamp: 2.5)
        let decoder = P5CaptureFrameDecoder()
        let frame = try decoder.decode(sample)
        #expect(frame.image.pixelWidth == 2)
        #expect(frame.timestamp == 2.5)

        let noBuffer = P5CaptureFrameDecoder(
            imageBuffer: { _ in nil },
            presentationTime: { _ in .zero },
            makeImage: { _ in nil }
        )
        #expect(throws: P5CaptureError.frameConversionFailed) { try noBuffer.decode(sample) }
        let noImage = P5CaptureFrameDecoder(
            imageBuffer: decoder.imageBuffer,
            presentationTime: decoder.presentationTime,
            makeImage: { _ in nil }
        )
        #expect(throws: P5CaptureError.frameConversionFailed) { try noImage.decode(sample) }
        let invalidTime = P5CaptureFrameDecoder(
            imageBuffer: decoder.imageBuffer,
            presentationTime: { _ in CMTime(value: -1, timescale: 1) },
            makeImage: decoder.makeImage
        )
        #expect(throws: P5CaptureError.frameConversionFailed) { try invalidTime.decode(sample) }
        let nonfiniteTime = P5CaptureFrameDecoder(
            imageBuffer: decoder.imageBuffer,
            presentationTime: { _ in CMTime.invalid },
            makeImage: decoder.makeImage
        )
        #expect(throws: P5CaptureError.frameConversionFailed) { try nonfiniteTime.decode(sample) }

        let observation = CaptureObservation()
        let delegate = P5CaptureDelegate(decoder: decoder)
        let connection = AVCaptureConnection(
            inputPorts: [],
            output: AVCaptureVideoDataOutput()
        )
        let url = URL(fileURLWithPath: "/tmp/delegate.mov")
        delegate.captureOutput(AVCaptureVideoDataOutput(), didOutput: sample, from: connection)
        delegate.fileOutput(
            AVCaptureMovieFileOutput(),
            didFinishRecordingTo: url,
            from: [],
            error: nil
        )
        delegate.frameHandler = { observation.frameResults.append($0) }
        delegate.captureOutput(AVCaptureVideoDataOutput(), didOutput: sample, from: connection)
        #expect(observation.frameResults.count == 1)

        delegate.recordingHandler = { observation.recordings.append($0) }
        delegate.fileOutput(
            AVCaptureMovieFileOutput(),
            didFinishRecordingTo: url,
            from: [],
            error: nil
        )
        delegate.fileOutput(
            AVCaptureMovieFileOutput(),
            didFinishRecordingTo: url,
            from: [],
            error: StubError.recording
        )
        delegate.fileOutput(
            AVCaptureMovieFileOutput(),
            didFinishRecordingTo: url,
            from: [],
            error: NSError(
                domain: AVFoundationErrorDomain,
                code: AVError.unknown.rawValue,
                userInfo: [AVErrorRecordingSuccessfullyFinishedKey: true]
            )
        )
        #expect(observation.recordings.count == 3)
    }

    @Test("Invalid captured frame timestamps terminate at the public boundary")
    func invalidFrameTimestamp() async {
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5CaptureFrame(image: try! Self.image(), timestamp: .nan)
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5CaptureFrame(image: try! Self.image(), timestamp: -1)
            }
        #endif
    }

    @Test("Default hardware factories are bound without requesting permission")
    func defaultBindings() async {
        let runtime = P5CaptureRuntime()
        _ = runtime.makeSession()
        _ = runtime.makeVideoOutput()
        _ = runtime.makeMovieOutput()
        _ = runtime.cameraDevice(.video, .unspecified)
        _ = runtime.microphoneDevice(.audio)

        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                let device = Self.uninitialized(AVCaptureDevice.self)
                _ = try! P5CaptureRuntime().makeInput(device)
            }
        #endif
    }

    @MainActor
    private static func capture(
        backend: FakeCaptureBackend,
        includesAudio: Bool = false,
        cameraStatus: AVAuthorizationStatus = .authorized,
        microphoneStatus: AVAuthorizationStatus = .authorized
    ) -> P5CaptureSession {
        let authorization = P5MediaAuthorization(
            runtime: P5MediaAuthorizationRuntime(
                status: { mediaType in
                    mediaType == .video ? cameraStatus : microphoneStatus
                },
                requestAccess: { _, completion in completion(false) }
            )
        )
        return P5CaptureSession(
            configuration: P5CaptureConfiguration(includesAudio: includesAudio),
            authorization: authorization,
            backend: backend
        )
    }

    private static func runtime(
        state: P5CaptureNativeState
    ) -> P5CaptureRuntime {
        P5CaptureRuntime(
            makeSession: { state.session },
            makeVideoOutput: AVCaptureVideoDataOutput.init,
            makeMovieOutput: { state.movieOutput },
            cameraDevice: { _, _ in state.hasCamera ? state.device : nil },
            microphoneDevice: { _ in state.hasMicrophone ? state.device : nil },
            makeInput: { _ in
                if let error = state.inputError { throw error }
                return state.input
            },
            frameDecoder: P5CaptureFrameDecoder()
        )
    }

    private static func expectNativeError(
        _ expected: P5CaptureError,
        state: P5CaptureNativeState,
        configuration: () -> P5CaptureConfiguration = { P5CaptureConfiguration() }
    ) async {
        let backend = P5NativeCaptureBackend(runtime: runtime(state: state))
        await #expect(throws: expected) {
            try await backend.configure(
                configuration: configuration(),
                frameHandler: { _ in },
                recordingHandler: { _ in }
            )
        }
        #expect(state.session.commitCount == 1)
    }

    private static func image() throws -> P5Image {
        try P5Image(
            pixelBuffer: P5PixelBuffer(width: 1, height: 1, bytes: [255, 0, 0, 255])
        )
    }

    private static func uninitialized<T: AnyObject>(_ type: T.Type) -> T {
        guard let object = class_createInstance(type, 0) else {
            preconditionFailure("Objective-C test allocation failed.")
        }
        return unsafeDowncast(object as AnyObject, to: type)
    }

    private static func sampleBuffer(timestamp: Double) throws -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes =
            [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            ] as CFDictionary
        try #require(
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                2,
                2,
                kCVPixelFormatType_32BGRA,
                attributes,
                &pixelBuffer
            ) == kCVReturnSuccess
        )
        let buffer = try #require(pixelBuffer)
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 255, CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])

        var format: CMVideoFormatDescription?
        try #require(
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: buffer,
                formatDescriptionOut: &format
            ) == noErr
        )
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(seconds: timestamp, preferredTimescale: 600),
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        try #require(
            CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: buffer,
                formatDescription: try #require(format),
                sampleTiming: &timing,
                sampleBufferOut: &sample
            ) == noErr
        )
        return try #require(sample)
    }

    @MainActor
    private static func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0..<100 where predicate() == false {
            await Task.yield()
        }
        #expect(predicate())
    }
}

private final class FakeCaptureBackend: @unchecked Sendable, P5CaptureBackend {
    var configuration: P5CaptureConfiguration?
    var frameHandler: (@Sendable (Result<P5CaptureFrame, any Error>) -> Void)?
    var recordingHandler: (@Sendable (Result<URL, any Error>) -> Void)?
    var configureCount = 0
    var startCount = 0
    var stopCount = 0
    var stopRecordingCount = 0
    var recordingURL: URL?
    var configureError: (any Error)?
    var startError: (any Error)?
    var startRecordingError: (any Error)?

    func configure(
        configuration: P5CaptureConfiguration,
        frameHandler: @escaping @Sendable (Result<P5CaptureFrame, any Error>) -> Void,
        recordingHandler: @escaping @Sendable (Result<URL, any Error>) -> Void
    ) async throws {
        configureCount += 1
        if let configureError { throw configureError }
        self.configuration = configuration
        self.frameHandler = frameHandler
        self.recordingHandler = recordingHandler
    }

    func startRunning() async throws {
        startCount += 1
        if let startError { throw startError }
    }

    func stopRunning() async {
        stopCount += 1
    }

    func startRecording(to url: URL) throws {
        if let startRecordingError { throw startRecordingError }
        recordingURL = url
    }

    func stopRecording() {
        stopRecordingCount += 1
    }
}

private final class CaptureObservation: @unchecked Sendable {
    var states: [P5CaptureSessionState] = []
    var frames: [P5CaptureFrame] = []
    var frameResults: [Result<P5CaptureFrame, any Error>] = []
    var recordings: [Result<URL, any Error>] = []
}

private final class FakeAVCaptureSession: AVCaptureSession, @unchecked Sendable {
    var beginCount = 0
    var commitCount = 0
    var inputCount = 0
    var outputCount = 0
    var startCount = 0
    var stopCount = 0
    var rejectedInputIndex: Int?
    var rejectedOutputIndex: Int?

    override func beginConfiguration() { beginCount += 1 }
    override func commitConfiguration() { commitCount += 1 }
    override func canAddInput(_ input: AVCaptureInput) -> Bool {
        inputCount != rejectedInputIndex
    }
    override func addInput(_ input: AVCaptureInput) { inputCount += 1 }
    override func canAddOutput(_ output: AVCaptureOutput) -> Bool {
        outputCount != rejectedOutputIndex
    }
    override func addOutput(_ output: AVCaptureOutput) { outputCount += 1 }
    override func startRunning() { startCount += 1 }
    override func stopRunning() { stopCount += 1 }
}

private final class FakeMovieOutput: AVCaptureMovieFileOutput, @unchecked Sendable {
    var lastURL: URL?
    var stopCount = 0

    override func startRecording(
        to outputFileURL: URL,
        recordingDelegate delegate: any AVCaptureFileOutputRecordingDelegate
    ) {
        lastURL = outputFileURL
    }

    override func stopRecording() {
        stopCount += 1
    }
}

private final class P5CaptureNativeState: @unchecked Sendable {
    let session: FakeAVCaptureSession
    let movieOutput = FakeMovieOutput()
    let device = leakedUninitialized(AVCaptureDevice.self)
    let input = leakedUninitialized(AVCaptureDeviceInput.self)
    var hasCamera = true
    var hasMicrophone = true
    var inputError: (any Error)?

    init(session: FakeAVCaptureSession = FakeAVCaptureSession()) {
        self.session = session
    }
}

private func leakedUninitialized<T: AnyObject>(_ type: T.Type) -> T {
    guard let allocation = class_createInstance(type, 0) else {
        preconditionFailure("Objective-C test allocation failed.")
    }
    let object = unsafeDowncast(allocation as AnyObject, to: type)
    _ = Unmanaged.passRetained(object).toOpaque()
    return object
}

private enum StubError: String, Error, LocalizedError {
    case configure
    case start
    case recording
    case frame
    case input

    var errorDescription: String? { rawValue }
}
