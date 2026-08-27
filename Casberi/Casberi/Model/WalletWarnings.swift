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
        case liquidation, poisoning, spoofedSymbol, fakeTransfer, approval, safe, delegation

        func label(_ n: Int) -> String {
            switch self {
            case .liquidation: n == 1 ? String(localized: "liquidation risk")
                                      : String(localized: "liquidation risks")
            case .poisoning:   n == 1 ? String(localized: "flagged transfer")
                                      : String(localized: "flagged transfers")
            case .spoofedSymbol: n == 1 ? String(localized: "fake symbol")
                                        : String(localized: "fake symbols")
            case .fakeTransfer: n == 1 ? String(localized: "spam transfer")
                                       : String(localized: "spam transfers")
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
            case .fakeTransfer:  "trash.fill"
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
            case .poisoning, .spoofedSymbol, .fakeTransfer: false
            }
        }
    }

    /// WHERE acting on this actually happens (2026-07-31, prd §241) — a
    /// label and the URL behind it.
    ///
    /// The app never signs, revokes or repays; prd §112's preparing-surface
    /// ruling settled that, and nothing here revisits it. What it settled was
    /// that the ACT lives elsewhere — not that the row should name elsewhere
    /// and then refuse to take you. Two of the four actionable kinds carried a
    /// door and two didn't: a Safe row read "Sign in the Safe app" as a dead
    /// sentence, and a liquidation row named a health factor with no route to
    /// the protocol holding it.
    ///
    /// Built HERE rather than in the view because this is where the facts a
    /// door needs already are — the protocol name, the chain, the Safe's own
    /// queue — and a view reverse-engineering them out of a title string is
    /// how a link goes quietly wrong.
    struct Action: Equatable {
        /// Names the destination, never the mechanism ("Open Aave", not
        /// "Fix"): the app can't perform this, so the label promises travel,
        /// not an outcome.
        let label: String
        let url: String
    }

    let id: String
    let severity: Severity
    let kind: Kind
    let title: String
    let subtitle: String?
    /// nil where no honest door exists — a liquidation on a protocol without
    /// a known app, or a Safe queue spanning several Safes at once (see
    /// `SafeBridge.Pending.queueURL`). A missing door renders NO pill rather
    /// than a disabled one; the design law's own rule about dead controls.
    var action: Action? = nil
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
    /// Where a lending protocol's own app lives — the door a liquidation row
    /// offers. Each URL was verified to answer 200 on 2026-07-31 rather than
    /// assumed; a link that 404s is a dead control wearing a promise.
    ///
    /// The protocol's own app ROOT, deliberately, not a per-position deep
    /// link: none of the three documents a stable per-position web URL, and
    /// the honest destination is the page that definitely exists (the same
    /// call `OneClawFetch.dashboard` makes for the same reason).
    static func appURL(forProtocol name: String) -> String? {
        switch name {
        case "Aave":   "https://app.aave.com/"
        case "Spark":  "https://app.spark.fi/"
        case "Morpho": "https://app.morpho.org/"
        default:       nil
        }
    }

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
    /// The Uniswap V3 liquidity book (2026-07-30) — read beside Aave/
    /// Morpho's in the same parallel pass.
    var uniswap: UniswapLiquidity.Book = UniswapLiquidity.Book()
    /// Hyperliquid and Aerodrome (2026-07-31, prd §240). Both were read every
    /// foreground pass by `WalletIngest.refresh`'s event sweeps and had NO
    /// seat on the screen at all — no card, no line, nothing in the crown
    /// number. They join the live state so `WalletComposition` can state
    /// them; both reads are coalesced behind the same 60s TTL the three above
    /// use, so adding them here costs no extra request inside a pass.
    var hyperliquid: HyperliquidDeFi.Book = HyperliquidDeFi.Book()
    var aerodrome: AerodromeDeFi.Book = AerodromeDeFi.Book()
    /// ether.fi's two halves (2026-07-31): the Cash account's collateral and
    /// credit line on Optimism, and the unstake queue on mainnet. Both join
    /// the same parallel pass and are coalesced behind the same 60s TTL as the
    /// books above, so stating them costs no extra request inside a pass.
    var etherfiCash: EtherFiCash.Book = EtherFiCash.Book()
    var etherfiUnstake: EtherFiUnstake.Book = EtherFiUnstake.Book()
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
    /// Those same grants, priced and ranked (2026-08-03, prd §292) — what each
    /// spender can actually move, which is the fact the count above can't
    /// carry. Built from the checks `activeApprovals` already ran, so it costs
    /// no read of its own.
    var exposure: WalletApprovalExposure = WalletApprovalExposure()
    /// Everything that can act AS the account rather than spend a token of it
    /// — Safe modules, an EIP-7702 delegate, Altana credentials (§293).
    ///
    /// Read here rather than by the card, because the card is drawn inside a
    /// `List` and a chain read hung off a row's `.task` fires on every scroll
    /// that remounts it. It is the cheapest read in this state (one `eth_call`
    /// per address plus a cached Safe lookup), and until §490 it had NO seat
    /// in any view at all — `WalletActingParties` was reachable only from a
    /// probe, so a Safe module that can move funds with no signature was
    /// invisible in the app that exists to point at exactly that.
    var acting: [WalletActingParties.Account] = []

    static func == (a: WalletLiveState, b: WalletLiveState) -> Bool {
        a.warnings == b.warnings
            && a.flagged.map(\.id) == b.flagged.map(\.id)
            && a.activeApprovals.map(\.id) == b.activeApprovals.map(\.id)
            && a.exposure == b.exposure
            && a.acting == b.acting
            && a.morpho == b.morpho
            && a.uniswap == b.uniswap
            && a.hyperliquid == b.hyperliquid
            && a.aerodrome == b.aerodrome
            && a.positions.count == b.positions.count
            && zip(a.positions, b.positions).allSatisfy {
                $0.address == $1.address && $0.network == $1.network
                    && $0.protocolName == $1.protocolName
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
        // `-seedVizDemo YES` (ProbeHooks, DEBUG-only trigger) OR the furnished
        // demo being active (2026-08-11, prd §351 follow-up — RELEASE-reachable,
        // since `DemoMode` itself ships to TestFlight/App Store) paints the DeFi
        // cards from synthetic books instead of the chain. It exists because
        // three of this room's visualizations — lending health, the veAERO melt
        // bar, the protocol composition strip — can only be photographed (or
        // furnished) from a wallet that really holds those positions, and both
        // marketing and the demo need them from a wallet that doesn't. Before
        // this the check itself was `#if DEBUG`, so a Release build (every
        // TestFlight/App Store build) compiled the whole branch away and
        // `DemoMode`'s wallet — which HAS a seeded balance/history via
        // `-seedWalletHistory`'s pattern — showed an empty "In protocols" strip
        // and no DeFi tiles, the exact silent gap this rule exists to prevent
        // (checked and confirmed against `demo-selftest.py`'s own reasoning:
        // a bridge gaining a capability with no textual signature needs a
        // human step, and nobody had taken it for this one).
        #if DEBUG
        let vizDemo = UserDefaults.standard.bool(forKey: "viz.demo")
        #else
        let vizDemo = false
        #endif
        if vizDemo || DemoMode.isActive {
            return WalletDemoState.state
        }
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
        // De-duped by the RESOLVED hex, not the watched spelling (2026-07-24,
        // crash fix): two watched entries that resolve to the same wallet —
        // an ENS name and its own hex, watched separately — used to run every
        // downstream read (positions, delegations, approvals) TWICE for the
        // identical address, producing two `WalletWarning`s with an
        // identical `id`. SwiftUI traps hard on a `ForEach` seeing a reused
        // id (confirmed via a field crash log: EXC_BREAKPOINT inside
        // `ForEachChild.updateValue()`) — the exact "crashes on open, only
        // once real data exists, never on a fresh install" signature this
        // was reported with, since a fresh install has no watched wallets to
        // collide.
        var seenHex = Set<String>()
        for target in targets {
            guard let hex = await WalletIngest.resolvedAddresses([target])
                .first(where: { ENS.isHexAddress($0) }) else { continue }
            guard seenHex.insert(hex.lowercased()).inserted else { continue }
            resolved.append(hex)
            owner[hex.lowercased()] = target
        }
        guard !resolved.isEmpty else { return WalletLiveState() }

        async let defi = WalletDeFi.positions(addresses: resolved)
        async let morphoBook = MorphoDeFi.book(addresses: resolved)
        async let uniswapBook = UniswapLiquidity.book(addresses: resolved)
        async let hyperBook = HyperliquidDeFi.book(addresses: resolved)
        async let aeroBook = AerodromeDeFi.book(addresses: resolved)
        async let cashBook = EtherFiCash.book(addresses: resolved)
        async let unstakeBook = EtherFiUnstake.book(addresses: resolved)
        async let safe = SafeBridge.pendingCounts(addresses: resolved)
        async let delegs = WalletSafety.currentDelegations(addresses: resolved)
        // Joins the same concurrent fan-out rather than running after it: it
        // shares `WalletSafety`'s delegation read and `SafeBridge`'s cached
        // module snapshot, so sequencing it would add latency and no safety
        // (prd §490).
        async let actingRead = WalletActingParties.read(addresses: resolved)
        async let approvalsRead = WalletApprovals.activeApprovals(hexAddresses: resolved, context: context)

        let positions = await defi
        let morpho = await morphoBook ?? MorphoDeFi.Book()
        let uniswap = await uniswapBook ?? UniswapLiquidity.Book()
        // An unreachable book is an EMPTY book here, exactly as Morpho's and
        // Uniswap's are above: the composition states what it could read and
        // says nothing about what it couldn't, which is the only shape that
        // can't overstate.
        let hyperliquid = await hyperBook ?? HyperliquidDeFi.Book()
        let aerodrome = await aeroBook ?? AerodromeDeFi.Book()
        // Unreachable is EMPTY here, exactly as the four books above — the
        // composition states what it could read and says nothing about what it
        // couldn't, the only shape that can't overstate.
        let etherfiCash = await cashBook ?? EtherFiCash.Book()
        let etherfiUnstake = await unstakeBook ?? EtherFiUnstake.Book()
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
        let fakeTransferCount = inScope.filter { $0.hasSecurityFlag("spam") }.count

        // Same belt-and-suspenders as `warnings()`'s own dedup: these two
        // also feed a `ForEach` (one row per `Thing`) directly, so a
        // duplicate `id` here traps a view exactly the same way.
        var seenApprovalIDs = Set<Thing.ID>()
        let dedupedChecked = activeApprovals.filter { seenApprovalIDs.insert($0.thing.id).inserted }
        let dedupedApprovals = dedupedChecked.map(\.thing)
        // Priced from the checks just read — no second pass over the chain
        // (2026-08-03, prd §292).
        let exposure = await WalletApprovalExposure.from(checked: dedupedChecked)
        var seenFlaggedIDs = Set<Thing.ID>()
        let dedupedFlagged = inScope.filter { seenFlaggedIDs.insert($0.id).inserted }

        return WalletLiveState(
            positions: positions,
            morpho: morpho,
            uniswap: uniswap,
            hyperliquid: hyperliquid,
            aerodrome: aerodrome,
            etherfiCash: etherfiCash,
            etherfiUnstake: etherfiUnstake,
            warnings: warnings(positions: positions, morpho: morpho,
                               safePending: safePending,
                               delegations: delegations, poisoningCount: poisoningCount,
                               spoofedSymbolCount: symbolCount,
                               fakeTransferCount: fakeTransferCount,
                               approvalCount: dedupedApprovals.count,
                               owner: owner),
            flagged: dedupedFlagged,
            activeApprovals: dedupedApprovals,
            exposure: exposure,
            acting: await actingRead)
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
                         safePending: [String: SafeBridge.Pending],
                         delegations: [WalletSafety.Delegation],
                         poisoningCount: Int,
                         spoofedSymbolCount: Int,
                         fakeTransferCount: Int = 0,
                         approvalCount: Int = 0,
                         owner: [String: String] = [:]) -> [WalletWarning] {
        let wallet = WalletStore.shared
        var out: [WalletWarning] = []
        for p in positions where (p.healthFactor ?? .infinity) < DeFiRisk.floor {
            let chain = WalletIngest.displayName(forNetwork: p.network) ?? p.network
            // Keyed by protocol too — Aave and Spark both run on Ethereum,
            // so two at-risk positions for the same wallet/chain would
            // otherwise share an `id` (a `ForEach` id collision, the crash
            // class this app has paid for before).
            out.append(WalletWarning(id: "defi:\(p.protocolName):\(p.network):\(p.address)", severity: .critical,
                                     kind: .liquidation,
                                     title: String(localized: "\(p.protocolName) position close to liquidation"),
                                     subtitle: "\(chain) · hf \(WalletIngest.format(p.healthFactor ?? 0))",
                                     action: WalletWarning.appURL(forProtocol: p.protocolName).map {
                                         WalletWarning.Action(label: String(localized: "Open \(p.protocolName)"), url: $0)
                                     },
                                     address: owner[p.address.lowercased()]))
        }
        // Morpho's markets are isolated, so each at-risk market warns on its
        // own (two risky markets are two liquidations, not one).
        for p in morpho.positions where (p.healthFactor ?? .infinity) < DeFiRisk.floor {
            let chain = WalletIngest.displayName(forNetwork: p.network) ?? p.network
            out.append(WalletWarning(id: "morpho:\(p.network):\(p.address):\(p.marketLabel)",
                                     severity: .critical,
                                     kind: .liquidation,
                                     title: String(localized: "Morpho position close to liquidation"),
                                     subtitle: "\(chain) · \(p.marketLabel) · hf \(WalletIngest.format(p.healthFactor ?? 0))",
                                     action: WalletWarning.appURL(forProtocol: "Morpho").map {
                                         WalletWarning.Action(label: String(localized: "Open Morpho"), url: $0)
                                     },
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
        // NOTICE, not critical — deliberately unlike its two neighbours. A
        // spoofed symbol is a claim about what you HOLD and believing it is
        // how the money goes; a fake transfer event claims something already
        // happened that didn't, and there is nothing to lose by it and nothing
        // to do about it. It is also the only one of the three that arrives by
        // the hundred (a measured whale wallet: 30 in one read), so ranking it
        // critical would spend all the red in the tray on noise and bury the
        // live approval underneath — the exact failure the Act/Aware reframe
        // was written to stop.
        if fakeTransferCount > 0 {
            out.append(WalletWarning(id: "fakeTransfer", severity: .notice,
                                     kind: .fakeTransfer,
                                     title: fakeTransferCount == 1
                                         ? String(localized: "1 transfer you didn't make")
                                         : String(localized: "\(fakeTransferCount) transfers you didn't make"),
                                     subtitle: String(localized: "Spam tokens announcing transfers from your address."),
                                     count: fakeTransferCount, address: nil))
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
        for (address, pending) in safePending.sorted(by: { $0.key < $1.key }) where pending.count > 0 {
            let label = wallet.label(forAddress: address) ?? WalletStore.shortAddress(address)
            let count = pending.count
            out.append(WalletWarning(id: "safe:\(address)", severity: .notice,
                                     kind: .safe,
                                     title: count == 1
                                         ? String(localized: "1 signature needed on \(label)'s Safe")
                                         : String(localized: "\(count) signatures needed on \(label)'s Safe"),
                                     subtitle: nil,
                                     // Straight to that Safe's own queue —
                                     // absent when the count spans Safes.
                                     action: pending.queueURL.map {
                                         WalletWarning.Action(label: String(localized: "Open Safe"), url: $0)
                                     },
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
                                     // Moved off the view (2026-07-31): the
                                     // tray used to build this URL itself from
                                     // `w.address`, which made it the one door
                                     // living somewhere different from the
                                     // other three. Same URL, same
                                     // `canServe` gate, one place.
                                     action: WalletApprovals.canServe(d.address)
                                         ? WalletWarning.Action(
                                             label: String(localized: "Revoke"),
                                             url: WalletApprovals.revokeURL(address: d.address))
                                         : nil,
                                     address: owner[d.address.lowercased()] ?? d.address))
        }
        // Belt-and-suspenders against the exact crash the resolved-hex dedup
        // above targets (2026-07-24): every `ForEach` that renders one row
        // per warning traps if two ever share an `id`. De-duping here too
        // means a duplicate from any OTHER path this function doesn't
        // already guard can't reach a view and crash it.
        var seenIDs = Set<String>()
        let deduped = out.filter { seenIDs.insert($0.id).inserted }
        return deduped.sorted { $0.severity == .critical && $1.severity != .critical }
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


/// The synthetic wallet books behind `-seedVizDemo` (2026-08-04) AND the
/// furnished demo (`DemoMode.isActive`, 2026-08-11) — RELEASE-reachable now,
/// not `#if DEBUG` (see `WalletWatch.liveState`'s own doc for why that gate
/// was a bug once `DemoMode` needed to reach this, not a decision to reopen).
///
/// Numbers chosen to be plainly demonstrative rather than plausible-as-real:
/// a healthy Aave position beside a Morpho one drifting toward risk, and two
/// veAERO locks — one melting, one permanent — because the melt bar's whole
/// claim is the DIFFERENCE between locked amount and remaining voting power,
/// and a single lock can't show it.
///
/// **UNISWAP AND HYPERLIQUID JOINED IT ON 2026-08-26 (prd §484), and their
/// absence is the shape this whole file exists to prevent.** Both are
/// connectable catalog offers, both are `BridgeStore.walletSeats` members,
/// and both were read every foreground pass by `WalletWatch.liveState` — so
/// on a real wallet they draw a card each and contribute to the composition
/// strip. In the demo they were the two empty books in a struct of five, so
/// the two seats had nothing to show and were exempted from
/// `demo-selftest.py`'s catalog-coverage check as if that were a property of
/// the bridges rather than of this fixture. A book here is the ONLY way
/// either can appear: `DemoMode` reaches nothing, and neither protocol lands
/// a `Thing` of its own, so no amount of corpus seeding could have reached
/// them.
///
/// Each is seeded to show the reading its seat is SOLD on rather than a
/// healthy row: Uniswap gets one position in range and one out (the alert
/// its catalog summary leads with — "stops earning the moment price leaves
/// its range, and nothing tells you"), and Hyperliquid gets an open perp
/// plus a spot balance, since the composition strip states the two as one
/// deposit and a perp account with no spot would hide half of that sum.
enum WalletDemoState {
    static var state: WalletLiveState {
        var s = WalletLiveState()
        s.positions = [
            .init(network: "eth-mainnet", address: "0xdemo", protocolName: "Aave",
                  totalCollateralUSD: 18_200, totalDebtUSD: 6_100, healthFactor: 2.4),
            .init(network: "base-mainnet", address: "0xdemo", protocolName: "Spark",
                  totalCollateralUSD: 4_800, totalDebtUSD: 0, healthFactor: nil),
        ]
        s.morpho = MorphoDeFi.Book(
            positions: [.init(network: "eth-mainnet", address: "0xdemo",
                              marketLabel: "wstETH / WETH", collateralUSD: 9_400,
                              supplyUSD: 0, borrowUSD: 4_900, healthFactor: 1.32)],
            vaults: [.init(network: "eth-mainnet", address: "0xdemo",
                           vaultName: "Steakhouse USDC", assetSymbol: "USDC",
                           usd: 12_600, vaultAddress: "0xvault",
                           totalAssetsUsd: 41_000_000, netApy: 0.058, allocation: [])])
        // Uniswap V3/V4 liquidity (2026-08-26). TWO positions and the pair is
        // the point: `UniswapLiquidity`'s alert fires BOTH ways, so a book of
        // in-range positions demonstrates half a feature. The out-of-range one
        // is V4 and therefore carries no on-chain fee reading — `fee0`/`fee1`
        // stay 0 there by the same rule the live read keeps (V4 has no cheap
        // `collect()` simulation), so the fixture can't imply a number the
        // real bridge would never have.
        s.uniswap = UniswapLiquidity.Book(positions: [
            .init(network: "eth-mainnet", address: "0xdemo", version: 3, tokenId: 884_120,
                  token0: "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
                  token1: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                  token0Symbol: "WETH", token1Symbol: "USDC", feeTier: 3_000,
                  tickLower: 199_800, tickUpper: 203_400, currentTick: 201_460,
                  inRange: true, uncollectedFee0: 0.0412, uncollectedFee1: 62.10,
                  uncollectedFeeUSD: 193, valueUSD: 7_400),
            .init(network: "base-mainnet", address: "0xdemo", version: 4, tokenId: 12_907,
                  token0: "0x4200000000000000000000000000000000000006",
                  token1: "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",
                  token0Symbol: "WETH", token1Symbol: "USDC", feeTier: 500,
                  tickLower: 204_200, tickUpper: 206_000, currentTick: 201_460,
                  inRange: false, uncollectedFee0: 0, uncollectedFee1: 0,
                  uncollectedFeeUSD: 34, valueUSD: 2_150),
        ])

        // Hyperliquid (2026-08-26) — one open perp, one spot balance, one
        // staked-HYPE delegation left out on purpose: the unlock countdown is
        // already seeded as a dated ROW (`DemoSeedAll.walletRoom`'s
        // "Staked HYPE unlocks"), and stating it here as well would put the
        // same fact on screen twice in one scroll.
        //
        // `liquidationPx` sits ~34% under the mark, comfortably outside
        // `isNearLiquidation` — the demo already carries a position drifting
        // toward risk (Morpho, hf 1.32), and a second alarm on the same screen
        // makes both read as decoration. `perpAccountValue` is the account's
        // own equity and is deliberately LARGER than `positionValue`: an
        // account is margin plus position, and making them equal would imply
        // full deployment nobody runs.
        s.hyperliquid = HyperliquidDeFi.Book(
            positions: [
                .init(owner: "0xdemo", account: "0xdemo", accountLabel: nil,
                      coin: "ETH", isLong: true, sizeAbs: 1.5, entryPx: 2_980,
                      markPx: 3_180, liquidationPx: 2_104, positionValue: 4_770,
                      leverageX: 3, leverageType: "cross",
                      unrealizedPnl: 300, fundingSinceOpen: -12.40),
            ],
            spot: [.init(symbol: "HYPE", amount: 42.5, usd: 1_260)],
            perpAccountValue: 5_120)

        s.aerodrome = AerodromeDeFi.Book(locks: [
            .init(owner: "0xdemo", tokenId: 41_882, amountAERO: 12_977,
                  votingPower: 5_342,
                  lockEnd: Calendar.current.date(byAdding: .day, value: 612, to: .now),
                  isPermanent: false, lastVoted: .now.addingTimeInterval(-4 * 86_400)),
            .init(owner: "0xdemo", tokenId: 52_104, amountAERO: 3_400,
                  votingPower: 3_400, lockEnd: nil, isPermanent: true,
                  lastVoted: .now.addingTimeInterval(-2 * 86_400)),
        ])

        // WHO CAN ACT FOR IT (prd §490). The demo's Permissions scope was
        // EMPTY without this and the chip therefore never appeared at all —
        // `liveState` returns this fixture wholesale in demo mode, so the
        // acting-parties read added to the live path is never reached here.
        //
        // Both fixtures are deliberately the kinds with NO dollar amount: the
        // token grants below are already priced, so what the demo was missing
        // is precisely the class that card exists to show — a holder no
        // money-ranked card can rank, which is the argument for the card.
        s.acting = [WalletActingParties.Account(
            address: "0xdemo",
            accountID: nil,
            parties: [
                .init(kind: .safeModule(safe: "0xdemo"),
                      address: "0x1f3b9a5c0d2e4f6a8b0c1d2e3f4a5b6c7d8e9f01",
                      name: "Spending limit"),
                .init(kind: .delegate(network: "eth-mainnet"),
                      address: "0x63c0c19a282a1b52b07dd5a65b58948a07dae32b",
                      name: "Metamask Delegator"),
            ],
            modulesUnreadable: false)]

        // The token half, so the card draws every rung it has rather than the
        // two the fixture above can reach. Ranked biggest-first, which is the
        // order `WalletApprovalExposure` itself produces and which the rungs
        // preserve when they name their two.
        s.exposure = WalletApprovalExposure(
            priced: [
                .init(thingID: UUID(), spender: "Uniswap",
                      spenderAddress: "0x7a250d5630b4cf539739df2c5dacb4c659f2488d",
                      named: true, symbol: "USDC", forAll: false, unlimited: true,
                      usd: 6_204, capTokens: nil,
                      grantedAt: .now.addingTimeInterval(-96 * 86_400)),
                .init(thingID: UUID(), spender: "1inch",
                      spenderAddress: "0x1111111254eeb25477b68fb85ed929f73a960582",
                      named: true, symbol: "USDT", forAll: false, unlimited: false,
                      usd: 500, capTokens: 500,
                      grantedAt: .now.addingTimeInterval(-14 * 86_400)),
            ],
            unpriced: [
                // An operator grant — all of one collection, at no stated
                // price, which is the rung a dollar ranking cannot place.
                .init(thingID: UUID(), spender: "OpenSea",
                      spenderAddress: "0x1e0049783f008a0085193e00003d00cd54003c71",
                      named: true, symbol: "Field Notes", forAll: true, unlimited: true,
                      usd: nil, capTokens: nil,
                      grantedAt: .now.addingTimeInterval(-220 * 86_400)),
            ])
        return s
    }
}
