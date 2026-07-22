import Foundation
import SwiftData

/// The wallet's "worth a look" aggregation — one thing worth a heads-up,
/// severity-ranked.
///
/// Lifted OUT of `WalletScreen` (2026-07-20, the surface split): warnings
/// moved to the Wallet FEED, where the reads live, while the manage screen
/// kept only connections. The aggregation itself is unchanged — it was always
/// a fresh roll-up over live state rather than a query for a "warning" kind
/// that doesn't exist, and no shared field spans Aave/Safe/poisoning/
/// delegation to filter on. Living here rather than in a view means the feed
/// and any future surface read the same list, computed once.
struct WalletWarning: Identifiable, Equatable {
    enum Severity { case critical, notice }

    /// What KIND of thing is wrong. The feed's tile summarises by kind
    /// ("1 delegation · 1 flagged transfer") rather than quoting one warning's
    /// own words — a specific address is detail for the page behind the tap,
    /// not for a 150pt tile (user, 2026-07-20).
    enum Kind {
        case liquidation, poisoning, safe, delegation

        func label(_ n: Int) -> String {
            switch self {
            case .liquidation: n == 1 ? String(localized: "liquidation risk")
                                      : String(localized: "liquidation risks")
            case .poisoning:   n == 1 ? String(localized: "flagged transfer")
                                      : String(localized: "flagged transfers")
            case .safe:        n == 1 ? String(localized: "signature") : String(localized: "signatures")
            case .delegation:  n == 1 ? String(localized: "delegation") : String(localized: "delegations")
            }
        }
    }

    let id: String
    let severity: Severity
    let kind: Kind
    let title: String
    let subtitle: String?
    /// The WATCHED address this warning belongs to (the person's own spelling
    /// — "vitalik.eth", not the resolved hex), so a door can route to that
    /// wallet's screen. nil when the warning spans wallets (poisoning).
    let address: String?
}

/// The live, never-landed wallet state the feed's tiles draw: Aave positions
/// and the warnings rolled up from them plus Safe/poisoning/delegation.
///
/// "Live" is the operative word — none of this is a `Thing`. It's re-read each
/// foreground pass and held only in view state, exactly as `WalletScreen` held
/// it before the split.
struct WalletLiveState: Equatable {
    var positions: [WalletDeFi.Position] = []
    /// The Morpho book (2026-07-21) — market positions + vault deposits,
    /// read beside Aave's in the same parallel pass.
    var morpho: MorphoDeFi.Book = MorphoDeFi.Book()
    var warnings: [WalletWarning] = []
    /// The address-poisoning things behind the poisoning warning — carried so
    /// the Worth-a-look tray can list each flagged transfer as its own row
    /// with a door to its sheet, instead of a dead aggregate line.
    var flagged: [Thing] = []

    static func == (a: WalletLiveState, b: WalletLiveState) -> Bool {
        a.warnings == b.warnings
            && a.flagged.map(\.id) == b.flagged.map(\.id)
            && a.morpho == b.morpho
            && a.positions.count == b.positions.count
            && zip(a.positions, b.positions).allSatisfy {
                $0.address == $1.address && $0.network == $1.network
                    && $0.totalCollateralUSD == $1.totalCollateralUSD
                    && $0.totalDebtUSD == $1.totalDebtUSD
                    && $0.healthFactor == $1.healthFactor
            }
    }
}

enum WalletWatch {

