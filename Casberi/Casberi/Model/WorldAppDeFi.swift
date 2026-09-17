import Foundation
import SwiftData

/// World App's money on World Chain, the reads (prd §795, 2026-09-16). The pure
/// half — addresses, calldata, the grant calendar, the username parse — is
/// `WorldApp`. Rides watched wallets like Aerodrome: no account, no key, no
/// seat. Every call is keyless: `eth_call` on the Wallet's own Alchemy World
/// Chain host, DeFiLlama for WLD's price, and World's public usernames service.
enum WorldAppDeFi {

    // MARK: - The WLD Vault (live state)

    struct VaultPosition: Equatable, Sendable {
        let owner: String
        let wld: Double
        /// nil when WLD's price could not be read — a missing price adds
        /// nothing to a total rather than a zero standing in for one.
        let usd: Double?
    }

    struct Book: Equatable, Sendable {
        var vaults: [VaultPosition] = []
        var isEmpty: Bool { vaults.isEmpty }
    }

    /// A deposit below this reads as nothing, `WalletIngest.holdingFloor`'s
    /// idea in WLD: yield dust left after a withdrawal is not a position.
    private static let dustWLD = 0.01

    private static let cache = CoalescingCache<Book>()

    /// The WLD Vault balance of each watched EVM wallet. Nil only when World
    /// Chain answered for NONE of them — an unreachable read is not an empty
    /// book, and the caller states only what it could read.
    static func book(addresses: [String]) async -> Book? {
        guard !DemoMode.isActive else { return Book() }
        let hex = addresses.filter { WorldApp.addressWord($0) != nil }
        guard !hex.isEmpty else { return Book() }
        let key = hex.map { $0.lowercased() }.sorted().joined(separator: ",")
        return await cache.value(key: key, ttl: 60) {
            await fetchBook(addresses: hex)
        }
    }

    private static func fetchBook(addresses: [String]) async -> Book? {
        var held: [(owner: String, wld: Double)] = []
        var reached = false
        for address in addresses {
            guard let data = WorldApp.balanceOfCalldata(owner: address),
                  let wld = WorldApp.amount18(fromWord: await ethCall(to: WorldApp.wldVault, data: data))
            else { continue }
            reached = true
            if wld >= dustWLD { held.append((address.lowercased(), wld)) }
        }
        guard reached else { return nil }
        guard !held.isEmpty else { return Book() }
        let prices = await DefiLlamaPrices.prices(for: [(network: WorldApp.network, contract: WorldApp.wld)])
        let price = prices["\(WorldApp.network)|\(WorldApp.wld)"].flatMap { $0.confidence >= 0.9 ? $0.price : nil }
        return Book(vaults: held.map { position in
            VaultPosition(owner: position.owner, wld: position.wld,
                          usd: price.map { position.wld * $0 })
        })
    }

    // MARK: - The next grant (a dated row)

