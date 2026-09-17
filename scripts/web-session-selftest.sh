#!/bin/zsh
# Casberi web-session capture self-test (prd §777) — the pure half of the
# measuring instrument, compiled WHOLE and unmodified:
#
#   Casberi/Casberi/Model/WebSessionCapture.swift
#
# THE SUBJECT IS A PERSON'S MONEY. Five providers publish no API, so the only
# way to write a seat against one is to watch what its own web app calls — and
# the moment that exists, the thing to be sure of is what it may REPORT. Every
# bound below is a test rather than a promise, because the failure mode is a
# diagnostics transcript that somebody copies into a chat carrying an amount,
# an account number or a live bearer token.
#
#   · a URL keeps its path and its query NAMES; every query value goes, and a
#     path segment that carries an account becomes `<id>`
#   · a response is reported as its SHAPE — keys, types, array lengths — and
#     never a value, at bounded depth and width
#   · an Authorization header is reported as its SCHEME, never its credential
#   · a host outside the named target's own is not recorded at all, so an
#     analytics beacon riding the same page is never in the report
#   · `evil-cash.app` is not `cash.app`
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

FEED="Casberi/Casberi/Model/WebSessionCapture.swift"
VIEW="Casberi/Casberi/Screens/WebSessionCaptureView.swift"
for f in "$FEED" "$VIEW"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# DEBUG ONLY. An instrument that records a money provider's traffic must not
# exist in a build anyone but the author runs.
head -1 "$VIEW" | grep -qF '#if DEBUG' \
  || { echo "✗ the capture view is not behind #if DEBUG — an instrument that records a money app must never reach a Release build"; exit 1; }
grep -qF '.nonPersistent()' "$VIEW" \
  || { echo "✗ the capture's cookie jar is not non-persistent — a measurement would leave a money session in the shared jar"; exit 1; }
# The filter is a DROP, not a redaction: the host test runs before the record.
grep -qF 'WebSessionCapture.records(host: url.host, in: target) else { return }' "$VIEW" \
  || { echo "✗ the capture no longer drops a call to a host outside its target"; exit 1; }
grep -qF 'WebSessionCapture.redactedURL(raw)' "$VIEW" \
  || { echo "✗ a raw URL reaches a Call — query values and account ids would be reported"; exit 1; }
grep -qF 'WebSessionCapture.headerNames(' "$VIEW" \
  || { echo "✗ request header names reach a Call without the name filter"; exit 1; }
if grep -vE '^[[:space:]]*//' "$VIEW" | grep -qE '\$0\.value|cookie\.value'; then
  echo "✗ the capture reads a cookie VALUE"; exit 1
fi
grep -qF 'WebSessionCapture.authScheme(' "$VIEW" \
  || { echo "✗ an Authorization header is no longer reduced to its scheme"; exit 1; }
# The report is built from shapes. A raw body string must never reach a Call.
if grep -vE '^[[:space:]]*//' "$VIEW" | grep -qE 'shape: *\(body\["body"\] as\? String\)$'; then
  echo "✗ a response body is carried verbatim into a Call"; exit 1
fi
echo "web-session-selftest: drift guards ✓"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}
func json(_ s: String) -> Any? { try? JSONSerialization.jsonObject(with: Data(s.utf8)) }

// ── The bounded target list ──────────────────────────────────────────────
check(WebSessionCapture.targets.count == 2, "two providers, and no open-ended 'record any site'")
let privy = WebSessionCapture.target("privy")!
check(WebSessionCapture.records(host: "home.privy.io", in: privy), "Privy's dashboard host is recorded")
check(WebSessionCapture.records(host: "auth.privy.io", in: privy), "…and its auth host, a subdomain of the same")
check(!WebSessionCapture.records(host: "notprivy.io", in: privy), "a lookalike of privy.io is NOT Privy")
check(["cashapp", "creditkarma", "rocketmoney", "acorns", "nerdwallet"].allSatisfy { WebSessionCapture.target($0) == nil },
      "a seat that was refused or is built has no capture row")
