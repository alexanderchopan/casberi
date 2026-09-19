#!/bin/zsh
# Casberi agent-sheet self-test — the SHIPPED pure judgement behind every agent
# thing sheet (prd §367, 2026-08-12):
#
#   Casberi/Casberi/Model/AgentSheet.swift
#
# Foundation-only BY DESIGN, so it is compiled WHOLE AND UNMODIFIED rather than
# extracted — the strongest form of "the harness ran the shipped logic".
# Everything touching `Thing`, SwiftData or the catalog lives in
# `AgentSheetSource.swift`.
#
# THAT FILE IS COMPILED WHOLE TOO, since 2026-09-19 (the SECOND harness below).
# It was left out from §367 (2026-08-12) onwards on the reasoning that it
# "holds lookups rather than judgement", and two defects shipped inside those
# lookups for the five weeks since, from one cause: `Thing.init` PREPENDS the kind's `typeTag` to `tags`
# (`Casberi/Shared/Thing.swift`), and both tag filters here were written
# against the array their CALLER passes rather than the array that is stored.
# `project(for:)` returned "Chat" for every agent row in the corpus, so the
# conversation head read "in Chat" on every agent sheet ever drawn and Claude
# Code's real project never reached it; `permissions(for:)` listed "Link" to
# the reader as a verb a key had been granted.
#
# The lesson is the fixture, not the filter: every fixture in the FIRST
# harness is built by hand, and a hand-built fixture is a statement of what
# the author BELIEVES is stored. It cannot disagree with them. So the second
# harness builds its things through the shipped `Thing.init` — the only thing
# that knows what a row really carries.
#
# WHY A HARNESS. Every failure mode here is a SILENT WRONG ANSWER that renders
# perfectly, and neither a build nor a screen sweep nor a probe can see any of
# them:
#
#   · a turn parsed with the wrong speaker label prints a stranger's words
#     under your own name — the §363 failure in its most expensive form
#   · a transcript split on every newline (which is what `ChatBubbles` does)
#     turns one answer's paragraphs into six separate messages
#   · an 84-turn chat showing its first 8,000 characters with no clause reads
#     as the whole conversation
#   · a clamp clause on a chat that was never clamped claims turns went missing
#     that never existed
#   · a Slack message or a Stocktwits post — both `.chat`, neither a transcript
#     — wearing a conversation's anatomy
#   · a grant's expiry off by a day boundary, on the one surface whose job is
#     "what can this agent reach, and until when"
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

SHEET="Casberi/Casberi/Model/AgentSheet.swift"
SOURCE="Casberi/Casberi/Model/AgentSheetSource.swift"
VIEWS="Casberi/Casberi/Screens/AgentSheetViews.swift"
VIEW="Casberi/Casberi/Screens/ThingSheetView.swift"
CONTENT="Casberi/Casberi/Screens/ThingContent.swift"
CATALOG="Casberi/Casberi/Model/BridgeCatalog.swift"
GPT="Casberi/Casberi/Model/ChatGPTImport.swift"
CLAUDE="Casberi/Casberi/Model/ClaudeImport.swift"
CODE="Casberi/Casberi/Model/ClaudeCodeImport.swift"
GEMINI="Casberi/Casberi/Model/GeminiImport.swift"
THING="Casberi/Shared/Thing.swift"
for f in "$SHEET" "$SOURCE" "$VIEWS" "$VIEW" "$CONTENT" "$CATALOG" \
         "$GPT" "$CLAUDE" "$CODE" "$GEMINI" "$THING"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
guard() {  # name, pattern, file
  if grep -qE -- "$2" "$3"; then echo "  ✓ $1"; else echo "  ✗ $1"; fail=1; fi
}
absent() { # name, pattern, comment-stripped file
  if grep -qE -- "$2" "$3"; then echo "  ✗ $1"; fail=1; else echo "  ✓ $1"; fi
}

echo "Drift guards"

# --- the wiring -------------------------------------------------------------
# A perfect `shape` is worthless if the sheet never asks it, and a perfect
# `turns` is worthless if the content view still draws `content`.
guard "the sheet asks AgentSheetSource for its shape" \
  'AgentSheetSource\.shape\(for: thing\)' "$VIEW"
guard "the conversation head is drawn" \
  'AgentConversationHead\(reading: agentConversation\)' "$VIEW"
guard "the grant replaces the title block" \
  'AgentGrantView\(grant: agentGrant\)' "$VIEW"
guard "the receipt card is drawn" \
  'AgentReceiptCard\(reading: agentConversation\)' "$VIEW"
# The reading is computed ONCE and handed down. Two derivations are two places
# that can disagree about how many turns a chat had.
guard "the content view is handed the reading, not left to re-derive it" \
  'ThingContentView\(thing: thing, agent: agentConversation\)' "$VIEW"
guard "the chat branch draws the turns" \
  'AgentTurnsView\(turns: agent\.turns' "$CONTENT"
# The two rows this pass takes with it. Deliberately tolerant of extra
# conjuncts: the same sheet serves every category and sibling passes add their
# own gates; what is asserted is that each row is gated on the agent shape at
# all.
guard "the Site row stands down on an agent sheet" \
  'hasSite = .*agentShape == nil' "$VIEW"
# The From row it also took no longer exists on ANY sheet (prd §736): the dial
# already carried a door for every kind that row named a place for, so it was
# the same fact twice — §367's own finding here ("From — from your session was
# this table's whole contribution to a chat"), applied everywhere. There is no
# stand-down left to assert, only a row that must not come back. Comment-
# stripped, because the view now carries a tombstone naming it.
python3 - "$VIEW" <<'FROMGONE' || fail=1
import sys
code = "\n".join(l for l in open(sys.argv[1]).read().splitlines()
                 if not l.strip().startswith("//"))
if any(n in code for n in ("hasFrom", "fromRow", "PlaceWords")):
    print("  ✗ the From row is back on the sheet — prd §736 deleted it")
    sys.exit(1)
print("  ✓ the From row stays deleted (prd §736)")
FROMGONE
# A grant draws no content: its link is the same dashboard URL on every row.
guard "a grant shows no link preview" \
  'agentShape != \.grant' "$VIEW"
