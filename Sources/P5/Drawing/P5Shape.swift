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

/// A canonical Core Graphics-compatible element in a reusable path.
public enum P5PathElement: Sendable, Hashable, Codable {
    /// Starts a new open subpath.
    case move(to: CGPoint)
    /// Adds a straight segment.
    case line(to: CGPoint)
    /// Adds a quadratic Bézier segment.
    case quadratic(control: CGPoint, end: CGPoint)
    /// Adds a cubic Bézier segment.
    case cubic(control1: CGPoint, control2: CGPoint, end: CGPoint)
    /// Closes the current subpath.
    case closeSubpath
}

/// Immutable reusable path geometry with Core Graphics import and export.
public struct P5Shape: Sendable, Hashable, Codable {
    /// Canonical ordered path elements.
    public let elements: [P5PathElement]
    /// Optional fill-rule override retained for contour geometry.
    public let fillRule: P5FillRule?

    /// Creates reusable geometry from canonical path elements.
    ///
    /// - Precondition: Every point component is finite.
    public init(
        elements: [P5PathElement],
        fillRule: P5FillRule? = nil
    ) {
        precondition(elements.allSatisfy(\.hasFiniteCoordinates))
        self.elements = elements
        self.fillRule = fillRule
    }

    /// Copies immutable Core Graphics path geometry.
    ///
    /// - Parameters:
    ///   - path: Source path whose elements are copied immediately.
    ///   - fillRule: Optional fill-rule override associated with the geometry.
    public init(path: CGPath, fillRule: P5FillRule? = nil) {
        var elements: [P5PathElement] = []
        path.applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            if element.type == .moveToPoint {
                elements.append(.move(to: element.points[0]))
            } else if element.type == .addLineToPoint {
                elements.append(.line(to: element.points[0]))
            } else if element.type == .addQuadCurveToPoint {
                elements.append(
                    .quadratic(control: element.points[0], end: element.points[1])
                )
            } else if element.type == .addCurveToPoint {
                elements.append(
                    .cubic(
                        control1: element.points[0],
                        control2: element.points[1],
                        end: element.points[2]
                    )
                )
            } else if element.type == .closeSubpath {
                elements.append(.closeSubpath)
            }
        }
        self.init(elements: elements, fillRule: fillRule)
    }

    /// Reconstructs an immutable Core Graphics path.
    public var cgPath: CGPath {
        let path = CGMutablePath()
        for element in elements {
            switch element {
            case let .move(point):
                path.move(to: point)
            case let .line(point):
                path.addLine(to: point)
            case let .quadratic(control, end):
                path.addQuadCurve(to: end, control: control)
            case let .cubic(control1, control2, end):
                path.addCurve(to: end, control1: control1, control2: control2)
            case .closeSubpath:
                path.closeSubpath()
            }
        }
        return path
    }

    /// Tight bounding box including curve extrema.
    public var bounds: CGRect {
        cgPath.boundingBoxOfPath
    }

    /// Returns whether a point lies inside the path under its effective fill rule.
    public func contains(_ point: CGPoint) -> Bool {
        precondition(point.x.isFinite && point.y.isFinite)
        let rule: CGPathFillRule = fillRule == .evenOdd ? .evenOdd : .winding
        return cgPath.contains(point, using: rule, transform: .identity)
    }

    /// Returns a reusable shape with every point transformed.
    public func applying(_ transform: P5Transform) -> P5Shape {
        P5Shape(
            elements: elements.map { $0.applying(transform) },
            fillRule: fillRule
        )
    }

    /// Decodes and revalidates reusable path geometry.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            elements: try container.decode([P5PathElement].self, forKey: .elements),
            fillRule: try container.decodeIfPresent(P5FillRule.self, forKey: .fillRule)
        )
    }

    init(commands: [P5PathCommand], closure: P5ShapeClosure) {
        let path = CGMutablePath()
        var hasPoint = false
        var curvePoints: [CGPoint] = []
        var usesEvenOddFill = false

        func flushCurvePoints() {
            guard curvePoints.count >= 4 else {
                curvePoints.removeAll()
                return
            }
            for index in 0...(curvePoints.count - 4) {
                let firstControl = curvePoints[index]
                let start = curvePoints[index + 1]
                let end = curvePoints[index + 2]
                let lastControl = curvePoints[index + 3]
                if !hasPoint {
                    path.move(to: start)
                    hasPoint = true
                }
                path.addCurve(
                    to: end,
                    control1: start + ((end - firstControl) / 6),
                    control2: end - ((lastControl - start) / 6)
                )
            }
            curvePoints.removeAll()
        }

        for command in commands {
            switch command {
            case let .curve(point):
                curvePoints.append(point)
            case let .vertex(point):
                flushCurvePoints()
                if hasPoint {
                    path.addLine(to: point)
                } else {
                    path.move(to: point)
                    hasPoint = true
                }
            case let .bezier(control1, control2, end):
                flushCurvePoints()
                path.addCurve(to: end, control1: control1, control2: control2)
                hasPoint = true
            case let .quadratic(control, end):
                flushCurvePoints()
                path.addQuadCurve(to: end, control: control)
                hasPoint = true
            case .beginContour:
                flushCurvePoints()
                path.closeSubpath()
                hasPoint = false
                usesEvenOddFill = true
            case .endContour:
                flushCurvePoints()
                path.closeSubpath()
                hasPoint = false
            }
        }
        flushCurvePoints()
        if closure == .close {
            path.closeSubpath()
        }
        self.init(path: path, fillRule: usesEvenOddFill ? .evenOdd : nil)
    }
}

