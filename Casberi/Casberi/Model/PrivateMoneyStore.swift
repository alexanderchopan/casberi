import Foundation
import Observation

/// **YOUR PRIVATE NOTES, AND WHAT THE ASP SAYS OF THEM (prd §1547).**
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

    /// **PRIVATE MONEY COUNTS IN THE WALLET (prd §1547).** Its one place in
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
