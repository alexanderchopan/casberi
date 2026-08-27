import SwiftUI

/// WHERE THE CHANGES LANDED — the Activity scope's drawing (prd §491).
///
/// Every judgement is `VibenetChangeFlow`'s; this is its shape. Bare on the
/// page like every other scope's lead (§483).
///
/// **Ribbons are weighted WITHIN a kind, never across.** An authorization is
/// not larger than a revocation — they are different things that happened, not
/// more and less of one thing — so each kind scales against its own heaviest
/// edge and states its number in words on the left. Wallet's flow band can
/// compare its ribbons because they are all dollars; this one cannot, and
/// pretending otherwise would draw one revocation as a hairline beside forty
/// grants and read as a quiet account.
struct VibenetChangeFlowCard: View {
    let flow: VibenetChangeFlow.Flow
    let name: (String) -> String
    /// Scope the room to a tapped account, or nil where there is nowhere to
    /// go — which keeps every node a plain read rather than pretending at a
    /// door (the delegate spine's own rule).
    var onPick: ((String) -> Void)? = nil
    let reduceMotion: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotionEnv

    private var kinds: [VibenetChangeFlow.Kind] {
        VibenetChangeFlow.Kind.allCases.filter { flow.total($0) > 0 }
    }
    private var addresses: [String] {
        Array(flow.addresses.prefix(VibenetChangeFlow.addressesShown))
    }

    private let rowHeight: CGFloat = 34
    private let labelColumn: CGFloat = 112
    private let faceColumn: CGFloat = 118

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(VibenetChangeFlow.headline(flow))
                .dsText(.stat24)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
            GeometryReader { geo in
                band(width: geo.size.width)
            }
            .frame(height: CGFloat(max(kinds.count, addresses.count)) * rowHeight + 8)
            .padding(.top, DS.Space.s2)
            if flow.addresses.count > VibenetChangeFlow.addressesShown {
                Text(String(localized: "and \(flow.addresses.count - VibenetChangeFlow.addressesShown) more"))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(VibenetChangeFlow.spoken(flow)))
        .accessibilityActions {
            if let onPick {
                ForEach(addresses, id: \.self) { address in
                    Button("Open \(name(address))") { onPick(address) }
                }
            }
        }
    }

    private func band(width: CGFloat) -> some View {
        let fieldStart = labelColumn
        let fieldEnd = max(fieldStart + 20, width - faceColumn)
        return ZStack(alignment: .topLeading) {
            // The ribbons first, so a label always draws over a stroke rather
            // than under it.
            ForEach(flow.edges) { edge in
                if let k = kinds.firstIndex(of: edge.kind),
                   let a = addresses.firstIndex(of: edge.address) {
                    ribbon(edge, from: y(k), to: y(a), x0: fieldStart, x1: fieldEnd)
                }
            }
            ForEach(Array(kinds.enumerated()), id: \.element) { index, kind in
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Text(kind.label)
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(flow.total(kind))")
                        .dsText(.label12)
                        .foregroundStyle(kind.isAlarming ? DS.attention : DS.textSecondary)
                        .monospacedDigit()
                }
                .frame(width: labelColumn - DS.Space.s2, alignment: .leading)
                .position(x: (labelColumn - DS.Space.s2) / 2, y: y(index))
            }
            ForEach(Array(addresses.enumerated()), id: \.element) { index, address in
                HStack(spacing: DS.Space.s2) {
                    WalletFace(address: address, size: DS.Face.rowCircle, circular: true)
                    Text(name(address))
                        .dsText(.label12)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                .frame(width: faceColumn - DS.Space.s2, alignment: .leading)
                .position(x: fieldEnd + (faceColumn - DS.Space.s2) / 2, y: y(index))
                .contentShape(Rectangle())
                .onTapGesture { onPick?(address) }
                // The band speaks as one element and carries the taps as
                // actions; a trait here would be a stray label (§299).
                .accessibilityHidden(true)
            }
        }
    }

    private func y(_ index: Int) -> CGFloat {
        rowHeight / 2 + CGFloat(index) * rowHeight
    }

    /// One ribbon, scaled against the heaviest edge OF ITS OWN KIND.
    @ViewBuilder
    private func ribbon(_ edge: VibenetChangeFlow.Edge,
                        from: CGFloat, to: CGFloat,
                        x0: CGFloat, x1: CGFloat) -> some View {
        let heaviest = max(1, flow.heaviest(edge.kind))
        let weight = 1.2 + 2.4 * CGFloat(min(1, Double(edge.count) / Double(heaviest)))
        Path { p in
            p.move(to: CGPoint(x: x0, y: from))
            p.addCurve(to: CGPoint(x: x1, y: to),
                       control1: CGPoint(x: (x0 + x1) / 2, y: from),
                       control2: CGPoint(x: (x0 + x1) / 2, y: to))
        }
        .stroke(edge.kind.isAlarming ? DS.attention : DS.tint,
                style: StrokeStyle(lineWidth: weight, lineCap: .round))
        .opacity(0.8)
        .chartWipe(reduceMotion: reduceMotion || reduceMotionEnv)
    }
}
