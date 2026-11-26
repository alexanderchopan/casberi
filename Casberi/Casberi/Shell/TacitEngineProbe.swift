#if DEBUG
import Foundation
import Security

/// `-tacitEngineProbe <step>` — drives the Tacit engine headless and NSLogs
/// `tacitEngine| <step> | <ms> | <detail>`. Read-only: nothing is sent.
///
/// A RANDOM key every run, kept nowhere (an empty account): what is measured
/// is the engine, not anyone's money. `-tacitEngineKey <0x…64 hex>` opens
/// that key's account instead.
/// - `identity` Tacit's own test wallet through `TacitIdentity`: the message
///            recovers its address, its signature makes Tacit's key, and a
///            high-s signature is refused
/// - `load`   start the web view, load the bundle, ask what it carries
/// - `open`   open the account on Ethereum and Robinhood
/// - `read`   find its notes on each network and add them up
/// - `chain`  try the Tacit chain's notes with its key: private TAC
/// - `prove`  quote and prove a deposit of 1 TAC, never handed
/// - `resume` a chain scan, then one resumed from where it stopped
/// - `defi`   read Tacit's DeFi pool with its key: private TAC there
/// - `all`    identity, load, open, read, chain, defi
enum TacitEngineProbe {

    @MainActor
    static func run(_ raw: String) {
        Task { @MainActor in
            let steps: [String] = raw == "all" || raw == "YES"
                ? ["identity", "load", "open", "read", "chain", "defi"]
                : raw.split(separator: ",").map(String.init)
            var key: [UInt8]?
            for step in steps {
                do {
                    switch step {
                    case "identity":
                        log("identity", 0, identityCheck())
                    case "load":
                        let t = Date()
                        try await TacitEngine.shared.start()
                        let info = try await TacitEngine.shared.info()
                        log("load", ms(t), "pool \(info.pool) networks \(info.chains.map(String.init).joined(separator: ","))")
                    case "open":
                        // The engine's reads ride Tor on iOS, and a cold
                        // launch takes about a minute to connect: wait for it
                        // here, so a slow start is not read as a dead node.
                        if TorRoute.available {
                            let began = Date()
                            TorClient.shared.start()
                            while !TorClient.shared.isConnected, Date().timeIntervalSince(began) < 150 {
                                try? await Task.sleep(for: .milliseconds(500))
                            }
                            log("tor", ms(began), TorClient.shared.isConnected ? "connected" : "NOT connected")
                        }
                        let t = Date()
                        let given = UserDefaults.standard.string(forKey: "tacitEngineKey").flatMap(SafeABI.hexBytes)
                        let fromRoot = given?.count == 32
                        let made = try given.flatMap { $0.count == 32 ? $0 : nil } ?? randomKey()
                        key = made
                        let opened = try await TacitEngine.shared.open(key: made)
                        let places = opened.networks.map { "\($0.chainId) receive \($0.receive) \($0.ms) ms" }.joined(separator: " · ")
                        log("open", ms(t), "\(fromRoot ? "given" : "random") key · address \(opened.address.map { "\($0.prefix(14))… (\($0.count) chars)" } ?? "none") · \(places)")
                    case "read":
                        guard key != nil else { throw TacitEngineWire.Failure(name: "NotOpen", message: "open first") }
                        for network in TacitNetwork.all {
                            let t = Date()
                            do {
                                let r = try await TacitEngine.shared.read(chainId: network.chainId)
                                let balance = TacitEngineWire.eth(r.balance).map { "\($0)" } ?? r.balance
                                let waiting = TacitEngineWire.eth(r.waiting).map { "\($0)" } ?? r.waiting
                                log("read", ms(t), "\(network.name) · balance \(balance) ETH · waiting \(waiting) ETH · \(r.notes) notes · pool \(r.leaves) entries to block \(r.block) behind \(r.behind) · page \(r.ms) ms")
                            } catch {
                                log("read", ms(t), "\(network.name) FAILED \(describe(error))")
                            }
                        }
                    case "chain":
                        guard key != nil else { throw TacitEngineWire.Failure(name: "NotOpen", message: "open first") }
                        let t = Date()
                        let r = try await TacitEngine.shared.chain()
                        let worth = TacitEngineWire.tac(r.worth).map { "\($0)" } ?? r.worth
                        log("chain", ms(t), "worth \(worth) TAC · \(r.notes) notes, \(r.spent) spent · \(r.leaves) tried · elsewhere \(r.elsewhere) · page \(r.ms) ms")
                    case "both":
                        // The chain and the DeFi pool at once, as opening
                        // Tacit reads them (`TacitAccount.open`).
                        guard key != nil else { throw TacitEngineWire.Failure(name: "NotOpen", message: "open first") }
                        let t = Date()
                        async let c: String = {
                            do { let r = try await TacitEngine.shared.chain(); return "chain \(r.next) tried in \(r.ms) ms" }
                            catch { return "chain FAILED \(describe(error))" }
                        }()
                        async let d: String = {
                            do { let r = try await TacitEngine.shared.defi(); return "defi whole \(r.whole) errors \(r.errors.joined(separator: ",")) in \(r.ms) ms" }
                            catch { return "defi FAILED \(describe(error))" }
                        }()
                        let (cs, ds) = await (c, d)
                        log("both", ms(t), "\(cs) · \(ds)")
                    case "prove":
                        // A deposit of 1 TAC quoted and proved, never handed:
                        // `shieldHand` is not called, nothing is signed.
                        guard key != nil else { throw TacitEngineWire.Failure(name: "NotOpen", message: "open first") }
                        let t = Date()
                        let q = try await TacitEngine.shared.shieldQuote(units: 100_000_000)
                        let p = try await TacitEngine.shared.shieldProve(units: 100_000_000)
                        log("prove", ms(t), "fee \(q.sweepFee) arrives \(q.arrives) · proved in \(p.proveMs) ms · inbox \(p.inbox) · value \(p.value) · index \(p.index)")
                    case "race":
                        // The phone's hang (2026-11-25): Make private asked
                        // while the DeFi read was still going. The slot read
                        // now waits for it; this proves alongside it.
                        guard key != nil else { throw TacitEngineWire.Failure(name: "NotOpen", message: "open first") }
                        let t = Date()
                        async let d = TacitEngine.shared.defi()
                        try await Task.sleep(for: .seconds(2))
                        _ = try await TacitEngine.shared.shieldQuote(units: 100_000_000)
                        let p = try await TacitEngine.shared.shieldProve(units: 100_000_000)
                        let proved = ms(t)
                        let r = try await d
                        log("race", proved, "proved in \(p.proveMs) ms · index \(p.index) · defi \(r.ms) ms")
                    case "resume":
                        // A scan, then one resumed from where it stopped:
                        // the second tries only what came after.
                        guard key != nil else { throw TacitEngineWire.Failure(name: "NotOpen", message: "open first") }
                        let t = Date()
                        let first = try await TacitEngine.shared.chain()
                        let t2 = Date()
                        let again = try await TacitEngine.shared.chain(from: first.next, known: first.kept)
                        log("resume", ms(t), "first \(first.next) tried in \(first.ms) ms · resumed from \(first.next) to \(again.next) in \(Int(Date().timeIntervalSince(t2) * 1000)) ms · address \(again.chainAddress.prefix(10))… (\(again.chainAddress.count) chars)")
                    case "out":
                        // Back to public (prd §1977), read only: the notes
                        // scanned, the quote for 1 TAC, the most that can go,
                        // and what the contract owes this key's own address.
                        // A random key holds nothing, so nothing is proved.
                        guard key != nil else { throw TacitEngineWire.Failure(name: "NotOpen", message: "open first") }
                        let t = Date()
                        let q = try await TacitEngine.shared.outQuote(units: 100_000_000)
                        let owed = try await TacitEngine.shared.owed("0x000000000000000000000000000000000000dEaD")
                        log("out", ms(t), "fee \(q.fee) · holders \(q.holders) · most \(q.most) · owed to 0x…dEaD \(owed.wei)")
                    case "defi":
                        guard key != nil else { throw TacitEngineWire.Failure(name: "NotOpen", message: "open first") }
                        let t = Date()
                        let r = try await TacitEngine.shared.defi()
                        let worth = TacitEngineWire.tac(r.worth).map { "\($0)" } ?? r.worth
                        log("defi", ms(t), "worth \(worth) TAC · \(r.notes) notes · \(r.leaves) leaves · whole \(r.whole) · passes \(r.passes) · errors \(r.errors.joined(separator: ",")) · page \(r.ms) ms")
                    default:
                        log(step, 0, "unknown step")
                    }
                } catch {
                    log(step, 0, "FAILED \(describe(error))")
                    break
                }
            }
            await TacitEngine.shared.close()
            TacitEngine.shared.stop()
            log("done", 0, "")
        }
    }

