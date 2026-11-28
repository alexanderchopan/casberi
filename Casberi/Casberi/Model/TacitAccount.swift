import CryptoKit
import Foundation
import Observation

/// YOUR TACIT ACCOUNT, AS THE WALLET SHOWS IT.
///
/// An account you ALREADY have on Tacit, opened by your co-signer's wallet
/// (`TacitPocket.signIn`) and read, never moved. The key is held only while
/// the account is open, in the engine's page: closing the app closes the
/// account, and the page asks your co-signer again.
///
/// **What stays when it is closed is the last reading, with its date:** the
/// two addresses and each network's amount. Nothing in it can spend, and the
/// Wallet counts it as it counts a wallet it could not reach (prd §825).
@MainActor
@Observable
final class TacitAccount {

    static let shared = TacitAccount()

    /// The catalogue name and the seat id (`BridgeCatalog`, `BridgeRouting`).
    static let name = "Tacit"
    static let seatID = "tacit"

    enum Phase: Equatable {
        case closed
        /// Tor is connecting: the reads ride it, so nothing is asked of the
        /// co-signer until it is up.
        case connecting
        /// Waiting on the co-signer's wallet.
        case signing
        /// The account is open and the networks are being read.
        case reading
        case open
        case failed(String)
    }

    /// One network's amount, as last read.
    struct Held: Codable, Equatable, Identifiable {
        let chainId: Int
        let network: String
        /// ETH in the pool that is yours.
        let eth: Double
        /// ETH paid to the receive address and not yet moved into the pool.
        let waiting: Double
        /// ETH the whole pool holds on this network: what there is to hide
        /// among. nil when the node did not say.
        var pool: Double? = nil
        /// False when this network did not answer at this reading.
        let reached: Bool
        var id: Int { chainId }
    }

    /// What a reading found. Public facts only: no key, no note.
    struct Reading: Codable, Equatable {
        let coSigner: String
        /// The address another Tacit account pays.
        let address: String
        /// The pool's deposit address: ETH sent to it is moved into the
        /// pool. Not the public address: that is the co-signer's own.
        let receive: String
        let held: [Held]
        let asOf: Date
        /// TAC the co-signer's wallet holds in public, as Tacit's own page
        /// counts Public; nil when it was not read.
        var publicTAC: Double? = nil
        /// TAC held privately on the Tacit chain, as shares of one pool, at
        /// what they were worth when read; nil when the chain was not read.
        var privateTAC: Double? = nil
        /// True when the key's record names a PQ ID: its notes are under a
        /// passkey this phone does not hold, so `privateTAC` may be short.
        var privateElsewhere: Bool? = nil
        /// TAC in your Casberi account, on Ethereum: public too, and made
        /// private from there by a send. nil when not read.
        var accountTAC: Double? = nil
        /// TAC held privately in Tacit's DeFi pool; nil when not read whole.
        var defiTAC: Double? = nil
        /// Your Tacit chain address (`tc1…`), for a sender of private TAC.
        var chainAddress: String? = nil
        /// Your Tacit chain shares and what one share was worth in TAC at
        /// this reading: the next reading's rise on the same shares is earned.
        var chainShares: Double? = nil
        var chainRate: Double? = nil
        /// TAC the Tacit chain's fees have added to your shares since
        /// `earnedSince`, the first reading that knew a rate.
        var earnedTAC: Double? = nil
        /// How many notes the Tacit chain holds at the last reading: the
        /// crowd a send from it hides in (How hidden, prd §1983).
        var chainNotes: Int? = nil
        var earnedSince: Date? = nil
        /// The network `receive` belongs to: each network has its own
        /// deposit address, and Receive says which one it shows (prd §1988).
        /// Nil on a reading kept before it was recorded.
        var receiveNetwork: String? = nil
        /// Your farm positions (prd §1993); nil when they were not read.
        var farmed: [TacitFarms.Position]? = nil
        /// **WHAT A SHARE WAS WORTH, A DAY APART (prd §1999).** The Tacit
        /// chain's share price as read, one mark a day at most, the last 31
        /// days: the rate is today's price against the oldest. Nil on a
        /// reading kept before it was recorded.
        var rateMarks: [RateMark]? = nil

