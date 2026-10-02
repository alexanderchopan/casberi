import SwiftUI

/// THE PRIVACY POOLS ROOM'S HEAD (2026-08-10, prd §349; regrouped into scopes
/// 2026-08-26, prd §486) — where every deposit stands with the screener.
///
/// **ONE READING AGAIN (prd §1060).** Privacy Pools folded into the Wallet
/// (§1048), whose menu draws this head when 0xBow is picked (§1048d), and the
/// Wallet's tiles are the ones under it — so the scope tiles below never drew,
/// and with them Shielded and Review. The tiles and their state are deleted;
/// the head draws every reading: Shielded, then Review, with the deposits'
/// line as the footnote under them. The history below is kept as written.
///
/// ## What §486 changed, and what it did not
///
/// Reported as *"the 0xbow room looks messy"*. It was: SEVEN blocks in one
/// slab, three of them grey sentences in three different type tiers at three
/// different positions, with the counts stated three times over.
///
/// **Every drawing survived; the arrangement is what changed.** The three
/// readings became three scopes behind `DSSectionSwitcher`, and the mapping
/// from block to scope is IDENTITY, which is what makes content loss
/// structurally impossible rather than merely unlikely:
///
///  - **Activity** — the deposits and reclaims themselves, as rows below, plus
///    the one line about what has happened here (`activityNote`).
///  - **Shielded** — what is in the pools per asset, its cover, and the caveats
///    that belong to a money line.
///  - **Review** — the split, its legend, and the one door.
///
/// ## The only scoped head, and what the template owns of it (prd §745)
///
/// Every source room's head is one `DSRoomChassis.Head`, and since prd §763 so
/// is this one: the sentence leads, the scopes are `DSScopeTiles` under it, the
/// scope's reading is a block and the activity note a footnote. It was a lead
/// standing bare on the page, a chip strip and a block per scope, composed from
/// the template's PARTS rather than the template.
///
/// ## The headline belongs to no scope
///
/// It stays ABOVE the control, bare on the page, the way Wallet's crown does:
/// it is the room's identity, and §349's trouble-leads ranking means it is
/// where "a deposit needs your proof" is said.
///
/// ## Two weights, one hue, and no red
///
/// The split encodes exactly one thing: **is this still in play.** Open states
/// take the card's hue at full strength; resolved ones take the faint fill. A
/// declined deposit is NOT painted red — a decline costs nothing but a reclaim,
/// while a cleared deposit is the outcome you wanted. Both are over.
///
/// ## The gap in the bar is the unknown, and it says so
///
/// The denominator is every deposit including the ones carrying no state tag,
/// so a room with unknown deposits draws a bar that does not reach the end. It
/// has a legend row of its own, drawn in exactly the colour the bar's TRACK is
/// drawn in, so the mapping is visible rather than described.
///
/// ## Liveness
///
/// Stores no `Thing` — only value types out of `PrivacyPoolsRoom`, filtered at
/// the boundary by `PrivacyPoolsRoomSource`. The tap hands back a `Slice` and
/// the section that owns the sheet does the lookup (corollary 5).
struct PrivacyPoolsRoomCard: View {
    let room: PrivacyPoolsRoom
    /// Hands back the SLICE, not a `Thing`. A slice owns many deposits, so the
    /// honest landing is that slice's newest deposit — resolved by the feed.
    var onOpen: (PrivacyPoolsRoom.Slice) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    private static let mark = DS.legibleCardFill(for: "Privacy Pools")

    /// Where a proof is actually supplied. 0xBow's own app, the same
    /// destination the `poi_required` alert row already links to — one place
    /// this URL means one thing.
    private static let respondURL = URL(string: "https://app.0xbow.io")

    /// §374, passed down rather than read inside `PrivacyPoolsRoom` — that
    /// file is Foundation-only and compiled whole by the harness, so it cannot
    /// reach `BalancePrivacy`.
    private var mask: String? {
        BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
    }

    /// **ONE HEAD, LIKE EVERY OTHER ROOM'S (prd §763)**: the sentence leads,
    /// each reading is a block, and the activity note is a footnote. The rows
    /// below are individually tappable, so the lead's own sentence carries its
    /// door and there is no face-wide gesture. A reading with nothing in it
    /// draws no block.
    var body: some View {
        DSRoomChassis.Head(lead: .sentence(PrivacyPoolsRoom.headline(room)), door: headDoor,
                           footnotes: [.quiet(PrivacyPoolsRoom.activityNote(room))]) {
            if shieldedHasContent { DSRoomChassis.Block { shieldedBody } }
            if reviewHasContent { DSRoomChassis.Block { reviewBody } }
        }
    }

    private var headDoor: DSRoomChassis.Door? {
        room.lead.map { lead in
            DSRoomChassis.Door(hint: Text("Opens these deposits"), wholeCard: false) {
                onOpen(.state(lead.state))
            }
        }
    }

    // MARK: - Shielded

    /// Presence and rendering, ONE expression (§483's own lesson, learned there
    /// from a Risk chip that opened an empty page).
    private var shieldedHasContent: Bool { !room.holdings.isEmpty }

