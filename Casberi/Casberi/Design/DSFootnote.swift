import SwiftUI

/// **ONE EXPLAINING SENTENCE, DRAWN ONE WAY (prd §748, user: "one explaining
/// sentence per screen at most, and only if it says something the controls
/// don't", 2026-09-15).**
///
/// The only view for a sentence that EXPLAINS — under a control, between
/// blocks, in a list section's footer. A date, a count, a name or an amount is
/// data and is not drawn here; a status ("Couldn't read…", "Waiting…") is not
/// an explanation either.
///
/// It exists so the rule can be counted. `scripts/footnote-audit.py` fails a
/// screen file that draws more than one of these (or `DSSlabNote`, which
/// renders through this view) without a reasoned allowance, and fails an
/// explaining sentence drawn by hand in the tertiary ink at a footnote rung.
/// Before reaching for it, ask the audit's question: does the door, the
/// field, the label or the row above already say this? Then it goes.
///
/// Two sizes and no more, the house pattern (`DSEmptyState.Scale`):
/// - `.meta` — `subhead12`, the meta rung, under a row or inside a card.
/// - `.page` — `body17`, a list section's footer, where a page's words sit.
///
/// Inside an account page's act it is always `.page` (prd §729: the page's
/// words were set at the meta size on a page whose content is the words).
struct DSFootnote: View {
    enum Scale { case meta, page }

    let text: Text
    var scale: Scale = .meta
    var centered = false

    @Environment(\.accountAct) private var accountAct

    /// A literal is a `LocalizedStringResource`, not a `LocalizedStringKey`,
    /// so it can be resolved to a string and bound against an orphaned last
    /// word (`DSProse`) before it is drawn; Xcode extracts it the same way.
    init(_ key: LocalizedStringResource, scale: Scale = .meta, centered: Bool = false) {
        self.text = DSProse.text(key)
        self.scale = scale
        self.centered = centered
    }

    /// A sentence built at runtime (a ternary, a composed line): resolved and
    /// bound like a literal. Labelled, because an unlabelled `String` init
    /// would win every bare literal and stop Xcode extracting them.
    init(prose: String, scale: Scale = .meta, centered: Bool = false) {
        self.text = DSProse.text(resolving: prose)
        self.scale = scale
        self.centered = centered
    }

    init(_ text: Text, scale: Scale = .meta, centered: Bool = false) {
        self.text = text
        self.scale = scale
        self.centered = centered
    }

    var body: some View {
        text
            .dsText(accountAct || scale == .page ? .body17 : .subhead12)
            .foregroundStyle(DS.textTertiary)
            .multilineTextAlignment(centered ? .center : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }
}
