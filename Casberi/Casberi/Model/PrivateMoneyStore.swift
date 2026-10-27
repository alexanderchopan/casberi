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
    @ObservationIgnored private var asked: Date = .distantPast

    private init() {
        notes = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([PrivateMoney.Note].self, from: $0) } ?? []
    }

    var rows: [PrivateMoney.Row] { PrivateMoney.rows(notes) }

    func add(_ note: PrivateMoney.Note) {
        notes.removeAll { $0.commitment == note.commitment }
        notes.append(note)
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
        let usd = PrivateMoney.worthUSD(notes, prices: found)
        NSLog("privateMoney| worth | $%.2f | %d prices", usd, found.count)
        return usd > 0 ? [(symbol: PrivateMoney.walletSymbol, usd: usd, holderID: PrivateMoney.holderID,
                           label: String(localized: "Private"))] : []
    }

    /// The approved private money on `chainId` one send can spend, base
    /// units: the most any one account holds (prd §1562: a withdrawal spends
    /// from one account).
    func spendable(chainId: Int) -> String {
        PrivateMoney.spendableByAccount(notes, chainId: chainId)
            .compactMap { Decimal(string: $0.amount) }.max().map(PrivateMoney.plain) ?? "0"
    }

    /// The account a send of `value` (base units) and its relayer's fee
    /// spends from: the current root's when it covers it, else any other
    /// that does (`PrivateRoot.legacy` for the device-only one).
    func account(toSpend value: String, fee: String, chainId: Int) -> String? {
        guard let need = Decimal(string: value).map({ $0 + (Decimal(string: fee) ?? 0) }) else { return nil }
        let held = PrivateMoney.spendableByAccount(notes, chainId: chainId)
            .filter { (Decimal(string: $0.amount) ?? 0) >= need }.map(\.root)
        let current = PrivateRootKey.currentID
        if let current, held.contains(current) { return current }
        return held.first.map { $0 ?? PrivateRoot.legacy }
    }

    /// The notes of one account as the pool holds them (`PrivacyEngine.discover`;
    /// `root` nil for the device-only account): an unspent note is kept with
    /// the approval it had (a new one, change from a spend, keeps its
    /// deposit's label and so its approval); a note the pool no longer holds
    /// unspent is gone, unless it was made in the last ten minutes and the
    /// pool has not indexed it yet. Other accounts' notes stand as they are.
    /// A note found on a new phone has no label hash yet: `fillLabelHashes`.
    func reconcile(_ found: PrivacyEngineWire.Discovered, root: String? = nil) {
        let mine = notes.filter { $0.root == root }
        let byLabel = Dictionary(notes.map { ($0.label.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        let unspent = found.notes.filter { $0.status.uppercased() == "ACTIVE" && $0.tokenId.lowercased() == PrivateMove.eth.lowercased() }
        var next: [PrivateMoney.Note] = unspent.map { n in
            let had = mine.first { $0.commitment.lowercased() == n.commitment.lowercased() }
            let sameLabel = byLabel[n.label.lowercased()]
            return .init(commitment: n.commitment, label: n.label, labelHash: had?.labelHash ?? sameLabel?.labelHash ?? "",
                         symbol: "ETH", amount: PrivateMoney.decimal(hex: n.value), decimals: 18,
                         chainId: PrivacyNetwork.sepolia.chainId, tx: had?.tx ?? "", at: had?.at ?? Date(),
                         status: had?.status ?? sameLabel?.status ?? .waiting, root: root)
        }
        let recent = Date().addingTimeInterval(-600)
        next += mine.filter { old in old.at > recent && !next.contains { $0.commitment.lowercased() == old.commitment.lowercased() } }
        notes = notes.filter { $0.root != root } + next
        save()
        NSLog("privateMoney| reconciled | %@ | %d notes | spendable %@", root ?? PrivateRoot.legacy, next.count,
              PrivateMoney.spendable(next, chainId: PrivacyNetwork.sepolia.chainId))
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
                             decimals: n.decimals, chainId: n.chainId, tx: n.tx, at: n.at, status: n.status, root: n.root)
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
        for note in notes where PrivateMoney.kind(note.status) == .waiting && note.labelHash != "0" {
            guard let url = PrivateMoney.statusURL(aspUrl: PrivacyNetwork.sepolia.aspUrl, labelHash: note.labelHash),
                  let (data, http) = await IngestSupport.sendRequest(URLRequest(url: url), service: PrivacyEngine.service),
                  http.statusCode == 200, let status = PrivateMoney.status(asp: data) else { continue }
            NSLog("privateMoney| asp | %@… | %@", String(note.commitment.prefix(10)), status.rawValue)
            guard status != note.status, let i = notes.firstIndex(where: { $0.commitment == note.commitment }) else { continue }
            notes[i].status = status
            save()
        }
    }

    #if DEBUG
    /// `-privateMoneySample YES|mainnet|clear`: two notes no pool holds — one
    /// approved, one waiting — so Holdings can be looked at with no funds;
    /// `mainnet` lays them on Ethereum, so the box's Private block and the
    /// total can be seen too (Sepolia's count nothing).
    func sample(_ raw: String) {
        if raw == "clear" {
            notes = []
            save()
            return
        }
        let now = Date()
        let chain = raw == "mainnet" ? 1 : PrivacyNetwork.sepolia.chainId
        notes = [
            .init(commitment: "0xsample-approved", label: "0x1", labelHash: "0", symbol: "ETH", amount: "4000000000000000",
                  decimals: 18, chainId: chain, tx: "0x", at: now.addingTimeInterval(-86_400), status: .approved),
            .init(commitment: "0xsample-waiting", label: "0x2", labelHash: "0", symbol: "ETH", amount: "1000000000000000",
                  decimals: 18, chainId: chain, tx: "0x", at: now.addingTimeInterval(-120), status: .waiting),
        ]
        save()
        NSLog("privateMoney| sample | %d rows", rows.count)
    }
    #endif
}
