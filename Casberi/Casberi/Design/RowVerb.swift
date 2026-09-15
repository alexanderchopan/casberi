import SwiftUI

/// **THE CATALOGUE'S VERBS, AS THE LAST WORD OF A ROW (prd §746, 2026-09-15).**
///
/// These were `CapsuleVerb`, drawn by `VerbCapsule` as a filled pill at the
/// trailing end of a row whose whole width already ran the same action (§641:
/// "one destination per catalogue row"). Two controls for one act, and the
/// louder one was the pill — which, repeated down 97 rows, is the screen the
/// user called generated. The word stays and the capsule goes: the verb is
/// the row's trailing fact, in its own ink, before the chevron
/// (`DSPushRowTrail(verb:)`).
///
/// Honest, always: Allow / Sign in / Add key / Import / Connect / Watch /
/// Automatic / Fix / Open / Soon, never "GET". Drawn in one place per screen,
/// so the same state always wears the same word.
///
/// **THE VERB SAYS THE PRICE (prd §653, 2026-09-08).** `allow` is a permission
/// sheet, `signIn` a sign-in on their site, `addKey` a key you fetch and
/// paste, `importFile` an export you point at, and `connect` stays for the
/// free ones (a handle, an address, a feed). Which one is
/// `BridgeCatalog.Offer.mode`, held in step by `scripts/catalog-mode-audit.py`.
///
/// `watch` and `automatic` are the wallet-riding seats' pair (prd §515):
/// `watch` is the one real act (there is no address yet); `automatic` is the
/// state after it, and is deliberately NEUTRAL ink — tinting it would promise
/// work rather than report it. `pair` is gone (prd §653 review).
///
/// The ink carries what the pill's fill used to: tint for an act that costs
/// something, attention for a broken seat, confirm for one that is healthy,
/// secondary for automatic, tertiary for Soon — which is the one verb that
/// opens nothing, so it is the one row with no chevron (§83).
enum RowVerb {
    case connect, watch, automatic, fix, open, soon
    case allow, signIn, addKey, importFile

    var label: String {
        switch self {
        case .connect: "Connect"
        case .allow:   "Allow"
        case .signIn:  "Sign in"
        case .addKey:  "Add key"
        case .importFile: "Import"
        case .watch:   "Watch"
        case .automatic: "Automatic"
        case .fix:     "Fix"
        case .open:    "Open"
        case .soon:    "Soon"
        }
    }

    var ink: Color {
        switch self {
        case .connect, .watch, .allow, .signIn, .addKey, .importFile: DS.tint
        case .automatic: DS.textSecondary
        case .fix:       DS.attention
        case .open:      DS.confirm
        case .soon:      DS.textTertiary
        }
    }

    /// Whether the row goes somewhere. Soon is inert, and a chevron on an
    /// inert row is a promise with nothing behind it.
    var opens: Bool { self != .soon }
}

extension RowVerb {
    /// The wallet-riding seats' verb, from the pure model that decides it.
    ///
    /// The mapping lives HERE rather than on `WalletSeatStanding` because that
    /// type is Foundation-only by design — a harness compiles it whole, and it
    /// cannot import SwiftUI to name an ink. So the model decides WHICH state
    /// a seat is in and this decides what that state wears.
    init(_ standing: WalletSeatStanding.Verb) {
        switch standing {
        case .watch:     self = .watch
        case .automatic: self = .automatic
        }
    }

    /// A dark setup seat's verb, from how it connects (prd §653). `nil` is
    /// the one-tap grant, which is `allow` — the tap raises the system sheet.
    init(mode: BridgeSetupMode?) {
        switch mode {
        case nil:              self = .allow
        case .signIn:          self = .signIn
        case .pasteKey:        self = .addKey
        case .oneTimeImport:   self = .importFile
        // On-device seats WITH a screen (Files, Obsidian, Apple Wallet) push
        // it — a folder pick or a consent page, not one grant — so Connect.
        case .onThisDevice:    self = .connect
        case .noAccount:       self = .connect
        // Never reached from the catalogue — a riding seat wears
        // `WalletSeatStanding.verb` (§515) before this is asked.
        case .watchedWallets:  self = .watch
        }
    }
}
