import SwiftUI

/// **HOME'S CARDS ARE BUTTONS (prd §1807, user: "i think we don't do tiles we
/// do cards like buttons basically and they can be larger").** Home is the
/// balance, the map of what you hold, and six places you go from it. Each
/// card is one control: its glyph and its state on the top edge, its name at
/// the bottom, the whole surface the tap.
///
/// The surface is the flat well (`dsWell`), one faint fill with its whole
/// shape showing. The elevated ink card was tried first and lost its bottom
/// edge on the black page, so the name read as falling off the card (user,
/// 2026-11-14: "it looks like their title is falling off them").
enum DSHomeCardMetrics {
    /// One card's height; two columns of them stand under the map.
    /// 88pt, so three rows, the map and the bar share an iPhone 17 Pro's
    /// screen with nothing to scroll.
    static let height: CGFloat = 88

    /// **THE CARDS TAKE THE SCREEN THEY ARE GIVEN (prd §1808, user: "we can
    /// have the cards on the home screen fill more space").** 88pt was sized
    /// for the smallest current phone and left a taller one with air under
    /// the third row. Three rows share whatever a taller screen adds over
    /// 874pt (an iPhone 17 Pro), and its spare 24pt; never under 80, where a
    /// name and a figure stop fitting, never over 132.
    static func height(screen: CGFloat) -> CGFloat {
        min(132, max(80, height + ((screen - 874 + 24) / 3).rounded(.down)))
    }
    /// The air between cards, both ways.
    /// `s3` since the first build (user, 2026-11-14: "they need a bit more
    /// spacing too gaps between"): at `s2` the rows read as one block.
    static let gap: CGFloat = DS.Space.s3
}

struct DSHomeCard<Lead: View>: View {
    let name: String
    /// What the card trails on its top edge: a count, a state word, a move.
    var figure: String? = nil
    /// A status word takes its ink (prd §1004); a plain count is secondary.
    var figureTone: Color = DS.textSecondary
    /// A small drawing in the figure's place, where a picture says it
    /// better than a word (Holdings' line); drawn only with no figure.
    var trailing: AnyView? = nil
    /// The card's height; Home passes the screen's share (`height(screen:)`).
    var height: CGFloat = DSHomeCardMetrics.height
    let act: () -> Void
    @ViewBuilder var lead: () -> Lead

    var body: some View {
        Button {
            DSHaptic.selection()
            act()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: DS.Space.s2) {
                    lead()
                    Spacer(minLength: DS.Space.s2)
                    if let figure {
                        Text(verbatim: figure)
                            .dsText(.body17)
                            .monospacedDigit()
                            .foregroundStyle(figureTone)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .contentTransition(.numericText())
                    } else if let trailing {
                        trailing.accessibilityHidden(true)
                    }
                }
                Spacer(minLength: DS.Space.s2)
                Text(verbatim: name)
                    .dsText(.heading20)
                    .foregroundStyle(DS.headInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .dsWell(cornerRadius: DS.Radius.widget)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        }
        .buttonStyle(PressSpring())
        .dsHover()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [name, figure].compactMap { $0 }.joined(separator: ". ")))
        .accessibilityAddTraits(.isButton)
    }
}

extension DSHomeCard where Lead == AnyView {
    /// A card led by a glyph in the glyph's ink (prd §1252: pink glyphs).
    init(glyph: String, glyphTone: Color = DS.brandInk, name: String, figure: String? = nil,
         figureTone: Color = DS.textSecondary, trailing: AnyView? = nil,
         height: CGFloat = DSHomeCardMetrics.height, act: @escaping () -> Void) {
        self.init(name: name, figure: figure, figureTone: figureTone, trailing: trailing, height: height, act: act) {
            AnyView(Image(systemName: glyph)
                .dsGlyph(.body)
                .foregroundStyle(glyphTone)
                .accessibilityHidden(true))
        }
    }
}
