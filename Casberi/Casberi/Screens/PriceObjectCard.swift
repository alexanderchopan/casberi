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
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                Text(verbatim: object.symbol)
                    .dsText(.heading24).foregroundStyle(DS.textPrimary)
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
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
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
            // INK, like every other paper (2026-08-29) — see `DS.pourInk`.
            //
            // This pour was DIRECTION rather than identity, which is why it
            // was proposed as one of three exceptions the ink ruling should
            // spare; the user's answer was that none of the three needed to
            // keep its colour. It costs nothing here, and that is the reason
            // it went quietly: the direction is already stated twice on this
            // card in the places a reader actually looks — the signed figure
            // and the capsule beside it, both still coloured — so the wash
            // was a third telling, at the weakest possible strength, and
            // removing it takes no fact off the screen.
            LinearGradient(colors: [DS.pourInk, DS.pourInk.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 150)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        // INK, for the same reason the pour above it is (prd §542,
        // 2026-08-31, user: "i think in the token rooms sheets we have that
        // gray" — this card, named). `DS.surfaceRaised` stood here, which is
        // the gray every paper in the app wore until §542 and this is a
        // paper: pour, clipped silhouette, `raisedShadow`. It reads on the
        // ink ground by its pour and its shadow, not by a tonal step.
        .background(DS.inkGround)
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
            DSStamp(word: String(localized: "Live"), weight: .good)
        case .aged(let when):
            DSStamp(word: when.formatted(.relative(presentation: .named)), weight: .quiet)
        }
    }

    /// The move, always naming its window. A percentage with no window is a
    /// number rather than a reading — and a change that rounds away takes the
    /// neutral fill and no sign, since it has no direction to report (§83).
    private func movePill(_ move: PriceObject.Move) -> some View {
        let flat = move.isFlat
        let ink = flat ? DS.textSecondary
                       : TokenChartStyle.accent(up: move.change > 0, scheme: scheme)
        // A FACT, so a word and not a pill (prd §746). The ink still carries
        // the direction; the emphasis the solid capsule gave a live reading is
        // its weight now — bold only while the reading is current AND has a
        // direction, because emphasis on a number we have just said we cannot
        // vouch for is the overclaim wearing a different hat.
        return Text(verbatim: "\(PriceObject.percent(move.change)) · \(move.window)")
            .dsText(.subhead12)
            .fontWeight(object.freshness.isLive && !flat ? .bold : .regular)
            .monospacedDigit()
            .foregroundStyle(ink)
    }

}
