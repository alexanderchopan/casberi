import SwiftUI

/// **WHOSE VIEW THIS IS, PICKED FROM A MENU** (prd §936 item 5, extended by
/// §959) — the showing slot's faces, its name and `chevron.up.chevron.down`,
/// every slot in a pull-down with a check on the current one.
///
/// The Wallet family's account line, lifted out of `DSRoomScopeChrome` so a
/// room that picks a SOURCE — a watched repo or person on GitHub, a board or
/// person on Pinterest — draws the same control in the same place: under the
/// tiles, or under the cover where a room has none. The social rooms keep a
/// row of faces instead (§959): there the face and its ring ARE the news, and
/// a menu would hide both behind a tap.
///
/// `slots` includes "All" as the slot whose `id` is `""`; the caller decides
/// whether the control draws at all.
struct DSScopeMenu: View {
    let slots: [DSAccountSlot]
    /// The slot showing — the caller resolves it, because the wallet family
    /// and the source rooms speak different scopes.
    let showing: DSAccountSlot
    /// What VoiceOver says: "Account: …" in the wallet family, "Showing: …"
    /// where the pick is a source rather than one of yours.
    var spoken: (String) -> String = { String(localized: "Account: \($0)") }
    /// Draw each slot's `sub` as its subtitle in the menu. On GitHub and
    /// Pinterest it says repo or person, board or person — the one fact the
    /// rail's square-or-circle carried and a menu of names would otherwise
    /// drop. Off in the wallet family, whose `sub` is a tooltip.
    var subtitles: Bool = false
    let onPick: (String?) -> Void

    var body: some View {
        Menu {
            ForEach(slots) { slot in
                Button {
                    DSHaptic.selection()
                    withAnimation(DS.Motion.standard) {
                        onPick(slot.id.isEmpty ? nil : slot.id)
                    }
                } label: {
                    if slot.id == showing.id {
                        Label(slot.name, systemImage: "checkmark")
                    } else {
                        Text(slot.name)
                    }
                    if subtitles, let sub = slot.sub {
                        Text(sub)
                    }
                }
            }
        } label: {
            HStack(spacing: DS.Space.s2) {
                HStack(spacing: -(DS.Face.row / 3.5)) {
                    ForEach(Array(showing.faces.prefix(2).enumerated()), id: \.offset) { pair in
                        RailFace(face: pair.element, size: DS.Face.row)
                    }
                }
                Text(showing.name)
                    .dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .dsGlyph(.caption)
                    .foregroundStyle(DS.textTertiary)
            }
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: spoken(showing.name)))
    }
}
