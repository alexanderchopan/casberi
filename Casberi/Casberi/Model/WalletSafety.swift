import Foundation
import SwiftData

/// Two more wallet safety signals (2026-07-20), both read-only and both
/// riding `WalletIngest.refresh`'s pass like `WalletApprovals`/`PeerBridge`:
///
/// (1) EIP-7702 delegation — an EOA can carry a `0xef0100`-prefixed 23-byte
///     "code" pointing at a delegate contract, turning it into a smart
///     account without changing its address. One `eth_getCode` per (wallet,
///     active EVM chain), watched forward like an approval cursor: a
///     delegate lands a thing only on CHANGE (appearing, changing, or
///     clearing) — first sight seeds the baseline silently, since a wallet
///     already delegated when first watched isn't news.
///
/// (2) Address-poisoning tagging — an incoming transfer whose counterparty
///     fuzzily mimics an address THIS wallet has actually sent to (same
///     leading/trailing hex, different address) is the scam's whole
///     mechanism: it relies on the lookalike showing up unflagged in
///     "recently interacted with" lists. This never touches any existing
///     dust/spam filter — a poisoning transfer already lands today,
///     unflagged; this only adds the warning. The trust anchor is
///     deliberately one-directional: an address you've SENT to is
///     unambiguous, while an incoming address is exactly what a poisoner
///     controls, so it can never itself become "known good".
///
/// (3) Spoofed token symbols (2026-07-21, prd §160) — the same attack as (2)
///     against the ASSET field: a token whose symbol is a confusable copy of
///     a well-known one ("ÚЅDС" for USDC). Purely local, no network at all —
///     the rule lives in `SymbolConfusables` and this only flags. Found on a
///     real watched wallet, where it had been landing unflagged into titles,
///     the money column, the holdings map and answers.
///
/// All three share the same grammar: the transfer LANDS, honestly, and wears
/// its flag. Nothing here hides a thing from the feed.
enum WalletSafety {

    // MARK: - EIP-7702 delegation

    private static func delegationKey(_ network: String, _ address: String) -> String {
        "wallet.delegation.\(network).\(address.lowercased())"
    }

    /// Unwatching wipes the delegation baseline too (called from
    /// `WalletStore.addresses.didSet`, next to the approvals/Peer cursor
    /// wipes) — the same "re-watching starts honest, at zero" rule.
    static func clearDelegation(address: String) {
        for network in WalletChainStore.allNetworkIDs
        where WalletApprovals.chainId(forNetwork: network) != nil {
            UserDefaults.standard.removeObject(forKey: delegationKey(network, address))
        }
    }

    /// The active EVM chains — reusing `WalletApprovals`' own knowledge of
    /// which networks it can read (`chainId(forNetwork:)` answering non-nil)
    /// rather than a second hand-kept list.
    private static func activeEVMNetworks() -> [String] {
        WalletChainStore.activeNetworkIDs().filter { WalletApprovals.chainId(forNetwork: $0) != nil }
    }

    /// Decodes an EIP-7702 delegation from `eth_getCode`'s reply — the magic
    /// `0xef0100` prefix (3 bytes) followed by the 20-byte delegate address.
    /// nil for plain undelegated code (`0x`) or genuine contract bytecode
    /// (any other shape) — a smart contract wallet is not a 7702 delegation.
    ///
    /// Shared with `AddressKind` (2026-07-25), which needs the same question
    /// answered for the opposite reason: this file asks "did a delegate
    /// appear?", the book asks "is this a contract or a person?" — and a
    /// delegated EOA is a person.
    static func delegateAddress(from codeHex: String) -> String? {
        let s = codeHex.lowercased()
        guard s.hasPrefix("0xef0100"), s.count == 48 else { return nil }
        return "0x" + s.suffix(40)
    }

    /// One CURRENTLY delegated (wallet, chain) pair — live state, like
    /// `WalletDeFi.positions`/`SafeBridge.pendingCounts`, deliberately
    /// separate from `sync`'s land-on-change alert. A delegation isn't
    /// inherently bad (it's how most smart-account wallets work), just worth
    /// surfacing — the Wallet screen's warnings band reads this directly
    /// rather than querying landed things, since a delegation that predates
    /// the watch never lands a thing at all.
    struct Delegation {
        let network: String
        let address: String
        let delegate: String
    }

