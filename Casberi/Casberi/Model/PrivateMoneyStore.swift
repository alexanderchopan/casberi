import Foundation
import Observation

/// **YOUR PRIVATE NOTES, AND WHAT THE ASP SAYS OF THEM (prd §1554).**
///
/// Each deposit Move to private makes is kept here by its public parts
/// (`PrivateMoney.Note`); Holdings draws `PrivateMoney.rows` off them. A note
/// waiting on 0xBow's ASP is asked again whenever Holdings shows it, at most
/// every 20 s, by its label's hash (never the label).
@MainActor
@Observable
final class PrivateMoneyStore {
    static let shared = PrivateMoneyStore()

    private static let key = "privateMoney.notes.v1"

    private(set) var notes: [PrivateMoney.Note]
    /// USD per unit by lower-cased symbol, for notes on a network whose coins
    /// have value (`MainnetPrices`); never asked for test money.
    private(set) var prices: [String: Double] = [:]
    /// Each yield share's exchange rate (the token's units per whole share)
    /// and the yearly rate it earns, read live (prd §1563), by lower-cased
    /// share. Never kept: a launch reads them again.
    private(set) var rates: [String: String] = [:]
    private(set) var apys: [String: Double] = [:]
    /// Each yield pool's smallest deposit in its token, read live with the
    /// rate (prd §1567), by lower-cased share.
    private(set) var minimums: [String: String] = [:]

    /// Where round-ups on Ethereum move: ppUSDC's smallest deposit in USDC
    /// units, once read (prd §1567).
    var roundUpsMinimum: String? {
        PrivacyNetwork.ethereum.yield.first { !$0.native }.flatMap { minimums[$0.share.lowercased()] }
    }
    @ObservationIgnored private var asked: Date = .distantPast
    /// Every commitment the pool has shown this launch (`reconcile`): an
    /// operation still out is landed once its note is here (finding 2).
    @ObservationIgnored private var poolSeen: Set<String> = []

    func seenInPool(_ commitment: String) -> Bool { poolSeen.contains(commitment.lowercased()) }
    @ObservationIgnored private var yieldRead: Date = .distantPast

    /// **RESTORING YOUR PRIVATE BALANCE (prd §1567).** True while a new
    /// phone finds a root's notes or walks its fresh addresses back (prd
    /// §1562): Holdings' Private header says so in one line, never a page.
    private(set) var restoring = false
    @ObservationIgnored private var restores = 0

    func beginRestore() {
        restores += 1
        if !restoring { restoring = true }
    }

    func endRestore() {
        restores = max(restores - 1, 0)
        if restores == 0, restoring { restoring = false }
    }

