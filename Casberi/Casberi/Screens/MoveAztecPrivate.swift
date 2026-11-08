import SwiftUI
import Observation

/// **YOUR PRIVATE BALANCE ON AZTEC, IN SEND (prd §1700f items 11–14).** The
/// same sentence 0xBow's private balance has (`MovePrivateSentence`), for
/// your Aztec account:
///
/// - **In** (`.deposit`): picked as "Your private account · Aztec" among
///   Send's recipients. "Send 2 USDC to your private account on Aztec." Your
///   Safe deposits through Shield (USDC or WETH), gas riding along in the
///   same operation when the account needs it; the claim on Aztec follows.
///   Or it says what stands in the way: "Fund …ca8d on Ethereum first.", or
///   "Shield needs a Human Passport score of 20 first." with Human Passport in
///   the foot (the only door a Casberi Safe has to a score).
/// - **From** (`.send`): picked as "Aztec · Private" in Send's networks.
///   "Send 2 USDC from your private account on Aztec to …4f38." An Aztec
///   address is a private send inside Aztec; an Ethereum address, anyone's,
///   is out through Shield, finished from Needs you. Either asks the
///   co-signer first (`AztecCoSign`).
///
/// No chips, no direction to choose: the place you send to or from says it.
@MainActor
@Observable
final class AztecMove {
    enum Mode: Equatable { case deposit, send }

    enum Stage: Equatable {
        case reading
        /// Your Safe holds too little to move in (or gas is short and it
        /// holds no AZTEC for it).
        case needsFunds(address: String)
        /// Shield will not take it: below the Passport score, or sanctioned.
        case shieldNo(score: Int, threshold: Int, sanctioned: Bool)
        /// Nothing private on Aztec to send from yet.
        case nothingPrivate
        /// Your Aztec account has no gas for a send of its own.
        case needsGas
        case ready
        case working(String)
        case done(String)
        case failed(String)
    }

    struct Option: Equatable, Identifiable {
        let symbol: String
        let amount: String
        var id: String { symbol + " " + amount }
    }

    var mode: Mode = .deposit
    var stage: Stage = .reading
    var symbol = "USDC"
    var amount = ""
    var recipient: String?
    private(set) var options: [Option] = []
    /// What the Safe holds on Ethereum, base units, by symbol.
    private(set) var safeHeld: [String: String] = [:]
    /// Whether a deposit brings gas along (the account is short of it).
    private(set) var bringsGas = false
    private(set) var maxUSD: Double?

    var decimals: Int { symbol == "USDC" ? 6 : 18 }
    var asset: ShieldBridge.Asset? { ShieldBridge.assets.first { $0.symbol == symbol } }
    var units: String? { PrivateMoney.baseUnits(amount, decimals: decimals) }
    var acting: Bool { if case .working = stage { true } else { false } }

    /// Whether `recipient` is an Aztec account (a private send) or an
    /// Ethereum address (out through Shield).
    var toAztec: Bool { recipient.map(AztecAddressText.isAztec) ?? false }
    var toEthereum: Bool { recipient.map(PrivateMoney.isAddress) ?? false }

    static let usdcSteps = ["1", "2", "5", "10", "25", "50", "100", "250", "500", "1000"]
    static let wethSteps = ["0.0005", "0.001", "0.0025", "0.005", "0.01", "0.025", "0.05", "0.1"]

    func pick(_ amount: String, of symbol: String) {
        self.symbol = symbol
        self.amount = amount
    }

