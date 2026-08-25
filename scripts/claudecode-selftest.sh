#!/bin/zsh
# Casberi Claude Code self-test — the SHIPPED pure logic behind the Claude Code
# import seat (2026-08-08):
#
#   Casberi/Casberi/Model/ClaudeCodeImport.swift
#     — enum ClaudeCodeSession, compiled WHOLE and unmodified (it is
#       Foundation-only by design, which is exactly why it is a separate type
#       from the SwiftData landing beside it in the same file)
#
# WHY A HARNESS AND NOT A SIM CHECK, AND WHY IT MATTERS MORE HERE THAN USUAL.
# This importer was authored WITHOUT EVER READING A REAL TRANSCRIPT — the
# session that wrote it was refused access to `~/.claude/projects` by its own
# permission classifier — so every field name in it is doc-derived. That is the
# same standing as the Stripe, PostHog and Cursor bridges, with one difference
# that makes this harness the strongest proof available rather than a
# supplement: those bridges can be measured by anyone willing to mint a key,
# and this one can be measured by anyone who opens a folder. Nobody has.
#
# Every failure mode here is a SILENT WRONG ANSWER that renders perfectly:
#   · tool traffic landing as prose, so every session matches every query
#     (§313's `t.co` cell, in a corpus of conversations)
#   · a session dated `.now` because the timestamp spelling drifted, so a
#     year of history arrives claiming to be today
#   · a project name guessed off the lossy directory encoding, filing somebody's
#     sessions under a name they never used
#   · a headline that trails the project name and is eaten by `titleLine`'s
#     80-char clamp (§303), so a room of four hundred rows says one word
# None of those crash, none fail a build, and none can be seen on screen —
# `enrichedText` is retrieval-only by the 2026-07-15 ruling, so the transcript
# is invisible whether it is right, wrong or missing.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/ClaudeCodeImport.swift"
SCREEN="Casberi/Casberi/Screens/ClaudeCodeImportScreen.swift"
SUPPORT="Casberi/Casberi/Model/IngestSupport.swift"
CATALOG="Casberi/Casberi/Model/BridgeCatalog.swift"
ROUTING="Casberi/Casberi/Model/BridgeRouting.swift"
for f in "$SRC" "$SCREEN" "$SUPPORT" "$CATALOG" "$ROUTING"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- drift guards -----------------------------------------------------------
# Each of these is a wiring fact the compiled functions below cannot prove on
# their own: a perfect `title` is worthless if the landing half stops calling
# it, and a perfect `blockText` is worthless if the transcript stops reaching
# the field that feeds retrieval.
#
# The negative guards read a COMMENT-STRIPPED copy, because this file
# DOCUMENTS the things it must never do ("a message-per-row import would bury
# the corpus", "a wrong answer here is not a wrong DATE") — a guard grepping
# raw source fires against the prose explaining it. That lesson is the
# Obsidian/Cursor one and it has been earned three times.
# The `XXXXXX` must be the LAST thing in a mktemp template: BSD mktemp (what
# macOS ships) only substitutes a trailing run of X's, so the old
# `…stripped.XXXXXX.swift` was taken LITERALLY — it created a real file named
# with six capital X's, and because a `.swift` suffix is required here (swiftc
# refuses to compile anything else) the X's could not simply be moved to the
# end. A run killed before its EXIT trap fires — which is every run this
# harness's own verify.sh kills, and several were killed this week — then
# leaves that fixed name behind, and EVERY later run dies on
# `mkstemp failed: File exists`, reporting a broken import self-test when
# nothing about the import changed. A temp DIRECTORY takes the trailing X's
# correctly and the file inside it can keep its required extension.
STRIPPED_DIR=$(mktemp -d /tmp/claudecode-stripped.XXXXXX)
STRIPPED="$STRIPPED_DIR/stripped.swift"
trap 'rm -rf "$STRIPPED_DIR"' EXIT
python3 - "$SRC" "$STRIPPED" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r"^\s*//.*$", "", src, flags=re.M)
open(sys.argv[2], "w").write(src)
PY

grep -qF 'sourceRef: ref' "$SRC" \
  || { echo "✗ rows no longer carry a sourceRef — every import would re-land everything"; exit 1; }
grep -qF '"claudecode:\(parsed.sessionId)"' "$SRC" \
  || { echo "✗ the dedupe key moved off the session id"; exit 1; }
