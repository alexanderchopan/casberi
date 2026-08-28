import SwiftUI

/// THE PRIVACY POOLS ROOM'S HEAD (2026-08-10, prd §349; regrouped into scopes
/// 2026-08-26, prd §486) — where every deposit stands with the screener.
///
/// ## What §486 changed, and what it did not
///
/// Reported as *"the 0xbow room looks messy"*. It was: SEVEN blocks in one
/// slab — headline, note, holdings, split bar, legend, respond door, cover
/// line, footnote — three of them grey sentences in three different type tiers
/// at three different positions (§315's setup-copy failure, in a room head),
/// with the counts stated three times over and a closing run-on of up to six
/// `·`-joined clauses.
///
/// **Every drawing survived; the arrangement is what changed.** The three
/// readings became three scopes behind `DSSectionSwitcher` — Wallet's own
/// control (§483), Vibenet's a day later (§482), this a day after that — and
/// the mapping from block to scope is IDENTITY, which is what makes content
/// loss structurally impossible rather than merely unlikely:
///
///  - **Activity** — the deposits and reclaims themselves, as rows below, plus
///    the one line about what has happened here (`activityNote`).
///  - **Shielded** — what is in the pools per asset, its cover, and the caveats
///    that belong to a money line.
///  - **Review** — the split, its legend, and the one door.
///
/// The `note` is no longer a second sentence under the headline competing with
/// it; it is the split bar's own caption, in the scope whose subject it is. The
/// footnote is not deleted but distributed — its clauses now sit under the
/// reading each one qualifies.
///
/// ## The headline belongs to no scope
///
/// It stays ABOVE the control, bare on the page, the way Wallet's crown does:
/// it is the room's identity, and §349's trouble-leads ranking means it is
/// where "a deposit needs your proof" is said. A strip that could scope that
/// away would let you open the room and not be told the one thing it exists to
/// tell you. Bare rather than in a card for `VibenetRoomCard.balanceHero`'s
/// reason (§475): a container around the room's lead is the app claiming an
/// emphasis the content already has.
///
/// ## Two weights, one hue, and no red
///
/// The split encodes exactly one thing: **is this still in play.** Open states
/// (in review, needs your proof) take the card's hue at full strength;
/// resolved ones (cleared, declined) take the faint fill. A declined deposit is
/// NOT painted red — the design law's honesty rule is that state is stated in
/// words, never in a colour that does the arguing (the Stripe dispute
/// precedent), and here it would be actively wrong: a decline costs nothing but
/// a reclaim, while a cleared deposit is the outcome you wanted. Both are over.
///
/// ## The gap in the bar is the unknown, and it says so now
///
/// The denominator is every deposit including the ones carrying no state tag,
/// so a room with unknown deposits draws a bar that does not reach the end.
/// That gap was explained only by a footnote clause several blocks below it —
/// the one unlabelled part of the drawing, decodable only by reading tertiary
/// text somewhere else. It has a legend row of its own now, drawn in exactly
/// the colour the bar's TRACK is drawn in, so the mapping is visible rather
/// than described. Filling the bar by dividing through the tagged count alone
/// would still be presenting partial knowledge as complete, and is still not
/// done.
///
/// ## Liveness
///
/// Stores no `Thing` — only value types out of `PrivacyPoolsRoom`, filtered at
/// the boundary by `PrivacyPoolsRoomSource`. The tap hands back a `Slice` and
/// the section that owns the sheet does the lookup (corollary 5).
///
/// FLAT BY LAW: plain VStacks, no generic `Widget`/`Row` mount.
struct PrivacyPoolsRoomCard: View {
    let room: PrivacyPoolsRoom
    /// Hands back the SLICE, not a `Thing`. A slice owns many deposits, so the
    /// honest landing is that slice's newest deposit — resolved by the feed.
    var onOpen: (PrivacyPoolsRoom.Slice) -> Void

