import Foundation
import SwiftData

/// The preparing surface (2026-07-17, prd §111) — the smart-account line the
/// wallet bridge holds: Casberi READS on-chain state and PREPARES transactions,
/// and a signature always happens somewhere else (a wallet app, Revoke.cash).
/// Nothing here can move funds: every call is a keyless JSON-RPC read on the
/// hosts `WalletApprovals` already measured.
///
/// v1 is approvals — the one fact the corpus already surfaces with an obvious
/// undo. For an approval thing this computes:
///   1. the grant's LIVE state (allowance / isApprovedForAll, read now — a
///      "still active" the record alone can't know, and the honest close of
///      the loop after the person revokes elsewhere: the card flips to
///      "no longer active" from reads, never from a callback);
///   2. the revoke transaction, encoded (approve(spender, 0) /
///      setApprovalForAll(operator, false)) — copyable, for any wallet;
///   3. the network fee to run it (eth_estimateGas × eth_gasPrice), quoted in
///      the chain's native coin — omitted when the estimate couldn't be read,
///      never invented.
///
/// The token contract isn't stored on the thing, so the log is refetched by
/// the sourceRef's (txHash, logIndex) — one receipt read — and the owner topic
/// is checked against the thing's wallet before anything renders: a prepare
/// card built from someone else's log would be worse than none.
enum WalletPrepare {

    struct Check {
        /// The grant as of the read, not as of the event.
        let active: Bool
        /// An operator grant (ApprovalForAll) vs an ERC-20 allowance.
        let forAll: Bool
        /// "~0.00042 ETH" — the fee to revoke, nil when unreadable.
        let feeLine: String?
        /// The prepared revoke as a wallet-ready JSON object — nil when the
        /// grant is no longer active (nothing left to prepare).
        let transactionJSON: String?
        /// The wallet's Revoke.cash page, built from the thing's OWN fields
        /// (owner + chain) — the card's door never trusts `content` to be
        /// what its label claims (review 2026-07-17).
        let revokeURL: String
    }

    /// The cheap gate the sheet checks before spending any network read.
    static func applies(to thing: Thing) -> Bool {
        thing.sourceRef?.hasPrefix("wallet:approval:") == true
            && !(thing.walletAddress ?? "").isEmpty
            && !(thing.counterpartyAddress ?? "").isEmpty
    }

    @MainActor
    static func check(for thing: Thing) async -> Check? {
        if case .ok(let check) = await outcome(for: thing) { return check }
        return nil
    }

    /// The step-attributed result — the probe's honest line names WHICH read
    /// refused instead of a bare nil.
    enum Outcome {
        case ok(Check)
        case fail(String)
    }

