import CoreGraphics
import Testing

@testable import P5

@Suite
struct P5MathTests {
    @Test
    func scalarUtilitiesMatchCreativeCodingConventions() {
        #expect(P5Math.constrain(-1, 0, 10) == 0)
        #expect(P5Math.constrain(5, 0, 10) == 5)
        #expect(P5Math.constrain(11, 0, 10) == 10)
        #expect(P5Math.map(0.5, from: 0, to: 1, onto: 0, to: 10) == 5)
        #expect(P5Math.map(2, from: 0, to: 1, onto: 0, to: 10) == 20)
        #expect(P5Math.map(2, from: 0, to: 1, onto: 0, to: 10, withinBounds: true) == 10)
        #expect(P5Math.map(-1, from: 0, to: 1, onto: 10, to: 0, withinBounds: true) == 10)
        #expect(P5Math.lerp(10, 20, 0.25) == 12.5)
        #expect(P5Math.norm(15, 10, 20) == 0.5)
        #expect(P5Math.dist(0, 0, 3, 4) == 5)
        #expect(P5Math.dist(0, 0, 0, 2, 3, 6) == 7)
        #expect(P5Math.magnitude(3, 4) == 5)
        #expect(P5Math.magnitude(2, 3, 6) == 7)
        #expect(P5Math.radians(180).isApproximately(.pi))
        #expect(P5Math.degrees(.pi / 2).isApproximately(90))
    }

    @Test
    func invalidMathRangesTerminateTheProcess() async {
        await #expect(processExitsWith: .failure) {
            _ = P5Math.constrain(1, 2, 0)
        }
        await #expect(processExitsWith: .failure) {
            _ = P5Math.map(1, from: 0, to: 0, onto: 0, to: 1)
        }
    }
}

@Suite
struct P5RandomGeneratorTests {
    @Test
    func splitMixSequenceIsStableAndReseedingRestartsIt() {
        var generator = P5RandomGenerator(seed: 0)

        #expect(generator.next() == 0xE220_A839_7B1D_CDAF)
        #expect(generator.next() == 0x6E78_9E6A_A1B9_65F4)
        generator.seed(0)
        #expect(generator.next() == 0xE220_A839_7B1D_CDAF)
    }

    @Test
    func uniformRangesAndArraySelectionCoverP5Forms() throws {
        var generator = P5RandomGenerator(seed: 42)
        let unit = generator.random()
        let positive = generator.random(10)
        let negative = generator.random(-10)
        let ascending = generator.random(20, 30)
        let descending = generator.random(30, 20)
        let selection = generator.random(["a", "b", "c"])
        let selected = try #require(selection)

        #expect((0..<1).contains(unit))
        #expect((0..<10).contains(positive))
        #expect((-10..<0).contains(negative))
        #expect((20..<30).contains(ascending))
        #expect((20..<30).contains(descending))
        #expect(["a", "b", "c"].contains(selected))
        #expect(generator.random([Int]()) == nil)
        #expect(generator.random(5, 5) == 5)
    }

    @Test
    func gaussianValuesAreDeterministicAndUseTheCachedPair() {
        var first = P5RandomGenerator(seed: 123)
        var second = P5RandomGenerator(seed: 123)
        let firstPair = [
            first.randomGaussian(mean: 10, standardDeviation: 2),
            first.randomGaussian(mean: 10, standardDeviation: 2),
        ]
        let secondPair = [
            second.randomGaussian(mean: 10, standardDeviation: 2),
            second.randomGaussian(mean: 10, standardDeviation: 2),
        ]

        #expect(firstPair == secondPair)
        first.seed(123)
        #expect(first.randomGaussian(mean: 10, standardDeviation: 2) == firstPair[0])
    }

    @Test
    func systemSeededGeneratorProducesValidValues() {
        var generator = P5RandomGenerator()
        #expect((0..<1).contains(generator.random()))
    }

    @Test
    func nonfiniteRandomParametersTerminateTheProcess() async {
        await #expect(processExitsWith: .failure) {
            var generator = P5RandomGenerator(seed: 0)
            _ = generator.random(.infinity, 1)
        }
        await #expect(processExitsWith: .failure) {
            var generator = P5RandomGenerator(seed: 0)
            _ = generator.random(0, .nan)
        }
        await #expect(processExitsWith: .failure) {
            var generator = P5RandomGenerator(seed: 0)
            _ = generator.randomGaussian(mean: .infinity)
        }
        await #expect(processExitsWith: .failure) {
            var generator = P5RandomGenerator(seed: 0)
            _ = generator.randomGaussian(standardDeviation: .nan)
        }
    }
}