grep -qF 'kind: .chat' "$SRC" \
  || { echo "✗ a session is no longer a chat thing"; exit 1; }
grep -qF 'thing.enrichedText = parsed.transcript' "$SRC" \
  || { echo "✗ the transcript no longer reaches the retrieval body — the whole session becomes unsearchable, invisibly"; exit 1; }
grep -qF 'thing.messageCount = parsed.messageCount' "$SRC" \
  || { echo "✗ the real turn count is no longer stamped"; exit 1; }
# INVERTED (2026-08-24, prd §457, same day as the assertion it replaces). It
# used to demand `thing.summary = parsed.summary`; the field was measured
# always nil, and the session's own NAME became the headline, so stamping it
# too would print the title a second line below itself — the exact
# redundancy §451/§452 swept out of every other room. The source states this
# by name ("`Thing.summary` is deliberately NOT set"), so the negative check
# strips `//` comment lines first — a raw grep would fire on the very
# sentence explaining the retirement, not on a real regression (the
# Obsidian/Cursor lesson).
if grep -v '^\s*//' "$SRC" | grep -qF 'thing.summary = parsed.summary'; then
  echo "✗ Claude Code's session summary is back on Thing.summary — it would print the"
  echo "  headline a second line below itself (§457)"
  exit 1
fi
grep -qF 'capturedAt: parsed.startedAt ?? .now' "$SRC" \
  || { echo "✗ a session no longer carries its REAL start — a first import would fake a day of urgency"; exit 1; }
# The composition, at its call site. The Swift checks below prove that a
# trailing project name IS eaten by the clamp; only a text guard can say the
# shipped importer leads with it (the Cursor-selftest lesson: a guard must
# prove the real condition, not that the words appear somewhere).
grep -qF 'IngestSupport.titleLine(
                ClaudeCodeSession.title(project: parsed.project, headline: parsed.headline))' "$SRC" \
  || { echo "✗ the title no longer leads with the project through titleLine (§303's clamp ruling)"; exit 1; }
# ONE THING PER SESSION. A `Thing(` per turn is the failure this seat is shaped
# against, and it would look like a working import with a very full room.
python3 - "$STRIPPED" <<'PY' || exit 1
import sys
src = open(sys.argv[1]).read()
n = src.count("Thing(")
# `thing(from:)` builds exactly one, and `heal` builds none. Anything more is a
# second row per session (or per message).
if n != 1:
    sys.exit(f"✗ {n} Thing( constructions — a session must land as exactly one row")
PY
# Sessions GROW. Without the heal a re-import is worth nothing at all, and the
# screen's "N updated" clause would be permanently zero.
grep -qF 'if heal(already, with: parsed) { summary.healed += 1 }' "$SRC" \
  || { echo "✗ a session that grew is no longer updated in place — a re-import can never add the turns since"; exit 1; }
grep -qF 'thing.embedding = nil' "$SRC" \
  || { echo "✗ a healed session keeps a vector computed from words it no longer says"; exit 1; }
# The cap must COUNT what it refused, on all three surfaces (§307/§309).
grep -qF 'summary.dropped = max(0, ordered.count - ClaudeCodeSession.sessionCap)' "$SRC" \
  || { echo "✗ the cap no longer counts what it refused — a truncated import reads as a complete one"; exit 1; }
grep -qF 'summary.dropped > 0' "$SCREEN" \
  || { echo "✗ the screen no longer says an import was capped — the one moment the person could act on it"; exit 1; }
grep -qF 'await ImportCommit.commit' "$SRC" \
  || { echo "✗ a large import lands in one transaction again — that holds the main thread for the whole run (§310)"; exit 1; }
# The walk is bounded to two levels. A recursive enumerate over a home
# directory is a way to import files nobody meant to pick.
grep -qv 'enumerator(at:' "$STRIPPED" \
  || { echo "✗ the folder walk became recursive — it would reach files outside the pick"; exit 1; }
grep -qF '.jsonl' "$SRC" \
  || { echo "✗ the walk no longer filters to transcripts"; exit 1; }
# The seat, end to end. A screen nothing routes to is a screen nobody reaches.
grep -qF 'Offer(name: "Claude Code"' "$CATALOG" \
  || { echo "✗ Claude Code is not in the catalog — BridgeCatalog.offers is the single source of truth"; exit 1; }