    /// MainActor like `WalletApprovals.sync` — the model reads stay on main;
    /// only the RPC awaits hop off.
    @MainActor
    static func outcome(for thing: Thing) async -> Outcome {
        // sourceRef: "wallet:approval:<network>:<txHash>:<logIndex>"
        guard applies(to: thing),
              let parts = thing.sourceRef?.split(separator: ":"), parts.count == 5,
              let logIndex = Int(parts[4]),
              let owner = thing.walletAddress?.lowercased(),
              let spender = thing.counterpartyAddress?.lowercased(),
              ENS.isHexAddress(owner), ENS.isHexAddress(spender)
        else { return .fail("not an approval thing") }
        let network = String(parts[2]), txHash = String(parts[3])
        guard let chainId = WalletApprovals.chainId(forNetwork: network)
        else { return .fail("unknown chain \(network)") }
        // The person's chain toggle holds here too — a chain switched off in
        // the Wallet screen spends no prepare reads either. The sheet just
        // shows no card; the thing's Revoke.cash content link still works.
        guard WalletChainStore.activeNetworkIDs().contains(network)
        else { return .fail("chain switched off") }
        let revokeURL = WalletApprovals.revokeURL(address: owner, chainId: chainId)

        // The event's log, refetched — the token contract lives only there.
        guard let receipt = await WalletApprovals.rpcRead(
                network: network, method: "eth_getTransactionReceipt",
                params: [txHash]) as? [String: Any],
              let logs = receipt["logs"] as? [[String: Any]],
              let log = logs.first(where: { entry in
                  // A missing index must not read as 0 — logIndex 0 is real.
                  guard let hex = entry["logIndex"] as? String else { return false }
                  return Int(WalletIngest.hexToDouble(hex)) == logIndex
              }),
              let contract = (log["address"] as? String)?.lowercased(),
              let topics = log["topics"] as? [String], topics.count >= 3
        else { return .fail("receipt unreadable") }
        // The log must be THIS wallet's grant — a drifted index would
        // otherwise dress a stranger's approval in this thing's words.
        guard topics[1].lowercased().hasSuffix(String(owner.dropFirst(2))),
              topics[2].lowercased().hasSuffix(String(spender.dropFirst(2)))
        else { return .fail("log/thing mismatch") }
        let forAll = topics[0].lowercased() == WalletApprovals.forAllTopic

        // The grant's live state — allowance(owner, spender) or
        // isApprovedForAll(owner, operator), both plain view reads.
        let stateData = (forAll ? "0xe985e9c5" : "0xdd62ed3e")
            + pad(owner) + pad(spender)
        guard let stateHex = await WalletApprovals.rpcRead(
                network: network, method: "eth_call",
                params: [["to": contract, "data": stateData], "latest"]) as? String,
              // A revert / empty reply is "0x", which parses to the same 0 as
              // a genuine revoke — only a full 32-byte word is a real answer.
              // Fail CLOSED (no card) rather than dress a failed read as
              // "revoked" (review 2026-07-17; WalletApprovals' own lesson 2).
              stateHex.count >= 66
        else { return .fail("state unreadable") }
        let active = WalletIngest.hexToDouble(stateHex) > 0
        guard active else {
            return .ok(Check(active: false, forAll: forAll, feeLine: nil,
                             transactionJSON: nil, revokeURL: revokeURL))
        }

        // The revoke, encoded: approve(spender, 0) / setApprovalForAll(
        // operator, false) — the zero word serves both.
        let zeroWord = String(repeating: "0", count: 64)
        let calldata = (forAll ? "0xa22cb465" : "0x095ea7b3") + pad(spender) + zeroWord
        let json = """
        {"chainId": \(chainId), "data": "\(calldata)", "from": "\(owner)", \
        "to": "\(contract)", "value": "0x0"}
        """

        // The fee — estimateGas doubles as a dry run (a reverting revoke
        // fails the estimate), so a quoted fee also means "would succeed".
        // The two reads are independent — one round-trip's wait, not two.
        async let gasRead = WalletApprovals.rpcRead(
            network: network, method: "eth_estimateGas",
            params: [["from": owner, "to": contract, "data": calldata]])
        async let priceRead = WalletApprovals.rpcRead(
            network: network, method: "eth_gasPrice", params: [])
        var feeLine: String?
        if let gasHex = await gasRead as? String,
           let priceHex = await priceRead as? String {
            let fee = WalletIngest.hexToDouble(gasHex)
                * WalletIngest.hexToDouble(priceHex) / 1e18
            if fee > 0, let symbol = WalletIngest.nativeSymbol(forNetwork: network) {
                feeLine = "~\(WalletIngest.format(fee)) \(symbol)"
            }
        }
        return .ok(Check(active: true, forAll: forAll, feeLine: feeLine,
                         transactionJSON: json, revokeURL: revokeURL))
    }

    /// `-prepareProbe YES` — runs the whole path over the newest landed
    /// approval thing and reports each fact in one line. Reads only.
    @MainActor
    static func probe(context: ModelContext) async -> String {
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Wallet" },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.fetchLimit = 500
        let things = (try? context.fetch(descriptor)) ?? []
        guard let thing = things.first(where: { applies(to: $0) })
        else { return "FAILED (no approval things — land one with -approvalProbe)" }
        switch await outcome(for: thing) {
        case .fail(let step):
            return "FAILED (\(step)) ref=\(thing.sourceRef ?? "?")"
        case .ok(let check):
            return "active=\(check.active ? "YES" : "NO")"
                + " forAll=\(check.forAll ? "YES" : "NO")"
                + " fee=\(check.feeLine ?? "unread")"
                + " tx=\(check.transactionJSON.map { "\($0.count) chars" } ?? "none")"
                + " ref=\(thing.sourceRef ?? "?")"
        }
    }

    /// A hex address as a 32-byte ABI word.
    private static func pad(_ address: String) -> String {
        String(repeating: "0", count: 24) + address.dropFirst(2).lowercased()
    }
}
