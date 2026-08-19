import Foundation

/// WHO CAN SIGN AS YOU, AND FOR HOW MUCH LONGER (2026-08-18, prd §403) — the
/// Altana room's head.
///
/// Every other wallet surface in this app answers *where is my money*. This
/// one answers a different question that account abstraction created: **which
/// credentials hold the ability to sign in my name, and when does each of them
/// stop?** It is `WalletActingParties` (§293) given a room of its own, because
/// a keystore publishes something those inventories never had — a start date
/// and an end date for every grant.
///
/// ## The runway is a TRUE fraction, and that is the point
///
/// `ASCRoom` (§324) had to gate its duration on "a transition this device
/// watched", because Apple publishes no timestamp for when a version entered
/// review — so on a fresh install the honest answer was silence. Here the
/// chain publishes BOTH ends: `getKey` carries the registration and
/// `getExpiry` the expiry, so a session key's bar shows real elapsed progress
/// through a real grant, on first sight, on every device, with nothing
/// observed locally. That is why this head can say "a 24-hour key, 3 hours
/// left" where the App Store head could only say "in review".
///
/// It also means the grant DURATION is a fact rather than an inference: the
/// measured BNB corpus is full of exactly-24-hour session keys, and naming
/// that is more useful than any percentage.
///
/// ## The hygiene reading
///
/// `isKeyActive` keeps returning true for a session key whose own expiry has
/// passed — measured, two of six sampled on BNB are in that state today. So
/// the registry lists credentials that cannot act. Nothing else surfaces
/// that, and it is the one line here that tells somebody to go and tidy up.
/// It is stated quietly and never alarmed about: an expired key is safe, it is
/// just noise in the list.
///
/// ## Refused, with reasons
///
/// **No security score and no judgement on key count.** Three keys is neither
/// good nor bad, and a number on a security screen is believed (§83 in the one
/// place it is most expensive). **No naming the app that registered a key** —
/// the registry does not record it, and a wrong name on a permissions notice
/// sends somebody to revoke the wrong thing (§239's rule). **No claim about
/// what a session key may DO** — the scope is not readable, so the copy states
/// what a key may sign *until*, never what it may sign *for*.
///
/// Costs nothing per open: composed from rows and readings the sweep already
/// took. Foundation-only so `scripts/altana-selftest.sh` compiles it as
/// shipped — nothing on this host can register or revoke a key, so the harness
/// is the only proof these numbers are right.
enum AltanaRoom {

    /// Below this, the head declines and the room renders as plain rows: a
    /// single root key with nothing else is the account merely existing, which
    /// the rows already say.
    static let minimumKeys = 2

    /// One credential, as the card draws it — root or session.
    ///
    /// It was `Session` until §405, and roots had no row at all: the most
    /// powerful credential on the account (permanent authority, no expiry) got
    /// a grey subline while three session keys got full rows with bars. That
    /// is importance drawn upside down, so both are rows now and `isRoot` is
    /// what separates them.
    struct KeyRow: Equatable, Identifiable {
        let id: String
        let isRoot: Bool
        /// "Passkey" / "Wallet key", computed from the key material itself
        /// (§404), or nil when the point satisfies neither curve.
        let kindLabel: String?
        /// "24-hour key", "30-day key", or nil when either end is unreadable.
        let grantPhrase: String?
        /// 0…1 through its own grant, or nil when it cannot be computed. Always
        /// nil for a root: a credential with no end has no runway, and drawing
        /// a full or empty bar would state a completion that does not exist.
        let progress: Double?
        let expiry: Date?
        /// Its own expiry has passed while the registry still lists it.
        let expired: Bool
        /// Whole days remaining, floored; nil once expired or unknown.
        let daysLeft: Int?
        /// Whole hours remaining, only meaningful inside the last day (§406):
        /// "today" under a headline saying "9 hours" is the card disagreeing
        /// with itself about the same clock.
        let hoursLeft: Int?
        let chainLabel: String?
        /// The key's own nonce (§404) — the room ignored this until §405 even
        /// though it was already in the snapshot it reads.
        let signatureCount: Int
        let registeredAt: Date?

        /// The row's leading word: the KIND when we can prove it, because
        /// "Passkey" is the only word here a person already owns. Falls back
        /// to the role, which is never a guess.
        var title: String {
            kindLabel ?? (isRoot ? String(localized: "Root key")
                                 : String(localized: "Session key"))
        }

