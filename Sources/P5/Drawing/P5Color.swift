import CoreGraphics
import Foundation

/// A color space supported by ``P5Color``.
public enum P5ColorSpace: String, Sendable, Hashable, Codable, CaseIterable {
    /// The standard RGB color space used for web and SDR Apple content.
    case sRGB

    /// Apple's wide-gamut Display P3 color space.
    case displayP3
}

/// The component model used when a sketch creates numeric colors.
public enum P5ColorMode: String, Sendable, Hashable, Codable, CaseIterable {
    /// Red, green, and blue components in the sRGB color space.
    case rgb

    /// Hue, saturation, and brightness components converted to sRGB.
    case hsb

    /// Red, green, and blue components in the Display P3 color space.
    case displayP3
}

/// Errors produced while parsing a native p5 color.
public enum P5ColorError: Error, Sendable, Hashable, LocalizedError {
    /// A string was not a supported three-, four-, six-, or eight-digit hexadecimal color.
    case invalidHex(String)

    /// A localized description suitable for diagnostics and UI.
    public var errorDescription: String? {
        switch self {
        case .invalidHex(let value):
            "Invalid hexadecimal color '\(value)'."
        }
    }
}

/// A value-semantic RGBA color for creative coding and Core Graphics rendering.
///
/// Components are stored in normalized `0...1` ranges. The value is `Codable`,
/// `Sendable`, and independent of UIKit or AppKit.
public struct P5Color: Sendable, Hashable, Codable {
    /// The normalized red component.
    public let red: CGFloat

    /// The normalized green component.
    public let green: CGFloat

    /// The normalized blue component.
    public let blue: CGFloat

    /// The normalized alpha component.
    public let alpha: CGFloat

    /// The RGB color space of the stored components.
    public let colorSpace: P5ColorSpace

    /// Creates a color from normalized RGB components.
    public init(
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        alpha: CGFloat = 1,
        colorSpace: P5ColorSpace = .sRGB
    ) {
        precondition(Self.isNormalized(red))
        precondition(Self.isNormalized(green))
        precondition(Self.isNormalized(blue))
        precondition(Self.isNormalized(alpha))
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
        self.colorSpace = colorSpace
    }

    /// Creates a normalized grayscale color.
    public init(gray: CGFloat, alpha: CGFloat = 1) {
        self.init(red: gray, green: gray, blue: gray, alpha: alpha)
    }

    /// Creates an sRGB color from normalized hue, saturation, and brightness.
    public init(hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat = 1) {
        precondition(Self.isNormalized(hue))
        precondition(Self.isNormalized(saturation))
        precondition(Self.isNormalized(brightness))
        precondition(Self.isNormalized(alpha))

        let scaledHue = hue == 1 ? 0 : hue * 6
        let sector = Int(floor(scaledHue))
        let fraction = scaledHue - CGFloat(sector)
        let minimum = brightness * (1 - saturation)
        let descending = brightness * (1 - (saturation * fraction))
        let ascending = brightness * (1 - (saturation * (1 - fraction)))
        let components: (CGFloat, CGFloat, CGFloat)
        switch sector {
        case 0:
            components = (brightness, ascending, minimum)
        case 1:
            components = (descending, brightness, minimum)
        case 2:
            components = (minimum, brightness, ascending)
        case 3:
            components = (minimum, descending, brightness)
        case 4:
            components = (ascending, minimum, brightness)
        default:
            components = (brightness, minimum, descending)
        }
        self.init(
            red: components.0,
            green: components.1,
            blue: components.2,
            alpha: alpha
        )
    }

