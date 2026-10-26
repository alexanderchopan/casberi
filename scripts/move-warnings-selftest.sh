#!/bin/zsh
# Move's warnings (prd §1509 item 2, §1513, Phase 2 of
# docs/signing-safety-spec.md) — `MoveWarnings`: the lookalike of history,
# the known set's one-way rule (received-from never makes an address known),
# the guard on OFAC's downloaded list (empty, malformed, sharply smaller),
# the order (red over amber, one line), the words, and the readers of
# GoPlus's and Blockscout's answers pinned to bodies measured 2026-10-24;
# then the wiring: a lookalike no longer blocks the line, a warning makes
# the verb a second tap, and a first send leaves it alone.
set -euo pipefail
cd "$(dirname "$0")/.."

WARN="Casberi/Casberi/Model/MoveWarnings.swift"
SENTENCE="Casberi/Casberi/Screens/MoveSentence.swift"
CHECKS="Casberi/Casberi/Model/MoveChecks.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
for f in "$WARN" "$SENTENCE" "$CHECKS" "$REACH"; do [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }; done

TMP=$(mktemp -d /tmp/move-warnings-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
typealias W = MoveWarnings
var bad = 0, ran = 0
func check(_ ok: Bool, _ what: String) { ran += 1; if !ok { print("✗ " + what); bad += 1 } }
// The app's display rule (`AddressSafety.isLookalike`): the same last four, a different address.
func looks(_ a: String, _ b: String) -> Bool { a.lowercased() != b.lowercased() && a.suffix(4).lowercased() == b.suffix(4).lowercased() }
let paid = "0x71c7656ec7ab88b098defb751b7401b5f6d849a2"
let older = "0x0000000000000000000000000000000000aa49a2"
let fake = "0x5e1f7a3b9c0d2e4f6a8b0c2d4e6f8a0b2c4d49a2"
let oct3 = Date(timeIntervalSince1970: 1_791_000_000), sep = Date(timeIntervalSince1970: 1_788_000_000)
let sent = [paid: oct3, older: sep]

// Known: sent to, named, your own. Received-from is not an input at all.
check(W.isKnown(paid.uppercased().replacingOccurrences(of: "0X", with: "0x"), sentTo: sent, named: [], own: []), "an address you paid, typed in caps, is not known")
check(!W.isKnown(fake, sentTo: sent, named: [], own: []), "a lookalike counts as known")
check(W.isKnown(fake, sentTo: [:], named: [fake], own: []) && W.isKnown(fake, sentTo: [:], named: [], own: [fake]), "a named or own address is not known")

// The lookalike of history: the NEWEST paid match, with its day.
check(W.imitated(fake, sentTo: sent, named: [:], own: [], looksLike: looks) == .lookalike(of: paid, name: nil, paid: oct3),
      "the lookalike did not name the newest address you paid")
check(W.imitated(fake, sentTo: [:], named: [paid: "Ana"], own: [], looksLike: looks) == .lookalike(of: paid, name: "Ana", paid: nil),
      "a lookalike of a named entry lost the name")
check(W.imitated(fake, sentTo: [:], named: [:], own: [], looksLike: looks) == nil, "nothing known matched a lookalike")
check(W.imitated(paid, sentTo: sent.filter { $0.key == paid }, named: [:], own: [], looksLike: looks) == nil, "an address looked like itself")

// The words.
let day: (Date) -> String = { _ in "Oct 3" }
let short: (String) -> String = { "..." + String($0.suffix(4)) }
check(W.line(.lookalike(of: paid, name: nil, paid: oct3), short: short, day: day)
      == "Looks like ...49a2, which you paid on Oct 3. They differ in the middle. Check it.", "the lookalike line drifted from the canvas")
check(W.line(.scam(address: fake, sources: "x"), short: short, day: day) == "Reported as a scam address.", "the scam line drifted")
check(W.line(.firstSend, short: short, day: day) == "First send to this address.", "the first-send line drifted")
check(W.contractLine(token: true, unverified: true, ageDays: 2, neverUsed: true) == "Not on Uniswap's list. Its contract is 2 days old, and you've never used it.",
      "the new-contract line drifted from the canvas")
check(W.contractLine(token: true, unverified: false, ageDays: 400, neverUsed: true) == nil, "an old, listed token you never used warned")
check(W.contractLine(token: true, unverified: false, ageDays: 29, neverUsed: false) == "Its contract is 29 days old.", "29 days is not new")
check(W.contractLine(token: true, unverified: false, ageDays: 30, neverUsed: true) == nil, "30 days is still new")
check(W.contractLine(token: false, unverified: false, ageDays: 0, neverUsed: true) == "This address is a contract less than a day old, and you've never sent to it.",
      "a send to a fresh contract is not said")

// The order: red over amber, the refusal first, the note last; arming.
let order = W.ordered([.firstSend, .lookalike(of: paid, name: nil, paid: nil), .scam(address: fake, sources: ""), .fails("x"), .sanctioned(address: fake, listed: nil)])
check(order.map(\.red) == [true, true, true, false, false], "amber stood before red")
check(order.first == .fails("x") && order.last == .firstSend, "the refusal does not lead, or the note is not last")
check(!W.arms([.firstSend]), "a first send made the verb a second tap")
check(W.arms([.firstSend, .lookalike(of: paid, name: nil, paid: nil)]), "a lookalike did not arm the verb")
check(!W.arms([.fails("x"), .scam(address: fake, sources: "")]), "a refused send can be signed anyway")

// OFAC's list: parsed whole, and never replaced by an empty, malformed or shrunk copy.
check(W.ofacList(Data(#"["0x8589427373D6D84E98730D7795D8f6f8731FDA16"]"#.utf8)) == ["0x8589427373d6d84e98730d7795d8f6f8731fda16"], "a good list did not parse")
check(W.ofacList(Data("[]".utf8)) == nil, "an empty list parsed")
check(W.ofacList(Data(#"["0x12"]"#.utf8)) == nil && W.ofacList(Data("<html>".utf8)) == nil, "a malformed list parsed")
let full = (0..<120).map { String(format: "0x%040x", $0) }
check(W.accepts(full, over: 120) && W.accepts(Array(full.prefix(90)), over: 120), "a full or slightly smaller list was refused")
check(!W.accepts(Array(full.prefix(89)), over: 120), "a list that lost more than a quarter was kept")
check(!W.accepts(nil, over: 120) && !W.accepts([], over: 0), "nothing replaced the kept list")
check(W.accepts(full, over: 0), "the first copy was refused")

// GoPlus, as measured: a ScamSniffer drainer, and USDC.
let drainer = #"{"code":1,"message":"ok","result":{"phishing_activities":"1","blacklist_doubt":"1","data_source":"SlowMist,ScamSniffer","stealing_attack":"0","sanctioned":"0","number_of_malicious_contracts_created":"0"}}"#
let clean = #"{"code":1,"message":"ok","result":{"phishing_activities":"0","blacklist_doubt":"0","data_source":"","mixer":"0","number_of_malicious_contracts_created":"0"}}"#
check(W.report(Data(drainer.utf8)) == W.Report(reported: true, sources: "SlowMist, ScamSniffer"), "GoPlus's drainer report was not read")
check(W.report(Data(clean.utf8))?.reported == false, "a clean address read as reported")
check(W.report(Data(#"{"code":1,"result":{"blacklist_doubt":"1"}}"#.utf8))?.reported == false, "a suspicion alone read as a report")
check(W.report(Data(#"{"code":4029,"message":"limit"}"#.utf8)) == nil, "a refusal read as clean")

// Blockscout's getcontractcreation, as measured on Base for USDC, and for an EOA.
let made = #"{"message":"OK","result":[{"blockNumber":"2797221","timestamp":"1692383789","txHash":"0x8a"}],"status":"1"}"#
check(W.creation(Data(made.utf8)) == .at(Date(timeIntervalSince1970: 1_692_383_789)), "USDC's creation time was not read")
check(W.creation(Data(#"{"message":"OK","result":[],"status":"1"}"#.utf8)) == .notContract, "an EOA read as a contract")
check(W.creation(Data("<html>Just a moment</html>".utf8)) == nil, "Cloudflare's wall read as an answer")
check(W.ageDays(Date(timeIntervalSince1970: 0), now: Date(timeIntervalSince1970: 2 * 86_400 + 5)) == 2, "the age is not whole days")

print(bad == 0 ? "move-warnings self-test: \(ran) checks ok" : "move-warnings self-test: \(bad) of \(ran) failed")
exit(bad == 0 ? 0 : 1)
SWIFT
xcrun swiftc -O -o "$TMP/t" "$WARN" "$TMP/main.swift" 2>"$TMP/err" || { cat "$TMP/err"; echo "✗ MoveWarnings.swift does not compile with Foundation alone"; exit 1; }
"$TMP/t" || exit 1

# The wiring.
grep -q 'guard let r = resolved, stands(r) else { return nil }' "$SENTENCE" \
  || { echo "✗ a lookalike blocks the line again — §1509 amends §1438b to a second tap"; exit 1; }
grep -q 'if verb != .buy, warned, armed != armKey {' "$SENTENCE" \
  || { echo "✗ a warned verb signs on the first tap (prd §1509 item 2)"; exit 1; }
grep -q 'stage == nil && !all.isEmpty && failNote == nil' "$SENTENCE" \
  || { echo "✗ a send the simulation refuses no longer dims its verb"; exit 1; }
grep -q 'where sanctions.addresses.contains(a.lowercased())' "$SENTENCE" \
  || { echo "✗ OFAC's list is no longer matched on the phone"; exit 1; }
grep -q '"api.gopluslabs.io", "base.blockscout.com", "eth.blockscout.com", "robinhoodchain.blockscout.com"' "$REACH" \
  && awk '/service: "Move.s checks"/,/throughTor: true/' "$REACH" | grep -q 'throughTor: true' \
  || { echo "✗ Move's checks no longer go through Tor — GoPlus is asked about the address you are paying"; exit 1; }
true
