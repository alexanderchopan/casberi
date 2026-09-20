#!/bin/zsh
# Casberi agent-landing self-test — the shipped judgement behind a keyed
# conversation becoming a thing (prd §839, §840):
#
#   Casberi/Casberi/Model/AgentConversationLanding.swift
#   Casberi/Casberi/Model/AgentRoomScope.swift
#
# WHY A HARNESS. Every failure here is a SILENT WRONG ANSWER that renders
# perfectly, and no build, screen sweep or probe can see one of them:
#
#   · a source spelled differently from `AgentSheet.assistant(for:)`'s label
#     makes `turns` return nothing, and the sheet draws the whole conversation
#     as ONE turn under your own name — the §363 failure, from a new door
#   · a transcript that does not use the importers' `"<Speaker>: <text>"`
#     convention lands a row the sheet cannot read back at all
#   · `messageCount` counted after the clamp reports an 84-turn chat as 40
#   · a conversation keyed on something other than one stable id lands one row
#     PER TURN, and a long conversation buries its own room
#   · a provider change that does not reset the history sends one agent's
#     conversation to a different agent (§840) — a leak before it is a bug
#
# The landing itself touches `Thing` and SwiftData, so it cannot be compiled by
# a `swiftc` harness. What CAN be proved without one is every rule that is a
# fact about text — and the wiring that the shipped code actually applies them.
# The transcript grammar is checked by compiling `AgentSheet` (Foundation-only,
# shipped, unmodified) against the exact strings this landing writes, so the
# two halves are proved to agree rather than assumed to.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

LANDING="Casberi/Casberi/Model/AgentConversationLanding.swift"
SCOPE="Casberi/Casberi/Model/AgentRoomScope.swift"
SHEET="Casberi/Casberi/Model/AgentSheet.swift"
ANSWER="Casberi/Casberi/Model/AgentAnswer.swift"
SHELL_="Casberi/Casberi/Shell/RootShell.swift"
CHROME="Casberi/Casberi/Shell/ShellChrome.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
SRC="Casberi/Casberi/Model/AgentSheetSource.swift"
GPT="Casberi/Casberi/Model/ChatGPTImport.swift"
for f in "$LANDING" "$SCOPE" "$SHEET" "$ANSWER" "$SHELL_" "$CHROME" "$FEED" "$SRC" "$GPT"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
guard() {  # name, pattern, file
  if grep -qE -- "$2" "$3"; then echo "  ✓ $1"; else echo "  ✗ $1"; fail=1; fi
}

echo "Drift guards"

# --- the wiring -------------------------------------------------------------
# A perfect landing that nothing calls lands nothing. This is the §377 class:
# registering and handling in different places, drifting apart in silence.
guard "the ask path lands the conversation" \
  'AgentConversationLanding\.record\(turns: keyedHistory' "$SHELL_"
guard "the landing is keyed on one id, not minted per turn" \
  'keyedConversationID \?\? UUID\(\)' "$SHELL_"
guard "lowering the composer ends the conversation" \
  'keyedConversationID = nil' "$SHELL_"
guard "the room's ask is served by the shell" \
  'onChange\(of: chrome\.roomAsk\)' "$SHELL_"
guard "the room's ask names its own provider" \
  'keyedAnswerDocument\(ask\.question,' "$SHELL_"
# §841's CORRUPTION bug. The provider reset must sit in the ONE funnel and
# ABOVE the history read — §840 had it on the room's door only, so the
# composer's door handed one agent's turns to the next and upserted the reply
# onto the first agent's row, whose `source` never changes: a row in Bankr's
# room full of "Claude:" lines, which the parser renders under YOUR name.
guard "the provider reset is inside the ask funnel, not on one door" \
  'if keyedProvider != provider \{' "$SHELL_"
python3 - "$SHELL_" <<'ORDER' || fail=1
import sys
src = open(sys.argv[1]).read()
i = src.find("private func keyedAnswerDocument")
if i < 0:
    print("  \u2717 keyedAnswerDocument is gone — this guard is blind"); sys.exit(1)
body = src[i:i + 6000]
reset = body.find("keyedProvider = provider")
hist = body.find("history: keyedHistory")
if reset < 0 or hist < 0:
    print("  \u2717 could not find the reset and the history read together"); sys.exit(1)
