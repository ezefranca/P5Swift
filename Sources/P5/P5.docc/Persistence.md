# Native Persistence

Store small settings in UserDefaults or larger Codable state in atomic files without
giving up type safety.

## Overview

``P5StorageKey`` gives a persisted value a stable name and a compile-time value type.
Names accept only ASCII letters, numbers, dots, hyphens, and underscores so the same
key is safe in both UserDefaults and a file-system directory.

Use ``P5Preferences`` for small preferences that belong in UserDefaults:

```swift
struct SketchSettings: Codable, Sendable {
    var particleCount: Int
    var trailsEnabled: Bool
}

let settingsKey = P5StorageKey<SketchSettings>("settings")
let preferences = P5Preferences(namespace: "MySketch")

try preferences.set(
    SketchSettings(particleCount: 500, trailsEnabled: true),
    for: settingsKey
)

let settings = try preferences.value(for: settingsKey)
```

The namespace becomes part of the physical UserDefaults key. Choose a stable,
application-specific namespace to avoid collisions with other packages. P5 does not
call `synchronize()`; UserDefaults controls when preferences reach durable storage.

Use the actor-isolated ``P5FileStore`` for documents, learned parameters, or other
larger state:

```swift
let directory = try FileManager.default.url(
    for: .applicationSupportDirectory,
    in: .userDomainMask,
    appropriateFor: nil,
    create: true
).appendingPathComponent("MySketch", isDirectory: true)

let store = P5FileStore(directory: directory)
try await store.save(settings, for: settingsKey)
let restored = try await store.value(for: settingsKey)
```

Each file write atomically replaces one `<key>.json` file. File operations run away
from the caller's executor, observe cooperative cancellation before and after native
I/O, and translate platform failures into ``P5PersistenceError``.

## Format and migration

Both stores encode deterministic JSON inside a versioned envelope. Missing values
return `nil`; corrupt data, a mismatched value type, or a future envelope version
throws a typed error. Removing a missing value succeeds.

An optional value stored as `.some(nil)` is indistinguishable at the call site from a
missing key. Prefer a nonoptional Codable wrapper when those states must differ.

The format version is intentionally validated rather than silently guessed. Before a
future release changes the envelope, applications can decode the previous model and
save a migrated value under the same key.

## Storage policy

The host application chooses the file-store directory and therefore owns its backup,
file-protection, sharing, and cleanup policy. Keep secrets in Keychain rather than
UserDefaults or ``P5FileStore``. Do not place cache-like values in Documents merely to
make them visible to the user.

## Topics

### Typed storage

- ``P5StorageKey``
- ``P5Preferences``
- ``P5FileStore``
- ``P5PersistenceError``
