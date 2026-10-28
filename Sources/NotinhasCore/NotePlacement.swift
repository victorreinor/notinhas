import CoreGraphics

/// Where note windows go as monitors come and go. A note's saved frame is its home: while no screen
/// shows it (its monitor is unplugged), the window waits on another screen, and it goes back home
/// once a screen shows that spot again. Frames are in screen coordinates.
public enum NotePlacement {
    /// The frame each window should move to, or nil to leave it. `screens` are the visible frames of
    /// the connected screens; notes away from home cascade from the top-right of `fallback`.
    public static func targets(homes: [CGRect], windows: [CGRect], screens: [CGRect], fallback: CGRect) -> [CGRect?] {
        var waiting = 0
        return zip(homes, windows).map { home, window in
            var target = home
            if !screens.contains(where: { $0.intersects(home) }) {
                let step = CGFloat(waiting % 6) * 28
                waiting += 1
                target.origin = CGPoint(x: fallback.maxX - home.width - 48 - step, y: fallback.maxY - home.height - 48 - step)
            }
            return window == target ? nil : target
        }
    }
}
