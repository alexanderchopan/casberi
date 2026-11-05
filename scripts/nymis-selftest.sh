#!/bin/zsh
# Casberi Nymis self-test (prd §1701, §1701a) — the SHIPPED pure logic behind
# Wallet › Threats' Privacy rows, compiled WHOLE and unmodified:
#
#   Casberi/Casberi/Model/NymisScan.swift
#
# driven off MADE-UP replies in the shape of Nymis's Privacy Score API
# contract (2026-11-05; no real person's result is ever committed: the repo is
# public). Every failure here renders as a perfectly good-looking sheet, or
# leaks what Nymis asked us to keep:
#
#   · the address or the scan token in a URL
#   · a finding with no evidence refusing the whole reply (evidence is optional)
#   · a cached reply for ANOTHER address filed under this one
#   · a completed scan Nymis did not call authoritative drawn as complete
#   · an unknown status read as success, so a dead scan "completes"
#   · a 429 read as a failure, or its Retry-After as an HTTP date dropped
#   · a typed string that is not an address reaching Nymis
#   · a score, a grade or points drawn anywhere (user: "NOT have their score")
#   · a scan started by anything but the Scan control or its probe
#   · the scan token written to disk or a log
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

SHAPE="Casberi/Casberi/Model/NymisScan.swift"
SCANS="Casberi/Casberi/Model/NymisScans.swift"
ROWS="Casberi/Casberi/Screens/FeedScreen+WalletPrivacy.swift"
SHEET="Casberi/Casberi/Screens/NymisReadingSheet.swift"
for f in "$SHAPE" "$SCANS" "$ROWS" "$SHEET"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# ── Drift guards ────────────────────────────────────────────────────────────
# Only the Scan control, Scan again and the probe start a scan.
callers=$(grep -rlF 'NymisScans.shared.scan(' Casberi/Casberi | sort | tr '\n' ' ')
[[ "$callers" == "Casberi/Casberi/Screens/FeedScreen+WalletPrivacy.swift Casberi/Casberi/Screens/NymisReadingSheet.swift Casberi/Casberi/Shell/ProbeHooks.swift " ]] \
  || { echo "✗ a scan starts from somewhere other than the Scan control: $callers"; exit 1; }
# No score, grade or points on screen, and the reading never reads them.
if grep -nEi 'score|grade|percentile' "$ROWS" "$SHEET" | grep -vE '^\S+:[0-9]+:\s*///'; then
  echo "✗ a score, grade or percentile is drawn"; exit 1
fi
if grep -nE '\["(score|grade)"\]' "$SHAPE"; then
  echo "✗ the reading reads Nymis's score or grade"; exit 1
fi
# No page, no web view: the API is the one door (§1701a).
if grep -nE 'WKWebView|WebKit|/analyze/|scan-progress' "$SHAPE" "$SCANS"; then
  echo "✗ the scraped page's door is back"; exit 1
fi
# Every read goes through the receipts funnel, and the host is disclosed.
if grep -nE 'URLSession|dataTask' "$SCANS"; then
  echo "✗ NymisScans reads past IngestSupport, where the receipts never see it"; exit 1
fi
grep -qF 'IngestSupport.sendRequest(request)' "$SCANS" \
  || { echo "✗ NymisScans does not send through IngestSupport"; exit 1; }
grep -qF 'hosts: ["nymis.io"]' Casberi/Casberi/Model/NetworkReach.swift \
  || { echo "✗ nymis.io is not in NetworkReach"; exit 1; }
# The token stays in memory: never encoded with a running scan, never logged.
if awk '/struct Running/,/^    }/' "$SCANS" | grep -nEi 'token'; then
  echo "✗ the scan token is persisted with a running scan"; exit 1
fi
if grep -nE 'NSLog\(.*[Tt]oken' "$SCANS" "$SHAPE"; then
  echo "✗ the scan token reaches a log"; exit 1
fi
grep -qF '@ObservationIgnored private var tokens' "$SCANS" \
  || { echo "✗ the scan tokens are not private memory"; exit 1; }
