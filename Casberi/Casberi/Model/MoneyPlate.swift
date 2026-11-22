import Foundation

/// **ONE PLATE, FIVE QUESTIONS (user, 2026-11-22: "I want them to follow a
/// system so they should all have the same formula"; "It needs to be totally
/// understandable").** Every place money can come into — and Round-ups, which
/// puts money away — answers the same five questions in the same order, so
/// two plates read side by side:
///
/// - **Receives**: what can arrive.
/// - **From**: the networks it can come from.
/// - **Settles**: where it ends up, naming the company that carries it at
///   the step it acts (Across, Relay, 0xBow).
/// - **Ready**: when it can be used.
/// - **Earns**: what it earns and where, or that it earns nothing.
///
/// A question with nothing to say is answered ("Nothing"), never dropped, so
/// every plate has the same five rows. The words live here once; Account's
/// Round-ups tray draws them now, and Receive and the setup walk will draw
/// the same plates (the Privacy Pools plate is the reference, user-approved
/// 2026-11-22; its Ready time waits on the user).
enum MoneyPlate {
    struct Fact: Identifiable, Equatable {
        let label: String
        let lines: [String]
        var id: String { label }
    }

    static var receives: String { String(localized: "Receives") }
    static var from: String { String(localized: "From") }
    static var settles: String { String(localized: "Settles") }
    static var ready: String { String(localized: "Ready") }
    static var earns: String { String(localized: "Earns") }

    /// **ROUND-UPS (prd §1690, §1830).** The change from every buy, send and
    /// swap is set aside as USDC lent on Aave on Base, carried there by
    /// Across from Ethereum and Robinhood; at the target the next send moves
    /// it into Privacy Pools on Ethereum, where 0xBow checks it.
    ///
    /// `baseRate` is Aave's USDC supply rate on Base; `privateRate` Privacy
    /// Pools' USDC rate on Ethereum. Either may be unread (nil):
    /// the row then names where it earns without a figure, never a guess.
    @MainActor
    static func roundUps(step: Int, baseRate: Double?, privateRate: Double?) -> [Fact] {
        let target = RoundUpsPot.targetWords
        let networks = YourAccountOp.networks.map(\.name).sorted().joined(separator: ", ")
        // "USDC on Base, in Aave" (user, 2026-11-22): the token, the
        // network, then the place, and the rate last once it is read.
        let base = AaveLend.rateOnly(baseRate).map { String(localized: "USDC on Base, in Aave · \($0)") }
            ?? String(localized: "USDC on Base, in Aave")
        let pools = AaveLend.rateOnly(privateRate).map { String(localized: "Then USDC on Ethereum, in Privacy Pools · \($0)") }
            ?? String(localized: "Then USDC on Ethereum, in Privacy Pools")
        return [
            Fact(label: receives, lines: [
                String(localized: "Your change from every buy, send and swap"),
                String(localized: "Rounded up to the next $\(step)"),
            ]),
            Fact(label: from, lines: [networks]),
            Fact(label: settles, lines: [
                String(localized: "Rounds up into USDC on Base, in Aave. Your sends can't spend it."),
                String(localized: "From Ethereum and Robinhood, through Across"),
                String(localized: "At \(target), into Privacy Pools on Ethereum"),
            ]),
            Fact(label: ready, lines: [
                String(localized: "Moves with your next send once it holds \(target)"),
                String(localized: "Then once 0xBow approves it"),
            ]),
            Fact(label: earns, lines: [base, pools]),
        ]
    }

    /// Aave's USDC supply rate on Base, read once: one `eth_call` to the
    /// pool's `getReserveData` through the account's own node door. Nil when
    /// unread. The demo reads nothing and takes Lend's demo rate.
    static func baseUSDCRate(demo: Bool) async -> Double? {
        if demo { return 0.0508 }
        guard let m = AaveLend.markets.first(where: { $0.chainId == 8453 && $0.symbol == "USDC" }),
              let data = SafeABI.hexBytes(AaveLend.reserveDataCall(m)),
              let answer = try? await YourAccountChain.ethCall(YourAccountOp.base, to: m.pool, data: data),
              answer.count > 2 else { return nil }
        return AaveLend.apy(reserveData: answer)
    }
}
