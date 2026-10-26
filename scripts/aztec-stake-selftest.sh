#!/bin/zsh
# Casberi Aztec staking self-test — AZTEC a watched wallet staked on Aztec
# mainnet, read off Ethereum (2026-10-12, prd §1277, §1279):
#
#   Casberi/Casberi/Model/AztecStakeWire.swift
#     — attesters / stake     (ValidatorQueued logs; getAttesterView's words)
#     — vaults / staker       (token-sale ATPs and the staker that withdraws)
#     — provider / share      (a delegated stake's payout split, its rewards)
#     — proposal / count      (an Aztec vote still to come)
#     — state / earned / titles (the row's words)
#
# Pure, local, deterministic, against replies saved off mainnet
# (scripts/fixtures/aztec/stake-*.json, atp-*.json, gov-*.json). Every
# failure below is a clean row that says something false about real money:
#
#   • a stake read on the Rollup that QUEUED it — every stake that followed
#     an upgrade reads empty (§1277's defect: three of seven drawn);
#   • a log for ANOTHER withdrawer taken as yours — a stranger's 200,000
#     AZTEC in your Positions;
#   • the view's withdrawer not checked — a stake re-registered to someone
#     else still drawn as yours;
#   • a vault from a contract that is not one of Aztec's factories — anyone
#     can emit the event;
#   • the provider's share read as yours — rewards three times too large;
#   • an exiting stake read off its effective balance (zero) — the money on
#     its way back to you vanishes until it lands;
#   • "Ready to withdraw" before the exit date, or a vote that opens on its
#     creation day.
set -euo pipefail
cd "$(dirname "$0")/.."

WIRE="Casberi/Casberi/Model/AztecStakeWire.swift"
APP="Casberi/Casberi/Model/AztecStaking.swift"
FIX="scripts/fixtures/aztec"
for f in "$WIRE" "$APP" "$FIX"/stake-logs-delegator.json "$FIX"/stake-view-validating.json "$FIX"/stake-view-exiting.json \
         "$FIX"/stake-view-old-rollup.json "$FIX"/stake-view-delegator.json "$FIX"/stake-view-carried.json \
         "$FIX"/stake-view-atp.json "$FIX"/stake-logs-atp.json "$FIX"/stake-provider-logs.json "$FIX"/stake-split-logs.json \
         "$FIX"/stake-rewards.json "$FIX"/atp-created-logs.json "$FIX"/atp-staker.json "$FIX"/atp-held.json \
         "$FIX"/atp-claimable.json "$FIX"/atp-beneficiary.json "$FIX"/registry-canonical.json "$FIX"/gov-count.json \
         "$FIX"/gov-proposal-4.json "$FIX"/gov-state-4.json "$FIX"/governance-v6-upgrade.json; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done
# The app half: reads through the Wallet's declared pool and Aztec's own
# node only; every stake read on the CANONICAL Rollup; unwatching clears the
# walk.
if grep -nE 'https?://' "$APP" | grep -v '^\s*[0-9]*:\s*///' \
   | grep -vE 'aztec-mainnet\.drpc\.org|stake\.aztec\.network|aztecscan\.xyz/validators|aztecgov\.nethermind\.io|//zk\.money"' | grep -q .; then
  echo "✗ AztecStaking.swift names a host it does not declare"; exit 1
fi
grep -q 'aztec-mainnet.drpc.org' Casberi/Casberi/Model/NetworkReach.swift \
  || { echo "✗ Aztec's mainnet node is not in NetworkReach"; exit 1; }
grep -q 'for (i, r) in (\[rollup\] + others' "$APP" && grep -q 'await call(r, AztecStakeWire.viewCall(attester))' "$APP" \
  || { echo "✗ a stake is no longer read on the canonical Rollup first (§1279: three of seven drawn)"; exit 1; }
grep -q 'AztecStakeWire.merged(await registryRollups())' "$APP" \
  || { echo "✗ the Rollups are no longer asked of the Registry: an upgrade's stakes go unseen (prd §1446)"; exit 1; }
