import Foundation

/// An offer sitting on one of your cards, and the room that leads with them
/// (prd §420). Foundation-only BY DESIGN — `scripts/cardpointers-selftest.sh`
/// compiles it WHOLE.
///
/// **What is measured here and what is not, because the split is unusual.**
/// The VOCABULARY is measured, read off their own `tools/list` on 2026-08-20,
/// which answers for a free account even though every `tools/call` is refused:
/// the six offer statuses and the eighteen category strings below are exactly
/// theirs. The RESPONSE SHAPE is not — no account this project can reach may
/// read an offer — so the field names are the tolerant part, and `decode`
/// accepts several plausible spellings for each rather than betting the room
/// on one. A field that never matches yields nil and the row lands without
/// it; nothing here fails loudly, and nothing here invents a value.
enum CardPointers {

    /// Their own status vocabulary. `snoozed` is the one that matters most and
    /// is the easiest to get wrong: it is an offer somebody deliberately put
    /// away, so resurfacing it in a room built around "what needs you" hands
    /// back the exact thing they dismissed.
    enum Status: String, CaseIterable, Equatable {
        case active, snoozed, redeemed, expired

        /// Only an ACTIVE offer can need you. Everything else is either done,
        /// gone, or deliberately hidden.
        var needsYou: Bool { self == .active }
    }

    /// Measured off `list_my_offers`'s own enum — not ours, and deliberately
    /// not prettified. It exists so a category we are handed can be recognised
    /// rather than guessed at, and so an UNKNOWN one is visibly unknown.
    static let categories: Set<String> = [
        "airline", "cable satellite tv", "car rental", "department store",
        "drug store", "entertainment", "everywhere else", "gas station",
        "home improvement store", "hotel", "office supply store",
        "online shopping", "restaurant", "ride sharing", "supermarket",
        "telephone service", "utility", "warehouse clubs",
    ]

    struct Offer: Equatable {
        var id: String
        var merchant: String
        var card: String?
        var status: Status
        var expires: Date?
        /// Their own words for what the offer gives ("$10 back on $50+"). Kept
        /// as TEXT and never parsed into a number — see `Room` below.
        var terms: String?

        var ref: String { "cardpointers:offer:\(id)" }
    }

    // MARK: - Decoding

    private static func string(_ d: [String: Any], _ keys: [String]) -> String? {
        for k in keys {
            if let v = d[k] as? String, !v.isEmpty { return v }
            if let n = d[k] as? NSNumber { return n.stringValue }
        }
        return nil
    }

    /// Dates arrive in an unknown form, so three are accepted: ISO-8601 with
    /// and without a time, and a UNIX epoch. **A parse failure yields nil, not
    /// today** — an offer stamped with today's date would enter the deadline
    /// machinery as expiring immediately and fire a notification about a
    /// deadline nobody has.
    static func date(_ raw: Any?) -> Date? {
        if let n = raw as? NSNumber {
            let seconds = n.doubleValue
            guard seconds > 0 else { return nil }
            // Milliseconds if it is implausibly large as seconds — the Snapchat
            // `Created(microseconds)` lesson: decide by MAGNITUDE, never by
            // the label, because the label has been wrong before.
            return Date(timeIntervalSince1970: seconds > 4_000_000_000 ? seconds / 1000 : seconds)
        }
        guard let s = raw as? String, !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withFullDate]
        if let d = iso.date(from: s) { return d }
        let plain = DateFormatter()
        plain.locale = Locale(identifier: "en_US_POSIX")
        plain.timeZone = TimeZone(identifier: "UTC")
        plain.dateFormat = "yyyy-MM-dd"
        return plain.date(from: s)
    }

    /// One offer out of whatever they hand us. Returns nil rather than a
    /// half-offer when there is no id or no merchant: a row that cannot be
    /// identified cannot be deduped, and would re-land on every sync forever.
    static func decode(_ any: Any) -> Offer? {
        guard let d = any as? [String: Any] else { return nil }
        guard let id = string(d, ["id", "offer_id", "offerId", "uuid"]) else { return nil }
        guard let merchant = string(d, ["merchant", "merchant_name", "merchantName",
                                        "name", "title"]) else { return nil }
        let rawStatus = (string(d, ["status", "state"]) ?? "active").lowercased()
        // An unknown status is treated as ACTIVE deliberately: the failure that
        // matters is hiding a live offer, not showing a stale one, and their
        // vocabulary may grow.
        let status = Status(rawValue: rawStatus) ?? .active
        return Offer(
            id: id,
            merchant: merchant,
            card: string(d, ["card", "card_name", "cardName"]),
            status: status,
            expires: date(d["expiration"] ?? d["expires"] ?? d["expires_at"]
                          ?? d["expirationDate"] ?? d["end_date"]),
            terms: string(d, ["description", "terms", "offer", "summary", "details"]))
    }

    // MARK: - Reading a landed row back

    /// The merchant, with the card stripped off the front of a landed title.
    ///
    /// **A strip, not a parse.** `CardPointersIngest.title(for:)` writes
    /// "<card> · <merchant>" and the card is its OWN stored field, so this
    /// removes a known prefix rather than splitting on a separator a merchant
    /// might contain. If the prefix is not there the whole title IS the
    /// merchant — the same rule `GnosisPayRoomSource` follows for its amounts.
    ///
    /// It lives here, in the Foundation-only half, because §487 gave it a
    /// SECOND reader: the room head rebuilds offers from rows, and now the row
    /// itself leads with the merchant. Two copies of a strip is where a room's
    /// head and its own rows quietly start naming different things.
    static let titleSeparator = " · "

    static func merchant(title: String, card: String?) -> String {
        guard let card, !card.isEmpty else { return title }
        let prefix = card + titleSeparator
        guard title.hasPrefix(prefix) else { return title }
        return String(title.dropFirst(prefix.count))
    }

    /// The card's initials for a row's leading mark — at most two letters, from
    /// the first two WORDS ("Amex Gold" → "AG", "Chase Sapphire Reserve" →
    /// "CS"). Never a brand mark: this app bundles no card artwork, and
    /// `AssetMark` matching "Gold" against a token would put somebody else's
    /// logo on their credit card.
    ///
    /// Empty for a card we could not read, which the caller draws as the row's
    /// ordinary kind glyph rather than as a blank disc.
    static func initials(card: String?) -> String {
        guard let card else { return "" }
        let words = card.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return String(words.prefix(2).compactMap(\.first)).uppercased()
    }

    /// The payload is a JSON STRING inside the tool result, and its top level
    /// may reasonably be either an array or an object wrapping one.
    static func decodeList(_ payload: String) -> [Offer] {
        guard let data = payload.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let array = root as? [Any] { return array.compactMap(decode) }
        guard let object = root as? [String: Any] else { return [] }
        for key in ["offers", "results", "data", "items"] {
            if let array = object[key] as? [Any] { return array.compactMap(decode) }
        }
        return []
    }
}

