import CoreGraphics

final class P5Renderer {
    private struct DrawingStyle {
        var fillColor: CGColor? = CGColor(gray: 1, alpha: 1)
        var strokeColor: CGColor? = CGColor(gray: 0, alpha: 1)
        var strokeWeight: CGFloat = 1
        var strokeCap = P5StrokeCap.round
        var strokeJoin = P5StrokeJoin.miter
        var strokeMiterLimit: CGFloat = 10
        var strokeDashPhase: CGFloat = 0
        var strokeDashLengths: [CGFloat] = []
        var fillRule = P5FillRule.nonZero
        var shouldAntialias = true
        var blendMode = P5BlendMode.normal
        var opacity: CGFloat = 1
        var tintColor: CGColor?
    }

    var size: CGSize = .zero

    private var operations: [P5Operation] = []
    private var style = DrawingStyle()

    func addOperation(_ operation: P5Operation) {
        operations.append(operation)
    }

    func render(in context: CGContext) {
        var styleStack: [DrawingStyle] = []
        let initialTransform = context.ctm
        context.saveGState()
        defer {
            context.restoreGState()
            operations.removeAll()
        }

        for operation in operations {
            switch operation {
            case .fill(let color):
                style.fillColor = color
            case .noFill:
                style.fillColor = nil
            case .stroke(let color):
                style.strokeColor = color
            case .noStroke:
                style.strokeColor = nil
            case .strokeWeight(let weight):
                style.strokeWeight = weight
            case .strokeCap(let cap):
                style.strokeCap = cap
            case .strokeJoin(let join):
                style.strokeJoin = join
            case .strokeMiterLimit(let limit):
                style.strokeMiterLimit = limit
            case .strokeDash(let phase, let lengths):
                style.strokeDashPhase = phase
                style.strokeDashLengths = lengths
            case .fillRule(let rule):
                style.fillRule = rule
            case .antialias(let shouldAntialias):
                style.shouldAntialias = shouldAntialias
            case .blendMode(let mode):
                style.blendMode = mode
            case .opacity(let opacity):
                style.opacity = opacity
            case .tint(let color):
                style.tintColor = color
            case .noTint:
                style.tintColor = nil
            case .clear:
                clear(in: context, initialTransform: initialTransform)
            case .background(let bgColor):
                background(bgColor, in: context, initialTransform: initialTransform)
            case .line(let x1, let y1, let x2, let y2):
                line(x1, y1, x2, y2, in: context)
            case .rect(let x, let y, let w, let h):
                draw(
                    CGRect(x: x, y: y, width: w, height: h),
                    in: context
                )
            case .square(let x, let y, let extent):
                draw(
                    CGRect(x: x, y: y, width: extent, height: extent),
                    in: context
                )
            case .ellipse(let x, let y, let width, let height):
                drawEllipse(
                    CGRect(
                        x: x - width / 2,
                        y: y - height / 2,
                        width: width,
                        height: height
                    ),
                    in: context
                )
            case .point(let x, let y):
                point(x, y, in: context)
            case .polygon(let points):
                polygon(points, in: context)
            case .arc(let x, let y, let width, let height, let start, let stop, let mode):
                arc(
                    center: CGPoint(x: x, y: y),
                    width: width,
                    height: height,
                    start: start,
                    stop: stop,
                    mode: mode,
                    in: context
                )
            case .roundedRect(let x, let y, let width, let height, let cornerRadius):
                roundedRect(
                    CGRect(x: x, y: y, width: width, height: height),
                    cornerRadius: cornerRadius,
                    in: context
                )
            case .shape(let commands, let closure):
                shape(commands, closure: closure, in: context)
            case .reusableShape(let reusableShape):
                shape(reusableShape, in: context)
            case .image(let image, let source, let destination):
                drawImage(image, source: source, destination: destination, in: context)
            case .rotate(let angle):
                context.rotate(by: angle)
            case .translate(let x, let y):
                context.translateBy(x: x, y: y)
            case .scale(let x, let y):
                context.scaleBy(x: x, y: y)
            case .shearX(let amount):
                context.concatenate(CGAffineTransform(a: 1, b: 0, c: amount, d: 1, tx: 0, ty: 0))
            case .shearY(let amount):
                context.concatenate(CGAffineTransform(a: 1, b: amount, c: 0, d: 1, tx: 0, ty: 0))
            case .applyMatrix(let transform):
                context.concatenate(transform)
            case .resetMatrix:
                context.concatenate(context.ctm.inverted())
                context.concatenate(initialTransform)
            case .push:
                context.saveGState()
                styleStack.append(style)
            case .pop:
                guard let savedStyle = styleStack.popLast() else {
                    continue
                }
                context.restoreGState()
                style = savedStyle
            }
        }
    }

