import CoreGraphics
import Foundation

/// A seeded, coherent Perlin-noise generator for natural-looking motion and textures.
public struct P5NoiseGenerator: Sendable {
    private static let gradients: [(CGFloat, CGFloat, CGFloat)] = [
        (1, 1, 0), (-1, 1, 0), (1, -1, 0), (-1, -1, 0),
        (1, 0, 1), (-1, 0, 1), (1, 0, -1), (-1, 0, -1),
        (0, 1, 1), (0, -1, 1), (0, 1, -1), (0, -1, -1),
        (1, 1, 0), (-1, 1, 0), (0, -1, 1), (0, -1, -1),
    ]

    private var permutation: [UInt8]
    private var octaveCount = 4
    private var octaveFalloff: CGFloat = 0.5

    /// Creates a generator with a nondeterministic system-provided seed.
    public init() {
        var system = SystemRandomNumberGenerator()
        self.init(seed: system.next())
    }

    /// Creates a repeatable coherent-noise field.
    public init(seed: UInt64) {
        permutation = []
        seedPermutation(seed)
    }

    /// Rebuilds the noise field from a deterministic seed.
    public mutating func seed(_ seed: UInt64) {
        seedPermutation(seed)
    }

    /// Sets the number of accumulated octaves and their amplitude falloff.
    ///
    /// - Parameters:
    ///   - octaves: The positive number of frequency layers.
    ///   - falloff: The amplitude multiplier for each subsequent layer, in `0...1`.
    public mutating func detail(octaves: Int, falloff: CGFloat = 0.5) {
        precondition(octaves > 0)
        precondition(falloff.isFinite && (0...1).contains(falloff))
        octaveCount = octaves
        octaveFalloff = falloff
    }

    /// Samples one-dimensional coherent noise in the closed range `0...1`.
    public func noise(_ x: CGFloat) -> CGFloat {
        noise(x, 0, 0)
    }

    /// Samples two-dimensional coherent noise in the closed range `0...1`.
    public func noise(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
        noise(x, y, 0)
    }

    /// Samples three-dimensional coherent noise in the closed range `0...1`.
    public func noise(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGFloat {
        precondition(x.isFinite && y.isFinite && z.isFinite)
        var frequency: CGFloat = 1
        var amplitude: CGFloat = 1
        var weightedNoise: CGFloat = 0
        var totalAmplitude: CGFloat = 0

        for _ in 0..<octaveCount {
            weightedNoise +=
                sample(abs(x) * frequency, abs(y) * frequency, abs(z) * frequency)
                * amplitude
            totalAmplitude += amplitude
            frequency *= 2
            amplitude *= octaveFalloff
        }

        return min(max(weightedNoise / totalAmplitude, 0), 1)
    }

    private mutating func seedPermutation(_ seed: UInt64) {
        var values = Array(UInt8.min...UInt8.max)
        var generator = P5RandomGenerator(seed: seed)
        for index in stride(from: values.count - 1, through: 1, by: -1) {
            let otherIndex = Int(generator.next() % UInt64(index + 1))
            values.swapAt(index, otherIndex)
        }
        permutation = values + values
    }

    private func sample(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGFloat {
        let xFloor = floor(x)
        let yFloor = floor(y)
        let zFloor = floor(z)
        let xIndex = Int(xFloor.truncatingRemainder(dividingBy: 256))
        let yIndex = Int(yFloor.truncatingRemainder(dividingBy: 256))
        let zIndex = Int(zFloor.truncatingRemainder(dividingBy: 256))
        let xFraction = x - xFloor
        let yFraction = y - yFloor
        let zFraction = z - zFloor
        let xFade = fade(xFraction)
        let yFade = fade(yFraction)
        let zFade = fade(zFraction)

        let aaa = hash(xIndex, yIndex, zIndex)
        let aba = hash(xIndex, yIndex + 1, zIndex)
        let aab = hash(xIndex, yIndex, zIndex + 1)
        let abb = hash(xIndex, yIndex + 1, zIndex + 1)
        let baa = hash(xIndex + 1, yIndex, zIndex)
        let bba = hash(xIndex + 1, yIndex + 1, zIndex)
        let bab = hash(xIndex + 1, yIndex, zIndex + 1)
        let bbb = hash(xIndex + 1, yIndex + 1, zIndex + 1)

        let lowerFront = interpolate(
            gradient(aaa, xFraction, yFraction, zFraction),
            gradient(baa, xFraction - 1, yFraction, zFraction),
            xFade
        )
        let upperFront = interpolate(
            gradient(aba, xFraction, yFraction - 1, zFraction),
            gradient(bba, xFraction - 1, yFraction - 1, zFraction),
            xFade
        )
        let lowerBack = interpolate(
            gradient(aab, xFraction, yFraction, zFraction - 1),
            gradient(bab, xFraction - 1, yFraction, zFraction - 1),
            xFade
        )
        let upperBack = interpolate(
            gradient(abb, xFraction, yFraction - 1, zFraction - 1),
            gradient(bbb, xFraction - 1, yFraction - 1, zFraction - 1),
            xFade
        )
        let front = interpolate(lowerFront, upperFront, yFade)
        let back = interpolate(lowerBack, upperBack, yFade)
        return (interpolate(front, back, zFade) + 1) / 2
    }

    private func hash(_ x: Int, _ y: Int, _ z: Int) -> UInt8 {
        let first = Int(permutation[x & 255]) + y
        let second = Int(permutation[first & 255]) + z
        return permutation[second & 255]
    }

    private func gradient(_ hash: UInt8, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGFloat {
        let gradient = Self.gradients[Int(hash & 15)]
        return (gradient.0 * x) + (gradient.1 * y) + (gradient.2 * z)
    }

    private func fade(_ value: CGFloat) -> CGFloat {
        value * value * value * (value * ((value * 6) - 15) + 10)
    }

    private func interpolate(_ start: CGFloat, _ stop: CGFloat, _ amount: CGFloat) -> CGFloat {
        start + (amount * (stop - start))
    }
}

public extension P5Sketch {
    /// Rebuilds the sketch's coherent-noise field from a deterministic seed.
    func noiseSeed(_ seed: UInt64) {
        noiseGenerator.seed(seed)
    }

    /// Sets the number of noise octaves and their amplitude falloff.
    func noiseDetail(_ octaves: Int, _ falloff: CGFloat = 0.5) {
        noiseGenerator.detail(octaves: octaves, falloff: falloff)
    }

    /// Samples one-dimensional coherent noise in the closed range `0...1`.
    func noise(_ x: CGFloat) -> CGFloat {
        noiseGenerator.noise(x)
    }

    /// Samples two-dimensional coherent noise in the closed range `0...1`.
    func noise(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
        noiseGenerator.noise(x, y)
    }

    /// Samples three-dimensional coherent noise in the closed range `0...1`.
    func noise(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGFloat {
        noiseGenerator.noise(x, y, z)
    }
}
