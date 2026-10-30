import Foundation

/// **THE SAFE PICK'S ROSTER (prd §1614).** Your account is a Safe, so the
/// Wallet's Safe pick answers "who can move this money, and what waits on
/// me?": every Safe you hold a key to, your account first, each with its
/// owners as faces and how many must sign; and, under the tiles, what can
/// move each one with nobody signing.
///
/// Foundation-only, so `safe-roster-selftest.sh` compiles it whole: the
/// names and faces are resolved by `SafeRoomSource.roster`, which reaches the
/// address book.
struct SafeRoster: Equatable {

    /// One owner as the box draws it.
    enum Face: Equatable {
        /// This phone's key (your account's "Signs from", or §425's co-signer key).
        case phone
        /// Your account's recovery key, in iCloud Keychain.
        case recovery
        /// Your account's co-signer.
        case coSigner
        /// A wallet you follow that owns this Safe.
        case you
        /// Anyone else: their name's first letter, or "" when unnamed.
        case person(String)

        /// Yours, drawn in the pick's ink; the rest are other people.
        var isYours: Bool {
            switch self {
            case .phone, .recovery, .coSigner, .you: true
            case .person: false
            }
        }
    }

    struct Safe: Equatable, Identifiable {
        var id: String { address.lowercased() }
        let address: String
        /// The Safe Transaction Service's chain segment, nil for your account.
        let seg: String?
        let name: String
        let isYourAccount: Bool
        /// Yours first, then the others in the order the Safe lists them.
        let faces: [Face]
        let threshold: Int?
        /// What can move it without a signature: your account's spend limit
        /// as words ("$100 a month"), else nil.
        let spendLimit: String?
        /// Modules enabled on it; never counted for your account, whose
        /// modules are its own send path and sign with your key.
        let modules: Int

        var ownerCount: Int { faces.count }
    }

    let safes: [Safe]

    /// How many faces a line draws before "+N".
    static let faceCap = 4
    /// How many Safes the box lists.
    static let boxCap = 3

    var isEmpty: Bool { safes.isEmpty }

    /// Your account first, then the rest A–Z by name.
    static func ordered(_ safes: [Safe]) -> [Safe] {
        safes.sorted { a, b in
            if a.isYourAccount != b.isYourAccount { return a.isYourAccount }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    // MARK: - Words

    /// Under a Safe's name: who signs it. Your account names its keys;
    /// another Safe says how many others hold one.
    static func line(_ safe: Safe) -> String {
        if safe.isYourAccount {
            let names = safe.faces.compactMap { face -> String? in
                switch face {
                case .phone: String(localized: "This iPhone")
                case .recovery: String(localized: "recovery key")
                case .coSigner: String(localized: "co-signer")
                default: nil
                }
            }
            if safe.threshold == 1, names.count > 1 { return String(localized: "Any one signs") }
            return names.formatted(.list(type: .and))
        }
        let others = safe.faces.filter { !$0.isYours }.count
        guard safe.faces.contains(where: \.isYours) else {
            return String(localized: "\(safe.ownerCount) owners")
        }
        switch others {
        case 0: return String(localized: "Only you")
        case 1: return String(localized: "You and 1 other")
        default: return String(localized: "You and \(others) others")
        }
    }

    /// Trailing a Safe: how many must sign of how many, or nil when its
    /// threshold has not been read.
    static func need(_ safe: Safe) -> String? {
        guard let threshold = safe.threshold, safe.ownerCount > 0 else { return nil }
        return String(localized: "\(threshold) of \(safe.ownerCount)")
    }

    /// The box's line under its figure at rest.
    static func statement(_ roster: SafeRoster, waiting: Int) -> String {
        let count = roster.safes.count
        let safes = count == 1 ? String(localized: "in 1 Safe") : String(localized: "in \(count) Safes")
        let rest = waiting == 0 ? String(localized: "nothing to sign")
            : waiting == 1 ? String(localized: "1 waiting on others")
            : String(localized: "\(waiting) waiting on others")
        return "\(safes) · \(rest)"
    }

    /// "Without a signature": what a Safe's row trails, and how loud.
    enum Tone: Equatable { case quiet, confirm, danger }

    static func unsigned(_ safe: Safe) -> (word: String, tone: Tone) {
        if safe.isYourAccount {
            if let limit = safe.spendLimit { return (limit, .quiet) }
            return (String(localized: "None"), .confirm)
        }
        switch safe.modules {
        case 0: return (String(localized: "None"), .confirm)
        case 1: return (String(localized: "1 module"), .danger)
        default: return (String(localized: "\(safe.modules) modules"), .danger)
        }
    }

    /// Your account's spend limit as the row's words.
    static func limitWords(dollars: Int?, period: String?) -> String? {
        guard let dollars, dollars > 0 else { return nil }
        let money = "$\(dollars.formatted())"
        guard let period else { return money }
        return String(localized: "\(money) a \(period)")
    }

    // MARK: - The queue in the box

    /// The box's figure when something waits on you.
    static func toSign(_ count: Int) -> String {
        String(localized: "\(count) to sign")
    }

    /// Under it: the Safe the first one is on, and what your signature does.
    static func signStatement(safeName: String, have: Int, required: Int) -> String {
        if have + 1 >= required {
            return String(localized: "\(safeName) · yours sends it")
        }
        return String(localized: "\(safeName) · yours makes \(have + 1) of \(required)")
    }

    /// A queued transaction's name: its description, sentence-cased.
    static func entryName(_ description: String) -> String {
        guard let first = description.first else { return description }
        return first.uppercased() + description.dropFirst()
    }
}