    private func clear(in context: CGContext, initialTransform: CGAffineTransform) {
        context.saveGState()
        restoreInitialTransform(in: context, initialTransform: initialTransform)
        context.clear(CGRect(origin: .zero, size: size))
        context.restoreGState()
    }

    private func background(
        _ color: CGColor,
        in context: CGContext,
        initialTransform: CGAffineTransform
    ) {
        context.saveGState()
        restoreInitialTransform(in: context, initialTransform: initialTransform)
        context.setFillColor(color)
        context.fill(CGRect(origin: .zero, size: size))
        context.restoreGState()
    }

    private func restoreInitialTransform(
        in context: CGContext,
        initialTransform: CGAffineTransform
    ) {
        context.concatenate(context.ctm.inverted())
        context.concatenate(initialTransform)
    }

    private func line(
        _ x1: CGFloat,
        _ y1: CGFloat,
        _ x2: CGFloat,
        _ y2: CGFloat,
        in context: CGContext
    ) {
        guard let strokeColor = style.strokeColor else {
            return
        }

        context.saveGState()
        applyStyle(to: context)
        context.setStrokeColor(strokeColor)
        context.beginPath()
        context.move(to: CGPoint(x: x1, y: y1))
        context.addLine(to: CGPoint(x: x2, y: y2))
        context.strokePath()
        context.restoreGState()
    }

    private func draw(_ rectangle: CGRect, in context: CGContext) {
        context.beginPath()
        context.addRect(rectangle)
        drawCurrentPath(in: context)
    }

    private func drawEllipse(_ rectangle: CGRect, in context: CGContext) {
        context.beginPath()
        context.addEllipse(in: rectangle)
        drawCurrentPath(in: context)
    }

    private func point(_ x: CGFloat, _ y: CGFloat, in context: CGContext) {
        guard let strokeColor = style.strokeColor else {
            return
        }
        context.saveGState()
        applyStyle(to: context)
        context.setFillColor(strokeColor)
        let diameter = style.strokeWeight
        context.fillEllipse(
            in: CGRect(x: x - diameter / 2, y: y - diameter / 2, width: diameter, height: diameter)
        )
        context.restoreGState()
    }

    private func polygon(_ points: [CGPoint], in context: CGContext) {
        guard let first = points.first else {
            return
        }
        context.beginPath()
        context.move(to: first)
        points.dropFirst().forEach(context.addLine)
        context.closePath()
        drawCurrentPath(in: context)
    }

