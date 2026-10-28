import SwiftUI

/// **YOUR ACCOUNT, RIGHT AFTER CREATE (prd §1457, rebuilt by §1501).**
/// Four steps in the sentence's grammar, each one that can wait — a recovery
/// key in iCloud Keychain, a co-signer in another wallet, with a co-signer a
/// spend limit, and round-ups — then the account itself, Created, with Done.
/// Nothing here touches a chain: the recovery key is made at once (free), the
/// co-signer and the limit are kept in `YourAccountSetup` and ride the first
/// move on each network, and round-ups are this phone's setting.
///
/// The walk was reviewed word by word (user, 2026-10-24: "i want to talk
/// about every word"); §1501 records each line and why.
struct MoveKeysWalk: View {
    let account: String
    var inTray = false
    /// Inert (DEBUG's `-movePreview keys`): every step draws, nothing is kept.
    var inert = false
    /// How the walk ends: Done closes Move, Receive opens it on Receive.
    enum Ending { case close, receive }
    let done: (Ending) -> Void

    enum Step: Int { case recovery = 1, signer, limit, roundUps, created }
    typealias Period = MoveSecurity.LimitPeriod

    @State private var step: Step
    @State private var choice = YourAccountSetup.Choice()
    @State private var connecting = false
    @State private var note: String?
    /// What a copy says, in place: a toast draws under the tray (§1442c).
    @State private var said: String?
    @State private var roundUps = RoundUps.Setting(on: true)

    init(account: String, inTray: Bool = false, inert: Bool = false, step: Step = .recovery,
         done: @escaping (Ending) -> Void) {
        self.account = account
        self.inTray = inTray
        self.inert = inert
        self.done = done
        _step = State(initialValue: step)
        // Picked up where it was left (DEBUG's `-keysWalk YES` reopens it).
        if !inert, let kept = YourAccountSetup.choice(for: account) { _choice = State(initialValue: kept) }
        #if DEBUG
        if inert {
            // The preview draws every key chosen.
            _choice = State(initialValue: .init(recovery: true, signer: "0x2F60D2BB84Eb8df6951F7215ef035eF052BA2725",
                                                requiresCoSigner: true))
        }
        #endif
    }

    /// The networks this phone's account is on, as the Create screen names them.
    private var networks: [YourAccountOp.Network] { YourAccountOp.networks.filter { !$0.isTest } }

