import SwiftUI

/// THE ACCOUNT DECK — the fused rail slab's replacement, and the reason the
/// wallet family has no bar any more (prd §747, 2026-09-15).
///
/// **The diagnosis.** `DSRoomRailSlab` (§547) fused two strips that disagreed
/// on bleed, shape and selection grammar, and the fusion fixed all three. What
/// it could not fix is what the strips were being asked to do: name an account
/// in a 66pt slot and name a reading in a 12pt chip. Measured on the shipped
/// build, an account's caption cut at ten characters — `accountle…` beside
/// `alexanderc…`, two wallets whose names differ only past the cut — and the
/// scope words wore `label12` with no rest fill under them, which is the size
/// and the weight of a caption rather than of a control (user, 2026-09-15:
/// *"the name gets truncated, so you don't see the full name of the account …
/// the sections like holdings accounts, et cetera, don't really look like
/// sections or buttons to tap, and they look so small"*).
///
/// Both complaints have the same cause and it is not the type ramp: a strip
/// gives a name as much room as fits after everything else on the line, and
/// there were two strips of everything else. So the bar is deleted rather than
/// re-tuned.
///
/// **What replaces it.** The account becomes a CARD you page between — one
/// account on screen at a time, the next peeking — which hands a name the
/// card's whole width (330pt on a 390pt phone, measured below) instead of a
/// slot's leftovers. The card carries what the room used to draw under the
/// bar: the crown, and the acts. The readings become door rows
/// (`DSScopeRows`), which is where the second complaint is answered — a row
/// with a word at `body17`, a reading beside it and a chevron is a control by
/// construction, and it says what it holds before you open it.
///
/// **It is content, not chrome, and that is a simplification §357 paid for.**
/// That ruling hoisted the wallet's rail to `MainSurface.roomControls` because
/// a control mounted inside a subtree carrying `.id(filter.source)` is
/// destroyed by the very move it commands. The deck commands the ACCOUNT
/// scope, which never changes `filter.source`, so it is safe where it is
/// drawn. Nothing here may grow a room-changing verb without moving first.
///
/// **No glass.** The design law puts glass on the floating layer only, and the
/// slab wore it because it floated over content that scrolled under it. This
/// scrolls WITH the room, so it takes the room card's own raised surface —
/// and a mark someone recognises stays opaque either way.
struct DSAccountDeck<Card: View>: View {
    let slots: [DSAccountSlot]
    /// The account showing — nil is "All", matching `FaceScopeRail.scope`.
    let scope: String?
    let onPick: (String?) -> Void
    /// The room's own card body: the crown, then the acts. Handed the slot so
    /// a per-account crown reads the account under the thumb, and so a room
    /// whose acts differ by account (an "All" card that cannot send) can say
    /// so without the deck knowing which rooms those are.
    @ViewBuilder let card: (DSAccountSlot) -> Card

    /// How much of the next card shows. `s8` is the smallest peek that reads
    /// as a card rather than as a rendering fault at the screen edge, and it
    /// leaves the card at 330pt on a 390pt phone — the width the direction was
    /// drawn and measured at.
    private static var peek: CGFloat { DS.Space.s8 }

    /// **Measured, not asked for (prd §724).** A horizontal scroll inside a
    /// `List` row keeps the content width it first measured, which is what
    /// makes `containerRelativeFrame` the wrong tool here: it would resolve
    /// against a container this row may report before the row is laid out.
    /// `DSSectionSwitcher` measures its own viewport for the same reason and
    /// this follows it exactly.
    @State private var viewport: CGFloat = 0
    /// What the scroll has settled on. Separate from `scope` so the deck can
    /// tell a page the FINGER caused from one the room caused, and write only
    /// the first back (see `settle`).
    @State private var visible: String?

    /// The showing card's id, resolved against the slots rather than taken
    /// raw.
    ///
    /// **Case is not identity for an address.** EIP-55 capitalisation IS a
    /// checksum, so the same wallet reaches this scope in two spellings
    /// depending on who wrote it — a deep link, a probe hook, or the deck
    /// itself. `WalletScopeRail.matches` existed to state that for the rail;
    /// resolving here states it once for every room instead, and a scope
    /// naming no slot resolves to "All" rather than paging nowhere.
    private var resolved: String {
        guard let scope, !scope.isEmpty else { return "" }
        let hit = slots.first { $0.id.caseInsensitiveCompare(scope) == .orderedSame }
        return hit?.id ?? ""
    }

