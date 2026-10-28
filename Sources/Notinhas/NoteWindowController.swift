import AppKit
import NotinhasCore

/// One sticky note: its window, its views and its saved state.
final class NoteWindowController: NSObject, NSWindowDelegate, NSTextViewDelegate, NSTextFieldDelegate {
    static let ink = NSColor(srgbRed: 0.17, green: 0.15, blue: 0.12, alpha: 1)
    private static let headerHeight: CGFloat = 28
    private static let minHeight: CGFloat = 120

    private(set) var note: Note
    let window: NoteWindow

    var onChange: ((Note) -> Void)?
    var onNewNote: ((NoteWindowController) -> Void)?
    var onDelete: ((NoteWindowController) -> Void)?
    var onShowAll: (() -> Void)?
    var cornerTab: CornerTab?

    private let content = NoteContentView()
    private let header = NoteHeaderView()
    private let body = NSView()
    private let titleField = NSTextField()
    private let collapsedTitle = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private let textView = MarkdownTextView(ink: NoteWindowController.ink)
    private let formatBar = NSStackView()
    private let colorButton = ColorDotButton()
    private let pinButton = IconButton(symbol: "pin", tooltip: "")
    private var bodyBottom: NSLayoutConstraint!
    private var pendingSave: DispatchWorkItem?
    /// Set while `rise` animates the window, so the in-between frames aren't saved as moves.
    private var isRising = false

    init(note: Note) {
        self.note = note
        window = NoteWindow(contentRect: note.frame)
        super.init()
        window.delegate = self
        buildViews()
        titleField.stringValue = note.title
        textView.string = note.body
        applyColor()
        applyPin()
        applyCollapsed(animated: false)
        window.layoutIfNeeded()
        fitTextViewToScrollView()
    }

    func focusBody() {
        if note.collapsed { toggleCollapse() }
        window.makeFirstResponder(textView)
    }

