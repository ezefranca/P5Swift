import CoreGraphics
import Foundation

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// Why native keyboard focus changed.
public enum P5FocusCause: String, Sendable, Hashable, Codable, CaseIterable {
    /// Focus changed because application code requested it.
    case programmatic
    /// A pointer interaction changed focus.
    case pointer
    /// Keyboard navigation changed focus.
    case keyboard
    /// The operating system or containing window changed focus.
    case system
}

/// A recordable native focus transition.
public struct P5FocusEvent: Sendable, Hashable, Codable {
    /// Whether the canvas is focused after the transition.
    public let isFocused: Bool
    /// Source of the focus change.
    public let cause: P5FocusCause
    /// Monotonic timestamp in seconds.
    public let timestamp: TimeInterval

    /// Creates a validated focus transition.
    public init(isFocused: Bool, cause: P5FocusCause, timestamp: TimeInterval) {
        precondition(timestamp.isFinite && timestamp >= 0)
        self.isFocused = isFocused
        self.cause = cause
        self.timestamp = timestamp
    }

    /// Decodes and revalidates a focus recording.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
        guard timestamp.isFinite, timestamp >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .timestamp,
                in: container,
                debugDescription: "Focus timestamps must be finite and nonnegative."
            )
        }
        self.init(
            isFocused: try container.decode(Bool.self, forKey: .isFocused),
            cause: try container.decode(P5FocusCause.self, forKey: .cause),
            timestamp: timestamp
        )
    }
}

/// Lifecycle phase of mouse or indirect-pointer hover.
public enum P5HoverPhase: String, Sendable, Hashable, Codable, CaseIterable {
    /// The pointer entered the canvas.
    case entered
    /// The pointer moved while inside the canvas.
    case moved
    /// The pointer exited the canvas.
    case exited
}

/// A recordable hover transition in top-left-origin canvas coordinates.
public struct P5HoverEvent: Sendable, Hashable, Codable {
    /// Hover lifecycle phase.
    public let phase: P5HoverPhase
    /// Current canvas position.
    public let location: CGPoint
    /// Keyboard modifiers held during delivery.
    public let modifiers: P5ModifierKeys
    /// Monotonic timestamp in seconds.
    public let timestamp: TimeInterval

    /// Creates a validated hover event.
    public init(
        phase: P5HoverPhase,
        location: CGPoint,
        modifiers: P5ModifierKeys = [],
        timestamp: TimeInterval
    ) {
        precondition(location.x.isFinite && location.y.isFinite)
        precondition(timestamp.isFinite && timestamp >= 0)
        self.phase = phase
        self.location = location
        self.modifiers = modifiers
        self.timestamp = timestamp
    }

    /// Decodes and revalidates a hover recording.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let location = try container.decode(CGPoint.self, forKey: .location)
        let timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
        guard location.x.isFinite, location.y.isFinite, timestamp.isFinite, timestamp >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .timestamp,
                in: container,
                debugDescription: "Hover coordinates and timestamp must be valid."
            )
        }
        self.init(
            phase: try container.decode(P5HoverPhase.self, forKey: .phase),
            location: location,
            modifiers: try container.decode(P5ModifierKeys.self, forKey: .modifiers),
            timestamp: timestamp
        )
    }
}

/// Lifecycle phase of a scrolling gesture or wheel sequence.
public enum P5ScrollPhase: String, Sendable, Hashable, Codable, CaseIterable {
    /// Scrolling began.
    case began
    /// Scrolling changed without a distinct native begin phase.
    case changed
    /// Scrolling and any momentum ended.
    case ended
    /// The platform cancelled scrolling.
    case cancelled
}

