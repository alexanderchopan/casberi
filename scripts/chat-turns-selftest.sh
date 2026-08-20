#!/bin/zsh
# Casberi chat-turns self-test — reading a stored chat transcript back as the
# conversation it was (2026-08-20):
#
#   Casberi/Casberi/Model/ChatTurns.swift  — compiled WHOLE and unmodified
#       (Foundation-only by design, which is why it is a separate type from
#       the importers that write the transcript and the views that draw it)
#
# WHY A HARNESS. Both features this parse exists for are invisible when it is
# wrong, and wrong in the most convincing possible way — a plausible
# conversation that nobody had:
#
#   • a loose speaker rule shatters ONE answer into a dozen turns, because a
#     message's own text is full of lines that look like prefixes ("Note:",
#     "Error:", "Step 3:", "TODO:"). The sheet then draws an argument between
#     speakers who do not exist, and it renders perfectly;
#   • the same failure fed to the keyed agent as `history` sends somebody
#     else's fabricated turns to a provider as though the person had said them;
#   • a transcript this app did NOT write (a vault note's body, an article's
#     lede, a keyed digest — `enrichedText` carries all of these) must parse to
#     nothing, or every one of those rows starts rendering as a chat;
#   • a CLAMPED transcript handed over without saying so invites a model to
#     answer as if it had read the whole conversation.
#
# The importers' own speaker vocabularies are checked against the parser's, so
# a fourth chat import — or a rename inside an existing one — cannot silently
# produce transcripts this can no longer read.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

TURNS="Casberi/Casberi/Model/ChatTurns.swift"
CHATGPT="Casberi/Casberi/Model/ChatGPTImport.swift"
CLAUDE="Casberi/Casberi/Model/ClaudeImport.swift"
GEMINI="Casberi/Casberi/Model/GeminiImport.swift"
for f in "$TURNS" "$CHATGPT" "$CLAUDE" "$GEMINI"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/chat-turns-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- drift guards -----------------------------------------------------------
# THE ONE THAT MATTERS: every speaker an importer WRITES must be a speaker this
# parser READS. These live in different files by necessity — the importers
# build `Thing`s and cannot compile here — so nothing but this ties them
# together, and the failure is silent: a renamed speaker produces transcripts
# that parse to nothing, and every imported chat quietly stops rendering as a
# chat while the import receipt still says it landed.
python3 - "$TURNS" "$CHATGPT" "$CLAUDE" "$GEMINI" <<'PY'
import re, sys
turns, *importers = sys.argv[1:5]

src = open(turns).read()
m = re.search(r'static let speakers: Set<String> = \[(.*?)\]', src, re.S)
if not m:
    sys.exit("✗ ChatTurns.speakers is gone or reshaped — the parse has no vocabulary")
known = set(re.findall(r'"([^"]+)"', m.group(1)))
if not known:
    sys.exit("✗ ChatTurns.speakers is empty — every transcript would parse to nothing")

# What the writers actually emit: `return "X"` inside a speakerName mapping,
# and any literal handed to ChatTranscript.make as a speaker.
written = set()
for path in importers:
    body = open(path).read()
    for block in re.findall(r'func speakerName\(.*?\n    \}', body, re.S):
        written |= set(re.findall(r'return "([^"]+)"', block))
    written |= set(re.findall(r'speaker: "([^"]+)"', body))

missing = sorted(written - known)
if missing:
    sys.exit("✗ an importer writes a speaker the parser cannot read: "
             + ", ".join(missing)
             + "\n  Every chat it lands would stop rendering as a conversation,"
               "\n  silently, while its import receipt still says it worked.")
print(f"  ✓ speaker vocabularies agree ({', '.join(sorted(written))})")

# And the separator the writers use is the one the parser matches on.
joined = open(importers[0]).read()
if '"\\($0.speaker): \\($0.text)"' not in joined:
    sys.exit("✗ ChatTranscript.make no longer joins as 'Speaker: text' — the parser's"
             "\n  ': ' separator would match nothing.")
print("  ✓ the writer still joins as 'Speaker: text'")
PY

# --- the driver -------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}

print("parse — an ordinary two-sided conversation")
let simple = """
You: how do I center a div
ChatGPT: Use flexbox on the parent.
You: and vertically?
ChatGPT: align-items: center does it.
"""
let parsed = ChatTurns.parse(simple)
check("four turns", parsed.count == 4)
check("oldest first", parsed.first?.text == "how do I center a div")
check("the person's side is identified", parsed.first?.isMine == true)
check("the assistant's side is not", parsed[1].isMine == false)
check("the speaker is kept, not normalized", parsed[1].speaker == "ChatGPT")
check("the prefix is stripped from the text",
      parsed[1].text == "Use flexbox on the parent.")

print("…and Claude's transcripts read the same way")
let claude = """
You: what's the difference
Claude: One is a value type.
"""
check("Claude is a known speaker", ChatTurns.parse(claude).count == 2)
check("Claude is not the person", ChatTurns.parse(claude)[1].isMine == false)

