#!/bin/zsh
# Casberi Aztec self-test — the SHIPPED wire logic behind the Aztec testnet seat
# (2026-10-11):
#
#   Casberi/Casberi/Model/AztecWire.swift
#     — result / sequencer      (node_getValidatorStats, an unknown attester)
#     — tips / chain / minL2Fee (node_getChainTips, node_getNodeInfo, fees)
#     — attester / isAccountAddress (what a paste is: 20 bytes, never 32)
#     — events(old:new:)        (what changed between two readings)
#     — date(of:in:) / line     (a slot's time, the roster's words)
#
# Foundation only BY DESIGN, so it is compiled WHOLE AND UNMODIFIED here,
# against replies saved off the live testnet (scripts/fixtures/aztec/, node
# 5.0.0 on Sepolia, 2026-10-11).
#
# WHY A HARNESS. A watch is forward-only and a healthy sequencer misses
# nothing, so the rows and the alarm run only when somebody's machine stops.
# Every failure below renders as a good-looking page:
#
#   • the first reading landing the window — 17 "Proposed a checkpoint" rows
#     dated before the watch began;
#   • a proposal landed before it is FINAL — a `checkpoint-valid` slot that
#     later reads `-mined` lands twice, or one that is never mined lands as
#     proposed;
#   • one row per missed attestation — 768 rows a window from a stopped box;
#   • a 32-byte Aztec ACCOUNT watched as a sequencer — the node answers
#     nothing and the page draws "no duty seen", a confident wrong answer
#     about a private account.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

WIRE="Casberi/Casberi/Model/AztecWire.swift"
P2="Casberi/Casberi/Model/AztecPoseidon2.swift"
FIX="scripts/fixtures/aztec"
for f in "$WIRE" "$P2" "$FIX/l1-batch.json" "$FIX/validator-v6.json" "$FIX/nodeinfo-v6.json" "$FIX/validator-active.json" "$FIX/validator-idle.json" "$FIX/validator-unknown.json" \
         "$FIX/tips.json" "$FIX/nodeinfo.json" "$FIX/fees.json" "$FIX/nodeinfo-v6-final.json" "$FIX/validator-v6-final.json" \
         "$FIX/l1-batch-v6-final.json" "$FIX/l1-attester-v6-final.txt" "$FIX/fpc-feejuice-v6-final.json"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP="$(mktemp -d)"
WORK="$TMP/work"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String, line: Int = #line) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what) (line \(line))"); failures += 1 }
}
let fix = ProcessInfo.processInfo.environment["AZTEC_FIX"]!
func load(_ name: String) -> Any? {
    let data = try! Data(contentsOf: URL(fileURLWithPath: fix + "/" + name))
    return try! JSONSerialization.jsonObject(with: data)
}

print("replies")
check(AztecWire.result(load("validator-unknown.json")) == nil, "an unknown attester has no result")
check(AztecWire.sequencer(AztecWire.result(load("validator-unknown.json"))) == nil, "…and reads as no sequencer")
let active = AztecWire.sequencer(AztecWire.result(load("validator-active.json")))!
check(active.address == "0x050a056dd1d0f98e58cc038e633f45e1737982fd", "address read and lowercased")
check(active.totalSlots == 768 && active.slotWindow == 768, "the node's 768-slot window")
check(active.attestations.total == 751 && active.attestations.count == 0, "751 attestations, none missed")
check(active.proposals.total == 17 && active.proposed == 17, "17 proposals, every one mined")
check(active.epochs == 513 && active.epochsMissed == 1, "513 all-time epochs, one with a miss")
check(AztecWire.line(active) == "Attested 751 of 751 · proposed 17", "the roster line: \(AztecWire.line(active))")
let idle = AztecWire.sequencer(AztecWire.result(load("validator-idle.json")))!
check(idle.totalSlots == 0 && idle.epochs == 35, "an idle sequencer keeps its all-time epochs")
check(AztecWire.line(idle) == "Not on a committee lately — 35 epochs all-time", "the idle line: \(AztecWire.line(idle))")