if reset > hist:
    print("  \u2717 the provider reset runs AFTER the history is handed over — "
          "the next agent is sent the previous agent's conversation (\u00a7841)")
    sys.exit(1)
print("  \u2713 the provider reset runs BEFORE the history is handed over")
ORDER
# §841's stale-evidence bug: a room ask never went through `answer()`, so
# `lastAnswerHits` belongs to a different question entirely.
guard "a room ask retrieves for its own question" \
  'freshEvidence: true' "$SHELL_"
guard "fresh evidence bypasses the last answer's hits" \
  'freshEvidence && !lastAnswerHits\.isEmpty' "$SHELL_"
guard "the composer keeps the last answer's evidence" \
  'freshEvidence: false' "$SHELL_"
guard "the pending room is cleared however the ask ends" \
  'defer \{ chrome\.roomAskSource = nil \}' "$SHELL_"
# §841: a refused ask is said out loud and the question handed back.
guard "a refusal is worded" \
  'chrome\.flash\(why\.line\)' "$SHELL_"
guard "a refusal names the room that asked" \
  'chrome\.roomAskFailed = ask\.source' "$SHELL_"
guard "a room can end a conversation" \
  'onChange\(of: chrome\.roomNewConversation\)' "$SHELL_"
# §841: the scope dies with the room, which §840 documented and never wrote.
guard "the agent scope is cleared on a source change" \
  'chrome\.agentScope = \.all' "Casberi/Casberi/Shell/MainSurface.swift"
# §841: without these the room is replaced wholesale when its last
# conversation is deleted, taking the Chat tile — the only way to start
# another — with it.
guard "an agent room keeps its tiles when empty" \
  '\|\| roomAgent != nil' "$FEED"
guard "an agent room is not replaced by the generic empty state" \
  'roomAgent == nil' "$FEED"
# §841: Accounts is presented, not pushed, so onAppear never fires again.
guard "a key added without leaving the room lights the tile" \
  'onChange\(of: bridges\.bridges\.count\)' "$FEED"
guard "the room draws the agent sections" \
  'agentRoomSections\(visible' "$FEED"
# The chat surface is TWO pieces in two of the room's slots (§841): the thread
# where the cover sits, the entry below the tiles. One block replacing the list
# is what put the tiles at the top of the screen on Chat and at 316pt on All.
guard "the thread fills the room's lead slot" \
  'AgentChatThread\(source: source\)' "$FEED"
guard "the composer row is drawn below the tiles" \
  'AgentChatEntry\(source: source, provider: roomAgent\)' "$FEED"
python3 - "$FEED" <<'SLOTS' || fail=1
import sys
src = open(sys.argv[1]).read()
i = src.find("private func agentRoomSections")
if i < 0:
    print("  \u2717 agentRoomSections is gone — this guard is blind"); sys.exit(1)
body = src[i:i + 4000]
thread = body.find("AgentChatThread(")
tiles  = body.find("agentTiles")
entry  = body.find("AgentChatEntry(")
if min(thread, tiles, entry) < 0:
    print("  \u2717 could not find all three slots"); sys.exit(1)
if not (thread < tiles < entry):
    print("  \u2717 the slots are out of order — the tiles must sit BETWEEN the "
          "thread and the entry, or they move when you switch tile (\u00a7841)")
    sys.exit(1)
print("  \u2713 thread, then tiles, then entry — the tiles never move")
SLOTS
# The §83 half: a Chat tile over a seat with no key cannot answer.
guard "the tiles stand only where a key is present" \
  'guard roomAgent != nil else \{ return nil \}' "$FEED"
guard "the agent is resolved outside the body (build 525)" \
  'private func resolveRoomAgent' "$FEED"

# --- the landed shape -------------------------------------------------------
guard "the transcript goes through the importers' own serializer" \
  'ChatTranscript\.make' "$LANDING"
guard "the count is the transcript's, taken before the clamp" \
  'thing\.messageCount = transcript\.messages' "$LANDING"
guard "a stale embedding is dropped with the words it was made from" \
  'thing\.embedding = nil' "$LANDING"
guard "the source is the provider's own agent name" \
  'provider\.agent' "$LANDING"
guard "the row is upserted, never duplicated" \
  'sourceRef == ref' "$LANDING"
