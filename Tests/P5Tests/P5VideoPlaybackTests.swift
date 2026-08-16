import AVFoundation
import CoreGraphics
import Foundation
import Testing

@testable import P5

@Suite("P5 native video playback", .serialized)
struct P5VideoPlaybackTests {
    @Test("Native video metadata and frame extraction work end to end")
    func nativeAsset() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "P5Playback-\(UUID().uuidString).mov"
        )
        defer { try? FileManager.default.removeItem(at: url) }
        try await Self.writeVideo(to: url)

        let video = P5Video(url: url)
        #expect(video.url == url)
        let metadata = try await video.metadata()
        #expect(abs(metadata.duration - 0.2) < 0.03)
        #expect(metadata.naturalSize == CGSize(width: 32, height: 32))
        #expect(abs(metadata.nominalFrameRate - 10) < 0.1)
        #expect(metadata.hasAudio == false)

        var invalidRuntime = P5VideoAssetRuntime()
        invalidRuntime.makeAsset = { _ in AVURLAsset(url: url) }
        invalidRuntime.duration = { _ in .invalid }
        let invalidMetadata = P5Video(url: url, runtime: invalidRuntime)
        await #expect(
            throws: P5VideoPlaybackError.metadataLoadingFailed(
                "AVFoundation returned invalid metadata."
            )
        ) {
            _ = try await invalidMetadata.metadata()
        }

        let extracted = try await video.frame(
            at: 0,
            configuration: P5VideoFrameExtractionConfiguration(
                maximumSize: CGSize(width: 16, height: 16),
                toleranceBefore: 0.01,
                toleranceAfter: 0.02,
                appliesPreferredTrackTransform: false
            )
        )
        #expect(extracted.requestedTime == 0)
        #expect(extracted.actualTime >= 0)
        #expect(extracted.image.pixelWidth <= 16)
        let color = try extracted.image.color(x: 2, y: 2)
        #expect(color.red > 0.7)
    }

    @Test("Video values validate, serialize, and describe failures")
    func values() throws {
        let metadata = P5VideoMetadata(
            duration: 3,
            naturalSize: CGSize(width: 1920, height: 1080),
            nominalFrameRate: 30,
            hasAudio: true
        )
        #expect(
            try JSONDecoder().decode(
                P5VideoMetadata.self,
                from: JSONEncoder().encode(metadata)
            ) == metadata
        )
        let configurations = [
            P5VideoFrameExtractionConfiguration(),
            P5VideoFrameExtractionConfiguration(
                maximumSize: CGSize(width: 640, height: 480),
                toleranceBefore: 0.5,
                toleranceAfter: 1,
                appliesPreferredTrackTransform: false
            ),
        ]
        for configuration in configurations {
            #expect(
                try JSONDecoder().decode(
                    P5VideoFrameExtractionConfiguration.self,
                    from: JSONEncoder().encode(configuration)
                ) == configuration
            )
        }
        for state in [
            P5VideoPlaybackState.paused,
            .playing,
            .ended,
            .failed("reason"),
        ] {
            #expect(
                try JSONDecoder().decode(
                    P5VideoPlaybackState.self,
                    from: JSONEncoder().encode(state)
                ) == state
            )
        }
        let errors: [P5VideoPlaybackError] = [
            .videoTrackMissing,
            .invalidTime,
            .metadataLoadingFailed("reason"),
            .frameExtractionFailed("reason"),
            .seekFailed,
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }

    @Test("Metadata loading preserves typed, framework, and cancellation failures")
    func metadataFailures() async throws {
        let url = URL(fileURLWithPath: "/missing.mov")
        var noTracks = P5VideoAssetRuntime()
        noTracks.duration = { _ in .zero }
        noTracks.tracks = { _, _ in [] }
        let missing = P5Video(url: url, runtime: noTracks)
        await #expect(throws: P5VideoPlaybackError.videoTrackMissing) {
            _ = try await missing.metadata()
        }

        var frameworkFailure = P5VideoAssetRuntime()
        frameworkFailure.duration = { _ in throw StubVideoError.metadata }
        frameworkFailure.tracks = { _, _ in [] }
        let failed = P5Video(url: url, runtime: frameworkFailure)
        await #expect(
            throws: P5VideoPlaybackError.metadataLoadingFailed("metadata")
        ) {
            _ = try await failed.metadata()
        }

        var cancelledRuntime = P5VideoAssetRuntime()
        cancelledRuntime.duration = { _ in throw CancellationError() }
        cancelledRuntime.tracks = { _, _ in [] }
        let cancelledVideo = P5Video(url: url, runtime: cancelledRuntime)
        await #expect(throws: CancellationError.self) {
            _ = try await cancelledVideo.metadata()
        }

        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await P5Video(url: url).metadata()
        }
        await #expect(throws: CancellationError.self) { _ = try await cancelled.value }
    }

    @Test("Frame extraction validates time and preserves native failures")
    func frameFailures() async throws {
        let url = URL(fileURLWithPath: "/missing.mov")
        let video = P5Video(url: url)
        for time in [Double.nan, -Double.infinity, -1] {
            await #expect(throws: P5VideoPlaybackError.invalidTime) {
                _ = try await video.frame(at: time)
            }
        }

        var runtime = P5VideoAssetRuntime()
        runtime.image = { _, _ in throw StubVideoError.extraction }
        let failed = P5Video(url: url, runtime: runtime)
        await #expect(
            throws: P5VideoPlaybackError.frameExtractionFailed("extraction")
        ) {
            _ = try await failed.frame(at: 0)
        }

        runtime.image = { _, _ in throw CancellationError() }
        let cancelled = P5Video(url: url, runtime: runtime)
        await #expect(throws: CancellationError.self) {
            _ = try await cancelled.frame(at: 0)
        }

        runtime.image = { _, _ in
            (try Self.image().cgImage, CMTime.invalid)
        }
        let invalidActualTime = P5Video(url: url, runtime: runtime)
        await #expect(
            throws: P5VideoPlaybackError.frameExtractionFailed(
                "AVFoundation returned an invalid presentation timestamp."
            )
        ) {
            _ = try await invalidActualTime.frame(at: 0)
        }

        let preCancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await video.frame(at: 0)
        }
        await #expect(throws: CancellationError.self) {
            _ = try await preCancelled.value
        }
    }

    @Test("The AVPlayer controller orders transport, end, loop, and scene state")
    @MainActor
    func playerLifecycle() async throws {
        let state = VideoPlayerState()
        var runtime = P5VideoPlayerRuntime()
        runtime.play = { _ in state.playCount += 1 }
        runtime.pause = { _ in state.pauseCount += 1 }
        runtime.seek = { _, time, before, after in
            state.seekTimes.append(time.seconds)
            state.seekTolerances.append((before.seconds, after.seconds))
            if state.cancelDuringSeek {
                withUnsafeCurrentTask { $0?.cancel() }
            }
            return state.seekSucceeds
        }
        runtime.currentTime = { _ in CMTime(seconds: 2, preferredTimescale: 600) }
        runtime.volume = { _ in state.volume }
        runtime.setVolume = { _, value in state.volume = value }
        runtime.isMuted = { _ in state.isMuted }
        runtime.setMuted = { _, value in state.isMuted = value }
        runtime.addEndObserver = { _, handler in
            state.endHandler = handler
            return P5VideoObserverToken(NSObject())
        }
        runtime.removeObserver = { _ in state.removeObserverCount += 1 }

        var player: P5VideoPlayer? = P5VideoPlayer(
            video: P5Video(url: URL(fileURLWithPath: "/movie.mov")),
            runtime: runtime
        )
        let observed = try #require(player)
        observed.stateChanged = { state.states.append($0) }
        #expect(observed.nativePlayer.currentItem != nil)
        #expect(observed.currentTime == 2)
        observed.volume = 0.25
        #expect(observed.volume == 0.25)
        observed.isMuted = true
        #expect(observed.isMuted)

        observed.play()
        observed.scenePhaseChanged(to: .active)
        #expect(state.pauseCount == 0)
        observed.scenePhaseChanged(to: .inactive)
        #expect(observed.state == .paused)
        observed.play()
        observed.pause()

        try await observed.seek(to: 1, toleranceBefore: 0.1, toleranceAfter: 0.2)
        #expect(state.seekTimes.last == 1)
        #expect(state.seekTolerances.last?.0 == 0.1)
        try await observed.stop()
        #expect(state.seekTimes.last == 0)

        state.endHandler?()
        await Self.waitUntil { observed.state == .ended }
        try await observed.seek(to: 0.5)
        #expect(observed.state == .paused)

        observed.loops = true
        state.endHandler?()
        await Self.waitUntil { state.playCount >= 3 }
        #expect(observed.state == .playing)

        state.seekSucceeds = false
        state.endHandler?()
        await Self.waitUntil {
            if case .failed = observed.state { return true }
            return false
        }

        do {
            _ = P5VideoPlayer(
                video: P5Video(url: URL(fileURLWithPath: "/disposable.mov")),
                runtime: runtime
            )
        }
        #expect(state.removeObserverCount == 1)
        player = nil
        _ = observed
    }

    @Test("Player seeks validate failure and cancellation boundaries")
    @MainActor
    func playerFailures() async throws {
        let state = VideoPlayerState()
        var runtime = P5VideoPlayerRuntime()
        runtime.seek = { _, _, _, _ in
            if state.cancelDuringSeek {
                withUnsafeCurrentTask { $0?.cancel() }
            }
            return state.seekSucceeds
        }
        runtime.addEndObserver = { _, handler in
            state.endHandler = handler
            return P5VideoObserverToken(NSObject())
        }
        runtime.removeObserver = { _ in state.removeObserverCount += 1 }
        let player = P5VideoPlayer(
            video: P5Video(url: URL(fileURLWithPath: "/movie.mov")),
            runtime: runtime
        )

        let invalid: [(Double, Double, Double)] = [
            (.nan, 0, 0), (0, -.infinity, 0), (0, 0, -1),
        ]
        for (time, before, after) in invalid {
            await #expect(throws: P5VideoPlaybackError.invalidTime) {
                try await player.seek(
                    to: time,
                    toleranceBefore: before,
                    toleranceAfter: after
                )
            }
        }

        state.seekSucceeds = false
        await #expect(throws: P5VideoPlaybackError.seekFailed) {
            try await player.seek(to: 0)
        }
        state.seekSucceeds = true
        state.cancelDuringSeek = true
        await #expect(throws: CancellationError.self) {
            try await player.seek(to: 0)
        }
        state.cancelDuringSeek = false

        let cancelled = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            try await player.seek(to: 0)
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }

        state.seekSucceeds = false
        player.loops = true
        state.endHandler?()
        await Self.waitUntil {
            if case .failed = player.state { return true }
            return false
        }
        player.scenePhaseChanged(to: .background)
    }

    @Test("The default AVPlayer runtime drives a real local movie")
    @MainActor
    func nativePlayer() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "P5NativePlayer-\(UUID().uuidString).mov"
        )
        defer { try? FileManager.default.removeItem(at: url) }
        try await Self.writeVideo(to: url)

        var player: P5VideoPlayer? = P5VideoPlayer(video: P5Video(url: url))
        let native = try #require(player)
        native.volume = 0.5
        #expect(native.volume == 0.5)
        native.isMuted = true
        #expect(native.isMuted)
        _ = native.currentTime
        native.play()
        native.pause()
        try await native.seek(to: 0)
        try await native.stop()
        NotificationCenter.default.post(
            name: AVPlayerItem.didPlayToEndTimeNotification,
            object: native.nativePlayer.currentItem
        )
        await Self.waitUntil { native.state == .ended }
        do {
            _ = P5VideoPlayer(video: P5Video(url: url))
        }
        player = nil
        _ = native
    }

    @Test("Invalid video values terminate at their public boundaries")
    func invalidValues() async {
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5VideoMetadata(
                    duration: .nan,
                    naturalSize: CGSize(width: 1, height: 1),
                    nominalFrameRate: 1,
                    hasAudio: false
                )
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5VideoMetadata(
                    duration: 1,
                    naturalSize: CGSize(width: 0, height: 1),
                    nominalFrameRate: 1,
                    hasAudio: false
                )
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5VideoMetadata(
                    duration: 1,
                    naturalSize: CGSize(width: 1, height: CGFloat.infinity),
                    nominalFrameRate: 1,
                    hasAudio: false
                )
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5VideoMetadata(
                    duration: 1,
                    naturalSize: CGSize(width: 1, height: 1),
                    nominalFrameRate: -.infinity,
                    hasAudio: false
                )
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5VideoFrameExtractionConfiguration(toleranceBefore: -1)
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5VideoFrameExtractionConfiguration(toleranceAfter: .nan)
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5VideoFrameExtractionConfiguration(
                    maximumSize: CGSize(width: 1, height: 0)
                )
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5VideoFrame(
                    image: try! Self.image(),
                    requestedTime: .nan,
                    actualTime: 0
                )
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5VideoFrame(
                    image: try! Self.image(),
                    requestedTime: 0,
                    actualTime: -1
                )
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    let player = P5VideoPlayer(
                        video: P5Video(url: URL(fileURLWithPath: "/movie.mov"))
                    )
                    player.volume = .nan
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    let player = P5VideoPlayer(
                        video: P5Video(url: URL(fileURLWithPath: "/movie.mov"))
                    )
                    player.volume = 2
                }
            }
        #endif
    }

    private static func writeVideo(to url: URL) async throws {
        let frames = try [
            P5Image(
                pixelBuffer: P5PixelBuffer(
                    width: 32,
                    height: 32,
                    bytes: Array(repeating: [UInt8(255), 0, 0, 255], count: 32 * 32)
                        .flatMap { $0 }
                )
            ),
            P5Image(
                pixelBuffer: P5PixelBuffer(
                    width: 32,
                    height: 32,
                    bytes: Array(repeating: [UInt8(0), 0, 255, 255], count: 32 * 32)
                        .flatMap { $0 }
                )
            ),
        ]
        try await P5FrameSequence(frames: frames, framesPerSecond: 10).writeVideo(to: url)
    }

    private static func image() throws -> P5Image {
        try P5Image(
            pixelBuffer: P5PixelBuffer(width: 1, height: 1, bytes: [255, 0, 0, 255])
        )
    }

    @MainActor
    private static func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0..<200 where predicate() == false {
            await Task.yield()
        }
        #expect(predicate())
    }
}

private final class VideoPlayerState: @unchecked Sendable {
    var playCount = 0
    var pauseCount = 0
    var seekTimes: [Double] = []
    var seekTolerances: [(Double, Double)] = []
    var seekSucceeds = true
    var cancelDuringSeek = false
    var volume: Float = 1
    var isMuted = false
    var endHandler: (@Sendable () -> Void)?
    var removeObserverCount = 0
    var states: [P5VideoPlaybackState] = []
}

private enum StubVideoError: String, Error, LocalizedError {
    case metadata
    case extraction

    var errorDescription: String? { rawValue }
}