        /// **TACIT'S RATE, WHAT IT EARNED (prd §1999):** the share price now
        /// against the oldest mark at least a day old, a year's worth. A
        /// share is the pool over the shares, so only the chain's fees move
        /// it; a deposit or a withdrawal, anyone's, does not. Nil under a day
        /// of marks or with no rise; "about", never a promise.
        func chainAPY(now: Date = .now) -> (apy: Double, days: Int)? {
            guard let rate = chainRate, rate > 0,
                  let then = rateMarks?.first(where: { now.timeIntervalSince($0.at) >= 86_400 }), then.rate > 0,
                  rate > then.rate else { return nil }
            let days = now.timeIntervalSince(then.at) / 86_400
            let apy = pow(rate / then.rate, 365 / days) - 1
            guard apy.isFinite, apy > 0, apy < 100 else { return nil }
            return (apy, Int(days.rounded()))
        }

        /// Private TAC in both places; nil when neither was read.
        var privateTACAll: Double? {
            privateTAC == nil && defiTAC == nil ? nil : (privateTAC ?? 0) + (defiTAC ?? 0)
        }

        /// Public and private TAC together; nil when none was read.
        var tac: Double? {
            publicTAC == nil && privateTACAll == nil && accountTAC == nil ? nil
                : (publicTAC ?? 0) + (accountTAC ?? 0) + (privateTACAll ?? 0)
        }

        /// Public TAC in both places: your co-signer's wallet and your
        /// Casberi account; nil when neither was read.
        var publicAll: Double? {
            publicTAC == nil && accountTAC == nil ? nil : (publicTAC ?? 0) + (accountTAC ?? 0)
        }

        var eth: Double { held.map(\.eth).reduce(0, +) }
    }

    /// The Tacit chain's share price at one reading (prd §1999).
    struct RateMark: Codable, Equatable {
        let at: Date
        let rate: Double
    }

    private var livePhase: Phase = .closed
    /// SHA-256 of the key the open account was made from, in memory only,
    /// while it is open: a second signature must make the same key before
    /// money is sent to it (`TacitShield`). Never the key itself.
    private var keyPrint: [UInt8]?
    private var liveReading: Reading?
    private var livePrice: Double?
    private var liveTacPrice: Double?
    private var liveTacMove: Double?

    // MARK: - The Tacit chain's rate (prd §2002)

    /// **WHAT A SHARE EARNED, THE LAST 30 DAYS (prd §2002; user, 2026-11-28:
    /// "i can't tell what it'll earn b/c it doesn't say the rate").** The
    /// Tacit chain's contract on Ethereum holds its pool and its shares; a
    /// share is the pool over the shares, each with the contract's virtual 1
    /// TAC, so only the chain's fees move it. Read now and 216,000 blocks
    /// back (an archive read, as Olla's rate), a year's worth: what it
    /// earned, never a promise, for anyone, open or not. Nil where the node
    /// keeps no history; then the marks this phone kept (§1999) stand in.
    private(set) var chainYield: Double?
    private var chainYieldAt: Date?

    func readChainYield() async {
        guard !DemoMode.isActive else { return }
        if let at = chainYieldAt, Date.now.timeIntervalSince(at) < 3_600 { return }
        guard let net = YourAccountOp.networks.first(where: { $0.chainId == 1 }) else { return }
        async let now = Self.sharePrice(net, at: "latest")
        guard let headHex = try? await YourAccountChain.rpc(net, "eth_blockNumber", []) as? String,
              let head = Int(AaveLend.decimal(hex: headHex)), head > OllaStake.windowBlocks else { return }
        let then = await Self.sharePrice(net, at: "0x" + String(head - OllaStake.windowBlocks, radix: 16))
        guard let n = await now, let t = then, t > 0, n >= t else { return }
        let apy = pow(n / t, 365 / OllaStake.windowDays) - 1
        guard apy.isFinite, apy >= 0, apy < 100 else { return }
        chainYield = apy
        chainYieldAt = .now
    }

