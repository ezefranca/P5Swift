import CoreGraphics
import Foundation
import Testing

@testable import P5

@Suite
struct P5ColorTests {
    @Test
    func normalizedRGBAndGrayscaleValuesBridgeToCoreGraphics() {
        let color = P5Color(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.8)
        let gray = P5Color(gray: 0.4, alpha: 0.6)
        let wide = P5Color(
            red: 0.1,
            green: 0.2,
            blue: 0.3,
            colorSpace: .displayP3
        )

        #expect(color.red == 0.25)
        #expect(color.green == 0.5)
        #expect(color.blue == 0.75)
        #expect(color.alpha == 0.8)
        #expect(color.colorSpace == .sRGB)
        #expect(gray.red == 0.4)
        #expect(gray.green == 0.4)
        #expect(gray.blue == 0.4)
        #expect(wide.colorSpace == .displayP3)
        #expect(color.cgColor.alpha == 0.8)
        #expect(wide.cgColor.alpha == 1)
    }

    @Test
    func everyHSBSectorConvertsToExpectedRGB() {
        let colors = stride(from: CGFloat(0), through: 1, by: 1 / 6).map {
            P5Color(hue: $0, saturation: 1, brightness: 1)
        }

        #expect(colors[0] == P5Color(red: 1, green: 0, blue: 0))
        #expect(colors[1] == P5Color(red: 1, green: 1, blue: 0))
        #expect(colors[2] == P5Color(red: 0, green: 1, blue: 0))
        #expect(colors[3] == P5Color(red: 0, green: 1, blue: 1))
        #expect(colors[4] == P5Color(red: 0, green: 0, blue: 1))
        #expect(colors[5] == P5Color(red: 1, green: 0, blue: 1))
        #expect(colors[6] == colors[0])
        #expect(P5Color(hue: 0.2, saturation: 0, brightness: 0.5) == P5Color(gray: 0.5))
    }

    @Test
    func hexadecimalFormsParseAndRejectMalformedInput() throws {
        #expect(
            try P5Color(hex: "#abc")
                == P5Color(red: 0xAA / 255, green: 0xBB / 255, blue: 0xCC / 255))
        #expect(
            try P5Color(hex: "#abcd")
                == P5Color(
                    red: 0xAA / 255,
                    green: 0xBB / 255,
                    blue: 0xCC / 255,
                    alpha: 0xDD / 255
                )
        )
        #expect(
            try P5Color(hex: "112233")
                == P5Color(red: 0x11 / 255, green: 0x22 / 255, blue: 0x33 / 255))
        #expect(
            try P5Color(hex: "11223344")
                == P5Color(
                    red: 0x11 / 255,
                    green: 0x22 / 255,
                    blue: 0x33 / 255,
                    alpha: 0x44 / 255
                )
        )
        #expect(throws: P5ColorError.invalidHex("#12")) {
            try P5Color(hex: "#12")
        }
        #expect(throws: P5ColorError.invalidHex("#xyz")) {
            try P5Color(hex: "#xyz")
        }
        #expect(
            P5ColorError.invalidHex("bad").errorDescription == "Invalid hexadecimal color 'bad'.")
    }

    @Test
    func componentExtractionLuminanceContrastAndInterpolationAreStable() {
        let black = P5Color(gray: 0)
        let white = P5Color(gray: 1, alpha: 0.5)
        let red = P5Color(red: 1, green: 0, blue: 0)
        let green = P5Color(red: 0, green: 1, blue: 0)
        let blue = P5Color(red: 0, green: 0, blue: 1)
        let magenta = P5Color(red: 1, green: 0, blue: 0.5)

        #expect(black.hue == 0)
        #expect(black.saturation == 0)
        #expect(black.brightness == 0)
        #expect(red.hue == 0)
        #expect(green.hue.isApproximately(1 / 3))
        #expect(blue.hue.isApproximately(2 / 3))
        #expect(magenta.hue.isApproximately(11 / 12))
        #expect(red.saturation == 1)
        #expect(white.brightness == 1)
        #expect(black.relativeLuminance == 0)
        #expect(white.relativeLuminance.isApproximately(1))
        #expect(black.contrastRatio(with: white).isApproximately(21))

        let wideWhite = P5Color(
            red: 1,
            green: 1,
            blue: 1,
            alpha: 0.5,
            colorSpace: .displayP3
        )
        #expect(black.interpolated(to: wideWhite, amount: -1) == black)
        #expect(black.interpolated(to: wideWhite, amount: 2) == wideWhite)
        #expect(black.interpolated(to: wideWhite, amount: 0.25).colorSpace == .sRGB)
        #expect(black.interpolated(to: wideWhite, amount: 0.75).colorSpace == .displayP3)
    }

    @Test
    func colorModelsRoundTripThroughCodable() throws {
        let colors = [
            P5Color(red: 0.1, green: 0.2, blue: 0.3),
            P5Color(red: 0.4, green: 0.5, blue: 0.6, colorSpace: .displayP3),
        ]
        let data = try JSONEncoder().encode(colors)

        #expect(try JSONDecoder().decode([P5Color].self, from: data) == colors)
        #expect(P5ColorSpace.allCases == [.sRGB, .displayP3])
        #expect(P5ColorMode.allCases == [.rgb, .hsb, .displayP3])
    }

    @Test
    func invalidNormalizedComponentsTerminateTheProcess() async {
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5Color(red: -.infinity, green: 0, blue: 0)
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5Color(red: 0, green: 2, blue: 0)
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5Color(red: 0, green: 0, blue: .nan)
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5Color(red: 0, green: 0, blue: 0, alpha: -1)
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5Color(hue: 2, saturation: 0, brightness: 0)
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5Color(hue: 0, saturation: 2, brightness: 0)
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5Color(hue: 0, saturation: 0, brightness: 2)
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5Color(hue: 0, saturation: 0, brightness: 0, alpha: 2)
            }
        #endif
    }
}

