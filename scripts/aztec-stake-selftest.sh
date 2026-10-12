#!/bin/zsh
# Casberi Aztec staking self-test — AZTEC a watched wallet staked on Aztec
# mainnet, read off Ethereum (2026-10-12, prd §1277):
#
#   Casberi/Casberi/Model/AztecStakeWire.swift
#     — attesters (a wallet's ValidatorQueued logs, as withdrawer)
#     — stake     (getAttesterView's eleven words)
#     — state     (the row's words), needsYou (its ink)
#
# Pure, local, deterministic, against replies saved off mainnet
# (scripts/fixtures/aztec/stake-*.json). Every failure below is a clean row
# that says something false about real money:
#
#   • a log for ANOTHER withdrawer taken as yours — a stranger's 200,000
#     AZTEC in your Positions;
#   • the view's withdrawer not checked — a stake re-registered to someone
#     else still drawn as yours;
#   • an exiting stake read off its effective balance (zero) — the money on
#     its way back to you vanishes until it lands;
#   • "Ready to withdraw" before the exit date, or never.
set -euo pipefail
cd "$(dirname "$0")/.."

WIRE="Casberi/Casberi/Model/AztecStakeWire.swift"
FIX="scripts/fixtures/aztec"
for f in "$WIRE" "$FIX/stake-logs-delegator.json" "$FIX/stake-view-validating.json" "$FIX/stake-view-exiting.json" \
         "$FIX/stake-view-old-rollup.json" "$FIX/stake-view-delegator.json"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done
# The app half reads through the Wallet's disclosed host pool only.
if grep -nE 'https?://' Casberi/Casberi/Model/AztecStaking.swift | grep -v '^\s*[0-9]*:\s*///' | grep -q .; then
  echo "✗ AztecStaking.swift names a host of its own — read through WalletApprovals' pool"; exit 1
fi
grep -q 'AztecStaking.clearState(address: old.address)' Casberi/Casberi/Model/WalletStore.swift \
  || { echo "✗ unwatching a wallet no longer clears its Aztec walk"; exit 1; }

TMP="$(mktemp -d)"
WORK="$TMP/work"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String, line: Int = #line) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what) (line \(line))"); failures += 1 }
}
let fix = ProcessInfo.processInfo.environment["STAKE_FIX"]!
func json(_ name: String) -> [String: Any] {
    try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: fix + "/" + name))) as! [String: Any]
}
let delegator = "0xc8ef578cf2c018a93ae99441f837de3edc4aebbb"
let rollup = AztecStakeWire.rollups[0]

print("logs")
let logs = json("stake-logs-delegator.json")["result"] as! [[String: Any]]
let found = AztecStakeWire.attesters(fromLogs: logs, withdrawer: delegator)
check(found.count == 10, "a delegator's ten queued sequencers, across all three rollups: \(found.count)")
check(found.last == "0xd056f5d706a4ff746056a91539e58c20e7b0a6ea@\(rollup)", "attester@rollup, oldest first")
check(AztecStakeWire.attesters(fromLogs: logs, withdrawer: "0x" + String(repeating: "1", count: 40)).isEmpty,
      "another wallet's logs are not yours")
var removed = logs[0]; removed["removed"] = true
check(AztecStakeWire.attesters(fromLogs: [removed], withdrawer: delegator).isEmpty, "a reorged log is dropped")
var elsewhere = logs[0]; elsewhere["address"] = "0x" + String(repeating: "2", count: 40)
check(AztecStakeWire.attesters(fromLogs: [elsewhere], withdrawer: delegator).isEmpty, "a log from another contract is dropped")
check(AztecStakeWire.attesters(fromLogs: logs + logs, withdrawer: delegator).count == 10, "a log seen twice counts once")
let filter = AztecStakeWire.logFilter(withdrawer: delegator, from: 23_790_839, to: 24_690_838)
check((filter["topics"] as! [Any]).count == 3 && (filter["topics"] as! [Any])[1] is NSNull
      && (filter["topics"] as! [Any])[2] as? String == "0x000000000000000000000000" + delegator.dropFirst(2),
      "the filter asks for this wallet as withdrawer (topic 2), any attester")
check(filter["fromBlock"] as? String == "0x16b04f7", "blocks in hex")
check(AztecStakeWire.viewCall("0x8D88535355C7372C572347C22866EBF7AC739FAB") == "0x34a51ed5000000000000000000000000" + "8d88535355c7372c572347c22866ebf7ac739fab",
      "getAttesterView's calldata")

print("views")
let validatingHex = json("stake-view-validating.json")["result"] as? String
let validating = AztecStakeWire.stake(view: validatingHex, owner: "0xC5A70027F3656355252A88717B6F4F0BA36F9A0B",
                                      attester: "0x8d88535355c7372c572347c22866ebf7ac739fab", rollup: rollup)
