#!/bin/zsh
# Casberi chat-import self-test — the SHIPPED pure logic behind the three chat
# import rooms (ChatGPT, Claude, Gemini), 2026-08-08.
#
#   Casberi/Casberi/Model/ChatGPTImport.swift
#     — ChatTranscript   (the flatten + clamp every chat import shares)
#     — turns            (the GRAPH walk — conversation order, not dict order)
#   Casberi/Casberi/Model/ClaudeImport.swift
#     — turns            (flat, and the block filter that keeps tools out)
#   Casberi/Casberi/Model/GeminiImport.swift
#     — turns/promptText (the ask, whole, past the title's 200-char clamp)
#
# WHY A HARNESS. Until this morning all three importers parsed a whole
# conversation and stored a title plus one line: the entire chat was thrown
# away at import. Every failure of the fix is a SILENT WRONG ANSWER that
# renders perfectly — a scrambled transcript reads as a chat, a transcript
# clamped without counting reads as a complete one, a tool-call block reads as
# something the person said, and a room whose messageCount is the post-clamp
# line count ranks perfectly plausibly. None of it is visible in a build, in a
# screen sweep, or in a landed-row count.
#
# The importers are far too entangled to compile as shipped (SwiftData models,
# a ModelContext, SpotlightIndex), so the pure functions are EXTRACTED from the
# shipped source by name — never copied into this file — so the harness cannot
# pass against logic the app doesn't run. The only transformation is stripping
# `private `. If an extraction stops matching, the compile fails loudly rather
# than asserting nothing.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

GPT="Casberi/Casberi/Model/ChatGPTImport.swift"
CLA="Casberi/Casberi/Model/ClaudeImport.swift"
GEM="Casberi/Casberi/Model/GeminiImport.swift"
TOPICS="Casberi/Casberi/Model/ScreenshotTopics.swift"
INSIGHT="Casberi/Casberi/Model/FeedInsight.swift"
REFRESH="Casberi/Casberi/Model/BridgeRefresh.swift"
FEEDSCREEN="Casberi/Casberi/Screens/FeedScreen.swift"
for f in "$GPT" "$CLA" "$GEM" "$TOPICS" "$INSIGHT"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- drift guards -----------------------------------------------------------
# Each is a wiring fact the extracted functions cannot prove on their own: a
# perfect `turns` is worthless if nothing stores what it returns, and a perfect
# clamp is worthless if nothing counts what it cut.

# 1. THE TRANSCRIPT REACHES THE STORE, AND REACHES THE RIGHT FIELD.
#    `enrichedText` is retrieval-only by the 2026-07-15 ruling; `content` is
#    what `ChatBubbles` draws and what several screens treat as display copy.
#    Putting the transcript on `content` would change every chat row's face.
grep -q 'thing.enrichedText = body' "$GPT" \
  || { echo "✗ the transcript no longer lands on enrichedText — the rooms go back to a title and one line"; exit 1; }
grep -q 'thing.messageCount = transcript.messages' "$GPT" \
  || { echo "✗ messageCount is no longer set — the only moment the true number exists is at import"; exit 1; }
grep -qF 'content: firstUserLine(convo)' "$GPT" \
  || { echo "✗ ChatGPT's content is no longer the opening ask — the per-kind display contract moved"; exit 1; }
grep -qF 'content: title == opener ? "" : opener' "$CLA" \
  || { echo "✗ Claude's content is no longer the opening ask"; exit 1; }
grep -qF 'content: ""' "$GEM" \
  || { echo "✗ Gemini's content is no longer empty — its title already IS the ask"; exit 1; }

# 2. THE §320 RULE. A rewritten retrieval body invalidates both marks: the
#    vector was computed from the old words, and a "we looked" stamp is not a
#    "we looked correctly" stamp. Without these two lines every repaired row
#    keeps the embedding and the topics it got when its only text was one line.
grep -q 'thing.embedding = nil' "$GPT" \
  || { echo "✗ an edited transcript no longer clears the embedding — search answers with what the chat USED to say"; exit 1; }
