#!/bin/zsh
# Casberi ChatGPT thread self-test (prd §1623) — which message in ChatGPT's
# own conversation JSON is the answer to what Casberi typed, compiled WHOLE
# and unmodified:
#
#   Casberi/Casberi/Model/ChatGPTThread.swift
#
# The answer is the CURRENT node, once it is the assistant's, finished, and
# newer than the question (measured 2026-10-30: "harbor",
# `finished_successfully`). Plus the drift guards on the page driver: only the
# redacted question is sent, nothing is logged, the session's bearer never
# leaves the page.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

THREAD="Casberi/Casberi/Model/ChatGPTThread.swift"
WEB="Casberi/Casberi/Model/ChatGPTWeb.swift"
ANSWER="Casberi/Casberi/Model/AgentAnswer.swift"
for f in "$THREAD" "$WEB" "$ANSWER"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

code() { grep -vE '^[[:space:]]*(//|///)' "$1"; }
if code "$WEB" | grep -qE 'NSLog|print\('; then
  echo "✗ ChatGPTWeb logs — the person's chats must never reach a log"; exit 1
fi
# The bearer is fetched and spent inside the page; Swift only ever gets the
# conversation back. A Swift line naming the token would mean it crossed.
if code "$WEB" | grep -vF 'j.accessToken' | grep -qiE 'accessToken'; then
  echo "✗ ChatGPTWeb's Swift side touches the session's access token"; exit 1
fi
body="$(awk '/static func chatGPTAnswer/,/^    }/' "$ANSWER")"
[[ -n "$body" ]] || { echo "✗ chatGPTAnswer not found in AgentAnswer.swift"; exit 1; }
print -r -- "$body" | grep -qF 'ChatGPTWeb.shared.ask(SecretScan.redacted(query), firstQuestion: first)' \
  || { echo "✗ chatGPTAnswer no longer sends only the redacted question"; exit 1; }
if print -r -- "$body" | grep -qE 'candidates|numberedCandidates|\.answer\b'; then
  echo "✗ chatGPTAnswer sends saved things or earlier answers into ChatGPT"; exit 1
fi
grep -qF 'if provider == .openai, TokenVault.get(provider.vaultKey) == nil, WebSession.signedIn(.chatgpt) {' "$ANSWER" \
  || { echo "✗ the ChatGPT session fork is gone or no longer yields to a stored key"; exit 1; }
echo "chatgpt-thread-selftest: drift guards ✓"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}

func node(_ id: String, _ role: String, _ status: String, _ time: Double, _ parts: [Any],
          type: String = "text") -> (String, [String: Any]) {
    (id, ["id": id, "message": ["author": ["role": role], "status": status, "create_time": time,
                                "content": ["content_type": type, "parts": parts]]])
}
func convo(current: String, _ nodes: [(String, [String: Any])]) -> [String: Any] {
    ["current_node": current, "mapping": Dictionary(uniqueKeysWithValues: nodes)]
}
let sent = 1_800_000_000.0
let question = node("q", "user", "finished_successfully", sent + 0.4, ["Reply with the single word: harbor"])

// ── Ids in addresses ─────────────────────────────────────────────────────
check(ChatGPTThread.conversationID(fromPath: "/c/6ae4e662-0d1c") == "6ae4e662-0d1c", "/c/<id> names the chat")
check(ChatGPTThread.conversationID(fromPath: "/g/g-abc/c/xyz") == "xyz", "a GPT's chat is named too")
check(ChatGPTThread.conversationID(fromPath: "/") == nil, "the home page names no chat")
check(ChatGPTThread.conversationID(fromPath: "/c/") == nil, "an empty id is no chat")

// ── The measured answer ──────────────────────────────────────────────────
let answered = convo(current: "a", [question, node("a", "assistant", "finished_successfully", sent + 3, ["harbor"])])
check(ChatGPTThread.reply(conversation: answered, sentAt: sent) == .done("harbor"), "a finished assistant node is the answer")
let split = convo(current: "a", [question, node("a", "assistant", "finished_successfully", sent + 3, ["har", "bor"],
                                                type: "multimodal_text")])
check(ChatGPTThread.reply(conversation: split, sentAt: sent) == .done("harbor"), "its string parts join")
let withPicture = convo(current: "a", [question, node("a", "assistant", "finished_successfully", sent + 3,
                                                      [["asset_pointer": "file"], "a picture"])])
check(ChatGPTThread.reply(conversation: withPicture, sentAt: sent) == .done("a picture"), "a part that is not words is skipped")

// ── Not yet ──────────────────────────────────────────────────────────────
check(ChatGPTThread.reply(conversation: convo(current: "q", [question]), sentAt: sent) == .pending,
      "the question as the current node is no answer")
let writing = convo(current: "a", [question, node("a", "assistant", "in_progress", sent + 3, ["harb"])])
check(ChatGPTThread.reply(conversation: writing, sentAt: sent) == .pending, "an answer still writing is not done")
let old = convo(current: "a", [node("a", "assistant", "finished_successfully", sent - 60, ["yesterday's answer"])])
check(ChatGPTThread.reply(conversation: old, sentAt: sent) == .pending, "an answer older than the question is not its answer")
let skew = convo(current: "a", [node("a", "assistant", "finished_successfully", sent - 1, ["harbor"])])
check(ChatGPTThread.reply(conversation: skew, sentAt: sent) == .done("harbor"), "a second of clock skew is forgiven")
let tool = convo(current: "t", [question, node("t", "tool", "finished_successfully", sent + 2, ["search results"])])
check(ChatGPTThread.reply(conversation: tool, sentAt: sent) == .pending, "a tool's node is not the answer")
let blank = convo(current: "a", [question, node("a", "assistant", "finished_successfully", sent + 3, ["  "])])
check(ChatGPTThread.reply(conversation: blank, sentAt: sent) == .pending, "an empty finished node is not an answer")
check(ChatGPTThread.reply(conversation: [:], sentAt: sent) == .pending, "an empty read is not an answer")
check(ChatGPTThread.reply(conversation: convo(current: "missing", [question]), sentAt: sent) == .pending,
      "a current node missing from the mapping is not an answer")

// ── Which chat ───────────────────────────────────────────────────────────
check(ChatGPTThread.chatKey(firstQuestion: " What is X? ") == ChatGPTThread.chatKey(firstQuestion: "what is x?"),
      "one conversation's first question keys one chat")
check(ChatGPTThread.chatKey(firstQuestion: "a") != ChatGPTThread.chatKey(firstQuestion: "b"),
      "another conversation keys another chat")

print(failures == 0 ? "chatgpt-thread-selftest: all checks ✓" : "chatgpt-thread-selftest: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

swiftc -O -o "$TMP/run" "$THREAD" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ chatgpt-thread-selftest: compile failed"; exit 1; }
"$TMP/run"
