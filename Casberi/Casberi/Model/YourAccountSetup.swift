import Foundation

/// **THE KEYS CHOSEN AT CREATE (prd §1457, user: "with the first send").**
/// A new account holds nothing, so nothing chosen at Create can be put on
/// chain then: the recovery key is made at once (iCloud Keychain, free), and
/// the Signer and the spend limit are kept here and ride the first operation
/// on each network (`YourAccountChain.setupCalls`), the one Face ID that
/// opens the account there. A network already open is Security's.
enum YourAccountSetup {
    struct Choice: Codable, Equatable, Sendable {
        var recovery = false
        var signer: String?
        var limitDollars: Int?
        var limitMinutes: Int?
        /// Every send and swap needs the co-signer (prd §1570). A limit
        /// chosen by an older build counts as this: the allowance is retired.
        var requiresCoSigner: Bool?

        var required: Bool { signer != nil && (requiresCoSigner == true || limit != nil) }

        var limit: (dollars: Int, minutes: Int)? {
            guard signer != nil, let limitDollars, limitDollars > 0, let limitMinutes, limitMinutes > 0 else { return nil }
            return (limitDollars, limitMinutes)
        }
    }

    /// The spend limit's periods the opening operation sets up (prd §1461).
    static let firstPeriods = 6

    private static func key(_ account: String) -> String { "yourAccount.setup." + account.lowercased() }

    static func choice(for account: String) -> Choice? {
        UserDefaults.standard.data(forKey: key(account)).flatMap { try? JSONDecoder().decode(Choice.self, from: $0) }
    }

    static func save(_ choice: Choice, for account: String) {
        if let data = try? JSONEncoder().encode(choice) { UserDefaults.standard.set(data, forKey: key(account)) }
    }
}

/// **YOUR ACCOUNT'S THREE FIGURES FOR SECURITY'S BOX (prd §1462).** Read
/// off this phone: the spend limit from the plan it saved (§1455), the
/// round-ups from their setting (§1452), and the Signers as the LAST
/// READING `MoveSecurity` made of the networks' owners (§825's rule: a
/// figure the chain gave once stands until it answers again), so the box
/// never waits on a chain and never shows a zero it did not read.
struct YourAccountFacts: Equatable {
    /// Whole dollars a period; nil when off on every network.
    var limitDollars: Int?
    /// "month", "week" or "day".
    var limitPeriod: String?
    /// Distinct Signers across the networks, as last read.
    var signers: Int
    /// Dollars each send rounds up to; nil when off.
    var roundUpStep: Int?
    var roundUpSymbol: String?

    static let signersKey = "yourAccount.signers"

    static var current: YourAccountFacts? {
        if YourAccountDemo.isOn { return YourAccountDemo.facts }
        guard YourAccountKey.address != nil else { return nil }
        var dollars: Int?
        var period: String?
        for net in YourAccountOp.networks {
            guard let plan = YourAccountChain.plan(net), let n = Int(plan.dollarCap.dropLast(6)) else { continue }
            dollars = n
            period = MoveSecurity.LimitPeriod.of(seconds: plan.windows.first.map { $0.until - $0.from } ?? 0).word
            break
        }
        let setting = RoundUps.setting
        return YourAccountFacts(limitDollars: dollars, limitPeriod: period,
                                signers: signerCount(stored: UserDefaults.standard.integer(forKey: signersKey)),
                                roundUpStep: setting.on ? setting.step : nil,
                                roundUpSymbol: setting.on ? setting.target.symbol : nil)
    }

    /// The Signers as last read, or the one chosen at Create when no network
    /// has it yet: the Signer row names it, so the box counts it (user: "i
    /// have signer set up but shows i don't").
    static func signerCount(stored: Int) -> Int {
        guard stored == 0, let address = YourAccountKey.address,
              YourAccountSetup.choice(for: address)?.signer != nil else { return stored }
        return 1
    }

    /// Stamped by `MoveSecurity` after every read of the networks.
    static func noteSigners(_ count: Int) {
        UserDefaults.standard.set(count, forKey: signersKey)
    }
}
