import SwiftUI

// MARK: - THE ROOM HEAD (prd §745)

/// **THE HEAD CARD EVERY SOURCE ROOM DRAWS, AND THE ONLY ONE** (prd §745, user:
/// "move the other 22 onto the shared template, so every room's top looks like
/// it came from the same hand").
///
/// Four rooms — vibenet, Hegotá, Frames and the Privacy devnet — compose the
/// chassis above: a fixed `visualSlot`, a rail, a switcher. The other
/// twenty-two drew their heads by hand the day their source landed, and read
/// side by side they were one anatomy spelled twenty-two ways: a `heading24`
/// sentence (or a §585 lede), a secondary line under it, a drawing, a few rows,
/// and tertiary footnotes, inside the same widget surface. The gaps between
/// those five pieces were `s1`, `s2`, `s3` or `s4` depending on the file, the
/// footnotes were `label12` in one room and `label12` in the next, the whole
/// card was a tap target in eleven rooms and a dead face in the rest, and the
/// row a ranked room draws existed as ten copies.
///
/// §495 already named the failure: shared COMPONENTS are not a shared
/// TEMPLATE. `ShareBar`, `RoomLedeView` and `DSRunwayRail` were all shared, and
/// the composition around them had twenty-two owners. So this owns the
/// composition, in reading order, and a room supplies facts:
///
///   1. **lead** — `Lead`: the sentence, or the lede figure (§585);
///   2. **notes** — `Line`s directly under the lead, `headNoteGap` apart;
///   3. **blocks** — the room's own drawing and rows, each a `Block`, which
///      owns the `headBlockGap` above it;
///   4. **footnotes** — quiet `Line`s, one `headBlockGap` below the last block.
///
/// **The fixed slot did not apply here, and since §760 it does.** §745 left
/// the height to the content, because clipping a Safe queue to 300pt would be
/// §665's silent lost row in the room where a lost row is a transaction. §760
/// fixes the card at `leadHeight` and keeps that reason: a head that runs long
/// draws fewer rows through `LeadFit` and `Rows`, and says how many it left
/// off, so no row is lost silently.
///
/// FLAT BY LAW, like every head it replaces: one `VStack`, no generic
/// `Widget`/`Row` mount beneath it (the first-frame stack lesson). The one
/// generic layer is this struct, which is the price of the composition having
/// one owner.
extension DSRoomChassis {

    /// Lead → the first note. The tightest gap on the card: a note is the
    /// lead's own second sentence, not a separate object.
    static let headNoteGap: CGFloat = DS.Space.s1

    /// Above every block (a drawing, a set of rows, a link) and above the
    /// footnotes. ONE rung for all of them — the twenty-two hand-drawn heads
    /// used `s2`, `s3` and `s4` for this same gap, which is most of why no two
    /// read as siblings. `s3` is `contentGap`'s rung: a separation, where
    /// `headNoteGap` is a grouping.
    static let headBlockGap: CGFloat = DS.Space.s3

    /// Between two footnotes. Two points, as every head that stacked them had
    /// it: they are one paragraph of small print, broken where the model
    /// breaks it.
    static let headFootnoteGap: CGFloat = 2

    /// THE HEIGHT OF EVERY HEAD'S DRAWING (prd §751, user: "it would be nice if
    /// they are all the same size … should all the charts be the same size on
    /// the chart rooms"). A runway rail, a span strip and a metric disc drew at
    /// 33, 38 and 56pt, so two chart rooms side by side never read as siblings.
    /// Each now draws into this box, and its axis words sit under it.
    ///
    /// 56 is the metric disc's own size (`AssetRosterSlot.markSize`), the one
    /// drawing that could not shrink without losing its curve. A strip's
    /// columns grow to fill it; a rail's track sits at its middle. The wallet
    /// and devnet rooms draw into `visualSlot` and are not governed by this.
    static let figureHeight: CGFloat = 56

    /// The most rows a model hands a head (prd §751, raised by §760). §751
    /// capped every head at three; §760 fills the lead's fixed box instead
    /// (user: "put as many rows in the header as fit"), so the model hands over
    /// up to eight — more than a 286pt box can hold — and `LeadFit` draws as
    /// many as fit. The models spell the literal (they compile without
    /// SwiftUI), and `room-heads-selftest.sh` holds each one to this.
    static let headRowCap = 8