        /// Usage, said only when it carries information. A session key that
        /// HAS been used is doing exactly what it was granted for and needs no
        /// remark; one that never has is the notable case. A root key's count
        /// is the account's own activity, so it is always worth stating.
        var usageNote: String? {
            if signatureCount == 0 { return String(localized: "never used") }
            guard isRoot else { return nil }
            return signatureCount == 1
                ? String(localized: "signed once")
                : String(localized: "signed \(signatureCount) times")
        }

        /// The second line (§406 rewording — "key" used to appear three times
        /// per row). The role is spelled ONLY when nothing else implies it: a
        /// grant implies a session, so "Session key · 24-hour key" said the
        /// same thing twice and now reads "24-hour grant"; a root whose title
        /// already says "key" leads with the bare word "Root".
        var detail: String? {
            var parts: [String] = []
            if isRoot {
                // "Root" when the title took the kind (it already says "key"),
                // "Root key" when the title IS the role and would otherwise
                // repeat itself exactly.
                if kindLabel != nil { parts.append(String(localized: "Root")) }
                if let registeredAt {
                    let when = registeredAt.formatted(date: .abbreviated, time: .omitted)
                    parts.append(String(localized: "registered \(when)"))
                }
            } else {
                if let grantPhrase {
                    parts.append(grantPhrase)
                } else if kindLabel != nil {
                    // No grant to imply the role, so the role is said.
                    parts.append(String(localized: "Session key"))
                }
            }
            if let usageNote { parts.append(usageNote) }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }

    /// The head.
    struct Card: Equatable {
        /// Lowercased hex of the wallet this card is about.
        let address: String
        /// Usable keys that can sign right now.
        let usableCount: Int
        let rootCount: Int
        /// The root credential's registration, when witnessed.
        let rootRegistered: Date?
        /// Every credential, ordered by `orderedRows` — roots, then live
        /// sessions soonest-first, then expired.
        let rows: [KeyRow]
        /// Hours until the soonest LIVE expiry, when that is close enough to
        /// be the reason to look today (`urgentWindowHours`). nil otherwise,
        /// and the headline then states the standing fact instead.
        let urgentHours: Int?
        /// Listed by the registry as active, but past their own expiry.
        let staleCount: Int
        /// Other watched wallets that also hold keys.
        let otherWallets: Int
        /// Distinct registries these keys live on.
        let chains: [String]

        /// Sessions only — the card drew these before roots had rows of their
        /// own, and the probe and harness still ask the question this way.
        var sessions: [KeyRow] { rows.filter { !$0.isRoot } }

        /// ALARM FIRST, then the standing fact.
        ///
        /// "3 keys can sign for this account" is true every day and is therefore
        /// never the reason to look today; "A key expires in 9 hours" is. The
        /// Stripe/ASC ranking, applied to a headline: state the thing with a
        /// clock on it when there is one, and only then the census.
        var headline: String {
            if let urgentHours {
                if urgentHours <= 0 { return String(localized: "A key expires within the hour") }
                return urgentHours == 1
                    ? String(localized: "A key expires in 1 hour")
                    : String(localized: "A key expires in \(urgentHours) hours")
            }
            let n = usableCount
            if n == 0 {
                return String(localized: "No key can sign for this account right now")
            }
            return n == 1
                ? String(localized: "1 key can sign for this account")
                : String(localized: "\(n) keys can sign for this account")
        }

        /// The census, kept when the alarm takes the headline (§406 — before
        /// this, "A key expires in 9 hours" deleted "3 keys can sign" from the
        /// card entirely). nil when the headline IS the census, so the card
        /// never says the same sentence twice.
        var subline: String? {
            guard urgentHours != nil else { return nil }
            let n = usableCount
            return n == 1
                ? String(localized: "1 key can sign for this account")
                : String(localized: "\(n) keys can sign for this account")
        }

        /// The hygiene line — nil when there is nothing to tidy.
        var staleNote: String? {
            guard staleCount > 0 else { return nil }
            return staleCount == 1
                ? String(localized: "1 key the registry still lists can no longer act")
                : String(localized: "\(staleCount) keys the registry still lists can no longer act")
        }

