import CoreGraphics

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

@MainActor
final class P5SketchInternalView: P5CanvasView, P5SketchInternal {
    private let renderer: P5Renderer
    private let automaticallyDriven: Bool

    var isLooping = true {
        didSet {
            guard oldValue != isLooping else {
                return
            }
            updateAnimationState()
        }
    }

    var userWantsRedraw = false {
        didSet {
            if !oldValue && userWantsRedraw {
                requestDisplay()
            }
        }
    }

    var framesPerSecond = 60.0 {
        didSet {
            updateFrameRate()
        }
    }

    var pixelDensity = CGFloat(1) {
        didSet {
            applyPixelDensity()
            requestDisplay()
        }
    }

    var gestureCoexistence = P5GestureCoexistence.nativeDefault {
        didSet {
            applyGestureCoexistence()
        }
    }

    var onDraw: () -> Void = {}
    var onPointerEvent: (P5PointerEvent) -> Void = { _ in }
    var onKeyboardEvent: (P5KeyboardEvent) -> Void = { _ in }
    var onFocusEvent: (P5FocusEvent) -> Void = { _ in }
    var onScrollEvent: (P5ScrollEvent) -> Void = { _ in }
    var onAccessibilityEvent: (P5AccessibilityEvent) -> Bool = { _ in false }

    #if canImport(UIKit)
        override var canBecomeFirstResponder: Bool {
            true
        }

        private var displayLink: CADisplayLink?
        private var displayLinkTarget: P5DisplayLinkTarget?
        private var nextTouchID: UInt64 = 1
        private var touchIDs: [ObjectIdentifier: UInt64] = [:]
        private var touchOrigins: [ObjectIdentifier: (location: CGPoint, timestamp: TimeInterval)] =
            [:]
    #elseif canImport(AppKit)
        private var timer: Timer?
        private var pointerTrackingArea: NSTrackingArea?
        private var lastMouseLocation: CGPoint?

        override var isFlipped: Bool {
            true
        }
    #endif

    init(size: CGSize, automaticallyDriven: Bool) {
        renderer = P5Renderer()
        self.automaticallyDriven = automaticallyDriven
        renderer.size = size
        super.init(frame: .init(origin: .zero, size: size))
        #if canImport(UIKit)
            isMultipleTouchEnabled = true
        #endif
        if automaticallyDriven {
            startAnimation()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        MainActor.assumeIsolated {
            #if canImport(UIKit)
                displayLinkTarget = nil
                displayLink?.invalidate()
            #elseif canImport(AppKit)
                timer?.invalidate()
            #endif
        }
    }

    #if canImport(UIKit)
        override func draw(_ rect: CGRect) {
            guard let context = UIGraphicsGetCurrentContext() else {
                return
            }
            render(in: context)
        }
    #elseif canImport(AppKit)
        override func draw(_ dirtyRect: NSRect) {
            guard let context = NSGraphicsContext.current?.cgContext else {
                return
            }
            render(in: context)
        }
    #endif

    func addOperation(_ operation: P5Operation) {
        renderer.addOperation(operation)
    }

    func renderQueuedOperations(in context: CGContext) {
        renderer.render(in: context)
    }

    func capture(
        pixelDensity: CGFloat,
        makeContext: (Int, Int) -> CGContext? = P5SketchCaptureRuntime.makeContext,
        makeImage: (CGContext) -> CGImage? = { $0.makeImage() }
    ) throws -> P5Image {
        precondition(pixelDensity.isFinite && pixelDensity > 0)
        let pixelWidth = Int((bounds.width * pixelDensity).rounded(.up))
        let pixelHeight = Int((bounds.height * pixelDensity).rounded(.up))
        guard let context = makeContext(pixelWidth, pixelHeight) else {
            throw P5ImageError.bitmapAllocationFailed
        }
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: pixelDensity, y: -pixelDensity)
        renderer.render(in: context, consumingOperations: false)
        guard let image = makeImage(context) else {
            throw P5ImageError.bitmapAllocationFailed
        }
        return P5Image(cgImage: image, pixelDensity: pixelDensity)
    }

