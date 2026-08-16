# Camera Capture and Movie Recording

Deliver native camera frames and record optional microphone audio with explicit lifecycle
control.

## Authorize before creating the experience

``P5CaptureSession`` never requests permission. Ask from a clear user action with
``P5MediaAuthorization``, then create and start the session on the main actor:

```swift
let authorization = P5MediaAuthorization()
guard try await authorization.requestAuthorization(for: .camera) == .authorized else {
    return
}

let capture = P5CaptureSession(
    configuration: P5CaptureConfiguration(
        cameraPosition: .front,
        quality: .hd1280x720
    )
)

capture.frameCaptured = { frame in
    // Update sketch state or run an ML5 image model on frame.image.
}

try await capture.start()
```

An audio-enabled configuration also requires explicit microphone authorization before
`start()`:

```swift
_ = try await authorization.requestAuthorization(for: .microphone)

let capture = P5CaptureSession(
    configuration: P5CaptureConfiguration(includesAudio: true)
)
```

P5 configures and starts AVFoundation away from the main actor, converts BGRA preview samples
through Core Image, and delivers ``P5CaptureFrame`` values back on the main actor. By default,
late preview frames are discarded so rendering or model inference cannot create an unbounded
backlog. Use ``P5CaptureSession/latestFrame`` when only the newest image matters.

## Record and finish a movie

Recording writes directly through `AVCaptureMovieFileOutput`. The destination must be a new
local file; P5 never overwrites an existing item.

```swift
try capture.startRecording(to: movieURL)

// Later, after a user action:
let completedURL = try await capture.stopRecording()
```

``P5CaptureSession/recordingFinished`` reports completion even when AVFoundation stops a
recording independently. `stopRecording()` waits for the native file-output delegate rather
than treating the stop request as successful prematurely. AVFoundation's
`AVErrorRecordingSuccessfullyFinishedKey` is honored when the framework attaches a
nonfatal diagnostic to a complete file.

## Release protected resources

Call ``P5CaptureSession/stop()`` when preview is no longer visible. Pass scene changes to
``P5CaptureSession/scenePhaseChanged(to:)``; inactive and background transitions finish an
active recording and stop camera and microphone resources. Returning active never restarts
capture implicitly.

Frame-conversion, recording, configuration, and start failures move
``P5CaptureSession/state`` to ``P5CaptureSessionState/failed(_:)`` and stop running hardware.
The callbacks and state transitions are main-actor ordered. A stopped session retains its
validated native configuration and can be started again without recreating inputs and outputs.

The host application must provide `NSCameraUsageDescription` and, when audio is enabled,
`NSMicrophoneUsageDescription`. See <doc:MediaAuthorization> and <doc:PhotosAndPrivacy> for
permission and privacy-manifest responsibilities.