grep -qF 'Row(offer: "Claude Code", id: "claudecode", destination: .claudeCode)' "$ROUTING" \
  || { echo "✗ the catalog offer routes nowhere"; exit 1; }
grep -qF 'case .claudeCode:     ClaudeCodeImportScreen()' "$ROUTING" \
  || { echo "✗ the destination opens no screen"; exit 1; }
grep -qF 'case .claudeCode:     "claudecode"' "$ROUTING" \
  || { echo "✗ the seat id is gone — destination(forID:) can never resolve it"; exit 1; }
grep -qF '.chatgpt, .claude, .claudeCode, .gemini, .instagram' "$ROUTING" \
  || { echo "✗ Claude Code no longer reads as a file import — AppDetailScreen would promise things arriving on their own"; exit 1; }
grep -qF 'mode: .oneTimeImport' "$SCREEN" \
  || { echo "✗ the setup screen lost its mode chip (setup-copy-audit's check 1)"; exit 1; }
grep -qF 'allowedContentTypes: [.folder]' "$SCREEN" \
  || { echo "✗ the pick is no longer a FOLDER — a session is one file among hundreds and picking them one at a time is not an import"; exit 1; }
grep -qF 'startAccessingSecurityScopedResource' "$SCREEN" \
  || { echo "✗ the folder is read without a security-scoped grant — every read fails on a sandboxed build"; exit 1; }
# The cap is a FLOOR, not an exact number — it should stay free to move, but
# never back under what a daily user of this tool accumulates in a year.
python3 - "$SRC" <<'PY' || exit 1
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r"let sessionCap = ([\d_]+)", src)
if not m:
    sys.exit("✗ sessionCap is gone — the landing bound is unreadable")
if int(m.group(1).replace("_", "")) < 1_000:
    sys.exit("✗ sessionCap is under 1,000 — a year of daily use lands truncated")
PY

TMP=$(mktemp -d /tmp/claudecode-selftest.XXXXXX)
trap 'rm -rf "$STRIPPED_DIR" "$TMP"' EXIT

# --- extract the shipped logic ---------------------------------------------
# `ClaudeCodeSession` is lifted WHOLE from the shipped file by brace matching —
# never a copy — so this harness cannot pass against logic the app does not
# run. The only transformation is stripping `private `.
python3 - "$SRC" "$SUPPORT" "$TMP/extracted.swift" <<'PY'
import sys
src_path, support, out = sys.argv[1:4]

def grab(path, signature):
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

pieces = [
    "import Foundation\n",
    grab(src_path, "enum ClaudeCodeSession {"),
    "",
    "enum IngestSupport {",
    grab(support, "static func titleLine"),
    "}\n",
]
open(out, "w").write("\n".join(pieces))
PY

# --- the driver -------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}
typealias S = ClaudeCodeSession

func day(_ d: Date?) -> String {
    guard let d else { return "nil" }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f.string(from: d)
}
func jsonl(_ lines: [String]) -> String { lines.joined(separator: "\n") }

print("projectName — the one field a directory name cannot honestly give")
check("cwd wins over the directory",
      S.projectName(cwd: "/Users/x/Developer/casberi", directory: "-Users-x-Developer-other")
          == "casberi")
check("the directory is the fallback",
      S.projectName(cwd: nil, directory: "-Users-x-Developer-casberi") == "casberi")
check("a trailing separator on cwd is tolerated",
      S.projectName(cwd: "/Users/x/Developer/casberi/", directory: nil) == "casberi")
check("nothing at all yields nothing, never a guess",
      S.projectName(cwd: nil, directory: nil) == "")
check("the encoded path decodes",
      S.decodeProjectDirectory("-Users-x-Developer-foo") == "/Users/x/Developer/foo")
// THE LOSSY CASE, pinned deliberately. The encoding replaces every `/` with a
// `-`, so a project whose own folder has a dash in it is indistinguishable
// from one nested a level deeper — and there is no repair, which is exactly
// why `cwd` is preferred above. Pinned so that anyone who "fixes" the decode
// discovers the ambiguity here rather than in somebody's room.
check("a dashed project name is ambiguous, and the decode says so plainly",
      S.decodeProjectDirectory("-Users-x-my-project") == "/Users/x/my/project")
check("…so the guessed name is the last segment",
      S.projectName(cwd: nil, directory: "-Users-x-my-project") == "project")