    /// One share in TAC at a block: (pool + 1) / (shares + 1), in TAC.
    private nonisolated static func sharePrice(_ net: YourAccountOp.Network, at block: String) async -> Double? {
        async let pool = chainWord(net, "pool()", at: block)
        async let shares = chainWord(net, "shares()", at: block)
        guard let p = await pool, let s = await shares else { return nil }
        return (p / 1e8 + 1) / (s / 1e8 + 1)
    }

    /// A one-word view of the Tacit chain's contract, in its 8-decimal units.
    private nonisolated static func chainWord(_ net: YourAccountOp.Network, _ signature: String, at block: String) async -> Double? {
        let data = SafeABI.hex(YourAccount.sel(signature))
        guard let hex = try? await YourAccountChain.rpc(net, "eth_call", [["to": TacitChain.blocks, "data": data], block]) as? String,
              hex.count >= 66 else { return nil }
        return Double(AaveLend.decimal(hex: hex))
    }

    /// The rate Earn shows: the chain's last 30 days, else the phone's marks.
    func earnRate(_ r: Reading) -> Double? { earnRateOver(r)?.apy }

    /// The rate and the days it was earned over, for "last 30 days".
    func earnRateOver(_ r: Reading) -> (apy: Double, days: Int)? {
        if let chainYield { return (chainYield, Int(OllaStake.windowDays)) }
        return r.chainAPY()
    }

    /// The demo's Tacit account: sample money on both networks, open, read
    /// from nowhere (the demo reaches no host). Its pool sizes are the real
    /// ones read on 2026-11-24.
    static let demoReading = Reading(
        coSigner: YourAccountDemo.signer,
        address: "bp1qff6cr0pdgh7w3k9t5m2x8v4n6j0c1ryz5e8q2u7a4s9d3fx9k2",
        receive: "0x9c4C4932dcc0911951fD4E2d77e3cb07FaB441c4",
        held: [Held(chainId: 1, network: "Ethereum", eth: 0.42, waiting: 0, pool: 14.7, reached: true),
               Held(chainId: 4663, network: "Robinhood", eth: 0.03, waiting: 0.01, pool: 0.10, reached: true)],
        asOf: .now, publicTAC: 240, privateTAC: 310, accountTAC: 55, defiTAC: 0,
        chainAddress: "tc1" + String(repeating: "3f", count: 40) + "c91d",
        chainRate: 1.0123, earnedTAC: 2.1, chainNotes: 12_135, earnedSince: Date.now.addingTimeInterval(-21 * 86_400),
        receiveNetwork: "Ethereum", farmed: TacitFarms.demoPositions,
        rateMarks: [RateMark(at: Date.now.addingTimeInterval(-21 * 86_400), rate: 1.0055)])
    static let demoPrice = 3_850.0
    static let demoTacPrice = 0.78

    var phase: Phase { DemoMode.isActive ? .open : livePhase }
    var reading: Reading? { DemoMode.isActive ? Self.demoReading : liveReading }
    /// **ONE RULE FOR "YOU HAVE TACIT" (prd §1984):** a reading, and a
    /// co-signer to open it. Every Move list asks this, never its own.
    var connected: Bool { reading != nil && (!YourAccountFacts.coSigners.isEmpty || DemoMode.isActive) }
    /// Dollars per ETH, as last priced; nil until a price has answered.
    var ethPrice: Double? { DemoMode.isActive ? Self.demoPrice : livePrice }

