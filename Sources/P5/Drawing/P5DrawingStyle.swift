import CoreGraphics

/// The interpretation of rectangle coordinates.
public enum P5RectMode: Sendable, Hashable, Codable, CaseIterable {
    /// The first two values are the top-left corner and the next two are size.
    case corner

    /// The two value pairs are opposite corners.
    case corners

    /// The first pair is the center and the next two values are full size.
    case center

    /// The first pair is the center and the next two values are half-size radii.
    case radius
}

/// The interpretation of ellipse and arc coordinates.
public enum P5EllipseMode: Sendable, Hashable, Codable, CaseIterable {
    /// The first pair is the top-left corner and the next two values are full size.
    case corner

    /// The two value pairs are opposite corners.
    case corners

    /// The first pair is the center and the next two values are full size.
    case center

    /// The first pair is the center and the next two values are radii.
    case radius
}

/// The shape drawn at the endpoints of stroked paths.
public enum P5StrokeCap: Sendable, Hashable, Codable, CaseIterable {
    /// A semicircular cap extends by half the stroke width.
    case round

    /// A square cap extends by half the stroke width.
    case project

    /// A flat cap ends exactly at the path endpoint.
    case square
}

/// The shape drawn where two stroked segments meet.
public enum P5StrokeJoin: Sendable, Hashable, Codable, CaseIterable {
    /// Extends the outside edges until they meet at a point.
    case miter

    /// Cuts off the outside corner with a straight edge.
    case bevel

    /// Rounds the outside corner.
    case round
}

/// The winding rule used when filling paths.
public enum P5FillRule: Sendable, Hashable, Codable, CaseIterable {
    /// Uses nonzero winding counts to determine the interior.
    case nonZero

    /// Alternates between interior and exterior at each crossed edge.
    case evenOdd
}

/// A Core Graphics blend operation supported by the 2D renderer.
public enum P5BlendMode: Sendable, Hashable, Codable, CaseIterable {
    /// Draws source content over destination content.
    case normal

    /// Multiplies source and destination components.
    case multiply

    /// Produces the inverse of multiplied inverse components.
    case screen

    /// Adds source and destination components for additive light effects.
    case add

    /// Keeps the darker component from source and destination.
    case darken

    /// Keeps the lighter component from source and destination.
    case lighten

    /// Uses the absolute difference between source and destination.
    case difference

    /// Uses a lower-contrast difference blend.
    case exclusion

    /// Replaces destination pixels with source pixels.
    case replace

    /// Multiplies or screens according to destination luminance.
    case overlay

    /// Multiplies or screens according to source luminance.
    case hardLight

    /// Applies a gentler contrast-changing light blend.
    case softLight

    /// Brightens destination pixels according to source color.
    case colorDodge

    /// Darkens destination pixels according to source color.
    case colorBurn
}

public extension P5Sketch {
    /// Selects how rectangle and square arguments are interpreted.
    func rectMode(_ mode: P5RectMode) {
        currentRectMode = mode
    }

    /// Selects how ellipse, circle, and arc arguments are interpreted.
    func ellipseMode(_ mode: P5EllipseMode) {
        currentEllipseMode = mode
    }

    /// Selects the endpoint shape for stroked paths.
    func strokeCap(_ cap: P5StrokeCap) {
        queueOperation(.strokeCap(cap))
    }

    /// Selects the corner shape for stroked paths.
    func strokeJoin(_ join: P5StrokeJoin) {
        queueOperation(.strokeJoin(join))
    }

    /// Sets the maximum extension of a mitered stroke join.
    func strokeMiterLimit(_ limit: CGFloat) {
        precondition(limit.isFinite && limit > 0)
        queueOperation(.strokeMiterLimit(limit))
    }

    /// Sets a repeating stroke dash pattern in points.
    func strokeDash(_ lengths: [CGFloat], phase: CGFloat = 0) {
        precondition(phase.isFinite)
        precondition(lengths.allSatisfy { $0.isFinite && $0 >= 0 })
        precondition(lengths.isEmpty || lengths.contains { $0 > 0 })
        queueOperation(.strokeDash(phase: phase, lengths: lengths))
    }

    /// Removes the current stroke dash pattern.
    func noStrokeDash() {
        queueOperation(.strokeDash(phase: 0, lengths: []))
    }

    /// Selects the winding rule used for filled paths.
    func fillRule(_ rule: P5FillRule) {
        queueOperation(.fillRule(rule))
    }

    /// Enables edge antialiasing for subsequent drawing.
    func smooth() {
        queueOperation(.antialias(true))
    }

    /// Disables edge antialiasing for subsequent drawing.
    func noSmooth() {
        queueOperation(.antialias(false))
    }

    /// Selects a compositing blend mode for subsequent drawing.
    func blendMode(_ mode: P5BlendMode) {
        queueOperation(.blendMode(mode))
    }

    /// Sets the global opacity for subsequent drawing in the range `0...1`.
    func opacity(_ opacity: CGFloat) {
        precondition(opacity.isFinite && (0...1).contains(opacity))
        queueOperation(.opacity(opacity))
    }
}
