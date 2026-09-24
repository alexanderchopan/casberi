import SwiftUI

/// THE LEAD'S BODY — what stands between a lead's statement and its foot
/// (prd §772).
///
/// **The defect this closes.** §760 gave every room's lead one height and §766
/// gave it three zones — a statement, a body, and a foot pinned to the bottom —
/// on the rule that "nothing in it is air it could honestly fill". The body
/// zone then had exactly ONE filler: `thing.summary`, the field this app treats
/// as display copy. Most of the corpus has no summary. An X notice has none, a
/// screenshot has none, a chat has none — so the ruling that was meant to end
/// the air only ended it for articles, and every other kind drew a sentence and
/// 176pt of black (user, 2026-09-15, over an X notice naming eight people:
/// "we made it so there wouldn't be any air on the leads. so for like this,
/// could you show more avatars or something? We need some way for this type of
/// lead", then on the scope: "any lead with air needs a solution").
///
/// **A LADDER, not a special case.** The rungs are ordered by how much each
/// says about the thing, and the lead draws every one it has until the box is
/// full — so a notice naming a cast draws the cast, an article draws its lede,
/// a contact draws its parts, and a thing with none of them falls through to
/// the rung below rather than to black. The order is in
/// `FeedLedeCard.bodyRungs`; the drawings are here, one view per rung, because
/// a rung that only the cover can draw is a rung the next lead to want it will
/// draw a second time (§489).
///
/// **Nothing here invents anything.** Every rung draws a fact the thing already
/// carries, and a rung with no fact draws nothing at all — never a placeholder,
/// never a shape standing in for a picture we do not have (`AssetMark`'s
/// no-invented-hue rule, and §83's on fake status). A lead that reaches the
/// bottom of the ladder with nothing has genuinely nothing to say, and §772's
/// answer there is that it stops claiming the height.
enum DSLeadBody {

    /// The air under the statement, before the body. `s3`, the head's own note
    /// gap, so a lead's body starts where a head's notes start.
    static let gap: CGFloat = DS.Space.s3
}

// MARK: - The cast (rung 1)

/// THE PEOPLE A LEAD'S SENTENCE NAMES, as faces (prd §772).
///
/// "New post notifications for Roman Storm and 7 others" is a sentence about
/// eight people, and until this the lead drew one of them — `authorAvatarURL`,
/// at 36pt, in the eyebrow. The other seven were in the same response
/// (`template.from_users` is an array) and were dropped at parse time by a
/// ruling written for the ROW's 26pt disc (§707). `ThingCast` keeps them now;
/// this draws them.
///
/// **A shelf, not a pile.** `FacePile`'s overlapping ring shape is right where
/// faces are a proof detail beside a line of text ("who just arrived", 20pt) and
/// wrong here: this is the lead's whole body, the faces are the payload, and
/// overlapping them hides most of every face but the first to save width the
/// lead is not short of. `DS.Face.shelf` is the token's own name for exactly
/// this — "a horizontal face shelf" — and the rung above `list` is what makes
/// the body read as the lead's subject rather than as a row of thumbnails.
///
/// **As many as the WIDTH holds, and the rest counted.** The capacity is
/// measured, never a constant: an SE and a Pro Max hold different numbers, and
/// a hard-coded five either wastes a Pro Max's width or overflows an SE's. What
/// cannot be shown is counted in a final circle ("+3") — and only when there IS
/// a remainder, because `+0` is §83's dead control drawn in a circle.
///
/// **A face with no picture is its first letter**, which is §753's own ruling
/// for exactly this case ("a face with no picture shows … a name's first letter
/// inside the circle"). Not the bridge glyph: a shelf of eight identical X
/// marks says nothing about eight different people, and reads from a screenshot
/// like a parse that failed.
struct DSLeadCast: View {

