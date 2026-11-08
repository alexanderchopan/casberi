#if DEBUG
import Darwin
import Foundation

/// `-railgunEngineProbe <step>` — drives the Railgun engine (prd §1713)
/// headless on Ethereum and NSLogs `railgunEngine| <step> | <ms> | <detail>`
/// with this app's memory footprint (the page's own memory is WebKit's
/// web-content process, measured from outside).
///
/// A RANDOM wallet every run, made in the page and kept nowhere: the sync, the
/// roots and the prepared calls are what is measured. Nothing is sent.
/// - `load`      start the web view, load the bundle, ask what it runs on
/// - `open`      open a random wallet through the account's node
/// - `sync`      build both trees from the checkpoint, check every root
///               (`-railgunEngineSyncCap <s>`, 600 by default)
/// - `shield`    prepare a 1 DAI shield into the wallet (approve + proxy call)
/// - `unshield`  prepare an unshield to the probe's address: an empty wallet
///               says so
/// - `all`       load, open, sync, shield, unshield
/// - `forget`    delete the kept trees (the engine's store)
///
/// The trees are kept on disk (prd §1713 item 9): run `all` twice and the
/// second sync reads only what landed since. `-railgunEngineMemory YES` keeps
/// them in memory instead. The random wallet is deleted on `done`.
enum RailgunEngineProbe {

    static let dai = "0x6B175474E89094C44Da98b954EedeAC495271d0F"
    static let probeRecipient = "0x00000000000000000000000000000000c0ffee01"

    @MainActor
    static func run(_ raw: String) {
        Task { @MainActor in
            let steps: [String] = raw == "all" || raw == "YES"
                ? ["load", "open", "sync", "shield", "unshield"]
                : raw.split(separator: ",").map(String.init)
            for step in steps {
                do { try await run(step: step) } catch {
                    log(step, 0, "FAILED \(describe(error))")
                    if step == "load" || step == "open" { break }
                }
            }
            await RailgunEngine.shared.close()
            log("done", 0, "footprint \(footprintMB()) MB peak \(peakMB()) MB")
        }
    }