    /// Reads every live-state source in parallel and rolls the warnings up.
    /// The four reads are independent, so the caller pays the slowest one
    /// rather than the sum — the same overlap `WalletScreen.sync` used.
    ///
    /// `scope` narrows to one watched address (the feed's wallet switcher);
    /// nil reads them all.
    @MainActor
    static func liveState(scopeTo scope: String? = nil,
                          context: ModelContext) async -> WalletLiveState {
        let watched = WalletStore.shared.addresses.map(\.address)
        let targets = scope.map { s in watched.filter { sameAddress($0, s) } } ?? watched
        guard !targets.isEmpty else { return WalletLiveState() }

        // Resolved one target at a time ON PURPOSE: `resolvedAddresses` skips
        // a name that fails to resolve, so zipping its batch output against
        // the input list would mis-pair every owner after the failure. Each
        // warning needs to know WHOSE it is (the door routes to that wallet),
        // and a wrong owner is worse than a slow loop over 1–5 wallets.
        var resolved: [String] = []
        var owner: [String: String] = [:]   // resolved (lowercased) → watched spelling
        for target in targets {
            guard let hex = await WalletIngest.resolvedAddresses([target])
                .first(where: { ENS.isHexAddress($0) }) else { continue }
            resolved.append(hex)
            owner[hex.lowercased()] = target
        }
        guard !resolved.isEmpty else { return WalletLiveState() }

        async let defi = WalletDeFi.positions(addresses: resolved)
        async let morphoBook = MorphoDeFi.book(addresses: resolved)
        async let safe = SafeBridge.pendingCounts(addresses: resolved)
        async let delegs = WalletSafety.currentDelegations(addresses: resolved)

        let positions = await defi
        let morpho = await morphoBook ?? MorphoDeFi.Book()
        let safePending = await safe
        let delegations = await delegs

        // Address poisoning — a plain model fetch, no network. Scoped the same
        // way the rows are, so a wallet-scoped feed never warns about another
        // wallet's flagged transfer.
        let flagged = (try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Wallet" && $0.securityFlag == "poisoning" }
        ))) ?? []
        let poisoningCount = scope == nil ? flagged.count : flagged.filter { t in
            guard let a = t.walletAddress else { return false }
            return targets.contains { sameAddress($0, a) }
        }.count

        let inScope = scope == nil ? flagged : flagged.filter { t in
            guard let a = t.walletAddress else { return false }
            return targets.contains { sameAddress($0, a) }
        }
        return WalletLiveState(
            positions: positions,
            morpho: morpho,
            warnings: warnings(positions: positions, morpho: morpho,
                               safePending: safePending,
                               delegations: delegations, poisoningCount: poisoningCount,
                               owner: owner),
            flagged: inScope)
    }

    /// Hex compares case-insensitively (EIP-55 case is a checksum), base58
    /// exactly (Solana case is identity) — the same equality the feed's
    /// switcher uses.
    static func sameAddress(_ a: String, _ b: String) -> Bool {
        ENS.isHexAddress(a) ? a.lowercased() == b.lowercased() : a == b
    }

    /// The roll-up, pure — every input passed in, so it's testable and the
    /// ordering rule (critical before notice, stable otherwise) lives in one
    /// readable place.
    static func warnings(positions: [WalletDeFi.Position],
                         morpho: MorphoDeFi.Book = MorphoDeFi.Book(),
                         safePending: [String: Int],
                         delegations: [WalletSafety.Delegation],
                         poisoningCount: Int,
                         owner: [String: String] = [:]) -> [WalletWarning] {
        let wallet = WalletStore.shared
        var out: [WalletWarning] = []
        for p in positions where (p.healthFactor ?? .infinity) < 1.5 {
            let chain = WalletIngest.displayName(forNetwork: p.network) ?? p.network
            out.append(WalletWarning(id: "defi:\(p.network):\(p.address)", severity: .critical,
                                     kind: .liquidation,
                                     title: String(localized: "Aave position close to liquidation"),
                                     subtitle: "\(chain) · hf \(WalletIngest.format(p.healthFactor ?? 0))",
                                     address: owner[p.address.lowercased()]))
        }
        // Morpho's markets are isolated, so each at-risk market warns on its
        // own (two risky markets are two liquidations, not one).
        for p in morpho.positions where (p.healthFactor ?? .infinity) < 1.5 {
            let chain = WalletIngest.displayName(forNetwork: p.network) ?? p.network
            out.append(WalletWarning(id: "morpho:\(p.network):\(p.address):\(p.marketLabel)",
                                     severity: .critical,
                                     kind: .liquidation,
                                     title: String(localized: "Morpho position close to liquidation"),
                                     subtitle: "\(chain) · \(p.marketLabel) · hf \(WalletIngest.format(p.healthFactor ?? 0))",
                                     address: owner[p.address.lowercased()]))
        }
        if poisoningCount > 0 {
            out.append(WalletWarning(id: "poisoning", severity: .critical,
                                     kind: .poisoning,
                                     title: poisoningCount == 1
                                         ? String(localized: "1 transfer looks like address poisoning")
                                         : String(localized: "\(poisoningCount) transfers look like address poisoning"),
                                     subtitle: nil, address: nil))
        }
        for (address, count) in safePending.sorted(by: { $0.key < $1.key }) where count > 0 {
            let label = wallet.label(forAddress: address) ?? WalletStore.shortAddress(address)
            out.append(WalletWarning(id: "safe:\(address)", severity: .notice,
                                     kind: .safe,
                                     title: count == 1
                                         ? String(localized: "1 signature needed on \(label)'s Safe")
                                         : String(localized: "\(count) signatures needed on \(label)'s Safe"),
                                     subtitle: nil,
                                     address: owner[address.lowercased()] ?? address))
        }
        for d in delegations {
            let chain = WalletIngest.displayName(forNetwork: d.network) ?? d.network
            let label = wallet.label(forAddress: d.address) ?? WalletStore.shortAddress(d.address)
            out.append(WalletWarning(id: "delegation:\(d.network):\(d.address)", severity: .notice,
                                     kind: .delegation,
                                     title: String(localized: "\(label) delegates on \(chain)"),
                                     subtitle: WalletIngest.knownLabel(for: d.delegate)
                                         ?? WalletStore.shortAddress(d.delegate),
                                     address: owner[d.address.lowercased()] ?? d.address))
        }
        return out.sorted { $0.severity == .critical && $1.severity != .critical }
    }

    /// "1 delegation · 1 flagged transfer" — the tile's subline. Counts by
    /// kind in severity order (the list is already sorted), so the worst kind
    /// is named first and nothing claims more precision than a count.
    static func summary(_ warnings: [WalletWarning]) -> String {
        var order: [WalletWarning.Kind] = []
        var counts: [String: Int] = [:]
        for w in warnings {
            let key = String(describing: w.kind)
            if counts[key] == nil { order.append(w.kind) }
            counts[key, default: 0] += 1
        }
        return order.map { kind in
            let n = counts[String(describing: kind)] ?? 0
            return "\(n) \(kind.label(n))"
        }.joined(separator: " · ")
    }
}
