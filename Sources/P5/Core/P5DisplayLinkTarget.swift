#if canImport(UIKit)
    import UIKit

    @MainActor
    final class P5DisplayLinkTarget: NSObject {
        private let onDisplay: @MainActor () -> Void

        init(onDisplay: @escaping @MainActor () -> Void) {
            self.onDisplay = onDisplay
        }

        @objc
        func displayLinkDidFire() {
            onDisplay()
        }
    }
#endif
