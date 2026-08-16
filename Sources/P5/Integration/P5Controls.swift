import Observation
import SwiftUI

#if canImport(AppKit)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif

/// Main-actor observable state that can be shared by a sketch and native controls.
@MainActor
@Observable
public final class P5ControlState<Value: Sendable> {
    /// The current control value.
    public var value: Value

    /// Creates state with an initial value.
    public init(_ value: Value) {
        self.value = value
    }

    /// A SwiftUI binding that reads and writes ``value``.
    public var binding: Binding<Value> {
        Binding(
            get: { self.value },
            set: { self.value = $0 }
        )
    }
}

/// A titled value shown by ``P5Picker``.
public struct P5ControlOption<Value: Hashable & Sendable>: Hashable, Sendable, Identifiable {
    /// The value used as the stable SwiftUI identity and selection tag.
    public let value: Value
    /// Text presented to the user.
    public let title: String

    /// Creates a titled selectable value.
    public init(_ title: String, value: Value) {
        self.title = title
        self.value = value
    }

    /// The stable option identity.
    public var id: Value { value }
}

/// A native SwiftUI button for a sketch interface.
public struct P5Button: View {
    private let title: String
    private let role: ButtonRole?
    private let action: @MainActor () -> Void

    /// Creates a button with an optional semantic role.
    public init(
        _ title: String,
        role: ButtonRole? = nil,
        action: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.role = role
        self.action = action
    }

    /// The native SwiftUI button hierarchy.
    public var body: some View {
        Button(title, role: role, action: action)
    }
}

/// A native SwiftUI slider with validated finite bounds and optional stepping.
public struct P5Slider: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double?
    private let label: String
    let onEditingChanged: (Bool) -> Void

    /// Creates a slider bound to a floating-point value.
    ///
    /// - Precondition: Bounds are finite and increasing. A supplied step is finite
    ///   and greater than zero.
    public init(
        value: Binding<Double>,
        in range: ClosedRange<Double> = 0...1,
        step: Double? = nil,
        label: String = "Value",
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        P5ControlValidation.validateSlider(range: range, step: step)
        _value = value
        self.range = range
        self.step = step
        self.label = label
        self.onEditingChanged = onEditingChanged
    }

    /// The native SwiftUI slider hierarchy.
    @ViewBuilder
    public var body: some View {
        if let step {
            Slider(
                value: $value,
                in: range,
                step: step,
                onEditingChanged: onEditingChanged,
                label: { Text(label) }
            )
        } else {
            Slider(
                value: $value,
                in: range,
                onEditingChanged: onEditingChanged,
                label: { Text(label) }
            )
        }
    }
}

/// A native SwiftUI single-line text field.
public struct P5TextField: View {
    @Binding private var text: String
    private let title: String
    private let prompt: String?
    let onSubmit: @MainActor () -> Void

    /// Creates a text field with optional prompt text and submit handling.
    public init(
        _ title: String,
        text: Binding<String>,
        prompt: String? = nil,
        onSubmit: @escaping @MainActor () -> Void = {}
    ) {
        self.title = title
        _text = text
        self.prompt = prompt
        self.onSubmit = onSubmit
    }

    /// The native SwiftUI text-field hierarchy.
    public var body: some View {
        TextField(title, text: $text, prompt: prompt.map(Text.init)).onSubmit(onSubmit)
    }
}

/// Read-only native SwiftUI text for a sketch interface.
public struct P5Label: View {
    private let text: String

    /// Creates a label from plain text.
    public init(_ text: String) {
        self.text = text
    }

    /// The native SwiftUI text hierarchy.
    public var body: some View {
        Text(text)
    }
}

/// A native SwiftUI Boolean toggle.
public struct P5Toggle: View {
    private let title: String
    @Binding private var isOn: Bool

    /// Creates a titled toggle bound to Boolean state.
    public init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    /// The native SwiftUI toggle hierarchy.
    public var body: some View {
        Toggle(title, isOn: $isOn)
    }
}

/// A native SwiftUI picker backed by stable titled options.
public struct P5Picker<Selection: Hashable & Sendable>: View {
    private let title: String
    @Binding private var selection: Selection
    private let options: [P5ControlOption<Selection>]

    /// Creates a picker whose options have unique values and include the selection.
    ///
    /// - Precondition: `options` is nonempty, has unique values, and contains the
    ///   binding's current selection.
    public init(
        _ title: String,
        selection: Binding<Selection>,
        options: [P5ControlOption<Selection>]
    ) {
        P5ControlValidation.validatePicker(
            selection: selection.wrappedValue,
            options: options
        )
        self.title = title
        _selection = selection
        self.options = options
    }