grep -q 'd.set(walked, forKey: key("cursorSet", withdrawer))' "$APP" \
  || { echo "✗ a stake walk no longer restarts when a Rollup is added (prd §1446)"; exit 1; }
grep -q 'if ZkMoney.hasDeposited, let wallet = addresses.first, let up = await upcomingUpgrade()' "$APP" \
  || { echo "✗ the upgrade warning no longer lands for someone with money in zk.money (prd §1446)"; exit 1; }
grep -q 'AztecStakeWire.registry, AztecStakeWire.getCanonicalRollup' "$APP" \
  || { echo "✗ the canonical Rollup is no longer asked of the Registry"; exit 1; }
grep -q 'if let b = beneficiary, AztecStakeWire.address(reply: b) != address { continue }' "$APP" \
  || { echo "✗ a vault is dropped on a failed beneficiary read (nine of seventeen stakes vanish)"; exit 1; }
grep -q 'guard landedNow.insert(ref).inserted else { return }' "$APP" \
  || { echo "✗ a row can land twice in one pass (a wallet listed twice)"; exit 1; }
grep -q 'AztecStaking.clearState(address: old.address)' Casberi/Casberi/Model/WalletStore.swift \
  || { echo "✗ unwatching a wallet no longer clears its Aztec walk"; exit 1; }
grep -q 'ref.hasPrefix("aztec:exit:") { return .poolCleared }' Casberi/Casberi/Model/NotifySweep.swift \
  || { echo "✗ a withdrawable stake no longer notifies"; exit 1; }
grep -q 'ref.hasPrefix("aztec:stake:"), ref.contains(":stopped:") { return .nodeDown }' Casberi/Casberi/Model/NotifySweep.swift \
  || { echo "✗ a stopped staked sequencer no longer notifies"; exit 1; }
grep -q 'AztecStaking.syncEvents(' Casberi/Casberi/Model/WalletIngest.swift \
  || { echo "✗ the Wallet sweep no longer lands Aztec's rows"; exit 1; }

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
func reply(_ name: String) -> String? { json(name)["result"] as? String }
func logs(_ name: String) -> [[String: Any]] { json(name)["result"] as! [[String: Any]] }
let delegator = "0xc8ef578cf2c018a93ae99441f837de3edc4aebbb"
let rollup = AztecStakeWire.rollups[0]

print("the canonical rollup")
check(AztecStakeWire.address(reply: reply("registry-canonical.json")) == rollup, "the Registry names the current Rollup")
check(AztecStakeWire.address(reply: "0x" + String(repeating: "0", count: 64)) == nil, "a zero address is no Rollup")
let carried = AztecStakeWire.stake(view: reply("stake-view-carried.json"), owner: delegator, withdrawer: delegator,
                                   attester: "0x70df6cd7e15ca8633ceb17786d2c504c1e53e5f1", rollup: rollup)
check(carried?.status == .validating && carried.map { abs($0.amount - 200_000) < 0.01 } == true,
      "a stake queued on an earlier Rollup reads validating on the current one")

print("logs")
let found = AztecStakeWire.attesters(fromLogs: logs("stake-logs-delegator.json"), withdrawers: [delegator])
check(found.count == 10, "a delegator's ten queued sequencers, across all three Rollups: \(found.count)")
check(found.last == "0xd056f5d706a4ff746056a91539e58c20e7b0a6ea@\(delegator)", "attester@withdrawer, oldest first")
check(AztecStakeWire.attesters(fromLogs: logs("stake-logs-delegator.json"), withdrawers: ["0x" + String(repeating: "1", count: 40)]).isEmpty,
      "another wallet's logs are not yours")
var removed = logs("stake-logs-delegator.json")[0]; removed["removed"] = true
check(AztecStakeWire.attesters(fromLogs: [removed], withdrawers: [delegator]).isEmpty, "a reorged log is dropped")
var elsewhere = logs("stake-logs-delegator.json")[0]; elsewhere["address"] = "0x" + String(repeating: "2", count: 40)
check(AztecStakeWire.attesters(fromLogs: [elsewhere], withdrawers: [delegator]).isEmpty, "a log from another contract is dropped")
check(AztecStakeWire.attesters(fromLogs: logs("stake-logs-delegator.json") + logs("stake-logs-delegator.json"), withdrawers: [delegator]).count == 10,
      "a log seen twice counts once")
