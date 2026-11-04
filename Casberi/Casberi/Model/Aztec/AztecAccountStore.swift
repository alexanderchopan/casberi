import Foundation
import Observation

/// What the app shows of your Aztec account (prd §1700, §1700a), kept between
/// launches so the row and Holdings draw at once, before the engine has read.
///
/// - **Used.** The row appears only once the account has been used (an Aztec
///   app connected, money moved to it, something received; §1700a item 2),
///   never as an empty "$0 Aztec" row. The engine's first use marks it.
/// - **The last reading.** The engine's `holdings` (Fee Juice and every token an
///   app taught the wallet), stamped with when it was read; a read that fails
///   keeps the last one (§1548, §825's rule for the Wallet).
///
/// The address is the account's public face (its tail on rows); nothing here
/// is a key. On the Mac the store shows what the iPhone last read through
/// iCloud only once the engine has run there; the Mac has no prover (§1700).
@MainActor
@Observable
final class AztecAccountStore {

    static let shared = AztecAccountStore()

    struct Holding: Codable, Equatable, Identifiable {
        enum Kind: String, Codable { case feeJuice, token }
        let kind: Kind
        /// The token's contract on Aztec.
        let address: String
        /// "Fee Juice", or the token contract's own name until a symbol is known.
        let name: String
        /// Nil when the token's contract would not say: no amount is shown then.
        let decimals: Int?
        /// Base units, as text (they overflow 64 bits). Nil: that side was not read.
        let privateUnits: String?
        let publicUnits: String?
        var id: String { address }

        /// What the account holds of it, in whole tokens, private and public
        /// together; nil when the decimals are unknown.
        var amount: Decimal? {
            guard let decimals else { return nil }
            let units = [privateUnits, publicUnits].compactMap { $0.flatMap { Decimal(string: $0) } }.reduce(0, +)
            return units / pow(10, decimals)
        }

        /// Whether any of it is held, decimals or not.
        var isHeld: Bool {
            [privateUnits, publicUnits].contains { ($0.flatMap { Decimal(string: $0) } ?? 0) > 0 }
        }
    }

    struct Snapshot: Codable, Equatable {
        var used = false
        var address: String?
        var holdings: [Holding] = []
        var readAt: Date?
    }

    private(set) var snapshot: Snapshot

    private static let key = "aztec.account.v1"

    private init() {
        snapshot = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) } ?? Snapshot()
    }

    /// What the screens show: the demo's sample account in the demo (prd
    /// §1618: demo data on every tab, never the phone's own), else this
    /// phone's reading.
    var shown: Snapshot { DemoMode.isActive ? Self.demo : snapshot }

    /// Whether the row and the Holdings place show (§1700a item 2).
    var isShown: Bool { shown.used }

    /// The demo's Aztec account: an address no key derives, a little private
    /// USDC on Aztec (Shield's bridged USDC) and some Fee Juice for gas.
    static let demo = Snapshot(
        used: true,
        address: "0x0de70a11ce0c4f7e2b9a1d3c5e7f90b2d4a6c8e01f2a3b4c5d6e7f8091a2b3c",
        holdings: [
            Holding(kind: .token, address: "0x30112e52178143b74cf6037d047bbba924f4b0db8aab587a340aacfc6ecb4f38",
                    name: "USDC", decimals: 6, privateUnits: "120000000", publicUnits: "0"),
            Holding(kind: .feeJuice, address: "0x0000000000000000000000000000000000000000000000000000000000000003",
                    name: "Fee Juice", decimals: 18, privateUnits: nil, publicUnits: "2500000000000000000"),
        ],
        readAt: nil)

    /// The account was used: an app connected, money moved to it, something arrived.
    func markUsed(address: String) {
        guard !snapshot.used || snapshot.address != address else { return }
        snapshot.used = true
        snapshot.address = address
        save()
    }

    /// Reads the engine's holdings and keeps them; a failed read keeps the last.
    @discardableResult
    func refresh() async -> Bool {
        do {
            let address = try await AztecEngine.shared.accountAddress()
            guard let rows = try await AztecEngine.shared.call("holdings") as? [[String: Any]] else { return false }
            snapshot.address = address
            snapshot.holdings = rows.compactMap(Self.holding)
            snapshot.readAt = Date()
            if snapshot.holdings.contains(where: \.isHeld) { snapshot.used = true }
            save()
            return true
        } catch {
            NSLog("aztecEngine| holdings | kept the last reading: %@", error.localizedDescription)
            return false
        }
    }

    private static func holding(_ row: [String: Any]) -> Holding? {
        guard let kind = (row["kind"] as? String).flatMap(Holding.Kind.init), let address = row["address"] as? String else { return nil }
        return Holding(kind: kind, address: address,
                       name: row["symbol"] as? String ?? row["name"] as? String ?? AddressTail.short(address),
                       decimals: row["decimals"] as? Int,
                       privateUnits: row["private"] as? String,
                       publicUnits: row["public"] as? String)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        DefaultsWrite.set(data, forKey: Self.key)
    }
}
