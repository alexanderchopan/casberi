import SwiftUI

/// One message of a conversation, as Messages draws it (prd §1213): yours on
/// the trailing edge in ink, theirs on the leading edge in the faint fill.
/// The one shape that stands behind words outside a control, because a
/// conversation's turns are read by side and by fill before a word is read;
/// it lives here so no screen hand-rolls its own (`ds-template-audit.py`).
struct DSChatBubble: View {
    let text: AttributedString
    let fromSelf: Bool
    /// A message the Observer says was not delivered draws faded.
    var faded = false

    init(text: String, fromSelf: Bool, faded: Bool = false) {
        self.init(attributed: AttributedString(text), fromSelf: fromSelf, faded: faded)
    }

    /// Words with their links already painted (`ProseLinks.rendered`), so an
    /// address in a chat opens (prd §1580).
    init(attributed: AttributedString, fromSelf: Bool, faded: Bool = false) {
        self.text = attributed
        self.fromSelf = fromSelf
        self.faded = faded
    }

    var body: some View {
        Text(text)
            .dsText(.body17)
            .foregroundStyle(fromSelf ? DS.surfaceSheet : DS.textPrimary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, DS.Space.s2)
            .background(fromSelf ? DS.textPrimary : DS.fillStrong,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(faded ? 0.55 : 1)
            .frame(maxWidth: 300, alignment: fromSelf ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: fromSelf ? .trailing : .leading)
    }
}
