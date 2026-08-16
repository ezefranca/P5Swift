import Foundation
import Testing

@testable import P5

#if canImport(AppKit)
    import AppKit
#endif

@MainActor
@Suite(.serialized)
struct P5KeyboardTests {
    @Test
    func semanticEventsMaintainHeldStateAndDispatchEveryPhase() throws {
        let sketch = RecordingKeyboardSketch(size: CGSize(width: 20, height: 20))
        let canvas = try #require(sketch.view as? P5SketchInternalView)
        let key = P5Key.character("a")

        canvas.deliverKeyboardEvent(makeEvent(.pressed, key: key, text: "a"))
        canvas.deliverKeyboardEvent(makeEvent(.pressed, key: key, text: "a", isRepeat: true))
        canvas.deliverKeyboardEvent(makeEvent(.typed, key: key, text: "a"))
        #expect(sketch.isKeyPressed)
        #expect(sketch.keyIsDown(key))
        #expect(sketch.pressedKeys == [key])

        canvas.deliverKeyboardEvent(makeEvent(.released, key: key, text: "a"))
        canvas.deliverKeyboardEvent(makeEvent(.pressed, key: .shift))
        canvas.deliverKeyboardEvent(makeEvent(.cancelled, key: .shift))

        #expect(
            sketch.receivedPhases == [.pressed, .pressed, .typed, .released, .pressed, .cancelled])
        #expect(sketch.pressedKeys.isEmpty)
        #expect(!sketch.isKeyPressed)
        #expect(!sketch.keyIsDown(key))
        #expect(sketch.latestKeyboardEvent?.phase == .cancelled)

