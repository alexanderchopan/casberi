import Foundation

/// **HOW YOUR ACCOUNTS WORK (prd §1948).** The words of the page behind
/// Account's "How your accounts work": an intro, then each account under its
/// name and Public or Private (no line under it: user, "they are kind of misleading"), open to Receive, Send (Swap for Railgun) and
/// Earns, each with its "Good to know". The words were settled with the user
/// line by line (2026-11-23); Privacy Pools' and Aztec's were corrected by
/// the sessions that built them. Privacy Pools' minimum, rates and fee are
/// read live (`ReceiveWords.Pools`); unread, the line says so without a number.
///
/// Learning lives here; Send and Receive carry only the rule that changes the
/// move in hand, when it applies (prd §1948 item 4).
enum AccountsGuide {
    struct Part: Identifiable, Hashable {
        let title: String
        let paragraphs: [String]
        /// Said after its label, mid-sentence: it starts in lower case.
        var goodToKnow: String?
        /// The note's label: "Good to know", or Safe's "From another network".
        var noteLabel: String = String(localized: "Good to know")
        var id: String { title }
    }

    struct Account: Identifiable, Hashable {
        enum Kind { case `public`, `private` }
        let id: String
        let name: String
        let kind: Kind
        let parts: [Part]
        /// Aztec's name wears its ink (prd §1779).
        var aztec = false
    }

    static var title: String { String(localized: "How your accounts work") }
    static var intro: String { String(localized: "You have one public account and three private ones.") }
    static var lede: String {
        String(localized: "Anyone can see what your public account holds and sends. Your private accounts keep that hidden, and each one does it differently.")
    }

    static func kindWord(_ kind: Account.Kind) -> String {
        kind == .public ? String(localized: "Public") : String(localized: "Private")
    }

