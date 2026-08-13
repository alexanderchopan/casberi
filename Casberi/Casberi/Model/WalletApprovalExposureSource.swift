import Foundation
import SwiftData

/// The reading half of the approvals card (2026-08-03, prd §292) — everything
/// `WalletApprovalExposure` deliberately can't hold: `Thing`s, the chain, the
/// holdings read.
///
/// Split for the reason `WalletRiskScaleSource` is split from
/// `WalletRiskScale`: the arithmetic's failure mode is a wrong number that
/// renders perfectly, so the arithmetic is compiled as shipped by
/// `scripts/wallet-viz-selftest.sh` and can't be allowed to import anything.
///
/// ## No read here is new
///
/// `WalletWatch.liveState` already runs `WalletPrepare.check` over every landed
/// approval on every foreground pass — that check IS the live allowance read,
/// and until this pass it discarded the amount and kept only its sign. Prices
/// come from the holdings read the treemap already pays for, behind its own
/// ten-minute window. The only marginal cost is `WalletApprovals.tokenFacts`:
/// one `eth_call` pair the first time a token appears in an approval, cached
/// for the life of the install because neither a symbol nor a decimals can
/// change for a deployed contract.
///
/// Reads only. Tapping a row opens `ApprovalPrepareCard`, which prepares a
/// revoke and hands the signature somewhere else — prd §112, unchanged.
extension WalletApprovalExposure {

    /// Builds the exposure from approval things whose live check already ran.
    ///
    /// Takes the checks rather than re-running them: running them twice would
    /// double the room's RPC cost to state a fact it already had.
    @MainActor
    static func from(checked: [(thing: Thing, check: WalletPrepare.Check)])
        async -> WalletApprovalExposure {
        var priced: [Grant] = []
        var unpriced: [Grant] = []

        for (thing, check) in checked {
            // Corollary 6: the caller awaited before handing these over, and
            // every iteration below awaits again — so liveness is re-checked
            // per row, not once at the top.
            guard thing.isLive, check.active else { continue }
            guard let spenderHex = thing.counterpartyAddress,
                  let owner = thing.walletAddress else { continue }
            let name = WalletIngest.knownLabel(for: spenderHex)
            let grantedAt = thing.grantedAt

            // The token's name and scale. `Optional.map` can't carry an
            // `await` (it's `rethrows`, not `reasync`), so this is spelled out.
            var facts: (symbol: String?, decimals: Int?) = (nil, nil)
            if let contract = check.contract, let network = check.network {
                facts = await WalletApprovals.tokenFacts(network: network, contract: contract)
            }
            let symbol = facts.symbol
                ?? check.contract.map(WalletStore.shortAddress)
                ?? String(localized: "a token")

            func grant(usd: Double?, capTokens: Double?) -> Grant {
                Grant(thingID: thing.id,
                      spender: name ?? WalletStore.shortAddress(spenderHex),
                      spenderAddress: spenderHex,
                      named: name != nil,
                      symbol: symbol,
                      forAll: check.forAll,
                      unlimited: check.allowanceRaw >= WalletApprovals.unlimitedThreshold,
                      usd: usd, capTokens: capTokens, grantedAt: grantedAt)
            }

            // An operator grant has no amount and this app prices no NFT —
            // stated, never counted as zero.
            guard !check.forAll else {
                unpriced.append(grant(usd: nil, capTokens: nil))
                continue
            }

            var held: WalletIngest.HeldPosition?
            if let contract = check.contract, let network = check.network {
                held = await WalletIngest.heldPosition(owner: owner, network: network,
                                                       contract: contract)
            }
            let usd = atStake(allowanceRaw: check.allowanceRaw,
                              decimals: facts.decimals,
                              heldUSD: held?.usd, heldTokens: held?.amount,
                              unlimitedAt: WalletApprovals.unlimitedThreshold)
            let capTokens = facts.decimals.map { check.allowanceRaw / pow(10, Double($0)) }
            let row = grant(usd: usd, capTokens: capTokens)
            if usd == nil { unpriced.append(row) } else { priced.append(row) }
        }

        priced.sort { ($0.usd ?? 0) > ($1.usd ?? 0) }
        // The unpriceable rows carry no number to sort on, so they take the
        // other honest order: oldest first, which is the one that matters for
        // a grant nobody can put a figure on.
        unpriced.sort { ($0.grantedAt ?? .distantFuture) < ($1.grantedAt ?? .distantFuture) }
        return WalletApprovalExposure(priced: priced, unpriced: unpriced)
    }

    /// What ONE address can move right now — the same reading, scoped to a
    /// single spender, for that address's own card (2026-08-13, prd §372).
    ///
    /// ## Why the book needed this at all
    ///
    /// The card has always said what you and an address have DONE together
    /// ("40 · since Mar 3 · net −0.80 ETH") and never what that address can
    /// still DO. §292 computed exactly that and landed it on the approvals
    /// card alone, so the one screen where a person decides whether an address
    /// is trustworthy was the one screen that didn't show the only fact with a
    /// consequence. The approval rows were already on the card — an approval
    /// is a `Wallet` thing whose `counterpartyAddress` is the spender, so
    /// `AddressActivity` has always filed them here — wearing the same clothes
    /// as every transfer beside them.
    ///
    /// ## The scoping is on the SPENDER, which is the opposite end from
    /// `WalletApprovals.activeApprovals`
    ///
    /// That function filters on `walletAddress` — YOUR wallet, the grantor.
    /// This one filters on `counterpartyAddress` — the grantee. Same rows,
    /// opposite end, and confusing the two would show an address the approvals
    /// it was GIVEN by you as though you had given them to it.
    ///
    /// Matched through `AddressBook.key` rather than `lowercased()`, so this
    /// agrees with the book about what one address IS — `CounterpartyRetitle`'s
    /// own rule, and the reason a `.eth` name that has been re-keyed still
    /// finds its grants.
    ///
    /// ## Cost
    ///
    /// One `WalletPrepare.check` per approval THIS address holds, which is a
    /// handful, against the room's whole-book pass. Nothing is cached and
    /// nothing is persisted: an allowance is live state (§216), and a stale
    /// "can move $8,924" is the fake status §83 bans in the one place it would
    /// be believed instantly.
    @MainActor
    static func forSpender(_ address: String, context: ModelContext)
        async -> WalletApprovalExposure {
        let wanted = AddressBook.key(for: address)
        let all = (try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate<Thing> { $0.source == "Wallet" }
        ))) ?? []
        let candidates = all.live.filter { thing in
            guard WalletPrepare.applies(to: thing),
                  let spender = thing.counterpartyAddress, !spender.isEmpty
            else { return false }
            return AddressBook.key(for: spender) == wanted
        }
        guard !candidates.isEmpty else { return WalletApprovalExposure() }
        var checked: [(thing: Thing, check: WalletPrepare.Check)] = []
        for thing in candidates {
            // Corollary 6: `check` awaits, so a Thing deleted out from under
            // this loop must not be read on the next turn.
            guard thing.isLive else { continue }
            if let check = await WalletPrepare.check(for: thing), check.active {
                checked.append((thing, check))
            }
        }
        return await from(checked: checked)
    }
}
