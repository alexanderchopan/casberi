import SwiftUI

/// **PERMISSIONS' BOX IS A PACK (prd §1654).** One circle per app that can
/// move your tokens, its area the dollars it reaches (`PermissionsPack`), an
/// app with no limit ringed in amber; past eight apps, one grey "N more". A
/// circle large enough carries its figure, a larger one what it reaches too;
/// the rest stand on their mark. Under the pack, the key and the total.
///
/// A tap opens the grant's sheet when the app holds one grant, else the
/// Approvals list under the box, open in full.
///
/// No plate (§782): the circles are the figure, on the box's well. Amber is
/// the one status hue, as on the rows.
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
                key(Circle().strokeBorder(DS.attention, lineWidth: 2), word: String(localized: "No limit"))
            }
            if pieces.contains(where: { !$0.unlimited }) {
                key(Circle().fill(DS.fillFaint), word: String(localized: "Capped"))
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

/// One app's circle: the faint disc, the amber ring when it has no limit, the
/// mark, and the figure and what it reaches when the circle can hold them.
private struct PermissionsCircle: View {
    let piece: PermissionsPack.Piece
    let diameter: CGFloat
    let figure: String?

    /// A circle this wide carries its figure; `wide` its tokens too.
    static let figured: CGFloat = 96
    static let wide: CGFloat = 150

    var body: some View {
        ZStack {
            Circle().fill(DS.fillFaint)
            if piece.unlimited {
                Circle().strokeBorder(DS.attention, lineWidth: diameter >= Self.figured ? 3 : 2)
            }
            VStack(spacing: 2) {
                if piece.isMore {
                    Text(verbatim: piece.name)
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    AssetMark(name: piece.name, size: markSize)
                }
                if diameter >= Self.figured, let figure {
                    Text(verbatim: figure)
                        .dsText(diameter >= Self.wide ? .heading24 : .body17)
                        .foregroundStyle(DS.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if diameter >= Self.wide, !piece.isMore, !piece.symbols.isEmpty {
                    Text(verbatim: piece.symbols.prefix(2).joined(separator: " · "))
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, DS.Space.s2)
        }
        .frame(width: diameter, height: diameter)
    }

    /// The seat's mark in a large circle, the list's in a small one, never
    /// wider than the circle leaves room for.
    private var markSize: CGFloat {
        let size = diameter >= 120 ? DS.Face.seat : DS.Face.list
        return min(size, diameter - 14)
    }
}