    static func accounts(pools: ReceiveWords.Pools) -> [Account] {
        let receive = String(localized: "Receive"), send = String(localized: "Send")
        let earns = String(localized: "Earns"), swap = String(localized: "Swap")
        return [
            Account(id: "safe", name: "Safe", kind: .public,
                    parts: [
                        Part(title: receive,
                             paragraphs: [String(localized: "Any token, on Base, Ethereum or Robinhood, at your public address. Ready in seconds. Your account reads it over Tor.")],
                             goodToKnow: String(localized: "USDC or a network's own token, from most other networks. Relay moves it to your public account. Relay doesn't accept Tor, so that request goes without it."),
                             noteLabel: String(localized: "From another network")),
                        Part(title: send,
                             paragraphs: [String(localized: "Any token, to any address on Base, Ethereum or Robinhood, over Tor. This iPhone signs; with Co-signer on, your co-signer signs too. Anyone can see it.")],
                             goodToKnow: String(localized: "moving your own money between Base, Ethereum and Robinhood goes through Across, over Tor.")),
                        Part(title: earns, paragraphs: [String(localized: "Nothing until you lend it.")]),
                    ]),
            Account(id: "pools", name: "Privacy Pools", kind: .private,
                    parts: [
                        Part(title: receive,
                             paragraphs: [
                                String(localized: "Send ETH or USDC on Ethereum or Base, or ETH or USDG on Robinhood, to your Privacy Pools address. It's a new address each time. Casberi moves it into your private balance on Ethereum, bringing it over from Base or Robinhood first. USDG arrives as USDC."),
                                String(localized: "Privacy Pools checks each payment before you can send it, usually within 15 minutes, sometimes a few hours."),
                             ],
                             goodToKnow: poolsMinimum(pools)),
                        Part(title: send,
                             paragraphs: [String(localized: "Send ETH or USDC to anyone on Ethereum, Base or Robinhood. A relayer sends it for you, so your public account never appears, and it takes a small fee. To someone with their own Privacy Pools account, it stays private.")],
                             goodToKnow: String(localized: "you can send only what Privacy Pools has approved. You can't swap inside Privacy Pools.")),
                        Part(title: earns, paragraphs: [poolsEarns(pools)]),
                    ]),
            Account(id: "railgun", name: "Railgun", kind: .private,
                    parts: [
                        Part(title: receive,
                             paragraphs: [String(localized: "Anyone on Ethereum can pay your Railgun address, in any token. It's usually yours to use within minutes. You can also move tokens in from your public account: ETH and USDC go to Privacy Pools instead, where they earn. Anything else is private in about an hour, once Railgun checks it.")],
                             goodToKnow: String(localized: "moving in starts at $10 of a token Casberi can price. Railgun takes 0.25%.")),
                        Part(title: send,
                             paragraphs: [String(localized: "Send to anyone with Railgun, and it stays private: only they can see it. Or send to anyone on Ethereum: a Railgun broadcaster, or a one-time address of yours paying gas from your private ETH, sends it for you, so your public account never shows up. You see the cost before you send. You can also send back to your public account.")],
                             goodToKnow: String(localized: "Railgun takes 0.25% when money leaves Railgun. Sending to another Railgun user doesn't leave it.")),
                        Part(title: swap,
                             paragraphs: [String(localized: "Swap your Railgun tokens for DAI, USDT, WBTC, WETH, LINK, UNI or AAVE without leaving your private balance.")],
                             goodToKnow: String(localized: "the tokens go out to Uniswap and back in, in one transaction, so Railgun takes 0.25% each way, 0.5% in all.")),
                        Part(title: earns, paragraphs: [String(localized: "Nothing.")]),
                    ]),
            Account(id: "aztec", name: "Aztec", kind: .private,
                    parts: [
                        Part(title: receive,
                             paragraphs: [String(localized: "Move USDC, ETH or WETH in from your public account on Ethereum; ETH is wrapped to WETH on the way. Shield, Aztec's bridge, carries it over in 5 to 15 minutes. Shield takes 0.5%, and Ethereum's gas comes from your public account. Your first move also turns a little of what you move into Aztec's gas. Another Aztec account can also pay your Aztec address in USDC or WETH. Only Aztec can pay that address.")],
                             goodToKnow: String(localized: "this iPhone can move in up to $100 a day. More than that needs a co-signer with a Human Passport score of 20 or more. Shield then sets how much each move can be, by that score.")),
                        Part(title: send,
                             paragraphs: [String(localized: "Send to another Aztec account in about 20 seconds; who, what and how much stay private. Or send out to any Ethereum address, your public account included; it arrives as WETH. Shield takes 0.5%. About an hour later, Needs you offers Finish on Ethereum, one Face ID.")],
                             goodToKnow: String(localized: "this iPhone can send out up to $100 a day. More than that needs a co-signer with a Human Passport score of 20 or more. With Co-signer on, your co-signer approves every Aztec transaction: each send, each send out, and anything an Aztec app asks for. Moving money in is never asked.")),
                        Part(title: earns, paragraphs: [String(localized: "Nothing.")]),
                    ],
                    aztec: true),
        ]
    }

    /// The minimum as Privacy Pools reads it; unread, said without a number (§83).
    static func poolsMinimum(_ pools: ReceiveWords.Pools) -> String {
        guard let least = pools.leastWords else {
            return String(localized: "each payment has a minimum, read from Privacy Pools. With USDC or USDG, include a little ETH for the network fee.")
        }
        return String(localized: "send at least \(least) each time. With USDC or USDG, include a little ETH for the network fee.")
    }

    /// What it earns as read; unread, the fact without the figures.
    static func poolsEarns(_ pools: ReceiveWords.Pools) -> String {
        func p(_ r: Double) -> String { (r * 100).formatted(.number.precision(.fractionLength(1))) + "%" }
        let rates: String? = switch (pools.usdcRate, pools.ethRate) {
        case let (u?, e?): String(localized: "currently about \(p(u)) on USDC and \(p(e)) on ETH")
        case let (u?, nil): String(localized: "currently about \(p(u)) on USDC")
        case let (nil, e?): String(localized: "currently about \(p(e)) on ETH")
        default: nil
        }
        var words = rates.map { String(localized: "Your balance earns interest in Aave from the moment it arrives, \($0).") }
            ?? String(localized: "Your balance earns interest in Aave from the moment it arrives.")
        if let fee = pools.feePercent {
            words += " " + String(localized: "Privacy Pools keeps \(fee)% of the interest.")
        }
        return words
    }
}
