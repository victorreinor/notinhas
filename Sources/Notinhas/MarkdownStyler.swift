import AppKit
import NotinhasCore

extension NSAttributedString.Key {
    /// Marks "- [ ]" / "- [x]"; value is the checked state. The layout manager draws the box.
    static let noteCheckbox = NSAttributedString.Key("NotinhasCheckbox")
    /// Marks the "-" of a bullet item. The layout manager draws the dot.
    static let noteBullet = NSAttributedString.Key("NotinhasBullet")
    /// URL opened by ⌘-click (a real .link would open on every click and get in the way of editing).
    static let noteLink = NSAttributedString.Key("NotinhasLink")
}

/// Live markdown: the text stays plain markdown, only attributes change. Syntax markers are
/// dimmed instead of hidden, except list markers, which are drawn as dots and checkboxes.
final class MarkdownStyler: NSObject, NSTextStorageDelegate {
    weak var textView: NSTextView?
    let ink: NSColor
    let font = NSFont.systemFont(ofSize: 13.5)
    private let codeFont = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
    private let linkColor = NSColor(srgbRed: 0.09, green: 0.36, blue: 0.80, alpha: 1)
    private lazy var baseParagraph = paragraph(indent: 0)
    private var muted: NSColor { ink.withAlphaComponent(0.32) }

