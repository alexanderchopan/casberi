import Foundation

/// **RECEIVE, EVERY PLACE ON ONE PAGE IN ONE SHAPE (prd §1946, user: "i'm
/// not sure why we need those little eyes for more information … all the
/// information should be on the main page", retiring §1929's ⓘ).** Every
/// place answers the same questions, in the same order, as labelled lines
/// under its name, so the places compare down the page:
///
/// - **Takes:** the tokens it accepts.
/// - **At least:** its minimum, where it has one (Privacy Pools).
/// - **On / From:** its networks, or who alone can pay it.
/// - **Ready:** how long until the money is yours to use.
/// - **Earns:** what it earns there.
/// - **Gas:** where a token must bring ETH with it (Privacy Pools).
///
/// Live figures (Privacy Pools' minimums, its rates and fee) are read by
/// `PrivateMoneyStore.readYield`; unread, a line says what it can without a
/// number, never a guessed one. The demo reads nothing and shows the figures
/// measured 2026-11-22.
///
/// UNMEASURED, said here so it is not mistaken for measured: Railgun's
/// "about an hour" is the screening wait Railgun shows for money shielded in
/// (`OnItsWay.railgun`), assumed for a payment from another Railgun balance;
/// Aztec's "about 20 seconds" is a send's own time on mainnet (24 s, measured
/// 2026-11-10, prd §1963), arrival also waits on your phone's next sync;
/// Privacy Pools' "15 minutes to a few hours" is the user's range.
enum ReceiveWords {
    enum Place: String, Identifiable {
        case `public`, elsewhere, pools, railgun, aztec, tacit, tacitETH, tacitDeposit
        var id: String { rawValue }
    }

    /// Privacy Pools' live figures, as words.
    struct Pools {
        /// "$11", or nil unread.
        var dollarsAtLeast: String?
        /// "0.005 ETH", or nil unread.
        var ethAtLeast: String?
        var usdcRate: Double?
        var ethRate: Double?
        /// "20", or nil unread.
        var feePercent: String?

        static let demo = Pools(dollarsAtLeast: "$11", ethAtLeast: "0.005 ETH",
                                usdcRate: 0.0203, ethRate: 0.012, feePercent: "20")

        /// Privacy Pools' figures as Receive says them, read off the store;
        /// the demo's are fixed.
        @MainActor static var current: Pools {
            guard !DemoMode.isActive else { return .demo }
            let store = PrivateMoneyStore.shared
            return Pools(
                dollarsAtLeast: dollars(minimumUnits: store.minimumUnits(symbol: "USDC")),
                ethAtLeast: eth(minimumWei: store.minimumUnits(symbol: "ETH")),
                usdcRate: store.yieldRate(symbol: "USDC"), ethRate: store.yieldRate(symbol: "ETH"),
                feePercent: store.yieldFeePercent(symbol: "USDC"))
        }

        /// "1.2–2.0%", one figure when only one is read.
        var earnsRange: String? {
            let read = [ethRate, usdcRate].compactMap { $0 }.filter { $0 > 0 }.sorted()
            guard let low = read.first, let high = read.last else { return nil }
            func p(_ r: Double) -> String { (r * 100).formatted(.number.precision(.fractionLength(1))) }
            return low == high ? "\(p(low))%" : "\(p(low))–\(p(high))%"
        }

        /// "$11 or 0.005 ETH", At least's value.
        var leastWords: String? {
            switch (dollarsAtLeast, ethAtLeast) {
            case let (d?, e?): String(localized: "\(d) or \(e)")
            case let (d?, nil): d
            case let (nil, e?): e
            default: nil
            }
        }

        /// "1.2–2.0%, after a 20% fee", Earns' value; "Interest" unread.
        var earnsWords: String {
            guard let range = earnsRange else { return String(localized: "Interest") }
            return feePercent.map { String(localized: "\(range), after a \($0)% fee") } ?? range
        }

        /// The pool's smallest deposit, rounded up, with room for the move's
        /// fees: whole dollars for USDC (10.07 → $11), and a thousandth of an
        /// ETH over its rounded-up minimum (0.004 → 0.005 ETH), which is the
        /// gas reserve the move holds back at today's price.
        static func dollars(minimumUnits: String?) -> String? {
            guard let u = minimumUnits.flatMap(Double.init), u > 0 else { return nil }
            return "$" + String(Int((u / 1_000_000).rounded(.up)))
        }
        static func eth(minimumWei: String?) -> String? {
            guard let w = minimumWei.flatMap(Double.init), w > 0 else { return nil }
            let thousandths = (w / 1e15).rounded(.up) + 1
            return (thousandths / 1000).formatted(.number.precision(.fractionLength(3))) + " ETH"
        }
    }

