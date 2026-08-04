#!/bin/zsh
# Casberi Sentry self-test — verifies the SHIPPED pure logic behind the Sentry
# bridge (2026-08-04):
#
#   Casberi/Casberi/Model/SentryBridge.swift
#     — SentrySubstatus     (which substatus CROSSINGS are news)
#     — SentryShape.title   (project leads; a crossing leads harder)
#     — SentryShape.isNew   (firstSeen, never lastSeen, never substatus)
#     — SentryShape refs    (why a second regression is a different thing)
#     — SentryIssueLedger.prune (what a bounded ledger may forget)
#     — SentryAccount.normalizeHost
#
# WHY A HARNESS AND NOT A LIVE PROBE. `-sentryProbe` needs a Sentry auth token
# and none is stored on this host — the bridge is UNMEASURED against a live
# organization. Without this, nothing proves any of these decisions.
#
# Every failure here is a SILENT WRONG ANSWER:
#
#   • keying "new" on `lastSeen` instead of `firstSeen` makes every busy issue
#     permanently new, so the feed fills with the same three errors forever;
#   • announcing a crossing on the FIRST pass tells someone an issue "just
#     regressed" when it regressed before they connected — inventing a moment
#     (the Hyperliquid first-sight bug);
#   • a crossing ref that doesn't carry the crossing NUMBER swallows every
#     regression after the first, silently and forever;
#   • a "Regressed" clause that falls off an 80-char title reads as an ordinary
#     issue (the §83 fake status);
#   • pruning the ledger's ANNOUNCED entries first makes the next regression
#     of that issue collide with a row already in the corpus.
#
# `SentryBridge.swift` cannot compile as shipped (it builds `Thing`, a
# SwiftData model, calls `IngestSupport`'s networking, and reads UserDefaults),
# so the pure functions are EXTRACTED from the shipped source by name — never
# copied here — so the harness cannot pass against logic the app doesn't run.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

SENTRY="Casberi/Casberi/Model/SentryBridge.swift"
SUPPORT="Casberi/Casberi/Model/IngestSupport.swift"
BRIDGES="Casberi/Casberi/Model/TokenBridges.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
for f in "$SENTRY" "$SUPPORT" "$BRIDGES" "$REACH"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- drift guards -----------------------------------------------------------
# Wiring the extracted functions can't prove. A perfect `isNew` is worthless if
# nothing routes Sentry to its own sweep.

grep -q 'if bridge == .sentry { return await SentryIngest.refresh' "$BRIDGES" \
  || { echo "✗ TokenIngest no longer routes Sentry to its own sweep — the bridge lands nothing"; exit 1; }
grep -q 'sentry.io' "$REACH" \
  || { echo "✗ sentry.io is not in the reach registry — the privacy screen is wrong"; exit 1; }
# The read-only promise is STRUCTURAL here (Sentry tokens carry scopes), and
# the setup screen names the three. A read this file makes with a scope not on
# that list would be a promise the screen didn't ask for.
for verb in '"POST"' '"DELETE"' '"PATCH"' '"PUT"' 'httpMethod' 'postJSON'; do
  grep -q "$verb" "$SENTRY" \
    && { echo "✗ SentryBridge.swift now contains a WRITE ($verb) — the catalog promises read-only"; exit 1; }
done
# THE FIRST-PASS GUARD. This is the assertion that keeps a freshly connected
# account from being told that an issue sitting at `regressed` just regressed.
# Anchored, the Cursor mutation lesson: a bare grep for `firstPass` passes
# against `!firstPass || true`.
grep -qE '!firstPass \{$' "$SENTRY" \
  || { echo "✗ the crossing branch no longer suppresses the first pass — connecting would invent moments"; exit 1; }
grep -q 'query=is:unresolved' "$SENTRY" \
  || { echo "✗ the issue read is no longer scoped to unresolved — it would walk the archive"; exit 1; }
# The one read this bridge must NEVER make. `/issues/<id>/events/` is where the
# stack traces, request bodies and user context live, and the catalog copy
# promises none of it is read.
grep -qE '/events/|/issues/\\\(.*\)/' "$SENTRY" \
  && { echo "✗ SentryBridge.swift now reaches an events path — 'never an event, a stack"; \
       echo "  trace, or anything about the person who hit it' is now a lie."; exit 1; }
grep -q 'thing.summary = culprit' "$SENTRY" \
  || { echo "✗ the culprit no longer lands as display copy — the row can't say where it broke"; exit 1; }

