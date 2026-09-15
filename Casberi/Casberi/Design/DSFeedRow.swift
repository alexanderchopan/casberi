import SwiftUI

/// THE FEED ROW — one anatomy for every row a room draws (prd §744, 2026-09-15,
/// user: "awesome do it all", on the spec "one shape every row uses: picture on
/// the left, name and time, one line, maybe some tiles").
///
/// Before this the feed had twenty row structs, each written the day its source
/// landed. `feed-row-skeleton-audit.py` (§586) had found five of them agreeing
/// on a skeleton by accident; the other fifteen put the lead at 26, 36, 38, 44
/// or 56pt, the name at 12, 13 or 17pt, the picture on the left, the right or
/// under the name, and the count or the time wherever there was room. Scanned
/// down All, that read as nine different apps. The user's word was "vibecoded".
///
/// ANATOMY, top to bottom, and nothing else:
///
///     lead      26pt (`DS.Mark.row`): a source mark, or a person's face
///     name      17pt primary, up to `nameLines` · trailing slot on its baseline
///     line      12pt secondary — who, where, the count, the excerpt
///     below     tiles at 44pt (`DS.Mark.tile`), a post's words and media,
///               a reading's bars — anything that is the row's CONTENT
///
/// **The lead is always 26pt, so the text column has ONE left edge from the
/// top of a room to the bottom.** The user caught the one exception in the
/// mock before a line of this existed ("why doesn't the social post … have the
/// same indentation as the rest. it should"). A face is drawn at
/// `Face.rowCircle` inside the same frame, as `BandRow` always did.
///
/// **What a row may vary is WHAT it puts in the slots, never where they are.**
/// A post puts its words below; a token puts its price in the trailing slot; a
/// strip puts its tiles below. None of them moves the time, the lead or the
/// name.
///
/// FLAT BY LAW: a plain `HStack`/`VStack` of `Text`, no `AnyView`, no erasure.
/// This draws for every visible row of the app's hottest scroll, and the
/// first-frame stack overflow in CLAUDE.md was paid three times by depth.
struct DSFeedRow<Lead: View, Trailing: View, Below: View>: View {
    let name: String
    /// A title worth reading gets two; a label (a person, a token, a source)
    /// gets one.
    var nameLines: Int = 2
    /// The next event on a calendar room — the one place weight carries a fact.
    var emphasized = false
    /// A done reminder: tertiary and struck, as `BandRow` drew it.
    var done = false
    /// `BandRow`'s ripple: a retitle cross-fades, staggered down the run.
    var ripple = 0
    /// ONE `Text`, so a clause can carry its own ink (a source's legible hue,
    /// an attention word) without an `HStack` of siblings that SwiftUI squeezes
    /// one of into a one-word column — `WalletRow.subtitleText`'s lesson (§588).
    var line: Text? = nil
    var lineLines = 1
    @ViewBuilder var lead: Lead
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var below: Below

    static var leadSize: CGFloat { DS.Mark.row }

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            lead
                .frame(width: Self.leadSize, height: Self.leadSize)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Text(name)
                        .dsText(.body17)
                        .fontWeight(emphasized ? .semibold : .regular)
                        .foregroundStyle(done ? DS.textTertiary : DS.textPrimary)
                        .strikethrough(done, color: DS.textTertiary)
                        .lineLimit(nameLines)
                        .contentTransition(.opacity)
                        .animation(DS.Motion.standard.delay(Double(ripple % 8) * 0.045),
                                   value: name)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    trailing
                }
                if let line {
                    line
                        .dsText(.subhead12)
                        .foregroundStyle(done ? DS.textTertiary : DS.textSecondary)
                        .lineLimit(lineLines)
                }
                below
            }
        }
        .padding(.vertical, DS.Space.s2)
    }

}

/// THE LEAD FOR A ROW THAT COUNTS A KIND OF THING rather than showing one
/// (prd §763): a glyph on a faint 26pt disc — the disc the Readings rows and
/// `DevnetVerbRow` wear (§752b) — so a head's ranked rows and the wallet
/// family's rows share the feed row's leading column.
struct DSGlyphLead: View {
    let glyph: String
    /// Ink for a glyph that states a STATE (prd §767) — Settings' on-device
    /// lock, a saved key. Everything else stays primary.
    var tint: Color = DS.textPrimary
    /// Bump for one bounce (a milestone the row just crossed).
    var bounce = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(DS.fillFaint)
                .frame(width: DS.Mark.row, height: DS.Mark.row)
            Image(systemName: glyph)
                .accessibilityHidden(true)
                .dsGlyph(.caption, weight: .semibold)
                .foregroundStyle(tint)
                // A row that flips in place (Theme) swaps its glyph; a glyph
                // that never changes never transitions.
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace.downUp))
                .symbolEffect(.bounce, value: bounce)
        }
    }
}

/// The feed row's plain helpers, outside the generic so a call site names no
/// type parameters.
enum DSFeed {
    /// The line from whatever clauses a row has, joined the way every row
    /// joins them. Nil when there are none, so no row draws an empty line.
    static func line(_ parts: String?...) -> Text? {
        let kept = parts.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !kept.isEmpty else { return nil }
        return Text(kept.joined(separator: " · "))
    }
}

extension DSFeedRow where Below == EmptyView {
    init(name: String, nameLines: Int = 2, emphasized: Bool = false,
         done: Bool = false, ripple: Int = 0,
         line: Text? = nil, lineLines: Int = 1,
         @ViewBuilder lead: () -> Lead,
         @ViewBuilder trailing: () -> Trailing) {
        self.init(name: name, nameLines: nameLines, emphasized: emphasized,
                  done: done, ripple: ripple, line: line, lineLines: lineLines,
                  lead: lead, trailing: trailing, below: { EmptyView() })
    }
}

/// The trailing slot's "Live" — a stream on air, drawn where the time would be.
/// Two rows spelled it by hand.
struct DSFeedLive: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(DS.confirm).frame(width: 6, height: 6)
            Text("Live").dsText(.label12).foregroundStyle(DS.confirm)
        }
    }
}

/// A row's pictures under the name: at most three tiles at 44pt, 6pt apart
/// (prd §730). One view so a strip, a bundle and a single thing's art are the
/// same squares.
struct DSFeedTiles<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 6) { content }
            .padding(.top, DS.Space.s1)
    }
}
