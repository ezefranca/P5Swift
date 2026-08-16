import Foundation
import ObjectiveC.runtime
import Photos
import Testing

@testable import P5

@Suite("P5 Photos library integration", .serialized)
struct P5PhotoLibraryTests {
    @Test("Authorization values map, serialize, and query native status without prompting")
    func authorizationValues() throws {
        #expect(P5PhotoLibraryAccess.addOnly.photosAccessLevel == .addOnly)
        #expect(P5PhotoLibraryAccess.readWrite.photosAccessLevel == .readWrite)

        let mappings: [(PHAuthorizationStatus, P5PhotoAuthorizationStatus)] = [
            (.notDetermined, .notDetermined),
            (.restricted, .restricted),
            (.denied, .denied),
            (.authorized, .authorized),
            (.limited, .limited),
            (Self.unknownNativeStatus(), .unknown),
        ]
        for (native, expected) in mappings {
            let status = P5PhotoAuthorizationStatus(native)
            #expect(status == expected)
            #expect(
                try JSONDecoder().decode(
                    P5PhotoAuthorizationStatus.self,
                    from: JSONEncoder().encode(status)
                ) == expected
            )
        }
        #expect(P5PhotoAuthorizationStatus.authorized.permitsSaving)
        #expect(P5PhotoAuthorizationStatus.limited.permitsSaving)
        #expect(P5PhotoAuthorizationStatus.denied.permitsSaving == false)