    private func arc(
        center: CGPoint,
        width: CGFloat,
        height: CGFloat,
        start: CGFloat,
        stop: CGFloat,
        mode: P5ArcMode,
        in context: CGContext
    ) {
        let path = CGMutablePath()
        let transform = CGAffineTransform(
            translationX: center.x,
            y: center.y
        ).scaledBy(x: width / 2, y: height / 2)
        if mode == .pie {
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: cos(start), y: sin(start)), transform: transform)
        }
        path.addArc(
            center: .zero,
            radius: 1,
            startAngle: start,
            endAngle: stop,
            clockwise: false,
            transform: transform
        )
        if mode != .open {
            path.closeSubpath()
        }
        context.beginPath()
        context.addPath(path)
        drawCurrentPath(in: context)
    }

    private func roundedRect(
        _ rectangle: CGRect,
        cornerRadius: CGFloat,
        in context: CGContext
    ) {
        let radius = max(0, cornerRadius)
        context.beginPath()
        context.addPath(
            CGPath(
                roundedRect: rectangle,
                cornerWidth: radius,
                cornerHeight: radius,
                transform: nil
            )
        )
        drawCurrentPath(in: context)
    }

    private func shape(
        _ commands: [P5PathCommand],
        closure: P5ShapeClosure,
        in context: CGContext
    ) {
        shape(P5Shape(commands: commands, closure: closure), in: context)
    }

    private func shape(_ shape: P5Shape, in context: CGContext) {
        context.beginPath()
        context.addPath(shape.cgPath)
        drawCurrentPath(in: context, usesEvenOddFill: shape.fillRule == .evenOdd)
    }

    private func drawImage(
        _ image: P5Image,
        source: CGRect?,
        destination: CGRect,
        in context: CGContext
    ) {
        let sourceImage: CGImage
        if let source {
            guard let cropped = image.cgImage.cropping(to: source) else { return }
            sourceImage = cropped
        } else {
            sourceImage = image.cgImage
        }

        context.saveGState()
        applyStyle(to: context)
        context.translateBy(x: destination.minX, y: destination.maxY)
        context.scaleBy(x: 1, y: -1)
        let localRectangle = CGRect(origin: .zero, size: destination.size)
        if let tintColor = style.tintColor {
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.draw(sourceImage, in: localRectangle)
            context.setBlendMode(.sourceAtop)
            context.setFillColor(tintColor)
            context.fill(localRectangle)
            context.endTransparencyLayer()
        } else {
            context.draw(sourceImage, in: localRectangle)
        }
        context.restoreGState()
    }

    private func drawCurrentPath(in context: CGContext, usesEvenOddFill: Bool = false) {
        applyStyle(to: context)
        let usesEvenOddFill = usesEvenOddFill || style.fillRule == .evenOdd
        switch (style.fillColor, style.strokeColor) {
        case let (fillColor?, strokeColor?):
            context.setFillColor(fillColor)
            context.setStrokeColor(strokeColor)
            context.drawPath(using: usesEvenOddFill ? .eoFillStroke : .fillStroke)
        case let (fillColor?, nil):
            context.setFillColor(fillColor)
            context.drawPath(using: usesEvenOddFill ? .eoFill : .fill)
        case let (nil, strokeColor?):
            context.setStrokeColor(strokeColor)
            context.drawPath(using: .stroke)
        case (nil, nil):
            context.beginPath()
        }
    }

    private func applyStyle(to context: CGContext) {
        context.setLineWidth(style.strokeWeight)
        context.setLineCap(style.strokeCap.cgLineCap)
        context.setLineJoin(style.strokeJoin.cgLineJoin)
        context.setMiterLimit(style.strokeMiterLimit)
        context.setLineDash(phase: style.strokeDashPhase, lengths: style.strokeDashLengths)
        context.setShouldAntialias(style.shouldAntialias)
        context.setBlendMode(style.blendMode.cgBlendMode)
        context.setAlpha(style.opacity)
    }
}

private extension P5StrokeCap {
    var cgLineCap: CGLineCap {
        switch self {
        case .round:
            .round
        case .project:
            .square
        case .square:
            .butt
        }
    }
}

private extension P5StrokeJoin {
    var cgLineJoin: CGLineJoin {
        switch self {
        case .miter:
            .miter
        case .bevel:
            .bevel
        case .round:
            .round
        }
    }
}

private extension P5BlendMode {
    var cgBlendMode: CGBlendMode {
        switch self {
        case .normal:
            .normal
        case .multiply:
            .multiply
        case .screen:
            .screen
        case .add:
            .plusLighter
        case .darken:
            .darken
        case .lighten:
            .lighten
        case .difference:
            .difference
        case .exclusion:
            .exclusion
        case .replace:
            .copy
        case .overlay:
            .overlay
        case .hardLight:
            .hardLight
        case .softLight:
            .softLight
        case .colorDodge:
            .colorDodge
        case .colorBurn:
            .colorBurn
        }
    }
}
