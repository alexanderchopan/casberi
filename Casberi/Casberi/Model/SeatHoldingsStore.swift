import Foundation

/// The readings `SeatHoldings` composes from a NEW read (prd §1701): each
/// seat's last answer, kept as JSON in `UserDefaults` so its pick's Holdings
/// stands on it between passes, as the seats' other readings do. The demo
/// holds its own (§483: it reads nothing), so each of those picks shows what
/// the read would.
enum SeatHoldingsStore {

    enum Seat: String, CaseIterable {
        case privacy = "seatHeld.privacy.v1"
        case etherFi = "seatHeld.etherfi.v1"
        case peer = "seatHeld.peer.v1"
        case metaMask = "seatHeld.metamask.v1"
    }

    static func items(_ seat: Seat) -> [SeatHoldings.Item] {
        if DemoMode.isActive { return demo(seat) }
        guard let data = UserDefaults.standard.data(forKey: seat.rawValue) else { return [] }
        return (try? JSONDecoder().decode([SeatHoldings.Item].self, from: data)) ?? []
    }

    /// Called off the main thread by the reads, never inside a lock
    /// (`defaults-lock-audit.py`).
    static func keep(_ items: [SeatHoldings.Item], _ seat: Seat) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: seat.rawValue)
    }

    static func forget(_ seat: Seat) {
        UserDefaults.standard.removeObject(forKey: seat.rawValue)
    }

    // MARK: - The demo's

    static func demo(_ seat: Seat) -> [SeatHoldings.Item] {
        switch seat {
        case .privacy:
            let cards = [
                SeatHoldings.PrivacyCard(token: "demo-netflix", lastFour: "8817", memo: "Streaming",
                                         state: "OPEN", limitCents: 4_000, duration: "MONTHLY"),
                SeatHoldings.PrivacyCard(token: "demo-shop", lastFour: "4421", memo: "Online shops",
                                         state: "OPEN", limitCents: 50_000, duration: "MONTHLY"),
                SeatHoldings.PrivacyCard(token: "demo-trial", lastFour: "0093", memo: "Free trials",
                                         state: "OPEN", limitCents: 100, duration: "TRANSACTION"),
            ]
            return SeatHoldings.privacy(cards, spentCents: ["demo-netflix": 2_298, "demo-shop": 13_140])
        case .etherFi:
            return SeatHoldings.etherFi([(safe: "0x5e1f0c8a2b3d4e6f7a8b9c0d1e2f3a4b5c6d7e8f",
                                          collateralUSD: 4_148.11, remainingUSD: 398.10)])
        case .peer:
            return SeatHoldings.peer([(id: "4127", symbol: "USDC", amount: 500)])
        case .metaMask:
            return SeatHoldings.metaMask(SeatHoldings.canSpend([(allowance: 1_000, balance: 1_250.40),
                                                                (allowance: 250, balance: 86.20)]))
        }
    }
}