    func setToolsVisible(_ visible: Bool, animated: Bool = true) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? 0.15 : 0
            formatBar.animator().alphaValue = visible ? 1 : 0
        }
    }

    func flushPendingSave() {
        if pendingSave != nil { saveNow() }
    }

    /// Fades the note in as it rises into place. Call it before ordering the window front.
    func rise(after delay: TimeInterval) {
        guard !isRising else { return }
        isRising = true
        let target = window.frame
        window.alphaValue = 0
        window.setFrame(target.offsetBy(dx: 0, dy: -28), display: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.32
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
                window.animator().setFrame(target, display: true)
                window.animator().alphaValue = CGFloat(note.opacity)
            } completionHandler: { [self] in
                isRising = false
            }
        }
    }

    func close() {
        pendingSave?.cancel()
        pendingSave = nil
        onChange = nil
        window.delegate = nil
        window.orderOut(nil)
        window.close()
    }

    // MARK: Layout

    private func buildViews() {
        window.contentView = content
        content.bandHeight = Self.headerHeight

        let plus = IconButton(symbol: "plus", tooltip: "Nova nota (⌃⌥N)", target: self, action: #selector(newNote))
        colorButton.target = self
        colorButton.action = #selector(showColors(_:))
        pinButton.target = self
        pinButton.action = #selector(togglePin)
        let more = IconButton(symbol: "ellipsis", tooltip: "Mais opções", target: self, action: #selector(showMenu(_:)))
        let leftButtons = NSStackView(views: [plus, colorButton])
        let rightButtons = NSStackView(views: [pinButton, more])
        leftButtons.spacing = 2
        rightButtons.spacing = 2

        collapsedTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        collapsedTitle.textColor = Self.ink.withAlphaComponent(0.75)
        collapsedTitle.lineBreakMode = .byTruncatingTail
        collapsedTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        header.onDoubleClick = { [weak self] in self?.toggleCollapse() }

        let titleFont = NSFont.systemFont(ofSize: 15, weight: .semibold)
        titleField.font = titleFont
        titleField.textColor = Self.ink
        titleField.placeholderAttributedString = NSAttributedString(
            string: "Título",
            attributes: [.font: titleFont, .foregroundColor: Self.ink.withAlphaComponent(0.3)])
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.focusRingType = .none
        titleField.lineBreakMode = .byTruncatingTail
        titleField.cell?.usesSingleLineMode = true
        titleField.cell?.isScrollable = true
        titleField.delegate = self

        textView.delegate = self
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        // Keep the text view as wide as the note and at least as tall, so clicking anywhere on the paper starts typing.
        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(fitTextViewToScrollView),
            name: NSView.frameDidChangeNotification, object: scrollView.contentView)

        let tools: [(symbol: String, tip: String, action: Selector)] = [
            ("bold", "Negrito  ⌘B", #selector(MarkdownTextView.mdBold(_:))),
            ("italic", "Itálico  ⌘I", #selector(MarkdownTextView.mdItalic(_:))),
            ("strikethrough", "Tachado  ⇧⌘X", #selector(MarkdownTextView.mdStrike(_:))),
            ("textformat.size", "Título  ⌘1 ⌘2 ⌘3", #selector(MarkdownTextView.mdHeading(_:))),
            ("list.bullet", "Lista  ⇧⌘8", #selector(MarkdownTextView.mdBulletList(_:))),
            ("checklist", "Checklist  ⇧⌘L", #selector(MarkdownTextView.mdChecklist(_:))),
            ("chevron.left.forwardslash.chevron.right", "Código  ⌘E", #selector(MarkdownTextView.mdCode(_:))),
            ("link", "Link  ⌘K (⌘-clique abre)", #selector(MarkdownTextView.mdLink(_:))),
        ]
        formatBar.setViews(
            tools.map { IconButton(symbol: $0.symbol, tooltip: $0.tip, target: textView, action: $0.action, pointSize: 11) },
            in: .leading)
        formatBar.spacing = 0
        formatBar.alphaValue = 0
        let grip = ResizeGrip()

        for view in [header, body] { add(view, to: content) }
        for view in [leftButtons, rightButtons, collapsedTitle] { add(view, to: header) }
        for view in [titleField, scrollView, formatBar, grip] { add(view, to: body) }

        bodyBottom = body.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: content.topAnchor),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: Self.headerHeight),
            leftButtons.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 5),
            leftButtons.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            rightButtons.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -5),
            rightButtons.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            collapsedTitle.leadingAnchor.constraint(equalTo: leftButtons.trailingAnchor, constant: 6),
            collapsedTitle.trailingAnchor.constraint(lessThanOrEqualTo: rightButtons.leadingAnchor, constant: -6),
            collapsedTitle.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            body.topAnchor.constraint(equalTo: header.bottomAnchor),
            body.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: content.trailingAnchor),

            titleField.topAnchor.constraint(equalTo: body.topAnchor, constant: 8),
            titleField.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 13),
            titleField.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -13),

            scrollView.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: formatBar.topAnchor, constant: -2),

            formatBar.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 7),
            formatBar.trailingAnchor.constraint(lessThanOrEqualTo: grip.leadingAnchor, constant: -4),
            formatBar.bottomAnchor.constraint(equalTo: body.bottomAnchor, constant: -5),
            formatBar.heightAnchor.constraint(equalToConstant: 22),

            grip.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -4),
            grip.bottomAnchor.constraint(equalTo: body.bottomAnchor, constant: -4),
            grip.widthAnchor.constraint(equalToConstant: 12),
            grip.heightAnchor.constraint(equalToConstant: 12),
        ])
    }

    private func add(_ view: NSView, to parent: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(view)
    }

    @objc private func fitTextViewToScrollView() {
        let size = scrollView.contentSize
        textView.minSize = NSSize(width: 0, height: size.height)
        textView.setFrameSize(NSSize(width: size.width, height: textView.frame.height))
        textView.sizeToFit()
    }

    // MARK: Applying note state

    private func applyColor() {
        content.paper = note.color.paper
        content.band = note.color.band
        colorButton.dotColor = note.color.dot
        window.alphaValue = CGFloat(note.opacity)
        window.invalidateShadow()
    }

    private func applyPin() {
        // Pinned notes float over every app, on every desktop and over full-screen apps.
        window.level = note.pinned ? .floating : .normal
        window.collectionBehavior = note.pinned ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
        pinButton.setSymbol(note.pinned ? "pin.fill" : "pin")
        pinButton.contentTintColor = NSColor.black.withAlphaComponent(note.pinned ? 0.85 : 0.45)
        pinButton.toolTip = note.pinned ? "Desafixar" : "Fixar por cima de tudo"
    }

    private func applyCollapsed(animated: Bool) {
        let headerHeight = Self.headerHeight
        var frame = window.frame
        if note.collapsed {
            if frame.height > headerHeight + 1 { note.expandedHeight = frame.height }
            if window.firstResponder is NSText { window.makeFirstResponder(nil) }
            body.isHidden = true
            bodyBottom.isActive = false
            collapsedTitle.stringValue = displayTitle
            collapsedTitle.isHidden = false
            window.minSize = NSSize(width: 220, height: headerHeight)
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: headerHeight)
            frame.origin.y = frame.maxY - headerHeight
            frame.size.height = headerHeight
            window.setFrame(frame, display: true, animate: animated)
        } else {
            collapsedTitle.isHidden = true
            window.minSize = NSSize(width: 220, height: Self.minHeight)
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            if frame.height <= headerHeight + 1 {
                let height = max(note.expandedHeight ?? 240, Self.minHeight)
                frame.origin.y = frame.maxY - height
                frame.size.height = height
                window.setFrame(frame, display: true, animate: animated)
            }
            bodyBottom.isActive = true
            body.isHidden = false
        }
        window.invalidateShadow()
    }

    private var displayTitle: String {
        let title = note.title.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty { return title }
        let fromBody = MarkdownEditing.plainTitle(fromBody: note.body)
        return fromBody.isEmpty ? "Nota" : fromBody
    }

    // MARK: Saving

    private func noteChanged() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        note.updatedAt = Date()
        onChange?(note)
    }

    // MARK: Header actions

    @objc private func newNote() {
        onNewNote?(self)
    }

    @objc private func togglePin() {
        note.pinned.toggle()
        applyPin()
        noteChanged()
    }

    @objc private func toggleCollapse() {
        note.collapsed.toggle()
        applyCollapsed(animated: true)
        noteChanged()
    }

    @objc private func showColors(_ sender: NSButton) {
        let picker = ColorPickerController(selected: note.color, opacity: note.opacity)
        picker.onColor = { [weak self] color in
            self?.note.color = color
            self?.applyColor()
            self?.noteChanged()
        }
        picker.onOpacity = { [weak self] opacity in
            self?.note.opacity = opacity
            self?.applyColor()
            self?.noteChanged()
        }
        let popover = NSPopover()
        popover.contentViewController = picker
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .aqua)
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: sender.isFlipped ? .maxY : .minY)
    }

    @objc private func showMenu(_ sender: NSButton) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        @discardableResult
        func add(_ title: String, _ action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = []) -> NSMenuItem {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = self
            return item
        }
        add("Nova nota", #selector(newNote), key: "n", modifiers: [.control, .option])
        add(note.collapsed ? "Expandir nota" : "Recolher nota", #selector(toggleCollapse))
        add(note.pinned ? "Desafixar" : "Fixar por cima de tudo", #selector(togglePin))
        menu.addItem(.separator())
        add("Mostrar todas as notas", #selector(showAll))
        add("Abrir ao iniciar o Mac", #selector(toggleLoginItem)).state = LoginItem.isEnabled ? .on : .off
        let corner = add("Abrir pelo canto da tela", #selector(toggleCornerTab))
        corner.state = cornerTab?.isEnabled == true ? .on : .off
        corner.toolTip = "Leve o mouse ao canto inferior direito da tela e clique na nota que aparece"
        let quitKey = add("⌘Q esconde as notas em vez de sair", #selector(toggleQuitKey))
        quitKey.state = MainMenu.quitKeyHides ? .on : .off
        quitKey.toolTip = "O app continua rodando, com a aba do canto e o ⌃⌥N. Para fechar, use Sair do Notinhas."
        menu.addItem(.separator())
        add("Excluir nota…", #selector(deleteNote))
        add("Esconder as notas", #selector(hideNotes), key: MainMenu.quitKeyHides ? "q" : "", modifiers: .command)
        add("Sair do Notinhas", #selector(quit), key: MainMenu.quitKeyHides ? "" : "q", modifiers: .command)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.isFlipped ? sender.bounds.maxY + 4 : -4), in: sender)
    }

    @objc private func showAll() {
        onShowAll?()
    }

    @objc private func toggleLoginItem() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
    }

    @objc private func toggleCornerTab() {
        cornerTab?.isEnabled.toggle()
    }

    @objc private func deleteNote() {
        let isEmpty = note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !isEmpty {
            let alert = NSAlert()
            alert.messageText = "Excluir esta nota?"
            alert.informativeText = "Não dá para desfazer."
            alert.addButton(withTitle: "Excluir").hasDestructiveAction = true
            alert.addButton(withTitle: "Cancelar")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        onDelete?(self)
    }

    @objc private func toggleQuitKey() {
        MainMenu.quitKeyHides.toggle()
    }

    @objc private func hideNotes() {
        NSApp.hide(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard !isRising else { return }
        note.frame = window.frame
        noteChanged()
    }

    func windowDidResize(_ notification: Notification) {
        note.frame = window.frame
        window.invalidateShadow()
        noteChanged()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        setToolsVisible(true)
    }

    func windowDidResignKey(_ notification: Notification) {
        setToolsVisible(false)
    }

    // MARK: Text delegates

    func textDidChange(_ notification: Notification) {
        note.body = textView.string
        noteChanged()
    }

    func controlTextDidChange(_ notification: Notification) {
        note.title = titleField.stringValue
        noteChanged()
    }

    /// Enter or Tab in the title jumps to the body.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.insertTab(_:)) else {
            return false
        }
        window.makeFirstResponder(self.textView)
        return true
    }
}
