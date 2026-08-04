import Foundation
import SwiftData

/// The preparing surface (2026-07-17, prd §112) — the smart-account line the
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
///
/// Permit2 grants (2026-07-20, `wallet:permit2:` refs) ride the same pipeline
/// with two swaps: the live-state read calls Permit2's own
/// `allowance(owner,token,spender)` (selector `0x927da105`, verified against
/// 4byte.directory) instead of the token's plain `allowance`, and the revoke
/// calldata calls Permit2's own `approve(token,spender,0,0)` (selector
/// `0x87517c45`, verified against Uniswap's `IAllowanceTransfer.sol` docs and
/// cross-checked on 4byte.directory) instead of the token's `approve`.
enum WalletPrepare {

    struct Check {
        /// The grant as of the read, not as of the event.
        let active: Bool
        /// An operator grant (ApprovalForAll) vs an ERC-20 allowance.
        let forAll: Bool
        /// The live allowance, in the token's RAW units (2026-08-03, prd §292).
        ///
        /// This read has always happened — `active` is literally this number
        /// tested against zero — and the amount was discarded on the way out.
        /// `WalletApprovalExposure` needs it to answer "how much can they
        /// actually move", which is the difference between a grant you should
        /// look at and one you shouldn't. Zero for a `forAll` grant: an
        /// operator approval has no amount, and reporting 0 as if it were a
        /// small allowance would rank the most dangerous grant in the list
        /// last. Callers must branch on `forAll` first.
        var allowanceRaw: Double = 0
        /// The approved token's contract, lowercased — refetched from the log
        /// on every check (it isn't stored on the thing) and passed out so the
        /// exposure read can price the grant without repeating the receipt
        /// read. nil for a check that failed before the log was resolved.
        var contract: String?
        /// The chain the grant lives on, as this app names it ("base-mainnet")
        /// — carried for the same reason as `contract`.
        var network: String?
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
        let ref = thing.sourceRef ?? ""
        return (ref.hasPrefix("wallet:approval:") || ref.hasPrefix("wallet:permit2:"))
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
        // Build 256: a detached Task runs LATER than it was created, so this
        // row can already be deleted by the time this line does (prd §297).
        guard thing.isLive else { return .fail("That thing is no longer here.") }
        // sourceRef: "wallet:approval:<network>:<txHash>:<logIndex>" or
        // "wallet:permit2:<network>:<txHash>:<logIndex>".
        guard applies(to: thing),
              let parts = thing.sourceRef?.split(separator: ":"), parts.count == 5,
              let logIndex = Int(parts[4]),
              let owner = thing.walletAddress?.lowercased(),
              let spender = thing.counterpartyAddress?.lowercased(),
              ENS.isHexAddress(owner), ENS.isHexAddress(spender)
        else { return .fail("not an approval thing") }
        let network = String(parts[2]), txHash = String(parts[3])
        let viaPermit2 = parts[1] == "permit2"
        guard let chainId = WalletApprovals.chainId(forNetwork: network)
        else { return .fail("unknown chain \(network)") }
        // The person's chain toggle holds here too — a chain switched off in
        // the Wallet screen spends no prepare reads either. The sheet just
        // shows no card; the thing's Revoke.cash content link still works.
        guard WalletChainStore.activeNetworkIDs().contains(network)
        else { return .fail("chain switched off") }
        let revokeURL = WalletApprovals.revokeURL(address: owner, chainId: chainId)

        // The event's log, refetched — the token contract lives only there
        // (and for a Permit2 grant, the log itself lives at Permit2's address,
        // not the token's).
        guard let receipt = await WalletApprovals.rpcRead(
                network: network, method: "eth_getTransactionReceipt",
                params: [txHash]) as? [String: Any],
              let logs = receipt["logs"] as? [[String: Any]],
              let log = logs.first(where: { entry in
                  // A missing index must not read as 0 — logIndex 0 is real.
                  guard let hex = entry["logIndex"] as? String else { return false }
                  return WalletIngest.hexToInt(hex) == logIndex
              }),
              let topics = log["topics"] as? [String]
        else { return .fail("receipt unreadable") }

        // The log must be THIS wallet's grant — a drifted index would
        // otherwise dress a stranger's approval in this thing's words. The
        // shape differs by mechanism: Permit2's own event names the token in
        // topics[2] (its own address is topics[0]'s log address, not the
        // asset); the plain ERC-20/ForAll event names the asset as the log's
        // own address and the spender in topics[2].
        let contract: String
        let forAll: Bool
        if viaPermit2 {
            guard topics.count >= 4,
                  topics[1].lowercased().hasSuffix(String(owner.dropFirst(2))),
                  topics[3].lowercased().hasSuffix(String(spender.dropFirst(2)))
            else { return .fail("log/thing mismatch") }
            contract = "0x" + topics[2].suffix(40).lowercased()
            forAll = false
        } else {
            guard topics.count >= 3, let logContract = (log["address"] as? String)?.lowercased(),
                  topics[1].lowercased().hasSuffix(String(owner.dropFirst(2))),
                  topics[2].lowercased().hasSuffix(String(spender.dropFirst(2)))
            else { return .fail("log/thing mismatch") }
            contract = logContract
            forAll = topics[0].lowercased() == WalletApprovals.forAllTopic
        }

