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
/// ## The card is a LIST (prd §488, 2026-08-26)
///
/// It was a CONSTELLATION until then — accounts down the left, a token per
/// credential, a drawn line for every account a key can sign for — plus a
/// dot rail underneath for the deadlines. Reported as messy, and it was, for
/// reasons that measured rather than argued: the layout was absolutely
/// positioned from a width this file computed (`88 + 62·N`), so a fifth key
/// overflowed a 321pt card with no scroll to catch it; a token carried six
/// visual variables (fill, border colour, border dash, opacity, glyph, plus
/// its ties' colour and dash) inside a 44pt circle; and the rail carried
/// `VibenetKeyShelf`'s own defect, unfixed (see `shelfWindow`).
///
/// One row per credential now, in one grammar: a seat that says root-or-
/// session, the key's name and grant, a bar whose length is time left on a
/// FIXED window, and one countdown. The rare fact the ties existed for — one
/// credential signing for two accounts — is the faces on that credential's
/// own row, which is where somebody looking at the key would look for it.
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
        /// the card draws ONE ROW for it — wearing the faces of both accounts
        /// (§488; it was one token with two ties until then) — and why the
        /// census counts credentials rather than registrations.
        var accountAddresses: [String] = []

        /// Signs for more than one watched account.
        var isShared: Bool { accountAddresses.count > 1 }

        /// REVOKED, and remembered (§410). The registry drops a revoked key
        /// from `getKeys` entirely, so the only way it appears at all is that
        /// we saw it before it went — which is why a ghost is forward-only and
        /// can never be backfilled on first sight.
        ///
        /// It is listed because a card with no memory answers "who can sign
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

        // MARK: - The shelf reading (prd §488)

        /// How much of this credential's life is left, as a fraction of ONE
        /// FIXED WINDOW shared by every row — or nil where a bar would be a
        /// claim rather than a reading.
        ///
        /// **nil is the common and correct answer for three of the four
        /// states**, and each is its own reason: a ROOT has no end, so a full
        /// bar would state a completion that does not exist (`progress`'s own
        /// rule, §405); an EXPIRED key has no time left to draw; a REVOKED one
        /// is not on the shelf at all. A bar here means exactly one thing —
        /// time remaining, on a scale every other bar shares — and absence
        /// means "no clock", which is the true reading in all three.
        ///
        /// Clamped at the top rather than dropped: a key lapsing beyond the
        /// window draws FULL and its countdown says the real figure, so the
        /// bar reads "at least a quarter" and the number stays exact. That
        /// differs from `VibenetKeyShelf`, which excludes those rows and
        /// counts them in a tail — because that shelf is a THREE-ROW FOOTER
        /// ranked by urgency, where a full-length bar would outrank the keys
        /// it was drawn beside, and this is the room's whole key list, where
        /// the row exists whatever its date.
        ///
        /// COMPUTED FROM `expiry` AT DRAW TIME, never from `daysLeft` — the
        /// head is memoized (`FeedScreen.headMemo`), so a card left open past
        /// midnight would otherwise count down to a number captured when the
        /// room composed.
        func shelfFraction(now: Date) -> Double? {
            guard !isRoot, !isGone, !expired, let expiry else { return nil }
            let remaining = expiry.timeIntervalSince(now)
            guard remaining > 0 else { return nil }
            return min(1, max(AltanaRoom.minimumFraction, remaining / AltanaRoom.shelfWindow))
        }

        /// The row's trailing word — the one clock this card keeps.
        ///
        /// Compact by design ("9h", "12d"), because it sits in a narrow
        /// right-hand column against a bar that already says roughly how long:
        /// the ROOM says how much is left, the key's own sheet says the dates.
        /// Days round UP, never down (`VibenetKeyShelfRow.countdown`'s rule) —
        /// a key with 30 hours left reading "1d" understates it on the one
        /// line whose job is to say how much time there is.
        func countdown(now: Date) -> String {
            if isGone { return String(localized: "revoked") }
            if expired { return String(localized: "expired") }
            guard let expiry else {
                // A root, or a session whose expiry could not be read. Both
                // are honestly "no end we can see"; only the root is common.
                return isRoot ? String(localized: "no expiry") : "—"
            }
            let remaining = expiry.timeIntervalSince(now)
            guard remaining > 0 else { return String(localized: "expired") }
            if remaining < 3600 { return String(localized: "<1h") }
            if remaining < 86_400 {
                return String(localized: "\(Int(remaining / 3600))h")
            }
            return String(localized: "\(Int((remaining / 86_400).rounded(.up)))d")
        }

        /// Inside the window worth acting on today — the ONE row that earns
        /// the room's mark. Same threshold the headline's alarm uses
        /// (`urgentWindowHours`), read from it rather than restated, so a row
        /// drawn blue is a row the headline is talking about.
        func isUrgent(now: Date) -> Bool {
            guard !isGone, !expired, let expiry else { return false }
            let hours = expiry.timeIntervalSince(now) / 3600
            return hours > 0 && hours < Double(AltanaRoom.urgentWindowHours)
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

    // MARK: - The shelf (prd §488)

    /// The window every bar on this card is drawn against — a quarter, FIXED.
    ///
    /// **It replaces an elastic axis that had `VibenetKeyShelf`'s defect, in
    /// the room next door, unfixed.** §408a drew the deadlines as dots on a
    /// rail spanning `now … furthest live deadline`: `now` is the minimum by
    /// construction (every expiry is in the future), so the now-marker was
    /// pinned at zero on every render this feature ever drew — a constant, on
    /// the element that gave the rail its meaning — and the axis stretched to
    /// whatever the furthest key was, so a 30-day key crushed a 9-hour key to
    /// position 0.01, indistinguishable from the marker.
    ///
    /// A fixed window is what makes two bars comparable: at a glance, and
    /// across two accounts, and between this card and the same card yesterday.
    /// 90 days is the horizon over which a lapsing key is still something you
    /// can act on (`VibenetKeyShelf.window`, same value on purpose — two
    /// keystore rooms drawing one figure on two scales would read as a bug,
    /// and `altana-selftest.sh` guards the pair).
    static let shelfWindow: TimeInterval = 90 * 86_400
    /// The smallest bar that still reads as a bar rather than as a hole — a
    /// key lapsing within the hour is 0.0005 of a quarter and would draw as
    /// nothing at all on the one row that matters most. The number beside it
    /// is exact; the bar is the picture.
    static let minimumFraction = 0.02

    /// How many credentials the card lists before the tail takes over.
    ///
    /// The measured BNB corpus runs to a handful of keys per account, so this
    /// bites rarely — but a card that silently stops at six looks exactly like
    /// an account that has six (the truncation class this repo has now paid
    /// for in four import rooms), so the remainder is COUNTED and said.
    static let rowCap = 6

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
    /// identicon, so the aggregate the footnote gestured at is the card.
    struct Card: Equatable {
        /// Ordered: the account with the soonest live deadline first — the
        /// same urgency ranking that used to pick the lead now merely picks
        /// who is drawn on top.
        let accounts: [AccountGroup]
        /// EVERY credential exactly once, deduped by key id (§408a) — the
        /// card's rows, and the honest unit for the census.
        let credentials: [KeyRow]
        /// Distinct credentials that can sign right now. NOT a count of
        /// registrations: a key signing for two accounts is one credential,
        /// and the card draws one row, so the sentence says one.
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

        /// The credentials this card LISTS, soonest-first order already
        /// applied by `compose` — capped, so the card cannot grow without
        /// bound on an account somebody has been generous with.
        var drawn: [KeyRow] { Array(credentials.prefix(rowCap)) }

        /// What the cap left off, said rather than silently dropped.
        var moreLine: String? {
            let hidden = credentials.count - drawn.count
            guard hidden > 0 else { return nil }
            return hidden == 1
                ? String(localized: "1 more key")
                : String(localized: "\(hidden) more keys")
        }

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
        /// only what may sign. Since §488 the shared credential's row wears
        /// the FACES of both accounts, so this sentence is the accessible
        /// reading of that rather than the only place the fact appears.
        var sharedNote: String? {
            guard !sharedKeyIDs.isEmpty else { return nil }
            let accountsSigned = credentials.filter(\.isShared)
                .map(\.accountAddresses.count).max() ?? 2
            return sharedKeyIDs.count == 1
                ? String(localized: "One key can sign for \(accountsSigned) of your accounts")
                : String(localized: "\(sharedKeyIDs.count) keys can sign for more than one of your accounts")
        }

        /// What was revoked, remembered (§410) — the sentence beside the
        /// ghosts, so the list has an accessible reading.
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

        /// THE CARD'S ONE LINE, ranked (prd §488).
        ///
        /// Both sentences below became SUMMARIES OF VISIBLE ROWS the moment
        /// the constellation became a list: a revoked credential is a row
        /// reading "revoked" and a stale one is a row reading "expired", so
        /// stacking two grey sentences under them says the same facts a second
        /// time in a weaker voice. What the sentences still carry is the part
        /// the rows cannot — the QUALIFIER ("while you were watching", which
        /// is the forward-only honesty §410 turns on) and the INSTRUCTION (the
        /// registry still lists a key that cannot act, so go and tidy it).
        ///
        /// One at a time, revocation first: a key somebody took away outranks
        /// a key that merely lapsed, and the hygiene line comes back on its
        /// own once the ghost ages out of `AltanaState.ghostLifetime`.
        var note: String? { revokedNote ?? staleNote }

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
    /// - Parameter scope: one watched account, RESOLVED TO ITS STORED HEX by
    ///   the caller (`AltanaRoom.card(scope:)`) — the face rail's pick. nil is
    ///   "All", which is every watched account at once.
    static func compose(readings: [AltanaKeystore.Reading],
                        ghosts: [Ghost] = [], now: Date,
                        scope: String? = nil) -> Card? {
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

        var groups = ranked.map { reading in
            AccountGroup(address: reading.address,
                         rows: orderedRows(reading.keys, now: now))
        }

        // ONE ROW per credential (§408a, §488). A key id derives from its
        // public key, so the same id under two accounts is one credential with
        // two registrations — drawn once, wearing the face of each account it
        // can sign for, and counted once.
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
        // revoked credentials the card remembers, so it answers "who used
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

        // NARROWED TO THE FACE RAIL'S PICK (prd §488), and narrowed HERE
        // rather than by filtering the readings on the way in, for one
        // reason: `accountAddresses` is built above by walking every account,
        // so a credential that also signs for a wallet now out of scope keeps
        // saying so. Filtering first would make the single most valuable fact
        // on a scoped card — this key can sign for something else too —
        // structurally unsayable, which is the reading §408a built the whole
        // tie for.
        var scopedKeys = allKeys
        if let scope {
            // A scope that matches NOTHING declines — it must never fall
            // through to the aggregate, which would draw every watched
            // account under one ringed face. Caught by this harness's own
            // fixture on its first run, where the obvious `if let scope, let
            // match = …` did exactly that.
            guard let match = ranked.first(where: { sameAddress($0.address, scope) }) else {
                return nil
            }
            groups = groups.filter { sameAddress($0.address, scope) }
            credentials = credentials.filter { row in
                row.accountAddresses.contains { sameAddress($0, scope) }
            }
            shared = shared.intersection(credentials.map { $0.id.lowercased() })
            scopedKeys = match.keys
            // A scope naming a wallet with no keys leaves nothing to head the
            // room with — and that is a real state (you watch five wallets and
            // picked the one Altana has never seen), so it declines rather
            // than silently falling back to the aggregate, which would answer
            // a question nobody asked.
            guard !credentials.isEmpty else { return nil }
        }

        return Card(accounts: groups,
                    credentials: credentials,
                    // DEDUPED: the card draws one row for a shared key, so
                    // the sentence counts one.
                    usableCount: credentials.filter { !$0.expired && !$0.isGone }.count,
                    rootCount: credentials.filter(\.isRoot).count,
                    // Read off the SCOPED key set, so a scoped card's alarm,
                    // census and hygiene line all describe the account whose
                    // face is ringed above them — not the room they came from.
                    urgentHours: urgentHours(scopedKeys, now: now),
                    staleCount: scopedKeys.filter { $0.isExpiredButListed(now: now) }.count,
                    chains: orderedChains(scopedKeys),
                    sharedKeyIDs: shared)
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

    // MARK: - Address identity

    /// Case-insensitive, because every account a keystore names is EVM hex and
    /// EIP-55 case is a CHECKSUM rather than identity — the same rule
    /// `WalletWatch.sameAddress` keeps for hex, spelled locally because this
    /// file is Foundation-only so a `swiftc` harness can compile it whole.
    ///
    /// Deliberately NOT the base58 arm of that function: a Solana address is
    /// case-SENSITIVE and folding case there merges distinct wallets — and no
    /// Solana address can reach this file, since the registry is EVM.
    static func sameAddress(_ a: String, _ b: String) -> Bool {
        a.caseInsensitiveCompare(b) == .orderedSame
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
