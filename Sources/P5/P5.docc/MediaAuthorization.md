# Camera and Microphone Authorization

Ask for protected capture access explicitly and keep system prompts tied to user intent.

## Separate status, request, and use

``P5MediaAuthorization`` never presents a prompt while checking or requiring access. Use
``P5MediaAuthorization/requestAuthorization(for:)`` only after a visible user action:

```swift
let authorization = P5MediaAuthorization()
let camera = try await authorization.requestAuthorization(for: .camera)

guard camera == .authorized else {
    return
}

try authorization.requireAuthorization(for: .camera)
```

If access is still undetermined, `requireAuthorization(for:)` throws
``P5MediaAuthorizationError/authorizationNotDetermined(_:)``. Restricted, denied, and
unknown future states produce
``P5MediaAuthorizationError/accessUnavailable(_:_:)``. This separation prevents a sketch,
preview, or background lifecycle event from surprising the user with a permission sheet.

## Declare truthful purpose strings

The host application must include `NSCameraUsageDescription` before requesting camera access
and `NSMicrophoneUsageDescription` before requesting microphone access. Swift packages cannot
provide application-specific purpose text. Missing purpose strings can terminate the host
application when it requests protected resources.

An application should request only the resource needed for the feature the user selected.
For example, a silent camera preview does not need microphone permission. Authorization can
change outside the application, so verify it again before starting a new capture session.

The system owns an authorization sheet after it is presented and does not expose a cancellation
operation. The async request observes task cancellation before presenting the sheet and after
AVFoundation returns.