    /// Parses `#RGB`, `#RGBA`, `#RRGGBB`, or `#RRGGBBAA` notation.
    public init(hex: String) throws {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard let value = UInt64(digits, radix: 16) else {
            throw P5ColorError.invalidHex(hex)
        }

        let components: (UInt64, UInt64, UInt64, UInt64)
        switch digits.count {
        case 3, 4:
            let red = (value >> (digits.count == 3 ? 8 : 12)) & 0xF
            let green = (value >> (digits.count == 3 ? 4 : 8)) & 0xF
            let blue = (value >> (digits.count == 3 ? 0 : 4)) & 0xF
            let alpha = digits.count == 3 ? 0xF : value & 0xF
            components = (red * 17, green * 17, blue * 17, alpha * 17)
        case 6, 8:
            let red = (value >> (digits.count == 6 ? 16 : 24)) & 0xFF
            let green = (value >> (digits.count == 6 ? 8 : 16)) & 0xFF
            let blue = (value >> (digits.count == 6 ? 0 : 8)) & 0xFF
            let alpha = digits.count == 6 ? 0xFF : value & 0xFF
            components = (red, green, blue, alpha)
        default:
            throw P5ColorError.invalidHex(hex)
        }
        self.init(
            red: CGFloat(components.0) / 255,
            green: CGFloat(components.1) / 255,
            blue: CGFloat(components.2) / 255,
            alpha: CGFloat(components.3) / 255
        )
    }