print("chain")
let tips = AztecWire.tips(AztecWire.result(load("tips.json")))!
check(tips.proposed == 115472 && tips.checkpointed == 115472 && tips.proven == 115465, "proposed, checkpointed and proven heads: \(tips)")
check(tips.provenLag == 7, "proven lags proposed by 7")
let chain = AztecWire.chain(AztecWire.result(load("nodeinfo.json")))!
check(chain.key == "0xd73a91bdcf6891c7642f3e460036e1ef2cc23178:1821665230", "the chain's key is rollup:version")
check(chain.l1ChainID == 11155111, "on Sepolia")
check(AztecWire.minL2Fee(AztecWire.result(load("fees.json"))) != nil, "a minimum L2 fee")

print("pastes")
check(AztecWire.attester(" 0x050A056DD1D0F98E58CC038E633F45E1737982FD. ") == "0x050a056dd1d0f98e58cc038e633f45e1737982fd", "an attester, trimmed and lowercased")
check(AztecWire.attester("https://testnet.aztecscan.xyz/validators/0x050a056dd1d0f98e58cc038e633f45e1737982fd") != nil, "…from an explorer link")
let account = "0x07ba0cac13d2eee4952c71ffe4b52bd64a54a3f48110cedf58f8c925e25d8416"
check(AztecWire.attester(account) == nil, "a 32-byte Aztec account is not an attester")
check(AztecWire.isAccountAddress(account), "…and is named as an account")
check(AztecWire.attester("0x050a056dd1d0f98e58cc038e633f45e1737982f") == nil, "a short address refused")

print("events")
func reading(_ s: AztecWire.Sequencer, through slot: Int, streak: Int = 0) -> AztecWire.Sequencer {
    AztecWire.Sequencer(address: s.address, totalSlots: s.totalSlots, proposals: s.proposals,
                        attestations: AztecWire.Missed(streak: streak, count: s.attestations.count, total: s.attestations.total),
                        lastProposal: s.lastProposal, lastAttestation: s.lastAttestation,
                        history: s.history.filter { $0.slot <= slot }, epochs: s.epochs,
                        epochsMissed: s.epochsMissed, lastProcessedSlot: slot, slotWindow: s.slotWindow)
}
check(AztecWire.events(old: nil, new: active).isEmpty, "the first reading lands nothing")
let mined = active.history.filter { $0.status == "checkpoint-mined" }.map(\.slot).sorted()
let cut = mined[mined.count - 4]
let later = AztecWire.events(old: reading(active, through: cut), new: active)
check(later.count == 3 && later.allSatisfy { $0.kind == .proposed }, "three proposals after the cut, one row each")
check(later.first?.title == "Proposed a checkpoint — slot \(AztecWire.grouped(mined[mined.count - 3]))", "the row names its slot: \(later.first?.title ?? "-")")
check(Set(later.map { $0.ref(active.address) }).count == 3, "each row has its own ref")
check(AztecWire.events(old: active, new: active).isEmpty, "the same reading twice lands nothing")
var pending = active.history
pending.append(AztecWire.Duty(slot: (active.lastProcessedSlot ?? 0) + 1, status: "checkpoint-valid"))
let withPending = AztecWire.Sequencer(address: active.address, totalSlots: active.totalSlots, proposals: active.proposals,
                                      attestations: active.attestations, lastProposal: active.lastProposal,
                                      lastAttestation: active.lastAttestation, history: pending, epochs: active.epochs,
                                      epochsMissed: active.epochsMissed, lastProcessedSlot: active.lastProcessedSlot,
                                      slotWindow: active.slotWindow)
check(AztecWire.events(old: active, new: withPending).isEmpty, "a proposal not yet mined lands nothing")
var missedHistory = active.history
missedHistory.append(AztecWire.Duty(slot: (active.lastProcessedSlot ?? 0) + 2, status: "checkpoint-missed"))
let withMiss = AztecWire.Sequencer(address: active.address, totalSlots: active.totalSlots, proposals: active.proposals,
                                   attestations: active.attestations, lastProposal: active.lastProposal,
                                   lastAttestation: active.lastAttestation, history: missedHistory, epochs: active.epochs,
                                   epochsMissed: active.epochsMissed, lastProcessedSlot: active.lastProcessedSlot,
                                   slotWindow: active.slotWindow)