grep -q 'thing.topicsAt = nil' "$GPT" \
  || { echo "✗ an edited transcript no longer clears topicsAt — the map keeps terms read off one line"; exit 1; }

# 3. THE DEDUPE HIT HEALS. Without this the fix reaches only conversations
#    imported from today on, and every chat already in the corpus stays empty
#    forever — the lesson CLAUDE.md records against the social bridges, and
#    against Instagram, Snapchat and X in turn. A re-import is the ONLY thing
#    that can reach these rows: no foreground sweep can, because the words
#    exist nowhere but inside a temporary scoped folder pick.
for f in "$GPT" "$CLA" "$GEM"; do
  grep -q 'ChatImportLanding.apply(script, to: already)' "$f" \
    || { echo "✗ ${f:t}: an already-imported chat is skipped, not healed — the fix reaches nothing already in the corpus"; exit 1; }
  grep -q 'IngestSupport.thingsByRef' "$f" \
    || { echo "✗ ${f:t}: back to a ref SET, which can only answer 'already here' and can never repair a row"; exit 1; }
  grep -q 'summary.imported > 0 || summary.healed > 0' "$f" \
    || { echo "✗ ${f:t}: an all-healed re-import never saves — the repair is thrown away on the way out"; exit 1; }
  # 4. THE §307/§309 RULE, twice: a cap that refuses rows and a clamp that
  #    cuts text must each COUNT what they took, or a truncated import reads
  #    word-for-word like a complete one.
  grep -q 'summary.dropped = max(0,' "$f" \
    || { echo "✗ ${f:t}: the cap no longer counts what it refused"; exit 1; }
  grep -q 'if script.clamped { summary.clamped += 1 }' "$f" \
    || { echo "✗ ${f:t}: the transcript clamp no longer counts what it cut"; exit 1; }
  grep -q 'guard already.isLive else' "$f" \
    || { echo "✗ ${f:t}: a held Thing is read without a liveness guard (the corollary chain)"; exit 1; }
done

# 5. THE ROOMS' REGISTRIES. Both are switches that answer nil for an unknown
#    source, and a call into a registry that answers nil is a no-op
#    indistinguishable from having nothing to say — the exact class that
#    shipped twice already (X, then TikTok).
#
#    Matched on the three literals appearing TOGETHER in one case line rather
#    than an exact-line match — 8d310d0c legitimately grew this case to a
#    fourth value (ClaudeCodeImport.source) the same day, and a bare exact
#    match goes stale on every future addition to the same case, which is
#    exactly the false failure this run just hit.
grep -qE 'case "ChatGPT", "Claude", "Gemini"' "$TOPICS" \
  || { echo "✗ the chat rooms have no topic source — healTopics is a no-op for them again"; exit 1; }
grep -q 'text: { $0.enrichedText ?? $0.content }' "$TOPICS" \
  || { echo "✗ a writing room reads the wrong field — the vault/chat rooms keep their words on enrichedText"; exit 1; }
grep -q 'case "ChatGPT", "Claude":' "$INSIGHT" \
  || { echo "✗ ChatGPT/Claude have no topic map — their rooms lead with a year heatmap over a corpus of subjects"; exit 1; }
grep -q 'case "Gemini":' "$INSIGHT" \
  || { echo "✗ Gemini has no topic map"; exit 1; }
# The writing/pixels fork, in the room where getting it wrong would be loudest:
# people paste links into chats constantly, so counting hostnames would rank
# the sites they pasted and call it what they talk about.
python3 - "$TOPICS" <<'PY' || exit 1
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'case "ChatGPT", "Claude", "Gemini"[^\n]*:', src)
if not m: sys.exit("✗ the chat TopicSource case is gone")
i = m.start()
block = src[i:i+400]
if "includeDomains: false" not in block:
    sys.exit("✗ the chat rooms count domains as topics — a hostname is not a subject (§313)")
if "kinds: [.chat]" not in block:
    sys.exit("✗ the chat rooms' topic kinds moved off .chat")