    /// The hue component normalized to `0...1`.
    public var hue: CGFloat {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        guard delta != 0 else {
            return 0
        }
        let sector: CGFloat
        if maximum == red {
            sector = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maximum == green {
            sector = ((blue - red) / delta) + 2
        } else {
            sector = ((red - green) / delta) + 4
        }
        let normalized = sector / 6
        return normalized < 0 ? normalized + 1 : normalized
    }

    /// The saturation component normalized to `0...1`.
    public var saturation: CGFloat {
        let maximum = max(red, green, blue)
        guard maximum != 0 else {
            return 0
        }
        return (maximum - min(red, green, blue)) / maximum
    }

    /// The brightness component normalized to `0...1`.
    public var brightness: CGFloat {
        max(red, green, blue)
    }

    /// The WCAG relative luminance of the RGB components.
    public var relativeLuminance: CGFloat {
        func linearize(_ component: CGFloat) -> CGFloat {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return (0.2126 * linearize(red)) + (0.7152 * linearize(green))
            + (0.0722 * linearize(blue))
    }

    /// Returns the WCAG contrast ratio against another color.
    public func contrastRatio(with other: Self) -> CGFloat {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Interpolates components toward another color with a clamped amount.
    public func interpolated(to other: Self, amount: CGFloat) -> Self {
        let amount = P5Math.constrain(amount, 0, 1)
        return Self(
            red: P5Math.lerp(red, other.red, amount),
            green: P5Math.lerp(green, other.green, amount),
            blue: P5Math.lerp(blue, other.blue, amount),
            alpha: P5Math.lerp(alpha, other.alpha, amount),
            colorSpace: amount < 0.5 ? colorSpace : other.colorSpace
        )
    }

    /// A Core Graphics color suitable for the P5 renderer.
    public var cgColor: CGColor {
        let fallback = CGColor(red: red, green: green, blue: blue, alpha: alpha)
        if colorSpace == .displayP3,
            let space = CGColorSpace(name: CGColorSpace.displayP3),
            let color = CGColor(colorSpace: space, components: [red, green, blue, alpha])
        {
            return color
        }
        return fallback
    }

    private static func isNormalized(_ value: CGFloat) -> Bool {
        value.isFinite && (0...1).contains(value)
    }
}

struct P5ColorConfiguration {
    var mode = P5ColorMode.rgb
    var maximum1: CGFloat = 255
    var maximum2: CGFloat = 255
    var maximum3: CGFloat = 255
    var maximumAlpha: CGFloat = 255

    mutating func configure(
        mode: P5ColorMode,
        maximum1: CGFloat,
        maximum2: CGFloat,
        maximum3: CGFloat,
        maximumAlpha: CGFloat
    ) {
        precondition(
            [maximum1, maximum2, maximum3, maximumAlpha].allSatisfy { $0.isFinite && $0 > 0 })
        self.mode = mode
        self.maximum1 = maximum1
        self.maximum2 = maximum2
        self.maximum3 = maximum3
        self.maximumAlpha = maximumAlpha
    }

    func grayscale(_ gray: CGFloat, alpha: CGFloat?) -> P5Color {
        P5Color(
            gray: normalize(gray, maximum: maximum1),
            alpha: normalize(alpha ?? maximumAlpha, maximum: maximumAlpha)
        )
    }

    func color(_ first: CGFloat, _ second: CGFloat, _ third: CGFloat, alpha: CGFloat?) -> P5Color {
        let first = normalize(first, maximum: maximum1)
        let second = normalize(second, maximum: maximum2)
        let third = normalize(third, maximum: maximum3)
        let alpha = normalize(alpha ?? maximumAlpha, maximum: maximumAlpha)
        switch mode {
        case .rgb:
            return P5Color(red: first, green: second, blue: third, alpha: alpha)
        case .hsb:
            return P5Color(hue: first, saturation: second, brightness: third, alpha: alpha)
        case .displayP3:
            return P5Color(
                red: first,
                green: second,
                blue: third,
                alpha: alpha,
                colorSpace: .displayP3
            )
        }
    }

    private func normalize(_ value: CGFloat, maximum: CGFloat) -> CGFloat {
        P5Math.constrain(value / maximum, 0, 1)
    }
}

public extension P5Sketch {
    /// Selects a numeric color model with one shared component maximum.
    func colorMode(_ mode: P5ColorMode, maximum: CGFloat = 255) {
        colorMode(mode, maximum, maximum, maximum, maximum)
    }

    /// Selects a numeric color model and independent component maxima.
    func colorMode(
        _ mode: P5ColorMode,
        _ maximum1: CGFloat,
        _ maximum2: CGFloat,
        _ maximum3: CGFloat,
        _ maximumAlpha: CGFloat
    ) {
        colorConfiguration.configure(
            mode: mode,
            maximum1: maximum1,
            maximum2: maximum2,
            maximum3: maximum3,
            maximumAlpha: maximumAlpha
        )
    }

    /// Creates a grayscale color using the sketch's configured ranges.
    func color(_ gray: CGFloat, _ alpha: CGFloat? = nil) -> P5Color {
        colorConfiguration.grayscale(gray, alpha: alpha)
    }

    /// Creates a color using the sketch's configured model and ranges.
    func color(
        _ first: CGFloat,
        _ second: CGFloat,
        _ third: CGFloat,
        _ alpha: CGFloat? = nil
    ) -> P5Color {
        colorConfiguration.color(first, second, third, alpha: alpha)
    }

    /// Parses a hexadecimal sRGB color.
    func color(_ hex: String) throws -> P5Color {
        try P5Color(hex: hex)
    }

    /// Paints the canvas with a native p5 color.
    func background(_ color: P5Color) {
        background(color.cgColor)
    }

    /// Paints the canvas with a numeric grayscale color.
    func background(_ gray: CGFloat, _ alpha: CGFloat? = nil) {
        background(color(gray, alpha))
    }

    /// Paints the canvas with a numeric color in the configured model.
    func background(
        _ first: CGFloat,
        _ second: CGFloat,
        _ third: CGFloat,
        _ alpha: CGFloat? = nil
    ) {
        background(color(first, second, third, alpha))
    }

    /// Sets the fill to a native p5 color.
    func fill(_ color: P5Color) {
        fill(color.cgColor)
    }

    /// Sets the fill to a numeric grayscale color.
    func fill(_ gray: CGFloat, _ alpha: CGFloat? = nil) {
        fill(color(gray, alpha))
    }

    /// Sets the fill to a numeric color in the configured model.
    func fill(
        _ first: CGFloat,
        _ second: CGFloat,
        _ third: CGFloat,
        _ alpha: CGFloat? = nil
    ) {
        fill(color(first, second, third, alpha))
    }

    /// Sets the stroke to a native p5 color.
    func stroke(_ color: P5Color) {
        stroke(color.cgColor)
    }

    /// Sets the stroke to a numeric grayscale color.
    func stroke(_ gray: CGFloat, _ alpha: CGFloat? = nil) {
        stroke(color(gray, alpha))
    }

    /// Sets the stroke to a numeric color in the configured model.
    func stroke(
        _ first: CGFloat,
        _ second: CGFloat,
        _ third: CGFloat,
        _ alpha: CGFloat? = nil
    ) {
        stroke(color(first, second, third, alpha))
    }

    /// Interpolates between two colors.
    func lerpColor(_ first: P5Color, _ second: P5Color, _ amount: CGFloat) -> P5Color {
        first.interpolated(to: second, amount: amount)
    }
}