let miss = AztecWire.events(old: active, new: withMiss)
check(miss.count == 1 && miss[0].kind == .missedProposal && miss[0].tags == ["Node", "Missed"], "a missed proposal is tagged missed")
let end = active.lastProcessedSlot ?? 0
let two = AztecWire.events(old: reading(active, through: end, streak: 0), new: reading(active, through: end, streak: 2))
check(two.isEmpty, "two misses in a row are a stumble, not a stop")
let stopped = AztecWire.events(old: reading(active, through: end, streak: 2), new: reading(active, through: end, streak: 3))
check(stopped.count == 1 && stopped[0].kind == .stopped && stopped[0].tags == ["Node", "Offline"], "the third miss in a row is a stop, tagged offline")
check(stopped.first?.ref(active.address).contains(":stopped:") == true, "a stop's ref carries the kind the alarm reads")
check(stopped.first?.title == "Stopped attesting — 3 missed in a row", "…worded: \(stopped.first?.title ?? "-")")
check(AztecWire.isStopped(reading(active, through: end, streak: 3)), "a streak of three reads as stopped")
check(AztecWire.events(old: reading(active, through: end, streak: 3), new: reading(active, through: end, streak: 9)).isEmpty,
      "a stop that continues lands once")
let back = AztecWire.events(old: reading(active, through: end, streak: 9), new: reading(active, through: end, streak: 0))
check(back.count == 1 && back[0].kind == .resumed && back[0].title == "Attesting again — after 9 missed", "a recovery lands once")
check(AztecWire.events(old: reading(active, through: end, streak: 1), new: reading(active, through: end, streak: 0)).isEmpty,
      "recovering from a stumble lands nothing")

let missing = AztecWire.Sequencer(address: active.address, totalSlots: active.totalSlots, proposals: active.proposals,
                                   attestations: AztecWire.Missed(streak: 0, count: 3, total: 751),
                                   lastProposal: active.lastProposal, lastAttestation: active.lastAttestation,
                                   history: active.history, epochs: active.epochs, epochsMissed: active.epochsMissed,
                                   lastProcessedSlot: active.lastProcessedSlot, slotWindow: active.slotWindow)
check(AztecWire.line(missing) == "Attested 748 of 751 · proposed 17 · missed 3", "a missing sequencer's line: \(AztecWire.line(missing))")

let slim = AztecWire.slim(active)
check(slim.history.allSatisfy { !$0.status.hasPrefix("attestation-") } && slim.history.count == 17, "a stored reading keeps proposer duty only")
check(AztecWire.events(old: slim, new: active).isEmpty, "a stored reading against its own fresh copy lands nothing")
func counted(_ n: Int) -> AztecWire.Sequencer {
    AztecWire.Sequencer(address: active.address, totalSlots: active.totalSlots, proposals: active.proposals,
                        attestations: AztecWire.Missed(streak: 0, count: n, total: 751),
                        lastProposal: active.lastProposal, lastAttestation: active.lastAttestation,
                        history: active.history, epochs: active.epochs, epochsMissed: active.epochsMissed,
                        lastProcessedSlot: active.lastProcessedSlot, slotWindow: active.slotWindow)
}
let away = AztecWire.events(old: counted(0), new: counted(40))
check(away.count == 1 && away[0].kind == .missedAway && away[0].title == "Missed 40 attestations", "a stop between two readings lands once, after the fact")
check(AztecWire.events(old: counted(0), new: counted(2)).isEmpty, "two scattered misses land nothing")

print("v6 and Ethereum")
let v6 = AztecWire.sequencer(AztecWire.result(load("validator-v6.json")))!
check(v6.epochs == 52 && v6.recentEpochs.count == 48, "the strip keeps the last 48 of 52 epochs")
check(v6.recentEpochs.allSatisfy { $0 == 0 }, "…every one clean")
// 60 epochs, handed over newest first; the 12 OLDEST each missed a slot.
let epochsReply: [String: Any] = ["validator": ["address": "0xab", "totalSlots": 1, "history": []] as [String: Any],
    "allTimeEpochPerformance": (0..<60).reversed().map { e -> [String: Any] in ["epoch": e, "missed": e < 12 ? 1 : 0, "total": 32] }]
