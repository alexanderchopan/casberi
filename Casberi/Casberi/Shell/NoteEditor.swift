import SwiftUI
import UIKit

/// THE NOTE'S EDITOR (prd §1100): a `UITextView`, because a SwiftUI
/// `TextField` never says where its cursor is — so §1099's checklist key,
/// bullets and links could only act on the LAST line, a tap on a word put the
/// cursor at the end, and the read page had to be a second drawing of the
/// same words that swapped out for the field when you typed.
///
/// One view now reads and writes. It is editable from the start and only
/// raises the keyboard when a tap asks for one, so a note opens as a page:
///
/// * **The lines are styled as they stand** (`restyle`): an item's circle is
///   the tint when ticked and its words fade and strike through; a bullet, a
///   number and an item hang their words past the mark; `# ` is a heading,
///   `> ` a quote; a `[[link]]`, a `[title](address)` and a bare address are
///   the tint. Marks stay visible and dim — the note keeps markdown, and what
///   you see is what it keeps.
/// * **A tap on a circle ticks it** and never places the cursor (the tap
///   recognizer wins only on a circle), and a ticked item sinks to the foot
///   of its run (`NoteEditing.tick`).
/// * **The list keys act at the cursor** (`NoteEditing`): Return continues a
///   list or ends it, `- ` makes a bullet, the checklist key turns THIS line.
/// * **A swipe right or left on a list line indents or outdents it**, and the
///   edit menu offers Indent, Outdent, Move up and Move down on any line.
/// * **`[[` opens the link picker** where you are typing.
/// * **A pasted address becomes `[its title](address)`** once the page's own
///   title is read (`LinkTitle.fetch`, the paste chip's read) — never
///   guessed; with no title, or in the demo, the address stays as pasted.
struct NoteEditor: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    /// The editor's handle for the page's tools, which act at its cursor.
    let controller: NoteEditorController
    /// Whether the editor has the keyboard, reported out.
    var onFocus: (Bool) -> Void = { _ in }
    /// `[[` typed: the page raises its link picker.
    var onLinkTrigger: () -> Void = {}

    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> NoteTextView {
        let view = NoteTextView()
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.autocorrectionType = .default
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        view.tintColor = UIColor(DS.tint)
        view.text = text
        context.coordinator.view = view
        context.coordinator.install(on: view)
        controller.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: NoteTextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        controller.coordinator = coordinator
        coordinator.style = NoteEditorStyle(bold: legibilityWeight == .bold)
        if view.text != text {
            let selection = view.selectedRange
            view.text = text
            let length = (text as NSString).length
            view.selectedRange = NSRange(location: min(selection.location, length), length: 0)
        }
        coordinator.placeholder = placeholder
        coordinator.restyle()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: NoteTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(fit.height, 120))
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: NoteEditor
        weak var view: NoteTextView?
        var style = NoteEditorStyle(bold: false)
        var placeholder = ""
        /// A paste whose title is being read: the address and where it sits.
        private var pendingTitles: [String: Task<Void, Never>] = [:]

        init(parent: NoteEditor) { self.parent = parent }

        func install(on view: NoteTextView) {
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            tap.delegate = self
            view.addGestureRecognizer(tap)
            for direction in [UISwipeGestureRecognizer.Direction.right, .left] {
                let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
                swipe.direction = direction
                swipe.delegate = self
                view.addGestureRecognizer(swipe)
            }
            view.onPaste = { [weak self] pasted in self?.pasted(pasted) ?? false }
        }

        // MARK: Writing back

        /// Commit an edit made here: the view's text and cursor, then the
        /// binding, which the page saves.
        func apply(_ edit: NoteEditing.Edit) {
            guard let view else { return }
            view.text = edit.text
            view.selectedRange = NSRange(location: min(edit.cursor, (edit.text as NSString).length), length: 0)
            parent.text = edit.text
            restyle()
        }

        var cursor: Int { view?.selectedRange.location ?? (parent.text as NSString).length }

        // MARK: UITextViewDelegate

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText replacement: String) -> Bool {
            let text = textView.text ?? ""
            if replacement == "\n", range.length == 0,
               let edit = NoteEditing.returnKey(text, cursor: range.location) {
                apply(edit)
                return false
            }
            if replacement == " ", range.length == 0,
               let edit = NoteEditing.space(text, cursor: range.location) {
                apply(edit)
                return false
            }
            if replacement == "[", range.length == 0, range.location > 0,
               (text as NSString).substring(with: NSRange(location: range.location - 1, length: 1)) == "[" {
                // Let the second bracket in, then ask for the thing to link.
                DispatchQueue.main.async { [weak self] in self?.parent.onLinkTrigger() }
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            restyle()
        }

        /// The marks a cursor stands in show; the rest hide (prd §1101).
        func textViewDidChangeSelection(_ textView: UITextView) { restyle() }

        func textViewDidBeginEditing(_ textView: UITextView) { parent.onFocus(true) }
        func textViewDidEndEditing(_ textView: UITextView) { parent.onFocus(false) }

        /// Indent, Outdent, Move up and Move down join the system's menu.
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            let at = range.location
            let lines: [UIAction] = [
                UIAction(title: String(localized: "Indent"), image: UIImage(systemName: "increase.indent")) { [weak self] _ in
                    self?.indent(at: at, by: 1)
                },
                UIAction(title: String(localized: "Outdent"), image: UIImage(systemName: "decrease.indent")) { [weak self] _ in
                    self?.indent(at: at, by: -1)
                },
                UIAction(title: String(localized: "Move up"), image: UIImage(systemName: "arrow.up")) { [weak self] _ in
                    self?.move(at: at, by: -1)
                },
                UIAction(title: String(localized: "Move down"), image: UIImage(systemName: "arrow.down")) { [weak self] _ in
                    self?.move(at: at, by: 1)
                },
            ]
            return UIMenu(children: suggestedActions + [UIMenu(options: .displayInline, children: lines)])
        }

        // MARK: Line verbs

        func indent(at offset: Int, by step: Int) {
            guard let view, let edit = NoteEditing.indent(view.text ?? "", cursor: offset, by: step) else { return }
            DSHaptic.selection()
            apply(edit)
        }

        func move(at offset: Int, by step: Int) {
            guard let view, let edit = NoteEditing.moveLine(view.text ?? "", cursor: offset, by: step) else { return }
            DSHaptic.selection()
            apply(edit)
        }

        /// The Aa key's bold, italic or strikethrough, over the selection.
        func format(_ style: NoteEditing.Inline) {
            guard let view else { return }
            let edit = NoteEditing.wrap(view.text ?? "", selection: view.selectedRange, in: style)
            DSHaptic.selection()
            view.text = edit.text
            view.selectedRange = NSRange(location: edit.cursor, length: edit.length)
            parent.text = edit.text
            restyle()
            focus()
        }

        /// The Aa key's line style, on the line at the cursor.
        func lineStyle(_ style: NoteEditing.LineStyle) {
            let edit = NoteEditing.setLineStyle(view?.text ?? parent.text, cursor: cursor, to: style)
            DSHaptic.selection()
            apply(edit)
            focus()
        }

        func toggleChecklist() {
            let edit = NoteEditing.toggleChecklist(view?.text ?? parent.text, cursor: cursor)
            DSHaptic.selection()
            apply(edit)
            focus()
        }

        /// Words at the cursor (a picked `[[link]]`), replacing `replacing`
        /// characters before it — the `[[` that asked.
        func insert(_ words: String, replacing count: Int = 0) {
            let text = view?.text ?? parent.text
            let at = cursor
            let start = max(0, at - count)
            let out = (text as NSString).replacingCharacters(in: NSRange(location: start, length: at - start), with: words)
            apply(NoteEditing.Edit(text: out, cursor: start + (words as NSString).length))
            focus()
        }

        /// The two characters before the cursor, to tell whether a picked link
        /// is answering a typed `[[`.
        var bracketsBeforeCursor: Bool {
            let text = (view?.text ?? parent.text) as NSString
            let at = cursor
            return at >= 2 && text.substring(with: NSRange(location: at - 2, length: 2)) == "[["
        }

        func focus() {
            guard let view, !view.isFirstResponder else { return }
            view.becomeFirstResponder()
        }

        // MARK: The circle's tap and the line's swipe

        /// The item a touch lands on: its line index when the touch is on
        /// the line's circle (the mark and a margin around it).
        private func circleLine(at point: CGPoint) -> Int? {
            guard let view else { return nil }
            let manager = view.layoutManager
            let container = view.textContainer
            var location = point
            location.x -= view.textContainerInset.left
            location.y -= view.textContainerInset.top
            let glyph = manager.glyphIndex(for: location, in: container)
            let char = manager.characterIndexForGlyph(at: glyph)
            let text = view.text ?? ""
            let range = NoteEditing.lineRange(text, at: char)
            let line = (text as NSString).substring(with: range).trimmingCharacters(in: .newlines)
            guard NoteEditing.isDone(line) != nil, !line.hasPrefix("- ") else { return nil }
            let lead = line.prefix(while: { $0 == " " }).count
            let markStart = range.location + lead
            let markRect = manager.boundingRect(
                forGlyphRange: manager.glyphRange(forCharacterRange: NSRange(location: markStart, length: 1),
                                                  actualCharacterRange: nil),
                in: container)
            // A finger, not a pixel: 22pt either side of the circle.
            guard location.x <= markRect.maxX + 22,
                  location.y >= markRect.minY - 11, location.y <= markRect.maxY + 11 else { return nil }
            return NoteEditing.lineIndex(text, at: markStart)
        }

        private func listLine(at point: CGPoint) -> Int? {
            guard let view else { return nil }
            var location = point
            location.x -= view.textContainerInset.left
            location.y -= view.textContainerInset.top
            let glyph = view.layoutManager.glyphIndex(for: location, in: view.textContainer)
            let char = view.layoutManager.characterIndexForGlyph(at: glyph)
            let text = view.text ?? ""
            let range = NoteEditing.lineRange(text, at: char)
            let line = (text as NSString).substring(with: range).trimmingCharacters(in: .newlines)
            return NoteEditing.mark(of: line) == nil ? nil : char
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let view else { return false }
            let point = touch.location(in: view)
            if g is UITapGestureRecognizer { return circleLine(at: point) != nil }
            if g is UISwipeGestureRecognizer { return listLine(at: point) != nil }
            return true
        }

        /// The circle's tap must win over the text view's own, so a tick
        /// never places the cursor or raises the keyboard.
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            g is UITapGestureRecognizer && other.view === view
        }

        @objc private func tapped(_ g: UITapGestureRecognizer) {
            guard let view, let index = circleLine(at: g.location(in: view)) else { return }
            let lines = (view.text ?? "").components(separatedBy: "\n")
            let out = NoteEditing.tick(lines: lines, at: index).joined(separator: "\n")
            DSHaptic.selection()
            let keep = view.selectedRange
            view.text = out
            view.selectedRange = NSRange(location: min(keep.location, (out as NSString).length), length: 0)
            parent.text = out
            restyle()
            parent.controller.onTick?()
        }

        @objc private func swiped(_ g: UISwipeGestureRecognizer) {
            guard let view, let at = listLine(at: g.location(in: view)) else { return }
            indent(at: at, by: g.direction == .right ? 1 : -1)
        }

        // MARK: Pasting an address

        /// A pasted bare address: let it in as pasted, then read the page's
        /// title and, if the address still stands where it was put, write
        /// `[title](address)` over it. Returns false to let the system paste.
        func pasted(_ string: String) -> Bool {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.contains(" "), !trimmed.contains("\n"),
                  let url = URL(string: trimmed), let scheme = url.scheme,
                  scheme == "https" || scheme == "http", url.host != nil else { return false }
            insertPlain(trimmed)
            guard !DemoMode.isActive else { return true }
            pendingTitles[trimmed]?.cancel()
            pendingTitles[trimmed] = Task { @MainActor [weak self] in
                guard let title = await LinkTitle.fetch(url), !Task.isCancelled,
                      let self, let view = self.view else { return }
                let clean = title.replacingOccurrences(of: "]", with: ")")
                    .replacingOccurrences(of: "[", with: "(")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { return }
                let text = view.text ?? ""
                let ns = text as NSString
                let found = ns.range(of: trimmed, options: .backwards)
                guard found.location != NSNotFound else { return }
                // Already a markdown link's address: leave it.
                if found.location >= 2, ns.substring(with: NSRange(location: found.location - 2, length: 2)) == "](" { return }
                let linked = "[\(clean)](\(trimmed))"
                let out = ns.replacingCharacters(in: found, with: linked)
                let shift = (linked as NSString).length - found.length
                let keep = view.selectedRange.location
                view.text = out
                view.selectedRange = NSRange(location: keep >= found.location ? keep + shift : keep, length: 0)
                self.parent.text = out
                self.restyle()
                self.pendingTitles[trimmed] = nil
            }
            return true
        }

        private func insertPlain(_ words: String) {
            guard let view else { return }
            let text = view.text ?? ""
            let range = view.selectedRange
            let out = (text as NSString).replacingCharacters(in: range, with: words)
            apply(NoteEditing.Edit(text: out, cursor: range.location + (words as NSString).length))
        }

        // MARK: Styling

        /// Paint every line in place — attributes only, so the cursor, the
        /// selection and undo stand.
        func restyle() {
            guard let view else { return }
            let storage = view.textStorage
            let text = storage.string
            let full = NSRange(location: 0, length: (text as NSString).length)
            view.typingAttributes = style.base
            storage.beginEditing()
            storage.setAttributes(style.base, range: full)
            (text as NSString).enumerateSubstrings(in: full, options: [.byLines, .substringNotRequired]) { _, lineRange, enclosing, _ in
                self.styleLine(storage, lineRange: lineRange, paragraphRange: enclosing)
            }
            style.links(in: storage, full: full)
            inline(storage, text: text)
            storage.endEditing()
            view.placeholderLabel.text = placeholder
            view.placeholderLabel.font = style.font
            view.placeholderLabel.isHidden = !text.isEmpty
            view.accessibilityCustomActions = itemActions(text)
        }

        private func styleLine(_ storage: NSTextStorage, lineRange: NSRange, paragraphRange: NSRange) {
            let line = (storage.string as NSString).substring(with: lineRange)
            let lead = line.prefix(while: { $0 == " " }).count
            let body = String(line.dropFirst(lead))
            let markStart = lineRange.location + lead
            func hang(_ markLength: Int) {
                let prefix = (line as NSString).substring(to: lead + markLength)
                let width = (prefix as NSString).size(withAttributes: [.font: style.font]).width
                let paragraph = style.paragraph(headIndent: width)
                storage.addAttribute(.paragraphStyle, value: paragraph, range: paragraphRange)
            }
            if body.hasPrefix(NoteChecklist.editorMark) || body.hasPrefix(NoteChecklist.doneEditorMark) {
                let done = body.hasPrefix(NoteChecklist.doneEditorMark)
                hang(2)
                storage.addAttributes([.foregroundColor: done ? UIColor(DS.tint) : UIColor(DS.textSecondary),
                                       .font: style.circleFont],
                                      range: NSRange(location: markStart, length: 1))
                if done {
                    let words = NSRange(location: markStart + 2, length: max(0, lineRange.length - lead - 2))
                    storage.addAttributes([.foregroundColor: UIColor(DS.textTertiary),
                                           .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                           .strikethroughColor: UIColor(DS.textTertiary)], range: words)
                }
            } else if body.hasPrefix(NoteChecklist.bulletMark) {
                hang(2)
                storage.addAttribute(.foregroundColor, value: UIColor(DS.textSecondary),
                                     range: NSRange(location: markStart, length: 1))
            } else if let n = NoteChecklist.numbered(body) {
                let markLength = ("\(n.number). " as NSString).length
                hang(markLength)
                storage.addAttribute(.foregroundColor, value: UIColor(DS.textSecondary),
                                     range: NSRange(location: markStart, length: markLength))
            } else if body.hasPrefix(NoteEditing.quoteMark) {
                hang(2)
                storage.addAttribute(.foregroundColor, value: UIColor(DS.textTertiary),
                                     range: NSRange(location: markStart, length: 1))
                storage.addAttribute(.foregroundColor, value: UIColor(DS.textSecondary),
                                     range: NSRange(location: markStart + 2, length: max(0, lineRange.length - lead - 2)))
            } else if body.hasPrefix(NoteEditing.headingMark) {
                storage.addAttribute(.font, value: style.headingFont, range: lineRange)
                storage.addAttribute(.foregroundColor, value: UIColor(DS.textTertiary),
                                     range: NSRange(location: markStart, length: 1))
            }
        }

        /// THE AA KEY'S MARKS, DRAWN (prd §1101): bold words in the bold
        /// face, italic slanted (Figtree ships no italic), struck words
        /// struck — and the `**`, `_` and `~~` themselves hidden unless the
        /// cursor stands in the run, so someone who never types markdown
        /// never reads it, and someone who does can still edit the marks.
        /// A heading's `# ` hides the same way, off its line.
        private func inline(_ storage: NSTextStorage, text: String) {
            guard let view else { return }
            let selection = view.isFirstResponder ? view.selectedRange : NSRange(location: NSNotFound, length: 0)
            func touched(_ range: NSRange) -> Bool {
                guard selection.location != NSNotFound else { return false }
                return selection.location >= range.location && selection.location <= range.upperBound
                    || NSIntersectionRange(selection, range).length > 0
            }
            let hidden: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.clear,
                                                          .font: style.font.withSize(1)]
            for run in NoteEditing.inlineRuns(text) {
                switch run.style {
                case .bold:
                    storage.enumerateAttribute(.font, in: run.words) { value, range, _ in
                        let base = (value as? UIFont) ?? style.font
                        storage.addAttribute(.font, value: style.bolder(base), range: range)
                    }
                case .italic:
                    // A slanted face: the text view's TextKit 2 ignores
                    // `.obliqueness` (measured), and Figtree ships no italic.
                    storage.enumerateAttribute(.font, in: run.words) { value, range, _ in
                        let base = (value as? UIFont) ?? style.font
                        storage.addAttribute(.font, value: style.slanted(base), range: range)
                    }
                case .strike:
                    storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue], range: run.words)
                }
                guard !touched(run.whole) else { continue }
                let markLength = (run.style.rawValue as NSString).length
                storage.addAttributes(hidden, range: NSRange(location: run.whole.location, length: markLength))
                storage.addAttributes(hidden, range: NSRange(location: run.words.upperBound, length: markLength))
            }
            // A heading's mark, off its line.
            (text as NSString).enumerateSubstrings(in: NSRange(location: 0, length: (text as NSString).length),
                                                   options: .byLines) { line, range, _, _ in
                guard let line, line.drop(while: { $0 == " " }).hasPrefix(NoteEditing.headingMark),
                      !touched(range) else { return }
                let lead = line.prefix(while: { $0 == " " }).count
                storage.addAttributes(hidden, range: NSRange(location: range.location + lead, length: 2))
            }
        }

        /// VoiceOver ticks an item by name, as a finger ticks its circle.
        private func itemActions(_ text: String) -> [UIAccessibilityCustomAction] {
            text.components(separatedBy: "\n").enumerated().compactMap { index, line in
                guard let done = NoteEditing.isDone(line) else { return nil }
                let words = NoteChecklist.plain(line)
                let name = done ? String(localized: "Untick \(words)") : String(localized: "Tick \(words)")
                return UIAccessibilityCustomAction(name: name) { [weak self] _ in
                    guard let self, let view = self.view else { return false }
                    let lines = (view.text ?? "").components(separatedBy: "\n")
                    guard lines.indices.contains(index) else { return false }
                    let out = NoteEditing.tick(lines: lines, at: index).joined(separator: "\n")
                    view.text = out
                    self.parent.text = out
                    self.restyle()
                    self.parent.controller.onTick?()
                    return true
                }
            }
        }
    }
}

