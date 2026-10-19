import SwiftUI
import UIKit

/// A testnet harness for "Your account" (docs/safe-wallet-spec.md): a Safe on
/// Base Sepolia whose key lives in this iPhone's Secure Enclave, a new key
/// with every send if you ask, gas paid from the account's own balance
/// through a public bundler. Nothing of ours on chain, no server. Never shipped.
@main
struct SafeSpikeApp: App {
    var body: some Scene {
        WindowGroup { SpikeView().preferredColorScheme(.dark) }
    }
}

@MainActor
final class Spike: ObservableObject {
    @Published var address = ""
    @Published var balance = "…"
    @Published var lines: [String] = []
    @Published var busy = false
    @Published var keyInfo = ""
    let net = Chain.baseSepolia

    func log(_ s: String) {
        lines.insert(s, at: 0)
        print("[safe-spike] \(s)")
    }

    func setUp() async {
        do {
            if EnclaveKeys.count == 0 { try EnclaveKeys.make(); EnclaveKeys.currentIndex = 0; log("made key 0 in the Secure Enclave") }
            address = try await SafeAccount.address(net, try EnclaveKeys.key(0))
            log("account \(address)")
            await refresh()
            // `-autocheck YES`: run the no-funds check at launch, for a console-only run.
            if UserDefaults.standard.bool(forKey: "autocheck") { check() }
        } catch { log("✗ \(error)") }
    }

    func refresh() async {
        guard !address.isEmpty else { return }
        do {
            let wei = try await Chain.balance(net, address)
            balance = String(format: "%.6f ETH", Double(wei) / 1e18)
            let onChain = try await Chain.codeExists(net, address)
            let current = try EnclaveKeys.key(EnclaveKeys.currentIndex)
            var line = "key \(EnclaveKeys.currentIndex) of \(EnclaveKeys.count) · " + (onChain ? "account on chain" : "not on chain yet")
            if onChain {
                let stored = try await SafeAccount.configuredKeyX(net, account: address)
                let matches = stored.lowercased() == SafeABI.hex(current.x).dropFirst(2).lowercased()
                line += matches ? " · answers to this key ✓" : " · answers to ANOTHER key"
            }
            keyInfo = line
        } catch { log("✗ \(error)") }
    }

    func run(_ label: String, _ body: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        log("— \(label) —")
        Task {
            let start = Date()
            do { try await body(); log(String(format: "✓ %@ · %.1f s", label, Date().timeIntervalSince(start))) }
            catch { log("✗ \(error)") }
            await refresh()
            busy = false
        }
    }

    /// No funds needed: estimate with a balance override, sign, and let the
    /// chain verify the signature.
    func check() {
        run("Check (no funds)") { [self] in
            let call = SafeAccount.sendCall(to: address, value: 1, rotateTo: nil)
            let prepared = try await SafeAccount.prepare(net, origin: try EnclaveKeys.key(0), callData: call, log: log)
            _ = try await SafeAccount.sign(net, prepared, with: try EnclaveKeys.key(EnclaveKeys.currentIndex), log: log)
        }
    }

    /// Send 1 wei to the account itself — the first one creates the account.
    /// With `rotate`, the next key is made first and the same transaction
    /// moves the account to it; the index advances only once it is mined.
    func send(rotate: Bool) {
        run(rotate ? "Send + new key" : "Send") { [self] in
            let signerIndex = EnclaveKeys.currentIndex
            var nextIndex: Int?
            if rotate { nextIndex = try EnclaveKeys.make(); log("made key \(nextIndex!) for after this send") }
            let call = SafeAccount.sendCall(to: address, value: 1, rotateTo: try nextIndex.map(EnclaveKeys.key))
            let prepared = try await SafeAccount.prepare(net, origin: try EnclaveKeys.key(0), callData: call, log: log)
            let signed = try await SafeAccount.sign(net, prepared, with: try EnclaveKeys.key(signerIndex), log: log)
            _ = try await SafeAccount.send(net, signed, log: log)
            if let nextIndex { EnclaveKeys.currentIndex = nextIndex; log("the account now answers to key \(nextIndex); key \(signerIndex) is retired") }
        }
    }

    /// Sign with the key before the current one. The bundler must refuse it
    /// (AA24): the proof that a used key never works again.
    func tryOldKey() {
        run("Try the previous key") { [self] in
            let old = EnclaveKeys.currentIndex - 1
            guard old >= 0 else { log("no previous key yet: send with a new key first"); return }
            let call = SafeAccount.sendCall(to: address, value: 1, rotateTo: nil)
            let prepared = try await SafeAccount.prepare(net, origin: try EnclaveKeys.key(0), callData: call, log: log)
            let signed = try await SafeAccount.sign(net, prepared, with: try EnclaveKeys.key(old), log: log)
            do {
                _ = try await SafeAccount.send(net, signed, log: log)
                log("✗ the previous key still worked — rotation did NOT take")
            } catch {
                log("refused, as it should be: \(error)")
            }
        }
    }
}

struct SpikeView: View {
    @StateObject private var spike = Spike()
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your test account").font(.title2.bold())
                    Text("Base Sepolia · Secured by Safe").foregroundStyle(.secondary)
                    Text(spike.address.isEmpty ? "…" : spike.address).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                    Text(spike.balance).font(.headline)
                    Text(spike.keyInfo).font(.footnote).foregroundStyle(.secondary)
                }
                Button("Copy the address") { UIPasteboard.general.string = spike.address }
                Button("Refresh") { Task { await spike.refresh() } }
            }
            Section {
                Button("Check (no funds needed)") { spike.check() }
                Button("Send 1 wei to yourself") { spike.send(rotate: false) }
                Button("Send with a new key") { spike.send(rotate: true) }
                Button("Try the previous key") { spike.tryOldKey() }
            }
            .disabled(spike.busy || spike.address.isEmpty)
            Section("Log") {
                ForEach(Array(spike.lines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.system(.caption, design: .monospaced))
                }
            }
        }
        .task { await spike.setUp() }
    }
}