    func resize(to size: CGSize) {
        renderer.size = size
        frame.size = size
        bounds.size = size
        requestDisplay()
    }

    func canvasMetrics() -> P5CanvasMetrics {
        #if canImport(UIKit)
            let scale = window?.screen.scale ?? traitCollection.displayScale
            let displaySize = window?.screen.bounds.size ?? UIScreen.main.bounds.size
            let insets = safeAreaInsets
            let isFullScreen =
                window.map { window in
                    window.frame.equalTo(window.screen.bounds)
                } ?? false
            return P5CanvasMetrics(
                size: bounds.size,
                displayScale: scale,
                pixelDensity: pixelDensity,
                displaySize: displaySize,
                safeAreaInsets: P5EdgeInsets(
                    top: insets.top,
                    left: insets.left,
                    bottom: insets.bottom,
                    right: insets.right
                ),
                isFullScreen: isFullScreen
            )
        #elseif canImport(AppKit)
            let mainScreen = NSScreen.screens[0]
            let scale = window?.backingScaleFactor ?? mainScreen.backingScaleFactor
            let displaySize = window?.screen?.frame.size ?? mainScreen.frame.size
            let insets = safeAreaInsets
            let isFullScreen = Self.isFullScreen(window?.styleMask)
            return P5CanvasMetrics(
                size: bounds.size,
                displayScale: scale,
                pixelDensity: pixelDensity,
                displaySize: displaySize,
                safeAreaInsets: P5EdgeInsets(
                    top: insets.top,
                    left: insets.left,
                    bottom: insets.bottom,
                    right: insets.right
                ),
                isFullScreen: isFullScreen
            )
        #endif
    }

    #if canImport(AppKit)
        static func isFullScreen(_ styleMask: NSWindow.StyleMask?) -> Bool {
            styleMask?.contains(.fullScreen) ?? false
        }
    #endif

    func requestManualFrame() {
        userWantsRedraw = true
    }

    func deliverPointerEvent(_ event: P5PointerEvent) {
        onPointerEvent(event)
    }

    func deliverKeyboardEvent(_ event: P5KeyboardEvent) {
        onKeyboardEvent(event)
    }

    func deliverFocusEvent(_ event: P5FocusEvent) {
        onFocusEvent(event)
    }

    func deliverScrollEvent(_ event: P5ScrollEvent) {
        onScrollEvent(event)
    }

    @discardableResult
    func deliverAccessibilityAction(_ action: P5AccessibilityAction) -> Bool {
        onAccessibilityEvent(
            P5AccessibilityEvent(
                action: action,
                timestamp: ProcessInfo.processInfo.systemUptime
            )
        )
    }

    @discardableResult
    func requestFocus() -> Bool {
        #if canImport(UIKit)
            becomeFirstResponder()
        #elseif canImport(AppKit)
            window?.makeFirstResponder(self) ?? false
        #endif
    }

    func updateAccessibility(label: String?, value: String?, hint: String?) {
        #if canImport(UIKit)
            isAccessibilityElement = label != nil || value != nil || hint != nil
            accessibilityLabel = label
            accessibilityValue = value
            accessibilityHint = hint
        #elseif canImport(AppKit)
            setAccessibilityElement(label != nil || value != nil || hint != nil)
            setAccessibilityLabel(label)
            setAccessibilityValue(value)
            setAccessibilityHelp(hint)
        #endif
    }

    private func render(in context: CGContext) {
        if automaticallyDriven && (isLooping || userWantsRedraw) {
            onDraw()
            renderer.render(in: context)
            userWantsRedraw = false
        } else if userWantsRedraw {
            renderer.render(in: context)
            userWantsRedraw = false
        }
    }

    private func updateAnimationState() {
        #if canImport(UIKit)
            displayLink?.isPaused = !isLooping
        #elseif canImport(AppKit)
            if isLooping {
                startTimer()
            } else {
                timer?.invalidate()
                timer = nil
            }
        #endif

        if isLooping {
            requestDisplay()
        }
    }

    private func updateFrameRate() {
        #if canImport(UIKit)
            displayLink?.preferredFramesPerSecond = Int(framesPerSecond.rounded())
        #elseif canImport(AppKit)
            if isLooping {
                startTimer()
            }
        #endif
    }

