import Foundation

/// APPLE'S RECEIPT MAILS, READ STRICTLY — a MEASUREMENT, not a feature.
///
/// The Wallet's Subscriptions tile (prd §1105, §1112) reads anything billed
/// through the App Store as the merchant "Apple", so the app behind the charge
/// is unknown and it lands in the map's Other tile. Apple mails a receipt for
/// those charges, and the receipt names the app. This file is the reader the
/// probe (`-appleReceiptProbe`) uses to find out whether that is good enough
/// to name a charge.
///
/// ## Nothing here is measured
///
/// **No real Apple receipt was available when this was written.** Every
/// layout below is written from public knowledge of what these mails look
/// like, and every such place is marked `UNMEASURED`. Until the probe has run
/// over a real inbox and its numbers are recorded, **nothing may attach a
/// name this reader produces to a real charge**: it is called from
/// `Shell/ProbeHooks.swift` and nowhere else, and
/// `scripts/apple-receipts-selftest.sh` fails if that changes.
///
/// ## It fails closed
///
/// A mail is read only when its sender's domain is Apple's (exact, on the
/// registrable domain, never `contains`), its subject is one of the classes
/// below, and its text fits a layout WHOLE: a receipt whose items do not sum
/// to its own total, a block that ends in a price but is not shaped like an
/// item, a label that appears twice, a price in a spelling not in the table —
/// each yields no line at all, never a partial one.
///
/// ## What it does not check
///
/// The `From` address is whatever the mail claims. Before any of this names a
/// charge, the receiving server's `Authentication-Results` (DKIM pass for
/// Apple's domain) has to be part of the gate; the probe's `fetch` mode logs
/// it so that can be measured too. The price-and-date match against a real
/// card charge is the second fence: a forged receipt names nothing unless a
/// real charge of that amount landed within three days of it.
///
/// Foundation-only, so the self-test compiles it whole.
enum AppleReceipts {

    // MARK: - Values

    /// One thing a receipt says was bought.
    struct Line: Equatable {
        /// The app's name, as the mail spells it.
        var app: String
        /// The plan or in-app item, when the layout states one.
        var item: String?
        var amount: Double
        /// The currency mark exactly as printed ("$", "US$", "€").
        var symbol: String
        /// The ISO code, only when the mark names ONE currency. A bare "$" is
        /// printed by the US, Canadian and Australian storefronts alike, so it
        /// is nil here rather than assumed to be USD.
        var currency: String?
        /// The renewal date, when stated in a spelling that cannot be misread
        /// (a month by name, or ISO). "11/02/2026" is two different days on
        /// two storefronts and is left nil.
        var renews: Date?
    }

    /// One mail, read.
    struct Receipt: Equatable {
        var date: Date
        var lines: [Line]
        /// What the receipt says was charged in all (tax included, when it
        /// states a total); a labelled confirmation's one price otherwise.
        var total: Double
    }

    /// A coarse class of subject — what the probe logs INSTEAD of the subject.
    enum Shape: String {
        case receipt, confirmation, renewal, expiring, other
    }

    // MARK: - The sender gate

    /// Apple's own sending domains.
    ///
    /// UNMEASURED: receipts are widely reported as `no_reply@email.apple.com`
    /// and, years ago, `do_not_reply@itunes.com`. Both are Apple's registrable
    /// domains; which hosts under them actually send receipts today is what
    /// the probe counts.
    static let senderDomains: Set<String> = ["apple.com", "itunes.com"]