    /// Which reading is on screen. Defaulted so `PrivacyPoolsScreen` and any
    /// other caller with no scope state draws the room whole, exactly as
    /// before — the narrowing is opt-in by construction rather than by a flag
    /// every caller has to remember to pass (`VibenetRoomCard.shows`'s rule).
    var section: PrivacyPoolsSection? = nil
    /// The strip's own inputs, handed down rather than read from the shell, so
    /// a caller with no scope state draws no strip for free.
    var scopes: [PrivacyPoolsSection] = []
    var scopeAttention: Set<PrivacyPoolsSection> = []
    var onPickScope: ((PrivacyPoolsSection) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    private static let mark = DS.legibleCardFill(for: "Privacy Pools")

    /// Where a proof is actually supplied. 0xBow's own app, the same
    /// destination the `poi_required` alert row already links to — one place
    /// this URL means one thing, and a door that opens anywhere else on the
    /// screen telling you to respond would be the sharpest dead door in the
    /// app.
    private static let respondURL = URL(string: "https://app.0xbow.io")

    /// §374, passed down rather than read inside `PrivacyPoolsRoom` — that
    /// file is Foundation-only and compiled whole by the harness, so it cannot
    /// reach `BalancePrivacy`.
    private var mask: String? {
        BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
    }

    /// Whether a scope's content draws. A nil `section` means the whole room in
    /// one scroll, which is what the un-scoped callers want.
    private func shows(_ candidate: PrivacyPoolsSection) -> Bool {
        section == nil || section == candidate
    }

    var body: some View {
        // s4, not s3. §471's lesson one room over: at 14pt a headline, a glass
        // control and a card read as one stack of seams rather than three
        // objects with air between them — and the whole complaint here was
        // that the room read as a slab. Not s6, which is that entry's answer
        // for several stacked CARDS: at most one card draws here, so the wider
        // gap would just push the reading down the page.
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            headline
            scopeStrip
            // Each scope draws AT MOST one card, and a scope with nothing to
            // put in one draws none rather than an empty box — Activity's
            // content is the rows below it, so on most rooms this head is a
            // sentence and a control and nothing else. That is the point.
            if shows(.shielded), shieldedHasContent { card { shieldedBody } }
            if shows(.review), reviewHasContent { card { reviewBody } }
            if shows(.activity), let note = PrivacyPoolsRoom.activityNote(room) {
                Text(note)
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s2)
    }

    // MARK: - The headline, which belongs to no scope

    private var headline: some View {
        // The source-name eyebrow retired here 2026-08-22 (prd §452). A room
        // head renders only inside its own source's room, under a chip strip
        // where that source's chip is the lit one — so the card introduced
        // itself with a word already on screen, one row up.
        Text(PrivacyPoolsRoom.headline(room))
            .dsText(.heading22)
            .foregroundStyle(DS.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The card-wide tap gesture retired with §486: the readings below
            // are now individually tappable rows inside their own cards, and a
            // whole-card target over them is a second answer to the same
            // gesture. The lead's own sentence carries it instead, which is
            // also the one line that names where it goes.
            .dsCardLead(Text("Opens these deposits")) {
                guard let lead = room.lead else { return }
                DSHaptic.selection()
                onOpen(.state(lead.state))
            }
    }

    /// The scope strip, below the headline and above every reading it scopes.
    ///
    /// STATED COST, inherited from `VibenetRoomCard.scopeStrip` rather than
    /// rediscovered: a control inside the scroll scrolls away, which is §357's
    /// complaint one level down. The answer is a pinned `Section` header, not a
    /// return to `safeAreaInset` — deliberately not done here, for the same
    /// reason it is not done there.
    @ViewBuilder
    private var scopeStrip: some View {
        if onPickScope != nil, PrivacyPoolsSection.shows(present: scopes) {
            DSSectionSwitcher(
                sections: scopes,
                active: section ?? .activity,
                attention: scopeAttention) { picked in
                    onPickScope?(picked)
                }
        }
    }

    /// The surface every scope's card wears — one definition, so two cards
    /// cannot drift into two slightly different boxes.
    @ViewBuilder
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsWidgetSurface()
    }

    // MARK: - Shielded

    /// Presence and rendering, ONE expression (§483's own lesson, learned there
    /// from a Risk chip that opened an empty page): this is exactly the test
    /// `PrivacyPoolsSection.present(shielded:)` is passed at the call site.
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
        // The one unambiguously good reading this seat has, and it now sits
        // beside the money it is about instead of below a footnote.
        if let cover = PrivacyPoolsRoom.coverLine(room.cover) {
            Text(cover)
                .dsText(.subhead13)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s2)
        }
        if let note = PrivacyPoolsRoom.shieldedNote(room) {
            Text(note)
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s2)
        }
    }

    // MARK: - Review

    /// The legend draws a row per state AND a row for the untagged deposits,
    /// so a room with untagged deposits and no states still has something to
    /// say — the same test the call site passes as `review:`.
    private var reviewHasContent: Bool {
        !room.segments.isEmpty || room.untagged > 0
    }

    @ViewBuilder
    private var reviewBody: some View {
        // THE BAR'S OWN CAPTION. §349 drew this directly under the headline,
        // where it read as a second sentence about the same fact; it is the
        // shape of the split and belongs against the split.
        Text(PrivacyPoolsRoom.note(room))
            .dsText(.subhead13)
            .foregroundStyle(DS.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        if !room.segments.isEmpty {
            splitBar
                .padding(.top, DS.Space.s3)
        }
        legend
            .padding(.top, DS.Space.s3)
        // Only for the state that needs a person — a standing "Open 0xBow"
        // link would be chrome on every other room state, where there is
        // nothing to respond to.
        if room.needsYou != nil {
            respondRow
                .padding(.top, DS.Space.s2)
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
                            // the `UnitTreemap` rule: rank can never hide a
                            // state that needs you.
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
    /// dot beside them has to be the colour of the gap. `mark.opacity(0.35)`
    /// would file them with the resolved states, which is a claim — an
    /// untagged deposit's review is not over, it is unrecorded.
    private func fill(_ slice: PrivacyPoolsRoom.Slice) -> Color {
        switch slice {
        case .state(let state): return state.resolved ? Self.mark.opacity(0.35) : Self.mark
        case .unknown:          return DS.fillFaint
        }
    }

    // MARK: - Legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ForEach(PrivacyPoolsRoom.legendRows(room)) { row in
                Button {
                    DSHaptic.selection()
                    onOpen(row.slice)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                        Circle()
                            .fill(fill(row.slice))
                            .frame(width: 7, height: 7)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        Text(PrivacyPoolsRoom.name(row.slice))
                            .dsText(.body17)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: DS.Space.s2)
                        Text(PrivacyPoolsRoom.legendLine(row))
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(PrivacyPoolsRoom.name(row.slice)), \(PrivacyPoolsRoom.legendLine(row))"))
            }
        }
    }

    // MARK: - The door

    /// The one action this card can offer, on the one state that needs it.
    ///
    /// Proof is supplied in 0xBow's own app and nowhere else — this app is
    /// capture-only by ruling (§162), so there is no version of this that
    /// responds on the person's behalf, and the honest affordance is a door
    /// rather than a form. It is the same hand-off shape `ApprovalPrepareCard`
    /// uses for Revoke.cash, down to the arrow.
    @ViewBuilder private var respondRow: some View {
        if let url = Self.respondURL {
            Button {
                DSHaptic.selection()
                openURL(url)
            } label: {
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: "arrow.up.right")
                        .dsGlyph(13, weight: .regular)
                        .foregroundStyle(DS.textSecondary)
                        .frame(width: 18, alignment: .center)
                    Text("Respond on 0xBow")
                        .dsText(.callout15)
                        .foregroundStyle(DS.textPrimary)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, DS.Space.s1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
