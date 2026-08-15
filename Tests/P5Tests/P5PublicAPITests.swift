import P5
import Testing

@Suite("P5 public client")
struct P5PublicAPITests {
    @Test("The P5 product exposes math APIs without testable import")
    func publicMathAPI() {
        let velocity = P5Vector(x: 3, y: 4)
        var random = P5RandomGenerator(seed: 5)
        let noise = P5NoiseGenerator(seed: 5)

        #expect(velocity.mag() == 5)
        #expect(P5Vector.add(velocity, P5Vector(x: 1, y: 2)) == P5Vector(x: 4, y: 6))
        #expect(P5Math.map(0.5, from: 0, to: 1, onto: 0, to: 10) == 5)
        #expect((0..<1).contains(random.random()))
        #expect((0...1).contains(noise.noise(0.5)))
        #expect(P5ArcMode.allCases == [.open, .chord, .pie])
        #expect(P5ShapeClosure.allCases == [.open, .close])
    }
}
