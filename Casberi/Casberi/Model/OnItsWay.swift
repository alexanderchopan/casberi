import Foundation

/// **ON ITS WAY, STEP BY STEP (prd §1779; user: "we need on its way").** Money
/// that has left one place and not arrived in another is never invisible:
/// the Wallet's Home lists each thing still travelling, its row says the step
/// it is on and how many there are, and its page lists them all.
///
/// Four trips, each a fixed list of steps in the order they happen. An item
/// says which step is under way; the ones before it are done, the ones after
/// are ahead. A trip that will not go on by itself says what it needs
/// (`needs`), and only that kind is amber.
///
/// Foundation only: the Wallet builds the items from its stores, and
/// `private-money-selftest.sh` compiles this file whole.
enum OnItsWay {
    enum Trip: String, Equatable {
        /// Paid to a one-time private address, on its way into Privacy Pools.
        case address
        /// In Privacy Pools, waiting for approval.
        case approval
        /// In Railgun, inside its hour.
        case railgun
        /// Deposited for Aztec, not handed over yet.
        case aztec
    }

    struct Item: Identifiable, Equatable {
        let id: String
        let trip: Trip
        /// "1,000 USDC": what is travelling.
        let title: String
        /// Its dollars, where it is priced.
        let usd: Double?
        /// The trip's steps, in order.
        let steps: [String]
        /// The step under way (an index into `steps`).
        let current: Int
        /// What it needs before it goes on, when it will not by itself.
        let needs: String?

        /// "Waiting for gas · step 2 of 4".
        var line: String {
            let step = needs ?? steps[current]
            return String(localized: "\(step) · step \(current + 1) of \(steps.count)")
        }
    }

    /// The four steps money paid to a private address takes.
    static var addressSteps: [String] {
        [String(localized: "Arrived at your private address"),
         String(localized: "Gas for the move"),
         String(localized: "Moving in"),
         String(localized: "Waiting for approval")]
    }

    /// Paid to a one-time address and not moved in: short of gas, or a move
    /// that failed and is tried again when Receive opens.
    static func atAddress(id: String, title: String, usd: Double?, needsGas: Bool) -> Item {
        Item(id: "address:" + id, trip: .address, title: title, usd: usd, steps: addressSteps,
             current: needsGas ? 1 : 2,
             needs: needsGas ? String(localized: "Waiting for gas") : String(localized: "Not moved yet"))
    }

    /// Moved in, waiting for approval: the last step of the same trip, and
    /// nobody is waiting on you.
    static func waitingApproval(id: String, title: String, usd: Double?) -> Item {
        Item(id: "approval:" + id, trip: .approval, title: title, usd: usd, steps: addressSteps, current: 3, needs: nil)
    }

    /// Moved into Railgun: its screening lists it in about an hour.
    static func railgun(id: String, title: String, usd: Double?) -> Item {
        Item(id: "railgun:" + id, trip: .railgun, title: title, usd: usd,
             steps: [String(localized: "Moved into Railgun"), String(localized: "Private in about an hour")],
             current: 1, needs: nil)
    }

    /// Deposited for your private account: Aztec carries it, then this phone claims it.
    static func aztec(id: String, title: String, usd: Double?) -> Item {
        Item(id: "aztec:" + id, trip: .aztec, title: title, usd: usd,
             steps: [String(localized: "Sent on Ethereum"), String(localized: "Aztec is carrying it"),
                     String(localized: "Claimed for you")],
             current: 1, needs: nil)
    }
}