    /// "1 of 4": the limit is a step only with a co-signer, so once the
    /// co-signer is skipped the walk is three steps long.
    private var stepCount: Int { step.rawValue <= Step.signer.rawValue || choice.signer != nil ? 4 : 3 }
    private var stepNumber: Int { step == .roundUps && choice.signer == nil ? 3 : step.rawValue }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                // Created is the account, not a step: no counter.
                if step != .created {
                    Text("\(stepNumber) of \(stepCount)")
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                        .padding(.bottom, DS.Space.s6)
                }
                content
                    .id(step)
                    .transition(.opacity)
                if let note {
                    Text(verbatim: note)
                        .dsText(.body17).foregroundStyle(DS.attentionInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DS.Space.s3)
                } else if let said {
                    Text(verbatim: said)
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DS.Space.s3)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
            .padding(.top, inTray ? DS.Space.s8 : DS.Space.s6 + DS.Space.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) { foot }
        .onAppear {
            #if DEBUG
            NSLog("keysWalk: step %d", step.rawValue)
            #endif
        }
    }

    // MARK: - The steps

    @ViewBuilder private var content: some View {
        // Each step is one running sentence at Move's one size (§1501), the
        // pick pink, and one line of small print at most.
        switch step {
        case .recovery:
            MoveFlow {
                MoveWord(String(localized: "A recovery key"))
                MoveClause(glue: String(localized: "in")) { MoveWord(String(localized: "iCloud Keychain."), ink: DS.pickInk) }
            }
            // "Device", not "iPhone": the key opens it on an iPad or a Mac on
            // the same Apple Account too. No "sign in": there is no Casberi
            // login to sign into (§1501).
            small(String(localized: "If you lose this device, your account opens on another."))
        case .signer:
            MoveFlow {
                MoveWord(String(localized: "A co-signer"))
                MoveClause(glue: String(localized: "in")) { MoveWord(String(localized: "another wallet."), ink: DS.pickInk) }
            }
            // Its own job, never the recovery key's; and when it lands —
            // connecting signs nothing (prd §1499).
            small(String(localized: "Once required, it approves every send and swap. Activates on your first move."))
        case .limit:
            // One switch, never an amount (prd §1570): required or not.
            MoveFlow {
                MoveWord(String(localized: "Require your co-signer"))
                MoveClause(glue: String(localized: "for")) { MoveWord(String(localized: "every send and swap."), ink: DS.pickInk) }
            }
            small(String(localized: "You can turn it off later in Account. Getting your account back needs it too."))
        case .roundUps:
            // One switch (prd §1572): spare change, saved privately.
            MoveFlow {
                MoveWord(String(localized: "Save your spare change"))
                MoveClause(glue: String(localized: "in your")) { MoveWord(String(localized: "private balance."), ink: DS.pickInk) }
            }
            small(String(localized: "Your spare change is saved privately in dollars, and earns interest."))
        case .created:
            MoveFlow {
                MoveWord(String(localized: "Created"), ink: DS.textSecondary)
                // Pink is a tap (§1385); the tap copies, naming the networks
                // the address works on (prd §1501).
                Button { copyAddress() } label: { MoveWord(YourAccount.short(account), ink: DS.pickInk) }
                    .buttonStyle(RowPress())
                    .accessibilityLabel(Text("Your address, \(account)"))
                    .accessibilityHint(Text("Copies your address"))
                MovePhrase(networks.map(\.name).formatted(.list(type: .and)) + ".", glue: String(localized: "on"))
            }
            small(createdLine)
        }
    }

    /// Where the address works, and where to go for the rest: a deposit
    /// address in Receive (§1453, §1470).
    private var createdLine: String {
        let short = YourAccount.short(account)
        return networks.count == 3
            ? String(localized: "Use \(short) on these three. On any other network, get a deposit address in Receive and pick the token and network to receive on.")
            : String(localized: "Use \(short) on these networks. On any other network, get a deposit address in Receive and pick the token and network to receive on.")
    }

    private func copyAddress() {
        // The demo's address holds no key: never copied (§1475).
        let words = YourAccountDemo.isDemo(account) ? YourAccountDemo.actsLater
            : String(localized: "Copied · only on \(networks.map(\.name).formatted(.list(type: .or)))")
        if !YourAccountDemo.isDemo(account) {
            UIPasteboard.general.string = account
            DSHaptic.tap()
        }
        withAnimation(DS.Motion.standard) { said = words }
        Task {
            try? await Task.sleep(for: .seconds(3))
            if said == words { withAnimation(DS.Motion.standard) { said = nil } }
        }
    }

    private func small(_ words: String) -> some View {
        Text(verbatim: words)
            .dsText(.body17).foregroundStyle(DS.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, DS.Space.s4)
    }

    // MARK: - The foot

    private var foot: some View {
        HStack(alignment: .firstTextBaseline) {
            Button { step == .created ? done(.receive) : advance() } label: {
                Text(step == .created ? String(localized: "Receive") : String(localized: "Later"))
                    .dsText(.heading17).foregroundStyle(DS.textSecondary).frame(minHeight: 48)
            }
            .buttonStyle(RowPress())
            .disabled(connecting)
            Spacer(minLength: DS.Space.s3)
            Button { act() } label: {
                Text(verbatim: verb)
                    .dsText(.heading34)
                    .foregroundStyle(verbEnabled ? DS.pickInk : DS.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(minHeight: 48, alignment: .trailing)
            }
            .buttonStyle(RowPress())
            .disabled(!verbEnabled)
        }
        .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
        .padding(.bottom, DS.Space.s2)
        .background { if inTray { DS.surfaceSheet } else { DSPageBackground() } }
    }

    private var verb: String {
        switch step {
        case .recovery: String(localized: "Add")
        case .signer: connecting ? String(localized: "Connecting…") : String(localized: "Connect")
        case .limit: String(localized: "Require")
        case .roundUps: String(localized: "Turn on")
        case .created: String(localized: "Done")
        }
    }

    private var verbEnabled: Bool {
        switch step {
        case .signer: !connecting
        case .limit: true
        default: true
        }
    }

    private func act() {
        note = nil
        switch step {
        case .recovery:
            if !inert {
                do {
                    try YourAccountRecovery.make(for: account)
                } catch {
                    note = String(localized: "iCloud Keychain did not take the key. Add it later in Wallet › Your account.")
                    return
                }
            }
            choice.recovery = true
            DSHaptic.success()
            advance()
        case .signer:
            guard !inert else { advance(); return }
            connecting = true
            Task {
                defer { connecting = false }
                do {
                    let owner = try await SignerRequestSheet.choose(on: networks.map(\.chainId), account: account)
                    // A contract (a smart wallet) cannot sign for the account.
                    if try await YourAccountChain.isContract(YourAccountOp.base, owner) {
                        note = String(localized: "That wallet is a contract, not one whose key you hold")
                        return
                    }
                    guard owner.caseInsensitiveCompare(account) != .orderedSame else {
                        note = String(localized: "That is your account's own address")
                        return
                    }
                    choice.signer = owner
                    DSHaptic.success()
                    advance()
                } catch {
                    note = SignerRequestSheet.proofWords(error)
                        ?? String(localized: "No wallet connected. Try again, or add one later.")
                }
            }
        case .limit:
            choice.requiresCoSigner = true
            DSHaptic.success()
            advance()
        case .roundUps:
            if !inert { RoundUps.setting = roundUps.simple }
            DSHaptic.success()
            advance()
        case .created:
            done(.close)
        }
    }

    /// The next step, kept as it goes; the limit only stands with a
    /// co-signer, and Created ends the walk.
    private func advance() {
        note = nil
        if !inert { YourAccountSetup.save(choice, for: account) }
        let next: Step
        switch step {
        case .recovery: next = .signer
        case .signer: next = choice.signer == nil ? .roundUps : .limit
        case .limit: next = .roundUps
        case .roundUps, .created: next = .created
        }
        #if DEBUG
        NSLog("keysWalk: step %d recovery=%@ signer=%@ limit=%@ roundUps=%@", next.rawValue, choice.recovery ? "yes" : "no",
              choice.signer ?? "none", choice.required ? "required" : "none",
              RoundUps.setting.on ? "\(RoundUps.setting.step)/\(RoundUps.setting.target.symbol)" : "off")
        #endif
        withAnimation(DS.Motion.standard) { step = next }
    }
}
