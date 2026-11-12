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
    @ViewBuilder let head: () -> Head

    @State private var open: Blank?
    @Environment(\.openURL) private var openURL
    @Environment(ShellChrome.self) private var chrome

    enum Blank { case amount, network }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                // The verb leads the sentence (prd §1681); while Aave is
                // read it stands on a line above.
                if move.stage == .reading {
                    head()
                        .padding(.bottom, DS.Space.s4)
                }
                MoveFlow { sentence }
                    .animation(DS.Motion.standard, value: move.figure)
                    .animation(DS.Motion.standard, value: move.chainId)
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
        .safeAreaInset(edge: .bottom, spacing: 0) { if open == nil { foot.transition(.opacity) } }
        // A word's choices make the sheet whole, and it stays whole (prd §1681b).
        .onChange(of: open) { _, now in if now != nil { chrome.moveTall = true } }
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
            case (.lend, false): String(localized: "Lend")
            case (.lend, true): String(localized: "Lent")
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
            MovePhrase(String(localized: "Aave"), glue: move.mode == .lend ? String(localized: "on") : String(localized: "from"))
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
                    // In dollars, as every Move sentence says them, Half · All
                    // under it; Aave's rate is the cost line's (prd §1700z).
                    Text(verbatim: move.amountLine ?? "")
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                    if live { chips }
                    if move.units == nil {
                        Text(move.mode == .lend ? String(localized: "No \(market.symbol) on \(market.network) to lend")
                             : String(localized: "Nothing lent on \(market.network)"))
                            .dsText(.body17).foregroundStyle(DS.textTertiary)
                    }
                }
                if live { switchMode }
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

    /// Half · All (prd §1700z), as Aztec's and Railgun's sentences: each
    /// picks its amount; the ladder stays in the amount's own choices.
    /// **ONE CONTROL, AS ROUND-UPS' (user, 2026-11-10: "the design needs to
    /// match how we do roundups").** Its halves share the row's width, 4 pt
    /// apart, each a `Chip` that fills, the pick crossfading
    /// (`MoveSecurity.RoundUpStepPick`'s anatomy), never small pills on the left.
    @ViewBuilder private var chips: some View {
        let half = move.half
        HStack(spacing: DS.Space.s1) {
            if let half {
                Button {
                    DSHaptic.selection()
                    withAnimation(DS.Motion.standard) { move.pick(half, all: false) }
                } label: { Chip(text: String(localized: "Half"), selected: !move.all && move.amount == half, fills: true) }
                .buttonStyle(PressSpring())
            }
            if let m = market, (Decimal(string: move.available(m) ?? "0") ?? 0) > 0 {
                Button {
                    DSHaptic.selection()
                    withAnimation(DS.Motion.standard) { move.pick(nil, all: true) }
                } label: { Chip(text: String(localized: "All"), selected: move.all, fills: true) }
                .buttonStyle(PressSpring())
            }
        }
    }

    /// The other half of the verb, as a word: Take back where something is
    /// lent, Lend more from Take back.
    @ViewBuilder private var switchMode: some View {
        if move.mode == .lend, move.anyLent {
            word(String(localized: "Take back")) { flip(.takeBack) }
        } else if move.mode == .takeBack {
            word(String(localized: "Lend more")) { flip(.lend) }
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

    private func word(_ text: String, act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(verbatim: text).dsText(.body17).foregroundStyle(DS.pickInk)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
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

    @ViewBuilder private func choices(_ blank: Blank) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            switch blank {
            case .amount: amounts
            case .network: networks
            }
        }
        .padding(.vertical, DS.Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Each token on this network: its amounts up the ladder, then all of it.
    /// Picking one picks its token too.
    private var amounts: some View {
        ForEach(AaveLend.markets.filter { $0.chainId == move.chainId && !move.refused.contains(LendMove.key($0)) },
                id: \.symbol) { m in
            ForEach(move.choices(m), id: \.self) { step in
                let units = PrivateMoney.baseUnits(step, decimals: m.decimals) ?? "0"
                choice(PrivateMoney.figure(units, decimals: m.decimals, symbol: m.symbol), mark: m.symbol,
                       picked: !move.all && move.amount == step && move.symbol == m.symbol) {
                    move.symbol = m.symbol
                    move.pick(step, all: false)
                }
            }
            if let all = move.available(m), all != "0" {
                choice(String(localized: "All, \(PrivateMoney.figure(all, decimals: m.decimals, symbol: m.symbol))"), mark: m.symbol,
                       picked: move.all && move.symbol == m.symbol) {
                    move.symbol = m.symbol
                    move.pick(nil, all: true)
                }
            }
        }
    }

    /// Base and Ethereum, each with what it holds for this verb.
    private var networks: some View {
        ForEach(AaveLend.chainIds, id: \.self) { id in
            let name = YourAccountOp.networks.first { $0.chainId == id }?.name ?? ""
            let there = AaveLend.markets.filter { $0.chainId == id }.compactMap { m -> String? in
                guard let a = move.available(m), (Decimal(string: a) ?? 0) > 0 else { return nil }
                return PrivateMoney.figure(a, decimals: m.decimals, symbol: m.symbol)
            }
            choice(name, mark: nil, line: there.isEmpty ? nil : there.joined(separator: " · "), picked: id == move.chainId) {
                move.chainId = id
                move.pick(nil, all: false)
                if let m = move.market, (Decimal(string: move.available(m) ?? "0") ?? 0) <= 0,
                   let other = AaveLend.markets.first(where: { $0.chainId == id && (Decimal(string: move.available($0) ?? "0") ?? 0) > 0 }) {
                    move.symbol = other.symbol
                }
                move.settle()
            }
        }
    }

    private func choice(_ title: String, mark: String?, line: String? = nil, picked: Bool, act: @escaping () -> Void) -> some View {
        Button {
            withAnimation(DS.Motion.standard) {
                act()
                open = nil
            }
            DSHaptic.selection()
        } label: {
            HStack(spacing: DS.Space.s3) {
                if let mark { AssetMark(name: mark, size: DS.Face.list) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .dsText(.body17)
                        .foregroundStyle(picked ? DS.textSecondary : DS.textPrimary)
                        .monospacedDigit()
                    if let line {
                        Text(verbatim: line).dsText(.subhead12).foregroundStyle(DS.textSecondary)
                    }
                }
                Spacer(minLength: DS.Space.s2)
            }
            .frame(minHeight: DSFeed.headHeight + DS.Space.s3)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .accessibilityAddTraits(picked ? [.isSelected] : [])
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

    private var foot: some View {
        VStack(spacing: 0) {
        // ONE THING AT A TIME over the act, as every Move sentence (prd
        // §1700y, §1700z): the steps while it works and after, the cost while ready.
        if let run = stepsRun {
            PrivateStepRows(run: run)
                .padding(.bottom, DS.Space.s3)
                .transition(.opacity)
        } else if live, move.units != nil {
            PrivateCostLine(cost: move.cost, tail: costTail, fallback: costTail ?? "")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, DS.Space.s1)
                .transition(.opacity)
        }
        HStack(alignment: .firstTextBaseline) {
            Spacer(minLength: 0)
            switch move.stage {
            case .done:
                footButton(String(localized: "Done"), on: true) {
                    if inTray { chrome.moveTray = false } else { Task { await move.read(account: account) } }
                }
            case .failed:
                footButton(String(localized: "Try again"), on: true) { Task { await move.read(account: account) } }
            default:
                footButton(footVerb, on: live && move.units != nil, faceID: !move.acting) {
                    open = nil
                    Task { await move.run(account: account) }
                }
                .disabled(!(live && move.units != nil))
            }
        }
        }
        .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
        .padding(.bottom, DS.Space.s2)
        .background { if inTray { DS.surfaceSheet } else { DSPageBackground() } }
    }

    // No credit under the act (prd §1754, retiring §1685's): the sentence
    // already says "on Aave".

    /// What the cost line says after the dollars.
    private var costTail: String? {
        switch move.mode {
        case .lend: market.flatMap { AaveLend.rateOnly(move.rates[LendMove.key($0)]) }
            .map { String(localized: "earns \($0) today") }
        case .takeBack: String(localized: "back in your account at once")
        }
    }

    private var footVerb: String {
        switch move.stage {
        // The rows say each step; the act waits, as Aztec's and Railgun's do.
        case .working(.signing): String(localized: "Confirm with Face ID")
        case .working(.cosigning): String(localized: "Waiting for your Signer…")
        case .working: String(localized: "Sending…")
        default: move.mode == .lend ? String(localized: "Lend") : String(localized: "Take back")
        }
    }

    private func footButton(_ word: String, on: Bool, faceID: Bool = false, act: @escaping () -> Void) -> some View {
        // Move's one act: the pink card (prd §1755).
        Button(action: act) { MoveSentence.actCard(word, on: on, faceID: faceID) }
            .buttonStyle(PressSpring())
    }
}
