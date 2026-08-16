import CoreGraphics

/// A finite, value-semantic two-dimensional affine transformation.
public struct P5Transform: Sendable, Hashable, Codable {
    /// Horizontal scale and rotation component.
    public let a: CGFloat
    /// Vertical shear and rotation component.
    public let b: CGFloat
    /// Horizontal shear and rotation component.
    public let c: CGFloat
    /// Vertical scale and rotation component.
    public let d: CGFloat
    /// Horizontal translation.
    public let tx: CGFloat
    /// Vertical translation.
    public let ty: CGFloat

    /// Identity transformation.
    public static let identity = P5Transform()

    /// Creates a finite affine transformation.
    ///
    /// - Precondition: Every component is finite.
    public init(
        a: CGFloat = 1,
        b: CGFloat = 0,
        c: CGFloat = 0,
        d: CGFloat = 1,
        tx: CGFloat = 0,
        ty: CGFloat = 0
    ) {
        precondition([a, b, c, d, tx, ty].allSatisfy(\.isFinite))
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    /// Copies a Core Graphics affine transformation.
    ///
    /// - Precondition: Every component is finite.
    public init(_ transform: CGAffineTransform) {
        self.init(
            a: transform.a,
            b: transform.b,
            c: transform.c,
            d: transform.d,
            tx: transform.tx,
            ty: transform.ty
        )
    }

    /// Equivalent Core Graphics transformation.
    public var cgAffineTransform: CGAffineTransform {
        CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
    }

    /// Returns this transformation followed by another transformation.
    public func concatenating(_ other: P5Transform) -> P5Transform {
        P5Transform(cgAffineTransform.concatenating(other.cgAffineTransform))
    }

    /// Returns a copy translated along both axes.
    public func translatedBy(x: CGFloat, y: CGFloat) -> P5Transform {
        precondition(x.isFinite && y.isFinite)
        return P5Transform(cgAffineTransform.translatedBy(x: x, y: y))
    }

    /// Returns a copy rotated clockwise in top-left-origin canvas coordinates.
    public func rotated(by radians: CGFloat) -> P5Transform {
        precondition(radians.isFinite)
        return P5Transform(cgAffineTransform.rotated(by: radians))
    }

    /// Returns a copy scaled independently along both axes.
    public func scaledBy(x: CGFloat, y: CGFloat) -> P5Transform {
        precondition(x.isFinite && y.isFinite)
        return P5Transform(cgAffineTransform.scaledBy(x: x, y: y))
    }

    /// Returns the inverse transformation, or `nil` when this value is singular.
    public var inverted: P5Transform? {
        let determinant = a * d - b * c
        guard determinant.isFinite, determinant != 0 else { return nil }
        return P5Transform(cgAffineTransform.inverted())
    }

    /// Applies the transformation to a point.
    public func applying(to point: CGPoint) -> CGPoint {
        precondition(point.x.isFinite && point.y.isFinite)
        return point.applying(cgAffineTransform)
    }

    /// Decodes and revalidates an affine transformation.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            a: try container.decode(CGFloat.self, forKey: .a),
            b: try container.decode(CGFloat.self, forKey: .b),
            c: try container.decode(CGFloat.self, forKey: .c),
            d: try container.decode(CGFloat.self, forKey: .d),
            tx: try container.decode(CGFloat.self, forKey: .tx),
            ty: try container.decode(CGFloat.self, forKey: .ty)
        )
    }
}
