import CoreGraphics
import Foundation

/// A stable direct, Pencil, or indirect touch during its active lifetime.
public struct P5Touch: Sendable, Hashable, Codable {
    /// Stable identifier allocated when the native touch begins.
    public let id: UInt64
    /// Direct touch, Pencil, or indirect touch category.
    public let kind: P5PointerKind
    /// Current top-left-origin canvas location.
    public let location: CGPoint
    /// Previous top-left-origin canvas location.
    public let previousLocation: CGPoint
    /// Normalized pressure in `0...1`, or `nil` when unavailable.
    public let pressure: CGFloat?
    /// Monotonic native timestamp in seconds.
    public let timestamp: TimeInterval

    /// Movement since ``previousLocation``.
    public var delta: CGVector {
        CGVector(
            dx: location.x - previousLocation.x,
            dy: location.y - previousLocation.y
        )
    }

    /// Creates a validated touch value.
    public init(
        id: UInt64,
        kind: P5PointerKind,
        location: CGPoint,
        previousLocation: CGPoint,
        pressure: CGFloat? = nil,
        timestamp: TimeInterval
    ) {
        precondition(kind != .mouse)
        precondition(location.x.isFinite && location.y.isFinite)
        precondition(previousLocation.x.isFinite && previousLocation.y.isFinite)
        precondition(pressure.map { $0.isFinite && (0...1).contains($0) } ?? true)
        precondition(timestamp.isFinite && timestamp >= 0)
        self.id = id
        self.kind = kind
        self.location = location
        self.previousLocation = previousLocation
        self.pressure = pressure
        self.timestamp = timestamp
    }

    /// Decodes and revalidates a touch recording.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(P5PointerKind.self, forKey: .kind)
        let location = try container.decode(CGPoint.self, forKey: .location)
        let previousLocation = try container.decode(CGPoint.self, forKey: .previousLocation)
        let pressure = try container.decodeIfPresent(CGFloat.self, forKey: .pressure)
        let timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
        guard
            kind != .mouse,
            location.x.isFinite,
            location.y.isFinite,
            previousLocation.x.isFinite,
            previousLocation.y.isFinite,
            pressure.map({ $0.isFinite && (0...1).contains($0) }) ?? true,
            timestamp.isFinite,
            timestamp >= 0
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .timestamp,
                in: container,
                debugDescription: "Touch kind, coordinates, pressure, or timestamp are invalid."
            )
        }
        self.init(
            id: try container.decode(UInt64.self, forKey: .id),
            kind: kind,
            location: location,
            previousLocation: previousLocation,
            pressure: pressure,
            timestamp: timestamp
        )
    }

    init(pointerEvent: P5PointerEvent) {
        self.init(
            id: pointerEvent.id,
            kind: pointerEvent.kind,
            location: pointerEvent.location,
            previousLocation: pointerEvent.previousLocation,
            pressure: pointerEvent.pressure,
            timestamp: pointerEvent.timestamp
        )
    }
}

/// Lifecycle phase of a deterministic multi-touch collection update.
public enum P5TouchPhase: String, Sendable, Hashable, Codable, CaseIterable {
    /// One touch became active.
    case started
    /// One active touch changed position or pressure.
    case moved
    /// One touch ended normally.
    case ended
    /// The platform cancelled one touch.
    case cancelled
}

/// An ordered, recordable update to the active multi-touch collection.
public struct P5TouchEvent: Sendable, Hashable, Codable {
    /// Touch lifecycle transition represented by this event.
    public let phase: P5TouchPhase
    /// Touches changed by this delivery, sorted by stable identifier.
    public let changedTouches: [P5Touch]
    /// Touches still active after applying this delivery, sorted by identifier.
    public let activeTouches: [P5Touch]
    /// Keyboard modifiers held during the native delivery.
    public let modifiers: P5ModifierKeys
    /// Monotonic timestamp in seconds.
    public let timestamp: TimeInterval

    /// Creates a deterministic touch collection update.
    public init(
        phase: P5TouchPhase,
        changedTouches: [P5Touch],
        activeTouches: [P5Touch],
        modifiers: P5ModifierKeys = [],
        timestamp: TimeInterval
    ) {
        precondition(changedTouches.isEmpty == false)
        precondition(timestamp.isFinite && timestamp >= 0)
        precondition(Self.hasUniqueIdentifiers(changedTouches))
        precondition(Self.hasUniqueIdentifiers(activeTouches))
        self.phase = phase
        self.changedTouches = changedTouches.sorted { $0.id < $1.id }
        self.activeTouches = activeTouches.sorted { $0.id < $1.id }
        self.modifiers = modifiers
        self.timestamp = timestamp
    }

    /// Decodes and revalidates a touch collection recording.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let changedTouches = try container.decode([P5Touch].self, forKey: .changedTouches)
        let activeTouches = try container.decode([P5Touch].self, forKey: .activeTouches)
        let timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
        guard
            changedTouches.isEmpty == false,
            timestamp.isFinite,
            timestamp >= 0,
            Self.hasUniqueIdentifiers(changedTouches),
            Self.hasUniqueIdentifiers(activeTouches)
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .timestamp,
                in: container,
                debugDescription: "Touch collections or timestamp are invalid."
            )
        }
        self.init(
            phase: try container.decode(P5TouchPhase.self, forKey: .phase),
            changedTouches: changedTouches,
            activeTouches: activeTouches,
            modifiers: try container.decode(P5ModifierKeys.self, forKey: .modifiers),
            timestamp: timestamp
        )
    }

    private static func hasUniqueIdentifiers(_ touches: [P5Touch]) -> Bool {
        Set(touches.map(\.id)).count == touches.count
    }
}

/// How the canvas cooperates with host-installed native gesture recognizers.
public enum P5GestureCoexistence: String, Sendable, Hashable, Codable, CaseIterable {
    /// Leaves host gesture recognizer cancellation and delay behavior unchanged.
    case nativeDefault
    /// Asks existing UIKit recognizers not to cancel or delay canvas touches.
    case cooperative
}
