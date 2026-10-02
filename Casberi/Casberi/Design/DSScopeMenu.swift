import SwiftUI

/// **WHOSE VIEW THIS IS, PICKED FROM A MENU** (prd §936 item 5, extended by
/// §959; in the title row since §1066) — a glass pill naming the pick, every
/// slot in a pull-down with a check on the current one.
///
/// The wallet family's and the merged rooms' account picker, drawn by
/// `FeedScreen.titleAccountsPill` beside the room's name. The social rooms
/// keep a row of faces instead (§959): there the face and its ring ARE the
/// news, and a menu would hide both behind a tap.
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
    @State private var open = false
    /// A row tapped, applied once the list has closed.
    @State private var pending: String?

    var body: some View {
        Button {
            DSHaptic.selection()
            open = true
        } label: {
            pillLabel
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(Text(verbatim: spoken(showing.name)))
        // OUR OWN LIST, NOT A SYSTEM `Menu` (prd §1066, user: "put the check
        // on the right justified not before the logo icon"): a system menu
        // puts its checkmark before the row's image, always. A popover kept
        // a popover on the phone too, so it drops from the pill.
        .popover(isPresented: $open, arrowEdge: .top) {
            list
                .presentationCompactAdaptation(.popover)
        }
        .onChange(of: open) { _, isOpen in
            guard !isOpen, let id = pending else { return }
            pending = nil
            #if DEBUG
            NSLog("[Casberi] accountsPill: picked \(id.isEmpty ? "all" : id)")
            #endif
            withAnimation(DS.Motion.standard) { onPick(id.isEmpty ? nil : id) }
        }
    }

    /// One plain list, no section headers (user: "don't categorize these"):
    /// "All" first, then each group's slots in the order the room listed
    /// them — the faces say what kind each one is.
    private var ordered: [DSAccountSlot] {
        slots.filter { $0.group == nil } + groups.flatMap { g in slots.filter { $0.group == g } }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(ordered) { slot in row(slot) }
            }
            .padding(.vertical, DS.Space.s2)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: Self.listWidth)
        .frame(maxHeight: Self.listMaxHeight)
    }

    /// A row: its face (an address's identicon, an app's own mark), its name,
    /// and the checkmark at the trailing edge on the one showing. "All" draws
    /// no face: it stands for every face below it.
    private func row(_ slot: DSAccountSlot) -> some View {
        let picked = slot.id == showing.id
        return Button {
            DSHaptic.selection()
            // The pick rebuilds the room under the list, and a popover whose
            // host rebuilds as it closes stays open (measured): close first,
            // and pick when it has closed (`onChange(of: open)`).
            pending = slot.id
            open = false
        } label: {
            HStack(spacing: DS.Space.s3) {
                Group {
                    if !slot.id.isEmpty, let face = slot.faces.first {
                        MenuFace(face: face)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: Self.faceSize, height: Self.faceSize)
                VStack(alignment: .leading, spacing: 0) {
                    Text(slot.name)
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    if subtitles, let sub = slot.sub {
                        Text(sub)
                            .dsText(.label12)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: DS.Space.s2)
                if picked {
                    Image(systemName: "checkmark")
                        .dsGlyph(.subhead)
                        .foregroundStyle(DS.textPrimary)
                }
            }
            .padding(.horizontal, DS.Space.s4)
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    static let listWidth: CGFloat = 260
    static let listMaxHeight: CGFloat = 480
    static let faceSize: CGFloat = 24

    /// **A GLASS PILL IN THE TITLE ROW (prd §1066, user: "a glass pill … in
    /// top right corner same axis as the category title, and it should say
    /// 'Accounts'").** "Accounts" while everything shows, the pick's name once
    /// one is picked: the title names the room, the pill what is in it. It
    /// was faces, a 12pt name and a chevron under the tiles, which read as a
    /// caption rather than a control.
    private var pillLabel: some View {
        HStack(spacing: DS.Space.s1) {
            Text(showing.id.isEmpty ? String(localized: "Accounts") : showing.name)
                .dsText(.body17)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .dsGlyph(.caption)
                .foregroundStyle(DS.textSecondary)
        }
        .padding(.horizontal, DS.Space.s3)
        .frame(height: Self.pillHeight)
        .dsGlass(cornerRadius: Self.pillHeight / 2)
        // The hand gets the full 44pt; the row does not (user: "the glass
        // pill should not touch the card"). A 44pt frame made the title row
        // taller than its title, and the drawn pill sat on the box below.
        .contentShape(Rectangle().inset(by: -(DS.Hit.min - Self.pillHeight) / 2))
    }

    static let pillHeight: CGFloat = 32

    private var groups: [String] {
        var seen: [String] = []
        for case let group? in slots.map(\.group) where !seen.contains(group) {
            seen.append(group)
        }
        return seen
    }
}

/// A face as a menu row draws it: round, from what is on the device.
private struct MenuFace: View {
    let face: FaceScopeRail.Item.Face
    var body: some View {
        switch face {
        case .wallet(let address):
            WalletFace(address: address, size: DSScopeMenu.faceSize, circular: true)
        case .avatar(_, let source), .mark(_, let source):
            BridgeIcon(name: source, size: DSScopeMenu.faceSize, circular: true)
        }
    }
}
