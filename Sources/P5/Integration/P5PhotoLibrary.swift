import Foundation
import Photos

/// The level of Photos access requested explicitly by an application.
public enum P5PhotoLibraryAccess: String, Sendable, Hashable, Codable, CaseIterable {
    /// Permission to add new assets without reading the user's library.
    case addOnly
    /// Permission to read the user's selected or complete library and add assets.
    case readWrite

    var photosAccessLevel: PHAccessLevel {
        switch self {
        case .addOnly: .addOnly
        case .readWrite: .readWrite
        }
    }
}

/// A stable, serializable representation of native Photos authorization.
public enum P5PhotoAuthorizationStatus: String, Sendable, Hashable, Codable, CaseIterable {
    /// The application has not asked the user for this access level.
    case notDetermined
    /// System policy prevents the application from receiving access.
    case restricted
    /// The user denied access.
    case denied
    /// The user granted access to the complete library for this access level.
    case authorized
    /// The user granted access to selected assets while retaining add access.
    case limited
    /// A newer Photos status is not understood by this version of P5.
    case unknown

    init(_ status: PHAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .restricted: self = .restricted
        case .denied: self = .denied
        case .authorized: self = .authorized
        case .limited: self = .limited
        @unknown default: self = .unknown
        }
    }

    var permitsSaving: Bool {
        self == .authorized || self == .limited
    }
}

/// Failures produced by permission-aware Photos library operations.
public enum P5PhotoLibraryError: Error, Sendable, Hashable, LocalizedError {
    /// Access has not been requested; saving never triggers a permission prompt.
    case authorizationNotDetermined
    /// System policy or the user's decision prevents saving.
    case accessUnavailable(P5PhotoAuthorizationStatus)
    /// A movie resource is not represented by a local file URL.
    case videoIsNotFileURL
    /// The local movie resource does not exist or is a directory.
    case videoDoesNotExist
    /// Photos completed a change without returning the created asset identifier.
    case missingAssetIdentifier
    /// Photos rejected or failed the requested library change.
    case changeFailed(String)

    /// A localized description suitable for diagnostics and user interfaces.
    public var errorDescription: String? {
        switch self {
        case .authorizationNotDetermined:
            "Photos access has not been requested. Request it from a user-initiated action first."
        case .accessUnavailable(let status):
            "Photos access is unavailable with authorization status '\(status.rawValue)'."
        case .videoIsNotFileURL:
            "Saving a video to Photos requires a local file URL."
        case .videoDoesNotExist:
            "The video selected for Photos does not exist as a regular file."
        case .missingAssetIdentifier:
            "Photos saved the change without returning an asset identifier."
        case .changeFailed(let reason):
            "Photos could not save the asset: \(reason)"
        }
    }
}

/// Explicit authorization and asset-saving integration for the native Photos library.
///
/// Querying status and saving never present a permission prompt. Call
/// ``requestAuthorization(for:)`` only in response to a clear user action, then
/// call one of the save methods if the returned status permits it.
public struct P5PhotoLibrary: @unchecked Sendable {
    private let runtime: P5PhotoLibraryRuntime

    /// Creates a Photos library integration backed by the system photo library.
    public init() {
        runtime = P5PhotoLibraryRuntime()
    }

    init(runtime: P5PhotoLibraryRuntime) {
        self.runtime = runtime
    }

    /// Returns current native authorization without asking the user for access.
    public func authorizationStatus(
        for access: P5PhotoLibraryAccess = .addOnly
    ) -> P5PhotoAuthorizationStatus {
        P5PhotoAuthorizationStatus(runtime.authorizationStatus(access.photosAccessLevel))
    }

    /// Explicitly asks the user for a Photos access level.
    ///
    /// The host application must provide the corresponding Photos purpose string.
    /// Cancellation is observed before the request and after the system responds;
    /// an authorization sheet already owned by the system cannot be withdrawn.
    public func requestAuthorization(
        for access: P5PhotoLibraryAccess = .addOnly
    ) async throws -> P5PhotoAuthorizationStatus {
        try Task.checkCancellation()
        let status = await withCheckedContinuation { continuation in
            runtime.requestAuthorization(access.photosAccessLevel) { status in
                continuation.resume(returning: status)
            }
        }
        try Task.checkCancellation()
        return P5PhotoAuthorizationStatus(status)
    }

    /// Encodes and saves an image, returning its Photos local identifier.
    ///
    /// This operation does not request authorization implicitly. PNG preserves
    /// alpha, while JPEG and HEIF use `quality` for lossy encoding.
    public func save(
        _ image: P5Image,
        as format: P5ImageFormat = .png,
        quality: Double = 0.9
    ) async throws -> String {
        precondition(quality.isFinite && (0...1).contains(quality))
        try requireSaveAuthorization()
        try Task.checkCancellation()
        let data = try image.encoded(as: format, quality: quality)
        return try await saveChange { runtime.preparePhoto(data) }
    }

    /// Saves an existing local movie, returning its Photos local identifier.
    ///
    /// This operation does not request authorization implicitly and never removes
    /// or modifies the source movie.
    public func saveVideo(at url: URL) async throws -> String {
        try requireSaveAuthorization()
        guard url.isFileURL else {
            throw P5PhotoLibraryError.videoIsNotFileURL
        }
        var isDirectory: ObjCBool = false
        guard
            runtime.fileExists(url.path, &isDirectory),
            isDirectory.boolValue == false
        else {
            throw P5PhotoLibraryError.videoDoesNotExist
        }
        try Task.checkCancellation()
        return try await saveChange { runtime.prepareVideo(url) }
    }