    let roll: ThingCastRoll
    /// The seat, for the fallback mark on a face whose URL turns out dead.
    let source: String
    /// **A TIER, defaulted to one** — `face-ramp-audit.py` resolves a face's
    /// size from the declaration it comes from, and a bare number resolves to
    /// nothing. `shelf` is the rung for a horizontal row of faces.
    var size: CGFloat = DS.Face.shelf
    /// **How many rows the shelf may take (prd §905).** One is the shelf as
    /// §772 drew it. The cover's large tier passes two, so a ten-person notice
    /// shows ten faces rather than four and a "+6" — the faces are the lead's
    /// payload, and a second row of them is content the box was holding air
    /// for. The size never changes with the rows: a face stays on `shelf`, so
    /// `face-ramp-audit.py`'s one rung per shelf still holds.
    var rows: Int = 1

    /// The air between faces. Tight on purpose: the shelf reads as one object
    /// (a group of people) rather than as N objects in a row.
    private static let spacing: CGFloat = DS.Space.s2

    /// How many cells a width holds, floored at one so a narrow box draws a
    /// face rather than nothing.
    private func capacity(in width: CGFloat) -> Int {
        guard width > 0 else { return 1 }
        let cell = size + Self.spacing
        return max(Int((width + Self.spacing) / cell), 1)
    }

    /// **THE NARROWEST ROW, declared (prd §905).** How many cells the shelf is
    /// sure of on the narrowest phone: at 375pt the cover's inner width is
    /// 311 (the row inset and the well's own padding off each side), and four
    /// `shelf` cells with their spacing are 254. The ROWS the shelf reserves
    /// are counted at this figure, before any width is read, so the frame is
    /// decided the way §772 decides everything about the lead — from the
    /// model, never from a measurement that could resolve two ways on two
    /// passes and leave the fit flickering. The real width, read below, only
    /// decides how many cells share each row.
    private static let narrowestPerRow = 4

    /// The rows the shelf takes for this cast and this `rows` cap: the cells
    /// it has, at the narrowest row, capped. Width-independent, so the frame
    /// below and the plan inside agree by construction.
    private var rowsDrawn: Int {
        let cells = roll.members.count + (roll.total > roll.members.count ? 1 : 0)
        let needed = Int((Double(cells) / Double(Self.narrowestPerRow)).rounded(.up))
        return min(max(needed, 1), max(rows, 1))
    }

    /// The faces to draw, the count after them, and the cells per row —
    /// ONE arithmetic for every row, so the rows come out even.
    ///
    /// The counter takes a cell of its own, so the arithmetic asks for one
    /// fewer face whenever there will be one — otherwise the shelf fills the
    /// width with faces and the "+N" falls off the edge, which is the one
    /// failure that loses the count rather than a face.
    ///
    /// The cells per row are the fewest that still fit the reserved rows, so
    /// five cells on two rows draw three and two rather than five and none;
    /// and they never exceed what the width holds, so nothing falls off the
    /// edge. Because the width holds at least `narrowestPerRow` on every
    /// phone, the rows drawn are exactly `rowsDrawn` — the frame never
    /// reserves a row the shelf leaves empty.
    private func plan(width: CGFloat) -> (shown: Int, rest: Int, perRow: Int) {
        let holds = capacity(in: width)
        let room = holds * rowsDrawn
        let shownIfCounted = max(room - 1, 1)
        let needsCounter = roll.members.count > room
            || roll.remainder(afterShowing: min(roll.members.count, room)) > 0
        let shown = needsCounter ? min(shownIfCounted, roll.members.count)
                                 : min(room, roll.members.count)
        let rest = roll.remainder(afterShowing: shown)
        let cells = shown + (rest > 0 ? 1 : 0)
        let even = Int((Double(cells) / Double(rowsDrawn)).rounded(.up))
        return (shown, rest, max(min(holds, even), 1))
    }

    /// The shelf's height: its rows at `size`, with the spacing between.
    private var height: CGFloat {
        CGFloat(rowsDrawn) * size + CGFloat(max(rowsDrawn - 1, 0)) * Self.spacing
    }

