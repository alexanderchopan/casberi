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
/// - **Back** (`.takeBack`): picked from a Railgun row (Send's token list,
///   Holdings). "Send 400 DAI from your private balance to your account."
///   The recipient is your account and nothing else: a send to someone else
///   waits for Railgun's broadcaster, because a send your account submits
///   shows your account paying the recipient (§1721 item 3).
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
    }

    enum Stage: Equatable {
        case reading
        /// Nothing on Ethereum worth $10 to move in, or nothing private to take back.
        case nothing
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

    static var floorUSD: Double { RailgunRouting.floorUSD }

    func pick(_ option: Option) { picked = option }

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
        switch error as? RailgunPocket.Failure {
        case .untrusted?: String(localized: "Railgun's records did not check out. Nothing was sent.")
        case .nothingSpendable?: String(localized: "Not private yet: Railgun lists it in about an hour.")
        case .notRailgun?: String(localized: "That was not Railgun's call. Nothing was sent.")
        case .noAccount?: String(localized: "No account on this iPhone")
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

    private var leadsWithVerb: Bool {
        switch move.stage {
        case .ready, .working: true
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
                // Your account and nothing else, until Railgun's broadcaster
                // carries a send to someone else (§1721 item 3).
                MovePhrase(String(localized: "your account."), glue: String(localized: "to"))
            }
        }
    }

    // MARK: - The line

    @ViewBuilder private var line: some View {
        switch move.stage {
        case .ready, .working:
            Text(verbatim: readyLine).dsText(.body17).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .failed(let words):
            Text(verbatim: words).dsText(.body17).foregroundStyle(DS.attentionInk)
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
        let fee = move.feeBps.map { String(localized: "Railgun takes \(RailgunPocket.percent(bps: $0))") }
        switch move.mode {
        case .deposit:
            return [fee, String(localized: "private in about an hour")].compactMap { $0 }.joined(separator: " · ")
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

    private var ready: Bool { move.stage == .ready && !DemoMode.isActive }

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
