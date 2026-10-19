import SwiftUI

/// **SECURITY (prd §1427): the Move page's last module**, the canvas's rows —
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
        var id: Int { network.chainId }
    }

    @State private var standings: [Standing] = []
    @State private var hasRecoveryKey = false
    @State private var working: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Security")
                .dsText(.heading20)
                .foregroundStyle(DS.headInk)
                .frame(minHeight: 44, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            row(title: String(localized: "This iPhone"), line: deviceLine,
                verb: canMoveHere ? (String(localized: "Move here"), moveHere) : nil)
            row(title: String(localized: "Recovery key"), line: recoveryLine,
                verb: recoveryVerb.map { ($0, setUp) })
            row(title: String(localized: "Rotate"), line: rotateLine, verb: nil)
        }
        .task(id: account) { await read() }
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
                    Text(verbatim: working ?? word)
                        .dsText(.body17)
                        .foregroundStyle(working == nil ? DS.pickInk : DS.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(minHeight: 44)
                }
                .buttonStyle(RowPress())
                .disabled(working != nil)
            }
        }
        .frame(minHeight: 60)
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
        if elsewhere.isEmpty { return String(localized: "Signs on \(names(here))") }
        if here.isEmpty { return String(localized: "Another device signs on \(names(elsewhere))") }
        return String(localized: "Signs on \(names(here)) · another device on \(names(elsewhere))")
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
        guard let highest else { return String(localized: "A new key with every send") }
        return String(localized: "A new key with every send · key \(highest)")
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
                    return Standing(network: net, deployed: deployed, keyIndex: index, recovery: state)
                }
            }
            for await s in group { if let s { found.append(s) } }
        }
        let order = Op.networks.map(\.chainId)
        standings = found.sorted { (order.firstIndex(of: $0.network.chainId) ?? 0) < (order.firstIndex(of: $1.network.chainId) ?? 0) }
    }

    // MARK: - Acting

    /// Put the recovery key on every network it is missing from, one signed
    /// operation each; a network that cannot pay its fee is named, not fatal.
    private func setUp() {
        guard working == nil else { return }
        let targets = missing.map(\.network)
        working = String(localized: "Setting up…")
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
        working = String(localized: "Moving…")
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
                chrome.flash(String(localized: "Your account signs on this iPhone"), tone: .success)
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
                    on: net, to: index, reason: String(localized: "Move your account to this iPhone on \(net.name)")) { _ in }
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
