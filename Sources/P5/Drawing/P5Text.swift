import CoreGraphics
import CoreText
import Foundation

/// Failures produced while loading native font data.
public enum P5TextError: Error, Sendable, Hashable, LocalizedError {
    /// Core Graphics could not decode a font from the supplied bytes.
    case fontDecodingFailed

    /// A localized description suitable for diagnostics and user interfaces.
    public var errorDescription: String? {
        switch self {
        case .fontDecodingFailed:
            "Core Graphics could not decode the supplied font data."
        }
    }
}

/// Immutable native font geometry that can be reused at any point size.
public struct P5Font: @unchecked Sendable {
    let cgFont: CGFont

    /// PostScript name reported by Core Text.
    public let postScriptName: String
    /// Family name reported by Core Text when present.
    public let familyName: String?
    /// Full display name reported by Core Text when present.
    public let fullName: String?

    init(cgFont: CGFont, postScriptName: String, familyName: String?, fullName: String?) {
        self.cgFont = cgFont
        self.postScriptName = postScriptName
        self.familyName = familyName
        self.fullName = fullName
    }

    /// Returns Apple's system font, or Core Text's fallback for a requested name.
    public static func system(named name: String? = nil) -> P5Font {
        let font = CTFontCreateWithName((name ?? ".AppleSystemUIFont") as CFString, 12, nil)
        return from(font)
    }

    /// Decodes a font from complete OpenType, TrueType, or supported font bytes.
    public static func decode(_ data: Data) throws -> P5Font {
        try decode(
            data,
            makeProvider: CGDataProvider.init(data:),
            makeFont: CGFont.init,
            fontName: { $0.postScriptName as String? }
        )
    }

    static func decode(
        _ data: Data,
        makeProvider: (CFData) -> CGDataProvider?,
        makeFont: (CGDataProvider) -> CGFont?,
        fontName: (CGFont) -> String?
    ) throws -> P5Font {
        guard let provider = makeProvider(data as CFData), let font = makeFont(provider) else {
            throw P5TextError.fontDecodingFailed
        }
        return P5Font(
            cgFont: font,
            postScriptName: fontName(font) ?? "Unknown",
            familyName: nil,
            fullName: font.fullName as String?
        )
    }

    /// Loads and decodes a font from a local file URL.
    public static func load(from url: URL) throws -> P5Font {
        precondition(url.isFileURL)
        return try decode(Data(contentsOf: url))
    }

    func sized(_ size: CGFloat) -> CTFont {
        CTFontCreateWithGraphicsFont(cgFont, size, nil, nil)
    }

    private static func from(_ font: CTFont) -> P5Font {
        P5Font(
            cgFont: CTFontCopyGraphicsFont(font, nil),
            postScriptName: CTFontCopyPostScriptName(font) as String,
            familyName: CTFontCopyFamilyName(font) as String,
            fullName: CTFontCopyFullName(font) as String
        )
    }
}

/// Horizontal placement of text relative to its anchor or layout rectangle.
public enum P5TextHorizontalAlignment: String, Sendable, Hashable, Codable, CaseIterable {
    /// Places the leading edge at the anchor.
    case left
    /// Centers text on the anchor or inside the layout width.
    case center
    /// Places the trailing edge at the anchor or layout width.
    case right
}

/// Vertical placement of text relative to its anchor or layout rectangle.
public enum P5TextVerticalAlignment: String, Sendable, Hashable, Codable, CaseIterable {
    /// Places the typographic top at the anchor.
    case top
    /// Centers the typographic bounds on the anchor or inside the layout height.
    case center
    /// Places the first baseline at the anchor.
    case baseline
    /// Places the typographic bottom at the anchor or layout height.
    case bottom
}

/// Line-breaking policy for constrained text.
public enum P5TextWrapMode: String, Sendable, Hashable, Codable, CaseIterable {
    /// Wraps at word boundaries when possible.
    case word
    /// Wraps between individual characters.
    case character
    /// Clips text that exceeds the layout rectangle.
    case clip
}

/// Native typographic measurements for a string under the current text style.
public struct P5TextMetrics: Sendable, Hashable {
    /// Suggested top-left-origin layout bounds.
    public let bounds: CGRect
    /// Font ascent above the baseline.
    public let ascent: CGFloat
    /// Font descent below the baseline.
    public let descent: CGFloat
    /// Configured baseline-to-baseline distance.
    public let leading: CGFloat
    /// Number of Core Text lines in the suggested bounds.
    public let lineCount: Int

    init(bounds: CGRect, ascent: CGFloat, descent: CGFloat, leading: CGFloat, lineCount: Int) {
        self.bounds = bounds
        self.ascent = ascent
        self.descent = descent
        self.leading = leading
        self.lineCount = lineCount
    }
}

struct P5TextConfiguration {
    var font = P5Font.system()
    var size = CGFloat(12)
    var leading: CGFloat?
    var horizontalAlignment = P5TextHorizontalAlignment.left
    var verticalAlignment = P5TextVerticalAlignment.baseline
    var wrapMode = P5TextWrapMode.word

    var effectiveLeading: CGFloat {
        leading ?? size * 1.2
    }

