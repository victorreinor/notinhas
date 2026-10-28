import Foundation

/// A replacement in the note text plus where the selection lands afterwards.
/// Ranges are UTF-16 based, like NSString and NSTextView.
public struct TextEdit: Equatable {
    public var range: NSRange
    public var replacement: String
    public var selection: NSRange

    public init(range: NSRange, replacement: String, selection: NSRange) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }

    /// An edit that only moves the cursor.
    public static func select(_ selection: NSRange) -> TextEdit {
        TextEdit(range: NSRange(location: selection.location, length: 0), replacement: "", selection: selection)
    }

    public var changesText: Bool { range.length > 0 || !replacement.isEmpty }
}

public struct ListPrefix: Equatable {
    public enum Kind: Equatable {
        case bullet
        case checklist(checked: Bool)
        case numbered(Int)
    }

    public var kind: Kind
    public var indent: String
    public var bullet: String
    /// UTF-16 length of the whole prefix, indentation and trailing space included.
    public var length: Int
    /// Range, relative to the line start, of what gets drawn as a bullet or checkbox ("-", "- [ ]" or "1.").
    public var markerRange: NSRange

    /// Prefix for the next item when Enter is pressed on this one.
    public var continuation: String {
        switch kind {
        case .bullet: return indent + bullet + " "
        case .checklist: return indent + bullet + " [ ] "
        case .numbered(let number): return indent + "\(number + 1). "
        }
    }
}

public enum LineStyle: Equatable {
    case bullet
    case checklist
    case heading(Int)
}

public enum MarkdownEditing {
    private static let listPattern = try! NSRegularExpression(
        pattern: #"^([ \t]*)(?:([-*+]) \[([ xX])\] |([-*+]) |(\d{1,9})\. )"#)
    private static let headingPattern = try! NSRegularExpression(pattern: #"^(#{1,6}) "#)

    // MARK: Parsing

    public static func listPrefix(in line: String) -> ListPrefix? {
        let ns = line as NSString
        guard let match = listPattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        let indentRange = match.range(at: 1)
        let indent = ns.substring(with: indentRange)
        if match.range(at: 2).location != NSNotFound {
            return ListPrefix(
                kind: .checklist(checked: ns.substring(with: match.range(at: 3)) != " "),
                indent: indent,
                bullet: ns.substring(with: match.range(at: 2)),
                length: match.range.length,
                markerRange: NSRange(location: indentRange.length, length: 5))
        }
        if match.range(at: 4).location != NSNotFound {
            return ListPrefix(
                kind: .bullet,
                indent: indent,
                bullet: ns.substring(with: match.range(at: 4)),
                length: match.range.length,
                markerRange: NSRange(location: indentRange.length, length: 1))
        }
        let number = match.range(at: 5)
        return ListPrefix(
            kind: .numbered(Int(ns.substring(with: number)) ?? 1),
            indent: indent,
            bullet: "",
            length: match.range.length,
            markerRange: NSRange(location: number.location, length: number.length + 1))
    }

    public static func headingLevel(of line: String) -> Int {
        let ns = line as NSString
        return headingPattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))?.range(at: 1).length ?? 0
    }