    /// Where the move stands: balances, Shield's word, the account's gas.
    func read() async {
        stage = .reading
        if DemoMode.isActive {
            options = (Self.usdcSteps.prefix(3)).map { Option(symbol: "USDC", amount: $0) }
            if amount.isEmpty { pick("2", of: "USDC") }
            stage = .ready
            return
        }
        guard let safe = YourAccountKey.address else { stage = .failed(String(localized: "There is no account on this iPhone")); return }
        switch mode {
        case .deposit:
            async let standing = ShieldBridge.eligibility(safe)
            var held: [String: String] = [:]
            for asset in ShieldBridge.assets { held[asset.symbol] = await Self.balance(of: asset.ethToken, at: safe) }
            held["AZTEC"] = await Self.balance(of: AztecGas.token, at: safe)
            safeHeld = held
            bringsGas = AztecProver.isAvailable && AztecGas.needed
            options = depositOptions(held)
            guard let standing = await standing else { stage = .failed(String(localized: "Shield did not answer")); return }
            maxUSD = standing.maxUSD
            if standing.sanctioned || !standing.eligible {
                stage = .shieldNo(score: Int(standing.score), threshold: Int(standing.threshold), sanctioned: standing.sanctioned)
                return
            }
            let gasShort = bringsGas && (Decimal(string: held["AZTEC"] ?? "0") ?? 0) < (Decimal(string: AztecGas.rideAlong) ?? 0)
            if options.isEmpty || gasShort { stage = .needsFunds(address: safe); return }
            if !options.contains(where: { $0.symbol == symbol && $0.amount == amount }), let first = options.first {
                pick(options.count > 1 ? options[1].amount : first.amount, of: first.symbol)
            }
            stage = .ready
        case .send:
            if AztecProver.isAvailable { await AztecAccountStore.shared.refresh() }
            let store = AztecAccountStore.shared
            options = store.privateHeld.flatMap { h -> [Option] in
                guard let units = h.privateUnits, let have = Decimal(string: units), let d = h.decimals else { return [] }
                let steps = h.name == "USDC" ? Self.usdcSteps : Self.wethSteps
                return steps.filter { (Decimal(string: $0) ?? 0) * pow(10, d) <= have }.map { Option(symbol: h.name, amount: $0) }
            }
            if options.isEmpty { stage = .nothingPrivate; return }
            if AztecGas.needed { stage = .needsGas; return }
            if !options.contains(where: { $0.symbol == symbol && $0.amount == amount }), let first = options.first {
                pick(first.amount, of: first.symbol)
            }
            stage = .ready
        }
    }

    private func depositOptions(_ held: [String: String]) -> [Option] {
        ShieldBridge.assets.flatMap { asset -> [Option] in
            guard let have = Decimal(string: held[asset.symbol] ?? "0"), have > 0 else { return [] }
            let steps = asset.symbol == "USDC" ? Self.usdcSteps : Self.wethSteps
            return steps.filter { (Decimal(string: $0) ?? 0) * pow(10, asset.decimals) <= have }
                .map { Option(symbol: asset.symbol, amount: $0) }
        }
    }

    /// An ERC-20 balance on Ethereum, base units, or "0".
    static func balance(of token: String, at owner: String) async -> String {
        let data = "0x70a08231" + String(repeating: "0", count: 24) + owner.lowercased().dropFirst(2)
        guard let answer = try? await YourAccountChain.rpc(YourAccountOp.ethereum, "eth_call", [["to": token, "data": data], "latest"]) as? String
        else { return "0" }
        return ShieldBridge.decimal(hex: String(answer.dropFirst(2))) ?? "0"
    }

    /// The move, as the sentence says it.
    func run() async {
        guard stage == .ready, let units, let asset else { return }
        let report: @Sendable (YourAccountChain.Stage) async -> Void = { s in
            await MainActor.run { self.stage = .working(s == .signing ? String(localized: "Confirm with Face ID") : String(localized: "Sending…")) }
        }
        do {
            switch mode {
            case .deposit:
                stage = .working(String(localized: "Checking…"))
                let gas = bringsGas ? try await AztecGas.plan(units: AztecGas.rideAlong) : nil
                let sent = try await ShieldBridge.deposit(asset, units: units, gas: gas, stage: report)
                stage = .done(sent.transaction)
            case .send:
                guard let recipient else { return }
                if toAztec {
                    try await PrivateRootKey.unlock(reason: String(localized: "Send privately on Aztec"))
                    try await AztecCoSign.approve(String(localized: "Send \(PrivateMoney.figure(units, decimals: decimals, symbol: symbol)) on Aztec to \(recipient)"))
                    stage = .working(String(localized: "Proving…"))
                    let out = try await AztecEngine.shared.call("sendPrivately", [symbol, recipient.lowercased(), units]) as? [String: Any]
                    stage = .done(out?["tx"] as? String ?? "")
                } else if toEthereum {
                    stage = .working(String(localized: "Proving…"))
                    let exit = try await ShieldBridge.exit(asset, units: units, to: recipient)
                    stage = .done(exit.transaction)
                }
                await AztecAccountStore.shared.refresh()
            }
            DSHaptic.success()
        } catch {
            stage = .failed(AztecEngine.words(error))
        }
    }

    /// Claims what Aztec has carried, gas first (a claim pays from gas).
    func settle() async {
        await AztecGas.settle()
        await ShieldBridge.settle()
    }

    var waiting: Bool {
        let s = AztecAccountStore.shared.snapshot
        return (s.gas ?? []).contains { !$0.claimed } || (s.shield ?? []).contains { !$0.claimed }
    }
}

