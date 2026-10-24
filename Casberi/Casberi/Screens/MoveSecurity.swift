import SwiftUI

/// **YOUR ACCOUNT'S KEYS (prd §1427, in the Wallet's Security tile since
/// §1436)**: the canvas's rows —
/// a name, a line that says the state, and a verb only where there is
/// something to do. Who signs, network by network (this iPhone, or another
/// device the recovery key can move it from); the recovery key and where it
/// is on; and the key that changes with every send.
///
/// Every line is read from the chain on open — the shared signer's key and
/// the Safe's owners — never remembered, because each network keeps its own.
/// Sign and Revoke are not drawn until they work (§83).
struct MoveSecurity: View {
    let account: String
    @Environment(ShellChrome.self) private var chrome

    typealias Op = YourAccountOp
    typealias Chain = YourAccountChain

    struct Standing: Identifiable {
        let network: Op.Network
        let deployed: Bool
        /// The index of this phone's key the network answers to; nil when
        /// another device's key signs there (or it is not there yet).
        let keyIndex: Int?
        let recovery: Chain.RecoveryState
        /// Owners that are plain addresses: keys the person holds outside
        /// Casberi (the shared signer and the recovery key are contracts).
        let outside: [String]
        /// How many keys a send needs (prd §1447); nil when not there yet.
        let threshold: Int?
        /// The spend limit there (prd §1455); nil when it could not be read.
        let limit: Chain.LimitState?
        var id: Int { network.chainId }
    }

