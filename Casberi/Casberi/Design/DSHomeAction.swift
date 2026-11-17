import SwiftUI

/// **HOME'S ACTS ARE ROUND BUTTONS (prd §1849, user, of four 26pt chips under
/// the card: "its very functional but not yet delightful"; of this row:
/// "great do it").** A glyph on a disc over one word, four across: Account,
/// Risks, Apps and the address's copy. The disc is 50pt, so the target
/// clears the floor the chips missed (§717).
///
/// **Grey discs, pink glyphs (§1252).** Move's face stays the one solid
/// button on Home. A disc changes only to say something: Risks takes the
/// attention hue and a count while a finding is unseen, and the copy turns
/// to the confirm hue and a check for a moment after it is pressed (§867).
struct DSHomeAction: View {
    enum Tone: Equatable {
        /// Nothing to say: the grey disc, the brand's glyph.
        case rest
        /// Something waits on you here.
        case attention
        /// What you just did landed.
        case done
    }

    let name: String
    let glyph: String
    var tone: Tone = .rest
    /// How many wait, on the disc's corner; nil draws none.
    var badge: Int? = nil

    static let disc: CGFloat = 50

    var body: some View {
        VStack(spacing: DS.Space.s1) {
            ZStack {
                Circle().fill(wash)
                Image(systemName: glyph)
                    .dsGlyph(.title)
                    .foregroundStyle(hue)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
            .frame(width: Self.disc, height: Self.disc)
            .overlay(alignment: .topTrailing) {
                if let badge, badge > 0 {
                    Text(verbatim: "\(badge)")
                        .dsText(.label12)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        // The page's own colour: black on the hue in dark,
                        // light on it in light.
                        .foregroundStyle(DS.page)
                        .padding(.horizontal, DS.Space.s1)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Capsule().fill(DS.attention))
                        .offset(x: DS.Space.s1, y: -DS.Space.s1)
                        .accessibilityHidden(true)
                }
            }
            Text(verbatim: name)
                .dsText(.label12)
                .foregroundStyle(word)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .animation(DS.Motion.standard, value: tone)
        .animation(DS.Motion.standard, value: name)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityValue(badge.map { Text(verbatim: "\($0)") } ?? Text(verbatim: ""))
        .accessibilityAddTraits(.isButton)
    }

    private var wash: Color {
        switch tone {
        case .rest: DS.fillFaint
        case .attention: DS.attention.opacity(0.22)
        case .done: DS.confirm.opacity(0.22)
        }
    }

    /// A glyph keeps the hue (§1004).
    private var hue: Color {
        switch tone {
        case .rest: DS.brandInk
        case .attention: DS.attention
        case .done: DS.confirm
        }
    }

    /// A word takes the ink (§1004).
    private var word: Color {
        switch tone {
        case .rest: DS.textPrimary
        case .attention: DS.attentionInk
        case .done: DS.confirmInk
        }
    }
}

/// **THE DAY, ON A PILL (prd §1849).** The balance's day under it, its words
/// in the day's ink on a wash of the same ink: the one fact on Home's card
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
