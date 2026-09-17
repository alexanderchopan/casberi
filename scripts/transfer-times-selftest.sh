#!/bin/zsh
# Transfer-times self-test (prd §790, 2026-09-16) — when an Alchemy transfer
# happened, on the chains where Alchemy will not say:
#
#   Casberi/Casberi/Model/TransferTimes.swift   compiled WHOLE and unmodified
#
# WHY A HARNESS. `alchemy_getAssetTransfers` returns `"metadata": null` on
# HyperEVM and World Chain (MEASURED), and the ingest dated a missing time
# `?? .now` — so every NFT move and every Zerion-outage transfer on those two
# chains landed stamped with the moment of the sync. Nothing crashes and nothing
# looks empty: the rows simply claim the wrong day. The failure modes:
#
#   • A TRANSFER WITH NO TIME PASSED THROUGH. It lands dated now — the bug.
#   • A BLOCK READ AS DECIMAL. `0x2182309` parsed as base 10 is nil (dropped
#     forever) or, for an all-digit hex, a block from years ago.
#   • A TIMESTAMP READ AS MILLISECONDS or as decimal: a date in 1970 or 50000.
#   • A TRANSFER THAT ALREADY HAD A TIME REWRITTEN from a block cache entry.
#   • THE FILL BYPASSED. `fetchAlchemy` returning its raw transfers again — a
#     drift guard, since no compiled assertion can see the call site.
#
# Pure, local, deterministic — no network, no simulator, no key.
set -euo pipefail
cd "$(dirname "$0")/.."

TIMES="Casberi/Casberi/Model/TransferTimes.swift"
INGEST="Casberi/Casberi/Model/WalletIngest.swift"
for f in "$TIMES" "$INGEST"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/transfer-times-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}

let timed: [String: Any] = ["hash": "0xa", "blockNum": "0x10",
                            "metadata": ["blockTimestamp": "2024-01-02T03:04:05.000Z"]]
let untimedA: [String: Any] = ["hash": "0xb", "blockNum": "0x2182309", "metadata": NSNull()]
let untimedA2: [String: Any] = ["hash": "0xc", "blockNum": "0x2182309"]
let untimedB: [String: Any] = ["hash": "0xd", "blockNum": "0x2182307", "metadata": [String: Any]()]
let noBlock: [String: Any] = ["hash": "0xe", "metadata": NSNull()]
let upper: [String: Any] = ["hash": "0xf", "blockNum": "0x218230A"]

// --- which blocks to ask about ------------------------------------------------
let missing = TransferTimes.blocksMissingTime([timed, untimedA, untimedA2, untimedB, noBlock, upper])
check(missing == ["0x2182309", "0x2182307", "0x218230a"],
      "blocks missing a time, deduped, first-seen order, lowercased — got \(missing)")
check(TransferTimes.blocksMissingTime([timed]).isEmpty, "a timed transfer asks for nothing")
check(TransferTimes.blocksMissingTime([["hash": "0x1", "blockNum": "12345"]]).isEmpty,
      "a block not spelled as hex is not asked about (never read as decimal)")

// --- a block's time -----------------------------------------------------------
let t = TransferTimes.time(fromBlockResult: ["number": "0x2182309", "timestamp": "0x6720f000"])
check(t == Date(timeIntervalSince1970: 1_730_211_840), "hex SECONDS — got \(String(describing: t))")
check(TransferTimes.time(fromBlockResult: ["timestamp": "1730211840"]) == nil,
      "a decimal timestamp is refused, not guessed")
check(TransferTimes.time(fromBlockResult: NSNull()) == nil, "a null result is no time")
check(TransferTimes.time(fromBlockResult: ["timestamp": "0x0"]) == nil, "a zero timestamp is no time")
check(TransferTimes.time(fromBlockResult: nil) == nil, "no result is no time")

// --- the fill -----------------------------------------------------------------
let blockDate = Date(timeIntervalSince1970: 1_730_211_840)
let out = TransferTimes.filled([timed, untimedA, untimedB, noBlock, upper],
                               times: ["0x2182309": blockDate, "0x218230a": blockDate,
                                       "0x10": Date(timeIntervalSince1970: 0)])
let hashes = out.compactMap { $0["hash"] as? String }
check(hashes == ["0xa", "0xb", "0xf"],
      "timed kept, filled kept, unreadable block and no-block DROPPED, order kept — got \(hashes)")
check(TransferTimes.timestamp(of: out[0]) == "2024-01-02T03:04:05.000Z",
      "a transfer that had a time is never rewritten from the block cache")
let filledStamp = TransferTimes.timestamp(of: out[1])
check(filledStamp == "2024-10-29T14:24:00Z", "the fill is internet date-time — got \(String(describing: filledStamp))")
let iso = ISO8601DateFormatter()
check(filledStamp.flatMap { iso.date(from: $0) } == blockDate,
      "the filled stamp reads back as the block's own time")
check(TransferTimes.filled([untimedA], times: [:]).isEmpty,
      "with no block time a transfer is dropped, NEVER dated now")

