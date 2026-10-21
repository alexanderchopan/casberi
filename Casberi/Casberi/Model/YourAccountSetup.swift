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