    /// The native SwiftUI picker hierarchy.
    public var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options, content: optionView)
        }
    }

    func optionView(_ option: P5ControlOption<Selection>) -> some View {
        Text(option.title).tag(option.value)
    }
}

/// A native SwiftUI color picker.
public struct P5ColorPicker: View {
    private let title: String
    @Binding private var selection: Color
    private let supportsOpacity: Bool

    /// Creates a color picker bound to a SwiftUI color.
    public init(_ title: String, selection: Binding<Color>, supportsOpacity: Bool = true) {
        self.title = title
        _selection = selection
        self.supportsOpacity = supportsOpacity
    }

    /// The native SwiftUI color-picker hierarchy.
    public var body: some View {
        ColorPicker(title, selection: $selection, supportsOpacity: supportsOpacity)
    }
}

/// Factories for embedding native platform controls outside SwiftUI.
@MainActor
public enum P5NativeControlFactory {
    #if canImport(AppKit)
        /// Creates an AppKit push button that owns its action closure.
        public static func button(
            _ title: String,
            accessibilityLabel: String? = nil,
            action: @escaping @MainActor () -> Void
        ) -> NSButton {
            let button = P5AppKitButton(title: title, handler: action)
            button.setAccessibilityLabel(accessibilityLabel ?? title)
            return button
        }

        /// Creates an AppKit slider that reports native value changes.
        ///
        /// - Precondition: The value and increasing bounds are finite and the value is
        ///   inside the bounds.
        public static func slider(
            value: Double,
            in range: ClosedRange<Double> = 0...1,
            accessibilityLabel: String = "Value",
            onChange: @escaping @MainActor (Double) -> Void
        ) -> NSSlider {
            P5ControlValidation.validateNativeSlider(value: value, range: range)
            let slider = P5AppKitSlider(value: value, range: range, handler: onChange)
            slider.setAccessibilityLabel(accessibilityLabel)
            return slider
        }

        /// Creates an AppKit editable text field whose action commits text.
        public static func textField(
            text: String = "",
            placeholder: String? = nil,
            accessibilityLabel: String = "Text",
            onCommit: @escaping @MainActor (String) -> Void
        ) -> NSTextField {
            let field = P5AppKitTextField(text: text, handler: onCommit)
            field.placeholderString = placeholder
            field.setAccessibilityLabel(accessibilityLabel)
            return field
        }

        /// Creates a noneditable AppKit text label.
        public static func label(_ text: String) -> NSTextField {
            NSTextField(labelWithString: text)
        }

        /// Creates an AppKit checkbox that reports Boolean changes.
        public static func toggle(
            _ title: String,
            isOn: Bool,
            accessibilityLabel: String? = nil,
            onChange: @escaping @MainActor (Bool) -> Void
        ) -> NSButton {
            let toggle = P5AppKitToggle(title: title, isOn: isOn, handler: onChange)
            toggle.setAccessibilityLabel(accessibilityLabel ?? title)
            return toggle
        }
    #elseif canImport(UIKit)
        /// Creates a UIKit system button that owns its action closure.
        public static func button(
            _ title: String,
            accessibilityLabel: String? = nil,
            action: @escaping @MainActor () -> Void
        ) -> UIButton {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.accessibilityLabel = accessibilityLabel ?? title
            button.addAction(UIAction { _ in action() }, for: .primaryActionTriggered)
            return button
        }

        /// Creates a UIKit slider that reports native value changes.
        ///
        /// - Precondition: The value and increasing bounds are finite and the value is
        ///   inside the bounds.
        public static func slider(
            value: Double,
            in range: ClosedRange<Double> = 0...1,
            accessibilityLabel: String = "Value",
            onChange: @escaping @MainActor (Double) -> Void
        ) -> UISlider {
            P5ControlValidation.validateNativeSlider(value: value, range: range)
            let slider = UISlider()
            slider.minimumValue = Float(range.lowerBound)
            slider.maximumValue = Float(range.upperBound)
            slider.value = Float(value)
            slider.accessibilityLabel = accessibilityLabel
            slider.addAction(
                UIAction { action in
                    guard let slider = action.sender as? UISlider else { return }
                    onChange(Double(slider.value))
                },
                for: .valueChanged
            )
            return slider
        }