// --- the cache ----------------------------------------------------------------
let sem = DispatchSemaphore(value: 0)
Task {
    let c = TransferTimes.Cache()
    await c.store(blockDate, network: "worldchain-mainnet", block: "0x1")
    let hit = await c.time(network: "worldchain-mainnet", block: "0x1")
    let other = await c.time(network: "hyperliquid-mainnet", block: "0x1")
    check(hit == blockDate, "a stored block time is read back")
    check(other == nil, "a block number on another chain is a different block")
    sem.signal()
}
sem.wait()

// --- the stored rows the heal re-times (prd §792) ------------------------------
let hash = "0x" + String(repeating: "ab", count: 32)
check(TransferTimes.healJob(ref: "wallet:0xdead:log:1", content: "https://worldscan.org/tx/" + hash)
      == TransferTimes.HealJob(ref: "wallet:0xdead:log:1", network: "worldchain-mainnet", hash: hash),
      "an Alchemy World Chain row is a heal job")
check(TransferTimes.healJob(ref: "wallet:0xdead:log:1", content: "https://hyperevmscan.io/tx/" + hash.uppercased().replacingOccurrences(of: "0X", with: "0x"))?.network
      == "hyperliquid-mainnet", "a HyperEVM row is a heal job, hash case folded")
check(TransferTimes.healJob(ref: "wallet:zerion:\(hash):in:WLD::1", content: "https://worldscan.org/tx/" + hash) == nil,
      "a Zerion row always carried its time — never re-timed")
check(TransferTimes.healJob(ref: "wallet:0xdead:log:1", content: "https://basescan.org/tx/" + hash) == nil,
      "a chain whose Alchemy rows carried a time is left alone")
check(TransferTimes.healJob(ref: "vibenet:1", content: "https://worldscan.org/tx/" + hash) == nil,
      "only wallet refs")
check(TransferTimes.healJob(ref: nil, content: "https://worldscan.org/tx/" + hash) == nil, "no ref, no job")
check(TransferTimes.healJob(ref: "wallet:x", content: "https://worldscan.org/tx/0x1234") == nil,
      "a truncated hash is not asked about")
check(TransferTimes.blockNumber(fromTransactionResult: ["blockNumber": "0x218230A"]) == "0x218230a",
      "a mined transaction's block, lowercased")
check(TransferTimes.blockNumber(fromTransactionResult: ["blockNumber": NSNull()]) == nil,
      "a pending transaction has no block")
check(TransferTimes.blockNumber(fromTransactionResult: NSNull()) == nil, "no such transaction has no block")
check(!TransferTimes.needsRewrite(stored: blockDate.addingTimeInterval(30), actual: blockDate),
      "within a minute is the same time")
check(TransferTimes.needsRewrite(stored: blockDate.addingTimeInterval(86_400 * 200), actual: blockDate),
      "a row dated months after its block is rewritten")

if failures > 0 { print("✗ transfer-times-selftest: \(failures) failure(s)"); exit(1) }
SWIFT

swiftc -O -o "$TMP/run" "$TIMES" "$TMP/main.swift" 2>"$TMP/build.log" \
  || { cat "$TMP/build.log"; echo "✗ transfer-times-selftest did not compile"; exit 1; }
"$TMP/run"

# --- drift guard: the Alchemy arm goes through the fill -----------------------
body=$(awk '/private static func fetchAlchemy\(/,/^    }$/' "$INGEST")
[[ -n "$body" ]] || { echo "✗ could not find fetchAlchemy in $INGEST"; exit 1; }
echo "$body" | grep -q 'return await withBlockTimes(transfers' \
  || { echo "✗ fetchAlchemy no longer fills missing block times — HyperEVM and World Chain transfers land dated now"; exit 1; }
if echo "$body" | grep -qE '^\s*return transfers\s*$'; then
  echo "✗ fetchAlchemy returns raw transfers — a transfer with no time lands dated now"; exit 1
fi

# --- drift guards: the heal is scheduled, and forgets nothing it did not answer --
grep -q 'await WalletIngest.healUntimedTransferDates(context: context)' Casberi/Casberi/Model/BridgeRefresh.swift \
  || { echo "✗ the stored-date heal is not scheduled — rows dated by the sync stay wrong forever"; exit 1; }
heal=$(awk '/static func healUntimedTransferDates\(/,/^    }$/' "$INGEST")
[[ -n "$heal" ]] || { echo "✗ could not find healUntimedTransferDates in $INGEST"; exit 1; }
echo "$heal" | grep -q 'guard !DemoMode.isActive' \
  || { echo "✗ the heal reaches the network in the demo"; exit 1; }
# The ledger records a ref only on a definitive answer: never on the failure arms.
if echo "$heal" | grep -E 'failuresInARow \+= 1' | grep -q 'checked.append'; then
  echo "✗ a network failure is written to the ledger — that row is never re-timed"; exit 1
fi
echo "$heal" | grep -q 'thing.isLive' \
  || { echo "✗ the heal writes a row it did not re-check live after the network wait"; exit 1; }

echo "✓ transfer-times-selftest passed"
