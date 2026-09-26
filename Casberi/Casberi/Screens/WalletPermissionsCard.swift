import SwiftUI

/// WHO CAN ACT FOR YOU — the `Permissions` scope's lead drawing (prd §490,
/// reshaped as COUNTS by §546, and MOVED ONTO THE SHARED FIGURE by §692).
///
/// Every judgement is `WalletPermissions`'; the SHAPE is now
/// `RoomPermissionsFigure`, which five rooms draw. What survives here is the
/// translation — a wallet's power rungs become the shared figure's kinds — and
/// the two facts only this room can state: the dollars in reach, and whether a
/// rung's total is complete enough to say out loud.
///
/// The rulings the shape carries, unchanged and now carried for everyone:
/// aggregate figures and NO names (§546 — the list below owns the names, this
/// owns the arithmetic); colour marks UNBOUNDEDNESS and nothing else; a rung
/// states its total only when every holder in it is priced; bare on the page
/// (§483: *"we don't do cards"*).
///
/// **The one visible change §692 makes here**: a cell is a well rather than a
/// bare numeral, and the numeral is `price17` rather than `price40` — vibenet's
/// census grammar, which is what lets a class with nothing in it draw a dash
/// instead of a "0" that reads as a measurement.
struct WalletPermissionsCard: View {
    let holders: [WalletPermissions.Holder]

    /// **THE WALLET'S CROWN IS WHO HOLDS A PERMISSION, MARK BY MARK (prd
    /// §944, the Accounts pattern of §941).** The rung bars were all one
    /// length and all red on a wallet with one holder per rung — a chart that
    /// said nothing (user: "i like your proposal"). The number is the dollars
    /// in reach (the count of permissions where nothing is priced), and under
    /// it one mark per holder with its name; a holder with no limit wears a
    /// red ring, the only red in the crown. The marks are a picture, not a
    /// control: a delegation has no honest destination in this app (§112), so
    /// the doors are the rows below, where a grant opens its sheet.
    /// The devnets keep `RoomPermissionsFigure` until their pass.
    var body: some View {
        let shown = Array(holders.prefix(Self.shown))
        VStack(alignment: .leading, spacing: 0) {
            reading
            Spacer(minLength: DS.Space.s3)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, holder in
                    mark(holder)
                        .frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    /// Five across fits the box with a name under each.
    static let shown = 5

    @ViewBuilder
    private var reading: some View {
        if let total = WalletPermissions.totalUSD(holders) {
            DSFigureReading(number: WalletValue.exactMoney(total),
                            caption: String(localized: "in reach"))
        } else {
            DSFigureReading(number: String(holders.count),
                            caption: holders.count == 1 ? String(localized: "permission")
                                                        : String(localized: "permissions"))
        }
    }

    private func mark(_ holder: WalletPermissions.Holder) -> some View {
        VStack(spacing: DS.Space.s1) {
            AssetMark(name: holder.name, size: 48)
                .overlay {
                    if holder.power.isUnbounded {
                        Circle()
                            .strokeBorder(DS.destructive, lineWidth: 2)
                            .padding(-4)
                    }
                }
                .padding(4)
            Text(holder.name)
                .dsText(.label12)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(holder.name), \(holder.power.short)"))
    }
}