/// A precision-aware, recordable scrolling update.
public struct P5ScrollEvent: Sendable, Hashable, Codable {
    /// Scroll lifecycle phase.
    public let phase: P5ScrollPhase
    /// Horizontal and vertical content delta in native canvas points.
    public let delta: CGVector
    /// Pointer location associated with the scroll.
    public let location: CGPoint
    /// Keyboard modifiers held during delivery.
    public let modifiers: P5ModifierKeys
    /// Whether native hardware reported high-resolution deltas.
    public let isPrecise: Bool
    /// Whether device preferences invert the physical scrolling direction.
    public let isDirectionInverted: Bool
    /// Whether this update belongs to inertial momentum.
    public let isMomentum: Bool
    /// Monotonic timestamp in seconds.
    public let timestamp: TimeInterval

    /// Creates a validated scroll event.
    public init(
        phase: P5ScrollPhase,
        delta: CGVector,
        location: CGPoint,
        modifiers: P5ModifierKeys = [],
        isPrecise: Bool = false,
        isDirectionInverted: Bool = false,
        isMomentum: Bool = false,
        timestamp: TimeInterval
    ) {
        precondition(delta.dx.isFinite && delta.dy.isFinite)
        precondition(location.x.isFinite && location.y.isFinite)
        precondition(timestamp.isFinite && timestamp >= 0)
        self.phase = phase
        self.delta = delta
        self.location = location
        self.modifiers = modifiers
        self.isPrecise = isPrecise
        self.isDirectionInverted = isDirectionInverted
        self.isMomentum = isMomentum
        self.timestamp = timestamp
    }

    /// Decodes and revalidates a scroll recording.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let delta = try container.decode(CGVector.self, forKey: .delta)
        let location = try container.decode(CGPoint.self, forKey: .location)
        let timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
        guard
            delta.dx.isFinite,
            delta.dy.isFinite,
            location.x.isFinite,
            location.y.isFinite,
            timestamp.isFinite,
            timestamp >= 0
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .timestamp,
                in: container,
                debugDescription: "Scroll delta, location, or timestamp is invalid."
            )
        }
        self.init(
            phase: try container.decode(P5ScrollPhase.self, forKey: .phase),
            delta: delta,
            location: location,
            modifiers: try container.decode(P5ModifierKeys.self, forKey: .modifiers),
            isPrecise: try container.decode(Bool.self, forKey: .isPrecise),
            isDirectionInverted: try container.decode(Bool.self, forKey: .isDirectionInverted),
            isMomentum: try container.decode(Bool.self, forKey: .isMomentum),
            timestamp: timestamp
        )
    }
}

/// A portable payload supplied by native drag/drop or application adapters.
public enum P5DropPayload: Sendable, Hashable, Codable {
    /// A file URL whose access lifetime is owned by the host application.
    case file(URL)
    /// Plain Unicode text.
    case text(String)
    /// Opaque bytes paired with a Uniform Type Identifier string.
    case data(Data, typeIdentifier: String)
}

/// Lifecycle phase of a drag/drop interaction.
public enum P5DropPhase: String, Sendable, Hashable, Codable, CaseIterable {
    /// A drag entered the canvas.
    case entered
    /// A drag moved within the canvas.
    case updated
    /// A drag exited without dropping.
    case exited
    /// The host accepted and delivered payloads.
    case performed
    /// The platform cancelled the interaction.
    case cancelled
}

/// An ordered, recordable drag/drop update.
public struct P5DropEvent: Sendable, Hashable, Codable {
    /// Drag/drop lifecycle phase.
    public let phase: P5DropPhase
    /// Top-left-origin canvas location.
    public let location: CGPoint
    /// Payloads available at this phase.
    public let payloads: [P5DropPayload]
    /// Monotonic timestamp in seconds.
    public let timestamp: TimeInterval

    /// Creates a validated drag/drop event.
    public init(
        phase: P5DropPhase,
        location: CGPoint,
        payloads: [P5DropPayload] = [],
        timestamp: TimeInterval
    ) {
        precondition(location.x.isFinite && location.y.isFinite)
        precondition(timestamp.isFinite && timestamp >= 0)
        self.phase = phase
        self.location = location
        self.payloads = payloads
        self.timestamp = timestamp
    }

