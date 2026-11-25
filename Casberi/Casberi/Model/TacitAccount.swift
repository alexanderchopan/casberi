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
        var earnedSince: Date? = nil

        /// Private TAC in both places; nil when neither was read.
        var privateTACAll: Double? {
            privateTAC == nil && defiTAC == nil ? nil : (privateTAC ?? 0) + (defiTAC ?? 0)
        }

        /// Public and private TAC together; nil when none was read.
        var tac: Double? {
            publicTAC == nil && privateTACAll == nil ? nil : (publicTAC ?? 0) + (privateTACAll ?? 0)
        }

        var eth: Double { held.map(\.eth).reduce(0, +) }
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

    /// The demo's Tacit account: sample money on both networks, open, read
    /// from nowhere (the demo reaches no host). Its pool sizes are the real
    /// ones read on 2026-11-24.
    static let demoReading = Reading(
        coSigner: YourAccountDemo.signer,
        address: "bp1qff6cr0pdgh7w3k9t5m2x8v4n6j0c1ryz5e8q2u7a4s9d3fx9k2",
        receive: "0x9c4C4932dcc0911951fD4E2d77e3cb07FaB441c4",
        held: [Held(chainId: 1, network: "Ethereum", eth: 0.42, waiting: 0, pool: 14.7, reached: true),
               Held(chainId: 4663, network: "Robinhood", eth: 0.03, waiting: 0.01, pool: 0.10, reached: true)],
        asOf: .now, publicTAC: 240, privateTAC: 310, defiTAC: 0,
        chainAddress: "tc1" + String(repeating: "3f", count: 40) + "c91d",
        earnedTAC: 2.1, earnedSince: Date.now.addingTimeInterval(-21 * 86_400))
    static let demoPrice = 3_850.0
    static let demoTacPrice = 0.78

    var phase: Phase { DemoMode.isActive ? .open : livePhase }
    var reading: Reading? { DemoMode.isActive ? Self.demoReading : liveReading }
    /// Dollars per ETH, as last priced; nil until a price has answered.
    var ethPrice: Double? { DemoMode.isActive ? Self.demoPrice : livePrice }

    private static let readingKey = "tacit.reading.v1"
    private static let priceKey = "tacit.ethPrice.v1"
    private static let tacPriceKey = "tacit.tacPrice.v1"

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
        guard reading != nil, usd != nil || privateTacUSD != nil else { return nil }
        return (usd ?? 0) + (privateTacUSD ?? 0)
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
            reading = Reading(coSigner: me, address: opened.address ?? reading.address,
                              receive: networks.first { !$0.receive.isEmpty }?.receive ?? reading.receive,
                              held: held, asOf: .now, publicTAC: reading.publicTAC, privateTAC: reading.privateTAC,
                              privateElsewhere: reading.privateElsewhere, defiTAC: reading.defiTAC,
                              chainAddress: reading.chainAddress, chainShares: reading.chainShares,
                              chainRate: reading.chainRate, earnedTAC: reading.earnedTAC, earnedSince: reading.earnedSince)
            keep(reading)
            if let tac = await TacitPocket.publicTAC(of: coSigner) { update(me) { $0.publicTAC = tac } }
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
                }
            }
            livePhase = .open
        } catch {
            TacitEngine.shared.stop()
            livePhase = .failed(Self.words(error))
        }
    }

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
        guard let shares = tac(chain.shares), let pool = tac(chain.pool), let all = tac(chain.allShares) else { return }
        // Tacit's own rate: a share is the pool over the shares, each with
        // the contract's virtual 1 TAC (`VIRTUAL`, 1e8 units).
        let rate = (pool + 1) / (all + 1)
        if let before = r.chainShares, let was = r.chainRate, before > 0, rate > was {
            r.earnedTAC = (r.earnedTAC ?? 0) + before * (rate - was)
        }
        if r.earnedSince == nil { r.earnedSince = .now }
        r.chainShares = shares
        r.chainRate = rate
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
                          publicTAC: 23.85)
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
                                  earnedTAC: 0.04, earnedSince: Date.now.addingTimeInterval(-6 * 86_400))
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