let filter = AztecStakeWire.logFilter(withdrawers: [delegator], from: 23_790_839, to: 24_690_838)
let topics = filter["topics"] as! [Any]
check(topics.count == 3 && topics[1] is NSNull && (topics[2] as? [String]) == ["0x000000000000000000000000" + delegator.dropFirst(2)],
      "the filter asks for this wallet as withdrawer (topic 2), any attester")
check(filter["fromBlock"] as? String == "0x16b04f7", "blocks in hex")

print("views")
let validating = AztecStakeWire.stake(view: reply("stake-view-validating.json"), owner: "0xc5a70027f3656355252a88717b6f4f0ba36f9a0b",
                                      withdrawer: "0xC5A70027F3656355252A88717B6F4F0BA36F9A0B",
                                      attester: "0x8d88535355c7372c572347c22866ebf7ac739fab", rollup: rollup)
check(validating?.status == .validating && validating.map { abs($0.amount - 200_000) < 0.01 } == true, "200,000 AZTEC validating")
check(validating?.exitableAt == nil && validating?.exitAmount == 0, "no exit")
check(AztecStakeWire.stake(view: reply("stake-view-validating.json"), owner: delegator, withdrawer: delegator,
                           attester: "0x8d88535355c7372c572347c22866ebf7ac739fab", rollup: rollup) == nil,
      "the view names another withdrawer: not yours")
let exitingOwner = "0xbb46064c0664618fd18689a37c9faa47ad848bcb"
let exiting = AztecStakeWire.stake(view: reply("stake-view-exiting.json"), owner: exitingOwner, withdrawer: exitingOwner,
                                   attester: "0x6f6cab6575da907fe9d035093b214b3c7eddb460", rollup: rollup)
check(exiting?.status == .exiting && exiting?.staked == 0, "exiting, nothing left staked")
check(exiting.map { abs($0.amount - 200_000) < 0.01 } == true, "…and its 200,000 AZTEC on the way out")
check(exiting?.exitableAt == Date(timeIntervalSince1970: 1_791_774_479) && exiting?.withdrawalID == 6197,
      "withdrawable from its own date, under its own withdrawal id")
check(AztecStakeWire.stake(view: reply("stake-view-old-rollup.json"), owner: "0x25cfb57e45f6a7b63ee33b94420407048eed844e",
                           withdrawer: "0x25cfb57e45f6a7b63ee33b94420407048eed844e", attester: "0x1", rollup: rollup) == nil,
      "status 0 is nothing")
check(AztecStakeWire.stake(view: "0x", owner: delegator, withdrawer: delegator, attester: "0x1", rollup: rollup) == nil, "a revert is nothing")
check(AztecStakeWire.stake(view: String((reply("stake-view-validating.json") ?? "").dropLast(64)), owner: "0xc5a70027f3656355252a88717b6f4f0ba36f9a0b",
                           withdrawer: "0xc5a70027f3656355252a88717b6f4f0ba36f9a0b", attester: "0x1", rollup: rollup) == nil,
      "a short reply is nothing")
let huge = String(repeating: "f", count: 64)
let hostile = "0x" + huge + String((reply("stake-view-validating.json") ?? "").dropFirst(2 + 64))
check(AztecStakeWire.stake(view: hostile, owner: "0xc5a70027f3656355252a88717b6f4f0ba36f9a0b",
                           withdrawer: "0xc5a70027f3656355252a88717b6f4f0ba36f9a0b", attester: "0x1", rollup: rollup) == nil,
      "a status word past 2^63 is nothing, never a trap")
check(AztecStakeWire.small(Substring(huge)) == nil && AztecStakeWire.small(Substring(String(repeating: "0", count: 63) + "7")) == 7,
      "small numbers only")
check(AztecStakeWire.small(Substring("1" + String(repeating: "0", count: 62) + "1")) == nil,
      "a high digit is not dropped to leave a status of 1")