PY
# The map is consulted for EVERY room by source, so registering a case really
# does reach the feed. Named here because it is the half the cases above can't
# prove on their own.
#
# PINNED TO THE INVARIANT, NOT TO ONE CALL SITE (2026-08-21). This used to
# demand the literal `FeedInsight.topicMap(source: source, things: visible)`,
# and it went red the moment the perf pass moved that call out of the body and
# into `recomputeHeads()` — a change that altered WHEN the map is consulted and
# not WHETHER. A guard that fails on a rename teaches people to edit the guard,
# which is how a guard stops being read. So: the call must exist somewhere in
# the file, keyed by source, AND the head chain the feed renders must still read
# the answer — both halves, because either alone can be satisfied by a call
# whose result nothing draws.
if [[ -f "$FEEDSCREEN" ]]; then
  grep -q 'FeedInsight.topicMap(source: source' "$FEEDSCREEN" \
    || { echo "✗ the feed no longer consults the topic map by source — registering a case reaches nothing"; exit 1; }
  # Across lines: the render is a gate chain wrapped onto a second line, so a
  # line-wise grep would answer "no" on a perfectly healthy file — which is the
  # same false alarm this guard was just rewritten to stop making.
  perl -0777 -ne 'exit(0) if /let topicMap\s*=.*?\?\s*(heads\?\.topicMap|FeedInsight\.topicMap)/s; exit(1)' \
    "$FEEDSCREEN" \
    || { echo "✗ the feed computes a topic map and never renders it"; exit 1; }
fi

# 6. PENDING WIRING (2026-08-08). `healTopics` is called per-source and there
#    is no call for these three anywhere, so their `ocrTopics` stay empty and
#    the maps registered above can never draw. The call belongs beside the
#    other import rooms' in BridgeRefresh.runForegroundWork — a file outside
#    the pass that added this test. This check FLIPS to a hard guard the moment
#    the call lands, so it can never quietly regress afterwards, and stays a
#    note until then rather than failing a build over work it can't do itself.
if grep -q 'healTopics(source: "ChatGPT"' "$REFRESH" 2>/dev/null; then
  for s in ChatGPT Claude Gemini; do
    grep -q "healTopics(source: \"$s\"" "$REFRESH" \
      || { echo "✗ $s lost its topic sweep — its map can never get terms"; exit 1; }
  done
else
  echo "  ⚠ PENDING: no healTopics(source:) call for ChatGPT/Claude/Gemini in BridgeRefresh.swift"
  echo "    — the topic sources registered above are unreachable until one lands."
fi

