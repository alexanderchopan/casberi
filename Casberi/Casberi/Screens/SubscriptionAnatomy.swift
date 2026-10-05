import SwiftUI

/// **ONE ANATOMY FOR THE TWO SUBSCRIPTIONS TILES.** The Wallet lists what
/// charges you and Day what writes to you (prd §1111): one idea in two
/// rooms, so one row and one sheet, composed by both.
///
/// The sheet, top to bottom:
///   1. the face and the name (`heading24`);
///   2. ONE statement — the Wallet's price and its cadence word, Day's how
///      often it writes — with a note under it when something changed;
///   3. the facts, in one order in both rooms: when (renews / last one),
///      since, how much so far (paid / mails), who (pays with / from),
///      found in;
///   4. the doors: this service's other pages first (`ServiceLinks`), then
///      the way out, which reads "<Verb> on <host>" in both;
///   5. the one sentence saying what Casberi will not do for you;
///   6. whatever only one room has (Day's recent mail).

/// One fact line: a label, and its value at the trailing edge.
struct SubscriptionFact: Identifiable {
    let label: String
    let value: String
    var id: String { label }

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
}

/// One door under the facts, drawn as a `DSDoorRow`.
struct SubscriptionDoor: Identifiable {
    let id: String
    let icon: String
    let title: Text
    var role: ButtonRole? = nil
    let act: () -> Void
}

/// The sheet's one statement: a figure, the word that follows it on its
/// baseline, and a note under both in the attention ink.
struct SubscriptionStatement {
    let figure: String
    var word: String? = nil
    var note: Text? = nil
}

/// The page both sheets compose. The caller owns the scroll and the sheet's
/// ground, so "no such subscription any more" still draws a solid sheet.
struct SubscriptionPage<Tail: View>: View {
    let name: String
    let statement: SubscriptionStatement?
    let facts: [SubscriptionFact]
    let doors: [SubscriptionDoor]
    @ViewBuilder var tail: Tail

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            HStack(spacing: DS.Space.s3) {
                SubscriptionFace(name: name, size: DS.Face.rowCircle)
                Text(verbatim: name)
                    .dsText(.heading24).foregroundStyle(DS.textPrimary)
                    .lineLimit(2)
            }
            if let statement {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                        Text(verbatim: statement.figure)
                            .dsText(.price40).monospacedDigit().foregroundStyle(DS.textPrimary)
                        if let word = statement.word {
                            Text(verbatim: word).dsText(.body17).foregroundStyle(DS.textSecondary)
                        }
                    }
                    if let note = statement.note {
                        note.dsText(.heading17).foregroundStyle(DS.attentionInk)
                    }
                }
            }
            if !facts.isEmpty {
                VStack(spacing: 0) {
                    ForEach(facts) { fact in
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
                            Text(verbatim: fact.label).dsText(.body17).foregroundStyle(DS.textPrimary)
                            Spacer(minLength: DS.Space.s2)
                            Text(verbatim: fact.value).dsText(.body17).foregroundStyle(DS.textSecondary)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.vertical, DS.Space.s2)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if !doors.isEmpty {
                VStack(spacing: 0) {
                    ForEach(doors) { door in
                        DSDoorRow(icon: door.icon, title: door.title, role: door.role, act: door.act)
                    }
                }
            }
            tail
        }
        .padding(DS.Space.s4)
    }
}

extension SubscriptionPage where Tail == EmptyView {
    init(name: String, statement: SubscriptionStatement?, facts: [SubscriptionFact],
         doors: [SubscriptionDoor]) {
        self.init(name: name, statement: statement, facts: facts, doors: doors) {
            EmptyView()
        }
    }
}

/// One subscription in either tile's list: its face, its name, one line, and
/// a figure at the trailing edge where the room has one (the Wallet's cost a
/// month; Day counts in its line and draws none).
struct SubscriptionRow<Figure: View>: View {
    let name: String
    let line: Text
    @ViewBuilder var figure: Figure

    var body: some View {
        DSFeedRow(name: name, line: line) {
            SubscriptionFace(name: name)
        } trailing: {
            figure
        }
    }
}

/// The words the two sheets share.
enum SubscriptionWords {
    /// The verb that starts one, in both rooms and on a mail (prd §1117):
    /// Casberi tracks what you pay for and what writes to you; it never
    /// subscribes you to anything, so the verb is never "Add" or
    /// "Subscribe". It pairs with Stop tracking.
    static var track: String { String(localized: "Track a subscription") }

    /// A host as a door names it: no scheme, no path, no leading `www.`.
    static func host(_ raw: String) -> String {
        var host = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if let scheme = host.range(of: "://") { host = String(host[scheme.upperBound...]) }
        if let slash = host.firstIndex(of: "/") { host = String(host[..<slash]) }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    /// The glyph of a door that leaves the app, in both rooms.
    static let wayOutGlyph = "arrow.up.right"
    /// The glyph of a door into a connected app's feed.
    static let appGlyph = "arrow.right"
    /// The Subscriptions tiles' glyph (`WalletSection.subscriptions`), for a
    /// door to a paid plan.
    static let planGlyph = "arrow.triangle.2.circlepath"
    /// Mail's glyph, for a door to a mailing list.
    static let listGlyph = "envelope"
}

/// Both Subscriptions sheets open at their page's own height (prd §886's
/// fit, as a thing's sheet does), so the last door never sits under the
/// sheet's edge at the half detent. It follows the page while the person has
/// not moved the sheet, never overrides a drag to full height, and ignores a
/// change under 8pt. Applied to the sheet's `ScrollView`, solid ground included.
struct SubscriptionSheetFit: ViewModifier {
    @State private var detent: PresentationDetent = .medium
    @State private var fitted: CGFloat?

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentSize.height + geo.contentInsets.top + geo.contentInsets.bottom
            } action: { _, height in
                fit(height)
            }
            .dsInk()
            .dsReadSheet(detent: $detent, fit: fitted)
    }

    private func fit(_ height: CGFloat) {
        guard height > 0 else { return }
        let fit = height.rounded(.up)
        if let old = fitted, abs(old - fit) < 8 { return }
        let stillFitted = fitted.map { detent == .height($0) } ?? true
        fitted = fit
        if stillFitted { detent = .height(fit) }
    }
}

extension View {
    /// A Subscriptions sheet: solid, and as tall as its page.
    func subscriptionSheet() -> some View { modifier(SubscriptionSheetFit()) }
}
