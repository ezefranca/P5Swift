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

    var onDraw: () -> Void = {}
    var onPointerEvent: (P5PointerEvent) -> Void = { _ in }

    #if canImport(UIKit)
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

    func requestManualFrame() {
        userWantsRedraw = true
    }

    func deliverPointerEvent(_ event: P5PointerEvent) {
        onPointerEvent(event)
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
    #endif

    #if canImport(UIKit)
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
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