    private func startAnimation() {
        #if canImport(UIKit)
            let target = P5DisplayLinkTarget { [weak self] in
                self?.requestDisplay()
            }
            let displayLink = CADisplayLink(
                target: target,
                selector: #selector(P5DisplayLinkTarget.displayLinkDidFire)
            )
            displayLink.preferredFramesPerSecond = Int(framesPerSecond.rounded())
            displayLink.add(to: .main, forMode: .common)
            displayLinkTarget = target
            self.displayLink = displayLink
        #elseif canImport(AppKit)
            startTimer()
        #endif
    }

    private func requestDisplay() {
        #if canImport(UIKit)
            setNeedsDisplay()
        #elseif canImport(AppKit)
            needsDisplay = true
        #endif
    }

    private func applyPixelDensity() {
        #if canImport(UIKit)
            contentScaleFactor = pixelDensity
        #elseif canImport(AppKit)
            wantsLayer = true
            layer?.contentsScale = pixelDensity
        #endif
    }

    private func applyGestureCoexistence() {
        #if canImport(UIKit)
            guard gestureCoexistence == .cooperative else { return }
            for recognizer in gestureRecognizers ?? [] {
                recognizer.cancelsTouchesInView = false
                recognizer.delaysTouchesBegan = false
                recognizer.delaysTouchesEnded = false
            }
        #endif
    }

