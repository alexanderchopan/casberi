#!/bin/zsh
# Casberi Claude thread self-test (prd §1624) — which message in claude.ai's
# own conversation JSON is the answer to what Casberi typed, compiled WHOLE
# and unmodified:
#
#   Casberi/Casberi/Model/ClaudeThread.swift
#
# The answer is the LAST message, once it is the assistant's, stopped and
# newer than the question, and its words are its text blocks, never its
# thinking (measured 2026-10-30: thinking, then "meridian", `end_turn`). Plus
# the drift guards: the Claude fork sends only the redacted question, and
# ClaudeWeb never logs.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

THREAD="Casberi/Casberi/Model/ClaudeThread.swift"
WEB="Casberi/Casberi/Model/ClaudeWeb.swift"
ANSWER="Casberi/Casberi/Model/AgentAnswer.swift"
for f in "$THREAD" "$WEB" "$ANSWER"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done
if grep -vE '^[[:space:]]*(//|///)' "$WEB" | grep -qE 'NSLog|print\('; then
  echo "✗ ClaudeWeb logs — the person's chats must never reach a log"; exit 1
fi
grep -qF 'if provider == .anthropic, TokenVault.get(provider.vaultKey) == nil, WebSession.signedIn(.claude) {' "$ANSWER" \
  || { echo "✗ the Claude session fork is gone or no longer yields to a stored key"; exit 1; }
grep -qF 'return await chatPageAnswer(await ClaudeWeb.shared, agent: "Claude", query: query, history: history)' "$ANSWER" \
  || { echo "✗ the Claude fork no longer goes through chatPageAnswer"; exit 1; }
echo "claude-thread-selftest: drift guards ✓"

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
func msg(_ i: Int, _ sender: String, _ t: Double, stop: String? = nil, blocks: [[String: Any]]? = nil,
         text: String = "") -> [String: Any] {
    var m: [String: Any] = ["index": i, "sender": sender, "created_at": iso(t), "text": text]
    if let stop { m["stop_reason"] = stop }
    if let blocks { m["content"] = blocks }
    return m
}
func chat(_ messages: [[String: Any]]) -> [String: Any] { ["chat_messages": messages] }
let sent = 1_800_000_000.0
let q = msg(0, "human", sent + 0.3, blocks: [["type": "text", "text": "Reply with the single word: meridian"]])

// ── The measured answer ──────────────────────────────────────────────────
let answered = chat([q, msg(1, "assistant", sent + 1.4, stop: "end_turn",
                            blocks: [["type": "thinking", "thinking": "one word"], ["type": "text", "text": "meridian"]])])
check(ClaudeThread.reply(conversation: answered, sentAt: sent) == "meridian", "a stopped assistant message's text is the answer")
check(!(ClaudeThread.reply(conversation: answered, sentAt: sent) ?? "").contains("one word"), "its thinking is never the answer")
let two = chat([q, msg(1, "assistant", sent + 2, stop: "end_turn",
                       blocks: [["type": "text", "text": "One."], ["type": "tool_use", "name": "x"], ["type": "text", "text": "Two."]])])
check(ClaudeThread.reply(conversation: two, sentAt: sent) == "One.\n\nTwo.", "text blocks join; a tool block is skipped")
let plain = chat([q, msg(1, "assistant", sent + 2, stop: "end_turn", text: "meridian")])
check(ClaudeThread.reply(conversation: plain, sentAt: sent) == "meridian", "a message with no blocks answers with its text")

// ── Not yet ──────────────────────────────────────────────────────────────
check(ClaudeThread.reply(conversation: chat([q]), sentAt: sent) == nil, "the question alone is no answer")
let writing = chat([q, msg(1, "assistant", sent + 1, blocks: [["type": "text", "text": "meri"]])])
check(ClaudeThread.reply(conversation: writing, sentAt: sent) == nil, "an answer with no stop reason is still writing")
let empty = chat([q, msg(1, "assistant", sent + 1, stop: "", blocks: [["type": "text", "text": "meri"]])])
check(ClaudeThread.reply(conversation: empty, sentAt: sent) == nil, "an empty stop reason is no stop")
let old = chat([msg(0, "assistant", sent - 60, stop: "end_turn", blocks: [["type": "text", "text": "yesterday"]])])
check(ClaudeThread.reply(conversation: old, sentAt: sent) == nil, "an answer older than the question is not its answer")
let skew = chat([msg(0, "assistant", sent - 1, stop: "end_turn", blocks: [["type": "text", "text": "meridian"]])])
check(ClaudeThread.reply(conversation: skew, sentAt: sent) == "meridian", "a second of clock skew is forgiven")
let thinkingOnly = chat([q, msg(1, "assistant", sent + 1, stop: "end_turn", blocks: [["type": "thinking", "thinking": "hm"]])])
check(ClaudeThread.reply(conversation: thinkingOnly, sentAt: sent) == nil, "thinking with no text is no answer")
let shuffled = chat([msg(1, "assistant", sent + 2, stop: "end_turn", blocks: [["type": "text", "text": "meridian"]]), q])
check(ClaudeThread.reply(conversation: shuffled, sentAt: sent) == "meridian", "the last message is the highest index, not the last listed")
let followUp = chat([msg(0, "human", sent - 30), msg(1, "assistant", sent - 29, stop: "end_turn", blocks: [["type": "text", "text": "first"]]), q])
check(ClaudeThread.reply(conversation: followUp, sentAt: sent) == nil, "an earlier answer is not a follow-up's answer")
check(ClaudeThread.reply(conversation: [:], sentAt: sent) == nil, "an empty read is no answer")

// ── Dates ────────────────────────────────────────────────────────────────
check(ClaudeThread.date("2026-10-30T19:35:49.228276Z") != nil, "a fractional timestamp reads")
check(ClaudeThread.date("2026-10-30T19:35:49Z") != nil, "a whole-second timestamp reads")

print(failures == 0 ? "claude-thread-selftest: all checks ✓" : "claude-thread-selftest: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

swiftc -O -o "$TMP/run" "$THREAD" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ claude-thread-selftest: compile failed"; exit 1; }
"$TMP/run"
