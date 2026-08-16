import AVFoundation
import CoreGraphics
import Foundation

/// Validated metadata loaded from a native audiovisual asset.
public struct P5VideoMetadata: Sendable, Hashable, Codable {
    /// Asset duration in seconds.
    public let duration: Double
    /// Display dimensions after applying the preferred track transform.
    public let naturalSize: CGSize
    /// Nominal video frame rate reported by the primary video track.
    public let nominalFrameRate: Double
    /// Whether the asset contains at least one audio track.
    public let hasAudio: Bool

    /// Creates validated video metadata.
    ///
    /// - Precondition: Duration and frame rate are finite and nonnegative, and
    ///   dimensions are finite and positive.
    public init(
        duration: Double,
        naturalSize: CGSize,
        nominalFrameRate: Double,
        hasAudio: Bool
    ) {
        precondition(duration.isFinite && duration >= 0)
        precondition(
            naturalSize.width.isFinite && naturalSize.width > 0
                && naturalSize.height.isFinite && naturalSize.height > 0
        )
        precondition(nominalFrameRate.isFinite && nominalFrameRate >= 0)
        self.duration = duration
        self.naturalSize = naturalSize
        self.nominalFrameRate = nominalFrameRate
        self.hasAudio = hasAudio
    }
}

/// Controls native frame extraction accuracy and output size.
public struct P5VideoFrameExtractionConfiguration: Sendable, Hashable, Codable {
    /// Maximum output dimensions, or `nil` to preserve the source resolution.
    public let maximumSize: CGSize?
    /// Allowed seek tolerance before the requested timestamp in seconds.
    public let toleranceBefore: Double
    /// Allowed seek tolerance after the requested timestamp in seconds.
    public let toleranceAfter: Double
    /// Whether to apply the source track's preferred display transform.
    public let appliesPreferredTrackTransform: Bool

    /// Creates validated frame-extraction options.
    ///
    /// - Precondition: Tolerances are finite and nonnegative; supplied maximum
    ///   dimensions are finite and positive.
    public init(
        maximumSize: CGSize? = nil,
        toleranceBefore: Double = 0,
        toleranceAfter: Double = 0,
        appliesPreferredTrackTransform: Bool = true
    ) {
        precondition(toleranceBefore.isFinite && toleranceBefore >= 0)
        precondition(toleranceAfter.isFinite && toleranceAfter >= 0)
        precondition(
            maximumSize.map {
                $0.width.isFinite && $0.width > 0 && $0.height.isFinite && $0.height > 0
            } ?? true
        )
        self.maximumSize = maximumSize
        self.toleranceBefore = toleranceBefore
        self.toleranceAfter = toleranceAfter
        self.appliesPreferredTrackTransform = appliesPreferredTrackTransform
    }
}

/// One image extracted from a native video timeline.
public struct P5VideoFrame: @unchecked Sendable {
    /// Immutable extracted image.
    public let image: P5Image
    /// Requested timestamp in seconds.
    public let requestedTime: Double
    /// Actual timestamp selected by AVFoundation in seconds.
    public let actualTime: Double

    /// Creates a validated extracted video frame.
    ///
    /// - Precondition: Both timestamps are finite and nonnegative.
    public init(image: P5Image, requestedTime: Double, actualTime: Double) {
        precondition(requestedTime.isFinite && requestedTime >= 0)
        precondition(actualTime.isFinite && actualTime >= 0)
        self.image = image
        self.requestedTime = requestedTime
        self.actualTime = actualTime
    }
}

/// Failures produced by native video inspection, extraction, and playback control.
public enum P5VideoPlaybackError: Error, Sendable, Hashable, LocalizedError {
    /// The asset does not contain a video track.
    case videoTrackMissing
    /// A requested playback or extraction timestamp is invalid.
    case invalidTime
    /// AVFoundation could not load asset metadata.
    case metadataLoadingFailed(String)
    /// AVFoundation could not produce an image at the requested time.
    case frameExtractionFailed(String)
    /// AVPlayer rejected a requested seek operation.
    case seekFailed

