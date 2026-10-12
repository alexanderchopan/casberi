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

    var body: some View {
        let verdict = AztecSignRequest.check(request)
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
                            Text(verbatim: AztecSignRequest.line(call))
                                .dsText(.body17)
                                .foregroundStyle(DS.textPrimary)
                            Text(verbatim: "\(call.type == "public" ? String(localized: "Public") : String(localized: "Private")) · \(AztecSignRequest.short(call.to))")
                                .dsText(.subhead12)
                                .foregroundStyle(DS.textSecondary)
                        }
                    }
                    switch verdict {
                    case .refused(let why):
                        Text(why)
                            .dsText(.body17)
                            .foregroundStyle(DS.destructiveInk)
                            .padding(.top, DS.Space.s2)
                    case .sign:
                        DSFootnote(prose: String(localized: "Your computer names each call; the signature covers what each one does. Test money only."))
                            .padding(.top, DS.Space.s2)
                        if let failure {
                            Text(failure).dsText(.body17).foregroundStyle(DS.destructiveInk)
                        }
                        if let outcome {
                            Text(outcome).dsText(.body17).foregroundStyle(DS.confirmInk)
                        } else {
                            DSSlabButton(title: String(localized: "Sign"), busy: busy,
                                         enabled: !busy && AztecSignerKey.publicKey() != nil, action: sign)
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
        .onAppear {
            #if DEBUG
            // `-aztecAutoSign YES`: sign without a tap, for a headless run.
            if UserDefaults.standard.bool(forKey: "aztecAutoSign"), case .sign = verdict { sign() }
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