    func attributedString(
        _ text: String,
        fillColor: CGColor?,
        strokeColor: CGColor?,
        strokeWeight: CGFloat
    ) -> NSAttributedString {
        let font = font.sized(size)
        var alignment: CTTextAlignment
        switch horizontalAlignment {
        case .left:
            alignment = .left
        case .center:
            alignment = .center
        case .right:
            alignment = .right
        }
        var lineBreakMode: CTLineBreakMode
        switch wrapMode {
        case .word:
            lineBreakMode = .byWordWrapping
        case .character:
            lineBreakMode = .byCharWrapping
        case .clip:
            lineBreakMode = .byClipping
        }
        var lineHeight = effectiveLeading
        let paragraphStyle = withUnsafePointer(to: &alignment) { alignmentPointer in
            withUnsafePointer(to: &lineBreakMode) { lineBreakPointer in
                withUnsafePointer(to: &lineHeight) { lineHeightPointer in
                    let settings = [
                        CTParagraphStyleSetting(
                            spec: .alignment,
                            valueSize: MemoryLayout<CTTextAlignment>.size,
                            value: alignmentPointer
                        ),
                        CTParagraphStyleSetting(
                            spec: .lineBreakMode,
                            valueSize: MemoryLayout<CTLineBreakMode>.size,
                            value: lineBreakPointer
                        ),
                        CTParagraphStyleSetting(
                            spec: .minimumLineHeight,
                            valueSize: MemoryLayout<CGFloat>.size,
                            value: lineHeightPointer
                        ),
                        CTParagraphStyleSetting(
                            spec: .maximumLineHeight,
                            valueSize: MemoryLayout<CGFloat>.size,
                            value: lineHeightPointer
                        ),
                    ]
                    return CTParagraphStyleCreate(settings, settings.count)
                }
            }
        }

        var attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTParagraphStyleAttributeName as NSAttributedString.Key: paragraphStyle,
        ]
        if let fillColor {
            attributes[kCTForegroundColorAttributeName as NSAttributedString.Key] = fillColor
        }
        if let strokeColor {
            attributes[kCTStrokeColorAttributeName as NSAttributedString.Key] = strokeColor
            let percentage = max(0.1, strokeWeight / size * 100)
            attributes[kCTStrokeWidthAttributeName as NSAttributedString.Key] =
                fillColor == nil ? percentage : -percentage
        }
        return NSAttributedString(string: text, attributes: attributes)
    }

    func metrics(for text: String, width: CGFloat?) -> P5TextMetrics {
        precondition(width.map { $0.isFinite && $0 > 0 } ?? true)
        let attributed = attributedString(
            text,
            fillColor: CGColor(gray: 0, alpha: 1),
            strokeColor: nil,
            strokeWeight: 1
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let constraint = CGSize(
            width: width ?? .greatestFiniteMagnitude,
            height: .greatestFiniteMagnitude
        )
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: attributed.length),
            nil,
            constraint,
            nil
        )
        let measuredSize = CGSize(width: ceil(suggested.width), height: ceil(suggested.height))
        let frameSize = CGSize(
            width: max(1, width ?? measuredSize.width),
            height: max(1, measuredSize.height)
        )
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributed.length),
            CGPath(rect: CGRect(origin: .zero, size: frameSize), transform: nil),
            nil
        )
        let font = font.sized(size)
        return P5TextMetrics(
            bounds: CGRect(origin: .zero, size: measuredSize),
            ascent: CTFontGetAscent(font),
            descent: CTFontGetDescent(font),
            leading: effectiveLeading,
            lineCount: CFArrayGetCount(CTFrameGetLines(frame))
        )
    }
}

public extension P5Sketch {
    /// Selects a reusable native font for subsequent text and measurement.
    func textFont(_ font: P5Font) {
        currentTextConfiguration.font = font
        queueOperation(.textFont(font))
    }

    /// Sets the font size in logical canvas points.
    func textSize(_ size: CGFloat) {
        precondition(size.isFinite && size > 0)
        currentTextConfiguration.size = size
        queueOperation(.textSize(size))
    }

    /// Sets the baseline-to-baseline distance in logical points.
    func textLeading(_ leading: CGFloat) {
        precondition(leading.isFinite && leading > 0)
        currentTextConfiguration.leading = leading
        queueOperation(.textLeading(leading))
    }

    /// Selects horizontal and vertical text alignment.
    func textAlign(
        _ horizontal: P5TextHorizontalAlignment,
        _ vertical: P5TextVerticalAlignment = .baseline
    ) {
        currentTextConfiguration.horizontalAlignment = horizontal
        currentTextConfiguration.verticalAlignment = vertical
        queueOperation(.textAlignment(horizontal, vertical))
    }

    /// Selects line breaking for constrained text.
    func textWrap(_ mode: P5TextWrapMode) {
        currentTextConfiguration.wrapMode = mode
        queueOperation(.textWrap(mode))
    }

    /// Draws an unconstrained string relative to a text-alignment anchor.
    func text(_ value: String, _ x: CGFloat, _ y: CGFloat) {
        precondition(x.isFinite && y.isFinite)
        queueOperation(.text(value, rectangle: CGRect(x: x, y: y, width: 0, height: 0)))
    }

    /// Draws and wraps a string inside a positive layout rectangle.
    func text(
        _ value: String,
        _ x: CGFloat,
        _ y: CGFloat,
        _ width: CGFloat,
        _ height: CGFloat
    ) {
        precondition([x, y, width, height].allSatisfy(\.isFinite))
        precondition(width > 0 && height > 0)
        queueOperation(
            .text(value, rectangle: CGRect(x: x, y: y, width: width, height: height))
        )
    }

    /// Measures a string under the current font, size, leading, alignment, and wrapping.
    func textBounds(_ value: String, width: CGFloat? = nil) -> P5TextMetrics {
        currentTextConfiguration.metrics(for: value, width: width)
    }
}