    @MainActor
    private static func run(step: String) async throws {
        let engine = RailgunEngine.shared
        switch step {
        case "load":
            let t = Date()
            try await engine.start()
            let info = try await engine.info()
            log("load", ms(t), "sdk \(info.sdk) engine \(info.engine) snarkjs \(info.snarkjs) wasm=\(info.webAssembly) workers=\(info.workers) cores=\(info.cores) secureContext=\(info.secureContext)")
        case "open":
            let t = Date()
            let memory = UserDefaults.standard.bool(forKey: "railgunEngineMemory")
            // The probe's test wallet is made once and reopened by its id, as
            // a real one is: its id and encryption key are kept in DEBUG
            // defaults (it never holds anything). A new wallet each launch
            // would trial-decrypt every kept leaf (measured: 448 s).
            let defaults = UserDefaults.standard
            let keptID = memory ? nil : defaults.string(forKey: "railgunProbe.walletID")
            let key = (memory ? nil : defaults.string(forKey: "railgunProbe.encryptionKey"))
                ?? (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
            let opened = try await engine.open(encryptionKey: key, walletID: keptID, persist: !memory)
            if !memory {
                defaults.set(opened.walletID, forKey: "railgunProbe.walletID")
                defaults.set(key, forKey: "railgunProbe.encryptionKey")
            }
            log("open", ms(t), "storage \(opened.storage ?? "?") · wallet \(opened.loaded ? "reopened" : "new") · kept leaves \(opened.keptLeaves) · random=\(opened.generated) head \(opened.headBlock) fees \(opened.shieldFeeBps ?? "?")/\(opened.unshieldFeeBps ?? "?") bps · address \(opened.address.prefix(12))…")
        case "sync":
            try await ensureOpen()
            let cap = UserDefaults.standard.integer(forKey: "railgunEngineSyncCap")
            let t = Date()
            let s = try await engine.sync(capMs: (cap > 0 ? cap : 600) * 1000)
            let trees = s.trees.map { "\($0.tree):\($0.length)\($0.onChain ? "✓" : "✗")" }.joined(separator: " ")
            log("sync", ms(t), "done=\(s.done) utxo \(s.utxo?.status ?? "?") txid \(s.txid?.status ?? "?") · trees [\(trees)] · txid index \(s.txidIndex) node \(s.screeningIndex.map(String.init) ?? "?") root=\(s.txidRootValid) · trusted=\(RailgunEngineWire.trusted(s)) · \(s.balances.count) tokens · footprint \(footprintMB()) MB")
        case "shield":
            try await ensureOpen()
            let t = Date()
            let shield = try await engine.prepareShield(token: dai, amount: "0xde0b6b3a7640000") // 1 DAI
            log("shield", ms(t), "to \(shield.tx.to.prefix(10))… calldata \(shield.tx.data.count / 2 - 1) bytes · approve \(shield.approve.map { "\($0.to.prefix(10))… \($0.data.count / 2 - 1) bytes" } ?? "none") · fee \(shield.fee ?? "?")")
        case "unshield":
            try await ensureOpen()
            let t = Date()
            let held = try await engine.balances().first { BigUIntHex.isPositive($0.spendable) }
            guard let held else { log("unshield", ms(t), "nothing spendable in this wallet (a random one): not prepared"); return }
            let u = try await engine.prepareUnshield(token: held.token, amount: held.spendable, to: probeRecipient)
            log("unshield", ms(t), "type \(u.type) to \(u.tx.to.prefix(10))… gas \(u.gasEstimate) proof \(u.proofMs) ms · fee \(u.fee ?? "?")")
        case "forget":
            let t = Date()
            try await engine.forget()
            UserDefaults.standard.removeObject(forKey: "railgunProbe.walletID")
            UserDefaults.standard.removeObject(forKey: "railgunProbe.encryptionKey")
            log("forget", ms(t), "kept trees deleted")
        default:
            log(step, 0, "unknown step")
        }
    }

    @MainActor
    private static func ensureOpen() async throws {
        guard !RailgunEngine.shared.isOpen else { return }
        try await run(step: "open")
    }

    /// Whether a 0x-hex amount is more than zero.
    enum BigUIntHex {
        static func isPositive(_ hex: String) -> Bool {
            let digits = hex.hasPrefix("0x") ? hex.dropFirst(2) : Substring(hex)
            return digits.contains { $0 != "0" }
        }
    }

    private static func describe(_ error: Error) -> String {
        if let failure = error as? RailgunEngineWire.Failure { return "\(failure.name): \(failure.message)" }
        return String(describing: error)
    }

    private static func ms(_ since: Date) -> Int { Int(Date().timeIntervalSince(since) * 1000) }

    private static func log(_ step: String, _ ms: Int, _ detail: String) {
        NSLog("railgunEngine| %@ | %d | %@", step, ms, detail)
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

#if DEBUG
/// `-railgunPocket <step>` — YOUR Railgun wallet (prd §1713), the real one
/// made from your private root, on Ethereum, through your account. Logs
/// `railgunPocket|` lines. The sends are REAL MONEY and ask Face ID:
/// - `status`              open, sync with every root checked, the balances
/// - `shield:<amount>`     move <amount> DAI from your account in (approve + shield)
/// - `send:<amount>|all`   send DAI from your Railgun wallet back to your account
///   (`send:<amount>:<0x…>` to another address)
enum RailgunPocketProbe {
    static let dai = "0x6B175474E89094C44Da98b954EedeAC495271d0F"

    @MainActor
    static func run(_ raw: String) {
        Task { @MainActor in
            let parts = raw.split(separator: ":").map(String.init)
            let started = Date()
            do {
                switch parts.first {
                case "status":
                    try await status()
                case "shield":
                    guard parts.count >= 2, let units = PrivateMoney.baseUnits(parts[1], decimals: 18) else { log("shield: say how much, shield:11"); break }
                    log("shield: \(parts[1]) DAI, Face ID next")
                    let hash = try await RailgunPocket.shield(token: dai, amount: units) { s in log("stage \(s)") }
                    log("shield: landed \(hash ?? "(not yet seen)") · private in about an hour")
                case "send":
                    guard parts.count >= 2, let account = YourAccountKey.address else { log("send: say how much, send:all"); break }
                    let to = parts.count >= 3 ? parts[2] : account
                    let units: String
                    if parts[1] == "all" {
                        try await RailgunPocket.open(reason: nil)
                        let synced = try await RailgunPocket.sync()
                        units = synced.balances.first { $0.token.lowercased() == dai.lowercased() }.map { PrivateMoney.decimal(hex: $0.spendable) } ?? "0"
                    } else {
                        units = PrivateMoney.baseUnits(parts[1], decimals: 18) ?? "0"
                    }
                    log("send: \(PrivateMoney.number(units, decimals: 18) ?? units) DAI to \(YourAccount.short(to)), Face ID next")
                    let hash = try await RailgunPocket.send(token: dai, amount: units, to: to) { s in log("stage \(s)") }
                    log("send: landed \(hash ?? "(not yet seen)")")
                default:
                    log("unknown step \(raw)")
                }
            } catch {
                log("FAILED \(String(describing: error))")
            }
            log("done in \(Int(Date().timeIntervalSince(started))) s")
        }
    }

    @MainActor
    private static func status() async throws {
        let opened = try await RailgunPocket.open(reason: nil)
        log("open: wallet \(opened.loaded ? "reopened" : "made") · kept leaves \(opened.keptLeaves) · account \(YourAccountKey.address.map(YourAccount.short) ?? "none")")
        let s = try await RailgunPocket.sync()
        log("sync: \(s.syncMs / 1000) s · trusted · txid \(s.txidIndex)/\(s.screeningIndex.map(String.init) ?? "?")")
        if s.balances.isEmpty { log("balance: nothing yet") }
        for b in s.balances {
            log("balance: \(b.token == dai ? "DAI" : b.token) \(PrivateMoney.number(PrivateMoney.decimal(hex: b.amount), decimals: 18) ?? b.amount) · spendable \(PrivateMoney.number(PrivateMoney.decimal(hex: b.spendable), decimals: 18) ?? b.spendable)")
        }
    }

    private static func log(_ line: String) { NSLog("railgunPocket| %@", line) }
}
#endif
