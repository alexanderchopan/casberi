import Foundation

/// **RECEIVE, TWO LINES AND AN ⓘ (user, 2026-11-22: "should we add little i
/// in a circle for info on each?"; "holy shit … that is so long").** Every
/// Receive place answers the same questions in the same order, so the rows
/// can be compared down the page:
///
/// - **Row, line 1:** what it takes · its limit (networks, minimum, or who
///   can pay it).
/// - **Row, line 2:** Ready … · Earns ….
/// - **ⓘ:** the whole account in short paragraphs — what, where it ends up
///   (naming the company that bridges it), how long, what it earns.
///
/// Live figures (Privacy Pools' minimums, its rates and fee) are read by
/// `PrivateMoneyStore.readYield`; unread, a line says what it can without a
/// number, never a guessed one. The demo reads nothing and shows the figures
/// measured 2026-11-22.
///
/// UNMEASURED, said here so it is not mistaken for measured: Railgun's
/// "about an hour" is the screening wait Railgun shows for money shielded in
/// (`OnItsWay.railgun`), assumed for a payment from another Railgun balance;
/// Aztec's "a few minutes" is not measured on mainnet (14 s on its testnet);
/// Privacy Pools' "15 minutes to a few hours" is the user's range.
enum ReceiveWords {
    enum Place: String, Identifiable {
        case `public`, elsewhere, pools, railgun, aztec
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

        /// "1.2–2.0%", one figure when only one is read.
        var earnsRange: String? {
            let read = [ethRate, usdcRate].compactMap { $0 }.filter { $0 > 0 }.sorted()
            guard let low = read.first, let high = read.last else { return nil }
            func p(_ r: Double) -> String { (r * 100).formatted(.number.precision(.fractionLength(1))) }
            return low == high ? "\(p(low))%" : "\(p(low))–\(p(high))%"
        }

        /// "at least $11 or 0.005 ETH".
        var atLeast: String? {
            switch (dollarsAtLeast, ethAtLeast) {
            case let (d?, e?): String(localized: "at least \(d) or \(e)")
            case let (d?, nil): String(localized: "at least \(d)")
            case let (nil, e?): String(localized: "at least \(e)")
            default: nil
            }
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

    // MARK: - The rows

    static func row(_ place: Place, networks: String, pools: Pools) -> [String] {
        switch place {
        case .public:
            [String(localized: "Any token · \(networks)"),
             String(localized: "Ready in seconds · Earns nothing")]
        case .elsewhere:
            [String(localized: "USDC or its token · most EVM networks"),
             String(localized: "Ready in seconds · Earns nothing")]
        case .pools:
            [pools.atLeast.map { String(localized: "ETH, USDC, USDG · \($0)") } ?? String(localized: "ETH, USDC, USDG"),
             pools.earnsRange.map { String(localized: "Ready in 15 min to a few hours · Earns \($0)") }
                ?? String(localized: "Ready in 15 min to a few hours · Earns interest")]
        case .railgun:
            [String(localized: "Ethereum tokens · from Railgun only"),
             String(localized: "Ready in about an hour · Earns nothing")]
        case .aztec:
            [String(localized: "USDC, ETH · from Aztec only"),
             String(localized: "Ready in a few minutes · Earns nothing")]
        }
    }

    // MARK: - The ⓘ

    static func title(_ place: Place) -> String {
        switch place {
        case .public: String(localized: "To your public account")
        case .elsewhere: String(localized: "From another network")
        case .pools: String(localized: "To Privacy Pools")
        case .railgun: String(localized: "To Railgun")
        case .aztec: String(localized: "To Aztec")
        }
    }

    static func info(_ place: Place, networks: String, pools: Pools) -> [String] {
        switch place {
        case .public:
            return [
                String(localized: "Any token, on \(networks), at your public address."),
                String(localized: "Ready in seconds. Anyone can see it. It earns nothing until you lend it."),
            ]
        case .elsewhere:
            return [
                String(localized: "USDC or the network's own token, from most EVM networks, at a deposit address for that network."),
                String(localized: "Relay bridges it to your public account. Dollars arrive as your network's dollar. ETH arrives as ETH."),
                String(localized: "Ready in seconds. It earns nothing until you lend it."),
            ]
        case .pools:
            var what = String(localized: "ETH, USDC or USDG, on Base, Ethereum or Robinhood, at a new address each time.")
            if let at = pools.atLeast { what += " " + String(localized: "Send \(at).") }
            what += " " + String(localized: "With USDC or USDG, send a little ETH too, to pay for the move.")
            let usdc = AaveLend.rateOnly(pools.usdcRate)
            let eth = AaveLend.rateOnly(pools.ethRate)
            var earns: String
            switch (usdc, eth) {
            case let (u?, e?): earns = String(localized: "USDC earns \(u) and ETH \(e) in Aave")
            case let (u?, nil): earns = String(localized: "USDC earns \(u) in Aave")
            case let (nil, e?): earns = String(localized: "ETH earns \(e) in Aave")
            default: earns = String(localized: "USDC and ETH earn interest in Aave")
            }
            earns += pools.feePercent.map { String(localized: ", after Privacy Pools keeps \($0)%.") } ?? "."
            return [
                what,
                String(localized: "It moves into your private balance on Ethereum by itself. From Base and Robinhood, Across bridges it to Ethereum. USDC and USDG arrive as USDC. ETH arrives as ETH."),
                String(localized: "Ready in 15 minutes to a few hours, once Privacy Pools approves it. Less than the minimum stays at the address, and Receive shows it."),
                earns,
            ]
        case .railgun:
            return [
                String(localized: "Ethereum tokens, only from another Railgun balance, at your 0zk address."),
                String(localized: "It arrives in your private balance on Ethereum."),
                String(localized: "Ready in about an hour, once Railgun's screening lists it. It earns nothing."),
            ]
        case .aztec:
            return [
                String(localized: "USDC or ETH, only from another Aztec account."),
                String(localized: "It arrives in your private account on Aztec."),
                String(localized: "Ready in a few minutes. It earns nothing."),
            ]
        }
    }
}
