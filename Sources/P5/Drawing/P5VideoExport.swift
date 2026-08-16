import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

/// A native video compression format supported by frame-sequence export.
public enum P5VideoCodec: String, Sendable, Hashable, Codable, CaseIterable {
    /// Broadly compatible H.264/AVC video without alpha.
    case h264
    /// High Efficiency Video Coding without alpha.
    case hevc
    /// Apple ProRes 422 for high-quality QuickTime workflows.
    case proRes422
    /// Apple ProRes 4444 with alpha-channel support.
    case proRes4444

    var avCodec: AVVideoCodecType {
        switch self {
        case .h264: .h264
        case .hevc: .hevc
        case .proRes422: .proRes422
        case .proRes4444: .proRes4444
        }
    }

    var supportsAlpha: Bool {
        self == .proRes4444
    }
}

/// Container used for native video export.
public enum P5VideoFileType: String, Sendable, Hashable, Codable, CaseIterable {
    /// Apple QuickTime Movie container.
    case quickTimeMovie
    /// ISO MPEG-4 container.
    case mpeg4

    var avFileType: AVFileType {
        switch self {
        case .quickTimeMovie: .mov
        case .mpeg4: .mp4
        }
    }

    /// Preferred file-name extension without a leading period.
    public var filenameExtension: String {
        switch self {
        case .quickTimeMovie: "mov"
        case .mpeg4: "mp4"
        }
    }
}

/// Validated options for writing a ``P5FrameSequence`` as a native movie.
public struct P5VideoExportConfiguration: Sendable, Hashable, Codable {
    /// Compression codec.
    public let codec: P5VideoCodec
    /// Destination container.
    public let fileType: P5VideoFileType
    /// Optional target average bit rate in bits per second.
    public let averageBitRate: Int?
    /// Whether the writer should arrange compatible output for network playback.
    public let optimizesForNetworkUse: Bool

    /// Creates validated video export options.
    ///
    /// - Precondition: A supplied bit rate is positive, and ProRes uses a
    ///   QuickTime Movie container.
    public init(
        codec: P5VideoCodec = .h264,
        fileType: P5VideoFileType = .quickTimeMovie,
        averageBitRate: Int? = nil,
        optimizesForNetworkUse: Bool = true
    ) {
        precondition(averageBitRate.map { $0 > 0 } ?? true)
        precondition(
            fileType == .quickTimeMovie || (codec != .proRes422 && codec != .proRes4444)
        )
        self.codec = codec
        self.fileType = fileType
        self.averageBitRate = averageBitRate
        self.optimizesForNetworkUse = optimizesForNetworkUse
    }

    /// Decodes and revalidates serialized export options.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let codec = try container.decode(P5VideoCodec.self, forKey: .codec)
        let fileType = try container.decode(P5VideoFileType.self, forKey: .fileType)
        let averageBitRate = try container.decodeIfPresent(Int.self, forKey: .averageBitRate)
        guard
            averageBitRate.map({ $0 > 0 }) ?? true,
            fileType == .quickTimeMovie || (codec != .proRes422 && codec != .proRes4444)
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .codec,
                in: container,
                debugDescription: "Video codec, container, or bit rate is invalid."
            )
        }
        self.init(
            codec: codec,
            fileType: fileType,
            averageBitRate: averageBitRate,
            optimizesForNetworkUse: try container.decode(
                Bool.self,
                forKey: .optimizesForNetworkUse
            )
        )
    }
}

/// Failures produced by deterministic native video export.
public enum P5VideoExportError: Error, Sendable, Hashable, LocalizedError {
    /// The destination is not a local file URL.
    case destinationIsNotFileURL
    /// A file already exists at the destination and was not overwritten.
    case destinationAlreadyExists
    /// AVFoundation could not create the output pipeline.
    case pipelineCreationFailed(String)
    /// Core Video could not allocate or render a frame.
    case frameConversionFailed(Int)
    /// AVFoundation rejected a numbered frame.
    case frameAppendFailed(Int, String)
    /// The writer failed to start or finish.
    case writingFailed(String)

