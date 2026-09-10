import SwiftUI

/// A folder springing UP out of its chip — the Mac dock's move (user,
/// 2026-09-05: "make it behave more like an apple mac dock … more signature
/// and have personality and be easier to navigate", "I DO want this to be
/// our signature").
///
/// **Why up and not out.** The first cut of §621 opened a category IN PLACE:
/// the chip grew to hold its venues and its neighbours slid aside. It kept
/// one row, and it spent the one thing the row does not have — width. Wallet
/// has seven venues; at 44pt seats they are wider than a phone, so the tail
/// of every real folder ran off the edge, and the word that closes the folder
/// had to be scrolled to a fixed seat to survive. A dock springs a folder UP
/// for exactly this reason: the row above has the whole width, the chip
/// never moves (so the close target is where the finger just was), and the
/// motion — a capsule growing out of the chip it belongs to, on a spring with
/// a real bounce — is the personality the in-place version could not have.
///
/// **Anchored to the chip, not to the edge.** `anchorX` is the tapped chip's
/// centre in window space; the row's leading edge is placed so its first seat
/// sits over the chip, clamped inside the band, and the scale transition
/// grows from that same point at the row's bottom edge — so the folder is
/// seen to come OUT of the chip rather than to appear above it. A small tail
/// under the row points at the chip.
///
/// **Closes on pick, like a stack.** Choosing a venue moves the room and the
/// row springs back down a beat later (`MainSurface`'s hop), once the ring
/// has been seen arriving on the pick. Retapping the chip, tapping the feed
/// or swiping rooms closes it too.
struct DockSpringRow<Content: View>: View {
    /// The tapped chip's centre, window space.
    let anchorX: CGFloat
    /// Built with the anchor's x IN THE ROW'S OWN SPACE, so the content can
    /// flow out of that point (see `DockFolderRow`).
    @ViewBuilder let content: (CGFloat) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bandMinX: CGFloat = 0
    @State private var bandWidth: CGFloat = 0
    @State private var rowWidth: CGFloat = 0

    /// The first seat's half-width — the row starts this far left of the
    /// anchor so the seat is centred on the chip.
    private var seatHalf: CGFloat { DS.Hit.min / 2 }
    private var tail: CGFloat { 10 }

    private var leading: CGFloat {
        let wanted = anchorX - bandMinX - seatHalf
        let maxLeading = max(DS.Space.s4, bandWidth - rowWidth - DS.Space.s4)
        return min(max(DS.Space.s4, wanted), maxLeading)
    }

    /// Where along the row the anchor falls, 0…1, for the tail and the
    /// transition's origin.
    private var anchorShare: CGFloat {
        guard rowWidth > 0 else { return 0.1 }
        let x = anchorX - bandMinX - leading
        return min(max(x / rowWidth, 0.06), 0.94)
    }

    var body: some View {
        // **IN A SCROLL VIEW, SO THE ROW CAN NEVER BE WIDER THAN THE BAND**
        // (measured 2026-09-05): Wallet's nine venues make a row wider than
        // a phone, and a child wider than its proposal grows the band's
        // VStack past the screen — which then CENTRES its children, dragging
        // the whole dock strip ~250pt to the left on every open. A scroll
        // view takes exactly the width it is offered and lets the row run
        // past the edge inside it, which is also the Mac stack's answer to a
        // folder with more in it than fits.
        ScrollView(.horizontal, showsIndicators: false) {
            content(rowWidth * anchorShare)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
                // The tail — a rounded diamond under the row, pointing at the chip.
                .overlay(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(DS.fillStrong)
                        .frame(width: tail, height: tail)
                        .rotationEffect(.degrees(45))
                        .offset(x: rowWidth * anchorShare - tail / 2, y: tail / 2)
                        .allowsHitTesting(false)
                }
                .padding(.leading, leading)
                .padding(.trailing, DS.Space.s4)
                .padding(.bottom, DS.Space.s2)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollClipDisabled()
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            bandMinX = frame.minX
            bandWidth = frame.width
        }
        .transition(reduceMotion
                    ? .opacity
                    : .scale(scale: 0.3, anchor: UnitPoint(x: anchorShare, y: 1.15))
                        .combined(with: .opacity))
    }
}

/// The venues of one open category, as a row of marks in a capsule — the
/// content `DockSpringRow` springs up. Marks, not words, and no captions
/// (the venue switcher's own grammar): a recognisable mark in a circle, the
/// lit one ringed, a broken one dashed.
struct DockFolderRow: View {
    let venues: [String]
    /// The room you are standing in — the lit venue.
    let standing: String
    /// The folder's name, for VoiceOver's group label.
    var category: String = ""
    var compact: Bool = false
    /// The chip's x in this row's space — where the venues flow out from.
    var anchorLocalX: CGFloat = 0
    let onPick: (String) -> Void

    @Environment(BridgeStore.self) private var bridges
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNS
    /// False on the first frame: every venue sits at the anchor, small and
    /// clear; then each springs to its seat a beat after the one before.
    @State private var flowed = false

    private var markSize: CGFloat { compact ? DS.Face.row : DS.Face.list }
    private static let seatPitch: CGFloat = DS.Hit.min + 2
    private static let stagger: Double = 0.035
    /// **THE DEAL IS BOUNDED (prd §668, 2026-09-10, user: "when switching tabs
    /// on the [dock] bar it lags… between any others there is a stutter").**
    /// The delay was `i * stagger` uncapped, so Work's twenty venues dealt for
    /// 0.42s of spring plus 0.7s of tail — over a second of animation running
    /// while the room card flew and the new room mounted. Six seats of stagger
    /// is the whole personality (§621's "flow out of the chip"); the rest
    /// arrive with the sixth. Same shape as `RowEntrance`'s cap (§661), same
    /// reason.
    private static let staggerSeats = 6

