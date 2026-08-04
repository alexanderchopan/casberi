#!/bin/zsh
# Casberi PagerDuty self-test — verifies the SHIPPED pure logic behind the
# PagerDuty bridge (2026-08-04):
#
#   Casberi/Casberi/Model/PagerDutyBridge.swift
#     — PagerDutyShape.duration  (how long it lasted, in a person's words)
#     — PagerDutyShape.title     (service leads; "Resolved after N" leads harder)
#     — PagerDutyShape refs      (both halves of one incident, never colliding)
#
# WHY A HARNESS AND NOT A LIVE PROBE. `-pagerdutyProbe` needs a REST API key and
# none is stored on this host — the bridge is UNMEASURED against a live account.
#
# Every failure here is a SILENT WRONG ANSWER:
#
#   • a negative duration ("resolved after -4 minutes") from a resolution
#     timestamp that precedes the trigger — a clock disagreement rendered as
#     fact;
#   • "0 minutes" for a fast resolution, which reads as a bug rather than as
#     good news;
#   • a "Resolved" clause falling off an 80-char title, so a closed incident
#     reads as one still burning — the §83 fake status in the domain where
#     believing it costs the most;
#   • the two halves of one incident sharing a ref, so the resolution never
#     lands and the feed says the outage is still open.
#
# `PagerDutyBridge.swift` cannot compile as shipped, so the pure functions are
# EXTRACTED from the shipped source by name — never copied here.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

PD="Casberi/Casberi/Model/PagerDutyBridge.swift"
SUPPORT="Casberi/Casberi/Model/IngestSupport.swift"
BRIDGES="Casberi/Casberi/Model/TokenBridges.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
for f in "$PD" "$SUPPORT" "$BRIDGES" "$REACH"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- drift guards -----------------------------------------------------------

grep -q 'if bridge == .pagerduty { return await PagerDutyIngest.refresh' "$BRIDGES" \
  || { echo "✗ TokenIngest no longer routes PagerDuty to its own sweep — the bridge lands nothing"; exit 1; }
grep -q 'api.pagerduty.com' "$REACH" \
  || { echo "✗ api.pagerduty.com is not in the reach registry — the privacy screen is wrong"; exit 1; }
# The read-only promise. A read-write PagerDuty key can TRIGGER an incident,
# which wakes whoever is on call — the highest-consequence write of any bridge
# in this catalog. Kept structurally by the key's own read-only flag, and
# mechanically here.
for verb in '"POST"' '"DELETE"' '"PATCH"' '"PUT"' 'httpMethod' 'postJSON'; do
  grep -q "$verb" "$PD" \
    && { echo "✗ PagerDutyBridge.swift now contains a WRITE ($verb) — it could page someone"; exit 1; }
done
# The versioned Accept header is REQUIRED, not politeness: v1 and v2 differ in
# the envelope, and omitting it means the shape you get is whatever their
# default is that year.
grep -q 'application/vnd.pagerduty+json;version=2' "$PD" \
  || { echo "✗ the versioned Accept header is gone — the envelope could change under us"; exit 1; }
# The cursor must advance only AFTER the rows are in the context, or a crash
# skips a window of incidents forever (the Stripe rule). Proven by ORDER in the
# shipped source.
python3 - "$PD" <<'PY'
import sys
src = open(sys.argv[1]).read()
save = src.find("if added > 0 { context.saveHonestly() }")
cursor = src.find("PagerDutyCursor.since = newest")
if save < 0 or cursor < 0:
    sys.exit("✗ could not find the save/cursor pair in PagerDutyBridge.swift")
if cursor < save:
    sys.exit("✗ the cursor advances BEFORE the rows are saved — a crash would skip a window forever")
PY
# First sight must read OPEN incidents only. Landing "Triggered" for something
# resolved days ago is inventing a moment (the Hyperliquid first-sight bug).
grep -q 'openOnly: firstPass' "$PD" \
  || { echo "✗ first sight no longer reads open-only — connecting would land stale triggers"; exit 1; }

TMP=$(mktemp -d /tmp/pagerduty-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

python3 - "$PD" "$SUPPORT" "$TMP/extracted.swift" <<'PY'
import sys
pd, support, out = sys.argv[1:4]

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
    grab(pd, "enum PagerDutyShape"),
    "",
    "enum IngestSupport {",
    grab(support, "static func titleLine"),
    "}\n",
]
open(out, "w").write("\n".join(pieces))
PY

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}

