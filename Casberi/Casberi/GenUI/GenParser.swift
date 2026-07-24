import Foundation

/// The gen UI document parser — a faithful port of the prototype's engine
/// (brief §5). Line grammar: `id = Component(arg, arg, [refs], token)`.
///
/// Laws (brief §5): the renderer mounts a component when its line parses;
/// string props fill as tokens arrive; declared children render as skeletons
/// until their lines resolve; unresolved references drop from arrays; any
/// prefix of any document renders.
enum GenArg: Equatable {
    case string(String)
    case refs([String])
    case null

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    var refsValue: [String] {
        if case .refs(let r) = self { return r }
        return []
    }
}

struct GenEl: Equatable {
    let comp: String
    let args: [GenArg]
    /// True once this element's OWN line has fully arrived (closed its final
    /// paren) — false while it's still the stream's single current frontier
    /// line, mid-arrival (§199). A plain sentence growing character by
    /// character reads as a typewriter; a component computing LAYOUT from its
    /// args (a treemap's cell shares, a sparkline's point count) does not —
    /// re-deriving those from a partial, still-growing string produces
    /// visible jumps (a cell resizing, a chart redrawing) rather than a
    /// smooth reveal. Callers that render structured layout from `args` (see
    /// `GenRender`'s `.block` slot) hold their placeholder until this flips
    /// true; callers that just grow text (`Insight`, `LeadPost`) can ignore
    /// it and keep the original per-character reveal.
    var isComplete: Bool = true

    /// arg n as string ("" when absent/null) — mirrors `el.args[n] ?? ""`.
    func str(_ n: Int) -> String {
        guard n < args.count else { return "" }
        return args[n].stringValue ?? ""
    }
    /// arg n as refs array — mirrors `Array.isArray(el.args[n]) ? ... : []`.
    func refs(_ n: Int) -> [String] {
        guard n < args.count else { return [] }
        return args[n].refsValue
    }
}

typealias GenEls = [String: GenEl]

enum GenParser {

    /// Tokenizes an argument string. Exact port of the prototype's `u()`:
    /// commas split at depth 0 outside quotes; `"` toggles in-string; a
    /// partial trailing string (no closing quote) still yields — that is how
    /// props fill as tokens arrive.
    static func parseArgs(_ s: String) -> [GenArg] {
        var out: [GenArg] = []
        var buf = ""
        var depth = 0
        var inString = false

        func flush() {
            let t = buf.trimmingCharacters(in: .whitespaces)
            buf = ""
            guard !t.isEmpty else { return }
            if t == "null" {
                out.append(.null)
            } else if t.hasPrefix("\"") {
                if t.hasSuffix("\"") && t.count > 1 {
                    out.append(.string(String(t.dropFirst().dropLast())))
                } else {
                    out.append(.string(String(t.dropFirst()))) // partial — still fills
                }
            } else if t.hasPrefix("[") {
                let inner = t.hasSuffix("]") ? String(t.dropFirst().dropLast()) : String(t.dropFirst())
                let refs = inner.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                out.append(.refs(refs))
            } else {
                out.append(.string(t)) // bare token, e.g. a color name
            }
        }

        for ch in s {
            if ch == "\"" { inString.toggle(); buf.append(ch); continue }
            if !inString && ch == "[" { depth += 1 }
            if !inString && ch == "]" { depth -= 1 }
            if !inString && depth == 0 && ch == "," { flush(); continue }
            buf.append(ch)
        }
        flush()
        return out
    }

    // Complete line: `id = Comp(...)`. Partial line: `id = Comp(...` (no close).
    private static let completeLine = /^(\w+) = (\w+)\((.*)\)$/
    private static let partialLine  = /^(\w+) = (\w+)\((.*)$/

    /// A single COMPLETE line → its (id, GenEl), or nil if it doesn't match
    /// the line grammar. Pulled out of `parse` so `parseIncremental` can
    /// apply it to only the lines that need it.
    private static func parseCompleteLine(_ line: String) -> (String, GenEl)? {
        guard let m = line.firstMatch(of: completeLine) else { return nil }
        return (String(m.1), GenEl(comp: String(m.2), args: parseArgs(String(m.3)), isComplete: true))
    }

    /// A single PARTIAL (still-streaming) line → its (id, GenEl), or nil.
    private static func parsePartialLine(_ line: String) -> (String, GenEl)? {
        guard let m = line.firstMatch(of: partialLine) else { return nil }
        var argStr = String(m.3)
        if argStr.hasSuffix(")") { argStr = String(argStr.dropLast()) }
        return (String(m.1), GenEl(comp: String(m.2), args: parseArgs(argStr), isComplete: false))
    }

    /// Parses a prefix of the document into the element map. The last line is
    /// treated as partial unless the prefix is the whole document — a partial
    /// line still mounts its component (the mount law).
    static func parse(prefix: Substring, isComplete: Bool) -> GenEls {
        var els: GenEls = [:]
        let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
        let completeCount = isComplete ? lines.count : lines.count - 1

        for i in 0..<max(0, completeCount) {
            if let (id, el) = parseCompleteLine(String(lines[i])) { els[id] = el }
        }
        if completeCount < lines.count, completeCount >= 0 {
            if let (id, el) = parsePartialLine(String(lines[completeCount])) { els[id] = el }
        }
        return els
    }

    /// Same result as `parse(prefix:isComplete:)`, but for a caller that
    /// re-parses a MONOTONICALLY GROWING prefix on every call (GenStream's
    /// typewriter tick, ~every 30ms) — `parse` re-ran the complete-line regex
    /// over every already-completed line on every single tick, O(doc²) over a
    /// rich document's stream lifetime. A completed line's GenEl never
    /// changes once complete (the mount law only lets the LAST line still be
    /// partial), so `cache`/`cachedCompleteLines` let the caller carry
    /// forward what was already parsed — each line's regex match then runs
    /// exactly once for the whole stream, not once per tick. Safe only
    /// across calls for the SAME document with a growing `prefix`; reset both
    /// `inout` params to `[:]`/`0` whenever the document itself changes
    /// (`GenStream` does this in `stream(_:)` and `paint(_:)`).
    static func parseIncremental(prefix: Substring, isComplete: Bool,
                                  cache: inout GenEls, cachedCompleteLines: inout Int) -> GenEls {
        let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
        let completeCount = isComplete ? lines.count : lines.count - 1

        if completeCount > cachedCompleteLines {
            for i in cachedCompleteLines..<completeCount {
                if let (id, el) = parseCompleteLine(String(lines[i])) { cache[id] = el }
            }
            cachedCompleteLines = completeCount
        }
        var els = cache
        if completeCount < lines.count, completeCount >= 0 {
            if let (id, el) = parsePartialLine(String(lines[completeCount])) { els[id] = el }
        }
        return els
    }
}