check(AztecStakeWire.proposal(id: 4, view: reply("gov-proposal-4.json"), state: "0x" + huge) == nil, "a proposal state past 2^63 is nothing")

print("token-sale vaults")
let beneficiary = "0xceb4b318b679d1d73d75b490d161724b9302462a"
let vaults = AztecStakeWire.vaults(fromLogs: logs("atp-created-logs.json"), beneficiary: beneficiary)
check(vaults == ["0x1040bdc94fc8bf8843a68e49d0bb95529cee76d1"], "the vault Aztec's factory made for the wallet")
check(AztecStakeWire.vaults(fromLogs: logs("atp-created-logs.json"), beneficiary: delegator).isEmpty, "another wallet has none of it")
var forged = logs("atp-created-logs.json")[0]; forged["address"] = "0x247c1fd92f692bbd24f7b6f99cda82b0558a4996"
check(AztecStakeWire.vaults(fromLogs: [forged], beneficiary: beneficiary).isEmpty,
      "the same event from a contract that is not Aztec's factory is no vault")
let staker = AztecStakeWire.address(reply: reply("atp-staker.json"))
check(staker == "0x1f8e67483b6a9a630643f240846c34562e5ac9a0", "its staker")
check(AztecStakeWire.address(reply: reply("atp-beneficiary.json")) == beneficiary, "it still names the wallet")
check(AztecStakeWire.amount(reply: reply("atp-held.json")).map { abs($0 - 200_000) < 0.01 } == true && AztecStakeWire.amount(reply: reply("atp-claimable.json")) == 0,
      "200,000 AZTEC unstaked in it, none claimable yet")
let vaultStakes = AztecStakeWire.attesters(fromLogs: logs("stake-logs-atp.json"), withdrawers: [staker!])
check(vaultStakes.count == 5, "its staker queued five sequencers: \(vaultStakes.count)")
let vaultStake = AztecStakeWire.stake(view: reply("stake-view-atp.json"), owner: beneficiary, withdrawer: staker!,
                                      attester: "0x65a523cecf1b4e6b32ee52f186164b9a5d7693b0", rollup: rollup)
check(vaultStake?.status == .validating && vaultStake?.owner == beneficiary, "a vault's stake is the wallet's, withdrawn by the staker")
check(AztecStakeWire.stake(view: reply("stake-view-atp.json"), owner: beneficiary, withdrawer: beneficiary,
                           attester: "0x65a523cecf1b4e6b32ee52f186164b9a5d7693b0", rollup: rollup) == nil,
      "…never by the wallet itself")

print("rewards")
let delegated = "0xe51b3c7c475b3089af4487a2b8abd9560413ffaa"
let p = AztecStakeWire.provider(fromLogs: logs("stake-provider-logs.json"), attester: delegated)
check(p?.id == 93 && p?.coinbase == "0x90e74eaee857fc3b6b2ea271e542049b92b36d9e" && p?.recipient == delegator,
      "provider 93, its split as payout address, the delegator as recipient")
check(AztecStakeWire.provider(fromLogs: logs("stake-provider-logs.json"), attester: "0x8d88535355c7372c572347c22866ebf7ac739fab") == nil,
      "a stake that was not delegated has no provider")
let share = AztecStakeWire.share(fromLogs: logs("stake-split-logs.json"), coinbase: p!.coinbase, recipient: delegator)
check(share == 0.75, "the delegator's share of the split, 7,500 of 10,000: \(String(describing: share))")
check(AztecStakeWire.share(fromLogs: logs("stake-split-logs.json"), coinbase: p!.coinbase,
                           recipient: "0x8997f34ca9c0b23941c14fe67d406ce18f7e79c9") == 0.25, "the provider's, 2,500")
check(AztecStakeWire.share(fromLogs: logs("stake-split-logs.json"), coinbase: p!.coinbase, recipient: beneficiary) == nil,
      "a wallet the split does not name has no share")
