import CoreGraphics
import Foundation

/// A deterministic random-number generator for repeatable creative-coding simulations.
///
/// The generator uses SplitMix64, so a given seed produces the same sequence on
/// every supported Apple platform and Swift toolchain.
public struct P5RandomGenerator: RandomNumberGenerator, Sendable, Hashable, Codable {
    private var state: UInt64
    private var spareGaussian: CGFloat?

    /// Creates a generator with a nondeterministic system-provided seed.
    public init() {
        var system = SystemRandomNumberGenerator()
        self.init(seed: system.next())
    }

    /// Creates a deterministic generator.
    ///
    /// - Parameter seed: The seed that identifies the generated sequence.
    public init(seed: UInt64) {
        state = seed
        spareGaussian = nil
    }

    /// Restarts the deterministic sequence from a seed.
    public mutating func seed(_ seed: UInt64) {
        state = seed
        spareGaussian = nil
    }

    /// Returns the next uniformly distributed 64-bit value.
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    /// Returns a uniform value in the half-open range `0..<1`.
    public mutating func random() -> CGFloat {
        let significand = next() >> 11
        return CGFloat(Double(significand) * 0x1.0p-53)
    }

    /// Returns a uniform value between zero and an upper endpoint.
    ///
    /// A negative endpoint produces values in `upperBound..<0`.
    public mutating func random(_ upperBound: CGFloat) -> CGFloat {
        random(0, upperBound)
    }

    /// Returns a uniform value between two endpoints, independent of their order.
    public mutating func random(_ first: CGFloat, _ second: CGFloat) -> CGFloat {
        precondition(first.isFinite && second.isFinite)
        let lowerBound = min(first, second)
        let upperBound = max(first, second)
        return lowerBound + random() * (upperBound - lowerBound)
    }

    /// Selects a uniformly distributed element, or returns `nil` for an empty array.
    public mutating func random<Element>(_ values: [Element]) -> Element? {
        guard !values.isEmpty else {
            return nil
        }
        let index = Int(random() * CGFloat(values.count))
        return values[index]
    }

    /// Selects an element according to nonnegative relative weights.
    ///
    /// Zero-weight elements are never selected. Weights do not need to sum to one.
    ///
    /// - Parameters:
    ///   - values: Candidate values in stable selection order.
    ///   - weights: One finite, nonnegative relative weight per candidate.
    /// - Returns: A weighted element, or `nil` when both arrays are empty.
    /// - Precondition: The arrays have equal counts, every weight is finite and
    ///   nonnegative, and a nonempty collection has a positive finite total weight.
    public mutating func randomWeighted<Element>(
        _ values: [Element],
        weights: [CGFloat]
    ) -> Element? {
        precondition(values.count == weights.count)
        guard !values.isEmpty else { return nil }
        precondition(weights.allSatisfy { $0.isFinite && $0 >= 0 })
        let total = weights.reduce(0, +)
        precondition(total.isFinite && total > 0)

        var remaining = random() * total
        for index in values.indices.dropLast() {
            if remaining < weights[index] {
                return values[index]
            }
            remaining -= weights[index]
        }
        return values[values.index(before: values.endIndex)]
    }

    /// Returns an exponentially distributed nonnegative value.
    ///
    /// - Parameter rate: A finite positive event rate whose reciprocal is the mean.
    /// - Returns: A sample generated with inverse-transform sampling.
    /// - Precondition: `rate` is finite and greater than zero.
    public mutating func randomExponential(rate: CGFloat = 1) -> CGFloat {
        precondition(rate.isFinite && rate > 0)
        return -log1p(-random()) / rate
    }

    /// Returns a normally distributed value using the Box-Muller transform.
    ///
    /// - Parameters:
    ///   - mean: The center of the distribution.
    ///   - standardDeviation: The distribution's scale.
    /// - Returns: A normally distributed value.
    public mutating func randomGaussian(
        mean: CGFloat = 0,
        standardDeviation: CGFloat = 1
    ) -> CGFloat {
        precondition(mean.isFinite && standardDeviation.isFinite)
        if let spareGaussian {
            self.spareGaussian = nil
            return mean + (spareGaussian * standardDeviation)
        }

        let radius = sqrt(-2 * log(1 - random()))
        let angle = 2 * CGFloat.pi * random()
        let first = radius * cos(angle)
        spareGaussian = radius * sin(angle)
        return mean + (first * standardDeviation)
    }
}

public extension P5Sketch {
    /// Restarts the sketch's random sequence from a deterministic seed.
    func randomSeed(_ seed: UInt64) {
        randomGenerator.seed(seed)
    }

    /// Returns a uniform value in the half-open range `0..<1`.
    func random() -> CGFloat {
        randomGenerator.random()
    }

    /// Returns a uniform value between zero and an upper endpoint.
    func random(_ upperBound: CGFloat) -> CGFloat {
        randomGenerator.random(upperBound)
    }

    /// Returns a uniform value between two endpoints, independent of their order.
    func random(_ first: CGFloat, _ second: CGFloat) -> CGFloat {
        randomGenerator.random(first, second)
    }

    /// Selects a uniformly distributed element, or returns `nil` for an empty array.
    func random<Element>(_ values: [Element]) -> Element? {
        randomGenerator.random(values)
    }

    /// Selects an element according to nonnegative relative weights.
    ///
    /// - Parameters:
    ///   - values: Candidate values in stable selection order.
    ///   - weights: One finite, nonnegative relative weight per candidate.
    /// - Returns: A weighted element, or `nil` when both arrays are empty.
    func randomWeighted<Element>(
        _ values: [Element],
        weights: [CGFloat]
    ) -> Element? {
        randomGenerator.randomWeighted(values, weights: weights)
    }

    /// Returns an exponentially distributed nonnegative value.
    ///
    /// - Parameter rate: A finite positive event rate whose reciprocal is the mean.
    /// - Returns: A sample generated with inverse-transform sampling.
    func randomExponential(rate: CGFloat = 1) -> CGFloat {
        randomGenerator.randomExponential(rate: rate)
    }

    /// Returns a normally distributed value using the Box-Muller transform.
    func randomGaussian(mean: CGFloat = 0, standardDeviation: CGFloat = 1) -> CGFloat {
        randomGenerator.randomGaussian(mean: mean, standardDeviation: standardDeviation)
    }
}
