import SwiftUI

// MARK: - THE ROOM HEAD (prd §745)

/// **THE HEAD CARD EVERY SOURCE ROOM DRAWS, AND THE ONLY ONE** (prd §745, user:
/// "move the other 22 onto the shared template, so every room's top looks like
/// it came from the same hand").
///
/// Four rooms — vibenet, Hegotá, Frames and the Privacy devnet — compose the
/// chassis above: a fixed `visualSlot`, a rail, a switcher. The other
/// twenty-two drew their heads by hand the day their source landed, and read
/// side by side they were one anatomy spelled twenty-two ways: a `heading22`
/// sentence (or a §585 lede), a secondary line under it, a drawing, a few rows,
/// and tertiary footnotes, inside the same widget surface. The gaps between
/// those five pieces were `s1`, `s2`, `s3` or `s4` depending on the file, the
/// footnotes were `label11` in one room and `label12` in the next, the whole
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
/// **The fixed slot does not apply here, on purpose.** `visualSlot` is a box
/// sized for a figure that scopes change under; these heads have no scopes and
/// their honest height is what they have to say (a quiet AWS account is one
/// sentence, a Safe queue is three rows). Clipping a Safe queue to 300pt would
/// be §665's silent lost row, in the room where a lost row is a transaction.
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

    /// The most rows a head draws (prd §751). Heads capped at three or four;
    /// they cap at three. The models spell the literal (they compile without
    /// SwiftUI), and `room-heads-selftest.sh` holds each one to this.
    static let headRowCap = 3

    /// The gap in a SCOPED head (Privacy Pools, §486): lead, scope switcher,
    /// the scope's card. `s4` rather than `headBlockGap` because those are
    /// three objects standing on the page, not three parts of one card — §471's
    /// finding that at 14pt they read as one stack of seams.
    static let scopedHeadGap: CGFloat = DS.Space.s4

    // MARK: - Facts

    /// What the card leads with.
    enum Lead {
        /// A finding stated as a sentence, at `heading22`.
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
            /// The lead's second sentence — `subhead13`, secondary ink.
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

    struct Head<Content: View>: View {
        let lead: Lead
        var door: Door?
        let notes: [Line]
        let footnotes: [Line]
        let content: Content

        /// `notes` and `footnotes` take optionals so a room can hand over its
        /// model's `String?`s as they come; an absent line takes no gap.
        init(lead: Lead,
             door: Door? = nil,
             notes: [Line?] = [],
             footnotes: [Line?] = [],
             @ViewBuilder content: () -> Content) {
            self.lead = lead
            self.door = door
            self.notes = notes.compactMap { $0 }
            self.footnotes = footnotes.compactMap { $0 }
            self.content = content()
        }

        var body: some View {
            faceDoor(VStack(alignment: .leading, spacing: 0) {
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
            }
            .dsRoomHeadCard()
            .dsRoomHeadPlacement())
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

    // MARK: - Pieces

    /// The lead, drawn. Public because a scoped head (Privacy Pools) stands its
    /// lead bare on the page above a switcher rather than inside a card; that
    /// head passes its `door` here and has no face-wide gesture, while `Head`
    /// applies both halves of its own door itself.
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
                Text(verbatim: sentence)
                    .dsText(.heading22)
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
                        .dsGlyph(11, weight: .regular)
                }
            } else {
                words
            }
        }

        private var words: some View {
            Text(verbatim: line.text)
                .dsText(line.tone == .quiet ? .label12 : .subhead13)
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
    /// A row is a door with ONE gesture (ruling 2026-07-16) and carries no
    /// presentation of its own (the half-open-then-close lesson). It lands as
    /// the `index`-th of its set, so the entrance narrates the model's order.
    struct Row<Measure: View>: View {
        let title: String
        var truncation: Text.TruncationMode = .tail
        let line: String
        var detail: String?
        var spoken: String?
        let index: Int
        let action: () -> Void
        let measure: Measure

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        init(title: String,
             truncation: Text.TruncationMode = .tail,
             line: String,
             detail: String? = nil,
             spoken: String? = nil,
             index: Int,
             action: @escaping () -> Void,
             @ViewBuilder measure: () -> Measure) {
            self.title = title
            self.truncation = truncation
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
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                        Text(verbatim: title)
                            .dsText(.body17)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                            .truncationMode(truncation)
                        Spacer(minLength: DS.Space.s2)
                        Text(verbatim: line)
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                    }
                    if let detail {
                        Text(verbatim: detail)
                            .dsText(.label12)
                            .foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    measure
                }
                .padding(.vertical, DS.Space.s1)
                .frame(maxWidth: .infinity, alignment: .leading)
                // A row is a door, so it is a 44pt target: a label, a line and a
                // 6pt bar measure shorter than a finger.
                .dsTapTarget()
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
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: name)
                            .dsText(.heading17)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        HStack(spacing: DS.Space.s1 + 2) {
                            if let stamp {
                                Text(verbatim: stamp)
                                    .dsText(.label11).fontWeight(.bold)
                                    .foregroundStyle(Color.fixed("#ffffff"))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(fill, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                            }
                            Text(verbatim: kind)
                                .dsText(.label12)
                                .foregroundStyle(DS.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: DS.Space.s2)
                    Text(verbatim: value)
                        .dsText(.price16)
                        .foregroundStyle(overdue ? DS.textPrimary : DS.textSecondary)
                        .monospacedDigit()
                }
                .padding(.vertical, DS.Space.s2)
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
        /// Whether `line` is news: secondary ink when it is, tertiary when not.
        let concerning: Bool
        let index: Int
        let action: () -> Void
        let mark: Mark
        let trailing: Trailing

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        init(name: String, flag: String?, line: String, concerning: Bool,
             index: Int, action: @escaping () -> Void,
             @ViewBuilder mark: () -> Mark,
             @ViewBuilder trailing: () -> Trailing) {
            self.name = name
            self.flag = flag
            self.line = line
            self.concerning = concerning
            self.index = index
            self.action = action
            self.mark = mark()
            self.trailing = trailing()
        }

        var body: some View {
            HStack(alignment: .center, spacing: DS.Space.s3) {
                mark
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: DS.Space.s2) {
                        Text(verbatim: name)
                            .dsText(.body17)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        if let flag {
                            Text(verbatim: flag)
                                .dsText(.label11).fontWeight(.bold)
                                .foregroundStyle(DS.attention)
                        }
                    }
                    Text(verbatim: line)
                        .dsText(.subhead13)
                        .foregroundStyle(concerning ? DS.textSecondary : DS.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: DS.Space.s2)
                trailing
            }
            .padding(.vertical, DS.Space.s2)
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
                        .dsText(.subhead13).fontWeight(.semibold)
                    if external {
                        Image(systemName: "arrow.up.right")
                            .dsGlyph(11, weight: .semibold)
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

extension DSRoomChassis.Head where Content == EmptyView {
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
         truncation: Text.TruncationMode = .tail,
         line: String,
         detail: String? = nil,
         spoken: String? = nil,
         index: Int,
         action: @escaping () -> Void) {
        self.init(title: title, truncation: truncation, line: line, detail: detail,
                  spoken: spoken, index: index, action: action) { EmptyView() }
    }
}

extension View {
    /// The head card's own surface: the inset, the full width and the widget
    /// rung. One definition, so a scoped head's cards (Privacy Pools) and every
    /// `DSRoomChassis.Head` are the same box.
    func dsRoomHeadCard() -> some View {
        padding(DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsWidgetSurface()
    }

    /// Where a head stands in the feed. `FeedScreen.insightSection` presents
    /// every head edge-to-edge on purpose, so the margin is the head's — the
    /// Altana head that ran flush to both screen edges (§488) is what happens
    /// when a card forgets it.
    func dsRoomHeadPlacement() -> some View {
        padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s2)
    }
}