# The readings stay on this phone.
grep -qF 'DefaultsWrite.set(data, forKey: Self.readingsKey)' "$SCANS" \
  || { echo "✗ readings are not persisted through DefaultsWrite"; exit 1; }

# ── The logic ───────────────────────────────────────────────────────────────
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/main.swift" <<'SWIFT'
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}
let alice = "0x00000000000000000000000000000000000A11CE"
let aliceKey = alice.lowercased()
let now = Date(timeIntervalSince1970: 1_793_900_000)
let scanID = "11111111-1111-4111-8111-111111111111"
let idem = "9d54bbd4-8570-4a16-8b28-c49e3717d45e"
func answer(_ status: Int, _ body: String?, retryAfter: String? = nil, address: String = alice) -> NymisScan.Answer {
    NymisScan.answer(status: status, retryAfter: retryAfter, body: body?.data(using: .utf8), address: address, now: now)
}

// Requests: nothing private in a URL.
let create = NymisScan.createRequest(address: alice, idempotencyKey: idem)
check(create?.url?.absoluteString == "https://nymis.io/api/v1/privacy-score", "the create URL carries no address")
check(create?.httpMethod == "POST", "create is a POST")
check(create?.value(forHTTPHeaderField: "Idempotency-Key") == idem, "the idempotency key rides a header")
check(create?.value(forHTTPHeaderField: "x-partner-id") == "casberi", "the partner id is attribution")
check(create?.value(forHTTPHeaderField: "Authorization") == nil, "no API key is sent")
let sent = create?.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }
check(sent == ["address": aliceKey], "the address rides the body, lowercased")
check(NymisScan.createRequest(address: "vitalik.eth", idempotencyKey: idem) == nil, "a name never reaches Nymis")
check(NymisScan.createRequest(address: "0x2f60/../../admin", idempotencyKey: idem) == nil, "a path never reaches Nymis")
check(NymisScan.createRequest(address: alice, idempotencyKey: "again") == nil, "a key that is not a UUID is refused")
let poll = NymisScan.pollRequest(scanID: scanID.uppercased(), token: "tok-secret")
check(poll?.url?.absoluteString == "https://nymis.io/api/v1/privacy-score/status/\(scanID)", "the poll URL is the scan id alone")
check(poll?.url?.absoluteString.contains("tok-secret") == false, "the token never reaches a URL")
check(poll?.value(forHTTPHeaderField: "x-scan-token") == "tok-secret", "the token rides x-scan-token")
check(NymisScan.pollRequest(scanID: "../admin", token: "t") == nil, "a scan id that is not a UUID is refused")
check(NymisScan.pollRequest(scanID: scanID, token: "") == nil, "no token, no poll")

