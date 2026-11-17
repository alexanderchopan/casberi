import SwiftUI

/// **HOME'S DOORS ARE WORDS (prd §1850, user, of the bar of buttons: "the
/// glass is probably totally all wrong bc those are actual pages someone
/// goes to"; of this: "the chevrons are a great touch").** Account, Risks and
/// Apps are places, so each is drawn as the balance over them already is: a
/// word and a grey chevron (§1815, §1838). No disc, no bar, no glyph.
///
/// A door changes only to say something: Risks takes the attention ink and
/// a count while a finding is unseen, and Account takes it while its setup
/// waits (§1004: the word takes the ink, the chevron keeps the hue).
struct DSHomeDoor: View {
    enum Tone: Equatable {
        /// Nothing to say: a white word, a grey chevron.
        case rest
        /// Something waits on you behind this door.
        case attention
    }

    let name: String
    var tone: Tone = .rest
    /// How many wait behind it, after the word; nil draws none.
    var count: Int? = nil

    var body: some View {
        HStack(spacing: DS.Space.s1) {
            Text(verbatim: name)
            if let count, count > 0 {
                Text(verbatim: "\(count)").monospacedDigit()
            }
            Image(systemName: "chevron.right")
                .dsGlyph(.tick, weight: .bold)
                .foregroundStyle(tone == .attention ? DS.attention : DS.textSecondary)
                .padding(.leading, 2)
                .accessibilityHidden(true)
        }
        .dsText(.body17)
        .fontWeight(.bold)
        .foregroundStyle(tone == .attention ? DS.attentionInk : DS.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(minHeight: DS.Hit.min)
        .contentShape(Rectangle())
        .animation(DS.Motion.standard, value: tone)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityValue(count.map { Text(verbatim: "\($0)") } ?? Text(verbatim: ""))
        .accessibilityAddTraits(.isButton)
    }
}

/// **THE FEED'S SECTIONS, AS CIRCLES (prd §1850, over §1843's jump chips).**
/// One circle a section standing on the page, its word under it: Needs you
/// wears how many wait, the Wallet its glyph, and a category the mark of the
/// app whose row leads it. A circle jumps to its section; none is lit and
/// none wears a ring (user: "the circles shouldn't have rings b/c they
/// always are new stuff").
struct DSHomeCircle<Face: View>: View {
    let name: String
    var tone: DSHomeDoor.Tone = .rest
    @ViewBuilder var face: Face

    var body: some View {
        VStack(spacing: DS.Space.s2) {
            face
                .frame(width: DSHomeCircleMetrics.face, height: DSHomeCircleMetrics.face)
                .clipShape(Circle())
                .accessibilityHidden(true)
            Text(verbatim: name)
                .dsText(.label12)
                .foregroundStyle(tone == .attention ? DS.attentionInk : DS.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: DSHomeCircleMetrics.column)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityAddTraits(.isButton)
    }
}

enum DSHomeCircleMetrics {
    /// The circle, and the column its word may fill.
    static let face: CGFloat = DS.Mark.hero
    static let column: CGFloat = 68
}

/// How many wait, on the attention wash: Needs you's face.
struct DSHomeCircleCount: View {
    let count: Int

    var body: some View {
        ZStack {
            Circle().fill(DS.attention.opacity(0.22))
            Text(verbatim: "\(count)")
                .dsText(.heading24)
                .monospacedDigit()
                .foregroundStyle(DS.attentionInk)
                .contentTransition(.numericText())
        }
    }
}

/// A glyph on the quiet wash: the Wallet's face, and a category's while no
/// app of it has a mark to show.
struct DSHomeCircleGlyph: View {
    let glyph: String

    var body: some View {
        ZStack {
            Circle().fill(DS.fillFaint)
            Image(systemName: glyph)
                .dsGlyph(.title)
                .foregroundStyle(DS.brandInk)
        }
    }
}

/// **THE DAY, ON A PILL (prd §1849).** The balance's day under it, its words
/// in the day's ink on a wash of the same ink: the one fact on Home's head
/// that moves, set apart from the two figures under it.
struct DSDayPill: View {
    let words: String
    let ink: Color

    var body: some View {
        Text(verbatim: words)
            .dsText(.body17)
            .fontWeight(.semibold)
            .monospacedDigit()
            .foregroundStyle(ink)
            .lineLimit(1)
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, 3)
            .background(Capsule().fill(ink.opacity(0.16)))
            .contentTransition(.numericText())
    }
}
