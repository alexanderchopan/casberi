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
    /// How hidden a send from this money is; nil where nothing was read.
    @State private var hidden: HiddenWords?
    #if DEBUG
    @State private var hiddenPreview = false
    #endif
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context
    @Environment(ShellChrome.self) private var chrome

    enum Blank { case amount, recipient, network }

    private var store: PrivateMoneyStore { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // **THE SENTENCE STANDS STILL ON TOP, THE DECK UNDER IT (prd
                // §1927, user: "we need to be consistent!"):** as Send's,
                // Swap's and Earn's.
                MoveFlow { sentence }
                    .moveHoldFill()
                    .allowsHitTesting(false)
                    .animation(DS.Motion.standard, value: move.stage)
                    .animation(DS.Motion.standard, value: move.amount)
                    .animation(DS.Motion.standard, value: move.recipient)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Ready, the facts are the deck's receipt; else the line here.
                if move.stage != .ready {
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        #if DEBUG
                        if hiddenPreview, let hidden { hiddenLine(hidden) }
                        #endif
                        line
                    }
                    .padding(.top, DS.Space.s4)
                }
            }
            .padding(.horizontal, MoveSentence.sideInset(inTray))
            .padding(.top, inTray ? DS.Space.s2 : DS.Space.s6)
            .padding(.bottom, DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { deck }
        // The deck opens on what is missing once read (prd §1782, as Earn's).
        .onChange(of: move.stage == .ready, initial: true) { _, on in
            guard on, open == nil else { return }
            if move.mode == .send, move.recipient == nil, move.tag == nil {
                withAnimation(DS.Motion.standard) { open = .recipient }
            }
        }
        // Send opens whole: its rows and sentence clip in the short sheet.
        .onAppear { chrome.moveTall = true }
        // A word's choices make the sheet whole, and it stays whole (prd §1681b).
        .onChange(of: open) { _, now in if now != nil { chrome.moveTall = true } }
        .onChange(of: chrome.moveTall) { _, tall in
            if !tall, open != nil { withAnimation(DS.Motion.standard) { open = nil } }
        }
        // How hidden the money is, read off the main body (prd §628, §1738).
        .task(id: move.symbol) {
            await PrivacyPoolsCrowd.refresh()
            hidden = hiddenWords()
        }
        .task(id: move.mode) {
            move.context = context
            await move.read()
            hidden = hiddenWords()
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
            // Money moved is felt, as Move's own sends are (prd §1586).
            DSHaptic.success()
        }
        // Approved is the moment it became private: felt once (prd §1586).
        .onChange(of: note?.status) { _, now in
            if now == .approved { DSHaptic.success() }
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
    /// A paste or a submit that was not an address.
    @State private var notAnAddress = false

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
        move.stage == .ready && (move.mode == .deposit || move.recipient.map(PrivateMoney.isAddress) == true || move.tag != nil)
    }

    // MARK: - The sentence

    /// Ready or working: the verb (Move's word, `head`) is the sentence's
    /// first word (prd §1681). Done says "Sent" in its place.
    private var leadsWithVerb: Bool {
        switch move.stage {
        case .reading, .needsFunds, .nothingPrivate: false
        default: !isDone
        }
    }

    @ViewBuilder private var sentence: some View {
        switch move.stage {
        case .reading:
            MovePhrase(move.onEthereum ? String(localized: "Reading Ethereum…") : String(localized: "Reading Sepolia…"), ink: DS.textSecondary)
        case .needsFunds(let address):
            MoveClause(glue: String(localized: "Fund")) {
                Button { copy(address) } label: { MoveWord(YourAccount.short(address), ink: DS.textPrimary) }
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
            if !isDone { head() }
            MoveClause(glue: isDone ? String(localized: "Sent") : nil) {
                Button {
                    guard move.stage == .ready else { return }
                    toggle(.amount)
                } label: {
                    MoveWord(figure, ink: MoveSentence.settledInk)
                }
                .buttonStyle(RowPress())
                .accessibilityLabel(Text("Amount, \(figure)"))
                .accessibilityHint(Text("Picks how much"))
            }
            if move.mode == .send {
                MoveWordsClause(glue: String(localized: "from"), words: "Privacy Pools",
                                ink: DS.textPrimary,
                                action: { if move.stage == .ready { leave(.switchOff) } },
                                hint: Text("Picks where it comes from"))
            }
            if move.mode == .deposit {
                MoveWordsClause(glue: String(localized: "to"), words: "Privacy Pools",
                                ink: DS.textPrimary,
                                action: { if move.stage == .ready { leave(.pickRecipient) } },
                                hint: Text("Picks the address"))
            } else if move.recipient != nil || move.tag != nil {
                // Nobody picked is not said (prd §1791): no "to address".
                MoveClause(glue: String(localized: "to")) { recipientWord }
            }
            // Where it arrives (prd §1879): Base or Robinhood once picked.
            // With no one picked yet it goes "to Base", never "your private
            // balance on Base" (the balance stays on Ethereum).
            MovePhrase(move.away ? Self.networkName(move.destination) + "."
                       : move.onEthereum ? String(localized: "Ethereum.") : String(localized: "Sepolia."),
                       glue: move.away && move.recipient == nil ? String(localized: "to") : String(localized: "on"))
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
                MoveWord("Privacy Pools", ink: MoveSentence.settledInk)
            }
            .buttonStyle(RowPress())
            .accessibilityHint(Text("Picks the address"))
        } else {
            // A failed read leaves the address open: the relayer's fee does
            // not wait on it, and taking one reads again (`take`).
            let pickable = live || failed
            Button {
                guard pickable else { return }
                toggle(.recipient)
            } label: {
                Group {
                    if let tag = move.tag {
                        MoveWord(ZkMoneyWire.display(tag), ink: MoveSentence.settledInk)
                    } else if let to = move.recipient {
                        MoveWord(YourAccount.short(to), ink: MoveSentence.settledInk)
                    } else {
                        MoveWord(String(localized: "address"), ink: open == .recipient ? DS.pickInk : DS.textTertiary)
                    }
                }
            }
            .buttonStyle(RowPress())
            .accessibilityLabel(Text(move.recipient.map { "To \($0)" } ?? String(localized: "Pick an address")))
        }
    }

    /// The one grey line under the sentence: what can move, what went wrong,
    /// or where the move stands.
    @ViewBuilder private var line: some View {
        switch move.stage {
        case .ready, .opening, .preparing, .registering, .proving, .sending:
            if move.mode == .send {
                // **FACTS, IN THE ANSWERS' COLUMN (prd §1896):** one line of
                // " · " parts at the page's edge was the one block on Move
                // that read as a sentence of small print.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sendFacts, id: \.name) { MoveFactRow(name: $0.name, value: $0.value) }
                }
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
        case .needsFunds:
            // Why it asks for funds, in the figures the check uses: the
            // pool's smallest step, and the ETH kept for the network fee.
            if let words = fundsLine {
                Text(verbatim: words)
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                Task { await move.read() }
                DSHaptic.selection()
            } label: {
                Text("Check again").dsText(.body17).foregroundStyle(DS.pickInk).frame(minHeight: 44)
            }
            .buttonStyle(RowPress())
        case .nothingPrivate:
            Button {
                DSHaptic.selection()
                move.mode = .deposit
            } label: {
                Text("Send to Privacy Pools first").dsText(.body17).foregroundStyle(DS.pickInk).frame(minHeight: 44)
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

    /// "At least 0.005 ETH or 10.05 USDC moves in, plus 0.0044 ETH kept for
    /// the network fee." Nil until the read has the figures.
    private var fundsLine: String? {
        guard let eth = move.leastETH, let fee = move.feeKept else { return nil }
        let coin = move.onEthereum ? "ETH" : String(localized: "test ETH")
        let least = move.leastUSDC.map { String(localized: "\(eth) \(coin) or \($0) USDC") } ?? "\(eth) \(coin)"
        return String(localized: "At least \(least) moves in, plus \(fee) \(coin) kept for the network fee.")
    }

    /// Switch on: the network where it cannot change, the relayer's fee, what
    /// a crossing keeps and about how long (the relayed withdrawal measured
    /// 27 s on Sepolia, the proof a few more), as facts (prd §1896).
    private var sendFacts: [(name: String, value: String?)] {
        var facts: [(name: String, value: String?)] = []
        // The network is the sentence's last word (prd §1929).
        // To someone with a private account of their own, it stays private:
        // balance to balance (prd §1567), nothing paid out.
        if move.balanceToBalance == true, !move.away {
            facts.append((String(localized: "Arrives"), String(localized: "in their private balance")))
            facts.append((String(localized: "Takes"), String(localized: "about a minute")))
            return facts
        }
        // A Sepolia fee is a few hundred-millionths: it keeps its digits.
        let fee: String? = move.symbol == "USDC"
            ? move.fee.map { PrivateMoney.figure($0, decimals: 6, symbol: "USDC") }
            : move.fee.flatMap { PrivateMoney.number($0, decimals: 18, places: move.onEthereum ? 6 : 12) }.map { "\($0) ETH" }
        if let fee { facts.append((String(localized: "Relayer fee"), fee)) }
        if move.away {
            // To Base or Robinhood, Across and a one-time sender's gas (prd §1879).
            if move.symbol == "USDC" {
                facts.append((String(localized: "Gas"), String(localized: "from your private ETH")))
                facts.append((String(localized: "Across keeps"), String(localized: "about 0.1%")))
            } else {
                facts.append((String(localized: "Across and gas keep"), String(localized: "about 1–2%")))
            }
        } else if move.tag != nil {
            // To a tag, zk.money's own fee follows the relayer's (prd §1874).
            facts.append((String(localized: "zk.money keeps"),
                          String(localized: "about $\(ZkMoneyWire.payFeeUSD.formatted(.number.precision(.fractionLength(2))))")))
        } else {
            facts.append((String(localized: "Takes"), String(localized: "about a minute")))
        }
        // The relayer refused Tor and was asked directly (`TorFallback`).
        if move.relayerDirect { facts.append((String(localized: "Not through Tor"), nil)) }
        return facts
    }

    private var approval: String {
        switch note?.status {
        case .approved: String(localized: "Approved, private now")
        case .rejected: String(localized: "Not approved")
        default: PrivateMoney.beingChecked
        }
    }

    // MARK: - The blanks' choices

    private func toggle(_ blank: Blank) {
        withAnimation(DS.Motion.standard) { open = open == blank ? nil : blank }
        DSHaptic.selection()
    }

    /// **THE DECK'S STEPS (prd §1927):** To, the network where ETH may
    /// arrive away (prd §1879), and the amount; a move-in's To goes back to
    /// Send's recipients.
    private var steps: [MoveDeckStep] {
        var out: [MoveDeckStep] = []
        if move.mode == .send {
            out.append(MoveDeckStep(id: "to", word: String(localized: "To"), on: open == .recipient,
                                    answered: move.recipient != nil || move.tag != nil) { toggle(.recipient) })
            if move.canGoAway {
                out.append(MoveDeckStep(id: "network", word: String(localized: "Network"), on: open == .network,
                                        answered: true) { toggle(.network) })
            }
        } else {
            out.append(MoveDeckStep(id: "to", word: String(localized: "To"), answered: true) { leave(.pickRecipient) })
        }
        out.append(MoveDeckStep(id: "amount", word: String(localized: "Amount"), on: open == .amount,
                                answered: !move.amount.isEmpty) { toggle(.amount) })
        return out
    }

    /// The deck's receipt, nothing open (prd §1927): where it goes and from,
    /// the facts, how hidden.
    @ViewBuilder private var receipt: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            // The token leads the receipt, as Send's does (prd §1929).
            TokenRowLabel(symbol: move.symbol, line: move.network.name, figure: "−" + figure)
            // **NOTHING THE SENTENCE SAYS (prd §1929):** from, to and the
            // network are its words; the receipt holds the rest.
            if move.mode == .send {
                ForEach(sendFacts, id: \.name) { MoveFactRow(name: $0.name, value: $0.value, indented: false) }
                if let hidden { hiddenLine(hidden) }
            } else {
                line
            }
            // "Through Privacy Pools" is the sentence's own word now (prd §1929).
        }
    }

    /// **MOVE'S LIST ROW (prd §1896):** the mark centred in the rows' mark
    /// column, the words where a row's answer starts, at Move's list rung,
    /// the pick checked; this page drew its own smaller rows.
    private func listRow<Mark: View>(_ title: String, picked: Bool, @ViewBuilder mark: () -> Mark) -> some View {
        HStack(spacing: MoveChoiceRowLabel.leadGap) {
            mark().frame(width: MoveChoiceRowLabel.markSize)
            Text(verbatim: title).dsText(MoveSentence.choiceRung).foregroundStyle(DS.textPrimary).monospacedDigit()
            Spacer(minLength: DS.Space.s2)
            if picked { MoveMenuCheck() }
        }
        .frame(maxWidth: .infinity, minHeight: MoveSentence.listRowHeight, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityAddTraits(picked ? [.isSelected] : [])
    }

    /// Where the money arrives: a picked network away, else the balance's own.
    private var arrivesOn: Int { move.away ? move.destination : (move.onEthereum ? 1 : 0) }

    /// A blank's choices, on the tray in the sentence's column as Move
    /// opens them (prd §1616).
    @ViewBuilder private func choices(_ blank: Blank) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            switch blank {
            case .amount: amounts
            case .recipient: recipients
            case .network: networks
            }
        }
        .padding(.vertical, DS.Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func networkName(_ chainId: Int) -> String {
        switch chainId {
        case 0: String(localized: "Sepolia")
        case 8453: String(localized: "Base")
        case 4663: String(localized: "Robinhood")
        default: String(localized: "Ethereum")
        }
    }

    /// Where ETH sent to an address arrives (prd §1879): Ethereum, or Base
    /// or Robinhood through Across.
    private var networks: some View {
        ForEach([1, 8453, 4663], id: \.self) { chain in
            Button {
                withAnimation(DS.Motion.standard) {
                    move.destination = chain
                    open = nil
                }
                DSHaptic.selection()
            } label: {
                listRow(Self.networkName(chain), picked: move.destination == chain) {
                    if let mark = MoveSentence.networkMark(chainId: chain) { MoveRowMark(network: mark, size: MoveSentence.listMark) }
                }
            }
            .buttonStyle(RowPress())
        }
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
                listRow(shown, picked: picked) { AssetMark(name: token, size: MoveSentence.listMark) }
            }
            .buttonStyle(RowPress())
            .accessibilityAddTraits(picked ? [.isSelected] : [])
        }
    }

    /// Switch on: an address, typed or pasted, and nothing else (a book
    /// entry is Send's list, before the switch).
    @ViewBuilder private var recipients: some View {
        if notAnAddress {
            Text("That isn't an address").dsText(.body17).foregroundStyle(DS.attentionInk)
                .padding(.top, DS.Space.s2)
        }
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
        // A zk.money tag typed here pays as Send's To does (prd §1874).
        if move.onEthereum, let tag = ZkMoneyWire.tag(address) {
            notAnAddress = false
            withAnimation(DS.Motion.standard) {
                move.pay(tag: tag)
                open = nil
            }
            DSHaptic.selection()
            if failed { Task { await move.read() } }
            return
        }
        guard PrivateMoney.isAddress(address) else {
            typed = address
            DSHaptic.failure()
            // Said, not only felt (prd §1586).
            withAnimation(DS.Motion.standard) { notAnAddress = !address.isEmpty }
            return
        }
        notAnAddress = false
        withAnimation(DS.Motion.standard) {
            move.pay(tag: nil, address: address)
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

    @Environment(\.moveBack) private var back
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var live: Bool { move.stage == .ready || failed }

    /// **PRIVACY POOLS' DECK (prd §1927, as Earn's §1901).**
    private var deck: some View {
        VStack(alignment: .leading, spacing: 0) {
            if live, !isDone {
                MoveDeckSteps(steps: steps)
                    .padding(.bottom, MoveDeck.stepsGap)
            }
            ZStack(alignment: .bottom) {
                Group {
                    if let open, live {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                switch open {
                                case .amount: amounts
                                case .recipient: recipients
                                case .network: networks
                                }
                            }
                            .padding(.vertical, DS.Space.s2)
                        }
                        .scrollIndicators(.hidden)
                        .contentMargins(.bottom, MoveDeck.fade, for: .scrollContent)
                        .transition(.opacity)
                    } else if move.stage == .ready {
                        ScrollView { receipt.padding(.vertical, DS.Space.s2) }
                            .scrollIndicators(.hidden)
                            .contentMargins(.bottom, MoveDeck.fade, for: .scrollContent)
                            .transition(.opacity)
                    } else {
                        Color.clear
                    }
                }
                .safeAreaPadding(.bottom, MoveDeck.footHeight)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: MoveDeck.bodyHeight + MoveDeck.footHeight
                       + MoveFootClearance.bar(inTray: inTray, sizeClass: sizeClass, chrome: chrome)
                       + MoveFootClearance.gained(inTray: inTray)
                       - MoveDeck.stepsGap, alignment: .top)
                .deckUnderFoot()
                MoveDeckFoot(back: {
                    withAnimation(DS.Motion.standard) {
                        // Back is the menu, never the step before (prd §1911).
                        open = nil; back?()
                    }
                }) { footWord }
            }
        }
        .padding(.horizontal, MoveSentence.sideInset(inTray))
        .padding(.top, HomePanelMetrics.cap)
        .modifier(MoveFootClearance(inTray: inTray, intoBody: true))
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                Group { if inTray { DS.surfaceSheet } else { DSPageBackground() } }
                HomePanelSurface()
            }
            .padding(.horizontal, inTray ? -DS.Space.s4 : 0)
            .ignoresSafeArea(edges: .bottom)
        }
        .animation(DS.Motion.standard, value: open)
    }

    /// **THE FOOT'S ONE WORD (prd §1897 item 7).**
    @ViewBuilder private var footWord: some View {
        switch move.stage {
        case .needsFunds(let address):
            MoveFootWord(word: copied ? String(localized: "Copied") : String(localized: "Copy address")) { copy(address) }
        case .done:
            // Done ends it, as every receipt does (prd §1586).
            MoveFootWord(word: String(localized: "Done")) {
                if inTray { chrome.moveTray = false } else { leave(.switchOff) }
            }
        case .nothingPrivate:
            EmptyView()
        case .failed:
            MoveFootWord(word: String(localized: "Try again")) { Task { await move.read() } }
        case .ready:
            if move.mode == .send, move.recipient == nil, move.tag == nil {
                // The word names what is missing (prd §1805).
                MoveFootWord(word: String(localized: "Choose an address")) { toggle(.recipient) }
            } else {
                MoveHoldWord(word: String(localized: "Hold to send"), enabled: ready) {
                    open = nil
                    Task { await move.run() }
                }
            }
        default:
            MoveFootWord(word: footVerb, ink: DS.textSecondary)
        }
    }

    /// **HOW HIDDEN, WHERE YOU SEND (prd §1738; was a section on the Privacy
    /// Pools pick, §1614).** The deposits this money sits among, or "Wait a
    /// day" while its newest deposit is under a day old and a send from it is
    /// easy to tie back. It advises and never blocks. Nothing where 0xBow
    /// publishes no count (off Ethereum) and nothing was just deposited.
    struct HiddenWords: Equatable {
        let text: String
        let soon: Bool
    }

    private func hiddenWords() -> HiddenWords? {
        guard move.mode == .send else { return nil }
        #if DEBUG
        // `-moveHiddenPreview soon|<count>`: the line drawn with no private
        // money to read, which a simulator never has (NSLogs `moveHidden:`).
        if let raw = UserDefaults.standard.string(forKey: "moveHiddenPreview"), !raw.isEmpty {
            hiddenPreview = true
            NSLog("[Casberi] moveHidden: preview %@", raw)
            if let count = Int(raw) {
                return HiddenWords(text: String(localized: "Hidden among \(count.formatted()) deposits"), soon: false)
            }
            return HiddenWords(text: String(localized: "Wait a day"), soon: true)
        }
        #endif
        let chain = move.network.chainId
        let notes = store.shownNotes.filter {
            $0.symbol == move.symbol && $0.chainId == chain && PrivateMoney.kind($0.status) != .refused
        }
        if PrivacyPoolsCrowd.tooSoon(newest: notes.map(\.at).max()) {
            return HiddenWords(text: String(localized: "Wait a day"), soon: true)
        }
        let counts = PrivacyPoolsCrowd.counts()
        // The smallest crowd any of its notes is in: the honest one.
        guard let crowd = notes.compactMap({
            PrivacyPoolsCrowd.crowd(symbol: move.symbol, chainId: chain, share: $0.share,
                                    plain: $0.share == nil, counts: counts)
        }).min() else { return nil }
        return HiddenWords(text: String(localized: "Hidden among \(crowd.formatted()) deposits"), soon: false)
    }

    private func hiddenLine(_ hidden: HiddenWords) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: hidden.text)
                .dsText(.body17)
                .foregroundStyle(hidden.soon ? DS.attentionInk : DS.textSecondary)
            if hidden.soon {
                Text("Your newest deposit is under a day old, so a send is easy to tie to it.")
                    .dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, DS.Space.s2)
        .accessibilityElement(children: .combine)
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

    /// One Activity row for the move, by its transaction: the eye-slash
    /// lead, the words with no verb, Etherscan its door.
    private func land(_ hash: String) {
        let title = PrivateMoney.activityTitle(figure: figure,
                                               to: move.mode == .send ? (move.tag.map(ZkMoneyWire.display) ?? move.recipient.map(YourAccount.short)) : nil)
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
/// Where a private sentence hands Move back: the switch off, the recipient
/// list, or (under Railgun's $10, prd §1728 item 2) Receive or Swap.
enum MovePrivateLeave { case switchOff, pickRecipient, receive, swap }

/// **THE PRIVATE SWITCH (prd §1554).** Under Send's sentence: the eye-slash,
/// "Private", an iOS switch. Off by default and never remembered on: each
/// Send starts public. The app's pink when on, as every switch (prd §1561).
struct MovePrivateSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.s2) {
            // The door rows' column, so "Private" reads with "From another
            // wallet" and the lines under the address (prd §1616 item 7).
            Image(systemName: "eye.slash")
                .dsGlyph(.caption, weight: .semibold)
                .foregroundStyle(isOn ? DS.pickInk : DS.textTertiary)
                .frame(width: DSDoorRowLabel.glyphColumn, alignment: .center)
                .accessibilityHidden(true)
            DSToggleRow(title: Text("Private"), isOn: $isOn)
        }
        .frame(minHeight: 52)
        .animation(DS.Motion.standard, value: isOn)
    }
}
