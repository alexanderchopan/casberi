import SwiftUI

/// What a vibenet account (or a room of them) holds, drawn as AREAS — the
/// design's holdings treemap (prd §467, 2026-08-24).
///
/// **A 2:1 SPLIT, MEASURED, not an `HStack` of equal children.** The first cut
/// gave every cell `.frame(maxWidth: .infinity)` with `.layoutPriority(2)` on
/// the lead — and priority is not a ratio: it resolves the lead's width FIRST
/// and hands it nearly the whole row, so the shipped card drew one large empty
/// rectangle with the second asset squeezed into a sliver against the trailing
/// edge. That is the picture the report called "some hodge podge put together
/// view", and it is why the widths here are computed from the container rather
/// than negotiated between siblings.
///
/// `GeometryReader` is safe because this block has a FIXED height, which is
/// the one condition that keeps it from collapsing inside a `VStack`.
///
/// **NO HUE, and no price.** The tone carries RANK and nothing else
/// (`DS.ink(magnitude:)`, the neutral ramp): this bridge has no price feed, so
/// three assets have no shared unit to size against and the areas state each
/// asset's own place in its own list rather than implying one converted
/// figure. `VibenetBalanceTreemap` owns that reasoning and returns NOTHING for
/// a lone asset — a single cell is not a treemap, it is a rectangle repeating
/// the crown directly above it.
///
/// ONE definition, used by both the aggregate room card and the scoped account
/// detail, so narrowing the room cannot quietly change how holdings are drawn.
struct VibenetHoldingsBlock: View {
    let cells: [VibenetTreemapCell]
    let reduceMotion: Bool

    /// 120pt — the design's own, and tall enough that the lead cell reads as
    /// an AREA rather than as a tall button with a word in it.
    static let height: CGFloat = 120

    var body: some View {
        if let lead = cells.first {
            let rest = Array(cells.dropFirst())
            GeometryReader { proxy in
                let gap = DS.Space.s2
                let leadWidth = max(0, (proxy.size.width - gap) * 2 / 3)
                HStack(spacing: gap) {
                    cell(lead, isLead: true, index: 0)
                        .frame(width: leadWidth)
                    if !rest.isEmpty {
                        VStack(spacing: gap) {
                            ForEach(Array(rest.enumerated()), id: \.offset) { index, entry in
                                cell(entry, isLead: false, index: index + 1)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: Self.height)
        }
    }

    @ViewBuilder
    private func cell(_ cell: VibenetTreemapCell, isLead: Bool, index: Int) -> some View {
        // The lead states its symbol at the top and its amount at the foot —
        // it has the height for the pair to read as a block. A stacked cell is
        // a third that height, so it puts them on ONE line with the amount
        // trailing, which is the difference between a label and an empty box
        // with two words pinned to its corners.
        Group {
            if isLead {
                VStack(alignment: .leading, spacing: 2) {
                    // **THE TOKEN'S OWN MARK (user, prd §491: Wallet's holdings
                    // cells carry one and these did not).** `AssetMark` resolves
                    // a bundled mark where one exists and falls back to a
                    // monogram where it does not — which is the honest outcome
                    // here, since a devnet token has no brand art and inventing
                    // a hue for it is exactly what that type refuses to do.
                    HStack(spacing: DS.Space.s2) {
                        AssetMark(name: cell.symbol, size: 22)
                        Text(cell.symbol)
                            .dsText(.body17)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                // STACKED, not side by side — measured twice. A stacked cell
                // is a third of the card's width, and a symbol beside a figure
                // on ONE line has ~86pt for both: side by side it first clipped
                // the NAME ("U… 500.25", which names no asset at all), and with
                // the name given priority it clipped the FIGURE instead
                // ("USDV 500…."), which is worse — a truncated number is a
                // wrong number, where a truncated word is merely an unreadable
                // one. Stacking gives each its own line and neither has to lose.
                VStack(alignment: .leading, spacing: 1) {
                    // The mark rides the SYMBOL's line, never the figure's:
                    // the stack below exists because a symbol and a figure
                    // could not share ~86pt without one of them clipping, and
                    // a mark on the figure's line would re-open exactly that.
                    HStack(spacing: DS.Space.s1 + 2) {
                        AssetMark(name: cell.symbol, size: 16)
                        Text(cell.symbol)
                            .dsText(.callout15)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
        }
        .padding(.horizontal, DS.Space.s3)
        .padding(.vertical, isLead ? DS.Space.s3 : DS.Space.s2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isLead ? .topLeading : .leading)
        .background(DS.ink(magnitude: cell.share),
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .chartArrival(index: index, reduceMotion: reduceMotion)
    }
}