    private var cardWidth: CGFloat {
        // The floor is what a card needs before its own head stops fitting —
        // a face, a gap and a name — rather than a round number.
        max(DS.Face.shelf * 4, viewport - Self.peek)
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: DS.Space.s2) {
                ForEach(slots) { slot in
                    page(slot)
                        .frame(width: cardWidth, alignment: .leading)
                        .id(slot.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        // The inset is the room card's own, so a card's leading edge lands on
        // the same rail as a feed row's (`DSRoomChassis.inset`, prd §495).
        .contentMargins(.horizontal, DSRoomChassis.inset, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $visible)
        .background(viewportProbe)
        .onAppear {
            visible = resolved
        }
        .onChange(of: scope) { _, _ in
            // The ROOM changed the account (a deep link, a pick elsewhere).
            // Page to it; `settle` sees the value already matches and writes
            // nothing back.
            let want = resolved
            guard visible != want else { return }
            withAnimation(DS.Motion.glide) { visible = want }
        }
        .onChange(of: visible) { _, now in settle(now) }
    }

    /// Only a page that DIFFERS from the room's scope is written back, which
    /// is what keeps the two `onChange`s from trading writes forever. A deck
    /// paged by the finger settles on a new id, writes it, and the room's
    /// `onChange` then finds `visible` already equal and stops.
    private func settle(_ now: String?) {
        guard let now, now != resolved else { return }
        DSHaptic.selection()
        onPick(now.isEmpty ? nil : now)
    }

    private var viewportProbe: some View {
        GeometryReader { g in
            Color.clear
                .onAppear { viewport = g.size.width }
                .onChange(of: g.size.width) { _, w in viewport = w }
        }
    }

    @ViewBuilder
    private func page(_ slot: DSAccountSlot) -> some View {
        VStack(alignment: .leading, spacing: DSRoomChassis.contentGap) {
            head(slot)
            card(slot)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSRoomChassis.inset)
        .dsWidgetSurface()
        // The whole card, so VoiceOver reads the account once rather than
        // once per element inside it; the card's own content keeps its labels.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(slot.sub.map { Text("\(slot.name), \($0)") } ?? Text(slot.name))
    }

    @ViewBuilder
    private func head(_ slot: DSAccountSlot) -> some View {
        HStack(spacing: DS.Space.s3) {
            if !slot.faces.isEmpty {
                HStack(spacing: -(DS.Face.shelf / 3.5)) {
                    ForEach(Array(slot.faces.prefix(2).enumerated()), id: \.offset) { pair in
                        RailFace(face: pair.element, size: DS.Face.shelf)
                            // The card's own ground, so the overlap reads as
                            // one face in front of another rather than as two
                            // circles sharing an edge. It is the surface this
                            // card draws, not a hairline — §8 bans those.
                            .overlay {
                                if pair.offset > 0 {
                                    Circle().strokeBorder(DS.surfaceSheet,
                                                          lineWidth: DS.Space.s1 - 1)
                                }
                            }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(slot.name)
                    .dsText(.heading17)
                    .foregroundStyle(DS.textPrimary)
                    // ONE line, and it fits: this is the whole point of the
                    // card. If a name ever needs two the card is too narrow,
                    // which is a layout bug and not a truncation to tune.
                    .lineLimit(1)
                if let sub = slot.sub {
                    Text(sub)
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// One page of the deck.
///
/// Deliberately NOT `FaceScopeRail.Item`: that type is a rail slot (one
/// face, one caption, a ring) and this is a card (a stack of faces, a
/// name, a line under it). Sharing it would mean widening the rail's slot
/// with two fields no rail draws, which is how one type ends up serving
/// two shapes badly.
/// **Top level, not nested in `DSAccountDeck`.** A type nested inside a
/// generic cannot be named without its parameter (`DSAccountDeck<Card>.Slot`),
/// which would make every caller spell a type it does not care about — and a
/// nested type reached from another file only through a signature is the
/// swift-frontend crash prd §718 records.
struct DSAccountSlot: Identifiable, Equatable {
    /// The value written to the room's account scope when this card is on
    /// screen. **The empty string is "All"** — a sentinel rather than an
    /// `Optional` because `scrollPosition(id:)` and `ForEach` both want a
    /// concrete `Hashable`, and no address, handle or account id this app
    /// holds is ever empty. The boundary converts (`scope`/`onPick` speak
    /// `String?`, as every rail in the app already does).
    let id: String
    /// The account's WHOLE name. Never pre-truncated by the caller: the
    /// card exists to have room for it, and a caller that shortens one
    /// first has re-created the defect this replaced.
    let name: String
    /// The line under the name — an address, a chain, or what "All" is
    /// made of. Nil draws nothing rather than an empty row.
    let sub: String?
    /// Up to two faces, stacked and overlapped. Two is the cap because a
    /// third reads as a crowd rather than as "these accounts": the "All"
    /// card takes the first two and lets its `sub` carry the rest.
    let faces: [FaceScopeRail.Item.Face]
}

extension DSAccountSlot {
    /// Whether this card is the one the room's scope names.
    ///
    /// **Case is not identity for an address** (EIP-55 capitalisation is a
    /// checksum), so a scope written by a deep link or a probe hook can name
    /// this slot in a different spelling than the deck wrote. Stated once
    /// here, rather than as the `matches` closure every rail adapter used to
    /// carry its own copy of.
    func isShowing(_ scope: String?) -> Bool {
        guard let scope, !scope.isEmpty else { return id.isEmpty }
        return id.caseInsensitiveCompare(scope) == .orderedSame
    }
}
