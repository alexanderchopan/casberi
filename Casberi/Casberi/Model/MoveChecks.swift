import Foundation
import SwiftData

/// **WHAT MOVE LOOKS UP BEFORE YOU SIGN (prd §1509 item 2, §1513).** The
/// reads behind `MoveWarnings`: your own history (on the phone), OFAC's
/// sanctioned addresses (downloaded whole, matched on the phone), GoPlus's
/// report on the address (one request per address, through Tor), and when a
/// contract was made (Blockscout, through Tor).
///
/// **Why GoPlus and not a list (user, 2026-10-24: "per address and ofac"):**
/// the spec's candidate, ScamSniffer's public `address.json`, has not
/// changed since 2024-02-28 (only its domain list is refreshed daily), and
/// every other open address list measured is older. GoPlus reads
/// ScamSniffer's and SlowMist's live data, keyless; the cost is that the
/// address you are about to pay leaves the phone, through Tor, on a circuit
/// of its own. Its own `sanctioned` flag missed two of three OFAC addresses
/// tried, so sanctions come from OFAC's list instead.
///
/// The demo reads none of this: its findings come off `YourAccountDemo`.
enum MoveChecks {
    static let service = "Move's checks"

    // MARK: - History (on the phone)

    /// The addresses this account has sent to, lowercased, each with the
    /// newest day it was paid; received-from never counts (`MoveWarnings.isKnown`).
    @MainActor
    static func sentTo(_ account: String, context: ModelContext) -> [String: Date] {
        let me = account.lowercased(), asKept = account
        // The account's own rows only, in either spelling it is kept under;
        // the case-blind check below is the rule, this is the narrowing.
        var descriptor = FetchDescriptor<Thing>(predicate: #Predicate {
            ($0.walletAddress == asKept || $0.walletAddress == me)
                && $0.transferDirection == "sent" && $0.counterpartyAddress != nil
        })
        descriptor.propertiesToFetch = [\.walletAddress, \.counterpartyAddress, \.createdAt]
        var out: [String: Date] = [:]
        for t in (try? context.fetch(descriptor)) ?? [] where t.walletAddress?.lowercased() == me {
            guard let cp = t.counterpartyAddress?.lowercased() else { continue }
            if out[cp].map({ $0 < t.createdAt }) ?? true { out[cp] = t.createdAt }
        }
        return out
    }

    /// Whether this account's history ever moved `symbol` (in or out).
    @MainActor
    static func used(_ symbol: String, by account: String, context: ModelContext) -> Bool {
        let me = account.lowercased(), asKept = account
        let suffix = " " + symbol
        var descriptor = FetchDescriptor<Thing>(predicate: #Predicate {
            ($0.walletAddress == asKept || $0.walletAddress == me) && $0.transferAmount != nil
        })
        descriptor.propertiesToFetch = [\.walletAddress, \.transferAmount]
        return ((try? context.fetch(descriptor)) ?? []).contains {
            $0.walletAddress?.lowercased() == me && ($0.transferAmount?.hasSuffix(suffix) ?? false)
        }
    }

    /// Names you typed in the book, by address (`WalletSafety`'s second
    /// anchor: an auto-name is how a poisoner's own dust lands there).
    @MainActor
    static func named() -> [String: String] {
        var out: [String: String] = [:]
        for e in AddressBook.shared.all
        where !WalletStore.isAutoName(e.name, for: e.address) && ENS.isHexAddress(e.address) {
            out[e.address.lowercased()] = e.name
        }
        return out
    }

    // MARK: - OFAC's list

    static let sanctionsURL = "https://raw.githubusercontent.com/0xB10C/ofac-sanctioned-digital-currency-addresses/lists/sanctioned_addresses_ETH.json"
    /// The bundled starting copy's date: the list's own commit, 2026-10-01.
    static let bundledDate = Date(timeIntervalSince1970: 1_790_838_911)

    private static var keptURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ofac-sanctioned-eth.json")
    }

    /// When the kept copy was written: the day it was read.
    private static var keptDate: Date? {
        keptURL.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date }
    }

    /// The kept copy, else the bundled one: the addresses and the copy's date.
    static func sanctions() -> (addresses: Set<String>, date: Date)? {
        if let url = keptURL, let data = try? Data(contentsOf: url), let list = MoveWarnings.ofacList(data) {
            return (Set(list), keptDate ?? bundledDate)
        }
        guard let url = Bundle.main.url(forResource: "OFACSanctionedETH", withExtension: "json"),
              let data = try? Data(contentsOf: url), let list = MoveWarnings.ofacList(data) else { return nil }
        return (Set(list), bundledDate)
    }

    /// Once a day on the foreground sweep, with an account on this phone:
    /// the whole list, kept only if it parses and is not sharply smaller
    /// than the copy it replaces. It names no wallet.
    static func refreshSanctionsIfDue() {
        guard YourAccountKey.address != nil, !DemoMode.isActive else { return }
        if let last = keptDate, Date.now.timeIntervalSince(last) < 86_400 { return }
        Task.detached(priority: .utility) {
            guard let url = URL(string: sanctionsURL),
                  let (data, http) = await IngestSupport.sendRequest(URLRequest(url: url), service: service),
                  http.statusCode == 200 else { return }
            let fresh = MoveWarnings.ofacList(data)
            guard MoveWarnings.accepts(fresh, over: sanctions()?.addresses.count ?? 0), let keptURL else {
                #if DEBUG
                NSLog("moveChecks| sanctions refused: %d addresses", fresh?.count ?? -1)
                #endif
                return
            }
            try? FileManager.default.createDirectory(at: keptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: keptURL, options: .atomic)
        }
    }

    // MARK: - GoPlus and Blockscout (through Tor)

    private static let cache = Cache()

    /// GoPlus's report on `address` on `chainId`; nil when it did not answer.
    static func report(_ address: String, chainId: Int) async -> MoveWarnings.Report? {
        let key = "\(chainId)|\(address.lowercased())"
        if let hit = await cache.report(key) { return hit }
        guard let url = URL(string: "https://api.gopluslabs.io/api/v1/address_security/\(address.lowercased())?chain_id=\(chainId)"),
              let (data, http) = await IngestSupport.sendRequest(URLRequest(url: url), service: service),
              http.statusCode == 200, let r = MoveWarnings.report(data) else { return nil }
        await cache.put(report: r, key)
        return r
    }

    /// The explorer each network's creation dates are read from.
    static func explorer(_ chainId: Int) -> String? {
        switch chainId {
        case 8453: "base.blockscout.com"
        case 1: "eth.blockscout.com"
        case 4663: "robinhoodchain.blockscout.com"
        default: nil
        }
    }

    /// When `address` was made as a contract, or that it is none; nil when
    /// the explorer did not answer. Blockscout's Cloudflare wall turns away
    /// a request without a browser's User-Agent (measured).
    static func creation(_ address: String, chainId: Int) async -> MoveWarnings.Creation? {
        let key = "\(chainId)|\(address.lowercased())"
        if let hit = await cache.creation(key) { return hit }
        guard let host = explorer(chainId),
              let url = URL(string: "https://\(host)/api?module=contract&action=getcontractcreation&contractaddresses=\(address.lowercased())")
        else { return nil }
        var request = URLRequest(url: url)
        request.setValue(IngestSupport.safariUserAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, http) = await IngestSupport.sendRequest(request, service: service),
              http.statusCode == 200, let c = MoveWarnings.creation(data) else { return nil }
        await cache.put(creation: c, key)
        return c
    }

    // MARK: - The other networks (prd §1711 item 6)

    /// Whether `address` was ever used on `net`: a contract there (its
    /// code), a send from it (its nonce), else any transaction or token
    /// transfer Blockscout lists for it. The node reads go to the network's
    /// own nodes as the account's do, Blockscout's through Tor. nil when it
    /// cannot be told.
    static func presence(_ address: String, on net: YourAccountOp.Network) async -> MoveWarnings.Presence? {
        let key = "\(net.chainId)|\(address.lowercased())"
        if let hit = await cache.presence(key) { return hit }
        guard let code = (try? await YourAccountChain.rpc(net, "eth_getCode", [address, "latest"]) as? String)?.lowercased()
        else { return nil }
        let hasCode = code.count > 2 && code != "0x0"
        // An EIP-7702 delegation ("0xef0100" and the delegate) is a person's
        // own key with code beside it: the key holds on every network, so it
        // counts as used here, never as a contract missing elsewhere.
        let contract = hasCode && !code.hasPrefix("0xef0100")
        var used = hasCode
        if !used, let nonce = try? await YourAccountChain.rpc(net, "eth_getTransactionCount", [address, "latest"]) as? String {
            used = PrivateMoney.decimal(hex: nonce) != "0"
        }
        if !used {
            var answered = false
            for action in ["txlist", "tokentx"] where !used {
                guard let host = explorer(net.chainId),
                      let url = URL(string: "https://\(host)/api?module=account&action=\(action)&address=\(address.lowercased())&page=1&offset=1")
                else { break }
                var request = URLRequest(url: url)
                request.setValue(IngestSupport.safariUserAgent, forHTTPHeaderField: "User-Agent")
                guard let (data, http) = await IngestSupport.sendRequest(request, service: service), http.statusCode == 200,
                      let listed = MoveWarnings.listed(data) else { continue }
                answered = true
                used = listed
            }
            // Neither list answered: not known to be unused.
            guard answered else { return nil }
        }
        let found = MoveWarnings.Presence(contract: contract, used: used)
        await cache.put(presence: found, key)
        return found
    }

    /// The other-network finding for a send to `address` on `net`, every
    /// network of your account asked at once.
    static func otherNetwork(_ address: String, sending net: YourAccountOp.Network) async -> MoveWarnings.Finding? {
        guard YourAccountOp.networks.contains(net) else { return nil }
        var seen: [String: MoveWarnings.Presence] = [:]
        await withTaskGroup(of: (String, MoveWarnings.Presence?).self) { group in
            for n in YourAccountOp.networks { group.addTask { (n.name, await presence(address, on: n)) } }
            for await (name, p) in group { if let p { seen[name] = p } }
        }
        return MoveWarnings.otherNetwork(here: net.name, seen: seen, order: YourAccountOp.networks.map(\.name))
    }

    /// The same, for each of a sentence's recipients at once.
    static func otherNetworks(_ addresses: [String], sending net: YourAccountOp.Network) async -> [MoveWarnings.Finding] {
        await withTaskGroup(of: MoveWarnings.Finding?.self) { group in
            for a in addresses { group.addTask { await otherNetwork(a, sending: net) } }
            var out: [MoveWarnings.Finding] = []
            for await f in group { if let f { out.append(f) } }
            return out
        }
    }

    // MARK: - One recipient, every check (prd §1711 item 4)

    /// What Move looks up about one address your account is about to pay on
    /// `net`, outside Move's own sentence (an exit from Aztec): OFAC's list,
    /// your history, GoPlus, Blockscout's creation date and the other
    /// networks. The same reads, the same order of words.
    @MainActor
    static func recipient(_ address: String, from account: String, on net: YourAccountOp.Network,
                          context: ModelContext) async -> [MoveWarnings.Finding] {
        var found: [MoveWarnings.Finding] = []
        let a = address.lowercased()
        if let list = Self.sanctions(), list.addresses.contains(a) {
            found.append(.sanctioned(address: address, listed: list.date))
        }
        let sent = Self.sentTo(account, context: context)
        let book = Self.named()
        let own = Set([account.lowercased()])
        if !MoveWarnings.isKnown(address, sentTo: sent, named: Set(book.keys), own: own) {
            found.append(MoveWarnings.imitated(address, sentTo: sent, named: book, own: own,
                                               looksLike: AddressSafety.isLookalike) ?? .firstSend)
        }
        async let reported = Self.report(address, chainId: net.chainId)
        async let made = Self.creation(address, chainId: net.chainId)
        async let elsewhere = Self.otherNetwork(address, sending: net)
        if let r = await reported, r.reported { found.append(.scam(address: address, sources: r.sources)) }
        // A contract finding that says nothing is no finding, as Move's own.
        if case .at(let when)? = await made, case let days = MoveWarnings.ageDays(when, now: .now),
           MoveWarnings.contractLine(token: false, unverified: false, ageDays: days, neverUsed: sent[a] == nil) != nil {
            found.append(.contract(token: false, unverified: false, ageDays: days, neverUsed: sent[a] == nil))
        }
        if let f = await elsewhere { found.append(f) }
        return MoveWarnings.ordered(found)
    }

    /// An hour for a report (a fresh one can land), for good for a creation.
    /// A presence that is used stays used; an unused one is asked again
    /// after an hour.
    private actor Cache {
        private var reports: [String: (MoveWarnings.Report, Date)] = [:]
        private var creations: [String: MoveWarnings.Creation] = [:]
        private var presences: [String: (MoveWarnings.Presence, Date)] = [:]
        func presence(_ key: String) -> MoveWarnings.Presence? {
            guard let (p, at) = presences[key], p.used || Date.now.timeIntervalSince(at) < 3_600 else { return nil }
            return p
        }
        func put(presence: MoveWarnings.Presence, _ key: String) { presences[key] = (presence, .now) }
        func report(_ key: String) -> MoveWarnings.Report? {
            guard let (r, at) = reports[key], Date.now.timeIntervalSince(at) < 3_600 else { return nil }
            return r
        }
        func put(report: MoveWarnings.Report, _ key: String) { reports[key] = (report, .now) }
        func creation(_ key: String) -> MoveWarnings.Creation? { creations[key] }
        func put(creation: MoveWarnings.Creation, _ key: String) { creations[key] = creation }
    }
}
