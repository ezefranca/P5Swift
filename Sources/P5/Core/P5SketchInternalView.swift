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

    #if canImport(UIKit)
        private var displayLink: CADisplayLink?
        private var displayLinkTarget: P5DisplayLinkTarget?
    #elseif canImport(AppKit)
        private var timer: Timer?

        override var isFlipped: Bool {
            true
        }
    #endif

    init(size: CGSize, automaticallyDriven: Bool) {
        renderer = P5Renderer()
        self.automaticallyDriven = automaticallyDriven
        renderer.size = size
        super.init(frame: .init(origin: .zero, size: size))
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
    #endif
}
