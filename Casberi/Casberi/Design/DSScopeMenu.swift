import SwiftUI

/// **WHOSE VIEW THIS IS, PICKED FROM A MENU** (prd §936 item 5, extended by
/// §959; in the title row since §1066) — a glass pill naming the pick, every
/// slot in a pull-down with a check on the current one.
///
/// The wallet family's and the merged rooms' account picker, drawn by
/// `FeedScreen.roomPickPill` beside the room's name (§1129). The social rooms
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
    /// The pill's word while everything shows: "All" (prd §1129), or Home
    /// in You, whose first door is a place and not everything. The rows say
    /// what they list ("All apps", "All accounts"); the pill never names a
    /// kind, so it cannot name the wrong one (§1128's tension).
    var allLabel: String = String(localized: "All")
    /// What VoiceOver says: "Account: …" in the wallet family, "Showing: …"
    /// where the pick is a source rather than one of yours.
    var spoken: (String) -> String = { String(localized: "Account: \($0)") }
    /// Draw each slot's `sub` as its subtitle in the menu. On GitHub and
    /// Pinterest it says repo or person, board or person — the one fact the
    /// rail's square-or-circle carried and a menu of names would otherwise
    /// drop. Off in the wallet family, whose `sub` is a tooltip.
    var subtitles: Bool = false
    /// **AN ACT AT THE HEAD OF THE LIST (prd §1107)**: the Wallet's "Watch a
    /// wallet". First, never last, because the list can run long (user: "it
    /// shouldn't go at the bottom b/c someone may have tons of things there
    /// already"), and set apart from the accounts by the tint it acts in.
    var action: Action? = nil
    let onPick: (String?) -> Void
    @State private var open = false
    /// A row tapped, applied once the list has closed.
    @State private var pending: String?
    /// The act tapped, run once the list has closed — the same reason as
    /// `pending`: what it raises must not rise from under a closing popover.
    @State private var pendingAction = false

    /// An act the list leads with: its word, its glyph, what it does.
    struct Action {
        let title: String
        let symbol: String
        let run: () -> Void
    }

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
            guard !isOpen else { return }
            if pendingAction {
                pendingAction = false
                // A sheet asked for while the popover is still leaving never
                // rises (measured: the list closed, no tray). Run the act once
                // it has gone — the app's one-presentation-at-a-time wait.
                let act = action
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    act?.run()
                }
                return
            }
            guard let id = pending else { return }
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
                if let action { actionRow(action) }
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
                    if slot.brandDisc, let symbol = slot.symbol {
                        Circle()
                            .fill(DS.surfaceRaised)
                            .overlay(
                                Image(systemName: symbol)
                                    .dsGlyph(.subhead, weight: .medium)
                                    .foregroundStyle(DS.brand)
                            )
                    } else if !slot.id.isEmpty, let symbol = slot.symbol {
                        BridgeIcon(name: "", size: Self.faceSize, circular: true, symbol: symbol)
                    } else if !slot.id.isEmpty, let face = slot.faces.first {
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

    /// The act's row: the row's anatomy, its glyph in the face column and its
    /// word in the tint, then the room's spacing before the accounts start.
    private func actionRow(_ action: Action) -> some View {
        Button {
            DSHaptic.selection()
            pendingAction = true
            open = false
        } label: {
            HStack(spacing: DS.Space.s3) {
                Image(systemName: action.symbol)
                    .dsGlyph(.subhead, weight: .semibold)
                    .foregroundStyle(DS.tint)
                    .frame(width: Self.faceSize, height: Self.faceSize)
                Text(action.title)
                    .dsText(.body17)
                    .foregroundStyle(DS.tint)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.s2)
            }
            .padding(.horizontal, DS.Space.s4)
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .padding(.bottom, DS.Space.s2)
    }

    static let listWidth: CGFloat = 260
    static let listMaxHeight: CGFloat = 480
    static let faceSize: CGFloat = DS.Face.row

    /// **A GLASS PILL BESIDE THE ROOM'S NAME (prd §1066, §1129; §1128 made
    /// it the title, and the user: "it's weird to not see the category
    /// name").** The title names the category, in pink; the pill, plain,
    /// names what is showing in it.
    private var pillLabel: some View {
        HStack(spacing: DS.Space.s1) {
            Text(showing.id.isEmpty ? allLabel : showing.name)
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
