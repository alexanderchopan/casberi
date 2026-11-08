import Foundation

/// The reads and writes behind Round-ups (prd §1690): the calls a send
/// carries to set its change aside, and the move into your private balance.
/// Every list here goes through your account's one simulated path, and a
/// list that does not check out is dropped, never the send.
extension RoundUpsPot {
    typealias Calls = [(to: String, data: String, value: String)]
    typealias Chain = YourAccountChain

    /// The demo's Round-ups (§1475): $6.20 of the $10, set aside.
    static let demoPot = "6200000"

    /// Round-ups as drawn: the demo's, or this phone's.
    static var shown: String { YourAccountDemo.isOn ? demoPot : pot }

    /// The figure Round-ups counts toward now, for words.
    @MainActor static var shownTarget: String { shownMoveAt(poolMinimum: PrivateMoneyStore.shared.roundUpsMinimum) }

    /// **The target as a round dollar (prd §1718, user: "i'd rather it say
    /// just $10. 10.06 is wonky").** The move happens at the pool's minimum
    /// ($10.06 today, the ladder's floor plus its fee); the words say the
    /// dollar it rounds to, "$10", everywhere the target is said — the
    /// sentence, Holdings' Round-ups row, Spending, Move's foot. The cents
    /// are the pool's, not a figure anyone chose.
    @MainActor static var targetWords: String {
        wholeDollars.string(from: NSNumber(value: dollars(shownTarget).rounded())) ?? figure(shownTarget)
    }

    /// "$6.20", "$10": Round-ups' figures, cents shown only when there are any.
    static func figure(_ units: String) -> String {
        let usd = dollars(units)
        let whole = (usd * 100).rounded().truncatingRemainder(dividingBy: 100) == 0
        return (whole ? wholeDollars : cents).string(from: NSNumber(value: usd)) ?? "$\(usd)"
    }

    private static func formatter(digits: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        return f
    }
    nonisolated(unsafe) private static let wholeDollars = formatter(digits: 0)
    nonisolated(unsafe) private static let cents = formatter(digits: 2)

    /// Base, as your account's network.
    static var homeNetwork: YourAccountOp.Network? { YourAccountOp.networks.first { $0.chainId == home } }

    // MARK: - Setting the change aside

    /// The calls that set `carry` aside with a send on `net`: on Base,
    /// Aave's approve and supply; elsewhere, Across's approve and deposit
    /// with the handler's message. nil when nothing can go with this send —
    /// under Across's minimum, no quote, a fee past its ceiling — and the
    /// change is owed to the next one.
    static func setAside(_ carry: String, on net: YourAccountOp.Network, account: String) async -> Calls? {
        guard !net.isTest, carries(carry, from: net.chainId), let m = market else { return nil }
        if net.chainId == home {
            guard let calls = AaveLend.lend(carry, in: m, account: account), AaveLend.checked(calls, in: m, account: account) else { return nil }
            return calls.map { ($0.to, $0.data, $0.value) }
        }
        guard acrossCarries(from: net.chainId), let message = message(budget: carry, account: account),
              let url = feesURL(from: net.chainId, amount: carry, account: account, message: message),
              let (data, http) = await IngestSupport.sendRequest(URLRequest(url: url), service: "Your account"),
              http.statusCode == 200,
              let fees = Across.fees(try? JSONSerialization.jsonObject(with: data), from: net.chainId), !fees.tooLow else {
            NSLog("roundUps| no carry from %@ | %@", net.name, carry)
            return nil
        }
        let now = Int(Date().timeIntervalSince1970)
        guard let input = PrivateBridge.input(budget: carry, quotedOutput: fees.outputAmount),
              fees.fillDeadline > now, fees.fillDeadline <= now + Across.maxDeadlineSeconds,
              let calls = calls(from: net.chainId, input: input, budget: carry, fees: fees, message: message, account: account) else {
            NSLog("roundUps| carry refused from %@ | %@", net.name, carry)
            return nil
        }
        return calls.map { ($0.to, SafeABI.hex($0.data), $0.value) }
    }

    // MARK: - The move into your private balance

    /// The move: Round-ups withdrawn from Aave on Base, then §1574's Across
    /// deposit into the private pool on Ethereum, the note proved now.
    struct Move {
        let calls: Calls
        let ride: PrivateOnEthereum.Ride
        /// What leaves Round-ups' count.
        let moved: String
    }

    /// The account's aUSDC on Base, interest included; nil unread.
    static func aBalance(_ account: String) async -> String? {
        guard let m = market, let net = homeNetwork, let data = AaveLend.lentCall(account: account),
              let bytes = SafeABI.hexBytes(data),
              let answer = try? await Chain.ethCall(net, to: m.aToken, data: bytes), answer.count > 2 else { return nil }
        return AaveLend.decimal(hex: answer)
    }

    /// The move, written for Base. Round-ups is first held to what is there
    /// (`healed`); anything unread or refused throws, and nothing moves.
    static func move(account: String) async throws -> Move {
        let open = await MainActor.run { PrivateMove.available && PrivateOnEthereum.owner != nil }
        guard open, let m = market, let base = homeNetwork else { throw PrivateOnEthereum.Failure.noPool }
        guard let held = await aBalance(account) else {
            throw Chain.Failure(message: String(localized: "Could not read Round-ups on Base"))
        }
        // What is there now moves; a carry still on its way across stays in
        // the pot after the move (`after`), and arrives into Round-ups.
        let kept = healed(pot: pot, aBalance: held)
        guard let w = withdrawal(pot: kept, aBalance: held),
              let out = AaveLend.takeBack(w.amount, all: w.all, in: m, account: account),
              AaveLend.checked(out, in: m, account: account) else { throw PrivateOnEthereum.Failure.noPool }
        let ride = try await PrivateBridge.ride(budget: w.amount, from: base, account: account)
        return Move(calls: out.map { ($0.to, $0.data, $0.value) } + ride.calls, ride: ride, moved: kept)
    }

    /// The move as its own operation on Base, after a send on another
    /// network, under that send's Face ID (the caller sets §1687's
    /// `YourAccountKey.ahead` to the tap's `FaceIDAhead.again()`).
    /// Simulated first; refused, it throws and Round-ups stays.
    static func moveAlone(account: String, reason: String) async throws -> (sent: Chain.Sent, move: Move, followed: Chain.Followed) {
        guard let base = homeNetwork else { throw PrivateOnEthereum.Failure.noPool }
        // **A CO-SIGNER REQUIRED ON BASE SIGNS THERE TOO.** This operation is
        // this phone's alone, so where every send needs the co-signer it is
        // not tried: the move rides the next send on Base, which asks both.
        if case .on = (try? await Chain.limitState(base, account)) ?? .off {
            throw Chain.Failure(message: String(localized: "Round-ups moves with your next send on Base"))
        }
        let mv = try await move(account: account)
        let followed = Chain.Followed()
        let sent = try await Chain.$following.withValue(followed) {
            try await Chain.privateCalls(mv.calls, on: base, reason: reason, stage: { _ in })
        }
        return (sent, mv, followed)
    }
}
