import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import Testing

@testable import P5

@Suite("P5 native video export", .serialized)
struct P5VideoExportTests {
    @Test("Frame sequences write complete atomic H.264 movies")
    func nativeMovie() async throws {
        let sequence = try frameSequence()
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(
            "P5Video-\(UUID().uuidString).mov"
        )
        defer { try? FileManager.default.removeItem(at: output) }

        let configuration = P5VideoExportConfiguration(
            codec: .h264,
            fileType: .quickTimeMovie,
            averageBitRate: 500_000,
            optimizesForNetworkUse: false
        )
        try await sequence.writeVideo(to: output, configuration: configuration)
        #expect(FileManager.default.fileExists(atPath: output.path))
        #expect((try Data(contentsOf: output)).isEmpty == false)

        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration)
        #expect(abs(duration.seconds - (3 / sequence.framesPerSecond)) < 0.02)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try #require(tracks.first)
        let dimensions = try await track.load(.naturalSize)
        #expect(dimensions == CGSize(width: 32, height: 32))

        let generator = AVAssetImageGenerator(asset: asset)
        let generated = try await generator.image(at: .zero)
        let firstFrame = P5Image(cgImage: generated.image)
        let color = try firstFrame.color(x: 4, y: 4)
        #expect(color.red > 0.7)
        #expect(color.green < 0.25)
    }

    @Test("Video options map, serialize, and reject corrupted state")
    func options() throws {
        for codec in P5VideoCodec.allCases {
            #expect(codec.avCodec.rawValue.isEmpty == false)
            #expect(codec.supportsAlpha == (codec == .proRes4444))
        }
        for fileType in P5VideoFileType.allCases {
            #expect(fileType.avFileType.rawValue.isEmpty == false)
            #expect(["mov", "mp4"].contains(fileType.filenameExtension))
        }

        let configurations = [
            P5VideoExportConfiguration(),
            P5VideoExportConfiguration(codec: .hevc, fileType: .mpeg4),
            P5VideoExportConfiguration(codec: .proRes422, averageBitRate: 1_000_000),
            P5VideoExportConfiguration(codec: .proRes4444),
        ]
        for configuration in configurations {
            #expect(
                try JSONDecoder().decode(
                    P5VideoExportConfiguration.self,
                    from: JSONEncoder().encode(configuration)
                ) == configuration
            )
        }

        let invalidBitRate = Data(
            """
            {"codec":"h264","fileType":"quickTimeMovie","averageBitRate":0,
             "optimizesForNetworkUse":true}
            """.utf8
        )
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                P5VideoExportConfiguration.self,
                from: invalidBitRate
            )
        }
        let invalidContainer = Data(
            """
            {"codec":"proRes422","fileType":"mpeg4","averageBitRate":null,
             "optimizesForNetworkUse":true}
            """.utf8
        )
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                P5VideoExportConfiguration.self,
                from: invalidContainer
            )
        }
    }

    @Test("Atomic orchestration preserves destinations and cleans partial output")
    func atomicOrchestration() async throws {
        let sequence = try frameSequence()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "P5VideoOrchestration-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        await #expect(throws: P5VideoExportError.destinationIsNotFileURL) {
            try await sequence.writeVideo(to: URL(string: "https://example.com/movie.mov")!)
        }

        let existing = directory.appendingPathComponent("existing.mov")
        try Data([1]).write(to: existing)
        await #expect(throws: P5VideoExportError.destinationAlreadyExists) {
            try await sequence.writeVideo(to: existing)
        }
        #expect(try Data(contentsOf: existing) == Data([1]))

        let successful = directory.appendingPathComponent("successful.mov")
        let successState = PipelineState()
        try await sequence.writeVideo(
            to: successful,
            configuration: P5VideoExportConfiguration(),
            fileManager: .default
        ) { temporaryURL, _, _ in
            TestVideoPipeline(outputURL: temporaryURL, state: successState, result: .success(()))
        }
        #expect(try Data(contentsOf: successful) == Data([7, 8, 9]))
        #expect(successState.writeCount == 1)

        let failed = directory.appendingPathComponent("failed.mov")
        let failureState = PipelineState()
        await #expect(throws: TestVideoError.intentional) {
            try await sequence.writeVideo(
                to: failed,
                configuration: P5VideoExportConfiguration(),
                fileManager: .default
            ) { temporaryURL, _, _ in
                TestVideoPipeline(
                    outputURL: temporaryURL,
                    state: failureState,
                    result: .failure(.intentional)
                )
            }
        }
        #expect(FileManager.default.fileExists(atPath: failed.path) == false)
        #expect(failureState.cancelCount == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 2)

        let missingTemporary = directory.appendingPathComponent("missing.mov")
        let missingState = PipelineState()
        await #expect(throws: CocoaError.self) {
            try await sequence.writeVideo(
                to: missingTemporary,
                configuration: P5VideoExportConfiguration(),
                fileManager: .default
            ) { temporaryURL, _, _ in
                TestVideoPipeline(
                    outputURL: temporaryURL,
                    state: missingState,
                    result: .success(()),
                    writesOutput: false
                )
            }
        }
        #expect(missingState.cancelCount == 1)
    }

    @Test("Cancellation reaches the writer and removes its partial file")
    func cancellation() async throws {
        let sequence = try frameSequence()
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(
            "P5VideoCancel-\(UUID().uuidString).mov"
        )
        let state = PipelineState()
        let task = Task {
            try await sequence.writeVideo(
                to: output,
                configuration: P5VideoExportConfiguration(),
                fileManager: .default
            ) { temporaryURL, _, _ in
                SuspendingVideoPipeline(outputURL: temporaryURL, state: state)
            }
        }
        await Task.yield()
        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(state.cancelCount >= 1)
        #expect(FileManager.default.fileExists(atPath: output.path) == false)
    }

    @Test("AVFoundation failure states and backpressure are deterministic")
    func avFoundationFailureStates() async throws {
        let sequence = try frameSequence()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "P5VideoFailures-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var creationFailure = P5AVVideoRuntime()
        creationFailure.makeWriter = { _, _ in throw TestVideoError.intentional }
        #expect(throws: P5VideoExportError.self) {
            _ = try P5AVVideoPipeline(
                outputURL: directory.appendingPathComponent("creation.mov"),
                sequence: sequence,
                configuration: P5VideoExportConfiguration(),
                runtime: creationFailure
            )
        }

        var rejectedInput = P5AVVideoRuntime()
        rejectedInput.canAdd = { _, _ in false }
        #expect(throws: P5VideoExportError.self) {
            _ = try P5AVVideoPipeline(
                outputURL: directory.appendingPathComponent("input.mov"),
                sequence: sequence,
                configuration: P5VideoExportConfiguration(),
                runtime: rejectedInput
            )
        }

        var startFailure = P5AVVideoRuntime()
        startFailure.startWriting = { _ in false }
        startFailure.error = { _ in nil }
        let failedStart = try pipeline(
            named: "start.mov",
            in: directory,
            sequence: sequence,
            runtime: startFailure
        )
        await #expect(throws: P5VideoExportError.self) {
            try await failedStart.write(
                frames: sequence.frames,
                framesPerSecond: sequence.framesPerSecond
            )
        }

        var describedStartFailure = startFailure
        describedStartFailure.error = { _ in TestVideoError.intentional }
        let describedStart = try pipeline(
            named: "described-start.mov",
            in: directory,
            sequence: sequence,
            runtime: describedStartFailure
        )
        await #expect(throws: P5VideoExportError.self) {
            try await describedStart.write(
                frames: sequence.frames,
                framesPerSecond: sequence.framesPerSecond
            )
        }

        var writerFailure = P5AVVideoRuntime()
        writerFailure.isReady = { _ in false }
        writerFailure.status = { _ in .failed }
        let failedWriter = try pipeline(
            named: "writer.mov",
            in: directory,
            sequence: sequence,
            runtime: writerFailure
        )
        await #expect(throws: P5VideoExportError.self) {
            try await failedWriter.write(
                frames: sequence.frames,
                framesPerSecond: sequence.framesPerSecond
            )
        }
        failedWriter.cancel()

        let readyState = ReadyState()
        var backpressure = P5AVVideoRuntime()
        backpressure.isReady = { _ in readyState.next() }
        let delayedWriter = try pipeline(
            named: "backpressure.mov",
            in: directory,
            sequence: sequence,
            runtime: backpressure
        )
        try await delayedWriter.write(
            frames: sequence.frames,
            framesPerSecond: sequence.framesPerSecond
        )
        #expect(readyState.checkCount > sequence.frames.count)
        delayedWriter.cancel()

        var missingPool = P5AVVideoRuntime()
        missingPool.pixelBufferPool = { _ in nil }
        let noPoolWriter = try pipeline(
            named: "pool.mov",
            in: directory,
            sequence: sequence,
            runtime: missingPool
        )
        await #expect(throws: P5VideoExportError.frameConversionFailed(0)) {
            try await noPoolWriter.write(
                frames: sequence.frames,
                framesPerSecond: sequence.framesPerSecond
            )
        }
        noPoolWriter.cancel()

        var rejectedFrame = P5AVVideoRuntime()
        rejectedFrame.append = { _, _, _ in false }
        rejectedFrame.error = { _ in nil }
        let rejectedFrameWriter = try pipeline(
            named: "append.mov",
            in: directory,
            sequence: sequence,
            runtime: rejectedFrame
        )
        await #expect(throws: P5VideoExportError.self) {
            try await rejectedFrameWriter.write(
                frames: sequence.frames,
                framesPerSecond: sequence.framesPerSecond
            )
        }
        rejectedFrameWriter.cancel()

        var describedFrame = rejectedFrame
        describedFrame.error = { _ in TestVideoError.intentional }
        let describedFrameWriter = try pipeline(
            named: "described-append.mov",
            in: directory,
            sequence: sequence,
            runtime: describedFrame
        )
        await #expect(throws: P5VideoExportError.self) {
            try await describedFrameWriter.write(
                frames: sequence.frames,
                framesPerSecond: sequence.framesPerSecond
            )
        }
        describedFrameWriter.cancel()

        var incomplete = P5AVVideoRuntime()
        incomplete.finishWriting = { _ in }
        incomplete.status = { _ in .writing }
        incomplete.error = { _ in nil }
        let incompleteWriter = try pipeline(
            named: "incomplete.mov",
            in: directory,
            sequence: sequence,
            runtime: incomplete
        )
        await #expect(throws: P5VideoExportError.self) {
            try await incompleteWriter.write(
                frames: sequence.frames,
                framesPerSecond: sequence.framesPerSecond
            )
        }
        incompleteWriter.cancel()
    }

    @Test("Pixel-buffer conversion covers alpha and allocation failures")
    func pixelBufferConversion() throws {
        let frame = try solidFrame(red: 255, green: 0, blue: 0)
        let pool = try #require(pixelBufferPool(width: 32, height: 32))

        let alphaBuffer = try P5AVVideoPipeline.pixelBuffer(
            for: frame,
            index: 0,
            pool: pool,
            width: 32,
            height: 32,
            preservesAlpha: true
        )
        #expect(CVPixelBufferGetWidth(alphaBuffer) == 32)

        #expect(throws: P5VideoExportError.frameConversionFailed(1)) {
            _ = try P5AVVideoPipeline.pixelBuffer(
                for: frame,
                index: 1,
                pool: pool,
                width: 32,
                height: 32,
                preservesAlpha: false,
                createPixelBuffer: { _ in nil }
            )
        }
        #expect(throws: P5VideoExportError.frameConversionFailed(2)) {
            _ = try P5AVVideoPipeline.pixelBuffer(
                for: frame,
                index: 2,
                pool: pool,
                width: 32,
                height: 32,
                preservesAlpha: false,
                baseAddress: { _ in nil }
            )
        }
        #expect(throws: P5VideoExportError.frameConversionFailed(3)) {
            _ = try P5AVVideoPipeline.pixelBuffer(
                for: frame,
                index: 3,
                pool: pool,
                width: 32,
                height: 32,
                preservesAlpha: false,
                makeContext: { _, _, _, _ in nil }
            )
        }
    }

    @Test("Video failures have actionable descriptions")
    func errorDescriptions() {
        let errors: [P5VideoExportError] = [
            .destinationIsNotFileURL,
            .destinationAlreadyExists,
            .pipelineCreationFailed("pipeline"),
            .frameConversionFailed(2),
            .frameAppendFailed(3, "append"),
            .writingFailed("writer"),
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }

    @Test("Invalid video options terminate at public boundaries")
    func invalidOptionsTerminateTheProcess() async {
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5VideoExportConfiguration(averageBitRate: 0)
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5VideoExportConfiguration(codec: .proRes422, fileType: .mpeg4)
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5VideoExportConfiguration(codec: .proRes4444, fileType: .mpeg4)
            }
        #endif
    }

    private func frameSequence() throws -> P5FrameSequence {
        P5FrameSequence(
            frames: [
                try solidFrame(red: 255, green: 0, blue: 0),
                try solidFrame(red: 0, green: 255, blue: 0),
                try solidFrame(red: 0, green: 0, blue: 255),
            ],
            framesPerSecond: 12
        )
    }

    private func solidFrame(red: UInt8, green: UInt8, blue: UInt8) throws -> P5Image {
        let pixel = [red, green, blue, UInt8(255)]
        return try P5Image(
            pixelBuffer: P5PixelBuffer(
                width: 32,
                height: 32,
                bytes: Array(repeating: pixel, count: 32 * 32).flatMap { $0 }
            )
        )
    }

    private func pipeline(
        named name: String,
        in directory: URL,
        sequence: P5FrameSequence,
        runtime: P5AVVideoRuntime
    ) throws -> P5AVVideoPipeline {
        try P5AVVideoPipeline(
            outputURL: directory.appendingPathComponent(name),
            sequence: sequence,
            configuration: P5VideoExportConfiguration(),
            runtime: runtime
        )
    }

    private func pixelBufferPool(width: Int, height: Int) -> CVPixelBufferPool? {
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(
            nil,
            nil,
            [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            ] as CFDictionary,
            &pool
        )
        return pool
    }
}