        let baseSketch = P5Sketch(size: CGSize(width: 10, height: 10))
        let baseCanvas = try #require(baseSketch.view as? P5SketchInternalView)
        for phase in P5KeyboardPhase.allCases {
            let text = phase == .typed ? "z" : nil
            let event = makeEvent(phase, key: .character("z"), text: text)
            baseCanvas.deliverKeyboardEvent(event)
            let data = try JSONEncoder().encode(event)
            #expect(try JSONDecoder().decode(P5KeyboardEvent.self, from: data) == event)
        }
        #expect(P5KeyboardPhase.allCases == [.pressed, .released, .typed, .cancelled])
    }

    #if canImport(AppKit)
        @Test
        func appKitAdapterMapsNativeKeysModifiersTypingAndRepeat() throws {
            let sketch = RecordingKeyboardSketch(size: CGSize(width: 20, height: 20))
            let canvas = try #require(sketch.view as? P5SketchInternalView)
            let letterDown = try keyboardEvent(
                type: .keyDown,
                keyCode: 0,
                characters: "A",
                charactersIgnoringModifiers: "a",
                modifiers: .shift,
                isRepeat: true
            )
            let letterUp = try keyboardEvent(
                type: .keyUp,
                keyCode: 0,
                characters: "A",
                charactersIgnoringModifiers: "a",
                modifiers: .shift
            )
            let commandDown = try keyboardEvent(
                type: .keyDown,
                keyCode: 0,
                characters: "a",
                charactersIgnoringModifiers: "a",
                modifiers: .command
            )
            let controlDown = try keyboardEvent(
                type: .keyDown,
                keyCode: 0,
                characters: "a",
                charactersIgnoringModifiers: "a",
                modifiers: .control
            )
            let arrowDown = try keyboardEvent(
                type: .keyDown,
                keyCode: 123,
                characters: "",
                charactersIgnoringModifiers: ""
            )
            let unknownUp = try keyboardEvent(
                type: .keyUp,
                keyCode: 200,
                characters: "",
                charactersIgnoringModifiers: ""
            )

            canvas.keyDown(with: letterDown)
            canvas.keyUp(with: letterUp)
            let typedCount = sketch.receivedPhases.filter { $0 == .typed }.count
            canvas.keyDown(with: commandDown)
            canvas.keyDown(with: controlDown)
            canvas.keyDown(with: arrowDown)
            canvas.keyUp(with: unknownUp)
            #expect(sketch.receivedPhases.filter { $0 == .typed }.count == typedCount)
            #expect(sketch.receivedEvents.first?.isRepeat == true)

            let modifierCases: [(UInt16, NSEvent.ModifierFlags)] = [
                (56, .shift), (59, .control), (58, .option), (54, .command),
                (57, .capsLock), (63, .function), (200, []),
            ]
            for (keyCode, modifiers) in modifierCases {
                canvas.flagsChanged(
                    with: try keyboardEvent(
                        type: .flagsChanged,
                        keyCode: keyCode,
                        characters: "",
                        charactersIgnoringModifiers: "",
                        modifiers: modifiers
                    )
                )
                canvas.flagsChanged(
                    with: try keyboardEvent(
                        type: .flagsChanged,
                        keyCode: keyCode,
                        characters: "",
                        charactersIgnoringModifiers: ""
                    )
                )
            }

            #expect(P5SketchInternalView.nonempty(nil) == nil)
            #expect(P5SketchInternalView.nonempty("") == nil)
            #expect(P5SketchInternalView.nonempty("x") == "x")
        }

        @Test
        func appKitSemanticMappingCoversNavigationFunctionAndUnknownKeys() {
            let cases: [(UInt16, String?, P5Key)] = [
                (36, nil, .enter), (76, nil, .enter), (48, nil, .tab),
                (51, nil, .backspace), (117, nil, .delete), (53, nil, .escape),
                (49, nil, .space), (123, nil, .arrowLeft), (124, nil, .arrowRight),
                (126, nil, .arrowUp), (125, nil, .arrowDown), (115, nil, .home),
                (119, nil, .end), (116, nil, .pageUp), (121, nil, .pageDown),
                (122, nil, .function(1)), (120, nil, .function(2)),
                (99, nil, .function(3)), (118, nil, .function(4)),
                (96, nil, .function(5)), (97, nil, .function(6)),
                (98, nil, .function(7)), (100, nil, .function(8)),
                (101, nil, .function(9)), (109, nil, .function(10)),
                (103, nil, .function(11)), (111, nil, .function(12)),
                (105, nil, .function(13)), (107, nil, .function(14)),
                (113, nil, .function(15)), (106, nil, .function(16)),
                (64, nil, .function(17)), (79, nil, .function(18)),
                (80, nil, .function(19)), (90, nil, .function(20)),
                (0, "q", .character("q")), (200, nil, .unidentified(200)),
            ]
            for (code, characters, expected) in cases {
                #expect(
                    P5SketchInternalView.semanticKey(
                        forAppKitKeyCode: code,
                        characters: characters
                    ) == expected
                )
            }

            let modifierCases: [(UInt16, P5Key)] = [
                (56, .shift), (60, .shift), (59, .control), (62, .control),
                (58, .option), (61, .option), (54, .command), (55, .command),
                (57, .capsLock), (63, .functionModifier), (200, .unidentified(200)),
            ]
            let allModifiers: P5ModifierKeys = [
                .shift, .control, .option, .command, .capsLock, .function,
            ]
            for (code, expected) in modifierCases {
                let key = P5SketchInternalView.semanticModifier(forAppKitKeyCode: code)
                #expect(key == expected)
                _ = P5SketchInternalView.isModifier(key, heldIn: allModifiers)
                #expect(!P5SketchInternalView.isModifier(key, heldIn: []))
            }

            #expect(P5Key.character("x").producesTypedText)
            #expect(P5Key.space.producesTypedText)
            #expect(!P5Key.enter.producesTypedText)
            #expect(!P5Key.character("").isValid)
            #expect(!P5Key.function(25).isValid)
        }
    #endif

    @Test
    func invalidKeyboardValuesAndDecodingAreRejected() async throws {
        let valid = makeEvent(.pressed, key: .character("a"), text: "a")
        let encoded = try JSONEncoder().encode(valid)
        let encodedString = try #require(String(data: encoded, encoding: .utf8))
        let invalidData = Data(
            encodedString.replacingOccurrences(
                of: "\"timestamp\":1",
                with: "\"timestamp\":-1"
            ).utf8
        )
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(P5KeyboardEvent.self, from: invalidData)
        }

        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5KeyboardEvent(phase: .pressed, key: .character(""), timestamp: 0)
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5KeyboardEvent(phase: .pressed, key: .function(0), timestamp: 0)
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5KeyboardEvent(
                    phase: .pressed,
                    key: .character("a"),
                    characters: "",
                    timestamp: 0
                )
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5KeyboardEvent(phase: .typed, key: .character("a"), timestamp: 0)
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5KeyboardEvent(phase: .pressed, key: .enter, timestamp: -.infinity)
            }
        #endif
    }

    private func makeEvent(
        _ phase: P5KeyboardPhase,
        key: P5Key,
        text: String? = nil,
        isRepeat: Bool = false
    ) -> P5KeyboardEvent {
        P5KeyboardEvent(
            phase: phase,
            key: key,
            characters: text,
            platformKeyCode: 4,
            modifiers: [.shift],
            isRepeat: isRepeat,
            timestamp: 1
        )
    }

    #if canImport(AppKit)
        private func keyboardEvent(
            type: NSEvent.EventType,
            keyCode: UInt16,
            characters: String,
            charactersIgnoringModifiers: String,
            modifiers: NSEvent.ModifierFlags = [],
            isRepeat: Bool = false
        ) throws -> NSEvent {
            try #require(
                NSEvent.keyEvent(
                    with: type,
                    location: .zero,
                    modifierFlags: modifiers,
                    timestamp: 2,
                    windowNumber: 0,
                    context: nil,
                    characters: characters,
                    charactersIgnoringModifiers: charactersIgnoringModifiers,
                    isARepeat: isRepeat,
                    keyCode: keyCode
                )
            )
        }
    #endif
}

@MainActor
private final class RecordingKeyboardSketch: P5Sketch {
    private(set) var receivedEvents: [P5KeyboardEvent] = []

    var receivedPhases: [P5KeyboardPhase] {
        receivedEvents.map(\.phase)
    }

    override func keyPressed(_ event: P5KeyboardEvent) { receivedEvents.append(event) }
    override func keyReleased(_ event: P5KeyboardEvent) { receivedEvents.append(event) }
    override func keyTyped(_ event: P5KeyboardEvent) { receivedEvents.append(event) }
    override func keyCancelled(_ event: P5KeyboardEvent) { receivedEvents.append(event) }
}
