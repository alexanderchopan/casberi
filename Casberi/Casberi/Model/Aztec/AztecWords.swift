import Foundation

/// The kinds of transaction your Aztec account sends (prd §1711): what an
/// Activity row says, and which of them are private.
enum AztecTxKind: String, Codable, Sendable {
    /// Fee Juice claimed from a gas deposit.
    case gas
    /// A Shield deposit claimed into your private account.
    case arrival
    /// A private send to another Aztec account.
    case send
    /// Out through Shield to an Ethereum address.
    case exit
    /// A transaction an Aztec app asked for.
    case app

    /// A private move wears the eye-slash, as 0xBow's do (prd §1554); gas
    /// and an app's transaction are not said to be private.
    var isPrivate: Bool { self == .arrival || self == .send || self == .exit }
}

/// **THE WORDS FOR ONE AZTEC TRANSACTION (prd §1711 items 1, 2).**
/// Foundation-only, so `aztec-words-selftest.sh` pins them with
/// `TitleSeam` and `AddressTail` beside it.
enum AztecWords {

    /// "0.31 Fee Juice": two places at most (user, §1700f item 1: "i also
    /// don't like all the decimals"); a fee below a hundredth says so.
    static func feeFigure(_ units: String) -> String {
        guard let raw = Decimal(string: units), raw > 0 else { return String(localized: "no Fee Juice") }
        var whole = raw
        for _ in 0..<18 { whole /= 10 }
        if whole < Decimal(string: "0.01")! { return String(localized: "under 0.01 Fee Juice") }
        let shown = whole.formatted(.number.precision(.fractionLength(0...2)))
        return String(localized: "\(shown) Fee Juice")
    }

    /// The row's title: the move with no verb, then what Aztec charged
    /// after the one seam.
    ///
    /// - gas: "30 Fee Juice as gas — 0.31 Fee Juice fee"
    /// - arrival: "25 USDC to your private account"
    /// - send: "25 USDC to ...a91c on Aztec"
    /// - exit: "25 USDC to ...e07a on Ethereum"
    /// - app: "Swap on nemi.fi"
    static func title(_ kind: AztecTxKind, figure: String, to: String?, calls: [String], fee: String?) -> String {
        let tail = to.map { AddressTail.short($0) } ?? ""
        let move: String = switch kind {
        case .gas: String(localized: "\(figure) as gas")
        case .arrival: String(localized: "\(figure) to your private account")
        case .send: String(localized: "\(figure) to \(tail) on Aztec")
        case .exit: String(localized: "\(figure) to \(tail) on Ethereum")
        case .app: appWords(calls: calls, host: to ?? String(localized: "an Aztec app"))
        }
        return TitleSeam.join(move, fee.map { String(localized: "\(feeFigure($0)) fee") })
    }

    /// "Swap on nemi.fi": the first call's name in words, then the site.
    static func appWords(calls: [String], host: String) -> String {
        guard let first = calls.first, !first.isEmpty else { return String(localized: "A transaction on \(host)") }
        let words = first.replacingOccurrences(of: "_", with: " ")
        let named = words.prefix(1).uppercased() + words.dropFirst()
        return calls.count > 1 ? String(localized: "\(named) and \(calls.count - 1) more on \(host)")
            : String(localized: "\(named) on \(host)")
    }
}

/// **WHAT AN APP'S TRANSACTION COSTS, SAID ON ITS SHEET (prd §1711 item 2).**
/// The engine simulates the transaction before asking and prices the gas it
/// used at the node's current fees; the sheet says that, who pays, and, in
/// amber, when your Fee Juice holds less than it.
enum AztecFeeWords {
    /// Who pays: your Fee Juice, Fee Juice the same transaction claims, or
    /// the app's own payer (a sponsor, a fee contract) — the engine's `feeBy`.
    enum Payer: String, Equatable, Sendable { case you, claim, app }

    static func line(units: String?, payer: Payer, held: String?) -> String {
        switch payer {
        case .app:
            return String(localized: "The app pays the fee.")
        case .claim:
            guard let units else { return String(localized: "Paid from the Fee Juice it claims.") }
            return String(localized: "About \(AztecWords.feeFigure(units)), from the Fee Juice it claims.")
        case .you:
            guard let units else { return String(localized: "Paid from your Fee Juice. Casberi could not price it.") }
            if short(units: units, payer: payer, held: held) {
                guard (Decimal(string: held ?? "0") ?? 0) > 0 else {
                    return String(localized: "About \(AztecWords.feeFigure(units)). You have no Fee Juice to pay it.")
                }
                return String(localized: "About \(AztecWords.feeFigure(units)). Your Fee Juice holds \(AztecWords.feeFigure(held ?? "0")): not enough.")
            }
            return String(localized: "About \(AztecWords.feeFigure(units)), from your Fee Juice.")
        }
    }

    /// Your Fee Juice holds less than the fee: the line turns amber. Unknown
    /// on either side is not short (nothing is said that was not read).
    static func short(units: String?, payer: Payer, held: String?) -> Bool {
        guard payer == .you, let units, let fee = Decimal(string: units), let held, let have = Decimal(string: held) else { return false }
        return have < fee
    }
}