    /// Every address currently delegated, across active EVM chains — nothing
    /// for an address with none (never a placeholder "not delegated" row).
    static func currentDelegations(addresses: [String]) async -> [Delegation] {
        guard !addresses.isEmpty else { return [] }
        var out: [Delegation] = []
        for network in activeEVMNetworks() {
            for address in addresses {
                guard let codeHex = await WalletApprovals.rpcRead(
                        network: network, method: "eth_getCode",
                        params: [address, "latest"]) as? String,
                      let delegate = delegateAddress(from: codeHex)
                else { continue }
                out.append(Delegation(network: network, address: address, delegate: delegate))
            }
        }
        return out
    }

    /// Reads each watched wallet's current delegate per active EVM chain and
    /// lands a thing only where it CHANGED since the last pass. Rides
    /// `WalletIngest.refresh` inside its running guard, like the approvals
    /// and Peer arms.
    @MainActor
    static func sync(context: ModelContext, addresses: [String], existing: Set<String>) async -> Int {
        guard !addresses.isEmpty else { return 0 }
        let defaults = UserDefaults.standard
        var added = 0
        for network in activeEVMNetworks() {
            for address in addresses {
                let key = delegationKey(network, address)
                // Presence of the KEY, not its value, is "first sight" — an
                // undelegated wallet's stored value is "" (empty, not nil),
                // so comparing against `lastKnown` (which is also nil for a
                // never-checked wallet) can't tell "never checked" from
                // "checked, still undelegated" apart. Getting this wrong
                // meant the single highest-value event this feature exists
                // to catch — a previously-clean wallet's FIRST real
                // delegation — read as "first sight" and never landed
                // (caught in review, 2026-07-20): the stored value only
                // ever changes away from "" on that first delegation, so the
                // old value-based check always mistook it for the seed.
                let neverChecked = defaults.object(forKey: key) == nil
                guard let codeHex = await WalletApprovals.rpcRead(
                        network: network, method: "eth_getCode",
                        params: [address, "latest"]) as? String
                else { continue }   // unreadable this pass — no false clear, retry next time
                let delegate = delegateAddress(from: codeHex)
                let stored = delegate ?? ""
                let lastKnown = defaults.string(forKey: key) ?? ""
                // Always write — every pass, change or not — so presence
                // alone can answer "seen before" next time.
                defaults.set(stored, forKey: key)
                guard !neverChecked else { continue }   // seed the baseline silently
                guard stored != lastKnown else { continue }   // no change — nothing to land
                let ref = "wallet:delegation:\(network):\(address.lowercased()):"
                    + String(Int(Date.now.timeIntervalSince1970))
                guard !existing.contains(ref) else { continue }
                let title: String
                if let delegate {
                    let label = WalletIngest.knownLabel(for: delegate)
                        ?? WalletStore.shortAddress(delegate)
                    title = String(localized: "Your wallet now delegates to \(label)")
                } else {
                    title = String(localized: "Your wallet's delegation was removed")
                }
                let content = WalletIngest.explorerAddressURL(forNetwork: network, address: address) ?? ""
                let thing = Thing(kind: .transaction, title: title, content: content,
                                  source: "Wallet", sourceRef: ref)
                thing.walletAddress = address
                context.insert(thing)
                SpotlightIndex.index([thing])
                added += 1
            }
        }
        if added > 0 { context.saveHonestly() }
        return added
    }

