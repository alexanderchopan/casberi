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

    /// From the farm, All of it: a farm bonds a position whole.
    private var deckSteps: [MoveDeckStep] {
        let usd = position.flatMap { account.farmUSD($0) }
        return [
            MoveDeckStep(id: "from", word: String(localized: "From"), answered: true,
                         value: String(localized: "\(pair) farm"), mark: MoveRowMark(token: coins.first ?? "TAC"), fixed: true) {},
            MoveDeckStep(id: "amount", word: String(localized: "Amount"), answered: true,
                         value: usd.map { String(localized: "All · \(MoveSentence.money($0, whole: false))") } ?? String(localized: "All"),
                         fixed: true) {},
        ]
    }

    /// **WHAT YOU GET, IN FIGURES (user, 2026-11-27: "build them all").**
    /// Each coin the position comes back as, read off the pool's reserves,
    /// the fee taken from its coin; what it earned as wTAC; then the fee and
    /// when it lands.
    @ViewBuilder private var receipt: some View {
        VStack(alignment: .leading, spacing: MoveReceipt.gap) {
            if let position, let farms = account.farms {
                VStack(alignment: .leading, spacing: 0) {
                    Text("You get").dsText(.body17).foregroundStyle(DS.textSecondary)
                    ForEach(TacitFarms.payout(position, in: farms, fee: out.feeFor == lpAsset ? out.fee : nil)) { coin in
                        coinRow(coin, about: coin.name != "wTAC")
                    }
                }
            }
            MoveDeckFacts(facts: facts)
            if case .failed(let why) = out.step, out.lpAsset == lpAsset {
                Text(verbatim: why).dsText(.body17).foregroundStyle(DS.attentionInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: lpAsset) { await out.quote(lpAsset) }
    }

    private var facts: [MoveDeckFacts.Fact] {
        // In dollars, as every Earn page says its fee: the relay's cut is
        // paid in the pool's first coin, ETH or TAC.
        let fee = out.feeFor == lpAsset ? out.fee : nil
        let cost = fee.flatMap { f in
            f.coin == "ETH" ? account.feeCost(eth: f.amount) : f.coin == "TAC" ? account.feeCost(tac: f.amount) : nil
        }
        return [
            .init(name: String(localized: "Fee"),
                  value: cost?.amount ?? fee.map { String(localized: "about \(TacitAccountRows.amount($0.amount)) \($0.coin)") } ?? "—"),
            .init(name: String(localized: "Arrives"), value: String(localized: "In a few minutes, private in Tacit")),
        ]
    }

    /// Four significant places at most: "0.0512", "99.1", "1,204".
    static func figure(_ amount: Double) -> String {
        amount >= 1 ? TacitAccountRows.amount(amount)
            : amount.formatted(.number.precision(.significantDigits(1...3)))
    }

    /// One coin coming back: its mark, its name (wTAC says it is what it
    /// earned), the amount; "about" until it lands.
    private func coinRow(_ coin: TacitFarms.Coin, about: Bool) -> some View {
        HStack(spacing: DSRoomChassis.headGap) {
            AssetMark(name: coin.name, size: DS.Mark.row)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: coin.name).dsText(.heading17).foregroundStyle(DS.textPrimary)
                if coin.name == "wTAC" {
                    Text("What it earned").dsText(.fact15).foregroundStyle(DS.textSecondary)
                }
            }
            Spacer(minLength: DS.Space.s2)
            Text(verbatim: about ? String(localized: "about \(Self.figure(coin.amount))") : Self.figure(coin.amount))
                .dsText(.heading17).monospacedDigit().foregroundStyle(DS.textPrimary)
        }
        .frame(minHeight: MoveDeck.rowHeight)
        .accessibilityElement(children: .combine)
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

    /// **WHERE IT LANDED (prd §1990's one finish, with the coins under it):**
    /// the headline and how long it took, each coin that came back, and the
    /// door to Holdings, where they now are.
    @ViewBuilder private var finish: some View {
        if case .done = out.step {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                PrivateFinishLines(headline: String(localized: "Back in Tacit, private"),
                                   note: PrivateFinish.took(out.tookSeconds))
                    .onAppear { chrome.rain(sources: ["Wallet"]) }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(paidCoins) { coin in coinRow(coin, about: false) }
                }
                DSPushRow(title: Text("See them in Holdings"), action: {
                    DSHaptic.selection()
                    out.finish()
                    chrome.moveTray = false
                    chrome.openWalletPage(.holdings, fromActivity: nil)
                }) { EmptyView() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, DS.Space.s6)
        }
    }

    /// The coins that came back, the earned wTAC last.
    private var paidCoins: [TacitFarms.Coin] {
        var coins = out.paid.sorted { $0.key < $1.key }.map { TacitFarms.Coin(name: $0.key, amount: $0.value) }
        if out.claimedTAC > 0 { coins.append(TacitFarms.Coin(name: "wTAC", amount: out.claimedTAC)) }
        return coins
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
