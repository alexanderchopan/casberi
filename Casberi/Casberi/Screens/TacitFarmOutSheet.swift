import SwiftUI

/// **WITHDRAW FROM A TACIT FARM (prd §2006).** Earn's Withdraw on a farm you
/// are in, in Move's deck as Tacit's other pages are (`TacitOutSheet`): From
/// the farm, the pair, All of it; what it earned and what comes back; then
/// Tacit's three steps (claim, release, take out), the sheet going behind
/// once they start, since they ask nobody anything. The whole position comes
/// out: Tacit's farms bond a position whole, so there is no amount to type.
struct TacitFarmOutSheet: View {
    let lpAsset: String
    var leave: () -> Void
    /// Earn · Deposit · Withdraw in the title's place.
    var header: AnyView? = nil
    @Bindable private var out = TacitFarmOut.shared
    @Bindable private var account = TacitAccount.shared
    @Environment(\.moveBack) private var moveBack
    @Environment(ShellChrome.self) private var chrome

    private var position: TacitFarms.Position? {
        account.reading?.farmed?.first { $0.lpAsset == lpAsset }
    }
    private var pool: TacitFarms.Pool? { account.farms?.pools.first { $0.lpAsset == lpAsset } }
    /// "TAC/ETH", the pair as Tacit's page names it.
    private var pair: String { TacitFarms.name(position?.pair ?? pool?.pair ?? "") }
    /// The pair's two coins, by name: what comes back.
    private var coins: [String] { pair.split(separator: "/").map(String.init) }

    var body: some View {
        MoveReceiptDeck(title: String(localized: "Withdraw"), inTray: true, backDisabled: out.inFlight, back: {
            withAnimation(DS.Motion.standard) { moveBack?() ?? leave() }
        }, header: header, lines: {
            if !working { MoveReceiptSteps(steps: deckSteps) }
        }, content: {
            Group {
                if working {
                    MoveDeckStatus(linesStand: false, sentence: { MovePhrase(sentenceWords) }) {
                        if let run = stepsRun { PrivateStepRows(run: run).transition(.opacity) }
                        finish
                    }
                } else {
                    MoveDeckScroll { receipt }
                }
            }
        }, word: { foot })
        .onChange(of: out.step) { _, now in follow(now) }
        // In Move's tray the steps go behind it (prd §2003).
        .onAppear { out.onAway = chrome.moveTray ? { chrome.moveTray = false } : nil }
        .onAppear { if !out.inFlight, out.lpAsset != lpAsset { out.finish() } }
        #if DEBUG
        .onAppear {
            if let how = UserDefaults.standard.string(forKey: "tacitFarmSample") { out.sample(how, lpAsset: lpAsset) }
        }
        #endif
    }

    /// The steps run, or they ended: the page says them, not the receipt.
    private var working: Bool {
        switch out.step {
        case .claiming, .releasing, .takingOut, .done: out.lpAsset == lpAsset
        default: false
        }
    }

    // MARK: - The deck

    private var deckSteps: [MoveDeckStep] {
        let usd = position.flatMap { account.farmUSD($0) }
        return [
            MoveDeckStep(id: "from", word: String(localized: "From"), answered: true,
                         value: String(localized: "Tacit farm"), fixed: true) {},
            MoveDeckStep(id: "token", word: String(localized: "Token"), answered: true,
                         value: "\(pair) · Ethereum", mark: MoveRowMark(token: coins.first ?? "TAC"), fixed: true) {},
            // A farm bonds a position whole, so all of it comes out.
            MoveDeckStep(id: "amount", word: String(localized: "Amount"), answered: true,
                         value: usd.map { String(localized: "All · \(MoveSentence.money($0, whole: false))") } ?? String(localized: "All"),
                         fixed: true) {},
        ]
    }

