import CoreGraphics

/// The unit used by sketch-level angular and trigonometric APIs.
public enum P5AngleMode: String, Sendable, Hashable, Codable, CaseIterable {
    /// Angles are expressed in radians.
    case radians

    /// Angles are expressed in degrees.
    case degrees

    /// Converts a value in this mode to radians.
    public func radians(from value: CGFloat) -> CGFloat {
        switch self {
        case .radians:
            value
        case .degrees:
            P5Math.radians(value)
        }
    }

    /// Converts a value in radians to this mode.
    public func value(fromRadians value: CGFloat) -> CGFloat {
        switch self {
        case .radians:
            value
        case .degrees:
            P5Math.degrees(value)
        }
    }
}
