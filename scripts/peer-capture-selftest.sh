#!/bin/zsh
# Deposit's capture (prd §1607): Peer's template read, the one request it
# names told apart from every other the page makes, the session assembled as
# the enclave reads it, and the payments and params read off the answer.
#
#   Casberi/Casberi/Model/PeerCapture.swift
#
# compiled WHOLE and unmodified over Peer's REAL Cash App template, recorded
# 2026-10-29 (`scripts/support/peer-cashapp-template.json`), and an activity
# answer shaped by that template's own paths. The answer is SYNTHETIC: what
# Cash App's page really returns is unseen until someone signs in (§1606
# item 3), so this proves the reader follows the template, not that the
# template matches Cash App today.
#
# WHY. Each part fails quietly. A loose URL match seals the wrong request's
# session; a dropped header is a verify the enclave refuses with no reason we
# can show; a template pointing its sign-in at another host would have us seal
# whatever that host's page sent; a mis-read index proves the wrong payment.
#
# Pure, local, deterministic — no network, no key, no simulator.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="Casberi/Casberi/Model/PeerCapture.swift"
TEMPLATE="scripts/support/peer-cashapp-template.json"
for f in "$SRC" "$TEMPLATE"; do [[ -f "$f" ]] || { print -u2 "✗ $f not found"; exit 1; }; done
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1; }

cat > "$work/main.swift" <<'SWIFT'
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) { if !ok { print("  ✗ \(what)"); failures += 1 } }
typealias C = PeerCapture
let json = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]

// The template.
guard let t = C.template(json: json) else { print("  ✗ Peer's Cash App template reads"); exit(1) }
check(t.platform == "cashapp" && t.actionType == "transfer_cashapp", "the platform and action")
check(t.authLink.absoluteString == "https://cash.app/account/activity", "the sign-in page")
check(t.method == "POST", "the request is a POST")
check(t.userAgent?.contains("Macintosh") == true, "the template's desktop user agent")
check(t.paramNames == ["SENDER_ID"], "the one public param")
func edited(_ f: (inout [String: Any]) -> Void) -> [String: Any] { var j = json; f(&j); return j }
check(C.template(json: edited { $0["authLink"] = "https://cash.app.evil.example/account/activity" }) == nil,
      "a sign-in on another host is refused")
check(C.template(json: edited { $0["authLink"] = "http://cash.app/account/activity" }) == nil, "a sign-in over http is refused")
check(C.template(json: edited { $0["paramSelectors"] = [] }) == nil, "params without their paths are refused")
check(C.template(json: edited { var m = $0["metadata"] as! [String: Any]; m["urlRegex"] = "(["; $0["metadata"] = m }) == nil,
      "a pattern that is not a pattern is refused")

// Which request.
let target = "https://cash.app/cash-app/activity/v1.0/page"
check(C.isTarget(t, method: "POST", url: target), "the activity page request is the target")
check(C.isTarget(t, method: "post", url: target), "whatever the method's case")
check(!C.isTarget(t, method: "GET", url: target), "not as a GET")
check(!C.isTarget(t, method: "POST", url: target + "/more"), "not a longer path")
check(!C.isTarget(t, method: "POST", url: "https://evil.example/?u=" + target), "not a URL that merely contains it")

// The session.
let headers = ["x-csrf-token": " t ", "x-device-name": "d", "x-request-signature": "s", "x-request-uuid": "u",
               "Cash-Web-Request": "1", "x-web-device-info": "i", "x-web-context": "c", "x-bt-id": "b"]
let s = C.session(headers: headers, body: "{\"a\":1}", cookies: [("one", "1"), ("two", "2")], userAgent: "UA")
check(s["Cookie"] == "one=1; two=2", "every cookie joins the session as one header")
check(s["x-csrf-token"] == "t", "headers are trimmed")
check(s["User-Agent"] == "UA" && s["body"] == "{\"a\":1}", "the user agent and the body")
check(C.missing(s, platform: "cashapp").isEmpty, "a full capture lacks nothing (case ignored)")
check(C.missing(C.session(headers: [:], body: nil, cookies: [], userAgent: "UA"), platform: "cashapp").count == 9,
      "an empty capture lacks all nine")
var noSig = headers; noSig.removeValue(forKey: "x-request-signature")
check(C.missing(C.session(headers: noSig, body: nil, cookies: [("a", "b")], userAgent: "UA"), platform: "cashapp") == ["x-request-signature"],
      "a missing signature is named")
check(C.session(headers: ["cookie": "page=1"], body: nil, cookies: [("jar", "2")], userAgent: "UA")["Cookie"] == nil,
      "the page's own cookie header is kept, not doubled")
check(C.session(headers: ["User-Agent": "Page"], body: nil, cookies: [], userAgent: "UA")["User-Agent"] == "Page",
      "the page's own user agent is kept")
