import Foundation
import Testing

@testable import P5

@Suite("P5 native persistence", .serialized)
struct P5PersistenceTests {
    @Test("Storage keys are typed, path-safe, Codable values")
    func storageKeys() async throws {
        let names = ["a", "AZaz09._-", String(repeating: "a", count: 128)]
        for name in names {
            let key = P5StorageKey<String>(name)
            #expect(key.name == name)
            #expect(
                try JSONDecoder().decode(
                    P5StorageKey<String>.self,
                    from: JSONEncoder().encode(key)
                ) == key
            )
            #expect(Set([key, P5StorageKey<String>(name)]).count == 1)
        }

        let invalidNames = [
            "", ".", "..", " leading", "trailing ", "line\n", "path/name", "café",
            String(repeating: "a", count: 129),
        ]
        for name in invalidNames {
            let data = try JSONEncoder().encode(name)
            #expect(throws: DecodingError.self) {
                _ = try JSONDecoder().decode(P5StorageKey<String>.self, from: data)
            }
        }

        #if os(macOS)
            await #expect(processExitsWith: .failure) { _ = P5StorageKey<String>("") }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) { _ = P5StorageKey<String>(".") }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) { _ = P5StorageKey<String>("..") }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) { _ = P5StorageKey<String>(" bad") }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) { _ = P5StorageKey<String>("bad ") }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) { _ = P5StorageKey<String>("bad/name") }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) { _ = P5StorageKey<String>("café") }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5StorageKey<String>(String(repeating: "x", count: 129))
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5Preferences(namespace: "invalid namespace")
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5FileStore(directory: URL(string: "https://example.com/store")!)
            }
        #endif
    }

    @Test("Persistence envelopes are stable, versioned, and diagnostic")
    func coding() throws {
        let sample = PersistenceSample(name: "Ada/Grace", count: 3)
        let first = try P5PersistenceCoding.encode(sample)
        let second = try P5PersistenceCoding.encode(sample)
        #expect(first == second)
        #expect(String(decoding: first, as: UTF8.self).contains("Ada/Grace"))
        #expect(try P5PersistenceCoding.decode(PersistenceSample.self, from: first) == sample)

        #expect(throws: P5PersistenceError.encodingFailed("failed")) {
            _ = try P5PersistenceCoding.encode(FailingPersistenceValue())
        }
        #expect(throws: P5PersistenceError.decodingFailed("failed")) {
            _ = try P5PersistenceCoding.decode(
                FailingPersistenceValue.self,
                from: Data(#"{"formatVersion":1,"value":{}}"#.utf8)
            )
        }
        #expect(throws: P5PersistenceError.unsupportedFormatVersion(2)) {
            _ = try P5PersistenceCoding.decode(
                PersistenceSample.self,
                from: Data(#"{"formatVersion":2,"value":{"count":3,"name":"Ada"}}"#.utf8)
            )
        }
        #expect(throws: P5PersistenceError.self) {
            _ = try P5PersistenceCoding.decode(PersistenceSample.self, from: Data("bad".utf8))
        }

        let errors: [P5PersistenceError] = [
            .encodingFailed("encode"),
            .decodingFailed("decode"),
            .unsupportedFormatVersion(9),
            .fileReadFailed("read"),
            .fileWriteFailed("write"),
            .fileRemovalFailed("remove"),
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }

    @Test("Preferences namespace Codable values and reject incompatible objects")
    func preferences() throws {
        let suiteName = "P5PersistenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        let preferences = P5Preferences(userDefaults: defaults, namespace: "sketch.one")
        let key = P5StorageKey<PersistenceSample>("settings")
        #expect(preferences.namespace == "sketch.one")
        #expect(preferences.contains(key) == false)
        #expect(try preferences.value(for: key) == nil)

        let sample = PersistenceSample(name: "Ada", count: 3)
        try preferences.set(sample, for: key)
        #expect(preferences.contains(key))
        #expect(try preferences.value(for: key) == sample)
        #expect(defaults.data(forKey: "sketch.one.settings") != nil)

        preferences.removeValue(for: key)
        #expect(preferences.contains(key) == false)
        preferences.removeValue(for: key)

        defaults.set("foreign", forKey: "sketch.one.settings")
        #expect(throws: P5PersistenceError.self) { _ = try preferences.value(for: key) }
        defaults.set(Data("bad".utf8), forKey: "sketch.one.settings")
        #expect(throws: P5PersistenceError.self) { _ = try preferences.value(for: key) }

        defaults.set(
            Data(#"{"formatVersion":2,"value":{"count":3,"name":"Ada"}}"#.utf8),
            forKey: "sketch.one.settings"
        )
        #expect(throws: P5PersistenceError.unsupportedFormatVersion(2)) {
            _ = try preferences.value(for: key)
        }
    }

    @Test("Preferences runtime receives only physical namespaced keys")
    func preferencesRuntime() throws {
        let state = PreferencesState()
        let runtime = P5PreferencesRuntime(
            object: { key in
                state.receivedKeys.append(key)
                return state.object
            },
            data: { key in
                state.receivedKeys.append(key)
                return state.data
            },
            set: { data, key in
                state.receivedKeys.append(key)
                state.object = data
                state.data = data
            },
            remove: { key in
                state.receivedKeys.append(key)
                state.object = nil
                state.data = nil
            }
        )
        let preferences = P5Preferences(namespace: "drawing", runtime: runtime)
        let key = P5StorageKey<Int>("frame-count")

        #expect(preferences.contains(key) == false)
        #expect(try preferences.value(for: key) == nil)
        try preferences.set(42, for: key)
        #expect(preferences.contains(key))
        #expect(try preferences.value(for: key) == 42)
        preferences.removeValue(for: key)
        #expect(state.receivedKeys.allSatisfy { $0 == "drawing.frame-count" })

        let callsBeforeFailure = state.receivedKeys.count
        #expect(throws: P5PersistenceError.self) {
            try P5Preferences(namespace: "drawing", runtime: runtime).set(
                FailingPersistenceValue(),
                for: P5StorageKey<FailingPersistenceValue>("failed")
            )
        }
        #expect(state.receivedKeys.count == callsBeforeFailure)
    }

    @Test("File store persists atomic JSON files with replace and absent semantics")
    func nativeFileStore() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "P5FileStore-\(UUID().uuidString)",
            isDirectory: true
        )
        let directory = parent.appendingPathComponent("nested/store", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let store = P5FileStore(directory: directory)
        let key = P5StorageKey<PersistenceSample>("settings")
        #expect(store.directory == directory.standardizedFileURL)
        #expect(try await store.contains(key) == false)
        #expect(try await store.value(for: key) == nil)
        try await store.removeValue(for: key)

        try await store.save(PersistenceSample(name: "first", count: 1), for: key)
        #expect(try await store.contains(key))
        #expect(try await store.value(for: key) == PersistenceSample(name: "first", count: 1))

        let fileURL = await store.fileURL(for: key)
        #expect(fileURL.lastPathComponent == "settings.json")
        #expect(try Data(contentsOf: fileURL).isEmpty == false)

        try await store.save(PersistenceSample(name: "second", count: 2), for: key)
        #expect(try await store.value(for: key) == PersistenceSample(name: "second", count: 2))
        try await store.removeValue(for: key)
        #expect(try await store.contains(key) == false)
    }

    @Test("File store translates native operation failures")
    func fileFailures() async throws {
        let directory = FileManager.default.temporaryDirectory
        let key = P5StorageKey<Int>("value")

        var runtime = P5FileStoreRuntime()
        runtime.contains = { _ in throw PersistenceStubError.failed }
        let containsStore = P5FileStore(directory: directory, runtime: runtime)
        await #expect(throws: P5PersistenceError.fileReadFailed("failed")) {
            _ = try await containsStore.contains(key)
        }

        runtime = P5FileStoreRuntime()
        runtime.read = { _ in throw PersistenceStubError.failed }
        let readStore = P5FileStore(directory: directory, runtime: runtime)
        await #expect(throws: P5PersistenceError.fileReadFailed("failed")) {
            _ = try await readStore.value(for: key)
        }

        runtime = P5FileStoreRuntime()
        runtime.createDirectory = { _ in throw PersistenceStubError.failed }
        let directoryStore = P5FileStore(directory: directory, runtime: runtime)
        await #expect(throws: P5PersistenceError.fileWriteFailed("failed")) {
            try await directoryStore.save(1, for: key)
        }

        runtime = P5FileStoreRuntime()
        runtime.write = { _, _ in throw PersistenceStubError.failed }
        let writeStore = P5FileStore(directory: directory, runtime: runtime)
        await #expect(throws: P5PersistenceError.fileWriteFailed("failed")) {
            try await writeStore.save(1, for: key)
        }

        runtime = P5FileStoreRuntime()
        runtime.remove = { _ in throw PersistenceStubError.failed }
        let removeStore = P5FileStore(directory: directory, runtime: runtime)
        await #expect(throws: P5PersistenceError.fileRemovalFailed("failed")) {
            try await removeStore.removeValue(for: key)
        }

        await #expect(throws: P5PersistenceError.self) {
            try await writeStore.save(
                FailingPersistenceValue(),
                for: P5StorageKey<FailingPersistenceValue>("failed")
            )
        }
    }

    @Test("File store preserves cancellation before and after native operations")
    func fileCancellation() async throws {
        let directory = FileManager.default.temporaryDirectory
        let key = P5StorageKey<Int>("value")

        let cancelledContains = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await P5FileStore(directory: directory).contains(key)
        }
        await #expect(throws: CancellationError.self) { _ = try await cancelledContains.value }

        let cancelledSave = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await P5FileStore(directory: directory).save(1, for: key)
        }
        await #expect(throws: CancellationError.self) { try await cancelledSave.value }

        let cancelledRead = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await P5FileStore(directory: directory).value(for: key)
        }
        await #expect(throws: CancellationError.self) { _ = try await cancelledRead.value }

        let cancelledRemove = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await P5FileStore(directory: directory).removeValue(for: key)
        }
        await #expect(throws: CancellationError.self) { try await cancelledRemove.value }

        var runtime = P5FileStoreRuntime()
        runtime.contains = { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return true
        }
        let containsStore = P5FileStore(directory: directory, runtime: runtime)
        let containsAfterOperation = Task { try await containsStore.contains(key) }
        await #expect(throws: CancellationError.self) {
            _ = try await containsAfterOperation.value
        }

        runtime = P5FileStoreRuntime()
        runtime.createDirectory = { _ in withUnsafeCurrentTask { $0?.cancel() } }
        let createStore = P5FileStore(directory: directory, runtime: runtime)
        let createAfterOperation = Task { try await createStore.save(1, for: key) }
        await #expect(throws: CancellationError.self) { try await createAfterOperation.value }

        runtime = P5FileStoreRuntime()
        runtime.write = { _, _ in withUnsafeCurrentTask { $0?.cancel() } }
        let writeStore = P5FileStore(directory: directory, runtime: runtime)
        let writeAfterOperation = Task { try await writeStore.save(1, for: key) }
        await #expect(throws: CancellationError.self) { try await writeAfterOperation.value }

        runtime = P5FileStoreRuntime()
        runtime.read = { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return Data(#"{"formatVersion":1,"value":1}"#.utf8)
        }
        let readStore = P5FileStore(directory: directory, runtime: runtime)
        let readAfterOperation = Task { try await readStore.value(for: key) }
        await #expect(throws: CancellationError.self) { _ = try await readAfterOperation.value }

        runtime = P5FileStoreRuntime()
        runtime.remove = { _ in withUnsafeCurrentTask { $0?.cancel() } }
        let removeStore = P5FileStore(directory: directory, runtime: runtime)
        let removeAfterOperation = Task { try await removeStore.removeValue(for: key) }
        await #expect(throws: CancellationError.self) {
            try await removeAfterOperation.value
        }
    }
}

private struct PersistenceSample: Codable, Equatable, Sendable {
    let name: String
    let count: Int
}

private struct FailingPersistenceValue: Codable, Sendable {
    init() {}

    init(from decoder: any Decoder) throws {
        throw PersistenceStubError.failed
    }

    func encode(to encoder: any Encoder) throws {
        throw PersistenceStubError.failed
    }
}

private enum PersistenceStubError: Error, LocalizedError {
    case failed

    var errorDescription: String? { "failed" }
}

private final class PreferencesState: @unchecked Sendable {
    var object: Any?
    var data: Data?
    var receivedKeys: [String] = []
}
