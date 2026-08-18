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

    /// One session key, as the card draws it.
    struct Session: Equatable, Identifiable {
        let id: String
        /// "24-hour key", "30-day key", or nil when either end is unreadable.
        let grantPhrase: String?
        /// 0…1 through its own grant, or nil when it cannot be computed.
        let progress: Double?
        let expiry: Date?
        /// Its own expiry has passed while the registry still lists it.
        let expired: Bool
        /// Whole days remaining, floored; nil once expired or unknown.
        let daysLeft: Int?
        let chainLabel: String?
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
        let sessions: [Session]
        /// Listed by the registry as active, but past their own expiry.
        let staleCount: Int
        /// Other watched wallets that also hold keys.
        let otherWallets: Int
        /// Distinct registries these keys live on.
        let chains: [String]

        var headline: String {
            let n = usableCount
            if n == 0 {
                return String(localized: "No key can sign for this wallet right now")
            }
            return n == 1
                ? String(localized: "1 key can sign for this wallet")
                : String(localized: "\(n) keys can sign for this wallet")
        }

        /// The hygiene line — nil when there is nothing to tidy.
        var staleNote: String? {
            guard staleCount > 0 else { return nil }
            return staleCount == 1
                ? String(localized: "1 key the registry still lists can no longer act")
                : String(localized: "\(staleCount) keys the registry still lists can no longer act")
        }

        /// Stated only when we really witnessed it — never "registered today"
        /// standing in for "we don't know".
        var rootLine: String? {
            guard rootCount > 0 else { return nil }
            guard let rootRegistered else {
                return rootCount == 1
                    ? String(localized: "1 root key")
                    : String(localized: "\(rootCount) root keys")
            }
            let when = rootRegistered.formatted(date: .abbreviated, time: .omitted)
            return rootCount == 1
                ? String(localized: "1 root key, registered \(when)")
                : String(localized: "\(rootCount) root keys, the first registered \(when)")
        }

        var otherWalletsNote: String? {
            guard otherWallets > 0 else { return nil }
            return otherWallets == 1
                ? String(localized: "1 other watched wallet also has keys")
                : String(localized: "\(otherWallets) other watched wallets also have keys")
        }
    }

    /// "24-hour key" / "30-day key" / "90-minute key".
    ///
    /// Rounded to the unit the grant was plainly written in, because these are
    /// human-chosen durations — the measured BNB corpus is full of grants that
    /// are 24 hours to the second. A phrase like "1.02-day key" would be
    /// arithmetically closer and read as though we had failed to understand
    /// what we were looking at.
    static func grantPhrase(seconds: TimeInterval) -> String? {
        guard seconds > 0 else { return nil }
        let minutes = seconds / 60, hours = seconds / 3600, days = seconds / 86_400
        if days >= 1, days.roundsCleanly {
            let d = Int(days.rounded())
            return d == 1 ? String(localized: "24-hour key") : String(localized: "\(d)-day key")
        }
        if hours >= 1, hours.roundsCleanly {
            let h = Int(hours.rounded())
            return String(localized: "\(h)-hour key")
        }
        if minutes >= 1 {
            let m = Int(minutes.rounded())
            return String(localized: "\(m)-minute key")
        }
        return nil
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

        let sessions = lead.keys.filter { !$0.isRoot }.map { key -> Session in
            let expired = key.isExpiredButListed(now: now)
            var days: Int?
            if !expired, let expiry = key.expiry {
                days = max(0, Int(expiry.timeIntervalSince(now) / 86_400))
            }
            return Session(id: key.id,
                           grantPhrase: key.grantDuration.flatMap { grantPhrase(seconds: $0) },
                           progress: key.progress(now: now),
                           expiry: key.expiry,
                           expired: expired,
                           daysLeft: days,
                           chainLabel: key.chainLabel)
        }

        return Card(address: lead.address,
                    usableCount: usable.count,
                    rootCount: roots.count,
                    // The EARLIEST root registration — for an account with one
                    // root, which is every account measured, this is simply
                    // when the account started.
                    rootRegistered: roots.compactMap(\.registeredAt).min(),
                    sessions: sessions,
                    staleCount: stale.count,
                    otherWallets: withKeys.count - 1,
                    chains: orderedChains(lead.keys))
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
