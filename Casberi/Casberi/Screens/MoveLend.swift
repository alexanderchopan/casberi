import SwiftUI

/// **LEND (prd §1674).** Move's verb for Aave, in Move's anatomy: the verbs
/// on their own line (`head`, Move's own, Lend bright), then
///
///     500 USDC
///     on Aave
///     on Base.
///
/// The amount and the network are pink words whose choices open under the
/// sentence; one grey line says what there is and Aave's rate today (never a
/// promise of what it pays); the act at the foot's trailing edge says each
/// stage. Taking back is the same sentence, "Take back 150 USDC from Aave on
/// Base.", reached from the line or from a lent row in Holdings.
struct MoveLendSentence<Head: View>: View {
    let move: LendMove
    let account: String
    var inTray = false
    /// The page's name over it (prd §1896); the verb word leads the sentence.
    var title: String = String(localized: "Earn")
    /// **TACIT EARNS (prd §1986):** its row opens Make private on Deposit and
    /// back to public on Withdraw, Tacit's own sheets.
    var tacit: ((LendMove.Mode) -> Void)? = nil
    /// **A DOOR, NOT A DEAD ROW (prd §2000):** a place you hold nothing for
    /// opens Swap to buy its token on its network.
    var swapFor: ((YourAccountOp.Token, Int) -> Void)? = nil
    @ViewBuilder let head: () -> Head

    @State private var open: Blank?
    /// Tacit's farm page, raised from a farm row (prd §1993).
    @State private var farmPage = false
    /// Every farm, past the first two (prd §2000).
    @State private var allFarms = false
    /// The cost's list stands in the rows' place (prd §1876).
    @Environment(\.openURL) private var openURL
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// `place` is To's list on Deposit (Aave, Olla, Tacit, the farms);
    /// `network` is From's (prd §1998).
    enum Blank { case amount, network, place }

