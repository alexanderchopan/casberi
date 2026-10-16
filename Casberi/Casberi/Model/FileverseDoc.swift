import Foundation

/// A dDoc's tree, written as the Markdown Casberi draws (prd §1346). The
/// editor's nodes are ProseMirror's (Tiptap's names, measured off four real
/// documents in §1339): `dBlock` wraps every top-level block; inside are
/// `heading` (`level`), `paragraph`, `bulletList`/`orderedList`/`taskList`
/// with `listItem`/`taskItem` (`checked`), `table`/`tableRow`/`tableHeader`/
/// `tableCell`, `blockquote`, `codeBlock` (`language`), `horizontalRule`,
/// `hardBreak` and `resizableMedia` (`src`). Marks are formats on the text:
/// `bold`, `italic`, `strike`, `code`, `link` (`href`), `underline`.
///
/// A node this does not know keeps its words: its children are walked as if
/// it were a wrapper, so a new block type reads as plain paragraphs rather
/// than vanishing (§83: never an empty page over a document that has words).
enum FileverseDoc {
    /// The document as Markdown: ATX headings, `-`/`1.`/`- [ ]` lists indented
    /// two spaces a level, `>` quotes, fenced code, `---`, pipe tables and
    /// `![alt](src)` images. Inline marks are `**`, `_`, `~~`, `` ` `` and
    /// `[text](href)`; a character that would read as a mark is escaped.
    static func markdown(_ nodes: [Yjs.Node]) -> String {
        var out: [String] = []
        blocks(nodes, depth: 0, into: &out)
        // Collapse runs of blank lines, trim the ends.
        var lines: [String] = []
        for line in out {
            if line.isEmpty, lines.last?.isEmpty ?? true { continue }
            lines.append(line)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    /// The words alone, one block a line — what search and a row's excerpt read.
    static func plainText(_ nodes: [Yjs.Node]) -> String {
        var out: [String] = []
        func walk(_ n: Yjs.Node) {
            switch n {
            case .text(let runs):
                let s = runs.compactMap(\.text).joined()
                if !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(s) }
            case .element(let name, _, let children):
                if isInlineParent(name) {
                    let s = inlinePlain(children)
                    if !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(s) }
                } else {
                    children.forEach(walk)
                }
            }
        }
        nodes.forEach(walk)
        return out.joined(separator: "\n")
    }

    // MARK: Blocks

    private static func isInlineParent(_ name: String) -> Bool {
        ["paragraph", "heading", "codeBlock"].contains(name)
    }

    private static func blocks(_ nodes: [Yjs.Node], depth: Int, into out: inout [String]) {
        for n in nodes {
            switch n {
            case .text(let runs):
                let s = inline(runs)
                if !s.isEmpty { out.append(s); out.append("") }
            case .element(let name, let attrs, let children):
                block(name, attrs, children, depth: depth, into: &out)
            }
        }
    }

    private static func block(_ name: String, _ attrs: [String: Yjs.Value], _ children: [Yjs.Node],
                              depth: Int, into out: inout [String]) {
        switch name {
        case "paragraph":
            out.append(inline(children))
            out.append("")
        case "heading":
            let level = max(1, min(6, Int(attrs["level"]?.number ?? 1)))
            let text = inline(children)
            if !text.isEmpty { out.append(String(repeating: "#", count: level) + " " + text) }
            out.append("")
        case "bulletList", "orderedList", "taskList":
            var n = Int(attrs["start"]?.number ?? 1)
            for child in children {
                guard case .element(let itemName, let itemAttrs, let itemChildren) = child else { continue }
                let marker: String
                if name == "orderedList" {
                    marker = "\(n). "
                    n += 1
                } else if itemName == "taskItem" || name == "taskList" {
                    marker = itemAttrs["checked"]?.bool == true ? "- [x] " : "- [ ] "
                } else {
                    marker = "- "
                }
                listItem(itemChildren, marker: marker, depth: depth, into: &out)
            }
            if depth == 0 { out.append("") }
        case "listItem", "taskItem":
            listItem(children, marker: "- ", depth: depth, into: &out)
        case "blockquote":
            var inner: [String] = []
            blocks(children, depth: 0, into: &inner)
            for line in inner where !line.isEmpty { out.append("> " + line) }
            out.append("")
        case "codeBlock":
            let lang = attrs["language"]?.string ?? ""
            out.append("```" + lang)
            out.append(contentsOf: inlinePlain(children).components(separatedBy: "\n"))
            out.append("```")
            out.append("")
        case "horizontalRule":
            out.append("---")
            out.append("")
        case "table":
            table(children, into: &out)
            out.append("")
        case "resizableMedia", "image":
            if let src = attrs["src"]?.string, !src.isEmpty {
                let alt = attrs["alt"]?.string ?? ""
                out.append("![\(escape(alt))](\(src))")
                out.append("")
            }
        default:
            // `dBlock` and anything new: a wrapper, walked for its words.
            blocks(children, depth: depth, into: &out)
        }
    }

