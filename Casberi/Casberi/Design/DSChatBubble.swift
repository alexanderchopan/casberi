import SwiftUI

/// One message of a conversation, as Messages draws it (prd §1213): yours on
/// the trailing edge in the tint (prd §1615; ink until then), theirs on the
/// leading edge in the faint fill.
/// The one shape that stands behind words outside a control, because a
/// conversation's turns are read by side and by fill before a word is read;
/// it lives here so no screen hand-rolls its own (`ds-template-audit.py`).
struct DSChatBubble: View {
    let text: AttributedString
    let fromSelf: Bool
    /// A message the Observer says was not delivered draws faded.
    var faded = false
    /// What a message that is not words carries (prd §1635): "photo",
    /// "waveform", drawn before its name inside the bubble.
    var glyph: String? = nil
    /// The run this bubble stands in (prd §1635): a bubble joined to the one
    /// above or below by the same sender tightens that corner on the
    /// sender's side, as Messages draws a run.
    var joinsAbove = false
    var joinsBelow = false
    /// A Feed row's bubble (prd §1642): it stands on the rows' text edge
    /// whoever sent it, the fill alone saying whose, and the row's tap opens
    /// the chat rather than selecting words.
    var onTextEdge = false

    init(text: String, fromSelf: Bool, faded: Bool = false) {
        self.init(attributed: AttributedString(text), fromSelf: fromSelf, faded: faded)
    }

    /// The Feed's one bubble for a chat (prd §1642).
    init(feedText text: String, fromSelf: Bool) {
        self.init(attributed: AttributedString(text), fromSelf: fromSelf)
        self.onTextEdge = true
    }

    /// Words with their links already painted (`ProseLinks.rendered`), so an
    /// address in a chat opens (prd §1580).
    init(attributed: AttributedString, fromSelf: Bool, faded: Bool = false,
         glyph: String? = nil, joinsAbove: Bool = false, joinsBelow: Bool = false) {
        self.text = attributed
        self.fromSelf = fromSelf
        self.faded = faded
        self.glyph = glyph
        self.joinsAbove = joinsAbove
        self.joinsBelow = joinsBelow
    }

    private static let round: CGFloat = 18
    private static let joined: CGFloat = 6

    private var shape: UnevenRoundedRectangle {
        let top = joinsAbove ? Self.joined : Self.round
        let bottom = joinsBelow ? Self.joined : Self.round
        return UnevenRoundedRectangle(
            topLeadingRadius: fromSelf ? Self.round : top,
            bottomLeadingRadius: fromSelf ? Self.round : bottom,
            bottomTrailingRadius: fromSelf ? bottom : Self.round,
            topTrailingRadius: fromSelf ? top : Self.round,
            style: .continuous)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            if let glyph {
                Image(systemName: glyph)
                    .dsGlyph(.body, weight: .regular)
                    .foregroundStyle(fromSelf ? Color.white.opacity(0.8) : DS.textSecondary)
                    .accessibilityHidden(true)
            }
            if onTextEdge {
                words.lineLimit(3)
            } else {
                words.textSelection(.enabled)
            }
        }
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, DS.Space.s2)
            .background(Self.fill(fromSelf: fromSelf), in: shape)
            .opacity(faded ? 0.55 : 1)
            .frame(maxWidth: 300, alignment: edge)
            .frame(maxWidth: .infinity, alignment: edge)
    }

    /// A bubble's fill: yours in the tint, theirs in the strong fill. The
    /// photo bubble (`ChatPhotoBubble`, prd §1660) wears the same.
    static func fill(fromSelf: Bool) -> Color {
        fromSelf ? DS.tint : DS.fillStrong
    }

    private var edge: Alignment { fromSelf && !onTextEdge ? .trailing : .leading }

    private var words: some View {
        Text(text)
            .dsText(.body17)
            .foregroundStyle(fromSelf ? Color.white : DS.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
