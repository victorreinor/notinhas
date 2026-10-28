import AppKit
import NotinhasCore

/// Development aid behind scripts/screenshots.sh: `NOTINHAS_SNAPSHOT_DIR=dir Notinhas` renders the
/// README images from the real note views, offscreen, and quits. Needs no Screen Recording permission.
enum Snapshot {
    static func render(into directory: String) {
        let folder = URL(fileURLWithPath: directory)
        save(hero(), as: .jpeg, to: folder.appendingPathComponent("hero.jpg"))
        save(markdown(), as: .png, to: folder.appendingPathComponent("markdown.png"))
        save(colors(), as: .png, to: folder.appendingPathComponent("colors.png"))
    }

    // MARK: Scenes

    /// A few notes on a wallpaper-like background: one focused, one translucent, two collapsed.
    private static func hero() -> NSBitmapImageRep {
        let size = NSSize(width: 1200, height: 520)
        let scene: [(note: Note, origin: NSPoint, focused: Bool)] = [
            (note("Ideias", """
            # Projetos
            - App de **receitas**
            - Viagem pra _Floripa_
            - Ler [Shape Up](https://basecamp.com/shapeup)
            """, .green, width: 280, height: 250, opacity: 0.85), NSPoint(x: 820, y: 195), false),
            (note("Aniversário da Ana", "", .purple, width: 270, collapsed: true), NSPoint(x: 820, y: 115), false),
            (note("Sprint 42", """
            ## Esta semana
            - [x] Revisar PR do **login**
            - [ ] Deploy em _homolog_
            - [ ] Atualizar `CHANGELOG.md`

            > daily às 9h30
            """, .blue, width: 300, height: 270), NSPoint(x: 470, y: 155), false),
            (note("Ligar pro dentista", "", .pink, width: 300, collapsed: true), NSPoint(x: 470, y: 75), false),
            (note("Mercado da semana", """
            - [ ] Café
            - [x] Pão
            - [ ] Frutas: **banana** e maçã
            - [ ] ~~Leite~~ Leite sem lactose

            Gastar até `R$ 150`
            """, .yellow, width: 290, height: 300, pinned: true), NSPoint(x: 120, y: 115), true),
        ]
        return canvas(size) {
            drawWallpaper(in: NSRect(origin: .zero, size: size))
            for item in scene {
                place(image(of: item.note, focused: item.focused), at: item.origin, opacity: item.note.opacity)
            }
        }
    }

    private static func markdown() -> NSBitmapImageRep {
        let body = """
        ## Hoje
        - [ ] Comprar **café** e pão
        - [x] Pagar a conta de luz
        - Ligar pro _João_ sobre o ~~orçamento~~ projeto
        1. Revisar `deploy.sh`
        > ver [docs](https://example.com) depois
        """
        let image = image(of: note("Markdown ao vivo", body, .yellow, width: 300, height: 320, pinned: true), focused: true)
        let margin: CGFloat = 40
        return canvas(NSSize(width: image.size.width + margin * 2, height: image.size.height + margin * 2)) {
            place(image, at: NSPoint(x: margin, y: margin + 6))
        }
    }

    /// The color popover next to a collapsed note of every color.
    private static func colors() -> NSBitmapImageRep {
        let picker = image(of: ColorPickerController(selected: .yellow, opacity: 0.85).view)
        let strips = NoteColor.allCases.map { image(of: note($0.displayName, "", $0, width: 230, collapsed: true), focused: false) }
        let margin: CGFloat = 36
        let spacing: CGFloat = 10
        let stripHeight = strips.first?.size.height ?? 28
        let stackHeight = CGFloat(strips.count) * (stripHeight + spacing) - spacing
        let size = NSSize(
            width: margin + picker.size.width + 40 + 230 + margin,
            height: margin * 2 + max(stackHeight, picker.size.height))
        return canvas(size) {
            let card = NSRect(origin: NSPoint(x: margin, y: (size.height - picker.size.height) / 2), size: picker.size)
            withShadow {
                NSColor.white.setFill()
                NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12).fill()
            }
            picker.draw(in: card)
            for (index, strip) in strips.enumerated() {
                let y = size.height - margin - stripHeight - CGFloat(index) * (stripHeight + spacing)
                place(strip, at: NSPoint(x: card.maxX + 40, y: y))
            }
        }
    }

    // MARK: Rendering

    private static func note(
        _ title: String, _ body: String, _ color: NoteColor,
        width: CGFloat, height: CGFloat = 240, pinned: Bool = false, collapsed: Bool = false, opacity: Double = 1
    ) -> Note {
        Note(title: title, body: body, color: color, opacity: opacity, pinned: pinned, collapsed: collapsed,
             frame: CGRect(x: 0, y: 0, width: width, height: height))
    }

    private static func image(of note: Note, focused: Bool) -> NSImage {
        let controller = NoteWindowController(note: note)
        controller.setToolsVisible(focused, animated: false)
        return snapshot(controller.window.contentView!)
    }

    /// Hosts the view in an offscreen window so it renders at the screen's backing scale.
    private static func image(of view: NSView) -> NSImage {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: view.fittingSize), styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = view
        return snapshot(view)
    }

    private static func snapshot(_ view: NSView) -> NSImage {
        view.layoutSubtreeIfNeeded()
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(bitmap)
        return image
    }

    private static func canvas(_ size: NSSize, scale: CGFloat = 2, draw: () -> Void) -> NSBitmapImageRep {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    private static func place(_ image: NSImage, at origin: NSPoint, opacity: Double = 1) {
        withShadow {
            image.draw(in: NSRect(origin: origin, size: image.size), from: .zero, operation: .sourceOver, fraction: opacity)
        }
    }

    private static func withShadow(_ draw: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        shadow.set()
        draw()
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawWallpaper(in rect: NSRect) {
        NSGradient(colors: [0x23304F, 0x4E4A8C, 0xB97C9B, 0xF0B58F].map { NSColor(hex: $0) })!.draw(in: rect, angle: 30)
        for (x, y, radius, hex, alpha) in [(0.85, 0.9, 460.0, 0xFFD7A8, 0.35), (0.1, 0.05, 420.0, 0x6EC6FF, 0.25)] as [(CGFloat, CGFloat, CGFloat, UInt32, CGFloat)] {
            let center = NSPoint(x: rect.width * x, y: rect.height * y)
            let color = NSColor(hex: hex)
            NSGradient(colors: [color.withAlphaComponent(alpha), color.withAlphaComponent(0)])!
                .draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
        }
    }

    private static func save(_ bitmap: NSBitmapImageRep, as type: NSBitmapImageRep.FileType, to url: URL) {
        let properties: [NSBitmapImageRep.PropertyKey: Any] = type == .jpeg ? [.compressionFactor: 0.88] : [:]
        do {
            try bitmap.representation(using: type, properties: properties)?.write(to: url)
        } catch {
            NSLog("Notinhas: failed to write \(url.path): \(error)")
        }
    }
}
