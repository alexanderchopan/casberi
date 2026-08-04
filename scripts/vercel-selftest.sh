#!/bin/zsh
# Casberi Vercel self-test — verifies the SHIPPED pure logic behind the Vercel
# bridge (2026-08-04):
#
#   Casberi/Casberi/Model/VercelBridge.swift
#     — VercelState        (which deployments are OVER, and what a bad one says)
#     — VercelShape.lands  (the whole editorial judgement of the bridge)
#     — VercelShape.title  (composed, then clamped by IngestSupport.titleLine)
#     — epochMillis        (Vercel dates in MILLISECONDS, not seconds)
#     — commitMessage/Ref  (namespaced per git provider, not GitHub-only)
#
# WHY A HARNESS AND NOT A LIVE PROBE. `-vercelProbe` needs a Vercel token, and
# none is stored on this host — the bridge is UNMEASURED against a live account.
# Without this, nothing at all proves these decisions.
#
# Every failure here is a SILENT WRONG ANSWER — the class that renders
# perfectly and reads as working:
#
#   • `lands` wrong in one direction turns the feed into a git log; wrong in
#     the other lets a broken production deploy pass in total silence;
#   • a FAILED build whose outcome fell off the end of an 80-char title reads
#     as a deploy that shipped (the §83 fake status, and the whole reason the
#     outcome LEADS instead of trails);
#   • `created` read as SECONDS instead of milliseconds dates every row to
#     1970, and read as a string finds no date at all;
#   • a GitLab-hosted project silently losing every commit message, because
#     only `githubCommitMessage` was read.
#
# `VercelBridge.swift` cannot compile as shipped (it builds `Thing`, a SwiftData
# model, and calls `IngestSupport`'s networking), so the pure functions are
# EXTRACTED from the shipped source by name — never copied into this file — so
# the harness cannot pass against logic the app doesn't run.
#
# MUTATION-TESTED seven ways (2026-08-04), six caught: successful previews
# landing, the epoch read as seconds, the commit subject not being taken, the
# outcome trailing instead of leading, `isProduction` by `contains`, and a
# write verb appearing in the file.
#
# The seventh is an EQUIVALENT MUTANT and is recorded here so nobody
# rediscovers it: dropping `state.terminal` from `VercelShape.lands`'s guard
# changes no behaviour, because the switch beneath it already returns false for
# every in-flight state through its `default`. The guard is kept as
# belt-and-braces for the day a case is added there, and `terminal` is asserted
# directly by the six `VercelState.terminal` checks below — so it is covered,
# just not by that mutation.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

VERCEL="Casberi/Casberi/Model/VercelBridge.swift"
SUPPORT="Casberi/Casberi/Model/IngestSupport.swift"
BRIDGES="Casberi/Casberi/Model/TokenBridges.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
for f in "$VERCEL" "$SUPPORT" "$BRIDGES" "$REACH"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- drift guards -----------------------------------------------------------
# Wiring facts the extracted functions can't prove on their own. A perfect
# `lands` is worthless if nothing calls `VercelFetch.things`.

grep -q 'VercelFetch.things(token: token)' "$BRIDGES" \
  || { echo "✗ TokenIngest no longer routes Vercel to VercelFetch — the bridge lands nothing"; exit 1; }

# THE CONDUCT GUARD, and the reason this harness earns its place in verify.sh.
# A Vercel token carries NO SCOPES: the same token that lists deployments can
# create one, promote it to production, roll back, cancel a build, delete a
# project, or read the environment variables where the project keeps its
# secrets. The catalog copy promises Casberi "never deploys, promotes, rolls
# back, cancels" and "never reads your environment variables" — promises kept
# only by this file's conduct. VercelBridge.swift records the tripwire in prose;
# prose is what CLAUDE.md calls memory, and memory lost. This makes it
# mechanical. (Cursor's precedent, same shape, same reasoning.)
for verb in '"POST"' '"DELETE"' '"PATCH"' '"PUT"' 'httpMethod' 'postJSON' 'deleteJSON'; do
  grep -q "$verb" "$VERCEL" \
    && { echo "✗ VercelBridge.swift now contains a WRITE ($verb) — the catalog's"; \
         echo "  'never deploys, promotes, rolls back, or cancels' is now a lie."; \
         echo "  Change that copy in the same commit, or drop the write."; exit 1; }
