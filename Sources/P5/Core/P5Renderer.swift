import CoreGraphics

final class P5Renderer {
    private struct DrawingStyle {
        var fillColor: CGColor? = CGColor(gray: 1, alpha: 1)
        var strokeColor: CGColor? = CGColor(gray: 0, alpha: 1)
        var strokeWeight: CGFloat = 1
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
            case .background(let bgColor):
                background(bgColor, in: context)
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
        operations.removeAll()
    }

    private func background(_ color: CGColor, in context: CGContext) {
        context.saveGState()
        context.setFillColor(color)
        context.fill(CGRect(origin: .zero, size: size))
        context.restoreGState()
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
        context.setStrokeColor(strokeColor)
        context.setLineWidth(style.strokeWeight)
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
        context.setFillColor(strokeColor)
        let diameter = style.strokeWeight
        context.fillEllipse(
            in: CGRect(x: x - diameter / 2, y: y - diameter / 2, width: diameter, height: diameter)
        )
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
            case .curve(let point):
                curvePoints.append(point)
            case .vertex(let point):
                flushCurvePoints()
                if hasPoint {
                    path.addLine(to: point)
                } else {
                    path.move(to: point)
                    hasPoint = true
                }
            case .bezier(let control1, let control2, let end):
                flushCurvePoints()
                path.addCurve(to: end, control1: control1, control2: control2)
                hasPoint = true
            case .quadratic(let control, let end):
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
        context.beginPath()
        context.addPath(path)
        drawCurrentPath(in: context, usesEvenOddFill: usesEvenOddFill)
    }

    private func drawCurrentPath(in context: CGContext, usesEvenOddFill: Bool = false) {
        switch (style.fillColor, style.strokeColor) {
        case let (fillColor?, strokeColor?):
            context.setFillColor(fillColor)
            context.setStrokeColor(strokeColor)
            context.setLineWidth(style.strokeWeight)
            context.drawPath(using: usesEvenOddFill ? .eoFillStroke : .fillStroke)
        case let (fillColor?, nil):
            context.setFillColor(fillColor)
            context.drawPath(using: usesEvenOddFill ? .eoFill : .fill)
        case let (nil, strokeColor?):
            context.setStrokeColor(strokeColor)
            context.setLineWidth(style.strokeWeight)
            context.drawPath(using: .stroke)
        case (nil, nil):
            context.beginPath()
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