private extension P5PathElement {
    var hasFiniteCoordinates: Bool {
        points.allSatisfy { $0.x.isFinite && $0.y.isFinite }
    }

    var points: [CGPoint] {
        switch self {
        case let .move(point), let .line(point):
            [point]
        case let .quadratic(control, end):
            [control, end]
        case let .cubic(control1, control2, end):
            [control1, control2, end]
        case .closeSubpath:
            []
        }
    }

    func applying(_ transform: P5Transform) -> P5PathElement {
        switch self {
        case let .move(point):
            .move(to: transform.applying(to: point))
        case let .line(point):
            .line(to: transform.applying(to: point))
        case let .quadratic(control, end):
            .quadratic(
                control: transform.applying(to: control),
                end: transform.applying(to: end)
            )
        case let .cubic(control1, control2, end):
            .cubic(
                control1: transform.applying(to: control1),
                control2: transform.applying(to: control2),
                end: transform.applying(to: end)
            )
        case .closeSubpath:
            .closeSubpath
        }
    }
}

private func + (lhs: CGPoint, rhs: CGVector) -> CGPoint {
    CGPoint(x: lhs.x + rhs.dx, y: lhs.y + rhs.dy)
}

private func - (lhs: CGPoint, rhs: CGPoint) -> CGVector {
    CGVector(dx: lhs.x - rhs.x, dy: lhs.y - rhs.y)
}

private func - (lhs: CGPoint, rhs: CGVector) -> CGPoint {
    CGPoint(x: lhs.x - rhs.dx, y: lhs.y - rhs.dy)
}

private func / (lhs: CGVector, rhs: CGFloat) -> CGVector {
    CGVector(dx: lhs.dx / rhs, dy: lhs.dy / rhs)
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
    /// - Returns: Immutable geometry that can be transformed and drawn again.
    @discardableResult
    func endShape(_ closure: P5ShapeClosure = .open) -> P5Shape {
        precondition(isBuildingShape && !isInsideContour)
        let commands = shapeCommands
        shapeCommands.removeAll(keepingCapacity: true)
        isBuildingShape = false
        shapeHasEndpoint = false
        queueOperation(.shape(commands: commands, closure: closure))
        return P5Shape(commands: commands, closure: closure)
    }

    /// Queues immutable reusable path geometry for drawing with the current style.
    func shape(_ shape: P5Shape) {
        queueOperation(.reusableShape(shape))
    }
}
