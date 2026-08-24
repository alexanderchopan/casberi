import SwiftUI

/// The price object, drawn (prd §369 amendment, 2026-08-16) — the hero a
/// watched token or stock never had.
///
/// **One object, and the chart is its evidence.** The order here is the whole
/// argument: subject, name, figure, sentence, and only then the curve. That is
/// `MoneyCommentaryCard`'s deliberate inversion applied to a price — a chart
/// above a headline makes the reader do the reading, and this app's job on a
/// screen full of numbers is to have already done it.
///
/// **The stamp is FRESHNESS, not finality** — the one place this diverges from
/// the receipt, and for a reason that is not cosmetic: a receipt can be
/// finished and a price never is, so the state slot carries the only state a
/// price has. See `PriceObject.Freshness`.
///
/// Takes VALUES, never a `Thing` (the build-188 leaf rule). The one place a
/// `Thing` is read is `PriceObjectSource`, on the main actor, behind `isLive`.
struct PriceObjectCard<Evidence: View>: View {
    let object: PriceObject
    /// The curve, handed in rather than built here — the card must not know how
    /// a price is fetched, and the two live in different layers.
    @ViewBuilder var evidence: () -> Evidence
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                subjectMark
                Spacer(minLength: DS.Space.s3)
                freshnessStamp
                    // Spoken as the accessibility VALUE below, so hearing it
                    // here too would say the state twice.
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 0) {
                if let name = object.name, !name.isEmpty {
                    Text(verbatim: name)
                        .dsText(.callout15).foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                Text(verbatim: object.symbol)
                    .dsText(.heading22).foregroundStyle(DS.textPrimary)
                    .lineLimit(1).truncationMode(.tail)

                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Text(verbatim: object.price)
                        .dsText(.price40)
                        .monospacedDigit()
                        .foregroundStyle(DS.textPrimary)
                        .contentTransition(.numericText())
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if let move = object.move { movePill(move) }
                }
                .padding(.top, DS.Space.s3)

                if let sentence = object.sentence {
                    Text(verbatim: sentence)
                        .dsText(.callout15).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DS.Space.s4)
                }
            }
            .padding(.top, DS.Space.s3)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(object.spokenLabel))
            .accessibilityValue(Text(object.spokenValue))

            evidence()
                .padding(.top, DS.Space.s4)
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) {
            // The pour is DIRECTION, and it stands down the moment the read is
            // no longer current: a green wash over a price we cannot vouch for
            // is colour making a claim the card is simultaneously withdrawing.
            LinearGradient(colors: [pour.opacity(DS.receiptPourOpacity(scheme)),
                                    pour.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 150)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(DS.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card + 4,
                                    style: .continuous))
        .shadow(color: DS.raisedShadow, radius: 10, y: 2)
    }

    /// A bundled mark where we have artwork, a neutral monogram where we don't,
    /// and nothing at all where the row never stamped a symbol. `AssetMark`
    /// already refuses to invent a hue for an unknown name, which matters more
    /// here than almost anywhere: a watchlist is mostly long-tail tokens.
    @ViewBuilder private var subjectMark: some View {
        switch object.subject {
        case .asset(let symbol):
            AssetMark(name: symbol, size: DS.Face.shelf)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder private var freshnessStamp: some View {
        switch object.freshness {
        case .live:
            stamp(String(localized: "Live"), ink: DS.confirm,
                  wash: DS.confirm.opacity(0.16))
        case .aged(let when):
            stamp(when.formatted(.relative(presentation: .named)),
                  ink: DS.textTertiary, wash: DS.fillFaint)
        }
    }

    private func stamp(_ word: String, ink: Color, wash: Color) -> some View {
        Text(verbatim: word)
            .dsText(.label12)
            .foregroundStyle(ink)
            .lineLimit(1)
            .padding(.horizontal, DS.Space.s2)
            .frame(minHeight: 24)
            .background(wash, in: Capsule(style: .continuous))
    }

    /// The move, always naming its window. A percentage with no window is a
    /// number rather than a reading — and a change that rounds away takes the
    /// neutral fill and no sign, since it has no direction to report (§83).
    private func movePill(_ move: PriceObject.Move) -> some View {
        let flat = move.isFlat
        let ink = flat ? DS.textSecondary
                       : TokenChartStyle.accent(up: move.change > 0, scheme: scheme)
        return Text(verbatim: "\(PriceObject.percent(move.change)) · \(move.window)")
            .dsText(.subhead13)
            .fontWeight(.bold)
            .monospacedDigit()
            .foregroundStyle(object.freshness.isLive && !flat ? .white : ink)
            .padding(.horizontal, DS.Space.s2 + 2)
            .padding(.vertical, 3)
            .background(
                // Loud only while the reading is current AND has a direction:
                // a solid capsule is emphasis, and emphasis on a number we
                // have just said we cannot vouch for is the overclaim wearing
                // a different hat.
                object.freshness.isLive && !flat ? AnyShapeStyle(ink)
                                                 : AnyShapeStyle(DS.fillStrong),
                in: Capsule(style: .continuous))
    }

    /// Deliberately NOT `DS.receiptPour(_:)` — this card has no
    /// `MoneyReceipt.Hue`, and a price's identity already lives in
    /// `subjectMark`/the name beside it. This wash answers a different
    /// question (which way did it move), which is exactly why it borrows
    /// only `receiptPourOpacity`'s intensity dial and not the identity
    /// function beside it (see that token's own doc).
    private var pour: Color {
        guard object.freshness.isLive, let move = object.move, !move.isFlat else {
            return DS.textPrimary.opacity(0.06)
        }
        return TokenChartStyle.accent(up: move.change > 0, scheme: scheme)
    }
}
