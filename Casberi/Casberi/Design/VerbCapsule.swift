import SwiftUI

/// The store's capsule verbs (docs/handoff-apps-page.md) — honest, always:
/// Connect / Pair / Fix / Open / Soon, never "GET". Shared by the Apps chart
/// and the app product page so the same state always wears the same word.
enum CapsuleVerb {
    case connect, pair, fix, open, soon

    var label: String {
        switch self {
        case .connect: "Connect"
        case .pair:    "Pair"
        case .fix:     "Fix"
        case .open:    "Open"
        case .soon:    "Soon"
        }
    }

    var background: Color {
        switch self {
        case .connect, .pair: DS.tint
        case .fix:            DS.attention
        case .open:           DS.confirm.opacity(0.15)
        case .soon:           DS.fillFaint
        }
    }

    var foreground: Color {
        switch self {
        case .connect, .pair, .fix: .white
        case .open:                 DS.confirm
        case .soon:                 DS.textTertiary
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