check(WebSessionCapture.target("bankr")?.apiHosts.contains("api.bankr.bot") == true, "Bankr records its API host")
check(WebSessionCapture.target("bankr")?.name == "Bankr", "a target resolves by key")
check(WebSessionCapture.target(" BANKR ")?.name == "Bankr", "a key is trimmed and case-folded")
check(WebSessionCapture.target("venmo") == nil, "a provider not in the list names nothing")
check(WebSessionCapture.target("") == nil, "and neither does an empty key")

let bankrTarget = WebSessionCapture.target("bankr")!
check(WebSessionCapture.records(host: "bankr.bot", in: bankrTarget), "the target's own host is recorded")
check(WebSessionCapture.records(host: "privy.bankr.bot", in: bankrTarget), "…and a subdomain of it")
check(!WebSessionCapture.records(host: "notbankr.bot", in: bankrTarget), "a lookalike host is NOT the target")
check(!WebSessionCapture.records(host: "google-analytics.com", in: bankrTarget), "a beacon riding the same page is never recorded")
check(!WebSessionCapture.records(host: nil, in: bankrTarget), "a call with no host is not recorded")

// ── A URL keeps its shape and loses its values ───────────────────────────
let raw = "https://api.rocketmoney.com/users/8817342/recurring?limit=50&token=abc123&after=2026-09-01"
let red = WebSessionCapture.redactedURL(raw)
check(red.contains("/users/<id>/recurring"), "an account in the path becomes <id>")
check(red.contains("limit=‹v›") && red.contains("token=‹v›"), "a query keeps its NAMES and loses every value")
check(!red.contains("8817342") && !red.contains("abc123") && !red.contains("2026-09-01"),
      "no value survives — not the account, not the token, not the date")
check(WebSessionCapture.redactedURL("https://cash.app/account") == "https://cash.app/account",
      "a plain path is left alone")
check(WebSessionCapture.redactedURL("https://a.cash.app/v1/x#frag") == "https://a.cash.app/v1/x",
      "a fragment is dropped")
check(WebSessionCapture.redactedURL("not a url") == "<unreadable url>", "an unreadable url says so")
check(WebSessionCapture.looksLikeID("8817342") && WebSessionCapture.looksLikeID("550e8400-e29b-41d4-a716-446655440000"),
      "a digit run and a UUID are both ids")
check(!WebSessionCapture.looksLikeID("recurring") && !WebSessionCapture.looksLikeID("v1"),
      "an endpoint name is not an id")

// ── An Authorization header is a scheme ──────────────────────────────────
check(WebSessionCapture.authScheme("Bearer eyJhbGciOi.payload.sig") == "Bearer", "a bearer is reported as 'Bearer'")
check(WebSessionCapture.authScheme("Basic dXNlcjpwYXNz") == "Basic", "and a basic as 'Basic'")
check(WebSessionCapture.authScheme("") == nil, "an empty header names no scheme")
check(WebSessionCapture.authScheme(nil) == nil, "an absent header names no scheme")