let strip = AztecWire.sequencer(epochsReply)!.recentEpochs
check(strip.count == 48 && strip.allSatisfy { $0 == 0 }, "the strip is the NEWEST 48, sorted by epoch")
let chain6 = AztecWire.chain(AztecWire.result(load("nodeinfo-v6.json")))!
check(chain6.nodeVersion == "6.0.0-rc.1" && chain6.rollup == "0x8c2fb2a68a3d362ab1de99e06f83f8903160bbd9", "v6.0.0-rc.1 had its own rollup")
check(chain6.stakingAsset?.lowercased() == "0x5595cb9ed193cac2c0bc5393313bc6115817954b", "the stake token's address")

print("v6.0.0, the final testnet (read 2026-10-26)")
let final6 = AztecWire.chain(AztecWire.result(load("nodeinfo-v6-final.json")))!
check(final6.nodeVersion == "6.0.0" && final6.version == 679_261_766 && final6.l1ChainID == 11_155_111,
      "node 6.0.0, rollup version 679261766, on Sepolia")
check(final6.rollup == "0x1f435a7f2da358caf887a470faeee7d5d5f4efba" && final6.key != chain6.key,
      "its rollup is the Registry's canonical one, a new chain to the store")
check(final6.stakingAsset == chain6.stakingAsset && final6.governance?.lowercased() == "0xcaf7447721447b22cd0076ac7c63877c3afd329f",
      "the same stake token and Governance as the release candidates")
let seq6 = AztecWire.sequencer(AztecWire.result(load("validator-v6-final.json")))!
check(seq6.address == "0x3332bf09054de0e3a8cd667bf5a7b6a8d90cb2f8" && seq6.totalSlots == 190, "a committee member's duty, read off the v6 node")
check(AztecWire.line(seq6) == "Attested 185 of 185 · proposed 5", "its line: \(AztecWire.line(seq6))")
check(seq6.recentEpochs.count == 17, "seventeen epochs since the reset")
let l1v6 = AztecWire.batchResults(load("l1-batch-v6-final.json"))
let stake6 = AztecWire.stake(view: l1v6[100], rewards: l1v6[101])!
check(stake6.status == .validating && AztecWire.tokens(stake6.staked) == "200,000" && stake6.rewards == 0,
      "the v6 Rollup answers the same selectors: validating, 200,000 STK")
let attester6 = (try! String(contentsOfFile: fix + "/l1-attester-v6-final.txt", encoding: .utf8)).trimmingCharacters(in: .whitespacesAndNewlines)
check(AztecWire.addresses(l1v6[1]!)?.count == 48 && AztecWire.addresses(l1v6[1]!)?.first == attester6, "its committee: 48, the attester first")
check(AztecWire.string(l1v6[2]!) == "STK", "the stake token's symbol")
let fpc6 = "0x2d8fff82a3b0c15d0a89169e7d8d043e079ab94d52031f1de1e4972ebad169d3"
check(AztecWire.feeJuiceSlot(fpc6) == "0x19fd6f21e3abf3142e0a10cf9af7e3809480d788e0c093b126f5ca41da61702f",
      "the v6 sponsored FPC's Fee Juice slot matches @aztec-labs/stdlib 6.0.0")
check(AztecWire.feeJuice(AztecWire.result(load("fpc-feejuice-v6-final.json"))).map { AztecWire.tokens($0) } == "366.75",
      "…and the v6 node answers it: 366.75 Fee Juice")