    /// A localized description suitable for diagnostics and user interfaces.
    public var errorDescription: String? {
        switch self {
        case .videoTrackMissing:
            "The asset does not contain a video track."
        case .invalidTime:
            "Video time must be finite and nonnegative."
        case .metadataLoadingFailed(let reason):
            "Video metadata could not be loaded: \(reason)"
        case .frameExtractionFailed(let reason):
            "A video frame could not be extracted: \(reason)"
        case .seekFailed:
            "The native video player did not complete the requested seek."
        }
    }
}

/// Immutable reference to a local or remote AVFoundation video asset.
public struct P5Video: @unchecked Sendable {
    /// Source URL used by AVFoundation.
    public let url: URL
    private let runtime: P5VideoAssetRuntime

    /// Creates a lazy native video reference without loading network or file data.
    public init(url: URL) {
        self.url = url
        runtime = P5VideoAssetRuntime()
    }

    init(url: URL, runtime: P5VideoAssetRuntime) {
        self.url = url
        self.runtime = runtime
    }

    /// Loads duration, transformed dimensions, frame rate, and audio presence.
    public func metadata() async throws -> P5VideoMetadata {
        try Task.checkCancellation()
        let asset = runtime.makeAsset(url)
        do {
            async let duration = runtime.duration(asset)
            async let videoTracks = runtime.tracks(asset, .video)
            async let audioTracks = runtime.tracks(asset, .audio)
            let (loadedDuration, loadedVideoTracks, loadedAudioTracks) = try await (
                duration, videoTracks, audioTracks
            )
            try Task.checkCancellation()
            guard let track = loadedVideoTracks.first else {
                throw P5VideoPlaybackError.videoTrackMissing
            }
            let naturalSize = try await runtime.naturalSize(track)
            let transform = try await runtime.preferredTransform(track)
            let transformed = CGRect(origin: .zero, size: naturalSize)
                .applying(transform).standardized.size
            let frameRate = try await runtime.nominalFrameRate(track)
            let durationSeconds = loadedDuration.seconds
            let nominalFrameRate = Double(frameRate)
            guard
                durationSeconds.isFinite && durationSeconds >= 0,
                transformed.width.isFinite && transformed.width > 0,
                transformed.height.isFinite && transformed.height > 0,
                nominalFrameRate.isFinite && nominalFrameRate >= 0
            else {
                throw P5VideoPlaybackError.metadataLoadingFailed(
                    "AVFoundation returned invalid metadata."
                )
            }
            return P5VideoMetadata(
                duration: durationSeconds,
                naturalSize: transformed,
                nominalFrameRate: nominalFrameRate,
                hasAudio: loadedAudioTracks.isEmpty == false
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as P5VideoPlaybackError {
            throw error
        } catch {
            throw P5VideoPlaybackError.metadataLoadingFailed(error.localizedDescription)
        }
    }

    /// Extracts a native image near a nonnegative timeline timestamp.
    public func frame(
        at time: Double,
        configuration: P5VideoFrameExtractionConfiguration =
            P5VideoFrameExtractionConfiguration()
    ) async throws -> P5VideoFrame {
        guard time.isFinite && time >= 0 else {
            throw P5VideoPlaybackError.invalidTime
        }
        try Task.checkCancellation()
        let asset = runtime.makeAsset(url)
        let generator = runtime.makeImageGenerator(asset)
        generator.appliesPreferredTrackTransform = configuration.appliesPreferredTrackTransform
        if let maximumSize = configuration.maximumSize {
            generator.maximumSize = maximumSize
        }
        generator.requestedTimeToleranceBefore = CMTime(
            seconds: configuration.toleranceBefore,
            preferredTimescale: 600
        )
        generator.requestedTimeToleranceAfter = CMTime(
            seconds: configuration.toleranceAfter,
            preferredTimescale: 600
        )
        do {
            let requested = CMTime(seconds: time, preferredTimescale: 600)
            let generated = try await runtime.image(generator, requested)
            try Task.checkCancellation()
            let actualTime = generated.actualTime.seconds
            guard actualTime.isFinite && actualTime >= 0 else {
                throw P5VideoPlaybackError.frameExtractionFailed(
                    "AVFoundation returned an invalid presentation timestamp."
                )
            }
            return P5VideoFrame(
                image: P5Image(cgImage: generated.image),
                requestedTime: time,
                actualTime: actualTime
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as P5VideoPlaybackError {
            throw error
        } catch {
            throw P5VideoPlaybackError.frameExtractionFailed(error.localizedDescription)
        }
    }
}

/// User-visible playback state maintained by ``P5VideoPlayer``.
public enum P5VideoPlaybackState: Sendable, Hashable, Codable {
    /// Playback is paused or has not started.
    case paused
    /// Playback is currently requested from AVPlayer.
    case playing
    /// The player reached the end and looping is disabled.
    case ended
    /// A looping seek or another asynchronous transport operation failed.
    case failed(String)
}

/// Main-actor AVPlayer controller suitable for SwiftUI's `VideoPlayer`.
@MainActor
public final class P5VideoPlayer {
    /// Video represented by this player.
    public let video: P5Video
    /// Native player for use with `AVPlayerLayer` or SwiftUI `VideoPlayer`.
    public let nativePlayer: AVPlayer
    /// Current deterministic transport state.
    public private(set) var state = P5VideoPlaybackState.paused
    /// Whether playback restarts automatically after reaching the end.
    public var loops = false
    /// Called on the main actor after every state transition.
    public var stateChanged: (@MainActor @Sendable (P5VideoPlaybackState) -> Void)?

    private let runtime: P5VideoPlayerRuntime
    private let item: AVPlayerItem
    private var endObserver: P5VideoObserverToken?

    /// Creates a paused native player without loading or starting media.
    public convenience init(video: P5Video) {
        self.init(video: video, runtime: P5VideoPlayerRuntime())
    }

    init(video: P5Video, runtime: P5VideoPlayerRuntime) {
        self.video = video
        self.runtime = runtime
        item = runtime.makeItem(video.url)
        nativePlayer = runtime.makePlayer(item)
        endObserver = runtime.addEndObserver(item) { [weak self] in
            Task { @MainActor in self?.reachedEnd() }
        }
    }

    deinit {
        if let endObserver {
            runtime.removeObserver(endObserver)
        }
    }

    /// Native playback volume in the closed range `0...1`.
    public var volume: Float {
        get { runtime.volume(nativePlayer) }
        set {
            precondition(newValue.isFinite && (0...1).contains(newValue))
            runtime.setVolume(nativePlayer, newValue)
        }
    }

    /// Whether AVPlayer suppresses audio output.
    public var isMuted: Bool {
        get { runtime.isMuted(nativePlayer) }
        set { runtime.setMuted(nativePlayer, newValue) }
    }

    /// Current native playback timestamp in seconds.
    public var currentTime: Double {
        runtime.currentTime(nativePlayer).seconds
    }

    /// Requests native playback from the current timeline position.
    public func play() {
        runtime.play(nativePlayer)
        transition(to: .playing)
    }

    /// Pauses native playback without changing the timeline position.
    public func pause() {
        runtime.pause(nativePlayer)
        transition(to: .paused)
    }

    /// Seeks to a nonnegative timeline position with explicit tolerances.
    public func seek(
        to time: Double,
        toleranceBefore: Double = 0,
        toleranceAfter: Double = 0
    ) async throws {
        guard
            time.isFinite && time >= 0,
            toleranceBefore.isFinite && toleranceBefore >= 0,
            toleranceAfter.isFinite && toleranceAfter >= 0
        else {
            throw P5VideoPlaybackError.invalidTime
        }
        try Task.checkCancellation()
        let completed = await runtime.seek(
            nativePlayer,
            CMTime(seconds: time, preferredTimescale: 600),
            CMTime(seconds: toleranceBefore, preferredTimescale: 600),
            CMTime(seconds: toleranceAfter, preferredTimescale: 600)
        )
        try Task.checkCancellation()
        guard completed else {
            throw P5VideoPlaybackError.seekFailed
        }
        if state == .ended {
            transition(to: .paused)
        }
    }

    /// Pauses and rewinds playback to the beginning.
    public func stop() async throws {
        runtime.pause(nativePlayer)
        try await seek(to: 0)
        transition(to: .paused)
    }

    /// Pauses playback whenever the host scene is not active.
    ///
    /// Returning active never resumes media implicitly.
    public func scenePhaseChanged(to phase: P5ScenePhase) {
        if phase != .active && state == .playing {
            pause()
        }
    }

    private func reachedEnd() {
        if loops {
            Task {
                do {
                    try await seek(to: 0)
                    play()
                } catch {
                    transition(to: .failed(error.localizedDescription))
                }
            }
        } else {
            transition(to: .ended)
        }
    }

    private func transition(to state: P5VideoPlaybackState) {
        self.state = state
        stateChanged?(state)
    }
}

struct P5VideoAssetRuntime: @unchecked Sendable {
    var makeAsset: (URL) -> AVURLAsset = { AVURLAsset(url: $0) }
    var duration: @Sendable (AVURLAsset) async throws -> CMTime = { try await $0.load(.duration) }
    var tracks: @Sendable (AVURLAsset, AVMediaType) async throws -> [AVAssetTrack] = {
        try await $0.loadTracks(withMediaType: $1)
    }
    var naturalSize: @Sendable (AVAssetTrack) async throws -> CGSize = {
        try await $0.load(.naturalSize)
    }
    var preferredTransform: @Sendable (AVAssetTrack) async throws -> CGAffineTransform = {
        try await $0.load(.preferredTransform)
    }
    var nominalFrameRate: @Sendable (AVAssetTrack) async throws -> Float = {
        try await $0.load(.nominalFrameRate)
    }
    var makeImageGenerator: (AVURLAsset) -> AVAssetImageGenerator = AVAssetImageGenerator.init(
        asset:)
    var image:
        @Sendable (AVAssetImageGenerator, CMTime) async throws -> (
            image: CGImage, actualTime: CMTime
        ) = {
            let generated = try await $0.image(at: $1)
            return (generated.image, generated.actualTime)
        }
}

struct P5VideoPlayerRuntime: @unchecked Sendable {
    var makeItem: (URL) -> AVPlayerItem = AVPlayerItem.init(url:)
    var makePlayer: (AVPlayerItem) -> AVPlayer = AVPlayer.init(playerItem:)
    var play: (AVPlayer) -> Void = { $0.play() }
    var pause: (AVPlayer) -> Void = { $0.pause() }
    var seek: @Sendable (AVPlayer, CMTime, CMTime, CMTime) async -> Bool = {
        await $0.seek(to: $1, toleranceBefore: $2, toleranceAfter: $3)
    }
    var currentTime: (AVPlayer) -> CMTime = { $0.currentTime() }
    var volume: (AVPlayer) -> Float = { $0.volume }
    var setVolume: (AVPlayer, Float) -> Void = { $0.volume = $1 }
    var isMuted: (AVPlayer) -> Bool = { $0.isMuted }
    var setMuted: (AVPlayer, Bool) -> Void = { $0.isMuted = $1 }
    var addEndObserver:
        (
            AVPlayerItem,
            @escaping @Sendable () -> Void
        ) -> P5VideoObserverToken = { item, handler in
            P5VideoObserverToken(
                NotificationCenter.default.addObserver(
                    forName: AVPlayerItem.didPlayToEndTimeNotification,
                    object: item,
                    queue: .main
                ) { _ in handler() }
            )
        }
    var removeObserver: (P5VideoObserverToken) -> Void = {
        NotificationCenter.default.removeObserver($0.value)
    }
}

final class P5VideoObserverToken: @unchecked Sendable {
    let value: any NSObjectProtocol

    init(_ value: any NSObjectProtocol) {
        self.value = value
    }
}
