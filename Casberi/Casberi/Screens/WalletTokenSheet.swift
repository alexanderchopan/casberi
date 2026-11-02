import SwiftUI

/// **ONE TOKEN, WHERE IT IS (prd §1670).** Holdings sums a symbol across every
/// network and place; a tap on its row opens this sheet, which takes the sum
/// apart under one heading per kind of place, never mixed (user, 2026-11-02:
/// "you are mixing chains and places"): Networks (its contracts summed across
/// your wallets), then Accounts, each biggest first. Every token
/// opens here, so a tap never lands on the whole list ("a user may want to see
/// just that token"); the Tokens door and See all open the list. Its price
/// chart stands under the total (prd §1672).
struct WalletTokenSheet: View {
    let position: WalletPortfolio.Position

    /// The read's route, else one off its biggest contract.
    private var chartRoute: String? {
        position.route ?? position.contracts.lazy.compactMap { WalletIngest.route(forPartKey: $0.key) }.first
    }

    /// What kind of place holds it, in the order the sheet lists them: on a
    /// network, or in an ACCOUNT someone else holds for you — a bank, an
    /// exchange, Wise, an app — one word for all (prd §1670, user: "is Wise a
    /// bank? Maybe we just create one generic word for all").
    enum Kind: Int, CaseIterable {
        case network, wallet, account

        var title: String {
            switch self {
            case .network: String(localized: "Networks")
            case .wallet:  String(localized: "Wallets")
            case .account: String(localized: "Accounts")
            }
        }

        /// A holder that is not a watched wallet, by its id. Validators are
        /// ETH staked on Ethereum itself.
        static func of(holder id: String) -> Kind {
            id == WalletPortfolio.validatorHolderID ? .network : .account
        }
    }

    struct Place: Identifiable, Equatable {
        let id: String
        let name: String
        /// The network's or the place's mark, by name.
        let mark: String
        let usd: Double
        let kind: Kind
        /// A wallet's address, for its face instead of a mark.
        var face: String? = nil
    }

    /// A network's bundled mark (`BrandMark` names): its own coin's, or
    /// L2BEAT's for a rollup whose coin is ETH; the rest take a monogram.
    static let networkMarks: [String: String] = [
        "eth-mainnet": "eth", "base-mainnet": "l2b-base", "arb-mainnet": "arb", "opt-mainnet": "op",
        "matic-mainnet": "matic", "solana-mainnet": "sol", "hyperliquid-mainnet": "hyperliquid",
        "robinhood-mainnet": "l2b-robinhood", "worldchain-mainnet": "l2b-worldchain",
    ]

    /// Networks from the contract parts, summed across wallets; each place
    /// that is not a wallet under its kind; a wallet whose stake was read
    /// with no contracts by its own name. Grouped by kind, biggest first.
    static func places(_ position: WalletPortfolio.Position,
                       networkName: (String) -> String) -> [(Kind, [Place])] {
        var byNetwork: [String: Double] = [:]
        for part in position.parts {
            let network = String(part.key.split(separator: ":", maxSplits: 1).first ?? Substring(part.key))
            byNetwork[network, default: 0] += part.usd
        }
        var places = byNetwork.map { network, usd in
            let name = networkName(network)
            return Place(id: "network:\(network)", name: name, mark: networkMarks[network] ?? name,
                         usd: usd, kind: .network)
        }
        let walletsWithParts = Set(position.parts.map { $0.holder.lowercased() })
        for holder in position.holders where holder.usd > 0 {
            if WalletPortfolio.isVenue(holder.address) {
                places.append(Place(id: "place:\(holder.address)", name: holder.label, mark: holder.label,
                                    usd: holder.usd, kind: Kind.of(holder: holder.address)))
            } else if !walletsWithParts.contains(holder.address.lowercased()) {
                places.append(Place(id: "wallet:\(holder.address)", name: holder.label, mark: position.symbol,
                                    usd: holder.usd, kind: .wallet, face: holder.address))
            }
        }
        return Kind.allCases.compactMap { kind in
            let rows = places.filter { $0.kind == kind }
                .sorted { $0.usd == $1.usd ? $0.name < $1.name : $0.usd > $1.usd }
            return rows.isEmpty ? nil : (kind, rows)
        }
    }

    var body: some View {
        let groups = Self.places(position) { HiddenTokens.place("\($0):native") }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DSSheetHead(disc: { AssetMark(name: position.symbol, size: DS.Face.shelf) },
                            lead: String(localized: "Token"),
                            title: position.symbol)
                Text(WalletValue.exactMoney(position.usd))
                    .dsText(.price40)
                    .foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                    .padding(.horizontal, DS.Space.s4)
                // **ITS PRICE, IN THE SHEET (prd §1672, user: "presumably the
                // token sheet should w/ price")**: the chart of its biggest
                // contract, a native coin's through its wrapped token.
                // The demo reaches nothing (§483), so it draws no chart.
                if !DemoMode.isActive, let route = chartRoute,
                   let r = TokenQuickRoute.from(sentinel: "@token:\(route)") {
                    TokenChartView(chain: r.chain, address: r.address) { EmptyView() }
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s4)
                }
                ForEach(groups, id: \.0) { kind, rows in
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        WalletSectionLabel(title: kind.title)
                        ForEach(rows) { place in
                            WalletRow(mark: place.face.map { .face($0) } ?? .asset(place.mark, tint: DS.textSecondary),
                                      title: place.name) {
                                WalletRowValue(value: WalletValue.exactMoney(place.usd))
                            }
                        }
                    }
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s6)
                }
            }
            .padding(.bottom, DS.Space.s6)
        }
        .scrollIndicators(.hidden)
        .dsInk()
        .dsReadSheet()
    }
}