# A row wears ONE anatomy. Cursor is in the Agents category and is drawn by the
# Work receipt — asking this first would take that away from it.
# `walletStage` was retired in the 2026-08-12 integration merge — §369's money
# receipt generalized the three wallet title grammars into one anatomy, so the
# gate is spelled `moneyReceipt` now. The RULE is unchanged and is what this
# guards: an agent sheet yields to the money anatomy and to the Work receipt.
guard "the agent shape yields to the money receipt and the Work receipt" \
  'moneyReceipt == nil, workReading == nil' "$VIEW"

# --- the ingest half --------------------------------------------------------
# THE INGEST IS GONE (2026-09-06): the 1Claw bridge was deleted with the other
# retired seats, so nothing stamps a grant's parts any more. Four guards over
# `OneClawBridge.swift` stood here and are not replaced by nothing — what
# survives the bridge is the READ, and the read is what still has to work,
# because a corpus that already holds grant rows still draws their sheets.
# `AgentSheetSource` owns both halves of that read now, so both are guarded
# there rather than deleted with the writer.
guard "a grant row is still recognised by its own ref" \
  'ref\?\.hasPrefix\("1claw:policy:"\)' "$SOURCE"
guard "the permissions still come off the row's tags, minus the facet" \
  'thing\.tags\.filter \{ \$0 != "Grant"' "$SOURCE"

# --- negative guards --------------------------------------------------------
# Read a COMMENT-STRIPPED copy: these files DOCUMENT what they must no longer do
# by naming it (`AgentSheet` quotes `ChatBubbles(text: thing.content)` in its own
# header as the defect it fixes), so a guard grepping raw source fires against
# the prose explaining itself — the Obsidian/Cursor lesson, paid again here.
strip() { sed -E 's://.*$::' "$1" | sed -E '/^[[:space:]]*\/\/\//d'; }
strip "$CONTENT" > "$TMP/content.nc"
strip "$SHEET"   > "$TMP/sheet.nc"

# The whole finding: a conversation drawn as its own opening line.
absent "the chat branch no longer draws content when a reading exists" \
  'if let agent \{$.*ChatBubbles\(text: thing\.content\)$' "$TMP/content.nc"
# The speaker labels are a WIRE FORMAT written by four importers, in stable
# English. Localizing the parser's expectation stops every transcript in the
# corpus from parsing the moment somebody changes their language (prd §340).
absent "the reader label is not localized" \
  'readerLabel = String\(localized' "$TMP/sheet.nc"
absent "the assistant labels are not localized" \
  'return String\(localized: "ChatGPT"\)' "$TMP/sheet.nc"

# --- the wire format itself -------------------------------------------------
# `turns` recovers what four other files WROTE. If an importer renames a
# speaker, every transcript it has ever landed stops parsing — and the sheet
# silently falls back to today's one-line rendering, which is exactly the state
# this pass exists to end.
python3 - "$SHEET" "$GPT" "$CLAUDE" "$CODE" "$GEMINI" <<'PY' || fail=1
import re, sys
sheet, gpt, claude, code, gemini = (open(p).read() for p in sys.argv[1:6])
bad = []
# The reader's label, in all four importers.
for name, src, pat in [
    ("ChatGPTImport",  gpt,    r'case "user":\s*return "You"'),
    ("ClaudeImport",   claude, r'case "human":\s*return "You"'),
    ("ClaudeCodeSession", code, r'turn\.role == "user" \? "You: "'),
    ("GeminiImport",   gemini, r'speaker: "You"'),
]:
    if not re.search(pat, src):
        bad.append(f"{name} no longer writes \"You\" as the reader's label")
# The assistants, and the one that differs from its seat name.
for name, src, pat in [
    ("ChatGPTImport", gpt,    r'case "assistant":\s*return "ChatGPT"'),
    ("ClaudeImport",  claude, r'case "assistant":\s*return "Claude"'),
    ("ClaudeCodeSession", code, r': "Claude: "'),
]:
    if not re.search(pat, src):
        bad.append(f"{name} no longer writes the assistant label this parser expects")
# The separator. Both writers use ": " and the parser requires the space.
if '"\\(.speaker): \\(.text)"' not in gpt.replace("$0", ".") and \
   not re.search(r'"\\\(\$0\.speaker\): \\\(\$0\.text\)"', gpt):
    bad.append("ChatTranscript no longer joins turns as \"<Speaker>: <text>\"")
if bad:
    for b in bad: print("  \u2717 " + b)
    sys.exit(1)
print("  \u2713 all four importers still write the speaker labels this parser reads")
PY

# --- the catalog ------------------------------------------------------------
# The chat-source set is a literal for speed; the catalog is the authority. An
# `Agent` seat that starts landing chats without joining this list gets no
# anatomy at all, silently.
python3 - "$CATALOG" "$SOURCE" <<'PY' || fail=1
import re, sys
catalog, source = (open(p).read() for p in sys.argv[1:3])
offers = set()
for block in catalog.split("Offer(")[1:]:
    block = block.split("needsSetup")[0]
    name = re.search(r'name:\s*"([^"]+)"', block)
    if name and re.search(r'group:\s*"Agent"', block):
        offers.add(name.group(1))
listed = set(re.findall(r'"([^"]+)"', re.search(
    r'static let chatSources: Set<String> = \[(.*?)\]', source, re.S).group(1)))
# The seats that deliberately land nothing (keys, not sources) and the one
# already covered by the Work receipt. Each is a conscious ruling, not a gap.
# Apple Intelligence (prd §833) switches which model answers; it lands nothing.
known = {"Venice", "OpenRouter", "Grok", "Bankr", "1Claw", "Cursor", "Apple Intelligence"}
missing = offers - listed - known
if missing:
    print("  \u2717 catalog Agent seats in neither chatSources nor the ruled-out set: "
          + ", ".join(sorted(missing)))
    sys.exit(1)
stale = listed - offers
if stale:
    print("  \u2717 chatSources names a seat the catalog does not offer: "
          + ", ".join(sorted(stale)))
    sys.exit(1)
