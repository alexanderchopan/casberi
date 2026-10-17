import Foundation

/// **UNDER "NEEDS YOU" A ROW DOES NOT SAY IT NEEDS YOU (prd §1378).** The
/// heading already says a row waits on you, so the words a bridge put in the
/// stored title to say the same thing are dropped there, and only there: in
/// the Feed the title still has to carry them.
///
/// - Wise leads a stuck transfer with "Needs attention · " (`WiseBridge`, prd
///   §852): the amounts lead instead.
/// - Safe appends " — your signature is needed" (`SafeBridge`), which the
///   title seam (§915) makes the line's first clause: the clause goes, and
///   "2 of 3 signatures collected on …" stays the title.
///
/// Foundation-only; `needs-you-words-selftest.sh` compiles it whole.
enum NeedsYouWords {
    /// Wise's stuck word, `WiseBridge.stuckTag`'s string.
    static var stuck: String { String(localized: "Needs attention") }
    /// Safe's clause once the seam has split it off.
    static var yourSignature: String { String(localized: "your signature is needed") }

    /// The row's name without a leading stuck word. A title that is nothing
    /// but the word keeps it: a row is never nameless.
    static func name(_ name: String) -> String {
        let lead = stuck + " · "
        guard name.hasPrefix(lead) else { return name }
        let rest = name.dropFirst(lead.count).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? name : rest
    }

    /// The seam's qualifier, nil when all it said was that you are needed.
    static func qualifier(_ line: String?) -> String? {
        guard let line else { return nil }
        let said = line.trimmingCharacters(in: .whitespaces)
        return said.compare(yourSignature, options: [.caseInsensitive]) == .orderedSame ? nil : line
    }
}