check("…and cwd resolves it correctly",
      S.projectName(cwd: "/Users/x/my-project", directory: "-Users-x-my-project") == "my-project")
// A folder that isn't an encoded path is left ALONE — and the fixture must
// carry a dash, or it proves nothing: "casberi" survives an unguarded
// replace unchanged, which is how the first cut of this harness scored a
// deleted guard green.
check("a plain folder name is not an encoding and is left alone",
      S.decodeProjectDirectory("my-project") == "my-project")
check("…so its name is the whole folder, not its last word",
      S.projectName(cwd: nil, directory: "my-project") == "my-project")
check("lastComponent tolerates repeated separators",
      S.lastComponent(ofPath: "/Users//x///foo//") == "foo")
check("a rootless path yields nil", S.lastComponent(ofPath: "///") == nil)

print("\ntitle — the project LEADS (§303's clamp ruling)")
check("the project leads", S.title(project: "casberi", headline: "fix the flaky test")
          == "casberi · fix the flaky test")
check("no project → the bare headline", S.title(project: "", headline: "hello") == "hello")
check("no headline → the bare project", S.title(project: "casberi", headline: "") == "casberi")
check("a newline in the headline is flattened",
      !S.title(project: "casberi", headline: "a\nb").contains("\n"))
// The ruling AS A TEST. `titleLine` cuts at 80 characters, so the same facts
// composed the other way round lose the project entirely — and a room of four
// hundred rows all named "fix the flaky test…" is the failure.
let longHead = "why does the migration keep failing on the second run when the store has already been opened once"
let led = IngestSupport.titleLine(S.title(project: "casberi", headline: longHead))
let trailed = IngestSupport.titleLine(longHead + " · casberi")
check("a leading project survives the 80-char clamp", led.hasPrefix("casberi · "))
check("…and a trailing one is provably eaten", !trailed.contains("casberi"))

print("\nblockText — tool traffic is machinery, not writing")
check("a plain string is the content", S.blockText("just a string") == "just a string")
check("text blocks join",
      S.blockText([["type": "text", "text": "one"], ["type": "text", "text": "two"]])
          == "one\ntwo")
check("a tool_use block contributes nothing",
      S.blockText([["type": "tool_use", "name": "Edit", "input": ["path": "/a"]]]) == "")
check("a tool_result block contributes nothing",
      S.blockText([["type": "tool_result", "tool_use_id": "x", "content": "1000 lines"]]) == "")
// THE FIXTURE THAT SEPARATES THE TWO GUARDS, and the reason it is here: the
// first cut of this harness tested `tool_use` and `tool_result` only, and
// deleting the TYPE check left it green — both of those carry a tool field, so
// the second guard caught them and the mutation survived. A thinking block
// carries `text` and nothing tool-shaped, so only the type check can refuse
// it. (It must be refused: reasoning is not what was said, and landing it puts
// words in somebody's mouth in a body that feeds every search.)
check("a thinking block is not what was said",
      S.blockText([["type": "thinking", "text": "weighing two approaches"]]) == "")
check("…even beside real prose",
      S.blockText([["type": "thinking", "text": "hmm"],
                   ["type": "text", "text": "here's the fix"]]) == "here's the fix")
check("mixed: only the prose survives",
      S.blockText([["type": "text", "text": "let me look"],
                   ["type": "tool_use", "name": "Read", "input": ["path": "/a"]],
                   ["type": "text", "text": "found it"]]) == "let me look\nfound it")
// An unknown block kind is more likely prose than a tool call, and if we are
// wrong the cost is one stray line in a body nothing displays.
check("a typeless block carrying text is read as prose",
      S.blockText([["text": "no type here"]]) == "no type here")
// …but a tool block that omits its type is still recognisable by what it
// carries. This is the case a type check alone cannot see.
check("a typeless block carrying tool fields is still refused",
      S.blockText([["text": "ok", "tool_use_id": "abc"]]) == "")
check("a typeless block carrying an input is still refused",
      S.blockText([["text": "ok", "input": ["path": "/a"]]]) == "")
check("an empty array is empty", S.blockText([[String: Any]]()) == "")
check("a shape we don't know yields nothing rather than garbage",
      S.blockText(42) == "")
check("nil content yields nothing", S.blockText(nil) == "")

