import AppKit

/// The app runs without a menu bar or Dock icon, but key equivalents (⌘C, ⌘Z, ⌘B…) are
/// still dispatched through the main menu, so it is built even though it is never shown.
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu("Notinhas", [
            item("Sair do Notinhas", #selector(NSApplication.terminate(_:)), "q"),
        ]))
        main.addItem(submenu("Arquivo", [
            item("Nova nota", #selector(AppDelegate.newNote(_:)), "n"),
        ]))
        main.addItem(submenu("Editar", [
            item("Desfazer", Selector(("undo:")), "z"),
            item("Refazer", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Recortar", #selector(NSText.cut(_:)), "x"),
            item("Copiar", #selector(NSText.copy(_:)), "c"),
            item("Colar", #selector(NSText.paste(_:)), "v"),
            item("Selecionar tudo", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item("Buscar…", #selector(NSTextView.performFindPanelAction(_:)), "f",
                 tag: NSTextFinder.Action.showFindInterface.rawValue),
            item("Buscar próximo", #selector(NSTextView.performFindPanelAction(_:)), "g",
                 tag: NSTextFinder.Action.nextMatch.rawValue),
        ]))
        main.addItem(submenu("Formatar", [
            item("Negrito", #selector(MarkdownTextView.mdBold(_:)), "b"),
            item("Itálico", #selector(MarkdownTextView.mdItalic(_:)), "i"),
            item("Tachado", #selector(MarkdownTextView.mdStrike(_:)), "x", [.command, .shift]),
            item("Código", #selector(MarkdownTextView.mdCode(_:)), "e"),
            item("Link", #selector(MarkdownTextView.mdLink(_:)), "k"),
            .separator(),
            item("Título 1", #selector(MarkdownTextView.mdHeading(_:)), "1", tag: 1),
            item("Título 2", #selector(MarkdownTextView.mdHeading(_:)), "2", tag: 2),
            item("Título 3", #selector(MarkdownTextView.mdHeading(_:)), "3", tag: 3),
            .separator(),
            item("Checklist", #selector(MarkdownTextView.mdChecklist(_:)), "l", [.command, .shift]),
        ]))
        return main
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(
        _ title: String,
        _ action: Selector,
        _ key: String,
        _ modifiers: NSEvent.ModifierFlags = .command,
        tag: Int = 0
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.tag = tag
        return item
    }
}
