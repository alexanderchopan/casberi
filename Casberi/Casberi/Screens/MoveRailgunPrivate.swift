import SwiftUI

/// **YOUR PRIVATE BALANCE ON ETHEREUM, FOR EVERY OTHER TOKEN (prd §1713,
/// §1721).** The sentence Move draws when the token is neither ETH nor USDC:
/// Railgun holds it, and the person never chose that (§1713 item 1).
///
/// - **In** (`.deposit`): picked as "Your private balance · Ethereum" with a
///   token on Ethereum already in the sentence. "Send 12 DAI to your private
///   balance on Ethereum." Your account approves and shields in one Face ID
///   operation (`RailgunPocket.shield`). The amount is typed (prd §1727);
///   it moves in at $10 worth or more (§1713 item 2), and a token Casberi
///   cannot price is not offered.
/// - **Out** (`.takeBack`): picked from a Railgun row (Send's token list,
///   Holdings). "Send 400 DAI from your private balance to your account."
///   your account sends it. To someone else ("…to ...e07a.") a Railgun
///   broadcaster sends it, paid inside Railgun in a token it takes, so no
///   account of yours is on the transaction (§1721 item 3, §1723). A wallet
///   holding none of those tokens is offered a little ETH for fees first.
///
/// The foot says what Railgun takes, read from its proxy (item 6), and
/// "Powered by Railgun".
@MainActor
@Observable
final class RailgunMove {
    enum Mode: Equatable { case deposit, takeBack }

    /// What opened the sentence: a token, and which way.
    struct Opening: Equatable {
        var contract: String?
        var takeBack: Bool
        /// Out to someone else; nil is your account.
        var recipient: String? = nil
    }

    enum Stage: Equatable {
        case reading
        /// Under the $10 minimum to move in, or nothing private to take back.
        case nothing
        /// A send to someone else, asking a broadcaster what it costs.
        case quoting
        /// A send to someone else with nothing to pay a broadcaster in.
        case needsFees
        case ready
        case working(String)
        case done(String)
        case failed(String)
    }

    /// What moves: a token and the typed amount of it.
    struct Option: Equatable {
        let contract: String
        let symbol: String
        let decimals: Int
        /// Base units, decimal.
        let units: String
    }

    /// A token that can move, and how much of it there is.
    struct Holding: Equatable, Identifiable {
        let contract: String
        let symbol: String
        let decimals: Int
        /// Base units, decimal.
        let units: String
        let price: Double?
        var id: String { contract.lowercased() }
    }

    /// **ANY AMOUNT (prd §1727, user: "it should let me enter in a custom
    /// amount").** What stands in a typed amount's way is said, never a list
    /// of allowed amounts.
    enum AmountProblem: Equatable {
        case moreThanHeld(String)
        /// Moving in under $10 worth (§1713 item 2).
        case underMinimum
    }

    var mode: Mode = .deposit
    var stage: Stage = .reading
    /// The token asked for when the sentence opened.
    var wanted: String?
    private(set) var holdings: [Holding] = []
    /// The token picked, by contract.
    private(set) var token: String?
    /// The amount, typed.
    var amount = ""
    private(set) var feeBps: Int?
    /// Out to someone else (prd §1721 item 3); nil, or your own account's
    /// address, is taking it back.
    var recipient: String?
    /// The broadcaster's terms for the picked amount.
    private(set) var quote: RailgunEngineWire.Quote?
    /// The fee token's symbol and decimals, for the line.
    private var feeToken: (symbol: String, decimals: Int)?
    /// No broadcaster can carry it (none answered, or nothing to pay one
    /// in), and your private ETH pays a fresh sender's gas (prd §1726).
    private(set) var viaFresh = false

    /// A send to someone else: a broadcaster sends it, never your account.
    var toSomeoneElse: Bool {
        guard mode == .takeBack, let recipient, PrivateMoney.isAddress(recipient) else { return false }
        return recipient.lowercased() != YourAccountKey.address?.lowercased()
    }

    static var floorUSD: Double { RailgunRouting.floorUSD }

    var holding: Holding? { holdings.first { $0.contract.lowercased() == token?.lowercased() } }

    /// What was typed, in the token's base units: a comma is a decimal
    /// point, and a trailing point (mid-typing) is ignored.
    var units: String? {
        guard let holding else { return nil }
        var typed = amount.replacingOccurrences(of: ",", with: ".")
        if typed.hasSuffix(".") { typed.removeLast() }
        return PrivateMoney.baseUnits(typed, decimals: holding.decimals)
    }

