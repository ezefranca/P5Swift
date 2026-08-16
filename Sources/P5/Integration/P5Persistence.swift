import Foundation

/// Failures produced by preferences and file-backed persistence.
public enum P5PersistenceError: Error, Sendable, Hashable, LocalizedError {
    /// A Codable value could not be encoded into the stable storage envelope.
    case encodingFailed(String)
    /// Stored bytes are missing their envelope or cannot decode the requested type.
    case decodingFailed(String)
    /// Stored data uses a newer or otherwise unsupported envelope version.
    case unsupportedFormatVersion(Int)
    /// A file could not be read.
    case fileReadFailed(String)
    /// A directory or atomic file write could not be completed.
    case fileWriteFailed(String)
    /// A persisted file could not be removed.
    case fileRemovalFailed(String)

    /// A localized description suitable for diagnostics and user interfaces.
    public var errorDescription: String? {
        switch self {
        case .encodingFailed(let reason):
            "The value could not be encoded for persistence: \(reason)"
        case .decodingFailed(let reason):
            "The stored value could not be decoded: \(reason)"
        case .unsupportedFormatVersion(let version):
            "The stored value uses unsupported format version \(version)."
        case .fileReadFailed(let reason):
            "The persisted file could not be read: \(reason)"
        case .fileWriteFailed(let reason):
            "The persisted file could not be written: \(reason)"
        case .fileRemovalFailed(let reason):
            "The persisted file could not be removed: \(reason)"
        }
    }
}

/// A path-safe, strongly typed key shared by P5 persistence stores.
public struct P5StorageKey<Value: Codable & Sendable>: Sendable, Hashable, Codable {
    /// Stable ASCII name used in UserDefaults and as a file name stem.
    public let name: String

    /// Creates a key containing 1 through 128 ASCII letters, numbers, dots, hyphens, or
    /// underscores.
    ///
    /// - Precondition: The name is path-safe, is not `.` or `..`, and has no surrounding
    ///   whitespace.
    public init(_ name: String) {
        precondition(Self.isValid(name))
        self.name = name
    }

    /// Decodes a key while preserving its path-safety invariant.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let name = try container.decode(String.self)
        guard Self.isValid(name) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid P5 storage key."
            )
        }
        self.name = name
    }

    /// Encodes the stable key name as one string value.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }

    static func isValid(_ name: String) -> Bool {
        guard
            name.isEmpty == false,
            name.utf8.count <= 128,
            name != ".",
            name != "..",
            name == name.trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return false
        }
        return name.utf8.allSatisfy { byte in
            byte.isASCIILetter || byte.isASCIIDigit || byte == 45 || byte == 46 || byte == 95
        }
    }
}

/// Thread-safe, namespaced Codable values stored in UserDefaults.
public struct P5Preferences: @unchecked Sendable {
    /// Namespace prepended to every physical UserDefaults key.
    public let namespace: String
    private let runtime: P5PreferencesRuntime

    /// Creates a preferences store without reading or writing a value.
    ///
    /// - Precondition: `namespace` satisfies the same path-safe rules as ``P5StorageKey``.
    public init(userDefaults: UserDefaults = .standard, namespace: String = "P5") {
        precondition(P5StorageKey<Bool>.isValid(namespace))
        self.namespace = namespace
        runtime = P5PreferencesRuntime(userDefaults: userDefaults)
    }

    init(namespace: String, runtime: P5PreferencesRuntime) {
        precondition(P5StorageKey<Bool>.isValid(namespace))
        self.namespace = namespace
        self.runtime = runtime
    }

    /// Whether a stored object exists for the typed key.
    public func contains<Value>(_ key: P5StorageKey<Value>) -> Bool {
        runtime.object(physicalKey(key)) != nil
    }

    /// Encodes and stores a value using a versioned JSON envelope.
    public func set<Value>(_ value: Value, for key: P5StorageKey<Value>) throws {
        let data = try P5PersistenceCoding.encode(value)
        runtime.set(data, physicalKey(key))
    }

    /// Decodes a value, returns `nil` for a missing key, and rejects non-Data objects.
    public func value<Value>(for key: P5StorageKey<Value>) throws -> Value? {
        let physicalKey = physicalKey(key)
        guard runtime.object(physicalKey) != nil else { return nil }
        guard let data = runtime.data(physicalKey) else {
            throw P5PersistenceError.decodingFailed(
                "The UserDefaults object is not encoded P5 data."
            )
        }
        return try P5PersistenceCoding.decode(Value.self, from: data)
    }

    /// Removes one value without affecting any other namespace or key.
    public func removeValue<Value>(for key: P5StorageKey<Value>) {
        runtime.remove(physicalKey(key))
    }

    private func physicalKey<Value>(_ key: P5StorageKey<Value>) -> String {
        "\(namespace).\(key.name)"
    }
}