    @State private var standings: [Standing] = []
    @State private var hasRecoveryKey = false
    /// The row acting and what its verb says meanwhile; every other row's
    /// verb waits, in its own word.
    @State private var working: (row: String, label: String)?
    /// The outside key's field, open after Add.
    @State private var addingOutside = false
    @State private var outsideText = ""
    @FocusState private var outsideFocused: Bool
    /// The spend limit being set (prd §1447): the switch is on here before
    /// the chain says so, while the amount is typed.
    /// The spend limit's amount being set.
    @State private var limitEditing = false
    @State private var amountText = ""
    @State private var period: LimitPeriod = .month
    @FocusState private var amountFocused: Bool
    @State private var roundUps = YourAccountDemo.isOn ? YourAccountDemo.roundUps : RoundUps.setting
    @State private var roundUpChoices: [(network: YourAccountOp.Network, tokens: [YourAccountTokens.Listed])] = []
    @State private var roundUpMarks: [String: UIImage] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(title: ThisDevice.title, line: deviceLine,
                verb: canMoveHere ? (ThisDevice.use, moveHere) : nil)
            row(title: String(localized: "Recovery key"), line: recoveryLine,
                verb: recoveryVerb.map { ($0, setUp) })
            row(title: String(localized: "Signer"), line: outsideLine,
                verb: addingOutside ? nil : outsideVerb.map { word in
                    // Add opens the field; Finish puts the key already on one
                    // network on the rest.
                    (word, { if outsideOwner == nil {
                        withAnimation(DS.Motion.standard) { addingOutside = true }
                    } else { addOutside() } })
                })
            if addingOutside { outsideField }
            spendLimit
            roundUpsRow
            // Said once, under the keys, only on a device that cannot open
            // them (§1442n item 3; user: "the user will have created their
            // account on the device they are reading this on"): the fact is
            // the account's, not either key's, and which device that was the
            // app does not know.
            if !elsewhere.isEmpty {
                Text("\(names(elsewhere)) \(elsewhere.count == 1 ? "opens" : "open") from the device this account was created on.")
                    .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, DS.Space.s2)
            }
        }
        // Read again whenever a send lands (`MoveSentence` bumps the rooms'
        // revision): a first send creates the account and moves its key.
        .task(id: "\(account)·\(chrome.roomRevision)") { await read() }
        .task {
            #if DEBUG
            // `-moveOutsideDraft "<address>"`: the outside key's field open and
            // filled, because a `simctl`-booted simulator drops typed characters.
            if let draft = UserDefaults.standard.string(forKey: "moveOutsideDraft"), outsideText.isEmpty {
                addingOutside = true
                outsideText = draft
            }
            #endif
        }
    }

    private func row(title: String, line: String, verb: (String, () -> Void)?) -> some View {
        HStack(spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).dsText(.body17).foregroundStyle(DS.textPrimary)
                Text(verbatim: line).dsText(.subhead12).foregroundStyle(DS.textSecondary)
            }
            Spacer(minLength: DS.Space.s2)
            if let (word, action) = verb {
                Button(action: action) {
                    Text(verbatim: working?.row == title ? working!.label : word)
                        .dsText(.body17)
                        .foregroundStyle(working == nil ? DS.pickInk : DS.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(minHeight: 44)
                }
                .buttonStyle(RowPress())
                .disabled(working != nil)
                // The verb keeps its width ("Setting up…" is longer than
                // "Finish"); the line beside it wraps instead.
                .layoutPriority(1)
            }
        }
        .walletRowPitch()
    }

    /// The demo's account changes no key (§1475): it says so, and nothing runs.
    private func demoSays() -> Bool {
        guard YourAccountDemo.isDemo(account) else { return false }
        chrome.flash(YourAccountDemo.actsLater)
        return true
    }

    // MARK: - Round-ups (prd §1452)

    /// Under the spend limit (user: "same place we have spend limits"),
    /// changed where it stands: the switch, $1 or $5, and what it buys.
    @ViewBuilder private var roundUpsRow: some View {
        DSToggleRow(title: Text("Round-ups"), detail: Text(verbatim: roundUpLine),
                    isOn: Binding(get: { roundUps.on }, set: { on in
                        withAnimation(DS.Motion.standard) { roundUps.on = on }
                        RoundUps.setting = roundUps
                    }))
            .walletRowPitch()
        if roundUps.on { roundUpSentence }
    }

    private var roundUpTarget: String {
        "\(roundUps.target.symbol) on \(roundUps.target.network)"
    }

    private var roundUpLine: String {
        guard roundUps.on else { return String(localized: "Off · each dollar send rounds up, the change buys a token") }
        let saved = YourAccountOp.networks.map { RoundUps.saved(on: $0.chainId) }.reduce("0") { YourAccountOp.sum($0, $1) }
        let usd = YourAccountOp.dollars(saved, decimals: RoundUps.dollarDecimals, price: 1)
        return String(localized: "\(dollarsText(usd)) toward \(roundUps.target.symbol) · buys at $5")
    }

    private func dollarsText(_ usd: Double) -> String {
        String(format: "$%.2f", usd)
    }

    /// ONE gutter for this card's two sentences (the spend limit and
    /// Round-ups), so their values stand in one column; sized to the widest
    /// glue, "round up". Move and the keys walk share `MoveSentence.gutter`,
    /// a narrower one, on their own screens.
    static let sentenceGutter: CGFloat = 76

    /// **ROWS, IN THE PAGE'S OWN TYPE (user: "whole screen looks odd
    /// different text sizes").** The sentence drew its values at 28pt among
    /// 17pt rows; each value is now a row's trailing word that opens a glass
    /// menu with the pick ticked (user: "unclear this is 1 or 5 b/c tapping
    /// it changes it and should show glass menu"), the tokens with their marks.
    private var roundUpSentence: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuRow(title: String(localized: "Round up"), value: String(localized: "To the next $\(roundUps.step)")) {
                Picker(selection: Binding(get: { roundUps.step }, set: { step in
                    withAnimation(DS.Motion.standard) { roundUps.step = step }
                    RoundUps.setting = roundUps
                })) {
                    ForEach([1, 5], id: \.self) { step in
                        Text("To the next $\(step)").tag(step)
                    }
                } label: { EmptyView() }
                .pickerStyle(.inline)
            }
            menuRow(title: String(localized: "And buy"), value: roundUpTarget) {
                // A section per network, named (Base's ETH is not Ethereum's),
                // each token a toggle: it ticks the pick and keeps its mark.
                ForEach(roundUpChoices, id: \.network.chainId) { group in
                    Section(group.network.name) {
                        ForEach(group.tokens) { listed in
                            let target = Self.target(listed, on: group.network)
                            Toggle(isOn: Binding(get: { roundUps.target == target }, set: { on in
                                guard on else { return }
                                withAnimation(DS.Motion.standard) { roundUps.target = target }
                                RoundUps.setting = roundUps
                            })) {
                                Label {
                                    Text(verbatim: listed.token.symbol)
                                } icon: {
                                    Image(uiImage: roundUpMarks[listed.token.symbol] ?? Self.menuMark(listed.token.symbol, image: nil))
                                }
                            }
                        }
                    }
                }
            }
            Text("Change collects in your dollars. At $5, your next send buys \(roundUps.target.symbol) with it.")
                .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, DS.Space.s3)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .task {
            guard roundUpChoices.isEmpty else { return }
            var groups: [(network: YourAccountOp.Network, tokens: [YourAccountTokens.Listed])] = []
            for net in YourAccountOp.networks {
                let listed = await YourAccountTokens.list(net).filter(\.onList)
                // The dollar itself is what the change already is.
                let picks = listed.filter { $0.token != YourAccountOp.dollar(on: net) }.prefix(10)
                if !picks.isEmpty { groups.append((net, Array(picks))) }
            }
            roundUpChoices = groups
            // A menu draws a picture it already has, never one it waits on:
            // the bundled mark, else the one the holdings read named, else a
            // monogram, each made before the menu can open.
            var marks: [String: UIImage] = [:]
            for symbol in Set(groups.flatMap { $0.tokens.map(\.token.symbol) }) {
                var picture = BrandMark.image(for: symbol)
                if picture == nil, !DemoMode.isActive, let url = TokenIconBook.url(for: symbol),
                   case .image(let ui, _) = await RemoteImageLoader.load(urlString: url, targetSide: 72) {
                    picture = ui
                }
                marks[symbol] = Self.menuMark(symbol, image: picture)
            }
            roundUpMarks = marks
        }
    }

    private static func target(_ listed: YourAccountTokens.Listed, on net: YourAccountOp.Network) -> RoundUps.Target {
        RoundUps.Target(chainId: net.chainId, address: listed.token.contract ?? YourAccountSwap.native,
                        symbol: listed.token.symbol, decimals: listed.token.decimals, network: net.name)
    }

    /// A row whose trailing word opens a menu: the name and the pick in the
    /// rows' one size, the pick in the pick's ink.
    private func menuRow<Content: View>(title: String, value: String, @ViewBuilder menu: () -> Content) -> some View {
        HStack(spacing: DS.Space.s3) {
            Text(verbatim: title).dsText(.body17).foregroundStyle(DS.textPrimary)
            Spacer(minLength: DS.Space.s2)
            Menu(content: menu) {
                Text(verbatim: value)
                    .dsText(.body17)
                    .foregroundStyle(DS.pickInk)
                    .contentTransition(.opacity)
                    .lineLimit(1)
                    .frame(minHeight: 44)
            }
            .layoutPriority(1)
        }
        .walletRowPitch()
    }

    /// A token's mark at a menu's size, circular, its own colours kept (a
    /// menu otherwise tints a picture to one ink); a monogram when the app
    /// holds no picture for it, as Holdings draws one.
    static func menuMark(_ symbol: String, image: UIImage?) -> UIImage {
        let side: CGFloat = 24
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        let drawn = UIGraphicsImageRenderer(size: rect.size).image { _ in
            UIBezierPath(ovalIn: rect).addClip()
            if let image {
                image.draw(in: rect)
            } else {
                UIColor.systemGray4.setFill()
                UIRectFill(rect)
                let words = String(symbol.prefix(2)).uppercased() as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
                    .foregroundColor: UIColor.secondaryLabel,
                ]
                let size = words.size(withAttributes: attributes)
                words.draw(at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2), withAttributes: attributes)
            }
        }
        return drawn.withRenderingMode(.alwaysOriginal)
    }

    // MARK: - The lines

    private var live: [Standing] { standings.filter(\.deployed) }

    private func names(_ list: [Standing]) -> String {
        list.map(\.network.name).formatted(.list(type: .and))
    }

    private var deviceLine: String {
        if standings.isEmpty { return String(localized: "Reading…") }
        let here = live.filter { $0.keyIndex != nil }
        let elsewhere = live.filter { $0.keyIndex == nil }
        if live.isEmpty { return String(localized: "Signs your first send, Face ID each time") }
        // The key that changes with every send rides this line (§1436:
        // Rotate's own row folded in).
        if elsewhere.isEmpty { return String(localized: "Signs on \(names(here)) · \(rotateLine)") }
        if here.isEmpty { return String(localized: "Your other device signs for it now") }
        return String(localized: "Signs on \(names(here)) · your other device on \(names(elsewhere))")
    }

    /// Networks another device signs on that the recovery key can move here.
    private var movable: [Standing] {
        live.filter { $0.keyIndex == nil && $0.recovery == .added }
    }
    private var canMoveHere: Bool { hasRecoveryKey && !movable.isEmpty }

    /// Where the recovery key is still missing: every network the account
    /// can be on, created where it is not there yet (prd §1427: both at once,
    /// so money on a network never used cannot be stuck behind one key).
    private var missing: [Standing] { standings.filter { $0.recovery != .added } }

    /// The missing networks this phone can put the key on: where it signs, or
    /// — where the account is not there yet — only on the phone that made it
    /// (prd §1442m). The rest are named, never offered and refused.
    private var fixable: [Standing] {
        missing.filter { $0.deployed ? $0.keyIndex != nil : YourAccountKey.holdsOrigin }
    }
    private var stuck: [Standing] {
        let ids = Set(fixable.map(\.id))
        return missing.filter { !ids.contains($0.id) }
    }

    /// Every network neither key can reach from here: not there yet, and
    /// this is not the device that made the account.
    private var elsewhere: [Standing] { standings.filter { !$0.deployed && !YourAccountKey.holdsOrigin } }

    /// Whether this phone can sign the change on a network (prd §1442m).
    private func canFix(_ s: Standing) -> Bool {
        s.deployed ? s.keyIndex != nil : YourAccountKey.holdsOrigin
    }

    /// The keys chosen at Create still to go on (prd §1457): the networks
    /// the account is not on yet, where its first send carries them.
    private var setup: YourAccountSetup.Choice? { YourAccountSetup.choice(for: account) }
    private var unopened: [Standing] { standings.filter { !$0.deployed && YourAccountKey.holdsOrigin } }
    private var withFirstSend: String { String(localized: "with your first send on \(names(unopened))") }

    /// **A NETWORK NOT OPENED YET IS NOT "NOT YET" (user: "need to figure
    /// out how we do this better").** With a recovery key on this phone the
    /// opening send carries it (`YourAccountChain.setupCalls`), as it carries
    /// the Signer, so those networks are said the Signer's way and never
    /// offered as a Finish that spends a fee there.
    private var recoveryRides: [Standing] { hasRecoveryKey ? unopened.filter { $0.recovery != .added } : [] }
    private var recoveryTargets: [Standing] {
        let rides = Set(recoveryRides.map(\.id))
        return fixable.filter { !rides.contains($0.id) }
    }

    private var recoveryLine: String {
        if standings.isEmpty { return String(localized: "Reading…") }
        let on = standings.filter { $0.recovery == .added }
        let rides = recoveryRides.isEmpty ? nil : String(localized: "with your first send on \(names(recoveryRides))")
        if on.isEmpty, let rides, recoveryTargets.isEmpty {
            return String(localized: "In iCloud Keychain") + " · " + rides
        }
        if on.isEmpty { return String(localized: "Not set up · if you lose this \(ThisDevice.name)") }
        // The networks only another device can open are the account's fact,
        // said once under the rows, not this key's.
        var line = String(localized: "On \(names(on))")
        if !recoveryTargets.isEmpty { line += " · " + String(localized: "not yet on \(names(recoveryTargets))") }
        if let rides { line += " · " + rides }
        return line
    }

    private var recoveryVerb: String? {
        guard !standings.isEmpty, !recoveryTargets.isEmpty else { return nil }
        return standings.contains { $0.recovery == .added } ? String(localized: "Finish") : String(localized: "Set up")
    }

    private var rotateLine: String {
        let highest = live.compactMap(\.keyIndex).max()
        guard let highest else { return String(localized: "a new key with every send") }
        return String(localized: "a new key with every send · key \(highest)")
    }

    // MARK: - Reading

    private func read() async {
        // The demo's account (§1475): every network on, its key here, the
        // recovery key and a Signer on, the limit standing — read off no node,
        // and nothing of it noted for this phone's own account.
        if YourAccountDemo.isDemo(account) {
            hasRecoveryKey = true
            let now = Int(Date().timeIntervalSince1970)
            standings = Op.networks.filter { !$0.isTest }.map { net in
                let plan = YourAccountDemo.plan(on: net)
                return Standing(network: net, deployed: true, keyIndex: 3, recovery: .added,
                                outside: [YourAccountDemo.signer], threshold: 2,
                                limit: .on(plan, current: plan.window(at: now)))
            }
            return
        }
        let recovery = YourAccountRecovery.publicKey(for: account)
        hasRecoveryKey = recovery != nil
        let signer = try? await recovery.asyncMap { try await Chain.recoverySigner(x: $0.x, y: $0.y) }
        var found: [Standing] = []
        await withTaskGroup(of: Standing?.self) { group in
            for net in Op.networks {
                group.addTask {
                    guard let deployed = try? await Chain.isDeployed(net, account) else { return nil }
                    var index: Int?
                    // This phone's only if it can still sign with it.
                    if deployed, let x = try? await Chain.configuredX(net, account),
                       let i = YourAccountKey.index(matchingX: x), YourAccountKey.holds(i) {
                        index = i
                    }
                    var state: Chain.RecoveryState = deployed ? .missing : .notThere
                    if deployed, let signer, let s = try? await Chain.recoveryState(net, account, signer: signer) { state = s }
                    var outside: [String] = []
                    if deployed, let all = try? await Chain.owners(net, account) {
                        for owner in all where owner.caseInsensitiveCompare(YourAccount.sharedSigner) != .orderedSame {
                            if (try? await Chain.isContract(net, owner)) == false { outside.append(owner) }
                        }
                    }
                    var threshold: Int?
                    var limit: Chain.LimitState?
                    if deployed {
                        threshold = try? await Chain.threshold(net, account)
                        limit = threshold == 2 ? try? await Chain.limitState(net, account) : .off
                    }
                    return Standing(network: net, deployed: deployed, keyIndex: index, recovery: state, outside: outside,
                                    threshold: threshold, limit: limit)
                }
            }
            for await s in group { if let s { found.append(s) } }
        }
        let order = Op.networks.map(\.chainId)
        standings = found.sorted { (order.firstIndex(of: $0.network.chainId) ?? 0) < (order.firstIndex(of: $1.network.chainId) ?? 0) }
        // The Wallet's Needs you asks for an outside key until every network
        // the account is on has one (prd §1432).
        let live = standings.filter(\.deployed)
        YourAccountKey.noteOutsideKey(held: !live.isEmpty && live.allSatisfy { !$0.outside.isEmpty })
        // The box's Signers figure (prd §1462): distinct keys across the networks.
        YourAccountFacts.noteSigners(Set(live.flatMap(\.outside).map { $0.lowercased() }).count)
        // And for the recovery key where money sits (prd §1442m), so Finish
        // clears the nudge as soon as it lands.
        await YourAccountProtection.check(force: true)
        #if DEBUG
        NSLog("spendLimit| %@", standings.map { "\($0.network.name):\($0.threshold.map(String.init) ?? "-"):\(plan(of: $0) == nil ? "off" : "on")" }.joined(separator: ","))
        // `-spendLimitOpen YES`: the sentence open, as the switch turned on
        // opens it, because a simulator does not flip a switch;
        // `-spendLimitAmount <dollars>` fills its amount (it types nothing).
        if UserDefaults.standard.bool(forKey: "spendLimitOpen"), !limitEditing {
            withAnimation(DS.Motion.standard) { limitEditing = true }
            if let amount = UserDefaults.standard.string(forKey: "spendLimitAmount") { amountText = amount }
        }
        #endif
    }

    // MARK: - The spend limit (prd §1455)

    /// How often the limit starts again: a day, a week or a month (prd
    /// §1447 item 15; per send dropped, user: "a period limit already caps
    /// every single send").
    enum LimitPeriod: CaseIterable {
        case day, week, month
        var minutes: Int {
            switch self {
            case .day: 60 * 24
            case .week: 60 * 24 * 7
            case .month: 60 * 24 * 30
            }
        }
        var word: String {
            switch self {
            case .day: String(localized: "day")
            case .week: String(localized: "week")
            case .month: String(localized: "month")
            }
        }
        static func of(seconds: Int) -> LimitPeriod {
            allCases.min { abs($0.minutes * 60 - seconds) < abs($1.minutes * 60 - seconds) } ?? .month
        }
    }

    /// Networks a limit can stand on: the account there, and this phone signing for it.
    private var limitNetworks: [Standing] { live.filter { $0.keyIndex != nil } }

    private func plan(of s: Standing) -> (plan: YourAccount7579.Plan, current: YourAccount7579.Window?)? {
        if case .on(let plan, let current) = s.limit { return (plan, current) }
        return nil
    }

    private var limited: [Standing] { limitNetworks.filter { plan(of: $0) != nil } }
    /// Where it is not yet, though a Signer stands there to turn it on.
    /// Only a network read as off: one whose limit could not be read is
    /// neither on nor off.
    private var notYet: [Standing] { limitNetworks.filter { $0.limit == .off && !$0.outside.isEmpty } }
    private var shown: YourAccount7579.Plan? { limited.compactMap { plan(of: $0)?.plan }.first }
    private var signerShort: String {
        limitNetworks.flatMap(\.outside).first.map(YourAccount.short) ?? String(localized: "your signer")
    }

    /// **ONE SWITCH FOR EVERY NETWORK (prd §1455, user: "we want one switch
    /// for all networks").** One amount and one period, set on each network
    /// the account is on — each its own transaction, because each network
    /// keeps its own copy of the account — with what it comes to in all said
    /// beside it.
    @ViewBuilder private var spendLimit: some View {
        if limitNetworks.isEmpty, let limit = setup?.limit, !unopened.isEmpty {
            row(title: String(localized: "Spend limit"),
                line: String(localized: "Up to \(MoveSentence.money(Double(limit.dollars))) of each coin a \(LimitPeriod.of(seconds: limit.minutes * 60).word)")
                    + " · " + withFirstSend,
                verb: nil)
        } else if !limitNetworks.isEmpty {
            DSToggleRow(title: Text("Spend limit"), detail: Text(verbatim: limitLine), isOn: limitBinding)
                .disabled(working != nil || (limited.isEmpty && notYet.isEmpty))
                .walletRowPitch()
            if limitEditing {
                limitSentence
            } else if !limited.isEmpty {
                HStack(spacing: DS.Space.s4) {
                    limitVerb(String(localized: "Change")) {
                        withAnimation(DS.Motion.standard) { limitEditing = true; amountText = ""; period = .month }
                    }
                    if !notYet.isEmpty { limitVerb(String(localized: "Finish")) { finishLimit() } }
                }
                .padding(.vertical, FeedScreen.rowAir)
            }
        }
    }

    private func limitVerb(_ word: String, _ act: @escaping () -> Void) -> some View {
        Button { act(); DSHaptic.selection() } label: {
            Text(verbatim: word).dsText(.body17).foregroundStyle(working == nil ? DS.pickInk : DS.textTertiary)
                .frame(minHeight: 44, alignment: .leading)
        }
        .buttonStyle(RowPress())
        .disabled(working != nil)
    }

    private func period(of plan: YourAccount7579.Plan) -> LimitPeriod {
        LimitPeriod.of(seconds: plan.windows.first.map { $0.until - $0.from } ?? 0)
    }

    private var limitLine: String {
        if working?.row == "limit" { return working!.label }
        guard let standing = shown else {
            if limitEditing { return String(localized: "Set the amount below") }
            return notYet.isEmpty ? String(localized: "Add a signer first") : String(localized: "Off · any one key signs")
        }
        var line = String(localized: "Up to \(dollars(standing.dollarCap)) of each coin a \(period(of: standing).word)")
        let spent = limited.filter { plan(of: $0)?.current == nil }
        // One setting (user: "needs to be one setting"): periods that ran out
        // renew with the next send, which the Signer signs once.
        if !spent.isEmpty { line += " · " + String(localized: "renews with your next send on \(spent.map(\.network.name).formatted(.list(type: .and)))") }
        if !notYet.isEmpty { line += " · " + String(localized: "not yet on \(notYet.map(\.network.name).formatted(.list(type: .and)))") }
        return line
    }

    private func dollars(_ units: String) -> String {
        MoveSentence.money(Op.dollars(units, decimals: 6, price: 1))
    }

    /// Whole dollars, one or more.
    private var amountDollars: Int? {
        let text = amountText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "$", with: "")
        guard let n = Int(text), n >= 1, n <= 1_000_000 else { return nil }
        return n
    }

    /// On opens the amount; off before it is set drops it, nothing sent; off
    /// once it stands is a change to the keys, so the Signer signs it too.
    private var limitBinding: Binding<Bool> {
        Binding(get: { !limited.isEmpty || limitEditing }, set: { on in
            if on {
                guard !limitEditing else { return }
                withAnimation(DS.Motion.standard) { limitEditing = true; amountText = ""; period = .month }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    amountFocused = true
                }
            } else if limited.isEmpty {
                withAnimation(DS.Motion.standard) { limitEditing = false; amountText = "" }
                amountFocused = false
            } else {
                turnOffLimit()
            }
        })
    }

    /// The amount, as Move says things (§1438): the glue in the gutter, the
    /// value large, pink while it can be changed. This card's two sentences
    /// (the limit and Round-ups) share ONE gutter, so their values stand in
    /// one column; "of each coin" is a line of the sentence as the keys
    /// walk says it, not glue.
    private var limitSentence: some View {
        let gutter = Self.sentenceGutter
        return VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text("up to").dsText(.body17).foregroundStyle(DS.textPrimary).frame(width: gutter, alignment: .leading)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(verbatim: "$").dsText(.heading28).foregroundStyle(DS.pickInk)
                    TextField("500", text: $amountText)
                        .keyboardType(.numberPad)
                        .focused($amountFocused)
                        .dsText(.heading28)
                        .foregroundStyle(DS.pickInk)
                        .tint(DS.pickInk)
                        .fixedSize()
                        .accessibilityLabel(Text("Dollars"))
                }
                Spacer(minLength: DS.Space.s2)
                Button { setLimit() } label: {
                    Text(working?.row == "limit" ? working!.label : String(localized: "Set"))
                        .dsText(.body17)
                        .foregroundStyle(amountDollars == nil || working != nil ? DS.textTertiary : DS.pickInk)
                        .frame(minHeight: 44)
                }
                .buttonStyle(RowPress())
                .disabled(amountDollars == nil || working != nil)
            }
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text(verbatim: " ").dsText(.body17).frame(width: gutter, alignment: .leading)
                Text("of each coin").dsText(.heading28).foregroundStyle(DS.textPrimary)
            }
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text("a").dsText(.body17).foregroundStyle(DS.textPrimary).frame(width: gutter, alignment: .leading)
                Menu {
                    ForEach(LimitPeriod.allCases, id: \.self) { p in
                        Button { withAnimation(DS.Motion.standard) { period = p } } label: {
                            if p == period { Label(p.word, systemImage: "checkmark") } else { Text(verbatim: p.word) }
                        }
                    }
                } label: {
                    Text(verbatim: period.word).dsText(.heading28).foregroundStyle(DS.pickInk)
                        .contentTransition(.opacity)
                }
                .accessibilityLabel(Text("How often it starts again"))
            }
            Text(limitFootnote)
                .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                .padding(.leading, gutter + DS.Space.s2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, DS.Space.s3)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Where it applies, and what that comes to in all (user: "each token is
    /// separate, this applies to eth and base, for a total of 1k").
    private var limitFootnote: String {
        // Short, as the user asked ("these helper texts could be clearer and
        // more concise").
        let targets = (limited + notYet).count
        guard let n = amountDollars else {
            return String(localized: "Over it, \(signerShort) signs too. ETH and dollars count apart on each network.")
        }
        let total = MoveSentence.money(Double(n * 2 * max(targets, 1)))
        return String(localized: "Over it, \(signerShort) signs too. ETH and dollars count apart on each network: up to \(total) in all.")
    }

    /// The Signer every one of these networks shares, for one scan (prd
    /// §1456): a network's first Signer may be on it alone (measured: the
    /// test account's Base kept a second Signer Robinhood Chain never had).
    private static func sharedSigner(_ list: [Standing]) -> String? {
        list.first?.outside.first { owner in
            list.allSatisfy { $0.outside.contains { $0.caseInsensitiveCompare(owner) == .orderedSame } }
        }
    }

    /// The batch's Signer where it stands on this network; else the
    /// network's own, asked alone.
    private func coSigner(_ s: Standing, _ batch: SignerRequestSheet.Batch?) -> Chain.CoSigner? {
        if let batch, s.outside.contains(where: { $0.caseInsensitiveCompare(batch.owner) == .orderedSame }) {
            return batch.coSigner(chainId: s.network.chainId)
        }
        return s.outside.first.map { SignerRequestSheet.coSigner(owner: $0, chainId: s.network.chainId) }
    }

    /// One network at a time, each its own transaction: on, this phone alone
    /// while one key still signs; a new amount where it stands, the Signer too.
    private func applyLimit(_ targets: [Standing], dollars n: Int, minutes: Int) {
        if demoSays() { return }
        guard working == nil, !targets.isEmpty else { return }
        amountFocused = false
        working = ("limit", String(localized: "Setting…"))
        let word = LimitPeriod.of(seconds: minutes * 60).word
        // One scan for every network that needs the Signer (prd §1456).
        let cosigned = targets.filter { $0.threshold == 2 }
        let batch = Self.sharedSigner(cosigned).map {
            SignerRequestSheet.Batch(owner: $0, chainIds: cosigned.map(\.network.chainId))
        }
        Task {
            var done: [String] = []
            var failed: [String] = []
            defer { Task { await batch?.finish() } }
            for s in targets {
                let net = s.network
                let reason = String(localized: "Spend limit of \(MoveSentence.money(Double(n))) a \(word) on \(net.name)")
                do {
                    let sent: Chain.Sent
                    if plan(of: s) != nil, let co = coSigner(s, batch) {
                        working = ("limit", String(localized: "Waiting on \(YourAccount.short(co.owner)) · \(net.name)"))
                        sent = try await Chain.changeLimit(on: net, dollars: n, minutes: minutes,
                                                           coSigner: co, reason: reason) { _ in }
                    } else {
                        working = ("limit", String(localized: "Setting on \(net.name)…"))
                        sent = try await Chain.turnOnLimit(on: net, dollars: n, minutes: minutes, reason: reason,
                                                           coSigner: s.threshold == 2 ? coSigner(s, batch) : nil) { _ in }
                    }
                    if case .pending = sent.outcome { failed.append(String(localized: "\(net.name): sent, not yet seen")) }
                    else { done.append(net.name) }
                } catch let failure as Chain.Failure {
                    #if DEBUG
                    NSLog("spendLimit| %@ failed: %@", net.name, failure.message)
                    #endif
                    failed.append(MoveRecovery.worded(failure.message, on: net))
                } catch {
                    #if DEBUG
                    NSLog("spendLimit| %@ not sent: %@", net.name, String(describing: error))
                    #endif
                    failed.append(String(localized: "\(net.name): not sent"))
                }
            }
            working = nil
            withAnimation(DS.Motion.standard) { limitEditing = false; amountText = "" }
            await read()
            if failed.isEmpty {
                chrome.flash(String(localized: "Spend limit set on \(done.formatted(.list(type: .and)))"), tone: .success)
            } else {
                chrome.flash(failed.joined(separator: " · "), tone: done.isEmpty ? .failure : .neutral, seconds: 6)
            }
        }
    }

    private func setLimit() {
        guard let n = amountDollars else { return }
        applyLimit(limited + notYet, dollars: n, minutes: period.minutes)
    }

    /// The networks it is not on yet, at the amount and period it stands at.
    private func finishLimit() {
        guard let plan = shown, let n = Int(plan.dollarCap.dropLast(6)) else { return }
        applyLimit(notYet, dollars: n, minutes: period(of: plan).minutes)
    }

    /// Off on every network: each its sessions removed and one key again —
    /// the Signer signs each.
    private func turnOffLimit() {
        if demoSays() { return }
        guard working == nil else { return }
        let targets = limited
        let batch = Self.sharedSigner(targets).map {
            SignerRequestSheet.Batch(owner: $0, chainIds: targets.map(\.network.chainId))
        }
        Task {
            var done: [String] = []
            var failed: [String] = []
            defer { Task { await batch?.finish() } }
            for s in targets {
                let net = s.network
                guard let co = coSigner(s, batch) else { continue }
                working = ("limit", String(localized: "Waiting on \(YourAccount.short(co.owner)) · \(net.name)"))
                do {
                    let sent = try await Chain.turnOffLimit(on: net, coSigner: co,
                                                            reason: String(localized: "Turn off the spend limit on \(net.name)")) { _ in }
                    if case .pending = sent.outcome { failed.append(String(localized: "\(net.name): sent, not yet seen")) }
                    else { done.append(net.name) }
                } catch let failure as Chain.Failure {
                    failed.append(MoveRecovery.worded(failure.message, on: net))
                } catch {
                    failed.append(String(localized: "\(net.name): not sent"))
                }
            }
            working = nil
            await read()
            if failed.isEmpty {
                chrome.flash(String(localized: "Spend limit off on \(done.formatted(.list(type: .and)))"), tone: .success)
            } else {
                chrome.flash(failed.joined(separator: " · "), tone: done.isEmpty ? .failure : .neutral, seconds: 6)
            }
        }
    }

    // MARK: - The outside key (prd §1432)

    /// The Signer chosen at Create rides the opening send on a network not
    /// opened yet (`setupCalls`); only a network already open needs Finish.
    private var signerRides: [Standing] { setup?.signer == nil ? [] : unopened.filter { $0.outside.isEmpty } }
    private var outsideTargets: [Standing] {
        let rides = Set(signerRides.map(\.id))
        return standings.filter { $0.outside.isEmpty && canFix($0) && !rides.contains($0.id) }
    }
    /// The key Finish puts on: one already on a network, else the one chosen.
    private var outsideOwner: String? { live.flatMap(\.outside).first ?? setup?.signer }

    private var outsideLine: String {
        if standings.isEmpty { return String(localized: "Reading…") }
        let keys = Set(live.flatMap(\.outside).map { $0.lowercased() })
        let on = live.filter { !$0.outside.isEmpty }
        guard let one = keys.first else {
            // Chosen at Create (user: "i have signer set up but shows i
            // don't"): the key, where it still has to go, and where the first
            // send takes it.
            if let chosen = setup?.signer {
                var line = YourAccount.short(chosen)
                if !outsideTargets.isEmpty { line += " · " + String(localized: "not yet on \(names(outsideTargets))") }
                if !signerRides.isEmpty { line += " · " + String(localized: "with your first send on \(names(signerRides))") }
                return line
            }
            return String(localized: "None · if you lose Casberi, a key in a wallet you hold signs instead")
        }
        let who = keys.count == 1 ? YourAccount.short(one) : String(localized: "\(keys.count) keys")
        // The networks only another device can open are said once under the
        // rows, never here.
        if outsideTargets.isEmpty { return String(localized: "\(who) · on \(names(on))") }
        return String(localized: "\(who) · not yet on \(names(outsideTargets))")
    }

    private var outsideVerb: String? {
        guard !standings.isEmpty else { return nil }
        if outsideOwner == nil { return String(localized: "Add") }
        return outsideTargets.isEmpty ? nil : String(localized: "Finish")
    }

    /// The address to add, the one warning that matters, and the verb.
    private var outsideField: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            TextField("0x… of a wallet you hold", text: $outsideText, axis: .vertical)
                .lineLimit(1...2)
                .focused($outsideFocused)
                .submitLabel(.done)
                // A wrapping field takes Return as a line break: here it is
                // Done, and no address holds one.
                .onChange(of: outsideText) { _, text in
                    guard text.contains("\n") else { return }
                    outsideText = text.replacingOccurrences(of: "\n", with: "")
                    outsideFocused = false
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .dsText(.body17)
                .foregroundStyle(DS.textPrimary)
                .disabled(working != nil)
            if outsideCandidate == nil, outsideText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 40 {
                Text("Check the address")
                    .dsText(.subhead12)
                    .foregroundStyle(DS.attentionInk)
            }
            DSFootnote("This key alone can move everything in your account. Use a wallet whose key only you hold, like a Ledger, never an exchange's deposit address.")
            HStack {
                Button { addOutside() } label: {
                    Text("Add as a key")
                        .dsText(.heading17)
                        .foregroundStyle(outsideCandidate == nil || working != nil ? DS.textTertiary : DS.pickInk)
                        .frame(minHeight: 44)
                }
                .buttonStyle(RowPress())
                .disabled(outsideCandidate == nil || working != nil)
                Spacer()
                Button { withAnimation(DS.Motion.standard) { addingOutside = false; outsideText = "" } } label: {
                    Text("Cancel").dsText(.body17).foregroundStyle(DS.textSecondary).frame(minHeight: 44)
                }
                .buttonStyle(RowPress())
                .disabled(working != nil)
            }
        }
        .padding(.bottom, DS.Space.s3)
    }

    /// A whole, correctly checksummed address that is not the account, nor
    /// one imitating an address in the book.
    private var outsideCandidate: String? {
        let text = outsideText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ENS.isHexAddress(text), AddressSafety.checksum(text) != .failed else { return nil }
        let address = EIP55.checksum(text)
        guard address.caseInsensitiveCompare(account) != .orderedSame else { return nil }
        let book = AddressBook.shared
        if book.name(for: address) == nil, !book.lookalikes(of: address).isEmpty { return nil }
        return address
    }

    /// The outside key on every network it is missing from — the account
    /// created where it is not there yet (§1427's rule: nothing stuck).
    private func addOutside() {
        if demoSays() { return }
        guard working == nil, let owner = addingOutside ? outsideCandidate : outsideOwner else { return }
        let targets = outsideTargets.map(\.network)
        working = (String(localized: "Signer"), String(localized: "Adding…"))
        Task {
            var done: [String] = []
            var failed: [String] = []
            for net in targets {
                do {
                    let sent = try await Chain.addOutsideKey(
                        owner, on: net, reason: String(localized: "Add \(YourAccount.short(owner)) as a key on \(net.name)")) { _ in }
                    if case .pending = sent.outcome { failed.append(String(localized: "\(net.name): sent, not yet seen")) }
                    else { done.append(net.name) }
                } catch let failure as Chain.Failure {
                    failed.append(MoveRecovery.worded(failure.message, on: net))
                } catch {
                    failed.append(String(localized: "\(net.name): not sent"))
                }
            }
            working = nil
            addingOutside = false
            outsideText = ""
            await read()
            if failed.isEmpty {
                chrome.flash(String(localized: "Signer on \(done.formatted(.list(type: .and)))"), tone: .success)
            } else {
                chrome.flash(failed.joined(separator: " · "), tone: done.isEmpty ? .failure : .neutral, seconds: 6)
            }
        }
    }

    // MARK: - Acting

    /// Put the recovery key on every network it is missing from, one signed
    /// operation each; a network that cannot pay its fee is named, not fatal.
    private func setUp() {
        if demoSays() { return }
        guard working == nil else { return }
        let targets = recoveryTargets.map(\.network)
        working = (String(localized: "Recovery key"), String(localized: "Setting up…"))
        Task {
            var done: [String] = []
            var failed: [String] = []
            for net in targets {
                do {
                    let sent = try await Chain.addRecovery(
                        on: net, reason: String(localized: "Add your recovery key on \(net.name)")) { _ in }
                    if case .pending = sent.outcome { failed.append(String(localized: "\(net.name): sent, not yet seen")) }
                    else { done.append(net.name) }
                } catch let failure as Chain.Failure {
                    failed.append(MoveRecovery.worded(failure.message, on: net))
                } catch {
                    failed.append(String(localized: "\(net.name): not sent"))
                }
            }
            working = nil
            await read()
            if failed.isEmpty {
                chrome.flash(String(localized: "Recovery key on \(done.formatted(.list(type: .and)))"), tone: .success)
            } else {
                chrome.flash(failed.joined(separator: " · "), tone: done.isEmpty ? .failure : .neutral, seconds: 6)
            }
        }
    }

    /// The recovery key moves the account to this phone on every network
    /// another device signs on.
    private func moveHere() {
        if demoSays() { return }
        guard working == nil else { return }
        let targets = movable.map(\.network)
        working = (ThisDevice.title, String(localized: "Setting up…"))
        Task {
            // A key made now: never one that might be dead or in use.
            guard let index = try? YourAccountKey.freshKey() else {
                working = nil
                chrome.flash(String(localized: "Couldn't make a key on this device"), tone: .failure)
                return
            }
            let failed = await MoveRecovery.move(targets, to: index)
            working = nil
            await read()
            if failed.isEmpty {
                chrome.flash(ThisDevice.ready, tone: .success)
            } else {
                chrome.flash(failed.joined(separator: " · "), tone: .failure, seconds: 6)
            }
        }
    }
}

