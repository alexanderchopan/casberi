import SwiftUI

/// **YOUR KEYS, RIGHT AFTER CREATE (prd §1457, the K1–K4 canvas; user:
/// "with the first send").** Three steps in the sentence's grammar, each one
/// that can wait: a recovery key in iCloud Keychain, a Signer in a wallet
/// the person already has, and — with a Signer — a spend limit. Nothing here
/// touches a chain: the recovery key is made at once (free), and the rest is
/// kept in `YourAccountSetup` and rides the first send on each network.
/// The last step hands straight over to the Created sentence, which says
/// the keys go on with the first send (user: "No summary").
struct MoveKeysWalk: View {
    let account: String
    var inTray = false
    /// Inert (DEBUG's `-movePreview keys`): every step draws, nothing is kept.
    var inert = false
    let done: () -> Void

    enum Step: Int { case recovery = 1, signer, limit }
    typealias Period = MoveSecurity.LimitPeriod

    @State private var step: Step
    @State private var choice = YourAccountSetup.Choice()
    @State private var connecting = false
    @State private var note: String?
    @State private var amountText = ""
    @State private var period: Period = .month
    @FocusState private var amountFocused: Bool

    init(account: String, inTray: Bool = false, inert: Bool = false, step: Step = .recovery, done: @escaping () -> Void) {
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
                                                limitDollars: 100, limitMinutes: Period.month.minutes))
            _amountText = State(initialValue: "100")
        }
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text("\(step.rawValue) of 3")
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
                    .padding(.bottom, DS.Space.s6)
                content
                    .id(step)
                    .transition(.opacity)
                if let note {
                    Text(verbatim: note)
                        .dsText(.body17).foregroundStyle(DS.attentionInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DS.Space.s3)
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
        // Each step is one running sentence (§1466): clauses that never
        // split across a line, the pick pink.
        switch step {
        case .recovery:
            MoveFlow {
                MoveWord(String(localized: "A recovery key"))
                MoveClause(glue: String(localized: "in")) { MoveWord(String(localized: "iCloud Keychain."), ink: DS.pickInk) }
            }
            small(String(localized: "Lose this iPhone, sign in on the next one."))
        case .signer:
            MoveFlow {
                MoveWord(String(localized: "Your co-signer"))
                MoveClause(glue: String(localized: "in")) { MoveWord(String(localized: "a wallet you have."), ink: DS.pickInk) }
            }
            // Why (user, 2026-10-23: "this needs helper text of why do it").
            small(String(localized: "Use multiple signatures to approve sensitive actions."))
        case .limit:
            MoveFlow {
                MoveWord(String(localized: "Face ID alone"))
                MoveClause(glue: String(localized: "up to")) {
                    MoveRungReader { rung in
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text(verbatim: "$").dsText(rung).foregroundStyle(DS.pickInk)
                            TextField("100", text: $amountText)
                                .keyboardType(.numberPad)
                                .focused($amountFocused)
                                .dsText(rung)
                                .foregroundStyle(DS.pickInk)
                                .tint(DS.pickInk)
                                .fixedSize()
                                .accessibilityLabel(Text("Dollars"))
                        }
                    }
                }
                MoveWord(String(localized: "of each coin"))
                MoveClause(glue: String(localized: "a")) {
                    Menu {
                        ForEach(Period.allCases, id: \.self) { p in
                            Button { withAnimation(DS.Motion.standard) { period = p } } label: {
                                if p == period { Label(p.word, systemImage: "checkmark") } else { Text(verbatim: p.word) }
                            }
                        }
                    } label: {
                        MoveWord(period.word + ".", ink: DS.pickInk)
                            .contentTransition(.opacity)
                    }
                    .accessibilityLabel(Text("How often it starts again"))
                }
            }
            // With the limit on, recovery needs the Signer too (prd §1456).
            small(String(localized: "Over it, your co-signer signs too. So does recovery."))
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
            Button { advance() } label: {
                Text("Later").dsText(.heading17).foregroundStyle(DS.textSecondary).frame(minHeight: 48)
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
        case .limit: String(localized: "Set")
        }
    }

    private var verbEnabled: Bool {
        switch step {
        case .signer: !connecting
        case .limit: amountDollars != nil
        default: true
        }
    }

    /// Whole dollars, one or more.
    private var amountDollars: Int? {
        let text = amountText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "$", with: "")
        guard let n = Int(text), n >= 1, n <= 1_000_000 else { return nil }
        return n
    }

    private func act() {
        note = nil
        switch step {
        case .recovery:
            if !inert {
                do {
                    try YourAccountRecovery.make(for: account)
                } catch {
                    note = String(localized: "iCloud Keychain did not take the key. Add it later in Wallet › Security.")
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
                    let owner = try await SignerRequestSheet.choose(on: YourAccountOp.networks.filter { !$0.isTest }.map(\.chainId))
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
                    note = String(localized: "No wallet connected. Try again, or add one later.")
                }
            }
        case .limit:
            guard let n = amountDollars else { return }
            amountFocused = false
            choice.limitDollars = n
            choice.limitMinutes = period.minutes
            DSHaptic.success()
            advance()
        }
    }

    /// The next step, kept as it goes; the limit only stands with a Signer,
    /// and the last step hands over to the Created sentence.
    private func advance() {
        note = nil
        if !inert { YourAccountSetup.save(choice, for: account) }
        let next: Step?
        switch step {
        case .recovery: next = .signer
        case .signer: next = choice.signer == nil ? nil : .limit
        case .limit: next = nil
        }
        #if DEBUG
        NSLog("keysWalk: step %d recovery=%@ signer=%@ limit=%@", next?.rawValue ?? 0, choice.recovery ? "yes" : "no",
              choice.signer ?? "none", choice.limit.map { "\($0.dollars)/\($0.minutes)" } ?? "none")
        #endif
        guard let next else { done(); return }
        withAnimation(DS.Motion.standard) { step = next }
        if next == .limit {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                amountFocused = true
            }
        }
    }
}