@Suite
struct P5NoiseGeneratorTests {
    @Test
    func seededNoiseIsRepeatableCoherentAndBounded() {
        let first = P5NoiseGenerator(seed: 99)
        let second = P5NoiseGenerator(seed: 99)
        let samples = stride(from: CGFloat(0), through: 3, by: 0.125).map(first.noise)

        #expect(samples == stride(from: CGFloat(0), through: 3, by: 0.125).map(second.noise))
        #expect(samples.allSatisfy { (0...1).contains($0) })
        #expect(Set(samples).count > 8)
        #expect(first.noise(-0.25, -0.5, -0.75) == first.noise(0.25, 0.5, 0.75))
        #expect(first.noise(0.2, 0.4) == first.noise(0.2, 0.4, 0))
    }

    @Test
    func detailAndReseedingControlTheNoiseField() {
        var generator = P5NoiseGenerator(seed: 7)
        let original = generator.noise(0.123, 0.456, 0.789)
        generator.detail(octaves: 1, falloff: 0)
        let detailed = generator.noise(0.123, 0.456, 0.789)
        generator.seed(8)
        let reseeded = generator.noise(0.123, 0.456, 0.789)
        generator.seed(7)

        #expect(original != detailed)
        #expect(detailed != reseeded)
        #expect(generator.noise(0.123, 0.456, 0.789) == detailed)
    }

    @Test
    func systemSeededNoiseProducesValidSamples() {
        let generator = P5NoiseGenerator()
        #expect((0...1).contains(generator.noise(0.25)))
    }

    @Test
    func invalidNoiseConfigurationTerminatesTheProcess() async {
        await #expect(processExitsWith: .failure) {
            var generator = P5NoiseGenerator(seed: 0)
            generator.detail(octaves: 0)
        }
        await #expect(processExitsWith: .failure) {
            var generator = P5NoiseGenerator(seed: 0)
            generator.detail(octaves: 1, falloff: .nan)
        }
        await #expect(processExitsWith: .failure) {
            var generator = P5NoiseGenerator(seed: 0)
            generator.detail(octaves: 1, falloff: -0.1)
        }
        await #expect(processExitsWith: .failure) {
            var generator = P5NoiseGenerator(seed: 0)
            generator.detail(octaves: 1, falloff: 1.1)
        }
        await #expect(processExitsWith: .failure) {
            let generator = P5NoiseGenerator(seed: 0)
            _ = generator.noise(.nan, 0, 0)
        }
        await #expect(processExitsWith: .failure) {
            let generator = P5NoiseGenerator(seed: 0)
            _ = generator.noise(0, .infinity, 0)
        }
        await #expect(processExitsWith: .failure) {
            let generator = P5NoiseGenerator(seed: 0)
            _ = generator.noise(0, 0, -.infinity)
        }
    }
}

@MainActor
@Suite(.serialized)
struct P5SketchMathTests {
    @Test
    func sketchConveniencesDelegateToDeterministicUtilities() throws {
        let sketch = P5Sketch(size: CGSize(width: 10, height: 10))

        #expect(sketch.constrain(20, 0, 10) == 10)
        #expect(sketch.map(0.5, 0, 1, 0, 10) == 5)
        #expect(sketch.map(2, 0, 1, 0, 10, true) == 10)
        #expect(sketch.lerp(0, 10, 0.2) == 2)
        #expect(sketch.norm(5, 0, 10) == 0.5)
        #expect(sketch.dist(0, 0, 3, 4) == 5)
        #expect(sketch.dist(0, 0, 0, 2, 3, 6) == 7)
        #expect(sketch.mag(3, 4) == 5)
        #expect(sketch.mag(2, 3, 6) == 7)
        #expect(sketch.radians(180).isApproximately(.pi))
        #expect(sketch.degrees(.pi).isApproximately(180))

        sketch.randomSeed(77)
        let firstRandom = sketch.random()
        _ = sketch.random(10)
        _ = sketch.random(-10, 10)
        let selection = sketch.random([1, 2, 3])
        _ = try #require(selection)
        _ = sketch.randomGaussian()
        sketch.randomSeed(77)
        #expect(sketch.random() == firstRandom)

        sketch.noiseSeed(88)
        let firstNoise = sketch.noise(0.1)
        _ = sketch.noise(0.1, 0.2)
        _ = sketch.noise(0.1, 0.2, 0.3)
        sketch.noiseDetail(2, 0.25)
        sketch.noiseSeed(88)
        #expect(sketch.noise(0.1) != firstNoise)
    }
}

private extension CGFloat {
    func isApproximately(_ other: Self, tolerance: Self = 0.000_001) -> Bool {
        abs(self - other) <= tolerance
    }
}
