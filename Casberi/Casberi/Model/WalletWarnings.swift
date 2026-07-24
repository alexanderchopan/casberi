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
    enum Kind: Hashable {
        case liquidation, poisoning, spoofedSymbol, approval, safe, delegation

        func label(_ n: Int) -> String {
            switch self {
            case .liquidation: n == 1 ? String(localized: "liquidation risk")
                                      : String(localized: "liquidation risks")
            case .poisoning:   n == 1 ? String(localized: "flagged transfer")
                                      : String(localized: "flagged transfers")
            case .spoofedSymbol: n == 1 ? String(localized: "fake symbol")
                                        : String(localized: "fake symbols")
            case .approval:    n == 1 ? String(localized: "active approval")
                                      : String(localized: "active approvals")
            case .safe:        n == 1 ? String(localized: "signature") : String(localized: "signatures")
            case .delegation:  n == 1 ? String(localized: "delegation") : String(localized: "delegations")
            }
        }

        /// The SF Symbol this kind wears everywhere it's shown as its own
        /// object — the tray's section headers and the feed card's badge row
        /// (prd §196) — so the two surfaces never pick different glyphs for
        /// the same kind.
        var glyph: String {
            switch self {
            case .liquidation:   "chart.line.downtrend.xyaxis"
            case .poisoning:     "eye.trianglebadge.exclamationmark.fill"
            case .spoofedSymbol: "doc.on.doc.fill"
            case .approval:      "key.fill"
            case .safe:          "signature"
            case .delegation:    "arrow.triangle.branch"
            }
        }

        /// Whether you can still DO something about this (2026-07-24, the
        /// Act/Aware reframe). `severity` alone had this backwards: a
        /// poisoning or spoofed-symbol transfer already happened — nothing
        /// undoes it, there's no button, it's just spam to recognize — yet
        /// it wore the loudest, reddest "critical" mark and, at real scale
        /// (a whale wallet's dozens of airdrops), buried the ONE thing that
        /// can still drain the wallet going forward: a live approval. This
        /// is the axis the tray sections by now: `isActionable` kinds lead
        /// as "Worth doing"; the rest fold into "Just so you know", muted by
        /// default and mutable, so red is spent only where it's earned.
        var isActionable: Bool {
            switch self {
            case .liquidation, .approval, .delegation, .safe: true
            case .poisoning, .spoofedSymbol: false
            }
        }
    }

    let id: String
    let severity: Severity
    let kind: Kind
    let title: String
    let subtitle: String?
    /// How many underlying things this warning stands for — 1 for the ones
    /// that are inherently singular (a delegation, a Safe's pending queue),
    /// N for the three aggregates (poisoning, spoofed symbols, active
    /// approvals) that roll many flagged things into one row.
    ///
    /// Added 2026-07-21 because the tile's subline was counting WARNINGS: with
    /// 21 spoofed-symbol transfers in the corpus it read "1 fake symbol",
    /// which is a fake status by the design law's own rule — and the aggregate
    /// warning's own title said "21" two taps away. Poisoning had the identical
    /// bug and is fixed by the same field.
    var count: Int = 1
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
    /// The approval/Permit2-grant things whose LIVE on-chain state (the same
    /// read `WalletPrepare`'s own card runs) says the grant is still active —
    /// carried the same way `flagged` is, so the tray can list each one with
    /// its own Revoke.cash door instead of a dead aggregate line (2026-07-23,
    /// prd §196: approvals used to land as plain feed things with no seat in
    /// this roll-up at all).
    var activeApprovals: [Thing] = []

    static func == (a: WalletLiveState, b: WalletLiveState) -> Bool {
        a.warnings == b.warnings
            && a.flagged.map(\.id) == b.flagged.map(\.id)
            && a.activeApprovals.map(\.id) == b.activeApprovals.map(\.id)
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

/// Whether the "Just so you know" pile — spam you can recognize but can't
/// act on — is muted (2026-07-24, the Act/Aware reframe's other half). Color
/// that never resolves teaches nothing: a wallet with dozens of airdrops
/// always shows red, so the person who's already recognized the pattern
/// gets to say so, and the feed's own badge stops crying wolf for it.
/// Persisted per install, not per wallet — recognizing spam doesn't need
/// re-teaching per address. Plain UserDefaults, not observed: the tray
/// mirrors it in its own `@State` for live redraws while open, and the
/// feed card re-reads it fresh the next time it's built (a sheet dismiss
/// already forces that).
enum WalletAwareness {
    private static let mutedKey = "wallet.awareness.muted"

    static var isMuted: Bool {
        get { UserDefaults.standard.bool(forKey: mutedKey) }
        set { UserDefaults.standard.set(newValue, forKey: mutedKey) }
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
        async let approvalsRead = WalletApprovals.activeApprovals(hexAddresses: resolved, context: context)

        let positions = await defi
        let morpho = await morphoBook ?? MorphoDeFi.Book()
        let safePending = await safe
        let delegations = await delegs
        let activeApprovals = await approvalsRead

        // The flagged transfers — a plain model fetch, no network. The
        // predicate asks only that a flag EXISTS: `securityFlag` holds a
        // comma-joined set now (poisoning and a spoofed symbol can both be
        // true of one transfer), so an equality test would miss any thing
        // wearing more than one. Which flag is which is decided in Swift,
        // below, over a list that is a handful of rows at most.
        let flagged = (try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Wallet" && $0.securityFlag != nil }
        ))) ?? []
        // Scoped the same way the rows are, so a wallet-scoped feed never
        // warns about another wallet's flagged transfer.
        let inScope = scope == nil ? flagged : flagged.filter { t in
            guard let a = t.walletAddress else { return false }
            return targets.contains { sameAddress($0, a) }
        }
        let poisoningCount = inScope.filter { $0.hasSecurityFlag("poisoning") }.count
        let symbolCount = inScope.filter { $0.hasSecurityFlag("symbol") }.count

        return WalletLiveState(
            positions: positions,
            morpho: morpho,
            warnings: warnings(positions: positions, morpho: morpho,
                               safePending: safePending,
                               delegations: delegations, poisoningCount: poisoningCount,
                               spoofedSymbolCount: symbolCount,
                               approvalCount: activeApprovals.count,
                               owner: owner),
            flagged: inScope,
            activeApprovals: activeApprovals)
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
                         spoofedSymbolCount: Int,
                         approvalCount: Int = 0,
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
                                     subtitle: nil, count: poisoningCount, address: nil))
        }
        // Critical, like poisoning: a symbol that copies USDC is a claim about
        // what you hold, and believing it is how the money goes.
        if spoofedSymbolCount > 0 {
            out.append(WalletWarning(id: "symbol", severity: .critical,
                                     kind: .spoofedSymbol,
                                     title: spoofedSymbolCount == 1
                                         ? String(localized: "1 transfer uses a fake token symbol")
                                         : String(localized: "\(spoofedSymbolCount) transfers use fake token symbols"),
                                     subtitle: nil, count: spoofedSymbolCount, address: nil))
        }
        // Notice, not critical: approving a spender is an everyday DeFi/NFT
        // action, not inherently dangerous the way poisoning/spoofing is —
        // the warning is that it's still LIVE, not that it happened.
        if approvalCount > 0 {
            out.append(WalletWarning(id: "approval", severity: .notice,
                                     kind: .approval,
                                     title: approvalCount == 1
                                         ? String(localized: "1 active approval")
                                         : String(localized: "\(approvalCount) active approvals"),
                                     subtitle: nil, count: approvalCount, address: nil))
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
            // The target itself is the fact worth a heads-up — a row that only
            // says "you delegate on Ethereum" makes the person open Revoke.cash
            // to find out to WHOM (user, 2026-07-24: "do we know what was
            // delegated, if so we should show it"). We already resolve it for
            // `subtitle`; the title states the whole fact now, same grammar the
            // Safe row already uses ("N signatures needed on <label>'s Safe").
            let target = WalletIngest.knownLabel(for: d.delegate)
                ?? WalletStore.shortAddress(d.delegate)
            out.append(WalletWarning(id: "delegation:\(d.network):\(d.address)", severity: .notice,
                                     kind: .delegation,
                                     title: String(localized: "\(label) delegates to \(target) on \(chain)"),
                                     subtitle: target,
                                     address: owner[d.address.lowercased()] ?? d.address))
        }
        return out.sorted { $0.severity == .critical && $1.severity != .critical }
    }

    /// The per-kind tally behind `summary(_:)` and the feed card's badge row
    /// (prd §196) — one shared count so the two surfaces can't disagree.
    /// Order is severity-first, same as `warnings` itself arrives sorted.
    static func breakdown(_ warnings: [WalletWarning])
        -> [(kind: WalletWarning.Kind, count: Int, severity: WalletWarning.Severity)] {
        var order: [WalletWarning.Kind] = []
        var counts: [String: Int] = [:]
        var severities: [String: WalletWarning.Severity] = [:]
        for w in warnings {
            let key = String(describing: w.kind)
            if counts[key] == nil { order.append(w.kind); severities[key] = w.severity }
            counts[key, default: 0] += w.count
        }
        return order.map { kind in
            let key = String(describing: kind)
            return (kind, counts[key] ?? 0, severities[key] ?? .notice)
        }
    }

    /// "1 delegation · 1 flagged transfer" — the tile's subline. Counts by
    /// kind in severity order (the list is already sorted), so the worst kind
    /// is named first and nothing claims more precision than a count.
    static func summary(_ warnings: [WalletWarning]) -> String {
        breakdown(warnings).map { "\($0.count) \($0.kind.label($0.count))" }
            .joined(separator: " · ")
    }
}
