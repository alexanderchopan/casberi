import SwiftUI
import WidgetKit

/// What the hero tile leads with (2026-08-14, prd §382 amendment).
///
/// The themes treemap used to hold this slot unconditionally, and it was the
/// weakest thing the brief draws: three abstract boxes carrying three WORDS,
/// which you have to read before they tell you anything. These are the brief's
/// own modules instead — `GenContactSheet`, `GenMoneyHero`, `GenSourceMix` —
/// each of which is legible before it is read. `WidgetDayLead.kind` picks
/// between them, in the app, from what the day actually holds.

/// Draws whichever lead the day earned. One switch, so no layout has to know
/// the ranking — that lives in `WidgetDayLead.kind`, in the app.
struct HeroLead: View {
    let entry: HeroEntry
    let accent: Color
    /// The contact sheet's row count — one across the medium family, two on
    /// large, where there is height for a real sheet rather than a strip.
    var pictureRows: Int = 1

    var body: some View {
        switch entry.lead?.kind {
        case .pictures:
            HeroContactSheet(shots: entry.shots,
                             total: entry.lead?.pictures ?? entry.shots.count,
                             rows: pictureRows)
        case .money:
            if let line = entry.wallet { HeroMoneyLead(line: line, accent: accent) }
        case .sources:
            HeroSourceMix(cells: entry.lead?.sources ?? [], accent: accent)
        default:
            EmptyView()
        }
    }
}

/// The day's own pictures, in a grid (`GenContactSheet` at widget scale).
///
/// The cells are the day itself rather than an abstraction of it, which is why
/// this outranks everything else when the day has any. The bytes come from the
/// shared store — the extension is already reading it for the newest rows, so
/// the thumbnails cost one wider fetch rather than a payload of their own.
struct HeroContactSheet: View {
    let shots: [Data]
    /// How many the day really holds, so a full grid can say what it left out.
    let total: Int
    var columns: Int = 4
    var rows: Int = 1

    private var capacity: Int { columns * rows }
    /// The last cell becomes a "+N" when there are more than fit. It is never a
    /// cropped extra thumbnail: a grid that silently stops is a grid that claims
    /// the day held exactly this many.
    private var overflow: Int { max(0, total - min(shots.count, capacity)) }

    var body: some View {
        let showing = overflow > 0 ? capacity - 1 : min(shots.count, capacity)
        GeometryReader { geo in
            let gap: CGFloat = 6
            let side = (geo.size.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
            HStack(spacing: gap) {
                ForEach(0..<columns, id: \.self) { column in
                    VStack(spacing: gap) {
                        ForEach(0..<rows, id: \.self) { row in
                            let index = row * columns + column
                            cell(at: index, showing: showing, side: side)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(at index: Int, showing: Int, side: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        if index < showing, index < shots.count, let image = UIImage(data: shots[index]) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: side, height: side)
                // Pinned in a frame and CLIPPED — a bare `scaledToFill` expands
                // its container to the image's own size (the gotcha this
                // codebase has paid for), which in a fixed-size widget spills
                // the grid straight out through the tile's rounded edge.
                .clipped()
                .clipShape(shape)
        } else if index == showing, overflow > 0 {
            shape.fill(Color.white.opacity(0.09))
                .frame(width: side, height: side)
                .overlay(
                    Text("+\(overflow)")
                        .dsText(.widgetRecentTitle12)
                        .foregroundStyle(.white.opacity(0.75))
                )
        } else {
            Color.clear.frame(width: side, height: side)
        }
    }
}

/// Where the day came from, as one big cell and two stacked (`GenSourceMix`,
/// §194's three-cell ruling).
///
/// The cells wear MONOGRAMS, not brand marks: `Design/` is app-target only, so
/// the extension cannot reach the bundled icons — and `AssetMark`'s rule for a
/// name we don't bundle is a neutral monogram rather than an invented hue. The
/// fills are the app's own accent at three strengths, so the ranking reads as
/// one family rather than three unrelated colours.
///
/// No cell prints its count (§213). Area carries the share and nothing else.
struct HeroSourceMix: View {
    let cells: [WidgetSourceCell]
    let accent: Color

    var body: some View {
        HStack(spacing: 4) {
            if let lead = cells.first {
                bigCell(lead)
            }
            let rest = Array(cells.dropFirst().prefix(2))
            if !rest.isEmpty {
                VStack(spacing: 4) {
                    ForEach(rest, id: \.name) { smallCell($0) }
                }
                .frame(width: 108)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func bigCell(_ cell: WidgetSourceCell) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 0)
            monogram(cell.name, side: 26, corner: 8, size: 13)
            Text(cell.name)
                .dsText(.widgetTreemapTerm12)
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(10)
        .background(accent.opacity(0.42))
    }

    private func smallCell(_ cell: WidgetSourceCell) -> some View {
        HStack(spacing: 6) {
            monogram(cell.name, side: 20, corner: 6, size: 11)
            Text(cell.name)
                .dsText(.widgetTreemapTerm12)
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .background(Color.white.opacity(0.12))
    }

    private func monogram(_ name: String, side: CGFloat, corner: CGFloat, size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(Color.white.opacity(0.22))
            .frame(width: side, height: side)
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(.white)
            )
    }
}

/// The day's money, with its own curve (`GenMoneyHero` at widget scale).
///
/// Reuses the wallet tile's published line, so the two can never disagree — and
/// inherits its rails whole: a flat curve draws down the middle, a change that
/// rounds to zero gets no direction, and Hide balances (§374) takes the figures
/// and leaves the shape.
struct HeroMoneyLead: View {
    let line: WidgetWalletLine
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(line.total.map { MoneyFormat.compactUSD($0) } ?? WidgetMask.figure)
                    .dsText(.widgetFigure24)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let pct = line.changePct {
                    Text(MoneyFormat.percentLabel(pct))
                        .dsText(.widgetSubline12)
                        .foregroundStyle(MoneyFormat.isFlatPercent(pct)
                                         ? .white.opacity(0.6) : (pct > 0 ? .green : .red))
                        .monospacedDigit()
                }
            }
            WidgetSpark(normalized: line.normalizedPoints)
                .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(maxHeight: .infinity)
        }
    }
}

/// Deadlines on a rail (`GenRunway` at widget scale).
///
/// The geometry — and the invariant that the window always CONTAINS now — lives
/// in `WidgetRunway`, in `Shared/`, where the harness can prove it. This is the
/// drawing only.
struct HeroRunway: View {
    let dates: [Date]
    let now: Date
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            if let placed = WidgetRunway.positions(for: dates, now: now) {
                let width = geo.size.width
                ZStack(alignment: .topLeading) {
                    Capsule()
                        .fill(Color.white.opacity(0.16))
                        .frame(height: 3)
                        .offset(y: 15)
                    // The marker is a bar, not another dot: it is not one of
                    // the things on the rail, it is where you are standing.
                    Capsule()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 2, height: 19)
                        .offset(x: width * placed.now - 1, y: 7)
                    ForEach(Array(placed.dots.enumerated()), id: \.offset) { index, position in
                        let late = dates[index] < now
                        Circle()
                            .fill(late ? accent : Color.white.opacity(0.55))
                            .frame(width: 11, height: 11)
                            // A ring in the tile's own ground, so two dots that
                            // land on the same hour read as two.
                            .overlay(Circle().strokeBorder(.black, lineWidth: 2))
                            .offset(x: width * position - 5.5, y: 11)
                    }
                }
            }
        }
        .frame(height: 34)
        .accessibilityHidden(true)
    }
}
