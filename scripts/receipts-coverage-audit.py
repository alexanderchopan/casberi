#!/usr/bin/env python3
"""Network-receipts coverage audit (prd §277).

`NetworkReceiptsScreen` tells the person what Casberi actually reached, and
its own copy names what it cannot see. That claim is only true while every
request either rides an instrumented transport or is on the short, stated
list of exceptions — and the failure mode is silent: a new bridge written
with `URLSession.shared.data(for:)` simply never appears in the receipts, and
the screen goes on implying it saw everything.

That is the same shape as the undisclosed-host gap that shipped in build 214,
which is why this is mechanical rather than remembered. It shipped WRONG once
already: the first version of the ledger claimed "the shared connection every
app connection uses" while ~20 bridges called `URLSession.shared` directly.

The rule: every `URLSession.shared.data/bytes/download` call in app source
must have a `NetworkLedger.shared.record(…)` within the few lines above it,
or be listed in NOT_RECORDED with a reason that matches what the screen says.

Usage:  scripts/receipts-coverage-audit.py [--self-test]
Exit 0 = clean.
"""

import re
import sys
import pathlib
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = [ROOT / "Casberi/Casberi", ROOT / "Casberi/Shared",
           ROOT / "Casberi/ShareExtension", ROOT / "Casberi/CasberiWidgets"]

CALL = re.compile(r"URLSession\.shared\.(?:data|bytes|download)\s*\(")
RECORD = re.compile(r"NetworkLedger\.shared\.record\s*\(")
# How far above a call the record may sit. Small on purpose: far enough for a
# multi-clause guard to be split, close enough that it is obviously paired.
LOOKBACK = 6

# Requests the receipts screen explicitly says it does NOT record. Each entry
# is a promise about the COPY as much as the code — if you remove one from
# here, the screen's footer has to change too.
NOT_RECORDED = {
    "ThingContent.swift": "pictures loaded into a row as you scroll",
    "ShapedRows.swift": "pictures loaded into a row as you scroll",
}

# The funnel itself must keep its recorder, or all ~167 bridge call sites go
# dark at once with nothing else in the tree changing.
FUNNEL = ("Casberi/Casberi/Model/IngestSupport.swift", "send")


def audit(paths, check_funnel=True):
    findings = []
    for root in paths:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.swift")):
            if path.name in NOT_RECORDED:
                continue
            lines = path.read_text(errors="ignore").splitlines()
            for i, line in enumerate(lines):
                if not CALL.search(line):
                    continue
                window = "\n".join(lines[max(0, i - LOOKBACK):i])
                if RECORD.search(window):
                    continue
                try:
                    rel = path.relative_to(ROOT)
                except ValueError:
                    rel = path
                findings.append(
                    f"{rel}:{i + 1}: reaches the network with no "
                    f"NetworkLedger.shared.record(…) above it — it would be "
                    f"invisible in \"What it actually reached\"")

    if check_funnel:
        funnel = ROOT / FUNNEL[0]
        if funnel.exists():
            src = funnel.read_text(errors="ignore")
            m = re.search(rf"func {FUNNEL[1]}\(.*?\n(.*?)\n    \}}", src, re.S)
            if not m or not RECORD.search(m.group(1)):
                findings.append(
                    f"{FUNNEL[0]}: `{FUNNEL[1]}` no longer records — every "
                    f"bridge that rides IngestSupport would vanish from the "
                    f"receipts at once")
    return findings


def self_test():
    cases = {
        "Bare.swift": ("let (d, r) = try? await URLSession.shared.data(for: request)\n",
                       True, "an uninstrumented request"),
        "Recorded.swift": ("NetworkLedger.shared.record(request)\n"
                           "let (d, r) = try? await URLSession.shared.data(for: request)\n",
                           False, "a recorded request"),
        "TooFar.swift": ("NetworkLedger.shared.record(request)\n" + "// filler\n" * 8 +
                         "let (d, r) = try? await URLSession.shared.data(for: request)\n",
                         True, "a record too far above to be a pair"),
        "NoNetwork.swift": ("let x = 1\n", False, "a file that reaches nothing"),
    }
    ok = True
    with tempfile.TemporaryDirectory() as tmp:
        for name, (body, should_flag, why) in cases.items():
            d = pathlib.Path(tmp) / name.lower()
            d.mkdir()
            (d / name).write_text(body)
            flagged = bool(audit([d], check_funnel=False))
            if flagged != should_flag:
                ok = False
            print(f"  {'ok  ' if flagged == should_flag else 'FAIL'} "
                  f"{'flags' if should_flag else 'passes'} {why}")
    return ok


if "--self-test" in sys.argv:
    print("receipts-coverage self-test")
    sys.exit(0 if self_test() else 1)

problems = audit(SOURCES)
if problems:
    print("✗ network receipts coverage findings:")
    for p in problems:
        print(f"  {p}")
    print("\nAdd NetworkLedger.shared.record(request|url) above the call, or "
          "list the file in NOT_RECORDED and change the receipts screen's "
          "footer to match.")
    sys.exit(1)
print("✓ receipts coverage: every network call is recorded or explicitly excepted")
