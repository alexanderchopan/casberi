import Foundation

/// What a WALLET-RIDING seat's product page says before it lights up
/// (prd §515, 2026-08-29).
///
/// Seven seats have no connection of their own: Peer, 0xBow Privacy Pools,
/// Railgun, Safe, Altana, Gnosis Pay and ether.fi. Watching an address is the
/// whole consent (§207), every one of their sweeps runs unconditionally inside
/// `WalletIngest.refresh`, and the seat is pure display gated on evidence
/// (§403) — so there is nothing to connect, and a Connect button was a control
/// that did not do what it said (§83's dead control, the one the honesty rule
/// names first). It landed on the wallet manager, a screen that cannot say why
/// you are on it: tap Aave with seven addresses watched and you got a door to a
/// room, a book and a chains row, and no answer at all.
///
/// **The verb is `Automatic`, and the page answers the question the verb
/// raises.** The app already knows whether it has seen the thing — the same
/// evidence mark `BridgeStore.reconcileWalletSeats()` reads — and had simply
/// never said so anywhere. Saying it turns a mystery into a reading.
///
/// **"Not seen yet" is never "you don't have one".** Evidence is
/// stamp-never-unstamp (`WalletSeatEvidence` rule 1): an empty read is not
/// evidence of absence, since a live-state read returns an empty book for an
/// unreachable host and an event read only sees blocks since its cursor. A
/// page claiming you hold no Safe would be the same fake status from the other
/// side, in the one domain where believing it is expensive.
///
/// Foundation-only by design, so `scripts/…` can compile it whole: every
/// sentence here is a claim about somebody's money, and the failure mode is a
/// page that reads perfectly while saying the wrong thing.
enum WalletSeatStanding {

    /// One seat that rides the watched addresses, and the singular name of the
    /// thing its sweep looks for. The NOUN is the whole design: "No Aerodrome
    /// lock seen yet" says what to go and get, where "nothing found" says only
    /// that something did not happen.
    struct Seat: Sendable {
        let id: String
        /// What one of them is, as it reads mid-sentence. SINGULAR only: the
        /// sentence is always about the first one ("No Safe seen yet"), so a
        /// plural would be a field with no reader — and an English plural is
        /// not a rule this app should own.
        let thing: String
    }

    /// The seven, by catalog seat id. Anything not here is an ordinary bridge
    /// with a connection of its own, and keeps its Connect.
    static let seats: [Seat] = [
        Seat(id: "peer",         thing: "Peer trade"),
        Seat(id: "privacypools", thing: "Privacy Pools deposit"),
        Seat(id: "railgun",      thing: "Railgun shield"),
        Seat(id: "safe",         thing: "Safe"),
        Seat(id: "altana",       thing: "Altana key"),
        Seat(id: "gnosispay",    thing: "Gnosis Pay card"),
        Seat(id: "etherfi",      thing: "ether.fi stake or card"),
    ]

    static func seat(id: String) -> Seat? { seats.first { $0.id == id } }

    /// True for a seat that cannot be connected, only found.
    static func rides(id: String) -> Bool { seat(id: id) != nil }

    /// The verb such a seat wears in the catalog and on its product page.
    ///
    /// Two states, and the split is not cosmetic: with nothing watched there
    /// IS a real action and it belongs in the tinted capsule; with addresses
    /// watched there is none, and a tinted verb would be promising work the
    /// app has already done.
    enum Verb: Sendable, Equatable {
        /// Nothing watched — the one act that makes this seat possible.
        case watch
        /// Watched, nothing seen yet. Neutral: it is a state, not a promise.
        case automatic
    }

    static func verb(watched: Int) -> Verb { watched == 0 ? .watch : .automatic }

    /// The sentence under the verb.
    ///
    /// - `watched`: how many addresses are being watched at all.
    /// - `seen`: how many of them this seat's evidence names (0 while dark).
    ///
    /// Returns nil for a seat that does not ride the wallets — every other
    /// bridge says what it needs on its own connect screen.
    static func line(id: String, watched: Int, seen: Int) -> String? {
        guard let seat = seat(id: id) else { return nil }
        if watched <= 0 {
            return String(localized: "Found automatically. Watch an address that holds \(article(seat.thing)) and it lands here.")
        }
        // Belt to `WalletSeatEvidence.count(in:)`'s braces: a mark can outlive
        // its watch, and "seen at 9 of 7 addresses" is the kind of sentence
        // that makes a person stop believing the rest of the screen.
        let found = min(max(seen, 0), watched)
        if found <= 0 {
            return String(localized: "Watching \(watched) \(addresses(watched)). No \(seat.thing) seen yet — it lands here the day one is.")
        }
        if found == watched {
            return watched == 1
                ? String(localized: "Found at the address you watch.")
                : String(localized: "Found at all \(watched) addresses you watch.")
        }
        return String(localized: "Found at \(found) of \(watched) addresses you watch.")
    }

    /// "a Safe" / "an Altana key" — English, not a claim, but a page that says
    /// "holds a Altana key" reads as machine-written, which is its own kind of
    /// unbelievable.
    static func article(_ noun: String) -> String {
        let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
        guard let first = noun.lowercased().first else { return noun }
        return (vowels.contains(first) ? "an " : "a ") + noun
    }

    private static func addresses(_ n: Int) -> String {
        n == 1 ? String(localized: "address") : String(localized: "addresses")
    }
}