    init(ink: NSColor) {
        self.ink = ink
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: ink, .paragraphStyle: baseParagraph]
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        willProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        // Leave text being composed (dead keys like ´ + a) alone; it is styled once committed.
        guard editedMask.contains(.editedCharacters), textView?.hasMarkedText() != true else { return }
        style(textStorage)
    }

    /// Notes are short, so the whole text is restyled on every edit.
    func style(_ storage: NSTextStorage) {
        let text = storage.string
        let all = NSRange(location: 0, length: (text as NSString).length)
        storage.setAttributes(baseAttributes, range: all)

        var code = styleBlocks(storage, text as NSString)
        each(Self.inlineCode, in: text, skipping: code) { match in
            code.append(match.range)
            dim(storage, match.range(at: 1))
            dim(storage, match.range(at: 3))
        }
        each(Self.bold, in: text, skipping: code) { match in
            addTraits(.bold, storage, match.range(at: 2))
            dimMarkers(storage, match, length: match.range(at: 1).length)
        }
        for italic in [Self.italicStar, Self.italicUnderscore] {
            each(italic, in: text, skipping: code) { match in
                addTraits(.italic, storage, match.range(at: 1))
                dimMarkers(storage, match, length: 1)
            }
        }
        each(Self.strike, in: text, skipping: code) { match in
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: match.range(at: 1))
            dimMarkers(storage, match, length: 2)
        }
        var links: [NSRange] = []
        each(Self.link, in: text, skipping: code) { match in
            links.append(match.range)
            let label = match.range(at: 1)
            storage.addAttributes(linkAttributes((text as NSString).substring(with: match.range(at: 2))), range: label)
            dim(storage, NSRange(location: match.range.location, length: 1))
            dim(storage, NSRange(location: NSMaxRange(label), length: NSMaxRange(match.range) - NSMaxRange(label)))
        }
        each(Self.bareURL, in: text, skipping: code + links) { match in
            storage.addAttributes(linkAttributes((text as NSString).substring(with: match.range)), range: match.range)
        }
        for range in code {
            storage.addAttributes([.font: codeFont, .backgroundColor: ink.withAlphaComponent(0.07)], range: range)
        }
    }

    // MARK: Blocks

    /// Styles headings, lists and quotes line by line; returns the ranges of fenced code blocks.
    private func styleBlocks(_ storage: NSTextStorage, _ ns: NSString) -> [NSRange] {
        var fences: [NSRange] = []
        var fenceStart: Int?
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, line, _, _ in
            let text = ns.substring(with: line)
            if text.hasPrefix("```") {
                self.dim(storage, line)
                if let start = fenceStart {
                    fences.append(NSRange(location: start, length: NSMaxRange(line) - start))
                    fenceStart = nil
                } else {
                    fenceStart = line.location
                }
            } else if fenceStart == nil {
                self.styleLine(storage, text, line)
            }
        }
        if let start = fenceStart {
            fences.append(NSRange(location: start, length: ns.length - start))
        }
        return fences
    }

    private func styleLine(_ storage: NSTextStorage, _ text: String, _ line: NSRange) {
        let level = MarkdownEditing.headingLevel(of: text)
        if level > 0 {
            let size: CGFloat = level == 1 ? 19 : level == 2 ? 16.5 : 14.5
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: size, weight: .bold), range: line)
            dim(storage, NSRange(location: line.location, length: level + 1))
            return
        }

        if let prefix = MarkdownEditing.listPrefix(in: text) {
            var prefixText = (text as NSString).substring(to: prefix.length)
            let marker = NSRange(location: line.location + prefix.markerRange.location, length: prefix.markerRange.length)
            if case .checklist = prefix.kind {
                // The hidden "x" of "[x]" is wider than the space of "[ ]"; kern it back so
                // checked and unchecked items start their text at the same x.
                let mark = NSRange(location: prefix.markerRange.location + 3, length: 1)
                let markWidth = ((prefixText as NSString).substring(with: mark) as NSString).size(withAttributes: [.font: font]).width
                let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
                storage.addAttribute(.kern, value: spaceWidth - markWidth, range: NSRange(location: line.location + mark.location, length: 1))
                prefixText = (prefixText as NSString).replacingCharacters(in: mark, with: " ")
            }
            // Wrapped lines of an item line up with its text, not with the marker.
            let indent = (prefixText as NSString).size(withAttributes: [.font: font]).width
            storage.addAttribute(.paragraphStyle, value: paragraph(indent: indent), range: line)
            switch prefix.kind {
            case .checklist(let checked):
                storage.addAttributes([.noteCheckbox: checked, .foregroundColor: NSColor.clear], range: marker)
                if checked {
                    let content = NSRange(location: line.location + prefix.length, length: line.length - prefix.length)
                    storage.addAttributes([
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                        .foregroundColor: ink.withAlphaComponent(0.45),
                    ], range: content)
                }
            case .bullet:
                storage.addAttributes([.noteBullet: true, .foregroundColor: NSColor.clear], range: marker)
            case .numbered:
                storage.addAttribute(.foregroundColor, value: ink.withAlphaComponent(0.55), range: marker)
            }
            return
        }

        if text.hasPrefix(">") {
            storage.addAttribute(.foregroundColor, value: ink.withAlphaComponent(0.6), range: line)
            dim(storage, NSRange(location: line.location, length: 1))
        } else if Self.rule.firstMatch(in: text, range: NSRange(location: 0, length: line.length)) != nil {
            dim(storage, line)
        }
    }

    // MARK: Helpers

    private func each(
        _ regex: NSRegularExpression,
        in text: String,
        skipping excluded: [NSRange],
        _ body: (NSTextCheckingResult) -> Void
    ) {
        regex.enumerateMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) { match, _, _ in
            guard let match, !excluded.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { return }
            body(match)
        }
    }

    private func dim(_ storage: NSTextStorage, _ range: NSRange) {
        storage.addAttribute(.foregroundColor, value: muted, range: range)
    }

    private func dimMarkers(_ storage: NSTextStorage, _ match: NSTextCheckingResult, length: Int) {
        dim(storage, NSRange(location: match.range.location, length: length))
        dim(storage, NSRange(location: NSMaxRange(match.range) - length, length: length))
    }

    private func addTraits(_ traits: NSFontDescriptor.SymbolicTraits, _ storage: NSTextStorage, _ range: NSRange) {
        storage.enumerateAttribute(.font, in: range) { value, run, _ in
            guard let current = value as? NSFont else { return }
            let descriptor = current.fontDescriptor.withSymbolicTraits(current.fontDescriptor.symbolicTraits.union(traits))
            storage.addAttribute(.font, value: NSFont(descriptor: descriptor, size: current.pointSize) ?? current, range: run)
        }
    }

    private func linkAttributes(_ string: String) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        if let url = URL(string: string), url.scheme != nil {
            attributes[.noteLink] = url
        }
        return attributes
    }

    private func paragraph(indent: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.paragraphSpacing = 3
        style.headIndent = indent
        return style
    }

    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let inlineCode = regex(#"(`)([^`\n]+)(`)"#)
    private static let bold = regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let italicStar = regex(#"(?<![*\w])\*(?![*\s])(.+?)(?<![*\s])\*(?![*\w])"#)
    private static let italicUnderscore = regex(#"(?<![_\w])_(?![_\s])(.+?)(?<![_\s])_(?![_\w])"#)
    private static let strike = regex(#"~~(?=\S)(.+?)(?<=\S)~~"#)
    private static let link = regex(#"\[([^\]\n]+)\]\(([^)\s]+)\)"#)
    private static let bareURL = regex(#"(?<![(\w/])https?://[^\s<>()\[\]]+"#)
    private static let rule = regex(#"^ {0,3}([-*_])(?: *\1){2,} *$"#)
}