let t0 = Date(timeIntervalSince1970: 1_800_000_000)
func after(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

print("duration — how long it lasted, in a person's words")
check("41 minutes",     PagerDutyShape.duration(from: t0, to: after(41 * 60)) == "41 min")
check("1 minute",       PagerDutyShape.duration(from: t0, to: after(60)) == "1 min")
check("59 minutes",     PagerDutyShape.duration(from: t0, to: after(59 * 60)) == "59 min")
// "0 minutes" would read as a bug rather than as good news.
check("under a minute reads as words, not '0 min'",
      PagerDutyShape.duration(from: t0, to: after(30)) == "under a minute")
check("an instant resolution still reads as words",
      PagerDutyShape.duration(from: t0, to: t0) == "under a minute")
// Deliberately COARSE past the hour: "3 hr 11 min" is a precision nobody uses
// and it lengthens the title exactly where the clamp starts cutting.
check("3 hours",        PagerDutyShape.duration(from: t0, to: after(3 * 3600 + 11 * 60)) == "3 hr")
check("exactly an hour", PagerDutyShape.duration(from: t0, to: after(3600)) == "1 hr")
check("47 hours is still hours", PagerDutyShape.duration(from: t0, to: after(47 * 3600)) == "47 hr")
check("past two days, days",     PagerDutyShape.duration(from: t0, to: after(72 * 3600)) == "3 days")

print("duration — what it REFUSES to say")
// A resolution before the trigger is a clock disagreement between PagerDuty
// and whatever wrote the timestamp. "Resolved after -4 minutes" is worse than
// saying nothing, so the title falls back to a bare "Resolved".
check("a negative interval → nil", PagerDutyShape.duration(from: after(600), to: t0) == nil)
check("a missing start → nil",     PagerDutyShape.duration(from: nil, to: t0) == nil)
check("a missing end → nil",       PagerDutyShape.duration(from: t0, to: nil) == nil)
check("both missing → nil",        PagerDutyShape.duration(from: nil, to: nil) == nil)

print("refs — both halves of one incident, never colliding")
check("a trigger ref",  PagerDutyShape.triggeredRef(id: "PABC123") == "pagerduty:incident:PABC123")
check("a resolve ref",  PagerDutyShape.resolvedRef(id: "PABC123") == "pagerduty:resolved:PABC123")
// THE assertion. If these collided, the resolution would dedupe against the
// trigger and never land — so the feed would say the outage is still open,
// forever.
check("the two halves are DIFFERENT refs",
      PagerDutyShape.triggeredRef(id: "PABC123") != PagerDutyShape.resolvedRef(id: "PABC123"))
check("two incidents don't collide",
      PagerDutyShape.triggeredRef(id: "PABC124") != PagerDutyShape.triggeredRef(id: "PABC123"))

print("title — the service leads, the resolution leads harder")
check("an open incident",
      PagerDutyShape.title(service: "Checkout API", title: "Error rate above 5%",
                           resolved: false, lasted: nil)
      == "Checkout API · Error rate above 5%")
check("a resolution carries how long it took",
      PagerDutyShape.title(service: "Payments", title: "Webhook backlog",
                           resolved: true, lasted: "41 min")
      == "Resolved after 41 min · Payments · Webhook backlog")
// A resolution whose duration couldn't be computed still says it resolved —
// the fact that matters most must not depend on the fact that matters least.
check("no duration still reads as resolved",
      PagerDutyShape.title(service: "Payments", title: "Webhook backlog",
                           resolved: true, lasted: nil)
      == "Resolved · Payments · Webhook backlog")
check("no service drops the separator cleanly",
      PagerDutyShape.title(service: nil, title: "Disk full", resolved: false, lasted: nil)
      == "Disk full")
check("an empty service is dropped too",
      PagerDutyShape.title(service: "  ", title: "Disk full", resolved: true, lasted: "2 hr")
      == "Resolved after 2 hr · Disk full")

print("the 80-character clamp — why the resolution LEADS")
// An incident title is machine-generated by whatever monitor fired it, which
// is exactly the long tail that eats a trailing clause. A resolved incident
// reading as one still burning is the §83 fake status, and here it is the
// difference between going back to sleep and getting out of bed.
let longTitle = "HTTP 5xx error rate on checkout-api exceeded 5% over a 10 minute rolling window"
let composed = PagerDutyShape.title(service: "Checkout API", title: longTitle,
                                    resolved: true, lasted: "41 min")
check("the composed title really does overflow (or this proves nothing)", composed.count > 80)
let shipped = IngestSupport.titleLine(composed)
check("clamped, the resolution SURVIVES", shipped.hasPrefix("Resolved after 41 min · "))
check("clamped, it is truncated (so the clamp really ran)", shipped.hasSuffix("…"))
let trailing = IngestSupport.titleLine("Checkout API · \(longTitle) · Resolved after 41 min")
check("trailing, the resolution would be EATEN", !trailing.contains("Resolved"))

print("")
if failures == 0 {
    print("✓ pagerduty self-test: all assertions passed")
} else {
    print("✗ pagerduty self-test: \(failures) assertion(s) failed")
    exit(1)
}
SWIFT

swiftc -O -o "$TMP/run" "$TMP/extracted.swift" "$TMP/main.swift" 2>&1 \
  | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ the extracted PagerDuty logic did not compile"; exit 1; }
"$TMP/run"
