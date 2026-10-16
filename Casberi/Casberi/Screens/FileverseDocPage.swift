import SwiftUI
import SwiftData

/// A Fileverse doc, read as a page (prd §1346; user: "A page, like your
/// notes"). The note page's anatomy without its editor: the title at
/// `heading34`, a line saying where it came from, then the document's blocks
/// in the reading rung. Read-only — the seat cannot write (§1339), so nothing
/// here takes a keyboard. The controls sit at the foot (§752): Done, and the
/// door to the doc in Fileverse.
struct FileverseDocPage: View {
    let thing: Thing
    /// The page's way out: Done, which closes the layer or the cover.
    let onCancel: () -> Void
    @State private var webDoor: WebDoor?

    private struct WebDoor: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            DS.page.ignoresSafeArea()
            // A doc deleted while its page is up (a pass saw its DeletedFile)
            // is never read again: the foot stays, so Done still closes.
            if thing.isLive { words }
            foot
        }
        .sheet(item: $webDoor) { door in
            DSWebSheet(url: door.url) { webDoor = nil }
        }
    }

    private var words: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    Text(thing.title)
                        .dsText(.heading34)
                        .foregroundStyle(DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Fileverse · \(thing.capturedAt, format: .relative(presentation: .named))")
                        .dsText(.label12)
                        .foregroundStyle(DS.textSecondary)
                        .padding(.bottom, DS.Space.s2)
                    ForEach(Array(MarkdownBlocks.parse(thing.enrichedText ?? "").enumerated()), id: \.offset) { _, block in
                        MarkdownBlockView(block: block)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DSRoomChassis.leadInset)
                .padding(.top, DS.Space.s4)
                .padding(.bottom, 120)
            }
    }

    private var foot: some View {
        HStack(spacing: DS.Space.s2) {
            Button {
                DSHaptic.tap()
                onCancel()
            } label: {
                Label("Done", systemImage: "chevron.down")
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .padding(.horizontal, DS.Space.s4)
                    .frame(height: 52)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressSpring())
            .dsGlass(cornerRadius: 26)
            Spacer(minLength: 0)
            if thing.isLive, let url = URL(string: thing.externalLink ?? thing.content), url.scheme == "https" {
                Button {
                    DSHaptic.tap()
                    webDoor = WebDoor(url: url)
                } label: {
                    Label("Open in Fileverse", systemImage: "arrow.up.right")
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                        .padding(.horizontal, DS.Space.s4)
                        .frame(height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressSpring())
                .dsGlass(cornerRadius: 26)
            }
        }
        .padding(.horizontal, DS.Space.s3)
        .padding(.bottom, DS.Space.s3)
    }
}

/// The Markdown subset `FileverseDoc` writes, read back into blocks.
enum MarkdownBlocks {
    enum Block: Equatable {
        case heading(Int, String)
        case paragraph(String)
        case item(depth: Int, marker: Marker, text: String)
        case quote(String)
        case code(String)
        case divider
        case table([[String]])
        case image(alt: String, src: String)
    }

    enum Marker: Equatable { case bullet, number(String), task(Bool) }