print("  \u2713 every catalog Agent seat is accounted for (%d offers, %d chat seats)"
      % (len(offers), len(listed)))
PY

[[ $fail -eq 0 ]] || { echo "agent-sheet-selftest: ✗ drift guard(s) failed"; exit 1; }

# --- the harness ------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}

func facts(kind: String = "chat", socialShaped: Bool = false, grantRef: Bool = false,
           turns: Int = 0, counted: Int? = nil) -> AgentSheet.Facts {
    .init(kind: kind, socialShaped: socialShaped, grantRef: grantRef,
          turns: turns, counted: counted)
}

print("Shape — which rows get an anatomy, and which already have one")

check("a chat with a parsed transcript is a conversation",
      AgentSheet.shape(facts(turns: 12)) == .conversation)
check("a chat with only a counted transcript is still a conversation",
      AgentSheet.shape(facts(counted: 12)) == .conversation)
// The rows this must NOT claim. Slack messages and Stocktwits posts are `.chat`
// and carry neither a transcript nor a turn count — they are one message, not a
// conversation, and giving them a receipt would invent a document.
check("a bare .chat with no transcript and no count has no shape",
      AgentSheet.shape(facts()) == nil)
// Social asked first: a Snapchat saved chat and an imported DM thread are
// transcripts of PEOPLE and already have an anatomy.
check("a socially shaped chat is left to the social sheet",
      AgentSheet.shape(facts(socialShaped: true, turns: 40)) == nil)
// A grant is a permission before it is a link — and before anything else,
// because its `.link` kind is exactly what was drawing the wrong noun.
check("a grant ref is a grant", AgentSheet.shape(facts(kind: "link", grantRef: true)) == .grant)
check("a grant wins even against a social shape",
      AgentSheet.shape(facts(kind: "link", socialShaped: true, grantRef: true)) == .grant)
check("a plain link is not a grant", AgentSheet.shape(facts(kind: "link")) == nil)
check("a note is not a conversation", AgentSheet.shape(facts(kind: "note", turns: 4)) == nil)

print("")
print("Turns — the wire format four importers write")

let gptChat = """
You: How should I structure the SwiftData migration?
ChatGPT: Lightweight is the only stage CloudKit mirrors.

So the question is whether the change can be expressed as one.
You: And a removed property?
ChatGPT: That is a new-field-plus-backfill problem.
"""

let parsed = AgentSheet.turns(gptChat, assistant: "ChatGPT")
check("four turns are recovered", parsed.count == 4)
check("the first turn is yours", parsed.first?.voice == .you)
check("the second turn is the assistant's", parsed[1].voice == .assistant)
check("the assistant is named as the importer wrote it", parsed[1].name == "ChatGPT")
// THE HEADLINE PARSE RULE. A message's own text contains newlines, so a new
// turn begins only at a KNOWN SPEAKER — splitting on every newline is what
// `ChatBubbles` does, and it is why a paragraph break inside an answer reads as
// a new message.
check("a paragraph break inside an answer stays inside that answer",
      parsed[1].text.contains("So the question is whether"))
check("the speaker prefix is removed from the words",
      parsed.first?.text == "How should I structure the SwiftData migration?")

// Claude Code writes the same format with a blank line between turns, and
// labels its assistant "Claude" — NOT "Claude Code". Assuming the seat's name
// is the speaker's name is how this whole parse silently returns nothing.
let session = "You: Chase the embedding race\n\nClaude: Two threads, one model object."
check("Claude Code's transcript parses", AgentSheet.turns(session, assistant: "Claude").count == 2)
check("Claude Code's assistant label is Claude, not Claude Code",
      AgentSheet.assistant(for: "Claude Code") == "Claude")
check("each import seat resolves its own assistant",
      AgentSheet.assistant(for: "ChatGPT") == "ChatGPT"
        && AgentSheet.assistant(for: "Claude") == "Claude"
        && AgentSheet.assistant(for: "Gemini") == "Gemini")

// THE SAFE NIL. With no label only "You" would split, and the assistant's words
// would be folded into the reader's turn — a stranger's words under your own
// name. Nothing is drawn rather than that.
check("an unknown source parses no turns at all",
      AgentSheet.turns(gptChat, assistant: AgentSheet.assistant(for: "Slack")).isEmpty)
check("an empty transcript parses nothing", AgentSheet.turns("", assistant: "Claude").isEmpty)
check("a transcript in no known format parses nothing",
      AgentSheet.turns("just some prose\nover two lines", assistant: "Claude").isEmpty)
// Prose before the first speaker cannot be attributed, so it is dropped rather
// than folded into somebody's turn.
check("unattributable prose ahead of the first speaker is dropped",
      AgentSheet.turns("preamble\nYou: hello", assistant: "Claude").count == 1)
// The space after the colon is required — both writers emit one, and without it
// a line reading "You:me" would open a turn.
check("a colon with no space does not open a turn",
      AgentSheet.turns("You:no space here", assistant: "Claude").isEmpty)

print("")
print("Cut — what the clamp took, from two numbers already on the row")

check("a clamped chat reports what is missing", AgentSheet.cut(counted: 84, shown: 55) == 29)
check("an unclamped chat reports nothing", AgentSheet.cut(counted: 12, shown: 12) == nil)
// The one that matters most: with NO readable transcript, a count says nothing
// about a clamp. Claiming "84 turns not shown" over a row that simply has no
// stored body is a claim about something that never ran.
check("no parsed turns means no claim about a clamp",
      AgentSheet.cut(counted: 84, shown: 0) == nil)
check("no count means no claim about a clamp", AgentSheet.cut(counted: nil, shown: 6) == nil)
check("a count below the parse is not reported as a cut",
      AgentSheet.cut(counted: 3, shown: 6) == nil)

print("")
print("The conversation reading")

func convo(source: String = "ChatGPT", title: String, ask: String? = nil,
           transcript: String? = nil, project: String? = nil, counted: Int? = nil,
           growing: Bool = false) -> AgentSheet.Conversation {
    AgentSheet.conversation(.init(source: source, title: title, ask: ask,
                                  transcript: transcript, project: project,
                                  counted: counted, opened: nil, growing: growing))
}

