import SwiftUI

/// Which agent key you're managing — a LIST, not a segmented control
/// (2026-07-31, prd §243).
///
/// Settings → Your key drove a `Picker(.segmented)` over `AgentProvider
/// .allCases` from the day there were four providers. At seven it broke in
/// three separate ways, only one of which was width:
///
/// 1. **Seven text segments don't fit.** "OpenRouter" alone truncates at
///    390pt, and this app scales with Dynamic Type (prd §206) — so it
///    degrades further for anyone who raised their text size, which is
///    exactly the person a truncated control fails hardest.
/// 2. **A segment can't carry STATE.** It cannot say which providers
///    actually hold a key, or which one is currently answering — the two
///    facts a person opens this screen to learn. The old card had to state
///    them in a separate line ABOVE the picker, about whichever segment
///    happened to be selected, which meant the list of seven told you
///    nothing and the line told you about one.
/// 3. **It conflated two jobs.** Selecting a segment picked which key to
///    EDIT; saving one silently made it ACTIVE (`AgentKey.set` writes both).
///    So "I want to update my Venice key" and "I want answers to run on
///    Venice" were the same gesture, and neither was named.
///
/// The list fixes all three by having a row per provider instead of a
/// segment: a row has room for a brand mark, a key hint, and its own verb.
/// Connected providers lead (with the active one checked); the rest sit
/// under a quiet "Add another" label — the same connected/available split
/// the catalog itself uses, and no rule between them (the design law's
/// no-hairlines ban, so the grouping is carried by a label and spacing).
///
/// Two tap targets per row, visually distinct, the shape
/// `WalletWarningsStrip`'s row-plus-Revoke-pill already established: the row
/// BODY selects that provider for editing (the field below follows it), and
/// a trailing "Make active" chip — shown only on a connected row that isn't
/// already active — flips `AgentKey.active` without re-pasting a key that
/// hasn't changed. Same verb, same one-tap contract as
/// `AgentActiveStatusRow` on the individual setup screens.
struct AgentKeyPicker: View {
    @Binding var selection: AgentProvider
    /// Called after a row selects a different provider — the caller clears
    /// its own draft/result state, exactly as the old `.onChange(of:)` did.
    var onSelect: () -> Void = {}
    /// Bumped after "Make active" so this view re-reads `AgentKey.active`,
    /// which is a static, non-observable read.
    @State private var tick = 0

    private var configured: [AgentProvider] { AgentProvider.allCases.filter { AgentKey.isConfigured($0) } }
    private var unconfigured: [AgentProvider] { AgentProvider.allCases.filter { !AgentKey.isConfigured($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ForEach(configured) { row($0) }
            if !unconfigured.isEmpty {
                // A label, never a rule — the design law bans hairlines
                // outright, so the two groups are separated by words and air.
                Text("Add another")
                    .dsText(.label12).fontWeight(.semibold)
                    .foregroundStyle(DS.textTertiary)
                    .padding(.top, configured.isEmpty ? 0 : DS.Space.s2)
                    .padding(.leading, 3)
                ForEach(unconfigured) { row($0) }
            }
        }
    }

    private func row(_ provider: AgentProvider) -> some View {
        let isConfigured = AgentKey.isConfigured(provider)
        let isActive = AgentKey.active == provider
        let isSelected = selection == provider
        return HStack(spacing: DS.Space.s3) {
            // The brand mark every catalog surface already uses — bundled
            // assets, no remote image (the site rule's own ban, applied in
            // app). Dimmed for a provider with no key, so "connected" reads
            // at a glance rather than only in the subline.
            BridgeIcon(name: provider.agent, size: DS.Mark.row)
                .opacity(isConfigured ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 1) {
                Text(provider.agent)
                    .dsText(.callout15).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                // The state a segment could never show: the stored key's own
                // tail, or the honest absence.
                Text(isConfigured ? String(localized: "Saved \(AgentKey.hint(provider))")
                                  : String(localized: "Not connected"))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.Space.s2)
            if isActive {
                // A STATE, not a control — the active provider is already
                // active, so there's nothing to tap (the no-dead-controls
                // rule: a button that performs its own current state is one).
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .dsGlyph(13, weight: .regular)
                    Text("Active").dsText(.label12).fontWeight(.semibold)
                }
                .foregroundStyle(DS.confirm)
            } else if isConfigured {
                Button {
                    DSHaptic.selection()
                    AgentKey.activate(provider)
                    tick += 1
                } label: {
                    Chip(text: "Make active", style: .tint, glyph: "checkmark")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.Space.s3)
        .padding(.vertical, DS.Space.s2)
        // The selected row is the one the field below edits — stated by a
        // fill, since without it "which key am I typing into" is invisible
        // the moment the picker stops being a control with a selected
        // segment.
        .background(isSelected ? DS.fillFaint : .clear,
                    in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            guard selection != provider else { return }
            DSHaptic.selection()
            selection = provider
            onSelect()
        }
        .dsTapCard()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .id(tick)
    }
}
