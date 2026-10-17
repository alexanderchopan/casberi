import SwiftUI

/// THE FIRST BOX: "START WITH ANY OF THESE" (prd §1314, user: "start here
/// in the box: LOVE IT", "if they do one let it clear and not be below
/// the box", "the user may think it is a checklist … like 'start with
/// any of these'"). Eight zeros read as a report card on day one. Until
/// anything arrives the box offers four ways in as Settings' rows (user,
/// of three layouts: "C is more purposefully designed. what would apple
/// do"): glyph, name, a grey value, the plus, A–Z so none is first.
///
/// **ONE BOX, TWO PLACES (prd §1365, user: "ok", of the Feed's mockup).**
/// Library's box and the empty Feed's box are this view, so the two cannot
/// drift. The Feed's carries the day above it (`dated`). Each host decides
/// what a way in opens and when the box gives way.
struct StartWaysIn: View {
    enum Way { case app, calendar, subscription, wallet }

    /// The day, on the Feed, where the box stood for the day before.
    var dated: Text? = nil
    let pick: (Way) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            if let dated {
                dated.dsText(.subhead12).foregroundStyle(DS.textSecondary)
                    .padding([.top, .horizontal], DS.Space.s2)
            }
            Text("Start with any of these").dsText(.heading20).foregroundStyle(DS.textPrimary)
                .padding(dated == nil ? [.top, .horizontal] : [.horizontal], DS.Space.s2)
            // Settings' row grammar (user: "what would apple do"): a glyph in
            // one column, the name, a grey value, the plus. A–Z, as every
            // room's tiles read, so no row is the first step. The rows share
            // the box evenly; it keeps its one size.
            VStack(spacing: 0) {
                row(String(localized: "App"), glyph: "square.grid.2x2",
                    value: String(localized: "Your apps"),
                    verb: String(localized: "Add an app")) { pick(.app) }
                row(String(localized: "Calendar"), glyph: "calendar",
                    value: String(localized: "Your events"),
                    verb: String(localized: "Add a calendar")) { pick(.calendar) }
                row(String(localized: "Subscription"), glyph: SubscriptionWords.planGlyph,
                    value: String(localized: "What you pay"),
                    verb: SubscriptionWords.track) { pick(.subscription) }
                row(String(localized: "Wallet"), glyph: "wallet.bifold",
                    value: String(localized: "Any address"),
                    verb: String(localized: "Follow a wallet")) { pick(.wallet) }
            }
            .frame(maxHeight: .infinity)
        }
        // The counts' own well and one size: the box is the box, whatever
        // it holds (top-card-fixed-size rule).
        .padding(DS.Space.s2)
        .frame(maxWidth: .infinity, minHeight: DSRoomChassis.leadHeight,
               maxHeight: DSRoomChassis.leadHeight, alignment: .topLeading)
        .dsWell(cornerRadius: DS.Radius.widget)
    }

    /// One way in, the whole row one button: the plus says what it does,
    /// as it will on the count this becomes.
    private func row(_ label: String, glyph: String, value: String, verb: String,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s3) {
                Image(systemName: glyph)
                    .dsGlyph(.body, weight: .regular)
                    .foregroundStyle(DS.brandInk)
                    .frame(width: DS.Hit.min / 1.5)
                Text(label).dsText(.body17).foregroundStyle(DS.textPrimary).lineLimit(1)
                Spacer(minLength: DS.Space.s2)
                Text(value).dsText(.body17).foregroundStyle(DS.textSecondary).lineLimit(1)
                Image(systemName: "plus")
                    .dsGlyph(.body, weight: .regular)
                    .foregroundStyle(DS.brandInk)
            }
            .padding(.horizontal, DS.Space.s2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .accessibilityLabel(Text(verb))
    }
}
