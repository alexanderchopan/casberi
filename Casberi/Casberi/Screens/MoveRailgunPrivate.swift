import SwiftUI

/// **YOUR PRIVATE BALANCE ON ETHEREUM, FOR EVERY OTHER TOKEN (prd §1713,
/// §1721).** The sentence Move draws when the token is neither ETH nor USDC:
/// Railgun holds it, and the person never chose that (§1713 item 1).
///
/// - **In** (`.deposit`): picked as "Your private balance · Ethereum" with a
///   token on Ethereum already in the sentence. "Send 12 DAI to your private
///   balance on Ethereum." Your account approves and shields in one Face ID
///   operation (`RailgunPocket.shield`). Amounts start at $10 worth (item 2);
///   a token Casberi cannot price is not offered.
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
        /// Nothing on Ethereum worth $10 to move in, or nothing private to take back.
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

    struct Option: Equatable, Identifiable {
        let contract: String
        let symbol: String
        let decimals: Int
        /// Base units, decimal.
        let units: String
        let all: Bool
        var id: String { contract.lowercased() + " " + units }
    }

    var mode: Mode = .deposit
    var stage: Stage = .reading
    /// The token asked for when the sentence opened.
    var wanted: String?
    private(set) var options: [Option] = []
    private(set) var picked: Option?
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

    func pick(_ option: Option) {
        picked = option
        if toSomeoneElse { Task { await requote() } }
    }

    var acting: Bool { if case .working = stage { true } else { false } }

    /// Reads what can move: your account's tokens on Ethereum (in) or your
    /// Railgun wallet's spendable tokens (back), and Railgun's fee.
    func read() async {
        stage = .reading
        picked = nil
        feeBps = await Self.readFee(mode == .deposit ? "shieldFee()" : "unshieldFee()")
        var found: [Option] = []
        switch mode {
        case .deposit where DemoMode.isActive:
            // The demo's account holds only ETH and USDC on Ethereum; its
            // sentence shows 120 DAI moving in, at $1, and sends nothing.
            found = Self.ladder(contract: RailgunHoldings.demo[0].contract, symbol: "DAI", decimals: 18,
                                held: "120000000000000000000", price: 1, floorUSD: Self.floorUSD)
        case .deposit:
            guard let account = YourAccountKey.address else {
                stage = .nothing; return
            }
            let net = YourAccountOp.ethereum
            let dollar = YourAccountOp.dollar(on: net).contract?.lowercased()
            for h in await YourAccountTokens.held(account, on: net) {
                guard let contract = h.token.contract, contract.lowercased() != dollar,
                      RailgunRouting.goesToRailgun(symbol: h.token.symbol, contract: contract, chainId: net.chainId),
                      let price = h.price, price > 0 else { continue }
                found += Self.ladder(contract: contract, symbol: h.token.symbol, decimals: h.token.decimals,
                                     held: h.units, price: price, floorUSD: Self.floorUSD)
            }
        case .takeBack:
            let store = RailgunHoldings.shared
            for h in store.spendableShown {
                let price = store.prices[h.symbol.uppercased()]
                found += Self.ladder(contract: h.contract, symbol: h.symbol, decimals: h.decimals,
                                     held: h.spendable, price: price, floorUSD: nil)
            }
        }
        options = found
        let first = found.first { $0.contract.lowercased() == wanted?.lowercased() && $0.all }
            ?? found.first { $0.contract.lowercased() == wanted?.lowercased() }
            ?? found.first
        picked = first
        stage = first == nil ? .nothing : .ready
        if first != nil, toSomeoneElse { await requote() }
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

    /// The amounts a token offers, from `RailgunRouting.ladder`.
    static func ladder(contract: String, symbol: String, decimals: Int, held: String,
                       price: Double?, floorUSD: Double?) -> [Option] {
        RailgunRouting.ladder(decimals: decimals, held: held, price: price, floorUSD: floorUSD).map {
            Option(contract: contract, symbol: symbol, decimals: decimals, units: $0.units, all: $0.all)
        }
    }

    /// Moves it: in through your account's shield, or back to your account.
    func run() async {
        guard let picked, !DemoMode.isActive else { return }
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

    static func words(_ error: Error) -> String {
        // The broadcaster may already have it: never "nothing was sent".
        if (error as? RailgunEngineWire.Failure)?.name == "BroadcastUnconfirmed" {
            return String(localized: "The broadcaster did not confirm. Check Activity before sending again.")
        }
        return switch error as? RailgunPocket.Failure {
        case .untrusted?: String(localized: "Railgun's records did not check out. Nothing was sent.")
        case .nothingSpendable?: String(localized: "Not private yet: Railgun lists it in about an hour.")
        case .notRailgun?: String(localized: "That was not Railgun's call. Nothing was sent.")
        case .noAccount?: String(localized: "No account on this iPhone")
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

    @State private var open = false
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
                    .animation(DS.Motion.standard, value: move.picked)
                Group {
                    if open, move.stage == .ready {
                        amounts
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
                       ? String(localized: "Nothing on Ethereum worth $10 to move in.")
                       : String(localized: "Nothing private to take back yet."), ink: DS.textSecondary)
        default:
            if !isDone { head() }
            MoveClause(glue: isDone ? String(localized: "Sent") : nil) {
                Button { if move.stage == .ready { toggle() } } label: {
                    MoveWord(figure, ink: move.stage == .ready ? DS.pickInk : DS.textPrimary)
                }
                .buttonStyle(RowPress())
                .accessibilityLabel(Text("Amount, \(figure)"))
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

    // MARK: - Amounts

    private func toggle() {
        withAnimation(DS.Motion.standard) { open.toggle() }
        DSHaptic.selection()
    }

    private var amounts: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(move.options) { option in
                let shown = (option.all ? String(localized: "All ") : "")
                    + RailgunHoldings.figure(option.units, decimals: option.decimals) + " " + option.symbol
                let picked = option == move.picked
                Button {
                    withAnimation(DS.Motion.standard) { move.pick(option); open = false }
                    DSHaptic.selection()
                } label: {
                    HStack(spacing: DS.Space.s3) {
                        AssetMark(name: option.symbol, size: DS.Face.list)
                        Text(verbatim: shown).dsText(.body17)
                            .foregroundStyle(picked ? DS.textSecondary : DS.textPrimary).monospacedDigit()
                        Spacer(minLength: DS.Space.s2)
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
        move.stage == .ready && !DemoMode.isActive
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