done
# The environment-variable half of the same promise. `/v9/projects/<id>/env` is
# the path that would break it, and `env` is short enough to appear innocently,
# so this matches the API shape rather than the word.
grep -qE '/v[0-9]+/(projects|env)' "$VERCEL" \
  && { echo "✗ VercelBridge.swift now reaches a projects/env path — 'it never reads"; \
       echo "  your environment variables' is now a lie."; exit 1; }
# …and the positive half: the only transport it may use.
grep -qE 'IngestSupport\.(getJSON|getJSONStatus)\(' "$VERCEL" \
  || { echo "✗ VercelBridge.swift no longer reads through IngestSupport's GET funnel"; exit 1; }

grep -q 'api.vercel.com' "$REACH" \
  || { echo "✗ api.vercel.com is not in the reach registry — the privacy screen is wrong"; exit 1; }
# ANCHORED, the Cursor mutation lesson: a bare grep for the call passes against
# `lands(...) || true`, which would land every successful preview.
grep -qE 'guard VercelShape\.lands\(state: state, target: target\) else \{ return nil \}' "$VERCEL" \
  || { echo "✗ thing(from:)'s landing filter is gone or weakened — previews would flood the feed"; exit 1; }
grep -q 'capturedAt: epochMillis' "$VERCEL" \
  || { echo "✗ a deployment no longer carries its REAL time — a first sync would fake a day of urgency"; exit 1; }
grep -q 'sourceRef: "vercel:deploy:' "$VERCEL" \
  || { echo "✗ the dedupe key changed — every deployment would re-land"; exit 1; }
# A finished deployment is finished forever — like Cursor, this bridge has no
# reconcile pass, and one appearing means somebody started landing in-flight
# deploys.
grep -qi 'reconcileVercel' "$BRIDGES" \
  && { echo "✗ a Vercel reconcile pass appeared — only terminal deployments should land"; exit 1; }

