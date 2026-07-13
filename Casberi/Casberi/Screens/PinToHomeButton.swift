import SwiftUI

/// The one "Pin to Home" control, shared by every app's own screen (ruling
/// 2026-07-12: pinning is per-APP now, not per-item). Pinning places the app's
/// tile — its recent things, in the app's own shape — on Home; tapping again
/// removes it. The corpus bump makes Home recompose the moment the pin flips,
/// even while this screen sits on top of it. Reads `HomePinnedSources` in body
/// so the label tracks the pinned state (the store is @Observable).
///
/// Two forms: the default full-width capsule (a screen's own pin row) and a
/// `.section` variant that supplies its own `Section` for List-based screens.
struct PinToHomeButton: View {
    let source: String
    /// True to wrap the button in its own `Section` (List/Form screens).
    var inSection: Bool = false

    private var pinned: Bool { HomePinnedSources.shared.isPinned(source) }

    var body: some View {
        if inSection {
            Section {
                button.listRowBackground(Color.clear)
            }
        } else {
            button
        }
    }

    private var button: some View {
        Button {
            HomePinnedSources.shared.toggle(source)
            CorpusSignal.shared.bump()
            DSHaptic.tap()
        } label: {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: pinned ? "pin.fill" : "pin")
                Text(pinned ? "Pinned to Home" : "Pin to Home")
            }
            .dsText(.body17).foregroundStyle(pinned ? DS.tint : DS.textPrimary)
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(pinned ? DS.tintDim : DS.gray100, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
