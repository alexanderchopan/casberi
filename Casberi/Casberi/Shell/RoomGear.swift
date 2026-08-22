import SwiftUI

/// The measured height of the top band (demo banner + chip strip + room
/// controls), so a floating control can sit just below it.
///
/// **Measured, not assumed, and that is the whole reason this key exists.** The
/// obvious placements were both tried on device and both wrong: an overlay
/// attached BEFORE `.safeAreaInset(edge: .top)` inherits the original safe area,
/// and one attached AFTER inherits it too — `safeAreaInset` reserves safe area
/// for the inset view's own SIBLINGS, and an overlay is not one, so either way
/// the gear rendered level with the demo banner, on top of the chrome it was
/// supposed to sit under.
///
/// A constant would have been worse than either: the band is three optional
/// rows deep — the demo banner appears only in demo mode, the venue switcher
/// only in a folded category, the face rail only in Wallet or a person scope —
/// and it shrinks again when the strip minimizes. Any number picked by reading
/// the code is correct for exactly one of those states.
struct BandHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    // `max` rather than last-wins: the band is reported once, but a transition
    // briefly has two in flight, and taking the taller one keeps the control
    // below both rather than letting it jump up through the outgoing band.
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The door from a source room to that source's own setup screen (2026-08-21).
///
/// **The gap it closes.** A scoped room had NO route to the seat behind it. The
/// only in-room door was `RoomQuiet`'s copy, which appears exactly when the seat
/// is broken or empty — so a healthy Farcaster room whose watch list you wanted
/// to edit sent you back out to the catalogue to hunt for Farcaster among a
/// hundred offers, four or five taps and a visual search away. This was known
/// and waved off once as "the catalogue is fine"; it isn't, and the tap count is
/// the smaller half of why.
///
/// The bigger half: **a broken seat is invisible from inside its own room.** It
/// simply stops landing rows, which from the reader's side is indistinguishable
/// from having nothing new — §311's failure, and the one thing the catalogue
/// route can never fix, because it requires already suspecting the problem.
///
/// **Why a bare gear is legible here**, when a gear in shared chrome would not
/// be. It is drawn ONLY in a room with a seat behind it — never in All, never in
/// You or Voice or Pinned — so at the moment it is on screen there is exactly
/// one thing it can be about. And it sits in the room's own body rather than up
/// in the strip head beside the avatar and the catalogue door, which are the
/// genuinely app-wide controls. Presence is the disambiguation.
///
/// **Floating, so nothing is pushed down.** Glass on the composer/toast layer,
/// which is the sanctioned use (build-brief §8: the floating layer only, never
/// on content). The feed starts exactly where it started before this existed;
/// the gear sits over the first row's trailing corner and fades while you scroll.
///
/// **It never has to resolve a fold.** `MainSurface.go(to:)` already turns a
/// category chip into a real venue before writing `FeedFilter.source` (§351's
/// central invariant), so by the time this view sees a source it is a source.
/// That is why there is no `CategoryFold` call here and must not be one — a
/// second resolver is how the two drift and the gear opens the wrong seat.
struct RoomGear: View {
    /// The room's source. Always a real source, never a category label — see
    /// the type doc.
    let source: String

    @Environment(BridgeStore.self) private var store
    @Environment(ShellChrome.self) private var chrome
    // Per-window, never a `.shared` — `HomeRoute.shared` was deleted for
    // multi-window on 2026-08-02 and that file says the deletion IS the
    // enforcement. Pushing onto another window's stack is the bug it prevents.
    @Environment(HomeRoute.self) private var route

    /// The seat registered for this source, if any.
    ///
    /// Matched on the SOURCE name first and the OFFER name second, because the
    /// two are not always the same string and either can be what got registered:
    /// `PrivacyPoolsBridge` stamps `source: "Privacy Pools"` while the catalog
    /// (and `reconcileWalletSeats`) calls the seat "0xBow Privacy Pools". The
    /// same split is why `BridgeCatalog.offer(forSource:)` exists at all.
    private var seat: BridgeApp? {
        let offerName = BridgeCatalog.offer(forSource: source)?.name
        return store.bridges.first { $0.name == source || $0.name == offerName }
    }

    /// Where the gear goes, or nil for a room that has no seat to open.
    ///
    /// Three rungs, in this order, and the last one is what keeps the demo
    /// honest:
    ///
    /// 1. The offer's own destination. `destination(forOffer:)` is deliberately
    ///    the CONNECT-side resolver rather than `forID`, because it already
    ///    encodes the §207 ruling this door needs: Peer, 0xBow Privacy Pools,
    ///    Safe and Railgun have no setup of their own — watching a wallet IS
    ///    their consent — so it routes them to the wallet manager, which is
    ///    genuinely where their settings live.
    /// 2. A registered seat with no routed screen falls to its detail screen.
    ///    **This is the demo's rung**: `DemoSeedAll.seatTable` registers seats
    ///    whose ids `BridgeRouter.rows` has never heard of, so rung 1 answers
    ///    nil for them and without this the gear would be missing from most
    ///    rooms in the one mode built to show every room working.
    /// 3. Nothing — no gear. Absent, never disabled, never a control that opens
    ///    nothing (the honesty law).
    private var destination: BridgeRouter.Destination? {
        guard let offer = BridgeCatalog.offer(forSource: source) else { return nil }
        if let routed = BridgeRouter.destination(forOffer: offer.name) { return routed }
        if let seat { return .detail(id: seat.id) }
        return nil
    }

    /// Does this seat want you? `attention` is the state this control exists
    /// for — see the type doc.
    private var needsYou: Bool { seat?.status == .attention }

    var body: some View {
        if let destination {
            Button {
                DSHaptic.selection()
                route.path.append(.bridge(destination))
            } label: {
                Image(systemName: "gearshape")
                    // OUTLINE, not `gearshape.fill`: a filled glyph at this size
                    // beside a strip full of saturated brand marks reads as a
                    // sixth chip. The thin stroke reads as chrome, which is what
                    // this is.
                    .dsGlyph(20)
                    .foregroundStyle(needsYou ? DS.destructive : DS.textSecondary)
                    .frame(width: 42, height: 42)
                    .dsGlass(cornerRadius: 21)
                    .overlay(alignment: .topTrailing) {
                        if needsYou {
                            Circle()
                                .fill(DS.destructive)
                                .frame(width: 11, height: 11)
                                // Reads against the glass in both themes without
                                // a hairline: the ring is the page behind it, so
                                // it is a shape, not a stroke.
                                .overlay(Circle().strokeBorder(DS.page, lineWidth: 2))
                                .offset(x: 1, y: -1)
                        }
                    }
                    // After the glass and its badge, so the drawn pill stays
                    // 42 and only the target grows to the 44pt floor.
                    .dsTapTarget(Circle())
            }
            .buttonStyle(PressSpring())
            .dsHover()
            .accessibilityLabel(needsYou
                ? Text("\(source) settings — needs your attention")
                : Text("\(source) settings"))
            // Out of the way while you read, back when you stop. The SAME
            // trigger the strip condenses on, so the two move together instead
            // of one fading while the other resizes.
            //
            // An ALERT never fades: the one state where this control is news
            // rather than a door is the one state worth interrupting a scroll
            // for.
            .opacity(chrome.minimized && !needsYou ? 0 : 1)
            .animation(DS.Motion.standard, value: chrome.minimized)
            .animation(DS.Motion.standard, value: needsYou)
            .padding(.trailing, DS.Space.s4)
            .padding(.top, DS.Space.s2)
        }
    }
}
