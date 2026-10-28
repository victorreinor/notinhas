import AppKit

/// Borderless so the note is all paper: no title bar, no traffic lights.
final class NoteWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        // Notes are always light paper, so keep controls and popovers light in dark mode too.
        appearance = NSAppearance(named: .aqua)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Paints the rounded paper and the darker header band behind everything else.
final class NoteContentView: NSView {
    var paper = NSColor.white { didSet { needsDisplay = true } }
    var band = NSColor.white { didSet { needsDisplay = true } }
    var bandHeight: CGFloat = 28

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        paper.setFill()
        shape.fill()

        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        band.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: bandHeight).fill()
        NSGraphicsContext.restoreGraphicsState()

        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9.5, yRadius: 9.5)
        NSColor.black.withAlphaComponent(0.1).setStroke()
        outline.stroke()
    }
}

/// Drag anywhere on the header (outside its buttons) to move the note; double-click to collapse it.
final class NoteHeaderView: NSView {
    var onDoubleClick: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        var view: NSView? = hit
        while let current = view, current !== self {
            if current is NSButton { return hit }
            view = current.superview
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
        } else {
            window?.performDrag(with: event)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Borderless SF Symbol button with a soft hover background.
class IconButton: NSButton {
    private var hovering = false { didSet { needsDisplay = true } }

    init(symbol: String?, tooltip: String, target: AnyObject? = nil, action: Selector? = nil, pointSize: CGFloat = 12) {
        super.init(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        self.target = target
        self.action = action
        toolTip = tooltip
        title = ""
        isBordered = false
        imagePosition = .imageOnly
        contentTintColor = NSColor.black.withAlphaComponent(0.55)
        if let symbol {
            setSymbol(symbol, pointSize: pointSize)
        }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 22),
            heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func setSymbol(_ name: String, pointSize: CGFloat = 12) {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        image = NSImage(systemSymbolName: name, accessibilityDescription: toolTip)?.withSymbolConfiguration(configuration)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        if hovering {
            NSColor.black.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
        }
        super.draw(dirtyRect)
    }
}

/// Header button showing the note's current color.
final class ColorDotButton: IconButton {
    var dotColor = NSColor.yellow { didSet { needsDisplay = true } }

    init() {
        super.init(symbol: nil, tooltip: "Cor e opacidade")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let dot = NSBezierPath(ovalIn: NSRect(x: bounds.midX - 6, y: bounds.midY - 6, width: 12, height: 12))
        dotColor.setFill()
        dot.fill()
        NSColor.black.withAlphaComponent(0.3).setStroke()
        dot.stroke()
    }
}

/// Bottom-right handle for resizing (borderless windows have no visible resize affordance).
final class ResizeGrip: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setStroke()
        for inset in [4.0, 8.0, 12.0] {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: bounds.maxX - inset, y: bounds.minY + 1))
            line.line(to: NSPoint(x: bounds.maxX - 1, y: bounds.minY + inset))
            line.lineWidth = 1.2
            line.lineCapStyle = .round
            line.stroke()
        }
    }

    override func resetCursorRects() {
        if #available(macOS 15, *) {
            addCursorRect(bounds, cursor: .frameResize(position: .bottomRight, directions: .all))
        } else {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let startFrame = window.frame
        let startMouse = NSEvent.mouseLocation
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]), next.type != .leftMouseUp {
            let mouse = NSEvent.mouseLocation
            var frame = startFrame
            frame.size.width = max(window.minSize.width, startFrame.width + mouse.x - startMouse.x)
            frame.size.height = max(window.minSize.height, startFrame.height - (mouse.y - startMouse.y))
            frame.origin.y = startFrame.maxY - frame.height
            window.setFrame(frame, display: true)
        }
    }
}
