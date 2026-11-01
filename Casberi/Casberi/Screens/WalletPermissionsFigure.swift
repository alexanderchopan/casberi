import SwiftUI

/// **PERMISSIONS' BOX (prd §1633): the worst one, then what each app reaches.**
/// The permission to look at by its kind ("Unlimited approval") over whose it
/// is ("Uniswap · USDC", `PermissionsLead`), then one strip of every priced
/// grant sized by its dollars, the lead's lit. With nothing left it says so
/// over the strip, empty (§769). No plate (§782); amber is the one status
/// ink, as on the rows.
struct WalletPermissionsFigure: View {
    let lead: PermissionsLead?
    let grants: [WalletApprovalExposure.Grant]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        let money: (Double) -> String = { mask ?? WalletValue.exactMoney($0) }
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(alignment: .center, spacing: DS.Space.s3) {
                mark
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: lead?.title ?? String(localized: "No permissions"))
                        .dsText(.heading24)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let lead {
                        Text(verbatim: lead.line)
                            .dsText(.body17)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
            }
            strip
                .padding(.top, DS.Space.s4)
            legend(money: money)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .animation(reduceMotion ? nil : DS.Motion.standard, value: lead)
    }

    @ViewBuilder
    private var mark: some View {
        switch lead {
        case .grant(let g):
            AssetMark(name: g.spender, size: DS.Face.seat)
        case .delegate(_, let name, _):
            if let name {
                AssetMark(name: name, size: DS.Face.seat)
            } else {
                glyph("questionmark.circle", ink: DS.destructive)
            }
        case .module(_, let name, _):
            AssetMark(name: name, size: DS.Face.seat)
        case nil:
            glyph("checkmark.shield", ink: DS.confirm)
        }
    }

    private func glyph(_ name: String, ink: Color) -> some View {
        Image(systemName: name)
            .dsGlyph(.title)
            .foregroundStyle(ink)
            .frame(width: DS.Face.seat, height: DS.Face.seat)
            .accessibilityHidden(true)
    }

    // MARK: - The strip

    private var segments: [PermissionsLead.Segment] {
        PermissionsLead.strip(grants, lead: lead?.grantID)
    }

    /// Every priced grant, sized by its dollars; a sliver never thinner than
    /// a dot. No grants priced draws the track, empty.
    private var strip: some View {
        let pieces = segments
        let total = pieces.map(\.usd).reduce(0, +)
        return GeometryReader { geo in
            HStack(spacing: 2) {
                if pieces.isEmpty || total <= 0 {
                    Capsule().fill(DS.fillFaint)
                } else {
                    let widths = PermissionsLead.widths(pieces.map(\.usd), in: geo.size.width,
                                                        floor: Self.thickness, gap: 2)
                    ForEach(Array(pieces.enumerated()), id: \.element.id) { index, piece in
                        Capsule()
                            .fill(ink(piece))
                            .frame(width: widths[index])
                    }
                }
            }
        }
        .frame(height: Self.thickness)
        .accessibilityHidden(true)
    }

    static let thickness: CGFloat = 10

    private func ink(_ piece: PermissionsLead.Segment) -> Color {
        if piece.lit { return DS.attention }
        return piece.unlimited ? DS.attention.opacity(0.4) : DS.textTertiary.opacity(0.5)
    }

    private func legend(money: (Double) -> String) -> some View {
        let pieces = segments
        let names = pieces.filter { !$0.lit }.map(\.name)
        let lit = pieces.first(where: \.lit)?.name
        let total = pieces.map(\.usd).reduce(0, +)
        var left = Text(verbatim: "")
        if let lit {
            left = Text(verbatim: lit).foregroundStyle(DS.attentionInk)
            if !names.isEmpty { left = left + Text(verbatim: " · ").foregroundStyle(DS.textTertiary) }
        }
        if pieces.isEmpty {
            left = Text(grants.isEmpty ? "No approvals" : "Nothing priced").foregroundStyle(DS.textTertiary)
        } else {
            left = left + Text(verbatim: names.joined(separator: " · ")).foregroundStyle(DS.textTertiary)
        }
        return HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            left.lineLimit(1)
            Spacer(minLength: DS.Space.s2)
            // Nothing priced states no total: a $0 would read as nothing at
            // stake (`WalletPermissions.totalUSD`'s rule).
            if !pieces.isEmpty {
                Text(verbatim: String(localized: "\(money(total)) in all"))
                    .foregroundStyle(DS.textTertiary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .dsText(.subhead12)
    }
}
