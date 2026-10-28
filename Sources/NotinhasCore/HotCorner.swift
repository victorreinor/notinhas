import CoreGraphics

/// Bottom-right hot corner geometry, in screen coordinates (origin at the bottom-left of the main screen).
public enum HotCorner {
    /// The pointer stops a point or so short of the screen's edge, so the corner is a small square.
    static let slack: CGFloat = 3

    /// The screen whose bottom-right corner the pointer is pushed into, if any.
    public static func screen(at point: CGPoint, among screens: [CGRect]) -> CGRect? {
        screens.first { frame in
            point.x >= frame.maxX - slack && point.x <= frame.maxX
                && point.y >= frame.minY && point.y <= frame.minY + slack
                && !screens.contains { other in
                    // With a screen right past the corner, the pointer slides on instead of stopping there.
                    other.contains(CGPoint(x: frame.maxX + 1, y: frame.minY + 1))
                        || other.contains(CGPoint(x: frame.maxX - 1, y: frame.minY - 1))
                }
        }
    }
}