/// Moving the account here, network by network — shared by the Security
/// row's Move here and the first page of a phone the account is recovered to.
enum MoveRecovery {
    /// The failures, worded per network; empty when every one moved.
    static func move(_ networks: [YourAccountOp.Network], to index: Int) async -> [String] {
        var failed: [String] = []
        for net in networks {
            do {
                let sent = try await YourAccountChain.recover(
                    on: net, to: index, reason: ThisDevice.reason(net.name)) { _ in }
                if case .pending = sent.outcome { failed.append(String(localized: "\(net.name): sent, not yet seen")) }
            } catch let failure as YourAccountChain.Failure {
                failed.append(worded(failure.message, on: net))
            } catch {
                failed.append(String(localized: "\(net.name): not moved"))
            }
        }
        return failed
    }

    /// A failure on one network, named once: most messages already say
    /// which network ("Needs … ETH on Base"), the rest get it in front.
    static func worded(_ message: String, on net: YourAccountOp.Network) -> String {
        message.contains(net.name) ? message : "\(net.name): \(message)"
    }
}

private extension Optional {
    func asyncMap<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        guard let self else { return nil }
        return try await transform(self)
    }
}

/// **THE OUTSIDE-KEY NUDGE (prd §1432, §1422 item 7): one row under Needs
/// you** — the Wallet's Home, and a dot on its tab (prd §1489) — while your
/// account answers only to keys inside Casberi. A passkey signs only where
/// it was made, so the way out is a key the person holds elsewhere; the row
/// stands until every network the account is on has one, and opens the
/// Wallet's Security, where Outside key adds it (§1436). Same anatomy as the rows around it
/// (§1413 item 7): the account's face, a name, one line.
struct OutsideKeyNudge: View {
    @Environment(ShellChrome.self) private var chrome

