import Foundation

/// When an Alchemy transfer happened, on the chains where Alchemy will not say
/// (prd §790, 2026-09-16).
///
/// `alchemy_getAssetTransfers` with `withMetadata: true` returns
/// `"metadata": null` on **HyperEVM and World Chain** — every category, every
/// transfer — while the seven other chains in `WalletIngest.allChains` carry
/// `metadata.blockTimestamp` (MEASURED 2026-09-16, three transfers per chain per
/// category). The ingest dated a missing time `?? .now`, so every transfer read
/// through Alchemy on those two chains — every NFT move, which rides Alchemy
/// unconditionally, and every fungible one while Zerion is unreachable — landed
/// stamped with the moment of the sync: a year-old mint reads as today's news,
/// and the feed's order is a lie about when money moved (§83).
///
/// The fix reads the time where it lives, on the block: one
/// `eth_getBlockByNumber` per distinct block, cached for the life of the
/// process because a mined block's timestamp never changes. A transfer whose
/// block could not be read is DROPPED from this pass rather than dated now —
/// nothing lands, so the next sync asks again, and a late row beats a wrong one.
///
/// Foundation-only, so `scripts/transfer-times-selftest.sh` compiles it whole.
enum TransferTimes {

    /// The blocks whose transfers carry no time, deduplicated in first-seen
    /// order. Alchemy spells a block as a hex string (`"0x2182309"`); a
    /// transfer with no `blockNum` has nothing to ask about and is left for
    /// `filled` to drop.
    static func blocksMissingTime(_ transfers: [[String: Any]]) -> [String] {
        var out: [String] = []
        for t in transfers where timestamp(of: t) == nil {
            guard let block = blockNumber(of: t), !out.contains(block) else { continue }
            out.append(block)
        }
        return out
    }

    /// The block's time from an `eth_getBlockByNumber` result — its
    /// `timestamp` is hex SECONDS. Nil for anything else (an error body, a
    /// null result for a block the node has not seen, a malformed number),
    /// because a guessed time is the defect this file exists to remove.
    static func time(fromBlockResult result: Any?) -> Date? {
        guard let block = result as? [String: Any],
              let hex = block["timestamp"] as? String,
              let seconds = hexValue(hex), seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    /// Every transfer that has a time, with the missing ones filled from
    /// `times` (block → date) in the ISO form `IngestSupport.isoDate` reads.
    /// A transfer that had no time and whose block is not in `times` is
    /// omitted. Order is preserved; a transfer that already carried a time is
    /// passed through untouched.
    static func filled(_ transfers: [[String: Any]], times: [String: Date]) -> [[String: Any]] {
        transfers.compactMap { t in
            if timestamp(of: t) != nil { return t }
            guard let block = blockNumber(of: t), let date = times[block] else { return nil }
            var copy = t
            var metadata = (t["metadata"] as? [String: Any]) ?? [:]
            metadata["blockTimestamp"] = iso.string(from: date)
            copy["metadata"] = metadata
            return copy
        }
    }

    // MARK: - The rows already stored wrong (prd §792)

    /// The chains whose Alchemy transfers carried no time, with the explorer
    /// prefix `WalletIngest` wrote their links from. The only rows the heal
    /// re-times: every other chain's Alchemy rows carried `blockTimestamp`.
    static let untimedChains: [(network: String, explorer: String)] = [
        ("hyperliquid-mainnet", "https://hyperevmscan.io/tx/"),
        ("worldchain-mainnet", "https://worldscan.org/tx/"),
    ]

    /// One stored row to re-time: its ref (to find it again after the network),
    /// the chain, and the transaction hash its link names.
    struct HealJob: Sendable, Equatable {
        let ref: String
        let network: String
        let hash: String
    }

    /// A stored wallet row the heal should check, or nil. It must be an
    /// ALCHEMY-sourced ref — a `wallet:zerion:` row always carried Zerion's
    /// own time — on one of `untimedChains`, whose link ends in a full
    /// 32-byte transaction hash. Anything else is left exactly as it is.
    static func healJob(ref: String?, content: String) -> HealJob? {
        guard let ref, ref.hasPrefix("wallet:"), !ref.hasPrefix("wallet:zerion:") else { return nil }
        for chain in untimedChains where content.hasPrefix(chain.explorer) {
            let hash = String(content.dropFirst(chain.explorer.count)).lowercased()
            guard hash.count == 66, hash.hasPrefix("0x"),
                  hash.dropFirst(2).allSatisfy(\.isHexDigit) else { return nil }
            return HealJob(ref: ref, network: chain.network, hash: hash)
        }
        return nil
    }

    /// The block a transaction was mined in, from `eth_getTransactionByHash`.
    /// Nil for a pending transaction (null `blockNumber`) or anything malformed.
    static func blockNumber(fromTransactionResult result: Any?) -> String? {
        guard let tx = result as? [String: Any],
              let raw = tx["blockNumber"] as? String,
              raw.hasPrefix("0x"), hexValue(raw) != nil else { return nil }
        return raw.lowercased()
    }

    /// Whether a stored date is the sync's clock rather than the block's. A
    /// minute of slack: the explorer's second and a stored second may be read
    /// through different formatters, and nothing that close is the bug.
    static func needsRewrite(stored: Date, actual: Date) -> Bool {
        abs(stored.timeIntervalSince(actual)) > 60
    }

    // MARK: - Pieces

    static func timestamp(of transfer: [String: Any]) -> String? {
        guard let s = (transfer["metadata"] as? [String: Any])?["blockTimestamp"] as? String,
              !s.isEmpty else { return nil }
        return s
    }

    /// Lowercased, so `0xABC` and `0xabc` are one block and one request.
    static func blockNumber(of transfer: [String: Any]) -> String? {
        guard let raw = transfer["blockNum"] as? String,
              raw.hasPrefix("0x"), hexValue(raw) != nil else { return nil }
        return raw.lowercased()
    }

    static func hexValue(_ hex: String) -> UInt64? {
        guard hex.hasPrefix("0x") || hex.hasPrefix("0X"), hex.count > 2 else { return nil }
        return UInt64(hex.dropFirst(2), radix: 16)
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Block times already read, per network. A mined block's timestamp is
    /// immutable, so an entry never goes stale; the bound only keeps a
    /// long-running process from growing without limit.
    actor Cache {
        static let shared = Cache()
        private var times: [String: Date] = [:]
        private let limit = 4_000

        func time(network: String, block: String) -> Date? {
            times["\(network)|\(block)"]
        }

        func store(_ date: Date, network: String, block: String) {
            if times.count >= limit { times.removeAll(keepingCapacity: true) }
            times["\(network)|\(block)"] = date
        }
    }
}
