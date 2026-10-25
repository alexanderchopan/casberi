import Foundation

/// **THE RECOVERY KEY IS CHECKED ONCE A MONTH (prd §1509 item 4, Phase 4 of
/// `docs/signing-safety-spec.md`; user: "every month if that is fine").**
/// One row in the Wallet's Needs you thirty days after the last good check,
/// or after the key was made; never a notification, never a badge (§1490).
/// The check sends nothing and costs no fee: the device owner unlocks the
/// key, it signs a random challenge verified on this phone against its own
/// public half, and each network says whether the account still lists the
/// key's signer among its owners. It is NOT `isValidSignature` on chain:
/// with the spend limit the threshold is two keys (§1456), so one key alone
/// would read as a failure.
///
/// Pure (Foundation): the due rule, each network's standing and the
/// sentence, held by `recovery-check-selftest.sh`. The reads are
/// `YourAccountRecovery.check`'s.
enum YourAccountRecoveryCheck {
    static let interval: TimeInterval = 30 * 86_400

    /// Due when thirty days have passed since the last good check, or since
    /// the key was made when it has never been checked; a key with neither
    /// date is due now.
    static func due(lastGood: Date?, made: Date?, now: Date) -> Bool {
        guard let since = lastGood ?? made else { return true }
        return now.timeIntervalSince(since) >= interval
    }

    /// What one network says about the key.
    enum Standing: Equatable, Sendable {
        /// The account lists the key's signer among its owners.
        case owner
        /// The account is not on this network yet: nothing to recover there.
        case notOnYet
        /// The account is there and does not list it: a failure.
        case notOwner
        /// The network did not answer: said, never counted either way.
        case unread

        var words: String {
            switch self {
            case .owner: String(localized: "An owner")
            case .notOnYet: String(localized: "Not on yet")
            case .notOwner: String(localized: "Not an owner")
            case .unread: String(localized: "Not read")
            }
        }
    }

    struct Network: Equatable, Sendable {
        let name: String
        let chainId: Int
        let standing: Standing
    }

    /// One check, whole.
    struct Result: Equatable, Sendable {
        /// The Keychain item is here and readable.
        var keyPresent: Bool
        /// The test signature verified against the key's public half.
        var signed: Bool
        var networks: [Network]
        var at: Date

        /// Good: the key is here, it signs, and no network the account is on
        /// refuses it. "Not on yet" and "not read" are not failures.
        var works: Bool { keyPresent && signed && !networks.contains { $0.standing == .notOwner } }
    }

    /// The page's sentence, and whether it is the green one. A failure is
    /// red and names what failed, the first that applies.
    static func sentence(_ r: Result) -> (text: String, works: Bool) {
        if !r.keyPresent {
            return (String(localized: "Your recovery key isn't in iCloud Keychain on this device."), false)
        }
        if !r.signed { return (String(localized: "Your recovery key did not sign. Nothing was sent."), false) }
        let refused = r.networks.filter { $0.standing == .notOwner }.map(\.name)
        if !refused.isEmpty {
            return (String(localized: "Your recovery key is not an owner on \(refused.formatted(.list(type: .and)))."), false)
        }
        let owners = r.networks.filter { $0.standing == .owner }.map(\.name)
        if owners.isEmpty { return (String(localized: "Your recovery key works, and no network has it yet."), true) }
        return (String(localized: "Your recovery key works on \(owners.formatted(.list(type: .and)))."), true)
    }

    /// The networks the fix door offers: on money's networks the account is
    /// not on yet, or where it is and the key is missing.
    static func fixable(_ r: Result) -> [Network] {
        r.networks.filter { $0.standing == .notOnYet || $0.standing == .notOwner }
    }
}