        // The grant's live state: allowance(owner, spender) on the token,
        // isApprovedForAll(owner, operator) on the collection, or Permit2's
        // OWN allowance(owner, token, spender) on Permit2 itself — three
        // reads, one shape.
        let stateTarget = viaPermit2 ? WalletApprovals.permit2Address : contract
        let stateData = viaPermit2
            ? "0x927da105" + pad(owner) + pad(contract) + pad(spender)
            : (forAll ? "0xe985e9c5" : "0xdd62ed3e") + pad(owner) + pad(spender)
        guard let stateHex = await WalletApprovals.rpcRead(
                network: network, method: "eth_call",
                params: [["to": stateTarget, "data": stateData], "latest"]) as? String,
              // A revert / empty reply is "0x", which parses to the same 0 as
              // a genuine revoke — only a full reply is a real answer. Fail
              // CLOSED (no card) rather than dress a failed read as
              // "revoked" (review 2026-07-17; WalletApprovals' own lesson 2).
              // Permit2's `allowance` returns THREE packed words, not one
              // (tightened in review 2026-07-20 — a truncated reply short of
              // all three shouldn't parse its first word as a real answer).
              stateHex.count >= (viaPermit2 ? 2 + 64 * 3 : 66)
        else { return .fail("state unreadable") }
        // Permit2's `allowance` returns THREE packed words (amount,
        // expiration, nonce) — only the first says whether the grant is
        // live, so reading the whole reply as one number would be wrong
        // (unlike the single-word ERC-20/ForAll replies).
        //
        // The amount is kept, not just its sign (2026-08-03) — see
        // `Check.allowanceRaw`. A `forAll` grant's state reply is a BOOL word
        // (`isApprovedForAll`), so its "1" is a flag and not an allowance of
        // one wei; it stays 0 here and callers branch on `forAll`.
        let allowanceRaw = forAll ? 0 : (viaPermit2 ? firstWord(stateHex)
                                                    : WalletIngest.hexToDouble(stateHex))
        let active = forAll ? WalletIngest.hexToDouble(stateHex) > 0 : allowanceRaw > 0
        guard active else {
            return .ok(Check(active: false, forAll: forAll, allowanceRaw: 0,
                             contract: contract, network: network, feeLine: nil,
                             transactionJSON: nil, revokeURL: revokeURL))
        }

        // The revoke, encoded: approve(spender, 0) / setApprovalForAll(
        // operator, false) / Permit2's own approve(token, spender, 0, 0) —
        // the zero word(s) serve all three.
        let zeroWord = String(repeating: "0", count: 64)
        let calldata: String
        let toContract: String
        if viaPermit2 {
            calldata = "0x87517c45" + pad(contract) + pad(spender) + zeroWord + zeroWord
            toContract = WalletApprovals.permit2Address
        } else {
            calldata = (forAll ? "0xa22cb465" : "0x095ea7b3") + pad(spender) + zeroWord
            toContract = contract
        }
        let json = """
        {"chainId": \(chainId), "data": "\(calldata)", "from": "\(owner)", \
        "to": "\(toContract)", "value": "0x0"}
        """

        // The fee — estimateGas doubles as a dry run (a reverting revoke
        // fails the estimate), so a quoted fee also means "would succeed".
        // The two reads are independent — one round-trip's wait, not two.
        async let gasRead = WalletApprovals.rpcRead(
            network: network, method: "eth_estimateGas",
            params: [["from": owner, "to": toContract, "data": calldata]])
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
        return .ok(Check(active: true, forAll: forAll, allowanceRaw: allowanceRaw,
                         contract: contract, network: network, feeLine: feeLine,
                         transactionJSON: json, revokeURL: revokeURL))
    }

    /// The first 32-byte word of a multi-word `eth_call` return — Permit2's
    /// `allowance` packs three (amount, expiration, nonce); only the first
    /// says whether a grant is live.
    private static func firstWord(_ hex: String) -> Double {
        var s = hex.lowercased(); if s.hasPrefix("0x") { s.removeFirst(2) }
        guard s.count >= 64 else { return 0 }
        return WalletIngest.hexToDouble("0x" + s.prefix(64))
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