    static func parse(_ md: String) -> [Block] {
        var out: [Block] = []
        var para: [String] = []
        var table: [[String]] = []
        var code: [String]?
        func flushPara() {
            if !para.isEmpty { out.append(.paragraph(para.joined(separator: "\n"))); para.removeAll() }
        }
        func flushTable() {
            if !table.isEmpty { out.append(.table(table)); table.removeAll() }
        }
        for raw in md.components(separatedBy: "\n") {
            if var lines = code {
                if raw.hasPrefix("```") { out.append(.code(lines.joined(separator: "\n"))); code = nil }
                else { lines.append(raw); code = lines }
                continue
            }
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("|") {
                flushPara()
                let cells = splitRow(line)
                if !cells.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } && !$0.isEmpty }) { table.append(cells) }
                continue
            }
            flushTable()
            if line.isEmpty { flushPara(); continue }
            if line.hasPrefix("```") { flushPara(); code = []; continue }
            if line == "---" { flushPara(); out.append(.divider); continue }
            if let h = heading(line) { flushPara(); out.append(h); continue }
            if line.hasPrefix("> ") { flushPara(); out.append(.quote(String(line.dropFirst(2)))); continue }
            if let img = image(line) { flushPara(); out.append(img); continue }
            let depth = raw.prefix { $0 == " " }.count / 2
            if let item = item(line, depth: depth) { flushPara(); out.append(item); continue }
            para.append(raw.hasSuffix("  ") ? String(raw.dropLast(2)) : raw)
        }
        flushPara()
        flushTable()
        if let lines = code { out.append(.code(lines.joined(separator: "\n"))) }
        return out
    }

    private static func heading(_ line: String) -> Block? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).hasPrefix(" ") else { return nil }
        return .heading(hashes, String(line.dropFirst(hashes + 1)))
    }

    private static func item(_ line: String, depth: Int) -> Block? {
        if line.hasPrefix("- [x] ") || line.hasPrefix("- [ ] ") {
            return .item(depth: depth, marker: .task(line.hasPrefix("- [x]")), text: String(line.dropFirst(6)))
        }
        if line.hasPrefix("- ") { return .item(depth: depth, marker: .bullet, text: String(line.dropFirst(2))) }
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") {
            return .item(depth: depth, marker: .number(String(digits)), text: String(line.dropFirst(digits.count + 2)))
        }
        return nil
    }

    private static func image(_ line: String) -> Block? {
        guard line.hasPrefix("!["), line.hasSuffix(")"),
              let mid = line.range(of: "](") else { return nil }
        let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<mid.lowerBound])
        let src = String(line[mid.upperBound..<line.index(before: line.endIndex)])
        return .image(alt: alt, src: src)
    }

    private static func splitRow(_ line: String) -> [String] {
        var cells: [String] = []
        var cur = ""
        var escaped = false
        for ch in line.dropFirst() {
            if escaped { cur.append(ch); escaped = false; continue }
            if ch == "\\" { escaped = true; cur.append(ch); continue }
            if ch == "|" { cells.append(cur.trimmingCharacters(in: .whitespaces)); cur = ""; continue }
            cur.append(ch)
        }
        return cells
    }

    /// The words alone, marks and markers stripped, for a demo row's excerpt.
    static func excerpt(_ md: String, limit: Int = 300) -> String {
        let words = parse(md).compactMap { block -> String? in
            switch block {
            case .heading(_, let t), .paragraph(let t), .quote(let t): return t
            case .item(_, _, let t): return t
            default: return nil
            }
        }
        let plain = words.map { String(inline($0).characters) }.joined(separator: " ")
        return String(plain.prefix(limit))
    }

    /// Inline marks through Foundation's Markdown, whitespace kept.
    static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlocks.Block

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(MarkdownBlocks.inline(text))
                .dsText(level <= 1 ? .heading28 : level == 2 ? .heading24 : level == 3 ? .heading20 : .heading17)
                .foregroundStyle(DS.textPrimary)
                .padding(.top, DS.Space.s2)
                .fixedSize(horizontal: false, vertical: true)
        case .paragraph(let text):
            prose(text)
        case .item(let depth, let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                switch marker {
                case .bullet:
                    Text("•").dsText(.reading17).foregroundStyle(DS.textSecondary)
                case .number(let n):
                    Text("\(n).").dsText(.reading17).foregroundStyle(DS.textSecondary).monospacedDigit()
                case .task(let done):
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .dsGlyph(.body, weight: .regular)
                        .foregroundStyle(done ? DS.tint : DS.textTertiary)
                }
                prose(text)
            }
            .padding(.leading, CGFloat(depth) * DS.Space.s4)
        case .quote(let text):
            prose(text, ink: DS.textSecondary)
                .padding(.leading, DS.Space.s3)
        case .code(let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text).dsText(.mono12).foregroundStyle(DS.textPrimary)
            }
        case .divider:
            Spacer().frame(height: DS.Space.s3)
        case .table(let rows):
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: DS.Space.s4, verticalSpacing: DS.Space.s2) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(MarkdownBlocks.inline(cell))
                                    .dsText(i == 0 ? .heading17 : .body17)
                                    .foregroundStyle(i == 0 ? DS.textPrimary : DS.textSecondary)
                                    .frame(maxWidth: 220, alignment: .leading)
                            }
                        }
                    }
                }
            }
        case .image(let alt, let src):
            if let url = URL(string: src), url.scheme == "https" {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Color.clear.frame(height: 120)
                }
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
            } else {
                Label(alt.isEmpty ? String(localized: "Picture") : alt, systemImage: "photo")
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
            }
        }
    }

    private func prose(_ text: String, ink: Color = DS.textPrimary) -> some View {
        Text(MarkdownBlocks.inline(text))
            .dsText(.reading17)
            .foregroundStyle(ink)
            .tint(DS.tint)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The page's layer in the shell, as the note page's is (`NotePageLayer`):
/// it fetches the doc it was asked for once, on appear (never in a body,
/// §628), and closes back to where it was raised.
struct FileverseDocLayer: View {
    let chrome: ShellChrome
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var thing: Thing?

    var body: some View {
        ZStack {
            DS.page.ignoresSafeArea()
            if let thing, thing.isLive {
                FileverseDocPage(thing: thing, onCancel: close)
            }
        }
        .onAppear {
            guard let id = chrome.docToRead else { return }
            let descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.id == id })
            thing = try? modelContext.fetch(descriptor).first
            if thing == nil { close() }
        }
    }

    private func close() {
        withAnimation(reduceMotion ? nil : DS.Motion.standard) { chrome.docToRead = nil }
    }
}
