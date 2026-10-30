#!/bin/zsh
# Casberi Grok thread self-test (prd §1626) — which response in grok.com's
# own `load-responses` read is the answer to what Casberi typed, compiled
# WHOLE and unmodified:
#
#   Casberi/Casberi/Model/GrokThread.swift
#
# The answer is the LAST response, once it is the assistant's, not partial
# and no older than the question (measured 2026-10-30: "lodestar"). Plus the
# drift guards: the Grok fork sends only the redacted question through the
# shared loop, GrokWeb never logs, and Grok is read on grok.com, never x.com.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

THREAD="Casberi/Casberi/Model/GrokThread.swift"
WEB="Casberi/Casberi/Model/GrokWeb.swift"
ANSWER="Casberi/Casberi/Model/AgentAnswer.swift"
for f in "$THREAD" "$WEB" "$ANSWER"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done
if grep -vE '^[[:space:]]*(//|///)' "$WEB" | grep -qE 'NSLog|print\('; then
  echo "✗ GrokWeb logs — the person's chats must never reach a log"; exit 1
fi
# Grok's own site: the X seat stays read-only (the 2026-09-24 rule).
if grep -vE '^[[:space:]]*(//|///)' "$WEB" | grep -qE 'x\.com'; then
  echo "✗ GrokWeb reaches x.com — Grok is asked on grok.com only"; exit 1
fi
grep -qF 'if provider == .grok, TokenVault.get(provider.vaultKey) == nil, WebSession.signedIn(.grok) {' "$ANSWER" \
  || { echo "✗ the Grok session fork is gone or no longer yields to a stored key"; exit 1; }
grep -qF 'return await chatPageAnswer(await GrokWeb.shared, agent: "Grok", query: query, history: history)' "$ANSWER" \
  || { echo "✗ the Grok fork no longer goes through chatPageAnswer"; exit 1; }
echo "grok-thread-selftest: drift guards ✓"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}
func iso(_ t: Double) -> String {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.string(from: Date(timeIntervalSince1970: t))
}
func resp(_ sender: String, _ message: String, at t: Double? = nil, partial: Bool? = nil) -> [String: Any] {
    var r: [String: Any] = ["responseId": UUID().uuidString, "sender": sender, "message": message]
    if let t { r["createTime"] = iso(t) }
    if let partial { r["partial"] = partial }
    return r
}
func read(_ r: [[String: Any]]) -> [String: Any] { ["responses": r] }
let sent = 1_800_000_000.0
let q = resp("human", "Reply with the single word: lodestar", at: sent + 0.2)

check(GrokThread.reply(conversation: read([q, resp("assistant", "lodestar", at: sent + 3, partial: false)]), sentAt: sent) == "lodestar",
      "a finished assistant response is the answer")
check(GrokThread.reply(conversation: read([q, resp("ASSISTANT", "lodestar")]), sentAt: sent) == "lodestar",
      "the sender's case does not matter, and a response with no time or flag still answers")
check(GrokThread.reply(conversation: read([q, resp("assistant", "lode", at: sent + 2, partial: true)]), sentAt: sent) == nil,
      "a partial response is still writing")
check(GrokThread.reply(conversation: read([q]), sentAt: sent) == nil, "the question alone is no answer")
check(GrokThread.reply(conversation: read([resp("assistant", "yesterday", at: sent - 60)]), sentAt: sent) == nil,
      "an answer older than the question is not its answer")
check(GrokThread.reply(conversation: read([resp("assistant", "lodestar", at: sent - 1)]), sentAt: sent) == "lodestar",
      "a second of clock skew is forgiven")
check(GrokThread.reply(conversation: read([q, resp("assistant", "  ", at: sent + 2)]), sentAt: sent) == nil,
      "an empty response is no answer")
check(GrokThread.reply(conversation: ["casberi": "node401"], sentAt: sent) == nil, "a failed read is no answer")
check(GrokThread.reply(conversation: [:], sentAt: sent) == nil, "an empty read is no answer")

print(failures == 0 ? "grok-thread-selftest: all checks ✓" : "grok-thread-selftest: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

swiftc -O -o "$TMP/run" "$THREAD" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ grok-thread-selftest: compile failed"; exit 1; }
"$TMP/run"