@MainActor
@Suite(.serialized)
struct P5SketchColorTests {
    @Test
    func sketchColorModesAndDrawingOverloadsUseConfiguredRanges() throws {
        let sketch = P5Sketch(size: CGSize(width: 12, height: 12))
        let bitmap = try #require(TestBitmap(width: 12, height: 12))

        #expect(sketch.color(128).red.isApproximately(128 / 255))
        #expect(sketch.color(255, 0).alpha == 0)
        #expect(sketch.color(255, 0, 0) == P5Color(red: 1, green: 0, blue: 0))
        #expect(try sketch.color("#00ff00") == P5Color(red: 0, green: 1, blue: 0))

        sketch.colorMode(.hsb, maximum: 360)
        #expect(
            sketch.color(120, 360, 360, 180)
                == P5Color(red: 0, green: 1, blue: 0, alpha: 0.5)
        )
        sketch.colorMode(.displayP3, 1, 1, 1, 1)
        let wide = sketch.color(2, -1, 0.5, 1)
        #expect(wide == P5Color(red: 1, green: 0, blue: 0.5, colorSpace: .displayP3))

        sketch.background(P5Color(gray: 0))
        sketch.background(0.25)
        sketch.background(1, 0, 0, 1)
        sketch.fill(P5Color(red: 1, green: 0, blue: 0))
        sketch.fill(0.5, 0.25)
        sketch.fill(0, 1, 0, 1)
        sketch.stroke(P5Color(red: 0, green: 0, blue: 1))
        sketch.stroke(0.5, 0.25)
        sketch.stroke(0, 0, 1, 1)
        sketch.rect(2, 2, 8, 8)

        let midpoint = sketch.lerpColor(P5Color(gray: 0), P5Color(gray: 1), 0.5)
        #expect(midpoint == P5Color(gray: 0.5))

        drawSketch(sketch, in: bitmap)
        #expect(bitmap.pixel(atX: 6, y: 6).green > 0)
    }

    @Test
    func invalidColorRangeTerminatesTheProcess() async {
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    P5Sketch(size: CGSize(width: 10, height: 10)).colorMode(.rgb, maximum: 0)
                }
            }
        #endif
    }

}

private extension CGFloat {
    func isApproximately(_ other: Self, tolerance: Self = 0.000_001) -> Bool {
        abs(self - other) <= tolerance
    }
}