    /// Decodes and revalidates a drop recording.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let location = try container.decode(CGPoint.self, forKey: .location)
        let timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
        guard location.x.isFinite, location.y.isFinite, timestamp.isFinite, timestamp >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .timestamp,
                in: container,
                debugDescription: "Drop location and timestamp must be valid."
            )
        }
        self.init(
            phase: try container.decode(P5DropPhase.self, forKey: .phase),
            location: location,
            payloads: try container.decode([P5DropPayload].self, forKey: .payloads),
            timestamp: timestamp
        )
    }
}

/// A semantic action exposed to VoiceOver and other assistive technologies.
public enum P5AccessibilityAction: Sendable, Hashable, Codable {
    /// Activates the canvas' primary semantic control.
    case activate
    /// Increments a semantic value.
    case increment
    /// Decrements a semantic value.
    case decrement
    /// Escapes or dismisses the current semantic interaction.
    case escape
    /// Invokes a host-defined action name.
    case custom(String)
}

/// A recordable accessibility action request.
public struct P5AccessibilityEvent: Sendable, Hashable, Codable {
    /// Requested semantic action.
    public let action: P5AccessibilityAction
    /// Monotonic timestamp in seconds.
    public let timestamp: TimeInterval

    /// Creates a validated accessibility request.
    public init(action: P5AccessibilityAction, timestamp: TimeInterval) {
        precondition(timestamp.isFinite && timestamp >= 0)
        self.action = action
        self.timestamp = timestamp
    }

    /// Decodes and revalidates an accessibility recording.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
        guard timestamp.isFinite, timestamp >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .timestamp,
                in: container,
                debugDescription: "Accessibility timestamps must be valid."
            )
        }
        self.init(
            action: try container.decode(P5AccessibilityAction.self, forKey: .action),
            timestamp: timestamp
        )
    }
}

/// Main-actor access to the native general clipboard.
@MainActor
public final class P5Clipboard {
    /// Shared native clipboard used by the current application.
    public static let general = P5Clipboard()

    #if canImport(AppKit)
        private let pasteboard: NSPasteboard

        init(pasteboard: NSPasteboard) {
            self.pasteboard = pasteboard
        }

        private convenience init() {
            self.init(pasteboard: .general)
        }
    #elseif canImport(UIKit)
        private init() {}
    #endif

    /// Current plain text, or `nil` when unavailable.
    public var text: String? {
        #if canImport(AppKit)
            pasteboard.string(forType: .string)
        #elseif canImport(UIKit)
            UIPasteboard.general.string
        #endif
    }

    /// Replaces clipboard contents with plain Unicode text.
    public func setText(_ text: String) {
        #if canImport(AppKit)
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        #elseif canImport(UIKit)
            UIPasteboard.general.string = text
        #endif
    }

    /// Returns bytes for a Uniform Type Identifier string.
    public func data(forTypeIdentifier identifier: String) -> Data? {
        precondition(identifier.isEmpty == false)
        #if canImport(AppKit)
            return pasteboard.data(forType: NSPasteboard.PasteboardType(identifier))
        #elseif canImport(UIKit)
            return UIPasteboard.general.data(forPasteboardType: identifier)
        #endif
    }

    /// Replaces clipboard contents with typed bytes.
    public func setData(_ data: Data, forTypeIdentifier identifier: String) {
        precondition(identifier.isEmpty == false)
        #if canImport(AppKit)
            pasteboard.clearContents()
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType(identifier))
        #elseif canImport(UIKit)
            UIPasteboard.general.setData(data, forPasteboardType: identifier)
        #endif
    }

    /// Removes all native clipboard contents.
    public func clear() {
        #if canImport(AppKit)
            pasteboard.clearContents()
        #elseif canImport(UIKit)
            UIPasteboard.general.items = []
        #endif
    }
}