print("a message's own lines are NOT turns — the whole reason for a closed set")
// Every one of these is ordinary text inside a single answer. A `^\w+:` rule
// would split this answer into six turns attributed to invented speakers, and
// the sheet would render an argument nobody had.
let tricky = """
You: why does my build fail
ChatGPT: A few things to check.
Note: this only applies on macOS.
Error: unexpected token at line 4
TODO: pin the version
Step 3: run it again
Warning: do not skip this
"""
let trickyTurns = ChatTurns.parse(tricky)
check("still exactly two turns", trickyTurns.count == 2)
check("the answer kept ALL its lines",
      trickyTurns[1].text.contains("Note:")
      && trickyTurns[1].text.contains("Error:")
      && trickyTurns[1].text.contains("Step 3:")
      && trickyTurns[1].text.contains("Warning:"))
check("and kept them as LINES, not re-joined with spaces",
      trickyTurns[1].text.contains("A few things to check.\nNote:"))
// A code block inside an answer is the same case and the one people notice.
let code = """
You: show me
Claude: Like this:
    let x = 1
    print(x)
"""
check("an indented code block survives whole",
      ChatTurns.parse(code)[1].text.contains("    let x = 1\n    print(x)"))

print("the separator is ': ', never a bare colon or a loose case")
// THESE TWO FIXTURES MUST START A LINE, and that is this harness's own first
// mutation finding. The obvious versions — "You: see Claude:3 below" and
// "You: he said you: no" — put the lookalike INSIDE a line whose own prefix
// already matched, so the parser never gets to judge it: loosening the
// separator to a bare colon, and making the match case-insensitive, both left
// the whole suite green. A fixture only tests the rule it names if it fails
// that rule and passes every other one.
let bareColon = """
You: which versions
ChatGPT: Here is the naming.
Claude:3 and up support it.
ChatGPT:4 was the old label.
"""
check("a line opening 'Claude:3' is text, not a turn (no space after the colon)",
      ChatTurns.parse(bareColon).count == 2)
check("…and those lines stayed inside the answer",
      ChatTurns.parse(bareColon)[1].text.contains("Claude:3 and up"))
let lowercased = """
You: what did I say
Claude: Your words were:
you: I'll do it tomorrow
"""
check("a line opening lowercase 'you: ' is text, not a turn",
      ChatTurns.parse(lowercased).count == 2)
check("…and it stayed inside the answer",
      ChatTurns.parse(lowercased)[1].text.contains("you: I'll do it tomorrow"))
check("an unknown speaker is not a turn",
      ChatTurns.parse("You: hi\nGemini: hello").count == 1)

print("a transcript we did not write parses to NOTHING")
// `enrichedText` also carries vault-note bodies, article ledes and keyed
// digests. Any of them rendering as a chat is worse than none of them doing so.
check("prose is not a conversation",
      ChatTurns.parse("A note about the meeting on Tuesday.").isEmpty)
check("an article lede is not a conversation",
      ChatTurns.parse("Reuters — the central bank said today: rates hold.").isEmpty)
check("nil is not a conversation", ChatTurns.parse(nil).isEmpty)
check("empty is not a conversation", ChatTurns.parse("").isEmpty)
// The subtle one: text that happens to contain a valid speaker line LATER is
// still not our transcript, because ours always opens with one (the clamp
// keeps the oldest end).
check("a speaker line partway down does not make it ours",
      ChatTurns.parse("Some preamble.\nYou: hi").isEmpty)

print("the clamp — a cut transcript is detectable and detected")
// `ChatTranscript` clamps at 8,000 characters and `Thing.messageCount` is
// counted BEFORE the clamp, so this comparison is the only thing that can see
// it. Getting this wrong sends a model half a conversation and lets it answer
// as though it had all of it.
check("fewer turns than messages is partial",
      ChatTurns.isPartial(parsed: parsed, messageCount: 9) == true)
check("all turns present is not partial",
      ChatTurns.isPartial(parsed: parsed, messageCount: 4) == false)
// Conservative where it counts: never put a caveat on a complete chat.
check("an unknown count claims nothing",
      ChatTurns.isPartial(parsed: parsed, messageCount: nil) == false)
check("a zero count claims nothing",
      ChatTurns.isPartial(parsed: parsed, messageCount: 0) == false)
// A clamp landing exactly on a prefix must not attribute a name to the
// previous turn.
let cutOnPrefix = "You: first ask\nChatGPT: an answer\nYou:"
check("a prefix with nothing under it is dropped, not landed empty",
      ChatTurns.parse(cutOnPrefix).count == 2)

print("exchanges — pairs, because AgentTurn is a pair on every wire")
let (history, pending) = ChatTurns.exchanges(parsed)
check("two exchanges", history.count == 2)
check("the first pairs ask with answer",
      history[0].question == "how do I center a div"
      && history[0].answer == "Use flexbox on the parent.")
check("nothing is left pending", pending == nil)