    // MARK: - The lines

    /// One labelled line under a place's name; `quiet` draws its value grey
    /// (nothing earned, a fact that is an absence).
    struct Fact: Hashable {
        let label: String
        let value: String
        var quiet = false
    }

    static func name(_ place: Place) -> String {
        switch place {
        case .public: String(localized: "Your public account")
        case .elsewhere: String(localized: "From another network")
        case .pools: "Privacy Pools"
        case .railgun: "Railgun"
        case .aztec: "Aztec"
        // Tacit's three addresses (prd §1978, from its deleted page).
        case .tacit: "Tacit"
        case .tacitETH: String(localized: "Tacit, private ETH")
        case .tacitDeposit: String(localized: "Tacit, from an exchange")
        }
    }

    /// "From another network"'s one line, under its name on its door.
    static var elsewhereLine: String { String(localized: "USDC or its token, most EVM networks") }

    static func facts(_ place: Place, networks: String, poolsNetworks: String, pools: Pools) -> [Fact] {
        // "Takes" here is what a place accepts; Move uses the word for time (MovePrivate), so its own key.
        let takes = String(localized: "Takes (accepts)", defaultValue: "Takes"), on = String(localized: "On"), from = String(localized: "From")
        let ready = String(localized: "Ready"), earns = String(localized: "Earns")
        switch place {
        case .public:
            return [Fact(label: takes, value: String(localized: "Any token")),
                    Fact(label: on, value: networks),
                    Fact(label: ready, value: String(localized: "In seconds")),
                    Fact(label: earns, value: String(localized: "Nothing until you lend it"), quiet: true)]
        case .elsewhere:
            return []
        case .pools:
            var lines = [Fact(label: takes, value: "ETH, USDC, USDG")]
            if let least = pools.leastWords { lines.append(Fact(label: String(localized: "At least"), value: least)) }
            lines += [Fact(label: on, value: poolsNetworks),
                      Fact(label: ready, value: String(localized: "15 min to a few hours")),
                      Fact(label: earns, value: pools.earnsWords),
                      Fact(label: String(localized: "Gas"), value: String(localized: "Send a little ETH with USDC or USDG"))]
            return lines
        case .railgun:
            return [Fact(label: takes, value: String(localized: "Ethereum tokens")),
                    Fact(label: from, value: String(localized: "Another Railgun balance only")),
                    Fact(label: ready, value: String(localized: "In about an hour")),
                    Fact(label: earns, value: String(localized: "Nothing"), quiet: true)]
        case .aztec:
            return [Fact(label: takes, value: "USDC, WETH"),  // On Aztec it is WETH (prd §1943).
                    Fact(label: from, value: String(localized: "Another Aztec account only")),
                    Fact(label: ready, value: String(localized: "In about 20 seconds")),
                    Fact(label: earns, value: String(localized: "Nothing"), quiet: true)]
        // Your Tacit chain address: private TAC, from another Tacit account.
        case .tacit:
            return [Fact(label: takes, value: "TAC"),
                    Fact(label: on, value: String(localized: "Tacit chain")),
                    Fact(label: from, value: String(localized: "Another Tacit account only")),
                    Fact(label: earns, value: String(localized: "A share of the chain's fees"))]
        // Your Tacit address: private ETH, Tacit to Tacit.
        case .tacitETH:
            return [Fact(label: takes, value: "ETH"),
                    Fact(label: on, value: "Ethereum, Robinhood"),
                    Fact(label: from, value: String(localized: "Another Tacit account only")),
                    Fact(label: earns, value: String(localized: "Nothing"), quiet: true)]
        // The pool's deposit address: ETH sent here goes private.
        case .tacitDeposit:
            return [Fact(label: takes, value: "ETH"),
                    Fact(label: from, value: String(localized: "Any wallet or exchange")),
                    Fact(label: ready, value: String(localized: "In a few minutes")),
                    Fact(label: earns, value: String(localized: "Nothing"), quiet: true)]
        }
    }
}
