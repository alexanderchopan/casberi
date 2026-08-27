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
        guard let entry = AddressBook.shared.entry(for: address) else { return }
        // `.key` is ASSERTED by the door that filed it, never detected — a
        // key is an ordinary EOA on-chain, so a re-check here could only ever
        // silently downgrade it. A devnet-only entry (vibenet) is gated the
        // same way: every read below is a MAINNET RPC, and asking one about a
        // vibenet keystore account answers "no code anywhere" and confidently
        // mislabels it `.wallet` (prd, the address-book unification, 2026-08-27).
        guard entry.kind != .key, !entry.isDevnetOnly else { return }
        guard ENS.isHexAddress(address) else {
            AddressBook.shared.setKind(.wallet, for: address)
            return
        }
        if await SafeBridge.isSafeAnywhere(address) {
            AddressBook.shared.setKind(.safe, for: address)
            return
        }
        guard let isContract = await hasCode(address) else {
            // Both reads failing leaves the kind `.unknown` — the honest
            // resting state. A row that hasn't been checked never claims to
            // be a wallet. An entry that already HAS a kind is stamped as
            // asked (`markKindChecked` refuses `.unknown`), so an address no
            // host will answer for can't burn the stale budget every pass.
            AddressBook.shared.markKindChecked(address)
            return
        }
        guard isContract else {
            AddressBook.shared.setKind(.wallet, for: address)
            return
        }
        // It has code — but "contract" is the least useful true thing you can
        // say about somebody's own smart wallet (2026-08-03, prd §294). Asked
        // only for addresses that got this far, so an EOA (the common case)
        // still costs exactly the reads it always did.
        let smart = await WalletActingParties.detectSmartAccount(address)
        AddressBook.shared.setKind(smart != nil ? .smartAccount : .contract, for: address)
        // Both reads failing leaves the kind `.unknown` — the honest resting
        // state. A row that hasn't been checked never claims to be a wallet.
    }

    /// How long a detected kind is believed before the chain is asked again
    /// (2026-08-13, prd §372).
    ///
    /// Thirty days is a deliberate compromise, not a guess at how often an
    /// address changes: the transition this exists for — a counterfactual
    /// smart-account address gaining code on its first UserOperation — happens
    /// ONCE per account and can happen any day, so no interval catches it
    /// promptly and any interval bounds how long the book is wrong. What the
    /// number really trades is RPC spend: `hasCode` walks all five chains for
    /// an EOA (it can only report "no code anywhere" once every chain has
    /// answered), and an EOA is most of a book, so a weekly sweep would re-read
    /// a fifty-address book about 250 times a week to learn nothing.
    static let recheckInterval: TimeInterval = 30 * 86_400

    /// Detects every entry whose kind is still unknown, then re-asks the
    /// stalest ones — one at a time so a bookful doesn't fan five RPCs out per
    /// row at once, and both halves inside ONE budget.
    ///
    /// ## Why a re-check exists at all
    ///
    /// The two migrations below (`recheckContractsOnce`, and `AddressBook`'s
    /// own `kindRecheck.7702`) are one-shots: they fire once per install and
    /// can only correct what was already wrong the day they shipped. Nothing
    /// re-asked after that, so a kind detected once was believed for life —
    /// see `Entry.kindCheckedAt` for the transition that makes that wrong.
    ///
    /// ## The unknown half keeps priority, and keeps its old behaviour
    ///
    /// An `.unknown` entry has never been resolved and is re-asked every pass;
    /// a stale one already has an answer that is probably still right. So the
    /// unknowns are taken first and the stale ones only fill what budget is
    /// left — on a book with new entries arriving, the re-check simply waits,
    /// which is the correct priority and also means this adds no cost at all
    /// to the case the old sweep was tuned for.
    ///
    /// `.safe` is never re-asked: a Safe is a deployed contract that stays one,
    /// `SafeBridge` caches the positive forever anyway, and re-asking it would
    /// spend the budget on the one kind that cannot change.
    ///
    /// Each check writes, because `kindCheckedAt` is stamped even when the
    /// answer is unchanged — that is what makes the sweep terminate. It is NOT
    /// wrapped in `AddressBook.batched`, which takes a synchronous closure and
    /// cannot hold an `await`. The cost is the one the unknown half already
    /// paid (a fresh book of eight unknowns has always been eight writes), and
    /// it is self-limiting: once a pass stamps them, those entries are quiet
    /// for `recheckInterval`, so the steady state writes nothing.
    @MainActor
    static func detectPending(limit: Int = 8) async {
        // Re-opens the contracts filed before smart accounts had a kind — runs
        // once ever, and is a no-op on every pass after that.
        recheckContractsOnce()
        let book = AddressBook.shared
        // `.unknown` is the priority queue's whole domain, so a devnet-only
        // address never leaves `.unknown` here — it is filtered out of BOTH
        // halves below instead, the same way `.key`/`.safe` are, rather than
        // being asked once and then quietly excluded forever after.
        let unknown = book.all.filter { $0.kind == .unknown && !$0.isDevnetOnly }.prefix(limit)
        for entry in unknown { await detect(entry.address) }

        let remaining = limit - unknown.count
        guard remaining > 0 else { return }
        let cutoff = Date(timeIntervalSinceNow: -recheckInterval)
        let stale = book.all
            .filter { $0.kind != .unknown && $0.kind != .safe && $0.kind != .key }
            .filter { !$0.isDevnetOnly }
            .filter { ($0.kindCheckedAt ?? .distantPast) < cutoff }
            // Stalest first, and nil sorts oldest — an entry written before
            // `kindCheckedAt` existed has genuinely never been re-asked.
            .sorted { ($0.kindCheckedAt ?? .distantPast) < ($1.kindCheckedAt ?? .distantPast) }
            .prefix(remaining)
        for entry in stale { await detect(entry.address) }
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

/// A one-off re-check for addresses already filed as `.contract` before smart
/// accounts had a kind of their own (2026-08-03, prd §294).
///
/// Without it the fix only reaches addresses added from today on: every smart
/// account already in the book carries a persisted `.contract` and nothing
/// would ever ask again. The same shape as `AddressBook`'s own
/// `kindRecheck.7702` migration, which existed for the same reason one
/// mechanism over.
extension AddressKind {
    private static let smartAccountRecheckKey = "wallet.addressBook.kindRecheck.smartAccount"

    /// Clears the stored kind for every `.contract` entry, ONCE, so the normal
    /// `detectPending` sweep re-asks them with the new question. Cheap: it
    /// re-reads only contracts, never the EOAs that make up most of a book.
    @MainActor
    static func recheckContractsOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: smartAccountRecheckKey) else { return }
        defaults.set(true, forKey: smartAccountRecheckKey)
        for entry in AddressBook.shared.all where entry.kind == .contract {
            AddressBook.shared.setKind(.unknown, for: entry.address)
        }
    }
}