    @ViewBuilder
    private var shieldedBody: some View {
        // What is actually in there — the reading, at primary weight.
        if let holdings = PrivacyPoolsRoom.holdingsLine(room, mask: mask) {
            Text(holdings)
                .dsText(.body17)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        // The one unambiguously good reading this seat has, beside the money it
        // is about.
        if let cover = PrivacyPoolsRoom.coverLine(room.cover) {
            DSRoomChassis.LineText(line: DSRoomChassis.Line(text: cover, tone: .note))
                .padding(.top, DSRoomChassis.headNoteGap)
        }
        if let note = PrivacyPoolsRoom.shieldedNote(room) {
            DSRoomChassis.LineText(line: DSRoomChassis.Line(text: note, tone: .quiet))
                .padding(.top, DSRoomChassis.headBlockGap)
        }
    }

    // MARK: - Review

    /// The legend draws a row per state AND a row for the untagged deposits,
    /// so a room with untagged deposits and no states still has something to
    /// say.
    private var reviewHasContent: Bool {
        !room.segments.isEmpty || room.untagged > 0
    }

    @ViewBuilder
    private var reviewBody: some View {
        // THE BAR'S OWN CAPTION. It is the shape of the split and belongs
        // against the split.
        DSRoomChassis.LineText(line: DSRoomChassis.Line(text: PrivacyPoolsRoom.note(room), tone: .note))
        if !room.segments.isEmpty {
            splitBar
                .padding(.top, DSRoomChassis.headBlockGap)
        }
        legend
            .padding(.top, DSRoomChassis.headBlockGap)
        // Only for the state that needs a person — a standing "Open 0xBow"
        // link would be chrome on every other room state, where there is
        // nothing to respond to.
        if room.needsYou != nil {
            respondRow
                .padding(.top, DSRoomChassis.headBlockGap)
        }
    }

    // MARK: - The split

    /// Drawn in the ranked order, so the state that needs you leads the bar as
    /// well as the headline. The track behind it is the unknown: a segment set
    /// that does not sum to the whole leaves it showing, on purpose.
    private var splitBar: some View {
        GeometryReader { geo in
            let gaps = CGFloat(max(room.segments.count - 1, 0)) * 2
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(DS.fillFaint)
                HStack(spacing: 2) {
                    ForEach(room.segments) { segment in
                        fill(.state(segment.state))
                            // Floored at 3pt so a single deposit among forty is
                            // still visible rather than a sub-pixel sliver —
                            // rank can never hide a state that needs you.
                            .frame(width: max((geo.size.width - gaps)
                                              * CGFloat(PrivacyPoolsRoom.share(count: segment.count,
                                                                               of: room.deposits)), 3))
                    }
                    Spacer(minLength: 0)
                }
                .clipShape(Capsule(style: .continuous))
            }
        }
        .frame(height: 12)
        // A split is read as proportions of one length, so revealing along that
        // length is the split being stated (`DistributionHero`'s ruling).
        .chartWipe(reduceMotion: reduceMotion)
        .accessibilityHidden(true)
    }

    /// Full strength while the review is open, faint once it is over — see the
    /// type note. One hue throughout.
    ///
    /// **`.unknown` takes the BAR'S OWN TRACK COLOUR**, and that is the whole
    /// of its correctness: the untagged deposits are the gap, so the legend's
    /// dot beside them has to be the colour of the gap.
    private func fill(_ slice: PrivacyPoolsRoom.Slice) -> Color {
        switch slice {
        case .state(let state): return state.resolved ? Self.mark.opacity(0.35) : Self.mark
        case .unknown:          return DS.fillFaint
        }
    }

    // MARK: - Legend

    /// Feed rows (prd §763): the state's dot on the 26pt lead, the name, the
    /// count in the trailing slot. Through `Rows`, so a legend longer than the
    /// lead's box gives up whole rows and counts them.
    private var legend: some View {
        DSRoomChassis.Rows(items: PrivacyPoolsRoom.legendRows(room)) { _, row in
            Button {
                DSHaptic.selection()
                onOpen(row.slice)
            } label: {
                DSFeedRow(name: PrivacyPoolsRoom.name(row.slice),
                          lead: {
                              Circle()
                                  .fill(fill(row.slice))
                                  .frame(width: 7, height: 7)
                          },
                          trailing: {
                              Text(PrivacyPoolsRoom.legendLine(row))
                                  .dsText(.subhead12)
                                  .foregroundStyle(DS.textSecondary)
                                  .lineLimit(1)
                                  .minimumScaleFactor(0.8)
                          })
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
            .accessibilityLabel(Text("\(PrivacyPoolsRoom.name(row.slice)), \(PrivacyPoolsRoom.legendLine(row))"))
        }
    }

    // MARK: - The door

    /// The one action this card can offer, on the one state that needs it.
    ///
    /// Proof is supplied in 0xBow's own app and nowhere else — this app is
    /// capture-only by ruling (§162), so the honest affordance is a door
    /// rather than a form: the template's `HeadLink`, marked as leaving the app.
    @ViewBuilder private var respondRow: some View {
        if let url = Self.respondURL {
            DSRoomChassis.HeadLink(title: String(localized: "Respond on 0xBow"), external: true) {
                openURL(url)
            }
        }
    }
}