extension CardPointers {

    /// What the CardPointers room LEADS with (prd §420, §487).
    ///
    /// **It never states a total value, and that is the load-bearing refusal.**
    /// The obvious card here is "$312 waiting for you", and it is false twice
    /// over: an offer is worth its face value only to somebody who was going to
    /// spend at that merchant anyway, so the sum is a CEILING rather than a
    /// saving; and the values are heterogeneous — "$10 back on $50+" beside
    /// "20% off" — so they do not share a unit any more than Gnosis Pay's
    /// currencies do (§349's per-currency rule, one product over). Their own
    /// words for each offer are shown on the row; nothing is added up.
    ///
    /// What it leads with instead is the DEADLINE, because that is the only
    /// thing here that gets worse while you do nothing, and it is the reading
    /// the app is uniquely placed to make: CardPointers knows your offers, and
    /// this app already has the machinery that puts a date on a lock screen.
    ///
    /// **§487 cut it to one sentence and a rail, and the deletions are the
    /// point.** It used to carry four blocks: the headline, the soonest offer
    /// in full, a card-by-card tally, and a footnote counting the undated. The
    /// soonest block was the first row of the list restated one card higher;
    /// the tally was a count, which the module doctrine already refuses as a
    /// thing and which nobody can act on; and the footnote described a group
    /// that now sits in the list under its own header, next to the rows it is
    /// about (§208 — never say one thing twice). What survives is the sentence
    /// and the one reading a sorted list genuinely cannot give: whether the
    /// deadlines are bunched or spread (§417).
    struct Room: Equatable {
        var headline: String
        /// Every deadline still ahead, soonest first. The rail's only input —
        /// dates, never rows, so the head holds no `Thing` (corollary 5).
        var deadlines: [Date]
    }

    /// Below this the room has nothing worth a head and falls back to whatever
    /// the generic registry offers. One offer is not a book.
    static let roomFloor = 2

    static func room(offers: [Offer], now: Date = Date(), soonWindowDays: Int = 7) -> Room? {
        // Only ACTIVE offers reach the head. `snoozed` is the sharp one: it is
        // an offer somebody deliberately put away, and a room built around
        // "what needs you" that resurfaces it hands back the exact thing they
        // dismissed. `redeemed` and `expired` are finished.
        let live = offers.filter { $0.status.needsYou }
        guard live.count >= roomFloor else { return nil }

        let dated = live.compactMap { offer -> Date? in offer.expires }
        // An offer whose date has already passed is not a deadline. It is left
        // out rather than reported as overdue, because their `expired` status
        // is the authority on that and a date we parsed is not.
        let ahead = dated.filter { $0 > now }.sorted()

        let cutoff = now.addingTimeInterval(TimeInterval(soonWindowDays) * 86_400)
        let expiringSoon = ahead.filter { $0 <= cutoff }.count

        let headline: String
        if expiringSoon > 0 {
            headline = expiringSoon == 1
                ? String(localized: "1 offer expires this week")
                : String(localized: "\(expiringSoon) offers expire this week")
        } else {
            headline = live.count == 1
                ? String(localized: "1 offer waiting")
                : String(localized: "\(live.count) offers waiting")
        }

        return Room(headline: headline, deadlines: ahead)
    }
}
