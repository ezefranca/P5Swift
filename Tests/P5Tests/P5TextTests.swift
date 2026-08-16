import CoreGraphics
import CoreText
import Foundation
import Testing

@testable import P5

@Suite("P5 Core Text typography", .serialized)
struct P5TextTests {
    @Test("System and file fonts expose reusable native metadata and typed failures")
    func fonts() throws {
        let system = P5Font.system()
        let named = P5Font.system(named: "Helvetica")
        #expect(system.postScriptName.isEmpty == false)
        #expect(named.postScriptName.isEmpty == false)
        #expect(system.familyName?.isEmpty == false)
        #expect(system.fullName?.isEmpty == false)
        #expect(CTFontGetSize(system.sized(24)) == 24)

        let descriptor = CTFontCopyFontDescriptor(system.sized(12))
        let fontURL = try #require(
            CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL
        )
        let data = try Data(contentsOf: fontURL)
        let decoded = try P5Font.decode(data)
        let loaded = try P5Font.load(from: fontURL)
        #expect(decoded.postScriptName.isEmpty == false)
        #expect(loaded.postScriptName == decoded.postScriptName)
        #expect(throws: P5TextError.fontDecodingFailed) {
            _ = try P5Font.decode(Data())
        }
        #expect(throws: P5TextError.fontDecodingFailed) {
            _ = try P5Font.decode(
                data,
                makeProvider: { _ in nil },
                makeFont: { _ in nil },
                fontName: { _ in nil }
            )
        }
        #expect(throws: P5TextError.fontDecodingFailed) {
            _ = try P5Font.decode(
                data,
                makeProvider: CGDataProvider.init(data:),
                makeFont: { _ in nil },
                fontName: { _ in nil }
            )
        }
        let unnamed = try P5Font.decode(
            data,
            makeProvider: CGDataProvider.init(data:),
            makeFont: CGFont.init,
            fontName: { _ in nil }
        )
        #expect(unnamed.postScriptName == "Unknown")
        #expect(P5TextError.fontDecodingFailed.errorDescription?.contains("font") == true)
    }

    @Test("Text metrics honor font size, custom leading, wrapping, and serialization")
    @MainActor
    func measurementAndConfiguration() throws {
        #expect(P5TextHorizontalAlignment.allCases == [.left, .center, .right])
        #expect(P5TextVerticalAlignment.allCases == [.top, .center, .baseline, .bottom])
        #expect(P5TextWrapMode.allCases == [.word, .character, .clip])
        for horizontal in P5TextHorizontalAlignment.allCases {
            #expect(
                try JSONDecoder().decode(
                    P5TextHorizontalAlignment.self,
                    from: JSONEncoder().encode(horizontal)
                ) == horizontal
            )
        }
        for vertical in P5TextVerticalAlignment.allCases {
            #expect(
                try JSONDecoder().decode(
                    P5TextVerticalAlignment.self,
                    from: JSONEncoder().encode(vertical)
                ) == vertical
            )
        }
        for wrap in P5TextWrapMode.allCases {
            #expect(
                try JSONDecoder().decode(
                    P5TextWrapMode.self,
                    from: JSONEncoder().encode(wrap)
                ) == wrap
            )
        }

        let sketch = P5Sketch(size: CGSize(width: 100, height: 80))
        sketch.textFont(.system(named: "Helvetica"))
        sketch.textSize(20)
        let automatic = sketch.textBounds("Native text")
        #expect(automatic.bounds.width > 0)
        #expect(automatic.ascent > 0)
        #expect(automatic.descent >= 0)
        #expect(automatic.leading == 24)
        #expect(automatic.lineCount == 1)

        sketch.textLeading(30)
        sketch.textWrap(.character)
        sketch.textAlign(.center, .top)
        let wrapped = sketch.textBounds("one two three four", width: 35)
        #expect(wrapped.bounds.width <= 35)
        #expect(wrapped.bounds.height > automatic.bounds.height)
        #expect(wrapped.leading == 30)
        #expect(wrapped.lineCount > 1)

        sketch.push()
        sketch.textSize(8)
        sketch.textLeading(9)
        sketch.pop()
        #expect(sketch.textBounds("M").leading == 30)
        #expect(sketch.textBounds("").lineCount == 0)
    }

    @Test("Core Text draws all alignment, wrapping, fill, and stroke paths")
    @MainActor
    func rendering() throws {
        let graphics = try P5Graphics(size: CGSize(width: 160, height: 120))
        graphics.clear()
        graphics.textFont(.system(named: "Helvetica"))
        graphics.textSize(14)
        graphics.textLeading(18)
        graphics.fill(P5Color(red: 1, green: 1, blue: 1))
        graphics.stroke(P5Color(red: 1, green: 0, blue: 0))
        graphics.strokeWeight(1)

        let horizontal: [P5TextHorizontalAlignment] = [.left, .center, .right, .left]
        for (index, vertical) in P5TextVerticalAlignment.allCases.enumerated() {
            graphics.textAlign(horizontal[index], vertical)
            graphics.text("Text", 40 + CGFloat(index) * 30, 18 + CGFloat(index) * 20)
        }

        for (index, wrap) in P5TextWrapMode.allCases.enumerated() {
            graphics.textWrap(wrap)
            graphics.textAlign(.left, P5TextVerticalAlignment.allCases[index])
            graphics.text("wrapped native text", CGFloat(index) * 52, 70, 48, 40)
        }
        graphics.textAlign(.left, .bottom)
        graphics.text("short", 110, 70, 45, 8)

        graphics.noFill()
        graphics.strokeWeight(0.001)
        graphics.text("outline", 5, 115)
        graphics.noStroke()
        graphics.text("hidden", 80, 115)

        let pixels = try graphics.snapshot().pixelBuffer()
        #expect(stride(from: 3, to: pixels.bytes.count, by: 4).contains { pixels.bytes[$0] > 0 })
    }

    @Test("Invalid typography values terminate at public boundaries")
    func invalidValuesTerminateTheProcess() async {
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = try! P5Font.load(from: URL(string: "https://example.com/font.ttf")!)
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    P5Sketch(size: CGSize(width: 10, height: 10)).textSize(0)
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    P5Sketch(size: CGSize(width: 10, height: 10)).textLeading(.nan)
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    P5Sketch(size: CGSize(width: 10, height: 10)).text("x", .infinity, 0)
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    P5Sketch(size: CGSize(width: 10, height: 10)).text("x", 0, 0, 0, 1)
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    _ = P5Sketch(size: CGSize(width: 10, height: 10)).textBounds("x", width: 0)
                }
            }
        #endif
    }
}