TMP=$(mktemp -d /tmp/chatimport-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- extraction -------------------------------------------------------------
cat > "$TMP/extract.py" <<'PY'
import sys
gpt, cla, gem, out = sys.argv[1:5]

def grab(path, signature):
    """The whole declaration whose line contains `signature`, brace-matched
    from the shipped source. Never a copy."""
    src = open(path).read()
    i = src.find(signature)
    if i < 0:
        sys.exit(f"✗ extraction failed: {signature!r} not found in {path}")
    start = src.rfind("\n", 0, i) + 1
    j = src.index("{", i)
    depth, k = 0, j
    while k < len(src):
        if src[k] == "{": depth += 1
        elif src[k] == "}":
            depth -= 1
            if depth == 0: break
        k += 1
    return src[start:k+1].replace("private ", "")

def grabline(path, signature):
    """A one-line `static let X = <literal>`. NOT `grab`, which brace-matches
    from the next `{` it sees — for a declaration with no closure that is the
    following FUNCTION's body, and it swallows it whole (the trap x-selftest
    records: it surfaces as an invalid-redeclaration error, not as a missing
    constant)."""
    src = open(path).read()
    i = src.find(signature)
    if i < 0:
        sys.exit(f"✗ extraction failed: {signature!r} not found in {path}")
    start = src.rfind("\n", 0, i) + 1
    return src[start:src.index("\n", i)].replace("private ", "")

pieces = [
    "import Foundation\n",
    # The shared flatten/clamp, compiled WHOLE and unmodified — it is
    # Foundation-only by design (the landing that touches a `Thing` lives in
    # `ChatImportLanding` beside it, precisely so this can be tested).
    grab(gpt, "struct ChatTranscript"),
    "\nenum ChatGPTImport {",
    grab(gpt, "static func turns"),
    grab(gpt, "static func rootID"),
    grab(gpt, "static func turn(in node"),
    grab(gpt, "static func speakerName"),
    grab(gpt, "static func messageText"),
    grab(gpt, "static func transcript"),
    grabline(gpt, "static let nodeCap"),
    "}\n",
    "enum ClaudeImport {",
    grab(cla, "static func turns"),
    grab(cla, "static func speakerName"),
    grab(cla, "static func messageText"),
    grab(cla, "static func transcript"),
    "}\n",
    "enum GeminiImport {",
    grab(gem, "static func turns"),
    grab(gem, "static func transcript"),
    grab(gem, "static func promptText"),
    "}\n",
]
open(out, "w").write("\n".join(pieces))
PY

python3 "$TMP/extract.py" "$GPT" "$CLA" "$GEM" "$TMP/extracted.swift"

# --- the driver -------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}

/// A fixture, parsed exactly the way the importer parses a real export — the
/// same `JSONSerialization` bridge, so an `as?` that would fail on device
/// fails here too.
func json(_ s: String) -> [String: Any] {
    ((try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any]) ?? [:]
}
func lines(_ turns: [(speaker: String, text: String)]) -> [String] {
    turns.map { "\($0.speaker): \($0.text)" }
}

// ---------------------------------------------------------------------------
print("ChatGPT — the mapping is a GRAPH, and order is the whole game")

// Node ids are deliberately NOT in conversational order alphabetically:
// sorted by key this reads root, then "a-second-ask", then "m-first-answer"…
// so any reader that falls back to a sorted or dictionary order produces a
// different sentence than the one asserted below.
let linear = json("""
{
  "title": "Sourdough",
  "current_node": "z-second-answer",
  "mapping": {
    "root": {"id": "root", "parent": null, "children": ["m-first-ask"], "message": null},
    "m-first-ask": {"id": "m-first-ask", "parent": "root", "children": ["b-first-answer"],
      "message": {"author": {"role": "user"}, "content": {"content_type": "text", "parts": ["why is my starter flat"]}}},
    "b-first-answer": {"id": "b-first-answer", "parent": "m-first-ask", "children": ["a-second-ask"],
      "message": {"author": {"role": "assistant"}, "content": {"content_type": "text", "parts": ["it is probably too cold"]}}},
    "a-second-ask": {"id": "a-second-ask", "parent": "b-first-answer", "children": ["z-second-answer"],
      "message": {"author": {"role": "user"}, "content": {"content_type": "text", "parts": ["how warm should the kitchen be"]}}},
    "z-second-answer": {"id": "z-second-answer", "parent": "a-second-ask", "children": [],
      "message": {"author": {"role": "assistant"}, "content": {"content_type": "text", "parts": ["around 24C"]}}}
  }
}
""")
check("the conversation comes back in the order it was said",
      lines(ChatGPTImport.turns(linear)) == [
        "You: why is my starter flat",
        "ChatGPT: it is probably too cold",
        "You: how warm should the kitchen be",
        "ChatGPT: around 24C",
      ])
check("…which is NOT the order the node ids sort in",
      ["a-second-ask", "b-first-answer", "m-first-ask", "root", "z-second-answer"]
        != ["root", "m-first-ask", "b-first-answer", "a-second-ask", "z-second-answer"])
check("the empty root node contributes no turn",
      ChatGPTImport.turns(linear).count == 4)
check("both speakers are named",
      Set(ChatGPTImport.turns(linear).map(\.speaker)) == ["You", "ChatGPT"])

// A REGENERATION. `current_node` names the branch ChatGPT itself considers
// current; the abandoned one must not be interleaved into the transcript.
let branched = json("""
{
  "current_node": "kept",
  "mapping": {
    "root": {"parent": null, "children": ["ask"], "message": null},
    "ask": {"parent": "root", "children": ["discarded", "kept"],
      "message": {"author": {"role": "user"}, "content": {"content_type": "text", "parts": ["name three"]}}},
    "discarded": {"parent": "ask", "children": [],
      "message": {"author": {"role": "assistant"}, "content": {"content_type": "text", "parts": ["FIRST TRY"]}}},
    "kept": {"parent": "ask", "children": [],
      "message": {"author": {"role": "assistant"}, "content": {"content_type": "text", "parts": ["SECOND TRY"]}}}
  }
}
""")
let branchText = ChatGPTImport.transcript(branched).text
check("an abandoned regeneration is left out", !branchText.contains("FIRST TRY"))
check("…and the current branch is kept", branchText.contains("SECOND TRY"))
check("a branched conversation counts only the branch it kept",
      ChatGPTImport.transcript(branched).messages == 2)

// NO `current_node` — an older export, or a fragment. The walk goes down from
// the root, taking the LAST child at each fork (the newest regeneration, which
// is what `current_node` would have named).
let rootless = json("""
{
  "mapping": {
    "start": {"parent": null, "children": ["ask"], "message": null},
    "ask": {"parent": "start", "children": ["older", "newer"],
      "message": {"author": {"role": "user"}, "content": {"content_type": "text", "parts": ["one"]}}},
    "older": {"parent": "ask", "children": [],
      "message": {"author": {"role": "assistant"}, "content": {"content_type": "text", "parts": ["OLD BRANCH"]}}},
    "newer": {"parent": "ask", "children": [],
      "message": {"author": {"role": "assistant"}, "content": {"content_type": "text", "parts": ["NEW BRANCH"]}}}
  }
}
""")
check("without current_node the walk still finds the conversation",
      lines(ChatGPTImport.turns(rootless)).first == "You: one")
check("…and takes the newest branch at a fork",
      ChatGPTImport.transcript(rootless).text.contains("NEW BRANCH"))
// A root whose parent is NAMED but absent from the mapping — a truncated
// export. Stranding the walk here would empty the whole conversation.
let orphaned = json("""
{
  "mapping": {
    "only": {"parent": "gone", "children": [],
      "message": {"author": {"role": "user"}, "content": {"content_type": "text", "parts": ["still here"]}}}
  }
}
""")
check("a node whose parent is missing still counts as a root",
      lines(ChatGPTImport.turns(orphaned)) == ["You: still here"])

print("ChatGPT — tool and system chrome is not conversation")
func gptOne(_ message: String) -> [(speaker: String, text: String)] {
    ChatGPTImport.turns(json("""
    { "current_node": "n",
      "mapping": {"n": {"parent": null, "children": [], "message": \(message)}} }
    """))
}
check("a system preamble is excluded",
      gptOne(#"{"author": {"role": "system"}, "content": {"content_type": "text", "parts": ["You are ChatGPT."]}}"#).isEmpty)
check("a tool's output is excluded",
      gptOne(#"{"author": {"role": "tool"}, "content": {"content_type": "text", "parts": ["{\"results\": []}"]}}"#).isEmpty)
check("a code block is excluded",
      gptOne(#"{"author": {"role": "assistant"}, "content": {"content_type": "code", "parts": ["import pandas"]}}"#).isEmpty)
check("the custom instructions are excluded (they wear the user role)",
      gptOne(#"{"author": {"role": "user"}, "content": {"content_type": "user_editable_context", "parts": ["Be concise."]}}"#).isEmpty)
check("a message ChatGPT hides from the conversation is excluded",
      gptOne(#"{"author": {"role": "user"}, "metadata": {"is_visually_hidden_from_conversation": true}, "content": {"content_type": "text", "parts": ["hidden setup"]}}"#).isEmpty)
check("…and the same message without that flag is kept",
      lines(gptOne(#"{"author": {"role": "user"}, "metadata": {"is_visually_hidden_from_conversation": false}, "content": {"content_type": "text", "parts": ["hidden setup"]}}"#)) == ["You: hidden setup"])
check("a multimodal message keeps its words and skips the image part",
      lines(gptOne(#"{"author": {"role": "user"}, "content": {"content_type": "multimodal_text", "parts": [{"asset_pointer": "file-1"}, "what is in this photo"]}}"#))
        == ["You: what is in this photo"])
check("an empty message contributes nothing",
      gptOne(#"{"author": {"role": "assistant"}, "content": {"content_type": "text", "parts": ["   "]}}"#).isEmpty)
check("a message with no content at all contributes nothing",
      gptOne(#"{"author": {"role": "assistant"}}"#).isEmpty)

print("ChatGPT — a malformed file costs a truncation, never a hang")
let selfParent = json("""
{ "current_node": "loop",
  "mapping": {"loop": {"parent": "loop", "children": ["loop"],
    "message": {"author": {"role": "user"}, "content": {"content_type": "text", "parts": ["round and round"]}}}} }
""")
check("a node that is its own parent terminates",
      lines(ChatGPTImport.turns(selfParent)) == ["You: round and round"])
let twoCycle = json("""
{ "current_node": "a",
  "mapping": {
    "a": {"parent": "b", "children": [], "message": {"author": {"role": "user"}, "content": {"content_type": "text", "parts": ["A"]}}},
    "b": {"parent": "a", "children": ["a"], "message": {"author": {"role": "user"}, "content": {"content_type": "text", "parts": ["B"]}}}} }
""")
check("a two-node cycle terminates with both turns",
      ChatGPTImport.turns(twoCycle).count == 2)
check("no mapping at all is a skip, not a crash",
      ChatGPTImport.turns(json(#"{"title": "empty"}"#)).isEmpty)
check("an empty mapping is a skip",
      ChatGPTImport.turns(json(#"{"mapping": {}}"#)).isEmpty)
check("…and its transcript is empty, uncounted and unclamped",
      ChatGPTImport.transcript(json(#"{"mapping": {}}"#)).isEmpty
        && ChatGPTImport.transcript(json(#"{"mapping": {}}"#)).messages == 0
        && !ChatGPTImport.transcript(json(#"{"mapping": {}}"#)).clamped)

// ---------------------------------------------------------------------------
print("ChatTranscript — the clamp, and the count that must survive it")
let short = ChatTranscript.make([("You", "hello"), ("ChatGPT", "hi")])
check("turns join speaker-prefixed, one per line",
      short.text == "You: hello\nChatGPT: hi")
check("a short conversation is not clamped", !short.clamped)
check("messages counts the turns", short.messages == 2)

let long = ChatTranscript.make((0..<400).map { ("You", "turn \($0) " + String(repeating: "x", count: 90)) })
check("a long conversation is cut at the cap", long.text.count == ChatTranscript.cap)
check("…and SAYS it was cut", long.clamped)
check("…and still counts every message, not the ones that fit",
      long.messages == 400)
check("the clamp keeps the START — a chat opens with the ask it exists to answer",
      long.text.hasPrefix("You: turn 0 "))
check("…so the tail is what's missing", !long.text.contains("turn 399"))
// Exactly at the ceiling: `>` and not `>=`, or a transcript that fits reports
// itself truncated and the receipt tells a person to re-export for nothing.
let exact = ChatTranscript.make([("You", String(repeating: "y", count: ChatTranscript.cap - 5))])
check("a transcript exactly at the cap is not clamped",
      exact.text.count == ChatTranscript.cap && !exact.clamped)
check("no turns → empty, and empty is not a clamp",
      ChatTranscript.make([]).isEmpty && ChatTranscript.make([]).messages == 0
        && !ChatTranscript.make([]).clamped)

// ---------------------------------------------------------------------------
print("Claude — flat, and the block filter that keeps tools out")
let claude = json("""
{
  "name": "Refactor",
  "chat_messages": [
    {"sender": "human", "text": "why is this slow"},
    {"sender": "assistant", "text": "the loop re-fetches"},
    {"sender": "human", "text": "fix it"}
  ]
}
""")
check("a flat conversation keeps the file's order",
      lines(ClaudeImport.turns(claude)) == [
        "You: why is this slow", "Claude: the loop re-fetches", "You: fix it"])
check("the assistant is named Claude, not ChatGPT",
      ClaudeImport.turns(claude)[1].speaker == "Claude")
check("messageCount is the turn count", ClaudeImport.transcript(claude).messages == 3)

func claudeOne(_ message: String) -> [(speaker: String, text: String)] {
    ClaudeImport.turns(json(#"{"chat_messages": [\#(message)]}"#))
}
check("a structured content block is read when `text` is empty",
      lines(claudeOne(#"{"sender": "human", "text": "", "content": [{"type": "text", "text": "from a block"}]}"#))
        == ["You: from a block"])
check("two text blocks join",
      lines(claudeOne(#"{"sender": "assistant", "content": [{"type": "text", "text": "one"}, {"type": "text", "text": "two"}]}"#))
        == ["Claude: one two"])
// The filter is on the block's TYPE, whatever keys it happens to carry — a
// thinking or tool block that also has a "text" key must not become words the
// person reads back as their conversation.
check("a non-prose block is excluded even when it carries a text key",
      claudeOne(#"{"sender": "assistant", "content": [{"type": "thinking", "text": "let me consider"}]}"#).isEmpty)
check("…and prose beside it survives",
      lines(claudeOne(#"{"sender": "assistant", "content": [{"type": "thinking", "text": "let me consider"}, {"type": "text", "text": "here you go"}]}"#))
        == ["Claude: here you go"])
check("an untyped block still reads as text (the older export's shape)",
      lines(claudeOne(#"{"sender": "human", "content": [{"text": "old shape"}]}"#)) == ["You: old shape"])
check("a sender that is neither human nor assistant is excluded",
      claudeOne(#"{"sender": "system", "text": "conversation summary"}"#).isEmpty)
check("an empty message is excluded",
      claudeOne(#"{"sender": "human", "text": ""}"#).isEmpty)
check("no chat_messages at all is a skip, not a crash",
      ClaudeImport.turns(json(#"{"name": "titled but empty"}"#)).isEmpty)

// ---------------------------------------------------------------------------
print("Gemini — one prompt, whole, past the title's clamp")
// Trimmed deliberately: `promptText` trims the whole title before it strips
// the verb, so a fixture with a trailing space would fail on the space and
// look like a broken reader. (A test that is wrong about the contract is worse
// than no test — this one caught itself on its first run.)
let ask = String(repeating: "a very specific question about roasting ", count: 20)
    .trimmingCharacters(in: .whitespaces)  // ~800 chars
let gemini = json(#"{"title": "Prompted \#(ask)", "time": "2026-04-16T09:41:00.000Z"}"#)
check("the Takeout verb is stripped",
      GeminiImport.turns(gemini).first?.text == ask)
check("the WHOLE ask survives — this is the gain over the 200-char title",
      (GeminiImport.transcript(gemini).text.count) > 400)
check("one record is one turn", GeminiImport.transcript(gemini).messages == 1)
check("the speaker is you", GeminiImport.turns(gemini).first?.speaker == "You")
check("an app-open record carries no ask and is skipped",
      GeminiImport.turns(json(#"{"title": "Used Gemini"}"#)).isEmpty)
check("a title in another export language passes through whole",
      GeminiImport.turns(json(#"{"title": "Consulta sobre pan"}"#)).first?.text == "Consulta sobre pan")
check("a record with no title is a skip, not a crash",
      GeminiImport.turns(json(#"{"time": "2026-04-16T09:41:00.000Z"}"#)).isEmpty)
check("a blank title is a skip",
      GeminiImport.turns(json(#"{"title": "   "}"#)).isEmpty)

print("")
if failures > 0 { print("chatimport-selftest: ✗ \(failures) assertion(s) failed"); exit(1) }
print("chatimport-selftest: OK — every assertion passed against the shipped source.")
SWIFT

if ! swiftc -O -o "$TMP/run" "$TMP/extracted.swift" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ the harness failed to compile against the shipped source"
  grep -E 'error:' "$TMP/build.log" | head -20
  exit 1
fi
"$TMP/run"

# --- mutations --------------------------------------------------------------
# A check that cannot fail proves nothing. Each mutation is a plausible
# "simplification" of the shipped source, and each must break the run.
echo
echo "mutations (each must be caught)"

WORK="$TMP/work"
mutate() {
  local file="$1" name="$2" from="$3" to="$4"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$GPT" "$WORK/ChatGPTImport.swift"
  cp "$CLA" "$WORK/ClaudeImport.swift"
  cp "$GEM" "$WORK/GeminiImport.swift"
  local target="$WORK/${file:t}"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$target" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$target"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  python3 "$TMP/extract.py" "$WORK/ChatGPTImport.swift" "$WORK/ClaudeImport.swift" \
    "$WORK/GeminiImport.swift" "$TMP/mutated.swift" >/dev/null 2>&1 \
    || { echo "  ✓ $name (rejected at extraction)"; return }
  if ! swiftc -O -o "$TMP/mut" "$TMP/mutated.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# 1. The bug this whole pass exists to prevent: a transcript in graph order
#    rather than conversation order. Leaving out the reverse is the smallest
#    possible version of it — every chat reads backwards.
mutate "$GPT" "the walk is not reversed (leaf → root)" \
  'chain.reverse()' \
  '_ = chain.count'

# 2. The parent link dropped — the transcript becomes the last message alone,
#    which still lands, still renders and still counts as a successful import.
mutate "$GPT" "the parent link is not followed" \
  'cursor = node["parent"] as? String' \
  'cursor = nil'

# 3. System and tool turns admitted. The room fills with prompt scaffolding
#    and search output filed as things the person said.
mutate "$GPT" "system/tool roles are landed as speakers" \
  'default: return nil
        }
    }' \
  'default: return "System"
        }
    }'

# 4. The content-type gate removed — code blocks and the custom instructions
#    become conversation.
mutate "$GPT" "the content_type gate is removed" \
  'guard type == "text" || type == "multimodal_text" else { return "" }' \
  'guard !type.isEmpty else { return "" }'

# 5. The hidden-message flag ignored.
mutate "$GPT" "ChatGPT's own hidden setup messages are landed" \
  '(metadata["is_visually_hidden_from_conversation"] as? Bool) == true' \
  '(metadata["is_visually_hidden_from_conversation"] as? Bool) == false'

# 6. The clamp stops saying it clamped — a truncated transcript reads exactly
#    like a complete one, everywhere it is reported (§307/§309).
mutate "$GPT" "the clamp no longer reports itself" \
  'clamped: joined.count > cap' \
  'clamped: false'

# 7. …and the off-by-one on the other side: a transcript that exactly fits
#    reports itself truncated, which sends someone re-exporting for nothing.
mutate "$GPT" "a transcript that exactly fits reports itself clamped" \
  'clamped: joined.count > cap' \
  'clamped: joined.count >= cap'

# 8. The count taken AFTER the clamp — the number a room's ranking rests on,
#    silently wrong for exactly the longest conversations.
mutate "$GPT" "messages counted after the clamp, not before" \
  'messages: turns.count' \
  'messages: String(joined.prefix(cap)).split(separator: "\n").count'

# 9. The clamp removed altogether.
mutate "$GPT" "the transcript is stored unclamped" \
  'text: String(joined.prefix(cap))' \
  'text: joined'

# 10. Claude's block filter removed — thinking and tool blocks become words
#     the person reads back as their own conversation.
mutate "$CLA" "Claude's non-prose blocks are landed" \
  '.filter { (($0["type"] as? String) ?? "text") == "text" }' \
  '.filter { _ in true }'

# 11. An unknown sender admitted.
mutate "$CLA" "an unknown Claude sender is landed" \
  'default: return nil
        }
    }' \
  'default: return "Them"
        }
    }'

# 12. Gemini's ask clamped to the display title — the exact defect this pass
#     removes, since a Gemini row's `content` is empty and the title is all
#     there was.
mutate "$GEM" "Gemini's ask is clamped back to the title's 200 chars" \
  'return title
    }' \
  'return String(title.prefix(200))
    }'

echo
echo "✓ chat-import self-test: assertions and mutations all passed"