    #if canImport(AppKit)
        private func startTimer() {
            timer?.invalidate()
            timer = Timer.scheduledTimer(
                withTimeInterval: 1 / framesPerSecond,
                repeats: true
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.requestDisplay()
                }
            }
        }

        override var acceptsFirstResponder: Bool {
            true
        }

        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted {
                deliverFocusEvent(
                    P5FocusEvent(
                        isFocused: true,
                        cause: .system,
                        timestamp: ProcessInfo.processInfo.systemUptime
                    )
                )
            }
            return accepted
        }

        override func resignFirstResponder() -> Bool {
            let accepted = super.resignFirstResponder()
            if accepted {
                deliverFocusEvent(
                    P5FocusEvent(
                        isFocused: false,
                        cause: .system,
                        timestamp: ProcessInfo.processInfo.systemUptime
                    )
                )
            }
            return accepted
        }

        override func accessibilityPerformPress() -> Bool {
            deliverAccessibilityAction(.activate) || super.accessibilityPerformPress()
        }

        override func accessibilityPerformIncrement() -> Bool {
            deliverAccessibilityAction(.increment) || super.accessibilityPerformIncrement()
        }

        override func accessibilityPerformDecrement() -> Bool {
            deliverAccessibilityAction(.decrement) || super.accessibilityPerformDecrement()
        }

        override func accessibilityPerformCancel() -> Bool {
            deliverAccessibilityAction(.escape) || super.accessibilityPerformCancel()
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let pointerTrackingArea {
                removeTrackingArea(pointerTrackingArea)
            }
            let trackingArea = NSTrackingArea(
                rect: bounds,
                options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                owner: self
            )
            addTrackingArea(trackingArea)
            pointerTrackingArea = trackingArea
        }

        override func mouseEntered(with event: NSEvent) {
            deliverMouseEvent(event, phase: .entered, button: .none)
        }

        override func mouseExited(with event: NSEvent) {
            deliverMouseEvent(event, phase: .exited, button: .none)
        }

        override func mouseMoved(with event: NSEvent) {
            deliverMouseEvent(event, phase: .moved, button: .none)
        }

        override func scrollWheel(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            deliverScrollEvent(
                P5ScrollEvent(
                    phase: Self.scrollPhase(
                        phase: event.phase,
                        momentumPhase: event.momentumPhase
                    ),
                    delta: CGVector(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY),
                    location: location,
                    modifiers: Self.modifierKeys(from: event.modifierFlags),
                    isPrecise: event.hasPreciseScrollingDeltas,
                    isDirectionInverted: event.isDirectionInvertedFromDevice,
                    isMomentum: event.momentumPhase.isEmpty == false,
                    timestamp: event.timestamp
                )
            )
        }

        static func scrollPhase(
            phase: NSEvent.Phase,
            momentumPhase: NSEvent.Phase
        ) -> P5ScrollPhase {
            let effective = momentumPhase.isEmpty ? phase : momentumPhase
            if effective.contains(.began) { return .began }
            if effective.contains(.ended) { return .ended }
            if effective.contains(.cancelled) { return .cancelled }
            return .changed
        }

        override func mouseDragged(with event: NSEvent) {
            deliverMouseEvent(event, phase: .dragged, button: .primary)
        }

        override func rightMouseDragged(with event: NSEvent) {
            deliverMouseEvent(event, phase: .dragged, button: .secondary)
        }

        override func otherMouseDragged(with event: NSEvent) {
            deliverMouseEvent(event, phase: .dragged, button: pointerButton(for: event))
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            deliverMouseEvent(event, phase: .pressed, button: .primary)
        }

        override func rightMouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            deliverMouseEvent(event, phase: .pressed, button: .secondary)
        }

        override func otherMouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            deliverMouseEvent(event, phase: .pressed, button: pointerButton(for: event))
        }

        override func mouseUp(with event: NSEvent) {
            deliverMouseRelease(event, button: .primary)
        }

        override func rightMouseUp(with event: NSEvent) {
            deliverMouseRelease(event, button: .secondary)
        }

        override func otherMouseUp(with event: NSEvent) {
            deliverMouseRelease(event, button: pointerButton(for: event))
        }

        private func deliverMouseRelease(_ event: NSEvent, button: P5PointerButton) {
            deliverMouseEvent(event, phase: .released, button: button)
            if event.clickCount > 0 {
                deliverMouseEvent(event, phase: .clicked, button: button)
            }
        }

        private func deliverMouseEvent(
            _ event: NSEvent,
            phase: P5PointerPhase,
            button: P5PointerButton
        ) {
            let location = convert(event.locationInWindow, from: nil)
            let previousLocation = lastMouseLocation ?? location
            let pressure = Self.normalizedPressure(event.pressure)
            deliverPointerEvent(
                P5PointerEvent(
                    id: 0,
                    kind: .mouse,
                    phase: phase,
                    location: location,
                    previousLocation: previousLocation,
                    button: button,
                    pressedButtons: Self.pointerButtons(from: NSEvent.pressedMouseButtons),
                    modifiers: Self.modifierKeys(from: event.modifierFlags),
                    pressure: pressure,
                    timestamp: event.timestamp
                )
            )
            lastMouseLocation = location
        }

        private func pointerButton(for event: NSEvent) -> P5PointerButton {
            Self.pointerButton(forButtonNumber: event.buttonNumber)
        }

        static func pointerButton(forButtonNumber buttonNumber: Int) -> P5PointerButton {
            switch buttonNumber {
            case 0: .primary
            case 1: .secondary
            case 2: .middle
            default: .other(buttonNumber)
            }
        }

        static func pointerButtons(from mask: Int) -> P5PointerButtons {
            var buttons: P5PointerButtons = []
            if mask & (1 << 0) != 0 { buttons.insert(.primary) }
            if mask & (1 << 1) != 0 { buttons.insert(.secondary) }
            if mask & (1 << 2) != 0 { buttons.insert(.middle) }
            if mask & ~0b111 != 0 { buttons.insert(.other) }
            return buttons
        }

        static func modifierKeys(from flags: NSEvent.ModifierFlags) -> P5ModifierKeys {
            var modifiers: P5ModifierKeys = []
            if flags.contains(.shift) { modifiers.insert(.shift) }
            if flags.contains(.control) { modifiers.insert(.control) }
            if flags.contains(.option) { modifiers.insert(.option) }
            if flags.contains(.command) { modifiers.insert(.command) }
            if flags.contains(.capsLock) { modifiers.insert(.capsLock) }
            if flags.contains(.function) { modifiers.insert(.function) }
            return modifiers
        }

        static func normalizedPressure(_ pressure: Float) -> CGFloat? {
            pressure.isFinite ? CGFloat(min(max(pressure, 0), 1)) : nil
        }

        override func keyDown(with event: NSEvent) {
            let key = Self.semanticKey(
                forAppKitKeyCode: event.keyCode,
                characters: event.charactersIgnoringModifiers
            )
            let modifiers = Self.modifierKeys(from: event.modifierFlags)
            deliverKeyboardEvent(
                P5KeyboardEvent(
                    phase: .pressed,
                    key: key,
                    characters: Self.nonempty(event.characters),
                    platformKeyCode: event.keyCode,
                    modifiers: modifiers,
                    isRepeat: event.isARepeat,
                    timestamp: event.timestamp
                )
            )

            if key.producesTypedText,
                !modifiers.contains(.command),
                !modifiers.contains(.control),
                let characters = event.characters,
                !characters.isEmpty
            {
                deliverKeyboardEvent(
                    P5KeyboardEvent(
                        phase: .typed,
                        key: key,
                        characters: characters,
                        platformKeyCode: event.keyCode,
                        modifiers: modifiers,
                        isRepeat: event.isARepeat,
                        timestamp: event.timestamp
                    )
                )
            }
        }

        override func keyUp(with event: NSEvent) {
            deliverKeyboardEvent(
                P5KeyboardEvent(
                    phase: .released,
                    key: Self.semanticKey(
                        forAppKitKeyCode: event.keyCode,
                        characters: event.charactersIgnoringModifiers
                    ),
                    characters: Self.nonempty(event.characters),
                    platformKeyCode: event.keyCode,
                    modifiers: Self.modifierKeys(from: event.modifierFlags),
                    isRepeat: false,
                    timestamp: event.timestamp
                )
            )
        }

        override func flagsChanged(with event: NSEvent) {
            let key = Self.semanticModifier(forAppKitKeyCode: event.keyCode)
            let modifiers = Self.modifierKeys(from: event.modifierFlags)
            deliverKeyboardEvent(
                P5KeyboardEvent(
                    phase: Self.isModifier(key, heldIn: modifiers) ? .pressed : .released,
                    key: key,
                    platformKeyCode: event.keyCode,
                    modifiers: modifiers,
                    timestamp: event.timestamp
                )
            )
        }

        static func semanticKey(forAppKitKeyCode keyCode: UInt16, characters: String?) -> P5Key {
            switch keyCode {
            case 36, 76: .enter
            case 48: .tab
            case 51: .backspace
            case 117: .delete
            case 53: .escape
            case 49: .space
            case 123: .arrowLeft
            case 124: .arrowRight
            case 126: .arrowUp
            case 125: .arrowDown
            case 115: .home
            case 119: .end
            case 116: .pageUp
            case 121: .pageDown
            case 122: .function(1)
            case 120: .function(2)
            case 99: .function(3)
            case 118: .function(4)
            case 96: .function(5)
            case 97: .function(6)
            case 98: .function(7)
            case 100: .function(8)
            case 101: .function(9)
            case 109: .function(10)
            case 103: .function(11)
            case 111: .function(12)
            case 105: .function(13)
            case 107: .function(14)
            case 113: .function(15)
            case 106: .function(16)
            case 64: .function(17)
            case 79: .function(18)
            case 80: .function(19)
            case 90: .function(20)
            default:
                if let characters, !characters.isEmpty {
                    .character(characters)
                } else {
                    .unidentified(keyCode)
                }
            }
        }

        static func semanticModifier(forAppKitKeyCode keyCode: UInt16) -> P5Key {
            switch keyCode {
            case 56, 60: .shift
            case 59, 62: .control
            case 58, 61: .option
            case 54, 55: .command
            case 57: .capsLock
            case 63: .functionModifier
            default: .unidentified(keyCode)
            }
        }

        static func isModifier(_ key: P5Key, heldIn modifiers: P5ModifierKeys) -> Bool {
            switch key {
            case .shift: modifiers.contains(.shift)
            case .control: modifiers.contains(.control)
            case .option: modifiers.contains(.option)
            case .command: modifiers.contains(.command)
            case .capsLock: modifiers.contains(.capsLock)
            case .functionModifier: modifiers.contains(.function)
            default: false
            }
        }

        static func nonempty(_ value: String?) -> String? {
            guard let value, !value.isEmpty else {
                return nil
            }
            return value
        }
    #endif

    #if canImport(UIKit)
        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted {
                deliverFocusEvent(
                    P5FocusEvent(
                        isFocused: true,
                        cause: .system,
                        timestamp: ProcessInfo.processInfo.systemUptime
                    )
                )
            }
            return accepted
        }

        override func resignFirstResponder() -> Bool {
            let accepted = super.resignFirstResponder()
            if accepted {
                deliverFocusEvent(
                    P5FocusEvent(
                        isFocused: false,
                        cause: .system,
                        timestamp: ProcessInfo.processInfo.systemUptime
                    )
                )
            }
            return accepted
        }

        override func accessibilityActivate() -> Bool {
            deliverAccessibilityAction(.activate) || super.accessibilityActivate()
        }

        override func accessibilityIncrement() {
            if deliverAccessibilityAction(.increment) == false {
                super.accessibilityIncrement()
            }
        }

        override func accessibilityDecrement() {
            if deliverAccessibilityAction(.decrement) == false {
                super.accessibilityDecrement()
            }
        }

        override func accessibilityPerformEscape() -> Bool {
            deliverAccessibilityAction(.escape) || super.accessibilityPerformEscape()
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            for press in orderedPresses(presses) {
                deliverPress(press, phase: .pressed)
                guard
                    let nativeKey = press.key,
                    let characters = nonempty(nativeKey.characters),
                    semanticKey(for: nativeKey).producesTypedText,
                    !nativeKey.modifierFlags.contains(.command),
                    !nativeKey.modifierFlags.contains(.control)
                else {
                    continue
                }
                deliverKeyboardEvent(
                    keyboardEvent(
                        for: press,
                        phase: .typed,
                        characters: characters
                    )
                )
            }
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            for press in orderedPresses(presses) {
                deliverPress(press, phase: .released)
            }
        }

        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            for press in orderedPresses(presses) {
                deliverPress(press, phase: .cancelled)
            }
        }

        private func orderedPresses(_ presses: Set<UIPress>) -> [UIPress] {
            presses.sorted {
                ($0.key?.keyCode.rawValue ?? 0) < ($1.key?.keyCode.rawValue ?? 0)
            }
        }

        private func deliverPress(_ press: UIPress, phase: P5KeyboardPhase) {
            deliverKeyboardEvent(keyboardEvent(for: press, phase: phase))
        }

        private func keyboardEvent(
            for press: UIPress,
            phase: P5KeyboardPhase,
            characters: String? = nil
        ) -> P5KeyboardEvent {
            guard let nativeKey = press.key else {
                return P5KeyboardEvent(
                    phase: phase,
                    key: .unidentified(0),
                    timestamp: press.timestamp
                )
            }
            return P5KeyboardEvent(
                phase: phase,
                key: semanticKey(for: nativeKey),
                characters: characters ?? nonempty(nativeKey.characters),
                platformKeyCode: UInt16(truncatingIfNeeded: nativeKey.keyCode.rawValue),
                modifiers: Self.modifierKeys(from: nativeKey.modifierFlags),
                isRepeat: false,
                timestamp: press.timestamp
            )
        }

        private func semanticKey(for key: UIKey) -> P5Key {
            Self.semanticKey(
                forHIDUsage: UInt16(truncatingIfNeeded: key.keyCode.rawValue),
                characters: nonempty(key.charactersIgnoringModifiers)
            )
        }

        private func nonempty(_ value: String) -> String? {
            value.isEmpty ? nil : value
        }

        static func semanticKey(forHIDUsage usage: UInt16, characters: String?) -> P5Key {
            switch usage {
            case 40: .enter
            case 43: .tab
            case 42: .backspace
            case 76: .delete
            case 41: .escape
            case 44: .space
            case 80: .arrowLeft
            case 79: .arrowRight
            case 82: .arrowUp
            case 81: .arrowDown
            case 74: .home
            case 77: .end
            case 75: .pageUp
            case 78: .pageDown
            case 225, 229: .shift
            case 224, 228: .control
            case 226, 230: .option
            case 227, 231: .command
            case 57: .capsLock
            case 58...69: .function(Int(usage - 57))
            case 104...115: .function(Int(usage - 91))
            default:
                if let characters, !characters.isEmpty {
                    .character(characters)
                } else {
                    .unidentified(usage)
                }
            }
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            applyGestureCoexistence()
            becomeFirstResponder()
            for touch in orderedTouches(touches) {
                let key = ObjectIdentifier(touch)
                touchOrigins[key] = (touch.location(in: self), touch.timestamp)
                deliverTouch(touch, phase: .pressed, event: event)
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in orderedTouches(touches) {
                deliverTouch(touch, phase: .dragged, event: event)
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in orderedTouches(touches) {
                let key = ObjectIdentifier(touch)
                deliverTouch(touch, phase: .released, event: event)
                if let origin = touchOrigins[key] {
                    let location = touch.location(in: self)
                    let distance = hypot(
                        location.x - origin.location.x, location.y - origin.location.y)
                    if distance <= 10, touch.timestamp - origin.timestamp <= 0.5 {
                        deliverTouch(touch, phase: .clicked, event: event)
                    }
                }
                touchIDs[key] = nil
                touchOrigins[key] = nil
            }
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in orderedTouches(touches) {
                let key = ObjectIdentifier(touch)
                deliverTouch(touch, phase: .cancelled, event: event)
                touchIDs[key] = nil
                touchOrigins[key] = nil
            }
        }

        private func orderedTouches(_ touches: Set<UITouch>) -> [UITouch] {
            touches.sorted { first, second in
                let firstLocation = first.location(in: self)
                let secondLocation = second.location(in: self)
                if firstLocation.x == secondLocation.x {
                    return firstLocation.y < secondLocation.y
                }
                return firstLocation.x < secondLocation.x
            }
        }

        private func deliverTouch(
            _ touch: UITouch,
            phase: P5PointerPhase,
            event: UIEvent?
        ) {
            let key = ObjectIdentifier(touch)
            let identifier = touchIdentifier(for: key)
            let pressure: CGFloat? =
                if touch.maximumPossibleForce > 0 {
                    min(max(touch.force / touch.maximumPossibleForce, 0), 1)
                } else {
                    nil
                }
            deliverPointerEvent(
                P5PointerEvent(
                    id: identifier,
                    kind: Self.pointerKind(for: touch.type),
                    phase: phase,
                    location: touch.location(in: self),
                    previousLocation: touch.previousLocation(in: self),
                    button: .primary,
                    pressedButtons: Self.hasActiveTouches(event) ? .primary : [],
                    modifiers: Self.modifierKeys(from: event?.modifierFlags ?? []),
                    pressure: pressure,
                    timestamp: touch.timestamp
                )
            )
        }

        private func touchIdentifier(for key: ObjectIdentifier) -> UInt64 {
            if let identifier = touchIDs[key] {
                return identifier
            }
            precondition(nextTouchID < .max)
            let identifier = nextTouchID
            nextTouchID += 1
            touchIDs[key] = identifier
            return identifier
        }

        private static func hasActiveTouches(_ event: UIEvent?) -> Bool {
            event?.allTouches?.contains { touch in
                touch.phase != .ended && touch.phase != .cancelled
            } ?? false
        }

        private static func pointerKind(for type: UITouch.TouchType) -> P5PointerKind {
            switch type {
            case .direct: .touch
            case .pencil: .pencil
            case .indirect, .indirectPointer: .indirect
            @unknown default: .touch
            }
        }

        private static func modifierKeys(from flags: UIKeyModifierFlags) -> P5ModifierKeys {
            var modifiers: P5ModifierKeys = []
            if flags.contains(.shift) { modifiers.insert(.shift) }
            if flags.contains(.control) { modifiers.insert(.control) }
            if flags.contains(.alternate) { modifiers.insert(.option) }
            if flags.contains(.command) { modifiers.insert(.command) }
            if flags.contains(.alphaShift) { modifiers.insert(.capsLock) }
            return modifiers
        }
    #endif
}

enum P5SketchCaptureRuntime {
    static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: P5RasterColorSpace.preferred(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}
