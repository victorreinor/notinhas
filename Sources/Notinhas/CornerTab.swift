import AppKit
import NotinhasCore

/// Like macOS's Quick Note corner: pushing the pointer into the bottom-right corner slides out a small
/// note, and clicking it brings every note forward. Off by default (the ⋯ menu turns it on), since
/// macOS ships Quick Note in that same corner.
final class CornerTab {
    private static let enabledKey = "cornerTabEnabled"
    private static let size = CGSize(width: 80, height: 80)

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            update()
        }
    }

    private let onOpen: () -> Void
    private var monitor: Any?
    private var panel: NSPanel?
    private var hideTimer: Timer?
    private var isShown = false
    /// Cleared when the tab shows, so it waits for the pointer to leave the corner before showing again.
    private var armed = true

    init(onOpen: @escaping () -> Void) {
        self.onOpen = onOpen
        update()
    }

    private func update() {
        if isEnabled, monitor == nil {
            // Global mouse monitors (unlike key monitors) need no Accessibility permission.
            monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
                self?.pointerMoved()
            }
        } else if !isEnabled, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
            hide()
        }
    }

    private func pointerMoved() {
        guard let screen = HotCorner.screen(at: NSEvent.mouseLocation, among: NSScreen.screens.map(\.frame)) else {
            armed = true
            return
        }
        guard armed, !isShown else { return }
        armed = false
        show(in: screen)
    }

    private func show(in screen: CGRect) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        isShown = true
        let frame = CGRect(origin: CGPoint(x: screen.maxX - Self.size.width, y: screen.minY), size: Self.size)
        panel.setFrame(Self.tucked(frame), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let panel = self.panel else { return }
            if !panel.frame.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation) { self.hide() }
        }
    }

    /// Slides the tab back into the corner.
    private func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        guard isShown, let panel else { return }
        isShown = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().setFrame(Self.tucked(panel.frame), display: true)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            if self?.isShown == false { panel.orderOut(nil) }
        }
    }

    /// Where the tab hides: half of it past the screen's corner.
    private static func tucked(_ frame: CGRect) -> CGRect {
        frame.offsetBy(dx: size.width / 2, dy: -size.height / 2)
    }

    private func makePanel() -> NSPanel {
        // Non-activating, so the tab shows up without taking focus from the app in front.
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        // Stays available while ⌘Q has the notes hidden.
        panel.canHide = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let view = CornerTabView()
        view.onClick = { [weak self] in
            self?.hide()
            self?.onOpen()
        }
        panel.contentView = view
        return panel
    }
}

/// A tilted yellow note whose top-left corner peeks out of the screen corner.
final class CornerTabView: NSView {
    var onClick: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        let tilt = NSAffineTransform()
        tilt.translateX(by: bounds.maxX, yBy: bounds.minY)
        tilt.rotate(byDegrees: 8)
        tilt.translateX(by: -bounds.maxX, yBy: -bounds.minY)
        tilt.concat()

        let paper = NSRect(x: 20, y: -50, width: 110, height: 112)
        let shape = NSBezierPath(roundedRect: paper, xRadius: 10, yRadius: 10)
        NoteColor.yellow.paper.setFill()
        shape.fill()
        shape.addClip()
        NoteColor.yellow.band.setFill()
        NSRect(x: paper.minX, y: paper.maxY - 14, width: paper.width, height: 14).fill()
        NSColor.black.withAlphaComponent(0.16).setFill()
        for (index, width) in [34.0, 26, 30].enumerated() {
            let line = NSRect(x: paper.minX + 12, y: paper.maxY - 28 - CGFloat(index) * 9, width: width, height: 3)
            NSBezierPath(roundedRect: line, xRadius: 1.5, yRadius: 1.5).fill()
        }
        NSColor.black.withAlphaComponent(0.1).setStroke()
        NSBezierPath(roundedRect: paper.insetBy(dx: 0.5, dy: 0.5), xRadius: 9.5, yRadius: 9.5).stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
