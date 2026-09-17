import SwiftUI

/// ONE APP'S PAGE (prd §803e) — the mockup's app page, drawn in the thing
/// sheet in place of the title block: the app's logo and name, what its wallet
/// holds, the wallet itself, and when you joined and last used it.
///
/// Export keys and Add funds are NOT here (user, 2026-09-17): this seat reads.
/// The doors out — the app itself, and the wallet on an explorer — ride the
/// sheet's dial (`ThingSheetView.privyVerbs`), where every sheet's doors are.
///
/// Stores no `Thing`: the app and its balance are values out of
/// `PrivyHomeStore`.
struct PrivyAppHead: View {
    let app: PrivyHomeFeed.App

    var body: some View {
        let store = PrivyHomeStore.shared
        let balances = app.wallets.compactMap { store.balances[PrivyHomeFeed.key($0.address)] }
        let usd = PrivyHomeFeed.appUSD(app, balances: store.balances)
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        let holdings = balances.flatMap { $0.bySymbol }
            .reduce(into: [String: Double]()) { $0[$1.key, default: 0] += $1.value }
            .filter { $0.value >= PrivyHomeFeed.fundedFloor }
            .sorted { $0.value > $1.value }

        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(spacing: DS.Space.s3) {
                PrivyAppMark(logoURL: app.logoURL)
                    .scaleEffect(44 / DS.Mark.row)
                    .frame(width: 44, height: 44)
                Text(verbatim: app.name)
                    .dsText(.heading24)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 2) {
                if let usd {
                    Text(verbatim: mask ?? PrivyHomeFeed.usd(usd))
                        .dsText(.price40)
                        .monospacedDigit()
                        .foregroundStyle(DS.textPrimary)
                    Text(app.wallets.count == 1 ? "Wallet balance" : "Across \(app.wallets.count) wallets")
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textSecondary)
                } else {
                    Text("Balance not read yet — it fills in on the next sync")
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textSecondary)
                }
            }

            if !holdings.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(holdings, id: \.key) { symbol, value in
                        WalletRow(mark: .symbol("circle.grid.2x2.fill", tint: DS.tint),
                                  title: symbol, subtitleText: nil) {
                            Text(verbatim: mask ?? PrivyHomeFeed.usd(value))
                                .dsText(.price17)
                                .foregroundStyle(DS.textPrimary)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(app.wallets, id: \.address) { wallet in
                    DSCopyRow(value: wallet.address,
                              label: LocalizedStringKey(PrivyHomeFeed.shortAddress(wallet.address)),
                              sensitive: false)
                }
            }

            Text(verbatim: facts)
                .dsText(.subhead12)
                .foregroundStyle(DS.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var facts: String {
        let joined = app.createdAt.map {
            String(localized: "Joined \($0.formatted(.dateTime.month(.abbreviated).day().year()))")
        }
        let used = PrivyHomeFeed.lastUsed(app.lastActiveAt, now: .now)
        return [joined, used].compactMap { $0 }.joined(separator: " · ")
    }
}