    /// The token and the typed amount, once there is more than nothing.
    var picked: Option? {
        guard let h = holding, let units, let want = Decimal(string: units), want > 0 else { return nil }
        return Option(contract: h.contract, symbol: h.symbol, decimals: h.decimals, units: units)
    }

    var amountProblem: AmountProblem? {
        guard let h = holding, let units, let want = Decimal(string: units), want > 0 else { return nil }
        if let have = Decimal(string: h.units), want > have {
            return .moreThanHeld(RailgunHoldings.figure(h.units, decimals: h.decimals) + " " + h.symbol)
        }
        if mode == .deposit, !RailgunRouting.meetsFloor(units: units, decimals: h.decimals, price: h.price, floorUSD: Self.floorUSD) {
            return .underMinimum
        }
        return nil
    }

    var amountOK: Bool { picked != nil && amountProblem == nil }

    /// Picks the token; the typed amount stays.
    func pick(_ h: Holding) {
        token = h.contract
        amountChanged()
    }

    private var quoteTask: Task<Void, Never>?

    /// A new amount or token: any quote is for the old one. A send to
    /// someone else asks a broadcaster again once typing pauses.
    func amountChanged() {
        quoteTask?.cancel()
        quote = nil
        switch stage {
        case .quoting, .needsFees, .failed: stage = .ready
        case .ready: break
        default: return
        }
        guard toSomeoneElse, amountOK else { return }
        stage = .quoting
        quoteTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await self?.requote()
        }
    }

    var acting: Bool { if case .working = stage { true } else { false } }

    /// Reads what can move: your account's tokens on Ethereum (in) or your
    /// Railgun wallet's spendable tokens (back), and Railgun's fee.
    func read() async {
        stage = .reading
        quoteTask?.cancel()
        quote = nil
        feeBps = await Self.readFee(mode == .deposit ? "shieldFee()" : "unshieldFee()")
        var found: [Holding] = []
        switch mode {
        case .deposit where DemoMode.isActive:
            // The demo's account holds only ETH and USDC on Ethereum; its
            // sentence shows DAI moving in, at $1, and sends nothing.
            found = [Holding(contract: RailgunHoldings.demo[0].contract, symbol: "DAI", decimals: 18,
                             units: "120000000000000000000", price: 1)]
        case .deposit:
            guard let account = YourAccountKey.address else {
                stage = .nothing; return
            }
            let net = YourAccountOp.ethereum
            let dollar = YourAccountOp.dollar(on: net).contract?.lowercased()
            for h in await YourAccountTokens.held(account, on: net) {
                guard let contract = h.token.contract, contract.lowercased() != dollar,
                      RailgunRouting.goesToRailgun(symbol: h.token.symbol, contract: contract, chainId: net.chainId),
                      let price = h.price, price > 0,
                      RailgunRouting.meetsFloor(units: h.units, decimals: h.token.decimals, price: price, floorUSD: Self.floorUSD)
                else { continue }
                found.append(Holding(contract: contract, symbol: h.token.symbol, decimals: h.token.decimals,
                                     units: h.units, price: price))
            }
        case .takeBack:
            let store = RailgunHoldings.shared
            found = store.spendableShown.map {
                Holding(contract: $0.contract, symbol: $0.symbol, decimals: $0.decimals,
                        units: $0.spendable, price: store.prices[$0.symbol.uppercased()])
            }
        }
        holdings = found
        let keep = found.first { $0.contract.lowercased() == token?.lowercased() }
            ?? found.first { $0.contract.lowercased() == wanted?.lowercased() }
            ?? found.first
        token = keep?.contract
        if DemoMode.isActive, amount.isEmpty { amount = "25" }
        stage = keep == nil ? .nothing : .ready
        amountChanged()
    }

    /// Asks a broadcaster what sending the picked amount costs. The demo
    /// asks nothing: its fee is 0.14 USDC.
    func requote() async {
        guard let picked, let to = recipient, toSomeoneElse else { return }
        quote = nil
        viaFresh = false
        stage = .quoting
        if DemoMode.isActive {
            // `-railgunDemoFresh YES` shows the fresh sender's line (§1726).
            viaFresh = UserDefaults.standard.bool(forKey: "railgunDemoFresh")
            stage = .ready
            return
        }
        do {
            let q = try await RailgunPocket.quote(token: picked.contract, amount: picked.units, to: to)
            guard self.picked == picked else { return }
            // The fee is named or the send is not offered (§83): the
            // holdings reading, else the token's own record.
            if let held = RailgunHoldings.shared.shown.first(where: { $0.id == q.feeToken.lowercased() }) {
                feeToken = (held.symbol, held.decimals)
            } else if let listed = await YourAccountTokens.lookUp(q.feeToken, on: YourAccountOp.ethereum) {
                feeToken = (listed.token.symbol, listed.token.decimals)
            } else {
                feeToken = nil
            }
            guard self.picked == picked else { return }
            quote = q
            stage = feeToken == nil ? .failed(String(localized: "Railgun did not answer. Nothing was sent.")) : .ready
        } catch let failure as RailgunPocket.Failure where [.noFeeToken, .feeTokenPending, .noBroadcaster].contains(failure) {
            // A fresh sender carries it when your private ETH pays its gas.
            let covered = await RailgunPocket.privateGasCovers()
            guard self.picked == picked else { return }
            if covered {
                viaFresh = true
                stage = .ready
            } else {
                stage = failure == .noFeeToken ? .needsFees : .failed(Self.words(failure))
            }
        } catch {
            guard self.picked == picked else { return }
            stage = .failed(Self.words(error))
        }
    }

    /// The broadcaster's fee as the line says it: "0.14 USDC".
    var feeWords: String? {
        if DemoMode.isActive, toSomeoneElse { return "0.14 USDC" }
        guard let q = quote, let feeToken else { return nil }
        return RailgunHoldings.figure(PrivateMoney.decimal(hex: q.fee), decimals: feeToken.decimals) + " " + feeToken.symbol
    }

    /// About $10 of ETH, as WETH, for broadcasters' fees.
    func addFees() async {
        guard !DemoMode.isActive else { return }
        do {
            let prices = await MainnetPrices.prices(for: ["eth"])
            guard let price = prices["eth"] ?? prices["ETH"], price > 0 else {
                stage = .failed(String(localized: "Couldn't price ETH. Nothing was sent.")); return
            }
            var wei = Decimal(RailgunRouting.nice(Self.floorUSD / price)) * pow(10, 18), whole = Decimal()
            NSDecimalRound(&whole, &wei, 0, .up)
            stage = .working(String(localized: "Confirm with Face ID"))
            _ = try await RailgunPocket.addFees(wei: NSDecimalNumber(decimal: whole).stringValue) { [weak self] s in
                await self?.say(s)
            }
            stage = .done(String(localized: "On its way: private in about an hour. Then send again."))
            await RailgunHoldings.shared.refresh(force: true)
        } catch {
            stage = .failed(Self.words(error))
        }
    }

    /// Railgun's fee off its proxy (`shieldFee()`/`unshieldFee()`, basis
    /// points), never a constant (§1713 item 6). The demo reads nothing:
    /// 25, the value measured on 2026-11-07.
    static func readFee(_ signature: String) async -> Int? {
        if DemoMode.isActive { return 25 }
        guard let hex = try? await YourAccountChain.ethCall(YourAccountOp.ethereum, to: RailgunPocket.proxy,
                                                           data: YourAccount.sel(signature)) else { return nil }
        return Int(PrivateMoney.decimal(hex: hex))
    }

    /// Moves it: in through your account's shield, or back to your account.
    func run() async {
        guard let picked, amountOK, !DemoMode.isActive else { return }
        do {
            switch mode {
            case .deposit:
                stage = .working(String(localized: "Confirm with Face ID"))
                _ = try await RailgunPocket.shield(token: picked.contract, amount: picked.units) { [weak self] s in
                    await self?.say(s)
                }
                stage = .done(String(localized: "On its way: private in about an hour."))
            case .takeBack where toSomeoneElse && viaFresh:
                stage = .working(String(localized: "Confirm with Face ID"))
                _ = try await RailgunPocket.sendFromFresh(token: picked.contract, amount: picked.units, to: recipient ?? "") { [weak self] words in
                    self?.stage = .working(words)
                }
                stage = .done(String(localized: "Sent privately."))
            case .takeBack where toSomeoneElse:
                guard let q = quote else { return }
                stage = .working(String(localized: "Proving on this iPhone…"))
                _ = try await RailgunPocket.send(q)
                quote = nil
                stage = .done(String(localized: "Sent privately."))
            case .takeBack:
                guard let account = YourAccountKey.address else { stage = .failed(String(localized: "No account on this iPhone")); return }
                stage = .working(String(localized: "Proving on this iPhone…"))
                _ = try await RailgunPocket.send(token: picked.contract, amount: picked.units, to: account) { [weak self] s in
                    await self?.say(s)
                }
                stage = .done(String(localized: "Back in your account."))
            }
            await RailgunHoldings.shared.refresh(force: true)
        } catch {
            stage = .failed(Self.words(error))
        }
    }

    private func say(_ s: YourAccountChain.Stage) {
        switch s {
        case .preparing: stage = .working(String(localized: "Preparing…"))
        case .signing: stage = .working(String(localized: "Confirm with Face ID"))
        case .cosigning: stage = .working(String(localized: "Waiting for your co-signer"))
        case .sending, .landing: stage = .working(String(localized: "Sending…"))
        }
    }

    /// Says what went wrong (prd §1727): your account's own reason (Face ID,
    /// gas, Ethereum), never folded into "Railgun did not answer", and the
    /// cause logged whatever the words.
    static func words(_ error: Error) -> String {
        NSLog("railgunMove| failed | %@", String(describing: error))
        // The broadcaster may already have it: never "nothing was sent".
        if (error as? RailgunEngineWire.Failure)?.name == "BroadcastUnconfirmed" {
            return String(localized: "The broadcaster did not confirm. Check Activity before sending again.")
        }
        if let failure = error as? YourAccountChain.Failure { return failure.message }
        if error is PrivateRootKey.Failure {
            return String(localized: "Face ID did not open the private account")
        }
        if error is URLError {
            return String(localized: "Ethereum could not be reached")
        }
        return switch error as? RailgunPocket.Failure {
        case .untrusted?: String(localized: "Railgun's records did not check out. Nothing was sent.")
        case .nothingSpendable?: String(localized: "Not private yet: Railgun lists it in about an hour.")
        case .notRailgun?: String(localized: "That was not Railgun's call. Nothing was sent.")
        case .noAccount?: String(localized: "No account on this iPhone")
        case .noRoot?, .curve?: String(localized: "Face ID did not open the private account")
        case .noBroadcaster?: String(localized: "No Railgun broadcaster answered. Nothing was sent.")
        case .feeNotCovered?: String(localized: "That leaves nothing for the broadcaster's fee. Send a little less.")
        case .noFeeToken?: String(localized: "A broadcaster takes its fee in WETH or USDC, and your private balance holds neither.")
        case .feeTokenPending?: String(localized: "Your ETH for fees is private in about an hour. Send then.")
        case .noPrivateGas?: String(localized: "No broadcaster can send it, and your private ETH can't pay its gas. Nothing was sent.")
        case .gasOnItsWay?: String(localized: "Its gas is on its way from your private ETH. Try again in a minute.")
        default: String(localized: "Railgun did not answer. Nothing was sent.")
        }
    }
}

