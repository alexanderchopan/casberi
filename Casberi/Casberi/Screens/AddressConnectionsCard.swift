import SwiftUI

/// The address book reading itself (2026-08-03, prd §295, ruled from
/// `design/wallet-viz/wallet-ties-mocks.html`) — the last card on the Wallet
/// manager, after the book's own rows.
///
/// A count and a spine: the connected address on the left, your wallets on the
/// right, one ribbon per landed relationship. The user ruling this card was
/// built to (2026-08-03): *limit the analysis, it should be factual.* So there
/// is no ranking, no superlative and no interpretation anywhere on it — every
/// line is a number the corpus holds or a name you gave something.
///
/// Three consequences of that ruling, none of them to be "improved" without a
/// new one:
///
/// - **Every ribbon is the same weight.** A connection exists or it doesn't.
///   Scaling one by volume would be the card claiming which relationship
///   matters — which is precisely the analysis it was told not to do. (The
///   flow band next door DOES scale its ribbons, correctly: there the whole
///   claim is that one side is bigger than the other.)
/// - **No hue.** Not even the one mark the approvals card spends. Nothing here
///   is a state, a warning or a gain — it is an inventory.
/// - **Order is the order you first dealt with each address**, never count and
///   never dollars. Sorting would rank.
///
/// FLAT BY LAW like its neighbours — a plain VStack and one `Path`, no generic
/// `Widget`/`Row` mount (the render-depth lesson, paid three times).
///
/// Liveness: this view stores no `Thing`, only value types out of
/// `AddressConnections`, so corollary 5 has nothing to guard here.
struct AddressConnectionsCard: View {
    let map: AddressConnections.Map
    /// Names an address that nobody has named. Hands back the SHORT form for
    /// the alert's title; the card holds no hex of its own.
    var onName: (AddressConnections.Node) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// **The ribbons draw themselves** (2026-08-03, prd §297) — a `trim` across
    /// the single `Path`, so the connections are STRUCK one after another, in
    /// first-dealt order, the same order the rows are already in. This card was
    /// the only wallet visualization with no motion of any kind: it sits on the
    /// Wallet manager, which doesn't use `RowEntrance`, so it didn't even
    /// inherit the fade every feed card gets.
    ///
    /// A stroke-draw and not a wipe, deliberately. A wipe would reveal the
    /// ribbons left-to-right as a group, which says "a picture is appearing";
    /// tracing each curve from a name to a wallet says "this address reached
    /// this wallet, and then this one" — the sentence the card exists to make.
    /// It stays inside the factual ruling: the ORDER traced is the order
    /// already on screen, so the entrance ranks nothing the drawing doesn't.
    @State private var drawn: CGFloat = 0
    /// One row of the spine, both sides. Fixed so the ribbon's arithmetic and
    /// the labels' layout can't disagree — the two are computed from the same
    /// number rather than one being measured off the other.
    private static let rowHeight: CGFloat = 38
    private static let sideWidth: CGFloat = 118

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "Connected"))
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(DS.textTertiary)

            Text(AddressConnections.headline(count: map.connectedCount))
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s2)

            if let subhead = AddressConnections.subhead(count: map.connectedCount) {
                Text(subhead)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s1)
            }

            if !map.isEmpty {
                spine
                    .padding(.top, DS.Space.s4)
            }

            if let target = map.firstUnnamed {
                nameButton(target)
            }

            notes
        }
        .padding(DS.Space.s4)
        .dsWidgetSurface(fillOpacity: WalletCardStyle.fill)
    }

    // MARK: - The spine

    /// Both columns and the ribbons between them, laid out on ONE height so
    /// the shorter side centres against the taller one.
    private var spine: some View {
        let rows = max(map.nodes.count, map.columns.count)
        let height = CGFloat(rows) * Self.rowHeight
        return HStack(spacing: DS.Space.s2) {
            VStack(spacing: 0) {
                // Enumerated for the entrance stagger only — the names settle
                // in the order they're already listed (first dealt with), so
                // the arrival ranks nothing the card doesn't.
                ForEach(Array(map.nodes.enumerated()), id: \.element.id) { index, node in
                    nodeRow(node)
                        .chartArrival(index: index, reduceMotion: reduceMotion)
                }
            }
            .frame(width: Self.sideWidth, height: height)

            ribbons
                .frame(maxWidth: .infinity)
                .frame(height: height)

            VStack(spacing: 0) {
                ForEach(Array(map.columns.enumerated()), id: \.element.id) { index, column in
                    columnRow(column)
                        .chartArrival(index: index, reduceMotion: reduceMotion)
                }
            }
            .frame(width: Self.sideWidth, height: height)
        }
        // The picture is one figure, not a list of controls — VoiceOver reads
        // the sentence the drawing makes rather than twelve stray labels.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(spineDescription))
    }

    private func nodeRow(_ node: AddressConnections.Node) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(node.name)
                .dsText(.subhead13).fontWeight(.semibold)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
            Text(transactionCount(node.count))
                .dsText(.label11)
                .foregroundStyle(DS.textTertiary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.rowHeight)
    }

    private func columnRow(_ column: AddressConnections.Column) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(column.name)
                .dsText(.subhead13).fontWeight(.semibold)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
            // A wallet whose connected transfers were never priced states
            // nothing, not "$0" — the whole reason `usd` is optional.
            if let usd = column.usd {
                Text(TokenStats.compact(usd))
                    .dsText(.label11)
                    .foregroundStyle(DS.textTertiary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .frame(height: Self.rowHeight)
    }

    /// One curve per relationship, all the same weight. Drawn in a single
    /// `Path` rather than a shape per edge: at five nodes and five wallets
    /// that is up to twenty-five views doing nothing but stroking a line.
    private var ribbons: some View {
        GeometryReader { geo in
            Path { path in
                let width = geo.size.width
                let leftInset = inset(count: map.nodes.count, of: geo.size.height)
                let rightInset = inset(count: map.columns.count, of: geo.size.height)
                for (nodeIndex, node) in map.nodes.enumerated() {
                    let from = leftInset + centre(nodeIndex)
                    for key in node.walletKeys {
                        guard let columnIndex = map.columns.firstIndex(where: { $0.id == key })
                        else { continue }
                        let to = rightInset + centre(columnIndex)
                        path.move(to: CGPoint(x: 0, y: from))
                        // Horizontal control points: the curve leaves and
                        // arrives flat, so a ribbon reads as joining two rows
                        // rather than pointing at the gap between them.
                        path.addCurve(to: CGPoint(x: width, y: to),
                                      control1: CGPoint(x: width / 2, y: from),
                                      control2: CGPoint(x: width / 2, y: to))
                    }
                }
            }
            // `trim` over the whole path walks its subpaths in order, so the
            // ribbons are struck one after another rather than all at once.
            .trim(from: 0, to: drawn)
            .stroke(DS.textTertiary,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .onAppear {
            guard drawn == 0 else { return }
            guard !reduceMotion else { drawn = 1; return }
            // Longer than a wipe: the point is to follow one line at a time,
            // and at `ChartEntrance.wipe` a busy map is a flicker.
            withAnimation(.easeInOut(duration: 1.1).delay(ChartEntrance.lead)) { drawn = 1 }
        }
    }

    /// Where a side's stack starts, so a short side centres against the tall one.
    private func inset(count: Int, of height: CGFloat) -> CGFloat {
        max(0, (height - CGFloat(count) * Self.rowHeight) / 2)
    }

    private func centre(_ index: Int) -> CGFloat {
        CGFloat(index) * Self.rowHeight + Self.rowHeight / 2
    }

    // MARK: - The action, and the caveats

    /// The card's ONE action, and only when a connected address has no name.
    ///
    /// An address that has moved real money with two of your wallets and still
    /// reads as hex is the best naming prompt this app can show — and naming it
    /// rewrites every landed transfer that carries it (`CounterpartyRetitle`),
    /// so one tap fixes the past as well as the future. It targets the FIRST
    /// unnamed one; picking the busiest would be a ranking.
    private func nameButton(_ target: AddressConnections.Node) -> some View {
        Button {
            DSHaptic.selection()
            onName(target)
        } label: {
            Text(String(localized: "Name \(target.name)"))
                .dsText(.callout15).fontWeight(.semibold)
                .foregroundStyle(DS.page)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.s3)
                .background(DS.textPrimary,
                            in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, DS.Space.s4)
    }

    /// What the picture doesn't say, in the order it matters: what wasn't
    /// drawn, which wallets nothing reaches, and since when any of this is true.
    @ViewBuilder
    private var notes: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let hidden = AddressConnections.hiddenNote(map.hiddenCount) {
                note(hidden)
            }
            if let untouched = AddressConnections.untouchedNote(
                map.untouchedWalletNames, connectedCount: map.connectedCount) {
                note(untouched)
            }
            // The honesty line every wallet running total carries: a wallet
            // watched four days ago and one watched in March are not
            // comparable, and a card that quietly compared them would be
            // stating a fact it can't know.
            note(String(localized: "Since you started watching each wallet."))
        }
        .padding(.top, DS.Space.s3)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .dsText(.label11)
            .foregroundStyle(DS.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func transactionCount(_ count: Int) -> String {
        count == 1 ? String(localized: "1 transaction")
                   : String(localized: "\(count) transactions")
    }

    /// The spine as a sentence, for VoiceOver — the same facts the drawing
    /// carries, since a `Path` reads as nothing at all.
    private var spineDescription: String {
        map.nodes.map { node in
            let wallets = node.walletKeys.compactMap { key in
                map.columns.first { $0.id == key }?.name
            }
            return String(localized:
                "\(node.name), \(transactionCount(node.count)), reaches \(wallets.joined(separator: ", "))")
        }.joined(separator: ". ")
    }
}
