import Foundation

/// zk.money in the Wallet (2026-10-11): the app half of `ZkMoneyWire`.
/// A label, not a seat (prd §515's choice (a)): zk.money's moves are a
/// watched wallet's own transfers, so they land as Wallet rows and this only
/// NAMES them — "Deposited 459.58 DAI into zk.money", "Withdrew 25 DAI from
/// zk.money" — and resolves a tag to its public addresses.
///
/// Every read rides the Wallet's mainnet hosts (`WalletApprovals.rpcRead`),
/// already disclosed under the Wallet in `NetworkReach`. Nothing here reaches
/// zk.money's own servers, except `depositAddress(tag:)`: Move's Send asks
/// the resolver's gateway for a fresh deposit address when you pay a tag
/// (prd §1692), disclosed under Your account.
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

    /// Whether a watched wallet has put money into zk.money on this device:
    /// one recognised deposit or savings address is enough (prd §1446).
    static var hasDeposited: Bool { !depositsSnapshot().isEmpty }

    /// The portals' DAI as last read in a pass that named a zk.money move.
    nonisolated(unsafe) static var lastPortalTotal: Decimal?

    // MARK: - Who a deposit address was for (prd §1767)

    private static let paidKey = "zkmoney.paid.v1"
    nonisolated(unsafe) private static var paid: [[String]] =
        (UserDefaults.standard.array(forKey: paidKey) as? [[String]]) ?? []

    /// The tag Send paid at this deposit address, as `bob.zk.money`; nil for
    /// an address it did not pay a tag at. Read from any thread.
    static func paidTag(at address: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return ZkMoneyWire.paidTag(paid, at: address).map(ZkMoneyWire.display)
    }

    /// Send paid these tags at these addresses: kept, and each address is a
    /// deposit address from now, before its sweep gives it code. The
    /// defaults writes happen outside the lock (prd §721).
    static func notePaid(_ pairs: [(address: String, tag: String)]) {
        guard !pairs.isEmpty else { return }
        lock.lock()
        paid = ZkMoneyWire.paid(paid, adding: pairs)
        deposits.formUnion(paid.prefix(pairs.count).map { $0[0] })
        let ledger = paid, kept = Array(deposits.prefix(500))
        lock.unlock()
        UserDefaults.standard.set(ledger, forKey: paidKey)
        UserDefaults.standard.set(kept, forKey: depositsKey)
    }

    /// What a zk.money address is called where a person is named: the tag
    /// paid there, else zk.money's own name.
    static func label(for address: String) -> String? {
        paidTag(at: address) ?? knownName(for: address)
    }

    /// zk.money's name for an address the app already knows to be zk.money's.
    static func knownName(for address: String) -> String? {
        let a = address.lowercased()
        return ZkMoneyWire.paysWithdrawals(a) || depositsSnapshot().contains(a) ? name : nil
    }

    /// Of the unnamed counterparties on Ethereum, which are zk.money's own
    /// single-use contracts — one `eth_getCode` each, at most `budget` a
    /// pass, the newest first. `sends` are recipients of what a watched
    /// wallet sent (a deposit address or a savings escrow); `receipts` are
    /// senders of what it received (a swap escrow paying out USDC or USDT,
    /// 2026-10-17). Each is named only in the role it was asked in, and
    /// positives are remembered.
    static func recognize(sends: [String], receipts: [String] = [], budget: Int = 8) async -> Set<String> {
        var found = Set<String>()
        var asked = 0
        let known = depositsSnapshot()
        let asks = sends.map { ($0.lowercased(), ZkMoneyWire.Role.deposit) }
            + receipts.map { ($0.lowercased(), ZkMoneyWire.Role.swapOut) }
        for (a, role) in asks where !known.contains(a) && !found.contains(a) {
            guard asked < budget else { break }
            asked += 1
            let code = await WalletApprovals.rpcRead(network: network, method: "eth_getCode",
                                                     params: [a, "latest"]) as? String
            if ZkMoneyWire.role(code: code) == role { found.insert(a) }
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

    // MARK: - Paying a tag (Aztec V6, 2026-11-03)

    /// What asking for a tag's deposit address came to.
    enum PayAnswer: Equatable {
        /// A fresh deposit address, proven on chain for today.
        case address(String)
        case notOnV6, unclaimed, unreachable
    }

    /// The demo's deposit address: made up, never asked of anyone.
    static let demoDeposit = "0x5a3e9d1b2c4f6a8e0d7c9b1a3f5e7d9c2b4a6e8f"

    /// A FRESH deposit address for `tag`, the one Move's Send pays: the
    /// resolver's lookup, its operator's gateway, then `resolveWithProof`
    /// on chain, which rebuilds the address and refuses any other
    /// (`ZkMoneyWire`'s MARK). Asked once per send, never kept: a deposit
    /// address is single-use, and its proof holds for its day only. The
    /// gateway learns which tag is paid and when, nothing about who pays
    /// (it is asked through Tor, as every Your account request is).
    static func depositAddress(tag: String) async -> PayAnswer {
        guard !DemoMode.isActive, let call = ZkMoneyWire.resolveCall(tag: tag) else { return .unreachable }
        // The resolver ENS names for zk.money now (prd §1750); the pinned
        // one only when the registry cannot be reached.
        var resolver = ZkMoneyWire.resolver
        if case .result(let word) = await WalletApprovals.ethCallKeepingRevert(network: network, to: ZkMoneyWire.ensRegistry,
                                                                              data: ZkMoneyWire.ensResolverCall),
           let named = ZkMoneyWire.namedResolver(result: word) {
            resolver = named
        }
        let lookup: ZkMoneyWire.Lookup
        switch await WalletApprovals.ethCallKeepingRevert(network: network, to: resolver, data: call) {
        case .reverted(let data): lookup = ZkMoneyWire.lookup(revert: data, from: resolver)
        case .result, .unreachable: return .unreachable
        }
        switch lookup {
        case .notOnV6: return .notOnV6
        case .unclaimed: return .unclaimed
        case .unreadable: return .unreachable
        case .offchain(let o):
            guard let url = ZkMoneyWire.gatewayURL(o),
                  let (data, http) = await IngestSupport.sendRequest(URLRequest(url: url, timeoutInterval: 30),
                                                                     service: "Your account"),
                  http.statusCode == 200,
                  let response = ZkMoneyWire.gatewayData(try? JSONSerialization.jsonObject(with: data)) else { return .unreachable }
            guard case .result(let proven) = await WalletApprovals.ethCallKeepingRevert(
                network: network, to: o.sender, data: ZkMoneyWire.callbackCall(o, response: response)),
                  let address = ZkMoneyWire.depositAddress(callbackResult: proven) else { return .unreachable }
            return .address(address)
        }
    }
}

// MARK: - Paying a saved request (prd §1745, §1748)

extension ZkMoney {
    /// What Pay opens Send with for a saved request.
    enum Payable {
        /// A long link, read: the sentence is written at once.
        case written(pay: ZkMoneyWire.RequestPayment, symbol: String?)
        /// A short link (prd §1748): it goes into To as it stands, and To
        /// looks it up as it does a pasted one.
        case link(String)
    }

    /// What Pay would open for `thing`, when it is a zk.money request still
    /// open: not expired, not already paid. nil otherwise, so no Pay is drawn
    /// (§83). The title's first words gate the read: this runs for every
    /// visible row (`VerbDerivation.verbs`), and only a request row parses
    /// its link again. A short link's expiry is not known until To reads it.
    static func payableRequest(_ thing: Thing, now: Date = .now) -> Payable? {
        guard thing.kind == .link, thing.mark != .done, thing.title.hasPrefix(ZkMoneyLink.requestTitleLead),
              let url = Capture.detectURL(in: thing.content) else { return nil }
        switch ZkMoneyLink.link(url.absoluteString) {
        case .request(let tag, let amount, let symbol, _, let expires)?:
            guard ZkMoneyWire.requestOpen(expires: expires, now: now) else { return nil }
            return .written(pay: ZkMoneyWire.requestPayment(tag: tag, amount: amount, symbol: symbol), symbol: symbol)
        case .shortRequest?:
            return .link(url.absoluteString)
        default:
            return nil
        }
    }

    /// The demo reads no chain: a short link there opens to this.
    static let demoRequest = ZkMoneyLink.Link.request(tag: "zac", amount: Decimal(string: "20.5"), symbol: "DAI", note: nil, expires: nil)

    /// **THE REQUEST A SHORT LINK NAMES (prd §1748).** The link's seed
    /// derives a tag; the Aztec engine hashes it and asks the node once for
    /// the records under it (`zkLinkLogs`: keyless, no wallet, no account);
    /// each is opened here with the seed (`ZkMoneyLink.open`), and the
    /// newest that opens to a request is it. nil when the engine is not
    /// there, the node finds nothing, or nothing opens.
    @MainActor
    static func request(short: ZkMoneyLink.Short) async -> ZkMoneyLink.Link? {
        guard short.kind == ZkMoneyLink.Short.request else { return nil }
        if DemoMode.isActive { return demoRequest }
        let seed = short.seed.map { String(format: "%02x", $0) }.joined()
        guard let out = try? await AztecEngine.shared.call("zkLinkLogs", [Int(short.kind), seed]) as? [String: Any],
              let records = out["payloads"] as? [[String]] else { return nil }
        for fields in records.reversed() {
            if let bytes = ZkMoneyLink.open(fields: fields, short: short),
               let link = ZkMoneyLink.requestPacket(bytes: bytes), case .request = link { return link }
        }
        return nil
    }
}