# The fence that keeps an IMPORTED conversation out of the live surface. A
# Claude export and a keyed Claude chat share a source on purpose (§839), so
# the ref is the only thing that tells them apart — and the writer and the
# reader must use ONE spelling of it or the fence silently matches nothing.
guard "the landing declares the ref prefix once" \
  'static let refPrefix = "agentchat:"' "$LANDING"
guard "the ref is built from that constant, not a second literal" \
  'let ref = refPrefix \+ conversationID\.uuidString' "$LANDING"
CHAT="Casberi/Casberi/Screens/AgentChatView.swift"
[[ -f "$CHAT" ]] || { echo "  ✗ $CHAT not found"; fail=1; }
guard "the chat surface fences its query on that same constant" \
  'AgentConversationLanding\.refPrefix' "$CHAT"
python3 - "$CHAT" <<'FENCE' || fail=1
import sys
code = "\n".join(l for l in open(sys.argv[1]).read().splitlines()
                 if not l.strip().startswith("//"))
if '"agentchat:"' in code:
    print("  ✗ the chat surface spells the prefix itself — two spellings of "
          "one fence, and one of them will drift")
    sys.exit(1)
print("  ✓ the chat surface never spells the prefix itself")
FENCE

# --- the rule that cannot be grepped: the two halves must AGREE -------------
# `AgentSheet` is Foundation-only and shipped; compile it WHOLE and unmodified
# and feed it exactly the strings the landing writes. This is the assertion the
# guards above cannot make — that a conversation this app lands is one this app
# can read back.
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    print(ok ? "  ✓ \(what)" : "  ✗ \(what)")
    if !ok { failures += 1 }
}

// The landing's own grammar, transcribed from AgentConversationLanding:
// "<reader>: <q>" and "<assistant>: <a>", oldest first, joined by "\n".
func transcript(_ pairs: [(String, String)], assistant: String) -> String {
    var lines: [String] = []
    for (q, a) in pairs {
        if !q.isEmpty { lines.append("\(AgentSheet.readerLabel): \(q)") }
        if !a.isEmpty { lines.append("\(assistant): \(a)") }
    }
    return lines.joined(separator: "\n")
}

// EVERY keyed seat round-trips. A seat whose source and speaker label differ
// by one character parses to nothing, and the sheet draws one giant turn.
for source in ["Bankr", "Venice", "OpenRouter", "Grok", "Claude", "ChatGPT", "Gemini"] {
    guard let assistant = AgentSheet.assistant(for: source) else {
        check(false, "\(source) has an assistant label"); continue
    }
    let body = transcript([("what is my exposure", "You hold 4.2 ETH."),
                           ("and gas", "About 0.02 gwei.")], assistant: assistant)
    let turns = AgentSheet.turns(body, assistant: assistant)
    check(turns.count == 4, "\(source): four turns round-trip")
    if turns.count == 4 {
        check(turns[0].text == "what is my exposure", "\(source): the question survives")
        check(turns[1].text == "You hold 4.2 ETH.", "\(source): the answer survives")
    }
}

// A multi-paragraph answer is ONE turn — the `ChatBubbles` defect the sheet's
// own parser exists to avoid, reached here through the landing's grammar.
if let a = AgentSheet.assistant(for: "Bankr") {
    let body = transcript([("explain", "First line.\nSecond line.\nThird.")], assistant: a)
    let turns = AgentSheet.turns(body, assistant: a)
    check(turns.count == 2, "a multi-line answer stays one turn")
    check(turns.last?.text == "First line.\nSecond line.\nThird.",
          "its own newlines are kept, not split on")
}

// The landing's own source rule must equal the label's. This is the single
// fact both files depend on and neither can check alone.
for p in AgentProvider.allCases {
    let source = p.agent
    let assistant = AgentSheet.assistant(for: source)
    check(assistant == source,
          "\(p.rawValue): the source it lands under is the label it reads back")
}

print(failures == 0 ? "landing round-trip: OK" : "landing round-trip: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

# `AgentProvider` lives in AgentAnswer.swift beside a great deal that needs
# SwiftUI, so the enum is extracted rather than compiled whole — and what is
# extracted is asserted to be byte-identical to the shipped switch below, so
# the extraction cannot drift from it.
python3 - "$ANSWER" "$TMP/provider.swift" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'var agent: String \{\n(.*?)\n    \}', src, re.S)
if not m:
    print("  ✗ AgentProvider.agent could not be read — the harness is blind")
    sys.exit(1)
