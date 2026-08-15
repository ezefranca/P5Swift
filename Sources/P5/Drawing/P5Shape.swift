import CoreGraphics

/// The closure used to finish a custom shape.
public enum P5ShapeClosure: Sendable, Hashable, Codable, CaseIterable {
    /// Leaves the final vertex disconnected from the first vertex.
    case open

    /// Connects the final vertex to the first vertex.
    case close
}

/// The closure geometry used to draw an arc.
public enum P5ArcMode: Sendable, Hashable, Codable, CaseIterable {
    /// Draws only the curved edge.
    case open

    /// Connects the arc endpoints with a straight chord.
    case chord

    /// Connects both arc endpoints to the ellipse center.
    case pie
}

enum P5PathCommand {
    case vertex(CGPoint)
    case bezier(control1: CGPoint, control2: CGPoint, end: CGPoint)
    case quadratic(control: CGPoint, end: CGPoint)
    case curve(CGPoint)
    case beginContour
    case endContour
}

public extension P5Sketch {
    /// Begins recording a custom shape.
    ///
    /// Pair this method with one or more vertex methods and ``endShape(_:)``.
    func beginShape() {
        precondition(!isBuildingShape)
        shapeCommands.removeAll(keepingCapacity: true)
        isBuildingShape = true
        isInsideContour = false
        shapeHasEndpoint = false
    }

    /// Adds a straight-line vertex to the custom shape being recorded.
    func vertex(_ x: CGFloat, _ y: CGFloat) {
        precondition(isBuildingShape)
        shapeCommands.append(.vertex(CGPoint(x: x, y: y)))
        shapeHasEndpoint = true
    }

    /// Adds a cubic Bézier segment to the custom shape being recorded.
    func bezierVertex(
        _ control1X: CGFloat,
        _ control1Y: CGFloat,
        _ control2X: CGFloat,
        _ control2Y: CGFloat,
        _ x: CGFloat,
        _ y: CGFloat
    ) {
        precondition(isBuildingShape && shapeHasEndpoint)
        shapeCommands.append(
            .bezier(
                control1: CGPoint(x: control1X, y: control1Y),
                control2: CGPoint(x: control2X, y: control2Y),
                end: CGPoint(x: x, y: y)
            )
        )
        shapeHasEndpoint = true
    }

    /// Adds a quadratic Bézier segment to the custom shape being recorded.
    func quadraticVertex(
        _ controlX: CGFloat,
        _ controlY: CGFloat,
        _ x: CGFloat,
        _ y: CGFloat
    ) {
        precondition(isBuildingShape && shapeHasEndpoint)
        shapeCommands.append(
            .quadratic(
                control: CGPoint(x: controlX, y: controlY),
                end: CGPoint(x: x, y: y)
            )
        )
        shapeHasEndpoint = true
    }

    /// Adds a Catmull-Rom curve control vertex to the custom shape.
    ///
    /// A contiguous run requires at least four curve vertices. Repeat the first
    /// and last visible points to make the curve pass through them.
    func curveVertex(_ x: CGFloat, _ y: CGFloat) {
        precondition(isBuildingShape)
        shapeCommands.append(.curve(CGPoint(x: x, y: y)))
        shapeHasEndpoint = true
    }

    /// Begins an interior contour that is removed from the shape using even-odd fill.
    func beginContour() {
        precondition(isBuildingShape && !isInsideContour && shapeHasEndpoint)
        shapeCommands.append(.beginContour)
        isInsideContour = true
        shapeHasEndpoint = false
    }

    /// Finishes the current interior contour.
    func endContour() {
        precondition(isBuildingShape && isInsideContour && shapeHasEndpoint)
        shapeCommands.append(.endContour)
        isInsideContour = false
        shapeHasEndpoint = true
    }

    /// Finishes and queues the current custom shape for drawing.
    ///
    /// - Parameter closure: Whether to connect the last outer vertex to the first.
    func endShape(_ closure: P5ShapeClosure = .open) {
        precondition(isBuildingShape && !isInsideContour)
        let commands = shapeCommands
        shapeCommands.removeAll(keepingCapacity: true)
        isBuildingShape = false
        shapeHasEndpoint = false
        queueOperation(.shape(commands: commands, closure: closure))
    }
}