TMP=$(mktemp -d /tmp/vercel-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- extract the shipped functions -----------------------------------------
python3 - "$VERCEL" "$SUPPORT" "$TMP/extracted.swift" <<'PY'
import sys
vercel, support, out = sys.argv[1:4]

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
    grab(vercel, "enum VercelState"),
    grab(vercel, "enum VercelShape"),
    "",
    "enum IngestSupport {",
    grab(support, "static func titleLine"),
    "}\n",
    "enum VercelFetch {",
    grab(vercel, "static func state(of row"),
    grab(vercel, "static func commitMessage"),
    grab(vercel, "static func commitRef"),
    grab(vercel, "static func epochMillis"),
    grab(vercel, "static func nonEmpty"),
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

print("VercelState.terminal — only a deployment that is OVER becomes a thing")
// BUILDING/QUEUED/INITIALIZING are STATES (§216): on screen in Vercel right
// now, no outcome, stale within ninety seconds.
check("BUILDING is not over",     VercelState.building.terminal     == false)
check("QUEUED is not over",       VercelState.queued.terminal       == false)
check("INITIALIZING is not over", VercelState.initializing.terminal == false)
check("READY is over",            VercelState.ready.terminal        == true)
check("ERROR is over",            VercelState.error.terminal        == true)
check("CANCELED is over",         VercelState.canceled.terminal     == true)

print("leadClause — a bad deployment says so, a good one stays quiet")
check("READY adds no clause",       VercelState.ready.leadClause    == nil)
check("ERROR reads 'Build failed'", VercelState.error.leadClause    == "Build failed")
check("CANCELED reads 'Canceled'",  VercelState.canceled.leadClause == "Canceled")
// An in-flight state never lands, so its clause is moot — but it must not be
// non-nil, or a future caller could render "Building ·" on a row.
check("BUILDING adds no clause",    VercelState.building.leadClause == nil)

print("isProduction — matched WHOLE, never by contains")
check("production matches",             VercelShape.isProduction("production"))
check("Production matches (case)",      VercelShape.isProduction("Production"))
check("padding is trimmed",             VercelShape.isProduction("  production "))
check("nil (a preview) does not match", VercelShape.isProduction(nil) == false)
check("staging does not match",         VercelShape.isProduction("staging") == false)
// The guard that keeps a custom environment from masquerading as the real one.
// A `contains` implementation passes every other case here and fails this.
check("'pre-production' does NOT match", VercelShape.isProduction("pre-production") == false)
check("'production-eu' does NOT match",  VercelShape.isProduction("production-eu") == false)

print("lands — the whole editorial judgement of this bridge")
// The two shapes that land.
check("a production deploy that went live LANDS",
      VercelShape.lands(state: .ready, target: "production"))
check("a failed build LANDS, on any target",
      VercelShape.lands(state: .error, target: nil))
check("a failed PRODUCTION build LANDS",
      VercelShape.lands(state: .error, target: "production"))
check("a canceled build LANDS",
      VercelShape.lands(state: .canceled, target: nil))
// The one that deliberately does NOT — this is the firehose the bridge exists
// not to be, and it is the single most important assertion in this file.
check("a SUCCESSFUL PREVIEW does not land (the git log)",
      VercelShape.lands(state: .ready, target: nil) == false)
check("a successful staging deploy does not land",
      VercelShape.lands(state: .ready, target: "staging") == false)
// In-flight, whatever the target.
check("an in-flight production build does not land",
      VercelShape.lands(state: .building, target: "production") == false)
check("a queued build does not land",
      VercelShape.lands(state: .queued, target: nil) == false)
// The safe direction: a state this build has never heard of lands NOTHING
// rather than a row titled with a guess.
check("an unknown state does not land",
      VercelShape.lands(state: nil, target: "production") == false)

print("state(of:) — readyState first, state as fallback, unknown → nil")
check("readyState parses",      VercelFetch.state(of: ["readyState": "READY"]) == .ready)
check("lowercase parses",       VercelFetch.state(of: ["readyState": "ready"]) == .ready)
check("padding is trimmed",     VercelFetch.state(of: ["readyState": " ERROR "]) == .error)
// Vercel's own examples show both keys; reading only one would empty the room
// for whichever shape an account happens to get back.
check("`state` is the fallback", VercelFetch.state(of: ["state": "CANCELED"]) == .canceled)
check("readyState WINS when both are present",
      VercelFetch.state(of: ["readyState": "READY", "state": "ERROR"]) == .ready)
check("a missing field → nil",  VercelFetch.state(of: [:]) == nil)
check("a non-string → nil",     VercelFetch.state(of: ["readyState": 7]) == nil)
check("a value this build doesn't know → nil",
      VercelFetch.state(of: ["readyState": "SUPERSEDED"]) == nil)

print("epochMillis — Vercel dates are MILLISECONDS")
// 1754300000000 ms = 2025-08-04T09:33:20Z. As SECONDS it would be the year
// 57560; as a string, nothing at all.
let ms = 1_754_300_000_000.0
let expected = Date(timeIntervalSince1970: 1_754_300_000)
check("a Double parses as ms", VercelFetch.epochMillis(ms) == expected)
check("an Int parses as ms",   VercelFetch.epochMillis(1_754_300_000_000) == expected)
// Some SDKs stringify large integers — accepted rather than silently dropped.
check("a numeric string parses", VercelFetch.epochMillis("1754300000000") == expected)
check("nil → nil",              VercelFetch.epochMillis(nil) == nil)
check("a non-numeric string → nil", VercelFetch.epochMillis("yesterday") == nil)
check("zero → nil (not 1970)",  VercelFetch.epochMillis(0) == nil)
// The mutation this assertion exists for: treating the field as seconds gives
// a date tens of thousands of years out, which sorts to the top of the feed
// forever and looks like a bug in the feed, not in the bridge.
check("read as SECONDS it would be absurd — proving the unit matters",
      Date(timeIntervalSince1970: ms).timeIntervalSince(expected) > 1_000_000_000)

print("commitMessage/commitRef — every provider, not just GitHub")
check("github", VercelFetch.commitMessage(["githubCommitMessage": "Fix the header"]) == "Fix the header")
// A GitLab- or Bitbucket-hosted project would silently have NO commit message
// at all if only GitHub's key were read — the row would fall back to a bare
// hostname and read as a bug.
check("gitlab", VercelFetch.commitMessage(["gitlabCommitMessage": "Bump deps"]) == "Bump deps")
check("bitbucket", VercelFetch.commitMessage(["bitbucketCommitMessage": "Patch"]) == "Patch")
check("no git metadata → nil", VercelFetch.commitMessage([:]) == nil)
check("an empty message → nil", VercelFetch.commitMessage(["githubCommitMessage": "  "]) == nil)
check("ref reads the same way", VercelFetch.commitRef(["gitlabCommitRef": "main"]) == "main")

print("title — the project leads, the outcome leads harder")
check("a clean production ship",
      VercelShape.title(project: "casberi-site", commitMessage: "Rewrite the pricing page",
                        host: "casberi-site.vercel.app", state: .ready)
      == "casberi-site · Rewrite the pricing page")
check("a failure leads with its outcome",
      VercelShape.title(project: "casberi-site", commitMessage: "bump next to 15.4",
                        host: nil, state: .error)
      == "Build failed · casberi-site · bump next to 15.4")
// A CLI deploy or a redeploy carries no git metadata at all; a row reading just
// "casberi-site" says nothing, so the hostname stands in.
check("no commit message falls back to the hostname",
      VercelShape.title(project: "casberi-site", commitMessage: nil,
                        host: "casberi-site-abc123.vercel.app", state: .ready)
      == "casberi-site · casberi-site-abc123.vercel.app")
// git itself takes the subject line; without this the body of a conventional
// commit runs into the title as one flattened paragraph.
check("a multi-line commit takes its SUBJECT line only",
      VercelShape.title(project: "app", commitMessage: "Fix the header\n\nIt was 4px off on mobile.",
                        host: nil, state: .ready)
      == "app · Fix the header")
check("an empty commit message falls through to the host",
      VercelShape.title(project: "app", commitMessage: "   ", host: "app.vercel.app", state: .ready)
      == "app · app.vercel.app")

print("the 80-character clamp — why the outcome LEADS")
// The §83 ruling as a test, Cursor's shape. A commit message is exactly the
// long tail that eats a trailing word, and a failed deploy reading as a
// successful one is the fake status the honesty rule forbids.
let longCommit = "migrate the legacy billing reconciliation job onto the new scheduler"
let composed = VercelShape.title(project: "casberi-platform", commitMessage: longCommit,
                                 host: nil, state: .error)
check("the composed title really does overflow (or this proves nothing)", composed.count > 80)
let shipped = IngestSupport.titleLine(composed)
check("clamped, the outcome SURVIVES", shipped.hasPrefix("Build failed · "))
check("clamped, it is truncated (so the clamp really ran)", shipped.hasSuffix("…"))
// The counterfactual. If this ever stops being true, the leading rule stopped
// mattering and VercelBridge.swift's comment should be rewritten, not the code.
let trailing = IngestSupport.titleLine("casberi-platform · \(longCommit) · Build failed")
check("trailing, the outcome would be EATEN", !trailing.contains("Build failed"))

print("")
if failures == 0 {
    print("✓ vercel self-test: all assertions passed")
} else {
    print("✗ vercel self-test: \(failures) assertion(s) failed")
    exit(1)
}
SWIFT

swiftc -O -o "$TMP/run" "$TMP/extracted.swift" "$TMP/main.swift" 2>&1 \
  | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ the extracted Vercel logic did not compile"; exit 1; }
"$TMP/run"
