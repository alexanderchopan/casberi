#!/bin/zsh
# Casberi Cursor self-test — verifies the SHIPPED pure logic behind the Cursor
# bridge (prd §303, 2026-08-04):
#
#   Casberi/Casberi/Model/CursorBridge.swift
#     — CursorAgentStatus  (which runs are OVER, and what an abnormal one says)
#     — repoLabel          (the repo that LEADS every title)
#     — status(of:)        (an unknown value must land NOTHING, not a guess)
#     — title(row:…)       (composed, then clamped by IngestSupport.titleLine)
#
# WHY A HARNESS AND NOT A LIVE PROBE. `-cursorProbe` needs a Cursor API key, and
# there is an open question the vendor's own docs and forum contradict each
# other on — whether an individual on a personal plan can mint a Cloud Agents
# key at all. So the live probe may be unavailable to this project indefinitely,
# and the bridge would otherwise ship with NOTHING proving it. This harness
# needs no key, no account, no network and no simulator.
#
# Every failure mode here is a SILENT WRONG ANSWER rather than a crash — the
# class that renders perfectly and reads as working:
#
#   • a FAILED run whose outcome fell off the end of an 80-char title, so it
#     reads in the feed as a run that succeeded (the §83 fake status, and the
#     entire reason the outcome LEADS instead of trails);
#   • a status value this build has never heard of, which lands nothing and
#     says nothing anywhere;
#   • a repo label trimmed to a repository that doesn't exist ("sub/project"
#     out of a nested GitLab group).
#
# `CursorBridge.swift` cannot compile as shipped (it builds `Thing`, a SwiftData
# model, and calls `IngestSupport`'s networking), so the pure functions are
# EXTRACTED from the shipped source by name — never copied into this file — so
# the harness cannot pass against logic the app doesn't run. The only
# transformation is stripping `private `. If an extraction stops matching, the
# compile fails loudly rather than asserting nothing.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

CURSOR="Casberi/Casberi/Model/CursorBridge.swift"
SUPPORT="Casberi/Casberi/Model/IngestSupport.swift"
BRIDGES="Casberi/Casberi/Model/TokenBridges.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
for f in "$CURSOR" "$SUPPORT" "$BRIDGES" "$REACH"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- drift guards -----------------------------------------------------------
# Wiring facts the extracted functions can't prove on their own. A perfect
# `repoLabel` is worthless if nothing calls `CursorFetch.things`, and a perfect
# `terminal` is worthless if `thing(from:)` stops consulting it.

grep -q 'CursorFetch.things(token: token)' "$BRIDGES" \
  || { echo "✗ TokenIngest no longer routes Cursor to CursorFetch — the bridge lands nothing"; exit 1; }

# THE CONDUCT GUARD, and the reason this whole harness earns its place in
# verify.sh. A Cursor key carries NO SCOPES: the same key that lists agents can
# POST one (spending the person's money and writing a branch to their repo) or
# DELETE one. The catalog copy promises Casberi "never starts one, follows one
# up, stops one, or deletes one" — a promise kept only by this file's conduct.
# CursorBridge.swift itself records the tripwire in prose ("If a future pass
# adds a write to this file, that copy becomes a lie"). Prose is what CLAUDE.md
# calls memory, and memory lost. This makes it mechanical.
for verb in '"POST"' '"DELETE"' '"PATCH"' '"PUT"' 'httpMethod' 'postJSON' 'deleteJSON'; do
  grep -q "$verb" "$CURSOR" \
    && { echo "✗ CursorBridge.swift now contains a WRITE ($verb) — the catalog's"; \
         echo "  'never starts one, follows one up, stops one, or deletes one' is now a lie."; \
         echo "  Change that copy in the same commit, or drop the write."; exit 1; }
done
# …and the positive half: the only transport it may use.
grep -qE 'IngestSupport\.(getJSON|getJSONStatus)\(' "$CURSOR" \
  || { echo "✗ CursorBridge.swift no longer reads through IngestSupport's GET funnel"; exit 1; }

grep -q 'api.cursor.com' "$REACH" \
  || { echo "✗ api.cursor.com is not in the reach registry — the privacy screen is wrong"; exit 1; }
# ANCHORED TO END OF LINE, and that is not fussiness — it is this guard's own
# mutation finding. A bare `grep -q 'runStatus.terminal'` passes clean against
# `runStatus.terminal || true`, which lands every in-flight run: the mutation
# survived the first cut of this harness. The guard must prove the condition is
# the WHOLE condition, not merely that the words appear.
grep -qE 'runStatus\.terminal[[:space:]]*$' "$CURSOR" \
  || { echo "✗ thing(from:)'s terminal filter is gone or weakened — in-flight runs would land"; exit 1; }