/// The page's handle on its editor (prd §1100): the tools on the capsule act
/// at the editor's cursor, and the page hears a tick to keep it at once.
@MainActor
final class NoteEditorController {
    weak var coordinator: NoteEditor.Coordinator?
    /// A circle was ticked — the page saves it as it is made (§1099).
    var onTick: (() -> Void)?

    func toggleChecklist() { coordinator?.toggleChecklist() }
    func format(_ style: NoteEditing.Inline) { coordinator?.format(style) }
    func lineStyle(_ style: NoteEditing.LineStyle) { coordinator?.lineStyle(style) }
    func focus() { coordinator?.focus() }
    func insertLink(_ title: String) {
        let link = "[[\(title)]]"
        if coordinator?.bracketsBeforeCursor == true {
            coordinator?.insert(link, replacing: 2)
        } else {
            coordinator?.insert(link)
        }
    }
}

/// The editor's text view: a placeholder, and a paste it can answer first.
final class NoteTextView: UITextView {
    let placeholderLabel = UILabel()
    /// Return true when the paste was handled (a bare address, §1100).
    var onPaste: ((String) -> Bool)?

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        placeholderLabel.textColor = UIColor(DS.textTertiary)
        placeholderLabel.numberOfLines = 1
        addSubview(placeholderLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        placeholderLabel.frame = CGRect(x: textContainerInset.left, y: textContainerInset.top,
                                        width: bounds.width, height: placeholderLabel.font.lineHeight)
    }

