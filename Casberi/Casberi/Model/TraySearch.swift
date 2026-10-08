import Foundation

/// THE TRAY'S SEARCH, GROUPED BY CATEGORY (prd §1185, user: "one thing to
/// consider is also if the results should be grouped in categories, eg if i
/// search meta it could show it in markets, day (calendar if i had), agents
/// and so on", then "i like C"; mockup `design/mockups/search-everything.html`).
///
/// The empty tray is a list of categories with their apps under them, and
/// Home groups by category (§1152), so a search stands its hits under the
/// same names: "spotify" is the app in Media, the stock in Markets, the plan
/// in Wallet, the mailing list in Day. The rules here decide which hits
/// match, in what order, under which group, and what to offer when nothing
/// does; `RoomsTray` reads the stores and draws the rows.
///
/// Foundation-only: `scripts/tray-search-selftest.sh` compiles it whole.
enum TraySearch {

    /// What a row is, which orders it inside its group: names you have first
    /// (an app, an account, a person), then money (a holding, a stock, a
    /// plan), then things you kept, then an app you could add.
    enum Tier: Int, Comparable, Sendable {
        case name, money, thing, add
        static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }
    }

    /// One thing the search could show, by its index in the caller's list.
    struct Candidate: Equatable, Sendable {
        let index: Int
        /// The group it stands under: a dock category, Markets, or `you`.
        let group: String
        let name: String
        /// Other words that find it (a ticker, a coin's common names).
        var aliases: [String] = []
        var tier: Tier = .name
        /// A match on any word of the name, not only its start, counts — a
        /// thing's title is a sentence ("Sent 0.5 ETH to Uniswap").
        var anyWord = false
        /// Matched elsewhere already: a note Find's engine found by its
        /// words, an address pasted whole.
        var given: Match? = nil
    }

    /// How well a candidate matched: lower is better.
    enum Match: Int, Comparable, Sendable {
        case exact, prefix, word, inside
        static func < (a: Match, b: Match) -> Bool { a.rawValue < b.rawValue }
    }

    /// The group You's places, your notes and the people you know stand
    /// under; drawn with your name (`HomeScope.title`).
    static let you = "You"

    /// Rows a group draws before Find takes over.
    static let groupCap = 4
    /// Of those, how many may be things you kept: the names lead.
    static let thingCap = 2

    // MARK: - Words

    /// The words as the person meant them: trimmed, a leading `$` dropped
    /// ("$PEPE" is PEPE), case and accents left to the comparison.
    static func normalized(_ query: String) -> String {
        var q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        while q.hasPrefix("$") { q.removeFirst() }
        return q.trimmingCharacters(in: .whitespaces)
    }

    /// The coins people call by more than one name. A query for any of them
    /// finds the others: "ethereum" finds your ETH, "eth" an Ethereum row.
    static let coinNames: [[String]] = [
        ["ETH", "Ether", "Ethereum"],
        ["BTC", "Bitcoin"],
        ["SOL", "Solana"],
        ["USDC", "USD Coin"],
        ["USDT", "Tether"],
        ["POL", "Polygon", "MATIC"],
        ["AVAX", "Avalanche"],
        ["ARB", "Arbitrum"],
        ["OP", "Optimism"],
        ["WLD", "Worldcoin"],
        ["HYPE", "Hyperliquid"],
    ]

    /// The other names a coin's symbol or name goes by, the asked word left out.
    static func otherNames(_ word: String) -> [String] {
        let w = fold(word)
        guard let family = coinNames.first(where: { $0.contains { fold($0) == w } }) else { return [] }
        return family.filter { fold($0) != w }
    }

    /// The names a coin symbol answers to beyond itself, for a holding's
    /// candidate: ETH also answers "ether" and "ethereum".
    static func aliases(forSymbol symbol: String) -> [String] {
        coinNames.first { $0.contains { fold($0) == fold(symbol) } }?.filter { fold($0) != fold(symbol) } ?? []
    }

    /// Case- and accent-folded, for comparing.
    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func words(_ s: String) -> [Substring] {
        s.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    }

    /// How `text` answers the words, or nil. A name matches from its start,
    /// at the start of any word, or (for a name, at three letters or more)
    /// anywhere inside it — "base" finds Coinbase. A sentence matches only
    /// at a word's start: "eth" is not inside "something".
    static func match(_ text: String, _ query: String, anyWord: Bool = false) -> Match? {
        let t = fold(text), q = fold(normalized(query))
        guard !q.isEmpty else { return nil }
        if t == q { return .exact }
        if t.hasPrefix(q) { return .prefix }
        if q.contains(" ") {
            // Several words: each must start a word of the text, in any order.
            let tw = words(t).map(String.init)
            let qw = words(q).map(String.init)
            if !qw.isEmpty, qw.allSatisfy({ w in tw.contains { $0.hasPrefix(w) } }) { return .word }
            return nil
        }
        if words(t).contains(where: { $0.hasPrefix(q) }) { return .word }
        if !anyWord, q.count >= 3, t.contains(q) { return .inside }
        return nil
    }

    /// A candidate's best match across its name, its aliases, and the other
    /// names of the coin the words name.
    static func match(_ c: Candidate, _ query: String) -> Match? {
        if let given = c.given { return given }
        let asked = [normalized(query)] + otherNames(normalized(query))
        var best: Match?
        for q in asked {
            for text in [c.name] + c.aliases {
                guard let m = match(text, q, anyWord: c.anyWord) else { continue }
                // Another name of the coin is a match on the coin itself, but
                // never better than a prefix: the typed word leads.
                let scored = q == asked[0] ? m : max(m, .prefix)
                if best == nil || scored < best! { best = scored }
            }
        }
        return best
    }

    // MARK: - Groups

    /// One group of results, in draw order.
    struct Group: Equatable, Sendable {
        let name: String
        let hits: [Candidate]
    }

    /// The hits for the words, grouped and ordered:
    ///
    /// - **Which group leads:** the one you are standing in, then any holding
    ///   a hit whose own name is the words ("meta" leads with Markets; an app
    ///   before a stock of the same name), then You, Markets and the
    ///   dock's categories in the dock's order, then the rest A–Z.
    /// - **Inside a group:** an exact match, then tier (names, money, things,
    ///   apps to add), then
    ///   how well it matched, then the caller's order.
    /// - **How many:** `groupCap` a group, `thingCap` of them things.
    static func groups(_ candidates: [Candidate], query: String,
                       standing: String?, dockOrder: [String]) -> [Group] {
        var byGroup: [String: [(Candidate, Match)]] = [:]
        for c in candidates {
            guard let m = match(c, query) else { continue }
            byGroup[c.group, default: []].append((c, m))
        }
        var out: [Group] = []
        for (name, found) in byGroup {
            let ordered = found.sorted { a, b in
                // The thing called exactly the words leads ("eth": your ETH
                // before the ether.fi app), then tier.
                if (a.1 == .exact) != (b.1 == .exact) { return a.1 == .exact }
                if a.0.tier != b.0.tier { return a.0.tier < b.0.tier }
                if a.1 != b.1 { return a.1 < b.1 }
                return a.0.index < b.0.index
            }
            var things = 0
            var kept: [Candidate] = []
            for (c, _) in ordered where kept.count < groupCap {
                if c.tier == .thing {
                    guard things < thingCap else { continue }
                    things += 1
                }
                kept.append(c)
            }
            out.append(Group(name: name, hits: kept))
        }
        // Only a NAME promotes its group: Muse answers "meta" through its
        // maker, but Markets holds the thing called Meta.
        // Between two exact names the app beats its stock: "spotify" is the
        // app in Media before the company in Markets (tier, then order).
        var exact: [String: Int] = [:]
        for (g, found) in byGroup {
            let tiers = found.filter { match($0.0.name, query) == .exact }.map(\.0.tier.rawValue)
            if let best = tiers.min() { exact[g] = best }
        }
        let fixed = [you, markets] + dockOrder.filter { $0 != you && $0 != markets }
        func rank(_ g: String) -> (Int, Int, Int, String) {
            let at = fixed.firstIndex(of: g) ?? fixed.count
            if g == standing { return (0, 0, 0, g) }
            if let tier = exact[g] { return (1, tier, at, g) }
            return (2, 0, at, g)
        }
        return out.sorted { rank($0.name) < rank($1.name) }
    }

    /// Markets' name, spelled once for the ordering (`HomeScope.markets`).
    static let markets = "Markets"

    // MARK: - When nothing matches

    /// The names nearest the words when nothing contains them — a typo
    /// ("spotfy" is one letter from Spotify). Off under four letters, where
    /// one edit reaches half the catalogue; one edit under seven letters,
    /// two from seven. Compared against a name's first word as well as the
    /// whole name, so "spotfy" reaches "Spotify Technology".
    static func closest(_ query: String, among names: [String], limit: Int = 3) -> [Int] {
        let q = fold(normalized(query))
        guard q.count >= 4, !q.contains(" ") else { return [] }
        let reach = q.count >= 7 ? 2 : 1
        var scored: [(Int, Int)] = []
        for (i, name) in names.enumerated() {
            let n = fold(name)
            let first = words(n).first.map(String.init) ?? n
            let d = min(distance(q, n, cap: reach), distance(q, first, cap: reach))
            if d <= reach { scored.append((d, i)) }
        }
        return scored.sorted { $0 < $1 }.prefix(limit).map(\.1)
    }

    /// Damerau–Levenshtein (optimal string alignment) distance, stopping
    /// early once it must exceed `cap`.
    static func distance(_ a: String, _ b: String, cap: Int) -> Int {
        let a = Array(a), b = Array(b)
        if abs(a.count - b.count) > cap { return cap + 1 }
        if a.isEmpty || b.isEmpty { return max(a.count, b.count) }
        var prev2 = [Int](repeating: 0, count: b.count + 1)
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            var rowMin = cur[0]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    cur[j] = min(cur[j], prev2[j - 2] + 1)
                }
                rowMin = min(rowMin, cur[j])
            }
            if rowMin > cap { return cap + 1 }
            (prev2, prev, cur) = (prev, cur, prev2)
        }
        return prev[b.count]
    }

    // MARK: - What the words are

    /// An EVM address pasted whole: `0x` and forty hex digits.
    static func isEVMAddress(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count == 42, q.lowercased().hasPrefix("0x") else { return false }
        return q.dropFirst(2).allSatisfy(\.isHexDigit)
    }

    /// Whether the words could be a ticker worth looking up in Markets: one
    /// to five letters, an optional `$` before them.
    static func looksLikeTicker(_ query: String) -> Bool {
        let q = normalized(query)
        return (1...5).contains(q.count) && q.allSatisfy { $0.isASCII && $0.isLetter }
    }
}
