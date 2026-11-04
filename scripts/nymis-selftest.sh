#!/bin/zsh
# Casberi Nymis self-test (prd §1701) — the SHIPPED pure logic behind Wallet ›
# Threats' Privacy rows, compiled WHOLE and unmodified:
#
#   Casberi/Casberi/Model/NymisScan.swift
#
# driven off scripts/fixtures/nymis-report.html, a MADE-UP report in the shape
# measured on 2026-11-04 (no real person's report is ever committed: the repo
# is public). Every failure here renders as a perfectly good-looking sheet:
#
#   · a payload split across two React pushes read as half a report
#   · a category Nymis adds tomorrow shown as its code ("mysteryNew")
#   · a `$$` escape drawn as two dollar signs
#   · an unknown progress word read as success, so a dead scan "completes"
#   · a typed string that is not an address reaching Nymis's URL
#   · a score, a grade or points drawn anywhere (user: "NOT have their score")
#   · a scan started by anything but the Scan control or its probe
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

SHAPE="Casberi/Casberi/Model/NymisScan.swift"
SCANS="Casberi/Casberi/Model/NymisScans.swift"
ROWS="Casberi/Casberi/Screens/FeedScreen+WalletPrivacy.swift"
SHEET="Casberi/Casberi/Screens/NymisReadingSheet.swift"
FIXTURE="scripts/fixtures/nymis-report.html"
for f in "$SHAPE" "$SCANS" "$ROWS" "$SHEET" "$FIXTURE"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# ── Drift guards ────────────────────────────────────────────────────────────
# Only the Scan control, Scan again and the probe start a scan.
callers=$(grep -rlF 'NymisScans.shared.scan(' Casberi/Casberi | sort | tr '\n' ' ')
[[ "$callers" == "Casberi/Casberi/Screens/FeedScreen+WalletPrivacy.swift Casberi/Casberi/Screens/NymisReadingSheet.swift Casberi/Casberi/Shell/ProbeHooks.swift " ]] \
  || { echo "✗ a scan starts from somewhere other than the Scan control: $callers"; exit 1; }
# No score, grade or points on screen.
if grep -nEi 'score|grade|percentile' "$ROWS" "$SHEET" | grep -vE '^\S+:[0-9]+:\s*///'; then
  echo "✗ a score, grade or percentile is drawn"; exit 1
fi
# The page's web view keeps nothing.
grep -qF 'config.websiteDataStore = .nonPersistent()' "$SCANS" \
  || { echo "✗ Nymis's page keeps cookies or storage on this phone"; exit 1; }
# Every read goes through the receipts funnel, and the host is disclosed.
if grep -nE 'URLSession|dataTask' "$SCANS"; then
  echo "✗ NymisScans reads past IngestSupport, where the receipts never see it"; exit 1
fi
grep -qF 'hosts: ["nymis.io"]' Casberi/Casberi/Model/NetworkReach.swift \
  || { echo "✗ nymis.io is not in NetworkReach"; exit 1; }
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
let html = try! String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
let when = Date(timeIntervalSince1970: 1_793_832_915)
let r = NymisScan.reading(fromReportHTML: html, address: "0x00000000000000000000000000000000000A11CE", scannedAt: when)
check(r != nil, "a report split across two pushes reads whole")
if let r {
    check(r.address == "0x00000000000000000000000000000000000a11ce", "the address is filed lowercased")
    check(r.summary.hasPrefix("$This address") && !r.summary.hasPrefix("$$"), "a `$$` escape reads as one dollar sign")
    check(NymisScan.rowLine(r) == "Related addresses, exchanges, identity, Safe signing",
          "the row line is most first, an unknown category left out: \(NymisScan.rowLine(r) ?? "nil")")
    let f = r.findings.map { "\($0.label)=\($0.value)" }
    check(f == ["Related addresses=4, 1 named", "Exchanges=Coinbase, Kraken", "Identity=X, ENS",
                "Signs for=3 Safes", "Active=Mar 2022 to Nov 2026"],
          "the findings, in order, none for zero contracts: \(f)")
    check(r.partial, "a coverage warning marks the reading partial")
    check(r.scannedAt == when, "the scan's own time is kept")
}
check(NymisScan.reading(fromReportHTML: "<html>NYMIS</html>", address: "0x00000000000000000000000000000000000a11ce", scannedAt: when) == nil,
      "a page with no report reads as nil, never as an empty reading")
let noSummary = html.replacingOccurrences(of: "walletSummary", with: "walletSummaryGone")
check(NymisScan.reading(fromReportHTML: noSummary, address: "0x00000000000000000000000000000000000a11ce", scannedAt: when) == nil,
      "a report with no summary is refused")

func p(_ s: String) -> NymisScan.Progress? { NymisScan.progress(from: s.data(using: .utf8)!) }
check(p(#"{"status":null,"stage":null,"scanId":null}"#)?.status == NymisScan.Status.none, "a null status is no scan")
check(p(#"{"status":"running","stage":{"stage":"checking-related-wallets"},"scanId":"bf59181c-42ea-4886-b8e4-bb6c09913c03","startedAt":1793832761061}"#)?.status == .running, "running reads as running")
check(p(#"{"status":"completed","scanId":"x","completedAt":1793832915590}"#)?.completedAt == Date(timeIntervalSince1970: 1793832915.59), "completedAt is milliseconds")
check(p(#"{"status":"exploded"}"#)?.status == .failed, "an unknown word is a failure, never success")
check(p(#"{"stage":"x"}"#) == nil, "a body with no status key is not progress")
check(p("[1,2]") == nil, "a non-object is not progress")
check(NymisScan.stageWords("checking-related-wallets") == "Checking related wallets", "stage words")
check(NymisScan.stageWords("resolving-cex-interactions") == "Resolving exchange interactions", "cex reads as exchange")
check(NymisScan.stageWords(nil) == nil && NymisScan.stageWords("") == nil, "no stage, no words")

check(NymisScan.analyzeURL("vitalik.eth") == nil, "a name never reaches Nymis's URL")
check(NymisScan.analyzeURL("0x2f60/../../admin") == nil, "a path never reaches Nymis's URL")
check(NymisScan.analyzeURL("0x00000000000000000000000000000000000A11CE")?.absoluteString
      == "https://nymis.io/analyze/0x00000000000000000000000000000000000a11ce", "the analyze URL")
check(NymisScan.reportURL(scanID: "../api") == nil, "a scan id that is not a UUID is refused")
check(NymisScan.reportURL(scanID: "BF59181C-42EA-4886-B8E4-BB6C09913C03")?.absoluteString
      == "https://nymis.io/scan/bf59181c-42ea-4886-b8e4-bb6c09913c03", "the report URL")
check(NymisScan.activeSpan(first: "Apr 25, 2021", last: "Apr 30, 2021") == "Apr 2021", "one month when they meet")
check(NymisScan.activeSpan(first: "soon", last: "Nov 4, 2026") == nil, "an unreadable date drops the row")
exit(failures == 0 ? 0 : 1)
SWIFT
xcrun swiftc -O "$SHAPE" "$WORK/main.swift" -o "$WORK/nymis" 2>&1 | grep -v "^$" || true
[[ -x "$WORK/nymis" ]] || { echo "✗ NymisScan.swift did not compile on its own"; exit 1; }
echo "Nymis self-test"
"$WORK/nymis" "$FIXTURE"
echo "✓ Nymis self-test passed"
