import Foundation

/// zk.money in the Wallet (2026-10-11): the app half of `ZkMoneyWire`.
/// A label, not a seat (prd §515's choice (a)): zk.money's moves are a
/// watched wallet's own transfers, so they land as Wallet rows and this only
/// NAMES them — "Deposited 459.58 DAI into zk.money", "Withdrew 25 DAI from
/// zk.money" — and resolves a tag to its public addresses.
///
/// Every read rides the Wallet's mainnet hosts (`WalletApprovals.rpcRead`),
/// already disclosed under the Wallet in `NetworkReach`. Nothing here reaches
/// zk.money's own servers, and the ENS gateway (a fresh deposit address per
/// lookup — the payment path) is never asked.
enum ZkMoney {
    /// The name every zk.money counterparty wears. A rename of the row
    /// (`CounterpartyRetitle`) reads it back through `knownName`.
    static let name = "zk.money"

    private static let depositsKey = "zkmoney.deposits.v1"
    private static let network = "eth-mainnet"

    /// Deposit addresses already recognised, lowercased. A deposit address
    /// is single-use and never stops being one, so a positive is kept for
    /// good; a negative is never kept — an address is code-less until the
    /// relayer sweeps it, minutes after the send. Read from any thread (the
    /// thing sheet's `knownLabel`), so it sits behind a lock; the defaults
    /// write happens OUTSIDE it (`defaults-lock-audit.py`, prd §721).
    private static let lock = NSLock()
    nonisolated(unsafe) private static var deposits: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: depositsKey) ?? [])

    private static func depositsSnapshot() -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        return deposits
    }

    /// The portals' DAI as last read in a pass that named a zk.money move.
    nonisolated(unsafe) static var lastPortalTotal: Decimal?

    /// zk.money's name for an address the app already knows to be zk.money's.
    static func knownName(for address: String) -> String? {
        let a = address.lowercased()
        return ZkMoneyWire.isPortal(a) || depositsSnapshot().contains(a) ? name : nil
    }

    /// Of `candidates` (the unnamed counterparties of SENT legs on Ethereum),
    /// which are zk.money deposit addresses — one `eth_getCode` each, at most
    /// `budget` a pass, the newest first. Positives are remembered.
    static func recognize(_ candidates: [String], budget: Int = 8) async -> Set<String> {
        var found = Set<String>()
        var asked = 0
        let known = depositsSnapshot()
        for a in candidates.map({ $0.lowercased() }) where !known.contains(a) {
            guard asked < budget else { break }
            asked += 1
            let code = await WalletApprovals.rpcRead(network: network, method: "eth_getCode",
                                                     params: [a, "latest"]) as? String
            if ZkMoneyWire.isDepositAddress(code: code) { found.insert(a) }
        }
        if !found.isEmpty {
            lock.lock()
            deposits.formUnion(found)
            // A cap: a set this size covers years of a person's own deposits,
            // and the label must never grow unbounded.
            let kept = Array(deposits.prefix(500))
            lock.unlock()
            UserDefaults.standard.set(kept, forKey: depositsKey)
        }
        return found
    }

    /// The DAI every zk.money portal holds right now, whole units: the public
    /// size of the pool your deposit joins. nil when the reads fail.
    static func portalTotal() async -> Decimal? {
        var total = Decimal(0)
        var read = false
        for d in ZkMoneyWire.deployments {
            let call = ZkMoneyWire.ethCall(to: ZkMoneyWire.dai, selector: ZkMoneyWire.Selector.balanceOf,
                                           arg: d.portal, id: 1)
            let params = (call["params"] as? [Any]) ?? []
            if let value = ZkMoneyWire.dai(await WalletApprovals.rpcRead(network: network, method: "eth_call",
                                                                          params: params) as? String) {
                total += value
                read = true
            }
        }
        return read ? total : nil
    }

    /// A row's note, said once at landing and dated: what is public about a
    /// zk.money move and what is not, and how big the pool was that day.
    static func note(portal: Decimal?, on date: Date = .now) -> String {
        var note = String(localized: "Money entering and leaving zk.money is public on Ethereum; inside it, payments and balances are private.")
        if let portal {
            note += " " + String(localized: "Its portals held \(ZkMoneyLink.plain(portal)) DAI on \(date.formatted(.dateTime.month(.abbreviated).day())).")
        }
        return note
    }

    /// A tag's public record — its Ethereum account, then its Aztec address
    /// — read off the NameRegistry and AccountMetadataRegistry. nil for a
    /// tag nobody has claimed, or when the reads fail.
    static func resolve(tag: String) async -> ZkMoneyWire.Record? {
        let owner = ZkMoneyWire.ethCall(to: ZkMoneyWire.nameRegistry, selector: ZkMoneyWire.Selector.ownerOf,
                                        arg: ZkMoneyWire.nameHash(tag), id: 1)
        guard let account = ZkMoneyWire.account(
            await WalletApprovals.rpcRead(network: network, method: "eth_call",
                                          params: (owner["params"] as? [Any]) ?? []) as? String) else { return nil }
        let record = ZkMoneyWire.ethCall(to: ZkMoneyWire.metadataRegistry, selector: ZkMoneyWire.Selector.getUserRecord,
                                         arg: account, id: 1)
        let raw = await WalletApprovals.rpcRead(network: network, method: "eth_call",
                                                params: (record["params"] as? [Any]) ?? []) as? String
        return ZkMoneyWire.record(tag: tag, account: account, userRecord: raw)
    }
}