print("\nrole — which lines are conversational at all")
check("message.role user", S.role(["message": ["role": "user"]]) == "user")
check("\"human\" is a user", S.role(["message": ["role": "human"]]) == "user")
check("message.role assistant", S.role(["message": ["role": "assistant"]]) == "assistant")
check("the line's own type stands in", S.role(["type": "user"]) == "user")
check("a capitalised key is read (field case varies within one file)",
      S.role(["Message": ["Role": "Assistant"]]) == "assistant")
check("a summary line is not a turn", S.role(["type": "summary", "summary": "x"]) == nil)
check("a system line is not a turn", S.role(["type": "system", "content": "hook fired"]) == nil)
check("an unknown type is not a turn", S.role(["type": "checkpoint"]) == nil)

print("\nstring — the tolerance every read goes through")
check("the first spelling wins",
      S.string(["timestamp": "a", "createdAt": "b"], S.dateKeys) == "a")
check("a later spelling is reached",
      S.string(["created_at": "b"], S.dateKeys) == "b")
check("a present-but-blank value is absent, never an empty title",
      S.string(["type": "   "], ["type"]) == nil)
check("a present-but-wrong-type value is absent, never coerced",
      S.string(["type": 7], ["type"]) == nil)

print("\nparseDate — a miss must be nil, never a plausible wrong date")
check("three fractional digits", day(S.parseDate("2026-08-08T09:41:00.123Z"))
          == "2026-08-08 09:41:00")
check("six fractional digits (the fraction strip)",
      day(S.parseDate("2026-08-08T09:41:00.123456Z")) == "2026-08-08 09:41:00")
check("one fractional digit", day(S.parseDate("2026-08-08T09:41:00.1Z"))
          == "2026-08-08 09:41:00")
check("no fraction at all", day(S.parseDate("2026-08-08T09:41:00Z"))
          == "2026-08-08 09:41:00")
check("a numeric offset in place of Z",
      day(S.parseDate("2026-08-08T09:41:00+00:00")) == "2026-08-08 09:41:00")
check("an offset that is not UTC is honoured, not assumed",
      day(S.parseDate("2026-08-08T11:41:00+02:00")) == "2026-08-08 09:41:00")
check("garbage is nil", S.parseDate("last Tuesday") == nil)
check("empty is nil", S.parseDate("") == nil)
check("nil is nil", S.parseDate(nil) == nil)

print("\nparse — a whole transcript")
let full = jsonl([
  #"{"type":"summary","summary":"Fixing the SwiftData liveness crash","leafUuid":"a"}"#,
  #"{"type":"user","sessionId":"11111111-2222-3333-4444-555555555555","cwd":"/Users/x/Developer/casberi","timestamp":"2026-08-01T10:00:00.000Z","message":{"role":"user","content":"why does the feed crash on refresh?"}}"#,
  #"{"type":"assistant","sessionId":"11111111-2222-3333-4444-555555555555","timestamp":"2026-08-01T10:00:05.000Z","message":{"role":"assistant","content":[{"type":"text","text":"Let me look at the ForEach."},{"type":"tool_use","name":"Read","input":{"path":"/FeedScreen.swift"}}]}}"#,
  #"{"type":"user","timestamp":"2026-08-01T10:00:09.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"1200 lines of Swift"}]}}"#,
  #"{"type":"system","timestamp":"2026-08-01T10:00:10.000Z","content":"PostToolUse hook"}"#,
  #"{"type":"assistant","timestamp":"2026-08-01T10:01:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"It reads a stored property off a deleted Thing."}]}}"#,
])
let parsed = S.parse(jsonl: full, fileName: "99999999-0000-0000-0000-000000000000.jsonl",
                     directory: "-Users-x-Developer-elsewhere")
check("a transcript parses", parsed != nil)
if let p = parsed {
    check("the summary line is the headline", p.headline == "Fixing the SwiftData liveness crash")
    check("the opener is kept apart from the headline",
          p.opener == "why does the feed crash on refresh?")
    check("the session id comes from the file's own field",
          p.sessionId == "11111111-2222-3333-4444-555555555555")
    check("cwd beats the directory for the project", p.project == "casberi")
    // The FIRST stamp. A session is dated by when it started, and the summary
    // line — which carries none — must not push the read past line one.
    check("dated from the FIRST timestamp", day(p.startedAt) == "2026-08-01 10:00:00")
    // Turns, not lines: the summary and system lines are not conversation, and
    // a turn spent entirely on tool traffic still happened.
    check("messageCount counts turns, not lines", p.messageCount == 4)
    check("the transcript names its speakers", p.transcript.contains("You: why does the feed"))
    check("…on both sides", p.transcript.contains("Claude: Let me look at the ForEach."))
    check("tool traffic is NOT in the retrieval body",
          !p.transcript.contains("1200 lines of Swift") && !p.transcript.contains("FeedScreen.swift"))
    check("the title composes project-first",
          S.title(project: p.project, headline: p.headline)
              == "casberi · Fixing the SwiftData liveness crash")
}

