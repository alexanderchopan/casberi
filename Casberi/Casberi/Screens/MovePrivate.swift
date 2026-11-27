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
    /// The amount typed in dollars (prd §1979): the figure on the keys, the
    /// token's amount worked out from today's price.
    @State private var inDollars = false
    @State private var dollars = ""
    /// How hidden a send from this money is; nil where nothing was read.
    @State private var hidden: HiddenWords?
    #if DEBUG
    @State private var hiddenPreview = false
    #endif
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context
    @Environment(ShellChrome.self) private var chrome

    enum Blank { case amount, recipient, network, token }

    private var store: PrivateMoneyStore { .shared }

    var body: some View {
        // **A RECEIPT, AS EVERY VERB'S (prd §1931).**
        deck
        // The deck opens on what is missing once read (prd §1782, as Earn's).
        .onChange(of: move.stage == .ready, initial: true) { _, on in
            guard on, open == nil else { return }
            if move.mode == .send, move.recipient == nil, move.tag == nil {
                withAnimation(DS.Motion.standard) { open = .recipient }
            }
        }
        // Send opens whole: its rows and sentence clip in the short sheet.
        .onAppear {
            chrome.moveTall = true
            move.watcher = nil
        }
        // **FACE ID GIVEN, THE SHEET STEPS ASIDE (2026-11-27, user:
        // "shouldn't it have turned into a banner?").** The send goes on
        // under the toast; nothing on the sheet waits on you.
        .onChange(of: move.stage) { was, now in
            if inTray, move.mode == .send, was == .opening, now == .preparing { chrome.moveTray = false }
        }
        // Closed on a send still going: the toast says each step and the
        // row lands without the sheet (2026-11-27).
        .onDisappear {
            guard move.busy, move.mode == .send else { return }
            let chrome = chrome, context = context
            move.watcher = { m in MovePrivateToast.say(m, chrome: chrome, context: context) }
            MovePrivateToast.say(move, chrome: chrome, context: context)
        }
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
        // An earlier send to the same place is finished, so its amount is
        // the sentence's (prd §1988).
        .onChange(of: move.stage == .ready ? move.finishing : nil, initial: true) { _, earlier in
            if earlier != nil { move.adoptFinishing() }
        }
        // A dollar send away: the private ETH its gas takes, once the
        // relayer's fee is read (prd §1988).
        .task(id: "\(move.away && move.symbol == "USDC") \(move.quotedFee ?? "")") { await move.readAwayGas() }
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
        move.stage == .ready && move.amountFits && (move.mode == .deposit || move.recipient.map(PrivateMoney.isAddress) == true || move.tag != nil)
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
                    guard move.stage == .ready, move.finishing == nil else { return }
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
                    MoveDeckFacts(facts: sendFacts.map { .init(name: $0.name, value: $0.value) })
                }
            } else if move.onEthereum, let short = move.usdcShort {
                // What there is and earns is the Amount line's note (prd §1992);
                // the minimum it misses stays the page's alert (§1938).
                usdcShortLine(short)
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
                // What went and where it is (prd §1990).
                PrivateFinishLines(headline: finishHeadline)
                    .onAppear { chrome.rain(sources: ["Wallet"]) }
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

    /// The finish's first line (prd §1990): into Privacy Pools, to someone's
    /// private balance, back to your public account, or to their address.
    private var finishHeadline: String {
        if move.mode == .deposit {
            return PrivateFinish.headline(figure, to: .yours("Privacy Pools"), onItsWay: true)
        }
        if let tag = move.tag {
            return PrivateFinish.headline(figure, to: .theirPrivate(ZkMoneyWire.display(tag)))
        }
        guard let to = move.recipient else { return String(localized: "Sent privately") }
        if move.balanceToBalance == true, !move.away {
            return PrivateFinish.headline(figure, to: .theirPrivate(PrivateFinish.who(to)))
        }
        if PrivateMove.isYours(to) { return PrivateFinish.headline(figure, to: .yourPublic, onItsWay: move.away) }
        return PrivateFinish.headline(figure, to: .theirPublic(PrivateFinish.who(to)), onItsWay: move.away)
    }

    /// Why USDC is not offered (prd §1938), in amber: under the list's
    /// amounts and in the receipt.
    private func usdcShortLine(_ words: String) -> some View {
        Text(verbatim: words)
            .dsText(.body17).foregroundStyle(DS.attentionInk)
            .fixedSize(horizontal: false, vertical: true)
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
        // A Sepolia fee is a few hundred-millionths: it keeps its digits.
        let fee: String? = move.symbol == "USDC"
            ? move.fee.map { PrivateMoney.figure($0, decimals: 6, symbol: "USDC") }
            : move.fee.flatMap { PrivateMoney.number($0, decimals: 18, places: move.onEthereum ? 6 : 12) }.map { "\($0) ETH" }
        // The network is the sentence's last word (prd §1929).
        // To someone with a private account of their own, it stays private:
        // balance to balance (prd §1567), nothing paid out.
        if move.balanceToBalance == true, !move.away {
            facts.append((String(localized: "Arrives"), String(localized: "in their private balance")))
            // **THE RELAYER IS PAID HERE TOO (prd §1988):** a transfer is
            // relayed as a withdrawal is, and the line said nothing of it.
            if let fee { facts.append((String(localized: "Relayer fee"), fee)) }
            facts.append((String(localized: "Takes"), String(localized: "about a minute")))
            return facts
        }
        // **FINISHING AN EARLIER SEND (prd §1988):** what goes is what
        // already left, said once, above the rest.
        if let earlier = move.finishing {
            let left = earlier.amount.map { PrivateMoney.figure($0, decimals: earlier.symbol == "USDC" ? 6 : 18, symbol: earlier.symbol ?? "ETH") }
            facts.append((left.map { String(localized: "Finishing your earlier send of \($0)") }
                          ?? String(localized: "Finishing your earlier send"), nil))
        }
        if let fee, move.finishing == nil { facts.append((String(localized: "Relayer fee"), fee)) }
        // Paid out: say where, as balance to balance does.
        // Only once the check has answered: "their public account" must not
        // flip to "private balance" a moment later (prd §1988).
        if let to = move.recipient, move.tag == nil, !move.away, move.balanceToBalance == false {
            facts.insert((String(localized: "Arrives"), PrivateMove.isYours(to)
                ? String(localized: "in your public account") : String(localized: "in their public account")), at: 0)
        }
        if move.away {
            // To Base or Robinhood, Across and a one-time sender's gas (prd §1879).
            if move.symbol == "USDC", move.finishing == nil {
                // **ITS GAS IS A SECOND WITHDRAWAL (prd §1988):** your private
                // ETH, the gas half again and its own relayer fee, as a figure.
                if let gas = move.awayGas.flatMap({ PrivateMoney.numberUp($0, decimals: 18, places: 6) }) {
                    facts.append((String(localized: "Gas from your private ETH, with its own relayer fee"),
                                  String(localized: "about \(gas) ETH")))
                } else {
                    facts.append((String(localized: "Gas"), String(localized: "from your private ETH")))
                }
                facts.append((String(localized: "Across keeps"), String(localized: "about 0.1%")))
            } else if move.symbol == "USDC" {
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
        let token = MoveRowMark(token: move.symbol, network: MoveSentence.networkMark(chainId: move.network.chainId))
        if move.mode == .send {
            // **THE SENTENCE'S WORDS ARE THE LINES (prd §1931):** from, to,
            // the network it arrives on, the token, how much.
            out.append(MoveDeckStep(id: "from", word: String(localized: "From"), answered: true,
                                    value: "Privacy Pools", glyph: "lock.fill") { leave(.switchOff) })
            let to: String? = move.tag.map(ZkMoneyWire.display) ?? move.recipient.map(YourAccount.short)
            out.append(MoveDeckStep(id: "to", word: String(localized: "To"), on: open == .recipient,
                                    answered: to != nil, value: to) { toggle(.recipient) })
            if move.canGoAway {
                out.append(MoveDeckStep(id: "network", word: String(localized: "Network"), on: open == .network,
                                        answered: true, value: Self.networkName(move.destination)) { toggle(.network) })
            }
        } else {
            out.append(MoveDeckStep(id: "to", word: String(localized: "To"), answered: true,
                                    value: "Privacy Pools", glyph: "lock.fill") { leave(.pickRecipient) })
        }
        // Finishing an earlier send, its token and amount are fixed (prd §1988).
        let fixed = move.finishing != nil
        out.append(MoveDeckStep(id: "token", word: String(localized: "Token"), on: open == .token, answered: true,
                                value: "\(move.symbol) · \(move.network.name)", mark: token) { if !fixed { toggle(.token) } })
        // **THE OPEN CHIP IS THE FIELD (prd §1989):** the figure in the unit
        // it is typed in, $ | token at its end, what it means under it.
        let typing = open == .amount
        let typingDollars = typing && inDollars
        let flips = price != nil && move.symbol != "USDC"
        out.append(MoveDeckStep(id: "amount", word: String(localized: "Amount"), on: typing,
                                answered: typingDollars ? !dollars.isEmpty : !move.amount.isEmpty,
                                value: typingDollars ? "$" + (dollars.isEmpty ? "0" : MoveSentence.grouped(dollars))
                                    // **THE FIELD SHOWS WHAT WAS TYPED (2026-11-27, user: "i am
                                    // unable to enter a decimal point"):** `figure` rounds, so
                                    // "0." and "0.000" drew "0" and the keys looked dead.
                                    : (move.amount.isEmpty ? (typing ? "0 \(move.symbol)" : nil)
                                        : typing ? "\(MoveSentence.grouped(move.amount)) \(move.symbol)" : figure),
                                note: typing ? nil : (depositNote ?? maxWhy),
                                accessory: flips ? AnyView(MoveUnitSwitch(symbol: move.symbol, dollars: inDollars) { setDollars($0) }) : nil,
                                fieldNote: typing ? (text: amountLine.words, ink: amountLine.ink) : nil) { if !fixed { toggle(.amount) } })
        return out
    }

    /// The deck's receipt, nothing open (prd §1927): where it goes and from,
    /// the facts, how hidden.
    @ViewBuilder private var receipt: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            // The token leads the receipt, as Send's does (prd §1929).
            // The token and its amount are the receipt's lines (prd §1931).
            // **NOTHING THE SENTENCE SAYS (prd §1929):** from, to and the
            // network are its words; the receipt holds the rest.
            if move.mode == .send {
                MoveDeckFacts(facts: sendFacts.map { .init(name: $0.name, value: $0.value) })
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
            case .amount: amountKeys
            case .recipient: recipients
            case .network: networks
            case .token: tokenChoices
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
    @ViewBuilder private var amounts: some View {
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
        if let short = move.usdcShort {
            usdcShortLine(short).padding(.top, DS.Space.s2)
        }
    }

    /// The tokens the money holds, each once (prd §1979): a pick keeps the
    /// typed amount when it fits the new token, else its first step.
    @ViewBuilder private var tokenChoices: some View {
        let symbols = move.options.map(\.symbol).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        // Move's one token list (prd §1910, `move-token-grid-audit.py`), as
        // every other place's tokens are drawn.
        MoveTokenGrid(places: [MoveTokenPlace(id: "private", choices: symbols.map { token in
            MoveTokenChoice(id: token, symbol: token, network: move.network.name, picked: token == move.symbol) {
                withAnimation(DS.Motion.standard) {
                    if let first = move.options.first(where: { $0.symbol == token }) { move.pick(first.amount, of: token) }
                    inDollars = false
                    open = nil
                }
                DSHaptic.selection()
            }
        })])
        if let short = move.usdcShort {
            usdcShortLine(short).padding(.top, DS.Space.s2)
        }
    }

    /// The steps the money covers, three at most, then Max (prd §1979).
    private var quickKeys: [MoveQuickKeys.Key] {
        // A count of options, never an address's head (the self-test's guard
        // reads a numeric `prefix(` as one).
        let shown = 3
        let steps = move.options.filter { $0.symbol == move.symbol }.prefix(shown)
        var keys = steps.map { o in
            MoveQuickKeys.Key(id: o.amount, word: PrivateMoney.number(PrivateMoney.baseUnits(o.amount, decimals: move.decimals) ?? "0",
                                                  decimals: move.decimals) ?? o.amount,
                          on: !inDollars && move.amount == o.amount) { inDollars = false; move.amount = o.amount }
        }
        if let top = move.most, top != "0", let maxShown = plainAmount(top) {
            keys.append(.max(on: !inDollars && move.amount == maxShown) { inDollars = false; move.amount = maxShown })
        }
        return Array(keys)
    }

    /// Base units as a plain typed figure ("1234.56", never "1,234.56"),
    /// rounded down to the keys' places, so it is never more than there is.
    private func plainAmount(_ units: String) -> String? {
        guard var whole = Decimal(string: units) else { return nil }
        for _ in 0..<move.decimals { whole /= 10 }
        var r = Decimal()
        NSDecimalRound(&r, &whole, tokenPlaces, .down)
        return NSDecimalNumber(decimal: r).stringValue
    }

    /// Today's dollar price of the token, when read (USDC is a dollar).
    private var price: Double? {
        move.symbol == "USDC" ? 1 : store.shownPrices[move.symbol.lowercased()]
    }

    /// The token's places on the keys: six for ETH, two for a dollar.
    private var tokenPlaces: Int { move.symbol == "USDC" ? 2 : 6 }

    /// **ANY AMOUNT, IN THE TOKEN OR IN DOLLARS (prd §1979).** The steps are
    /// the keys' top row with Max; the keys type the figure; the flip types
    /// dollars and works out the token. Under them, the most it can move.
    @ViewBuilder private var amountKeys: some View {
        VStack(spacing: MoveReceipt.gap) {
            let keys = quickKeys
            if !keys.isEmpty { MoveQuickKeys(keys: keys) }
            MoveKeypad(text: inDollars ? Binding(get: { dollars }, set: { new in
                dollars = new
                guard let price, price > 0, let usd = Decimal(string: new) else { move.amount = ""; return }
                var units = usd / Decimal(price), r = Decimal()
                NSDecimalRound(&r, &units, tokenPlaces, .down)
                move.amount = NSDecimalNumber(decimal: r).stringValue
            }) : Binding(get: { move.amount }, set: { move.amount = $0 }), places: inDollars ? 2 : tokenPlaces,
                       keyHeight: MoveSentence.bigKeyHeight, big: true)
        }
    }

    /// $ | token, in the field (prd §1989): the same money in the other unit.
    private func setDollars(_ on: Bool) {
        guard on != inDollars else { return }
        withAnimation(DS.Motion.standard) {
            inDollars = on
            if inDollars, let price, let units = Decimal(string: move.amount) {
                var d = units * Decimal(price), r = Decimal()
                NSDecimalRound(&r, &d, 2, .plain)
                dollars = NSDecimalNumber(decimal: r).stringValue
            }
        }
    }

    /// The line under the field (prd §1989, was over the keys): the other
    /// unit's figure and the most it can move, or what is wrong, in amber.
    /// **A NOTE ABOUT A LINE STANDS UNDER IT (prd §1992).** Moving in, what
    /// your account holds and what it earns, under Amount, never at the
    /// page's edge (the first sweep sheet drew it three ways).
    private var depositNote: String? {
        guard move.mode == .deposit, let held = move.held else { return nil }
        guard move.onEthereum else { return String(localized: "\(held) test ETH in this build's account") }
        // What moves in earns (prd §1563): the rate, read live, or nothing.
        let have = move.symbol == "USDC"
            ? move.usdcBalance.map { PrivateMoney.figure($0, decimals: 6, symbol: "USDC") }.map { String(localized: "\($0) in your account") }
            : String(localized: "\(held) ETH in your account")
        let parts = [have, store.yieldLine(symbol: move.symbol)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// **WHY MAX IS SEVERAL SENDS (2026-11-27, user: "user needs to know
    /// tho why it is 5 sends").** Your private ETH is held in parts, one per
    /// deposit and per send's change; 0xBow's relayer moves one a send, each
    /// paying its fee. Said under the amount whenever Max is several.
    private var maxWhy: String? {
        guard move.mode == .send, let units = PrivateMoney.baseUnits(move.amount, decimals: move.decimals),
              move.isMax(units), move.sends > 1 else { return nil }
        let n = move.sends
        let fees: String? = {
            guard let f = move.fee.flatMap({ Decimal(string: $0) }) else { return nil }
            let all = f * Decimal(n)
            if move.symbol == "USDC" { return PrivateMoney.figure(PrivateMoney.plain(all), decimals: 6, symbol: "USDC") }
            guard let price else { return PrivateMoney.figure(PrivateMoney.plain(all), decimals: 18, symbol: "ETH") }
            var d = all, one = Decimal(1)
            for _ in 0..<18 { one *= 10 }
            d /= one
            return "$" + (d * Decimal(price)).formatted(.number.precision(.fractionLength(2)))
        }()
        let fee = fees.map { String(localized: " · fees \($0)") } ?? ""
        return String(localized: "Held in \(n) parts, and the relayer sends one at a time\(fee)")
    }

    private var amountLine: (words: String, ink: Color) {
        let typedFigure = inDollars ? "$\(dollars.isEmpty ? "0" : dollars)" : "\(move.amount.isEmpty ? "0" : move.amount) \(move.symbol)"
        let other: String? = {
            guard let price, move.symbol != "USDC", let units = Decimal(string: move.amount) else { return nil }
            if inDollars { return "\(move.amount) \(move.symbol)" }
            return "$" + (units * Decimal(price)).formatted(.number.precision(.fractionLength(2)))
        }()
        let top = move.most.flatMap { PrivateMoney.number($0, decimals: move.decimals, places: tokenPlaces) }
        if let units = PrivateMoney.baseUnits(move.amount, decimals: move.decimals).flatMap({ Decimal(string: $0) }), units > 0 {
            if let most = move.most.flatMap({ Decimal(string: $0) }), units > most {
                return (String(localized: "More than you can send · up to \(top ?? "0") \(move.symbol)"), DS.attentionInk)
            }
            // Over one note and short of Max: the relayer takes one note a
            // send, so it is one note's worth, or Max for every note.
            if move.mode == .send, move.onEthereum, let one = move.oneSend, units > one,
               !move.isMax(PrivateMoney.plain(units)) {
                let oneShown = PrivateMoney.number(PrivateMoney.plain(one), decimals: move.decimals, places: tokenPlaces) ?? "0"
                return (String(localized: "One send moves up to \(oneShown) \(move.symbol). Choose Max to move it all."), DS.attentionInk)
            }
            if let why = maxWhy { return (why, DS.textSecondary) }
            if units < (Decimal(string: move.least) ?? 1) {
                let least = PrivateMoney.number(move.least, decimals: move.decimals, places: tokenPlaces) ?? move.least
                return (String(localized: "At least \(least) \(move.symbol)"), DS.attentionInk)
            }
        }
        let parts = [inDollars ? other : (other.map { "≈ \($0)" }), top.map { String(localized: "up to \($0) \(move.symbol)") }].compactMap { $0 }
        return (parts.isEmpty ? typedFigure : parts.joined(separator: " · "), DS.textSecondary)
    }

    /// Switch on: an address, typed or pasted, and nothing else (a book
    /// entry is Send's list, before the switch).
    @ViewBuilder private var recipients: some View {
        // **YOUR OWN ACCOUNT AND YOUR ADDRESSES (2026-11-25, user: "when i
        // try and click choose it doesn't show my addresses").** The field
        // alone left sending out to yourself, the way to swap what Privacy
        // Pools holds, a paste away.
        ForEach(recipientChoices, id: \.address) { choice in
            Button { take(choice.address) } label: {
                listRow(choice.title, picked: move.recipient?.lowercased() == choice.address.lowercased()) {
                    WalletFace(address: choice.address, size: DS.Face.list, circular: true)
                }
            }
            .buttonStyle(RowPress())
            .dsTapTarget()
        }
        if notAnAddress {
            Text("That isn't an address or a name").dsText(.body17).foregroundStyle(DS.attentionInk)
                .padding(.top, DS.Space.s2)
        }
        TextField(text: $typed, prompt: Text("Name, ENS or address").foregroundStyle(DS.textTertiary)) { Text("Address") }
            .dsText(.body17)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .frame(minHeight: MoveDeck.rowHeight)  // every Move row, 40pt (prd §1984)
            .onSubmit { take(typed) }
        Button {
            take(UIPasteboard.general.string ?? "")
        } label: {
            Text("Paste").dsText(.body17).foregroundStyle(DS.pickInk)
                .frame(maxWidth: .infinity, minHeight: MoveDeck.rowHeight, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
    }

    /// Your public account first, then the book's Ethereum-style addresses,
    /// newest first.
    private var recipientChoices: [(title: String, address: String)] {
        var out: [(title: String, address: String)] = []
        if let mine = PrivateOnEthereum.owner {
            out.append((String(localized: "Your public account"), mine))
        }
        for entry in AddressBook.shared.all where PrivateMoney.isAddress(entry.address)
            && !out.contains(where: { $0.address.lowercased() == entry.address.lowercased() }) {
            out.append((entry.name.isEmpty ? YourAccount.short(entry.address) : entry.name, entry.address))
        }
        return out
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
        // A name (vitalik.eth and the other families Send takes) is
        // resolved, then taken as the address it names (2026-11-25, user:
        // "it doesn't even take my ENS").
        if !PrivateMoney.isAddress(address), address.contains(".") {
            typed = address
            Task {
                if let resolved = await NameResolve.resolve(address), PrivateMoney.isAddress(resolved) {
                    take(resolved)
                } else {
                    DSHaptic.failure()
                    withAnimation(DS.Motion.standard) { notAnAddress = true }
                }
            }
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
        MoveReceiptDeck(title: String(localized: "Send"), inTray: inTray, back: {
            withAnimation(DS.Motion.standard) {
                // Back is the menu, never the step before (prd §1911).
                open = nil; back?()
            }
        }, lines: {
            // **THE LINES STAND WHILE IT GOES, AS PUBLIC SEND'S (2026-11-25,
            // user: "is this the same design we have on public send? … we
            // need to be consistent").** Confirming and sending keep To ·
            // From · Token · Amount on screen, untouchable; no sentence.
            if !isDone, move.stage == .ready || failed || move.acting { MoveReceiptSteps(steps: steps, disabled: !live) }
        }, content: {
                // The deck's bodies (prd §1992): keys, a list, the receipt or
                // where it stands, each the template's.
                Group {
                    if open == .amount, live {
                        MoveDeckKeys { amountKeys }
                    } else if let open, live {
                        MoveDeckScroll {
                            switch open {
                            case .amount: EmptyView()
                            case .recipient: recipients
                            case .network: networks
                            case .token: tokenChoices
                            }
                        }
                    } else if move.stage == .ready {
                        MoveDeckScroll { receipt }
                    } else {
                        // Reading, funding, working, done: with no lines over
                        // it, the sentence says where it stands.
                        MoveDeckStatus(linesStand: move.acting || failed, sentence: { sentence }) {
                            #if DEBUG
                            if hiddenPreview, let hidden { hiddenLine(hidden) }
                            #endif
                            line
                        }
                    }
                }
        }, word: { footWord })
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
        case .proving:
            move.part.map { String(localized: "Proving \($0.0) of \($0.1)…") } ?? String(localized: "Proving…")
        case .sending:
            move.mode == .send ? (move.part.map { String(localized: "Sending \($0.0) of \($0.1)…") } ?? String(localized: "Sending…"))
                : move.onEthereum ? String(localized: "Waiting for Ethereum…") : String(localized: "Waiting for Sepolia…")
        default: String(localized: "Send")
        }
    }

    /// One Activity row for the move, by its transaction: the eye-slash
    /// lead, the words with no verb, Etherscan its door.
    private func land(_ hash: String) {
        MovePrivateToast.land(hash, move: move, chrome: chrome, context: context)
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
        .frame(minHeight: DSFeed.headHeight)
        .animation(DS.Motion.standard, value: isOn)
    }
}

/// **A SEND THE SHEET LET GO OF (2026-11-27, user: "even if it was like a
/// toast that said each step").** The glass toast above the bar says where
/// it stands, step by step; done, the Activity row lands as the sheet's
/// would and the toast says it went; failed, its words, in amber.
@MainActor
enum MovePrivateToast {
    static func say(_ m: PrivateMove, chrome: ShellChrome, context: ModelContext) {
        // No trailing "…": in a toast it reads as words cut off (2026-11-27,
        // user: "should it say more after proving").
        switch m.stage {
        case .opening: chrome.flash(String(localized: "Confirm your private send with Face ID"), mark: "Privacy Pools", seconds: 600)
        case .preparing: chrome.flash(String(localized: "Preparing your private send"), mark: "Privacy Pools", seconds: 600)
        case .proving:
            chrome.flash(m.part.map { String(localized: "Proving send \($0.0) of \($0.1)") } ?? String(localized: "Proving your private send"),
                         mark: "Privacy Pools", seconds: 600)
        case .sending:
            chrome.flash(m.part.map { String(localized: "Sending \($0.0) of \($0.1) privately") } ?? String(localized: "Sending privately"),
                         mark: "Privacy Pools", seconds: 600)
        case .done(let hash):
            m.watcher = nil
            land(hash, move: m, chrome: chrome, context: context)
            chrome.flash(String(localized: "Sent from Privacy Pools"), tone: .success, mark: "Privacy Pools", seconds: 3)
        case .failed(let words):
            m.watcher = nil
            chrome.flash(words, tone: .failure, mark: "Privacy Pools", seconds: 8)
        default: break
        }
    }

    /// One Activity row for the move, by its transaction: the eye-slash
    /// lead, the words with no verb, Etherscan its door.
    static func land(_ hash: String, move: PrivateMove, chrome: ShellChrome, context: ModelContext) {
        // **NO TRANSACTION, NO ROW (prd §1988):** a deposit Ethereum named
        // no hash for wrote an empty row keyed on "", which every later one
        // was deduped against. Holdings shows its note by its commitment.
        guard !hash.isEmpty else { return }
        let figure = PrivateMoney.figure(PrivateMoney.baseUnits(move.amount, decimals: move.decimals) ?? "0",
                                         decimals: move.decimals, symbol: move.symbol)
        let title = PrivateMoney.activityTitle(figure: figure,
                                               to: move.mode == .send ? (move.tag.map(ZkMoneyWire.display) ?? move.recipient.map(YourAccount.short)) : nil)
        PrivateActivity.land(hash: hash, title: title, chainId: move.network.chainId, context: context)
        chrome.refreshRooms()
    }
}