    override func paste(_ sender: Any?) {
        if let string = UIPasteboard.general.string, onPaste?(string) == true { return }
        super.paste(sender)
    }
}

/// The rungs the editor draws in, as UIKit wants them: `reading17` for the
/// words, `heading24` for a `# ` line — the shipped Figtree face, Dynamic Type
/// through `UIFontMetrics`, the rung's own leading (`KeepableText`'s recipe).
struct NoteEditorStyle {
    let font: UIFont
    let headingFont: UIFont
    let circleFont: UIFont
    let lineSpacing: CGFloat

    init(bold: Bool) {
        func face(_ tier: DSTextStyle) -> UIFont {
            let size = UIFontMetrics(forTextStyle: tier.relative).scaledValue(for: tier.platformSize)
            let weight = bold ? DSFont.bolder(tier.weight) : tier.weight
            return UIFont(name: DSFont.name(for: weight), size: size) ?? .systemFont(ofSize: size)
        }
        font = face(.reading17)
        headingFont = face(.heading24)
        circleFont = UIFont.systemFont(ofSize: font.pointSize * 1.12)
        lineSpacing = DSTextStyle.reading17.lineSpacing
    }

    /// The same face one weight heavier, at its own size — bold words in a
    /// heading stay the heading's size.
    func bolder(_ base: UIFont) -> UIFont {
        let weight: UIFont.Weight = base.pointSize > font.pointSize ? .heavy : .bold
        let name = DSFont.name(for: weight == .heavy ? .heavy : .bold)
        return UIFont(name: name, size: base.pointSize) ?? .boldSystemFont(ofSize: base.pointSize)
    }

