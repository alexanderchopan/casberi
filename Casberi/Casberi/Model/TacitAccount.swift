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
        /// The plain address any wallet or exchange pays, on either network.
        let receive: String
        let held: [Held]
        let asOf: Date

        var eth: Double { held.map(\.eth).reduce(0, +) }
    }

    private var livePhase: Phase = .closed
    private var liveReading: Reading?
    private var livePrice: Double?

    /// The demo's Tacit account: sample money on both networks, open, read
    /// from nowhere (the demo reaches no host). Its pool sizes are the real
    /// ones read on 2026-11-24.
    static let demoReading = Reading(
        coSigner: YourAccountDemo.signer,
        address: "bp1qff6cr0pdgh7w3k9t5m2x8v4n6j0c1ryz5e8q2u7a4s9d3fx9k2",
        receive: "0x9c4C4932dcc0911951fD4E2d77e3cb07FaB441c4",
        held: [Held(chainId: 1, network: "Ethereum", eth: 0.42, waiting: 0, pool: 14.7, reached: true),
               Held(chainId: 4663, network: "Robinhood", eth: 0.03, waiting: 0.01, pool: 0.10, reached: true)],
        asOf: .now)
    static let demoPrice = 3_850.0

    var phase: Phase { DemoMode.isActive ? .open : livePhase }
    var reading: Reading? { DemoMode.isActive ? Self.demoReading : liveReading }
    /// Dollars per ETH, as last priced; nil until a price has answered.
    var ethPrice: Double? { DemoMode.isActive ? Self.demoPrice : livePrice }

    private static let readingKey = "tacit.reading.v1"
    private static let priceKey = "tacit.ethPrice.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.readingKey),
           let kept = try? JSONDecoder().decode(Reading.self, from: data) {
            liveReading = kept
        }
        let price = UserDefaults.standard.double(forKey: Self.priceKey)
        if price > 0 { livePrice = price }
    }

    var isOpen: Bool { phase == .open || phase == .reading }

    /// How long a reading counts in the Wallet's totals: three days, as a
    /// lent reading does (`LendMove`). Past it the page still shows it, dated.
    static let countsFor: TimeInterval = 3 * 86_400

    /// What the Wallet's totals add: the last reading's dollars while it is
    /// recent and its co-signer is still this account's; nil otherwise.
    var countedUSD: Double? {
        guard let reading, let usd else { return nil }
        if DemoMode.isActive { return usd }
        guard Date.now.timeIntervalSince(reading.asOf) < Self.countsFor,
              YourAccountFacts.coSigners.contains(where: { $0.caseInsensitiveCompare(reading.coSigner) == .orderedSame })
        else { return nil }
        return usd
    }

    /// The engine dropped its page (iOS reclaimed it, or it failed): the key
    /// went with it, so the account is closed.
    func engineStopped() {
        if livePhase == .open || livePhase == .reading { livePhase = .closed }
    }

    /// What the account is worth in dollars at the last reading; nil with no
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
        livePhase = .reading
        do {
            let overview = try await TacitPocket.overview(key: key)
            // Nothing answered: that is an outage, never a reading. The last
            // one stands, with its own date.
            guard overview.networks.contains(where: { $0.reading != nil }) else {
                TacitEngine.shared.stop()
                livePhase = .failed(String(localized: "Tacit could not be read"))
                return
            }
            let held = overview.networks.map { n in
                Held(chainId: n.network.chainId, network: n.network.name,
                     eth: n.reading.flatMap { Self.eth($0.balance) } ?? liveReading?.held.first { $0.chainId == n.network.chainId }?.eth ?? 0,
                     waiting: n.reading.flatMap { Self.eth($0.waiting) } ?? 0,
                     pool: n.reading.flatMap { $0.pool }.flatMap { Self.eth($0) },
                     reached: n.reading != nil)
            }
            let receive = overview.networks.first { !$0.receive.isEmpty }?.receive ?? ""
            keep(Reading(coSigner: coSigner.lowercased(), address: overview.address, receive: receive,
                         held: held, asOf: .now))
            livePhase = .open
            await readPrice()
        } catch {
            TacitEngine.shared.stop()
            livePhase = .failed(Self.words(error))
        }
    }

    /// Closes the account: the page, and the key with it, are dropped. The
    /// last reading stays.
    func close() {
        guard !DemoMode.isActive else { return }
        TacitEngine.shared.stop()
        livePhase = .closed
    }

    /// Removing the app forgets the reading too.
    func forget() {
        close()
        liveReading = nil
        UserDefaults.standard.removeObject(forKey: Self.readingKey)
    }

    func readPrice() async {
        guard let price = await MainnetPrices.prices(for: ["ETH"])["ETH"], price > 0 else { return }
        livePrice = price
        UserDefaults.standard.set(price, forKey: Self.priceKey)
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
                          asOf: raw == "closed" ? Date.now.addingTimeInterval(-3 * 3600) : .now)
        livePrice = 2044
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
