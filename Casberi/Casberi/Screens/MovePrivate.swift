import SwiftData
import SwiftUI

/// **SEND, PRIVATELY (prd §1554; user: "why is Private a verb? it should be a
/// switch on send").** Private is never a verb. Send carries it two ways:
///
/// - **Into your private balance**: "Your private balance" is a recipient,
///   the first in Send's list. The sentence reads
///
///       Send 0.001 ETH
///       to your private balance
///       on Sepolia.
///
///   and the act runs the deposit (Face ID, the keystore the first time, the
///   proof, the send), then waits for 0xBow's approval. No switch here:
///   private to private is not a move.
/// - **From your private balance**: the Private switch under any other
///   recipient's sentence (`MovePrivateSwitch`), off by default and never
///   remembered on. On, the sentence names the source,
///
///       Send 0.001 ETH
///       from your private balance
///       to ...a3f1 on Sepolia.
///
///   the amounts are what the APPROVED private balance holds, the foot says
///   the relayer's fee and about how long, and the act proves a withdrawal on
///   the phone and hands it to 0xBow's relayer, which posts it.
///
/// Both in Move's anatomy: the verbs on their own line (`head`, Move's own,
/// Send bright), the sentence at its one size (`MoveFlow`), a pink word's
/// choices in the glass box under it, one grey line, and the act at the
/// foot's trailing edge, saying each stage as Move's does. Sepolia only,
/// DEBUG builds only: the sender is the DEBUG testnet sender
/// (`PrivacyTestnetSender`) until your account sends. Addresses by their
/// tail (`YourAccount.short`).
struct MovePrivateSentence<Head: View>: View {
    /// Held by whoever draws the sentence, so Move's verbs can wait on it.
    let move: PrivateMove
    var inTray = false
    /// Leaves the private sentence: the switch turned off, or the recipient
    /// word tapped to pick someone else.
    var leave: (MovePrivateLeave) -> Void = { _ in }
    @ViewBuilder let head: () -> Head

    @State private var open: Blank?
    @State private var copied = false
    @State private var typed = ""
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context
    @Environment(ShellChrome.self) private var chrome

    enum Blank { case amount, recipient }