print("…and the three shapes that are dropped rather than guessed at")
// 1. An answer whose question the clamp ate has no pair, and is not invented
// one — a fabricated question sent to a provider as the person's own words.
let orphan = ChatTurns.parse("ChatGPT: as I was saying\nYou: go on\nChatGPT: right")
check("an opening answer with no question is dropped",
      ChatTurns.exchanges(orphan).history.count == 1)
check("…and the pair that IS complete survives",
      ChatTurns.exchanges(orphan).history[0].question == "go on")
// 2. Two asks in a row — every one of these products allows it. The LATEST is
// the one the answer replies to.
let doubled = ChatTurns.parse("You: first\nYou: actually, this instead\nClaude: ok")
check("consecutive asks pair the LATEST with the answer",
      ChatTurns.exchanges(doubled).history.count == 1
      && ChatTurns.exchanges(doubled).history[0].question == "actually, this instead")
// 3. A trailing ask is not half a pair — it is the thing to continue with.
let trailing = ChatTurns.parse("You: hi\nClaude: hello\nYou: one more thing")
let (h3, p3) = ChatTurns.exchanges(trailing)
check("a trailing ask is not a pair", h3.count == 1)
check("…it is returned as pending", p3 == "one more thing")

print("continuation instructions — a partial transcript SAYS it is partial")
let whole = ChatTurns.continuationInstructions(source: "ChatGPT", partial: false)
let cut = ChatTurns.continuationInstructions(source: "ChatGPT", partial: true)
check("both name the product", whole.contains("ChatGPT") && cut.contains("ChatGPT"))
check("a complete transcript makes no excuse", !whole.lowercased().contains("missing"))
check("a cut one says so", cut.lowercased().contains("missing"))
check("…and the two really differ (or the flag does nothing)", whole != cut)

print("")
if failures == 0 {
    print("✓ chat-turns self-test: all assertions passed")
} else {
    print("✗ chat-turns self-test: \(failures) assertion(s) failed")
    exit(1)
}
SWIFT

swiftc -O -o "$TMP/run" "$TURNS" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ ChatTurns.swift did not compile"; exit 1; }
"$TMP/run"

# --- mutations (each must be caught) ---------------------------------------
echo
echo "mutations (each must be caught)"

WORK="$TMP/work"
mutate() {
  local name="$1" from="$2" to="$3"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$TURNS" "$WORK/ChatTurns.swift"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/ChatTurns.swift" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]]; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$WORK/mut" "$WORK/ChatTurns.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$WORK/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# 1. THE ONE THIS FILE EXISTS FOR. A bare colon turns "Note:", "Error:" and
# "Step 3:" inside one answer into turns by speakers who do not exist.
mutate "the separator loosens to a bare colon" \
  'let marker = speaker + ": "' \
  'let marker = speaker + ":"'

# 2. Case-insensitive matching — "he said you: no" inside a sentence becomes a
# turn, splitting an answer at a phrase.
mutate "speaker matching becomes case-insensitive" \
  'if line.hasPrefix(marker) {' \
  'if line.lowercased().hasPrefix(marker.lowercased()) {'

# 3. The whole-or-nothing rule. Without it, a vault note whose body happens to
# contain "You: " halfway down renders as a conversation.
mutate "a non-transcript is no longer rejected whole" \
  'speakerPrefix(first) != nil else { return [] }' \
  'speakerPrefix(first) != nil || true else { return [] }'

# 4. Continuation lines re-joined with spaces — a code block inside an answer
# collapses into one line and stops being readable as code.
mutate "an answer's own line breaks are lost" \
  'body.joined(separator: "\n")' \
  'body.joined(separator: " ")'

# 5. The clamp goes unnoticed, and a model answers half a conversation as
# though it had read all of it.
mutate "a cut transcript no longer reports itself as partial" \
  'return parsed.count < messageCount' \
  'return false'

# 6. …and the inverse: a caveat put on a COMPLETE chat, which is the error that
# makes people distrust a feature that is working.
mutate "an unknown message count claims the chat is cut" \
  'guard let messageCount, messageCount > 0 else { return false }' \
  'guard let messageCount, messageCount > 0 else { return true }'

# 7. An orphan answer gets a question invented for it — somebody else's words
# sent to a provider as the person's own.
mutate "an answer with no question is paired anyway" \
  '} else if let asked = question {' \
  '} else if let asked = question ?? Optional("") {'

# 8. A trailing ask swallowed into history rather than offered as the thing to
# continue with.
mutate "the pending ask is dropped" \
  'return (history, question)' \
  'return (history, nil)'

# 9. The partial warning stops differing, so the flag is decoration.
mutate "the partial warning is no longer added" \
  'if partial {' \
  'if false {'

# 10. An unknown speaker promoted to the person — an answer misattributed to
# you, in a room of your own conversations.
mutate "the person's side stops being one exact name" \
  'var isMine: Bool { speaker == ChatTurns.mine }' \
  'var isMine: Bool { speaker != "ChatGPT" }'

echo
echo "✓ chat-turns self-test: assertions and mutations all pass"
