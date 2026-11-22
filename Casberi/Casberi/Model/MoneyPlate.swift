import Foundation

/// **ONE PLATE, FIVE QUESTIONS (user, 2026-11-22: "I want them to follow a
/// system so they should all have the same formula"; "It needs to be totally
/// understandable").** Every place money can come into — and Round-ups, which
/// puts money away — answers the same five questions in the same order, so
/// two plates read side by side:
///
/// - **Receives**: what can arrive.
/// - **From**: the networks it can come from.
/// - **Where** (was Settles): where it ends up, naming the company that carries it at
///   the step it acts (Across, Relay, 0xBow).
/// - **When** (was Ready): when it moves or can be used.
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
    static var settles: String { String(localized: "Where") }
    static var ready: String { String(localized: "When") }
    static var earns: String { String(localized: "Earns") }

    /// **ROUND-UPS, AS SENTENCES (user, 2026-11-22: "instead of the
    /// sections we should just write this as a paragraph"; "we need to say
    /// the parts about USDC"; "if we say private balance we need to also say
    /// public balance").** Round-ups is one sequence, not a place to compare
    /// on Receive, so it reads in order: the change is saved as USDC in your
    /// public balance, in Aave on Base, where sends cannot spend it; at the
    /// target the next send moves it, still USDC, into your private balance,
    /// in Aave on Ethereum (Privacy Pools' ppUSDC lends to Aave's Ethereum
    /// market, `PrivateYield.aavePool`).
    ///
    /// `baseRate` is Aave's USDC supply rate on Base; `privateRate` Privacy
    /// Pools' USDC rate on Ethereum, net of 0xBow's fee; `privateFee` that
    /// fee as a whole percent. Either may be unread
    /// (nil): the sentence then says it earns interest, never a guessed figure.
    @MainActor
    static func roundUps(step: Int, baseRate: Double?, privateRate: Double?, privateFee: String?) -> String {
        let target = RoundUpsPot.targetWords
        let publicEarns = AaveLend.rateOnly(baseRate).map { String(localized: "where it earns \($0)") }
            ?? String(localized: "where it earns interest")
        // Why the rate drops when it turns private (user, 2026-11-22: "say
        // it"): Privacy Pools keeps a share of the interest, read off the
        // pool (`feeBps`, 2000 measured that day). Unread, the clause goes.
        let keeps = privateFee.map { String(localized: ", after Privacy Pools keeps \($0)%") } ?? ""
        let privateEarns = (AaveLend.rateOnly(privateRate).map { String(localized: "where it earns \($0) in Aave") }
            ?? String(localized: "where it earns interest in Aave")) + keeps
        return [
            String(localized: "Every buy, send and swap rounds up to the next $\(step)."),
            String(localized: "The change is saved as USDC in your public balance, in Aave on Base, \(publicEarns). Your sends can't spend it."),
            String(localized: "At \(target), it moves as USDC to your private balance in Privacy Pools, on Ethereum, \(privateEarns)."),
        ].joined(separator: " ")
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