    private var store: PrivateMoneyStore { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                head()
                    .padding(.bottom, DS.Space.s4)
                MoveFlow { sentence }
                    .animation(DS.Motion.standard, value: move.stage)
                    .animation(DS.Motion.standard, value: move.amount)
                    .animation(DS.Motion.standard, value: move.recipient)
                if move.mode == .send, !isDone {
                    MovePrivateSwitch(isOn: Binding(get: { true }, set: { on in if !on { leave(.switchOff) } }))
                        .padding(.top, DS.Space.s4)
                        .disabled(move.acting)
                }
                Group {
                    if let open, move.stage == .ready || open == .recipient {
                        choices(open)
                            .transition(.asymmetric(insertion: .offset(y: 24).combined(with: .opacity), removal: .opacity))
                    } else {
                        line.transition(.opacity)
                    }
                }
                .padding(.top, open != nil ? DS.Space.s4 : DS.Space.s6)
            }
            .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
            .padding(.top, inTray ? DS.Space.s2 : DS.Space.s6)
            .padding(.bottom, DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) { if open == nil { foot.transition(.opacity) } }
        .task(id: move.mode) {
            move.context = context
            await move.read()
            #if DEBUG
            if let amount = UserDefaults.standard.string(forKey: "movePrivateAmount"), move.choices.contains(amount) {
                move.amount = amount
            }
            if move.mode == .send, move.recipient == nil,
               let to = UserDefaults.standard.string(forKey: "movePrivateTo"), PrivateMoney.isAddress(to) {
                move.recipient = to
                await move.checkRecipient()
            }
            NSLog("[Casberi] movePrivate: %@ %@", move.mode == .send ? "send" : "deposit", String(describing: move.stage))
            if UserDefaults.standard.bool(forKey: "movePrivateGo"), move.stage == .ready, ready {
                await move.run()
            }
            #endif
        }
        // Switch on, whether the recipient holds a private account of their
        // own: then it goes balance to balance (prd §1567).
        .task(id: move.recipient) {
            guard move.mode == .send else { return }
            await move.checkRecipient()
        }
        // Done, the move lands in Activity as its own row (prd §1554).
        .onChange(of: doneHash) { _, hash in
            guard let hash else { return }
            land(hash)
        }
        // Done, the ASP is asked again while a deposit's sentence stands, so
        // the approval lands here as well as in Holdings.
        .task(id: doneHash) {
            guard doneHash != nil, move.mode == .deposit else { return }
            for _ in 0..<30 where note?.status == .waiting {
                try? await Task.sleep(for: .seconds(20))
                await store.refresh(force: true)
            }
        }
    }

    private var doneHash: String? {
        if case .done(let hash) = move.stage { return hash }
        return nil
    }

    private var isDone: Bool { doneHash != nil }

    /// The note a deposit made, once it has.
    private var note: PrivateMoney.Note? {
        guard let doneHash else { return nil }
        // By its commitment on Ethereum (kept even when no transaction was
        // named, finding 2); else by its transaction.
        if let kept = move.deposited { return store.notes.first { $0.commitment == kept } }
        return doneHash.isEmpty ? nil : store.notes.first { $0.tx == doneHash }
    }

    private var figure: String {
        PrivateMoney.figure(PrivateMoney.baseUnits(move.amount, decimals: move.decimals) ?? "0", decimals: move.decimals, symbol: move.symbol)
    }

    /// Ready to act: an amount, and switch on, an address.
    private var ready: Bool {
        move.stage == .ready && (move.mode == .deposit || move.recipient.map(PrivateMoney.isAddress) == true)
    }

    // MARK: - The sentence

    @ViewBuilder private var sentence: some View {
        switch move.stage {
        case .reading:
            MovePhrase(move.onEthereum ? String(localized: "Reading Ethereum…") : String(localized: "Reading Sepolia…"), ink: DS.textSecondary)
        case .needsFunds(let address):
            MoveClause(glue: String(localized: "Fund")) {
                Button { copy(address) } label: { MoveWord(YourAccount.short(address), ink: DS.pickInk) }
                    .buttonStyle(RowPress())
                    .accessibilityLabel(move.onEthereum ? Text("Your account, \(address)") : Text("This build's test account, \(address)"))
                    .accessibilityHint(Text("Copies the address"))
            }
            MovePhrase(move.network.name, glue: String(localized: "on"))
            MovePhrase(String(localized: "first."))
        case .nothingPrivate:
            MovePhrase(move.onEthereum ? String(localized: "Nothing private to send on Ethereum yet.")
                       : String(localized: "Nothing private to send on Sepolia yet."), ink: DS.textSecondary)
        default:
            // Ready, working, done or refused: the sentence stands as written
            // (past tense once done), and the foot or the line says the rest.
            MoveClause(glue: isDone ? String(localized: "Sent") : String(localized: "Send")) {
                Button {
                    guard move.stage == .ready else { return }
                    toggle(.amount)
                } label: {
                    MoveWord(figure, ink: move.stage == .ready ? (open == .amount ? DS.pickInk.opacity(0.6) : DS.pickInk) : DS.textPrimary)
                }
                .buttonStyle(RowPress())
                .accessibilityLabel(Text("Amount, \(figure)"))
                .accessibilityHint(Text("Picks how much"))
            }
            if move.mode == .send {
                MovePhrase(String(localized: "your private balance"), glue: String(localized: "from"),
                           ink: move.stage == .ready ? DS.pickInk : DS.textPrimary)
            }
            MoveClause(glue: String(localized: "to")) { recipientWord }
            MovePhrase(move.onEthereum ? String(localized: "Ethereum.") : String(localized: "Sepolia."), glue: String(localized: "on"))
        }
    }

    /// Who it goes to: your private balance (a tap picks someone else), or
    /// switch on, an address by its tail, or the blank "address".
    @ViewBuilder private var recipientWord: some View {
        let live = move.stage == .ready
        if move.mode == .deposit {
            Button {
                guard live else { return }
                leave(.pickRecipient)
            } label: {
                MoveWord(String(localized: "your private balance"), ink: live ? DS.pickInk : DS.textPrimary)
            }
            .buttonStyle(RowPress())
            .accessibilityHint(Text("Picks who it goes to"))
        } else {
            // A failed read leaves the address open: the relayer's fee does
            // not wait on it, and taking one reads again (`take`).
            let pickable = live || failed
            Button {
                guard pickable else { return }
                toggle(.recipient)
            } label: {
                if let to = move.recipient {
                    MoveWord(YourAccount.short(to), ink: pickable ? DS.pickInk : DS.textPrimary)
                } else {
                    MoveWord(String(localized: "address"), ink: DS.textTertiary)
                }
            }
            .buttonStyle(RowPress())
            .accessibilityLabel(Text(move.recipient.map { "To \($0)" } ?? String(localized: "Pick who it goes to")))
        }
    }

    /// The one grey line under the sentence: what can move, what went wrong,
    /// or where the move stands.
    @ViewBuilder private var line: some View {
        switch move.stage {
        case .ready, .opening, .preparing, .registering, .proving, .sending:
            if move.mode == .send {
                Text(verbatim: sendLine)
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let held = move.held {
                if move.onEthereum {
                    // What moves in earns (prd §1563): the rate, read live, or nothing.
                    let have = move.symbol == "USDC"
                        ? move.usdcBalance.map { PrivateMoney.figure($0, decimals: 6, symbol: "USDC") }.map { String(localized: "\($0) in your account") }
                        : String(localized: "\(held) ETH in your account")
                    Text(verbatim: [have, store.yieldLine(symbol: move.symbol)].compactMap { $0 }
                        .joined(separator: " · "))
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                } else {
                    Text("\(held) test ETH in this build's account")
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                }
            }
        case .nothingPrivate:
            Button {
                DSHaptic.selection()
                move.mode = .deposit
            } label: {
                Text("Send to your private balance first").dsText(.body17).foregroundStyle(DS.pickInk).frame(minHeight: 44)
            }
            .buttonStyle(RowPress())
        case .failed(let words):
            Text(verbatim: words).dsText(.body17).foregroundStyle(DS.attentionInk)
                .fixedSize(horizontal: false, vertical: true)
        case .done(let hash):
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if move.mode == .deposit {
                    Text(verbatim: approval)
                        .dsText(.body17)
                        .foregroundStyle(note?.status == .approved ? DS.confirmInk
                                         : note?.status == .rejected ? DS.destructiveInk : DS.attentionInk)
                }
                if !hash.isEmpty, let link = URL(string: PrivateMoney.explorerTx(hash, chainId: move.network.chainId)) {
                    let explorer = "Etherscan"
                    Button { openURL(link) } label: {
                        Text("View on \(explorer)").dsText(.body17).foregroundStyle(DS.pickInk).frame(minHeight: 44)
                    }
                    .buttonStyle(RowPress())
                }
            }
        default:
            EmptyView()
        }
    }

    /// Switch on: the relayer's fee and about how long (the relayed
    /// withdrawal measured 27 s on Sepolia, the proof a few more).
    private var sendLine: String {
        // To someone with a private account of their own, it stays private:
        // balance to balance (prd §1567), nothing paid out.
        if move.balanceToBalance == true {
            return [String(localized: "To their private balance"), String(localized: "about a minute")].joined(separator: " · ")
        }
        // A Sepolia fee is a few hundred-millionths: it keeps its digits.
        let fee: String? = move.symbol == "USDC"
            ? move.fee.map { String(localized: "\(PrivateMoney.figure($0, decimals: 6, symbol: "USDC")) relayer fee") }
            : move.fee.flatMap { PrivateMoney.number($0, decimals: 18, places: move.onEthereum ? 6 : 12) }.map { String(localized: "\($0) ETH relayer fee") }
        let parts = [fee, String(localized: "about a minute")]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    private var approval: String {
        switch note?.status {
        case .approved: String(localized: "Approved, private now")
        case .rejected: String(localized: "Not approved")
        default: String(localized: "Waiting for approval")
        }
    }

    // MARK: - The blanks' choices

    private func toggle(_ blank: Blank) {
        withAnimation(DS.Motion.standard) { open = open == blank ? nil : blank }
        DSHaptic.selection()
    }

    /// A blank's choices, in the glass box Move opens them in.
    @ViewBuilder private func choices(_ blank: Blank) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            switch blank {
            case .amount: amounts
            case .recipient: recipients
            }
        }
        .padding(.vertical, DS.Space.s2)
        .padding(.horizontal, DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsGlass(cornerRadius: RoomsTray.radius)
    }

    /// The amounts the money can cover: the test account's after the gas a
    /// first deposit takes, or switch on, the approved private balance.
    /// ETH's amounts, then on Ethereum USDC's (prd §1567): picking one picks
    /// its token too, so the sentence names it.
    private var amounts: some View {
        ForEach(move.options.map { "\($0.symbol) \($0.amount)" }, id: \.self) { key in
            let parts = key.split(separator: " ").map(String.init)
            let (token, step) = (parts[0], parts[1])
            let places = token == "USDC" ? 6 : 18
            let shown = PrivateMoney.figure(PrivateMoney.baseUnits(step, decimals: places) ?? "0", decimals: places, symbol: token)
            let picked = step == move.amount && token == move.symbol
            Button {
                withAnimation(DS.Motion.standard) {
                    move.pick(step, of: token)
                    open = nil
                }
                DSHaptic.selection()
            } label: {
                HStack(spacing: DS.Space.s3) {
                    AssetMark(name: token, size: DS.Face.list)
                    Text(verbatim: shown)
                        .dsText(.body17)
                        .foregroundStyle(picked ? DS.textSecondary : DS.textPrimary)
                        .monospacedDigit()
                    Spacer(minLength: DS.Space.s2)
                }
                .frame(minHeight: DSFeed.headHeight + DS.Space.s3)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
            .accessibilityAddTraits(picked ? [.isSelected] : [])
        }
    }

    /// Switch on: an address, typed or pasted, and nothing else (a book
    /// entry is Send's list, before the switch).
    @ViewBuilder private var recipients: some View {
        TextField(text: $typed, prompt: Text("0x…").foregroundStyle(DS.textTertiary)) { Text("Address") }
            .dsText(.body17)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .frame(minHeight: DSFeed.headHeight + DS.Space.s3)
            .onSubmit { take(typed) }
        Button {
            take(UIPasteboard.general.string ?? "")
        } label: {
            Text("Paste").dsText(.body17).foregroundStyle(DS.pickInk)
                .frame(maxWidth: .infinity, minHeight: DSFeed.headHeight + DS.Space.s3, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
    }

    private func take(_ raw: String) {
        let address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PrivateMoney.isAddress(address) else {
            typed = address
            DSHaptic.failure()
            return
        }
        withAnimation(DS.Motion.standard) {
            move.recipient = address
            open = nil
        }
        DSHaptic.selection()
        if failed { Task { await move.read() } }
    }

    /// The read or the act failed, and the foot offers Try again.
    private var failed: Bool {
        if case .failed = move.stage { true } else { false }
    }

    // MARK: - The foot

    /// The act at the trailing edge, Move's rung; a quiet word beside it
    /// where there is a second thing to do.
    private var foot: some View {
        HStack(alignment: .firstTextBaseline) {
            switch move.stage {
            case .needsFunds(let address):
                Button {
                    Task { await move.read() }
                    DSHaptic.selection()
                } label: {
                    Text("Check again").dsText(.heading24).foregroundStyle(DS.textPrimary).frame(minHeight: 48)
                }
                .buttonStyle(RowPress())
                Spacer(minLength: DS.Space.s3)
                footButton(copied ? String(localized: "Copied") : String(localized: "Copy address"), on: true) { copy(address) }
            case .done, .nothingPrivate:
                Spacer(minLength: 0)
            case .failed:
                Spacer(minLength: 0)
                footButton(String(localized: "Try again"), on: true) { Task { await move.read() } }
            default:
                Spacer(minLength: 0)
                footButton(footVerb, on: ready) {
                    open = nil
                    Task { await move.run() }
                }
                .disabled(!ready)
            }
        }
        .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
        .padding(.bottom, DS.Space.s2)
        .background { if inTray { DS.surfaceSheet } else { DSPageBackground() } }
    }

    /// Each stage in the foot's own words, as Move's verb says its own.
    private var footVerb: String {
        switch move.stage {
        case .opening: String(localized: "Confirm with Face ID")
        case .preparing: String(localized: "Preparing…")
        case .registering(let n): String(localized: "Setting up, \(n) of 2…")
        case .proving: String(localized: "Proving…")
        case .sending:
            move.mode == .send ? String(localized: "Sending…")
                : move.onEthereum ? String(localized: "Waiting for Ethereum…") : String(localized: "Waiting for Sepolia…")
        default: String(localized: "Send")
        }
    }

    private func footButton(_ word: String, on: Bool, act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(verbatim: word)
                .dsText(.heading34)
                .foregroundStyle(on ? DS.pickInk : DS.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(minHeight: 48, alignment: .trailing)
        }
        .buttonStyle(RowPress())
    }

    /// One Activity row for the move, by its transaction: the eye-slash
    /// lead, the words with no verb, Etherscan its door.
    private func land(_ hash: String) {
        let title = PrivateMoney.activityTitle(figure: figure,
                                               to: move.mode == .send ? move.recipient.map(YourAccount.short) : nil)
        PrivateActivity.land(hash: hash, title: title, chainId: move.network.chainId, context: context)
        chrome.refreshRooms()
    }

    private func copy(_ address: String) {
        DSPasteboard.copy(address)
        DSHaptic.tap()
        withAnimation(DS.Motion.standard) { copied = true }
    }
}

/// How the private sentence is left: the switch turned off, or the
/// recipient word tapped to pick someone else.
enum MovePrivateLeave { case switchOff, pickRecipient }

/// **THE PRIVATE SWITCH (prd §1554).** Under Send's sentence: the eye-slash,
/// "Private", an iOS switch. Off by default and never remembered on: each
/// Send starts public. The app's pink when on, as every switch (prd §1561).
struct MovePrivateSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.s3) {
            Image(systemName: "eye.slash")
                .dsGlyph(.body, weight: .semibold)
                .foregroundStyle(isOn ? DS.pickInk : DS.textTertiary)
                .accessibilityHidden(true)
            DSToggleRow(title: Text("Private"), isOn: $isOn)
        }
        .frame(minHeight: 52)
        .animation(DS.Motion.standard, value: isOn)
    }
}
