import Foundation

/// **ROUND-UPS, SET ASIDE (prd §1690, user: "i guess what i am worried about
/// is that a user spends the money that they were supposed to save").**
/// Until §1690 the change was a number on this phone and the dollars stayed
/// in the account, spendable, until a send carried ~$10 into the private
/// balance. Now every send sets its change aside as it goes, into ONE place:
/// Round-ups, USDC lent on Aave on Base by your own account, where it earns
/// and cannot be spent by a send. Once Round-ups holds `moveAt` (about $10,
/// never under 0xBow's smallest deposit), the next send moves it into your
/// private balance.
///
/// - **One place, every network.** A send on Base supplies its change to
///   Aave there in the same transaction (`AaveLend.lend`). A send on
///   Ethereum or Robinhood carries its change to Base through Across, whose
///   handler supplies it to Aave on arrival on behalf of the account
///   (`RoundUpsPot+Across`). Across will not carry under about $0.50
///   (measured 2026-11-03: $0.40 is "too low", $1 costs $0.0045), so change
///   under `carryFloor` waits as `owed` and goes with the next send.
/// - **What is set aside is a number this phone keeps, held to the chain.**
///   `pot` is what Round-ups put in Aave on Base; Holdings and Lend read the
///   account's aUSDC there and split it (`split`), so Round-ups is never
///   offered as something lent, and a pot larger than the aUSDC there is
///   cut down to it (`healed`).
/// - **The move.** On Base it rides the send itself: Aave's withdrawal, then
///   §1574's Across deposit into the private pool on Ethereum. A send on
///   another network is followed by that same operation on Base, signed
///   under the Face ID asked at the tap (§1687's `FaceIDAhead`, `again()`). Either way it is
///   simulated first, and a move that does not check out waits for the next
///   send: Round-ups stays where it is, set aside and earning.
///
/// Pure (Foundation only): `round-ups-pot-selftest.sh` compiles it whole.
enum RoundUpsPot {
    /// Where Round-ups is kept: Base.
    static let home = 8453
    /// The dollar's decimals: USDC and USDG are both 6.
    static let decimals = 6
    /// Moves into your private balance from here: $10, or 0xBow's smallest
    /// deposit if that is more (`moveAt`).
    static let moveFloor = "10000000"
    /// The least Across carries from Ethereum or Robinhood: its own minimum
    /// was $0.5003 on 2026-11-03, so a little over it.
    static let carryFloor = "510000"
    /// Aave's interest on Round-ups is moved with it when the account lends
    /// nothing else there: aUSDC up to this much over the pot is its interest.
    static let interestSlack = "500000"

    // MARK: - What is kept

    private static let potKey = "yourAccount.roundUps.pot"
    private static let owedKey = "yourAccount.roundUps.owed"
    private static let migratedKey = "yourAccount.roundUps.pot.v1"
    /// The networks with value whose old counts become owed.
    private static let valueChains: Set<String> = ["1", "8453", "4663"]

    /// What Round-ups has put in Aave on Base, in the dollar's units.
    static var pot: String {
        get { UserDefaults.standard.string(forKey: potKey) ?? "0" }
        set { UserDefaults.standard.set(digits(newValue), forKey: potKey) }
    }

    /// Change counted and not yet set aside: under Across's minimum, or a
    /// send whose set-aside did not check out. It goes with the next send.
    static var owed: String {
        get { UserDefaults.standard.string(forKey: owedKey) ?? "0" }
        set { UserDefaults.standard.set(digits(newValue), forKey: owedKey) }
    }

