import AppKit
import NotinhasCore

extension NoteColor {
    var displayName: String {
        switch self {
        case .yellow: "Amarelo"
        case .orange: "Laranja"
        case .pink: "Rosa"
        case .purple: "Roxo"
        case .blue: "Azul"
        case .green: "Verde"
        case .gray: "Cinza"
        }
    }

    var paper: NSColor { NSColor(hex: palette.paper) }
    var band: NSColor { NSColor(hex: palette.band) }
    var dot: NSColor { NSColor(hex: palette.dot) }

    private var palette: (paper: UInt32, band: UInt32, dot: UInt32) {
        switch self {
        case .yellow: (0xFFF4A3, 0xFBE57D, 0xF2C230)
        case .orange: (0xFFE0BF, 0xFDCB98, 0xF59E42)
        case .pink: (0xFFD9E6, 0xFCC2D6, 0xEE6E9B)
        case .purple: (0xE9DEFF, 0xD9C7FD, 0x9B72F0)
        case .blue: (0xD3EBFF, 0xB9DBFC, 0x4A9BEA)
        case .green: (0xD8F3C8, 0xC1E8AB, 0x5CB85C)
        case .gray: (0xEEEEEC, 0xDDDDDA, 0x9A9A96)
        }
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
    }
}

/// Popover content: color swatches plus an opacity slider.
final class ColorPickerController: NSViewController {
    var onColor: ((NoteColor) -> Void)?
    var onOpacity: ((Double) -> Void)?

    private var selected: NoteColor
    private let opacity: Double
    private var swatches: [SwatchButton] = []

    init(selected: NoteColor, opacity: Double) {
        self.selected = selected
        self.opacity = opacity
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func loadView() {
        swatches = NoteColor.allCases.map { color in
            let swatch = SwatchButton(color: color, target: self, action: #selector(pick(_:)))
            swatch.isChosen = color == selected
            return swatch
        }
        let swatchRow = NSStackView(views: swatches)
        swatchRow.spacing = 4

        let label = NSTextField(labelWithString: "Opacidade")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        let slider = NSSlider(value: opacity, minValue: 0.3, maxValue: 1, target: self, action: #selector(slide(_:)))
        slider.controlSize = .small
        let opacityRow = NSStackView(views: [label, slider])
        opacityRow.spacing = 8

        let stack = NSStackView(views: [swatchRow, opacityRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        slider.trailingAnchor.constraint(equalTo: swatchRow.trailingAnchor).isActive = true
        view = stack
        preferredContentSize = stack.fittingSize
    }

    @objc private func pick(_ sender: SwatchButton) {
        selected = sender.color
        swatches.forEach { $0.isChosen = $0.color == selected }
        onColor?(sender.color)
    }

    @objc private func slide(_ sender: NSSlider) {
        onOpacity?(sender.doubleValue)
    }
}

final class SwatchButton: NSButton {
    let color: NoteColor
    var isChosen = false { didSet { needsDisplay = true } }

    init(color: NoteColor, target: AnyObject, action: Selector) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
        self.target = target
        self.action = action
        title = ""
        isBordered = false
        toolTip = color.displayName
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 26),
            heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 4, dy: 4))
        color.paper.setFill()
        circle.fill()
        circle.lineWidth = 1.5
        color.dot.setStroke()
        circle.stroke()
        if isChosen {
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
            ring.lineWidth = 1.5
            NSColor.black.withAlphaComponent(0.55).setStroke()
            ring.stroke()
        }
    }
}
