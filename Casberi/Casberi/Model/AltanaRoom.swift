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
        /// EVERY watched account this credential can sign for (§408a).
        ///
        /// A key id derives from its public key, so the same id under two
        /// accounts is ONE credential with two registrations — which is why
        /// the card draws one token with two ties rather than two tokens, and
        /// why the census counts credentials rather than registrations.
        var accountAddresses: [String] = []

        /// Signs for more than one watched account.
        var isShared: Bool { accountAddresses.count > 1 }

        /// REVOKED, and remembered (§410). The registry drops a revoked key
        /// from `getKeys` entirely, so the only way it appears at all is that
        /// we saw it before it went — which is why a ghost is forward-only and
        /// can never be backfilled on first sight.
        ///
        /// It is drawn because a picture with no memory answers "who can sign
        /// as me" and silently refuses "who used to" — and the second question
        /// is the one somebody asks after a scare.
        var isGone: Bool = false

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

    /// A credential we watched disappear (§410).
    ///
    /// Carries only what survives the key itself: the registry drops a revoked
    /// key from `getKeys`, so nothing can be re-read about it afterwards and
    /// every field here is what was noted while it still existed.
    struct Ghost: Equatable {
        let address: String
        let keyID: String
        let isRoot: Bool
        let kindLabel: String?
        let chainLabel: String?
        /// When we NOTICED it gone — not when it was revoked, which the
        /// registry does not tell us. The copy says "noticed" for that reason:
        /// those are two different claims and only one of them is ours.
        let noticedAt: Date
    }

    /// One deadline on the "next" rail (§408a).
    ///
    /// POSITION ONLY — never a length. A span drawn as a bar invites the
    /// reading that a long grant is somehow more than a short one, which is
    /// the user's own objection to the timeline draft: seeing a long line for
    /// a wallet key beside a shorter one for a passkey tells you nothing you
    /// can act on. A dot says the one thing that IS actionable — when,
    /// relative to now and to the others.
    struct RailDot: Equatable, Identifiable {
        /// The key id of the first credential in the group.
        let id: String
        /// True fraction from now to the furthest live deadline, 0…1.
        let position: Double
        /// "9h · Passkey", or "2 keys" once a group merged.
        let label: String
        /// How many deadlines this dot stands for.
        let count: Int
    }

    /// Dots closer together than this merge into one, because two overlapping
    /// dots are one unreadable dot. The merge keeps the TRUE position of the
    /// earliest in the group and says how many — it never nudges a dot to a
    /// time that is not its own.
    static let railMergeGap = 0.05

    /// One account's keys, behind its face (§407a).
    struct AccountGroup: Equatable, Identifiable {
        /// Lowercased hex — feeds `WalletFace` and the row-matching tap.
        let address: String
        let rows: [KeyRow]
        var id: String { address }
    }

    /// The head — EVERY watched account with keys, not a ranked lead (§407a).
    ///
    /// Until this, `compose` ranked accounts and drew ONE, relegating the rest
    /// to "1 other watched wallet also has keys" — a footnote about the thing
    /// the card exists to show. The keyring draws them all, each behind its
    /// identicon, so the aggregate the footnote gestured at is the picture.
    struct Card: Equatable {
        /// Ordered: the account with the soonest live deadline first — the
        /// same urgency ranking that used to pick the lead now merely picks
        /// who is drawn on top.
        let accounts: [AccountGroup]
        /// EVERY credential exactly once, deduped by key id (§408a) — the
        /// constellation's tokens, and the honest unit for the census.
        let credentials: [KeyRow]
        /// Distinct credentials that can sign right now. NOT a count of
        /// registrations: a key signing for two accounts is one credential,
        /// and the picture shows one token, so the sentence says one.
        let usableCount: Int
        let rootCount: Int
        /// Hours until the soonest LIVE expiry anywhere, when that is close
        /// enough to be the reason to look today (`urgentWindowHours`).
        let urgentHours: Int?
        /// Listed by the registry as active, but past their own expiry.
        let staleCount: Int
        /// Distinct registries these keys live on.
        let chains: [String]
        /// Key ids registered under MORE THAN ONE watched account — the same
        /// credential by construction (an id derives from its public key), so
        /// this is the single-point-of-failure fact with no inference in it.
        let sharedKeyIDs: Set<String>
        /// The deadlines ahead, as positions on one shared rail (§408a).
        let rail: [RailDot]

        /// The first account's address — kept for the headline's tap target
        /// (the explorer door opens on the most urgent account).
        var address: String { accounts.first?.address ?? "" }

        /// Every registration in drawn order — the probe's per-account view.
        var rows: [KeyRow] { accounts.flatMap(\.rows) }
        /// Sessions only — the harness still asks the question this way.
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
            if accounts.count > 1 {
                return String(localized: "\(n) keys can sign for \(accounts.count) accounts")
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
            if accounts.count > 1 {
                return String(localized: "\(n) keys can sign for \(accounts.count) accounts")
            }
            return n == 1
                ? String(localized: "1 key can sign for this account")
                : String(localized: "\(n) keys can sign for this account")
        }

        /// The shared-credential fact.
        ///
        /// **A key SIGNS FOR an account; it never "holds" one** (user ruling,
        /// §408a). Holding implies custody of the account itself, which is the
        /// §83 overclaim this whole seat is careful about — the registry says
        /// only what may sign. Since §408a the tie is DRAWN, so this sentence
        /// exists as the accessible reading of the picture rather than as the
        /// only place the fact appears.
        var sharedNote: String? {
            guard !sharedKeyIDs.isEmpty else { return nil }
            let accountsSigned = credentials.filter(\.isShared)
                .map(\.accountAddresses.count).max() ?? 2
            return sharedKeyIDs.count == 1
                ? String(localized: "One key can sign for \(accountsSigned) of your accounts")
                : String(localized: "\(sharedKeyIDs.count) keys can sign for more than one of your accounts")
        }

        /// What was revoked, remembered (§410) — the sentence beside the
        /// ghosts, so the picture has an accessible reading.
        ///
        /// "NOTICED", never "revoked on": the registry drops a revoked key
        /// without telling us when it went, so the only honest date is the
        /// pass that found it missing. Forward-only by construction, and the
        /// copy carries that rather than implying a complete history.
        var revokedNote: String? {
            let gone = credentials.filter(\.isGone).count
            guard gone > 0 else { return nil }
            return gone == 1
                ? String(localized: "1 key was revoked while you were watching")
                : String(localized: "\(gone) keys were revoked while you were watching")
        }

        /// The hygiene line — nil when there is nothing to tidy.
        var staleNote: String? {
            guard staleCount > 0 else { return nil }
            return staleCount == 1
                ? String(localized: "1 key the registry still lists can no longer act")
                : String(localized: "\(staleCount) keys the registry still lists can no longer act")
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
    static func compose(readings: [AltanaKeystore.Reading],
                        ghosts: [Ghost] = [], now: Date) -> Card? {
        let withKeys = readings.filter { !$0.keys.isEmpty }
        guard !withKeys.isEmpty else { return nil }

        // The urgency ranking that used to pick a single lead now merely
        // decides who draws on top (§407a) — soonest live deadline first, then
        // more keys, then address so a tie can never flip.
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

        let allKeys = ranked.flatMap(\.keys)
        // The floor is the TOTAL now: a single root key across every account
        // is the registry merely existing, which the rows already say.
        guard allKeys.count >= minimumKeys else { return nil }

        // The same credential under two accounts — same id by construction.
        var seenIDs = Set<String>(), shared = Set<String>()
        for reading in ranked {
            for id in Set(reading.keys.map { $0.id.lowercased() }) {
                if !seenIDs.insert(id).inserted { shared.insert(id) }
            }
        }

        let groups = ranked.map { reading in
            AccountGroup(address: reading.address,
                         rows: orderedRows(reading.keys, now: now))
        }

        // ONE token per credential (§408a). A key id derives from its public
        // key, so the same id under two accounts is one credential with two
        // registrations — drawn once, with a tie to each account it can sign
        // for, and counted once.
        var byID: [String: KeyRow] = [:]
        var order: [String] = []
        for group in groups {
            for row in group.rows {
                let key = row.id.lowercased()
                if var existing = byID[key] {
                    existing.accountAddresses.append(group.address)
                    byID[key] = existing
                } else {
                    var fresh = row
                    fresh.accountAddresses = [group.address]
                    byID[key] = fresh
                    order.append(key)
                }
            }
        }
        var credentials = order.compactMap { byID[$0] }

        // The ghosts (§410), appended once each and therefore always last:
        // revoked credentials the picture remembers, so it answers "who used
        // to" as well as "who can". An id that came BACK is skipped — a key
        // re-registered under the same id is alive again, and drawing both
        // would be wrong in two directions at once.
        let alive = Set(credentials.map { $0.id.lowercased() })
        var ghostSeen = Set<String>()
        for ghost in ghosts where !alive.contains(ghost.keyID.lowercased())
                                  && ghostSeen.insert(ghost.keyID.lowercased()).inserted {
            credentials.append(KeyRow(
                id: ghost.keyID, isRoot: ghost.isRoot, kindLabel: ghost.kindLabel,
                grantPhrase: nil, progress: nil, expiry: nil, expired: false,
                daysLeft: nil, hoursLeft: nil, chainLabel: ghost.chainLabel,
                signatureCount: 0, registeredAt: nil,
                accountAddresses: [ghost.address], isGone: true))
        }

        return Card(accounts: groups,
                    credentials: credentials,
                    // DEDUPED: the picture shows one token for a shared key,
                    // so the sentence counts one.
                    usableCount: credentials.filter { !$0.expired && !$0.isGone }.count,
                    rootCount: credentials.filter(\.isRoot).count,
                    urgentHours: urgentHours(allKeys, now: now),
                    staleCount: allKeys.filter { $0.isExpiredButListed(now: now) }.count,
                    chains: orderedChains(allKeys),
                    sharedKeyIDs: shared,
                    rail: rail(credentials, now: now))
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

    // MARK: - The constellation's geometry (§408a)

    /// Where every node sits, in points, and what ties to what.
    ///
    /// PURE, and here rather than in the view for one reason: this is the only
    /// place that can guarantee ONE TOKEN PER CREDENTIAL. The first cut drew
    /// each account's credentials in its own row, which put a shared key on
    /// screen twice — so the picture showed six tokens while the sentence
    /// counted four, which is the very disagreement §408a exists to end. A
    /// shared credential has one position and several ties, and that is only
    /// expressible as a layout.
    struct Placement: Equatable {
        struct Node: Equatable, Identifiable {
            let id: String
            let x: Double
            let y: Double
        }
        struct Tie: Equatable, Identifiable {
            let account: String
            let credential: String
            /// This credential can sign for more than one account, so the tie
            /// is drawn in the card's own hue rather than as quiet chrome.
            let shared: Bool
            /// The credential was revoked (§410) — the tie is drawn CUT, which
            /// is the whole reading: it reached this account and no longer
            /// does. A ghost with an intact tie would say the opposite.
            var severed: Bool = false
            var id: String { account + "→" + credential }
        }
        let accounts: [Node]
        let credentials: [Node]
        let ties: [Tie]
        let width: Double
        let height: Double
    }

    static let tokenSize: Double = 44
    static let faceSize: Double = 30
    static let nodeGap: Double = 18
    /// Tall enough that a token, its two label lines AND a clear channel
    /// between rows all fit — the channel is what a shared credential's ties
    /// route through, instead of cutting diagonally across the labels of the
    /// row above (measured on the sim: at 96 the tie crossed "Session key /
    /// expired" and made both unreadable).
    static let rowGap: Double = 124

    /// Lays the constellation out.
    ///
    /// Accounts run down the left. Each account's EXCLUSIVE credentials sit in
    /// a row beside it. A SHARED credential is placed once, in a column to the
    /// right of everything, at the mean height of the accounts it serves — so
    /// its ties fan visibly to both, which is the whole reading.
    ///
    /// Deterministic: positions derive from the card's own ordering, so the
    /// picture cannot reshuffle between two draws of identical data.
    static func placement(_ card: Card) -> Placement {
        let faceX = faceSize / 2
        let firstTokenX = faceX + faceSize / 2 + nodeGap + tokenSize / 2 + nodeGap
        let step = tokenSize + nodeGap

        var accountNodes: [Placement.Node] = []
        var credentialNodes: [Placement.Node] = []
        var ties: [Placement.Tie] = []
        var maxX = firstTokenX

        for (index, account) in card.accounts.enumerated() {
            let y = tokenSize / 2 + Double(index) * rowGap
            accountNodes.append(.init(id: account.address, x: faceX, y: y))

            let exclusive = card.credentials.filter {
                $0.accountAddresses == [account.address]
            }
            for (column, credential) in exclusive.enumerated() {
                let x = firstTokenX + Double(column) * step
                credentialNodes.append(.init(id: credential.id, x: x, y: y))
                ties.append(.init(account: account.address, credential: credential.id,
                                  shared: false, severed: credential.isGone))
                maxX = max(maxX, x)
            }
        }

        // The shared ones, once each, to the right of every exclusive token.
        let shared = card.credentials.filter(\.isShared)
        for (column, credential) in shared.enumerated() {
            let ys = credential.accountAddresses.compactMap { address in
                accountNodes.first { $0.id == address }?.y
            }
            guard !ys.isEmpty else { continue }
            let x = maxX + step + Double(column) * step
            let y = ys.reduce(0, +) / Double(ys.count)
            credentialNodes.append(.init(id: credential.id, x: x, y: y))
            for address in credential.accountAddresses {
                ties.append(.init(account: address, credential: credential.id, shared: true))
            }
        }

        let width = (credentialNodes.map(\.x).max() ?? firstTokenX) + tokenSize / 2
        let height = (accountNodes.map(\.y).max() ?? tokenSize / 2) + tokenSize / 2 + 22
        return Placement(accounts: accountNodes, credentials: credentialNodes,
                         ties: ties, width: width, height: height)
    }

    /// The deadlines ahead as positions on ONE rail (§408a).
    ///
    /// The span is now → the furthest LIVE deadline, so the last dot always
    /// sits at the end and the rail is never mostly empty. Positions are true
    /// fractions of that span; dots closer than `railMergeGap` merge, keeping
    /// the earliest one's real position and saying how many. Nothing is ever
    /// nudged to a time it does not have.
    ///
    /// Empty when nothing is expiring — a rail with no dots is a rail with
    /// nothing to say, and the card omits it rather than drawing an empty axis.
    static func rail(_ credentials: [KeyRow], now: Date) -> [RailDot] {
        let live = credentials
            .filter { !$0.expired && !$0.isGone }
            .compactMap { row -> (KeyRow, Date)? in row.expiry.map { (row, $0) } }
            .filter { $0.1 > now }
            .sorted { $0.1 < $1.1 }
        guard let furthest = live.last?.1 else { return [] }
        let span = furthest.timeIntervalSince(now)
        guard span > 0 else { return [] }

        var dots: [RailDot] = []
        for (row, expiry) in live {
            let position = min(1, max(0, expiry.timeIntervalSince(now) / span))
            if var last = dots.last, position - last.position < railMergeGap {
                last = RailDot(id: last.id, position: last.position,
                               label: String(localized: "\(last.count + 1) keys"),
                               count: last.count + 1)
                dots[dots.count - 1] = last
                continue
            }
            dots.append(RailDot(id: row.id, position: position,
                                label: dotLabel(row, now: now), count: 1))
        }
        return dots
    }

    /// "9h · Passkey" near, "25d · Passkey" further out — the same relative
    /// clock the tokens use, so the rail and the rest of the card never
    /// disagree about the same deadline.
    static func dotLabel(_ row: KeyRow, now: Date) -> String {
        let title = row.title
        if let hours = row.hoursLeft {
            return hours <= 0 ? String(localized: "<1h · \(title)")
                              : String(localized: "\(hours)h · \(title)")
        }
        if let days = row.daysLeft { return String(localized: "\(days)d · \(title)") }
        return title
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
