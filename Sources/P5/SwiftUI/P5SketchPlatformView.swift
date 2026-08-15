import CoreGraphics
import SwiftUI

#if canImport(UIKit)
    import UIKit

    @MainActor
    struct P5SketchPlatformView<Sketch: P5Sketch>: UIViewRepresentable {
        let size: CGSize
        let makeSketch: @MainActor (CGSize) -> Sketch

        func makeCoordinator() -> P5SketchViewCoordinator<Sketch> {
            P5SketchViewCoordinator(size: size, makeSketch: makeSketch)
        }

        func makeUIView(context: Context) -> UIView {
            let container = UIView(frame: CGRect(origin: .zero, size: size))
            install(context.coordinator.sketch, in: container)
            return container
        }

        func updateUIView(_ container: UIView, context: Context) {
            guard context.coordinator.size != size else {
                return
            }

            context.coordinator.replaceSketch(for: size, using: makeSketch)
            install(context.coordinator.sketch, in: container)
        }

        func sizeThatFits(
            _ proposal: ProposedViewSize,
            uiView: UIView,
            context: Context
        ) -> CGSize? {
            size
        }

        private func install(_ sketch: Sketch, in container: UIView) {
            sketch.view.frame = container.bounds
            sketch.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.addSubview(sketch.view)
        }
    }
#elseif canImport(AppKit)
    import AppKit

    @MainActor
    struct P5SketchPlatformView<Sketch: P5Sketch>: NSViewRepresentable {
        let size: CGSize
        let makeSketch: @MainActor (CGSize) -> Sketch

        func makeCoordinator() -> P5SketchViewCoordinator<Sketch> {
            P5SketchViewCoordinator(size: size, makeSketch: makeSketch)
        }

        func makeNSView(context: Context) -> NSView {
            let container = NSView(frame: CGRect(origin: .zero, size: size))
            install(context.coordinator.sketch, in: container)
            return container
        }

        func updateNSView(_ container: NSView, context: Context) {
            guard context.coordinator.size != size else {
                return
            }

            context.coordinator.replaceSketch(for: size, using: makeSketch)
            install(context.coordinator.sketch, in: container)
        }

        func sizeThatFits(
            _ proposal: ProposedViewSize,
            nsView: NSView,
            context: Context
        ) -> CGSize? {
            size
        }

        private func install(_ sketch: Sketch, in container: NSView) {
            sketch.view.frame = container.bounds
            sketch.view.autoresizingMask = [.width, .height]
            container.addSubview(sketch.view)
        }
    }
#endif
