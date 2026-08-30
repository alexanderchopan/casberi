import SwiftUI
import SwiftData

/// MAKING AN ACCOUNT, AS A SHEET (prd §523, 2026-08-29).
///
/// `SafeSignBlock`'s anatomy, one chain over: a phase model, a NAMED reason for
/// every state that is not ready, and no button until the thing that would go
/// wrong has been ruled out. The whole point of that shape is that every
/// non-ready state otherwise renders as the same absent control, leaving
/// somebody with a screen that does nothing and no way to find out why.
///
/// **The facts are stated before the ask, not after.** Which network, what the
/// key is, who pays. A person is authorizing a specific transaction, so the
/// screen says what it is while they still have the choice — and "the devnet's
/// faucet pays" is a fact on a receipt rather than a feature to opt into,
/// because it is not a decision anybody makes.
struct VibenetCreateSheet: View {
    /// Called with the new account's address once the chain has it, so the room
    /// can watch it without this sheet knowing what a watch list is.
    var onCreated: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ShellChrome.self) private var chrome

    @State private var phase: Phase = .checking
    @State private var payer: String?
    /// Why making a key failed, said where the tap was. Re-asserting `.noKey`
    /// instead — which this screen did at first — repeats the sentence the
    /// person just acted on and reads as a dead control.
    @State private var keyFailure: String?

    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")

    /// The tray follows its content. A fixed 480 over a two-line refusal is a
    /// void below the content — the §480 fault the key sheet already fixed
    /// once, and it looked exactly the same here the first time this screen
    /// was opened on a device.
    private var trayHeight: CGFloat {
        switch phase {
        case .checking:        240
        case .refused:         keyFailure == nil ? 340 : 400
        case .ready, .working: 520
        case .done:            390
        }
    }

    private enum Phase: Equatable {
        case checking
        case ready
        case refused(VibenetSigner.Refusal)
        case working
        case done(account: String)
    }

    var body: some View {
        // INK, like the sibling devnet's sheets (2026-08-29). `dsInk()` forces
        // pure black rather than the theme-adaptive sheet, so a tray that
        // precedes or IS a detail surface reads as one continuous sheet
        // instead of a shade off beside it. Hegotá's four trays went ink the
        // same day this screen was written; vibenet's older sheets have not
        // been converted yet, which is why the first cut of this one matched
        // the wrong siblings.
        DSTray(title: String(localized: "Create an account"), height: trayHeight, ink: true) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                // THE HOUSE SHEET HEAD, not a bare title (user, 2026-08-29:
                // "the UI is a bit barebones"). `DSSheetHead` is what makes a
                // sheet read as an OBJECT rather than as text on a page — the
                // subject's disc, a stamp for its state, the title, and one
                // sentence saying what it means now. This screen had none of
                // it and looked exactly like the "jumble of text" that
                // component was introduced to end.
                DSSheetHead(disc: { headDisc },
                            stamp: headStamp,
                            stampWeight: headStampWeight,
                            title: headTitle,
                            secondary: headSecondary,
                            sentence: headSentence)
                switch phase {
                case .checking:
                    ProgressView().frame(maxWidth: .infinity)
                case .refused(let refusal):
                    refusedBody(refusal)
                case .ready, .working:
                    readyBody
                case .done(let account):
                    doneBody(account)
                }
            }
        }
        .task { await check() }
    }

    // MARK: - The head

    /// The subject is the KEY, so the disc is the key's own mark rather than a
    /// generic plus — the same face the Permissions row draws, so the two
    /// screens are recognisably about one thing.
    private var headDisc: some View {
        ZStack {
            Circle()
                .fill(headIsFault ? DS.destructive.opacity(0.16) : Self.mark.opacity(0.18))
                .frame(width: DS.Face.list, height: DS.Face.list)
            Image(systemName: headIsFault ? "exclamationmark.triangle.fill" : "faceid")
                .dsGlyph(headIsFault ? 14 : 17, weight: .semibold)
                .foregroundStyle(headIsFault ? DS.destructive : Self.mark)
        }
        .accessibilityHidden(true)
    }

    private var headIsFault: Bool {
        if case .refused(let r) = phase { return r.isFault }
        return false
    }

    private var headTitle: String {
        switch phase {
        case .done:            String(localized: "The account is yours")
        case .working:         String(localized: "Making it\u{2026}")
        case .refused:         String(localized: "Not yet")
        default:               String(localized: "A new account")
        }
    }

    private var headSecondary: String? {
        if case .done(let account) = phase { return account }
        return String(localized: "Base vibenet \u{00B7} devnet")
    }

    /// What it MEANS now — the line that makes a head an answer rather than a
    /// label.
    private var headSentence: String? {
        switch phase {
        case .ready, .working:
            String(localized: "This phone's key becomes its only key, and it never leaves this phone.")
        case .done:
            String(localized: "It answers to this phone's key, and to nothing else.")
        case .refused(let r):
            // The reason belongs HERE — `sentence` is the head's "what it means
            // now" slot, and putting it in the body instead left the head
            // saying only "Not yet" while the actual answer sat underneath it
            // as loose text.
            VibenetSigner.sentence(r)
        case .checking: nil
        }
    }

    private var headStamp: String? {
        switch phase {
        case .done:    String(localized: "Created")
        case .refused: String(localized: "Blocked")
        default:       nil
        }
    }

    /// `urgent` means "waiting on YOU", which is exactly what a fault here is
    /// — the key is gone, or the chain would refuse it, and nothing proceeds
    /// until the person does something. `good` is reserved for the created
    /// state. Everything else is quiet, which is the default for a reason:
    /// a caller that has not thought about the stamp must not raise an alarm
    /// by omission.
    private var headStampWeight: DSStamp.Weight {
        switch phase {
        case .done: .good
        case .refused(let r): r.isFault ? .urgent : .quiet
        default: .quiet
        }
    }

    /// One block caption — `VibenetKeySheet`'s own helper, so the two sheets
    /// caption their blocks the same way.
    private func caption(_ text: String) -> some View {
        Text(text)
            .dsText(.label12)
            .foregroundStyle(DS.textTertiary)
    }

    // MARK: - Ready

    private var readyBody: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            // The headline moved INTO the head — it was said twice, once as a
            // title and once as the first line of the body.
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                caption(String(localized: "What this does"))
                fact(String(localized: "Network"), String(localized: "Base vibenet \u{00B7} devnet"))
                fact(String(localized: "First key"), String(localized: "This phone"))
                // WHO PAYS is said plainly and only when it is known. A missing
                // payer is not silence — it means the person's own account
                // needs funds, which is a different sentence and a worse
                // surprise if it arrives after the fact.
                fact(String(localized: "Gas"),
                     payer == nil
                     ? String(localized: "Nobody is sponsoring \u{2014} the account needs funds first")
                     : String(localized: "Paid by the devnet's faucet"))
                if payer != nil {
                    fact(String(localized: "From you"), String(localized: "Nothing"))
                }
            }

            Button {
                DSHaptic.tap()
                Task { await create() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "faceid").dsGlyph(14, weight: .semibold)
                    Text(String(localized: "Create with Face ID"))
                    if phase == .working { ProgressView().controlSize(.mini) }
                }
                .dsText(.callout15).fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.s3)
                .background(Self.mark, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            }
            .buttonStyle(PressSpring())
            .disabled(phase == .working)
            .dsHover()

            Text(String(localized: "Test money on an experimental network."))
                .dsText(.label11)
                .foregroundStyle(DS.textTertiary)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Refused

    @ViewBuilder
    private func refusedBody(_ refusal: VibenetSigner.Refusal) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            // The reason is in the head's own sentence — see `headSentence`.
            // The one refusal this screen can DO something about. Everything
            // else is stated and left alone rather than given a control that
            // cannot help — the §83 rule that a button which does nothing is
            // worse than no button.
            if refusal == .noKey {
                // A FULL-WIDTH CONTROL, not a text link (user, 2026-08-29:
                // "the 'make a key' link is super tiny"). It is the primary
                // action of this state — the only thing the screen is asking
                // for — so it gets the weight the ready state's own button
                // gets. A `label12` link for the one thing to do here read as
                // a footnote.
                Button {
                    DSHaptic.tap()
                    Task { await makeKey() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "key.fill").dsGlyph(13, weight: .semibold)
                        Text(String(localized: "Make a key on this phone"))
                    }
                    .dsText(.callout15).fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Space.s3)
                    .background(Self.mark, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                }
                .buttonStyle(PressSpring())
                .dsHover()
                if let keyFailure {
                    Text(keyFailure)
                        .dsText(.label11)
                        .foregroundStyle(DS.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Done

    private func doneBody(_ account: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            // The address is already in the head's `secondary`; what this block
            // adds is the one thing left to decide.
            Button {
                DSHaptic.tap()
                onCreated(account)
                dismiss()
            } label: {
                Text(String(localized: "Watch it"))
                    .dsText(.callout15).fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Space.s3)
                    .background(Self.mark, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            }
            .buttonStyle(PressSpring())
            .dsHover()
            Text(String(localized: "Watching puts it in this room with your other accounts."))
                .dsText(.label11)
                .foregroundStyle(DS.textTertiary)
                .frame(maxWidth: .infinity)
        }
    }

    private func fact(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
            Text(key)
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .dsText(.label12)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Acts

    /// The ladder, asked with what this device really has. Deliberately does
    /// NOT reach the chain for an account's actor list: there is no account
    /// yet, so the only rungs that can apply are the local ones.
    private func check() async {
        guard let contracts = await VibenetConfig.current() else {
            phase = .refused(.contractsUnreadable); return
        }
        let facts = VibenetSigner.Facts(
            enclaveAvailable: VibenetDeviceKey.enclaveAvailable,
            publicKeyHex: VibenetDeviceKey.publicKeyHex(),
            keyDestroyed: VibenetDeviceKey.presence() == .destroyed,
            contractsReadable: true)
        switch VibenetSigner.decide(facts, now: .now) {
        case .success:
            phase = .ready
        case .failure(let refusal):
            // Everything past the local rungs needs an account that does not
            // exist yet, so those refusals are not real here — a key that is
            // present and undamaged is all this act requires.
            if refusal == .actorDataUnreadable || refusal == .notAnAuthenticator
                || refusal == .simulationUnread {
                phase = .ready
            } else {
                phase = .refused(refusal)
            }
        }
        if case .ready = phase, let address = draftAddress(contracts) {
            payer = await VibenetSend.sponsoredPayer(for: address, gasLimit: 300_000)
                .map { "0x" + VibenetTransaction.hex($0) }
        }
    }

    /// A throwaway address purely to ask the payer whether it would sponsor.
    /// The real one is derived inside `createAccount` with its own salt — this
    /// is only a question about the network's willingness, never the account.
    private func draftAddress(_ c: VibenetContracts) -> Data? {
        guard let key = VibenetDeviceKey.publicKeyXY(),
              let keystore = VibenetTransaction.data(fromHex: c.keystore),
              let defaultAccount = c.defaultAccount.flatMap(VibenetTransaction.data(fromHex:)),
              let auth = VibenetTransaction.data(fromHex: c.p256Authenticator) else { return nil }
        return VibenetCreate.plan(keystore: keystore, defaultAccount: defaultAccount,
                                  authenticator: auth, publicKeyXY: key,
                                  userSalt: Data(repeating: 0, count: 32),
                                  gasLimit: 300_000, maxFeePerGas: 0x3b9a_ca00,
                                  maxPriorityFeePerGas: 0xf4240)?.address
    }

    private func makeKey() async {
        keyFailure = nil
        do {
            _ = try VibenetDeviceKey.create()
            DSHaptic.success()
            await check()
        } catch {
            // The REASON, in the sheet. A first cut set `.refused(.noKey)`
            // here and put the reason in a toast: the screen then repeated the
            // sentence the person had just acted on, the toast scrolled away,
            // and the button read as dead. Found by tapping it on a simulator,
            // where there is no enrolled biometric and `create` throws
            // `.noBiometry` — a state no static check can see.
            keyFailure = Self.keySentence(for: error)
        }
    }

    private static func keySentence(for error: Error) -> String {
        guard let f = error as? VibenetDeviceKey.Failure else {
            return String(localized: "Couldn't make a key.")
        }
        switch f {
        case .noEnclave:
            return String(localized: "This device has no Secure Enclave, so it can't hold a key.")
        case .noBiometry:
            return String(localized: "Set up Face ID first \u{2014} the key is locked to it and would be unusable without it.")
        case .alreadyExists:
            return String(localized: "There's already a key on this phone.")
        case .enclaveRefused:
            return String(localized: "The Secure Enclave refused to make a key.")
        case .keychainRefused(let status):
            return String(localized: "The keychain refused (code \(String(Int(status)))).")
        case .badDigest, .noKey, .signingRefused:
            return String(localized: "Couldn't make a key.")
        }
    }

    private func create() async {
        guard let c = await VibenetConfig.current(),
              let keystore = VibenetTransaction.data(fromHex: c.keystore),
              let defaultAccount = c.defaultAccount.flatMap(VibenetTransaction.data(fromHex:)),
              let auth = VibenetTransaction.data(fromHex: c.p256Authenticator) else {
            phase = .refused(.contractsUnreadable); return
        }
        phase = .working
        do {
            let sent = try await VibenetSend.createAccount(keystore: keystore,
                                                           defaultAccount: defaultAccount,
                                                           authenticator: auth)
            DSHaptic.success()
            // What you did lands in the corpus (prd §523) — a real gap this
            // sheet shipped with: `landReceipt` existed and had no caller.
            VibenetSend.landReceipt(sent, in: modelContext)
            phase = .done(account: "0x" + VibenetTransaction.hex(sent.account))
        } catch {
            phase = .ready
            chrome.flash(Self.sentence(for: error))
        }
    }

    /// Every failure gets its own sentence. They all render as the same
    /// nothing-happened, and only some of them are something a person can act
    /// on — which is the same reason the ladder above names its refusals.
    private static func sentence(for error: Error) -> String {
        guard let f = error as? VibenetSend.Failure else {
            return String(localized: "Couldn't create the account.")
        }
        switch f {
        case .noKey:            return String(localized: "This phone has no key yet.")
        case .cannotCompose:    return String(localized: "Couldn't put the transaction together.")
        case .noSponsor:        return String(localized: "Nobody is sponsoring right now.")
        case .signingRefused:   return String(localized: "Face ID didn't confirm, so nothing was signed.")
        case .payerRefused(let why):     return String(localized: "The sponsor refused: \(why)")
        case .broadcastRefused(let why): return String(localized: "The network refused it: \(why)")
        }
    }
}
