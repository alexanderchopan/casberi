#if DEBUG
import Darwin
import Foundation

/// `-privacyEngineProbe <step>` — drives the Privacy Pools engine (prd §1540)
/// headless on Sepolia and NSLogs `privacyEngine| <step> | <ms> | <detail>`
/// with this app's memory footprint (the page's own memory is WebKit's
/// web-content process, measured from outside).
///
/// Steps, each including the ones before it where it needs them:
/// - `load`     start the web view, load the bundle, ask what it runs on
/// - `keys`     make the seed if there is none, derive the keys, open Sepolia
/// - `deposit`  registration state, the registration's two transactions,
///              then a 0.001 ETH deposit prepared WITH its proof
/// - `discover` your notes and private balance (a log scan from the pool's block)
/// - `bench`    a real-key proof on synthetic inputs for deposit, transact_1x1
///              (a withdrawal), transact_1x2 (a transfer) and transact_2x2;
///              `-privacyEngineSingleThread YES` proves without workers
/// - `spend`    a transfer and a withdrawal of 0.0005 ETH: needs an approved
///              note, so it names what is missing on an unfunded account
/// - `all`      load, keys, deposit, bench, discover, spend
/// - `forget`   delete the seed
///
/// `-privacyEngineOwner <0x…>` names the keystore owner (your account);
/// without it the probe's fixed owner, which holds nothing and never will.
/// Nothing is sent: every transaction is only prepared.
enum PrivacyEngineProbe {

    static let probeOwner = "0x00000000000000000000000000000000c0ffee01"
    static let eth = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"

    @MainActor
    static func run(_ raw: String) {
        Task { @MainActor in
            let steps: [String] = raw == "all"
                ? ["load", "keys", "deposit", "bench", "discover", "spend"]
                : raw.split(separator: ",").map(String.init)
            // Alone through the engine, every step (finding 8).
            await PrivacyEngine.exclusive {
                for step in steps {
                    do { try await run(step: step) } catch {
                        log(step, 0, "FAILED \(describe(error))")
                        if step == "load" || step == "keys" { break }
                    }
                }
            }
            log("done", 0, "footprint \(footprintMB()) MB peak \(peakMB()) MB")
        }
    }

    @MainActor
    private static func run(step: String) async throws {
        let engine = PrivacyEngine.shared
        let owner = UserDefaults.standard.string(forKey: "privacyEngineOwner") ?? probeOwner
        switch step {
        case "load":
            let t = Date()
            try await engine.start()
            let info = try await engine.info()
            log("load", ms(t), "sdk \(info.sdk) snarkjs \(info.snarkjs) wasm=\(info.webAssembly) workers=\(info.workers) cores=\(info.cores) secureContext=\(info.secureContext)")
        case "keys":
            var t = Date()
            if !PrivacyPoolsKey.exists() {
                try PrivacyPoolsKey.create()
                log("keys.create", ms(t), "seed stored")
            }
            t = Date()
            var seed = try PrivacyPoolsKey.seed(reason: "Open your private balance")
            log("keys.read", ms(t), "\(seed.count) bytes")
            t = Date()
            let opened = try await engine.open(seed: seed, owner: owner)
            seed.resetBytes(in: 0..<seed.count)
            log("keys.open", ms(t), "derive \(opened.keysMs) ms · session \(opened.sessionMs) ms · viewing key \(opened.viewingPublicKey.prefix(10))… · owner \(owner)")
        case "deposit":
            try await ensureOpen(owner)
            var t = Date()
            let registered = try await engine.isRegistered()
            log("deposit.isRegistered", ms(t), "\(registered.registered)")
            t = Date()
            let registration = try await engine.prepareRegister()
            log("deposit.prepareRegister", ms(t), "already=\(registration.alreadyRegistered) txs=\(registration.txs.count) to \(registration.txs.map { $0.to.prefix(10) }.joined(separator: ","))")
            t = Date()
            let deposit = try await engine.prepareDeposit(tokenId: eth, value: "0x38d7ea4c68000") // 0.001 ETH
            log("deposit.prepare", ms(t), "to \(deposit.tx.to.prefix(10))… value \(deposit.tx.value) calldata \(deposit.tx.data.count / 2 - 1) bytes · proofs \(deposit.proofs.map { "\($0.circuit ?? "?") \($0.ms) ms" }.joined(separator: ", "))")
            // The prepared transaction (public: a commitment and a proof), so a
            // Mac can ask Sepolia whether it would land (`eth_estimateGas`).
            let dump = FileManager.default.temporaryDirectory.appendingPathComponent("privacy-deposit.json")
            try? JSONEncoder().encode(deposit.tx).write(to: dump)
            log("deposit.dump", 0, dump.path)
        case "discover":
            try await ensureOpen(owner)
            let t = Date()
            let found = try await engine.discover()
            let balances = found.balances.map { "\($0.tokenId.prefix(8)) \($0.value)" }.joined(separator: ", ")
            log("discover", ms(t), "\(found.notes.count) notes · balance [\(balances)]")
        case "bench":
            let single = UserDefaults.standard.bool(forKey: "privacyEngineSingleThread")
            for circuit in ["deposit", "transact_1x1", "transact_1x2", "transact_2x2"] {
                let t = Date()
                let b = try await engine.bench(circuit: circuit, singleThread: single)
                log("bench.\(circuit)", ms(t), "load \(b.loadMs) ms · witness \(b.witnessMs) ms · prove \(b.proveMs) ms · verifies=\(b.verifies) · wasm \(b.wasmBytes / 1024) KB zkey \(b.zkeyBytes / 1024) KB\(single ? " · single thread" : "") · footprint \(footprintMB()) MB")
            }
        case "spend":
            try await ensureOpen(owner)
            for (name, act) in [("transfer", engine.prepareTransfer), ("withdraw", engine.prepareWithdraw)] {
                let t = Date()
                do {
                    let spend = try await act(eth, "0x1c6bf52634000", owner) // 0.0005 ETH
                    log("spend.\(name)", ms(t), "proofs \(spend.proofs.map { "\($0.circuit ?? "?") \($0.ms) ms" }.joined(separator: ", "))")
                } catch {
                    log("spend.\(name)", ms(t), "not prepared: \(describe(error))")
                }
            }
        case "forget":
            PrivacyPoolsKey.delete()
            log("forget", 0, "seed deleted")
        default:
            log(step, 0, "unknown step")
        }
    }

    @MainActor
    private static func ensureOpen(_ owner: String) async throws {
        guard PrivacyEngine.shared.network == nil else { return }
        try await run(step: "keys")
    }

    private static func describe(_ error: Error) -> String {
        if let failure = error as? PrivacyEngineWire.Failure { return "\(failure.name): \(failure.message)" }
        return String(describing: error)
    }

    private static func ms(_ since: Date) -> Int { Int(Date().timeIntervalSince(since) * 1000) }

    private static func log(_ step: String, _ ms: Int, _ detail: String) {
        NSLog("privacyEngine| %@ | %d | %@", step, ms, detail)
    }

    private static func vmInfo() -> task_vm_info_data_t? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? info : nil
    }

    private static func footprintMB() -> Int { Int((vmInfo()?.phys_footprint ?? 0) / 1_048_576) }
    private static func peakMB() -> Int { Int((vmInfo()?.ledger_phys_footprint_peak ?? 0) / 1_048_576) }
}
#endif
