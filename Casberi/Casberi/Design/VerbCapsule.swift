import SwiftUI

/// The store's capsule verbs (docs/handoff-apps-page.md) — honest, always:
/// Connect / Pair / Watch / Automatic / Fix / Open / Soon, never "GET". Shared
/// by the Apps chart and the app product page so the same state always wears
/// the same word.
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

    var label: String {
        switch self {
        case .connect: "Connect"
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
        case .connect, .pair, .watch: DS.tint
        case .automatic:      DS.fillFaint
        case .fix:            DS.attention
        case .open:           DS.confirm.opacity(0.15)
        case .soon:           DS.fillFaint
        }
    }

    var foreground: Color {
        switch self {
        case .connect, .pair, .watch, .fix: .white
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
