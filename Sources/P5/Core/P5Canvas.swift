import CoreGraphics

/// Platform-independent safe-area distances measured in canvas points.
public struct P5EdgeInsets: Sendable, Hashable {
    /// Distance from the visual top edge.
    public let top: CGFloat
    /// Distance from the leading edge in the canvas coordinate system.
    public let left: CGFloat
    /// Distance from the visual bottom edge.
    public let bottom: CGFloat
    /// Distance from the trailing edge in the canvas coordinate system.
    public let right: CGFloat

    /// Creates edge distances for layout and tests.
    public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        precondition([top, left, bottom, right].allSatisfy { $0.isFinite && $0 >= 0 })
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
}

/// A current snapshot of native canvas and display characteristics.
public struct P5CanvasMetrics: Sendable, Hashable {
    /// Logical canvas extent in points.
    public let size: CGSize
    /// Native display pixels represented by one logical point.
    public let displayScale: CGFloat
    /// Requested canvas raster density multiplier.
    public let pixelDensity: CGFloat
    /// Current display extent in points.
    public let displaySize: CGSize
    /// Insets where system interface elements may obscure canvas content.
    public let safeAreaInsets: P5EdgeInsets
    /// Whether the containing native window currently occupies full-screen presentation.
    public let isFullScreen: Bool

    init(
        size: CGSize,
        displayScale: CGFloat,
        pixelDensity: CGFloat,
        displaySize: CGSize,
        safeAreaInsets: P5EdgeInsets,
        isFullScreen: Bool
    ) {
        self.size = size
        self.displayScale = displayScale
        self.pixelDensity = pixelDensity
        self.displaySize = displaySize
        self.safeAreaInsets = safeAreaInsets
        self.isFullScreen = isFullScreen
    }
}

/// Application visibility state used to suspend or resume automatic drawing.
public enum P5ScenePhase: String, CaseIterable, Sendable, Hashable, Codable {
    /// The scene is visible and interactive.
    case active
    /// The scene is visible but not currently interactive.
    case inactive
    /// The scene is not visible and should release or suspend optional work.
    case background
}