// The conversation's own NAME leads — it is what the export called it and what
// the row shows. The ask is the first turn, not the headline.
let named = convo(title: "SwiftData migration plan",
                  ask: "How should I structure the SwiftData migration?",
                  transcript: gptChat, counted: 4)
check("the export's own name is the hero", named.hero == "SwiftData migration plan")
check("the ask stays in the turns", named.turns.count == 4)
check("nothing is reported as cut when nothing was", named.cut == nil)

// THE PROVEN EXCEPTION: where the title is a CLAMP of the ask, the ask replaces
// it, because the two are the same string and one of them is whole. This is
// every Gemini row (`titleLine(ask)`).
let long = "Summarise this paper for someone who knows the field but not this subfield, and flag anything the abstract overstates"
let clamped = String(long.prefix(80)) + "…"
check("a clamped title gives way to the whole ask",
      convo(source: "Gemini", title: clamped, ask: long).hero == long)
// …and the floor keeps a real name from being replaced by a sentence that
// happens to start with it.
check("a short title that prefixes the ask is still the hero",
      convo(title: "Espresso", ask: "Espresso ratios and why 1:2 is the default").hero == "Espresso")
check("a title unrelated to the ask is kept",
      convo(title: "Naming things", ask: "What should I call the panel?").hero == "Naming things")

// A first turn that IS the hero is dropped — PROVEN, never sliced blind. Without
// it a chat whose title is its own ask prints the ask twice, once at display
// size and once as the opening bubble.
let echo = convo(source: "Gemini", title: clamped, ask: long,
                 transcript: "You: \(long)", counted: 1)
check("a first turn that repeats the hero is dropped", echo.turns.isEmpty)
// The cut is measured against the FULL parse, never the drawn list. A fixture
// where the two differ is the only thing that can prove it: dropping the
// duplicate opening turn must not make the sheet report a turn as missing.
let dropped = convo(title: clamped, ask: long,
                    transcript: "You: \(long)\nChatGPT: a reply\nYou: a follow-up",
                    counted: 3)
check("dropping the duplicate leaves two turns drawn", dropped.turns.count == 2)
check("dropping the duplicate does not invent a missing turn", dropped.cut == nil)
check("dropping it does not make the sheet claim a cut", echo.cut == nil)

// ONE-SIDED, by construction and never by source name: Takeout carries the
// prompt and has no field for the reply.
check("a transcript with no assistant turn reads as one-sided", echo.oneSided)
check("a two-sided transcript does not", !named.oneSided)
check("an unparsed transcript is not called one-sided",
      !convo(title: "x", counted: 9).oneSided)

// The project comes off a stored tag and is stripped from the title only when
// it really is the prefix.
let cc = convo(source: "Claude Code", title: "casberi · Chase the embedding race",
               project: "casberi", counted: 61, growing: true)
check("the project moves out of the headline", cc.hero == "Chase the embedding race")
check("the project is stated as its own fact", cc.project == "casberi")
check("a title that does not carry the project is left whole",
      convo(title: "Chase · the race", project: "casberi").hero == "Chase · the race")
check("no project means no strip",
      AgentSheet.stripProject("casberi · Chase the race", project: nil)
        == "casberi · Chase the race")

// The sentence. Dateless on purpose — no chat importer lands an
// `ImportReceipt`, so there is no stored read-date to state.
check("an export says which export", named.provenance == "From your ChatGPT export.")
check("a growing source says that it grows",
      cc.provenance == "From your Claude Code history. Sessions grow — re-importing updates this one in place.")

print("")
print("Grant — a permission with a clock")

let now = Date(timeIntervalSince1970: 1_786_000_000)
func grant(path: String? = "openai/*", vault: String? = "personal",
           permissions: [String] = ["read", "list"],
           granted: Date? = nil, expires: Date? = nil,
           title: String = "personal · openai/* · read, list") -> AgentSheet.Grant {
    AgentSheet.grant(.init(title: title, path: path, vault: vault,
                           permissions: permissions, granted: granted,
                           expires: expires, now: now))
}

check("the path is the stored field, not a split title", grant().path == "openai/*")
// A row landed before the parts were stamped shows the string it has always
// shown, WHOLE — never a guess made by splitting on a separator.
check("a grant with no stamped path falls back to the whole title",
      grant(path: nil).path == "personal · openai/* · read, list")
check("an empty stamped path falls back too", grant(path: "   ").path
        == "personal · openai/* · read, list")
check("the permissions ride through in the API's own words",
      grant().permissions == ["read", "list"])

// MOST GRANTS HAVE NO CLOCK, and none of the three clock facts may appear for
// them: a bar drawn against a guessed end date is an invented fact.
let open = grant()
check("a grant with no expiry has no status", open.status == nil)
check("a grant with no expiry is not urgent", !open.urgent)
check("a grant with no expiry has no runway", open.fraction == nil)

let day = 86_400.0
check("a grant expiring in six days says so and is urgent",
      grant(expires: now + 6 * day).status == "Expires in 6 days"
        && grant(expires: now + 6 * day).urgent)
// The day boundary, not raw seconds: a grant expiring at 09:00 tomorrow is
// "tomorrow" all of today, and "in 0 days" at 10:00 is the true-but-useless
// number a receipt exists to replace.
check("a grant expiring tomorrow says tomorrow",
      grant(expires: now + day).status == "Expires tomorrow")
check("a grant expiring today says today",
      grant(expires: now + 600).status == "Expires today")
// THE DAY BOUNDARY, and the only fixture that can prove it: late tonight,
// expiring at nine tomorrow morning. That is ten hours away, so a raw-seconds
// read calls it "today" — on the evening when acting on it still would have
// been possible, and the morning it is already gone.
let midnight = Calendar.current.startOfDay(for: now)
check("ten hours across midnight reads as tomorrow, not today",
      AgentSheet.expiry(midnight.addingTimeInterval(33 * 3600),
                        now: midnight.addingTimeInterval(23 * 3600))?.text
        == "Expires tomorrow")