let unsummarised = jsonl([
  #"{"type":"user","sessionId":"abc","timestamp":"2026-07-04T08:00:00Z","message":{"role":"user","content":"add a probe hook for the sweep"}}"#,
  #"{"type":"assistant","timestamp":"2026-07-04T08:00:02Z","message":{"role":"assistant","content":"On it."}}"#,
])
let plain = S.parse(jsonl: unsummarised, fileName: "abc.jsonl", directory: "-Users-x-Developer-casberi")
check("with no summary line the opening ask is the headline",
      plain?.headline == "add a probe hook for the sweep")
check("…so the subtitle would repeat nothing", plain?.opener == plain?.headline)
check("the directory names the project when there is no cwd", plain?.project == "casberi")

// The filename is the last resort for identity — the file is named for the
// session, so a transcript that names itself nowhere inside is still landable.
let anonymous = #"{"type":"user","timestamp":"2026-07-04T08:00:00Z","message":{"role":"user","content":"hi"}}"#
check("the session id falls back to the filename stem",
      S.parse(jsonl: anonymous, fileName: "deadbeef-0000.jsonl", directory: nil)?.sessionId
          == "deadbeef-0000")
check("…and with neither, nothing is landed on a guess",
      S.parse(jsonl: anonymous, fileName: nil, directory: nil) == nil)