TMP=$(mktemp -d /tmp/sentry-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- extract the shipped functions -----------------------------------------
python3 - "$SENTRY" "$SUPPORT" "$TMP/extracted.swift" <<'PY'
import sys
sentry, support, out = sys.argv[1:4]

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

def line(path, signature):
    """A single shipped declaration line (a `static let`), verbatim."""
    for raw in open(path):
        if signature in raw:
            return raw.replace("private ", "").rstrip()
    sys.exit(f"✗ extraction failed: {signature!r} not found in {path}")

pieces = [
    "import Foundation\n",
    grab(sentry, "enum SentrySubstatus"),
    grab(sentry, "enum SentryShape"),
    "",
    "enum IngestSupport {",
    grab(support, "static func titleLine"),
    "}\n",
    # The ledger's bounded-forgetting rule, without its UserDefaults half.
    "enum SentryIssueLedger {",
    line(sentry, "static let cap = 500"),
    grab(sentry, "struct Entry: Codable"),
    grab(sentry, "static func prune"),
    "}\n",
    "enum SentryAccount {",
    line(sentry, 'static let defaultHost = "sentry.io"'),
    grab(sentry, "static func normalizeHost"),
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

print("SentrySubstatus.isCrossing — only a CROSSING is news")
check("regressed is a crossing",   SentrySubstatus.regressed.isCrossing  == true)
check("escalating is a crossing",  SentrySubstatus.escalating.isCrossing == true)
// `ongoing` is the steady state of nearly every issue in a busy org. If it
// were a crossing, the feed would refill with the same errors every sync.
check("ongoing is NOT a crossing", SentrySubstatus.ongoing.isCrossing    == false)
// `new` is deliberately not a crossing: the ingest lands new issues off
// `firstSeen`, which works on installs that predate substatus entirely.
// Routing it through here too would land every new issue TWICE.
check("new is NOT a crossing (firstSeen owns that)",
      SentrySubstatus.new.isCrossing == false)
check("archived_until_escalating is not a crossing",
      SentrySubstatus.archivedUntilEscalating.isCrossing == false)
check("archived_forever is not a crossing",
      SentrySubstatus.archivedForever.isCrossing == false)

print("leadClause — a crossing says so, everything else stays quiet")
check("regressed reads 'Regressed'",   SentrySubstatus.regressed.leadClause  == "Regressed")
check("escalating reads 'Escalating'", SentrySubstatus.escalating.leadClause == "Escalating")
check("ongoing adds no clause",        SentrySubstatus.ongoing.leadClause    == nil)
check("new adds no clause",            SentrySubstatus.new.leadClause        == nil)

print("raw values match Sentry's own vocabulary")
// A typo here empties the room silently: the value never parses, so no issue
// ever crosses and nothing anywhere says why.
check("regressed",  SentrySubstatus(rawValue: "regressed")  == .regressed)
check("escalating", SentrySubstatus(rawValue: "escalating") == .escalating)
check("archived_until_escalating",
      SentrySubstatus(rawValue: "archived_until_escalating") == .archivedUntilEscalating)
check("an unknown value → nil", SentrySubstatus(rawValue: "quarantined") == nil)

print("isNew — firstSeen, against a window")
let now = Date(timeIntervalSince1970: 1_800_000_000)
let lookback: TimeInterval = 14 * 24 * 3600
check("an issue first seen an hour ago is new",
      SentryShape.isNew(firstSeen: now.addingTimeInterval(-3600), now: now, lookback: lookback))
check("13 days ago is still new",
      SentryShape.isNew(firstSeen: now.addingTimeInterval(-13 * 86400), now: now, lookback: lookback))
check("15 days ago is NOT new",
      SentryShape.isNew(firstSeen: now.addingTimeInterval(-15 * 86400), now: now, lookback: lookback) == false)
// A year-old issue that is still unresolved is the most common row in any
// real Sentry account. If it read as new, connecting would dump the whole
// backlog into today.
check("a year-old unresolved issue is NOT new",
      SentryShape.isNew(firstSeen: now.addingTimeInterval(-365 * 86400), now: now, lookback: lookback) == false)
check("a missing firstSeen is NOT new", SentryShape.isNew(firstSeen: nil, now: now, lookback: lookback) == false)
// A clock disagreement between phone and server, accepted rather than
// rejected: being slightly early is harmless, and rejecting it would silently
// drop real issues for anyone whose device clock runs behind.
check("a slightly-future firstSeen is accepted",
      SentryShape.isNew(firstSeen: now.addingTimeInterval(60), now: now, lookback: lookback))

print("refs — why a SECOND regression is a different thing")
check("a new-issue ref is one per issue, forever",
      SentryShape.newRef(id: "4507") == "sentry:issue:4507")
check("a crossing carries its NUMBER",
      SentryShape.crossingRef(id: "4507", substatus: .regressed, crossing: 1)
      == "sentry:regressed:4507:1")
// THE assertion this design exists for. Without the number, the second
// regression of an issue dedupes against the first and is swallowed — silently,
// forever, on the one row this bridge exists to deliver.
check("the second regression is a DIFFERENT ref",
      SentryShape.crossingRef(id: "4507", substatus: .regressed, crossing: 2)
      != SentryShape.crossingRef(id: "4507", substatus: .regressed, crossing: 1))
check("a regression and an escalation don't collide",
      SentryShape.crossingRef(id: "4507", substatus: .escalating, crossing: 1)
      != SentryShape.crossingRef(id: "4507", substatus: .regressed, crossing: 1))
check("two issues don't collide",
      SentryShape.crossingRef(id: "4508", substatus: .regressed, crossing: 1)
      != SentryShape.crossingRef(id: "4507", substatus: .regressed, crossing: 1))
// A crossing row must never dedupe against the issue's own arrival row.
check("a crossing never collides with the new-issue ref",
      SentryShape.crossingRef(id: "4507", substatus: .regressed, crossing: 1)
      != SentryShape.newRef(id: "4507"))

print("title — the project leads, a crossing leads harder")
check("a plain new issue",
      SentryShape.title(project: "checkout-web", title: "TypeError: cart is undefined", crossing: nil)
      == "checkout-web · TypeError: cart is undefined")
check("a regression leads with its outcome",
      SentryShape.title(project: "api", title: "KeyError: 'customer_id'", crossing: .regressed)
      == "Regressed · api · KeyError: 'customer_id'")
// A Sentry issue can be attributed to no project in some payloads; a lone
// separator would read as a rendering bug.
check("no project drops the separator cleanly",
      SentryShape.title(project: nil, title: "Timeout", crossing: nil) == "Timeout")
check("an empty project is dropped too",
      SentryShape.title(project: "  ", title: "Timeout", crossing: .regressed)
      == "Regressed · Timeout")

print("the 80-character clamp — why a crossing LEADS")
// The §83 ruling as a test. A stack-frame title is exactly the long tail that
// eats a trailing word, and a regression reading as an ordinary new issue is
// the fake status the honesty rule forbids.
let longTitle = "TypeError: Cannot read properties of undefined (reading 'subscriptionStatus')"
let composed = SentryShape.title(project: "checkout-web", title: longTitle, crossing: .regressed)
check("the composed title really does overflow (or this proves nothing)", composed.count > 80)
let shipped = IngestSupport.titleLine(composed)
check("clamped, 'Regressed' SURVIVES", shipped.hasPrefix("Regressed · "))
check("clamped, it is truncated (so the clamp really ran)", shipped.hasSuffix("…"))
let trailing = IngestSupport.titleLine("checkout-web · \(longTitle) · Regressed")
check("trailing, 'Regressed' would be EATEN", !trailing.contains("Regressed"))

print("ledger.prune — what a bounded ledger may forget")
var big: [String: SentryIssueLedger.Entry] = [:]
for i in 0..<(SentryIssueLedger.cap + 50) {
    big["issue-\(i)"] = SentryIssueLedger.Entry(substatus: "ongoing", crossings: 0)
}
// One entry that HAS announced a crossing, buried in the middle of the churn.
big["issue-250"] = SentryIssueLedger.Entry(substatus: "regressed", crossings: 3)
let pruned = SentryIssueLedger.prune(big)
check("pruned to the cap", pruned.count == SentryIssueLedger.cap)
// THE assertion. Losing an announced entry means the next regression of that
// issue gets crossing number 1 again, collides with a row already in the
// corpus, and is swallowed — so announced entries must outlive silent ones.
check("an entry with crossings SURVIVES the prune", pruned["issue-250"] != nil)
check("an entry with crossings keeps its count", pruned["issue-250"]?.crossings == 3)
// Under the cap, nothing is touched at all.
var small: [String: SentryIssueLedger.Entry] = ["a": .init(substatus: "ongoing", crossings: 0)]
small["b"] = .init(substatus: "new", crossings: 0)
check("under the cap, nothing is dropped", SentryIssueLedger.prune(small).count == 2)

print("normalizeHost — what a person actually pastes")
check("a bare host",        SentryAccount.normalizeHost("sentry.io") == "sentry.io")
check("the EU region",      SentryAccount.normalizeHost("de.sentry.io") == "de.sentry.io")
check("a pasted URL",       SentryAccount.normalizeHost("https://sentry.io/organizations/acme/") == "sentry.io")
check("a self-hosted host", SentryAccount.normalizeHost("sentry.internal.acme.com") == "sentry.internal.acme.com")
check("uppercase is folded", SentryAccount.normalizeHost("Sentry.IO") == "sentry.io")
check("padding is trimmed", SentryAccount.normalizeHost("  sentry.io  ") == "sentry.io")
// An empty field must fall back rather than build "https:///api/0/…", which
// fails in a way that reads exactly like a refused token.
check("empty falls back to the default", SentryAccount.normalizeHost("") == "sentry.io")
check("whitespace falls back too",       SentryAccount.normalizeHost("   ") == "sentry.io")

print("")
if failures == 0 {
    print("✓ sentry self-test: all assertions passed")
} else {
    print("✗ sentry self-test: \(failures) assertion(s) failed")
    exit(1)
}
SWIFT

swiftc -O -o "$TMP/run" "$TMP/extracted.swift" "$TMP/main.swift" 2>&1 \
  | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ the extracted Sentry logic did not compile"; exit 1; }
"$TMP/run"