// Answers.
check(answer(202, #"{"version":"1","address":"\#(aliceKey)","status":"processing","scanId":"\#(scanID)","coverage":"unscored","scanToken":"tok"}"#)
      == .processing(scanID: scanID, token: "tok"), "a 202 hands the scan id and token")
check(answer(200, #"{"status":"processing","scanId":"\#(scanID)"}"#) == .processing(scanID: scanID, token: nil), "a poll's processing hands no token")
check(answer(202, #"{"status":"processing","scanId":"../x","scanToken":"tok"}"#) == .processing(scanID: nil, token: "tok"),
      "a scan id that is not a UUID is dropped")
check(answer(429, nil, retryAfter: "120") == .busy(until: now.addingTimeInterval(120)), "a 429 waits Retry-After seconds")
check(answer(429, nil, retryAfter: "Fri, 06 Nov 2026 00:00:00 GMT")
      == .busy(until: Date(timeIntervalSince1970: 1_793_923_200)), "a 429's Retry-After as an HTTP date")
check(answer(429, nil) == .busy(until: now.addingTimeInterval(60)), "a 429 with no Retry-After waits a minute")
check(answer(429, nil, retryAfter: "0") == .busy(until: now.addingTimeInterval(10)), "never less than ten seconds")
check(answer(0, nil) == .retry && answer(503, "oops") == .retry, "no answer or a 5xx asks again")
check(answer(409, nil) == .failed && answer(404, nil) == .failed && answer(400, "{}") == .failed, "a refusal ends the scan")
check(answer(200, #"{"status":"failed","code":"result_expired"}"#) == .failed, "an expired result ends the scan")
check(answer(200, #"{"status":"exploded"}"#) == .failed, "an unknown status is a failure, never success")
check(answer(200, "<html>") == .failed, "a body that is not JSON is a failure")

let full = #"""
{"version":"1","address":"\#(aliceKey)","status":"completed","scanId":null,"score":42,"grade":"C",
 "coverage":"scored",
 "completeness":{"status":"complete","authoritative":true,"chainsAnalyzed":["ethereum","base"],
   "activityEventsAnalyzed":812,"providerIssuesDetected":false,"fetchTruncatedEarly":false},
 "findings":{
   "Identity":[{"id":"ens","title":"Linked to an ENS name","severity":"medium","explanation":"Resolves to a name.","evidence":[{"ref":"x","type":"ens"}]}],
   "Financial":[
     {"id":"related","title":"Related addresses","severity":"low","explanation":"Two addresses."},
     {"id":"cex","title":"Funded from an exchange","severity":"HIGH","explanation":"  Deposits.  "},
     {"id":"bad","severity":"high","explanation":"no title"}],
   "Behavioral":[],
   "Mystery":[{"id":"m","title":"A group Nymis adds tomorrow","severity":"high","explanation":"x"}]}}
"""#
if case .read(let r) = answer(200, full) {
    check(r.address == aliceKey, "the address is filed lowercased")
    check(r.groups.map(\.name) == ["Identity", "Financial"], "groups in Nymis's order, empty and unknown ones left out")
    check(r.groups.last?.findings.map(\.id) == ["cex", "related"], "a group's findings are most severe first, case aside")
    check(r.findings.count == 3, "a finding with no title is dropped, one with no evidence kept")
    check(r.groups.last?.findings.first?.explanation == "Deposits.", "an explanation is trimmed")
    check(!r.partial, "an authoritative completed scan is whole")
    check(r.scannedAt == now, "the read's own time is kept")
    check(NymisScan.rowLine(r) == "Financial, identity", "the row line is the groups, most first: \(NymisScan.rowLine(r) ?? "nil")")
} else { check(false, "a completed reply reads") }

let unsure = full.replacingOccurrences(of: #""authoritative":true"#, with: #""authoritative":false"#)
if case .read(let r) = answer(200, unsure) { check(r.partial, "a scan Nymis did not call authoritative is partial") }
else { check(false, "a non-authoritative reply still reads") }
let incomplete = #"{"status":"incomplete","score":null,"reason":"provider_timeout","findings":{"Identity":[{"id":"a","title":"A","severity":"low","explanation":""}]}}"#
if case .read(let r) = answer(200, incomplete) {
    check(r.partial && r.findings.count == 1, "an incomplete scan keeps its findings and is partial")
} else { check(false, "an incomplete reply reads") }
if case .read(let r) = answer(200, #"{"status":"completed","completeness":{"authoritative":true}}"#) {
    check(r.findings.isEmpty && NymisScan.rowLine(r) == nil, "no findings reads as an empty reading, no line")
} else { check(false, "a reply with no findings reads") }
check(answer(200, full, address: "0x000000000000000000000000000000000000b0b0") == .failed,
      "a reply for another address is refused")
exit(failures == 0 ? 0 : 1)
SWIFT
xcrun swiftc -O "$SHAPE" "$WORK/main.swift" -o "$WORK/nymis" 2>&1 | grep -v "^$" || true
[[ -x "$WORK/nymis" ]] || { echo "✗ NymisScan.swift did not compile on its own"; exit 1; }
echo "Nymis self-test"
"$WORK/nymis"
echo "✓ Nymis self-test passed"