    private static let readingKey = "tacit.reading.v1"
    private static let priceKey = "tacit.ethPrice.v1"
    private static let tacPriceKey = "tacit.tacPrice.v1"
    private static let farmsKey = "tacit.farms.v1"
    private var liveFarms: TacitFarms.Reading?

    /// Tacit's farms as last read (prd §1993): public facts, kept between
    /// launches, read again each time the account opens.
    var farms: TacitFarms.Reading? { DemoMode.isActive ? TacitFarms.demo : liveFarms }

    /// Your farm positions in dollars: their shares at today's pool and the
    /// TAC they earned, unclaimed; nil when none was read or TAC has no price.
    var farmUSD: Double? {
        guard let positions = reading?.farmed, !positions.isEmpty, let farms, let tacPrice else { return nil }
        let tac = positions.reduce(0.0) { $0 + (TacitFarms.worthTAC($1, in: farms) ?? 0) + $1.pendingTAC }
        return tac * tacPrice
    }

    /// One position in dollars, shares and earned TAC together.
    func farmUSD(_ position: TacitFarms.Position) -> Double? {
        guard let farms, let tacPrice, let worth = TacitFarms.worthTAC(position, in: farms) else { return nil }
        return (worth + position.pendingTAC) * tacPrice
    }

    /// Dollars per TAC, as DeFiLlama last priced the token; nil until it has.
    var tacPrice: Double? { DemoMode.isActive ? Self.demoTacPrice : liveTacPrice }

    /// TAC's move over the last day, as a fraction (0.02 is 2% up); nil until
    /// DeFiLlama has said. Not kept between launches: a day's move goes stale.
    var tacMove: Double? { DemoMode.isActive ? 0.024 : liveTacMove }

    /// Public and private TAC in dollars; nil when none was read or TAC has
    /// no price.
    var tacUSD: Double? {
        guard let tac = reading?.tac, let tacPrice else { return nil }
        return tac * tacPrice
    }

