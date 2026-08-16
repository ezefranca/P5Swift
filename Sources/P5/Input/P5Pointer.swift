import CoreGraphics
import Foundation

/// The kind of native pointing device that produced an event.
public enum P5PointerKind: Sendable, Hashable, Codable, CaseIterable {
    /// A mouse or mouse-like trackpad cursor.
    case mouse

    /// A direct finger touch.
    case touch

    /// Apple Pencil input.
    case pencil

    /// An indirect pointer such as a trackpad-directed iPad cursor.
    case indirect
}

/// The lifecycle phase of a pointer event.
public enum P5PointerPhase: Sendable, Hashable, Codable, CaseIterable {
    /// The pointer entered the canvas.
    case entered

    /// The pointer exited the canvas.
    case exited

    /// The pointer moved without a pressed button.
    case moved

    /// The pointer moved while pressed.
    case dragged

    /// A button or touch became pressed.
    case pressed

    /// A button or touch was released.
    case released

    /// A complete click or tap occurred.
    case clicked

    /// The platform cancelled an active interaction.
    case cancelled
}

/// The button directly associated with a pointer event.
public enum P5PointerButton: Sendable, Hashable, Codable {
    /// No particular button, as with movement or entry events.
    case none

    /// The primary mouse button or a direct touch.
    case primary

    /// The secondary mouse button.
    case secondary

    /// The middle mouse button.
    case middle

    /// Another platform button identified by its zero-based number.
    case other(Int)
}

/// The complete set of pointer buttons held during an event.
public struct P5PointerButtons: OptionSet, Sendable, Hashable, Codable {
    /// The underlying bit field.
    public let rawValue: UInt8

    /// Creates a set from its underlying bit field.
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// The primary mouse button or a direct touch is held.
    public static let primary = P5PointerButtons(rawValue: 1 << 0)

    /// The secondary mouse button is held.
    public static let secondary = P5PointerButtons(rawValue: 1 << 1)

    /// The middle mouse button is held.
    public static let middle = P5PointerButtons(rawValue: 1 << 2)

    /// At least one other platform button is held.
    public static let other = P5PointerButtons(rawValue: 1 << 3)
}

/// Keyboard modifiers held during a pointer or keyboard event.
public struct P5ModifierKeys: OptionSet, Sendable, Hashable, Codable {
    /// The underlying bit field.
    public let rawValue: UInt8

    /// Creates a set from its underlying bit field.
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// The Shift key is held.
    public static let shift = P5ModifierKeys(rawValue: 1 << 0)

    /// The Control key is held.
    public static let control = P5ModifierKeys(rawValue: 1 << 1)

    /// The Option or Alt key is held.
    public static let option = P5ModifierKeys(rawValue: 1 << 2)

    /// The Command key is held.
    public static let command = P5ModifierKeys(rawValue: 1 << 3)

    /// Caps Lock is enabled.
    public static let capsLock = P5ModifierKeys(rawValue: 1 << 4)

    /// The Function key is held.
    public static let function = P5ModifierKeys(rawValue: 1 << 5)
}

/// A platform-neutral pointer event in canvas coordinates.
public struct P5PointerEvent: Sendable, Hashable, Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case phase
        case location
        case previousLocation
        case button
        case pressedButtons
        case modifiers
        case pressure
        case timestamp
    }

    /// A stable identifier for the pointer's active lifetime.
    ///
    /// Mouse events use zero.
    public let id: UInt64

    /// The native pointing-device category.
    public let kind: P5PointerKind

    /// The interaction phase.
    public let phase: P5PointerPhase

    /// The current location in top-left-origin canvas points.
    public let location: CGPoint

    /// The preceding location in top-left-origin canvas points.
    public let previousLocation: CGPoint

    /// The button directly associated with the event.
    public let button: P5PointerButton

    /// All buttons held after applying this event.
    public let pressedButtons: P5PointerButtons

    /// Keyboard modifiers held during the event.
    public let modifiers: P5ModifierKeys

    /// Normalized pressure in `0...1`, or `nil` when unavailable.
    public let pressure: CGFloat?

    /// The platform's monotonic event timestamp in seconds.
    public let timestamp: TimeInterval

    /// Movement since ``previousLocation`` in canvas points.
    public var delta: CGVector {
        CGVector(
            dx: location.x - previousLocation.x,
            dy: location.y - previousLocation.y
        )
    }

    /// Creates a validated pointer event.
    ///
    /// Locations and timestamps must be finite. Pressure, when present, must be
    /// normalized to `0...1`.
    public init(
        id: UInt64,
        kind: P5PointerKind,
        phase: P5PointerPhase,
        location: CGPoint,
        previousLocation: CGPoint,
        button: P5PointerButton = .none,
        pressedButtons: P5PointerButtons = [],
        modifiers: P5ModifierKeys = [],
        pressure: CGFloat? = nil,
        timestamp: TimeInterval
    ) {
        precondition(location.x.isFinite && location.y.isFinite)
        precondition(previousLocation.x.isFinite && previousLocation.y.isFinite)
        precondition(timestamp.isFinite && timestamp >= 0)
        precondition(pressure.map { $0.isFinite && (0...1).contains($0) } ?? true)
        self.id = id
        self.kind = kind
        self.phase = phase
        self.location = location
        self.previousLocation = previousLocation
        self.button = button
        self.pressedButtons = pressedButtons
        self.modifiers = modifiers
        self.pressure = pressure
        self.timestamp = timestamp
    }

    /// Decodes an event while preserving its finite-value invariants.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let location = try container.decode(CGPoint.self, forKey: .location)
        let previousLocation = try container.decode(CGPoint.self, forKey: .previousLocation)
        let pressure = try container.decodeIfPresent(CGFloat.self, forKey: .pressure)
        let timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
        guard
            location.x.isFinite,
            location.y.isFinite,
            previousLocation.x.isFinite,
            previousLocation.y.isFinite,
            timestamp.isFinite,
            timestamp >= 0,
            pressure.map({ $0.isFinite && (0...1).contains($0) }) ?? true
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .timestamp,
                in: container,
                debugDescription: "Pointer coordinates, timestamp, or pressure are invalid."
            )
        }

        self.init(
            id: try container.decode(UInt64.self, forKey: .id),
            kind: try container.decode(P5PointerKind.self, forKey: .kind),
            phase: try container.decode(P5PointerPhase.self, forKey: .phase),
            location: location,
            previousLocation: previousLocation,
            button: try container.decode(P5PointerButton.self, forKey: .button),
            pressedButtons: try container.decode(P5PointerButtons.self, forKey: .pressedButtons),
            modifiers: try container.decode(P5ModifierKeys.self, forKey: .modifiers),
            pressure: pressure,
            timestamp: timestamp
        )
    }
}