    /// `-delegationProbe YES` — reports each watched wallet's CURRENT
    /// delegate per chain, bypassing the land-on-change gate (so a probe run
    /// against an already-delegated wallet still reports something, rather
    /// than needing a live delegation change to verify anything).
    @MainActor
    static func probe() async -> String {
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched).filter { ENS.isHexAddress($0) }
        guard !addresses.isEmpty else { return "no EVM wallets watched" }
        var lines: [String] = []
        for address in addresses {
            for network in activeEVMNetworks() {
                guard let codeHex = await WalletApprovals.rpcRead(
                        network: network, method: "eth_getCode",
                        params: [address, "latest"]) as? String
                else {
                    lines.append("\(WalletStore.shortAddress(address)) \(network): unreadable")
                    continue
                }
                if let delegate = delegateAddress(from: codeHex) {
                    lines.append("\(WalletStore.shortAddress(address)) \(network): delegates to \(delegate)")
                } else {
                    lines.append("\(WalletStore.shortAddress(address)) \(network): none")
                }
            }
        }
        return lines.joined(separator: " | ")
    }

    // MARK: - Address poisoning

    /// Addresses each watched wallet has SENT to, lowercased — the trust
    /// signal poisoning detection anchors on. One fetch per pass, keyed by
    /// owner; a partial fetch (only the two fields poisoning needs).
    @MainActor
    static func knownGoodCounterparties(context: ModelContext, owners: [String]) -> [String: Set<String>] {
        guard !owners.isEmpty else { return [:] }
        let ownerSet = Set(owners.map { $0.lowercased() })
        var descriptor = FetchDescriptor<Thing>(predicate: #Predicate {
            $0.transferDirection == "sent" && $0.counterpartyAddress != nil
        })
        descriptor.propertiesToFetch = [\.walletAddress, \.counterpartyAddress]
        let things = (try? context.fetch(descriptor)) ?? []
        var out: [String: Set<String>] = [:]
        for t in things {
            guard let owner = t.walletAddress?.lowercased(), ownerSet.contains(owner),
                  let cp = t.counterpartyAddress?.lowercased() else { continue }
            out[owner, default: []].insert(cp)
        }
        return out
    }

    /// The fuzzy-match rule: same first 4 and last 4 hex chars as a KNOWN
    /// GOOD address, but not identical to it — shared by the real ingest-time
    /// flag and the read-only probe, so testing the rule doesn't need a
    /// second copy of it.
    private static func isFuzzyMatch(_ candidate: String, against knownGood: Set<String>) -> Bool {
        guard ENS.isHexAddress(candidate) else { return false }
        let body = candidate.dropFirst(2)
        for good in knownGood where good != candidate {
            guard ENS.isHexAddress(good) else { continue }
            let goodBody = good.dropFirst(2)
            if body.prefix(4) == goodBody.prefix(4), body.suffix(4) == goodBody.suffix(4) {
                return true
            }
        }
        return false
    }

    /// Flags `thing` when its counterparty fuzzily mimics one of
    /// `knownGood` — only ever called for a RECEIVED transfer, and only sets
    /// `securityFlag`; the thing still lands honestly as a transfer either
    /// way.
    @MainActor
    static func flagPoisoning(_ thing: Thing, knownGood: Set<String>) {
        guard let cp = thing.counterpartyAddress?.lowercased(),
              isFuzzyMatch(cp, against: knownGood) else { return }
        thing.addSecurityFlag("poisoning")
    }

    // MARK: - Spoofed token symbols

    /// Flags `thing` when a token symbol in the transfer is a confusable copy
    /// of a well-known one — the same class of attack as poisoning, aimed at
    /// the asset field instead of the address (prd §160, 2026-07-21). The rule
    /// itself lives in `SymbolConfusables`; this is only the flagging.
    ///
    /// Called for EVERY transfer, not just received ones: unlike poisoning —
    /// where an outgoing address is one you chose — a spoofed symbol lies just
    /// as hard on the way out, and "Sent 100,000 ÚЅDС" is exactly the line
    /// someone would misread as having sent real USDC.
    @MainActor
    static func flagSpoofedSymbol(_ thing: Thing, symbols: [String]) {
        guard let spoof = symbols.first(where: { SymbolConfusables.isSuspicious($0) })
        else { return }
        thing.addSecurityFlag("symbol")
        // Recorded here because here is the only place that HAS it — see
        // `Thing.spoofedSymbol`. Every surface reads this rather than parsing
        // the sentence built from it.
        thing.spoofedSymbol = spoof
    }

    /// The spoofed symbol in a thing, whether or not it's flagged — the one
    /// scan rule, shared by the flag accessor, the heal pass and the probe so
    /// those three can never disagree about WHERE the symbol lives.
    ///
    /// The stored `spoofedSymbol` wins; the text scan is the fallback for
    /// transfers that landed before that field existed (`transferAmount`
    /// carries "100,000 ÚЅDС", and a swap, which has no amount field, carries
    /// both its symbols in the title).
    private static func spoofScan(_ thing: Thing) -> SymbolConfusables.Verdict? {
        if let stored = thing.spoofedSymbol,
           let v = SymbolConfusables.verdict(for: stored) { return v }
        if let amount = thing.transferAmount,
           let v = SymbolConfusables.firstSuspicious(in: amount) { return v }
        return SymbolConfusables.firstSuspicious(in: thing.title)
    }

    /// The verdict behind a thing's `"symbol"` flag — what the sheet's warning
    /// line and the Worth-a-look row say.
    static func spoofVerdict(for thing: Thing) -> SymbolConfusables.Verdict? {
        guard thing.hasSecurityFlag("symbol") else { return nil }
        return spoofScan(thing)
    }

    /// Flags the spoofed symbols ALREADY in the corpus, once.
    ///
    /// Without this the feature would have shipped doing nothing for the very
    /// wallet that revealed the attack: the ingest-time flag only ever sees
    /// NEW transfers, and `WalletIngest.refresh` dedupes on `sourceRef`, so a
    /// transfer that landed yesterday is never rebuilt and never re-examined.
    /// The first probe run measured exactly that gap — 21 confusable symbols
    /// in the corpus, 0 of them flagged.
    ///
    /// Runs at most once per install (the same "seed the baseline" idiom as
    /// the delegation cursor above, keyed by presence). Honest limit: a thing
    /// arriving later from another device via CloudKit lands already-decoded
    /// and misses this pass. That's the same shape as the poisoning flag's own
    /// gap and not worth a permanent full-corpus scan on every refresh — the
    /// probe is how you'd see it, and re-running the heal is one defaults key.
    @MainActor
    static func healSpoofedSymbols(context: ModelContext) -> Int {
        let key = "wallet.symbolHeal.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return 0 }
        let things = (try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Wallet" }))) ?? []
        var healed = 0
        for t in things where !t.hasSecurityFlag("symbol") {
            guard let v = spoofScan(t) else { continue }
            t.addSecurityFlag("symbol")
            t.spoofedSymbol = v.symbol
            healed += 1
        }
        // The key is written whether or not anything was healed — a clean
        // corpus must not re-scan on every launch forever.
        UserDefaults.standard.set(true, forKey: key)
        if healed > 0 { context.saveHonestly() }
        return healed
    }

    /// `-symbolProbe YES` — the read-only twin of `poisoningProbe`: runs the
    /// confusable rule over ALREADY-LANDED wallet things and reports what it
    /// finds, so the rule can be verified against a real corpus without
    /// waiting for a fresh spoofed transfer to arrive. Reports the flagged
    /// count separately from the count the rule finds NOW, since things landed
    /// before this shipped carry no flag — a gap between the two numbers is
    /// the backfill's size, not a bug.
    @MainActor
    static func symbolProbe(context: ModelContext) -> String {
        let all = (try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Wallet" }))) ?? []
        var found: [String] = []
        var alreadyFlagged = 0
        for t in all {
            if t.hasSecurityFlag("symbol") { alreadyFlagged += 1 }
            guard let v = spoofScan(t) else { continue }
            let scalars = v.symbol.unicodeScalars
                .map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
            found.append("\"\(v.symbol)\" [\(scalars)] → \(v.impersonating ?? "lookalike chars")")
        }
        guard !found.isEmpty else {
            return "\(all.count) wallet things scanned, no confusable symbols"
        }
        return "\(all.count) wallet things scanned, \(found.count) confusable "
            + "(\(alreadyFlagged) already flagged): " + found.prefix(8).joined(separator: " | ")
    }

    /// `-poisoningProbe YES` — runs the fuzzy-match rule over
    /// ALREADY-LANDED things (a read-only scan, not a live sync) and reports
    /// what it would flag — the matching logic is what's being verified, and
    /// it needs no live poisoning transfer to test against. Doesn't mutate
    /// anything; the real flag only ever sets `securityFlag` at ingest time.
    @MainActor
    static func poisoningProbe(context: ModelContext) -> String {
        let all = (try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Wallet" }))) ?? []
        let owners = Set(all.compactMap(\.walletAddress).map { $0.lowercased() })
        let knownGood = knownGoodCounterparties(context: context, owners: Array(owners))
        var matches = 0
        for t in all where t.transferDirection == "received" {
            guard let cp = t.counterpartyAddress?.lowercased() else { continue }
            let good = knownGood[t.walletAddress?.lowercased() ?? ""] ?? []
            if isFuzzyMatch(cp, against: good) { matches += 1 }
        }
        return "\(all.count) wallet things scanned, \(matches) look like poisoning"
    }
}