    /// "World ID grant · 0.96 WLD opens Oct 1" for each watched wallet that has
    /// RECEIVED a grant before — the only evidence this app has that a wallet
    /// is a grant recipient, and one it already holds (a landed row whose
    /// counterparty is a holder World's `RecurringGrantDrop` names, §791). A
    /// reconciling `dueAt` row, `AerodromeDeFi`'s shape; one per wallet per
    /// grant, so next month lands a new row and this one keeps its date.
    ///
    /// Nothing about THIS person's claim is stated: whether they claimed is a
    /// nullifier, private by design. The row says when the next grant opens and
    /// what it pays, both read off World's contract. The amount is read live
    /// (`grant()` then `getAmount(id)`); a revert or a zero lands nothing.
    @MainActor
    static func syncGrantEvents(context: ModelContext, addresses: [String],
                                existing: Set<String>) async -> Int? {
        guard !DemoMode.isActive else { return 0 }
        let recipients = grantRecipients(context: context, among: addresses)
        guard !recipients.isEmpty else { return 0 }
        guard let opens = WorldApp.nextGrantOpens(after: .now) else { return 0 }
        let nextId = WorldApp.grantId(at: opens)
        guard let grantContract = WorldApp.address(fromWord: await ethCall(to: WorldApp.recurringGrantDrop,
                                                                           data: WorldApp.grantCalldata)),
              let amountData = WorldApp.getAmountCalldata(grantId: nextId)
        else { return nil }
        guard let amount = WorldApp.amount18(fromWord: await ethCall(to: grantContract, data: amountData)),
              amount > 0 else { return 0 }

        let when = opens.formatted(.dateTime.month(.abbreviated).day())
        let fresh = String(localized: "World ID grant · \(WalletIngest.format(amount)) WLD opens \(when)")
        var added = 0
        for owner in recipients {
            let ref = "worldapp:grant:\(owner):\(nextId)"
            if existing.contains(ref) {
                if let landed = try? context.fetch(FetchDescriptor<Thing>(
                    predicate: #Predicate { $0.sourceRef == ref })).first,
                   landed.isLive, landed.dueAt != opens || landed.title != fresh {
                    landed.dueAt = opens
                    landed.title = fresh
                }
                continue
            }
            let thing = Thing(kind: .link, title: fresh,
                              content: grantAppPage,
                              source: "Wallet", capturedAt: .now, sourceRef: ref)
            thing.dueAt = opens
            thing.walletAddress = owner
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        if added > 0 { _ = context.saveHonestly() }
        return added
    }

    /// World's own page for its "Worldcoin — Claim your Worldcoin" app — a web
    /// page that answers everywhere, so the row's link never lands on nothing.
    static let grantAppPage = "https://world.org/ecosystem/app_d2905e660b94ad24d6fc97816182ab35"

    /// Watched wallets (lowercased hex) with at least one received transfer from
    /// a grant holder.
    @MainActor
    private static func grantRecipients(context: ModelContext, among addresses: [String]) -> [String] {
        let watched = Set(addresses.map { $0.lowercased() }.filter { WorldApp.addressWord($0) != nil })
        guard !watched.isEmpty else { return [] }
        var descriptor = FetchDescriptor<Thing>(predicate: #Predicate {
            $0.source == "Wallet" && $0.counterpartyAddress != nil
        })
        descriptor.propertiesToFetch = [\.counterpartyAddress, \.walletAddress, \.transferDirection]
        var out = Set<String>()
        for t in (try? context.fetch(descriptor)) ?? [] where t.isLive {
            guard WalletIngest.isWorldGrantHolder(t.counterpartyAddress),
                  let owner = t.walletAddress?.lowercased(), watched.contains(owner),
                  t.transferDirection != "sent" else { continue }
            out.insert(owner)
        }
        return out.sorted()
    }

    // MARK: - Usernames

    /// Per launch, misses included — `ENS.reverseName`'s cache shape, so a
    /// feed of strangers costs one request per address per launch at most.
    @MainActor private static var usernameCache: [String: WorldApp.Username?] = [:]

    /// A World App username for this address, FORWARD-VERIFIED (prd §599's bar,
    /// which every name `NameResolve.primaryNames` returns must meet): the
    /// record for the address names a username, and the record for that
    /// username names the same address. A service that does not answer the
    /// second question leaves the name unshown.
    @MainActor
    static func username(for hexAddress: String) async -> WorldApp.Username? {
        guard !DemoMode.isActive else { return nil }
        let addr = hexAddress.lowercased()
        guard WorldApp.addressWord(addr) != nil else { return nil }
        if let cached = usernameCache[addr] { return cached }
        var result: WorldApp.Username?
        if let found = WorldApp.username(fromJSON: await IngestSupport.getJSON(usernamesAPI + addr), for: addr),
           let encoded = found.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           WorldApp.username(fromJSON: await IngestSupport.getJSON(usernamesAPI + encoded), for: addr) != nil {
            result = found
        }
        usernameCache[addr] = result
        return result
    }

    static let usernamesAPI = "https://usernames.worldcoin.org/api/v1/"

    // MARK: - RPC

    private static func ethCall(to: String, data: String) async -> String? {
        let url = "https://\(WorldApp.network).g.alchemy.com/v2/\(IngestSupport.alchemyKey)"
        let root = await IngestSupport.postJSON(url, body: [
            "id": 1, "jsonrpc": "2.0", "method": "eth_call",
            "params": [["to": to, "data": data], "latest"],
        ]) as? [String: Any]
        return root?["result"] as? String
    }

    #if DEBUG
    /// `-worldAppProbe YES` — each watched EVM wallet's WLD Vault balance and
    /// World App username, the grant calendar and the next grant's amount, then
    /// one grant-row sync. One line per fact (the `-todayProbe` truncation rule).
    @MainActor
    static func probe(context: ModelContext) async -> [String] {
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched).filter { ENS.isHexAddress($0) }
        guard !addresses.isEmpty else { return ["no EVM wallets watched"] }
        var lines: [String] = []
        if let book = await book(addresses: addresses) {
            if book.isEmpty { lines.append("vault: no WLD Vault deposits (a real empty book)") }
            for v in book.vaults {
                lines.append("vault: \(WalletStore.shortAddress(v.owner)) \(WalletIngest.format(v.wld)) WLD usd=\(v.usd.map { String(format: "%.2f", $0) } ?? "unpriced")")
            }
        } else {
            lines.append("vault: UNREACHABLE")
        }
        for a in addresses {
            let u = await username(for: a)
            lines.append("username: \(WalletStore.shortAddress(a)) \(u?.name ?? "none") picture=\(u?.pictureURL == nil ? "no" : "yes")")
        }
        if let opens = WorldApp.nextGrantOpens(after: .now) {
            lines.append("grants: current=\(WorldApp.grantId(at: .now)) next=\(WorldApp.grantId(at: opens)) opens=\(opens)")
        }
        let landed = await syncGrantEvents(context: context, addresses: addresses,
                                           existing: IngestSupport.existingSourceRefs(context, source: "Wallet"))
        lines.append("grant rows: \(landed.map(String.init) ?? "UNREACHABLE") landed")
        return lines
    }
    #endif
}
