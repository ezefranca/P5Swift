import AVFoundation
import Foundation
import ObjectiveC.runtime
import Testing

@testable import P5

@Suite("P5 media authorization", .serialized)
struct P5MediaAuthorizationTests {
    @Test("Capture kinds and authorization statuses map and serialize")
    func values() throws {
        #expect(P5MediaCaptureKind.camera.mediaType == .video)
        #expect(P5MediaCaptureKind.microphone.mediaType == .audio)

        let mappings: [(AVAuthorizationStatus, P5MediaAuthorizationStatus)] = [
            (.notDetermined, .notDetermined),
            (.restricted, .restricted),
            (.denied, .denied),
            (.authorized, .authorized),
            (Self.unknownNativeStatus(), .unknown),
        ]
        for (native, expected) in mappings {
            let status = P5MediaAuthorizationStatus(native)
            #expect(status == expected)
            #expect(
                try JSONDecoder().decode(
                    P5MediaAuthorizationStatus.self,
                    from: JSONEncoder().encode(status)
                ) == expected
            )
        }
        for kind in P5MediaCaptureKind.allCases {
            #expect(
                try JSONDecoder().decode(
                    P5MediaCaptureKind.self,
                    from: JSONEncoder().encode(kind)
                ) == kind
            )
        }

        _ = P5MediaAuthorization().status(for: .camera)
        _ = P5MediaAuthorizationRuntime()
    }

    @Test("Requests return granted and current denied statuses")
    func requests() async throws {
        let state = MediaAuthorizationState()
        let authorization = Self.authorization(state: state)

        state.granted = true
        #expect(try await authorization.requestAuthorization(for: .camera) == .authorized)
        #expect(state.requestedTypes == [.video])

        state.granted = false
        state.status = .denied
        #expect(try await authorization.requestAuthorization(for: .microphone) == .denied)
        #expect(state.requestedTypes == [.video, .audio])

        let cancelledBefore = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await authorization.requestAuthorization(for: .camera)
        }
        await #expect(throws: CancellationError.self) {
            _ = try await cancelledBefore.value
        }

        state.cancelDuringRequest = true
        await #expect(throws: CancellationError.self) {
            _ = try await authorization.requestAuthorization(for: .camera)
        }
    }

    @Test("Authorization requirements never prompt implicitly")
    func requirements() throws {
        let state = MediaAuthorizationState()
        let authorization = Self.authorization(state: state)

        state.status = .authorized
        try authorization.requireAuthorization(for: .camera)

        state.status = .notDetermined
        #expect(
            throws: P5MediaAuthorizationError.authorizationNotDetermined(.microphone)
        ) {
            try authorization.requireAuthorization(for: .microphone)
        }

        for status in [
            AVAuthorizationStatus.restricted,
            .denied,
            Self.unknownNativeStatus(),
        ] {
            state.status = status
            let expected = P5MediaAuthorizationStatus(status)
            #expect(
                throws: P5MediaAuthorizationError.accessUnavailable(.camera, expected)
            ) {
                try authorization.requireAuthorization(for: .camera)
            }
        }
        #expect(state.requestedTypes.isEmpty)

        let errors: [P5MediaAuthorizationError] = [
            .authorizationNotDetermined(.camera),
            .accessUnavailable(.microphone, .denied),
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }

    @Test("The system request binding calls AVFoundation's native entry point")
    func systemBinding() throws {
        let stub = try NativeMediaAuthorizationStub()
        defer { stub.restore() }
        let state = MediaAuthorizationState()
        let runtime = P5MediaAuthorizationRuntime()

        runtime.requestAccess(.video) { granted in
            state.granted = granted
        }
        #expect(state.granted)
    }

    private static func authorization(
        state: MediaAuthorizationState
    ) -> P5MediaAuthorization {
        P5MediaAuthorization(
            runtime: P5MediaAuthorizationRuntime(
                status: { _ in state.status },
                requestAccess: { mediaType, completion in
                    state.requestedTypes.append(mediaType)
                    if state.cancelDuringRequest {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                    completion(state.granted)
                }
            )
        )
    }

    private static func unknownNativeStatus() -> AVAuthorizationStatus {
        precondition(MemoryLayout<AVAuthorizationStatus>.size == MemoryLayout<Int>.size)
        return unsafeBitCast(99, to: AVAuthorizationStatus.self)
    }
}

private final class MediaAuthorizationState: @unchecked Sendable {
    var status = AVAuthorizationStatus.notDetermined
    var granted = false
    var requestedTypes: [AVMediaType] = []
    var cancelDuringRequest = false
}

private final class NativeMediaAuthorizationStub {
    private typealias Handler = @convention(block) (Bool) -> Void

    private let method: Method
    private let original: IMP
    private let replacement: IMP

    init() throws {
        method = try #require(
            class_getClassMethod(
                AVCaptureDevice.self,
                #selector(AVCaptureDevice.requestAccess(for:completionHandler:))
            )
        )
        let block: @convention(block) (AnyObject, AVMediaType, @escaping Handler) -> Void =
            { _, _, handler in handler(true) }
        replacement = imp_implementationWithBlock(block)
        original = method_setImplementation(method, replacement)
    }

    func restore() {
        method_setImplementation(method, original)
        imp_removeBlock(replacement)
    }
}