cases = re.findall(r'case \.(\w+):\s*"([^"]+)"', m.group(1))
if len(cases) < 5:
    print(f"  ✗ read only {len(cases)} providers — the shape changed")
    sys.exit(1)
body = "\n".join(f'        case .{n}: return "{v}"' for n, v in cases)
names = "\n".join(f"    case {n}" for n, _ in cases)
open(sys.argv[2], "w").write(
    "enum AgentProvider: String, CaseIterable {\n" + names +
    "\n    var agent: String {\n        switch self {\n" + body +
    "\n        }\n    }\n}\n")
print(f"  ✓ extracted {len(cases)} providers from the shipped switch")
PY

echo "Round-trip against the shipped parser"
xcrun swiftc -O -o "$TMP/run" "$SHEET" "$TMP/provider.swift" "$TMP/main.swift" 2>"$TMP/build.log" || {
  echo "  ✗ harness did not compile:"; sed -n '1,25p' "$TMP/build.log"; exit 1; }
"$TMP/run" || fail=1

# --- mutations: prove the round-trip can FAIL -------------------------------
# A check that cannot demonstrate it catches anything certifies nothing
# (CLAUDE.md). Each mutation breaks exactly one rule and must be caught.
echo "Mutations"
mutate() {  # name, perl-expr
  cp "$SHEET" "$TMP/sheet.swift"
  perl -0pi -e "$2" "$TMP/sheet.swift"
  if cmp -s "$SHEET" "$TMP/sheet.swift"; then
    echo "  ✗ $1 — the mutation changed NOTHING (stale anchor)"; fail=1; return
  fi
  if xcrun swiftc -O -o "$TMP/mrun" "$TMP/sheet.swift" "$TMP/provider.swift" "$TMP/main.swift" \
       2>/dev/null && "$TMP/mrun" >/dev/null 2>&1; then
    echo "  ✗ $1 SURVIVED"; fail=1
  else
    echo "  ✓ $1"
  fi
}

mutate "a keyed seat losing its speaker label is caught" \
  's/case "Bankr":       return "Bankr"//'
mutate "a label that disagrees with the source is caught" \
  's/case "Venice":      return "Venice"/case "Venice":      return "venice"/'
# The parser's own line rule. A transcript is split on newlines and a line
# that starts no turn is APPENDED to the one before it — break the split and a
# multi-paragraph answer becomes one turn per paragraph, which is exactly the
# `ChatBubbles` defect `turns` exists to replace.
mutate "splitting a transcript on something other than newlines is caught" \
  's/components\(separatedBy: "\\n"\)/components(separatedBy: "\\t")/'
# The speaker marker is `speaker + ": "`, trailing space included. Without it
# "You:me" opens a turn, and an answer that merely contains a colon starts a
# new one.
mutate "dropping the space after the speaker's colon is caught" \
  's/let head = speaker \+ ": "/let head = speaker/'

# `readerLabel` is NOT mutated, and the reason is the finding itself: the
# landing writes it and the parser reads it, so drifting it moves BOTH sides
# and a round-trip still passes — a non-discriminating fixture, which this
# harness's own mutation pass caught on its first run (the standing rule: a
# fixture only tests the rule it names if it fails that rule and passes every
# other one). The real failure it guards is across BUILDS, not within one: a
# device that landed "You: …" cannot read those rows back if a later build
# spells it differently, which is why the shipped constant is a plain literal
# and not `String(localized:)`. That is a fact about the source, so it is
# asserted as one.
echo "Stored-transcript compatibility"
guard "the reader label is the literal \"You\", unlocalized" \
  'readerLabel = "You"' "$SHEET"
python3 - "$SHEET" <<'LOC' || fail=1
import sys, re
for line in open(sys.argv[1]):
    if "readerLabel" in line and "String(localized:" in line:
        print("  ✗ readerLabel is localized — every stored transcript stops "
              "parsing the moment the device language changes")
        sys.exit(1)
print("  ✓ readerLabel cannot change with the device language")
LOC

[[ $fail -eq 0 ]] || { echo; echo "agent-landing-selftest: FAILED"; exit 1; }
echo
echo "agent-landing-selftest: OK — assertions and mutations both pass."
