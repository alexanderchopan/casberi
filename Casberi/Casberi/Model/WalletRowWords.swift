import Foundation

/// **A MONEY ROW'S NAME FITS ITS ONE LINE (prd §1414).** The Wallet's rows
/// draw a one-line name (§902, "don't wrap them"), and two bridges store a
/// whole sentence as the title, so the row cut its tail: "Swapped 0.0136 ETH
/// → 32.55 USDC on…" and "1 of 2 signatures collected on deposit e t h". The
/// sentence stays in the store — `SwapStage`, `MoneyReceipt` and the sheet
/// parse it — and the row reads it into the anatomy's three slots instead:
///
/// - **A swap** is the trade as it reads, its verb left to the swap glyph
///   (prd §1555): "0.0136 ETH for 32.55 USDC", the venue on the line ("On
///   Uniswap"), and VoiceOver keeps "Swapped …" (`spoken`). It was §1414's
///   pair, "ETH → USDC on Uniswap", with the amounts on either side.
/// - **A move between your own accounts** names the two accounts
///   ("accountless.eth → You") and puts the amount on the right with no
///   sign and no colour, because the money stayed yours (§1078, §1550).
/// - **A Safe row** names the act ("Deposit ETH", "Transfer of 1,500 USDC to
///   payroll.eth") and puts the count on the line ("1 of 2 signed"), ahead
///   of the clause the seam carried ("your signature is needed"), which
///   `NeedsYouWords` still drops under the heading that says it.
///
/// The stored shapes are `WalletIngest.swapThing`'s, `SolanaActivity.story`'s
/// and `SafeBridge.rowFace`'s; any other title reads nil and the row draws
/// the seam as before. Foundation-only; `wallet-row-words-selftest.sh`
/// compiles it whole.
enum WalletRowWords {
    struct Words: Equatable {
        /// The row's name.
        var name: String
        /// The signed figure for the trailing column, nil when the title
        /// carries no amount in.
        var figure: String? = nil
        /// The line's first clause.
        var clause: String? = nil
        /// What the title's seam said, for the row's own Needs-you trim.
        var qualifier: String? = nil
        /// What VoiceOver says for the name, when the drawn name dropped a
        /// word the glyph carries ("Swapped 0.5 ETH for 1,240 USDC").
        var spoken: String? = nil
        /// The figure is money that stayed yours (a move between your own
        /// accounts): unsigned, in the primary ink, never the received green.
        var stayed = false
    }

    /// The row's words off a stored title; nil for a title in another shape.
    static func read(_ title: String) -> Words? {
        swap(title) ?? safe(title) ?? moved(title)
    }

    // MARK: - Moves between your own accounts

