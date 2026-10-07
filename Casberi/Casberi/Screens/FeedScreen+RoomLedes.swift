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
                    .listRowBackground(Color.clear)
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
        Section {
            ForEach(Array(keyed(ordered).enumerated()), id: \.element.id) { i, item in
                // Corollary 3 (build 176) — see `ThingRowKeying`.
                if let thing = item.live {
                    shapedListRow(thing, index: i, nextEventID: nextEventID,
                                  position: positions[i])
                }
            }
        }
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
            .listRowBackground(Color.clear)
            .listRowInsets(.init(top: DS.Space.s2,
                                 leading: DSRoomChassis.inset,
                                 bottom: DSRoomChassis.leadGap,
                                 trailing: DSRoomChassis.inset))
            .listRowSeparator(.hidden)
        }
    }

    /// The cross-source Themes treemap (2026-07-18: moved off Home — "should
    /// it go on all?" — a cross-source overview belongs on the cross-source
    /// feed, the same split that already sent the Wallet treemap to the
    /// Wallet feed). Synchronous, off the SAME `visible` the rows below draw
    /// from (no separate query, so the two can't disagree) — no GenStream
    /// needed, unlike the wallet block, which waits on a real network fetch.
    ///
    /// ABOVE THE FOLD since 2026-08-14 (prd §385, user: "i'm not sure it
    /// needs to be a treemap … i like the idea of 1 and 3"): the map is an
    /// all-time reading that almost never changes, so as a standing head it
    /// answered "what does my corpus contain" on a surface whose question is
    /// "what's different since I last looked". It no longer claims the head
    /// at all — the list opens settled at `themesFoldAnchor` just below it
    /// (see `foldSettled`), and the map is revealed by scrolling up past the
    /// top, the way Mail hides search. The digest-collapse machinery this
    /// replaces (2026-07-20's seen-digest + the collapsed one-line row) is
    /// deleted, not demoted: hidden-by-geometry does the same job with no
    /// stored state, and re-hides on every re-mount for free.
    ///
    /// Deliberately NOT gated on `heroShown` anymore: the no-stacking rule
    /// (2026-08-07) was about two cross-source overviews competing for the
    /// resting open, and above the fold this one isn't present at rest —
    /// seeing it under a thread head costs an explicit scroll-up, which is a
    /// request for more, not a stack.
    @ViewBuilder
    private func themesLedeSection(_ visible: [Thing], proxy: ScrollViewProxy) -> some View {
        // Memoized since 2026-07-31 (see `themesData`), so it no longer walks
        // the corpus on every launch-window body pass.
        let themes = themesData(visible)
        if let doc = themes.doc {
            let rendered = doc.joined(separator: "\n")
            let els = perfAccum("themesParse") { GenParser.parse(prefix: rendered[...], isComplete: true) }
            Section {
                GenRender(id: "root", els: els)
                    // The Themes CARD (2026-07-21, the §160 ruling carried
                    // to the All room): every other feed-head read — the
                    // wallet's two parcels, the heatmaps, the mosaics —
                    // wears the widget surface; this was the
                    // last one floating bare on the page. Same recipe as
                    // the holdings card: GenTagMap self-pads horizontally,
                    // so only the bottom needs closing.
                    .padding(.bottom, DS.Space.s3)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    // The card needs the page gutter the bare map didn't.
                    .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DS.Space.s4,
                                              bottom: 0, trailing: DS.Space.s4))
                    .environment(\.genProjectTap) { name in
                        // The Mac pushes it, zooming out of the tile; the
                        // phone raises it as the one sheet (prd §1132).
                        #if targetEnvironment(macCatalyst)
                        openProject = ProjectRoute(name: name)
                        #else
                        route.push(.project(name))
                        #endif
                    }
                // The fold anchor — the line the list opens settled at, so
                // everything above it (the card) sits above the fold. Zero
                // height on purpose, and `defaultMinListRowHeight` is forced
                // down PER-ROW because a List otherwise gives any row its
                // ~44pt minimum, which would render as a mystery gap between
                // the revealed card and the Today header.
                //
                // The settle rides the ANCHOR'S OWN `onAppear`, not the
                // List's: it fires exactly when this row materialises, so the
                // `scrollTo` can never race the List's first layout (a
                // List-level `onAppear` can run before lazy rows register,
                // and a `scrollTo` no target has heard of is a silent no-op
                // that would leave the map sitting visibly at the top). It
                // also self-gates for free — no themes card, no anchor, no
                // scroll. Unanimated on purpose: this is the room's resting
                // position, not a motion.
                Color.clear
                    .frame(height: 0)
                    .id(Self.themesFoldAnchor)
                    .environment(\.defaultMinListRowHeight, 0)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .onAppear {
                        guard !foldSettled else { return }
                        foldSettled = true
                        proxy.scrollTo(Self.themesFoldAnchor, anchor: .top)
                    }
            }
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
                        DSChevron()
                    }
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.vertical, DS.Space.s2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .dsHover()
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
            }
        }
    }
}