struct MoveAztecPrivateSentence<Head: View>: View {
    let move: AztecMove
    var inTray = false
    /// Leaves the sentence: back to Send's recipients (`pickRecipient`) or
    /// its networks (`switchOff`), as 0xBow's does.
    var leave: (MovePrivateLeave) -> Void = { _ in }
    @ViewBuilder let head: () -> Head

    private enum Blank { case amount, recipient }
    @State private var open: Blank?
    @State private var typed = ""
    @State private var notAnAddress = false
    @State private var copied = false
    @State private var passport = false
    @Environment(ShellChrome.self) private var chrome

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                if !leadsWithVerb {
                    head().padding(.bottom, DS.Space.s4)
                }
                MoveFlow { sentence }
                    .environment(\.moveQuiet, open != nil)
                    .animation(DS.Motion.standard, value: move.stage)
                    .animation(DS.Motion.standard, value: move.amount)
                    .animation(DS.Motion.standard, value: move.recipient)
                Group {
                    if let open, move.stage == .ready {
                        choices(open)
                            .transition(.asymmetric(insertion: .offset(y: 24).combined(with: .opacity), removal: .opacity))
                    } else {
                        line.transition(.opacity)
                    }
                }
                .padding(.top, open != nil ? DS.Space.s4 : DS.Space.s6)
            }
            .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
            .padding(.top, inTray ? DS.Space.s2 : DS.Space.s6)
            .padding(.bottom, DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) { if open == nil { foot.transition(.opacity) } }
        .onChange(of: open) { _, now in if now != nil { chrome.moveTall = true } }
        .task(id: move.mode) { await move.read() }
        // What Aztec has carried is claimed while the sentence stands.
        .task {
            guard AztecProver.isAvailable, !DemoMode.isActive else { return }
            while !Task.isCancelled {
                if move.waiting { await move.settle() }
                try? await Task.sleep(for: .seconds(30))
            }
        }
        // Back from Human Passport, Shield is asked again.
        .sheet(isPresented: $passport, onDismiss: { Task { await move.read() } }) {
            AztecBrowserView(url: URL(string: "https://app.passport.xyz")!, aztec: false, ethereum: true)
                .presentationDragIndicator(.visible)
        }
    }

    private var isDone: Bool { if case .done = move.stage { true } else { false } }

    private var leadsWithVerb: Bool {
        switch move.stage {
        case .ready, .working: true
        default: false
        }
    }

    private var figure: String {
        PrivateMoney.figure(move.units ?? "0", decimals: move.decimals, symbol: move.symbol)
    }

    // MARK: - The sentence

    @ViewBuilder private var sentence: some View {
        switch move.stage {
        case .reading:
            MovePhrase(String(localized: "Reading Aztec…"), ink: DS.textSecondary)
        case .needsFunds(let address):
            MoveClause(glue: String(localized: "Fund")) {
                Button { copy(address) } label: { MoveWord(YourAccount.short(address), ink: DS.pickInk) }
                    .buttonStyle(RowPress())
                    .accessibilityHint(Text("Copies the address"))
            }
            MovePhrase(String(localized: "Ethereum"), glue: String(localized: "on"))
            MovePhrase(String(localized: "first."))
        case .shieldNo(_, let threshold, let sanctioned):
            MovePhrase(sanctioned ? String(localized: "Shield will not move money for this account.")
                       : String(localized: "Shield needs a Human Passport score of \(threshold) first."), ink: DS.textPrimary)
        case .nothingPrivate:
            MovePhrase(String(localized: "Nothing private to send on Aztec yet."), ink: DS.textSecondary)
        case .needsGas:
            MovePhrase(String(localized: "Your private account on Aztec needs gas first."), ink: DS.textPrimary)
        default:
            if !isDone { head() }
            MoveClause(glue: isDone ? String(localized: "Sent") : nil) {
                Button { if move.stage == .ready { toggle(.amount) } } label: {
                    MoveWord(figure, ink: move.stage == .ready ? DS.pickInk : DS.textPrimary)
                        .environment(\.moveQuiet, open != nil && open != .amount)
                }
                .buttonStyle(RowPress())
                .accessibilityLabel(Text("Amount, \(figure)"))
            }
            if move.mode == .deposit {
                // "Your private balance", as on Ethereum (prd §1719): in Move
                // a balance is where money sits; "account" stays where it
                // has an address and apps (Your account, Receive).
                MoveWordsClause(glue: String(localized: "to"), words: String(localized: "your private balance"),
                                ink: move.stage == .ready ? DS.pickInk : DS.textPrimary,
                                action: { if move.stage == .ready { leave(.pickRecipient) } },
                                hint: Text("Picks who it goes to"))
                MovePhrase(String(localized: "Aztec."), glue: String(localized: "on"))
            } else {
                MoveWordsClause(glue: String(localized: "from"), words: String(localized: "your private balance on Aztec"),
                                ink: move.stage == .ready ? DS.pickInk : DS.textPrimary,
                                action: { if move.stage == .ready { leave(.switchOff) } },
                                hint: Text("Picks where it comes from"))
                MoveClause(glue: String(localized: "to")) { recipientWord }
            }
        }
    }

    @ViewBuilder private var recipientWord: some View {
        let live = move.stage == .ready
        Button { if live { toggle(.recipient) } } label: {
            Group {
                if let to = move.recipient {
                    MoveWord(AddressTail.short(to) + ".", ink: live ? DS.pickInk : DS.textPrimary)
                } else {
                    MoveWord(String(localized: "address."), ink: open == .recipient ? DS.pickInk : DS.textTertiary)
                }
            }
            .environment(\.moveQuiet, open != nil && open != .recipient)
        }
        .buttonStyle(RowPress())
        .accessibilityLabel(Text(move.recipient.map { "To \($0)" } ?? String(localized: "Pick who it goes to")))
    }

    // MARK: - The line

    @ViewBuilder private var line: some View {
        switch move.stage {
        case .ready, .working:
            Text(verbatim: readyLine).dsText(.body17).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .needsFunds:
            Text(verbatim: fundsLine).dsText(.body17).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .shieldNo(let score, _, let sanctioned):
            if !sanctioned {
                Text("Yours is \(score).").dsText(.body17).foregroundStyle(DS.textSecondary)
            }
        case .needsGas:
            Text("30 AZTEC from your account pays for it, about $0.45.").dsText(.body17).foregroundStyle(DS.textSecondary)
        case .failed(let words):
            Text(verbatim: words).dsText(.body17).foregroundStyle(DS.attentionInk)
                .fixedSize(horizontal: false, vertical: true)
        case .done:
            Text(verbatim: doneLine).dsText(.body17).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        default:
            EmptyView()
        }
    }

    private var readyLine: String {
        if case .working(let words) = move.stage { return words }
        switch move.mode {
        case .deposit:
            let gas = move.bringsGas ? String(localized: "with 30 AZTEC as its gas") : nil
            return [String(localized: "Through Shield"), String(localized: "0.5% fee"), String(localized: "5 to 15 minutes"), gas]
                .compactMap { $0 }.joined(separator: " · ")
        case .send:
            if move.toEthereum {
                return [String(localized: "Through Shield"), String(localized: "0.5% fee"), String(localized: "finish on Ethereum in about an hour")]
                    .joined(separator: " · ")
            }
            return String(localized: "Who, what and how much stay private · about 20 seconds")
        }
    }

    private var fundsLine: String {
        let gasShort = move.bringsGas && (Decimal(string: move.safeHeld["AZTEC"] ?? "0") ?? 0) < (Decimal(string: AztecGas.rideAlong) ?? 0)
        if gasShort, !(move.options.isEmpty) {
            return String(localized: "Your Aztec account needs 30 AZTEC as gas the first time.")
        }
        return String(localized: "At least 1 USDC or 0.0005 WETH moves in.")
    }

    private var doneLine: String {
        switch move.mode {
        case .deposit: String(localized: "On its way: Aztec carries it in minutes, then it is yours.")
        case .send:
            move.toEthereum ? String(localized: "Proved. In about an hour Needs you offers Finish on Ethereum.")
                : String(localized: "Sent privately.")
        }
    }

    // MARK: - Choices

    private func toggle(_ blank: Blank) {
        withAnimation(DS.Motion.standard) { open = open == blank ? nil : blank }
        DSHaptic.selection()
    }

    @ViewBuilder private func choices(_ blank: Blank) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            switch blank {
            case .amount: amounts
            case .recipient: recipients
            }
        }
        .padding(.vertical, DS.Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var amounts: some View {
        ForEach(move.options) { option in
            let places = option.symbol == "USDC" ? 6 : 18
            let shown = PrivateMoney.figure(PrivateMoney.baseUnits(option.amount, decimals: places) ?? "0", decimals: places, symbol: option.symbol)
            let picked = option.amount == move.amount && option.symbol == move.symbol
            Button {
                withAnimation(DS.Motion.standard) { move.pick(option.amount, of: option.symbol); open = nil }
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

    /// An Aztec account (a private send) or an Ethereum address (out
    /// through Shield), typed or pasted.
    @ViewBuilder private var recipients: some View {
        if notAnAddress {
            Text("That isn't an Aztec or Ethereum address").dsText(.body17).foregroundStyle(DS.attentionInk)
                .padding(.top, DS.Space.s2)
        }
        TextField(text: $typed, prompt: Text("0x…").foregroundStyle(DS.textTertiary)) { Text("Address") }
            .dsText(.body17)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .frame(minHeight: DSFeed.headHeight + DS.Space.s3)
            .onSubmit { take(typed) }
        Button { take(UIPasteboard.general.string ?? "") } label: {
            Text("Paste").dsText(.body17).foregroundStyle(DS.pickInk)
                .frame(maxWidth: .infinity, minHeight: DSFeed.headHeight + DS.Space.s3, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
    }

    private func take(_ raw: String) {
        let address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AztecAddressText.isAztec(address) || PrivateMoney.isAddress(address) else {
            typed = address
            DSHaptic.failure()
            withAnimation(DS.Motion.standard) { notAnAddress = !address.isEmpty }
            return
        }
        notAnAddress = false
        withAnimation(DS.Motion.standard) { move.recipient = address; open = nil }
        DSHaptic.selection()
    }

    // MARK: - The foot

    private var ready: Bool {
        move.stage == .ready && (move.mode == .deposit || move.toAztec || move.toEthereum) && !DemoMode.isActive
    }

    private var foot: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                switch move.stage {
                case .needsFunds(let address):
                    checkAgain
                    Spacer(minLength: DS.Space.s3)
                    footButton(copied ? String(localized: "Copied") : String(localized: "Copy address"), on: true) { copy(address) }
                case .shieldNo(_, _, let sanctioned):
                    checkAgain
                    Spacer(minLength: DS.Space.s3)
                    // The only door a Casberi Safe has to a score (prd §1700f).
                    if !sanctioned {
                        footButton(String(localized: "Human Passport"), on: true) { passport = true }
                    }
                case .needsGas:
                    Spacer(minLength: 0)
                    footButton(String(localized: "Add gas"), on: !DemoMode.isActive) {
                        Task {
                            move.stage = .working(String(localized: "Confirm with Face ID"))
                            do { _ = try await AztecGas.send(units: AztecGas.rideAlong) { _ in }; move.stage = .done("") }
                            catch { move.stage = .failed(AztecEngine.words(error)) }
                        }
                    }
                case .done:
                    Spacer(minLength: 0)
                    footButton(String(localized: "Done"), on: true) {
                        if inTray { chrome.moveTray = false } else { leave(.switchOff) }
                    }
                case .failed:
                    Spacer(minLength: 0)
                    footButton(String(localized: "Try again"), on: true) { Task { await move.read() } }
                case .reading, .nothingPrivate:
                    Spacer(minLength: 0)
                default:
                    Spacer(minLength: 0)
                    footButton(DemoMode.isActive ? String(localized: "Not in the demo") : footVerb, on: ready) {
                        open = nil
                        Task { await move.run() }
                    }
                    .disabled(!ready)
                }
            }
            if move.stage != .reading, !isDone { credit }
        }
        .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
        .padding(.bottom, DS.Space.s2)
        .background { if inTray { DS.surfaceSheet } else { DSPageBackground() } }
    }

    /// Fits beside the act, never cut (prd §1700f item 13).
    private var checkAgain: some View {
        Button {
            Task { await move.read() }
            DSHaptic.selection()
        } label: {
            Text("Check again").dsText(.heading24).foregroundStyle(DS.textPrimary)
                .lineLimit(1).fixedSize().frame(minHeight: 48)
        }
        .buttonStyle(RowPress())
    }

    private var footVerb: String {
        if case .working(let words) = move.stage { return words }
        return String(localized: "Send")
    }

    private var credit: some View {
        HStack(spacing: DS.Space.s1) {
            // Shield carries money in and out; a send that stays on Aztec is Aztec's alone.
            Text(move.mode == .send && !move.toEthereum ? "Powered by Aztec" : "Powered by Shield")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
            ProtocolInlineMark(mark: "aztec").accessibilityHidden(true)
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

    private func copy(_ address: String) {
        DSPasteboard.copy(address)
        DSHaptic.tap()
        withAnimation(DS.Motion.standard) { copied = true }
    }
}

enum AztecAddressText {
    /// An Aztec account's address: `0x` and 64 hex characters.
    static func isAztec(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        return t.hasPrefix("0x") && t.count == 66 && t.dropFirst(2).allSatisfy(\.isHexDigit)
    }
}
