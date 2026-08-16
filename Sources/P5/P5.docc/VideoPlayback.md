# Video Playback and Frame Extraction

Inspect, sample, and play AVFoundation media without starting protected resources implicitly.

## Inspect a video lazily

``P5Video`` is an immutable URL-backed reference. Creating one does not open a file, make a
network request, or start playback. Load metadata explicitly from an asynchronous context:

```swift
let video = P5Video(url: movieURL)
let metadata = try await video.metadata()

print(metadata.duration)
print(metadata.naturalSize)
print(metadata.nominalFrameRate)
print(metadata.hasAudio)
```

Metadata dimensions include the video's preferred display transform. Failures are reported as
``P5VideoPlaybackError`` values, and task cancellation is preserved as `CancellationError`.

## Extract a frame

Frame extraction uses `AVAssetImageGenerator`. The default configuration requests an exact
timestamp and applies the preferred display transform:

```swift
let frame = try await video.frame(at: 1.25)
let image = frame.image

print(frame.requestedTime)
print(frame.actualTime)
```

For thumbnails or media whose exact frames are expensive to decode, set a maximum size and
explicit seek tolerances:

```swift
let thumbnail = try await video.frame(
    at: 10,
    configuration: P5VideoFrameExtractionConfiguration(
        maximumSize: CGSize(width: 320, height: 180),
        toleranceBefore: 0.1,
        toleranceAfter: 0.1
    )
)
```

Use the reported `actualTime` when synchronizing extracted images with another timeline. Remote
URLs are loaded by AVFoundation and may involve network access when metadata or frames are
requested.

## Control native playback

Create ``P5VideoPlayer`` on the main actor. Its ``P5VideoPlayer/nativePlayer`` is an `AVPlayer`
that can be passed directly to SwiftUI's `VideoPlayer` or an `AVPlayerLayer`:

```swift
let controller = P5VideoPlayer(video: video)

controller.stateChanged = { state in
    print(state)
}

controller.play()
try await controller.seek(to: 5)
controller.pause()
try await controller.stop()
```

Set ``P5VideoPlayer/loops`` before playback to restart automatically at the end. Looping performs
an asynchronous seek; a rejected seek moves the controller to
``P5VideoPlaybackState/failed(_:)``. Non-looping playback transitions to
``P5VideoPlaybackState/ended``. Seek or stop before calling `play()` again from the beginning.

Forward host lifecycle changes with ``P5VideoPlayer/scenePhaseChanged(to:)``. Inactive and
background scenes pause playback; returning active never resumes media automatically. Playback,
volume, mute state, and scene behavior are always explicit and require no camera, microphone, or
Photos authorization.

Movie creation and camera recording are separate operations. Use
``P5FrameSequence/writeVideo(to:configuration:)`` for rendered frames and
``P5CaptureSession`` for live camera media. See <doc:RasterColorAndExport> and
<doc:CameraCapture>.