    var body: some View {
        GeometryReader { geo in
            let p = plan(width: geo.size.width)
            let cells: [Cell] = roll.members.prefix(p.shown).map { Cell.face($0) }
                + (p.rest > 0 ? [Cell.counter(p.rest)] : [])
            VStack(alignment: .leading, spacing: Self.spacing) {
                ForEach(0..<rowsDrawn, id: \.self) { row in
                    HStack(spacing: Self.spacing) {
                        ForEach(Array(cells.dropFirst(row * p.perRow).prefix(p.perRow).enumerated()),
                                id: \.offset) { _, cell in
                            switch cell {
                            case .face(let member): face(member)
                            case .counter(let rest): counter(rest)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(width: geo.size.width, height: height, alignment: .topLeading)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// One slot on the shelf.
    private enum Cell {
        case face(ThingCastMember)
        case counter(Int)
    }

    @ViewBuilder private func face(_ member: ThingCastMember) -> some View {
        if let url = member.avatarURL, !url.isEmpty {
            RemoteThumb(urlString: url, size: size, fallback: source, circular: true)
        } else {
            Text(verbatim: member.handle.first.map { String($0).uppercased() } ?? "")
                .dsText(.heading24)
                .foregroundStyle(DS.textSecondary)
                .frame(width: size, height: size)
                .background(Circle().fill(DS.fillFaint))
        }
    }

    /// The remainder, in a face-shaped cell so the shelf's rhythm holds. Quiet
    /// ink and a faint fill: it is a count, not a person, and a filled circle
    /// among portraits would read as the loudest member of the cast.
    private func counter(_ rest: Int) -> some View {
        Text(verbatim: "+\(rest)")
            .dsText(.label12)
            .foregroundStyle(DS.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: size, height: size)
            .background(Circle().fill(DS.fillFaint))
    }

    /// What VoiceOver hears — names, never "eight circles". The remainder is
    /// spoken as a count because that is what it is.
    ///
    /// **The remainder is counted against the whole cast, not against what was
    /// named.** `handle` is never empty by `ThingCast.record`'s own rule, but
    /// filtering after `prefix(3)` would still be the bug `SocialLikeRoll.line`
    /// spells out: drop a member from the three and the count of "others" has
    /// to grow by one, or the shelf speaks a total that is short. So the names
    /// are filtered FIRST and the remainder is taken from `total`.
    ///
    /// **And one other is "1 other".** `SocialLikeRoll.line` branches for exactly
    /// this, and an accessibility label is the one place a plural bug is read
    /// out loud rather than seen.
    private var spoken: String {
        let usable = roll.members.map(\.handle).filter { !$0.isEmpty }
        let named = Array(usable.prefix(3))
        guard !named.isEmpty else { return "" }
        let rest = max(roll.total - named.count, 0)
        let lead = named.joined(separator: ", ")
        guard rest > 0 else { return lead }
        if rest == 1 { return String(localized: "\(lead) and 1 other") }
        return String(localized: "\(lead) and \(rest) others")
    }
}

// MARK: - The post a notice is about (rung 2)

/// THE POST A LEAD'S THING IS ABOUT, drawn flat (prd §772).
///
/// `SocialQuoteCard` has drawn `thing.quote` in the ROW since 2026-07-16 and in
/// the SHEET since §704, and the cover — the biggest drawing of the same record
/// in the app — never drew it at all. So a notice whose entire reason for
/// existing is a post showed the notice's sentence and not one word of the post,
/// on the one surface with room for both.
///
/// **Flat, and that is the whole difference from `SocialQuoteCard`.** That card
/// is `dsWell` — correct inside a row, which stands on nothing (§749), and wrong
/// inside a lead, which since §766 IS a well. A well inside a well is the plate-
/// on-a-plate §759 spent a pass deleting, and it would be the only one left in
/// the app. Same anatomy, same fields, no ground: a badge face, the handle, the
/// words in the quiet tier.
struct DSLeadQuote: View {

    let card: SocialCard
    let source: String
    /// How many lines the words may take. The lead's fit ladder sets it — a
    /// cover with a cast above this has fewer to give than one without.
    var lines: Int = 4
    /// **A TIER** (`face-ramp-audit.py`) — `badge` is the rung for a face
    /// beside dense inline text, which is what the handle is.
    var faceSize: CGFloat = DS.Face.badge

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(spacing: DS.Space.s2) {
                if let avatar = card.avatarURL, !avatar.isEmpty {
                    RemoteThumb(urlString: avatar, size: faceSize,
                                fallback: source, circular: true)
                } else {
                    BridgeIcon(name: source, size: faceSize, circular: true)
                }
                // `verbatim:` — a handle is data, never a string to localize.
                Text(verbatim: "@\(SocialThread.shortHandle(card.handle))")
                    .dsText(.subhead12)
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            // A WORDLESS post is a real card, not a broken one (prd §704): a
            // photo-only post carries a handle and pictures and no sentence, and
            // an empty `Text` here draws a blank line under the face that reads
            // as a failed fetch.
            if !card.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(card.text)
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(lines)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Whether a card is worth a rung at all — a handle with neither words nor
    /// a face is a stranger's name on a line of its own, which says less than
    /// the rung under it.
    static func draws(_ card: SocialCard) -> Bool {
        !card.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(card.avatarURL?.isEmpty ?? true)
    }
}

// MARK: - The thing's own parts (rung 4)

/// THE STRUCTURED PARTS A THING LANDED WITH, as lines (prd §772).
///
/// `ThingFact` exists because §365 found every Life bridge joining its facts
/// into a display string at ingest and throwing the parts away. The sheet draws
/// them; the lead did not, so a contact, a calendar event, a HomeKit accessory
/// and a workout — every kind whose whole content IS its parts — covered a room
/// with a name and nothing else.
///
/// **Label and value on one line, the label quiet.** Not the sheet's table:
/// a lead is a glance, and a two-column table inside a 316pt box that also holds
/// a statement and a foot is a screen inside a screen. Not tappable either —
/// the cover is one button (`ledeListRow`), and a control inside a button is the
/// §83 dead control in its most literal form.
///
/// `.metric` and `.state` facts lead, because a number and a live word are what
/// a glance is for; the rest follow in the bridge's own order.
struct DSLeadFacts: View {

    let facts: [ThingFact]
    /// How many lines the lead can spare. Set by the fit ladder.
    var limit: Int = 3

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            ForEach(Array(Self.ranked(facts).prefix(limit).enumerated()), id: \.offset) { _, fact in
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Text(verbatim: fact.label)
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                    Text(verbatim: fact.value)
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A number and a live state first, then the bridge's order — a stable sort,
    /// so two facts of one kind keep the order the bridge stated them in.
    static func ranked(_ facts: [ThingFact]) -> [ThingFact] {
        let lead = facts.filter { $0.action == .metric || $0.action == .state }
        let rest = facts.filter { $0.action != .metric && $0.action != .state }
        return lead + rest
    }
}

// MARK: - What the thing is filed under (rung 5)

/// THE THING'S OWN TAGS, as stamps (prd §772).
///
/// The last rung with anything to draw, and deliberately the quietest: a tag
/// says what a thing is filed under, which is less than what it says. It is
/// here because it is TRUE of nearly everything — a room's cover almost always
/// has tags even when it has no summary, no cast, no quote and no parts — so it
/// is what keeps the ladder from ending in air for the ordinary case.
///
/// **Stamps, not chips (§746).** A chip is a choice and a stamp is a fact, and
/// nothing here is choosable: the cover is one button, and a tappable tag inside
/// it could not be tapped.
struct DSLeadTags: View {

    let tags: [String]
    var limit: Int = 4

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            ForEach(Array(tags.prefix(limit).enumerated()), id: \.offset) { _, tag in
                DSStamp(word: tag, weight: .quiet)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