check("twenty-one hours inside one day is still today",
      AgentSheet.expiry(midnight.addingTimeInterval(22 * 3600),
                        now: midnight.addingTimeInterval(3600))?.text == "Expires today")
check("an expired grant says so", grant(expires: now - day).status == "Expired")
check("an expired grant is urgent", grant(expires: now - day).urgent)
// Two weeks is the window a deadline can still be acted on. Beyond it the clock
// is a fact, not an alarm.
check("a grant expiring in thirty days is not urgent",
      !grant(expires: now + 30 * day).urgent)
check("a grant expiring in exactly fourteen days is urgent",
      grant(expires: now + 14 * day).urgent)

// The runway needs BOTH ends known, and never leaves its bar.
check("a runway needs both ends",
      grant(granted: nil, expires: now + 6 * day).fraction == nil
        && grant(granted: now - day, expires: nil).fraction == nil)
let half = grant(granted: now - 5 * day, expires: now + 5 * day).fraction
check("a half-spent grant reads as half", half != nil && abs(half! - 0.5) < 0.001)
check("an expired grant's runway is full, never past it",
      grant(granted: now - 10 * day, expires: now - day).fraction == 1)
check("a grant that has not started reads as empty, never negative",
      grant(granted: now + day, expires: now + 10 * day).fraction == 0)
check("a zero-length grant draws no runway",
      grant(granted: now, expires: now).fraction == nil)

print("")
print("exchanges — turns as PAIRS, for carrying a conversation on (2026-08-20)")
func turn(_ voice: AgentSheet.Turn.Voice, _ text: String) -> AgentSheet.Turn {
    AgentSheet.Turn(voice: voice, name: voice == .you ? "You" : "Claude", text: text)
}
let straight = [turn(.you, "how do I center a div"), turn(.assistant, "Use flexbox."),
                turn(.you, "and vertically?"), turn(.assistant, "align-items: center.")]
let paired = AgentSheet.exchanges(straight)
check("a two-exchange chat yields two pairs", paired.history.count == 2)
check("each pair is its own ask and its own answer",
      paired.history[0].question == "how do I center a div"
      && paired.history[0].answer == "Use flexbox.")
check("nothing is pending when the agent spoke last", paired.pending == nil)
// The clamp keeps the OLDEST end, so a transcript can open on an answer whose
// question was cut. Inventing one would send words to a provider as the
// person's own — the most expensive thing this pairing could get wrong.
let orphaned = AgentSheet.exchanges([turn(.assistant, "as I was saying"),
                                     turn(.you, "go on"), turn(.assistant, "right")])
check("an opening answer with no question is DROPPED, never given one",
      orphaned.history.count == 1 && orphaned.history[0].question == "go on")
// Two asks in a row — all four of these products allow it. The answer replies
// to the LATEST one.
let doubled = AgentSheet.exchanges([turn(.you, "first"),
                                    turn(.you, "actually, this instead"),
                                    turn(.assistant, "ok")])
check("consecutive asks pair the LATEST with the answer",
      doubled.history.count == 1 && doubled.history[0].question == "actually, this instead")
// A trailing ask is not half a pair — it is the thing to continue with.
let trailing = AgentSheet.exchanges([turn(.you, "hi"), turn(.assistant, "hello"),
                                     turn(.you, "one more thing")])
check("a trailing ask is not folded into history", trailing.history.count == 1)
check("…it is returned as the pending ask", trailing.pending == "one more thing")
check("an empty transcript yields nothing to carry on",
      AgentSheet.exchanges([]).history.isEmpty && AgentSheet.exchanges([]).pending == nil)

print("")
print("continuationInstructions — a clamped transcript SAYS it is clamped")
let whole = AgentSheet.continuationInstructions(source: "ChatGPT", cut: nil)
let clipped = AgentSheet.continuationInstructions(source: "ChatGPT", cut: 84)
check("both name the product the conversation came from",
      whole.contains("ChatGPT") && clipped.contains("ChatGPT"))
// Handing a model 8,000 characters of a long chat without saying so invites it
// to answer as though it had read the rest.
check("a complete transcript makes no excuse", !whole.contains("NOT here"))
check("a clamped one says how much is missing", clipped.contains("84"))
check("…and the two really differ, or the argument does nothing", whole != clipped)
check("a zero cut is not a cut", AgentSheet.continuationInstructions(source: "Claude", cut: 0) ==
      AgentSheet.continuationInstructions(source: "Claude", cut: nil))

print("")
if failures > 0 { print("agent-sheet-selftest: ✗ \(failures) assertion(s) failed"); exit(1) }
print("agent-sheet-selftest: OK — every assertion passed against the shipped source.")
SWIFT

# `-Onone`, not `-O`: 97% of a pure-logic harness's wall time is the optimizer,
# and it buys nothing an assertion can see. NOT a blanket rule — `-O` can change
# a harness's OBSERVABLE behaviour (a trapping one prints NOTHING under `-O`) —
# so this file was proven equivalent run-for-run by
# `scripts/support/harness-opt-probe.sh` before the swap (2026-09-05, 2.2x faster).
# Re-probe before trusting it again after adding mutations.
if ! swiftc -Onone -o "$TMP/as-selftest" "$SHEET" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ harness failed to compile against the shipped source"
  grep -E 'error:' "$TMP/build.log" | head -20
  exit 1
fi
echo ""
"$TMP/as-selftest"

# --- mutations --------------------------------------------------------------
# A check that cannot fail proves nothing. Each mutation below is a plausible
# "simplification" of the shipped logic, and each must break at least one
# assertion above.
echo ""
echo "Mutations (each must break something)"