    /// Whether an address is at one of Apple's domains. EXACT on the
    /// registrable domain: `apple.com` or a host ending `.apple.com`.
    /// `apple.com.evil.example`, `notapple.com`, `apple.co`, a Cyrillic "а",
    /// a trailing dot and a display name smuggled into the address all fail.
    static func isAppleSender(_ address: String?) -> Bool {
        guard let address else { return false }
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let host = parts[1].lowercased()
        // ASCII letters, digits, dot and hyphen only: a homoglyph, a space or
        // an angle bracket is not a host this gate will reason about.
        guard !host.isEmpty, host.unicodeScalars.allSatisfy({
            ($0.value >= 97 && $0.value <= 122) || ($0.value >= 48 && $0.value <= 57)
                || $0 == "." || $0 == "-"
        }) else { return false }
        guard !host.hasPrefix("."), !host.hasSuffix("."), !host.contains("..") else { return false }
        return senderDomains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// The subject's class. Coarse on purpose: the sender gate is the fence,
    /// and this only picks which layout to hold the text to.
    ///
    /// UNMEASURED: "Your receipt from Apple.", "Your subscription
    /// confirmation", "Your subscription is renewing"/"Subscription Renewal",
    /// "Your subscription is expiring" are the English subjects publicly
    /// reported. A localized subject reads `other`, and `other` is never read.
    static func shape(subject: String) -> Shape {
        let s = subject.lowercased()
        if s.contains("receipt") || s.contains("invoice") { return .receipt }
        if s.contains("subscription confirmation") { return .confirmation }
        if s.contains("expir") { return .expiring }
        if s.contains("renew") { return .renewal }
        return .other
    }

    // MARK: - The reader

    /// The lines a mail states, or nothing.
    static func parse(sender: String?, subject: String, text: String) -> [Line] {
        read(sender: sender, subject: subject, text: text)?.lines ?? []
    }

    /// The same reading with its total, for the charge match. `date` is the
    /// mail's own; it is not read out of the text.
    static func receipt(sender: String?, subject: String, text: String, date: Date) -> Receipt? {
        guard let r = read(sender: sender, subject: subject, text: text) else { return nil }
        return Receipt(date: date, lines: r.lines, total: r.total)
    }

    private static func read(sender: String?, subject: String, text: String)
        -> (lines: [Line], total: Double)? {
        guard isAppleSender(sender) else { return nil }
        switch shape(subject: subject) {
        case .receipt:                 return itemised(text)
        case .confirmation, .renewal:  return labelled(text)
        case .expiring, .other:        return nil
        }
    }

    // MARK: Layout A — labelled fields (confirmation, renewal notice)

    /// UNMEASURED layout. A subscription confirmation or renewal notice is
    /// publicly described as a short table of labelled fields:
    ///
    ///     App                 Quillmark
    ///     Subscription        Pro (Monthly)
    ///     Content Provider    Quillmark Ltd
    ///     Renewal Price       $9.99/month
    ///     Renewal Date        Nov 2, 2026
    ///
    /// Read as: `Label: value`, `Label<tab or two spaces>value`, or a label
    /// alone on its line with the value on the next. EXACTLY one `App` and
    /// exactly one price label, or nothing: two apps in one mail is a layout
    /// this does not know.
    private static let appLabels: Set<String> = ["app"]
    private static let itemLabels: Set<String> = ["subscription"]
    private static let priceLabels: Set<String> = ["renewal price", "price"]
    private static let renewLabels: Set<String> = ["renewal date", "renews"]
    private static let otherLabels: Set<String> = ["content provider", "date of purchase"]

    private static func labelled(_ text: String) -> (lines: [Line], total: Double)? {
        let known = appLabels.union(itemLabels).union(priceLabels).union(renewLabels).union(otherLabels)
        var fields: [(label: String, value: String)] = []
        let raw = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var i = 0
        while i < raw.count {
            let line = raw[i].trimmingCharacters(in: .whitespaces)
            i += 1
            guard !line.isEmpty else { continue }
            if let (label, value) = splitLabel(line, known: known) {
                fields.append((label, value))
            } else if known.contains(line.lowercased()) {
                // A label alone: its value is the next line that is not blank.
                while i < raw.count, raw[i].trimmingCharacters(in: .whitespaces).isEmpty { i += 1 }
                guard i < raw.count else { return nil }
                let value = collapse(raw[i])
                // A label followed by another label has no value: unknown.
                guard !known.contains(value.lowercased()) else { return nil }
                fields.append((line.lowercased(), value))
                i += 1
            }
        }
        func only(_ labels: Set<String>) -> String?? {
            let hits = fields.filter { labels.contains($0.label) }
            if hits.count > 1 { return .none }          // twice: unknown layout
            return .some(hits.first?.value)
        }
        guard case .some(let app?) = only(appLabels),
              case .some(let priceText?) = only(priceLabels),
              case .some(let item) = only(itemLabels),
              case .some(let renewText) = only(renewLabels) else { return nil }
        guard isName(app), let price = price(priceText, allowPeriod: true) else { return nil }
        if let item, !isName(item) { return nil }
        let line = Line(app: app, item: item, amount: price.amount, symbol: price.symbol,
                        currency: price.currency, renews: renewText.flatMap(date))
        return ([line], price.amount)
    }

    /// `Label: value`, or `Label` then a tab or two spaces then the value.
    private static func splitLabel(_ line: String, known: Set<String>) -> (String, String)? {
        if let colon = line.firstIndex(of: ":") {
            let label = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = collapse(String(line[line.index(after: colon)...]))
            if known.contains(label), !value.isEmpty { return (label, value) }
        }
        if let gap = line.range(of: "\t+| {2,}", options: .regularExpression) {
            let label = line[..<gap.lowerBound].trimmingCharacters(in: .whitespaces).lowercased()
            let value = collapse(String(line[gap.upperBound...]))
            if known.contains(label), !value.isEmpty { return (label, value) }
        }
        return nil
    }

    // MARK: Layout B — the itemised receipt

    /// UNMEASURED layout. "Your receipt from Apple." is publicly described, in
    /// its plain-text part, as header blocks (`ORDER ID`, `DATE`, `BILLED TO`)
    /// and then one block per item, blank lines between:
    ///
    ///     Quillmark
    ///     Pro (Monthly)
    ///     Renews Nov 2, 2026
    ///     $9.99
    ///
    ///     TOTAL $9.99
    ///
    /// Held to all of these, or nothing:
    ///   • an `Order ID` line (the mark of a receipt, not a promotion);
    ///   • exactly one total;
    ///   • every block ending in a price is an ITEM (2–5 lines, the first a
    ///     name) or the totals — one that is neither voids the mail;
    ///   • one currency mark throughout;
    ///   • the items sum to the subtotal when one is stated, else the total.
    ///
    /// That the FIRST line of a block is the app and the second the plan is
    /// the assumption a real sample has to confirm before anything trusts it.
    private static let totalWords: Set<String> = ["total"]
    private static let subtotalWords: Set<String> = ["subtotal"]
    private static let taxWords: Set<String> = ["tax", "vat", "gst"]

    private static func itemised(_ text: String) -> (lines: [Line], total: Double)? {
        let all = text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n").map(collapse)
        guard all.contains(where: { $0.lowercased() == "order id" || $0.lowercased().hasPrefix("order id:") })
        else { return nil }

        // Blocks: runs of lines with no blank between.
        var blocks: [[String]] = [], current: [String] = []
        for line in all {
            if line.isEmpty { if !current.isEmpty { blocks.append(current); current = [] } }
            else { current.append(line) }
        }
        if !current.isEmpty { blocks.append(current) }

        var lines: [Line] = []
        var totals: [Price] = [], subtotals: [Price] = []
        for block in blocks {
            // Sums first: `TOTAL $9.99`, `Total: $9.99`, or the word and the
            // price on two lines. A block may hold several (subtotal, tax, total).
            var rest: [String] = []
            var j = 0
            var sawSum = false
            while j < block.count {
                if let (word, value) = sumLine(block[j], next: j + 1 < block.count ? block[j + 1] : nil) {
                    sawSum = true
                    if totalWords.contains(word) { totals.append(value.price) }
                    else if subtotalWords.contains(word) { subtotals.append(value.price) }
                    j += value.consumed
                } else { rest.append(block[j]); j += 1 }
            }
            if sawSum {
                // Anything priced left beside a sum is a layout this does not know.
                if rest.contains(where: { price($0, allowPeriod: false) != nil }) { return nil }
                continue
            }
            guard let last = block.last, let p = price(last, allowPeriod: false) else {
                // No price at its end: a header or the footer. But a price
                // INSIDE such a block is one this reader cannot place.
                if block.contains(where: { price($0, allowPeriod: false) != nil }) { return nil }
                continue
            }
            guard (2...5).contains(block.count), isName(block[0]) else { return nil }
            let middle = Array(block[1..<(block.count - 1)])
            guard !middle.contains(where: { price($0, allowPeriod: false) != nil }) else { return nil }
            let renewLine = middle.first { $0.lowercased().hasPrefix("renews ") }
            let item = middle.first.flatMap { $0.lowercased().hasPrefix("renews ") ? nil : $0 }
            if let item, !isName(item) { return nil }
            lines.append(Line(app: block[0], item: item, amount: p.amount, symbol: p.symbol,
                              currency: p.currency,
                              renews: renewLine.flatMap { date(String($0.dropFirst("renews ".count))) }))
        }

        guard !lines.isEmpty, totals.count == 1, subtotals.count <= 1, let total = totals.first else { return nil }
        let marks = Set(lines.map(\.symbol) + [total.symbol] + subtotals.map(\.symbol))
        guard marks.count == 1 else { return nil }
        let sum = lines.reduce(0) { $0 + $1.amount }
        let against = subtotals.first?.amount ?? total.amount
        guard abs(sum - against) < 0.005 else { return nil }
        guard total.amount + 0.005 >= sum else { return nil }
        return (lines, total.amount)
    }

    /// A sum's word and its price: on one line, or the word alone with the
    /// price on the next. `consumed` is how many lines it took.
    private static func sumLine(_ line: String, next: String?)
        -> (String, (price: Price, consumed: Int))? {
        let words = totalWords.union(subtotalWords).union(taxWords)
        let lower = line.lowercased()
        for word in words {
            if lower == word || lower == word + ":" {
                guard let next, let p = price(next, allowPeriod: false) else { return nil }
                return (word, (p, 2))
            }
            for lead in [word + " ", word + ": "] where lower.hasPrefix(lead) {
                if let p = price(String(line.dropFirst(lead.count)), allowPeriod: false) {
                    return (word, (p, 1))
                }
            }
        }
        return nil
    }

    // MARK: - Small strict readers

    struct Price: Equatable {
        var amount: Double
        var symbol: String
        var currency: String?
    }

    /// The marks this reads, longest first so "US$" is not read as "$". The
    /// code is nil where one mark is several currencies.
    private static let marks: [(String, String?)] = [
        ("US$", "USD"), ("CA$", "CAD"), ("A$", "AUD"), ("NZ$", "NZD"),
        ("$", nil), ("€", "EUR"), ("£", "GBP"), ("¥", nil),
    ]

    /// A WHOLE string that is one price: a mark then digits (`$9.99`,
    /// `US$1,299.00`, `¥980`), or digits, a comma decimal and a trailing euro
    /// (`9,99 €`). With `allowPeriod`, a trailing `/month`, `/year`, `/week`
    /// (or "per month" …) is accepted and dropped. Anything else — a range, a
    /// minus, text around it — is not a price.
    static func price(_ raw: String, allowPeriod: Bool) -> Price? {
        var s = collapse(raw)
        if allowPeriod,
           let r = s.range(of: "\\s*(/|per)\\s*(month|year|week)$", options: [.regularExpression, .caseInsensitive]) {
            s = String(s[..<r.lowerBound])
        }
        for (mark, code) in marks where s.hasPrefix(mark) {
            let digits = String(s.dropFirst(mark.count)).trimmingCharacters(in: .whitespaces)
            guard digits.range(of: "^(\\d{1,3}(,\\d{3})+|\\d+)(\\.\\d{2})?$", options: .regularExpression) != nil,
                  let amount = Double(digits.replacingOccurrences(of: ",", with: "")) else { return nil }
            return Price(amount: amount, symbol: mark, currency: code)
        }
        if s.hasSuffix("€") {
            let digits = String(s.dropLast()).trimmingCharacters(in: .whitespaces)
            guard digits.range(of: "^\\d+,\\d{2}$", options: .regularExpression) != nil,
                  let amount = Double(digits.replacingOccurrences(of: ",", with: ".")) else { return nil }
            return Price(amount: amount, symbol: "€", currency: "EUR")
        }
        return nil
    }

    /// A date that reads one way only: a month by its English name, or ISO.
    static func date(_ raw: String) -> Date? {
        let s = collapse(raw)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.isLenient = false
        for format in ["MMM d, yyyy", "MMMM d, yyyy", "d MMM yyyy", "d MMMM yyyy", "yyyy-MM-dd"] {
            f.dateFormat = format
            // Round-trip, so "Nov 2, 2026 and more" or a lenient parse is refused.
            if let d = f.date(from: s), f.string(from: d).lowercased() == s.lowercased() { return d }
        }
        return nil
    }

    /// Whether a string can stand as an app's or a plan's name: short, not a
    /// price, not an address, not one of the receipt's own words.
    private static func isName(_ s: String) -> Bool {
        guard (1...100).contains(s.count), !s.contains("@") else { return false }
        guard price(s, allowPeriod: true) == nil else { return false }
        let lower = s.lowercased()
        let reserved = totalWords.union(subtotalWords).union(taxWords).union(appLabels)
            .union(itemLabels).union(priceLabels).union(renewLabels).union(otherLabels)
            .union(["order id", "date", "billed to", "apple id", "apple account", "document no.", "receipt"])
        return !reserved.contains(lower) && !lower.hasPrefix("order id")
    }

    private static func collapse(_ s: String) -> String {
        s.replacingOccurrences(of: "[ \\t\\u{00A0}]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - The charge match (the probe's answer)

    /// The card descriptors an App Store charge arrives under.
    ///
    /// UNMEASURED beyond "Apple", which is what the Wallet's own rows carry;
    /// `APPLE.COM/BILL`, `Apple Services` and `ITUNES.COM/BILL` are the
    /// descriptors publicly reported on statements. Exact, after trimming and
    /// an `APL*` prefix some issuers add.
    static func isAppleBilling(merchant: String) -> Bool {
        var m = merchant.trimmingCharacters(in: .whitespaces).lowercased()
        for lead in ["apl*", "apl* "] where m.hasPrefix(lead) { m = String(m.dropFirst(lead.count)) }
        m = m.trimmingCharacters(in: .whitespaces)
        return ["apple", "apple.com/bill", "apple services", "itunes.com/bill", "apple.com/us"].contains(m)
    }

    enum Match: Equatable {
        case app(String)
        /// More than one app fits the same price and days, or the charge is a
        /// receipt's total over several items: no one name is honest.
        case ambiguous
        case none
    }

    static let matchDays = 3.0
    static let matchCents = 0.01

    /// Which app a charge was for, by the receipts read: the price within a
    /// cent and the mail within three days of the charge. A charge equal to a
    /// one-item receipt's TOTAL counts (tax makes the charge differ from the
    /// item's price); one equal to a several-item total is ambiguous.
    static func match(amount: Double, currency: String, at: Date, in receipts: [Receipt]) -> Match {
        var apps = Set<String>()
        var ambiguous = false
        for r in receipts where abs(r.date.timeIntervalSince(at)) <= matchDays * 86_400 {
            let fitting = r.lines.filter {
                abs($0.amount - amount) <= matchCents + 1e-9 && fits($0, currency: currency)
            }
            fitting.forEach { apps.insert($0.app) }
            if fitting.isEmpty, abs(r.total - amount) <= matchCents + 1e-9,
               let first = r.lines.first, fits(first, currency: currency) {
                if r.lines.count == 1 { apps.insert(first.app) } else { ambiguous = true }
            }
        }
        if apps.count == 1, !ambiguous, let app = apps.first { return .app(app) }
        return (apps.isEmpty && !ambiguous) ? .none : .ambiguous
    }

    /// A line's currency against a charge's: the code when the mark names
    /// one, else the family the mark can mean.
    private static func fits(_ line: Line, currency: String) -> Bool {
        if let code = line.currency { return code == currency }
        switch line.symbol {
        case "$": return ["USD", "CAD", "AUD", "NZD", "SGD", "HKD", "MXN"].contains(currency)
        case "¥": return ["JPY", "CNY"].contains(currency)
        default:  return false
        }
    }

    // MARK: - The shape of a mail this could not read (probe only)

    /// The receipt's own vocabulary: the only words `skeleton` lets through.
    private static let anchors: Set<String> = [
        "apple", "receipt", "invoice", "order", "id", "document", "no.", "date", "billed", "to",
        "total", "subtotal", "tax", "vat", "gst", "renews", "renewal", "app", "store", "subscription",
        "price", "content", "provider", "purchase", "of", "account", "payment", "method", "type",
        "item", "purchased", "from", "monthly", "yearly", "annual", "trial", "free", "icloud",
    ]

    /// A mail's LAYOUT with its content removed, so an unread format can be
    /// described in a log without the log holding the mail: each line becomes
    /// its anchors (the fixed vocabulary above), `<price>` for a price, `9`
    /// for a number, `w` for any other word (runs folded to `w+`). No name,
    /// address, order number or card digit survives; the self-test holds it
    /// to that.
    static func skeleton(_ text: String, maxLines: Int = 60) -> [String] {
        var out: [String] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            guard out.count < maxLines else { break }
            let line = collapse(raw)
            if line.isEmpty { if out.last != "" { out.append("") }; continue }
            var tokens: [String] = []
            for word in line.split(separator: " ") {
                let w = String(word)
                let bare = w.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":,;()"))
                let token: String
                if anchors.contains(bare) { token = bare + (w.hasSuffix(":") ? ":" : "") }
                else if price(w, allowPeriod: true) != nil { token = "<price>" }
                else if w.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) { token = "w" }
                else if w.unicodeScalars.contains(where: { CharacterSet.decimalDigits.contains($0) }) { token = "9" }
                else { token = "·" }
                if token == "w", tokens.last == "w" || tokens.last == "w+" { tokens[tokens.count - 1] = "w+" }
                else { tokens.append(token) }
            }
            out.append(tokens.joined(separator: " "))
        }
        return out
    }
}
