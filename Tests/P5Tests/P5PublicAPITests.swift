import P5
import Testing

@Suite("P5 public client")
struct P5PublicAPITests {
    @Test("The P5 product exposes its vector API without testable import")
    func publicVectorAPI() {
        let velocity = P5Vector(x: 3, y: 4)

        #expect(velocity.mag() == 5)
        #expect(P5Vector.add(velocity, P5Vector(x: 1, y: 2)) == P5Vector(x: 4, y: 6))
    }
}