    // MARK: - Facts

    /// What the card leads with.
    enum Lead {
        /// A finding stated as a sentence, at `heading24`.
        case sentence(String)
        /// A figure with its words demoted underneath (§585), spoken as the
        /// sentence it stands in for.
        case lede(RoomLede, spoken: String?)

        /// The §585 rule every room applied by hand: the lede when the model
        /// has a figure to lead with, the sentence when it declines.
        static func figure(_ lede: RoomLede?, otherwise sentence: String) -> Lead {
            if let lede { return .lede(lede, spoken: sentence) }
            return .sentence(sentence)
        }
    }

    /// Where the lead goes. `wholeCard` extends the lead's own door to the
    /// card's face for touch and pointer — the sighted half of `dsCardLead`,
    /// which stays on the lead so VoiceOver reaches the same destination.
    ///
    /// Nil is a legitimate door: a head that names nothing single (CardPointers,
    /// Apple Wallet) opens nothing, and a gesture with no destination is §83's
    /// dead control (the Safe module-only card, 2026-08-17).
    struct Door {
        let hint: Text
        var wholeCard: Bool = true
        let action: () -> Void
    }

    /// One line of words under the lead or under the blocks.
    struct Line {
        enum Tone {
            /// The lead's second sentence — `subhead12`, secondary ink.
            case note
            /// Small print: coverage, staleness, what a cap left off —
            /// `label12`, tertiary ink.
            case quiet
            /// The one register a head may raise its voice in: a fact that can
            /// cost somebody money without their signature (a Safe module).
            /// Attention ink, never red.
            case alert
        }
        let text: String
        var tone: Tone = .note
        /// An SF Symbol before the words, in the line's own register.
        var glyph: String? = nil

        static func note(_ text: String?, glyph: String? = nil) -> Line? {
            text.map { Line(text: $0, tone: .note, glyph: glyph) }
        }
        static func quiet(_ text: String?) -> Line? {
            text.map { Line(text: $0, tone: .quiet) }
        }
        static func alert(_ text: String?, glyph: String) -> Line? {
            text.map { Line(text: $0, tone: .alert, glyph: glyph) }
        }
    }

    // MARK: - The card

    struct Head<Content: View, Scopes: View>: View {
        let lead: Lead
        var door: Door?
        let notes: [Line]
        let footnotes: [Line]
        let content: Content
        /// The room's section tiles, UNDER the well — the wallet family's
        /// place for them (`DSRoomScopeChrome`), so a scoped room that is not a
        /// wallet still wears the one template (user, 2026-09-15: "privacy
        /// pools page isn't a wallet but it should adhere to our uniform
        /// template we use for wallet"). Nil draws the head alone.
        let scopes: Scopes?

        /// `notes` and `footnotes` take optionals so a room can hand over its
        /// model's `String?`s as they come; an absent line takes no gap.
        init(lead: Lead,
             door: Door? = nil,
             notes: [Line?] = [],
             footnotes: [Line?] = [],
             @ViewBuilder content: () -> Content,
             @ViewBuilder scopes: () -> Scopes) {
            self.lead = lead
            self.door = door
            self.notes = notes.compactMap { $0 }
            self.footnotes = footnotes.compactMap { $0 }
            self.content = content()
            self.scopes = scopes()
        }

        var body: some View {
            // THE WALLET'S GEOMETRY WHEN THERE ARE TILES: the well at the top
            // of the row, the tiles `contentGap` under it, both at the rows'
            // inset — `DSRoomScopeChrome.content`'s own arithmetic, so the
            // tiles land at one height in every scoped room.
            VStack(alignment: .leading, spacing: DSRoomChassis.contentGap) {
                well
                if let scopes { scopes }
            }
            .dsRoomHeadPlacement(top: scopes == nil ? DS.Space.s2 : 0)
        }