var splitLog = logs("stake-split-logs.json")[0]
splitLog["data"] = "0x" + String(repeating: "f", count: 64 * 11)
check(AztecStakeWire.share(fromLogs: [splitLog], coinbase: p!.coinbase, recipient: delegator) == nil,
      "a split whose offsets are garbage is no share, never a trap")
var misaligned = logs("stake-split-logs.json")[0]
misaligned["data"] = "0x" + String(repeating: "0", count: 62) + "21" + String((misaligned["data"] as! String).dropFirst(2 + 64))
check(AztecStakeWire.share(fromLogs: [misaligned], coinbase: p!.coinbase, recipient: delegator) == nil,
      "an offset that is not a whole word is no share")
let owed = AztecStakeWire.amount(reply: reply("stake-rewards.json"))
check(owed.map { abs($0 - 350) < 0.000001 } == true, "350 AZTEC owed to the split, unclaimed")
var earning = carried!; earning.rewards = owed! * share!
check(AztecStakeWire.earned(earning) == "262.5 AZTEC earned", "the wallet's part: \(AztecStakeWire.earned(earning) ?? "nil")")
check(AztecStakeWire.earned(carried!) == nil, "nothing read, nothing said")

print("health")
var silent = carried!; silent.missedStreak = 3
check(silent.isStopped && AztecStakeWire.state(silent) == "Missing attestations" && AztecStakeWire.needsYou(silent),
      "three missed in a row: missing attestations, and it asks you")
var quiet = carried!; quiet.missedStreak = 2
check(!quiet.isStopped && AztecStakeWire.state(quiet) == "Validating", "two is not yet a stop")
check(AztecStakeWire.stoppedTitle(silent) == "Your Aztec sequencer ...e5f1 stopped attesting", "its row")

print("governance")
check(AztecStakeWire.count(reply: reply("gov-count.json")) == 5, "five proposals")
check(AztecStakeWire.proposal(id: 4, view: reply("gov-proposal-4.json"), state: reply("gov-state-4.json")) == nil,
      "an executed proposal is no vote to come")
let active = AztecStakeWire.proposal(id: 4, view: reply("gov-proposal-4.json"), state: "0x" + String(repeating: "0", count: 63) + "1")
check(active?.opens == Date(timeIntervalSince1970: 1_783_023_491 + 259_200)
      && active?.closes == Date(timeIntervalSince1970: 1_783_023_491 + 259_200 + 604_800),
      "a vote opens three days after creation and runs seven")
check(active.map { AztecStakeWire.voteTitle($0).hasPrefix("Aztec proposal 4 is open for votes until ") } == true, "its row")
let pending = AztecStakeWire.proposal(id: 4, view: reply("gov-proposal-4.json"), state: "0x" + String(repeating: "0", count: 64))!
check(AztecStakeWire.voteTitle(pending, now: Date(timeIntervalSince1970: 1_783_023_491)).hasPrefix("Aztec proposal 4 opens for votes "),
      "pending, it says when it opens")

print("an upgrade coming (prd §1446)")
let up = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: fix + "/governance-v6-upgrade.json"))) as! [String: String]
check(AztecStakeWire.addedRollup(actions: up["v6Actions"]) == "0xe37a2663cc9c119ba41572c40fab0bbb23a5402f",
      "proposal 5's payload adds V6's Rollup to the Registry")
check(AztecStakeWire.addedRollup(actions: up["proposal4Actions"]) == "0x91ff8bbd8ebb07893010d50a48a1609e5ebd8e34",
      "proposal 4's added V5's")
check(AztecStakeWire.rollups.contains(AztecStakeWire.addedRollup(actions: up["v6Actions"]) ?? "-"),
      "the Rollup V6 adds is walked before the Registry lists it")
