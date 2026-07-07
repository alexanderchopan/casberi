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

    /// Parses a prefix of the document into the element map. The last line is
    /// treated as partial unless the prefix is the whole document — a partial
    /// line still mounts its component (the mount law).
    static func parse(prefix: Substring, isComplete: Bool) -> GenEls {
        var els: GenEls = [:]
        let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
        let completeCount = isComplete ? lines.count : lines.count - 1

        for i in 0..<max(0, completeCount) {
            if let m = String(lines[i]).firstMatch(of: completeLine) {
                els[String(m.1)] = GenEl(comp: String(m.2), args: parseArgs(String(m.3)))
            }
        }
        if completeCount < lines.count, completeCount >= 0 {
            let last = String(lines[completeCount])
            if let m = last.firstMatch(of: partialLine) {
                var argStr = String(m.3)
                if argStr.hasSuffix(")") { argStr = String(argStr.dropLast()) }
                els[String(m.1)] = GenEl(comp: String(m.2), args: parseArgs(argStr))
            }
        }
        return els
    }
}
