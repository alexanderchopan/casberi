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
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Menu {
            // One plain list, no section headers (user: "don't categorize
            // these"): "All" first, then each group's slots in the order the
            // room listed them — the faces say what kind each one is.
            ForEach(slots.filter { $0.group == nil }) { slot in item(slot) }
            ForEach(groups, id: \.self) { group in
                ForEach(slots.filter { $0.group == group }) { slot in item(slot) }
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

    private var groups: [String] {
        var seen: [String] = []
        for case let group? in slots.map(\.group) where !seen.contains(group) {
            seen.append(group)
        }
        return seen
    }

    /// A row: its face (an address's identicon, an app's own mark) beside
    /// its name, and the checkmark on the one showing (user: "this needs to
    /// show the icons of the app"). A `Toggle` is what gives a menu row a
    /// checkmark AND an image; a `Label` carries only one of the two. "All"
    /// draws no face: it stands for every face below it.
    private func item(_ slot: DSAccountSlot) -> some View {
        Toggle(isOn: Binding(
            get: { slot.id == showing.id },
            set: { _ in
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) {
                    onPick(slot.id.isEmpty ? nil : slot.id)
                }
            }
        )) {
            if let image = slot.id.isEmpty ? nil : menuImage(slot.faces.first) {
                Label { Text(slot.name) } icon: { image }
            } else {
                Text(slot.name)
            }
            if subtitles, let sub = slot.sub {
                Text(sub)
            }
        }
    }

    /// A menu draws images, not views, so the face is rendered once to a
    /// bitmap, round and in its own colours (`.alwaysOriginal`, or the menu
    /// tints it). A face read from the network (an avatar) has no bitmap yet,
    /// so it draws its source's mark instead.
    @MainActor
    private func menuImage(_ face: FaceScopeRail.Item.Face?) -> Image? {
        guard let face else { return nil }
        let renderer = ImageRenderer(content: MenuFace(face: face))
        renderer.scale = displayScale
        guard let image = renderer.uiImage else { return nil }
        return Image(uiImage: image.withRenderingMode(.alwaysOriginal))
    }
}

/// A face as a menu row draws it: round, at the badge tier, from what is on
/// the device (`DSScopeMenu.menuImage`).
private struct MenuFace: View {
    let face: FaceScopeRail.Item.Face
    var body: some View {
        switch face {
        case .wallet(let address):
            WalletFace(address: address, size: DS.Face.badge, circular: true)
        case .avatar(_, let source), .mark(_, let source):
            BridgeIcon(name: source, size: DS.Face.badge, circular: true)
        }
    }
}