check(C.session(headers: [:], body: "", cookies: [], userAgent: "UA")["body"] == nil, "an empty body is no body")

// The answer, shaped by the template's own paths.
func row(_ tag: String, _ cents: Int, _ sender: String) -> [String: Any] {
    ["payment_history_inputs_row": [
        "recipient": ["cashtag": tag],
        "payment": ["amount": ["amount": cents, "currency_code": "USD"], "display_date": "Oct 29",
                    "history_data": ["transaction_id": "tx-\(tag)"], "state": "COMPLETED",
                    "sender_id": sender]]]
}
let answer: [String: Any] = ["activity_rows": [row("$seller", 10000, "C_one"), row("$other", 500, "C_two")]]
let p = C.payments(t, in: answer)
check(p.count == 2, "both rows read")
check(p.first == C.Payment(index: 0, recipient: "$seller", amount: "10000", date: "Oct 29", paymentId: "tx-$seller",
                           currency: "USD", state: "COMPLETED"), "every field at its path, numbers as text")
check(C.params(t, in: answer, index: 1) == ["index": "1", "SENDER_ID": "C_two"], "the params of the row asked")
check(C.params(t, in: answer, index: 2) == nil, "no row, no params")
check(C.payments(t, in: ["rows": []]).isEmpty, "an answer without the list reads as none")

// The path reader.
check(C.value(at: "$.a[1].b", in: ["a": [["b": 1], ["b": 2]]]) as? Int == 2, "keys and indices")
check(C.value(at: "$.a[-1]", in: ["a": [1]]) == nil && C.value(at: "$.a[x]", in: ["a": [1]]) == nil, "a bad index is no value")
check(C.value(at: "$..a", in: ["a": 1]) == nil && C.value(at: "a", in: ["a": 1]) == nil, "anything past the subset is no value")
check(C.value(at: "$", in: [1]) as? [Int] == [1], "the root")

// Paying.
check(C.payURL(t, recipient: "$seller", amount: "100")?.absoluteString == "https://cash.app/$seller/100", "Cash App's pay link")
var other = t; other.payLink = "https://evil.example/{{RECIPIENT_ID}}"
check(C.payURL(other, recipient: "$seller", amount: "1") == nil, "a pay link off the app's host is refused")

if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("  ok   Peer's Cash App template read, the one request told apart, the session as the enclave reads it, the payments at their paths")
SWIFT

xcrun swiftc -O "$SRC" "$work/main.swift" -o "$work/t" 2>&1 | grep -v "^$" || true
[[ -x "$work/t" ]] || fail "the shipped source did not compile"
"$work/t" "$TEMPLATE" || fail "assertions failed against the shipped source"

mutate() {
  local why="$1" expr="$2"
  cp "$SRC" "$work/m.swift"
  perl -0pi -e "$expr" "$work/m.swift"
  cmp -s "$SRC" "$work/m.swift" && fail "mutation matched nothing: $why"
  rm -f "$work/m"
  xcrun swiftc -O "$work/m.swift" "$work/main.swift" -o "$work/m" >/dev/null 2>&1 || fail "mutation did not compile: $why"
  if "$work/m" "$TEMPLATE" >/dev/null 2>&1; then fail "mutation SURVIVED — $why"; fi
  print "  ok   catches  $why"
}
mutate "the pattern not anchored"        's/"\^\(\?:" \+ t\.urlPattern \+ "\)\$"/t.urlPattern/'
mutate "the method never compared"       's/guard method\.uppercased\(\) == t\.method,/guard true,/'
mutate "the sign-in host never checked"  's/let host = auth\.host\(\), onHost\(host, hosts\[platform\]\),/let host = auth.host(), !host.isEmpty,/'
mutate "a lookalike host passes"         's/h == declared \|\| h\.hasSuffix\("\." \+ declared\)/h.hasPrefix(declared)/'
mutate "cookies never added"             's/out\["Cookie"\] = cookies/_ = cookies/'
mutate "the page's cookie doubled"       's/if !out\.keys\.contains\(where: \{ \$0\.caseInsensitiveCompare\("Cookie"\) == \.orderedSame \}\), !cookies\.isEmpty \{/if !cookies.isEmpty {/'
mutate "the signature not required"      's/"x-request-signature", //'
mutate "header case not ignored"         's/!session\.keys\.contains \{ \$0\.caseInsensitiveCompare\(need\) == \.orderedSame \}/!session.keys.contains(need)/'
mutate "the row index not substituted"   's/replacingOccurrences\(of: "\{\{INDEX\}\}", with: String\(index\)\)/replacingOccurrences(of: "{{INDEX}}", with: "0")/'
mutate "a negative index read"           's/n >= 0,\n/\n/'
mutate "the body dropped"                's/if let body, !body\.isEmpty \{ out\["body"\] = body \}//'