    /// What it earned, what comes back, the fee, when; then what the relay
    /// sees, the one line a private move owes (prd §748: privacy is kept).
    @ViewBuilder private var receipt: some View {
        VStack(alignment: .leading, spacing: MoveReceipt.gap) {
            MoveDeckFacts(facts: facts)
            if case .failed(let why) = out.step, out.lpAsset == lpAsset {
                Text(verbatim: why).dsText(.body17).foregroundStyle(DS.attentionInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var facts: [MoveDeckFacts.Fact] {
        var out: [MoveDeckFacts.Fact] = []
        if let earned = position?.pendingTAC, earned >= 0.0001 {
            let tac = "\(TacitAccountRows.amount(earned)) wTAC"
            let usd = account.tacPrice.map { LendMove.usd(earned * $0) }
            out.append(.init(name: String(localized: "Earned"), value: usd.map { "\(tac) (\($0))" } ?? tac))
        }
        if let pool, let farms = account.farms, let rate = TacitFarms.rateWords(TacitFarms.rate(pool, in: farms)) {
            out.append(.init(name: String(localized: "Earns"), value: String(localized: "\(rate) today")))
        }
        out.append(.init(name: String(localized: "You get"),
                         value: coins.count == 2 ? String(localized: "\(coins[0]) and \(coins[1]), private in Tacit") : String(localized: "Its coins, private in Tacit")))
        // Tacit takes it from the pool's first coin (`lpRemove`'s A side).
        let feeCoin = pool.map { TacitFarms.coinName($0.a) }.flatMap { $0.isEmpty ? nil : $0 } ?? coins.first ?? "TAC"
        out.append(.init(name: String(localized: "Fee"), value: String(localized: "Tacit's relay fee, from the \(feeCoin)")))
        out.append(.init(name: String(localized: "Arrives"), value: String(localized: "In a few minutes")))
        return out
    }

    // MARK: - The steps

    private var sentenceWords: String { String(localized: "\(pair) out of Tacit's farm") }

    private var stepsRun: PrivateSendSteps.Run? {
        guard let run = PrivateSendSteps.shared.run, run.kind == .move, run.plan == TacitFarmOut.plan else { return nil }
        return run
    }

    /// The steps, told to the shared run; the sheet goes behind once they start.
    private func follow(_ step: TacitFarmOut.Step) {
        guard out.lpAsset == lpAsset else { return }
        let steps = PrivateSendSteps.shared
        switch step {
        case .claiming:
            if stepsRun?.isRunning != true {
                steps.forget(.move)
                steps.begin(.move, plan: TacitFarmOut.plan, quiet: true)
                if let onAway = out.onAway, steps.sendAway(from: .tacitFarm, landed: String(localized: "Out of the farm")) {
                    onAway()
                }
            }
        case .releasing: steps.mark(.signing)
        case .takingOut: steps.mark(.sent)
        case .done: steps.finish()
        case .failed(let why): steps.fail(why)
        default: break
        }
    }

    /// Where it landed: the coins and what it earned, private in Tacit.
    @ViewBuilder private var finish: some View {
        if case .done = out.step {
            // What came back, then where it is; wTAC said once, if earned.
            PrivateFinishLines(headline: out.paidWords.isEmpty ? String(localized: "Out of the farm")
                                   : String(localized: "Back in Tacit: \(out.paidWords)"),
                               note: nil)
                .onAppear { chrome.rain(sources: ["Wallet"]) }
                .padding(.top, DS.Space.s6)
        }
    }

    // MARK: - The foot

    @ViewBuilder private var foot: some View {
        switch out.step {
        case .claiming:
            MoveFootWord(word: String(localized: "Claiming…"), ink: DS.textSecondary)
        case .releasing, .takingOut:
            MoveFootWord(word: String(localized: "Withdrawing…"), ink: DS.textSecondary)
        case .done where out.lpAsset == lpAsset:
            MoveFootWord(word: String(localized: "Done")) { out.finish(); leave() }
        case .failed where out.lpAsset == lpAsset:
            MoveFootWord(word: String(localized: "Try again")) { Task { await out.leave(lpAsset) } }
        default:
            if DemoMode.isActive {
                MoveFootWord(word: String(localized: "Not in the demo"), ink: DS.textSecondary)
            } else if !TacitEngine.shared.isOpen, let coSigner = YourAccountFacts.coSigners.first {
                MoveFootWord(word: String(localized: "Connect")) { Task { await account.open(coSigner: coSigner) } }
            } else if position == nil {
                MoveFootWord(word: String(localized: "Not in this farm"), ink: DS.textSecondary)
            } else {
                MoveHoldWord(word: String(localized: "Hold to withdraw"), enabled: TacitEngine.shared.isOpen) {
                    Task { await out.leave(lpAsset) }
                }
            }
        }
    }
}
