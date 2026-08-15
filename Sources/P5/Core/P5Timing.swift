import Foundation

/// A monotonic time source used by a ``P5Sketch``.
///
/// Clock values are measured in seconds from an arbitrary origin. Implementations
/// must return finite values that never move backwards. The protocol is isolated
/// to the main actor because sketch lifecycle callbacks are delivered there.
@MainActor
public protocol P5Clock {
    /// The clock's current monotonic time in seconds.
    var now: TimeInterval { get }
}

/// The system monotonic clock used by automatically driven sketches.
@MainActor
public struct P5SystemClock: P5Clock, Sendable {
    /// Creates a system clock backed by process uptime.
    public init() {}

    /// The process uptime in seconds.
    public var now: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}

/// A deterministic monotonic clock for tests, previews, and reproducible sketches.
@MainActor
public final class P5ManualClock: P5Clock {
    /// The clock's current monotonic time in seconds.
    public private(set) var now: TimeInterval

    /// Creates a manual clock.
    ///
    /// - Parameter initialTime: A finite, nonnegative time in seconds.
    public init(initialTime: TimeInterval = 0) {
        precondition(initialTime.isFinite && initialTime >= 0)
        now = initialTime
    }

    /// Advances the clock by a finite, nonnegative duration.
    ///
    /// - Parameter duration: The number of seconds to advance.
    public func advance(by duration: TimeInterval) {
        precondition(duration.isFinite && duration >= 0)
        let advancedTime = now + duration
        precondition(advancedTime.isFinite)
        now = advancedTime
    }
}

/// The source of frame requests for a ``P5Sketch``.
public enum P5FrameDriver: Sendable, Hashable, Codable, CaseIterable {
    /// Uses a display link on iOS and a main-run-loop timer on macOS.
    case automatic

    /// Draws only after ``P5Sketch/advanceFrame()`` requests a frame.
    case manual
}
