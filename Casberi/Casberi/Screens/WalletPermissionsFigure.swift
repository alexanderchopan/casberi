import SwiftUI

/// **PERMISSIONS' BOX IS A PACK (prd §1654, coloured by §1656).** One circle
/// per app that can move your tokens, its area the dollars it reaches
/// (`PermissionsPack`). The fill says the limit: amber (`DS.attention`) for an
/// app with no limit, the charts' tint for a capped one; past eight apps, one
/// grey "N more". The figure leads inside a circle; a larger one names the app
/// and what it reaches, the largest carries the app's mark too. Under the
/// pack, the key and the total.
///
/// A tap opens the grant's sheet when the app holds one grant, else the
/// Approvals list under the box, open in full.
///
/// No plate (§782): the circles are the figure, on the box's well. Amber is
/// the rows' status hue; the tint is the charts' (§1385).
struct WalletPermissionsFigure: View {
    let grants: [WalletApprovalExposure.Grant]
    let open: (PermissionsPack.Piece) -> Void

    var body: some View {
        let pieces = PermissionsPack.pieces(grants)
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        let money: (Double) -> String = { mask ?? WalletValue.exactMoney($0) }
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if pieces.isEmpty {
                // What would fill it, empty (§769).
                Circle()
                    .fill(DS.fillFaint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            } else {
                DSCirclePack(items: pieces.map { piece in
                    DSCirclePackItem(id: piece.id, share: piece.usd, label: label(piece, money: money))
                }, mark: { item, diameter in
                    if let piece = pieces.first(where: { $0.id == item.id }) {
                        PermissionsCircle(piece: piece, diameter: diameter,
                                          figure: piece.priced ? money(piece.usd) : nil)
                    }
                }, action: { item in
                    if let piece = pieces.first(where: { $0.id == item.id }) { open(piece) }
                })
            }
            legend(pieces, money: money)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func label(_ piece: PermissionsPack.Piece, money: (Double) -> String) -> String {
        var parts = [piece.name]
        if piece.priced { parts.append(money(piece.usd)) }
        parts += piece.symbols.prefix(3)
        if piece.unlimited { parts.append(String(localized: "No limit")) }
        return parts.joined(separator: ", ")
    }

    /// The key names only what the pack holds; the total trails, and nothing
    /// priced states none.
    private func legend(_ pieces: [PermissionsPack.Piece], money: (Double) -> String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s4) {
            if pieces.isEmpty {
                Text("No approvals").foregroundStyle(DS.textTertiary)
            }
            if pieces.contains(where: \.unlimited) {
                key(Circle().fill(PermissionsCircle.unlimitedFill), word: String(localized: "No limit"))
            }
            if pieces.contains(where: { !$0.unlimited }) {
                key(Circle().fill(PermissionsCircle.cappedFill), word: String(localized: "Capped"))
            }
            Spacer(minLength: DS.Space.s2)
            if let total = PermissionsPack.total(pieces) {
                Text(verbatim: money(total))
                    .foregroundStyle(DS.textTertiary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .dsText(.subhead12)
        .lineLimit(1)
    }

    private func key(_ swatch: some View, word: String) -> some View {
        HStack(spacing: DS.Space.s1 + 2) {
            swatch
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(verbatim: word).foregroundStyle(DS.textTertiary)
        }
    }
}

/// One app's circle (prd §1656): filled by its limit, the figure leading.
///
///   · 150pt and wider: the app's mark, the figure at `heading34`, then
///     "Uniswap · USDC".
///   · 96pt and wider: the figure at `heading24` over the app's name.
///   · Narrower: the figure alone, or the mark when nothing is priced.
///   · More: grey, "N more".
struct PermissionsCircle: View {
    let piece: PermissionsPack.Piece
    let diameter: CGFloat
    let figure: String?

    static let named: CGFloat = 96
    static let marked: CGFloat = 150

    static var unlimitedFill: Color { DS.attention }
    static var cappedFill: Color { DS.tint }

    private var fill: Color {
        if piece.isMore { return DS.fillStrong }
        return piece.unlimited ? Self.unlimitedFill : Self.cappedFill
    }

    /// Dark words on amber, white on the tint, the page's own on grey.
    private var ink: Color {
        if piece.isMore { return DS.textSecondary }
        return piece.unlimited ? Color.black.opacity(0.88) : .white
    }

    var body: some View {
        ZStack {
            Circle().fill(fill)
            VStack(spacing: 2) {
                if piece.isMore {
                    Text(verbatim: piece.name)
                        .dsText(.subhead12)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else if diameter >= Self.marked {
                    AssetMark(name: piece.name, size: DS.Face.list)
                        .padding(.bottom, DS.Space.s1)
                    figureText(.heading34)
                    caption([piece.name] + piece.symbols.prefix(1))
                } else if diameter >= Self.named {
                    if figure == nil { AssetMark(name: piece.name, size: DS.Face.list) }
                    figureText(.heading24)
                    caption([piece.name])
                } else if figure != nil {
                    figureText(diameter >= 60 ? .body17 : .subhead12)
                } else {
                    AssetMark(name: piece.name, size: min(DS.Face.list, diameter - 20))
                }
            }
            .foregroundStyle(ink)
            .padding(.horizontal, DS.Space.s2)
        }
        .frame(width: diameter, height: diameter)
    }

    @ViewBuilder
    private func figureText(_ rung: DSTextStyle) -> some View {
        if let figure {
            Text(verbatim: figure)
                .dsText(rung)
                .fontWeight(.bold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private func caption(_ parts: [String]) -> some View {
        Text(verbatim: parts.joined(separator: " · "))
            .dsText(.subhead12)
            .opacity(0.72)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}