    private static func listItem(_ children: [Yjs.Node], marker: String, depth: Int, into out: inout [String]) {
        let indent = String(repeating: "  ", count: depth)
        var first = true
        for child in children {
            if case .element(let name, let attrs, let grand) = child,
               ["bulletList", "orderedList", "taskList"].contains(name) {
                block(name, attrs, grand, depth: depth + 1, into: &out)
                continue
            }
            let line: String
            switch child {
            case .element(let name, _, let grand) where isInlineParent(name): line = inline(grand)
            case .element(_, _, let grand): line = inlinePlain(grand)
            case .text(let runs): line = inline(runs)
            }
            if first {
                out.append(indent + marker + line)
                first = false
            } else if !line.isEmpty {
                out.append(indent + String(repeating: " ", count: marker.count) + line)
            }
        }
        if first { out.append(indent + marker) }
    }

    private static func table(_ rows: [Yjs.Node], into out: inout [String]) {
        var grid: [[String]] = []
        for row in rows {
            guard case .element(_, _, let cells) = row else { continue }
            grid.append(cells.map { cell -> String in
                guard case .element(_, _, let content) = cell else { return "" }
                var parts: [String] = []
                for c in content {
                    switch c {
                    case .element(let name, _, let grand) where isInlineParent(name): parts.append(inline(grand))
                    case .element(_, _, let grand): parts.append(inlinePlain(grand))
                    case .text(let runs): parts.append(inline(runs))
                    }
                }
                return parts.filter { !$0.isEmpty }.joined(separator: " ")
                    .replacingOccurrences(of: "|", with: "\\|")
                    .replacingOccurrences(of: "\n", with: " ")
            })
        }
        guard let width = grid.map(\.count).max(), width > 0 else { return }
        for (i, row) in grid.enumerated() {
            let padded = row + Array(repeating: "", count: width - row.count)
            out.append("| " + padded.joined(separator: " | ") + " |")
            if i == 0 { out.append("|" + Array(repeating: " --- |", count: width).joined()) }
        }
    }

    // MARK: Inline

    private static func inline(_ children: [Yjs.Node]) -> String {
        var s = ""
        for c in children {
            switch c {
            case .text(let runs): s += inline(runs)
            case .element("hardBreak", _, _): s += "  \n"
            case .element(let name, let attrs, _) where name == "resizableMedia" || name == "image":
                if let src = attrs["src"]?.string { s += "![\(escape(attrs["alt"]?.string ?? ""))](\(src))" }
            case .element(_, _, let grand): s += inline(grand)
            }
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static func inline(_ runs: [Yjs.Run]) -> String {
        var s = ""
        for r in runs {
            guard let text = r.text else { continue }
            if r.attributes["code"] != nil {
                s += wrap(text, "`", escaped: text.replacingOccurrences(of: "`", with: "'"))
                continue
            }
            var body = escape(text)
            if r.attributes["strike"] != nil { body = wrap(text, "~~", escaped: body) }
            if r.attributes["italic"] != nil { body = wrap(text, "_", escaped: body) }
            if r.attributes["bold"] != nil { body = wrap(text, "**", escaped: body) }
            if case .object(let link)? = r.attributes["link"], let href = link["href"]?.string {
                body = "[\(body)](\(href))"
            }
            s += body
        }
        return s
    }

    /// Wraps a run in a mark with its edge whitespace kept outside, because
    /// Markdown does not read `** bold**` as bold.
    private static func wrap(_ raw: String, _ mark: String, escaped: String) -> String {
        let lead = escaped.prefix { $0 == " " }
        let trail = escaped.reversed().prefix { $0 == " " }
        let core = escaped.trimmingCharacters(in: .whitespaces)
        guard !core.isEmpty, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return escaped }
        return lead + mark + core + mark + String(trail)
    }

    private static func inlinePlain(_ children: [Yjs.Node]) -> String {
        var s = ""
        for c in children {
            switch c {
            case .text(let runs): s += runs.compactMap(\.text).joined()
            case .element("hardBreak", _, _): s += "\n"
            case .element(_, _, let grand): s += inlinePlain(grand)
            }
        }
        return s
    }

    private static func escape(_ s: String) -> String {
        var out = ""
        for ch in s {
            if "\\*_~`[]".contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }
}