struct MoveRailgunSentence<Head: View>: View {
    @Bindable var move: RailgunMove
    var inTray = false
    var leave: (MovePrivateLeave) -> Void = { _ in }
    @ViewBuilder let head: () -> Head

    /// The token list is open.
    @State private var open = false
    @FocusState private var typing: Bool
    @Environment(ShellChrome.self) private var chrome

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                if !leadsWithVerb {
                    head().padding(.bottom, DS.Space.s4)
                }
                MoveFlow { sentence }
                    .environment(\.moveQuiet, open)
                    .animation(DS.Motion.standard, value: move.stage)
                    .animation(DS.Motion.standard, value: move.holding)
                Group {
                    if open, picking {
                        tokens
                            .padding(.vertical, DS.Space.s2)
                            .transition(.asymmetric(insertion: .offset(y: 24).combined(with: .opacity), removal: .opacity))
                    } else {
                        line.transition(.opacity)
                    }
                }
                .padding(.top, open ? DS.Space.s4 : DS.Space.s6)
            }
            .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
            .padding(.top, inTray ? DS.Space.s2 : DS.Space.s6)
            .padding(.bottom, DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { if !open { foot.transition(.opacity) } }
        .onChange(of: open) { _, now in if now { chrome.moveTall = true } }
        .task(id: move.mode) { await move.read() }
    }

    private var isDone: Bool { if case .done = move.stage { true } else { false } }

    /// The recipient can be picked again while nothing is moving.
    private var picking: Bool {
        switch move.stage {
        case .ready, .quoting, .needsFees, .failed: true
        default: false
        }
    }

    private var leadsWithVerb: Bool {
        switch move.stage {
        case .ready, .working, .quoting, .needsFees: true
        default: false
        }
    }

    private var figure: String {
        guard let p = move.picked else { return "" }
        return RailgunHoldings.figure(p.units, decimals: p.decimals) + " " + p.symbol
    }

    // MARK: - The sentence

    @ViewBuilder private var sentence: some View {
        switch move.stage {
        case .reading:
            MovePhrase(String(localized: "Reading…"), ink: DS.textSecondary)
        case .nothing:
            MovePhrase(move.mode == .deposit
                       ? String(localized: "Moving to your private balance takes $10 or more.")
                       : String(localized: "Nothing private to take back yet."), ink: DS.textSecondary)
        default:
            if !isDone { head() }
            if picking {
                // The amount typed, the token its own word (prd §1727).
                MoveClause { amountField }
                MoveClause {
                    Button { toggle() } label: {
                        MoveWord(move.holding?.symbol ?? "", ink: DS.pickInk)
                    }
                    .buttonStyle(RowPress())
                    .accessibilityLabel(Text("Token, \(move.holding?.symbol ?? "")"))
                    .accessibilityHint(Text("Picks the token"))
                }
            } else {
                MoveClause(glue: isDone ? String(localized: "Sent") : nil) {
                    MoveWord(figure, ink: DS.textPrimary)
                        .accessibilityLabel(Text("Amount, \(figure)"))
                }
            }
            switch move.mode {
            case .deposit:
                MoveWordsClause(glue: String(localized: "to"), words: String(localized: "your private balance"),
                                ink: move.stage == .ready ? DS.pickInk : DS.textPrimary,
                                action: { if move.stage == .ready { leave(.pickRecipient) } },
                                hint: Text("Picks who it goes to"))
                MovePhrase(String(localized: "Ethereum."), glue: String(localized: "on"))
            case .takeBack:
                MoveWordsClause(glue: String(localized: "from"), words: String(localized: "your private balance"),
                                ink: move.stage == .ready ? DS.pickInk : DS.textPrimary,
                                action: { if move.stage == .ready { leave(.switchOff) } },
                                hint: Text("Picks where it comes from"))
                // Your account (your account sends it), or someone else (a
                // broadcaster sends it, §1721 item 3); a tap picks who.
                MoveWordsClause(glue: String(localized: "to"),
                                words: move.toSomeoneElse ? YourAccount.short(move.recipient ?? "") + "." : String(localized: "your account."),
                                ink: picking ? DS.pickInk : DS.textPrimary,
                                action: { if picking { leave(.pickRecipient) } },
                                hint: Text("Picks who it goes to"))
            }
        }
    }

    // MARK: - The line

    @ViewBuilder private var line: some View {
        switch move.stage {
        case .ready where move.amountProblem != nil:
            Text(verbatim: problemLine).dsText(.body17).foregroundStyle(DS.attentionInk)
                .fixedSize(horizontal: false, vertical: true)
        case .ready, .working, .quoting:
            Text(verbatim: readyLine).dsText(.body17).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .failed(let words):
            Text(verbatim: words).dsText(.body17).foregroundStyle(DS.attentionInk)
                .fixedSize(horizontal: false, vertical: true)
        case .needsFees:
            Text("A broadcaster takes its fee in WETH or USDC, and your private balance holds neither. Add about $10 of ETH for fees first.")
                .dsText(.body17).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .done(let words):
            Text(verbatim: words).dsText(.body17).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        default:
            EmptyView()
        }
    }

    /// Only what this move costs (§1713 item 6): the in fee going in, the
    /// out fee coming back.
    private var readyLine: String {
        if case .working(let words) = move.stage { return words }
        if move.stage == .quoting { return String(localized: "Finding a broadcaster…") }
        let fee = move.feeBps.map { String(localized: "Railgun takes \(RailgunPocket.percent(bps: $0))") }
        switch move.mode {
        case .deposit:
            return [fee, String(localized: "private in about an hour")].compactMap { $0 }.joined(separator: " · ")
        case .takeBack where move.toSomeoneElse && move.viaFresh:
            return [fee, String(localized: "gas from your private ETH")].compactMap { $0 }.joined(separator: " · ")
        case .takeBack where move.toSomeoneElse:
            return [fee, move.feeWords.map { String(localized: "\($0) to the broadcaster") }].compactMap { $0 }.joined(separator: " · ")
        case .takeBack:
            return [fee, String(localized: "gas from your account")].compactMap { $0 }.joined(separator: " · ")
        }
    }

    private var problemLine: String {
        switch move.amountProblem {
        case .moreThanHeld(let have)?: String(localized: "You have \(have).")
        case .underMinimum?: String(localized: "Moving to your private balance takes $10 or more.")
        case nil: ""
        }
    }

    // MARK: - Amount and token

    private func toggle() {
        typing = false
        withAnimation(DS.Motion.standard) { open.toggle() }
        DSHaptic.selection()
    }

    /// The amount, typed (prd §1727): the decimal pad, the token's places at
    /// most, the figure in the sentence's own rung — as Aztec's (§1700q).
    private var amountField: some View {
        MoveRungReader { rung in
            TextField(text: $move.amount,
                      prompt: Text(verbatim: "0").foregroundStyle(DS.textTertiary)) { Text(verbatim: "0") }
                .keyboardType(.decimalPad)
                .focused($typing)
                .dsText(rung)
                .monospacedDigit()
                .foregroundStyle(DS.pickInk)
                .fixedSize()
                .opacity(open ? 0.3 : 1)
        }
        .accessibilityLabel(Text("Amount"))
        .onChange(of: move.amount) { _, now in
            if open, typing { open = false }
            let places = move.holding?.decimals ?? 18
            if let dot = now.firstIndex(where: { $0 == "." || $0 == "," }),
               now.distance(from: dot, to: now.endIndex) - 1 > places {
                move.amount = String(now[...now.index(dot, offsetBy: places)])
                return
            }
            move.amountChanged()
        }
    }

    private var tokens: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(move.holdings) { h in
                let picked = h == move.holding
                Button {
                    withAnimation(DS.Motion.standard) { move.pick(h); open = false }
                    DSHaptic.selection()
                } label: {
                    HStack(spacing: DS.Space.s3) {
                        AssetMark(name: h.symbol, size: DS.Face.list)
                        Text(verbatim: h.symbol).dsText(.body17)
                            .foregroundStyle(picked ? DS.textSecondary : DS.textPrimary)
                        Spacer(minLength: DS.Space.s2)
                        Text(verbatim: RailgunHoldings.figure(h.units, decimals: h.decimals)).dsText(.body17)
                            .foregroundStyle(DS.textSecondary).monospacedDigit()
                    }
                    .frame(minHeight: DSFeed.headHeight + DS.Space.s3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .accessibilityAddTraits(picked ? [.isSelected] : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The foot

    private var ready: Bool {
        move.stage == .ready && move.amountOK && !DemoMode.isActive
            && (!move.toSomeoneElse || move.viaFresh || (move.quote != nil && move.feeWords != nil))
    }

    private var foot: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Spacer(minLength: 0)
                switch move.stage {
                case .done:
                    footButton(String(localized: "Done"), on: true) {
                        if inTray { chrome.moveTray = false } else { leave(.switchOff) }
                    }
                case .failed:
                    footButton(String(localized: "Try again"), on: true) { Task { await move.read() } }
                case .reading, .nothing:
                    EmptyView()
                case .needsFees:
                    footButton(DemoMode.isActive ? String(localized: "Not in the demo") : String(localized: "Add ETH for fees"),
                               on: !DemoMode.isActive) {
                        Task { await move.addFees() }
                    }
                    .disabled(DemoMode.isActive)
                default:
                    footButton(DemoMode.isActive ? String(localized: "Not in the demo") : footVerb, on: ready) {
                        Task { await move.run() }
                    }
                    .disabled(!ready)
                }
            }
            if move.stage != .reading, move.stage != .nothing, !isDone { credit }
        }
        .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
        .padding(.bottom, DS.Space.s2)
        .background { if inTray { DS.surfaceSheet } else { DSPageBackground() } }
    }

    private var footVerb: String {
        if case .working(let words) = move.stage { return words }
        return String(localized: "Send")
    }

    private var credit: some View {
        HStack(spacing: DS.Space.s1) {
            Text("Powered by Railgun").dsText(.label12).foregroundStyle(DS.textTertiary)
            ProtocolInlineMark(mark: "railgun").accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DS.Space.s1)
    }

    private func footButton(_ word: String, on: Bool, act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(verbatim: word)
                .dsText(.heading34)
                .foregroundStyle(on ? DS.pickInk : DS.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(minHeight: 48, alignment: .trailing)
        }
        .buttonStyle(RowPress())
    }
}