    var body: some View {
        // **EARN IS A RECEIPT (prd §1931):** its name, Type · From · Amount,
        // what the open line asks, the foot. No sentence, no panel.
        // **EARN OPENS ON YOUR MONEY (prd §2000):** what is earning, then
        // where more could; a row opens the deck on it.
        Group {
            if move.home { homeDeck.transition(.opacity) } else { deck.transition(.opacity) }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // A word's choices make the sheet whole, and it stays whole (prd §1681b).
        .onChange(of: open) { _, now in if now != nil { chrome.moveTall = true } }
        // The deck opens on the keys once Aave is read: never an empty panel
        // under a sentence that asks how much (prd §1782).
        .onChange(of: live, initial: true) { _, on in
            if on, !move.home, open == nil, move.units == nil { withAnimation(DS.Motion.standard) { open = .amount } }
        }
        .onChange(of: chrome.moveTall) { _, tall in
            if !tall, open != nil { withAnimation(DS.Motion.standard) { open = nil } }
        }
        .task(id: account) {
            // Tacit's farms, beside the markets' read (prd §1993).
            if tacit != nil, TacitAccount.shared.connected {
                Task { await TacitAccount.shared.readFarmsIfStale() }
                // Tacit's rate, the last 30 days off its contract (prd §2002).
                Task { await TacitAccount.shared.readChainYield() }
            }
            await move.read(account: account)
            #if DEBUG
            NSLog("[Casberi] moveLend| %@ | %@ | %@ | %@", move.mode == .lend ? "lend" : "takeBack", move.figure,
                  move.network?.name ?? "-", rateLine ?? "no rate")
            #endif
        }
        .onChange(of: doneHash) { _, hash in
            if hash != nil { DSHaptic.success() }
        }
        // In the tray, a move goes behind it once Face ID has answered (prd §2003).
        .onAppear { move.onAway = inTray ? { chrome.moveTray = false } : nil }
        .sheet(isPresented: $farmPage) {
            DSWebSheet(url: TacitFarms.page) { farmPage = false }
        }
    }

    private var market: AaveLend.Market? { move.market }
    /// "4,583 stAZTEC": what a deposit to Olla mints at today's price.
    private var ollaYouGet: String? {
        guard market?.place == .olla, move.mode == .lend, let units = move.units, let rate = move.ollaRate,
              let shares = OllaStake.shares(forAssets: units, rate: rate).flatMap({ Decimal(string: $0) }) else { return nil }
        // Whole stAZTEC: a quote, never six places of false precision.
        var whole = shares / pow(10, 18), rounded = Decimal()
        NSDecimalRound(&rounded, &whole, 0, .plain)
        return "\(rounded.formatted(.number.precision(.fractionLength(0)))) stAZTEC"
    }
    /// Whether this market has anything to move: the empty line, else the facts.
    private var hasAny: Bool { (move.market.flatMap { move.available($0) }.flatMap { Decimal(string: $0) } ?? 0) > 0 }
    private var live: Bool { move.stage == .ready }
    private var doneHash: String? { if case .done(let h) = move.stage { h } else { nil } }
    private var rateLine: String? { market.flatMap { AaveLend.rateLine(move.rates[LendMove.key($0)]) } }

    // MARK: - The sentence

    @ViewBuilder private var sentence: some View {
        if move.stage == .reading {
            MovePhrase(String(localized: "Reading…"), ink: DS.textSecondary)
        } else {
            let done = doneHash != nil
            let glue: String = switch (move.mode, done) {
            // **EARN SAYS EARN (prd §1901, the user: "you have 'lend' on the
            // screen but it is now Earn").**
            case (.lend, false): String(localized: "Earn with")
            case (.lend, true): String(localized: "Earning with")
            case (.takeBack, false): String(localized: "Take back")
            case (.takeBack, true): String(localized: "Took back")
            }
            // "Lend" and "Take back" are Move's verb word (`head`, prd §1681),
            // which opens the verbs; done, the past tense stands in its place.
            if !done { head() }
            MoveClause(glue: done ? glue : nil) {
                // **NEVER "0 USDC" BEFORE A FIGURE (prd §1916):** the amount
                // still to type is a grey "an amount of USDC", as Send's is.
                let unset = move.units == nil && !move.all && !done
                Button { toggle(.amount) } label: {
                    MoveWord(unset ? String(localized: "an amount of \(move.market?.symbol ?? "")") : move.figure,
                             ink: unset ? DS.textTertiary : MoveSentence.settledInk)
                }
                .buttonStyle(RowPress())
                .accessibilityLabel(Text("Amount, \(move.figure)"))
                .accessibilityHint(Text("Picks how much"))
            }
            // One "on" (prd §1800): "Earn with 100 USDC on Base." Aave is a
            // fact, "Through" (prd §1901).
            MoveClause(glue: String(localized: "on")) {
                Button { toggle(.network) } label: {
                    MoveWord((move.network?.name ?? "") + ".", ink: MoveSentence.settledInk)
                }
                .buttonStyle(RowPress())
                .accessibilityLabel(Text("On \(move.network?.name ?? ""), change"))
            }
        }
    }

    // MARK: - The line

    /// What there is and the rate today; or what went wrong; or where it went.
    @ViewBuilder private var line: some View {
        switch move.stage {
        case .ready, .working:
            // The sentence stands alone while the steps run in the foot (prd §1700z).
            if stepsRun == nil {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if let market {
                    // What you have and Half · All are the amount's own
                    // menu (prd §1802); Aave's rate is the cost line's.
                    if !hasAny {
                        Text(move.mode == .lend ? String(localized: "No \(market.symbol) on \(market.network) to earn with")
                             : String(localized: "Nothing earning on \(market.network)"))
                            .dsText(.body17).foregroundStyle(DS.textTertiary)
                    } else if move.ollaUnderMinimum {
                        Text("Olla takes back 100 stAZTEC or more")
                            .dsText(.body17).foregroundStyle(DS.attentionInk)
                    } else if move.mode == .lend {
                        // **THE AUDIT GAP, SAID ONCE (prd §1970):** Olla's own docs
                        // say its live StakingManager carries an unaudited change;
                        // its day to take back is a fact now (prd §2000). Aave
                        // says where its rate comes from, and that it moves.
                        DSFootnote(prose: market.place == .olla ? String(localized: "Olla's latest contract change isn't covered by its audit.")
                                   : String(localized: "Aave lends it to borrowers; that is where the rate comes from, and it moves."))
                    }
                }
            }
            }
        case .failed(let words):
            // A failure the rows carry is said once, on its step.
            if stepsRun == nil {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text(verbatim: words).dsText(.body17).foregroundStyle(DS.attentionInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .done(let hash):
            if hash.isEmpty {
                Text("On its way to \(move.network?.name ?? "")").dsText(.body17).foregroundStyle(DS.textSecondary)
            } else if let link = explorer(hash) {
                Button { openURL(link.url) } label: {
                    Text("View on \(link.name)").dsText(.body17).foregroundStyle(DS.pickInk).frame(minHeight: 44)
                }
                .buttonStyle(RowPress())
            }
        case .reading:
            EmptyView()
        }
    }

    /// What lending earns today, or where taking back lands: a fact (prd §1896).
    private var rateFact: (name: String, value: String)? {
        let olla = market?.place == .olla
        switch move.mode {
        // **OLLA'S RATE IS WHAT IT EARNED (prd §1970):** the share price over
        // the last 30 days, a year's worth, never a promise.
        case .lend where olla:
            return market.flatMap { AaveLend.rateOnly(move.rates[LendMove.key($0)]) }
                .map { (String(localized: "Earned"), String(localized: "about \($0) a year, last 30 days")) }
        case .lend:
            return market.flatMap { AaveLend.rateOnly(move.rates[LendMove.key($0)]) }
                .map { (String(localized: "Earns"), String(localized: "\($0) today")) }
        case .takeBack where olla && move.claims: return (String(localized: "Status"), String(localized: "Ready to claim"))
        case .takeBack where olla: return (String(localized: "Arrives"), String(localized: "in about a day"))
        case .takeBack: return (String(localized: "Arrives"), String(localized: "in your account at once"))
        }
    }

    private func flip(_ mode: LendMove.Mode) {
        withAnimation(DS.Motion.standard) {
            move.mode = mode
            move.pick(nil, all: false)
            move.settle()
            // The amount was cleared, so the keys ask it, as Deposit's open
            // does (user, 2026-11-21: Withdraw opened on an empty "0 USDC").
            if live { open = .amount }
        }
        DSHaptic.selection()
    }

    /// The transaction on its own network's explorer, the hosts Move's own
    /// receipt links (`MoveSentence.explorer`); a network with none draws no
    /// link, never another network's explorer (prd §1988: anything not
    /// Ethereum was sent to Basescan).
    private func explorer(_ hash: String) -> (name: String, url: URL)? {
        let name: String, host: String
        switch move.chainId {
        case 1: (name, host) = ("Etherscan", "etherscan.io")
        case 8453: (name, host) = ("Basescan", "basescan.org")
        case 4663: (name, host) = ("Blockscout", "robinhoodchain.blockscout.com")
        case 84532: (name, host) = ("Basescan", "sepolia.basescan.org")
        default: return nil
        }
        return URL(string: "https://\(host)/tx/\(hash)").map { (name, $0) }
    }

    // MARK: - The blanks' choices

    private func toggle(_ blank: Blank) {
        guard live, !(blank == .amount && move.claims) else { return }
        withAnimation(DS.Motion.standard) { open = open == blank ? nil : blank }
        DSHaptic.selection()
    }

    // MARK: - The foot

    /// This sentence's own send, while it works, failed or done (prd §1700z).
    private var stepsRun: PrivateSendSteps.Run? {
        guard let run = PrivateSendSteps.shared.run, run.kind == .move, run.plan == move.plan else { return nil }
        switch move.stage {
        case .working: return run
        case .failed: return run.ok == false ? run : nil
        case .done: return run.ok == true ? run : nil
        default: return nil
        }
    }

    @Environment(\.moveBack) private var back

    /// **EARN'S DECK (prd §1901 items 1–3, §1911):** Earn · Take back as
    /// chips over From · Amount on Home's panel, the foot's word held to act.
    private var deck: some View {
        // **THE RECEIPT'S PAGE, EVERY VERB'S (prd §1992):** Earn drew its own
        // copy of `MoveReceiptDeck` for its title; the title is now the
        // deck's `header`.
        MoveReceiptDeck(title: title, inTray: inTray, backDisabled: move.acting, back: {
            withAnimation(DS.Motion.standard) {
                // Back is Earn's home, never the step before (prd §1911,
                // §2000); opened on one position, there is none: the menu.
                if move.onRow { open = nil; back?() } else { goHome() }
            }
        }, header: doneHash == nil ? AnyView(kindTitle) : nil, lines: {
            if move.stage == .reading {
                // **READING DRAWS THE PAGE, EMPTY (prd §2000, §769):** the
                // lines it will fill, their chips unfilled, no act.
                VStack(alignment: .leading, spacing: MoveReceipt.gap) {
                    ForEach(Array([(String(localized: "To"), 96.0), (String(localized: "From"), 148.0), (String(localized: "Amount"), 84.0)].enumerated()), id: \.offset) { _, line in
                        MoveReceiptLine(label: line.0) {
                            Capsule().fill(DS.fillFaint).frame(width: line.1, height: MoveReceipt.chipHeight)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Reading your balances and today's rates"))
            } else {
                receiptLines
            }
        }, content: {
            Group {
                if open == .amount {
                    // **BIG KEYS, AT THE SAME HEIGHT AS SEND'S (prd §1931).**
                    MoveDeckKeys {
                        // The quick shares are the keys' top row (prd §1932).
                        if canUseAll {
                            MoveQuickKeys(keys: MoveQuickKeys.shares.map { p in
                                MoveQuickKeys.Key.share(p, on: p == 100 && move.all) { pickShare(p) }
                            }, disabled: !live)
                        }
                        MoveKeypad(text: typed, places: min(move.market?.decimals ?? 6, 6), disabled: !live,
                                   keyHeight: MoveSentence.bigKeyHeight, big: true)
                    }
                } else if open == .network {
                    MoveDeckScroll { fromRows }
                } else if open == .place {
                    MoveDeckScroll { placeRows }
                } else {
                    // **THE RECEIPT IS THE DECK'S (prd §1927, §1929):** the
                    // facts under the steps, never between the sentence
                    // and the plate.
                    MoveDeckScroll { receipt }
                }
            }
        }, word: { footWord })
        .animation(DS.Motion.standard, value: open)
    }

    /// **TO · FROM · AMOUNT (prd §1931, §1998).** Deposit and Withdraw in the
    /// title (user: "instead of an earn pill it could be deposit and instead of
    /// take back it could be withdraw"), the place on To (From, withdrawing),
    /// the token on From, the figure and its quick shares on Amount.
    private var receiptLines: some View {
        VStack(alignment: .leading, spacing: MoveReceipt.gap) {
            // **TO PICKS THE PLACE (prd §1998; user, 2026-11-27: "aave isn't
            // tappable. the earn places come up when i click from").**
            // Depositing, To is where it earns, a choice under Public and
            // Private; From is your token, its network in words. Withdrawing,
            // the place is where the money comes from, so From holds it and
            // To is your public account.
            if move.mode == .lend {
                if let m = market {
                    MoveReceiptLine(label: String(localized: "To")) {
                        MoveChip(text: String(localized: "\(m.placeName) · Public"), mark: MoveRowMark(token: m.placeName),
                                 tone: open == .place ? .open : .answered, disabled: !live) { toggle(.place) }
                    }
                }
                fromLine
            } else {
                fromLine
                if market != nil {
                    // Nothing to pick: words, never a chip that looks tappable (prd §2000).
                    MoveReceiptLine(label: String(localized: "To")) {
                        Text("Your public account").dsText(.body17).foregroundStyle(DS.textPrimary)
                            .frame(minHeight: MoveReceipt.chipHeight)
                    }
                }
            }
            MoveReceiptLine(label: String(localized: "Amount")) {
                // While typing, the field shows what was typed (2026-11-27):
                // `figure` rounds, so "0." and "0.000" drew "0".
                let typedShown = open == .amount && !move.all && !move.claims
                    ? move.amount.flatMap { $0.isEmpty ? nil : "\(MoveSentence.grouped($0)) \(move.market?.symbol ?? move.symbol)" }
                    : nil
                MoveChip(text: typedShown ?? move.figure, tone: open == .amount ? .open : (move.units == nil ? .empty : .answered),
                         caret: open == .amount, disabled: !live, placeholder: typedShown == nil && move.units == nil) { toggle(.amount) }
            }
            // What the figure means, under the field (prd §1989).
            if open == .amount, let m = market,
               let n = MoveFieldNote.against(typed: typed.wrappedValue,
                                             have: MoveFieldNote.plain(units: move.available(m), decimals: m.decimals),
                                             symbol: m.symbol) {
                MoveFieldNote(text: n.text, ink: n.ink)
            }
        }
    }

    /// From: the token and its network, in words.
    private var fromLine: some View {
        MoveReceiptLine(label: String(localized: "From")) {
            if let m = market {
                MoveChip(text: "\(m.symbol) · \(move.network?.name ?? m.network)",
                         mark: MoveRowMark(token: m.symbol, network: MoveSentence.networkMark(chainId: m.chainId)),
                         tone: open == .network ? .open : .answered, disabled: !live) { toggle(.network) }
            } else {
                MoveChip(text: String(localized: "Choose"), tone: .empty, disabled: !live) { toggle(.network) }
            }
        }
    }

    /// A share of what there is: All is every unit, as Use all was.
    private func pickShare(_ p: Int) {
        guard let m = market, let have = move.available(m).flatMap({ Decimal(string: $0) }) else { return }
        if p == 100 {
            move.pick(nil, all: true)
            return
        }
        var raw = have * Decimal(p) / 100 / pow(10, m.decimals)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, min(m.decimals, 6), .down)
        move.pick(NSDecimalNumber(decimal: rounded).stringValue, all: false)
    }

    /// What the move does, how much it earns, who carries it and the cost.
    @ViewBuilder private var receipt: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if let run = stepsRun {
                PrivateStepRows(run: run).transition(.opacity)
            }
            // **READY IS THE RECEIPT, AS SEND'S AND SWAP'S (prd §1932; user,
            // 2026-11-21: "fix earn's ready screen").** Each fact's word in
            // the label column, its value where the chips' words start: what
            // there is, the rate, who carries it, the fee. The fee is a plain
            // fact: its one part (gas) said again behind a door, rounded
            // another way ("under $0.01" over "about $0.00"), told nothing.
            if live, stepsRun == nil {
                VStack(alignment: .leading, spacing: MoveReceipt.gap) {
                    // Claiming is not earning: the figure is the Amount's own.
                    if hasAny, !move.claims, let have = move.haveFigure {
                        MoveReceiptFact(label: move.mode == .lend ? String(localized: "You have") : String(localized: "Earning"),
                                        value: have)
                    }
                    if let get = ollaYouGet {
                        MoveReceiptFact(label: String(localized: "You get"), value: get)
                    }
                    // **WHAT IT EARNED, WITHDRAWING (prd §2000):** above what went
                    // in, since this phone first read it; and the rate it earns.
                    if hasAny, move.mode == .takeBack, !move.claims, let m = market {
                        if let e = move.earned(m), let usd = move.dollars(e.units, in: m), usd >= 0.005 {
                            MoveReceiptFact(label: String(localized: "Earned"),
                                            value: String(localized: "\(LendMove.usd(usd)) since \(e.since.formatted(.dateTime.month(.abbreviated).day()))"))
                        }
                        if m.place == .aave, let rate = AaveLend.rateOnly(move.rates[LendMove.key(m)]) {
                            MoveReceiptFact(label: String(localized: "Earns"), value: String(localized: "\(rate) today"))
                        }
                    }
                    if hasAny, let fact = rateFact {
                        MoveReceiptFact(label: fact.name, value: fact.value)
                    }
                    // **WHAT A YEAR WOULD BRING, AND HOW IT COMES BACK (prd
                    // §2000):** the amount at today's rate, a figure and never
                    // a promise; Olla's rate is the last 30 days'.
                    if hasAny, move.mode == .lend, let m = market {
                        if let units = move.units, let year = move.yearly(units, in: m), year >= 0.01 {
                            MoveReceiptFact(label: String(localized: "In a year"),
                                            value: m.place == .olla ? String(localized: "about \(LendMove.usd(year)), at the last 30 days' rate")
                                                : String(localized: "about \(LendMove.usd(year)), at today's rate"))
                        }
                        MoveReceiptFact(label: String(localized: "Take back"),
                                        value: m.place == .olla ? String(localized: "in about a day") : String(localized: "any time, at once"))
                    }
                    if market?.place == .olla, move.mode == .takeBack, !move.claims, hasAny {
                        MoveReceiptFact(label: String(localized: "Then"), value: String(localized: "Claim it here, we'll tell you"))
                    }
                    if market?.place == .olla, move.mode == .takeBack, !move.ollaWaiting.isEmpty, let m = market {
                        MoveReceiptFact(label: String(localized: "On its way"),
                                        value: PrivateMoney.figure(move.ollaBack(ready: false), decimals: m.decimals, symbol: m.symbol))
                    }
                    if move.units != nil, let cost = move.cost {
                        MoveReceiptFact(label: String(localized: "Fee"), value: cost.amount)
                    }
                }
                .transition(.opacity)
            }
            line
        }
    }

    /// The keypad's figure: what was typed, or all of it written out.
    private var typed: Binding<String> {
        Binding(get: {
            guard move.all, let m = move.market, let units = move.units, let u = Decimal(string: units) else { return move.amount ?? "" }
            // At the keys' places, rounded down; `all` still moves every unit
            // (the review of 2026-11-27: Max drawn longer than the keys read
            // as more than you have).
            var whole = u / pow(10, m.decimals), cut = Decimal()
            NSDecimalRound(&cut, &whole, min(m.decimals, 6), .down)
            return NSDecimalNumber(decimal: cut).stringValue
        }, set: { text in
            move.pick(text.isEmpty ? nil : text, all: false)
        })
    }

    /// There is something to use all of.
    private var canUseAll: Bool {
        (move.market.flatMap { move.available($0) }.flatMap { Decimal(string: $0) } ?? 0) > 0
    }

    /// The markets Earn offers: not refused, and Olla only to someone with
    /// AZTEC or something there (prd §1970).
    private var offered: [AaveLend.Market] {
        AaveLend.markets.filter { m in
            !move.refused.contains(LendMove.key(m))
                && (m.place != .olla || (Decimal(string: move.available(m) ?? "0") ?? 0) > 0 || move.anyOlla)
        }
    }

    /// What a market's amount is worth in dollars, nil with no price.
    private func worth(_ m: AaveLend.Market) -> Double? { move.available(m).flatMap { move.dollars($0, in: m) } }

    /// One market as From's row: the token, its network in words, its rate
    /// today (prd §1958, §1972), what there is trailing. One with nothing is
    /// dimmed, never hidden.
    private func choice(_ m: AaveLend.Market) -> MoveTokenChoice {
        let name = YourAccountOp.networks.first { $0.chainId == m.chainId }?.name ?? m.network
        let have = move.available(m).flatMap { Decimal(string: $0) } ?? 0
        return MoveTokenChoice(id: LendMove.key(m), symbol: m.symbol, network: name,
                               sub: worth(m).map { MoveSentence.money($0, whole: true) } ?? PrivateMoney.figure(move.available(m) ?? "0", decimals: m.decimals, symbol: ""),
                               rate: AaveLend.rateOnly(move.rates[LendMove.key(m)]),
                               picked: m.chainId == move.chainId && m.symbol == move.symbol, dim: have <= 0) {
            withAnimation(DS.Motion.standard) {
                move.chainId = m.chainId
                move.symbol = m.symbol
                move.pick(nil, all: false)
                move.settle()
                open = .amount
            }
        }
    }

    /// **FROM (prd §1998, amending §1972's place on the row).** Depositing,
    /// the tokens the place in To takes, from your public account, by worth.
    /// Withdrawing, every place under Public or Private, its name a grey
    /// head, as Holdings groups money (§1985): Aave, Olla and the farms you
    /// are in under Public, Tacit's private TAC under Private.
    private var fromRows: some View {
        let byWorth: (AaveLend.Market, AaveLend.Market) -> Bool = { (worth($0) ?? 0) > (worth($1) ?? 0) }
        if move.mode == .lend {
            let here = offered.filter { $0.place == market?.place }.sorted(by: byWorth)
            return MoveTokenGrid(places: [MoveTokenPlace(id: "lend", choices: here.map(choice))])
        }
        let aave = offered.filter { $0.place == .aave }.sorted(by: byWorth)
        let olla = offered.filter { $0.place == .olla }
        var places = [MoveTokenPlace(id: "aave", title: "Aave", group: String(localized: "Public"), choices: aave.map(choice))]
        places.append(MoveTokenPlace(id: "olla", title: "Olla", group: String(localized: "Public"), choices: olla.map(choice)))
        places += farmPlace
        places.append(MoveTokenPlace(id: "tacit", title: "Tacit", group: String(localized: "Private"), choices: tacitChoice))
        return MoveTokenGrid(places: places)
    }

    /// **TO, DEPOSITING (prd §1998).** Where the money earns, under Public
    /// and Private: Aave and Olla hold it in the open from your public
    /// account, the farms are Tacit's pools on Ethereum, and Tacit's TAC
    /// earns private. Each names what it takes and its rate today, and
    /// trails what you have for it, or the way to get some (prd §2000).
    private var placeRows: some View {
        var places = [MoveTokenPlace(id: "places", group: String(localized: "Public"), choices: publicPlaces)]
        places += farmPlace
        places.append(MoveTokenPlace(id: "tacit", group: String(localized: "Private"), choices: tacitChoice))
        return MoveTokenGrid(places: places)
    }

    /// Aave and Olla as places: every market not refused, Olla too when you
    /// hold no AZTEC, since its row is now the way to buy some (prd §2000).
    private var publicPlaces: [MoveTokenChoice] {
        let markets = AaveLend.markets.filter { !move.refused.contains(LendMove.key($0)) }
        let aave = markets.filter { $0.place == .aave }, olla = markets.filter { $0.place == .olla }
        return (aave.isEmpty ? [] : [placeChoice("Aave", aave)]) + (olla.isEmpty ? [] : [placeChoice("Olla", olla)])
    }

    /// The token a market takes, to buy where there is none.
    private func token(_ m: AaveLend.Market) -> YourAccountOp.Token {
        m.native ? YourAccountOp.eth : YourAccountOp.Token(symbol: m.symbol, decimals: m.decimals, contract: m.asset)
    }

    /// One place on To's list: its markets' tokens and rates, what you have
    /// for it in dollars; picked, its richest market with something to move.
    /// Holding none of what it takes, "Swap for it" opens Swap to buy its
    /// first token there (prd §2000), never a dimmed row.
    private func placeChoice(_ name: String, _ ms: [AaveLend.Market]) -> MoveTokenChoice {
        var tokens: [String] = []
        for m in ms where !tokens.contains(m.symbol) { tokens.append(m.symbol) }
        let networks = ms.reduce(into: [String]()) { out, m in
            let n = YourAccountOp.networks.first { $0.chainId == m.chainId }?.name ?? m.network
            if !out.contains(n) { out.append(n) }
        }
        let usd = ms.compactMap(worth).reduce(0, +)
        let has = ms.filter { (Decimal(string: move.available($0) ?? "0") ?? 0) > 0 }
        let line = [tokens.joined(separator: ", "), Self.rateSpan(ms.compactMap { move.rates[LendMove.key($0)] })]
            .compactMap { $0 }.joined(separator: " · ")
        let buys = has.isEmpty && swapFor != nil && move.mode == .lend
        return MoveTokenChoice(id: "place|\(name)", symbol: name, network: networks.joined(separator: ", "),
                               sub: usd > 0 ? MoveSentence.money(usd, whole: true) : nil, line: line,
                               picked: !move.home && market?.placeName == name, dim: has.isEmpty && !buys,
                               door: buys ? String(localized: "Swap for it") : nil) {
            if buys {
                swapFor?(token(ms[0]), ms[0].chainId)
            } else {
                enter(.lend, place: has)
            }
        }
    }

    /// **INTO THE DECK (prd §2000).** From Earn's home or To's list: the
    /// mode, the place's richest market with something to move (the one in
    /// hand if it is one), and From open when there is more than one.
    private func enter(_ mode: LendMove.Mode, place has: [AaveLend.Market]) {
        withAnimation(DS.Motion.standard) {
            move.mode = mode
            if let pick = (has.first { $0.chainId == move.chainId && $0.symbol == move.symbol })
                ?? has.max(by: { (worth($0) ?? 0) < (worth($1) ?? 0) }) {
                move.chainId = pick.chainId
                move.symbol = pick.symbol
            }
            move.pick(nil, all: false)
            move.home = false
            open = has.count > 1 ? .network : .amount
        }
        DSHaptic.selection()
    }

    /// "1.4–5.1%", or "5.1%" when the rates round alike: the facts, no
    /// "best" (prd §1958 item 2).
    static func rateSpan(_ apys: [Double]) -> String? {
        guard let lo = apys.min(), let hi = apys.max(), let top = AaveLend.rateOnly(hi) else { return nil }
        guard let low = AaveLend.rateOnly(lo), low != top else { return top }
        return "\(low.dropLast())–\(top)"
    }

    /// **TACIT'S FARMS (prd §1993; user, 2026-11-26: "Farms in Earn").**
    /// Each pool Tacit pays TAC to, at the rate its own pools price, highest
    /// first; Withdraw lists the ones you are in. A farm is entered and left
    /// on Tacit's own page, so a row opens it: Casberi reads, Tacit moves.
    /// Shown while a Tacit account is connected, as Tacit's own row (§1986),
    /// under Public: the farms are pools on Ethereum (prd §1998).
    private var farmPlace: [MoveTokenPlace] {
        let tacit = TacitAccount.shared
        guard self.tacit != nil, tacit.connected, let farms = tacit.farms else { return [] }
        let mine = tacit.reading?.farmed ?? []
        let pools = farms.pools
            .filter { p in move.mode == .lend || mine.contains { $0.lpAsset == p.lpAsset } }
            .sorted { (TacitFarms.rate($0, in: farms) ?? 0) > (TacitFarms.rate($1, in: farms) ?? 0) }
        let choices = pools.map { p in
            let held = mine.first { $0.lpAsset == p.lpAsset }
            return MoveTokenChoice(id: "farm|\(p.lpAsset)", symbol: TacitFarms.name(p.pair), network: String(localized: "Ethereum"),
                                   sub: held.flatMap { tacit.farmUSD($0) }.map { MoveSentence.money($0, whole: true) },
                                   rate: TacitFarms.rateWords(TacitFarms.rate(p, in: farms))) {
                farmPage = true
            }
        }
        let day = farms.endsAt.formatted(.dateTime.month(.abbreviated).day())
        // **THE RULE IS THE HEAD (prd §2000):** when, and where you join,
        // in the grey head; two pools, the rest a tap away.
        let title = farms.active && farms.endsAt > .now
            ? String(localized: "Tacit farms · until \(day), on Tacit's site")
            : String(localized: "Tacit farms · ended \(day)")
        let folded = !allFarms && choices.count > 3
        return [MoveTokenPlace(id: "tacit-farms", title: title, group: String(localized: "Public"),
                               choices: folded ? Array(choices.prefix(2)) : choices,
                               more: folded ? (words: String(localized: "\(choices.count - 2) more pools"), act: { allFarms = true }) : nil)]
    }

    /// **TACIT (prd §1986), UNDER PRIVATE (prd §1998).** Private TAC earns a
    /// share of the Tacit chain's fees: Deposit is Make private (your public
    /// TAC), Withdraw is back to public (your private TAC). Its rate is what
    /// a share earned over the marks this phone kept (prd §1999, user:
    /// "for the main tacit it should say the earn rate"), none under a day
    /// of them. Shown while a Tacit account is connected, dimmed when empty
    /// (§1984).
    private var tacitChoice: [MoveTokenChoice] {
        guard let tacit, TacitAccount.shared.connected, let r = TacitAccount.shared.reading else { return [] }
        let held = move.mode == .lend ? (r.accountTAC ?? 0) + (r.publicTAC ?? 0) : (r.privateTAC ?? 0)
        let usd = TacitAccount.shared.tacPrice.map { held * $0 }
        let mode = move.mode
        let rate = AaveLend.rateOnly(TacitAccount.shared.earnRate(r))
        // No public TAC to make private: the row buys some (prd §2000).
        let buys = mode == .lend && held <= 0 && swapFor != nil
        return [MoveTokenChoice(id: "tacit|TAC", symbol: mode == .lend ? "Tacit" : "TAC", network: String(localized: "Tacit chain"),
                                sub: buys ? nil : usd.map { MoveSentence.money($0, whole: true) } ?? "\(TacitAccountRows.amount(held)) TAC",
                                line: mode == .lend ? (["TAC", rate].compactMap { $0 }.joined(separator: " · "))
                                    : ([String(localized: "Tacit chain"), rate].compactMap { $0 }.joined(separator: " · ")),
                                dim: held <= 0 && !buys, door: buys ? String(localized: "Swap for it") : nil) {
            if buys, let tac = YourAccountTokens.appTokens[1]?.first?.token {
                swapFor?(tac, 1)
            } else {
                tacit(mode)
            }
        }]
    }

    // MARK: - Earn's home (prd §2000)

    /// **EARN OPENS ON YOUR MONEY (prd §2000).** What is earning and what a
    /// year of it comes to at today's rates; then each position, a door to
    /// Withdraw; then where more could earn, a door to Deposit. No act in the
    /// foot: every row is one.
    private var homeDeck: some View {
        MoveReceiptDeck(title: title, inTray: inTray, back: {
            withAnimation(DS.Motion.standard) { back?() }
        }, header: AnyView(kindTitle), lines: {
            homeHead
        }, content: {
            MoveDeckScroll {
                MoveTokenGrid(places: [
                    MoveTokenPlace(id: "earning", title: String(localized: "Earning"), choices: earningRows.map(\.choice)),
                    // **READY TO EARN (prd §2001; user: "earn more shows what i
                    // am earning too doesn't it?"):** what you hold that a
                    // place takes and is not in yet.
                    MoveTokenPlace(id: "more", title: String(localized: "Ready to earn"), choices: moreRows),
                ])
            }
        }, word: { EmptyView() })
    }

    @ViewBuilder private var homeHead: some View {
        if move.readFor == nil {
            // Reading: the figure's place, empty (prd §769).
            Capsule().fill(DS.fillFaint).frame(width: 140, height: 52)
                .accessibilityLabel(Text("Reading what is earning"))
        } else {
            let rows = earningRows
            let total = rows.compactMap(\.usd).reduce(0, +)
            let year = rows.compactMap(\.year).reduce(0, +)
            let earned = rows.compactMap(\.earned).reduce(0, +)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(verbatim: MoveSentence.money(total, whole: true))
                    .dsText(.price52).monospacedDigit().foregroundStyle(DS.textPrimary)
                    .contentTransition(.numericText())
                Text(rows.isEmpty ? String(localized: "Nothing earning yet")
                     : year >= 1 ? String(localized: "Earning about \(MoveSentence.money(year, whole: true)) a year at today's rates")
                     : year > 0 ? String(localized: "Earning about \(LendMove.usd(year)) a year at today's rates")
                     : String(localized: "Earning at today's rates"))
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
                // What it earned, said once under the head: on each row it
                // pushed the line past the row (user, 2026-11-27: "clipping").
                if earned >= 0.005 {
                    Text("Earned \(LendMove.usd(earned)) so far").dsText(.body17).foregroundStyle(DS.textSecondary)
                }
            }
        }
    }

    private struct Earning {
        let choice: MoveTokenChoice
        let usd: Double?
        let year: Double?
        /// Dollars earned above what went in (prd §2000).
        let earned: Double?
    }

    /// Each position earning: Aave's and Olla's markets with something lent,
    /// and Tacit's private TAC. Its line says where, the rate, and what it
    /// earned since this phone first read it; a tap opens Withdraw on it.
    private var earningRows: [Earning] {
        var out: [Earning] = []
        for m in AaveLend.markets {
            let key = LendMove.key(m)
            guard let units = move.lent[key], (Decimal(string: units) ?? 0) > 0 else { continue }
            let net = YourAccountOp.networks.first { $0.chainId == m.chainId }?.name ?? m.network
            let earned = move.earned(m).flatMap { move.dollars($0.units, in: m) }
            let usd = move.dollars(units, in: m)
            let line = [m.placeName, net, AaveLend.rateOnly(move.rates[key])].compactMap { $0 }.joined(separator: " · ")
            out.append(Earning(choice: MoveTokenChoice(id: "earning|\(key)", symbol: m.symbol, network: net,
                                                       sub: usd.map { MoveSentence.money($0, whole: true) }
                                                           ?? PrivateMoney.figure(units, decimals: m.decimals, symbol: ""),
                                                       line: line) { withdraw(m) },
                               usd: usd, year: move.yearly(units, in: m), earned: earned))
        }
        if let tacit, TacitAccount.shared.connected, let r = TacitAccount.shared.reading, let held = r.privateTAC, held > 0 {
            let price = TacitAccount.shared.tacPrice
            let apy = TacitAccount.shared.earnRate(r)
            let earned = r.earnedTAC.flatMap { e in price.map { e * $0 } }
            let usd = price.map { held * $0 }
            let line = ["Tacit", String(localized: "Private"), AaveLend.rateOnly(apy)].compactMap { $0 }.joined(separator: " · ")
            out.append(Earning(choice: MoveTokenChoice(id: "earning|tacit", symbol: "TAC", network: String(localized: "Tacit chain"),
                                                       sub: usd.map { MoveSentence.money($0, whole: true) } ?? "\(TacitAccountRows.amount(held)) TAC",
                                                       line: line) { tacit(.takeBack) },
                               usd: usd, year: usd.flatMap { u in apy.map { u * $0 } }, earned: earned))
        }
        return out.sorted { ($0.usd ?? 0) > ($1.usd ?? 0) }
    }

    /// Where more could earn: Aave and Olla, Tacit, and Tacit's farms as one
    /// row that opens To's list on them.
    private var moreRows: [MoveTokenChoice] {
        var rows = publicPlaces + tacitChoice
        if self.tacit != nil, TacitAccount.shared.connected, let farms = TacitAccount.shared.farms, !farms.pools.isEmpty {
            let rates = farms.pools.compactMap { TacitFarms.rate($0, in: farms) }
            let day = farms.endsAt.formatted(.dateTime.month(.abbreviated).day())
            let live = farms.active && farms.endsAt > .now
            // One line, no more (user, 2026-11-27: "clipping"): the rates;
            // the day stands in To's head for the farms.
            let line = live ? (Self.farmSpan(rates) ?? "") : String(localized: "ended \(day)")
            rows.append(MoveTokenChoice(id: "farms", symbol: String(localized: "Tacit farms"), network: String(localized: "Ethereum"),
                                        line: line) {
                withAnimation(DS.Motion.standard) {
                    move.mode = .lend
                    move.home = false
                    open = .place
                }
                DSHaptic.selection()
            })
        }
        return rows
    }

    /// The farms' rates, low to high, in Tacit's own words.
    static func farmSpan(_ rates: [Double]) -> String? {
        guard let lo = rates.min(), let hi = rates.max(), let top = TacitFarms.rateWords(hi) else { return nil }
        guard let low = TacitFarms.rateWords(lo), low != top else { return top }
        return "\(low.dropLast())–\(top)"
    }

    /// Withdraw, opened on one position.
    private func withdraw(_ m: AaveLend.Market) {
        withAnimation(DS.Motion.standard) {
            move.mode = .takeBack
            move.chainId = m.chainId
            move.symbol = m.symbol
            move.pick(nil, all: false)
            move.home = false
            open = .amount
        }
        DSHaptic.selection()
    }

    /// Face ID has the act.
    private var signing: Bool { if case .working(.signing) = move.stage { true } else { false } }

    /// **EARN · DEPOSIT · WITHDRAW (prd §2001; user, 2026-11-27: "in the
    /// title we should still show deposit and withdraw … kinda like how we
    /// have gift cards and tokens besides themselves in buy").** The page you
    /// are on in white, the others grey, a tap switches; always drawn, so
    /// the two verbs are named before either is picked. Earn leads, the
    /// verbs after it in the order you do them, not A–Z (amends §1934).
    private var kindTitle: some View {
        MoveKindTitle(kinds: [
            MoveKindTitle.Kind(id: "home", word: String(localized: "Earn"), on: move.home) { goHome() },
            MoveKindTitle.Kind(id: "lend", word: String(localized: "Deposit"), on: !move.home && move.mode == .lend) { kind(.lend) },
            MoveKindTitle.Kind(id: "takeBack", word: String(localized: "Withdraw"), on: !move.home && move.mode == .takeBack) { kind(.takeBack) },
        ], disabled: move.acting)
    }

    /// Earn's home again: Deposit is where a deck opens from it next.
    private func goHome() {
        withAnimation(DS.Motion.standard) {
            open = nil
            move.mode = .lend
            move.pick(nil, all: false)
            move.home = true
        }
    }

    /// Deposit or Withdraw from the title: on the deck, the other kind; from
    /// the home, the richest market with something to move that way.
    private func kind(_ mode: LendMove.Mode) {
        guard move.home else { flip(mode); return }
        move.mode = mode
        let has = AaveLend.markets.filter {
            !move.refused.contains(LendMove.key($0)) && (Decimal(string: move.available($0) ?? "0") ?? 0) > 0
        }
        // **TACIT TOO (prd §2005):** where Tacit holds more that way than any
        // market, its own sheet opens: Make private, or back to public.
        let richest = has.compactMap(worth).max() ?? 0
        if let tacit, TacitAccount.shared.connected, let r = TacitAccount.shared.reading, let price = TacitAccount.shared.tacPrice {
            let held = mode == .lend ? (r.accountTAC ?? 0) + (r.publicTAC ?? 0) : (r.privateTAC ?? 0)
            if held * price > richest, held > 0 {
                move.mode = .lend
                tacit(mode)
                return
            }
        }
        enter(mode, place: has)
    }

    /// From (the network), Amount.
    private var steps: [MoveDeckStep] {
        [MoveDeckStep(id: "from", word: String(localized: "From"), on: open == .network, answered: hasAny) {
            toggle(.network)
        },
         MoveDeckStep(id: "amount", word: String(localized: "Amount"), on: open == .amount, answered: move.units != nil) {
            toggle(.amount)
        }]
    }

    /// **THE FOOT'S ONE WORD (prd §1897 item 7):** Hold to earn, Hold to take
    /// back; the stage while it works; Done or Try again after.
    @ViewBuilder private var footWord: some View {
        switch move.stage {
        case .done:
            MoveFootWord(word: String(localized: "Done")) {
                if inTray { chrome.moveTray = false } else { Task { await move.read(account: account) } }
            }
        case .failed:
            MoveFootWord(word: String(localized: "Try again")) { Task { await move.read(account: account) } }
        case .working:
            MoveFootWord(word: footVerb, ink: DS.textSecondary,
                         glyph: signing ? "faceid" : nil)
        case .reading:
            // **NO ACT BEFORE THE PAGE KNOWS (2026-11-27, user: "also says
            // hold to deposit but it's not active and user may not be
            // depositing").** Deposit · Withdraw is drawn once the read says
            // something is earning; until then the foot names no verb.
            EmptyView()
        case .ready:
            MoveHoldWord(word: move.claims ? String(localized: "Hold to claim")
                         : move.mode == .lend ? String(localized: "Hold to deposit") : String(localized: "Hold to withdraw"),
                         enabled: live && move.units != nil && !move.ollaUnderMinimum) {
                open = nil
                Task { await move.run(account: account) }
            }
        }
    }

    // No credit under the act (prd §1754, retiring §1685's): the sentence
    // already says "on Aave".

    private var footVerb: String {
        switch move.stage {
        // The rows say each step; the act waits, as Aztec's and Railgun's do.
        case .working(.signing): String(localized: "Confirm with Face ID")
        case .working(.cosigning): String(localized: "Waiting for your co-signer…")
        case .working: String(localized: "Sending…")
        default: move.claims ? String(localized: "Claim") : move.mode == .lend ? String(localized: "Deposit") : String(localized: "Withdraw")
        }
    }

}