        private var well: some View {
            // `dsRoomHeadBlock` pads `s4` on every side, so the box inside is
            // `leadHeight` less that twice (prd §760).
            faceDoor(LeadFit(height: DSRoomChassis.leadHeight - 2 * DS.Space.s4) {
                VStack(alignment: .leading, spacing: 0) {
                    leadView
                    ForEach(notes.indices, id: \.self) { index in
                        LineText(line: notes[index])
                            .padding(.top, DSRoomChassis.headNoteGap)
                    }
                    content
                    if !footnotes.isEmpty {
                        VStack(alignment: .leading, spacing: DSRoomChassis.headFootnoteGap) {
                            ForEach(footnotes.indices, id: \.self) { index in
                                LineText(line: footnotes[index])
                            }
                        }
                        .padding(.top, DSRoomChassis.headBlockGap)
                    }
                    // The foot is pinned to the bottom of the box (prd §766),
                    // so every lead has a lower edge that is not air. `LeadFit`
                    // measures it with the rest, so rows give way before it.
                    Spacer(minLength: 0)
                    LeadFooter()
                }
            }
            .dsRoomHeadBlock())
        }

        /// The door's VoiceOver half, on the lead: a `Text` is already an
        /// element, so the trait and the action attach to something real, and
        /// the rows below stay individually reachable (`dsCardLead`'s own note).
        @ViewBuilder
        private var leadView: some View {
            if let door {
                LeadView(lead: lead)
                    .dsCardLead(door.hint) {
                        DSHaptic.selection()
                        door.action()
                    }
            } else {
                LeadView(lead: lead)
            }
        }

        /// The door's face-wide half, for touch and pointer. Attached only where
        /// there is somewhere to go, so a card with no destination does not read
        /// as tappable. Spelled in THIS struct, beside `dsCardLead`, because the
        /// two halves are one door and must not be able to drift apart.
        @ViewBuilder
        private func faceDoor<Face: View>(_ face: Face) -> some View {
            if let door, door.wholeCard {
                face
                    .contentShape(Rectangle())
                    .onTapGesture {
                        DSHaptic.selection()
                        door.action()
                    }
            } else {
                face
            }
        }
    }

    /// A stretch of the card below the notes: a drawing, a set of rows, a link.
    /// It owns the gap above itself, so a block a room declines to draw takes
    /// no air with it.
    /// **THE LEAD'S FOOT (prd §766, user: "proposed with the well").** One quiet
    /// line pinned to the bottom of every lead — how many things the room holds
    /// and since when — so the box states its lower edge with a fact instead
    /// of leaving 200pt of air under a short head. The room sets it once
    /// (`FeedScreen.leadFooter`, through `dsLeadFooter`); a lead drawn outside
    /// a room (no value) draws nothing here.
    struct LeadFooter: View {
        @Environment(\.dsLeadFooter) private var fact