    /// A localized description suitable for diagnostics and user interfaces.
    public var errorDescription: String? {
        switch self {
        case .destinationIsNotFileURL:
            "Video export requires a local file URL."
        case .destinationAlreadyExists:
            "Video export does not overwrite an existing destination."
        case .pipelineCreationFailed(let reason):
            "The native video pipeline could not be created: \(reason)"
        case .frameConversionFailed(let index):
            "Video frame \(index) could not be converted to a native pixel buffer."
        case .frameAppendFailed(let index, let reason):
            "Video frame \(index) could not be appended: \(reason)"
        case .writingFailed(let reason):
            "The native video writer failed: \(reason)"
        }
    }
}

extension P5FrameSequence {
    /// Writes the complete sequence as an atomic native movie.
    ///
    /// Export never overwrites an existing item. Cancellation removes the private
    /// partial file and throws `CancellationError`.
    public func writeVideo(
        to url: URL,
        configuration: P5VideoExportConfiguration = P5VideoExportConfiguration()
    ) async throws {
        try await writeVideo(
            to: url,
            configuration: configuration,
            fileManager: .default,
            makePipeline: { outputURL, sequence, configuration in
                try P5AVVideoPipeline(
                    outputURL: outputURL,
                    sequence: sequence,
                    configuration: configuration
                )
            }
        )
    }

    func writeVideo(
        to url: URL,
        configuration: P5VideoExportConfiguration,
        fileManager: FileManager,
        makePipeline: (URL, P5FrameSequence, P5VideoExportConfiguration) throws ->
            any P5VideoPipeline
    ) async throws {
        guard url.isFileURL else {
            throw P5VideoExportError.destinationIsNotFileURL
        }
        guard fileManager.fileExists(atPath: url.path) == false else {
            throw P5VideoExportError.destinationAlreadyExists
        }
        let temporaryURL = url.deletingLastPathComponent().appendingPathComponent(
            ".\(url.lastPathComponent).p5-\(UUID().uuidString).partial"
        )
        let pipeline = try makePipeline(temporaryURL, self, configuration)
        do {
            try await withTaskCancellationHandler {
                try await pipeline.write(frames: frames, framesPerSecond: framesPerSecond)
            } onCancel: {
                pipeline.cancel()
            }
            try fileManager.moveItem(at: temporaryURL, to: url)
        } catch {
            pipeline.cancel()
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }
}

protocol P5VideoPipeline: Sendable {
    func write(frames: [P5Image], framesPerSecond: Double) async throws
    func cancel()
}

struct P5AVVideoRuntime {
    var makeWriter: (URL, AVFileType) throws -> AVAssetWriter = {
        try AVAssetWriter(outputURL: $0, fileType: $1)
    }
    var canAdd: (AVAssetWriter, AVAssetWriterInput) -> Bool = { $0.canAdd($1) }
    var startWriting: (AVAssetWriter) -> Bool = { $0.startWriting() }
    var isReady: (AVAssetWriterInput) -> Bool = { $0.isReadyForMoreMediaData }
    var status: (AVAssetWriter) -> AVAssetWriter.Status = { $0.status }
    var error: (AVAssetWriter) -> (any Error)? = { $0.error }
    var pixelBufferPool: (AVAssetWriterInputPixelBufferAdaptor) -> CVPixelBufferPool? = {
        $0.pixelBufferPool
    }
    var append: (AVAssetWriterInputPixelBufferAdaptor, CVPixelBuffer, CMTime) -> Bool = {
        $0.append($1, withPresentationTime: $2)
    }
    var finishWriting: (AVAssetWriter) async -> Void = { await $0.finishWriting() }
    var cancelWriting: (AVAssetWriter) -> Void = { $0.cancelWriting() }
}

final class P5AVVideoPipeline: P5VideoPipeline, @unchecked Sendable {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let width: Int
    private let height: Int
    private let preservesAlpha: Bool
    private let runtime: P5AVVideoRuntime

