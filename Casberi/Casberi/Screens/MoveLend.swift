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
    @ViewBuilder let head: () -> Head

    @State private var open: Blank?
    /// Tacit's farm page, raised from a farm row (prd §1993).
    @State private var farmPage = false
    /// The cost's list stands in the rows' place (prd §1876).
    @Environment(\.openURL) private var openURL
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.horizontalSizeClass) private var sizeClass

    enum Blank { case amount, network }

    var body: some View {
        // **EARN IS A RECEIPT (prd §1931):** its name, Type · From · Amount,
        // what the open line asks, the foot. No sentence, no panel.
        deck
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // A word's choices make the sheet whole, and it stays whole (prd §1681b).
        .onChange(of: open) { _, now in if now != nil { chrome.moveTall = true } }
        // The deck opens on the keys once Aave is read: never an empty panel
        // under a sentence that asks how much (prd §1782).
        .onChange(of: live, initial: true) { _, on in
            if on, open == nil, move.units == nil { withAnimation(DS.Motion.standard) { open = .amount } }
        }
        .onChange(of: chrome.moveTall) { _, tall in
            if !tall, open != nil { withAnimation(DS.Motion.standard) { open = nil } }
        }
        .task(id: account) {
            await move.read(account: account)
            #if DEBUG
            NSLog("[Casberi] moveLend| %@ | %@ | %@ | %@", move.mode == .lend ? "lend" : "takeBack", move.figure,
                  move.network?.name ?? "-", rateLine ?? "no rate")
            #endif
        }
        .onChange(of: doneHash) { _, hash in
            if hash != nil { DSHaptic.success() }
        }
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
                    } else if market.place == .olla, move.mode == .lend {
                        // **THE AUDIT GAP, SAID ONCE (prd §1970):** Olla's own docs
                        // say its live StakingManager carries an unaudited change.
                        DSFootnote("Withdrawing takes about a day. Olla's latest contract change isn't covered by its audit.")
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
                // Back is the menu, never the step before (prd §1911).
                open = nil; back?()
            }
        }, header: kindsShown && doneHash == nil ? AnyView(
            // The title is the Type (prd §1934): Deposit · Withdraw.
            MoveKindTitle(kinds: [
                MoveKindTitle.Kind(id: "lend", word: String(localized: "Deposit"), on: move.mode == .lend) { flip(.lend) },
                MoveKindTitle.Kind(id: "takeBack", word: String(localized: "Withdraw"), on: move.mode == .takeBack) { flip(.takeBack) },
            ], disabled: move.acting)
        ) : nil, lines: {
            if move.stage == .reading {
                MoveReceiptLine(label: "") {
                    Text("Reading…").dsText(.body17).foregroundStyle(DS.textSecondary)
                }
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

    /// **TYPE · FROM · AMOUNT (prd §1931).** Deposit and Withdraw on the Type
    /// line (user: "instead of an earn pill it could be deposit and instead of
    /// take back it could be withdraw"), the market on From, the figure and
    /// its quick shares on Amount.
    private var receiptLines: some View {
        VStack(alignment: .leading, spacing: MoveReceipt.gap) {
            MoveReceiptLine(label: String(localized: "From")) {
                if let m = market {
                    MoveChip(text: "\(m.symbol) · \(move.network?.name ?? m.network)",
                             mark: MoveRowMark(token: m.symbol, network: MoveSentence.networkMark(chainId: m.chainId)),
                             tone: open == .network ? .open : .answered, disabled: !live) { toggle(.network) }
                } else {
                    MoveChip(text: String(localized: "Choose"), tone: .empty, disabled: !live) { toggle(.network) }
                }
            }
            // **FROM AND TO (prd §1970; user: "maybe its just in the from and
            // to"):** the place is the token's, so To says it, Aave or Olla;
            // taking back, it says your account. Nothing to pick.
            if let m = market {
                MoveReceiptLine(label: String(localized: "To")) {
                    MoveChip(text: move.mode == .lend ? m.placeName : String(localized: "Your public account"),
                             tone: .answered, disabled: true) {}
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
                    if hasAny, let fact = rateFact {
                        MoveReceiptFact(label: fact.name, value: fact.value)
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
            return NSDecimalNumber(decimal: u / pow(10, m.decimals)).stringValue
        }, set: { text in
            move.pick(text.isEmpty ? nil : text, all: false)
        })
    }

    /// There is something to use all of.
    private var canUseAll: Bool {
        (move.market.flatMap { move.available($0) }.flatMap { Decimal(string: $0) } ?? 0) > 0
    }

    /// **FROM IS A TOKEN ON A NETWORK (prd §1898 item 1):** every market Aave
    /// takes here, with what you have of it (or have earning), as Send's
    /// From rows; one with nothing is dimmed, never hidden. Move's one token
    /// list (`MoveTokenGrid`, prd §1910): each network under its title.
    private var fromRows: some View {
        // Olla is offered only to someone with AZTEC there (prd §1970).
        // By worth, richest first, as every Move list (prd §1986).
        let worth: (AaveLend.Market) -> Double = { m in move.available(m).flatMap { move.dollars($0, in: m) } ?? 0 }
        let markets = AaveLend.markets.filter { m in
            !move.refused.contains(LendMove.key(m))
                && (m.place != .olla || (Decimal(string: move.available(m) ?? "0") ?? 0) > 0 || move.anyOlla)
        }.sorted { worth($0) > worth($1) }
        // Tacit stands where its worth puts it; last when there is no price.
        let worths = markets.map(worth)
        let tacitAt = tacitWorth.map { w in worths.firstIndex { $0 < w } ?? worths.count } ?? worths.count
        let choices: [MoveTokenChoice] = markets.map { m in
            let name = YourAccountOp.networks.first { $0.chainId == m.chainId }?.name ?? ""
            let have = move.available(m).flatMap { Decimal(string: $0) } ?? 0
            let worth = move.available(m).flatMap { move.dollars($0, in: m) }
            return MoveTokenChoice(id: LendMove.key(m), symbol: m.symbol, network: name, badge: MoveSentence.networkMark(chainId: m.chainId),
                                   sub: worth.map { MoveSentence.money($0, whole: true) } ?? PrivateMoney.figure(move.available(m) ?? "0", decimals: m.decimals, symbol: ""),
                                   // Today's rate on every choice, a dimmed one too (prd §1958).
                                   // Withdrawing, the rate is what it still earns (prd §1972).
                                   rate: AaveLend.rateOnly(move.rates[LendMove.key(m)]), place: m.placeName,
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
        var all = choices
        all.insert(contentsOf: tacitChoice, at: min(tacitAt, all.count))
        return MoveTokenGrid(places: [MoveTokenPlace(id: "lend", choices: all)] + farmPlace)
    }

    /// **TACIT'S FARMS (prd §1993; user, 2026-11-26: "Farms in Earn").**
    /// Each pool Tacit pays TAC to, at the rate its own pools price, highest
    /// first; Withdraw lists the ones you are in. A farm is entered and left
    /// on Tacit's own page, so a row opens it: Casberi reads, Tacit moves.
    /// Shown while a Tacit account is connected, as Tacit's own row (§1986).
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
                                   // The pair's two marks fill the face: no network badge.
                                   sub: held.flatMap { tacit.farmUSD($0) }.map { MoveSentence.money($0, whole: true) },
                                   rate: TacitFarms.rateWords(TacitFarms.rate(p, in: farms)), place: "Tacit") {
                farmPage = true
            }
        }
        let day = farms.endsAt.formatted(.dateTime.month(.abbreviated).day())
        let rule = farms.active && farms.endsAt > .now
            ? String(localized: "On Ethereum, paid in TAC until \(day). You join on Tacit's site.")
            : String(localized: "Rewards ended \(day).")
        return [MoveTokenPlace(id: "tacit-farms", title: String(localized: "Tacit farms"), rule: rule, choices: choices)]
    }

    /// What Tacit's row is worth, to stand it among the rest.
    private var tacitWorth: Double? {
        guard let r = TacitAccount.shared.reading, let price = TacitAccount.shared.tacPrice else { return nil }
        return (move.mode == .lend ? (r.accountTAC ?? 0) + (r.publicTAC ?? 0) : (r.privateTAC ?? 0)) * price
    }

    /// **TACIT, BESIDE AAVE AND OLLA (prd §1986; user, 2026-11-26: "should
    /// we put tacit in the Earn flow", "ok pls update earn").** Private TAC
    /// earns a share of the Tacit chain's fees: Deposit is Make private (your
    /// public TAC), Withdraw is back to public (your private TAC). No rate:
    /// Tacit pays a share of fees, not a rate the app can read. Shown while
    /// a Tacit account is connected, dimmed when empty (§1984).
    private var tacitChoice: [MoveTokenChoice] {
        guard let tacit, TacitAccount.shared.connected, let r = TacitAccount.shared.reading else { return [] }
        let held = move.mode == .lend ? (r.accountTAC ?? 0) + (r.publicTAC ?? 0) : (r.privateTAC ?? 0)
        let usd = TacitAccount.shared.tacPrice.map { held * $0 }
        let mode = move.mode
        return [MoveTokenChoice(id: "tacit|TAC", symbol: "TAC", network: String(localized: "Tacit chain"),
                                // Public TAC is on Ethereum; private TAC on the Tacit chain.
                                badge: mode == .lend ? MoveSentence.networkMark(chainId: 1) : nil,
                                sub: usd.map { MoveSentence.money($0, whole: true) } ?? "\(TacitAccountRows.amount(held)) TAC",
                                place: "Tacit", dim: held <= 0) {
            tacit(mode)
        }]
    }

    /// Face ID has the act.
    private var signing: Bool { if case .working(.signing) = move.stage { true } else { false } }

    /// Earn and Take back are chips over the steps (§1911): there is
    /// something to take back, or Take back is on.
    private var kindsShown: Bool { move.anyLent || move.mode == .takeBack }

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
        default:
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
        case .working(.cosigning): String(localized: "Waiting for your Signer…")
        case .working: String(localized: "Sending…")
        default: move.claims ? String(localized: "Claim") : move.mode == .lend ? String(localized: "Deposit") : String(localized: "Withdraw")
        }
    }

}