        var otherWalletsNote: String? {
            guard otherWallets > 0 else { return nil }
            return otherWallets == 1
                ? String(localized: "1 other watched wallet also has keys")
                : String(localized: "\(otherWallets) other watched wallets also have keys")
        }
    }

    /// How a grant's length is spelled — the SHAPE, shared by both wordings.
    ///
    /// Rounded to the unit the grant was plainly written in, because these are
    /// human-chosen durations — the measured BNB corpus is full of grants that
    /// are 24 hours to the second. "1.02 days" would be arithmetically closer
    /// and read as though we had failed to understand what we were looking at.
    ///
    /// One computation, two renderings (`grantPhrase`, `grantDetail`): the
    /// rounding here is measured and mutation-tested, and a second copy of it
    /// would be free to drift from the tested one.
    static func grantUnits(seconds: TimeInterval) -> (value: Int, unit: String)? {
        guard seconds > 0 else { return nil }
        let minutes = seconds / 60, hours = seconds / 3600, days = seconds / 86_400
        if days >= 1, days.roundsCleanly {
            let d = Int(days.rounded())
            // One day is said as 24 hours, which is how these grants are
            // actually written and how every one measured was expressed.
            return d == 1 ? (24, "hour") : (d, "day")
        }
        if hours >= 1, hours.roundsCleanly { return (Int(hours.rounded()), "hour") }
        if minutes >= 1 { return (Int(minutes.rounded()), "minute") }
        return nil
    }

    /// "24-hour key" — the SHEET's title, where the row is the key itself.
    static func grantPhrase(seconds: TimeInterval) -> String? {
        guard let (value, unit) = grantUnits(seconds: seconds) else { return nil }
        switch unit {
        case "day":    return String(localized: "\(value)-day key")
        case "hour":   return String(localized: "\(value)-hour key")
        default:       return String(localized: "\(value)-minute key")
        }
    }

    /// "24-hour grant" — the ROOM's detail line (§406).
    ///
    /// The room's rows already carry "key" in their title, so the old detail
    /// read "Session key · 24-hour key": the word three times in one row, and
    /// the role earning nothing, since a credential WITH a grant is a session
    /// by definition. Naming the grant instead says the same thing once.
    static func grantDetail(seconds: TimeInterval) -> String? {
        guard let (value, unit) = grantUnits(seconds: seconds) else { return nil }
        switch unit {
        case "day":    return String(localized: "\(value)-day grant")
        case "hour":   return String(localized: "\(value)-hour grant")
        default:       return String(localized: "\(value)-minute grant")
        }
    }

    /// The card for the best-ranked wallet, or nil when there is nothing worth
    /// heading the room with.
    ///
    /// RANKING, and it is total (a head that reshuffles between opens over
    /// identical data reads as broken — the `ASCRoom` ruling): a wallet with a
    /// live deadline outranks one without, soonest first; then more keys;
    /// then the address itself, so ties can never flip.
    static func compose(readings: [AltanaKeystore.Reading], now: Date) -> Card? {
        let withKeys = readings.filter { !$0.keys.isEmpty }
        guard !withKeys.isEmpty else { return nil }

        let ranked = withKeys.sorted { a, b in
            switch (soonestDeadline(a, now: now), soonestDeadline(b, now: now)) {
            case let (x?, y?) where x != y: return x < y
            case (nil, _?): return false
            case (_?, nil): return true
            default: break
            }
            if a.keys.count != b.keys.count { return a.keys.count > b.keys.count }
            return a.address < b.address
        }
        guard let lead = ranked.first else { return nil }
        guard lead.keys.count >= minimumKeys else { return nil }

        let usable = lead.keys.filter { $0.isUsable(now: now) }
        let stale = lead.keys.filter { $0.isExpiredButListed(now: now) }
        let roots = lead.keys.filter(\.isRoot)

        let rows = orderedRows(lead.keys, now: now)

        return Card(address: lead.address,
                    usableCount: usable.count,
                    rootCount: roots.count,
                    // The EARLIEST root registration — for an account with one
                    // root, which is every account measured, this is simply
                    // when the account started.
                    rootRegistered: roots.compactMap(\.registeredAt).min(),
                    rows: rows,
                    urgentHours: urgentHours(lead.keys, now: now),
                    staleCount: stale.count,
                    otherWallets: withKeys.count - 1,
                    chains: orderedChains(lead.keys))
    }