/// `(address target, bytes data)[]`, ABI-encoded, for actions built here.
func encodeActions(_ actions: [(String, String)]) -> String {
    func w(_ n: Int) -> String { String(repeating: "0", count: 64 - String(n, radix: 16).count) + String(n, radix: 16) }
    func pad(_ hex: String) -> String { hex + String(repeating: "0", count: (64 - hex.count % 64) % 64) }
    var heads = "", tails = "", offset = 32 * actions.count
    for (target, data) in actions {
        heads += w(offset)
        let body = String(repeating: "0", count: 24) + target.dropFirst(2) + w(64) + w(data.count / 2) + pad(data)
        tails += body
        offset += body.count / 2
    }
    return "0x" + w(32) + w(actions.count) + heads + tails
}
let addsElsewhere = encodeActions([("0xa92ecfd0e70c9cd5e5cd76c50af0f7da93567a4f",
                                "59264f00" + String(repeating: "0", count: 24) + "00000000000000000000000000000000deadbeef")])
check(AztecStakeWire.addedRollup(actions: addsElsewhere) == nil, "addRollup on another contract is not the Registry's")
check(AztecStakeWire.addedRollup(actions: encodeActions([("0x35b22e09ee0390539439e24f06da43d83f90e298",
                                "59264f00" + String(repeating: "0", count: 24) + "00000000000000000000000000000000deadbeef")]))
      == "0x00000000000000000000000000000000deadbeef", "the encoder agrees with Aztec's")
check(AztecStakeWire.payload(view: up["proposal5View"]) == "0xe8d663a8b355415f331a54d694f36685346b5433", "the payload is read off the view")
let v6 = AztecStakeWire.upgrade(id: 5, view: up["proposal5View"], state: up["proposal5State"], actions: up["v6Actions"])
check(v6?.rollup == "0xe37a2663cc9c119ba41572c40fab0bbb23a5402f"
      && v6?.executableFrom == Date(timeIntervalSince1970: 1_791_952_895 + 259_200 + 604_800 + 172_800),
      "open now, it can execute after voting and the execution delay")
let ran = "0x" + String(repeating: "0", count: 63) + "5"
check(AztecStakeWire.upgrade(id: 5, view: up["proposal5View"], state: ran, actions: up["v6Actions"]) == nil,
      "an executed upgrade is no longer coming")
check(AztecStakeWire.upgrade(id: 5, view: up["proposal5View"], state: up["proposal5State"], actions: "0x") == nil,
      "a proposal that adds no Rollup is no upgrade")
let ref = AztecStakeWire.upgradeRef(v6!)
check(AztecStakeWire.upgradeWaiting(ref: ref, now: Date(timeIntervalSince1970: 1_792_900_000))
      && !AztecStakeWire.upgradeWaiting(ref: ref, now: Date(timeIntervalSince1970: 1_793_000_000)),
      "it waits on you until it can execute")
check(AztecStakeWire.upgradeTitle(v6!).hasSuffix("take your money out of zk.money first"), "its row")
check(AztecStakeWire.merged(["0x603bb2c05d474794ea97805e8de69bccfb3bca12", "0xABC"]).last == "0xabc"
      && AztecStakeWire.merged([]).count == AztecStakeWire.rollups.count,
      "the Registry's Rollups join the known ones, once each")
check(AztecStakeWire.walkKey(AztecStakeWire.rollups) != AztecStakeWire.walkKey(AztecStakeWire.rollups.dropLast().map { $0 }),
      "a Rollup added changes the walk")

print("words")
let before = Date(timeIntervalSince1970: 1_791_774_479 - 86_400)
let after = Date(timeIntervalSince1970: 1_791_774_479 + 60)
check(AztecStakeWire.state(validating!) == "Validating" && !AztecStakeWire.needsYou(validating!), "validating asks nothing")
check(AztecStakeWire.state(exiting!, now: before).hasPrefix("Withdrawing · from ") && !AztecStakeWire.needsYou(exiting!, now: before),
      "before its date: withdrawing, from when")
check(AztecStakeWire.state(exiting!, now: after) == "Ready to withdraw" && AztecStakeWire.needsYou(exiting!, now: after),
      "after it: ready, and it asks you")
check(AztecStakeWire.readyTitle(exiting!) == "Your 200,000 AZTEC can be withdrawn from Aztec staking", "the ready row")
check(AztecStakeWire.count(reply: "0x1") == nil && AztecStakeWire.amount(reply: "0x" + String(repeating: "z", count: 64)) == nil,
      "a malformed reply is nothing")