mutate() {
  local name="$1" from="$2" to="$3"
  local a="$TMP/mut.swift"
  cp "$SHEET" "$a"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$a" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$a"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -Onone -o "$TMP/mut" "$a" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# THE SEAT NAME IS NOT THE SPEAKER NAME. This is the single likeliest mistake in
# the file, and it fails silently: the parse returns nothing and the sheet falls
# back to exactly the one-line rendering this pass exists to end.
mutate "Claude Code's assistant becomes its seat name" \
  'case "Claude Code": return "Claude"' \
  'case "Claude Code": return "Claude Code"'
# The parse rule itself — splitting on every newline is what ChatBubbles does.
mutate "a paragraph break opens a new turn" \
  '} else if !out.isEmpty {
                out[out.count - 1].text += "\n" + line' \
  '} else if !out.isEmpty {
                out.append(Turn(voice: out[out.count - 1].voice,
                                name: out[out.count - 1].name, text: line))'
# The safe nil: with no label, a two-party chat collapses into one turn
# attributed to the reader.
mutate "an unknown source folds the assistant into your own turn" \
  'guard let transcript, !transcript.isEmpty, let assistant else { return [] }' \
  'guard let transcript, !transcript.isEmpty else { return [] }
        let assistant = assistant ?? "\u{0}"'
# NOTE — localizing `readerLabel` is NOT mutated here, and the reason is worth
# recording: `String(localized: "You")` in a harness with no bundle resolves to
# "You", so the mutation runs green while being exactly the bug. It is a lie a
# runtime test structurally cannot catch, which is why it is a negative GREP
# guard above instead. Do not "fix" this by adding the mutation back.
#
# The clamp clause, claimed over a row that has no stored transcript at all.
mutate "a count with no transcript claims a clamp" \
  'guard let counted, shown > 0, counted > shown else { return nil }' \
  'guard let counted, counted > shown else { return nil }'
# …and computed against the DRAWN list, so dropping a duplicate first turn
# invents a missing one.
mutate "the cut is measured against the drawn turns" \
  'cut: cut(counted: i.counted, shown: parsed.count)' \
  'cut: cut(counted: i.counted, shown: drawn.count)'
# The hero: without the clamp test, Gemini's rows keep an 80-character stub.
mutate "the clamped title is never replaced by the whole ask" \
  'return isClamp(named, of: ask) ? ask : named' \
  'return named'
# …and without the floor, a real conversation name is replaced by a sentence
# that happens to start with it.
mutate "any prefix counts as a clamp" \
  'guard core.count >= 24, full.count > core.count else { return false }' \
  'guard full.count > core.count else { return false }'
# The duplicate-drop, unproven: it would cut a real opening turn.
mutate "the first turn is dropped without proving it is the hero" \
  'if let first = drawn.first, first.voice == .you,
           first.text.trimmingCharacters(in: .whitespacesAndNewlines) == hero {' \
  'if let first = drawn.first, first.voice == .you, !first.text.isEmpty {'
# The project strip, taken from the first separator instead of the stored field.
mutate "the project is sliced at the first separator" \
  'guard title.hasPrefix(prefix) else { return title }' \
  'guard let r = title.range(of: " · ") else { return title }
        _ = prefix
        return String(title[r.upperBound...])'
# Shape: social must be asked first, or a Snapchat thread wears two anatomies.
mutate "the social shape stops winning a chat" \
  'guard !f.socialShaped, f.kind == "chat" else { return nil }' \
  'guard f.kind == "chat" else { return nil }'
# …and a bare `.chat` with nothing in it becomes a conversation, which is every
# Slack message and every Stocktwits post in the corpus.
mutate "any chat becomes a conversation" \
  'return (f.turns > 0 || f.counted != nil) ? .conversation : nil' \
  'return .conversation'
# The grant must be decided before the kind, since its kind is what was drawing
# the wrong noun.
mutate "the grant ref stops leading" \
  'if f.grantRef { return .grant }' \
  'if f.grantRef, f.kind == "reminder" { return .grant }'
# The path, guessed by splitting the display title instead of read from a field.
mutate "the grant path is split out of the title" \
  'path: path ?? i.title' \
  'path: path ?? String(i.title.split(separator: "·").dropFirst().first ?? "")'
# The clock, at the day boundary. Raw seconds makes tomorrow-at-09:00 read as
# "in 0 days" from 10:00 this morning.
mutate "the expiry counts raw days instead of day boundaries" \
  'let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: now),
                                      to: cal.startOfDay(for: expires)).day ?? 0' \
  'let days = Int(expires.timeIntervalSince(now) / 86_400)'
# The urgency window, and the expired case that must always wear it.
mutate "an expired grant stops being urgent" \
  'if expires <= now { return (String(localized: "Expired"), true) }' \
  'if expires <= now { return (String(localized: "Expired"), false) }'
mutate "every dated grant is urgent" \
  'default:   return (String(localized: "Expires in \(days) days"), days <= urgentDays)' \
  'default:   return (String(localized: "Expires in \(days) days"), true)'
# The runway clamp — an expired grant would draw past the end of its own bar.
# An orphaned answer given an invented question — somebody else's words sent to
# a provider as the person's own.
mutate "an answer with no question is paired anyway" \
  '} else if let asked = question {' \
  '} else if let asked = question ?? Optional("") {'

# The pending ask swallowed into history: the one thing a continuation is for
# goes missing, and the conversation resumes with nothing asked.
mutate "the pending ask is dropped" \
  'return (history, question)' \
  'return (history, nil)'

# The clamp goes unmentioned and the model answers half a conversation as
# though it had all of it.
mutate "a clamped transcript stops saying so" \
  'if let cut, cut > 0 {' \
  'if let cut, cut < 0 {'

mutate "the runway is not clamped" \
  'return min(max(done, 0), 1)' \
  'return done'

# ============================================================================
# THE SECOND HARNESS — `AgentSheetSource`, against the REAL `Thing`
# ============================================================================
# Everything above builds its fixtures by hand: `facts(kind:turns:)`,
# `convo(title:project:)`, `grant(permissions:)`. That is right for
# `AgentSheet`, which only ever sees values somebody passes it — but it is
# structurally blind to `AgentSheetSource`, whose whole job is deciding WHICH
# values to pass. A hand-built fixture is the author's belief about what a row
# carries, so it agrees with the reader by construction, and the two defects
# this section exists for lived in that gap from §367 until 2026-09-19:
#
#   · `project(for:)` returned the string "Chat" for every agent row in the
#     corpus, because `Thing.init` prepends `kind.typeTag` and the filter only
#     excluded "Session". The conversation head read "in Chat" on every agent
#     sheet ever drawn, and Claude Code's real project reached neither the head
#     nor `stripProject`.
#   · `permissions(for:)` listed "Link" as a verb the key had been granted,
#     for the same reason.
#
# So these fixtures are built through the shipped `Thing.init` and read by the
# shipped `AgentSheetSource`, both compiled WHOLE AND UNMODIFIED. Only
# `SocialSheetSource` is stubbed — it is a different sheet's judgement with a
# harness of its own, and all this file needs from it is the boolean.
echo ""
echo "AgentSheetSource — the shipped readers, over things built by Thing.init"

mkdir -p "$TMP/src"
cat > "$TMP/src/Stubs.swift" <<'SWIFT'
import Foundation

/// `SocialSheetSource`'s judgement belongs to `social-sheet-selftest.sh`.
/// `AgentSheetSource` asks it one question — "does this row already have a
/// social anatomy?" — and only the answer matters here, so the stub is a set
/// of ids the fixtures opt into. Deliberately NOT keyed on source or kind: a
/// stub that re-derived the real rule could drift away from it silently and
/// would be testing itself.
enum SocialSheetSource {
    static var shaped: Set<UUID> = []
    static func shape(for thing: Thing) -> Int? { shaped.contains(thing.id) ? 1 : nil }
}
SWIFT

cat > "$TMP/src/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}

// The four seats, EXACTLY as their importers call the initializer. Nothing is
// assembled by hand and nothing is assigned to `tags` afterwards — the point
// of this whole section is that only `Thing.init` knows what is stored.
//
// ChatGPT, Claude and Gemini pass no tags at all; `ClaudeCodeImport` passes
// `["Session", <project>]` (or `["Session"]` alone when the export names no
// project). See `ClaudeCodeImport.swift`'s `tags:` argument.
func chat(_ source: String, title: String, tags: [String] = []) -> Thing {
    Thing(kind: .chat, title: title, source: source, tags: tags)
}

// THE MECHANISM, asserted before anything that depends on it. If this line
// ever stops being true the two readings below are testing a fiction, and the
// failure should say which fact moved rather than which reading broke.
let plain = chat("ChatGPT", title: "SwiftData migration plan")
check("Thing.init prepends the kind's type tag, so a no-tag chat stores [\"Chat\"]",
      plain.tags == ["Chat"])
let session = chat("Claude Code", title: "casberi · Chase the embedding race",
                   tags: ["Session", "casberi"])
check("…and a Claude Code session stores [\"Chat\", \"Session\", <project>]",
      session.tags == ["Chat", "Session", "casberi"])

print("")
print("project(for:) — the tag that is neither the facet nor the type")

// THE FIRST SHIPPED DEFECT. "Chat" is not a project, and a head that says
// "in Chat" is §83's fake status: a fact stated with total confidence about a
// row that carries no project at all.
check("a ChatGPT chat has no project, and certainly not \"Chat\"",
      AgentSheetSource.project(for: plain) == nil)
check("a Claude chat has no project either",
      AgentSheetSource.project(for: chat("Claude", title: "Espresso ratios")) == nil)
check("a Gemini chat has no project either",
      AgentSheetSource.project(for: chat("Gemini", title: "Summarise this paper")) == nil)
// …and the row that DOES carry one gets it. Before the fix this returned
// "Chat" here too, so the project never reached the head or `stripProject`.
check("a Claude Code session's project is the project",
      AgentSheetSource.project(for: session) == "casberi")
check("a session whose export named no project has none",
      AgentSheetSource.project(for: chat("Claude Code", title: "Chase the race",
                                         tags: ["Session"])) == nil)

// DERIVED FROM THE KIND, never matched against the literal "Chat" — which is
// the half that keeps this from coming back. A seat that starts landing its
// sessions under a different kind must not reintroduce the defect, and this
// is the only fixture that can tell the two spellings apart.
let noteSession = Thing(kind: .note, title: "casberi · a note-kind session",
                        source: "Claude Code", tags: ["Session", "casberi"])
check("the facet is the THING's own type tag, not the literal \"Chat\"",
      noteSession.tags == ["Note", "Session", "casberi"]
        && AgentSheetSource.project(for: noteSession) == "casberi")

print("")
print("permissions(for:) — the verbs, and nothing the initializer added")

// THE SECOND SHIPPED DEFECT, same cause: a grant is a `.link`, so "Link" was
// stored ahead of the verbs and listed to the reader as one of them — on the
// single surface whose entire job is "what can this agent reach".
let grantRow = Thing(kind: .link, title: "personal · openai/* · read, list",
                     source: "1Claw", tags: ["Grant", "read", "list"],
                     sourceRef: "1claw:policy:abc")
check("a grant row stores [\"Link\", \"Grant\", <verbs…>]",
      grantRow.tags == ["Link", "Grant", "read", "list"])
check("…and the permissions are the verbs alone",
      AgentSheetSource.permissions(for: grantRow) == ["read", "list"])
check("the row is still recognised as a grant by its ref",
      AgentSheetSource.isGrantRef(grantRow.sourceRef)
        && AgentSheetSource.shape(for: grantRow) == .grant)
// Derived from the kind here too.
let notedGrant = Thing(kind: .note, title: "a note-kind grant", source: "1Claw",
                       tags: ["Grant", "read"], sourceRef: "1claw:policy:def")
check("the facet is the THING's own type tag, not the literal \"Link\"",
      AgentSheetSource.permissions(for: notedGrant) == ["read"])

print("")
print("The consequence — the reading the head actually draws")

// END TO END, and the reason both defects were worth a harness: every
// assertion above is about a string, and this is about the sentence a person
// reads. `AgentConversationHead` draws `reading.project` as "in <project>".
let readCode = AgentSheetSource.conversation(for: session)
check("the head names the real project", readCode.project == "casberi")
check("…and it comes out of the headline, which needed the real project",
      readCode.hero == "Chase the embedding race")
let readGPT = AgentSheetSource.conversation(for: plain)
check("a ChatGPT sheet names no project at all", readGPT.project == nil)
check("…and its title is untouched", readGPT.hero == "SwiftData migration plan")

// The grant's half of the same sentence: `AgentGrantView` draws
// `grant.permissions` as the list of verbs the key holds, so this is the
// surface where "Link" was being read as something an agent had been allowed
// to do. `grant(for:)` is `@MainActor` and top-level code here is NOT
// main-actor isolated (measured — it is a compile error), so the hop is
// asserted rather than awaited: this runs on the main thread, and the sheet
// it stands in for is a view body, which does too.
let readGrant = MainActor.assumeIsolated {
    AgentSheetSource.grant(for: grantRow, now: Date(timeIntervalSince1970: 1_786_000_000))
}
check("the grant view is handed the verbs alone",
      readGrant.permissions == ["read", "list"])

// The social hand-off, through the real reader: a row another sheet has
// already shaped gets no agent anatomy, whatever its tags say.
// Counted rather than transcribed on purpose: `AgentSheet.assistant` knows no
// label for Snapchat, so a stored transcript would parse to nothing and the
// row would have no shape for the social sheet to take away.
let dm = chat("Snapchat", title: "a saved chat")
dm.messageCount = 40
check("a chat with a counted transcript is a conversation",
      AgentSheetSource.shape(for: dm) == .conversation)
SocialSheetSource.shaped.insert(dm.id)
check("…until the social sheet claims it", AgentSheetSource.shape(for: dm) == nil)

print("")
if failures > 0 {
    print("agent-sheet-selftest: ✗ \(failures) source assertion(s) failed"); exit(1)
}
print("agent-sheet-selftest: OK — AgentSheetSource reads real Thing rows correctly.")
SWIFT

SRC_UNITS=("$THING" "$SHEET" "$SOURCE" "$TMP/src/Stubs.swift" "$TMP/src/main.swift")
if ! swiftc -Onone -o "$TMP/src-selftest" "${SRC_UNITS[@]}" 2>"$TMP/src-build.log"; then
  echo "✗ the source harness failed to compile against the shipped source"
  grep -E 'error:' "$TMP/src-build.log" | head -20
  exit 1
fi
"$TMP/src-selftest"

# --- mutations, over BOTH shipped files -------------------------------------
# The first harness mutates `AgentSheet.swift` alone. These mutate the reader
# and the initializer, because the defect lived in the RELATIONSHIP between
# them: either file alone reads correctly.
echo ""
echo "Mutations — AgentSheetSource and Thing (each must break something)"

mutate_src() {  # name, file-to-mutate, from, to
  local name="$1" target="$2" from="$3" to="$4"
  local work="$TMP/srcmut"
  rm -rf "$work"; mkdir -p "$work"
  cp "$THING" "$work/Thing.swift"
  cp "$SHEET" "$work/AgentSheet.swift"
  cp "$SOURCE" "$work/AgentSheetSource.swift"
  local a
  case "$target" in
    thing)  a="$work/Thing.swift" ;;
    source) a="$work/AgentSheetSource.swift" ;;
    *) echo "  ✗ $name — unknown mutation target '$target'"; exit 1 ;;
  esac
  local rc=0
  MUT_FROM="$from" MUT_TO="$to" python3 - "$a" <<'PY' || rc=$?
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if src.count(frm) != 1:
    sys.stderr.write("ANCHOR-%d\n" % src.count(frm)); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  # A mutation that did not APPLY reports SURVIVED forever after the source
  # moves under it, so the applier is pinned, not the detector.
  if [[ $rc -ne 0 ]] || ! grep -qF -- "$to" "$a"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -Onone -o "$work/mut" "$work/Thing.swift" "$work/AgentSheet.swift" \
       "$work/AgentSheetSource.swift" "$TMP/src/Stubs.swift" "$TMP/src/main.swift" \
       2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$work/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# THE TWO SHIPPED DEFECTS, restored exactly. If either of these survives, this