    /// First non-empty body line without markdown syntax, used as the title of a collapsed note.
    public static func plainTitle(fromBody body: String) -> String {
        var line = body.components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        if let prefix = listPrefix(in: line) {
            line = (line as NSString).substring(from: prefix.length)
        }
        return strippingHeading(line)
            .replacingOccurrences(of: #"[*_~`]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: Inline formatting

    /// ⌘B / ⌘I / …: wraps the selection in `marker`, or unwraps it when it is already wrapped.
    public static func toggleWrap(_ marker: String, in text: String, selection: NSRange) -> TextEdit {
        let ns = text as NSString
        let m = (marker as NSString).length
        let selected = ns.substring(with: selection)
        let start = selection.location
        let end = NSMaxRange(selection)

        // **|word|** → word
        if start >= m, end + m <= ns.length,
           ns.substring(with: NSRange(location: start - m, length: m)) == marker,
           ns.substring(with: NSRange(location: end, length: m)) == marker {
            return TextEdit(
                range: NSRange(location: start - m, length: selection.length + 2 * m),
                replacement: selected,
                selection: NSRange(location: start - m, length: selection.length))
        }

        // |**word**| → word
        if selection.length >= 2 * m, selected.hasPrefix(marker), selected.hasSuffix(marker) {
            let inner = (selected as NSString).substring(with: NSRange(location: m, length: selection.length - 2 * m))
            return TextEdit(
                range: selection,
                replacement: inner,
                selection: NSRange(location: start, length: (inner as NSString).length))
        }

        if selection.length == 0 {
            // Typed "**word" and hit ⌘B again: step over the closing marker instead of nesting.
            let line = lineRange(in: ns, at: start)
            let before = ns.substring(with: NSRange(location: line.location, length: start - line.location))
            let openMarkers = before.components(separatedBy: marker).count - 1
            if end + m <= ns.length, ns.substring(with: NSRange(location: end, length: m)) == marker, openMarkers % 2 == 1 {
                return .select(NSRange(location: end + m, length: 0))
            }
            return TextEdit(range: selection, replacement: marker + marker, selection: NSRange(location: start + m, length: 0))
        }

        // Keep surrounding whitespace outside the markers: "word " → "**word** ".
        let trimmed = selected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .select(selection) }
        let inner = NSRange(
            location: start + (selected as NSString).range(of: trimmed).location,
            length: (trimmed as NSString).length)
        return TextEdit(
            range: inner,
            replacement: marker + trimmed + marker,
            selection: NSRange(location: inner.location + m, length: inner.length))
    }

    public static func insertLink(in text: String, selection: NSRange) -> TextEdit {
        let selected = (text as NSString).substring(with: selection)
        if selected.hasPrefix("http://") || selected.hasPrefix("https://") {
            return TextEdit(
                range: selection,
                replacement: "[](\(selected))",
                selection: NSRange(location: selection.location + 1, length: 0))
        }
        let label = selected.isEmpty ? "link" : selected
        let labelLength = (label as NSString).length
        // Select what still needs typing: the label when there was none, otherwise the URL.
        let next = selected.isEmpty
            ? NSRange(location: selection.location + 1, length: labelLength)
            : NSRange(location: selection.location + labelLength + 3, length: 8)
        return TextEdit(range: selection, replacement: "[\(label)](https://)", selection: next)
    }

    // MARK: Line formatting

    /// Adds the style to every selected line, or removes it when all of them already have it.
    public static func toggleLineStyle(_ style: LineStyle, in text: String, selection: NSRange) -> TextEdit {
        let ns = text as NSString
        var probe = selection
        if probe.length > 0, ns.character(at: NSMaxRange(probe) - 1) == 0x0A {
            probe.length -= 1 // a selection ending in "\n" doesn't include the next line
        }
        let block = trimmingNewline(ns.lineRange(for: probe), in: ns)
        let lines = ns.substring(with: block).components(separatedBy: "\n")
        let isBlank: (String) -> Bool = { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        let skipBlank = lines.count > 1
        let targets = skipBlank ? lines.filter { !isBlank($0) } : lines
        let remove = !targets.isEmpty && targets.allSatisfy { has(style, $0) }

        let replacement = lines.map { line -> String in
            if skipBlank && isBlank(line) { return line }
            return remove ? removing(style, from: line) : applying(style, to: line)
        }.joined(separator: "\n")
        let newLength = (replacement as NSString).length

        let newSelection: NSRange
        if lines.count == 1 {
            let location = min(max(selection.location + newLength - block.length, block.location), block.location + newLength)
            newSelection = NSRange(location: location, length: min(selection.length, block.location + newLength - location))
        } else {
            newSelection = NSRange(location: block.location, length: newLength)
        }
        return TextEdit(range: block, replacement: replacement, selection: newSelection)
    }

    /// Toolbar heading button: none → # → ## → ### → none.
    public static func cycleHeading(in text: String, selection: NSRange) -> TextEdit {
        let ns = text as NSString
        let level = headingLevel(of: ns.substring(with: lineRange(in: ns, at: selection.location)))
        return toggleLineStyle(.heading(level >= 3 ? level : level + 1), in: text, selection: selection)
    }

    // MARK: Typing in lists

    /// Enter on a list item starts the next item; Enter on an empty item ends the list.
    /// Returns nil when Enter should just insert a newline.
    public static func newline(in text: String, selection: NSRange) -> TextEdit? {
        guard selection.length == 0 else { return nil }
        let ns = text as NSString
        let line = lineRange(in: ns, at: selection.location)
        let lineText = ns.substring(with: line)
        guard let prefix = listPrefix(in: lineText), selection.location >= line.location + prefix.length else {
            return nil
        }
        let content = (lineText as NSString).substring(from: prefix.length)
        if content.trimmingCharacters(in: .whitespaces).isEmpty {
            return TextEdit(range: line, replacement: "", selection: NSRange(location: line.location, length: 0))
        }
        let insertion = "\n" + prefix.continuation
        return TextEdit(
            range: selection,
            replacement: insertion,
            selection: NSRange(location: selection.location + (insertion as NSString).length, length: 0))
    }

    /// Backspace right after "- [ ] " removes the whole marker instead of a single space.
    public static func deleteBackward(in text: String, selection: NSRange) -> TextEdit? {
        guard selection.length == 0 else { return nil }
        let ns = text as NSString
        let line = lineRange(in: ns, at: selection.location)
        guard let prefix = listPrefix(in: ns.substring(with: line)),
              selection.location == line.location + prefix.length else { return nil }
        let indentLength = (prefix.indent as NSString).length
        let range = NSRange(location: line.location + indentLength, length: prefix.length - indentLength)
        return TextEdit(range: range, replacement: "", selection: NSRange(location: range.location, length: 0))
    }

    /// Tab / Shift-Tab on a list item nests or un-nests it. Returns nil outside lists.
    public static func indentListItem(in text: String, selection: NSRange, outdent: Bool) -> TextEdit? {
        let ns = text as NSString
        let line = lineRange(in: ns, at: selection.location)
        let lineText = ns.substring(with: line)
        guard listPrefix(in: lineText) != nil else { return nil }
        if outdent {
            let removable = lineText.hasPrefix("\t") ? 1 : min(2, lineText.prefix { $0 == " " }.count)
            guard removable > 0 else { return .select(selection) }
            return TextEdit(
                range: NSRange(location: line.location, length: removable),
                replacement: "",
                selection: NSRange(location: max(line.location, selection.location - removable), length: selection.length))
        }
        return TextEdit(
            range: NSRange(location: line.location, length: 0),
            replacement: "  ",
            selection: NSRange(location: selection.location + 2, length: selection.length))
    }

    /// Flips "- [ ]" ↔ "- [x]" on the line containing `location`, leaving the selection alone.
    public static func toggleCheckbox(in text: String, at location: Int, selection: NSRange) -> TextEdit? {
        let ns = text as NSString
        let line = lineRange(in: ns, at: location)
        guard let prefix = listPrefix(in: ns.substring(with: line)),
              case .checklist(let checked) = prefix.kind else { return nil }
        let mark = NSRange(location: line.location + prefix.markerRange.location + 3, length: 1)
        return TextEdit(range: mark, replacement: checked ? " " : "x", selection: selection)
    }

    // MARK: Helpers

    /// The line containing `location`, without its line break.
    static func lineRange(in ns: NSString, at location: Int) -> NSRange {
        var start = 0
        var contentsEnd = 0
        ns.getLineStart(&start, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
        return NSRange(location: start, length: contentsEnd - start)
    }

    private static func trimmingNewline(_ range: NSRange, in ns: NSString) -> NSRange {
        var range = range
        while range.length > 0, [0x0A, 0x0D].contains(ns.character(at: NSMaxRange(range) - 1)) {
            range.length -= 1
        }
        return range
    }

    private static func has(_ style: LineStyle, _ line: String) -> Bool {
        switch style {
        case .bullet:
            if case .bullet? = listPrefix(in: line)?.kind { return true }
            return false
        case .checklist:
            if case .checklist? = listPrefix(in: line)?.kind { return true }
            return false
        case .heading(let level):
            return headingLevel(of: line) == level
        }
    }

    private static func applying(_ style: LineStyle, to line: String) -> String {
        switch style {
        case .bullet:
            let (indent, content) = splitListPrefix(line)
            return indent + "- " + content
        case .checklist:
            let (indent, content) = splitListPrefix(line)
            return indent + "- [ ] " + content
        case .heading(let level):
            return String(repeating: "#", count: level) + " " + strippingHeading(line)
        }
    }

    private static func removing(_ style: LineStyle, from line: String) -> String {
        switch style {
        case .bullet, .checklist:
            let (indent, content) = splitListPrefix(line)
            return indent + content
        case .heading:
            return strippingHeading(line)
        }
    }

    private static func splitListPrefix(_ line: String) -> (indent: String, content: String) {
        let ns = line as NSString
        if let prefix = listPrefix(in: line) {
            return (prefix.indent, ns.substring(from: prefix.length))
        }
        let indentLength = line.prefix { $0 == " " || $0 == "\t" }.utf16.count
        return (ns.substring(to: indentLength), ns.substring(from: indentLength))
    }

    private static func strippingHeading(_ line: String) -> String {
        let level = headingLevel(of: line)
        return level == 0 ? line : (line as NSString).substring(from: level + 1)
    }
}