    init(
        outputURL: URL,
        sequence: P5FrameSequence,
        configuration: P5VideoExportConfiguration,
        runtime: P5AVVideoRuntime = P5AVVideoRuntime()
    ) throws {
        width = sequence.frames[0].pixelWidth
        height = sequence.frames[0].pixelHeight
        preservesAlpha = configuration.codec.supportsAlpha
        self.runtime = runtime
        do {
            writer = try runtime.makeWriter(outputURL, configuration.fileType.avFileType)
        } catch {
            throw P5VideoExportError.pipelineCreationFailed(error.localizedDescription)
        }
        writer.shouldOptimizeForNetworkUse = configuration.optimizesForNetworkUse

        var compression: [String: Any] = [
            AVVideoExpectedSourceFrameRateKey: sequence.framesPerSecond
        ]
        if let averageBitRate = configuration.averageBitRate {
            compression[AVVideoAverageBitRateKey] = averageBitRate
        }
        let settings: [String: Any] = [
            AVVideoCodecKey: configuration.codec.avCodec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        guard runtime.canAdd(writer, input) else {
            throw P5VideoExportError.pipelineCreationFailed("AVAssetWriter rejected video input.")
        }
        writer.add(input)

        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ]
        )
    }

    func write(frames: [P5Image], framesPerSecond: Double) async throws {
        guard runtime.startWriting(writer) else {
            throw writingError(fallback: "AVAssetWriter did not start.")
        }
        writer.startSession(atSourceTime: .zero)

        for (index, frame) in frames.enumerated() {
            while runtime.isReady(input) == false {
                try Task.checkCancellation()
                if runtime.status(writer) == .failed {
                    throw writingError(fallback: "AVAssetWriter failed while awaiting input.")
                }
                await Task.yield()
            }
            try Task.checkCancellation()
            guard let pool = runtime.pixelBufferPool(adaptor) else {
                throw P5VideoExportError.frameConversionFailed(index)
            }
            let pixelBuffer = try Self.pixelBuffer(
                for: frame,
                index: index,
                pool: pool,
                width: width,
                height: height,
                preservesAlpha: preservesAlpha
            )
            let presentationTime = CMTime(
                seconds: Double(index) / framesPerSecond,
                preferredTimescale: 60_000
            )
            guard runtime.append(adaptor, pixelBuffer, presentationTime) else {
                throw P5VideoExportError.frameAppendFailed(
                    index,
                    runtime.error(writer)?.localizedDescription
                        ?? "AVAssetWriter rejected the frame."
                )
            }
        }

        input.markAsFinished()
        writer.endSession(
            atSourceTime: CMTime(
                seconds: Double(frames.count) / framesPerSecond,
                preferredTimescale: 60_000
            )
        )
        await runtime.finishWriting(writer)
        guard runtime.status(writer) == .completed else {
            throw writingError(fallback: "AVAssetWriter did not complete.")
        }
    }

    func cancel() {
        runtime.cancelWriting(writer)
    }

    private func writingError(fallback: String) -> P5VideoExportError {
        P5VideoExportError.writingFailed(runtime.error(writer)?.localizedDescription ?? fallback)
    }

    static func pixelBuffer(
        for frame: P5Image,
        index: Int,
        pool: CVPixelBufferPool,
        width: Int,
        height: Int,
        preservesAlpha: Bool,
        createPixelBuffer: (CVPixelBufferPool) -> CVPixelBuffer? = { pool in
            var pixelBuffer: CVPixelBuffer?
            _ = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            return pixelBuffer
        },
        baseAddress: (CVPixelBuffer) -> UnsafeMutableRawPointer? = {
            CVPixelBufferGetBaseAddress($0)
        },
        makeContext: (UnsafeMutableRawPointer, Int, Int, Int) -> CGContext? = {
            baseAddress,
            width,
            height,
            bytesPerRow in
            CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: P5RasterColorSpace.preferred(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                    | CGImageAlphaInfo.premultipliedFirst.rawValue
            )
        }
    ) throws -> CVPixelBuffer {
        guard let pixelBuffer = createPixelBuffer(pool) else {
            throw P5VideoExportError.frameConversionFailed(index)
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard
            let baseAddress = baseAddress(pixelBuffer),
            let context = makeContext(
                baseAddress,
                width,
                height,
                CVPixelBufferGetBytesPerRow(pixelBuffer)
            )
        else {
            throw P5VideoExportError.frameConversionFailed(index)
        }
        if preservesAlpha == false {
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.draw(frame.cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }
}