    private init() {
        notes = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([PrivateMoney.Note].self, from: $0) } ?? []
    }

    var rows: [PrivateMoney.Row] { PrivateMoney.rows(shownNotes, rates: rates) }

    /// **WHAT THE SCREENS DRAW (prd §1618 item 6).** The notes, or in the
    /// demo its own private balance, so 0xBow's box, How hidden and Holdings'
    /// Private section agree with the demo's deposits instead of "$0" beside
    /// them. Never saved, never watched: `notes` stays this phone's.
    var shownNotes: [PrivateMoney.Note] { DemoMode.isActive ? Self.demoNotes : notes }

    /// The prices the screens draw by: the read ones, or the demo's own.
    var shownPrices: [String: Double] { DemoMode.isActive ? ["eth": 3_850, "usdc": 1] : prices }

    private static let demoNotes: [PrivateMoney.Note] = {
        let day: TimeInterval = 86_400
        func note(_ id: String, _ symbol: String, _ amount: String, _ decimals: Int,
                  daysAgo: Double, _ status: PrivateMoney.Status) -> PrivateMoney.Note {
            .init(commitment: "0xdemo-\(id)", label: "0x\(id)", labelHash: "0", symbol: symbol, amount: amount,
                  decimals: decimals, chainId: 1, tx: "0x", at: Date().addingTimeInterval(-daysAgo * day), status: status)
        }
        return [
            note("eth1", "ETH", "250000000000000000", 18, daysAgo: 17, .approved),
            note("eth2", "ETH", "40000000000000000", 18, daysAgo: 24, .approved),
            note("usdc", "USDC", "250000000", 6, daysAgo: 13, .approved),
            note("eth3", "ETH", "70000000000000000", 18, daysAgo: 2, .waiting),
        ]
    }()

    /// A private row's line (prd §1563): "1.0% on Aave" where its token earns
    /// and the rate was read; else nil, and the row says its network.
    func yieldLine(_ row: PrivateMoney.Row) -> String? {
        guard row.kind == .held, let pool = PrivacyNetwork.forChain(row.chainId)?.yield.first(where: { $0.symbol == row.symbol }) else { return nil }
        return PrivateYield.line(apy: apys[pool.share.lowercased()])
    }

    /// Ethereum's ETH rate, for Move's line: "1.0% on Aave", or nil.
    var ethereumYieldLine: String? { yieldLine(symbol: "ETH") }

    /// A token's rate on Ethereum (ETH or USDC, prd §1567), or nil.
    func yieldLine(symbol: String) -> String? {
        guard let pool = PrivacyNetwork.ethereum.yield.first(where: { $0.symbol == symbol }) else { return nil }
        return PrivateYield.line(apy: apys[pool.share.lowercased()])
    }

    /// Reads every yield pool's exchange rate, fee and Aave's rate, on each
    /// network a note is on, at most once a minute: three calls a pool to the
    /// network's node, through the engine's door (Tor, a receipt each).
    func readYield(force: Bool = false, including network: PrivacyNetwork? = nil) async {
        guard !DemoMode.isActive, force || Date().timeIntervalSince(yieldRead) > 60 else { return }
        let chains = Set(notes.map(\.chainId) + (network.map { [$0.chainId] } ?? []))
        let networks = chains.compactMap(PrivacyNetwork.forChain).filter { !$0.yield.isEmpty }
        guard !networks.isEmpty else { return }
        yieldRead = Date()
        for network in networks {
            for pool in network.yield {
                let key = pool.share.lowercased()
                if let rate = await Self.call(network, to: pool.share, data: PrivateYield.exchangeRateCall).flatMap({ PrivateYield.word($0, 0) }),
                   rate != "0" {
                    rates[key] = rate
                    // The pool's smallest deposit in the token, at this rate
                    // (prd §1567: round-ups move once they reach it).
                    if let call = FreshAddress.assetsCall(token: pool.share),
                       let config = await Self.call(network, to: network.entrypoint, data: call).flatMap(FreshAddress.assetConfig),
                       config.enabled,
                       let floor = FreshAddress.minimumBudget(minimumShares: config.minimum, exchangeRate: rate, shareDecimals: pool.shareDecimals) {
                        minimums[key] = floor
                    }
                }
                guard let fee = await Self.call(network, to: pool.share, data: PrivateYield.feeBpsCall).flatMap({ PrivateYield.word($0, 0) }).flatMap(Int.init),
                      let reserve = PrivateYield.reserveDataCall(underlying: pool.underlying),
                      let ray = await Self.call(network, to: PrivateYield.aavePool, data: reserve).flatMap(PrivateYield.liquidityRate),
                      let apy = PrivateYield.apy(liquidityRateRay: ray, feeBps: fee) else {
                    apys[key] = nil
                    continue
                }
                apys[key] = apy
                NSLog("privateMoney| yield | %@ | rate %@ | fee %d bps | %.4f%%", pool.symbol, rates[key] ?? "-", fee, apy * 100)
            }
        }
    }

    /// One `eth_call` to the network's node through the engine's door.
    private static func call(_ network: PrivacyNetwork, to: String, data: String) async -> String? {
        guard let url = URL(string: network.rpcUrl) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "eth_call",
                                   "params": [["to": to, "data": data], "latest"]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (answer, http) = await IngestSupport.sendRequest(request, service: PrivacyEngine.service), http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: answer) as? [String: Any] else { return nil }
        return json["result"] as? String
    }

    /// What Wallet › Needs you shows (prd §1561): every deposit the ASP has
    /// not approved, and in a DEBUG build the samples `-privateNeedsSample`
    /// stood up, which are never kept.
    func asks(now: Date = .now) -> [PrivateMoney.Ask] {
        PrivateMoney.asks(notes + samples, now: now)
    }

    /// `-privateNeedsSample`'s notes: drawn in Needs you only, never saved,
    /// never in Holdings or the total.
    private(set) var samples: [PrivateMoney.Note] = []

    func add(_ note: PrivateMoney.Note) {
        notes.removeAll { $0.commitment == note.commitment }
        notes.append(note)
        save()
    }

    /// A note taken back (prd §1561): it left the pool, so it leaves here.
    func remove(commitment: String) {
        notes.removeAll { $0.commitment.lowercased() == commitment.lowercased() }
        samples.removeAll { $0.commitment.lowercased() == commitment.lowercased() }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        DefaultsWrite.set(data, forKey: Self.key)
    }

    /// **PRIVATE MONEY COUNTS IN THE WALLET (prd §1554).** Its one place in
    /// the combined read: approved notes on a network whose coins have value,
    /// in dollars, as a venue named Private (`PrivateMoney.walletSymbol`), so
    /// the box draws one block for it and the total counts it once. A deposit
    /// waiting for approval counts once approved; Sepolia's counts nothing.
    func walletHolding() async -> [(symbol: String, usd: Double, holderID: String, label: String)] {
        let real = notes.filter { $0.status == .approved && !PrivateMoney.testnets.contains($0.chainId) }
        guard !real.isEmpty else { return [] }
        let found = await MainnetPrices.prices(for: real.map(\.symbol))
        if found != prices { prices = found }
        await readYield()
        let usd = PrivateMoney.worthUSD(notes, prices: found, rates: rates)
        NSLog("privateMoney| worth | $%.2f | %d prices", usd, found.count)
        return usd > 0 ? [(symbol: PrivateMoney.walletSymbol, usd: usd, holderID: PrivateMoney.holderID,
                           label: String(localized: "Private"))] : []
    }

    /// The approved private money on `chainId` one send can spend, base
    /// units: the most any one account holds (prd §1562: a withdrawal spends
    /// from one account).
    func spendable(chainId: Int) -> String {
        spendable(chainId: chainId, symbol: "ETH")
    }

    func spendable(chainId: Int, symbol: String) -> String {
        PrivateMoney.spendableByAccount(notes, chainId: chainId, symbol: symbol, rates: rates)
            .compactMap { Decimal(string: $0.amount) }.max().map(PrivateMoney.plain) ?? "0"
    }

    /// The account a send of `value` (base units) and its relayer's fee
    /// spends from: the current root's when it covers it, else any other
    /// that does (`PrivateRoot.legacy` for the device-only one).
    func account(toSpend value: String, fee: String, chainId: Int, symbol: String = "ETH") -> String? {
        guard let need = Decimal(string: value).map({ $0 + (Decimal(string: fee) ?? 0) }) else { return nil }
        let held = PrivateMoney.spendableByAccount(notes, chainId: chainId, symbol: symbol, rates: rates)
            .filter { (Decimal(string: $0.amount) ?? 0) >= need }.map(\.root)
        let current = PrivateRootKey.currentID
        if let current, held.contains(current) { return current }
        return held.first.map { $0 ?? PrivateRoot.legacy }
    }

    /// The notes of one account as the pool holds them (`PrivacyEngine.discover`;
    /// `root` nil for the device-only account, prd §1562): an unspent note is
    /// kept with the approval it had (a new one, change from a spend, keeps
    /// its deposit's label and so its approval); a note the pool no longer
    /// holds unspent is gone, unless it was made in the last ten minutes and
    /// the pool has not indexed it yet. Other accounts' notes stand as they
    /// are. A note found on a new phone has no label hash yet: `fillLabelHashes`.
    func reconcile(_ found: PrivacyEngineWire.Discovered, root: String? = nil, network: PrivacyNetwork = .sepolia) {
        // Every note the pool showed, whatever its state: what an operation
        // still out carried is known to have landed once seen here (finding 2).
        poolSeen.formUnion(found.notes.map { $0.commitment.lowercased() })
        // One network's notes at a time: an account's notes on the other
        // network stand as they are.
        let mine = notes.filter { $0.root == root && $0.chainId == network.chainId }
        let byLabel = Dictionary(notes.map { ($0.label.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        // Unspent is ACTIVE, and a deposit the ASP has not approved (PENDING)
        // or refused (REJECTED): both still hold their money, and Needs you
        // asks about them (prd §1561). SPENT and EXITED are gone.
        // ETH, and on Ethereum each yield pool's shares (prd §1563).
        let unspent = found.notes.filter { ["ACTIVE", "PENDING", "REJECTED"].contains($0.status.uppercased())
            && ($0.tokenId.lowercased() == PrivateMove.eth.lowercased() || Self.isShare($0.tokenId, on: network)) }
        var next: [PrivateMoney.Note] = unspent.map { n in
            let had = mine.first { $0.commitment.lowercased() == n.commitment.lowercased() }
            let sameLabel = byLabel[n.label.lowercased()]
            let pool: PrivateMoney.Status? = switch n.status.uppercased() {
            case "REJECTED": .rejected
            // The SDK promotes PENDING to ACTIVE only on the ASP's approval.
            case "ACTIVE": .approved
            default: nil
            }
            let share = network.yield.first { $0.share.lowercased() == n.tokenId.lowercased() }
            return .init(commitment: n.commitment, label: n.label, labelHash: had?.labelHash ?? sameLabel?.labelHash ?? "",
                         symbol: share?.symbol ?? "ETH", amount: PrivateMoney.decimal(hex: n.value), decimals: share?.shareDecimals ?? 18,
                         chainId: network.chainId, tx: had?.tx ?? "", at: had?.at ?? Date(),
                         status: pool ?? had?.status ?? sameLabel?.status ?? .waiting, root: root, share: share?.share)
        }
        let recent = Date().addingTimeInterval(-600)
        // A note whose transaction is still out (finding 2) stands however
        // old: it may still land, and it leaves only when that is decided.
        let out = Set(PrivatePending.shared.ops.compactMap { $0.exits ? nil : $0.commitment?.lowercased() })
        let outTx = Set(FreshReceive.shared.entries.compactMap { e -> String? in
            if case .sent(_, let tx, .deposit, _, _) = e.state { return tx.lowercased() }
            return nil
        })
        next += mine.filter { old in
            (old.at > recent || out.contains(old.commitment.lowercased()) || outTx.contains(old.tx.lowercased()))
                && !next.contains { $0.commitment.lowercased() == old.commitment.lowercased() }
        }
        notes = notes.filter { !($0.root == root && $0.chainId == network.chainId) } + next
        save()
        NSLog("privateMoney| reconciled | %@ | %@ | %d notes | spendable %@", root ?? PrivateRoot.legacy, network.name, next.count,
              PrivateMoney.spendable(next, chainId: network.chainId, rates: rates))
    }

    private static func isShare(_ token: String, on network: PrivacyNetwork) -> Bool {
        network.yield.contains { $0.share.lowercased() == token.lowercased() }
    }

    /// The ASP files a deposit under Poseidon(label): a note found again on
    /// a new phone gets its hash from the engine (no account need be open),
    /// so its approval can be asked.
    func fillLabelHashes() async {
        for note in notes where note.labelHash.isEmpty {
            guard let hash = try? await PrivacyEngine.shared.labelHash(note.label),
                  let i = notes.firstIndex(where: { $0.commitment == note.commitment }) else { continue }
            let n = notes[i]
            notes[i] = .init(commitment: n.commitment, label: n.label, labelHash: hash, symbol: n.symbol, amount: n.amount,
                             decimals: n.decimals, chainId: n.chainId, tx: n.tx, at: n.at, status: n.status, root: n.root,
                             share: n.share)
            save()
        }
    }

    #if DEBUG
    /// `-privateForgetLocal YES` (prd §1562's proof): what this phone keeps
    /// about the root accounts' notes goes; the device-only account's stay.
    /// Nothing in the Keychain is touched: the root rebuilds them.
    func forgetRootNotes() {
        notes = notes.filter { $0.root == nil }
        save()
    }
    #endif

    /// The dollars Holdings' rows draw, read when they show.
    func readPrices() async { _ = await walletHolding() }

    /// Asks the ASP about every note still waiting.
    func refresh(force: Bool = false) async {
        guard !DemoMode.isActive, PrivateMoney.anyWaiting(notes), force || Date().timeIntervalSince(asked) > 20 else { return }
        asked = Date()
        // A sample note's hash is "0": nothing to ask.
        for note in notes where PrivateMoney.asksASP(note.status) && note.labelHash != "0" {
            // Each note asks its own network's ASP (Ethereum's is api-v2).
            guard let network = PrivacyNetwork.forChain(note.chainId),
                  let url = PrivateMoney.statusURL(aspUrl: network.aspUrl, labelHash: note.labelHash),
                  let (data, http) = await IngestSupport.sendRequest(URLRequest(url: url), service: PrivacyEngine.service),
                  http.statusCode == 200, let status = PrivateMoney.status(asp: data) else { continue }
            NSLog("privateMoney| asp | %@… | %@", String(note.commitment.prefix(10)), status.rawValue)
            guard status != note.status, let i = notes.firstIndex(where: { $0.commitment == note.commitment }) else { continue }
            notes[i].status = status
            save()
        }
    }

    #if DEBUG
    /// `-privateNeedsSample "waiting,rejected,overdue"`: Needs you's rows with
    /// no deposit behind them (prd §1561) — a refusal cannot be forced on
    /// Sepolia. Drawn in Needs you only and never saved; Take it back on one
    /// says it is a sample.
    func sampleAsks(_ raw: String) {
        let now = Date()
        samples = raw.split(separator: ",").enumerated().compactMap { i, word in
            let (status, at): (PrivateMoney.Status, Date) = switch word.trimmingCharacters(in: .whitespaces) {
            case "waiting": (.waiting, now.addingTimeInterval(-25 * 60))
            case "rejected": (.rejected, now.addingTimeInterval(-3 * 3600))
            case "proof": (.needsProof, now.addingTimeInterval(-3 * 3600))
            case "overdue": (.waiting, now.addingTimeInterval(-9 * 86_400))
            default: (.approved, now)
            }
            guard status != .approved else { return nil }
            return .init(commitment: "0xsample-ask-\(i)", label: "0x\(i + 10)", labelHash: "0", symbol: "ETH",
                         amount: "100000000000000", decimals: 18, chainId: PrivacyNetwork.sepolia.chainId,
                         tx: "", at: at, status: status)
        }
        NSLog("privateMoney| needs samples | %d", samples.count)
    }

    /// `-privateMoneySample YES|mainnet|none|clear`: notes no pool holds — one
    /// approved, one waiting — so Holdings can be looked at with no funds;
    /// `mainnet` lays them on Ethereum, so the box's Private block and the
    /// total can be seen too (Sepolia's count nothing).
    func sample(_ raw: String) {
        if raw == "clear" {
            notes = []
            save()
            return
        }
        // Added beside the notes this phone holds, never over them (the
        // simulator's are real Sepolia notes); `none` takes the samples away.
        let kept = notes.filter { !$0.commitment.hasPrefix("0xsample") }
        if raw == "none" {
            notes = kept
            save()
            return
        }
        let now = Date()
        let chain = raw == "mainnet" ? 1 : PrivacyNetwork.sepolia.chainId
        // On Ethereum the notes hold yield SHARES (prd §1563): ppETH and
        // ppUSDC, worth their token at the live rate, the rate line live too.
        let eth = raw == "mainnet" ? PrivacyNetwork.ethereum.yield.first { $0.symbol == "ETH" } : nil
        let usdc = raw == "mainnet" ? PrivacyNetwork.ethereum.yield.first { $0.symbol == "USDC" } : nil
        notes = kept + [
            .init(commitment: "0xsample-approved", label: "0x1", labelHash: "0", symbol: "ETH", amount: "4000000000000000",
                  decimals: 18, chainId: chain, tx: "0x", at: now.addingTimeInterval(-86_400), status: .approved, share: eth?.share),
            .init(commitment: "0xsample-waiting", label: "0x2", labelHash: "0", symbol: "ETH", amount: "1000000000000000",
                  decimals: 18, chainId: chain, tx: "0x", at: now.addingTimeInterval(-120), status: .waiting, share: eth?.share),
        ]
        if let usdc {
            notes.append(.init(commitment: "0xsample-usdc", label: "0x3", labelHash: "0", symbol: "USDC", amount: "25000000000000000000",
                               decimals: 18, chainId: chain, tx: "0x", at: now.addingTimeInterval(-3 * 86_400), status: .approved,
                               share: usdc.share))
        }
        save()
        NSLog("privateMoney| sample | %d rows", rows.count)
    }
    #endif
}