/// Actor-isolated Codable file store with versioned payloads and atomic writes.
public actor P5FileStore {
    /// Directory containing one JSON envelope per typed key.
    public nonisolated let directory: URL
    private let runtime: P5FileStoreRuntime

    /// Creates a store without creating its directory or reading files.
    ///
    /// - Precondition: `directory` is a file URL.
    public init(directory: URL) {
        precondition(directory.isFileURL)
        self.directory = directory.standardizedFileURL
        runtime = P5FileStoreRuntime()
    }

    init(directory: URL, runtime: P5FileStoreRuntime) {
        precondition(directory.isFileURL)
        self.directory = directory.standardizedFileURL
        self.runtime = runtime
    }

    /// Whether a file currently exists for the typed key.
    public func contains<Value>(_ key: P5StorageKey<Value>) async throws -> Bool {
        try Task.checkCancellation()
        do {
            let exists = try await runtime.contains(fileURL(for: key))
            try Task.checkCancellation()
            return exists
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw P5PersistenceError.fileReadFailed(error.localizedDescription)
        }
    }

    /// Encodes and atomically replaces the file for a typed key.
    public func save<Value>(_ value: Value, for key: P5StorageKey<Value>) async throws {
        let data = try P5PersistenceCoding.encode(value)
        try Task.checkCancellation()
        do {
            try await runtime.createDirectory(directory)
            try Task.checkCancellation()
            try await runtime.write(data, fileURL(for: key))
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw P5PersistenceError.fileWriteFailed(error.localizedDescription)
        }
    }

    /// Decodes a value or returns `nil` when its file does not exist.
    public func value<Value>(for key: P5StorageKey<Value>) async throws -> Value? {
        try Task.checkCancellation()
        let data: Data?
        do {
            data = try await runtime.read(fileURL(for: key))
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw P5PersistenceError.fileReadFailed(error.localizedDescription)
        }
        guard let data else { return nil }
        return try P5PersistenceCoding.decode(Value.self, from: data)
    }

    /// Removes one persisted file and succeeds when it is already absent.
    public func removeValue<Value>(for key: P5StorageKey<Value>) async throws {
        try Task.checkCancellation()
        do {
            try await runtime.remove(fileURL(for: key))
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw P5PersistenceError.fileRemovalFailed(error.localizedDescription)
        }
    }

    func fileURL<Value>(for key: P5StorageKey<Value>) -> URL {
        directory.appendingPathComponent(key.name).appendingPathExtension("json")
    }
}

private struct P5PersistenceEnvelope<Value: Codable>: Codable {
    let formatVersion: Int
    let value: Value
}

enum P5PersistenceCoding {
    static let formatVersion = 1

    static func encode<Value: Codable>(_ value: Value) throws -> Data {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return try encoder.encode(
                P5PersistenceEnvelope(formatVersion: formatVersion, value: value)
            )
        } catch {
            throw P5PersistenceError.encodingFailed(String(describing: error))
        }
    }

    static func decode<Value: Codable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            let envelope = try JSONDecoder().decode(P5PersistenceEnvelope<Value>.self, from: data)
            guard envelope.formatVersion == formatVersion else {
                throw P5PersistenceError.unsupportedFormatVersion(envelope.formatVersion)
            }
            return envelope.value
        } catch let error as P5PersistenceError {
            throw error
        } catch {
            throw P5PersistenceError.decodingFailed(String(describing: error))
        }
    }
}

struct P5PreferencesRuntime: @unchecked Sendable {
    var object: (String) -> Any?
    var data: (String) -> Data?
    var set: (Data, String) -> Void
    var remove: (String) -> Void

    init(userDefaults: UserDefaults) {
        object = { userDefaults.object(forKey: $0) }
        data = { userDefaults.data(forKey: $0) }
        set = { userDefaults.set($0, forKey: $1) }
        remove = { userDefaults.removeObject(forKey: $0) }
    }

    init(
        object: @escaping (String) -> Any?,
        data: @escaping (String) -> Data?,
        set: @escaping (Data, String) -> Void,
        remove: @escaping (String) -> Void
    ) {
        self.object = object
        self.data = data
        self.set = set
        self.remove = remove
    }
}

struct P5FileStoreRuntime: @unchecked Sendable {
    var createDirectory: @Sendable (URL) async throws -> Void = { url in
        try await Task.detached {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
        }.value
    }
    var contains: @Sendable (URL) async throws -> Bool = { url in
        await Task.detached { FileManager.default.fileExists(atPath: url.path) }.value
    }
    var read: @Sendable (URL) async throws -> Data? = { url in
        try await Task.detached {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try Data(contentsOf: url, options: .mappedIfSafe)
        }.value
    }
    var write: @Sendable (Data, URL) async throws -> Void = { data, url in
        try await Task.detached { try data.write(to: url, options: .atomic) }.value
    }
    var remove: @Sendable (URL) async throws -> Void = { url in
        try await Task.detached {
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            try FileManager.default.removeItem(at: url)
        }.value
    }
}

extension UInt8 {
    fileprivate var isASCIILetter: Bool { (65...90).contains(self) || (97...122).contains(self) }
    fileprivate var isASCIIDigit: Bool { (48...57).contains(self) }
}
