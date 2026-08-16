import Foundation
import P5
import SwiftUI
import Testing

@MainActor
@Suite("P5 public client")
struct P5PublicAPITests {
    @Test("The P5 product exposes math APIs without testable import")
    func publicMathAPI() throws {
        let velocity = P5Vector(x: 3, y: 4)
        var random = P5RandomGenerator(seed: 5)
        let noise = P5NoiseGenerator(seed: 5)
        let clock = P5ManualClock()
        let color = try P5Color(hex: "#336699")
        let persistenceKey = P5StorageKey<Int>("frame-count")
        let preferences = P5Preferences(namespace: "PublicAPI")
        let fileStore = P5FileStore(directory: FileManager.default.temporaryDirectory)
        let controlState = P5ControlState(0.5)
        let controlOption = P5ControlOption("Flow", value: "flow")
        let slider = P5Slider(value: controlState.binding, label: "Speed")
        let picker = P5Picker(
            "Motion",
            selection: .constant("flow"),
            options: [controlOption]
        )

        #expect(velocity.mag() == 5)
        #expect(P5Vector.add(velocity, P5Vector(x: 1, y: 2)) == P5Vector(x: 4, y: 6))
        #expect(P5Math.map(0.5, from: 0, to: 1, onto: 0, to: 10) == 5)
        #expect((0..<1).contains(random.random()))
        #expect((0...1).contains(noise.noise(0.5)))
        #expect(P5ArcMode.allCases == [.open, .chord, .pie])
        #expect(P5ShapeClosure.allCases == [.open, .close])
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
        #expect(P5FrameDriver.allCases == [.automatic, .manual])
        #expect(P5PointerKind.allCases == [.mouse, .touch, .pencil, .indirect])
        #expect(P5PointerPhase.allCases.count == 8)
        #expect(P5PointerButtons.primary.rawValue == 1)
        #expect(P5ModifierKeys.command.rawValue == 8)
        #expect(P5KeyboardPhase.allCases == [.pressed, .released, .typed, .cancelled])
        #expect(P5Key.arrowUp != .arrowDown)
        #expect(clock.now == 0)
        #expect(color.alpha == 1)
        #expect(persistenceKey.name == "frame-count")
        #expect(preferences.namespace == "PublicAPI")
        #expect(fileStore.directory.isFileURL)
        #expect(controlState.value == 0.5)
        #expect(controlOption.id == "flow")
        _ = slider.body
        _ = picker.body
        _ = P5Button("Run") {}.body
        _ = P5TextField("Name", text: .constant("")).body
        _ = P5Label("Particles").body
        _ = P5Toggle("Trails", isOn: .constant(true)).body
        _ = P5ColorPicker("Tint", selection: .constant(.red)).body
    }
}