    /// What the PAGE adds up: private ETH and public TAC. The Wallet's totals
    /// keep `usd`, the private ETH alone: the public TAC sits in your
    /// co-signer's own wallet, which a followed wallet may already count.
    var pageUSD: Double? {
        guard let reading else { return nil }
        let tac = reading.tac ?? 0
        if reading.eth > 0, usd == nil { return nil }
        if tac > 0, tacUSD == nil { return nil }
        return (usd ?? 0) + (tacUSD ?? 0)
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.readingKey),
           let kept = try? JSONDecoder().decode(Reading.self, from: data) {
            liveReading = kept
        }
        let price = UserDefaults.standard.double(forKey: Self.priceKey)
        if price > 0 { livePrice = price }
        let tac = UserDefaults.standard.double(forKey: Self.tacPriceKey)
        if tac > 0 { liveTacPrice = tac }
        if let data = UserDefaults.standard.data(forKey: Self.farmsKey),
           let kept = try? JSONDecoder().decode(TacitFarms.Reading.self, from: data) {
            liveFarms = kept
        }
    }

    var isOpen: Bool { phase == .open || phase == .reading }

    /// How long a reading counts in the Wallet's totals: three days, as a
    /// lent reading does (`LendMove`). Past it the page still shows it, dated.
    static let countsFor: TimeInterval = 3 * 86_400

    /// What the Wallet's totals add: the last reading's dollars while it is
    /// recent and its co-signer is still this account's; nil otherwise.
    var countedUSD: Double? {
        guard let reading, let usd = privateUSD else { return nil }
        if DemoMode.isActive { return usd }
        guard Date.now.timeIntervalSince(reading.asOf) < Self.countsFor,
              YourAccountFacts.coSigners.contains(where: { $0.caseInsensitiveCompare(reading.coSigner) == .orderedSame })
        else { return nil }
        return usd
    }

    /// The engine dropped its page (iOS reclaimed it, or it failed): the key
    /// went with it, so the account is closed.
    func engineStopped() {
        keyPrint = nil
        if livePhase == .open || livePhase == .reading { livePhase = .closed }
    }

    /// The private TAC on the Tacit chain, in dollars; nil when it was not
    /// read or TAC has no price.
    var privateTacUSD: Double? {
        guard let tac = reading?.privateTACAll, let tacPrice else { return nil }
        return tac * tacPrice
    }

    /// The account's PRIVATE money in dollars, what the Wallet's Private
    /// total counts: private ETH and private TAC. Public TAC is left out: it
    /// is in your co-signer's own wallet. nil when nothing held has a price.
    var privateUSD: Double? {
        guard reading != nil, usd != nil || privateTacUSD != nil || farmUSD != nil else { return nil }
        return (usd ?? 0) + (privateTacUSD ?? 0) + (farmUSD ?? 0)
    }

    /// The account's private ETH in dollars at the last reading; nil with no
    /// reading or no price.
    var usd: Double? {
        guard let reading, let ethPrice else { return nil }
        return reading.eth * ethPrice
    }

    func usd(_ held: Held) -> Double? {
        ethPrice.map { held.eth * $0 }
    }

    /// Your share of a network's pool, 0...1; nil when the pool was not
    /// read or you hold nothing there.
    static func share(_ held: Held) -> Double? {
        guard let pool = held.pool, pool > 0, held.eth > 0 else { return nil }
        return min(1, held.eth / pool)
    }

    /// From this share up, the pool is too small to hide the amount well:
    /// a tenth of everything in it.
    static let thinShare = 0.10

    // MARK: - Opening and closing

    /// Asks `coSigner`'s wallet for Tacit's signature, opens the account it
    /// makes and reads it. A cancelled ask leaves the page as it was.
    func open(coSigner: String) async {
        guard !DemoMode.isActive, livePhase != .connecting, livePhase != .signing, livePhase != .reading else { return }
        // The reads go through Tor on iOS, and a cold start takes about a
        // minute: wait for it BEFORE the co-signer signs, so a signature is
        // never spent on a read that cannot leave.
        if TorRoute.available, !TorClient.shared.isConnected {
            livePhase = .connecting
            let began = Date()
            TorClient.shared.start()
            while !TorClient.shared.isConnected, Date().timeIntervalSince(began) < 90 {
                try? await Task.sleep(for: .milliseconds(500))
            }
            guard TorClient.shared.isConnected else {
                livePhase = .failed(String(localized: "Tor could not connect"))
                return
            }
        }
        livePhase = .signing
        var key: [UInt8]
        do {
            key = try await TacitPocket.signIn(coSigner: coSigner)
        } catch is CancellationError {
            livePhase = .closed
            return
        } catch {
            livePhase = .failed(Self.words(error))
            return
        }
        defer { for i in key.indices { key[i] = 0 } }
        keyPrint = Array(SHA256.hash(data: key))
        livePhase = .reading
        do {
            let opened = try await TacitPocket.open(key: key)
            let me = coSigner.lowercased()
            let prior = liveReading.flatMap { $0.coSigner == me ? $0 : nil }
            let networks = await TacitPocket.networks(opened)
            // Nothing answered: that is an outage, never a reading. The last
            // one stands, with its own date.
            guard networks.contains(where: { $0.reading != nil }) else {
                TacitEngine.shared.stop()
                livePhase = .failed(String(localized: "Tacit could not be read"))
                return
            }
            let held = networks.map { n in
                Held(chainId: n.network.chainId, network: n.network.name,
                     eth: n.reading.flatMap { Self.eth($0.balance) } ?? prior?.held.first { $0.chainId == n.network.chainId }?.eth ?? 0,
                     waiting: n.reading.flatMap { Self.eth($0.waiting) } ?? 0,
                     pool: n.reading.flatMap { $0.pool }.flatMap { Self.eth($0) },
                     reached: n.reading != nil)
            }
            // **ROWS FILL IN AS EACH READ LANDS (user, 2026-11-24, "do all",
            // of "open instantly, then refresh").** The networks first, the
            // last reading's TAC standing until its own read replaces it.
            var reading = prior ?? Reading(coSigner: me, address: "", receive: "", held: [], asOf: .now)
            let paidAt = networks.first { !$0.receive.isEmpty }
            reading = Reading(coSigner: me, address: opened.address ?? reading.address,
                              receive: paidAt?.receive ?? reading.receive,
                              held: held, asOf: .now, publicTAC: reading.publicTAC, privateTAC: reading.privateTAC,
                              privateElsewhere: reading.privateElsewhere, defiTAC: reading.defiTAC,
                              chainAddress: reading.chainAddress, chainShares: reading.chainShares,
                              chainRate: reading.chainRate, earnedTAC: reading.earnedTAC, chainNotes: reading.chainNotes,
                              earnedSince: reading.earnedSince,
                              receiveNetwork: paidAt.map { $0.network.name } ?? reading.receiveNetwork,
                              farmed: reading.farmed, rateMarks: reading.rateMarks)
            keep(reading)
            if let tac = await TacitPocket.publicTAC(of: coSigner) { update(me) { $0.publicTAC = tac } }
            if let account = YourAccountKey.address, let tac = await TacitPocket.publicTAC(of: account) {
                update(me) { $0.accountTAC = tac }
            }
            await readPrice()
            // The Tacit chain and the DeFi pool, side by side: each is kept
            // the moment it answers.
            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in
                    guard let chain = await TacitPocket.chain(coSigner: coSigner) else { return }
                    self.update(me) { Self.apply(chain, to: &$0) }
                }
                group.addTask { @MainActor in
                    guard let defi = await TacitPocket.defi() else { return }
                    self.update(me) { $0.defiTAC = TacitEngineWire.tac(defi.worth).map { NSDecimalNumber(decimal: $0).doubleValue } }
                    // Your farm positions after the DeFi read: the pool's
                    // logs it read are kept, so this pass reads only the farm's.
                    if let farmed = await TacitPocket.farmed() { self.update(me) { $0.farmed = farmed } }
                }
                group.addTask { @MainActor in await self.readFarms() }
            }
            livePhase = .open
        } catch {
            TacitEngine.shared.stop()
            livePhase = .failed(Self.words(error))
        }
    }

    /// Tacit's farms, read for anyone; kept as they answer (prd §1993).
    func readFarms() async {
        guard !DemoMode.isActive, let farms = await TacitPocket.farms() else { return }
        liveFarms = farms
        if let data = try? JSONEncoder().encode(farms) { DefaultsWrite.set(data, forKey: Self.farmsKey) }
    }

    /// Earn's farms when none was read, or the last is over an hour old.
    /// The farm read needs no key, so it never waits for the account to be
    /// opened again: build 1094 read farms only on opening, and an account
    /// opened before it showed no farms at all.
    func readFarmsIfStale() async {
        guard !DemoMode.isActive, !readingFarms,
              liveFarms.map({ Date.now.timeIntervalSince($0.asOf) > 3_600 }) ?? true else { return }
        readingFarms = true
        defer { readingFarms = false }
        await readFarms()
    }
    @ObservationIgnored private var readingFarms = false

    /// Whether `key` is the key the open account was made from.
    func isKey(_ key: [UInt8]) -> Bool {
        guard let keyPrint, livePhase == .open || livePhase == .reading else { return false }
        return Array(SHA256.hash(data: key)) == keyPrint
    }

    /// A Tacit chain read made after the account opened (a deposit landed).
    func applyChain(_ chain: TacitEngineWire.ChainReading, coSigner: String) {
        update(coSigner.lowercased()) { Self.apply(chain, to: &$0) }
    }

    /// A Tacit chain reading into a reading: what is held, the address, and
    /// what the shares earned since the last reading on the same shares.
    static func apply(_ chain: TacitEngineWire.ChainReading, to r: inout Reading) {
        let tac = { (hex: String) in TacitEngineWire.tac(hex).map { NSDecimalNumber(decimal: $0).doubleValue } }
        r.privateTAC = tac(chain.worth)
        r.privateElsewhere = chain.elsewhere
        r.chainAddress = chain.chainAddress
        if chain.leaves > 0 { r.chainNotes = chain.leaves }
        guard let shares = tac(chain.shares), let pool = tac(chain.pool), let all = tac(chain.allShares) else { return }
        // Tacit's own rate: a share is the pool over the shares, each with
        // the contract's virtual 1 TAC (`VIRTUAL`, 1e8 units).
        let rate = (pool + 1) / (all + 1)
        if let before = r.chainShares, let was = r.chainRate, before > 0, rate > was {
            r.earnedTAC = (r.earnedTAC ?? 0) + before * (rate - was)
        }
        if r.earnedSince == nil { r.earnedSince = .now }
        // **THE FIRST MARK, FROM WHAT WAS EARNED (prd §1999).** A reading
        // kept before marks were recorded holds the TAC its shares earned
        // since `earnedSince`: the price then was the price now less what
        // each share earned, exact while the shares were not changed.
        if r.rateMarks == nil, let earned = r.earnedTAC, let since = r.earnedSince, let held = r.chainShares, held > 0,
           rate - earned / held > 0 {
            r.rateMarks = [RateMark(at: since, rate: rate - earned / held)]
        }
        r.rateMarks = Self.marked(r.rateMarks ?? [], rate: rate)
        r.chainShares = shares
        r.chainRate = rate
    }

    /// The marks with today's price: one a day at most, none past 31 days.
    static func marked(_ marks: [RateMark], rate: Double, now: Date = .now) -> [RateMark] {
        var out = marks.filter { now.timeIntervalSince($0.at) <= 31 * 86_400 }
        if out.last.map({ now.timeIntervalSince($0.at) >= 86_400 }) ?? true {
            out.append(RateMark(at: now, rate: rate))
        }
        return out
    }

    /// Your public TAC again, in your co-signer's wallet and your Casberi
    /// account: two balance reads, no key (after back to public, §1977).
    func readPublic() async {
        guard !DemoMode.isActive, let me = liveReading?.coSigner else { return }
        if let tac = await TacitPocket.publicTAC(of: me) { update(me) { $0.publicTAC = tac } }
        if let account = YourAccountKey.address, let tac = await TacitPocket.publicTAC(of: account) {
            update(me) { $0.accountTAC = tac }
        }
    }

    /// Changes the kept reading in place, if it is still this co-signer's.
    private func update(_ coSigner: String, _ change: (inout Reading) -> Void) {
        guard var r = liveReading, r.coSigner == coSigner else { return }
        change(&r)
        keep(r)
    }

    /// Closes the account: the page, and the key with it, are dropped. The
    /// last reading stays.
    func close() {
        guard !DemoMode.isActive else { return }
        keyPrint = nil
        TacitEngine.shared.stop()
        livePhase = .closed
    }

    /// Removing the app forgets the reading too.
    func forget() {
        close()
        if let coSigner = liveReading?.coSigner { TacitChainScan.forget(coSigner) }
        liveReading = nil
        UserDefaults.standard.removeObject(forKey: Self.readingKey)
    }

    func readPrice() async {
        if let price = await MainnetPrices.prices(for: ["ETH"])["ETH"], price > 0 {
            livePrice = price
            UserDefaults.standard.set(price, forKey: Self.priceKey)
        }
        // TAC by its contract, at DeFiLlama, and only a price it stands behind.
        let mint = (network: "eth-mainnet", contract: TacitPocket.tacToken)
        if let tac = await DefiLlamaPrices.prices(for: [mint])["\(mint.network)|\(mint.contract)"],
           tac.confidence >= DefiLlamaPrices.confidenceFloor {
            liveTacPrice = tac.price
            UserDefaults.standard.set(tac.price, forKey: Self.tacPriceKey)
            let id = "ethereum:\(mint.contract)"
            if let root = await IngestSupport.getJSON("https://coins.llama.fi/percentage/\(id)") as? [String: Any],
               let coins = root["coins"] as? [String: Any],
               let percent = (coins[id] as? NSNumber)?.doubleValue, percent.isFinite {
                liveTacMove = percent / 100
            }
        }
    }

    #if DEBUG
    /// `-tacitSample open|closed|clear`: a sample reading, so the page can be
    /// looked at on a simulator, where no co-signer's wallet can sign.
    /// Nothing is read and nothing is kept past `clear`.
    func sample(_ raw: String) {
        guard raw != "clear" else { forget(); return }
        liveReading = Reading(coSigner: "0x2c7536e3605d9c16a7a3d7b1898e529396a65c23",
                          address: "bp1qff6cr0pdghsamplesamplesamplesamplesamplex9k2",
                          receive: "0x9c4C4932dcc0911951fD4E2d77e3cb07FaB441c4",
                          held: [Held(chainId: 1, network: "Ethereum", eth: 0.42, waiting: 0, pool: 14.7, reached: true),
                                 Held(chainId: 4663, network: "Robinhood", eth: 0.03, waiting: 0.01, pool: 0.10, reached: true)],
                          asOf: raw == "closed" ? Date.now.addingTimeInterval(-3 * 3600) : .now,
                          publicTAC: 23.85, receiveNetwork: "Ethereum")
        livePrice = 2044
        liveTacPrice = 0.78
        liveTacMove = 0.115
        if raw == "tac" {
            // A TAC-only account, as the user's own reads: no private ETH.
            liveReading = Reading(coSigner: "0x2c7536e3605d9c16a7a3d7b1898e529396a65c23",
                                  address: "bp1qff6cr0pdghsamplesamplesamplesamplesamplex9k2",
                                  receive: "0x9c4C4932dcc0911951fD4E2d77e3cb07FaB441c4",
                                  held: [Held(chainId: 1, network: "Ethereum", eth: 0, waiting: 0, pool: 14.7, reached: true),
                                         Held(chainId: 4663, network: "Robinhood", eth: 0, waiting: 0, pool: 0.10, reached: true)],
                                  asOf: .now, publicTAC: 23.85, privateTAC: 10.02, defiTAC: 0,
                                  chainAddress: "tc1" + String(repeating: "5a", count: 40) + "7e2c",
                                  earnedTAC: 0.04, earnedSince: Date.now.addingTimeInterval(-6 * 86_400),
                                  receiveNetwork: "Ethereum")
        }
        livePhase = raw == "closed" ? .closed : .open
    }
    #endif

    private func keep(_ new: Reading) {
        liveReading = new
        if let data = try? JSONEncoder().encode(new) {
            UserDefaults.standard.set(data, forKey: Self.readingKey)
        }
    }

    private static func eth(_ hex: String) -> Double? {
        TacitEngineWire.eth(hex).map { NSDecimalNumber(decimal: $0).doubleValue }
    }

    /// One plain clause for what went wrong.
    static func words(_ error: Error) -> String {
        if let failure = error as? TacitIdentity.Failure {
            switch failure {
            case .notCanonical: return String(localized: "That wallet's signature cannot open a Tacit account")
            case .malformed: return String(localized: "That wallet did not answer with a signature")
            }
        }
        if let link = error as? YourAccountSignerLink.Failure {
            switch link {
            case .timedOut: return String(localized: "Your co-signer did not answer")
            case .declined, .refused: return String(localized: "Your co-signer declined")
            case .notTheSigner, .notProven: return String(localized: "That wallet is not your co-signer")
            default: return String(localized: "Your co-signer could not be reached")
            }
        }
        return String(localized: "Tacit could not be read")
    }
}