let l1 = AztecWire.batchResults(load("l1-batch.json"))
let stake = AztecWire.stake(view: l1[100], rewards: l1[101])!
check(stake.status == .validating && stake.status.word == "Validating", "status 1 reads as validating")
check(AztecWire.tokens(stake.staked) == "200,000", "the stake in whole STK: \(AztecWire.tokens(stake.staked))")
check(stake.rewards == 0, "no rewards on the attester")
check(AztecWire.string(l1[2]!) == "STK", "the stake token's symbol")
let attester = (try! String(contentsOfFile: fix + "/l1-attester.txt", encoding: .utf8)).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
let committee = AztecWire.addresses(l1[1]!)!
check(committee.count == 48 && committee.contains(attester), "the committee: 48, the attester on it")
check(committee.first == "0x63d7485e20711a251fb63172ebe5900edfe79983" && committee.last == "0xd0a50a3d6917eecea2397dea288225096ca73173", "the committee's first and last members")
check(AztecWire.word(address: "0xABCDEF") == String(repeating: "0", count: 58) + "abcdef", "an address as one word")
check(AztecWire.word(32) == String(repeating: "0", count: 62) + "20", "an integer as one word")
check(AztecWire.nextProposal(of: attester, proposers: [nil, "0x01", attester.uppercased(), attester], startSlot: 100) == 102,
      "the first slot it proposes, case-blind")
check(AztecWire.nextProposal(of: attester, proposers: ["0x01"], startSlot: 100) == nil, "none in the window")
let exiting = AztecWire.Stake(status: .exiting, staked: stake.staked, rewards: 0)
check(AztecWire.stakeEvent(old: nil, new: stake, slot: 1) == nil, "a first stake reading lands nothing")
check(AztecWire.stakeEvent(old: stake, new: stake, slot: 1) == nil, "an unchanged status lands nothing")
let exitRow = AztecWire.stakeEvent(old: stake, new: exiting, slot: 9)
check(exitRow?.title == "Started exiting — the stake unlocks after a delay" && exitRow?.ref("0xa").contains(":status:9") == true, "exiting lands once, by slot")

print("Poseidon2 and public Fee Juice")
func f(_ n: UInt64) -> Data { AztecPoseidon2.field(String(n, radix: 16))! }
check(AztecPoseidon2.hex(AztecPoseidon2.hash([f(1), f(2), f(3)])) == "0x23864adb160dddf590f1d3303683ebcb914f828e2635f6e85a32f0a1aecd3dd8",
      "poseidon2([1,2,3]) matches aztec.js")
check(AztecWire.feeJuiceSlot("0x2ece607a8dba690c9aa4ee1d53a55286fa815543a27f9364bbaf65eb68e7315b") == "0x1952c68e0d610ed871634f4d2d14dc04aeaa93888f16f79cadb9de7c89e37d5e",
      "the FPC's Fee Juice slot matches aztec.js (read live: 1,502,868 on v5)")
check(AztecWire.feeJuice("0x00000000000000000000000000000000000000000001randomness") == nil, "a garbage field is no balance")
check(AztecWire.feeJuice("0x13e3ea60b3d2505d111c1") == Decimal(string: "1502868.204409181430682049"), "a field read as whole Fee Juice")
check(AztecWire.account(" 0x07BA0CAC13D2EEE4952C71FFE4B52BD64A54A3F48110CEDF58F8C925E25D8416 ") == account, "an account, trimmed and lowercased")
check(AztecWire.account("0x050a056dd1d0f98e58cc038e633f45e1737982fd") == nil, "an attester is not an account")

print("time")
let stamp = active.lastAttestation!
check(AztecWire.date(of: stamp.slot, in: active) == stamp.date, "a stamped slot is exact")
check(AztecWire.date(of: stamp.slot - 10, in: active) == stamp.date.addingTimeInterval(-720), "ten slots earlier is 12 minutes earlier")

if failures > 0 { print("✗ \(failures) failed"); exit(1) }
SWIFT

echo "AztecWire, compiled whole"
if ! swiftc -Onone -o "$TMP/run" "Casberi/Shared/AddressTail.swift" "$WIRE" "$P2" "$TMP/main.swift" > "$TMP/build.log" 2>&1; then
  echo "✗ the harness did not compile against the shipped AztecWire:"
  sed -n '1,40p' "$TMP/build.log"
  exit 1
fi
AZTEC_FIX="$PWD/$FIX" "$TMP/run" || exit 1

