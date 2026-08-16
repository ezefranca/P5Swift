import SwiftUI
import Testing

@testable import P5

#if canImport(AppKit)
    import AppKit
#endif

@MainActor
@Suite("P5 native controls", .serialized)
struct P5ControlsTests {
    @Test("Observable state and SwiftUI controls retain native bindings")
    func swiftUIControls() {
        let number = P5ControlState(0.25)
        #expect(number.value == 0.25)
        let numberBinding = number.binding
        numberBinding.wrappedValue = 0.75
        #expect(number.value == 0.75)

        let first = P5ControlOption("First", value: 1)
        let second = P5ControlOption("Second", value: 2)
        #expect(first.id == 1)
        #expect(first.title == "First")
        #expect(first.value == 1)
        #expect(Set([first, P5ControlOption("First", value: 1)]).count == 1)

        var buttonPresses = 0
        let button = P5Button("Run", role: .destructive) { buttonPresses += 1 }
        _ = button.body
        #expect(buttonPresses == 0)

        let steppedSlider = P5Slider(
            value: numberBinding,
            in: 0...1,
            step: 0.1,
            label: "Speed"
        )
        _ = steppedSlider.body
        let defaultSlider = P5Slider(value: numberBinding)
        _ = defaultSlider.body
        defaultSlider.onEditingChanged(false)

        let text = P5ControlState("Ada")
        _ = P5TextField("Name", text: text.binding, prompt: "Your name").body
        let defaultTextField = P5TextField("Name", text: text.binding)
        _ = defaultTextField.body
        defaultTextField.onSubmit()
        _ = P5Label("Particles").body

        let enabled = P5ControlState(true)
        _ = P5Toggle("Trails", isOn: enabled.binding).body

        let selection = P5ControlState(1)
        let picker = P5Picker(
            "Mode",
            selection: selection.binding,
            options: [first, second]
        )
        _ = picker.body
        _ = picker.optionView(first)

        _ = P5ColorPicker("Tint", selection: .constant(.red)).body
        _ = P5ColorPicker("Tint", selection: .constant(.blue), supportsOpacity: false).body
    }

    #if canImport(AppKit)
        @Test("AppKit factories produce configured controls and retain callbacks")
        func appKitControls() {
            _ = NSApplication.shared
            let state = ControlCallbackState()

            let button = P5NativeControlFactory.button("Run") { state.buttonPresses += 1 }
            #expect(button.title == "Run")
            #expect(button.accessibilityLabel() == "Run")
            #expect(button.sendAction(button.action, to: button.target))
            #expect(state.buttonPresses == 1)

            let customButton = P5NativeControlFactory.button(
                "Delete",
                accessibilityLabel: "Delete particle"
            ) {}
            #expect(customButton.accessibilityLabel() == "Delete particle")

            let slider = P5NativeControlFactory.slider(
                value: 0.5,
                in: 0...2,
                accessibilityLabel: "Speed"
            ) { state.sliderValue = $0 }
            #expect(slider.minValue == 0)
            #expect(slider.maxValue == 2)
            #expect(slider.accessibilityLabel() == "Speed")
            slider.doubleValue = 1.5
            #expect(slider.sendAction(slider.action, to: slider.target))
            #expect(state.sliderValue == 1.5)

            let field = P5NativeControlFactory.textField(
                text: "before",
                placeholder: "Name",
                accessibilityLabel: "Particle name"
            ) { state.text = $0 }
            #expect(field.stringValue == "before")
            #expect(field.placeholderString == "Name")
            #expect(field.accessibilityLabel() == "Particle name")
            field.stringValue = "after"
            #expect(field.sendAction(field.action, to: field.target))
            #expect(state.text == "after")

            let emptyField = P5NativeControlFactory.textField { _ in }
            #expect(emptyField.stringValue.isEmpty)
            #expect(emptyField.placeholderString == nil)

            let label = P5NativeControlFactory.label("Count: 3")
            #expect(label.stringValue == "Count: 3")
            #expect(label.isEditable == false)

            let toggle = P5NativeControlFactory.toggle("Trails", isOn: false) {
                state.toggleValue = $0
            }
            #expect(toggle.state == .off)
            #expect(toggle.accessibilityLabel() == "Trails")
            toggle.state = .on
            #expect(toggle.sendAction(toggle.action, to: toggle.target))
            #expect(state.toggleValue == true)

            let onToggle = P5NativeControlFactory.toggle(
                "Sound",
                isOn: true,
                accessibilityLabel: "Sound enabled"
            ) { _ in }
            #expect(onToggle.state == .on)
            #expect(onToggle.accessibilityLabel() == "Sound enabled")
        }
    #endif

    @Test("Control validation rejects invalid slider and picker state")
    func validation() async {
        #expect(P5ControlValidation.isValidSlider(range: 0...1, step: nil))
        #expect(P5ControlValidation.isValidSlider(range: 0...1, step: 0.1))
        #expect(P5ControlValidation.isValidSlider(range: -.infinity...1, step: nil) == false)
        #expect(P5ControlValidation.isValidSlider(range: 0...(.infinity), step: nil) == false)
        #expect(P5ControlValidation.isValidSlider(range: 1...1, step: nil) == false)
        #expect(P5ControlValidation.isValidSlider(range: 0...1, step: .nan) == false)
        #expect(P5ControlValidation.isValidSlider(range: 0...1, step: 0) == false)

        let optionA = P5ControlOption("A", value: 1)
        #expect(P5ControlValidation.isValidPicker(selection: 1, options: [optionA]))
        #expect(P5ControlValidation.isValidPicker(selection: 1, options: []) == false)
        #expect(
            P5ControlValidation.isValidPicker(
                selection: 1,
                options: [optionA, P5ControlOption("B", value: 1)]
            ) == false
        )
        #expect(P5ControlValidation.isValidPicker(selection: 2, options: [optionA]) == false)

        #expect(P5ControlValidation.isValidNativeSlider(value: 0.5, range: 0...1))
        #expect(P5ControlValidation.isValidNativeSlider(value: .infinity, range: 0...1) == false)
        #expect(
            P5ControlValidation.isValidNativeSlider(value: 0, range: -.infinity...1) == false
        )
        #expect(
            P5ControlValidation.isValidNativeSlider(value: 0, range: 0...(.infinity)) == false
        )
        #expect(
            P5ControlValidation.isValidNativeSlider(
                value: 1,
                range: 1...1
            ) == false
        )
        #expect(P5ControlValidation.isValidNativeSlider(value: 2, range: 0...1) == false)

        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                P5ControlValidation.validateSlider(range: -.infinity...1, step: nil)
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                P5ControlValidation.validatePicker(selection: 1, options: [])
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                P5ControlValidation.validateNativeSlider(value: 2, range: 0...1)
            }
        #endif
    }
}

@MainActor
private final class ControlCallbackState {
    var buttonPresses = 0
    var sliderValue = 0.0
    var text = ""
    var toggleValue = false
}