private enum TestVideoError: Error {
    case intentional
}

private final class PipelineState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedWriteCount = 0
    private var storedCancelCount = 0

    var writeCount: Int {
        lock.withLock { storedWriteCount }
    }

    var cancelCount: Int {
        lock.withLock { storedCancelCount }
    }

    func recordWrite() {
        lock.withLock { storedWriteCount += 1 }
    }

    func recordCancel() {
        lock.withLock { storedCancelCount += 1 }
    }
}

private final class ReadyState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCheckCount = 0

    var checkCount: Int {
        lock.withLock { storedCheckCount }
    }

    func next() -> Bool {
        lock.withLock {
            storedCheckCount += 1
            return storedCheckCount != 1
        }
    }
}

private final class TestVideoPipeline: P5VideoPipeline, @unchecked Sendable {
    let outputURL: URL
    let state: PipelineState
    let result: Result<Void, TestVideoError>
    let writesOutput: Bool

    init(
        outputURL: URL,
        state: PipelineState,
        result: Result<Void, TestVideoError>,
        writesOutput: Bool = true
    ) {
        self.outputURL = outputURL
        self.state = state
        self.result = result
        self.writesOutput = writesOutput
    }

    func write(frames: [P5Image], framesPerSecond: Double) async throws {
        state.recordWrite()
        if writesOutput {
            try Data([7, 8, 9]).write(to: outputURL)
        }
        try result.get()
    }

    func cancel() {
        state.recordCancel()
    }
}

private final class SuspendingVideoPipeline: P5VideoPipeline, @unchecked Sendable {
    let outputURL: URL
    let state: PipelineState

    init(outputURL: URL, state: PipelineState) {
        self.outputURL = outputURL
        self.state = state
    }

    func write(frames: [P5Image], framesPerSecond: Double) async throws {
        try Data([1]).write(to: outputURL)
        try await Task.sleep(for: .seconds(60))
    }

    func cancel() {
        state.recordCancel()
    }
}