    /// **THE OLD COUNTS BECOME OWED, ONCE.** Before §1690 the change was only
    /// counted (`yourAccount.roundUps.private.<chain>` and
    /// `.saved.<chain>`); nothing was set aside, so it is all owed, and the
    /// next send sets it aside. The old keys are removed; a test network's
    /// count was test money, and is dropped, never owed.
    static func migrate(_ defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: migratedKey) else { return }
        var total = Decimal(string: defaults.string(forKey: owedKey) ?? "0") ?? 0
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("yourAccount.roundUps.private.") || key.hasPrefix("yourAccount.roundUps.saved.") {
            let chain = key.split(separator: ".").last.map(String.init) ?? ""
            if valueChains.contains(chain) { total += Decimal(string: defaults.string(forKey: key) ?? "0") ?? 0 }
            defaults.removeObject(forKey: key)
        }
        defaults.set(digits(total), forKey: owedKey)
        defaults.set(true, forKey: migratedKey)
    }

    // MARK: - One send

    /// What one send does with Round-ups.
    struct Step: Equatable, Sendable {
        /// This send's round-up.
        let change: String
        /// What it sets aside: the change and what was owed.
        let carry: String
        /// Round-ups already holds enough: this send moves it.
        let moves: Bool
    }

    /// When Round-ups moves: $10, or 0xBow's smallest deposit when that is
    /// more; nil while that minimum is unread (nothing moves on a guess).
    static func moveAt(poolMinimum: String?) -> String? {
        guard let floor = poolMinimum.flatMap({ Decimal(string: $0) }), floor > 0,
              let ten = Decimal(string: moveFloor) else { return nil }
        return digits(max(floor, ten))
    }

    /// The figure Round-ups is counted toward, for words: `moveAt`, else $10.
    static func shownMoveAt(poolMinimum: String?) -> String { moveAt(poolMinimum: poolMinimum) ?? moveFloor }

    /// One send's step. The move is decided by what is ALREADY set aside, so
    /// what it moves is in Aave when it is withdrawn.
    static func step(change: String, owed: String, pot: String, moveAt: String?) -> Step {
        let carry = sum(change, owed)
        let moves = moveAt.map { at in (Decimal(string: pot) ?? 0) >= (Decimal(string: at) ?? .greatestFiniteMagnitude) } ?? false
        return Step(change: change, carry: carry, moves: moves)
    }

    /// Whether `carry` can be set aside from `chainId` with this send: any
    /// amount on Base, at least `carryFloor` through Across.
    static func carries(_ carry: String, from chainId: Int) -> Bool {
        guard let c = Decimal(string: carry), c > 0 else { return false }
        return chainId == home || c >= (Decimal(string: carryFloor) ?? 0)
    }

    /// After a send: the pot and what is owed. Set aside, the carry joins
    /// the pot; not, it is all owed. A move takes what it moved out of the
    /// pot, never below zero.
    static func after(_ step: Step, pot: String, setAside: Bool, moved: String?) -> (pot: String, owed: String) {
        var p = Decimal(string: pot) ?? 0
        if setAside { p += Decimal(string: step.carry) ?? 0 }
        if let moved { p -= Decimal(string: moved) ?? 0 }
        return (digits(max(p, 0)), setAside ? "0" : step.carry)
    }

    // MARK: - Held to the chain

    private static let carriedKey = "yourAccount.roundUps.carriedAt"

    /// When change last left Ethereum or Robinhood through Across: until its
    /// fill deadline has passed (six hours at most) it may not have reached
    /// Aave on Base yet, so a pot above the aUSDC there is not cut then.
    static var carriedAt: Date? {
        get { UserDefaults.standard.object(forKey: carriedKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: carriedKey) }
    }

    /// Whether a pot above what Aave holds may be cut to it now.
    static func mayHeal(carriedAt: Date?, now: Date = Date()) -> Bool {
        guard let carriedAt else { return true }
        return now.timeIntervalSince(carriedAt) > 6 * 3_600
    }

    /// The account's aUSDC on Base split into Round-ups and what you lent:
    /// Round-ups is the pot, never more than is there.
    static func split(aBalance: String, pot: String) -> (roundUps: String, lent: String) {
        let a = max(Decimal(string: aBalance) ?? 0, 0), p = max(Decimal(string: pot) ?? 0, 0)
        let r = min(a, p)
        return (digits(r), digits(a - r))
    }

    /// The pot held to what is there: never more than the account's aUSDC on
    /// Base (a set-aside that was refunded, a move counted twice).
    static func healed(pot: String, aBalance: String) -> String { split(aBalance: aBalance, pot: pot).roundUps }

    /// What a move withdraws: everything there (`all`, Aave's `max`) when
    /// the account lends nothing else on Base beyond the pot's interest, so
    /// the interest moves too and no dust is left lent; else exactly the pot.
    static func withdrawal(pot: String, aBalance: String) -> (amount: String, all: Bool)? {
        guard let p = Decimal(string: pot), p > 0, let a = Decimal(string: aBalance), a > 0 else { return nil }
        let slack = Decimal(string: interestSlack) ?? 0
        if a <= p + slack { return (digits(a), true) }
        return (digits(p), false)
    }

    // MARK: - Words

    /// "$6.20": an amount in the dollar's units, as Round-ups says it.
    static func dollars(_ units: String) -> Double {
        NSDecimalNumber(decimal: (Decimal(string: units) ?? 0) / pow(10, decimals)).doubleValue
    }

    // MARK: - Arithmetic

    static func sum(_ a: String, _ b: String) -> String {
        digits((Decimal(string: a) ?? 0) + (Decimal(string: b) ?? 0))
    }

    /// Whole base units as digits, never negative or a fraction.
    static func digits(_ d: Decimal) -> String {
        var v = max(d, 0), out = Decimal()
        NSDecimalRound(&out, &v, 0, .down)
        return NSDecimalNumber(decimal: out).stringValue
    }

    static func digits(_ s: String) -> String { digits(Decimal(string: s) ?? 0) }
}
