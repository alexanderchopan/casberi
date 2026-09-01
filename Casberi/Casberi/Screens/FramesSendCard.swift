import SwiftUI

/// THE FRAMES DEVNET'S HOME SCOPE — two tiles, not a form (prd §548, mirroring
/// §553).
///
/// The panel, the sheet and the keypad are all `DevnetSendConsole`'s, shared
/// with Hegotá and vibenet. What is this room's own is the one thing neither
/// neighbour can say: **a send here is not one act.** It becomes a VERIFY
/// frame that authorises execution and payment, then a SENDER frame that moves
/// the value — and without the first the transaction has no payer and is
/// invalid. `plan` hands those to the sheet as `DevnetSendStep`s.
///
/// **Both halves, unlike vibenet.** That room draws Send alone because its
/// faucet is a payer that sponsors gas rather than something an address can
/// claim from, so a Top up tile there would be the dead control §83 bans. This
/// chain has a real `POST /api/claim`, so the ink half can act.
struct FramesSendCard: View {
    @Environment(ShellChrome.self) private var chrome

    let onSend: () -> Void

    @State private var keyAddress: String? = FramesKey.address()
    @State private var creating = false
    @State private var createError: String?
    @State private var topUpBusy = false
    @State private var topUpNote: String?

    /// `DS.tint` rather than an invented hue — the seat's own icon is the
    /// brand and the console is chrome around it.
    private static let mark = DS.tint

    var body: some View {
        if keyAddress == nil {
            create
        } else {
            DevnetSendPanel(
                tint: Self.mark,
                // The faucet leaves nothing to open — it funds the address in
                // place — so `handsOff` is false and the tile acts here.
                topUp: .init(busy: topUpBusy, note: topUpNote, handsOff: false, action: topUp),
                onSend: onSend)
        }
    }

    // MARK: - Before there is a key

    /// **ONE TAP MAKES IT, and there is no screen in between** — §553's ruling
    /// for Hegotá, and the reasoning carries unchanged: a confirmation screen
    /// would ask the question the button just asked. Nothing rises here at all
    /// on this chain, since the key is a plain scalar rather than an Enclave
    /// one, so the tap IS the act.
    ///
    /// The copy makes no claim about the room that follows: making a key does
    /// not make the chain answer, and an account with no test ETH can send
    /// nothing yet.
    @ViewBuilder private var create: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            DevnetCreatePanel(tint: Self.mark,
                              title: String(localized: "Make an account"),
                              busy: creating,
                              onCreate: makeKey)
            if let createError {
                Text(createError)
                    .dsText(.label12)
                    .foregroundStyle(DS.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func makeKey() {
        guard !creating else { return }
        creating = true
        defer { creating = false }
        do {
            keyAddress = try FramesKey.create()
            createError = nil
            // The arrival is worth a moment — it is the only thing this seat
            // makes rather than reads.
            chrome.refreshPulse &+= 1
        } catch {
            // The keychain's own answer, never a bare "it failed" (§531): a
            // code with no remedy is a dead end.
            createError = String(localized: "Couldn't make a key: \(String(describing: error))")
        }
    }

    // MARK: - Top up

    private func topUp() {
        guard !topUpBusy, let address = keyAddress else { return }
        topUpBusy = true
        topUpNote = nil
        Task { @MainActor in
            defer { topUpBusy = false }
            do {
                _ = try await FramesSend.claimFaucet(for: address)
                topUpNote = nil
                await FramesLiveState.shared.refresh()
                chrome.refreshPulse &+= 1
            } catch let failure as FramesSend.Failure {
                if case .faucet(let verdict) = failure {
                    topUpNote = Self.faucetNote(verdict)
                } else {
                    topUpNote = String(localized: "The faucet didn't answer.")
                }
            } catch {
                topUpNote = String(localized: "The faucet didn't answer.")
            }
        }
    }

    /// **The rate limit and a real failure read the SAME way, on purpose**
    /// (§525, and `DevnetSendPanel.TopUp.note`'s own rule): the hourly refusal
    /// is expected rather than a fault, and either way the next step is
    /// identical — tap it again later.
    private static func faucetNote(_ verdict: HegotaFaucetVerdict) -> String {
        verdict.sentence ?? String(localized: "The faucet didn't answer.")
    }
}

// MARK: - What a Frames send becomes

/// The steps the sheet draws between the figure and the keypad.
///
/// **Built from `FramesSend.plan(…)`, which is the object that gets signed** —
/// not a description of it. A preview drawn from a parallel description is how
/// a screen ends up promising two frames and sending three; here they are the
/// same `Fields`, so they cannot disagree.
///
/// Empty until there is a real recipient and a real amount, so the strip
/// appears when there is something true to say rather than sitting there as a
/// diagram of nothing.
enum FramesSendPlanSteps {
    @MainActor
    static func steps(destination: String, amount: String) -> [DevnetSendStep] {
        guard let sender = FramesKey.address().flatMap({ RLP.data(fromHex: $0) }),
              DevnetSendParse.isValidAddress(destination),
              let target = RLP.data(fromHex: destination),
              let wei = DevnetSendParse.weiData(from: amount)
        else { return [] }

        let fields = FramesSend.plan(sender: sender, to: target, valueWei: wei,
                                     nonce: FramesLiveState.shared.accounts.first?.nonce ?? 0)
        return fields.frames.map { frame in
            DevnetSendStep(name: name(for: frame), detail: detail(for: frame))
        }
    }

    /// The chain's own words — `FramesSection.label`'s ruling: the chip is
    /// where the vocabulary gets learned, and this chain is named for frames.
    private static func name(for frame: FramesTransaction.Frame) -> String {
        switch frame.mode {
        case 1: String(localized: "Verify")
        case 2: String(localized: "Sender")
        case 0: String(localized: "Default")
        default: String(localized: "Mode \(String(frame.mode))")
        }
    }

    /// **THE PERMISSION, said out loud.** A VERIFY frame's flags ARE the
    /// authorisation on this chain — there is no standing grant anywhere, so
    /// this is the only place it can be read (`FramesSection`'s Permissions
    /// ruling). Without an APPROVE the transaction has no payer and is
    /// invalid, so "approves both" is load-bearing rather than a detail.
    private static func detail(for frame: FramesTransaction.Frame) -> String {
        if frame.mode == 1 {
            let execution = frame.flags & 0x1 != 0
            let payment = frame.flags & 0x2 != 0
            if execution && payment { return String(localized: "approves both") }
            if payment { return String(localized: "approves payment") }
            if execution { return String(localized: "approves running") }
            return String(localized: "approves nothing")
        }
        return frame.value.isEmpty ? String(localized: "no value")
                                   : String(localized: "moves the value")
    }
}
