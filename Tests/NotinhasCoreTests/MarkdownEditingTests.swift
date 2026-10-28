import Foundation
import Testing
@testable import NotinhasCore

private func applying(_ edit: TextEdit, to text: String) -> String {
    (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
}

private func range(_ location: Int, _ length: Int = 0) -> NSRange {
    NSRange(location: location, length: length)
}

@Suite struct ToggleWrap {
    @Test func wrapsSelection() {
        let edit = MarkdownEditing.toggleWrap("**", in: "oi mundo", selection: range(3, 5))
        #expect(applying(edit, to: "oi mundo") == "oi **mundo**")
        #expect(edit.selection == range(5, 5))
    }

    @Test func keepsWhitespaceOutsideMarkers() {
        let edit = MarkdownEditing.toggleWrap("**", in: "oi mundo", selection: range(2, 6))
        #expect(applying(edit, to: "oi mundo") == "oi **mundo**")
    }

    @Test func unwrapsWhenMarkersAreAroundSelection() {
        let edit = MarkdownEditing.toggleWrap("**", in: "oi **mundo**", selection: range(5, 5))
        #expect(applying(edit, to: "oi **mundo**") == "oi mundo")
        #expect(edit.selection == range(3, 5))
    }

    @Test func unwrapsWhenSelectionIncludesMarkers() {
        let edit = MarkdownEditing.toggleWrap("_", in: "oi _mundo_", selection: range(3, 7))
        #expect(applying(edit, to: "oi _mundo_") == "oi mundo")
    }

    @Test func emptySelectionInsertsPairAndTogglesBack() {
        let first = MarkdownEditing.toggleWrap("**", in: "oi ", selection: range(3))
        let text = applying(first, to: "oi ")
        #expect(text == "oi ****")
        #expect(first.selection == range(5))
        let second = MarkdownEditing.toggleWrap("**", in: text, selection: first.selection)
        #expect(applying(second, to: text) == "oi ")
    }

    @Test func stepsOverClosingMarker() {
        let edit = MarkdownEditing.toggleWrap("**", in: "**forte**", selection: range(7))
        #expect(!edit.changesText)
        #expect(edit.selection == range(9))
    }

    @Test func worksWithMultiByteCharacters() {
        let text = "café ☕️ bom"
        let ns = text as NSString
        let edit = MarkdownEditing.toggleWrap("**", in: text, selection: ns.range(of: "bom"))
        #expect(applying(edit, to: text) == "café ☕️ **bom**")
    }
}

@Suite struct LineStyles {
    @Test func addsAndRemovesBullet() {
        let add = MarkdownEditing.toggleLineStyle(.bullet, in: "item", selection: range(4))
        #expect(applying(add, to: "item") == "- item")
        #expect(add.selection == range(6))
        let remove = MarkdownEditing.toggleLineStyle(.bullet, in: "- item", selection: range(6))
        #expect(applying(remove, to: "- item") == "item")
    }

    @Test func convertsBulletToChecklist() {
        let edit = MarkdownEditing.toggleLineStyle(.checklist, in: "  - item", selection: range(8))
        #expect(applying(edit, to: "  - item") == "  - [ ] item")
    }

    @Test func styleAppliesToEverySelectedLineSkippingBlanks() {
        let text = "a\n\nb\nc"
        let edit = MarkdownEditing.toggleLineStyle(.checklist, in: text, selection: range(0, 6))
        #expect(applying(edit, to: text) == "- [ ] a\n\n- [ ] b\n- [ ] c")
    }

    @Test func selectionEndingInNewlineDoesNotTouchNextLine() {
        let text = "a\nb"
        let edit = MarkdownEditing.toggleLineStyle(.bullet, in: text, selection: range(0, 2))
        #expect(applying(edit, to: text) == "- a\nb")
    }

    @Test func headingCycles() {
        var text = "Título"
        var selection = range(0)
        var seen: [String] = []
        for _ in 0..<4 {
            let edit = MarkdownEditing.cycleHeading(in: text, selection: selection)
            text = applying(edit, to: text)
            selection = edit.selection
            seen.append(text)
        }
        #expect(seen == ["# Título", "## Título", "### Título", "Título"])
    }
}

@Suite struct ListTyping {
    @Test func enterContinuesBullet() {
        let edit = MarkdownEditing.newline(in: "- leite", selection: range(7))
        #expect(edit.map { applying($0, to: "- leite") } == "- leite\n- ")
        #expect(edit?.selection == range(10))
    }

    @Test func enterContinuesChecklistUnchecked() {
        let edit = MarkdownEditing.newline(in: "  * [x] feito", selection: range(13))
        #expect(edit.map { applying($0, to: "  * [x] feito") } == "  * [x] feito\n  * [ ] ")
    }

    @Test func enterIncrementsNumberedList() {
        let edit = MarkdownEditing.newline(in: "9. nove", selection: range(7))
        #expect(edit.map { applying($0, to: "9. nove") } == "9. nove\n10. ")
    }

    @Test func enterOnEmptyItemEndsList() {
        let text = "- a\n- [ ] "
        let edit = MarkdownEditing.newline(in: text, selection: range(10))
        #expect(edit.map { applying($0, to: text) } == "- a\n")
        #expect(edit?.selection == range(4))
    }

    @Test func enterOutsideListsIsLeftAlone() {
        #expect(MarkdownEditing.newline(in: "texto", selection: range(5)) == nil)
        #expect(MarkdownEditing.newline(in: "- a", selection: range(1)) == nil)
    }

    @Test func backspaceRemovesWholeMarker() {
        let edit = MarkdownEditing.deleteBackward(in: "  - [ ] ", selection: range(8))
        #expect(edit.map { applying($0, to: "  - [ ] ") } == "  ")
        #expect(MarkdownEditing.deleteBackward(in: "- a", selection: range(3)) == nil)
    }

    @Test func tabNestsAndShiftTabUnnests() {
        let indent = MarkdownEditing.indentListItem(in: "- a", selection: range(3), outdent: false)
        #expect(indent.map { applying($0, to: "- a") } == "  - a")
        let outdent = MarkdownEditing.indentListItem(in: "  - a", selection: range(5), outdent: true)
        #expect(outdent.map { applying($0, to: "  - a") } == "- a")
        #expect(MarkdownEditing.indentListItem(in: "a", selection: range(1), outdent: false) == nil)
    }

    @Test func checkboxToggles() {
        let text = "x\n- [ ] tarefa"
        let check = MarkdownEditing.toggleCheckbox(in: text, at: 4, selection: range(0))
        let checked = check.map { applying($0, to: text) }
        #expect(checked == "x\n- [x] tarefa")
        let uncheck = MarkdownEditing.toggleCheckbox(in: checked!, at: 3, selection: range(0))
        #expect(uncheck.map { applying($0, to: checked!) } == text)
        #expect(MarkdownEditing.toggleCheckbox(in: "- item", at: 0, selection: range(0)) == nil)
    }
}

@Suite struct Parsing {
    @Test func listPrefixes() {
        #expect(MarkdownEditing.listPrefix(in: "- a")?.kind == .bullet)
        #expect(MarkdownEditing.listPrefix(in: "- [X] a")?.kind == .checklist(checked: true))
        #expect(MarkdownEditing.listPrefix(in: "12. a")?.kind == .numbered(12))
        #expect(MarkdownEditing.listPrefix(in: "-a") == nil)
        #expect(MarkdownEditing.listPrefix(in: "**bold**") == nil)
        #expect(MarkdownEditing.listPrefix(in: "  - [ ] a")?.markerRange == NSRange(location: 2, length: 5))
    }

    @Test func plainTitleStripsMarkdown() {
        #expect(MarkdownEditing.plainTitle(fromBody: "\n## **Compras** da _semana_\nresto") == "Compras da semana")
        #expect(MarkdownEditing.plainTitle(fromBody: "- [ ] ligar") == "ligar")
    }
}

@Suite struct Storage {
    @Test func roundTripsAndDeletes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteStore(directory: directory)
        let note = Note(title: "t", body: "- [ ] b", color: .pink, pinned: true, frame: CGRect(x: 1, y: 2, width: 3, height: 4))
        try store.save(note)
        let loaded = store.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded.first?.title == "t")
        #expect(loaded.first?.color == .pink)
        #expect(loaded.first?.frame == note.frame)
        store.delete(id: note.id)
        #expect(store.loadAll().isEmpty)
    }

    @Test func decodesNotesMissingNewerFields() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","body":"oi","color":"unknown"}"#
        let note = try JSONDecoder().decode(Note.self, from: Data(json.utf8))
        #expect(note.body == "oi")
        #expect(note.color == .yellow)
        #expect(note.opacity == 1)
    }
}