    private func requireSaveAuthorization() throws {
        let status = authorizationStatus(for: .addOnly)
        guard status != .notDetermined else {
            throw P5PhotoLibraryError.authorizationNotDetermined
        }
        guard status.permitsSaving else {
            throw P5PhotoLibraryError.accessUnavailable(status)
        }
    }

    private func saveChange(
        _ prepare: @escaping @Sendable () -> String?
    ) async throws -> String {
        let result = P5PhotoChangeResult()
        return try await withCheckedThrowingContinuation { continuation in
            runtime.performChanges(
                {
                    result.setIdentifier(prepare())
                },
                { success, error in
                    if let error {
                        continuation.resume(
                            throwing: P5PhotoLibraryError.changeFailed(error.localizedDescription)
                        )
                    } else if success == false {
                        continuation.resume(
                            throwing: P5PhotoLibraryError.changeFailed(
                                "The system reported an unsuccessful change."
                            )
                        )
                    } else if let identifier = result.identifier() {
                        continuation.resume(returning: identifier)
                    } else {
                        continuation.resume(throwing: P5PhotoLibraryError.missingAssetIdentifier)
                    }
                }
            )
        }
    }
}

private final class P5PhotoChangeResult: @unchecked Sendable {
    private let lock = NSLock()
    private var storedIdentifier: String?

    func setIdentifier(_ identifier: String?) {
        lock.lock()
        storedIdentifier = identifier
        lock.unlock()
    }

    func identifier() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storedIdentifier
    }
}

struct P5PhotoLibraryRuntime: @unchecked Sendable {
    var authorizationStatus: (PHAccessLevel) -> PHAuthorizationStatus
    var requestAuthorization:
        (PHAccessLevel, @escaping @Sendable (PHAuthorizationStatus) -> Void) -> Void
    var performChanges:
        (@escaping @Sendable () -> Void, (@Sendable (Bool, (any Error)?) -> Void)?) -> Void
    var preparePhoto: (Data) -> String?
    var prepareVideo: (URL) -> String?
    var fileExists: (String, UnsafeMutablePointer<ObjCBool>?) -> Bool

    init() {
        let library = PHPhotoLibrary.shared()
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for:)
        requestAuthorization = PHPhotoLibrary.requestAuthorization(for:handler:)
        performChanges = library.performChanges(_:completionHandler:)
        preparePhoto = p5PhotoDataPreparation(
            resourceType: .photo,
            makeAsset: PHAssetCreationRequest.forAsset,
            addResource: PHAssetCreationRequest.addResource(with:data:options:),
            identifier: p5Property(
                \PHAssetCreationRequest.placeholderForCreatedAsset?.localIdentifier)
        )
        prepareVideo = p5PhotoFilePreparation(
            resourceType: .video,
            makeAsset: PHAssetCreationRequest.forAsset,
            addResource: PHAssetCreationRequest.addResource(with:fileURL:options:),
            identifier: p5Property(
                \PHAssetCreationRequest.placeholderForCreatedAsset?.localIdentifier)
        )
        fileExists = FileManager.default.fileExists(atPath:isDirectory:)
    }

    init(
        authorizationStatus: @escaping (PHAccessLevel) -> PHAuthorizationStatus,
        requestAuthorization:
            @escaping (
                PHAccessLevel,
                @escaping @Sendable (PHAuthorizationStatus) -> Void
            ) -> Void,
        performChanges:
            @escaping (
                @escaping @Sendable () -> Void,
                (@Sendable (Bool, (any Error)?) -> Void)?
            ) -> Void,
        preparePhoto: @escaping (Data) -> String?,
        prepareVideo: @escaping (URL) -> String?,
        fileExists: @escaping (String, UnsafeMutablePointer<ObjCBool>?) -> Bool
    ) {
        self.authorizationStatus = authorizationStatus
        self.requestAuthorization = requestAuthorization
        self.performChanges = performChanges
        self.preparePhoto = preparePhoto
        self.prepareVideo = prepareVideo
        self.fileExists = fileExists
    }
}

func p5Property<Root, Value>(_ keyPath: KeyPath<Root, Value>) -> (Root) -> Value {
    { root in root[keyPath: keyPath] }
}

func p5PhotoDataPreparation<Asset>(
    resourceType: PHAssetResourceType,
    makeAsset: @escaping () -> Asset,
    addResource:
        @escaping (
            Asset
        ) -> (PHAssetResourceType, Data, PHAssetResourceCreationOptions?) -> Void,
    identifier: @escaping (Asset) -> String?
) -> (Data) -> String? {
    { data in
        let asset = makeAsset()
        addResource(asset)(resourceType, data, nil)
        return identifier(asset)
    }
}

func p5PhotoFilePreparation<Asset>(
    resourceType: PHAssetResourceType,
    makeAsset: @escaping () -> Asset,
    addResource:
        @escaping (
            Asset
        ) -> (PHAssetResourceType, URL, PHAssetResourceCreationOptions?) -> Void,
    identifier: @escaping (Asset) -> String?
) -> (URL) -> String? {
    { url in
        let asset = makeAsset()
        addResource(asset)(resourceType, url, nil)
        return identifier(asset)
    }
}