    /// Tacit's own test wallet (`tests/identity-message.test.mjs`): its
    /// address, its signature over the message and the key that makes,
    /// computed with ethers 6 on 2026-11-24.
    private static func identityCheck() -> String {
        let address = "0x2c7536e3605d9c16a7a3d7b1898e529396a65c23"
        let signature = SafeABI.hexBytes("0x39be0db0be35278658a49b95b2291961de3c1ec8ada6ab675fd6af8377d4fd8a726dfaeb9b9cc7c878aa529c16242d84a19ad83d8069866a71a748bcdc8f53ba1c") ?? []
        let want = "f05bf1d9bb3fbe2766822069f56d6abeb47b00ea07c25e9357189dc8dc036f92"
        let recovered = EcRecover.address(digest: TacitIdentity.digest, signature: signature) ?? "none"
        let key = (try? TacitIdentity.key(fromSignature: signature)).map { $0.map { String(format: "%02x", $0) }.joined() } ?? "none"
        // The same signature in its high form: (r, n - s, the other v).
        var high = signature
        if high.count == 65 {
            let n: [UInt8] = [0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xfe,
                              0xba, 0xae, 0xdc, 0xe6, 0xaf, 0x48, 0xa0, 0x3b, 0xbf, 0xd2, 0x5e, 0x8c, 0xd0, 0x36, 0x41, 0x41]
            var borrow = 0
            for i in stride(from: 31, through: 0, by: -1) {
                let d = Int(n[i]) - Int(high[32 + i]) - borrow
                high[32 + i] = UInt8((d + 256) % 256); borrow = d < 0 ? 1 : 0
            }
            high[64] = high[64] == 27 ? 28 : 27
        }
        let refused: Bool
        do { _ = try TacitIdentity.key(fromSignature: high); refused = false } catch { refused = true }
        let ok = recovered == address && key == want && refused
        return "\(ok ? "ok" : "MISMATCH") · recovers \(recovered == address) · key \(key == want) · high-s refused \(refused)"
    }

    private static func randomKey() throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw TacitEngineWire.Failure(name: "NoRandom", message: "no random bytes")
        }
        return bytes
    }

    private static func describe(_ error: Error) -> String {
        if let failure = error as? TacitEngineWire.Failure { return "\(failure.name): \(failure.message)" }
        return "\(error)"
    }

    private static func ms(_ since: Date) -> Int { Int(Date().timeIntervalSince(since) * 1000) }

    private static func log(_ step: String, _ ms: Int, _ detail: String) {
        NSLog("tacitEngine| %@ | %d | %@", step, ms, detail)
    }
}
#endif