    /// The same face slanted 12°, Figtree having no italic of its own.
    func slanted(_ base: UIFont) -> UIFont {
        #if targetEnvironment(macCatalyst)
        // `withMatrix` is unavailable on Mac Catalyst (verify's Catalyst
        // compile, 2026-10-04): the Mac asks for the italic trait, and keeps
        // the upright face when Figtree has none to give.
        let italic = base.fontDescriptor.withSymbolicTraits(.traitItalic) ?? base.fontDescriptor
        return UIFont(descriptor: italic, size: base.pointSize)
        #else
        let slant = CGAffineTransform(a: 1, b: 0, c: tan(12 * .pi / 180), d: 1, tx: 0, ty: 0)
        return UIFont(descriptor: base.fontDescriptor.withMatrix(slant), size: base.pointSize)
        #endif
    }

    func paragraph(headIndent: CGFloat = 0) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = lineSpacing
        p.paragraphSpacing = lineSpacing / 2
        p.headIndent = headIndent
        return p
    }

    var base: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: UIColor(DS.textPrimary), .paragraphStyle: paragraph()]
    }

    /// The tint on what links: `[[a thing you keep]]`, `[title](address)` and
    /// a bare address — the `(address)` of a markdown link dims, its title is
    /// the link.
    func links(in storage: NSTextStorage, full: NSRange) {
        let text = storage.string
        let tint = UIColor(DS.tint)
        for pattern in [#"\[\[[^\]\n]+\]\]"#, #"https?://[^\s)\]]+"#] {
            guard let rx = try? NSRegularExpression(pattern: pattern) else { continue }
            for m in rx.matches(in: text, range: full) {
                storage.addAttribute(.foregroundColor, value: tint, range: m.range)
            }
        }
        if let rx = try? NSRegularExpression(pattern: #"\[([^\[\]\n]+)\]\((https?://[^\s)]+)\)"#) {
            for m in rx.matches(in: text, range: full) {
                storage.addAttribute(.foregroundColor, value: tint, range: m.range(at: 1))
                let address = NSRange(location: m.range(at: 1).upperBound, length: m.range.upperBound - m.range(at: 1).upperBound)
                storage.addAttributes([.foregroundColor: UIColor(DS.textTertiary),
                                       .font: font.withSize(font.pointSize * 0.8)], range: address)
            }
        }
    }
}
