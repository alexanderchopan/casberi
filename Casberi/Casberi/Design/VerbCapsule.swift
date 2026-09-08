import SwiftUI

/// The store's capsule verbs (docs/handoff-apps-page.md) — honest, always:
/// Allow / Sign in / Add key / Import / Connect / Pair / Watch / Automatic /
/// Fix / Open / Soon, never "GET". Shared by the Apps chart and the app
/// product page so the same state always wears the same word.
///
/// **THE VERB SAYS THE PRICE (prd §653, 2026-09-08).** A dark row used to say
/// "Connect" whether the tap would raise one system sheet or send you to a
/// developer console for a key, and the person found out which on the next
/// screen. The cost word cannot be a second line — the 2026-07-16 ruling
/// killed exactly that badge as wallpaper ("'no account' repeatedly under the
/// names") — so it takes the one slot the row already has: `allow` is a
/// permission sheet, `signIn` a sign-in on their site, `addKey` a key you
/// fetch and paste, `importFile` an export you point at, and `connect` stays
/// for the free ones (a handle, an address, a feed). Which one is
/// `BridgeCatalog.Offer.mode`, the same fact the setup screen's §315 chip
/// draws, held in step by `scripts/catalog-mode-audit.py`.
///
/// `watch` and `automatic` are the wallet-riding seats' pair (prd §515). Those
/// seven have no connection to make — their sweeps run for every watched
/// address whether a seat exists or not — so `connect` was a control that did
/// not do what it said, and it pushed the wallet manager, which cannot say why
/// you are there. `watch` is the one real act (there is no address yet);
/// `automatic` is the state after it, and is deliberately the NEUTRAL capsule:
/// tinting it would promise work rather than report it. Which of the two a
/// seat wears is `WalletSeatStanding.verb(watched:)`, and the sentence that
/// answers the question the word raises is `WalletSeatStanding.line`.
enum CapsuleVerb {
    case connect, pair, watch, automatic, fix, open, soon
    case allow, signIn, addKey, importFile

    var label: String {
        switch self {
        case .connect: "Connect"
        case .allow:   "Allow"
        case .signIn:  "Sign in"
        case .addKey:  "Add key"
        case .importFile: "Import"
        case .pair:    "Pair"
        case .watch:   "Watch"
        case .automatic: "Automatic"
        case .fix:     "Fix"
        case .open:    "Open"
        case .soon:    "Soon"
        }
    }

    var background: Color {
        switch self {
        case .connect, .pair, .watch, .allow, .signIn, .addKey, .importFile: DS.tint
        case .automatic:      DS.fillFaint
        case .fix:            DS.attention
        case .open:           DS.confirm.opacity(0.15)
        case .soon:           DS.fillFaint
        }
    }

    var foreground: Color {
        switch self {
        case .connect, .pair, .watch, .fix, .allow, .signIn, .addKey, .importFile: .white
        // Secondary, not tertiary: `soon` is inert and reads disabled, and
        // this one is a live state you can still tap through.
        case .automatic:            DS.textSecondary
        case .open:                 DS.confirm
        case .soon:                 DS.textTertiary
        }
    }
}

extension CapsuleVerb {
    /// The wallet-riding seats' verb, from the pure model that decides it.
    ///
    /// The mapping lives HERE rather than on `WalletSeatStanding` because that
    /// type is Foundation-only by design — a harness compiles it whole, and it
    /// cannot import SwiftUI to name a capsule. So the model decides WHICH
    /// state a seat is in and this decides what that state wears.
    init(_ standing: WalletSeatStanding.Verb) {
        switch standing {
        case .watch:     self = .watch
        case .automatic: self = .automatic
        }
    }
}

extension CapsuleVerb {
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

/// The capsule itself. `action` nil renders the inert state (Soon).
struct VerbCapsule: View {
    let verb: CapsuleVerb
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) { label }
                .buttonStyle(.plain)
                // Hover rides the ACTIONABLE branch only — Soon is inert, and a
                // cursor lighting it up would be the honesty rule's dead
                // control wearing a pointer affordance.
                .dsHover()
        } else {
            label
        }
    }

    private var label: some View {
        Text(LocalizedStringKey(verb.label))
            .dsText(.label12)
            .foregroundStyle(verb.foreground)
            .padding(.horizontal, DS.Space.s3)
            .frame(minHeight: 32)
            .background(verb.background, in: Capsule(style: .continuous))
    }
}
