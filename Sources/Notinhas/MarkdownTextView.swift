import AppKit
import Carbon.HIToolbox
import NotinhasCore

/// The note body: a plain-text NSTextView whose markdown is styled live by `MarkdownStyler`.
final class MarkdownTextView: NSTextView {
    let styler: MarkdownStyler
    // The text system is assembled by hand (TextKit 1, for the custom layout manager),
    // and nothing else in it keeps the storage alive.
    private let ownedStorage: NSTextStorage

    init(ink: NSColor) {
        let storage = NSTextStorage()
        let layoutManager = NoteLayoutManager()
        layoutManager.ink = ink
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        ownedStorage = storage
        styler = MarkdownStyler(ink: ink)
        super.init(frame: .zero, textContainer: container)

        storage.delegate = styler
        styler.textView = self
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticLinkDetectionEnabled = false
        drawsBackground = false
        textContainerInset = NSSize(width: 10, height: 2)
        insertionPointColor = ink
        selectedTextAttributes = [.backgroundColor: ink.withAlphaComponent(0.15)]
        typingAttributes = styler.baseAttributes
        isVerticallyResizable = true
        isHorizontallyResizable = false
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    // MARK: Formatting commands (toolbar buttons and the Formatar menu)

    @objc func mdBold(_ sender: Any?) { runEdit { MarkdownEditing.toggleWrap("**", in: $0, selection: $1) } }
    @objc func mdItalic(_ sender: Any?) { runEdit { MarkdownEditing.toggleWrap("_", in: $0, selection: $1) } }
    @objc func mdStrike(_ sender: Any?) { runEdit { MarkdownEditing.toggleWrap("~~", in: $0, selection: $1) } }
    @objc func mdCode(_ sender: Any?) { runEdit { MarkdownEditing.toggleWrap("`", in: $0, selection: $1) } }
    @objc func mdLink(_ sender: Any?) { runEdit(MarkdownEditing.insertLink(in:selection:)) }
    @objc func mdBulletList(_ sender: Any?) { runEdit { MarkdownEditing.toggleLineStyle(.bullet, in: $0, selection: $1) } }
    @objc func mdChecklist(_ sender: Any?) { runEdit { MarkdownEditing.toggleLineStyle(.checklist, in: $0, selection: $1) } }

    /// Menu items carry the level in their tag; the toolbar button (tag 0) cycles through levels.
    @objc func mdHeading(_ sender: Any?) {
        let level = (sender as? NSMenuItem)?.tag ?? 0
        runEdit { text, selection in
            level > 0
                ? MarkdownEditing.toggleLineStyle(.heading(level), in: text, selection: selection)
                : MarkdownEditing.cycleHeading(in: text, selection: selection)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // ⇧⌘8 produces "*" on most layouts, so a menu key equivalent never matches it.
        if window?.firstResponder === self,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift],
           event.keyCode == UInt16(kVK_ANSI_8) {
            mdBulletList(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: List-aware typing

    override func insertNewline(_ sender: Any?) {
        if let edit = MarkdownEditing.newline(in: string, selection: selectedRange()) {
            apply(edit)
        } else {
            super.insertNewline(sender)
        }
    }

    override func deleteBackward(_ sender: Any?) {
        if let edit = MarkdownEditing.deleteBackward(in: string, selection: selectedRange()) {
            apply(edit)
        } else {
            super.deleteBackward(sender)
        }
    }

    override func insertTab(_ sender: Any?) {
        if let edit = MarkdownEditing.indentListItem(in: string, selection: selectedRange(), outdent: false) {
            apply(edit)
        } else {
            super.insertTab(sender)
        }
    }

    override func insertBacktab(_ sender: Any?) {
        if let edit = MarkdownEditing.indentListItem(in: string, selection: selectedRange(), outdent: true) {
            apply(edit)
        } else {
            super.insertBacktab(sender)
        }
    }

    // MARK: Clicks: checkboxes and ⌘-click on links

    override func mouseDown(with event: NSEvent) {
        if let index = characterIndex(at: convert(event.locationInWindow, from: nil)), let storage = textStorage {
            if storage.attribute(.noteCheckbox, at: index, effectiveRange: nil) != nil,
               let edit = MarkdownEditing.toggleCheckbox(in: string, at: index, selection: selectedRange()) {
                apply(edit)
                return
            }
            if event.modifierFlags.contains(.command), let url = storage.attribute(.noteLink, at: index, effectiveRange: nil) as? URL {
                NSWorkspace.shared.open(url)
                return
            }
        }
        super.mouseDown(with: event)
    }

    /// Index of the character drawn under `point`, or nil when the point is between or past glyphs.
    private func characterIndex(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        guard glyphRect.insetBy(dx: -2, dy: -2).contains(containerPoint) else { return nil }
        let index = layoutManager.characterIndexForGlyph(at: glyph)
        return index < storage.length ? index : nil
    }

    // MARK: Applying edits

    private func runEdit(_ makeEdit: (String, NSRange) -> TextEdit) {
        window?.makeFirstResponder(self)
        apply(makeEdit(string, selectedRange()))
    }

    /// Goes through shouldChangeText/didChangeText so the change is undoable and saved.
    func apply(_ edit: TextEdit) {
        if edit.changesText {
            breakUndoCoalescing()
            guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
            textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
            didChangeText()
        }
        setSelectedRange(edit.selection)
        scrollRangeToVisible(edit.selection)
    }
}

/// Draws checkboxes and bullet dots over the list markers the styler made transparent.
final class NoteLayoutManager: NSLayoutManager {
    var ink = NSColor.black

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.noteCheckbox, in: characters) { value, range, _ in
            guard let checked = value as? Bool, let anchor = self.anchor(for: range, origin: origin) else { return }
            self.drawCheckbox(checked: checked, left: anchor.rect.minX, centerY: anchor.capMiddle)
        }
        storage.enumerateAttribute(.noteBullet, in: characters) { value, range, _ in
            guard value != nil, let anchor = self.anchor(for: range, origin: origin) else { return }
            let dot = NSRect(x: anchor.rect.midX - 2.5, y: anchor.xMiddle - 2.5, width: 5, height: 5)
            self.ink.withAlphaComponent(0.75).setFill()
            NSBezierPath(ovalIn: dot).fill()
        }
    }

    /// Marker bounds plus the vertical middle of capitals and of lowercase letters on its line.
    private func anchor(for characters: NSRange, origin: NSPoint) -> (rect: NSRect, capMiddle: CGFloat, xMiddle: CGFloat)? {
        let glyphs = glyphRange(forCharacterRange: characters, actualCharacterRange: nil)
        guard glyphs.length > 0,
              let container = textContainer(forGlyphAt: glyphs.location, effectiveRange: nil),
              let font = textStorage?.attribute(.font, at: characters.location, effectiveRange: nil) as? NSFont
        else { return nil }
        let line = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let baseline = origin.y + line.minY + location(forGlyphAt: glyphs.location).y
        let rect = boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: origin.x, dy: origin.y)
        return (rect, baseline - font.capHeight / 2, baseline - font.xHeight / 2)
    }

    private func drawCheckbox(checked: Bool, left: CGFloat, centerY: CGFloat) {
        let size: CGFloat = 13
        let box = NSRect(x: left + 0.5, y: centerY - size / 2, width: size, height: size)
        if checked {
            ink.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: box, xRadius: 3.5, yRadius: 3.5).fill()
            // The text view is flipped: larger y is lower on screen.
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: box.minX + 3.2, y: box.minY + 6.8))
            tick.line(to: NSPoint(x: box.minX + 5.6, y: box.minY + 9.3))
            tick.line(to: NSPoint(x: box.minX + 9.9, y: box.minY + 4.0))
            tick.lineWidth = 1.7
            tick.lineCapStyle = .round
            tick.lineJoinStyle = .round
            NSColor.white.setStroke()
            tick.stroke()
        } else {
            let outline = NSBezierPath(roundedRect: box.insetBy(dx: 0.65, dy: 0.65), xRadius: 3, yRadius: 3)
            outline.lineWidth = 1.3
            ink.withAlphaComponent(0.55).setStroke()
            outline.stroke()
        }
    }
}
