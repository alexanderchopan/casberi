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
    @ViewBuilder let head: () -> Head

    @State private var open: Blank?
    /// The cost's list stands in the rows' place (prd §1876).
    @State private var costOpen = false
    @Environment(\.openURL) private var openURL
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.horizontalSizeClass) private var sizeClass

    enum Blank { case amount, network }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // **THE SENTENCE STANDS STILL ON TOP (prd §1897 item 1, Earn
                // since §1901):** "Earn with 0.001 ETH on Base."
                MoveFlow { sentence }
                    .moveHoldFill()
                    // No control (prd §1781): its choices are the deck's.
                    .allowsHitTesting(false)
                    .animation(DS.Motion.standard, value: move.figure)
                    .animation(DS.Motion.standard, value: move.chainId)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    if let run = stepsRun {
                        PrivateStepRows(run: run).transition(.opacity)
                    }
                    // The cost is a row of the facts (prd §1876), the rate a
                    // fact over it, Aave the one it goes through (prd §1901).
                    MoveCostRows(cost: live && move.units != nil && stepsRun == nil ? move.cost : nil, open: $costOpen, indented: false) {
                        // What there is leads the facts, as Send's You have
                        // does (prd §1898 item 6).
                        if live, stepsRun == nil, hasAny, let have = move.haveFigure {
                            MoveFactRow(name: move.mode == .lend ? String(localized: "You have") : String(localized: "Earning"),
                                        value: have, indented: false)
                        }
                        if live, stepsRun == nil, hasAny, let fact = rateFact {
                            MoveFactRow(name: fact.name, value: fact.value, indented: false)
                        }
                        if live, stepsRun == nil {
                            MoveFactRow(name: String(localized: "Through"), value: "Aave", indented: false)
                        }
                    }
                    if !costOpen { line }
                }
                .padding(.top, DS.Space.s4)
            }
            .padding(.horizontal, MoveSentence.sideInset(inTray))
            .padding(.top, inTray ? DS.Space.s2 : DS.Space.s6)
            .padding(.bottom, DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { deck }
        // A word's choices make the sheet whole, and it stays whole (prd §1681b).
        .onChange(of: open) { _, now in if now != nil { chrome.moveTall = true } }
        // The deck opens on the keys once Aave is read: never an empty panel
        // under a sentence that asks how much (prd §1782).
        .onChange(of: live, initial: true) { _, on in
            if on, open == nil, !kindOpen, move.units == nil { withAnimation(DS.Motion.standard) { open = .amount } }
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
    }

    private var market: AaveLend.Market? { move.market }
    /// Whether this market has anything to move: the empty line, else the facts.
    private var hasAny: Bool { (move.market.flatMap { move.available($0) }.flatMap { Decimal(string: $0) } ?? 0) > 0 }
    private var live: Bool { move.stage == .ready }
    private var doneHash: String? { if case .done(let h) = move.stage { h } else { nil } }
    private var rateLine: String? { market.flatMap { AaveLend.rateLine(move.rates[LendMove.key($0)]) } }

    // MARK: - The sentence

    @ViewBuilder private var sentence: some View {
        if move.stage == .reading {
            MovePhrase(String(localized: "Reading Aave…"), ink: DS.textSecondary)
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
                Button { toggle(.amount) } label: {
                    MoveWord(move.figure, ink: MoveSentence.settledInk)
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
        switch move.mode {
        case .lend:
            market.flatMap { AaveLend.rateOnly(move.rates[LendMove.key($0)]) }
                .map { (String(localized: "Earns"), String(localized: "\($0) today")) }
        case .takeBack: (String(localized: "Arrives"), String(localized: "in your account at once"))
        }
    }

    private func flip(_ mode: LendMove.Mode) {
        withAnimation(DS.Motion.standard) {
            move.mode = mode
            move.pick(nil, all: false)
            move.settle()
        }
        DSHaptic.selection()
    }

    private func explorer(_ hash: String) -> (name: String, url: URL)? {
        let (name, base) = move.chainId == 1 ? ("Etherscan", "https://etherscan.io/tx/") : ("Basescan", "https://basescan.org/tx/")
        return URL(string: base + hash).map { (name, $0) }
    }

    // MARK: - The blanks' choices

    private func toggle(_ blank: Blank) {
        guard live else { return }
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

    /// The verb's two kinds are open in the deck.
    @State private var kindOpen = false
    @Environment(\.moveBack) private var back

    /// **EARN'S DECK (prd §1901 items 1–3):** Kind · From · Amount on Home's
    /// panel, the foot's word held to act.
    private var deck: some View {
        VStack(alignment: .leading, spacing: 0) {
            if live, doneHash == nil {
                MoveDeckSteps(steps: steps)
            }
            // The body runs under the foot and fades there (prd §1904 item 9).
            ZStack(alignment: .bottom) {
                Group {
                    if kindOpen {
                        VStack(alignment: .leading, spacing: 0) {
                            kindRow(String(localized: "Earn"), .lend, glyph: "chart.line.uptrend.xyaxis")
                            kindRow(String(localized: "Take back"), .takeBack, glyph: "arrow.uturn.backward")
                        }
                        .transition(.opacity)
                    } else if open == .amount {
                        // **EARN TYPES ITS AMOUNT (prd §1897 item 4, user
                        // 2026-11-19: "earn looks weird"):** Send's keypad, Half
                        // and All as its sums, never a ladder of rows.
                        MoveKeypad(text: typed, presets: keypadPresets,
                                   places: min(move.market?.decimals ?? 6, 6), disabled: !live)
                            .padding(.top, DS.Space.s1)
                            .transition(.opacity)
                    } else if open == .network {
                        ScrollView { fromRows.padding(.vertical, DS.Space.s2) }
                            .scrollIndicators(.hidden)
                            // The last row clears the foot and its fade.
                            .contentMargins(.bottom, MoveDeck.fade, for: .scrollContent)
                            .transition(.opacity)
                    } else {
                        Color.clear
                    }
                }
                .safeAreaPadding(.bottom, MoveDeck.footHeight)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                // The bar's band is the list's (`MoveFootClearance.intoBody`).
                .frame(height: MoveDeck.bodyHeight + MoveDeck.footHeight
                       + MoveFootClearance.bar(inTray: inTray, sizeClass: sizeClass, chrome: chrome)
                       + MoveFootClearance.gained(inTray: inTray), alignment: .top)
                .deckUnderFoot()
                MoveDeckFoot(backDisabled: move.acting, back: {
                    withAnimation(DS.Motion.standard) {
                        if kindOpen { kindOpen = false } else if costOpen { costOpen = false } else if open != nil { open = nil } else { back?() }
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
            // The panel runs edge to edge, past the tray's own inset.
            .padding(.horizontal, inTray ? -DS.Space.s4 : 0)
            .ignoresSafeArea(edges: .bottom)
        }
        .animation(DS.Motion.standard, value: open)
        .animation(DS.Motion.standard, value: kindOpen)
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

    /// Half and All of what there is, dimmed when there is nothing.
    private var keypadPresets: [MoveKeypadPreset] {
        let have = move.market.flatMap { move.available($0) }.flatMap { Decimal(string: $0) } ?? 0
        return [
            MoveKeypadPreset(id: "half", title: String(localized: "Half"), enabled: move.half != nil,
                             picked: !move.all && move.half != nil && move.amount == move.half) {
                if let half = move.half { move.pick(half, all: false) }
            },
            MoveKeypadPreset(id: "all", title: String(localized: "All"), enabled: have > 0, picked: move.all) {
                move.pick(nil, all: true)
            },
        ]
    }

    /// **FROM IS A TOKEN ON A NETWORK (prd §1898 item 1):** every market Aave
    /// takes here, with what you have of it (or have earning), as Send's
    /// From rows; one with nothing is dimmed, never hidden. Move's one token
    /// list (`MoveTokenGrid`, prd §1910): each network under its title.
    private var fromRows: some View {
        let markets = AaveLend.markets.filter { !move.refused.contains(LendMove.key($0)) }
        return MoveTokenGrid(places: [MoveTokenPlace(id: "lend", choices: markets.map { m in
            let name = YourAccountOp.networks.first { $0.chainId == m.chainId }?.name ?? ""
            let have = move.available(m).flatMap { Decimal(string: $0) } ?? 0
            let worth = move.available(m).flatMap { move.dollars($0, in: m) }
            return MoveTokenChoice(id: LendMove.key(m), symbol: m.symbol, network: name, badge: MoveSentence.networkMark(chainId: m.chainId),
                                   sub: worth.map { MoveSentence.money($0, whole: true) } ?? PrivateMoney.figure(move.available(m) ?? "0", decimals: m.decimals, symbol: ""),
                                   picked: m.chainId == move.chainId && m.symbol == move.symbol, dim: have <= 0) {
                withAnimation(DS.Motion.standard) {
                    move.chainId = m.chainId
                    move.symbol = m.symbol
                    move.pick(nil, all: false)
                    move.settle()
                    open = .amount
                }
            }
        })])
    }

    /// Face ID has the act.
    private var signing: Bool { if case .working(.signing) = move.stage { true } else { false } }

    /// Kind (where something is lent), From (the network), Amount.
    private var steps: [MoveDeckStep] {
        var out: [MoveDeckStep] = []
        if move.anyLent || move.mode == .takeBack {
            out.append(MoveDeckStep(id: "kind", word: String(localized: "Kind"), on: kindOpen, answered: true) {
                withAnimation(DS.Motion.standard) { open = nil; kindOpen.toggle() }
            })
        }
        out.append(MoveDeckStep(id: "from", word: String(localized: "From"), on: open == .network && !kindOpen, answered: hasAny) {
            kindOpen = false
            toggle(.network)
        })
        out.append(MoveDeckStep(id: "amount", word: String(localized: "Amount"), on: open == .amount && !kindOpen, answered: move.units != nil) {
            kindOpen = false
            toggle(.amount)
        })
        return out
    }

    private func kindRow(_ text: String, _ mode: LendMove.Mode, glyph: String) -> some View {
        Button {
            kindOpen = false
            if move.mode != mode { flip(mode) }
        } label: {
            MoveDeckRowLabel(name: text, picked: move.mode == mode) {
                Image(systemName: glyph).dsGlyph(.title, weight: .semibold).foregroundStyle(DS.brandInk)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(RowPress())
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
            MoveHoldWord(word: move.mode == .lend ? String(localized: "Hold to earn") : String(localized: "Hold to take back"),
                         enabled: live && move.units != nil) {
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
        default: move.mode == .lend ? String(localized: "Earn") : String(localized: "Take back")
        }
    }

}