if failures > 0 { print("✗ \(failures) failed"); exit(1) }
SWIFT

echo "AztecStakeWire, compiled whole"
if ! swiftc -Onone -o "$TMP/run" "Casberi/Shared/AddressTail.swift" "$WIRE" "$TMP/main.swift" > "$TMP/build.log" 2>&1; then
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
  if ! swiftc -Onone -o "$TMP/mut" "Casberi/Shared/AddressTail.swift" "$WORK/AztecStakeWire.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if STAKE_FIX="$PWD/$FIX" "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

mutate "another withdrawer's log taken" \
  'topics[0] == validatorQueued, mine.contains(topics[2]) else { continue }' \
  'topics[0] == validatorQueued else { continue }'
mutate "the view's withdrawer not checked" \
  'guard address(words[10]) == withdrawer.lowercased() else { return nil }' \
  '_ = withdrawer'
mutate "an exit read off the effective balance" \
  'var amount: Double { status == .exiting ? exitAmount : staked }' \
  'var amount: Double { staked }'
mutate "ready before its date" \
  'if at <= now { return String(localized: "Ready to withdraw") }' \
  'if at > now { return String(localized: "Ready to withdraw") }'
mutate "a status-0 view drawn" \
  'guard let raw = small(words[0]), let status = Status(rawValue: raw), status != .none else { return nil }' \
  'guard let raw = small(words[0]), let status = Status(rawValue: raw) else { return nil }'
mutate "a vault from any contract" \
  'guard let topics = live(log, from: atpFactories), topics.count == 3,' \
  'guard let topics = live(log, from: [(log["address"] as? String ?? "").lowercased()]), topics.count == 3,'
mutate "a vault for any beneficiary" \
  'topics[0] == atpCreated, topics[1] == topic(beneficiary) else { continue }' \
  'topics[0] == atpCreated else { continue }'
mutate "payout address and recipient swapped" \
  'let coinbase = address(w[0]), let recipient = address(w[1]) else { continue }' \
  'let coinbase = address(w[1]), let recipient = address(w[0]) else { continue }'
mutate "the share read off the wrong slot" \
  'for i in 0..<n where address(w[recipientsAt + 1 + i]) == recipient.lowercased() {' \
  'for i in 0..<n where address(w[recipientsAt + 2 - i]) == recipient.lowercased() {'
mutate "a vote opening on its creation day" \
  'let opens = uint(w[10]) + uint(w[0])' \
  'let opens = uint(w[10])'
mutate "a stop called one miss late" \
  'var isStopped: Bool { (missedStreak ?? 0) >= AztecStakeWire.stoppedStreak && status == .validating }' \
  'var isStopped: Bool { (missedStreak ?? 0) > AztecStakeWire.stoppedStreak && status == .validating }'
mutate "a garbage word trusted as a small number" \
  'guard w.count == 64, w.prefix(48).allSatisfy({ $0 == "0" }) else { return nil }' \
  'guard w.count == 64 else { return nil }'
mutate "an upgrade read off any target" \
  'if target == registry, selector == addRollup { return address(at: data + 4) }' \
  'if selector == addRollup { return address(at: data + 4) }'
mutate "an executed upgrade still coming" \
  'let state = small(s[0]), (0...3).contains(state), let rollup' \
  'let state = small(s[0]), state >= 0, let rollup'
mutate "the execution delay left off" \
  'uint(w[10]) + uint(w[0]) + uint(w[1]) + uint(w[2])' \
  'uint(w[10]) + uint(w[0]) + uint(w[1])'
mutate "an upgrade waits on you forever" \
  'return now.timeIntervalSince1970 < t' \
  'return t > 0'
mutate "V6's Rollup left off the known list" \
  '                          "0xe37a2663cc9c119ba41572c40fab0bbb23a5402f"]' \
  '                          ]'
mutate "an executed proposal drawn as a vote" \
  'guard let state = small(s[0]), state == 0 || state == 1 else { return nil }' \
  'guard let state = small(s[0]), state >= 0 else { return nil }'

echo "✓ Aztec staking self-test passed"
