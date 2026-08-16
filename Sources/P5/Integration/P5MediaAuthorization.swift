import AVFoundation
import Foundation

/// A protected capture capability managed by AVFoundation.
public enum P5MediaCaptureKind: String, Sendable, Hashable, Codable, CaseIterable {
    /// Video input from a built-in or connected camera.
    case camera
    /// Audio input from a built-in or connected microphone.
    case microphone

    var mediaType: AVMediaType {
        switch self {
        case .camera: .video
        case .microphone: .audio
        }
    }
}

/// A stable, serializable representation of AVFoundation authorization.
public enum P5MediaAuthorizationStatus: String, Sendable, Hashable, Codable, CaseIterable {
    /// The application has not asked the user for this capture capability.
    case notDetermined
    /// System policy prevents the application from receiving access.
    case restricted
    /// The user denied access.
    case denied
    /// The user granted access.
    case authorized
    /// A newer AVFoundation status is not understood by this version of P5.
    case unknown

    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .restricted: self = .restricted
        case .denied: self = .denied
        case .authorized: self = .authorized
        @unknown default: self = .unknown
        }
    }
}

/// Failures produced when a protected capture capability is unavailable.
public enum P5MediaAuthorizationError: Error, Sendable, Hashable, LocalizedError {
    /// Access has not been requested; capture never triggers a permission prompt.
    case authorizationNotDetermined(P5MediaCaptureKind)
    /// System policy or the user's decision prevents capture.
    case accessUnavailable(P5MediaCaptureKind, P5MediaAuthorizationStatus)

    /// A localized description suitable for diagnostics and user interfaces.
    public var errorDescription: String? {
        switch self {
        case .authorizationNotDetermined(let kind):
            "\(kind.rawValue.capitalized) access has not been requested. Request it from a user-initiated action first."
        case .accessUnavailable(let kind, let status):
            "\(kind.rawValue.capitalized) access is unavailable with authorization status '\(status.rawValue)'."
        }
    }
}

/// Explicit camera and microphone authorization without implicit system prompts.
public struct P5MediaAuthorization: @unchecked Sendable {
    private let runtime: P5MediaAuthorizationRuntime

    /// Creates an authorization integration backed by AVFoundation.
    public init() {
        runtime = P5MediaAuthorizationRuntime()
    }

    init(runtime: P5MediaAuthorizationRuntime) {
        self.runtime = runtime
    }

    /// Returns current authorization without asking the user for access.
    public func status(for kind: P5MediaCaptureKind) -> P5MediaAuthorizationStatus {
        P5MediaAuthorizationStatus(runtime.status(kind.mediaType))
    }

    /// Explicitly asks the user for camera or microphone access.
    ///
    /// The host application must provide the matching purpose string. Cancellation
    /// is observed before and after the system-owned authorization interaction.
    public func requestAuthorization(
        for kind: P5MediaCaptureKind
    ) async throws -> P5MediaAuthorizationStatus {
        try Task.checkCancellation()
        let granted = await withCheckedContinuation { continuation in
            runtime.requestAccess(kind.mediaType) { granted in
                continuation.resume(returning: granted)
            }
        }
        try Task.checkCancellation()
        if granted {
            return .authorized
        }
        return status(for: kind)
    }

    /// Verifies that capture is already authorized without presenting a prompt.
    public func requireAuthorization(for kind: P5MediaCaptureKind) throws {
        let status = status(for: kind)
        guard status != .notDetermined else {
            throw P5MediaAuthorizationError.authorizationNotDetermined(kind)
        }
        guard status == .authorized else {
            throw P5MediaAuthorizationError.accessUnavailable(kind, status)
        }
    }
}

struct P5MediaAuthorizationRuntime: @unchecked Sendable {
    var status: (AVMediaType) -> AVAuthorizationStatus
    var requestAccess: (AVMediaType, @escaping @Sendable (Bool) -> Void) -> Void

    init() {
        status = AVCaptureDevice.authorizationStatus(for:)
        requestAccess = AVCaptureDevice.requestAccess(for:completionHandler:)
    }

    init(
        status: @escaping (AVMediaType) -> AVAuthorizationStatus,
        requestAccess: @escaping (AVMediaType, @escaping @Sendable (Bool) -> Void) -> Void
    ) {
        self.status = status
        self.requestAccess = requestAccess
    }
}
