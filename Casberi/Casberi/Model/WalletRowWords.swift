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
        /// The figure is what a card paid out: unsigned, in the primary ink,
        /// as a shop's row reads ("Blue Bottle · $6.50").
        var spent = false
        /// What the row did, when its verb left the name for the lead's
        /// glyph (prd §1987). nil: the verb, if any, is still in the name.
        var act: WalletActionMark.Action? = nil
        /// The figure is money that came in: signed, in the received green.
        var received = false
    }

    /// The row's words off a stored title; nil for a title in another shape.
    static func read(_ title: String) -> Words? {
        swap(title) ?? safe(title) ?? moved(title) ?? spent(title) ?? wise(title) ?? acted(title)
    }

    // MARK: - The verb is the glyph

    /// **THE GLYPH SAYS THE VERB (prd §1987, user, 2026-11-26: "if we were
    /// using an icon for in vs out we wouldn't need to see 'received' would
    /// we? same for swap and all the other verbs").** "Received 5.214713 USDC
    /// privately on Aztec" ran off its row. Every own act whose verb has a
    /// glyph (`WalletActionMark.Action`) drops the verb: where it went or
    /// who it was is the name, the amount stands on the right, signed only
    /// when the money left you or came in. A verb with no glyph (Staked,
    /// Claimed, Wrapped) keeps its sentence and its row reads nil here.
    /// VoiceOver keeps the sentence (`spoken`).
    static func acted(_ title: String) -> Words? {
        let seam = TitleSeam.split(title)
        let s = seam.name
        if s.hasPrefix("Approved ") { return granted(seam) }
        if s.hasPrefix("Revoked ") { return revoked(seam) }
        // The verb, the clause that names where or who, and the sign.
        let verbs: [(verb: String, joint: String?, act: WalletActionMark.Action, sign: String)] = [
            ("Received ", " from ", .received, "+"), ("Sent ", " to ", .sent, "−"),
            ("Deposited ", " into ", .deposited, ""), ("Withdrew ", " from ", .withdrew, ""),
            ("Minted ", " on ", .minted, "+"), ("Burned ", nil, .burned, "−"),
        ]
        guard let v = verbs.first(where: { s.hasPrefix($0.verb) }) else { return nil }
        var rest = String(s.dropFirst(v.verb.count))
        // A private receive says where it landed with " on ": "Received 5 USDC
        // privately on Aztec" (`AztecAccountStore`).
        var place: String?
        for joint in [v.joint, v.act == .received ? " on " : nil].compactMap({ $0 }) {
            guard place == nil, let r = rest.range(of: joint, options: .backwards) else { continue }
            let named = rest[r.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !named.isEmpty else { continue }
            place = named
            rest = String(rest[..<r.lowerBound])
        }
        var privately = false
        if rest.hasSuffix(" privately") {
            privately = true
            rest = String(rest.dropLast(" privately".count))
        }
        let what = leg(rest)
        // Something to name: an amount, a place, or a piece a mint or a burn
        // made ("Burned an NFT"). A Wise stage ("Sent · £820 → €961 · Rent")
        // has none of them and keeps its words.
        guard let lead = what.symbol.first, lead.isLetter || lead.isNumber || lead.isCurrencySymbol,
              what.amount != nil || place != nil || v.act == .minted || v.act == .burned
        else { return nil }
        // "Burned an NFT": no amount, the thing itself is the name.
        let thing = what.amount == nil ? actName(what.symbol) : what.symbol
        return Words(name: place ?? thing,
                     figure: what.amount.map { "\(v.sign)\($0) \(what.symbol)" },
                     clause: privately ? String(localized: "Privately") : nil,
                     qualifier: seam.line,
                     spoken: s,
                     stayed: v.sign.isEmpty,
                     act: v.act,
                     received: v.sign == "+")
    }

    /// "Approved <spender> to spend <amount | unlimited> <asset>[ through
    /// Permit2]" and "Approved <spender> to manage all <asset>"
    /// (`WalletApprovals.title`, `SolanaActivity`): who holds the key is the
    /// name, what it opens stands on the right, unsigned, because nothing
    /// has moved yet; the key is Permissions' (prd §1987).
    private static func granted(_ seam: (name: String, line: String?)) -> Words? {
        var rest = String(seam.name.dropFirst("Approved ".count))
        var via: String?
        if rest.hasSuffix(" through Permit2") {
            via = String(localized: "Through Permit2")
            rest = String(rest.dropLast(" through Permit2".count))
        }
        for (joint, all) in [(" to spend ", false), (" to manage all ", true)] {
            guard let r = rest.range(of: joint) else { continue }
            let spender = rest[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
            let opens = rest[r.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !spender.isEmpty, !opens.isEmpty else { return nil }
            var figure = all ? String(localized: "All \(opens)") : opens
            if figure.hasPrefix("unlimited ") { figure = "Unlimited" + figure.dropFirst("unlimited".count) }
            return Words(name: spender, figure: figure, clause: via, qualifier: seam.line,
                         spoken: seam.name, stayed: true, act: .granted)
        }
        return nil
    }

    /// "Revoked <spender>'s <asset> approval[ through Permit2]" and "Revoked
    /// <spender>'s access to all <asset>": who lost the key is the name, what
    /// it no longer opens the line.
    private static func revoked(_ seam: (name: String, line: String?)) -> Words? {
        var rest = String(seam.name.dropFirst("Revoked ".count))
        var via: String?
        if rest.hasSuffix(" through Permit2") {
            via = String(localized: "Through Permit2")
            rest = String(rest.dropLast(" through Permit2".count))
        }
        guard let r = rest.range(of: "'s ") else { return nil }
        let spender = rest[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
        var what = String(rest[r.upperBound...])
        if what.hasPrefix("access to all ") {
            what = String(localized: "All \(what.dropFirst("access to all ".count))")
        } else if what.hasSuffix(" approval") {
            what = String(what.dropLast(" approval".count))
        } else { return nil }
        guard !spender.isEmpty, !what.isEmpty else { return nil }
        return Words(name: spender, clause: [what, via].compactMap { $0 }.joined(separator: " · "),
                     qualifier: seam.line, spoken: seam.name, act: .revoked)
    }

    // MARK: - Card spending

    /// **A CARD'S ROW SAYS ITS AMOUNT ONCE (prd §1810).** "Spent $12.40 with
    /// MetaMask Card" and "Settled $246.31 of card spending" carry the figure
    /// in the sentence, and the row drew the transfer's own beside it
    /// ("−12.40 USDC"), which cut the name to make room. The card is the
    /// name and the sentence's figure stands on the right, as a shop's row
    /// reads. A send, a receive and a swap keep their sentence (§1805).
    static func spent(_ title: String) -> Words? {
        let seam = TitleSeam.split(title)
        // A card's name is drawn as written ("ether.fi Cash"); what a
        // settlement settled is a common noun and takes a capital.
        for (verb, joint, noun) in [("Spent ", " with ", false), ("Settled ", " of ", true)] {
            guard seam.name.hasPrefix(verb),
                  let at = seam.name.range(of: joint) else { continue }
            let start = seam.name.index(seam.name.startIndex, offsetBy: verb.count)
            guard start < at.lowerBound else { return nil }
            let figure = seam.name[start..<at.lowerBound].trimmingCharacters(in: .whitespaces)
            let who = seam.name[at.upperBound...].trimmingCharacters(in: .whitespaces)
            // A figure is money: a currency sign or a digit leads it, and a
            // digit is in it.
            guard let first = figure.first, first.isNumber || first.isCurrencySymbol,
                  figure.contains(where: \.isNumber), !figure.contains(" "),
                  let initial = who.first else { return nil }
            return Words(name: noun ? initial.uppercased() + who.dropFirst() : who,
                         figure: figure, qualifier: seam.line,
                         spoken: seam.name, spent: true)
        }
        return nil
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
        // **ACTIVITY KEEPS THE SENTENCE MOVE WROTE (prd §1805, amending
        // §1555's "the swap glyph says Swapped"):** a swap's row reads as a
        // send's and a receive's do, verb first, in the past tense.
        // **THE PAIR IS THE NAME, THE AMOUNTS THE LINE (prd §1863, amending
        // §1805's whole sentence):** "Swapped 1,240 USDC for 0.4962 E…" ran
        // off the row. The name keeps the verb and says what for what
        // ("Swapped USDC for ETH"); the amounts and the venue are the line.
        // **THE GLYPH SAYS "SWAPPED" AGAIN (prd §1987, amending §1805 item
        // 8):** the pair is the name ("ETH → TAC"), the lead's two-way arrow
        // the verb; `FollowedSince`, a line with no glyph, keeps the word.
        let name = "\(out.symbol) → \(inn.symbol)"
        let said = "Swapped \(Self.amounted(out)) for \(Self.amounted(inn))"
        let on = venue.flatMap { $0.isEmpty ? nil : $0 }
        let amounts = out.amount == nil && inn.amount == nil
            ? nil : "\(Self.amounted(out)) → \(Self.amounted(inn))"
        let clause = amounts.map { a in on.map { "\(a) on \($0)" } ?? a } ?? on.map { "On \($0)" }
        return Words(name: name,
                     clause: clause,
                     qualifier: seam.line,
                     spoken: said + (on.map { " on \($0)" } ?? ""),
                     act: .exchanged)
    }

    // MARK: - Wise

    /// "<Stage> · <amounts>[ · <reference>]" (`WiseBridge.rowTitle`). The
    /// reference ran the name off the row ("Sending · £120 → €141 ·
    /// Invoice…"), so the name is the stage and the amounts, the reference
    /// the line (prd §1863). "Needs attention · " keeps its seam so the
    /// Needs-you trim (`NeedsYouWords`) still finds it.
    static func wise(_ title: String) -> Words? {
        let seam = TitleSeam.split(title)
        for stage in ["Sent", "Sending", "Returned", "Needs attention"] {
            let lead = stage + " · "
            guard seam.name.hasPrefix(lead) else { continue }
            let rest = String(seam.name.dropFirst(lead.count))
            guard rest.contains(" → ") || rest.first?.isCurrencySymbol == true || rest.first?.isNumber == true
            else { return nil }
            let parts = rest.components(separatedBy: " · ")
            guard let amounts = parts.first, !amounts.isEmpty else { return nil }
            let reference = parts.dropFirst().joined(separator: " · ")
            let name = stage == "Needs attention" ? lead + amounts : "\(stage) \(amounts)"
            return Words(name: name, clause: reference.isEmpty ? nil : reference,
                         qualifier: seam.line, spoken: seam.name)
        }
        return nil
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