    /// Drawn at all: the account needs the key.
    static var shown: Bool { YourAccountKey.needsOutsideKey && !YourAccountDemo.isOn }

    var body: some View {
        Button {
            DSHaptic.selection()
            chrome.openYourAccount(at: FeedScreen.SecurityAnchor.account.id)
        } label: {
            DSFeedRow(name: String(localized: "Add a signer"),
                      line: Text("If you lose Casberi, a key in a wallet you hold signs instead")) {
                if let address = YourAccountKey.address {
                    WalletFace(address: address, size: DS.Face.seat, circular: true)
                }
            } trailing: {
                EmptyView()
            } below: {
                EmptyView()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .accessibilityHint(Text("Opens the Wallet's security tile"))
    }

    /// As a row of a `List`, in the feed's insets.
    var listRow: some View {
        self
            .walletListRow()
    }
}

/// **THE RECOVERY-KEY NUDGE (prd §1442m): one row under Needs you** while a
/// network holds your money without the recovery key, and this phone can put
/// it there (`YourAccountProtection`). It leads Needs you: until the key is
/// there, losing this phone loses that money. Opens the Wallet's Security,
/// where the recovery row's Finish opens the network and adds the key.
struct RecoveryKeyNudge: View {
    @Environment(ShellChrome.self) private var chrome

    static var shown: Bool { YourAccountProtection.shown }

    var body: some View {
        let names = YourAccountProtection.unprotected.map(\.name).formatted(.list(type: .and))
        Button {
            DSHaptic.selection()
            chrome.openYourAccount(at: FeedScreen.SecurityAnchor.account.id)
        } label: {
            // One line each (§902): the verb is the title, as the outside
            // key's row; where the money is rides the line.
            DSFeedRow(name: String(localized: "Add your recovery key"),
                      line: Text("On \(names), only this \(ThisDevice.name) can move it")) {
                if let address = YourAccountKey.address {
                    WalletFace(address: address, size: DS.Face.seat, circular: true)
                }
            } trailing: {
                EmptyView()
            } below: {
                EmptyView()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .accessibilityHint(Text("Opens the Wallet's security tile"))
    }

    /// As a row of a `List`, in the feed's insets.
    var listRow: some View {
        self
            .walletListRow()
    }
}

/// **THIS DEVICE, BY ITS NAME (prd §1434, user: "say your other 'device' …
/// what if it is ipad")**: the account's words name the device they run on
/// — iPhone, iPad, Mac — and the one that signed before is "your other
/// device", whatever it was.
enum ThisDevice {
    static var name: String {
        #if targetEnvironment(macCatalyst)
        return "Mac"
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }
    static var title: String { String(localized: "This \(name)") }
    static var use: String { String(localized: "Use on this \(name)") }
    static var ready: String { String(localized: "Your account works on this \(name)") }
    static func reason(_ network: String) -> String {
        String(localized: "Use your account on this \(name) · \(network)")
    }
}