grep -q 'IngestSupport.isoDate(row\["createdAt"\])' "$CURSOR" \
  || { echo "✗ a run no longer carries its REAL start — a first sync would fake a day of urgency"; exit 1; }
grep -q 'sourceRef: "cursor:agent:' "$CURSOR" \
  || { echo "✗ the dedupe key moved — every sync would re-land every run"; exit 1; }
# The agent's account of what it did is the whole reason to keep a finished
# run, so it must be DISPLAY copy. `enrichedText` is retrieval-only by the
# 2026-07-15 ruling and would make it invisible on every screen.
grep -q 'thing.summary = summary' "$CURSOR" \
  || { echo "✗ the agent's summary no longer lands as display copy"; exit 1; }
grep -q 'never starts one, follows one up, stops one, or deletes one' "$BRIDGES" \
  || { echo "✗ canLine no longer names the four verbs — the conduct promise is unstated"; exit 1; }
# A finished run is finished forever — this is the one keyed Work bridge with
# no reconcile pass, and a reconcile appearing means somebody started landing
# non-terminal runs.
grep -qi 'reconcileCursor' "$BRIDGES" \
  && { echo "✗ a Cursor reconcile pass appeared — only terminal runs should land"; exit 1; }

TMP=$(mktemp -d /tmp/cursor-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- extract the shipped functions -----------------------------------------
python3 - "$CURSOR" "$SUPPORT" "$TMP/extracted.swift" <<'PY'
import sys
cursor, support, out = sys.argv[1:4]

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

pieces = [
    "import Foundation\n",
    # The status enum whole — `terminal` and `leadClause` are the two rulings.
    grab(cursor, "enum CursorAgentStatus"),
    "",
    "enum IngestSupport {",
    grab(support, "static func titleLine"),
    "}\n",
    "enum CursorFetch {",
    grab(cursor, "static func repoLabel"),
    grab(cursor, "static func status(of row"),
    grab(cursor, "static func title(row:"),
    grab(cursor, "static func trimmed"),
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

print("CursorAgentStatus.terminal — only a run that is OVER becomes a thing")
// CREATING/RUNNING are STATES (§216): on screen in Cursor right now, no
// summary, no PR, stale within minutes.
check("CREATING is not over",  CursorAgentStatus.creating.terminal  == false)
check("RUNNING is not over",   CursorAgentStatus.running.terminal   == false)
check("FINISHED is over",      CursorAgentStatus.finished.terminal  == true)
check("ERROR is over",         CursorAgentStatus.error.terminal     == true)
check("EXPIRED is over",       CursorAgentStatus.expired.terminal   == true)
// Not in v0's documented five — it is v1's, carried so that if v0 ever gains
// it a cancelled run doesn't silently match no case and never land.
check("CANCELLED is over",     CursorAgentStatus.cancelled.terminal == true)

print("leadClause — an abnormal run says so, a normal one stays quiet")
check("FINISHED adds no clause",  CursorAgentStatus.finished.leadClause  == nil)
check("ERROR reads 'Failed'",     CursorAgentStatus.error.leadClause     == "Failed")
check("EXPIRED reads 'Expired'",  CursorAgentStatus.expired.leadClause   == "Expired")
check("CANCELLED reads 'Cancelled'", CursorAgentStatus.cancelled.leadClause == "Cancelled")

print("status(of:) — an unknown value lands NOTHING, never a guess")
check("FINISHED parses",   CursorFetch.status(of: ["status": "FINISHED"]) == .finished)
check("lowercase parses",  CursorFetch.status(of: ["status": "finished"]) == .finished)
check("padding is trimmed", CursorFetch.status(of: ["status": "  RUNNING  "]) == .running)
check("a missing field → nil", CursorFetch.status(of: [:]) == nil)
check("an empty value → nil",  CursorFetch.status(of: ["status": ""]) == nil)
check("a non-string → nil",    CursorFetch.status(of: ["status": 3]) == nil)
// The safe direction: nil is treated as NON-terminal by thing(from:), so a
// status this build has never heard of lands nothing rather than a row titled
// with a guess. `diagnose` names it so it surfaces as a probe line.
check("a value this build doesn't know → nil", CursorFetch.status(of: ["status": "PAUSED"]) == nil)

print("repoLabel — the repo that leads every title")
// v0 sends a full URL…
check("v0's full URL → org/repo",
      CursorFetch.repoLabel(["repository": "https://github.com/your-org/your-repo"]) == "your-org/your-repo")
// …and v1 sends the same value scheme-stripped. Both must land identically,
// or the v0→v1 migration silently renames every repo in the feed.
check("v1's bare host form → org/repo",
      CursorFetch.repoLabel(["repository": "github.com/your-org/your-repo"]) == "your-org/your-repo")
check("an already-bare org/repo keeps BOTH components",
      CursorFetch.repoLabel(["repository": "your-org/your-repo"]) == "your-org/your-repo")
check(".git is stripped",
      CursorFetch.repoLabel(["repository": "https://github.com/org/repo.git"]) == "org/repo")
check("an ssh remote lands the same",
      CursorFetch.repoLabel(["repository": "ssh://git@github.com/org/repo"]) == "org/repo")
// A GitLab nested group really IS "group/sub/project" — trimming to the last
// two components would name a repository that does not exist.
check("a nested GitLab group is kept whole",
      CursorFetch.repoLabel(["repository": "https://gitlab.com/group/sub/project"]) == "group/sub/project")
check("a self-hosted host is dropped like any other",
      CursorFetch.repoLabel(["repository": "https://git.acme.internal/team/service"]) == "team/service")
check("a missing repository → nil", CursorFetch.repoLabel([:]) == nil)
check("an empty repository → nil",  CursorFetch.repoLabel(["repository": "   "]) == nil)
check("a non-string → nil",         CursorFetch.repoLabel(["repository": 7]) == nil)

print("title — repo leads, and the outcome leads the repo")
check("the happy path is repo · name",
      CursorFetch.title(row: ["name": "Add README documentation"],
                        source: ["repository": "https://github.com/your-org/your-repo"],
                        status: .finished) == "your-org/your-repo · Add README documentation")
check("a failure leads with its outcome",
      CursorFetch.title(row: ["name": "fix the flaky test"],
                        source: ["repository": "https://github.com/org/repo"],
                        status: .error) == "Failed · org/repo · fix the flaky test")
// Cursor's own clients default an empty name, so the field is never trusted.
check("an empty name falls back, with no lone separator",
      CursorFetch.title(row: ["name": "  "],
                        source: ["repository": "github.com/org/repo"],
                        status: .finished) == "org/repo · Background agent")
check("no repository → just the name, no lone separator",
      CursorFetch.title(row: ["name": "nightly sweep"], source: [:], status: .finished)
        == "nightly sweep")
check("no repository AND a failure → outcome · name",
      CursorFetch.title(row: ["name": "nightly sweep"], source: [:], status: .error)
        == "Failed · nightly sweep")

print("the 80-char clamp — WHY the outcome leads (prd §303)")
// The ruling: titleLine clamps at 80, so an outcome parked at the END is
// exactly the word the clamp eats — and a failed run reading as a successful
// one is the fake status §83 bans. These two assertions are the ruling as a
// test, and the second is the mutation that proves it is load-bearing.
let longRepo = "acme-industries/internal-platform-services"
let longName = "migrate the legacy billing reconciliation job to the new scheduler"
let shipped = IngestSupport.titleLine(
    CursorFetch.title(row: ["name": longName],
                      source: ["repository": "https://github.com/\(longRepo)"],
                      status: .error))
check("the composed title really does overflow (or this proves nothing)",
      CursorFetch.title(row: ["name": longName],
                        source: ["repository": "https://github.com/\(longRepo)"],
                        status: .error).count > 80)
check("clamped, the outcome SURVIVES", shipped.hasPrefix("Failed · "))
check("clamped, it is truncated (so the clamp really ran)", shipped.hasSuffix("…"))
// The counterfactual: the same facts with the outcome trailing, clamped the
// same way. If this ever stops being true, the leading rule stopped mattering
// and the comment in CursorBridge.swift should be rewritten, not the code.
let trailing = IngestSupport.titleLine("\(longRepo) · \(longName) · Failed")
check("trailing, the outcome would be EATEN", !trailing.contains("Failed"))

print("")
if failures == 0 {
    print("✓ cursor self-test: all assertions passed")
} else {
    print("✗ cursor self-test: \(failures) assertion(s) failed")
    exit(1)
}
SWIFT

swiftc -O -o "$TMP/run" "$TMP/extracted.swift" "$TMP/main.swift" 2>&1 \
  | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ the extracted Cursor logic did not compile"; exit 1; }
"$TMP/run"