# whole section is decoration.
mutate_src "project stops excluding the type tag (the shipped defect)" source \
  '        let facet = thing.kind.typeTag
        return thing.tags.first { $0 != "Session" && $0 != facet && !$0.isEmpty }' \
  '        return thing.tags.first { $0 != "Session" && !$0.isEmpty }'
mutate_src "permissions stop excluding the type tag (the shipped defect)" source \
  '        let facet = thing.kind.typeTag
        return thing.tags.filter { $0 != "Grant" && $0 != facet && !$0.isEmpty }' \
  '        return thing.tags.filter { $0 != "Grant" && !$0.isEmpty }'

# The literal spelling, which reads identically on every row shipping today
# and is exactly how this class comes back.
mutate_src "project hard-codes \"Chat\" instead of reading the kind" source \
  '        let facet = thing.kind.typeTag
        return thing.tags.first { $0 != "Session" && $0 != facet && !$0.isEmpty }' \
  '        return thing.tags.first { $0 != "Session" && $0 != "Chat" && !$0.isEmpty }'
mutate_src "permissions hard-code \"Link\" instead of reading the kind" source \
  '        let facet = thing.kind.typeTag
        return thing.tags.filter { $0 != "Grant" && $0 != facet && !$0.isEmpty }' \
  '        return thing.tags.filter { $0 != "Grant" && $0 != "Link" && !$0.isEmpty }'

# …and the other end of the relationship. This one proves the FIXTURES: if
# removing the prepend leaves the harness green, the things are not going
# through `Thing.init` at all and the section above proves nothing.
mutate_src "Thing.init stops prepending the type tag" thing \
  '        self.tags = ([kind.typeTag] + tags).reduced()' \
  '        self.tags = tags.reduced()'

# The hand-off itself: `AgentSheetSource` is the only place that asks the
# social sheet first, so a row with two anatomies is a defect only this file
# can introduce.
mutate_src "the source stops asking the social sheet" source \
  'socialShaped: SocialSheetSource.shape(for: thing) != nil,' \
  'socialShaped: false,'

echo ""
echo "agent-sheet-selftest: OK — assertions and mutations both pass."