// A SKIP, not a failure. A folder holds files nobody meant to import.
check("a file with nothing conversational in it is skipped",
      S.parse(jsonl: #"{"type":"system","content":"hook"}"#, fileName: "x.jsonl", directory: nil) == nil)
check("an empty file is skipped", S.parse(jsonl: "", fileName: "x.jsonl", directory: nil) == nil)
check("a file of plain text is skipped",
      S.parse(jsonl: "not json at all\nnor this", fileName: "x.jsonl", directory: nil) == nil)
// One bad line must not cost the whole session.
let ragged = jsonl([
  "{ this is not json",
  "",
  "   ",
  #"{"type":"user","sessionId":"r1","timestamp":"2026-07-04T08:00:00Z","message":{"role":"user","content":"still here"}}"#,
])
check("a malformed line is skipped and the rest still parses",
      S.parse(jsonl: ragged, fileName: "r.jsonl", directory: nil)?.headline == "still here")

print("\nbudgets — one huge paste must not swallow the conversation")
let huge = String(repeating: "x", count: S.turnLimit + 500)
let hoggish = jsonl([
  "{\"type\":\"user\",\"sessionId\":\"h\",\"timestamp\":\"2026-07-04T08:00:00Z\",\"message\":{\"role\":\"user\",\"content\":\"\(huge)\"}}",
  #"{"type":"user","timestamp":"2026-07-04T08:00:01Z","message":{"role":"user","content":"and the actual question"}}"#,
])
let hog = S.parse(jsonl: hoggish, fileName: "h.jsonl", directory: nil)
check("a single turn is clamped", (hog?.transcript.count ?? 0) < S.turnLimit + 200)
check("…so the turns after it are still in the body",
      hog?.transcript.contains("and the actual question") == true)
check("the whole body is clamped too",
      S.transcript((0..<200).map { _ in S.Turn(role: "user", text: String(repeating: "y", count: 500)) })
          .count <= S.transcriptLimit + 1)
check("a clamp is MARKED, never a silently whole-looking string",
      S.clamp("abcdef", to: 3) == "abc…")
check("…and a string inside the budget is untouched", S.clamp("abc", to: 3) == "abc")
check("the session cap is a real bound", S.sessionCap >= 1_000)

print("")
if failures > 0 { print("claudecode-selftest: ✗ \(failures) assertion(s) failed"); exit(1) }
print("claudecode-selftest: OK — every assertion passed against the shipped source.")
SWIFT

if ! swiftc -O -o "$TMP/run" "$TMP/extracted.swift" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ the harness failed to compile against the shipped source"
  grep -E 'error:' "$TMP/build.log" | head -20
  exit 1
fi
"$TMP/run"

# --- mutations --------------------------------------------------------------
# A check that cannot fail proves nothing. Each mutation below is a plausible
# "simplification" of the shipped source — several of them are what a first
# draft of this file would actually have said — and each must break the run.
echo
echo "mutations (each must be caught)"

WORK="$TMP/work"
mutate() {
  local name="$1" from="$2" to="$3"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$TMP/extracted.swift" "$WORK/extracted.swift"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/extracted.swift" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$WORK/extracted.swift"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/mut" "$WORK/extracted.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# 1. The headline failure this seat is shaped against: tool traffic as prose.
#    Every session would then match every query about any file you ever opened.
mutate "tool blocks land as writing" \
  'if let type, type != "text" { continue }' \
  'if false { continue }'

# 2. The same failure by the other door — a tool block that omits its type.
#    A type check alone cannot see this one, which is why both exist.
mutate "a typeless tool block lands as writing" \
  'if block["tool_use_id"] != nil || block["toolUseId"] != nil
                || block["input"] != nil || block["tool_use"] != nil { continue }' \
  'if false { continue }'

# 3. §303's clamp ruling, inverted. Renders perfectly and names four hundred
#    rows the same thing.
mutate "the project trails the headline" \
  'return name + " · " + head' \
  'return head + " · " + name'

# 4. The date, and the mutation this one had to become. The first version
#    deleted the trailing fraction STRIP and the harness stayed green —
#    correctly, because a `.withFractionalSeconds` formatter turns out to
#    accept a fraction of any length (measured 2026-08-08: 1, 2, 3, 6 and 9
#    digits, with a Z or a numeric offset), so the strip rescues nothing that
#    has ever been seen and is not load-bearing. What IS load-bearing is the
#    pair: that same formatter REFUSES a whole-second stamp outright, so
#    without the plain fallback a transcript written with no fraction reads as
#    an undated session and a whole history lands stamped today.
mutate "the fraction-less fallback removed" \
  'if let d = isoPlain.date(from: raw) { return d }' \
  'if false, let d = isoPlain.date(from: raw) { return d }'

# 5. LAST timestamp instead of first. A session is dated by when it started;
#    dating it by its end marches long sessions forward a day.
mutate "the session is dated by its last line" \
  'if startedAt == nil, let when = parseDate(string(object, dateKeys)) {
                startedAt = when
            }' \
  'if let when = parseDate(string(object, dateKeys)) {
                startedAt = when
            }'

# 6. Turn counting. Summary and system lines are not conversation, and a
#    messageCount that includes them makes "how long was that session" wrong on
#    every row.
mutate "system and summary lines counted as turns" \
  'if let turn = turn(object) { turns.append(turn) }' \
  'turns.append(turn(object) ?? Turn(role: "system", text: ""))'

# 7. The per-turn budget. One pasted file in message three would otherwise eat
#    the whole conversation and everything after it goes unsearchable.
mutate "the per-turn clamp removed" \
  'return Turn(role: role, text: clamp(text, to: turnLimit))' \
  'return Turn(role: role, text: text)'

# 8. `human` is what a great many transcript formats call the user. Unmapped,
#    every question you asked disappears and only the answers are searchable.
mutate "\"human\" is no longer a user" \
  'case "user", "human":     return "user"' \
  'case "user":              return "user"'

# 9. The blank-value tolerance. Without it a whitespace-only field becomes a
#    real value and a session can land wearing an empty title.
mutate "a whitespace-only field reads as a value" \
  'if !trimmed.isEmpty { return trimmed }' \
  'return trimmed'

# 10. The decode guard. Without it an ordinary folder name gets its dashes
#     turned into path separators and the project is named its own last word.
mutate "a plain folder name is mangled as an encoding" \
  'guard name.hasPrefix("-") else { return name }' \
  'guard !name.isEmpty else { return name }'

# 11. The clamp marker. A clamped string that looks whole is a lie about how
#     much of the session is here.
mutate "a clamp no longer marks itself" \
  'return String(text.prefix(limit)) + "…"' \
  'return String(text.prefix(limit))'

echo
echo "✓ claudecode self-test: assertions and mutations all passed"
