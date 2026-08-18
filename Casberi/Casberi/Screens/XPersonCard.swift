import SwiftUI

/// YOUR YEARS WITH ONE PERSON (2026-08-18, prd §395) — the person room's head
/// for an X handle.
///
/// `XRoomCard`'s anatomy at one person's scale: kicker, the finding as a
/// sentence, the span as a strip, then the three ways they appear in your
/// archive. What differs is the ROWS — that card ranks years against each
/// other, this one names what the counts are made of, because "214 replies and
/// 40 likes" is the fact and which year held most of them is the shape.
///
/// ## Silent years are drawn, faint
///
/// `XRoom`'s ruling, and it says more here: the two years you stopped talking
/// are most of what this relationship looks like.
///
/// ## No colour, no rate, no streak
///
/// One hue, one scale, and nothing derived. The card states three counts and a
/// span, all of them things the corpus holds — the `AddressConnections` ruling
/// (keep the analysis factual) applied where the temptation to editorialise
/// about somebody's friendships is at its highest.
///
/// ## Liveness
///
/// Stores no `Thing` — only value types out of `XPerson`, filtered at the
/// boundary by `XPersonSource`.
///
/// FLAT BY LAW: a plain VStack, no generic `Widget`/`Row` mount.
struct XPersonCard: View {
    let person: XPerson
    let handle: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let mark = DS.legibleCardFill(for: "X")

    /// The busiest year's count — every bar's full width, so the strip and the
    /// rows below it are on ONE scale and cannot disagree.
    private var top: Int { XPerson.peak(person) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "X"))
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(Self.mark)

            Text(XPerson.headline(person, handle: SocialThread.shortHandle(handle)))
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s2)

            Text(XPerson.note(person))
                .dsText(.subhead13)
                .foregroundStyle(DS.textSecondary)
                .padding(.top, DS.Space.s1)

            if person.span > 1 {
                yearStrip.padding(.top, DS.Space.s3)
            }

            ForEach(Array(parts.enumerated()), id: \.element.0) { index, part in
                countRow(label: part.0, count: part.1, index: index)
                    .chartArrival(index: index, reduceMotion: reduceMotion)
            }
            .padding(.top, DS.Space.s3)
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsWidgetSurface()
    }

    /// The three memberships, largest first, and a zero is DROPPED rather than
    /// drawn: "0 liked" on somebody whose likes simply have no author yet
    /// (`fetchFaces` names them, and until it runs every liked row is
    /// anonymous) would read as "you never liked anything of theirs", which is
    /// a claim this corpus cannot make.
    private var parts: [(String, Int)] {
        [(String(localized: "Replies you sent"), person.replies),
         (String(localized: "Posts naming them"), person.mentions),
         (String(localized: "Their posts you liked"), person.liked)]
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
    }

    // MARK: - The span

    /// A column per YEAR, oldest at the left, ends labelled — `XRoomCard`'s
    /// strip, deliberately identical, because it is the same object at a
    /// different scope and two spellings of one chart would read as two
    /// different measurements.
    private var yearStrip: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(person.years) { year in
                    Capsule(style: .continuous)
                        .fill(Self.mark.opacity(year.total == 0 ? 0.18 : 0.85))
                        // Floored, so a year you spoke to them once is a
                        // visible column rather than a sub-pixel nothing.
                        .frame(height: max(4, 38 * XPerson.share(year.total, of: top)))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 38, alignment: .bottom)
            .chartWipe(reduceMotion: reduceMotion)
            if let first = person.years.first, let last = person.years.last {
                HStack {
                    Text(verbatim: XPerson.plainYear(first.year))
                    Spacer(minLength: DS.Space.s2)
                    Text(verbatim: XPerson.plainYear(last.year))
                }
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(XPerson.note(person)))
    }

    // MARK: - Rows

    private func countRow(label: String, count: Int, index: Int) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text(label)
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.s2)
                Text(count.formatted())
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .monospacedDigit()
            }
            ShareBar(fraction: XPerson.share(count, of: max(person.total, 1)),
                     index: index,
                     reduceMotion: reduceMotion)
        }
        .padding(.vertical, DS.Space.s1)
        .accessibilityElement()
        .accessibilityLabel(Text("\(label), \(count)"))
    }
}
