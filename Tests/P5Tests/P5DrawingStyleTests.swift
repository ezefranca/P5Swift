import CoreGraphics
import Foundation
import Testing

@testable import P5

@MainActor
@Suite(.serialized)
struct P5DrawingStyleTests {
    @Test
    func coordinateModesAndStyleControlsReachTheRenderer() throws {
        let sketch = P5Sketch(size: CGSize(width: 64, height: 48))
        let bitmap = try #require(TestBitmap(width: 64, height: 48))

        sketch.fill(255, 0, 0)
        sketch.noStroke()
        sketch.rectMode(.corner)
        sketch.rect(1, 1, 5, 4)
        sketch.rectMode(.corners)
        sketch.rect(12, 1, 7, 5)
        sketch.rectMode(.center)
        sketch.rect(17, 3, 6, 4)
        sketch.square(25, 3, 4)
        sketch.rectMode(.radius)
        sketch.rect(34, 3, 3, 2)
        sketch.rect(43, 3, 3, 2, cornerRadius: 1)

        sketch.ellipseMode(.corner)
        sketch.ellipse(1, 10, 6, 4)
        sketch.ellipseMode(.corners)
        sketch.ellipse(12, 10, 7, 14)
        sketch.ellipseMode(.center)
        sketch.circle(18, 12, 5)
        sketch.ellipseMode(.radius)
        sketch.ellipse(27, 12, 3, 2)
        sketch.arc(36, 12, 3, 2, 0, .pi, .pie)

        sketch.stroke(0, 0, 255)
        sketch.noFill()
        for cap in P5StrokeCap.allCases {
            sketch.strokeCap(cap)
        }
        for join in P5StrokeJoin.allCases {
            sketch.strokeJoin(join)
        }
        sketch.strokeMiterLimit(5)
        sketch.strokeDash([3, 2], phase: 1)
        sketch.noStrokeDash()
        sketch.fillRule(.nonZero)
        sketch.fillRule(.evenOdd)
        sketch.noSmooth()
        sketch.smooth()
        for mode in P5BlendMode.allCases {
            sketch.blendMode(mode)
        }
        sketch.opacity(0.75)
        sketch.line(2, 24, 40, 24)

        drawSketch(sketch, in: bitmap)

        #expect(bitmap.pixel(atX: 2, y: 2).red > 0)
        #expect(bitmap.pixel(atX: 9, y: 2).red > 0)
        #expect(bitmap.pixel(atX: 34, y: 3).red > 0)
        #expect(bitmap.pixel(atX: 2, y: 12).red > 0)
        #expect(bitmap.pixel(atX: 20, y: 12).red > 0)
        #expect(bitmap.pixel(atX: 20, y: 24).blue > 0)

        #expect(P5RectMode.allCases == [.corner, .corners, .center, .radius])
        #expect(P5EllipseMode.allCases == [.corner, .corners, .center, .radius])
        #expect(P5StrokeCap.allCases == [.round, .project, .square])
        #expect(P5StrokeJoin.allCases == [.miter, .bevel, .round])
        #expect(P5FillRule.allCases == [.nonZero, .evenOdd])
        #expect(
            P5BlendMode.allCases == [
                .normal, .multiply, .screen, .add, .darken, .lighten, .difference, .exclusion,
                .replace, .overlay, .hardLight, .softLight, .colorDodge, .colorBurn,
            ]
        )
        let encoded = try JSONEncoder().encode(P5RectMode.radius)
        #expect(try JSONDecoder().decode(P5RectMode.self, from: encoded) == .radius)
    }

    @Test
    func invalidStyleValuesTerminateTheProcess() async {
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    P5Sketch(size: CGSize(width: 10, height: 10)).strokeMiterLimit(0)
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    P5Sketch(size: CGSize(width: 10, height: 10)).strokeDash([1], phase: .nan)
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    P5Sketch(size: CGSize(width: 10, height: 10)).strokeDash([-.infinity])
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    P5Sketch(size: CGSize(width: 10, height: 10)).strokeDash([-1])
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    P5Sketch(size: CGSize(width: 10, height: 10)).strokeDash([0, 0])
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    P5Sketch(size: CGSize(width: 10, height: 10)).opacity(.nan)
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    P5Sketch(size: CGSize(width: 10, height: 10)).opacity(-0.1)
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    P5Sketch(size: CGSize(width: 10, height: 10)).opacity(1.1)
                }
            }
        #endif
    }

}
