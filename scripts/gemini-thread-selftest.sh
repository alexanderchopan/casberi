#!/bin/zsh
# Casberi Gemini thread self-test (prd §1627) — which of the answers on
# gemini.google.com's page is the answer to what Casberi typed, compiled WHOLE
# and unmodified:
#
#   Casberi/Casberi/Model/GeminiThread.swift
#
# Gemini's traffic is Google's batchexecute RPC, so the answer is read where
# the page draws it: the newest model-response, once the page holds one more
# than before the question (measured 2026-10-30: "wayfinder"). Plus the drift
# guards: only the redacted question is sent, GeminiWeb never logs, and the
# sheet never clears Google's cookies (a Google sign-in can cost a backup code).
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

THREAD="Casberi/Casberi/Model/GeminiThread.swift"
WEB="Casberi/Casberi/Model/GeminiWeb.swift"
ANSWER="Casberi/Casberi/Model/AgentAnswer.swift"
SESSION="Casberi/Casberi/Model/WebSession.swift"
for f in "$THREAD" "$WEB" "$ANSWER" "$SESSION"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done
if grep -vE '^[[:space:]]*(//|///)' "$WEB" | grep -qE 'NSLog|print\('; then
  echo "✗ GeminiWeb logs — the person's chats must never reach a log"; exit 1
fi
body="$(awk '/static func geminiAnswer/,/^    }/' "$ANSWER")"
[[ -n "$body" ]] || { echo "✗ geminiAnswer not found in AgentAnswer.swift"; exit 1; }
print -r -- "$body" | grep -qF 'GeminiWeb.ask(SecretScan.redacted(query), firstQuestion: first)' \
  || { echo "✗ geminiAnswer no longer sends only the redacted question"; exit 1; }
if print -r -- "$body" | grep -qE 'candidates|numberedCandidates|\.answer\b'; then
  echo "✗ geminiAnswer sends saved things or earlier answers into Gemini"; exit 1
fi
grep -qF 'var clearsFirst: Bool { self != .gemini }' "$SESSION" \
  || { echo "✗ Gemini's sheet may clear Google's cookies again"; exit 1; }
echo "gemini-thread-selftest: drift guards ✓"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}
typealias S = GeminiThread.Snapshot
func snap(_ models: [String], generating: Bool = false, path: String = "/app/1003e6") -> S {
    S(models: models, generating: generating, path: path)
}

check(GeminiThread.chatID(path: "/app/1003e6459d866c1a") == "1003e6459d866c1a", "/app/<id> names the chat")
check(GeminiThread.chatID(path: "/app") == nil, "the new-chat page names none")
check(GeminiThread.chatID(path: "/u/1/app/abc") == "abc", "a second account's chat is named too")

check(GeminiThread.reply(before: 0, now: snap(["wayfinder"])) == "wayfinder", "a first answer in a new chat is the reply")
check(GeminiThread.reply(before: 2, now: snap(["a", "b", "wayfinder"])) == "wayfinder", "a new answer in a continued chat is the reply")
check(GeminiThread.reply(before: 2, now: snap(["a", "b"])) == nil, "no new answer is no reply, however long the chat")
check(GeminiThread.reply(before: 0, now: snap([])) == nil, "an empty page is no reply")
check(GeminiThread.reply(before: 0, now: snap(["  "])) == nil, "an answer with no words yet is no reply")
check(GeminiThread.reply(before: 0, now: snap(["  way  "])) == "way", "the words are trimmed")

let json = #"{"models":["harbinger"],"generating":true,"path":"/app/x"}"#
let decoded = try? JSONDecoder().decode(S.self, from: Data(json.utf8))
check(decoded == snap(["harbinger"], generating: true, path: "/app/x"), "the page script's snapshot decodes")

print(failures == 0 ? "gemini-thread-selftest: all checks ✓" : "gemini-thread-selftest: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

swiftc -O -o "$TMP/run" "$THREAD" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ gemini-thread-selftest: compile failed"; exit 1; }
"$TMP/run"
