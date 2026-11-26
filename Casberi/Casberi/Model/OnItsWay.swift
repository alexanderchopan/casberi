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
        /// In Privacy Pools, being checked by its ASP.
        case approval
        /// In Railgun, inside its hour.
        case railgun
        /// Deposited for Aztec, not handed over yet.
        case aztec
        /// Into, out of or across Tacit's chain, not taken yet (prd §1983).
        case tacit
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
        /// The Privacy Pools notes Take it back returns (`.approval` only).
        var commitments: [String] = []

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
         // The same words as `PrivateMoney.beingChecked` (prd §1841); this
         // file compiles alone in `private-money-selftest.sh`.
         String(localized: "Being checked by Privacy Pools")]
    }

    /// Paid to a one-time address and not moved in: short of gas, or a move
    /// that failed and is tried again when Receive opens.
    static func atAddress(id: String, title: String, usd: Double?, needsGas: Bool) -> Item {
        Item(id: "address:" + id, trip: .address, title: title, usd: usd, steps: addressSteps,
             current: needsGas ? 1 : 2,
             needs: needsGas ? String(localized: "Waiting for gas") : String(localized: "Not moved yet"))
    }

    /// Moved in, being checked: the last step of the same trip, and nobody
    /// is waiting on you. `commitments` are the notes Take it back returns
    /// (prd §1576, on this sheet since §1841).
    static func waitingApproval(id: String, title: String, usd: Double?, commitments: [String] = []) -> Item {
        Item(id: "approval:" + id, trip: .approval, title: title, usd: usd, steps: addressSteps, current: 3, needs: nil,
             commitments: commitments)
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

    /// TAC made private, proved and handed, not taken by a block yet.
    static func tacitIn(id: String, title: String, usd: Double?) -> Item {
        Item(id: "tacit-in:" + id, trip: .tacit, title: title, usd: usd,
             steps: [String(localized: "Proved on your iPhone"), String(localized: "Tacit is taking it"),
                     String(localized: "Private on the Tacit chain")],
             current: 1, needs: nil)
    }

    /// TAC going back to public: taken by a block, then collected by your
    /// account; or, `paid`, sent privately to another Tacit account.
    static func tacitOut(id: String, title: String, usd: Double?, collecting: Bool, paid: Bool) -> Item {
        Item(id: "tacit-out:" + id, trip: .tacit, title: title, usd: usd,
             steps: paid ? [String(localized: "Proved on your iPhone"), String(localized: "Tacit is taking it")]
                : [String(localized: "Proved on your iPhone"), String(localized: "Tacit is taking it"),
                   String(localized: "Collected by your account")],
             current: collecting ? 2 : 1, needs: nil)
    }
}