        /// Creates a UIKit editable text field that reports committed text.
        public static func textField(
            text: String = "",
            placeholder: String? = nil,
            accessibilityLabel: String = "Text",
            onCommit: @escaping @MainActor (String) -> Void
        ) -> UITextField {
            let field = UITextField()
            field.text = text
            field.placeholder = placeholder
            field.accessibilityLabel = accessibilityLabel
            field.addAction(
                UIAction { action in
                    guard let field = action.sender as? UITextField else { return }
                    onCommit(field.text ?? "")
                },
                for: .editingDidEndOnExit
            )
            return field
        }

        /// Creates a UIKit text label.
        public static func label(_ text: String) -> UILabel {
            let label = UILabel()
            label.text = text
            return label
        }

        /// Creates a UIKit switch that reports Boolean changes.
        public static func toggle(
            _ title: String,
            isOn: Bool,
            accessibilityLabel: String? = nil,
            onChange: @escaping @MainActor (Bool) -> Void
        ) -> UISwitch {
            let toggle = UISwitch()
            toggle.isOn = isOn
            toggle.accessibilityLabel = accessibilityLabel ?? title
            toggle.addAction(
                UIAction { action in
                    guard let toggle = action.sender as? UISwitch else { return }
                    onChange(toggle.isOn)
                },
                for: .valueChanged
            )
            return toggle
        }
    #endif

}

enum P5ControlValidation {
    static func validateSlider(range: ClosedRange<Double>, step: Double?) {
        precondition(isValidSlider(range: range, step: step))
    }

    static func isValidSlider(range: ClosedRange<Double>, step: Double?) -> Bool {
        range.lowerBound.isFinite && range.upperBound.isFinite
            && range.lowerBound < range.upperBound
            && (step.map { $0.isFinite && $0 > 0 } ?? true)
    }

    static func validatePicker<Value: Hashable & Sendable>(
        selection: Value,
        options: [P5ControlOption<Value>]
    ) {
        precondition(isValidPicker(selection: selection, options: options))
    }

    static func isValidPicker<Value: Hashable & Sendable>(
        selection: Value,
        options: [P5ControlOption<Value>]
    ) -> Bool {
        options.isEmpty == false && Set(options.map(\.value)).count == options.count
            && options.contains { $0.value == selection }
    }

    static func validateNativeSlider(value: Double, range: ClosedRange<Double>) {
        precondition(isValidNativeSlider(value: value, range: range))
    }

    static func isValidNativeSlider(value: Double, range: ClosedRange<Double>) -> Bool {
        value.isFinite && range.lowerBound.isFinite && range.upperBound.isFinite
            && range.lowerBound < range.upperBound && range.contains(value)
    }
}

#if canImport(AppKit)
    @MainActor
    private final class P5AppKitButton: NSButton {
        private let handler: @MainActor () -> Void

        init(title: String, handler: @escaping @MainActor () -> Void) {
            self.handler = handler
            super.init(frame: .zero)
            self.title = title
            bezelStyle = .rounded
            target = self
            action = #selector(invoke)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is unavailable")
        }

        @objc private func invoke() {
            handler()
        }
    }

    @MainActor
    private final class P5AppKitSlider: NSSlider {
        private let handler: @MainActor (Double) -> Void

        init(
            value: Double,
            range: ClosedRange<Double>,
            handler: @escaping @MainActor (Double) -> Void
        ) {
            self.handler = handler
            super.init(frame: .zero)
            minValue = range.lowerBound
            maxValue = range.upperBound
            doubleValue = value
            target = self
            action = #selector(invoke)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is unavailable")
        }

        @objc private func invoke() {
            handler(doubleValue)
        }
    }

    @MainActor
    private final class P5AppKitTextField: NSTextField {
        private let handler: @MainActor (String) -> Void

        init(text: String, handler: @escaping @MainActor (String) -> Void) {
            self.handler = handler
            super.init(frame: .zero)
            stringValue = text
            target = self
            action = #selector(invoke)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is unavailable")
        }

        @objc private func invoke() {
            handler(stringValue)
        }
    }

    @MainActor
    private final class P5AppKitToggle: NSButton {
        private let handler: @MainActor (Bool) -> Void

        init(
            title: String,
            isOn: Bool,
            handler: @escaping @MainActor (Bool) -> Void
        ) {
            self.handler = handler
            super.init(frame: .zero)
            self.title = title
            setButtonType(.switch)
            state = isOn ? .on : .off
            target = self
            action = #selector(invoke)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is unavailable")
        }

        @objc private func invoke() {
            handler(state == .on)
        }
    }
#endif