    /// **THE BROKEN SET, ONE PASS PER BODY (prd §668).** `folderVenue` asked
    /// `bridges.bridges.contains { … }` per venue — a linear scan of the whole
    /// store for each of up to twenty marks, on every body build, and this row
    /// rebuilds whenever the room lands (`standing` changes). One filter over
    /// the store, then one `Set` membership per venue.
    private var brokenVenues: Set<String> {
        let attention = Set(bridges.bridges.lazy.filter { $0.status == .attention }.map(\.name))
        guard !attention.isEmpty else { return [] }
        return Set(venues.filter { attention.contains(BridgeCatalog.seatName(forSource: $0)) })
    }

    var body: some View {
        let broken = brokenVenues
        // The container the lit venue's lens morphs within — see `folderVenue`.
        DSGlassContainer(spacing: 2) {
        HStack(spacing: 2) {
            ForEach(Array(venues.enumerated()), id: \.element) { i, venue in
                // THE FLOW (user, 2026-09-05: "they should flow out of the
                // chip in some springy way and feel sort of fun"): each
                // venue starts on the chip and springs to its seat, one
                // after another — the nearest first — so the row is seen
                // dealt out of the chip rather than switched on.
                let seatX = 2 + CGFloat(i) * Self.seatPitch + DS.Hit.min / 2
                let settled = flowed || reduceMotion
                folderVenue(venue, broken: broken.contains(venue))
                    .scaleEffect(settled ? 1 : 0.3)
                    .opacity(settled ? 1 : 0)
                    .offset(x: settled ? 0 : anchorLocalX - seatX)
                    .animation(reduceMotion ? nil
                               : DS.Motion.folder
                                   .delay(Double(min(i, Self.staggerSeats)) * Self.stagger),
                               value: settled)
            }
        }
        }
        .padding(2)
        // GLASS, not a faint fill (measured 2026-09-05): the row rises above
        // the slab into the band, where the feed's rows pass behind it, and a
        // 16% wash left the marks floating over a headline. It is floating
        // chrome by §8's own definition, and glass is what the floating
        // layer wears.
        .dsGlass(cornerRadius: DS.Radius.pill)
        .clipShape(Capsule(style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("\(category) sources"))
        .onAppear { flowed = true }
    }

    private func folderVenue(_ venue: String, broken: Bool) -> some View {
        let lit = venue == standing
        return Button {
            guard !lit else { return }
            DSHaptic.selection()
            onPick(venue)
        } label: {
            BridgeIcon(name: venue, size: markSize, circular: true)
                // 6pt, was 2.5 (measured 2026-09-06): at 2.5 the lens was a
                // rim a hair wider than the mark and did not read as a
                // selection against the row; a lens needs glass on either side
                // of what it frames, the way the rail's slot has.
                .padding(6)
                // **THE LIT VENUE SITS IN A GLASS LENS (prd §637, user: "that
                // makes it more cohesive right?").** It wore the same 2.5pt
                // stroked ring the wallet rail did — the last selection in the
                // app drawn as an outline. Same treatment as the rail now: the
                // mark INSIDE an untinted glass circle, applied to the content
                // rather than behind it (iOS 26 hoists glass above content, so
                // a background lens hides what it is meant to frame), morphing
                // between venues through the row's `DSGlassContainer` by
                // `glassEffectID`. The mark keeps its own colour — §359's
                // reason a fill could never speak on a brand mark still holds,
                // and a lens says "this one" without painting it.
                .modifier(VenueGlass(on: lit, reduceMotion: reduceMotion, ns: selectionNS,
                                     radius: (markSize + 12) / 2))
                .overlay {
                    if !lit, broken {
                        Capsule(style: .circular)
                            .strokeBorder(DS.attention,
                                          style: StrokeStyle(lineWidth: 2.5, dash: [3, 3]))
                    }
                }
                // DRAWN 36, TARGETED 44 — the switcher's own correction.
                .frame(width: DS.Hit.min, height: DS.Hit.min)
                .contentShape(Capsule(style: .circular))
                .dsHover()
        }
        .buttonStyle(.plain)
        .dsTooltip(broken ? String(localized: "\(venue), needs reconnecting") : venue)
        .accessibilityLabel(broken ? String(localized: "\(venue), needs reconnecting") : venue)
        .accessibilityAddTraits(lit ? .isSelected : [])
    }
}

/// The lit venue's lens — `FaceScopeRail.PickGlass`'s twin (prd §637): glass
/// applied to the mark's own content, never behind it, morphing between
/// venues by id inside the row's container. Reduce Motion drops the id so the
/// lens appears rather than slides; Reduce Transparency plates it via the
/// token.
private struct VenueGlass: ViewModifier {
    let on: Bool
    let reduceMotion: Bool
    let ns: Namespace.ID
    let radius: CGFloat
    @ViewBuilder
    func body(content: Content) -> some View {
        if on {
            content.dsGlass(cornerRadius: radius,
                            glassID: reduceMotion ? nil : "venueSelection",
                            in: reduceMotion ? nil : ns)
        } else {
            content
        }
    }
}
