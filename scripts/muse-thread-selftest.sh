#!/bin/zsh
# Casberi Muse thread self-test (prd §1619) — which of the messages on
# muse.ai's page are Muse's reply to what Casberi typed, compiled WHOLE and
# unmodified:
#
#   Casberi/Casberi/Model/MuseThread.swift
#
# Muse keeps one chat and answers in it like a person texting: several
# messages, sometimes news of its own first (measured 2026-10-30). So the
# reply is every assistant message after the one sent, and only once the page
# has gone quiet. Plus the drift guards on the page driver: it sends only the
# question, never logs, and never reads a cookie value.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

THREAD="Casberi/Casberi/Model/MuseThread.swift"
WEB="Casberi/Casberi/Model/MuseWeb.swift"
ANSWER="Casberi/Casberi/Model/AgentAnswer.swift"
for f in "$THREAD" "$WEB" "$ANSWER"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

code() { grep -vE '^[[:space:]]*(//|///)' "$1"; }
# The page's words never reach a log: they are the person's chat.
if code "$WEB" | grep -qE 'NSLog|print\('; then
  echo "✗ MuseWeb logs — the person's Muse chat must never reach a log"; exit 1
fi
# Casberi reads no cookie of Muse's; WebKit attaches them.
if code "$WEB" | grep -qE '\.value\b|cookie\.value'; then
  echo "✗ MuseWeb reads a cookie VALUE"; exit 1
fi
# Only the question goes: the Muse fork hands MuseWeb the redacted query and
# nothing built from candidates or history.
body="$(awk '/static func museAnswer/,/^    }/' "$ANSWER")"
[[ -n "$body" ]] || { echo "✗ museAnswer not found in AgentAnswer.swift"; exit 1; }
print -r -- "$body" | grep -qF 'MuseWeb.shared.ask(SecretScan.redacted(query))' \
  || { echo "✗ museAnswer no longer sends only the redacted question"; exit 1; }
if print -r -- "$body" | grep -qE 'candidates|history|numberedCandidates'; then
  echo "✗ museAnswer sends saved things or earlier turns into Muse's chat"; exit 1
fi
# The fork stands before the key is asked for, and only when no key is kept.
grep -qF 'if provider == .meta, TokenVault.get(provider.vaultKey) == nil, WebSession.signedIn(.muse) {' "$ANSWER" \
  || { echo "✗ the Muse session fork is gone or no longer yields to a pasted key"; exit 1; }
echo "muse-thread-selftest: drift guards ✓"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}
typealias M = MuseThread.Message
func m(_ id: String, _ role: String, _ text: String) -> M { M(id: id, role: role, text: text) }

let old = [m("u1", "user", "You:\n\nhow come you never posted"),
           m("a1", "assistant", "I did post the reel.")]
let before = Set(old.map(\.id))
let sent = "Reply with the single word: ready"

// ── Words ────────────────────────────────────────────────────────────────
check(MuseThread.words(m("x", "user", "You:\n\nhello")) == "hello", "the page's \"You:\" heading comes off")
check(MuseThread.words(m("x", "user", "  hello ")) == "hello", "a message with no heading keeps its words")

// ── Before Muse speaks ───────────────────────────────────────────────────
check(MuseThread.reply(sent: sent, before: before, now: old) == nil, "nothing new on the page is no reply")
let justSent = old + [m("u2", "user", "You:\n\n" + sent)]
check(MuseThread.sentIndex(sent: sent, before: before, now: justSent) == 2, "the sent message is found by its words")
check(MuseThread.reply(sent: sent, before: before, now: justSent) == nil, "the sent message alone is no reply")

// ── The measured reply: news first, then the answer ──────────────────────
let answered = justSent + [m("a2", "assistant", "Quick update I owe you first: posted.\n\nready")]
check(MuseThread.reply(sent: sent, before: before, now: answered) == "Quick update I owe you first: posted.\n\nready",
      "the reply is the assistant message after the one sent")
let twoBubbles = answered + [m("a3", "assistant", "Anything else?")]
check(MuseThread.reply(sent: sent, before: before, now: twoBubbles)
        == "Quick update I owe you first: posted.\n\nready\n\nAnything else?",
      "several assistant messages are one reply, in order")

// ── Old assistant messages are never the reply ───────────────────────────
check(MuseThread.reply(sent: sent, before: before, now: old + [m("u2", "user", sent)]) == nil,
      "an assistant message from before the question is not its answer")
let proactive = old + [m("a9", "assistant", "Your post went live."), m("u2", "user", "You:\n\n" + sent),
                       m("a2", "assistant", "ready")]
check(MuseThread.reply(sent: sent, before: before, now: proactive) == "ready",
      "a message Muse wrote before the question landed is not part of the reply")

// ── The same words sent twice: the newest one counts ─────────────────────
let twice = old + [m("u2", "user", sent), m("a2", "assistant", "ready"), m("u3", "user", sent)]
check(MuseThread.reply(sent: sent, before: before, now: twice) == nil,
      "the newest of two identical questions is the one waiting")

// ── A tidied message still counts as sent ───────────────────────────────
let tidied = old + [m("u2", "user", "You:\n\nReply with the single word:  ready"), m("a2", "assistant", "ready")]
check(MuseThread.reply(sent: sent, before: before, now: tidied) == "ready",
      "a new message the page reworded still anchors the reply")

// ── Empty bubbles say nothing ────────────────────────────────────────────
check(MuseThread.reply(sent: sent, before: before, now: justSent + [m("a2", "assistant", "  ")]) == nil,
      "an empty assistant bubble is no reply yet")

// ── Settling ─────────────────────────────────────────────────────────────
var settle = MuseThread.Settle(quietPolls: 2)
check(!settle.see(nil), "no reply never settles")
check(!settle.see("Hel"), "a first read does not settle")
check(!settle.see("Hello"), "a growing reply does not settle")
check(!settle.see("Hello"), "one quiet read is not enough")
check(settle.see("Hello"), "two quiet reads settle it")
check(settle.last == "Hello", "the settled reply is the last read")
check(!settle.see("Hello, again"), "a reply that grows again is open again")
check(!settle.see(nil) && settle.last == nil, "a reply that vanished starts over")

print(failures == 0 ? "muse-thread-selftest: all checks ✓" : "muse-thread-selftest: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

swiftc -O -o "$TMP/run" "$THREAD" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ muse-thread-selftest: compile failed"; exit 1; }
"$TMP/run"