    /// "Moved <amount> <SYMBOL> · <from> → <to>" (`WalletIngest`'s own-move
    /// arm; `MovedStage` parses the same). The sentence ran off the row
    /// ("Moved 0.0002 ETH · accountless.eth →…", user 2026-10-26: "I don't
    /// like it when it's an activity item that runs off the screen"), so the
    /// accounts are the name and the amount stands on the right (prd §1550).
    static func moved(_ title: String) -> Words? {
        let seam = TitleSeam.split(title)
        let prefix = "Moved "
        guard seam.name.hasPrefix(prefix),
              let dot = seam.name.range(of: " · "),
              let arrow = seam.name.range(of: " → ", range: dot.upperBound..<seam.name.endIndex) else { return nil }
        let start = seam.name.index(seam.name.startIndex, offsetBy: prefix.count)
        let what = leg(String(seam.name[start..<dot.lowerBound]))
        let from = seam.name[dot.upperBound..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
        let to = seam.name[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !what.symbol.isEmpty, !from.isEmpty, !to.isEmpty else { return nil }
        // No amount: the symbol alone goes on the line, so the asset is said.
        return Words(name: "\(from) → \(to)",
                     figure: what.amount.map { "\($0) \(what.symbol)" },
                     clause: what.amount == nil ? what.symbol : nil,
                     qualifier: seam.line,
                     stayed: true)
    }

    // MARK: - Swaps

    /// "Swapped <out> → <in>[ on <venue>]". A leg is "<amount> <SYMBOL>" or
    /// a bare symbol; the venue is the last " on " after the arrow, so a
    /// symbol holding the word keeps it.
    static func swap(_ title: String) -> Words? {
        let seam = TitleSeam.split(title)
        let prefix = "Swapped "
        guard seam.name.hasPrefix(prefix),
              let arrow = seam.name.range(of: " → ") else { return nil }
        let start = seam.name.index(seam.name.startIndex, offsetBy: prefix.count)
        let out = leg(String(seam.name[start..<arrow.lowerBound]))
        var rest = String(seam.name[arrow.upperBound...])
        var venue: String?
        if let on = rest.range(of: " on ", options: .backwards) {
            venue = String(rest[on.upperBound...]).trimmingCharacters(in: .whitespaces)
            rest = String(rest[..<on.lowerBound])
        }
        let inn = leg(rest)
        guard !out.symbol.isEmpty, !inn.symbol.isEmpty else { return nil }
        // **THE SWAP GLYPH SAYS "SWAPPED" (user, 2026-10-26, prd §1555).** The
        // row's name is the trade as it reads, "0.5 ETH for 1,240 USDC", the
        // arrow said as "for"; the venue goes to the line ("On Uniswap").
        // Display only: the stored title keeps "Swapped …", which search,
        // `CounterpartyRetitle`, `BalancePrivacy` and the demo read, and
        // VoiceOver keeps the verb (`spoken`).
        let name = "\(Self.amounted(out)) for \(Self.amounted(inn))"
        let on = venue.flatMap { $0.isEmpty ? nil : $0 }
        return Words(name: name,
                     clause: on.map { "On \($0)" },
                     qualifier: seam.line,
                     spoken: "Swapped \(name)" + (on.map { " on \($0)" } ?? ""))
    }

    /// "0.5 ETH", or the bare symbol when the title carries no amount.
    private static func amounted(_ l: (amount: String?, symbol: String)) -> String {
        l.amount.map { "\($0) \(l.symbol)" } ?? l.symbol
    }

    /// "0.0136 ETH" → (0.0136, ETH); "ETH" → (nil, ETH). An amount starts
    /// with a digit; everything after the first space is the symbol.
    private static func leg(_ text: String) -> (amount: String?, symbol: String) {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard let first = text.first, first.isNumber,
              let space = text.firstIndex(of: " ") else { return (nil, text) }
        let symbol = String(text[text.index(after: space)...]).trimmingCharacters(in: .whitespaces)
        guard !symbol.isEmpty else { return (nil, text) }
        return (String(text[..<space]), symbol)
    }

    // MARK: - Safe

    /// "N of M signatures collected on <act>[ — <clause>]" and "Fully signed
    /// — <act> is ready to execute | is behind N earlier transaction(s)".
    static func safe(_ title: String) -> Words? {
        let seam = TitleSeam.split(title)
        if let r = seam.name.range(of: " signatures collected on ") {
            let head = seam.name[..<r.lowerBound].split(separator: " ")
            guard head.count == 3, head[1] == "of",
                  let have = Int(head[0]), let need = Int(head[2]) else { return nil }
            let act = String(seam.name[r.upperBound...])
            guard !act.isEmpty else { return nil }
            return Words(name: actName(act),
                         clause: String(localized: "\(have) of \(need) signed"),
                         qualifier: seam.line)
        }
        guard seam.name == "Fully signed", let line = seam.line else { return nil }
        let tails = [" is ready to execute": String(localized: "ready to execute"),
                     " is behind ": String(localized: "behind ")]
        for (tail, word) in tails {
            guard let t = line.range(of: tail) else { continue }
            let act = String(line[..<t.lowerBound])
            guard !act.isEmpty else { return nil }
            let rest = String(line[t.upperBound...])
            return Words(name: actName(act),
                         clause: "\(seam.name) · \(word)\(rest)")
        }
        return nil
    }

    /// The act as a name: the article goes, the first letter stands up.
    /// "a transfer of 1,500 USDC to payroll.eth" → "Transfer of 1,500 USDC to
    /// payroll.eth"; "deposit ETH" → "Deposit ETH".
    static func actName(_ act: String) -> String {
        var act = act.trimmingCharacters(in: .whitespaces)
        for article in ["an ", "a "] where act.lowercased().hasPrefix(article) && act.count > article.count {
            act = String(act.dropFirst(article.count))
            break
        }
        guard let first = act.first else { return act }
        return first.uppercased() + act.dropFirst()
    }

    // MARK: - ABI methods

    /// An ABI method's camelCase as words, a run of capitals kept whole:
    /// "multiSend" → "multi send", "depositETH" → "deposit ETH",
    /// "swapExactETHForTokens" → "swap exact ETH for tokens". Splitting on
    /// every capital read "deposit e t h". Cosmetic only: never changes WHICH
    /// method is named.
    static func method(_ method: String) -> String {
        let chars = Array(method)
        var out = ""
        for (i, ch) in chars.enumerated() {
            guard ch.isUppercase else { out.append(ch); continue }
            let prevLower = i > 0 && chars[i - 1].isLowercase
            let prevUpper = i > 0 && chars[i - 1].isUppercase
            let nextLower = i + 1 < chars.count && chars[i + 1].isLowercase
            let nextUpper = i + 1 < chars.count && chars[i + 1].isUppercase
            if prevLower || (prevUpper && nextLower) { out += " " }
            let acronym = (prevUpper || nextUpper) && !nextLower
            out += acronym ? String(ch) : ch.lowercased()
        }
        return out
    }
}
