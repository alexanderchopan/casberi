import SwiftUI
import SwiftData

// The smaller rooms' ledes and groupings: Markets, Bitrefill, the themes
// lede, the feed-health note and CardPointers, split out of
// FeedScreen.swift (prd §718). Nothing here changed but the file it lives
// in and, where another file reads a member, its access level.
extension FeedScreen {
    /// The Tokens room's tiles where the rail stands (iPad, Mac); on the phone
    /// they ride the glass capsule beside the seat (`dsScopeDock`, the
    /// Addresses and What-this-app-reaches control) and nothing stands here.
    @ViewBuilder
    var tokensInlineTiles: some View {
        if !DSScopeDock<TokensScope>.atBottom(roomSizeClass) {
            Section {
                DSScopeTiles(sections: TokensScope.bar, active: chrome.tokensScope,
                             strip: true, verbs: [.new]) { pickTokensScope($0) }
                    .feedRowBackground()
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.inset,
                                              bottom: DSRoomChassis.leadGap,
                                              trailing: DSRoomChassis.inset))
            }
        }
    }

    func pickTokensScope(_ picked: TokensScope) {
        // New is a verb (prd §1081, §1171b): it opens the sheet, never lights.
        if picked == .new {
            feedSheet = .watchAdd
            return
        }
        // Pressing the picked category again is the watchlist (prd §1138).
        let next = picked == chrome.tokensScope && picked.isPack ? TokensScope.watchlist : picked
        withAnimation(DS.Motion.standard) { chrome.tokensScope = next }
    }

    /// A watched row's day change, token or stock — what the Markets lede
    /// counts and the watchlist's movers order sorts by.
    @MainActor
    static func watchChange(_ thing: Thing) -> Double? {
        if let pulse = TokenPulse.shared.pulse(for: thing) { return pulse.change24h }
        guard let symbol = StockWatch.symbol(of: thing) else { return nil }
        return CompanyQuotes.shared.quote(.stock(symbol))?.change
    }

    /// The watchlist's OWN order, not chronology (2026-07-15) — day headers
    /// answer "when did I watch this", a question that stops mattering once
    /// there's more than a couple of tokens; what you actually want is what
    /// MOVED, or the order you dragged it into (TokenWatchOrder — the same
    /// shared choice the settings screen and Home's tile read). One flat
    /// section, no day breaks; the "new since" divider drops with it — it's
    /// a chronological-feed idea, and this list may no longer read top to
    /// bottom by time.
    @ViewBuilder
    func watchlistSection(_ visible: [Thing], nextEventID: UUID?) -> some View {
        // The span the box is on orders "Movers" too (prd §1081).
        let ordered = TokenWatchOrder.shared.apply(
            visible, sourceRef: \.sourceRef,
            change24h: { Self.watchChange($0) })
        // One flat run: pulsed tokens wear the fat TokenRow and stand alone
        // (standsAlone), so merging only ever joins the still-unpulsed rows.
        let positions = cardRunPositions(count: ordered.count,
                                         isBreaker: { standsAlone(ordered[$0]) })
        // Drag to reorder (prd §1250): only in My order, only once Reorder was
        // asked for from a row's long press; the list's own handles move the
        // rows and the order saves through `TokenWatchOrder`, as Move to top's.
        let reorderable = marketsReordering && TokenWatchOrder.shared.mode == .manual
        Section {
            ForEach(Array(keyed(ordered).enumerated()), id: \.element.id) { i, item in
                // Corollary 3 (build 176) — see `ThingRowKeying`.
                if let thing = item.live {
                    shapedListRow(thing, index: i, nextEventID: nextEventID,
                                  position: positions[i])
                }
            }
            .onMove(perform: watchMove(ordered, enabled: reorderable))
        }
        if marketsReordering {
            Section {
                DSDoorRow(icon: "checkmark", title: Text("Done")) {
                    withAnimation(DS.Motion.standard) { marketsReordering = false }
                    DSHaptic.tap()
                }
                .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset,
                                          bottom: 0, trailing: DSRoomChassis.rowInset))
                .feedRowBackground()
                .listRowSeparator(.hidden)
            }
        }
    }

    /// The drop: the rows in their new order become My order. The refs are
    /// read now, while the rows are drawn; a drop must not touch a model a
    /// sync could have deleted in between (`ThingRowKeying`'s corollaries).
    private func watchMove(_ ordered: [Thing], enabled: Bool) -> ((IndexSet, Int) -> Void)? {
        guard enabled else { return nil }
        let refs = ordered.map { $0.isLive ? $0.sourceRef : nil }
        return { from, to in
            var moved = refs
            moved.move(fromOffsets: from, toOffset: to)
            TokenWatchOrder.shared.saveManual(moved.compactMap(\.self))
            DSHaptic.selection()
        }
    }

    /// Reorder, from a row's long press (prd §1250): the list takes its drag
    /// handles. Offered only while the list is in My order.
    func startReorder() {
        guard TokenWatchOrder.shared.mode == .manual else { return }
        withAnimation(DS.Motion.standard) { marketsReordering = true }
        DSHaptic.tap()
    }

    /// A shape's one glanceable block, in the room's lead box (prd §906).
    ///
    /// It stood bare at its own height with words at the row inset, the one
    /// lead in the app outside the template. Now it is the cover's exact
    /// geometry — the box inside `dsRoomHeadBlock`, the pinned foot, `s2`
    /// above and `leadGap` below — so Tokens and Bitrefill open at the same
    /// height as every other room.
    func ledeSection(_ content: some View) -> some View {
        let box = DSRoomChassis.leadBox
        return Section {
            VStack(alignment: .leading, spacing: 0) {
                content
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: box, maxHeight: box, alignment: .topLeading)
            .clipped()
            .dsRoomHeadBlock()
            .feedRowBackground()
            .listRowInsets(.init(top: DS.Space.s2,
                                 leading: DSRoomChassis.inset,
                                 bottom: DSRoomChassis.leadGap,
                                 trailing: DSRoomChassis.inset))
            .listRowSeparator(.hidden)
        }
    }

    /// A room whose head comes from that room's OWN model rather than from a
    /// registry over `[Thing]` (2026-08-04, prd §298).
    ///
    /// `FeedInsight` is pure over the corpus by contract — it can only count
    /// and group stored fields. These three rooms lead with facts that are not
    /// in the corpus at all: a certificate's expiry, a Stripe balance, a
    /// PostHog reading, each held in bridge state. So they get a head each,
    /// and they share one slot in the chain because they can never compete —
    /// every case names exactly one source.
    /// A feed that has stopped answering, said in the room (2026-08-23, prd
    /// §455). Draws nothing at all when every feed is fine, which is the
    /// common case — see `FeedRoomHealth`.
    ///
    /// A DOOR, not a label. The one useful response is to look at the followed
    /// list and re-add or remove the feed, and that list lives on the bridge's
    /// own screen; a line stating a problem with no way to act on it is the
    /// half-control the honesty law is about. Its destination comes from
    /// `FeedRoomHealthSource`, so a room whose screen we cannot name draws no
    /// note rather than a chevron that goes nowhere.
    @ViewBuilder
    var feedHealthNote: some View {
        if let standing = heads?.feedHealth,
           let destination = FeedRoomHealthSource.destination(for: source) {
            Section {
                Button {
                    DSHaptic.selection()
                    route.pushBridge(destination)
                } label: {
                    HStack(spacing: DS.Space.s2) {
                        Text(standing.line)
                            .dsText(.subhead12)
                            .foregroundStyle(DS.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.vertical, DS.Space.s2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .dsHover()
                .feedRowBackground()
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
            }
        }
    }
}