// ── A body is a shape, never a value ─────────────────────────────────────
let body = json(#"""
{"recurring":[{"merchant":"Netflix","amount":17.99,"currency":"USD","active":true,
               "nextDate":"2026-10-01","id":9912345,"logo":null}],
 "total":1}
"""#)
let sketch = WebSessionCapture.shape(body)
check(sketch.contains("merchant: string") && sketch.contains("amount: number"),
      "every key is reported with its TYPE")
check(sketch.contains("active: bool"), "a JSON true is a bool, not the integer it is stored as")
check(sketch.contains("id: int") && sketch.contains("total: int"), "a whole number is an int")
check(sketch.contains("logo: null"), "a null is a null")
check(sketch.contains("[1 × "), "an array is its length and its first element's shape")
check(!sketch.contains("Netflix") && !sketch.contains("17.99") && !sketch.contains("2026-10-01"),
      "NO VALUE survives the sketch — not a merchant, not an amount, not a date")
check(WebSessionCapture.shape(json("[]")) == "[0]", "an empty array says it is empty")
check(WebSessionCapture.shape(nil) == "null", "nothing is null")

// Bounded, so one dashboard response cannot flood a transcript.
var deep: Any = ["leaf": 1]
for _ in 0..<8 { deep = ["nested": deep] }
check(WebSessionCapture.shape(deep).contains("…"), "depth is bounded")
var wide: [String: Any] = [:]
for i in 0..<60 { wide["k\(i)"] = i }
check(WebSessionCapture.shape(wide).contains("more"), "width is bounded, and says how much it left out")

// ── The report ───────────────────────────────────────────────────────────
let calls = [
    WebSessionCapture.Call(method: "POST", url: "https://api.cash.app/login", status: 200,
                           authScheme: nil, shape: "{token: string}"),
    WebSessionCapture.Call(method: "GET", url: "https://api.cash.app/activity?page=‹v›", status: 200,
                           authScheme: "Bearer", shape: "[3 × {amount: number}]"),
    WebSessionCapture.Call(method: "GET", url: "https://api.cash.app/activity?page=‹v›", status: 200,
                           authScheme: "Bearer", shape: "[3 × {amount: number}]"),
    WebSessionCapture.Call(method: "GET", url: "https://api.cash.app/profile", status: 401,
                           authScheme: "Bearer", shape: nil),
]
let report = WebSessionCapture.report(calls)
check(report.count == 3, "the same endpoint asked twice is one line")
check(report.first?.hasPrefix("GET* ") == true, "a replayable GET leads the report")
check(report.contains { $0.contains("POST ") }, "a POST is still reported — it is how a session is minted")
check(report.contains { $0.contains("(no readable body)") }, "a call with nothing to read says so")
check(!calls[3].replayable, "a 401 is not something to replay")
check(!calls[0].replayable, "and neither is a POST")
check(!WebSessionCapture.nothingRecorded.isEmpty, "an empty capture has a sentence of its own")

// ── How a call proves who it is: names, never values ─────────────────────
check(WebSessionCapture.headerNames(["Privy-Id-Token", "x-access-token", "privy-id-token"])
        == ["privy-id-token", "x-access-token"], "header names are lowercased, deduped and sorted")
check(WebSessionCapture.headerNames(["Bearer eyJhbGci", "a=b", "x:y", ""]).isEmpty,
      "a string that is a VALUE in the name slot is dropped, never reported")
let signed = WebSessionCapture.Call(method: "POST", url: "https://api.bankr.bot/api-keys", status: 201,
    authScheme: nil, shape: "{apiKey: string}", headerNames: ["privy-id-token"],
    credentials: "include", sentShape: "{name: string, readOnly: bool}")
let signedLine = WebSessionCapture.report([signed]).first ?? ""
check(signedLine.contains("headers=[privy-id-token]") && signedLine.contains("credentials=include")
      && signedLine.contains("sent {name: string, readOnly: bool}"),
      "a report line names the headers, the credentials mode and the fields sent")
let bankr = WebSessionCapture.target("bankr")!
let jar = WebSessionCapture.cookieReport([
    .init(name: "privy-token", domain: ".bankr.bot", httpOnly: true),
    .init(name: "_ga", domain: ".google.com", httpOnly: false),
], in: bankr)
check(jar == ["cookies: privy-token (httpOnly) @.bankr.bot"],
      "the target's own cookies are named; another site's are not")
check(WebSessionCapture.cookieReport([], in: bankr) == ["cookies: none on this target's hosts"],
      "an empty jar says so")

print(failures == 0 ? "web-session-selftest: all checks ✓" : "web-session-selftest: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

swiftc -O -o "$TMP/run" "$FEED" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ web-session-selftest: compile failed"; exit 1; }
"$TMP/run"