        for access in P5PhotoLibraryAccess.allCases {
            #expect(
                try JSONDecoder().decode(
                    P5PhotoLibraryAccess.self,
                    from: JSONEncoder().encode(access)
                ) == access
            )
        }

        _ = P5PhotoLibrary().authorizationStatus()
        _ = P5PhotoLibraryRuntime()
    }

    @Test("Authorization requests are explicit and cancellation-aware")
    func explicitAuthorization() async throws {
        let state = PhotoState()
        let library = Self.makeLibrary(state: state)

        state.requestedStatus = .limited
        #expect(try await library.requestAuthorization() == .limited)
        #expect(state.requestedLevels == [.addOnly])

        state.requestedStatus = .authorized
        #expect(try await library.requestAuthorization(for: .readWrite) == .authorized)
        #expect(state.requestedLevels == [.addOnly, .readWrite])

        let cancelledBefore = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await library.requestAuthorization()
        }
        await #expect(throws: CancellationError.self) {
            _ = try await cancelledBefore.value
        }

        state.cancelDuringRequest = true
        await #expect(throws: CancellationError.self) {
            _ = try await library.requestAuthorization()
        }
        state.cancelDuringRequest = false
    }

    @Test("Authorized image and movie saves create deterministic Photos changes")
    func saves() async throws {
        let state = PhotoState()
        let library = Self.makeLibrary(state: state)
        let image = try Self.sampleImage()

        state.status = .authorized
        state.photoIdentifier = "photo-1"
        #expect(try await library.save(image) == "photo-1")
        let png = try #require(state.photoData)
        #expect(try P5Image.decode(png).pixelWidth == 2)
        #expect(state.requestedLevels.isEmpty)

        state.status = .limited
        state.photoIdentifier = "photo-2"
        #expect(try await library.save(image, as: .jpeg, quality: 0.75) == "photo-2")
        #expect(try P5Image.decode(try #require(state.photoData)).pixelHeight == 1)

        let movie = FileManager.default.temporaryDirectory.appendingPathComponent(
            "P5Photos-\(UUID().uuidString).mov"
        )
        try Data([1, 2, 3]).write(to: movie)
        defer { try? FileManager.default.removeItem(at: movie) }
        state.videoIdentifier = "video-1"
        #expect(try await library.saveVideo(at: movie) == "video-1")
        #expect(state.videoURL == movie)
        #expect(state.changeCount == 3)
    }

    @Test("Saving never prompts and rejects unavailable access and invalid movies")
    func saveValidation() async throws {
        let state = PhotoState()
        let library = Self.makeLibrary(state: state)
        let image = try Self.sampleImage()

        state.status = .notDetermined
        await #expect(throws: P5PhotoLibraryError.authorizationNotDetermined) {
            _ = try await library.save(image)
        }
        for status in [
            PHAuthorizationStatus.restricted,
            .denied,
            Self.unknownNativeStatus(),
        ] {
            state.status = status
            let expected = P5PhotoAuthorizationStatus(status)
            await #expect(throws: P5PhotoLibraryError.accessUnavailable(expected)) {
                _ = try await library.save(image)
            }
        }
        #expect(state.requestedLevels.isEmpty)
        #expect(state.changeCount == 0)

        state.status = .authorized
        await #expect(throws: P5PhotoLibraryError.videoIsNotFileURL) {
            _ = try await library.saveVideo(at: URL(string: "https://example.com/movie.mov")!)
        }
        state.fileExists = false
        await #expect(throws: P5PhotoLibraryError.videoDoesNotExist) {
            _ = try await library.saveVideo(at: URL(fileURLWithPath: "/missing.mov"))
        }
        state.fileExists = true
        state.fileIsDirectory = true
        await #expect(throws: P5PhotoLibraryError.videoDoesNotExist) {
            _ = try await library.saveVideo(at: URL(fileURLWithPath: "/directory"))
        }

        state.fileIsDirectory = false
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await library.saveVideo(at: URL(fileURLWithPath: "/movie.mov"))
        }
        await #expect(throws: CancellationError.self) {
            _ = try await cancelled.value
        }
    }

    @Test("Photos change failures preserve deterministic typed diagnostics")
    func changeFailures() async throws {
        let state = PhotoState()
        state.status = .authorized
        let library = Self.makeLibrary(state: state)
        let image = try Self.sampleImage()

        state.changeError = TestFailure.message
        await #expect(
            throws: P5PhotoLibraryError.changeFailed(TestFailure.message.localizedDescription)
        ) {
            _ = try await library.save(image)
        }

        state.changeError = nil
        state.changeSucceeds = false
        await #expect(
            throws: P5PhotoLibraryError.changeFailed(
                "The system reported an unsuccessful change."
            )
        ) {
            _ = try await library.save(image)
        }

        state.changeSucceeds = true
        state.photoIdentifier = nil
        await #expect(throws: P5PhotoLibraryError.missingAssetIdentifier) {
            _ = try await library.save(image)
        }

        let errors: [P5PhotoLibraryError] = [
            .authorizationNotDetermined,
            .accessUnavailable(.restricted),
            .videoIsNotFileURL,
            .videoDoesNotExist,
            .missingAssetIdentifier,
            .changeFailed("reason"),
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }

    @Test("Native asset preparation is expressed through independently testable adapters")
    func assetPreparation() throws {
        final class Asset {
            let identifier: String
            var data: Data?
            var url: URL?
            var resourceType: PHAssetResourceType?

            init(identifier: String) {
                self.identifier = identifier
            }
        }

        let property = p5Property(\Asset.identifier)
        #expect(property(Asset(identifier: "property")) == "property")

        let dataPreparation = p5PhotoDataPreparation(
            resourceType: .photo,
            makeAsset: { Asset(identifier: "photo") },
            addResource: { asset in
                { resourceType, data, options in
                    #expect(options == nil)
                    asset.resourceType = resourceType
                    asset.data = data
                }
            },
            identifier: property
        )
        #expect(dataPreparation(Data([4, 5])) == "photo")

        var preparedAsset: Asset?
        let filePreparation = p5PhotoFilePreparation(
            resourceType: .video,
            makeAsset: {
                let asset = Asset(identifier: "video")
                preparedAsset = asset
                return asset
            },
            addResource: { asset in
                { resourceType, url, options in
                    #expect(options == nil)
                    asset.resourceType = resourceType
                    asset.url = url
                }
            },
            identifier: property
        )
        let url = URL(fileURLWithPath: "/movie.mov")
        #expect(filePreparation(url) == "video")
        #expect(preparedAsset?.resourceType == .video)
        #expect(preparedAsset?.url == url)
    }

    @Test("System Photos function bindings call the expected Objective-C entry points")
    func systemBindings() throws {
        let stubs = try NativePhotosStubs()
        defer { stubs.restore() }
        let state = PhotoState()
        let runtime = P5PhotoLibraryRuntime()

        runtime.requestAuthorization(.addOnly) { status in
            state.requestedStatus = status
        }
        #expect(state.requestedStatus == .limited)
        #expect(runtime.preparePhoto(Data([1, 2])) == nil)
        #expect(runtime.prepareVideo(URL(fileURLWithPath: "/movie.mov")) == nil)

        var isDirectory = ObjCBool(false)
        #expect(runtime.fileExists(#filePath, &isDirectory))
        #expect(isDirectory.boolValue == false)
    }

    @Test("Invalid Photos image quality terminates at the public boundary")
    func invalidQuality() async {
        await #expect(processExitsWith: .failure) {
            let state = PhotoState()
            state.status = .authorized
            _ = try! await Self.makeLibrary(state: state).save(
                try! Self.sampleImage(),
                quality: .nan
            )
        }
        await #expect(processExitsWith: .failure) {
            let state = PhotoState()
            state.status = .authorized
            _ = try! await Self.makeLibrary(state: state).save(
                try! Self.sampleImage(),
                quality: 1.1
            )
        }
    }

    private static func makeLibrary(state: PhotoState) -> P5PhotoLibrary {
        P5PhotoLibrary(
            runtime: P5PhotoLibraryRuntime(
                authorizationStatus: { _ in state.status },
                requestAuthorization: { access, callback in
                    state.requestedLevels.append(access)
                    if state.cancelDuringRequest {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                    callback(state.requestedStatus)
                },
                performChanges: { changes, completion in
                    state.changeCount += 1
                    changes()
                    completion?(state.changeSucceeds, state.changeError)
                },
                preparePhoto: { data in
                    state.photoData = data
                    return state.photoIdentifier
                },
                prepareVideo: { url in
                    state.videoURL = url
                    return state.videoIdentifier
                },
                fileExists: { _, isDirectory in
                    isDirectory?.pointee = ObjCBool(state.fileIsDirectory)
                    return state.fileExists
                }
            )
        )
    }

    private static func sampleImage() throws -> P5Image {
        try P5Image(
            pixelBuffer: P5PixelBuffer(
                width: 2,
                height: 1,
                bytes: [255, 0, 0, 255, 0, 255, 0, 255]
            )
        )
    }

    private static func unknownNativeStatus() -> PHAuthorizationStatus {
        precondition(MemoryLayout<PHAuthorizationStatus>.size == MemoryLayout<Int>.size)
        return unsafeBitCast(99, to: PHAuthorizationStatus.self)
    }
}