    /// How the card orders its credentials — and it is `compose` that owns
    /// this, deliberately.
    ///
    /// **It did not, until §405, and that was a real defect nobody could see.**
    /// `compose` mapped whatever order it was handed, and real accounts came
    /// through `AltanaKeystore.sorted`, which is roots-first then ASCENDING
    /// EXPIRY — so an expired key, holding the earliest date of all, sorted
    /// above everything live. A real card would have led with dead credentials
    /// and buried the one expiring in nine hours. The demo could not show it,
    /// because it seeds `AltanaState` directly and never passes through that
    /// sort: two orderings, and the one nobody had seen was the one everybody
    /// would get.
    ///
    /// The order, and it is TOTAL (a head that reshuffles between opens over
    /// identical data reads as broken — the `ASCRoom` ruling):
    ///
    /// 1. **Roots first.** Permanent authority over the account, and they have
    ///    no deadline to compete on.
    /// 2. **Live sessions before expired ones**, soonest first — the thing
    ///    with a clock on it is the thing to look at.
    /// 3. **Expired last, most recent first.** They need nothing; they are
    ///    there to be tidied, and the freshest is the one still recognisable.
    /// 4. Key id, so a tie can never flip between two draws.
    static func orderedRows(_ keys: [AltanaKeystore.Key], now: Date) -> [KeyRow] {
        let ordered = keys.sorted { a, b in
            if a.isRoot != b.isRoot { return a.isRoot }
            let ax = a.isExpiredButListed(now: now), bx = b.isExpiredButListed(now: now)
            if ax != bx { return !ax }
            switch (a.expiry, b.expiry) {
            case let (x?, y?) where x != y: return ax ? x > y : x < y
            case (nil, _?): return false
            case (_?, nil): return true
            default: break
            }
            return a.id < b.id
        }
        return ordered.map { key in
            let expired = key.isExpiredButListed(now: now)
            var days: Int?
            var hours: Int?
            if !expired, let expiry = key.expiry {
                let left = expiry.timeIntervalSince(now)
                days = max(0, Int(left / 86_400))
                // Only inside the last day — past that, hours are noise.
                if left < 86_400 { hours = max(0, Int(left / 3600)) }
            }
            return KeyRow(id: key.id,
                          isRoot: key.isRoot,
                          kindLabel: key.curve.label,
                          // The DETAIL wording ("24-hour grant") — the sheet
                          // keeps `grantPhrase`'s "24-hour key" as its title,
                          // where the row IS the key (§406).
                          grantPhrase: key.grantDuration.flatMap { grantDetail(seconds: $0) },
                          // A root has no end, so it has no runway (see KeyRow).
                          progress: key.isRoot ? nil : key.progress(now: now),
                          expiry: key.expiry,
                          expired: expired,
                          daysLeft: days,
                          hoursLeft: hours,
                          chainLabel: key.chainLabel,
                          signatureCount: key.signatureCount,
                          registeredAt: key.registeredAt)
        }
    }

    /// Whole hours until the soonest live expiry, when it falls inside the
    /// window worth leading with. nil otherwise — including when the soonest
    /// deadline is days away, which is a fact for a row and not a headline.
    static let urgentWindowHours = 24
    static func urgentHours(_ keys: [AltanaKeystore.Key], now: Date) -> Int? {
        guard let soonest = keys.compactMap(\.expiry).filter({ $0 > now }).min() else { return nil }
        let hours = soonest.timeIntervalSince(now) / 3600
        guard hours < Double(urgentWindowHours) else { return nil }
        return Int(hours)
    }

    /// The soonest expiry still in the future, or nil.
    static func soonestDeadline(_ reading: AltanaKeystore.Reading, now: Date) -> Date? {
        reading.keys.compactMap(\.expiry).filter { $0 > now }.min()
    }

    /// Distinct chain labels in first-appearance order — never a `Set`, whose
    /// order changes between runs and would reshuffle the card's own subtitle.
    static func orderedChains(_ keys: [AltanaKeystore.Key]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for label in keys.compactMap(\.chainLabel) where seen.insert(label).inserted {
            out.append(label)
        }
        return out
    }
}

private extension Double {
    /// Within a second of a whole unit — the test behind `grantPhrase`'s
    /// refusal to print "1.02-day key" for a grant plainly written as a day.
    var roundsCleanly: Bool { abs(self - rounded()) < 0.02 }
}