        var body: some View {
            if let fact {
                Text(verbatim: fact)
                    .dsText(.subhead12)
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, DS.Space.s2)
            }
        }
    }

    struct Block<Content: View>: View {
        let content: Content

        init(@ViewBuilder content: () -> Content) {
            self.content = content()
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, DSRoomChassis.headBlockGap)
        }
    }

    /// **THE LEAD'S FIXED BOX, AND HOW A HEAD FITS IT (prd §760).**
    ///
    /// The same content at a falling row limit — every row, then seven down to
    /// none — and `ViewThatFits` draws the first whose natural height
    /// fits the box. Every `Rows` inside reads the limit, so a head that runs
    /// long gives up whole rows from the bottom and counts them; the spellings
    /// that do not fit are measured and never mounted. Asking the layout rather
    /// than adding up the ramp is deliberate: a heading wraps to one line or
    /// two depending on its words, and no spelled sum knows which.
    ///
    /// The clip is the floor under the last spelling. A lead, its notes and
    /// its footnotes that are taller than the card on their own (the largest
    /// Dynamic Type sizes) are the one case that can still lose their bottom.
    struct LeadFit<Content: View>: View {
        let height: CGFloat
        let content: Content

        init(height: CGFloat, @ViewBuilder content: () -> Content) {
            self.height = height
            self.content = content()
        }

        var body: some View {
            ViewThatFits(in: .vertical) {
                content.environment(\.dsHeadRowLimit, nil)
                content.environment(\.dsHeadRowLimit, 7)
                content.environment(\.dsHeadRowLimit, 6)
                content.environment(\.dsHeadRowLimit, 5)
                content.environment(\.dsHeadRowLimit, 4)
                content.environment(\.dsHeadRowLimit, 3)
                content.environment(\.dsHeadRowLimit, 2)
                content.environment(\.dsHeadRowLimit, 1)
                content.environment(\.dsHeadRowLimit, 0)
            }
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height,
                   alignment: .topLeading)
            .clipped()
        }
    }

    /// A head's rows, under `LeadFit`'s limit (prd §760). What the limit leaves
    /// off is counted on a quiet line under the last row drawn — "2 more", not
    /// "2 more below", because a ranked year or a currency is not a row further
    /// down the room (§83).
    struct Rows<Item: Identifiable, RowContent: View>: View {
        let items: [Item]
        let row: (Int, Item) -> RowContent

        @Environment(\.dsHeadRowLimit) private var limit

        init(items: [Item], @ViewBuilder row: @escaping (Int, Item) -> RowContent) {
            self.items = items
            self.row = row
        }

        var body: some View {
            let shown = limit.map { Array(items.prefix($0)) } ?? items
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                row(index, item)
            }
            if shown.count < items.count {
                LineText(line: Line(text: String(localized: "\(items.count - shown.count) more"),
                                    tone: .quiet))
                    .padding(.top, DS.Space.s1)
            }
        }
    }

    // MARK: - Pieces

    /// The lead, drawn. `Head` applies both halves of its own door itself; a
    /// caller with no face-wide gesture passes its `door` here.
    struct LeadView: View {
        let lead: Lead
        var door: Door? = nil

        var body: some View {
            if let door {
                face.dsCardLead(door.hint) {
                    DSHaptic.selection()
                    door.action()
                }
            } else {
                face
            }
        }

        @ViewBuilder
        private var face: some View {
            switch lead {
            case .sentence(let sentence):
                Text(verbatim: DSProse.unorphaned(sentence))
                    .dsText(.heading24)
                    .foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .lede(let lede, let spoken):
                RoomLedeView(lede: lede, spoken: spoken)
            }
        }
    }

    /// A `Line`, drawn in its tone.
    struct LineText: View {
        let line: Line

        var body: some View {
            if let glyph = line.glyph {
                Label {
                    words
                } icon: {
                    Image(systemName: glyph)
                        .foregroundStyle(line.tone == .alert ? DS.attention : DS.textTertiary)
                        .dsGlyph(.caption, weight: .regular)
                }
            } else {
                words
            }
        }

        private var words: some View {
            Text(verbatim: DSProse.unorphaned(line.text))
                .dsText(line.tone == .quiet ? .label12 : .subhead12)
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
        }

        private var ink: Color {
            switch line.tone {
            case .note: return DS.textSecondary
            case .quiet: return DS.textTertiary
            case .alert: return DS.attention
            }
        }
    }

    /// THE RANKED ROW — a thing the room counts, what it holds, and a measure
    /// under both. Ten heads drew this byte-for-byte (X, Journal, Agent,
    /// Cursor, Peer, Gnosis Pay, Dodo Payments, Railgun, Radicle, App Store
    /// Connect), at two paddings and with a 44pt target in one of them.
    ///
    /// **It is a `DSFeedRow` (prd §763).** A head's rows sat in a different
    /// column from the feed rows under them — no 26pt lead, the line on the
    /// right at 13pt, `s1` of padding — so a room's top and its list were two
    /// anatomies. The lead is a glyph for the KIND of thing the row counts (a
    /// calendar for a year, a banknote for a currency), on the disc the
    /// Readings rows wear (§752b); the count keeps the trailing slot.
    ///
    /// A row is a door with ONE gesture (ruling 2026-07-16) and carries no
    /// presentation of its own (the half-open-then-close lesson). It lands as
    /// the `index`-th of its set, so the entrance narrates the model's order.
    struct Row<Measure: View>: View {
        let title: String
        /// The lead's SF Symbol — what kind of thing this row counts.
        let glyph: String
        let line: String
        var detail: String?
        var spoken: String?
        let index: Int
        let action: () -> Void
        let measure: Measure

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        init(title: String,
             glyph: String,
             line: String,
             detail: String? = nil,
             spoken: String? = nil,
             index: Int,
             action: @escaping () -> Void,
             @ViewBuilder measure: () -> Measure) {
            self.title = title
            self.glyph = glyph
            self.line = line
            self.detail = detail
            self.spoken = spoken
            self.index = index
            self.action = action
            self.measure = measure()
        }

        var body: some View {
            Button {
                DSHaptic.selection()
                action()
            } label: {
                DSFeedRow(name: title,
                          line: detail.map { Text(verbatim: $0) },
                          lead: { DSGlyphLead(glyph: glyph) },
                          trailing: {
                              Text(verbatim: line)
                                  .dsText(.subhead12)
                                  .foregroundStyle(DS.textSecondary)
                                  .lineLimit(1)
                          },
                          below: { measure })
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: spoken ?? "\(title), \(line)"))
            .chartArrival(index: index, reduceMotion: reduceMotion)
        }
    }

    /// THE DEADLINE ROW — something with a clock on it, in the room's one hue
    /// (Stripe, Polar, Dodo Payments). Three byte-identical copies before §745,
    /// each carrying its own spelling of the stamp.
    struct DeadlineRow: View {
        let name: String
        /// The one fact that changes what you would do ("Dispute"), in the
        /// room's hue; nil draws the kind alone.
        let stamp: String?
        let kind: String
        let value: String
        /// Past its deadline: the value takes primary ink. Never red — the
        /// §250 ruling that challenged money states itself in words.
        let overdue: Bool
        let fill: Color
        let index: Int
        let action: () -> Void

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            Button {
                DSHaptic.selection()
                action()
            } label: {
                // The feed row's anatomy (prd §763): a clock on the lead disc,
                // the name, the days in the trailing slot, the stamp and the
                // kind under it.
                DSFeedRow(name: name,
                          lead: { DSGlyphLead(glyph: "clock") },
                          trailing: {
                              Text(verbatim: value)
                                  .dsText(.price17)
                                  .foregroundStyle(overdue ? DS.textPrimary : DS.textSecondary)
                                  .monospacedDigit()
                          },
                          below: {
                              HStack(spacing: DS.Space.s1 + 2) {
                                  if let stamp {
                                      Text(verbatim: stamp)
                                          .dsText(.label12)
                                          .foregroundStyle(Color.fixed("#ffffff"))
                                          .padding(.horizontal, 5)
                                          .padding(.vertical, 1)
                                          .background(fill, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                                  }
                                  Text(verbatim: kind)
                                      .dsText(.subhead12)
                                      .foregroundStyle(DS.textSecondary)
                                      .lineLimit(1)
                              }
                              .padding(.top, 1)
                          })
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .chartArrival(index: index, reduceMotion: reduceMotion)
        }
    }

    /// THE MARKED ROW — an entity with its own face and an assessment beside
    /// it (Walletbeat's wallets, L2BEAT's chains). Twins before §745.
    struct MarkedRow<Mark: View, Trailing: View>: View {
        let name: String
        /// A word that outranks the assessment (an unresolved incident), said
        /// on the row in attention ink rather than left to a colour.
        let flag: String?
        let line: String
        let index: Int
        let action: () -> Void
        let mark: Mark
        let trailing: Trailing

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        init(name: String, flag: String?, line: String,
             index: Int, action: @escaping () -> Void,
             @ViewBuilder mark: () -> Mark,
             @ViewBuilder trailing: () -> Trailing) {
            self.name = name
            self.flag = flag
            self.line = line
            self.index = index
            self.action = action
            self.mark = mark()
            self.trailing = trailing()
        }

        /// The feed row's anatomy (prd §763): the mark on the 26pt lead, the
        /// name, the flag and the assessment in the trailing slot, the line
        /// under. The line's ink no longer says whether it is news — a row
        /// varies what it puts in the slots, never the slots (§744); the flag
        /// is the one word that outranks the rating, and it is still said.
        var body: some View {
            DSFeedRow(name: name,
                      line: Text(verbatim: line), lineLines: 2,
                      lead: { mark },
                      trailing: {
                          HStack(spacing: DS.Space.s2) {
                              if let flag {
                                  Text(verbatim: flag)
                                      .dsText(.label12)
                                      .foregroundStyle(DS.attention)
                              }
                              trailing
                          }
                      })
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { DSHaptic.tap(); action() }
            .dsTapCard()
            .chartArrival(index: index, reduceMotion: reduceMotion)
        }
    }

    /// THE HEAD'S ONE LINK — a verb the room offers past its own rows
    /// (Walletbeat's and L2BEAT's directory, Privacy Pools' respond door).
    /// `external` marks a door that leaves the app, with the arrow every such
    /// hand-off wears (§162: we read and state, they act).
    struct HeadLink: View {
        let title: String
        var external: Bool = false
        let action: () -> Void

        var body: some View {
            Button {
                DSHaptic.tap()
                action()
            } label: {
                HStack(spacing: DS.Space.s1) {
                    Text(verbatim: title)
                        .dsText(.subhead12)
                    if external {
                        Image(systemName: "arrow.up.right")
                            .dsGlyph(.caption, weight: .semibold)
                            .accessibilityHidden(true)
                    }
                }
                .foregroundStyle(DS.tint)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// THE SPAN — a column per period, oldest at the left, ends labelled (X's
    /// years, a journal's years, an agent room's months, a card's months). Four
    /// copies before §745, at two heights and two column gaps.
    ///
    /// A SILENT period is drawn faint rather than absent: it is part of the
    /// span, its emptiness is the reading, and dropping it would put two bars
    /// years apart side by side and quietly rescale the axis. Every column is
    /// floored at 4pt, so a period with one item never draws as one with none.
    struct SpanStrip: View {
        struct Column: Identifiable {
            let id: Int
            /// The column's height as a share of the tallest, from the room's
            /// own model — the strip never computes a scale of its own.
            let share: Double
            var silent: Bool = false
        }

        let columns: [Column]
        let fill: Color
        let first: String?
        let last: String?
        /// What VoiceOver hears instead of the drawing.
        let spoken: String

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        /// The columns fill the head's one figure box (prd §751).
        static let height: CGFloat = DSRoomChassis.figureHeight

        var body: some View {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                // Denser spans pack tighter: thirty months at 3pt leave
                // columns thinner than their own gaps.
                HStack(alignment: .bottom, spacing: columns.count > 24 ? 2 : 3) {
                    ForEach(columns) { column in
                        Capsule(style: .continuous)
                            .fill(fill.opacity(column.silent ? 0.18 : 0.85))
                            .frame(height: max(4, Self.height * column.share))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: Self.height, alignment: .bottom)
                .chartWipe(reduceMotion: reduceMotion)
                if let first, let last, columns.count > 1 {
                    HStack {
                        Text(verbatim: first)
                        Spacer(minLength: DS.Space.s2)
                        Text(verbatim: last)
                    }
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: spoken))
        }
    }
}

extension DSRoomChassis.Head {
    /// A head whose tiles may be absent (prd §816). The kind-tile rooms offer
    /// tiles only over two kinds or more, and nil must draw the head ALONE —
    /// the `scopes == nil` geometry — never an empty slot that moves the well.
    /// Same stored fields as the builder form, so the same body draws both.
    init(lead: DSRoomChassis.Lead,
         door: DSRoomChassis.Door? = nil,
         notes: [DSRoomChassis.Line?] = [],
         footnotes: [DSRoomChassis.Line?] = [],
         tiles: Scopes?,
         @ViewBuilder content: () -> Content) {
        self.lead = lead
        self.door = door
        self.notes = notes.compactMap { $0 }
        self.footnotes = footnotes.compactMap { $0 }
        self.content = content()
        self.scopes = tiles
    }
}

extension DSRoomChassis.Head where Scopes == EmptyView {
    /// A head with no section tiles — every room but a scoped one.
    init(lead: DSRoomChassis.Lead,
         door: DSRoomChassis.Door? = nil,
         notes: [DSRoomChassis.Line?] = [],
         footnotes: [DSRoomChassis.Line?] = [],
         @ViewBuilder content: () -> Content) {
        self.lead = lead
        self.door = door
        self.notes = notes.compactMap { $0 }
        self.footnotes = footnotes.compactMap { $0 }
        self.content = content()
        self.scopes = nil
    }
}

extension DSRoomChassis.Head where Content == EmptyView, Scopes == EmptyView {
    /// A head that is its words alone (AWS, Instagram).
    init(lead: DSRoomChassis.Lead,
         door: DSRoomChassis.Door? = nil,
         notes: [DSRoomChassis.Line?] = [],
         footnotes: [DSRoomChassis.Line?] = []) {
        self.init(lead: lead, door: door, notes: notes, footnotes: footnotes) { EmptyView() }
    }
}

extension DSRoomChassis.Row where Measure == EmptyView {
    init(title: String,
         glyph: String,
         line: String,
         detail: String? = nil,
         spoken: String? = nil,
         index: Int,
         action: @escaping () -> Void) {
        self.init(title: title, glyph: glyph, line: line, detail: detail,
                  spoken: spoken, index: index, action: action) { EmptyView() }
    }
}

private struct DSLeadFooterKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

private struct DSHeadRowLimitKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    /// How many rows each `DSRoomChassis.Rows` draws; nil draws them all. Set
    /// only by `DSRoomChassis.LeadFit` (prd §760).
    var dsHeadRowLimit: Int? {
        get { self[DSHeadRowLimitKey.self] }
        set { self[DSHeadRowLimitKey.self] = newValue }
    }

    /// The fact `DSRoomChassis.LeadFooter` draws (prd §766). Set by the room.
    var dsLeadFooter: String? {
        get { self[DSLeadFooterKey.self] }
        set { self[DSLeadFooterKey.self] = newValue }
    }
}

extension View {
    /// The head's own block: the inset and the full width. One definition, so a
    /// scoped head (Privacy Pools) and every `DSRoomChassis.Head` are laid out
    /// the same.
    ///
    /// **IT DRAWS NO PLATE (prd §758, user: "again here, we don't want cards
    /// that are like this").** It was `dsRoomHeadCard()` and it applied
    /// `dsWidgetSurface` — the elevated card. That surface has now been taken
    /// off every other kind of block in the app, one report at a time: §743's
    /// row plates (§749), the reading cover's own deck (§749), every account
    /// page (§708), the wallet family's Actions and Readings (§757). The head
    /// was the last, and it is the biggest — a Safe room's head is a number, a
    /// warning and three rows, so the plate was a card the height of half a
    /// screen.
    ///
    /// **The words stand in the rows' column (prd §763).** §758 kept both halves
    /// of the `s4` padding so removing the plate moved nothing sideways; that
    /// left a head's words 3pt further in than every feed row under it. The
    /// horizontal half is `s3` now — `dsRoomHeadPlacement`'s `s4` plus this is
    /// `DSRoomChassis.leadInset`, the rows' own edge. The vertical half stays,
    /// and `LeadFit`'s box is spelled against it.
    ///
    /// **AND IT SITS IN A WELL (prd §766, user: "proposed with the well").**
    /// Not a plate: §759's no-lift rule stands, and `dsWell` is the RECESSED
    /// rung it names as outside that rule — a faint fill, no shadow, no edge.
    /// §760 gave every lead one height and nothing drew it, so a short head
    /// read as a line and a gap. The well is that box made visible, in every
    /// room at once because every lead's layout is this one definition: its
    /// edge is `DSRoomChassis.inset` from the screen, the words stand `s3`
    /// inside it at `leadInset`, the rows' column.
    func dsRoomHeadBlock() -> some View {
        padding(.horizontal, DS.Space.s3)
            .padding(.vertical, DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsWell(cornerRadius: DS.Radius.widget)
    }

    /// Where a head stands in the feed. `FeedScreen.insightSection` presents
    /// every head edge-to-edge on purpose, so the margin is the head's — the
    /// Altana head that ran flush to both screen edges (§488) is what happens
    /// when a card forgets it.
    ///
    /// **And the air under it is the lead's (prd §763).** Every lead — a head,
    /// a hero, the cover — ends `leadGap` above the first day, so the divider
    /// lands at one y in every room.
    func dsRoomHeadPlacement(top: CGFloat = DS.Space.s2) -> some View {
        padding(.horizontal, DS.Space.s4)
            .padding(.top, top)
            .padding(.bottom, DSRoomChassis.leadGap)
    }
}
