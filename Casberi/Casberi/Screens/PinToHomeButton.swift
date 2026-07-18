import SwiftUI

/// The one Home-visibility control, shared by every app's own screen. Under
/// auto-pin (user 2026-07-18) a connected app is ON Home by default — its tile
/// (recent things, in the app's own shape) shows unless the person removes it —
/// so this is a show/hide toggle, not an opt-in pin: "On Home" by default,
/// "Show on Home" once removed. The corpus bump makes Home recompose the moment
/// it flips, even while this screen sits on top of it. Reads `HomePinnedSources`
/// in body so the label tracks the state (the store is @Observable).
///
/// Two forms: the default full-width capsule (a screen's own pin row) and a
/// `.section` variant that supplies its own `Section` for List-based screens.
struct PinToHomeButton: View {
    let source: String
    /// True to wrap the button in its own `Section` (List/Form screens).
    var inSection: Bool = false
    /// One line under the section — what pinning places on Home, in the
    /// source's own words ("The newest drops ride a strip on Home."). Lets
    /// the screens that hand-rolled this section for their footer use the
    /// shared control instead (consolidation 2026-07-16).
    var footer: String? = nil

    private var onHome: Bool { HomePinnedSources.shared.isOnHome(source) }

    var body: some View {
        if inSection {
            Section {
                button.listRowBackground(Color.clear)
            } footer: {
                if let footer {
                    Text(LocalizedStringKey(footer))
                        .dsText(.callout15).foregroundStyle(DS.textTertiary)
                }
            }
        } else {
            button
        }
    }

    private var button: some View {
        Button {
            HomePinnedSources.shared.setOnHome(source, !onHome)
            CorpusSignal.shared.bump()
            DSHaptic.tap()
        } label: {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: onHome ? "pin.fill" : "pin")
                Text(onHome ? "On Home" : "Show on Home")
            }
            .dsText(.body17).foregroundStyle(onHome ? DS.tint : DS.textPrimary)
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(onHome ? DS.tintDim : DS.gray100, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