check(validating?.status == .validating, "validating")
check(validating.map { abs($0.amount - 200_000) < 0.01 } == true, "200,000 AZTEC staked")
check(validating?.exitableAt == nil && validating?.exitAmount == 0, "no exit")
check(AztecStakeWire.stake(view: validatingHex, owner: delegator, attester: "0x8d88535355c7372c572347c22866ebf7ac739fab", rollup: rollup) == nil,
      "the view names another withdrawer: not yours")
let exitingHex = json("stake-view-exiting.json")["result"] as? String
let exiting = AztecStakeWire.stake(view: exitingHex, owner: "0xbb46064c0664618fd18689a37c9faa47ad848bcb",
                                   attester: "0x6f6cab6575da907fe9d035093b214b3c7eddb460", rollup: rollup)
check(exiting?.status == .exiting && exiting?.staked == 0, "exiting, nothing left staked")
check(exiting.map { abs($0.amount - 200_000) < 0.01 } == true, "…and its 200,000 AZTEC on the way out")
check(exiting?.exitableAt == Date(timeIntervalSince1970: 1_791_774_479), "withdrawable from its own date")
check(AztecStakeWire.stake(view: json("stake-view-old-rollup.json")["result"] as? String, owner: "0x25cfb57e45f6a7b63ee33b94420407048eed844e",
                           attester: "0x1", rollup: AztecStakeWire.rollups[1]) == nil, "an earlier rollup's emptied stake is nothing")
check(AztecStakeWire.stake(view: json("stake-view-delegator.json")["result"] as? String, owner: delegator,
                           attester: "0x1", rollup: AztecStakeWire.rollups[1]) == nil, "status 0 is nothing")
check(AztecStakeWire.stake(view: "0x", owner: delegator, attester: "0x1", rollup: rollup) == nil, "a revert is nothing")
check(AztecStakeWire.stake(view: String((validatingHex ?? "").dropLast(64)), owner: "0xc5a70027f3656355252a88717b6f4f0ba36f9a0b",
                           attester: "0x1", rollup: rollup) == nil, "a short reply is nothing")

print("words")
let before = Date(timeIntervalSince1970: 1_791_774_479 - 86_400)
let after = Date(timeIntervalSince1970: 1_791_774_479 + 60)
check(AztecStakeWire.state(validating!) == "Validating" && !AztecStakeWire.needsYou(validating!), "validating asks nothing")
check(AztecStakeWire.state(exiting!, now: before).hasPrefix("Withdrawing · from ") && !AztecStakeWire.needsYou(exiting!, now: before),
      "before its date: withdrawing, from when")
check(AztecStakeWire.state(exiting!, now: after) == "Ready to withdraw" && AztecStakeWire.needsYou(exiting!, now: after),
      "after it: ready, and it asks you")

if failures > 0 { print("✗ \(failures) failed"); exit(1) }
SWIFT

echo "AztecStakeWire, compiled whole"
if ! swiftc -Onone -o "$TMP/run" "$WIRE" "$TMP/main.swift" > "$TMP/build.log" 2>&1; then
  echo "✗ the harness did not compile:"; sed -n '1,30p' "$TMP/build.log"; exit 1
fi
STAKE_FIX="$PWD/$FIX" "$TMP/run" || exit 1

echo
echo "mutations — each must be caught"
mutate() {
  local name="$1" from="$2" to="$3"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$WIRE" "$WORK/AztecStakeWire.swift"
  if ! MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/AztecStakeWire.swift" <<'PY'
import os, sys
p = sys.argv[1]; s = open(p).read(); f, t = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if f not in s: sys.exit(2)
open(p, "w").write(s.replace(f, t, 1))
PY
  then echo "  ✗ $name — the mutation did not apply"; exit 1; fi
  if cmp -s "$WIRE" "$WORK/AztecStakeWire.swift"; then echo "  ✗ $name — changed nothing"; exit 1; fi
  if ! swiftc -Onone -o "$TMP/mut" "$WORK/AztecStakeWire.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if STAKE_FIX="$PWD/$FIX" "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

mutate "another withdrawer's log taken" \
  'topics[0] == validatorQueued, topics[2] == me else { continue }' \
  'topics[0] == validatorQueued else { continue }'
mutate "the view's withdrawer not checked" \
  'guard withdrawer == owner.lowercased() else { return nil }' \
  '_ = withdrawer'
mutate "an exit read off the effective balance" \
  'var amount: Double { status == .exiting ? exitAmount : staked }' \
  'var amount: Double { staked }'
mutate "ready before its date" \
  'if at <= now { return String(localized: "Ready to withdraw") }' \
  'if at > now { return String(localized: "Ready to withdraw") }'
mutate "a status-0 view drawn" \
  'guard let status = Status(rawValue: Int(uint(words[0]))), status != .none else { return nil }' \
  'guard let status = Status(rawValue: Int(uint(words[0]))) else { return nil }'

echo "✓ Aztec staking self-test passed"
