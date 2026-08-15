import CoreGraphics

enum P5Operation {
    case fill(CGColor)
    case noFill
    case stroke(CGColor)
    case noStroke
    case strokeWeight(CGFloat)

    case background(CGColor)
    case line(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat)
    case rect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat)
    case square(x: CGFloat, y: CGFloat, extent: CGFloat)
    case ellipse(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat)
    case point(x: CGFloat, y: CGFloat)
    case polygon([CGPoint])
    case arc(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        start: CGFloat,
        stop: CGFloat,
        mode: P5ArcMode
    )
    case roundedRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, cornerRadius: CGFloat)
    case shape(commands: [P5PathCommand], closure: P5ShapeClosure)

    case rotate(CGFloat)
    case translate(x: CGFloat, y: CGFloat)
    case scale(x: CGFloat, y: CGFloat)
    case shearX(CGFloat)
    case shearY(CGFloat)
    case applyMatrix(CGAffineTransform)
    case resetMatrix

    case push
    case pop
}
