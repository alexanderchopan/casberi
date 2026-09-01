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

    @State private var phase: Phase = .checking
    /// What the faucet said, in its own three answers (prd §530). It was a
    /// `String?` address, so "the payer service didn't answer" and "the payer
    /// has nothing for you" were one state — and this screen stated the second
    /// as a fact for both, on the one line whose whole subject is who pays.
    @State private var offer: VibenetSend.PayerOffer?
    /// Why making a key failed, said where the tap was. Re-asserting `.noKey`
    /// instead — which this screen did at first — repeats the sentence the
    /// person just acted on and reads as a dead control.
    @State private var keyFailure: String?
    /// Why creating the account failed, said where the tap was — `create()`'s
    /// own sibling to `keyFailure`, and for the identical reason: on failure
    /// `phase` resets to `.ready`, the SAME screen the person was just on, and
    /// this sheet is a modal `.sheet` presentation — `chrome.flash()`'s toast
    /// renders inside `RootShell`'s own ZStack, which sits BEHIND any open
    /// sheet, so it was never visible while this tray was up. The failure
    /// read as nothing happening at all, and a re-tap failed the same
    /// invisible way — reported as "it's like a loop." `makeKey()` beside
    /// this already learned the exact lesson (see its own comment); this
    /// path just never got the fix applied to it too.
    @State private var createFailure: String?

    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")

    /// The tray follows its content. A fixed 480 over a two-line refusal is a
    /// void below the content — the §480 fault the key sheet already fixed
    /// once, and it looked exactly the same here the first time this screen
    /// was opened on a device.
    /// **RE-MEASURED against what each phase now DRAWS (prd §538,
    /// 2026-08-31).** The ready state was 520 for a head, a four-row table and
    /// a button; it is a head, a two-row table and a footnote now — the two
    /// duplicated rows and the button both left this stack — so 520 would be
    /// a void under the content, the §480 fault in the other direction.
    ///
    /// The action is no longer part of this arithmetic in any phase: it is
    /// pinned outside the scroll, so these numbers describe the SCROLLING
    /// content alone and a wrong one costs a scroll rather than a clipped
    /// control.
    private var trayHeight: CGFloat {
        switch phase {
        case .checking:        240
        case .refused:         keyFailure == nil ? 320 : 380
        case .ready, .working: 430
        case .done:            360
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
        // SCROLLABLE, AND WIDENED — the `VibenetKeySheet`/`HegotaSendSheet`
        // fix for the same class of bug (§480, then the Hegotá send tray the
        // day before this one): a fixed height with no `ScrollView` clips
        // dead the moment real device text metrics run past the guessed
        // number, with no way to reach whatever fell below the tray's own
        // bottom edge — reported here exactly as it was on Hegotá's sheet,
        // "the tray is clipped at top and won't reach to the bottom." A
        // `ScrollView` makes every reachable state reachable regardless of
        // how `trayHeight` is guessed, and `detents: [.height(trayHeight),
        // .large]` gives a drag past the resting size for free.
        //
        // INK, like the sibling devnet's sheets (2026-08-29). `dsInk()` forces
        // pure black rather than the theme-adaptive sheet, so a tray that
        // precedes or IS a detail surface reads as one continuous sheet
        // instead of a shade off beside it. Hegotá's four trays went ink the
        // same day this screen was written; vibenet's older sheets have not
        // been converted yet, which is why the first cut of this one matched
        // the wrong siblings.
        // **THE ACTION IS PINNED, THE CONTENT SCROLLS UNDER IT (prd §538,
        // 2026-08-31; user: "create account content doesn't fit on the sheet
        // when you open it. this is a miss").**
        //
        // `trayHeight` is a GUESS — a hand-summed arithmetic over content whose
        // real height depends on the type size, the language and how long the
        // sponsor's sentence turned out to be — and every guess here has been
        // wrong at least once. When it is short the `ScrollView` above made
        // every state REACHABLE and left the primary button cut in half by the
        // screen edge, which is worse than a scroll: a control sliced through
        // the middle reads as a broken screen, and the one thing a person came
        // here to do is the thing they cannot see.
        //
        // So the scroll owns only what can legitimately be long (the head, the
        // facts, a refusal's reason) and the action sits OUTSIDE it, against
        // the tray's own bottom edge. No height, guessed or measured, can clip
        // it. `VStack(spacing: 0)` because the footer carries its own padding,
        // and the scroll takes `maxHeight: .infinity` so it — not the button —
        // absorbs whatever slack the detent leaves.
        DSTray(title: String(localized: "Create an account"), height: trayHeight, ink: true,
               detents: [.height(trayHeight), .large]) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.s4) {
                        // THE HOUSE SHEET HEAD, not a bare title (user,
                        // 2026-08-29: "the UI is a bit barebones"). `DSSheetHead`
                        // is what makes a sheet read as an OBJECT rather than as
                        // text on a page — the subject's disc, a stamp for its
                        // state, the title, and one sentence saying what it
                        // means now. This screen had none of it and looked
                        // exactly like the "jumble of text" that component was
                        // introduced to end.
                        DSSheetHead(disc: { headDisc },
                                    stamp: headStamp,
                                    stampWeight: headStampWeight,
                                    title: headTitle,
                                    secondary: headSecondary,
                                    sentence: headSentence,
                                    inkCard: true)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, DS.Space.s4)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: .infinity)
                pinnedAction
            }
        }
        .task { await check() }
    }

    /// THE ONE THING THIS SCREEN IS ASKING FOR, in each state that has one.
    ///
    /// Every phase's primary control lives here rather than at the bottom of
    /// its own body — that is what makes the pinning above true rather than
    /// true-for-the-ready-state. `.checking` has no action (it is waiting on
    /// us, not on the person) and a refusal that is not `.noKey` has none by
    /// §83's rule: a control that cannot help is worse than no control.
    @ViewBuilder
    private var pinnedAction: some View {
        switch phase {
        case .checking:
            EmptyView()
        case .ready, .working:
            actionButton(title: String(localized: "Create with Face ID"),
                         symbol: "faceid",
                         busy: phase == .working,
                         disabled: phase == .working) {
                createFailure = nil
                Task { await create() }
            }
        case .refused(let refusal):
            // A FULL-WIDTH CONTROL, not a text link (user, 2026-08-29: "the
            // 'make a key' link is super tiny"). It is the primary action of
            // this state — the only thing the screen is asking for — so it
            // gets the weight the ready state's own button gets.
            if refusal == .noKey {
                actionButton(title: String(localized: "Make a key on this phone"),
                             symbol: "key.fill",
                             busy: false,
                             disabled: false) {
                    Task { await makeKey() }
                }
            }
        case .done(let account):
            actionButton(title: String(localized: "Watch it"),
                         symbol: nil,
                         busy: false,
                         disabled: false) {
                onCreated(account)
                dismiss()
            }
        }
    }

    /// One button shape for all four states, so the pinned slot cannot drift
    /// into four spellings of the same control.
    private func actionButton(title: String, symbol: String?, busy: Bool,
                              disabled: Bool, act: @escaping () -> Void) -> some View {
        Button {
            DSHaptic.tap()
            act()
        } label: {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).dsGlyph(14, weight: .semibold) }
                Text(title)
                if busy { ProgressView().controlSize(.mini) }
            }
            .dsText(.callout15).fontWeight(.semibold)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Space.s3)
            .background(Self.mark, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        }
        .buttonStyle(PressSpring())
        .disabled(disabled)
        .dsHover()
        .padding(.top, DS.Space.s3)
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

    /// **THE TABLE SAYS ONLY WHAT THE HEAD HAS NOT (prd §538, 2026-08-31.)**
    ///
    /// It carried four rows and the head above it had already answered two of
    /// them: `secondary` is "Base vibenet · devnet" and the Network row read
    /// "Base vibenet · devnet", `sentence` is "This phone's key becomes its
    /// only key" and the First key row read "This phone". So a sheet whose
    /// content did not fit was spending a third of its height restating the
    /// three lines directly above it, in a smaller type, as a table.
    ///
    /// What is LEFT is what the head cannot say: who pays, and what it costs
    /// you. Those two are the only reason to read a table here at all — and
    /// with the two duplicates gone the ready state fits with room to spare
    /// rather than relying on the scroll to be discovered.
    private var readyBody: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                caption(String(localized: "What this does"))
                // WHO PAYS is said plainly and only when it is known — and
                // "we couldn't ask" is now its own sentence rather than being
                // reported as a refusal (prd §530). A missing payer is not
                // silence: it means this creation cannot go through at all,
                // which is a fact worth having before the tap rather than
                // after a Face ID.
                fact(String(localized: "Gas"), gasSentence)
                if isSponsored {
                    fact(String(localized: "From you"), String(localized: "Nothing"))
                }
            }

            // SAID HERE, not just in a toast — see `createFailure`'s own doc.
            // A retry that fails the same invisible way is what reads as a
            // loop; this is what breaks it.
            if let createFailure {
                Text(createFailure)
                    .dsText(.label11)
                    .foregroundStyle(DS.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(String(localized: "Test money on an experimental network."))
                    .dsText(.label11)
                    .foregroundStyle(DS.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Refused

    @ViewBuilder
    private func refusedBody(_ refusal: VibenetSigner.Refusal) -> some View {
        // The reason is in the head's own sentence — see `headSentence` — and
        // the one act this state offers is in `pinnedAction`. What is left here
        // is why that act just failed, which belongs beside the reason rather
        // than under a button that is no longer in this block.
        if refusal == .noKey, let keyFailure {
            Text(keyFailure)
                .dsText(.label11)
                .foregroundStyle(DS.destructive)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Done

    private func doneBody(_ account: String) -> some View {
        // The address is already in the head's `secondary` and the act is in
        // `pinnedAction`; what is left is what that act will mean.
        Text(String(localized: "Watching puts it in this room with your other accounts."))
            .dsText(.label11)
            .foregroundStyle(DS.textTertiary)
            .frame(maxWidth: .infinity)
    }

    /// Is a faucet really on offer — the only state in which this creation
    /// costs the person nothing.
    private var isSponsored: Bool {
        guard let offer else { return false }
        if case .sponsored = offer { return true }
        return false
    }

    /// The three answers, said apart, plus the check still running. Unwrapped
    /// FIRST rather than matched through the Optional: `PayerOffer` is spelled
    /// so no case can collide with `Optional.none`, and this keeps the match
    /// on the enum itself where it plainly means what it reads as.
    private var gasSentence: String {
        guard let offer else { return String(localized: "Checking\u{2026}") }
        switch offer {
        case .sponsored:
            return String(localized: "Paid by the devnet's faucet")
        case .declined:
            return String(localized: "Nobody is sponsoring \u{2014} a new account has nothing to pay with")
        case .unreadable:
            return String(localized: "Couldn't reach the sponsor to ask")
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
            offer = await VibenetSend.payerOffer(for: address, gasLimit: 300_000)
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
            // NOT `chrome.flash` — that toast renders inside `RootShell`'s own
            // ZStack, which sits BEHIND this modal sheet, so it was never
            // visible while the tray was open. See `createFailure`'s doc.
            createFailure = Self.sentence(for: error)
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
        case .noSponsor:
            // The one refusal that is not a fault. A brand-new account holds
            // nothing by construction, so without a sponsor there is nothing
            // to pay with — said plainly, and said INSTEAD of a Face ID.
            return String(localized: "Nobody is sponsoring right now, and a new account has nothing to pay with. Try again later.")
        case .sponsorUnreadable:
            return String(localized: "Couldn't reach the sponsor to ask who pays, so nothing was signed.")
        case .chainUnreachable:
            return String(localized: "Couldn't reach the network, so nothing was sent.")
        case .signingRefused:   return String(localized: "Face ID didn't confirm, so nothing was signed.")
        case .payerRefused(let why):     return String(localized: "The sponsor refused: \(why)")
        case .broadcastRefused(let why): return String(localized: "The network refused it: \(why)")
        }
    }
}
