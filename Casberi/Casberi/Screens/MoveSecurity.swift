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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(title: ThisDevice.title, line: deviceLine,
                verb: canMoveHere ? (ThisDevice.use, moveHere) : nil)
            row(title: String(localized: "Recovery key"), line: recoveryLine,
                verb: recoveryVerb.map { ($0, setUp) })
            row(title: String(localized: "Outside key"), line: outsideLine,
                verb: addingOutside ? nil : outsideVerb.map { word in
                    // Add opens the field; Finish puts the key already on one
                    // network on the rest.
                    (word, { if live.allSatisfy({ $0.outside.isEmpty }) {
                        withAnimation(DS.Motion.standard) { addingOutside = true }
                    } else { addOutside() } })
                })
            if addingOutside { outsideField }
        }
        // Read again whenever a send lands (`MoveSend` bumps the rooms'
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

    private var recoveryLine: String {
        if standings.isEmpty { return String(localized: "Reading…") }
        let on = standings.filter { $0.recovery == .added }
        if on.isEmpty { return String(localized: "Not set up · for a new iPhone") }
        if missing.isEmpty { return String(localized: "On \(names(on))") }
        return String(localized: "On \(names(on)) · not yet on \(names(missing))")
    }

    private var recoveryVerb: String? {
        guard !standings.isEmpty, !missing.isEmpty else { return nil }
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
                    return Standing(network: net, deployed: deployed, keyIndex: index, recovery: state, outside: outside)
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
    }

    // MARK: - The outside key (prd §1432)

    private var outsideLine: String {
        if standings.isEmpty { return String(localized: "Reading…") }
        let keys = Set(live.flatMap(\.outside).map { $0.lowercased() })
        let on = live.filter { !$0.outside.isEmpty }
        let missing = standings.filter { $0.outside.isEmpty }
        guard let one = keys.first else {
            return String(localized: "None · a wallet of yours, so the account never depends on this app")
        }
        let who = keys.count == 1 ? YourAccount.short(one) : String(localized: "\(keys.count) keys")
        if missing.isEmpty { return String(localized: "\(who) · on \(names(on))") }
        return String(localized: "\(who) · not yet on \(names(missing))")
    }

    private var outsideVerb: String? {
        guard !standings.isEmpty else { return nil }
        if live.allSatisfy({ $0.outside.isEmpty }) { return String(localized: "Add") }
        return standings.contains { $0.outside.isEmpty } ? String(localized: "Finish") : nil
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
        let targets = standings.filter { $0.outside.isEmpty }.map(\.network)
        working = (String(localized: "Outside key"), String(localized: "Adding…"))
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
                chrome.flash(String(localized: "Outside key on \(done.formatted(.list(type: .and)))"), tone: .success)
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
        let targets = missing.map(\.network)
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
            DSFeedRow(name: String(localized: "Add a key you hold outside Casberi"),
                      line: Text("So your account never depends on this app")) {
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
