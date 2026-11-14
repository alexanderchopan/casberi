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

    /// `intro` opens the walk and is no step (prd §1741a): it says what the
    /// wallet holds, has nothing to choose, and wears no counter.
    enum Step: Int { case intro = 0, recovery, signer, limit, roundUps, created }
    typealias Period = MoveSecurity.LimitPeriod

    @State private var step: Step
    @State private var choice = YourAccountSetup.Choice()
    @State private var connecting = false
    @State private var note: String?
    /// What a copy says, in place: a toast draws under the tray (§1442c).
    @State private var said: String?
    @State private var roundUps = RoundUps.Setting(on: true)

    init(account: String, inTray: Bool = false, inert: Bool = false, step: Step = .intro,
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

    /// "1 of 3", and it never changes midway (user, 2026-11-13: it read
    /// "of 4" then "of 3"): the limit is the co-signer's second half, so
    /// it keeps the co-signer's number.
    private var stepCount: Int { 3 }
    private var stepNumber: Int {
        switch step {
        case .intro, .recovery: 1
        case .signer, .limit: 2
        case .roundUps, .created: 3
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                // The opening page and the end are not steps: no counter.
                if step != .created, step != .intro {
                    Text("\(stepNumber) of \(stepCount)")
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                        // The Round-ups step holds a headline, two rows and
                        // a line: less air, so the line stays in view.
                        .padding(.bottom, step == .roundUps ? DS.Space.s2 : DS.Space.s6)
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
        case .intro:
            // **WHAT YOU HAVE, BEFORE WHAT TO SET (prd §1741a, user: "it
            // likely isn't clear they have private balance that is railgun
            // and privacy pools or what aztec is for").** The walk never said
            // the wallet has a private side. Three places, each under its
            // app's own mark, in the names §1700g settled.
            MoveFlow {
                MoveWord(String(localized: "Your wallet,"))
                MoveWord(String(localized: "privately."), ink: DS.pickInk)
            }
            // **ONE LINE EACH, AND THE WHOLE PAGE IN VIEW (prd §1803, user:
            // "look better; the Aztec line says Aztec to Aztec").** The
            // paragraphs ran past the tray's foot. Each place says the one
            // fact its address carries everywhere else, and wears the marks
            // of the networks it is good on.
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                place(["Safe"], String(localized: "Public account"),
                      networks.map(\.name).joined(separator: ", "),
                      marks: networks.compactMap { MoveSentence.networkMark($0) })
                place(["Privacy Pools", "Railgun"], String(localized: "Private balance"),
                      String(localized: "A new address each time"),
                      marks: [MoveSentence.networkMark(chainId: 1)].compactMap { $0 })
                place(["Aztec"], String(localized: "Private account"),
                      String(localized: "Aztec to Aztec only"), ink: DS.aztecInk)
            }
            .padding(.top, DS.Space.s6)
        case .recovery:
            MoveFlow {
                MoveWord(String(localized: "A recovery key"))
                MoveClause(glue: String(localized: "in")) { MoveWord(String(localized: "iCloud Keychain."), ink: DS.pickInk) }
            }
            // "Device", not "iPhone": the key opens it on an iPad or a Mac on
            // the same Apple Account too. No "sign in": there is no Casberi
            // login to sign into (§1501).
            small(String(localized: "If you lose this device, you can open your account on another device."))
        case .signer:
            MoveFlow {
                MoveWord(String(localized: "A co-signer"))
                MoveClause(glue: String(localized: "in")) { MoveWord(String(localized: "another wallet."), ink: DS.pickInk) }
            }
            // **RECOMMENDED, AND WHY (prd §1741a, user: "it really makes
            // aztec easier to use. how can we somehow say its good to turn
            // on"; "i like recommended. and say use another wallet to approve
            // every send and swap. i think the aztec line comes after").**
            // The word leads in the primary ink; when it lands moved to the
            // next step, where it is required (§1499).
            Text(Self.signerWords)
                .dsText(.body17).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s4)
        case .limit:
            // One switch, never an amount (prd §1570): required or not.
            MoveFlow {
                MoveWord(String(localized: "Require your co-signer"))
                MoveClause(glue: String(localized: "for")) { MoveWord(String(localized: "every send and swap."), ink: DS.pickInk) }
            }
            small(String(localized: "Activates on your first move. You can turn it off later in Account. Getting your account back needs it too."))
        case .roundUps:
            // **THE PAYOFF, NOT THE MECHANISM (prd §1741, user: "save change,
            // earn interest, privately works. i mean it moves to private
            // balance").** A tester met "Round up your sends into Round-ups."
            // and asked whether privacy was the point. The line under it says
            // when the change turns private and that it earns at both stages;
            // the step is $1 or $5, and the example follows the pick.
            MoveFlow {
                MoveWord(String(localized: "Save your change,"))
                MoveWord(String(localized: "earn interest,"))
                MoveWord(String(localized: "privately."), ink: DS.pickInk)
            }
            // One control under the headline, then one paragraph in one size
            // that follows the pick (prd §1741a, user, of the pick beside the
            // foot's acts: "ugly and weird"; of four pieces in three sizes:
            // "this looks messy").
            // The sums as Move's large rows, each saying what it saves, and
            // one line (prd §1803, user: "no pill buttons; far less text").
            MoveSecurity.RoundUpStepPick(setting: $roundUps)
                .padding(.top, DS.Space.s2)
            small(MoveSecurity.roundUpsAt)
        case .created:
            // **WHAT "READY" MEANT (prd §1803, user: "what Ready means; a
            // clearer line about which networks the address works on").**
            // The headline says what you can do now; the whole address
            // stands under its name, then each network by mark and name.
            MoveFlow {
                MoveWord(String(localized: "Your account can"))
                MoveWord(String(localized: "receive now."), ink: DS.pickInk)
            }
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text("Public address").dsText(.body17).foregroundStyle(DS.textSecondary)
                Button { copyAddress() } label: { AddressGroupsGrid(address: account) }
                    .buttonStyle(RowPress())
                    .accessibilityLabel(Text("Your address, \(account)"))
                    .accessibilityHint(Text("Copies your address"))
                HStack(spacing: DS.Space.s3) {
                    ForEach(networks, id: \.chainId) { net in
                        HStack(spacing: DS.Space.s1) {
                            if let mark = MoveSentence.networkMark(net) { MoveRowMark(network: mark, size: 22) }
                            Text(verbatim: net.name).dsText(.body17).foregroundStyle(DS.textPrimary)
                        }
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, DS.Space.s1)
            }
            .padding(.top, DS.Space.s4)
            small(String(localized: "On another network, Receive gives you a deposit address."))
        }
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

    /// "Recommended." in the primary ink, the rest in the small print's.
    private static var signerWords: AttributedString {
        var lead = AttributedString(String(localized: "Recommended."))
        lead.foregroundColor = DS.textPrimary
        return lead + AttributedString(" " + String(localized: "Use another wallet to approve every send and swap. It also serves as the external wallet Aztec requires."))
    }

    /// One place on the opening page: its app's mark (two for the private
    /// balances), its name at the section rung, one line under it.
    private func place(_ apps: [String], _ name: String, _ words: String, ink: Color = DS.textSecondary,
                       marks: [String] = []) -> some View {
        HStack(spacing: DS.Space.s4) {
            ZStack {
                if apps.count == 1 {
                    BridgeIcon(name: apps[0], size: DS.Mark.tile)
                } else {
                    BridgeIcon(name: apps[0], size: DS.Mark.row)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    BridgeIcon(name: apps[1], size: DS.Mark.row)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .frame(width: DS.Mark.tile, height: DS.Mark.tile)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: name).dsText(.heading20).foregroundStyle(DS.headInk)
                Text(verbatim: words).dsText(.subhead12).foregroundStyle(ink).lineLimit(1)
            }
            Spacer(minLength: DS.Space.s2)
            // The words name the networks; the marks are for the eye.
            HStack(spacing: DS.Space.s1) {
                ForEach(marks, id: \.self) { MoveRowMark(network: $0, size: 22) }
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private func small(_ words: String) -> some View {
        Text(verbatim: words)
            .dsText(.body17).foregroundStyle(DS.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, DS.Space.s4)
    }

    // MARK: - The foot

    private var foot: some View {
        // **THE WALK'S ACTS ARE MOVE'S CARDS (prd §1803):** the step's act
        // in the pick's card, what puts it off in the grey one beside it,
        // as Move's foot draws Back and its verb (§1781, §1801).
        HStack(spacing: DS.Space.s3) {
            // The opening page has nothing to put off: Next alone.
            if step != .intro {
                Button { step == .created ? done(.receive) : advance() } label: {
                    Text(step == .created ? String(localized: "Receive") : String(localized: "Later"))
                        .dsText(.heading20).foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                        .padding(.horizontal, DS.Space.s6)
                        .frame(minHeight: MoveSentence.actHeight)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous).fill(DS.fillStrong))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressSpring())
                .disabled(connecting)
            }
            Button { act() } label: { MoveSentence.actCard(verb, on: verbEnabled) }
                .buttonStyle(PressSpring())
                .disabled(!verbEnabled)
        }
        .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
        .modifier(MoveFootClearance(inTray: inTray))
        .background { if inTray { DS.surfaceSheet } else { DSPageBackground() } }
    }

    private var verb: String {
        switch step {
        case .intro: String(localized: "Next")
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
        case .intro:
            advance()
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
        case .intro: next = .recovery
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
