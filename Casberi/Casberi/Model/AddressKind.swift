import Foundation

/// What an address IS — detected, never asked (prd §169, 2026-07-21).
///
/// The person supplies a name; the chain supplies the kind. A kind picker in
/// the add sheet would be homework, and the app would know better than the
/// person half the time anyway — `eth_getCode` is a fact, "is this a contract?"
/// asked of a human is a quiz.
///
/// Both reads are KEYLESS and already run elsewhere in the app: the public
/// per-chain RPCs `WalletApprovals` measured (prd §84) and Safe's own
/// transaction service (`SafeBridge`, which caches positives forever). Naming
/// an address stays free on the keyed budget — the whole point of the book.
enum AddressKind {

    /// The EVM chains worth asking. First answer wins: a contract deployed on
    /// Base is a contract, and walking the rest to confirm it's also one on
    /// Ethereum tells the person nothing new.
    private static let networks = ["eth-mainnet", "base-mainnet", "arb-mainnet",
                                   "opt-mainnet", "matic-mainnet"]

    /// Detects and records the kind for one address. Safe first — a Safe IS a
    /// contract, so asking `eth_getCode` first would label every Safe with the
    /// less specific answer.
    ///
    /// Solana addresses return `.wallet` without a lookup: these reads are
    /// EVM-only, and guessing a kind we can't check would be exactly the
    /// invented status the honesty rule forbids.
    @MainActor
    static func detect(_ address: String) async {
        guard AddressBook.shared.entry(for: address) != nil else { return }
        guard ENS.isHexAddress(address) else {
            AddressBook.shared.setKind(.wallet, for: address)
            return
        }
        if await SafeBridge.isSafeAnywhere(address) {
            AddressBook.shared.setKind(.safe, for: address)
            return
        }
        if let isContract = await hasCode(address) {
            AddressBook.shared.setKind(isContract ? .contract : .wallet, for: address)
        }
        // Both reads failing leaves the kind `.unknown` — the honest resting
        // state. A row that hasn't been checked never claims to be a wallet.
    }

    /// Detects every entry whose kind is still unknown, one at a time so a
    /// bookful of new entries doesn't fan five RPCs out per row at once.
    @MainActor
    static func detectPending(limit: Int = 8) async {
        let pending = AddressBook.shared.all.filter { $0.kind == .unknown }.prefix(limit)
        for entry in pending { await detect(entry.address) }
    }

    /// True when the address has bytecode — an EOA answers "0x". nil when no
    /// chain answered at all, which must NOT be cached as "wallet" (a
    /// transient outage would permanently mislabel a contract).
    private static func hasCode(_ address: String) async -> Bool? {
        var answered = false
        for network in networks {
            guard let result = await WalletApprovals.rpcRead(
                network: network, method: "eth_getCode",
                params: [address, "latest"]) as? String else { continue }
            answered = true
            // An EIP-7702 delegation is NOT a contract (2026-07-25). Since
            // Pectra an ordinary wallet can carry `0xef0100` + a delegate
            // address as its "code", and reading that as bytecode labelled a
            // person's own account "Contract" and took away its identicon
            // face — the one thing the mark exists to say. Caught on
            // vitalik.eth, which is delegated. Treated as no code here, so a
            // genuine contract deployment on another chain can still answer.
            if WalletSafety.delegateAddress(from: result) != nil { continue }
            let code = result.dropFirst(2)   // strip "0x"
            if !code.isEmpty, code.contains(where: { $0 != "0" }) { return true }
            // An empty answer on this chain only rules it out here — the
            // address may still be a contract elsewhere, so keep asking, and
            // only report "no code anywhere" once the chains that can answer
            // have.
        }
        return answered ? false : nil
    }
}
