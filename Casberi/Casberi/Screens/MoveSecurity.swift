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
        /// This phone's allowance of the network's dollar on the module, in
        /// base units; nil when none.
        let allowance: YourAccountSigning.Allowance?
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
    @State private var limitOn = false
    @State private var amountText = ""
    @State private var period: LimitPeriod = .month
    @FocusState private var amountFocused: Bool

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
                    (word, { if live.allSatisfy({ $0.outside.isEmpty }) {
                        withAnimation(DS.Motion.standard) { addingOutside = true }
                    } else { addOutside() } })
                })
            if addingOutside { outsideField }
            // The spend limit (prd §1447) is NOT drawn (item 9): the phone's
            // key signs through Safe's shared signer, which answers only the
            // account itself, so it can never be the Allowance module's
            // delegate — and at 2-of-2 the 4337 module asks both keys of
            // every send. Turned on, every send would wait on the signer.
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "spendLimitOpen") { spendLimit }
            #endif
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
        .frame(minHeight: 60)
        // A line that wraps to two keeps the air between rows.
        .padding(.vertical, DS.Space.s1)
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

    private var recoveryLine: String {
        if standings.isEmpty { return String(localized: "Reading…") }
        let on = standings.filter { $0.recovery == .added }
        if on.isEmpty { return String(localized: "Not set up · if you lose this \(ThisDevice.name)") }
        // The networks only another device can open are the account's fact,
        // said once under the rows, not this key's.
        if fixable.isEmpty { return String(localized: "On \(names(on))") }
        return String(localized: "On \(names(on)) · not yet on \(names(fixable))")
    }

    private var recoveryVerb: String? {
        guard !standings.isEmpty, !fixable.isEmpty else { return nil }
        return standings.contains { $0.recovery == .added } ? String(localized: "Finish") : String(localized: "Set up")
    }

    private var rotateLine: String {
        let highest = live.compactMap(\.keyIndex).max()
        guard let highest else { return String(localized: "a new key with every send") }
        return String(localized: "a new key with every send · key \(highest)")
    }

    // MARK: - Reading

    private func read() async {
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
                    var allowance: YourAccountSigning.Allowance?
                    if deployed {
                        threshold = try? await Chain.threshold(net, account)
                        if threshold == 2 {
                            allowance = try? await Chain.allowance(net, account, delegate: YourAccount.sharedSigner, token: net.dollar)
                        }
                    }
                    return Standing(network: net, deployed: deployed, keyIndex: index, recovery: state, outside: outside,
                                    threshold: threshold, allowance: allowance)
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
        // And for the recovery key where money sits (prd §1442m), so Finish
        // clears the nudge as soon as it lands.
        await YourAccountProtection.check(force: true)
        #if DEBUG
        NSLog("spendLimit| both=%d single=%d hasSigner=%d thresholds=%@", both.count, single.count, hasSigner ? 1 : 0,
              standings.map { "\($0.network.name):\($0.threshold.map(String.init) ?? "-"):\($0.keyIndex.map(String.init) ?? "-")" }.joined(separator: ","))
        // `-spendLimitOpen YES`: the sentence open, as the switch turned on
        // opens it, because a simulator does not flip a switch.
        if UserDefaults.standard.bool(forKey: "spendLimitOpen"), both.isEmpty, !limitOn {
            withAnimation(DS.Motion.standard) { limitOn = true }
        }
        #endif
    }

    // MARK: - The spend limit (prd §1447)

    /// How often the limit starts again (user: "is there option to change
    /// month?"; "need per tx too!"): the module counts in minutes. Safe's
    /// Allowance module knows only an amount a period, so PER SEND is the
    /// amount a minute: each send spends up to it alone, and two inside one
    /// minute share it (the second waits on the signer).
    enum LimitPeriod: CaseIterable {
        case send, day, week, month
        var minutes: Int {
            switch self {
            case .send: 1
            case .day: 60 * 24
            case .week: 60 * 24 * 7
            case .month: 60 * 24 * 30
            }
        }
        var word: String {
            switch self {
            case .send: String(localized: "send")
            case .day: String(localized: "day")
            case .week: String(localized: "week")
            case .month: String(localized: "month")
            }
        }
        /// The sentence's glue for it: "a day", "per send".
        var glue: String { self == .send ? String(localized: "per") : String(localized: "a") }
        var phrase: String { glue + " " + word }
        /// The period a limit on the chain resets on, nearest of the three.
        static func of(minutes: Int) -> LimitPeriod {
            allCases.min { abs($0.minutes - minutes) < abs($1.minutes - minutes) } ?? .month
        }
    }

    /// The networks at 2-of-2, and at 1, among those this phone signs on.
    private var both: [Standing] { live.filter { $0.threshold == 2 } }
    private var single: [Standing] { live.filter { $0.threshold == 1 && $0.keyIndex != nil } }
    private var hasSigner: Bool { live.contains { !$0.outside.isEmpty } }
    private var signerShort: String { live.flatMap(\.outside).first.map(YourAccount.short) ?? String(localized: "your signer") }
    /// The limit the chain holds, where one does.
    private var held: YourAccountSigning.Allowance? { both.compactMap(\.allowance).first }

    /// Whole dollars, one or more; the dollar's units at six decimals.
    private var amountUnits: String? {
        let text = amountText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "$", with: "")
        guard let n = Int(text), n >= 1 else { return nil }
        return String(n) + "000000"
    }

    private func dollars(_ units: String) -> String {
        MoveSentence.money(Op.dollars(units, decimals: 6, price: 1))
    }

    /// The switch: on where the chain says 2-of-2, or while an amount is
    /// being set. Turning it on opens the amount; off before it is set drops
    /// it, nothing sent; off at 2-of-2 is itself a two-key transaction, and
    /// until the signer's half is built it says so and stays on (§83).
    private var limitBinding: Binding<Bool> {
        Binding(get: { !both.isEmpty || limitOn }, set: { on in
            if on, both.isEmpty {
                withAnimation(DS.Motion.standard) { limitOn = true; amountText = "" }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    amountFocused = true
                }
            } else if !on, both.isEmpty {
                withAnimation(DS.Motion.standard) { limitOn = false; amountText = "" }
                amountFocused = false
            } else if !on {
                chrome.flash(String(localized: "Turning it off needs \(signerShort) to sign too — coming next"), seconds: 5)
            }
        })
    }

    private var limitLine: String {
        if standings.isEmpty { return String(localized: "Reading…") }
        if let held {
            let every = LimitPeriod.of(minutes: held.resetMinutes)
            var line = String(localized: "Over \(dollars(held.amount)) \(every.phrase), \(signerShort) signs too")
            if held.spent != "0" { line += " · " + String(localized: "\(dollars(held.spent)) spent") }
            if held.resetMinutes > 1 {
                let reset = Date(timeIntervalSince1970: TimeInterval((held.lastReset + held.resetMinutes) * 60))
                line += " · " + String(localized: "resets \(reset.formatted(.dateTime.month(.abbreviated).day()))")
            }
            return line
        }
        if !both.isEmpty { return String(localized: "\(signerShort) signs every send") }
        if limitOn { return String(localized: "Over it, \(signerShort) signs too") }
        if !hasSigner { return String(localized: "Off · add a signer to set one") }
        return String(localized: "Off · any one key signs")
    }

    @ViewBuilder private var spendLimit: some View {
        DSToggleRow(title: Text("Spend limit"), detail: Text(verbatim: limitLine), isOn: limitBinding)
            .disabled(standings.isEmpty || working != nil || (both.isEmpty && (!hasSigner || single.isEmpty)))
            .frame(minHeight: 60)
            .padding(.vertical, DS.Space.s1)
        if !both.isEmpty || limitOn { limitSentence }
    }

    /// The amount, as Move says things (§1438): the glue in the gutter, the
    /// value large, pink while it can be changed.
    private var limitSentence: some View {
        let editing = both.isEmpty
        return VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text("up to").dsText(.body17).foregroundStyle(DS.textPrimary).frame(width: 44, alignment: .leading)
                if editing {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(verbatim: "$").dsText(.heading28).foregroundStyle(DS.pickInk)
                        TextField("500", text: $amountText)
                            .keyboardType(.numberPad)
                            .focused($amountFocused)
                            .dsText(.heading28)
                            .foregroundStyle(DS.pickInk)
                            .tint(DS.pickInk)
                            .fixedSize()
                            .accessibilityLabel(Text("Dollars a month"))
                    }
                } else {
                    Text(verbatim: held.map { dollars($0.amount) } ?? "—").dsText(.heading28).foregroundStyle(DS.textPrimary)
                }
                Spacer(minLength: DS.Space.s2)
                if editing {
                    Button { setBothKeys() } label: {
                        Text(working?.row == "limit" ? working!.label : String(localized: "Set"))
                            .dsText(.body17)
                            .foregroundStyle(amountUnits == nil || working != nil ? DS.textTertiary : DS.pickInk)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(RowPress())
                    .disabled(amountUnits == nil || working != nil)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text(verbatim: editing ? period.glue : LimitPeriod.of(minutes: held?.resetMinutes ?? LimitPeriod.month.minutes).glue)
                    .dsText(.body17).foregroundStyle(DS.textPrimary).frame(width: 44, alignment: .leading)
                if editing {
                    // A blank of the sentence: pink, and its choices in a menu.
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
                } else {
                    Text(verbatim: LimitPeriod.of(minutes: held?.resetMinutes ?? LimitPeriod.month.minutes).word)
                        .dsText(.heading28).foregroundStyle(DS.textPrimary)
                }
            }
            Text(editing ? "with Face ID alone." : "with Face ID alone. A new amount needs both keys.")
                .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                .padding(.leading, 44 + DS.Space.s2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, DS.Space.s3)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// 2-of-2 above the amount, on every network this phone signs on at 1
    /// with a Signer: one operation each, the threshold last.
    private func setBothKeys() {
        guard working == nil, let units = amountUnits else { return }
        let targets = single.filter { !$0.outside.isEmpty }.map(\.network)
        guard !targets.isEmpty else { return }
        amountFocused = false
        working = ("limit", String(localized: "Setting…"))
        Task {
            var done: [String] = []
            var failed: [String] = []
            for net in targets {
                do {
                    let sent = try await Chain.setBothKeys(
                        on: net, token: net.dollar, amount: units, resetMinutes: period.minutes,
                        reason: String(localized: "Set a spend limit of \(dollars(units)) \(period.phrase) on \(net.name)")) { _ in }
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
            withAnimation(DS.Motion.standard) { limitOn = false; amountText = ""; period = .month }
            if failed.isEmpty {
                chrome.flash(String(localized: "Spend limit set on \(done.formatted(.list(type: .and)))"), tone: .success)
            } else {
                chrome.flash(failed.joined(separator: " · "), tone: done.isEmpty ? .failure : .neutral, seconds: 6)
            }
        }
    }

    // MARK: - The outside key (prd §1432)

    private var outsideLine: String {
        if standings.isEmpty { return String(localized: "Reading…") }
        let keys = Set(live.flatMap(\.outside).map { $0.lowercased() })
        let on = live.filter { !$0.outside.isEmpty }
        let missing = standings.filter { $0.outside.isEmpty }
        guard let one = keys.first else {
            return String(localized: "None · if you lose Casberi, a key in a wallet you hold signs instead")
        }
        let who = keys.count == 1 ? YourAccount.short(one) : String(localized: "\(keys.count) keys")
        // The networks only another device can open are said once under the
        // rows, never here.
        let here = missing.filter(canFix)
        if here.isEmpty { return String(localized: "\(who) · on \(names(on))") }
        return String(localized: "\(who) · not yet on \(names(here))")
    }

    private var outsideVerb: String? {
        guard !standings.isEmpty else { return nil }
        if live.allSatisfy({ $0.outside.isEmpty }) { return String(localized: "Add") }
        return standings.contains { $0.outside.isEmpty && canFix($0) } ? String(localized: "Finish") : nil
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
        guard working == nil, let owner = addingOutside ? outsideCandidate : live.flatMap(\.outside).first else { return }
        let targets = standings.filter { $0.outside.isEmpty && canFix($0) }.map(\.network)
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
        guard working == nil else { return }
        let targets = fixable.map(\.network)
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
/// you** — the Wallet's Home and the Feed's Wallet section — while your
/// account answers only to keys inside Casberi. A passkey signs only where
/// it was made, so the way out is a key the person holds elsewhere; the row
/// stands until every network the account is on has one, and opens the
/// Wallet's Security, where Outside key adds it (§1436). Same anatomy as the rows around it
/// (§1413 item 7): the account's face, a name, one line.
struct OutsideKeyNudge: View {
    @Environment(ShellChrome.self) private var chrome

    /// Drawn at all: the account needs the key.
    static var shown: Bool { YourAccountKey.needsOutsideKey }

    var body: some View {
        Button {
            DSHaptic.selection()
            chrome.openWalletSecurity(at: FeedScreen.SecurityAnchor.account.id)
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
            .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DSRoomChassis.rowInset,
                                      bottom: DS.Space.s2, trailing: DSRoomChassis.rowInset))
            .feedRowBackground()
            .listRowSeparator(.hidden)
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
            chrome.openWalletSecurity(at: FeedScreen.SecurityAnchor.account.id)
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
            .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DSRoomChassis.rowInset,
                                      bottom: DS.Space.s2, trailing: DSRoomChassis.rowInset))
            .feedRowBackground()
            .listRowSeparator(.hidden)
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
