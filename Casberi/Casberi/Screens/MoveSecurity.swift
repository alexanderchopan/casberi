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
        /// Casberi (the shared signer and the recovery key are contracts),
        /// less the keys exported from this phone.
        let outside: [String]
        /// Plain-key owners this phone exported (prd §1493).
        let exported: [String]
        /// How many keys a send needs (prd §1447); nil when not there yet.
        let threshold: Int?
        /// The spend limit there (prd §1455); nil when it could not be read.
        let limit: Chain.LimitState?
        var id: Int { network.chainId }
    }

    @State private var standings: [Standing] = []
    /// The networks a read failed on, any read: named, never dropped, and
    /// nothing is offered until they answer (prd §1549).
    @State private var unread: [Op.Network] = []
    @State private var reading = false
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
    /// Whether private money is on this phone alone (prd §1562), read in a
    /// task: the Keychain and the store, never in a body.
    @State private var privateBackup: PrivateRoot.Backup = .fine
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    /// **TWO SECTIONS, SEVEN ROWS, NO LINES (prd §1496, user: "the two
    /// sections … is better b/c spend limit and round ups are different type
    /// than the key stuff"; "perhaps those things don't need subtext either").**
    /// Keys and Spending are the Feed's section names (`SectionPanelName`,
    /// `heading24`, the glyph in its column); every row is a name and ONE
    /// trailing word — a fact in grey, the verb in the pick's ink where there
    /// is something to do, a state in amber where something is missing. The
    /// lines that read as technical (key indexes, "a new key with every
    /// send", the network list on every row) are gone; the networks are one
    /// row, said once.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionPanelName(name: String(localized: "Keys"), glyph: Self.keysGlyph, inset: 0)
            VStack(alignment: .leading, spacing: 0) {
            row(title: String(localized: "Signs from"), value: deviceValue,
                verb: canMoveHere ? (ThisDevice.use, moveHere) : nil)
            row(title: String(localized: "Recovery key"), value: recoveryValue.text, tone: recoveryValue.tone,
                verb: recoveryVerb.map { ($0, setUp) })
            row(title: String(localized: "Co-signer"), value: outsideValue.text, tone: outsideValue.tone,
                verb: addingOutside ? nil : outsideVerb.map { word in
                    // Add opens the field; Finish puts the key already on one
                    // network on the rest.
                    (word, { if outsideOwner == nil {
                        withAnimation(DS.Motion.standard) { addingOutside = true }
                    } else { addOutside() } })
                })
            if addingOutside { outsideField }
            row(title: String(localized: "Networks"), value: networksValue,
                tone: unread.isEmpty || reading ? DS.textSecondary : DS.attentionInk,
                short: networksShort,
                verb: unread.isEmpty || reading ? nil : (String(localized: "Try again"), { _ = Task { _ = await read() } }))
            // Already on, never a choice (prd §1495 item 6, placed by §1496):
            // its state where a setting's value stands, no line.
            row(title: String(localized: "Tor"), value: TorFact.word(TorStatus.shared.state),
                tone: TorFact.ink(TorStatus.shared.state), verb: nil)
            row(title: String(localized: "Private key"), value: exportValue,
                verb: exportVerb.map { word in (word, { exportedKey == nil ? export() : removeExported() }) })
            // Only when private money is on this phone alone (prd §1562).
            if privateBackup != .fine {
                row(title: String(localized: "Private balance"), value: String(localized: "Not backed up"),
                    tone: DS.attentionInk, verb: privateBackupVerb)
            }
            }
            .padding(.leading, Self.rowIndent)
            SectionPanelName(name: String(localized: "Spending"), glyph: ScopeTileGlyph.spending, inset: 0)
                .padding(.top, DS.Space.s3)
            VStack(alignment: .leading, spacing: 0) {
                spendLimit
                roundUpsRow
            }
            .padding(.leading, Self.rowIndent)
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
        .task(id: "\(account)·\(chrome.roomRevision)") { await readUntilAnswered() }
        .task(id: PrivateMoneyStore.shared.notes.map(\.id)) { readPrivateBackup() }
        // Tor connecting late reads what failed again, unasked (prd §1549).
        .onChange(of: TorStatus.shared.state) { _, now in
            if case .ready = now, !unread.isEmpty, !reading { Task { await read(unread) } }
        }
        .task {
            #if DEBUG
            // `-moveOutsideDraft "<address>"`: the outside key's field open and
            // filled, because a `simctl`-booted simulator drops typed characters.
            if let draft = UserDefaults.standard.string(forKey: "moveOutsideDraft"), outsideText.isEmpty {
                addingOutside = true
                outsideText = draft
            }
            // `-exportKeyPreview intro|shown`: the export page raised at mount,
            // `shown` with a key created here and put on no network — the
            // page's look, never a key that opens anything.
            if let preview = UserDefaults.standard.string(forKey: "exportKeyPreview") {
                UserDefaults.standard.removeObject(forKey: "exportKeyPreview")
                try? await Task.sleep(for: .seconds(1.5))
                let nets = Op.networks.filter(YourAccountExport.eligible)
                var stage = MoveExportKey.Stage.intro
                if preview == "shown", let key = try? YourAccountExport.create() {
                    stage = .shown(key, on: nets.map(\.name), failed: [])
                }
                NSLog("exportKey: preview %@", preview)
                MoveExportKey.present(account: account, networks: nets, stage: stage) {}
            }
            #endif
        }
    }

    /// **A ROW STARTS UNDER ITS SECTION'S NAME (§1496, user: "it looks
    /// weirdly indented").** These rows have no lead of their own, so at the
    /// margin they stood under the header's glyph, left of the name they
    /// belong to; the glyph's column and its gap in `SectionPanelName` put
    /// them under the name, as a Feed row's words stand beside its mark.
    static let rowIndent: CGFloat = DSRoomChassis.headGlyph + DSRoomChassis.headGap

    // MARK: - Private balance (prd §1562)

    private func readPrivateBackup() {
        #if DEBUG
        let notes = PrivateMoneyStore.shared.notes
        privateBackup = PrivateRoot.backup(holdsPrivate: !notes.isEmpty,
                                           deviceOnlyHolds: PrivateAccount.legacyExists && PrivateMigration.needed(notes),
                                           iCloud: PrivateRootKey.iCloudSignedIn)
        #endif
    }

    /// The fix: Back up moves the device-only account's money into the
    /// root's; signed out of iCloud, Settings is where to sign in.
    private var privateBackupVerb: (String, () -> Void)? {
        switch privateBackup {
        case .fine: return nil
        case .noICloud:
            return (String(localized: "Settings"), {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            })
        case .deviceOnly:
            return (String(localized: "Back up"), backUpPrivate)
        }
    }

    private func backUpPrivate() {
        #if DEBUG
        let title = String(localized: "Private balance")
        working = (title, String(localized: "Backing up…"))
        Task {
            let outcome = await PrivateMigration.run(context: modelContext)
            working = nil
            if case .failed(let why) = outcome { chrome.flash(why) }
            readPrivateBackup()
        }
        #endif
    }

    /// Who signs, as a section's glyph: a person with a key. Not Permissions'
    /// bare key (who can spend FROM you) and not Your account's shield.
    static let keysGlyph = "person.badge.key"

    /// A row (prd §1496): its name, then the fact in grey and, where there is
    /// something to do, the verb in the pick's ink — both when a fact stands
    /// beside a verb ("…d203" then "Finish"). A row acting shows its word
    /// ("Setting up…") in the verb's place, grey.
    private func row(title: String, value: String?, tone: Color = DS.textSecondary, short: String? = nil,
                     verb: (String, () -> Void)?) -> some View {
        HStack(spacing: DS.Space.s3) {
            Text(verbatim: title).dsText(.body17).foregroundStyle(DS.textPrimary)
            Spacer(minLength: DS.Space.s2)
            if let value, working?.row != title {
                // One line, always (§1496): a value too wide for it says its
                // short form, never a second line ("Base, Ethereum, and
                // Robinhood" → "3 networks").
                ViewThatFits(in: .horizontal) {
                    Text(verbatim: value).lineLimit(1).fixedSize()
                    Text(verbatim: short ?? value).lineLimit(1)
                }
                .dsText(.body17)
                .foregroundStyle(tone)
            }
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
                // "Finish"); the fact beside it wraps instead.
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

    /// Under the spend limit (user: "same place we have spend limits"): one
    /// row whose trailing word says the setting ("$1, buys ETH", or Off) and
    /// opens the one glass menu — the switch, $1 or $5, and what it buys,
    /// the tokens with their marks (prd §1452, §1496). The sentence under it
    /// says the one thing the word cannot: when the change is spent.
    @ViewBuilder private var roundUpsRow: some View {
        HStack(spacing: DS.Space.s3) {
            Text("Round-ups").dsText(.body17).foregroundStyle(DS.textPrimary)
            Spacer(minLength: DS.Space.s2)
            Menu {
                Toggle(isOn: Binding(get: { roundUps.on }, set: { on in
                    withAnimation(DS.Motion.standard) { roundUps.on = on }
                    RoundUps.setting = roundUps
                })) { Text("Round up sends, swaps and buys") }
                if roundUps.on {
                    Picker(selection: Binding(get: { roundUps.step }, set: { step in
                        withAnimation(DS.Motion.standard) { roundUps.step = step }
                        RoundUps.setting = roundUps
                    })) {
                        ForEach([1, 5], id: \.self) { step in
                            Text("To the next $\(step)").tag(step)
                        }
                    } label: { EmptyView() }
                    .pickerStyle(.inline)
                    // A section per network, named (Base's ETH is not
                    // Ethereum's), each token a toggle: it ticks the pick and
                    // keeps its mark.
                    ForEach(roundUpChoices, id: \.network.chainId) { group in
                        Section(group.network.name) {
                            ForEach(group.tokens) { listed in
                                let target = Self.target(listed, on: group.network)
                                Toggle(isOn: Binding(get: { roundUps.target == target && !roundUps.movesPrivately }, set: { on in
                                    guard on else { return }
                                    withAnimation(DS.Motion.standard) {
                                        roundUps.target = target
                                        roundUps.toPrivate = nil
                                    }
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
                    // **OR YOUR PRIVATE BALANCE (prd §1561, §1567)**, a word
                    // beside the tokens, only where this build has a pool to
                    // move the change into: Ethereum (ppUSDC), or Sepolia in
                    // a DEBUG build; none with the kill switch off.
                    ForEach(RoundUps.privatePools.filter { PrivacyNetwork.forChain($0) != nil }.sorted(), id: \.self) { chain in
                        Section(PrivateMoney.network(chain)) {
                            Toggle(isOn: Binding(get: { roundUps.movesPrivately }, set: { on in
                                guard on else { return }
                                withAnimation(DS.Motion.standard) { roundUps.toPrivate = true }
                                RoundUps.setting = roundUps
                            })) {
                                Label { Text("Your private balance") } icon: { Image(systemName: "eye.slash") }
                            }
                        }
                    }
                }
            } label: {
                Text(verbatim: roundUpWord)
                    .dsText(.body17)
                    .foregroundStyle(DS.pickInk)
                    .contentTransition(.opacity)
                    .lineLimit(1)
                    .frame(minHeight: 44)
            }
            .layoutPriority(1)
            .accessibilityLabel(Text("Round-ups, \(roundUpWord)"))
        }
        .walletRowPitch()
        .task {
            // Where round-ups move privately on Ethereum: the pool's smallest
            // deposit, read live for the sentence below (prd §1567).
            if RoundUps.privatePools.contains(RoundUps.ethereumPool), PrivateMove.available {
                await PrivateMoneyStore.shared.readYield(including: .ethereum)
            }
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
        if roundUps.on {
            Text(verbatim: Self.roundUpsExample(roundUps))
                .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, DS.Space.s2)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    /// "To next $1, buys ETH", or Off. "To next" because a bare "$1" read
    /// as the amount each send adds.
    private var roundUpWord: String {
        guard roundUps.on else { return String(localized: "Off") }
        if roundUps.movesPrivately { return String(localized: "Moves to private") }
        return String(localized: "To next $\(roundUps.step), buys \(roundUps.target.symbol)")
    }

    /// A worked send, because "the next $1" read as a $1 round-up: what a
    /// $3.40 send sets aside, and when that buys. Security and the keys walk
    /// say it the same way.
    static func roundUpsExample(_ setting: RoundUps.Setting) -> String {
        // Private: where it runs, and that it moves together (prd §1561).
        // Where the change counts for your private balance, whether or not
        // private money can take it now (it never buys instead, finding 7).
        if setting.movesPrivately, let chain = RoundUps.privateChains.sorted().first {
            // On Ethereum the change is dollars, moved as USDC once it reaches
            // the pool's smallest deposit, read live (prd §1567).
            if chain == RoundUps.ethereumPool {
                guard let at = RoundUps.privateMoveAt(on: chain, poolMinimum: PrivateMoneyStore.shared.roundUpsMinimum) else {
                    return String(localized: "Round-ups on Ethereum move to your private balance together, once the pool's smallest deposit is set aside.")
                }
                let usd = YourAccountOp.dollars(at, decimals: RoundUps.dollarDecimals, price: 1)
                return String(localized: "Round-ups on Ethereum move to your private balance together, once \(WalletValue.money(usd)) is set aside.")
            }
            let at = PrivateMoney.figure(RoundUps.privateMoveAt, decimals: 18, symbol: "ETH")
            return String(localized: "Round-ups on \(PrivateMoney.network(chain)) move to your private balance together, once \(at) is set aside.")
        }
        return setting.step == 5
            ? String(localized: "A $3.40 send rounds up to $5, setting aside $1.60. When $5 is set aside, it buys \(setting.target.symbol).")
            : String(localized: "A $3.40 send rounds up to $4, setting aside $0.60. When $5 is set aside, it buys \(setting.target.symbol).")
    }

    /// ONE gutter for this card's limit sentence; sized to the widest glue,
    /// "up to". Move and the keys walk share `MoveSentence.gutter`, a
    /// narrower one, on their own screens.
    static let sentenceGutter: CGFloat = 76

    static func target(_ listed: YourAccountTokens.Listed, on net: YourAccountOp.Network) -> RoundUps.Target {
        RoundUps.Target(chainId: net.chainId, address: listed.token.contract ?? YourAccountSwap.native,
                        symbol: listed.token.symbol, decimals: listed.token.decimals, network: net.name)
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
        names(list.map(\.network))
    }

    private func names(_ list: [Op.Network]) -> String {
        list.map(\.name).formatted(.list(type: .and))
    }

    /// **A READ THAT FAILED IS NOT A FACT (prd §1549, user, on a Keys card
    /// reading "Signs from · Use on this iPhone" and "Activates on first
    /// move" for an account this phone made: "now it's acting like i haven't
    /// activated my account").** Every key row says what every network
    /// answered, so until each one has answered every read, the rows say
    /// "Reading…" or "Couldn't read" and offer nothing: a failed key read
    /// had offered to move the account's key here, a transaction resting on
    /// a timeout. nil once every network answered.
    private var unsettled: String? {
        if !unread.isEmpty { return reading ? String(localized: "Reading…") : String(localized: "Couldn't read") }
        if standings.isEmpty { return String(localized: "Reading…") }
        return nil
    }

    /// Who signs: this device, your other one, or both — the fact alone (the
    /// key index and "a new key with every send" read as technical, §1496).
    private var deviceValue: String {
        if let unsettled { return unsettled }
        let here = live.filter { $0.keyIndex != nil }
        let elsewhere = live.filter { $0.keyIndex == nil }
        if live.isEmpty || elsewhere.isEmpty { return ThisDevice.title }
        if here.isEmpty { return String(localized: "Your other device") }
        return String(localized: "\(ThisDevice.title) and another")
    }

    /// Networks another device signs on that the recovery key can move here.
    private var movable: [Standing] {
        live.filter { $0.keyIndex == nil && $0.recovery == .added }
    }
    private var canMoveHere: Bool { unsettled == nil && hasRecoveryKey && !movable.isEmpty }

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

    /// Where the recovery key is: iCloud Keychain once it stands anywhere (or
    /// rides the first send there); "Not yet on …" in amber where this phone
    /// can still put it (Finish stands beside); nothing beside Set up.
    private var recoveryValue: (text: String?, tone: Color) {
        if let unsettled { return (unsettled, DS.textSecondary) }
        let on = standings.filter { $0.recovery == .added }
        if !recoveryTargets.isEmpty, !on.isEmpty {
            return (String(localized: "Not yet on \(names(recoveryTargets))"), DS.attentionInk)
        }
        if on.isEmpty, recoveryTargets.isEmpty, !recoveryRides.isEmpty {
            return (String(localized: "iCloud Keychain"), DS.textSecondary)
        }
        if on.isEmpty { return (recoveryVerb == nil ? String(localized: "Not set up") : nil, DS.attentionInk) }
        return (String(localized: "iCloud Keychain"), DS.textSecondary)
    }

    private var recoveryVerb: String? {
        guard unsettled == nil, !recoveryTargets.isEmpty else { return nil }
        return standings.contains { $0.recovery == .added } ? String(localized: "Finish") : String(localized: "Set up")
    }

    // MARK: - Reading

    /// **READ UNTIL EVERY NETWORK ANSWERS (prd §1548, §1549; user: "whenever
    /// I open the app in account, it always shows reading, but if I tap
    /// holdings and then go back, it's there").** At launch Tor is still
    /// connecting, so the first read times out and nothing asked again until
    /// a remount. The unread networks are asked again — 2s, then doubling to
    /// every 30s — for as long as the page is on screen; leaving it cancels
    /// the loop. Tor reporting ready asks at once (the `onChange` above); this
    /// covers a Tor that reads ready over circuits too slow to answer.
    private func readUntilAnswered() async {
        await read()
        var pause: Duration = .seconds(2)
        while !Task.isCancelled, !unread.isEmpty {
            NSLog("moveSecurity| unread %@, again in %@", unread.map(\.name).joined(separator: ","), "\(pause)")
            try? await Task.sleep(for: pause)
            guard !Task.isCancelled, !unread.isEmpty else { return }
            if !reading { await read(unread) }
            pause = min(pause * 2, .seconds(30))
        }
    }

    /// Reads `nets` and returns the ones that did not answer (§1549).
    @discardableResult
    private func read(_ nets: [Op.Network] = Op.networks) async -> [Op.Network] {
        // The demo's account (§1475): every network on, its key here, the
        // recovery key and a Signer on, the limit standing — read off no node,
        // and nothing of it noted for this phone's own account.
        if YourAccountDemo.isDemo(account) {
            hasRecoveryKey = true
            let now = Int(Date().timeIntervalSince1970)
            standings = Op.networks.filter { !$0.isTest }.map { net in
                let plan = YourAccountDemo.plan(on: net)
                return Standing(network: net, deployed: true, keyIndex: 3, recovery: .added,
                                outside: [YourAccountDemo.signer], exported: [], threshold: 2,
                                limit: .on(plan, current: plan.window(at: now)))
            }
            return []
        }
        let recovery = YourAccountRecovery.publicKey(for: account)
        hasRecoveryKey = recovery != nil
        reading = true
        defer { reading = false }
        let signer = try? await recovery.asyncMap { try await Chain.recoverySigner(x: $0.x, y: $0.y) }
        // A recovery key whose signer could not be read leaves its standing
        // unknown on every network it could be on (§1549).
        let signerUnread = recovery != nil && signer == nil
        var found: [Standing] = []
        var failed: Set<Int> = []
        // Each network answers a Standing, or nil when ANY of its reads
        // failed (§1549): a failed key read is not another device signing,
        // a failed owners read is not a missing recovery key or co-signer.
        await withTaskGroup(of: (Int, Standing?).self) { group in
            for net in nets {
                group.addTask {
                    guard let deployed = try? await Chain.isDeployed(net, account) else { return (net.chainId, nil) }
                    guard deployed else {
                        return (net.chainId, Standing(network: net, deployed: false, keyIndex: nil, recovery: .notThere,
                                                      outside: [], exported: [], threshold: nil, limit: nil))
                    }
                    guard !signerUnread else { return (net.chainId, nil) }
                    // **ASKED AT ONCE, EACH ONCE.** Every read here went one
                    // after another over Tor (~1–2s each), and the recovery
                    // state and the limit asked the code, the owners and the
                    // threshold again: eleven round trips a network before the
                    // page said anything. The owners answer the recovery key
                    // too; the threshold feeds the limit.
                    async let configured = Chain.configuredX(net, account)
                    async let ownersRead = Chain.owners(net, account)
                    async let spending = Self.spending(net, account)
                    let x: [UInt8]?
                    do { x = try await configured } catch { return (net.chainId, nil) }
                    let all: [String]
                    do { all = try await ownersRead } catch { return (net.chainId, nil) }
                    // This phone's only if it can still sign with it.
                    var index: Int?
                    if let x, let i = YourAccountKey.index(matchingX: x), YourAccountKey.holds(i) {
                        index = i
                    }
                    var state: Chain.RecoveryState = .missing
                    if let signer {
                        state = all.contains { $0.caseInsensitiveCompare(signer) == .orderedSame } ? .added : .missing
                    }
                    var exported: [String] = []
                    var asked: [String] = []
                    for owner in all where owner.caseInsensitiveCompare(YourAccount.sharedSigner) != .orderedSame {
                        if YourAccountExport.isExported(owner, for: account) { exported.append(owner) }
                        else { asked.append(owner) }
                    }
                    let isContract = await IngestSupport.boundedGather(asked, maxConcurrent: 6) {
                        try? await Chain.isContract(net, $0)
                    }
                    guard !isContract.contains(where: { $0 == nil }) else { return (net.chainId, nil) }
                    let outside = zip(asked, isContract).filter { $0.1 == false }.map { $0.0 }
                    let (threshold, limit) = await spending
                    guard threshold != nil else { return (net.chainId, nil) }
                    return (net.chainId, Standing(network: net, deployed: deployed, keyIndex: index, recovery: state,
                                                  outside: outside, exported: exported, threshold: threshold, limit: limit))
                }
            }
            for await (id, s) in group {
                if let s { found.append(s) } else { failed.insert(id) }
            }
        }
        // A network not asked this time keeps what it last said, read or
        // unread; one asked that failed drops its standing (§1549).
        let asked = Set(nets.map(\.chainId))
        let wasUnread = Set(unread.map(\.chainId))
        found += standings.filter { !asked.contains($0.network.chainId) }
        let order = Op.networks.map(\.chainId)
        standings = found.sorted { (order.firstIndex(of: $0.network.chainId) ?? 0) < (order.firstIndex(of: $1.network.chainId) ?? 0) }
        unread = Op.networks.filter { failed.contains($0.chainId) || (!asked.contains($0.chainId) && wasUnread.contains($0.chainId)) }
        // Nothing is noted for the Wallet from a read with a gap in it: the
        // nudges and the Signers figure wait for every network (§1549).
        if unread.isEmpty {
            // The Wallet's Needs you asks for an outside key until every network
            // the account is on has one (prd §1432); an exported key is one
            // (prd §1493: the same way out, held in another wallet).
            let live = standings.filter(\.deployed)
            YourAccountKey.noteOutsideKey(held: !live.isEmpty && live.allSatisfy { !$0.outside.isEmpty || !$0.exported.isEmpty })
            // The box's Signers figure (prd §1462): distinct keys across the networks.
            YourAccountFacts.noteSigners(Set(live.flatMap(\.outside).map { $0.lowercased() }).count)
            // And for the recovery key where money sits (prd §1442m), so Finish
            // clears the nudge as soon as it lands.
            await YourAccountProtection.check(force: true)
        }
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
        return nets.filter { failed.contains($0.chainId) }
    }

    /// How many keys a send needs on `net`, then the limit that implies: one
    /// chain of reads, run beside the key and the owners.
    private static func spending(_ net: Op.Network, _ account: String) async -> (threshold: Int?, limit: Chain.LimitState?) {
        let threshold = try? await Chain.threshold(net, account)
        let limit = threshold == 2 ? try? await Chain.limitState(net, account, threshold: 2) : .off
        return (threshold, limit)
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
        limitNetworks.flatMap(\.outside).first.map(YourAccount.short) ?? String(localized: "your co-signer")
    }

    /// **ONE SWITCH FOR EVERY NETWORK (prd §1455, user: "we want one switch
    /// for all networks").** One amount and one period, set on each network
    /// the account is on — each its own transaction, because each network
    /// keeps its own copy of the account — with what it comes to in all said
    /// beside it.
    @ViewBuilder private var spendLimit: some View {
        if !unread.isEmpty, let unsettled {
            // Neither on nor off until every network answered (§1549).
            row(title: String(localized: "Spend limit"), value: unsettled, verb: nil)
        } else if limitNetworks.isEmpty, let limit = setup?.limit, !unopened.isEmpty {
            // Chosen at Create, landing with the first send (prd §1457).
            row(title: String(localized: "Spend limit"),
                value: String(localized: "\(MoveSentence.money(Double(limit.dollars))) a \(LimitPeriod.of(seconds: limit.minutes * 60).word)"),
                verb: nil)
        } else if !limitNetworks.isEmpty {
            limitRow
            if limitEditing { limitSentence }
        }
    }

    /// The row's one word: the amount and period in the pick's ink, opening
    /// the menu (Change, Finish where it is not yet, Turn off); Off opens the
    /// amount; "Add a co-signer first" grey, because over the limit a send
    /// waits on that key (prd §1455).
    private var limitRow: some View {
        HStack(spacing: DS.Space.s3) {
            Text("Spend limit").dsText(.body17).foregroundStyle(DS.textPrimary)
            Spacer(minLength: DS.Space.s2)
            if working?.row == "limit" {
                Text(verbatim: working!.label).dsText(.body17).foregroundStyle(DS.textTertiary)
                    .lineLimit(1).frame(minHeight: 44)
            } else if (limited.isEmpty && notYet.isEmpty) {
                Text("Add a co-signer first").dsText(.body17).foregroundStyle(DS.textTertiary)
                    .lineLimit(1).frame(minHeight: 44)
            } else {
                Menu {
                    if limited.isEmpty {
                        Button { openLimit() } label: { Label(String(localized: "Set a limit"), systemImage: "plus") }
                    } else {
                        Button { openLimit() } label: { Label(String(localized: "Change"), systemImage: "pencil") }
                        if !notYet.isEmpty {
                            Button { finishLimit() } label: {
                                Label(String(localized: "Finish on \(notYet.map(\.network.name).formatted(.list(type: .and)))"),
                                      systemImage: "checkmark")
                            }
                        }
                        Button(role: .destructive) { turnOffLimit() } label: {
                            Label(String(localized: "Turn off"), systemImage: "xmark")
                        }
                    }
                } label: {
                    Text(verbatim: limitWord)
                        .dsText(.body17)
                        .foregroundStyle(notYet.isEmpty || limitEditing ? DS.pickInk : DS.attentionInk)
                        .contentTransition(.opacity)
                        .lineLimit(1)
                        .frame(minHeight: 44)
                }
                .layoutPriority(1)
                .accessibilityLabel(Text("Spend limit, \(limitWord)"))
            }
        }
        .walletRowPitch()
    }

    /// "$100 a month", or Off; "Set below" while the amount is being typed.
    private var limitWord: String {
        if limitEditing { return String(localized: "Set below") }
        guard let standing = shown else { return String(localized: "Off") }
        // A limit is whole dollars (`amountDollars`), so it says no cents.
        let usd = Op.dollars(standing.dollarCap, decimals: 6, price: 1)
        let amount = usd == usd.rounded() ? "$\(Int(usd))" : dollars(standing.dollarCap)
        let word = String(localized: "\(amount) a \(period(of: standing).word)")
        // **A NETWORK WITHOUT IT IS SAID ON THE ROW (user, 2026-10-27: Base
        // read one key under "$100 a month", its Finish only in the menu).**
        guard !notYet.isEmpty else { return word }
        return word + " · " + String(localized: "not on \(notYet.map(\.network.name).formatted(.list(type: .and)))")
    }

    /// On, or a new amount: the sentence opens with the amount focused.
    private func openLimit() {
        guard !limitEditing else { return }
        withAnimation(DS.Motion.standard) { limitEditing = true; amountText = ""; period = .month }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            amountFocused = true
        }
    }

    private func period(of plan: YourAccount7579.Plan) -> LimitPeriod {
        LimitPeriod.of(seconds: plan.windows.first.map { $0.until - $0.from } ?? 0)
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

    /// The co-signer: its short address (or how many), "Not yet on …" in
    /// amber where it still has to go (Finish stands beside), nothing beside
    /// Add. A key chosen at Create and on no network yet says when it lands,
    /// never its address alone, which read as a key already standing (prd
    /// §1499; user: "it connects, but it doesn't sign"), and never "Waiting",
    /// which reads as waiting on the wallet to sign.
    private var outsideValue: (text: String?, tone: Color) {
        if let unsettled { return (unsettled, DS.textSecondary) }
        let keys = Set(live.flatMap(\.outside).map { $0.lowercased() })
        let who: String
        if let one = keys.first {
            who = keys.count == 1 ? YourAccount.short(one) : String(localized: "\(keys.count) keys")
        } else if let chosen = setup?.signer {
            if outsideTargets.isEmpty, !signerRides.isEmpty {
                return (String(localized: "Activates on first move"), DS.textSecondary)  // prd §1501: the flow's one word
            }
            who = YourAccount.short(chosen)
        } else {
            return (nil, DS.textSecondary)
        }
        if !outsideTargets.isEmpty { return (String(localized: "Not yet on \(names(outsideTargets))"), DS.attentionInk) }
        return (who, DS.textSecondary)
    }

    /// The networks the account is on, said once (§1496); the ones that did
    /// not answer, by name, in their place (§1549).
    private var networksValue: String {
        if !unread.isEmpty {
            return reading ? String(localized: "Reading…") : String(localized: "Couldn't read \(names(unread))")
        }
        if standings.isEmpty { return String(localized: "Reading…") }
        return live.isEmpty ? String(localized: "None yet") : names(live)
    }

    private var networksShort: String? {
        if !unread.isEmpty { return unread.count > 1 && !reading ? String(localized: "Couldn't read \(unread.count) networks") : nil }
        return live.count > 1 ? String(localized: "\(live.count) networks") : nil
    }

    private var outsideVerb: String? {
        guard unsettled == nil else { return nil }
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
        // A typed address is a key only once its wallet signs for it (prd
        // §1516); the one chosen at Create signed then.
        let typed = addingOutside
        working = (String(localized: "Co-signer"), typed ? String(localized: "Waiting for your wallet…") : String(localized: "Adding…"))
        Task {
            if typed {
                do {
                    try await SignerRequestSheet.prove(signer: owner, on: YourAccountOp.networks.filter { !$0.isTest }.map(\.chainId),
                                                       account: account)
                } catch {
                    working = nil
                    chrome.flash(SignerRequestSheet.proofWords(error)
                                 ?? String(localized: "No wallet connected, so nothing was added"), tone: .failure, seconds: 6)
                    return
                }
                working = (String(localized: "Co-signer"), String(localized: "Adding…"))
            }
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
                chrome.flash(String(localized: "Co-signer on \(done.formatted(.list(type: .and)))"), tone: .success)
            } else {
                chrome.flash(failed.joined(separator: " · "), tone: done.isEmpty ? .failure : .neutral, seconds: 6)
            }
        }
    }

    // MARK: - The private key (prd §1493)

    /// Where Export puts the key: every network the account can be on but
    /// Robinhood, created where it is not there yet (§1427's rule).
    private var exportTargets: [Standing] {
        standings.filter { YourAccountExport.eligible($0.network) && canFix($0) }
    }
    /// The exported key on chain, one at a time: Remove comes before another.
    private var exportedKey: String? { live.flatMap(\.exported).first }

    /// The exported key's short address once one is out; nothing beside
    /// Export; "None" where there is nothing to export yet.
    private var exportValue: String? {
        if let unsettled { return unsettled }
        if let key = exportedKey { return YourAccount.short(key) }
        return exportTargets.isEmpty ? String(localized: "None") : nil
    }

    private var exportVerb: String? {
        guard unsettled == nil else { return nil }
        if exportedKey != nil { return String(localized: "Remove") }
        return exportTargets.isEmpty ? nil : String(localized: "Export")
    }

    private func export() {
        if demoSays() { return }
        guard working == nil, !exportTargets.isEmpty else { return }
        MoveExportKey.present(account: account, networks: exportTargets.map(\.network)) {
            Task { await read() }
        }
    }

    /// Off every network it is on, one Face ID each.
    private func removeExported() {
        if demoSays() { return }
        guard working == nil, let key = exportedKey else { return }
        let on = live.filter { s in s.exported.contains { $0.caseInsensitiveCompare(key) == .orderedSame } }.map(\.network)
        working = (String(localized: "Private key"), String(localized: "Removing…"))
        Task {
            let failed = await MoveExportKey.remove(key, account: account, from: on)
            working = nil
            await read()
            if failed.isEmpty {
                chrome.flash(String(localized: "Private key removed"), tone: .success)
            } else {
                chrome.flash(failed.joined(separator: " · "), tone: .failure, seconds: 6)
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
        working = (String(localized: "Signs from"), String(localized: "Setting up…"))
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
            DSFeedRow(name: String(localized: "Add a co-signer"),
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
