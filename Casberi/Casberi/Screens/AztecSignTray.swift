import SwiftUI

/// Sign for an Aztec testnet account (2026-10-11): the request a computer
/// handed over, read before anyone is asked. What it will run, rebuilt from
/// its own calls (`AztecSignRequest.check`); a request that is not for an
/// Aztec testnet, or whose hash its calls do not make, offers no button.
/// Signing copies the signature for the computer's tool to read back.
struct AztecSignTray: View {
    let request: AztecSignRequest.Request
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var outcome: String?
    @State private var failure: String?
    /// What Aztec's testnet node reports (prd §1419), read once on open; nil
    /// until it answers. A request on an unknown rollup waits for it rather
    /// than being refused for a reset the phone has not heard of.
    @State private var live: AztecSignRequest.LiveTestnet?
    @State private var askedLive = false

    var body: some View {
        let verdict = AztecSignRequest.check(request, live: live)
        // A Sepolia request the fixed list refuses may be on a rollup the
        // testnet moved to since; it waits for the node before it is refused.
        let waiting = !askedLive && AztecSignRequest.int(request.chainId) == AztecSignRequest.l1ChainID
        DSTray(title: String(localized: "Sign for Aztec"), height: 640, detents: [.height(640), .large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    if case .sign(let network) = verdict {
                        Text(verbatim: "\(network) · \(AztecSignRequest.short(request.account))")
                            .dsText(.body17)
                            .foregroundStyle(DS.textSecondary)
                    }
                    Text("It will run")
                        .dsText(.heading17)
                        .foregroundStyle(DS.textPrimary)
                        .padding(.top, DS.Space.s2)
                    ForEach(Array(request.calls.enumerated()), id: \.offset) { _, call in
                        VStack(alignment: .leading, spacing: DS.Space.s1) {
                            Text(verbatim: AztecSignRequest.line(call, account: request.account))
                                .dsText(.body17)
                                .foregroundStyle(DS.textPrimary)
                            Text(verbatim: "\(call.type == "public" ? String(localized: "Public") : String(localized: "Private")) · \(AztecSignRequest.target(call, account: request.account))")
                                .dsText(.subhead12)
                                .foregroundStyle(DS.textSecondary)
                        }
                    }
                    switch verdict {
                    case .refused where waiting:
                        HStack(spacing: DS.Space.s2) {
                            DSSpinner()
                            Text("Checking Aztec's testnet")
                                .dsText(.body17)
                                .foregroundStyle(DS.textSecondary)
                        }
                        .padding(.top, DS.Space.s2)
                    case .refused(let why):
                        Text(why)
                            .dsText(.body17)
                            .foregroundStyle(DS.destructiveInk)
                            .padding(.top, DS.Space.s2)
                    case .sign:
                        DSFootnote(prose: request.calls.allSatisfy(AztecSignRequest.nameChecked)
                                   ? String(localized: "Each call's name is checked against what it runs. Test money only.")
                                   : String(localized: "Your computer names each call; the signature covers what each one does. Test money only."))
                            .padding(.top, DS.Space.s2)
                        if let failure {
                            Text(failure).dsText(.body17).foregroundStyle(DS.destructiveInk)
                        }
                        if let outcome {
                            Text(outcome).dsText(.body17).foregroundStyle(DS.confirmInk)
                        } else {
                            // The Safe ask sheet's verb (prd §1419): the faceid
                            // disc says how it confirms — the Secure Enclave key
                            // asks for Face ID on every signature.
                            DSActVerb(title: busy ? String(localized: "Signing…") : String(localized: "Sign"),
                                      glyph: "faceid", busy: busy,
                                      disabled: AztecSignerKey.publicKey() == nil, act: sign)
                                .padding(.top, DS.Space.s2)
                            if AztecSignerKey.publicKey() == nil {
                                Text("Make a signing key on the Aztec page first.")
                                    .dsText(.subhead12)
                                    .foregroundStyle(DS.textSecondary)
                            }
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .task {
            if let chain = AztecWire.chain(await AztecIngest.call("node_getNodeInfo", on: .testnet)) {
                live = AztecSignRequest.LiveTestnet(rollupVersion: chain.version, l1ChainID: chain.l1ChainID)
            }
            askedLive = true
            #if DEBUG
            // `-aztecAutoSign YES`: sign without a tap, for a headless run.
            if UserDefaults.standard.bool(forKey: "aztecAutoSign"),
               case .sign = AztecSignRequest.check(request, live: live) { sign() }
            #endif
        }
    }

    private func sign() {
        busy = true
        failure = nil
        let hash = request.messageHash
        let reason = String(localized: "Sign this Aztec testnet transaction")
        Task { @MainActor in
            defer { busy = false }
            do {
                // Off the main actor: Face ID holds the call for as long as
                // its sheet is up, and the tray must keep drawing meanwhile.
                let sig = try await Task.detached {
                    try AztecSignerKey.sign(messageHash: hash, reason: reason)
                }.value
                let line = AztecSignRequest.signatureLine(r: sig.r, s: sig.s)
                // The signer's own record, and the account followed so its
                // public Fee Juice stands in Holdings (prd §1419).
                if case .sign(let network) = AztecSignRequest.check(request, live: live) {
                    AztecSignedLog.record(AztecSignedLog.entry(for: request, network: network))
                }
                AztecStore.shared.add(request.account)
                UIPasteboard.general.string = line
                NSLog("[Casberi] aztecSign: signed %@", request.messageHash)
                DSHaptic.tap()
                outcome = String(localized: "Signed. The signature is copied — paste it on your computer.")
            } catch {
                failure = String(localized: "Couldn't sign: \(String(describing: error))")
            }
        }
    }
}