private final class PhotoState: @unchecked Sendable {
    var status = PHAuthorizationStatus.notDetermined
    var requestedStatus = PHAuthorizationStatus.authorized
    var requestedLevels: [PHAccessLevel] = []
    var cancelDuringRequest = false
    var changeSucceeds = true
    var changeError: (any Error)?
    var changeCount = 0
    var photoIdentifier: String? = "photo"
    var videoIdentifier: String? = "video"
    var photoData: Data?
    var videoURL: URL?
    var fileExists = true
    var fileIsDirectory = false
}

private enum TestFailure: LocalizedError {
    case message

    var errorDescription: String? { "test failure" }
}

private final class NativePhotosStubs {
    private typealias AuthorizationHandler = @convention(block) (PHAuthorizationStatus) -> Void
    private struct Replacement {
        let method: Method
        let original: IMP
        let replacement: IMP
    }

    private let asset: PHAssetCreationRequest
    private var replacements: [Replacement] = []

    init() throws {
        asset = try #require(
            class_createInstance(PHAssetCreationRequest.self, 0)
                as? PHAssetCreationRequest
        )

        let requestAuthorization:
            @convention(block) (AnyObject, PHAccessLevel, @escaping AuthorizationHandler) -> Void =
                { _, _, handler in handler(.limited) }
        try replaceClassMethod(
            PHPhotoLibrary.self,
            #selector(PHPhotoLibrary.requestAuthorization(for:handler:)),
            with: requestAuthorization
        )

        let createdAsset: @convention(block) (AnyObject) -> PHAssetCreationRequest =
            { [asset] _ in asset }
        try replaceClassMethod(
            PHAssetCreationRequest.self,
            #selector(PHAssetCreationRequest.forAsset),
            with: createdAsset
        )

        let addData:
            @convention(block) (
                AnyObject,
                PHAssetResourceType,
                NSData,
                PHAssetResourceCreationOptions?
            ) -> Void = { _, _, _, _ in }
        try replaceInstanceMethod(
            PHAssetCreationRequest.self,
            #selector(PHAssetCreationRequest.addResource(with:data:options:)),
            with: addData
        )

        let addFile:
            @convention(block) (
                AnyObject,
                PHAssetResourceType,
                NSURL,
                PHAssetResourceCreationOptions?
            ) -> Void = { _, _, _, _ in }
        try replaceInstanceMethod(
            PHAssetCreationRequest.self,
            #selector(PHAssetCreationRequest.addResource(with:fileURL:options:)),
            with: addFile
        )

        let placeholder: @convention(block) (AnyObject) -> PHObjectPlaceholder? = { _ in nil }
        try replaceInstanceMethod(
            PHAssetCreationRequest.self,
            #selector(getter: PHAssetCreationRequest.placeholderForCreatedAsset),
            with: placeholder
        )
    }

    func restore() {
        for replacement in replacements.reversed() {
            method_setImplementation(replacement.method, replacement.original)
            imp_removeBlock(replacement.replacement)
        }
        replacements.removeAll()
    }

    private func replaceClassMethod(
        _ type: AnyClass,
        _ selector: Selector,
        with block: Any
    ) throws {
        let method = try #require(class_getClassMethod(type, selector))
        replace(method, with: block)
    }

    private func replaceInstanceMethod(
        _ type: AnyClass,
        _ selector: Selector,
        with block: Any
    ) throws {
        let method = try #require(class_getInstanceMethod(type, selector))
        replace(method, with: block)
    }

    private func replace(_ method: Method, with block: Any) {
        let replacement = imp_implementationWithBlock(block)
        let original = method_setImplementation(method, replacement)
        replacements.append(
            Replacement(method: method, original: original, replacement: replacement)
        )
    }
}