# --- mutations ----------------------------------------------------------------
echo
echo "mutations — each must be caught"
mutate() {
  local name="$1" from="$2" to="$3"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$WIRE" "$WORK/AztecWire.swift"
  if ! MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/AztecWire.swift" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  then echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1; fi
  if cmp -s "$WIRE" "$WORK/AztecWire.swift"; then
    echo "  ✗ $name — the mutation changed nothing"; exit 1
  fi
  if ! swiftc -Onone -o "$TMP/mut" "Casberi/Shared/AddressTail.swift" "$WORK/AztecWire.swift" "$P2" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if AZTEC_FIX="$PWD/$FIX" "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

mutate "the first reading lands the window" \
  'guard let old else { return [] }' \
  'let old = old ?? Sequencer(address: new.address, totalSlots: 0, proposals: new.proposals, attestations: new.attestations, lastProposal: nil, lastAttestation: nil, history: [], epochs: 0, epochsMissed: 0, lastProcessedSlot: 0, slotWindow: nil)'
mutate "a proposal landed before it is final" \
  'case "checkpoint-mined":' \
  'case "checkpoint-mined", "checkpoint-valid":'
mutate "a stumble read as a stop" \
  'static let stoppedStreak = 3' \
  'static let stoppedStreak = 2'
mutate "a continuing stop landed every pass" \
  'if now >= stoppedStreak && was < stoppedStreak {' \
  'if now >= stoppedStreak {'
mutate "recovering from a stumble landed" \
  '} else if now == 0 && was >= stoppedStreak {' \
  '} else if now == 0 && was > 0 {'
mutate "a 32-byte account accepted as an attester" \
  'guard hex.count == 40, hex.allSatisfy(\.isHexDigit) else { return nil }' \
  'guard hex.count >= 40, hex.allSatisfy(\.isHexDigit) else { return nil }'
mutate "an attester kept in the case it was pasted" \
  'return "0x" + hex.lowercased()' \
  'return "0x" + hex'
mutate "a slot dated the wrong way from its anchor" \
  'TimeInterval(slot - anchor.slot) * Network.slotSeconds' \
  'TimeInterval(anchor.slot - slot) * Network.slotSeconds'
mutate "the proven head read from the checkpointed one" \
  'return Tips(proposed: proposed, checkpointed: block("checkpointed"), proven: block("proven"))' \
  'return Tips(proposed: proposed, checkpointed: block("checkpointed"), proven: block("checkpointed"))'
mutate "missed attestations counted as attested" \
  'var attested: Int { attestations.total - attestations.count }' \
  'var attested: Int { attestations.total }'
mutate "a stop between readings never said" \
  'new.attestations.count - old.attestations.count >= stoppedStreak {' \
  'new.attestations.count - old.attestations.count >= Int.max {'
mutate "the stored reading keeps attestations" \
  'history: s.history.filter { !$0.status.hasPrefix("attestation-") },' \
  'history: s.history,'
mutate "the stake read from the status word" \
  'let status = Status(rawValue: raw), let balance = uint(w[1]) else { return nil }' \
  'let status = Status(rawValue: raw), let balance = uint(w[0]) else { return nil }'
mutate "the stake left in base units" \
  'return Stake(status: status, staked: whole(balance), rewards: earned.map(whole))' \
  'return Stake(status: status, staked: balance, rewards: earned.map(whole))'
mutate "the committee read from its offset word" \
  'return w[(offset + 1)..<(offset + 1 + n)].compactMap(address)' \
  'return w[offset..<(offset + n)].compactMap(address)'
mutate "the next proposal off by one slot" \
  'proposers.firstIndex { $0?.lowercased() == me }.map { startSlot + $0 }' \
  'proposers.firstIndex { $0?.lowercased() == me }.map { startSlot + $0 + 1 }'
mutate "a first stake reading landing a row" \
  'guard let old, old.status != new.status else { return nil }' \
  'guard old?.status != new.status else { return nil }'
mutate "the Fee Juice map slot read as 0" \
  'static let feeJuiceBalancesSlot: UInt64 = 1' \
  'static let feeJuiceBalancesSlot: UInt64 = 0'
mutate "the strip keeping the oldest epochs" \
  'recentEpochs: epochs.suffix(stripEpochs)' \
  'recentEpochs: epochs.prefix(stripEpochs)'
mutate "a missed proposal tagged as a proposal" \
  'case .missedProposal: return ["Node", "Missed"]' \
  'case .missedProposal: return ["Node", "Proposed"]'

echo "✓ Aztec self-test passed"
