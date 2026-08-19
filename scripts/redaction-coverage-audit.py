#!/usr/bin/env python3
"""Redaction coverage audit (prd §277).

`SecretScan` is well tested — `secret-scan-selftest.py` runs 28 fixtures and a
mutation pass proving every threshold is load-bearing. All of that proves the
CLASSIFIER still classifies. None of it proves it is still CALLED.

The tripwire is kept by ~20 call sites spread across eight files, and nothing
in the tree asserts one of them still exists. Delete a single
`SecretScan.redacted(` and every check in `verify.sh` stays green while the
app quietly starts handing a recovery phrase to a provider's context window,
to CoreSpotlight, or to whatever program is on the other end of the local
MCP listener.

That is the same shape as the undisclosed-host gap that shipped in build 214,
and it gets the same answer this codebase gives every rule it has re-broken:
a check, not a written reminder. This is `receipts-coverage-audit.py`'s idiom
pointed at redaction instead of the network ledger.

THREE CHECKS.

  1. REGISTRY (file-scoped, coarse on purpose). Every file in EGRESS must
     still call `SecretScan` in CODE. Coarse because pairing a redaction with
     the string it protects means parsing Swift, and a declared egress file
     that never names the scrubber at all is the finding either way.

  2. PER-SITE (sharp). Inside an egress file, a person's own free text that is
     INTERPOLATED INTO A STRING must be scrubbed on that line or within a few
     lines of it. This is the check that catches ONE dropped call rather than
     a whole file's worth, and it earned itself on its first run: it found
     `SearchCasberiIntent` building the dialog Siri SPEAKS out of raw titles
     while the snippet rows beside it, and both of `AskCasberiIntent`'s paths,
     all redacted correctly.

     The interpolation rule is what makes it usable rather than noise, and it
     is MEASURED, not guessed. Matching every read of `.title`/`.content`
     flagged 13 sites of which 12 were ranking inputs, local comparisons and
     stored properties that never leave — a lint that cries wolf gets turned
     off within a week. Text composed into a string is text on its way OUT;
     text handed to `words()` or compared to a needle is not. Two consequences
     worth knowing: `.content` and `.title` are ordinary property names
     (`AgentStep.Result.content` is a tool result, already scrubbed upstream),
     and the interpolation rule drops all of those for free.

  3. DRIFT. A file OUTSIDE the registry that scrubs in code is evidence the
     registry has gone stale — a new egress path was written, its author got
     the redaction right, and nobody added it here. Reported so the registry
     maintains itself instead of decaying into the eight files true in 2026.

COMMENTS ARE STRIPPED BEFORE ANY CHECK, and that is not fussiness. Three
files in this tree DOCUMENT the rule by naming the very API it governs —
`DSPasteboard` carries a paragraph on why it deliberately does NOT auto-scrub,
`AccountDetailSheet` says the tripwire out loud in user-facing copy. A check
reading raw source scores all three as compliant on prose alone. (The
Obsidian/Cursor lesson, earned again here on this audit's first run: before
stripping, check 1 passed against a `DSPasteboard` that has never once called
`SecretScan`.)

WHAT THIS DELIBERATELY DOES NOT CHECK, so it can't become a lint that cries
wolf:

  · Whether the redaction is CORRECT. That is `secret-scan-selftest.py`'s job
    and it does it far better than a regex could.
  · Any file outside the registry. Every screen in the app reads `thing.title`
    and must not scrub it — the feed is not an egress path, and a person's own
    corpus on their own screen is the one place the text belongs. Scoping by
    registry rather than by field read is what keeps the finding count at the
    handful of places that actually leave.
  · The on-device model, which is exempt BY RULING (prd §277) — it never
    leaves the device, and "what's my wifi password?" is a fair question to
    ask your own corpus.

Usage:  scripts/redaction-coverage-audit.py [--self-test]
Exit 0 = clean.
"""

import re
import sys
import pathlib
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = [ROOT / "Casberi/Casberi", ROOT / "Casberi/Shared",
           ROOT / "Casberi/ShareExtension", ROOT / "Casberi/CasberiWidgets"]

# Every path by which a person's own corpus text leaves this process, with
# what it leaves FOR. Adding a file here is a claim that text crosses a
# boundary in it; removing one is a claim that it no longer does.
EGRESS = {
    "SpotlightIndex.swift":
        "CoreSpotlight AND the `ThingEntity` semantic index Siri and Apple "
        "Intelligence ground on — one edit covers both",
    "ThingEntity.swift":
        "the App Intents display representation, rendered by the system",
    "CasberiIntents.swift":
        "Shortcuts and Siri grounding",
    "AgentAnswer.swift":
        "the keyed provider's request body — the candidates a paid model is "
        "asked to read",
    "AgentCorpusTools.swift":
        "tool results, which are corpus text fetched AFTER `synthesize`'s own "
        "gate and would otherwise sail past the tripwire entirely",
    "AgentContext.swift":
        "the markdown clipboard hand-off to any agent on the machine",
    "MCPServer.swift":
        "the loopback JSON-RPC listener — another program's context window",
    "MCPTools.swift":
        "the corpus reads behind the MCP tools",
}

# A person's own free text, as stored on `Thing`. NOT `source`/`sourceRef`/
# addresses — those are ours or the chain's, never something somebody typed.
SENSITIVE = r"\.(?:title|content|summary|postText|enrichedText)\b"

# EMITTED, not merely read: the field sits inside a `\(…)` interpolation, so
# it is being composed into a string somebody or something else will see.
FIELD = re.compile(r"\\\(" + r"[^)]*" + SENSITIVE)
SCRUB = re.compile(r"SecretScan\s*\.")
# How far a scrub may sit from the read it protects. Small on purpose: far
# enough for `let title = x.title` / `SecretScan.redacted(title)` to pair,
# close enough that the pairing is obvious to a reader.
WINDOW = 4

# Files that scrub but are NOT egress paths, so check 3 must not ask for a
# registry entry that would be a false claim. An entry here says "text is
# scrubbed in this file and yet nothing leaves the process by it".
NOT_EGRESS = {
    "ProbeHooks.swift":
        "`-secretScanProbe`, the tripwire's own DEBUG probe. It scrubs for the "
        "opposite reason the registry exists: the probe for a feature that "
        "keeps secrets out of logs must not print one. Nothing leaves the "
        "process — it NSLogs, and the arg is on `secretArgKeys` so even "
        "`probeArgs:` cannot echo the sample.",
}

# CHECK 4 — exact pairings, for the boundaries where a miss is worst and where
# neither of the checks above can see one. Check 1 is file-scoped, so it stays
# green while one of three calls goes; check 2 only sees text INTERPOLATED into
# a string, so an ASSIGNMENT to an outbound sink is invisible to it.
#
# `SpotlightIndex` is exactly that shape and is the single most load-bearing
# entry in this file — prd §277 routes BOTH CoreSpotlight and `ThingEntity`'s
# semantic index through `attributeSet`, so one edit there is the whole
# donation surface. Deleting its `redacted` survived checks 1–3 cleanly when
# this audit was first mutation-tested against the real tree; that is why this
# check exists rather than a wider version of check 2, which would have bought
# the same catch at the price of a dozen false positives a week.
#
# Keep these literal and few. A guard is worth its maintenance only where the
# sink cannot be inferred from the shape of the line.
REQUIRED = {
    "SpotlightIndex.swift": [
        ("attrs.title = SecretScan.redacted(thing.title)",
         "the donated title — CoreSpotlight and the semantic index both"),
        ("SecretScan.redacted(thing.content)",
         "the donated body"),
        ("SecretScan.safeTags(thing.tags)",
         "the donated keywords, which are the person's own tags"),
    ],
    "ThingEntity.swift": [
        ("SecretScan.redacted(title)",
         "the display representation — the entity stores raw text and scrubs "
         "HERE, so this call is the only thing standing between the system's "
         "renderer and a stored secret"),
    ],
    "AgentAnswer.swift": [
        ("SecretScan.redacted(candidate.title)", "the candidate title sent to a paid provider"),
        ("SecretScan.redacted(candidate.note)", "the candidate excerpt sent to a paid provider"),
    ],
    "MCPServer.swift": [
        ("SecretScan.redacted(thing.title)",
         "the only scrub between the corpus and another program on the machine"),
    ],
}

# Files that read a sensitive field inside an egress file and legitimately do
# NOT scrub it. Each entry is a conscious ruling, and the reason is the part
# that gets skipped when nothing enforces it.
SITE_EXEMPT = {
    # A haystack built for a local `contains` test. It is interpolated, so the
    # rule sees it, but the string is never emitted — it is compared and
    # dropped. Scrubbing it would be worse than useless: it would make a
    # search for a password field's own label stop matching the row.
    ("CasberiIntents.swift", "haystack"): "local match input, never emitted",
}


def strip_comments(src):
    """Comments out, string literals preserved as-is.

    Naive on purpose — it is not a Swift parser. It must never turn a comment
    into apparent compliance, and it must never eat real code. A `//` inside a
    string literal (a URL) is left alone by tracking quotes.
    """
    out = []
    for line in src.splitlines():
        cleaned, in_str, i = [], False, 0
        while i < len(line):
            c = line[i]
            if c == '"' and (i == 0 or line[i - 1] != "\\"):
                in_str = not in_str
            if not in_str and line.startswith("//", i):
                break
            cleaned.append(c)
            i += 1
        out.append("".join(cleaned))
    src = "\n".join(out)
    return re.sub(r"/\*.*?\*/", "", src, flags=re.S)


def audit(paths, registry=EGRESS, check_drift=True, required=None):
    findings = []
    seen = set()

    for root in paths:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.swift")):
            code = strip_comments(path.read_text(errors="ignore"))
            lines = code.splitlines()
            try:
                rel = path.relative_to(ROOT)
            except ValueError:
                rel = path

            if path.name not in registry:
                # CHECK 3 — drift. A scrub outside the registry means a new
                # egress path exists that nobody declared here.
                if (check_drift and path.name not in NOT_EGRESS
                        and re.search(r"SecretScan\s*\.\s*(?:redacted|safeTags)\b", code)):
                    findings.append(
                        f"{rel}: scrubs with SecretScan but is not in EGRESS — "
                        f"if corpus text leaves the process here, add it with "
                        f"the reason; if it does not, this call is misleading")
                continue

            seen.add(path.name)

            # CHECK 1 — the registry file still names the scrubber at all.
            if not SCRUB.search(code):
                findings.append(
                    f"{rel}: declared an egress path ({registry[path.name]}) "
                    f"but never calls SecretScan — corpus text leaves here "
                    f"unscrubbed")
                continue

            # CHECK 4 — exact pairings.
            for needle, why in (REQUIRED if required is None else required).get(path.name, ()):
                if needle not in code:
                    findings.append(
                        f"{rel}: `{needle}` is gone — {why} ({registry[path.name]})")

            # CHECK 2 — per-site.
            for i, line in enumerate(lines):
                if not FIELD.search(line):
                    continue
                if any(k[0] == path.name and k[1] in line for k in SITE_EXEMPT):
                    continue
                lo, hi = max(0, i - WINDOW), min(len(lines), i + WINDOW + 1)
                if SCRUB.search("\n".join(lines[lo:hi])):
                    continue
                findings.append(
                    f"{rel}:{i + 1}: interpolates a person's own text into a "
                    f"string on an egress path with no SecretScan within "
                    f"{WINDOW} lines — {registry[path.name]}")

    for name, why in (NOT_EGRESS if check_drift else {}).items():
        hits = [p for root in paths if root.exists()
                for p in root.rglob(name)]
        if hits and not any(re.search(r"SecretScan\s*\.", strip_comments(
                h.read_text(errors="ignore"))) for h in hits):
            findings.append(
                f"{name}: in NOT_EGRESS ({why}) but no longer calls SecretScan "
                f"at all — the exemption now excuses nothing and should go")

    for name in registry:
        if name not in seen:
            findings.append(
                f"{name}: in EGRESS but not found in the tree — the file was "
                f"renamed or deleted and this registry entry now guards nothing")
    return findings


def self_test():
    cases = {
        # name: (registry, body, should_flag, why)
        "Gone.swift": ({"Gone.swift": "a boundary"},
                       "func out() -> String { thing.title }\n",
                       True, "an egress file that never calls SecretScan"),
        "Scrubbed.swift": ({"Scrubbed.swift": "a boundary"},
                           "func out() -> String { SecretScan.redacted(thing.title) }\n",
                           False, "a scrubbed egress read"),
        "Paired.swift": ({"Paired.swift": "a boundary"},
                         "let t = thing.title\n"
                         "return SecretScan.redacted(t)\n",
                         False, "a scrub a couple of lines below the read"),
        "TooFar.swift": ({"TooFar.swift": "a boundary"},
                         'let t = "\\(thing.title)"\n' + "let filler = 1\n" * 9 +
                         "return SecretScan.redacted(t)\n",
                         True, "a scrub too far away to be a pair"),
        "OneDropped.swift": ({"OneDropped.swift": "a boundary"},
                             'let a = SecretScan.redacted(thing.title)\n'
                             + "let filler = 1\n" * 9 +
                             'let b = "\\(thing.content)"\n',
                             True, "ONE dropped call in an otherwise scrubbed file"),
        # The narrowing that makes check 2 usable, pinned so nobody widens it
        # back to every field read and re-earns the 12 false positives.
        "Ranking.swift": ({"Ranking.swift": "a boundary"},
                          "let t = SecretScan.redacted(thing.title)\n"
                          + "let filler = 1\n" * 9 +
                          "let score = words(snap.title).count\n"
                          "let hit = other.title.lowercased() == needle\n",
                          False, "reads used for ranking and matching, never emitted"),
        "Stored.swift": ({"Stored.swift": "a boundary"},
                         "let t = SecretScan.redacted(thing.title)\n"
                         + "let filler = 1\n" * 9 +
                         "content = thing.content\n",
                         False, "a stored property assignment, scrubbed at its own display boundary"),
        # The bug this audit's own first run had: prose naming the API scoring
        # as compliance.
        "OnlyComment.swift": ({"OnlyComment.swift": "a boundary"},
                              "// SecretScan is deliberately not used here.\n"
                              "func out() -> String { thing.title }\n",
                              True, "a file whose only SecretScan is a comment"),
        "BlockComment.swift": ({"BlockComment.swift": "a boundary"},
                               "/* SecretScan.redacted covers this */\n"
                               "func out() -> String { thing.title }\n",
                               True, "a file whose only SecretScan is a block comment"),
        # A `//` inside a string literal must not truncate real code.
        "URLInString.swift": ({"URLInString.swift": "a boundary"},
                              'let u = "https://x.example"; '
                              'let t = SecretScan.redacted(thing.title)\n',
                              False, "a scrub sharing a line with a URL literal"),
        # The mutation that survived checks 1-3 on the real tree: an
        # assignment, in a file with other scrubs still present.
        "Assign.swift": ({"Assign.swift": "a boundary"},
                         "attrs.title = thing.title\n"
                         "attrs.body = SecretScan.redacted(thing.content)\n",
                         True, "an outbound ASSIGNMENT stripped of its scrub"),
        "Drift.swift": ({}, "let t = SecretScan.redacted(thing.title)\n",
                        True, "a scrub in a file missing from the registry"),
        "Screen.swift": ({}, "Text(thing.title)\n",
                         False, "an ordinary screen reading a title"),
        "Renamed.swift": ({"Vanished.swift": "a boundary"}, "let x = 1\n",
                          True, "a registry entry whose file no longer exists"),
    }
    ok = True
    with tempfile.TemporaryDirectory() as tmp:
        for name, (registry, body, should_flag, why) in cases.items():
            d = pathlib.Path(tmp) / name.lower().replace(".swift", "")
            d.mkdir()
            (d / name).write_text(body)
            required = ({"Assign.swift": [
                ("attrs.title = SecretScan.redacted(thing.title)", "the donated title")]}
                if name == "Assign.swift" else {})
            flagged = bool(audit([d], registry=registry, required=required))
            if flagged != should_flag:
                ok = False
            print(f"  {'ok  ' if flagged == should_flag else 'FAIL'} "
                  f"{'flags' if should_flag else 'passes'} {why}")
    return ok


if "--self-test" in sys.argv:
    print("redaction-coverage self-test")
    sys.exit(0 if self_test() else 1)

problems = audit(SOURCES)
if problems:
    print("✗ redaction coverage:")
    for p in problems:
        print(f"  {p}")
    sys.exit(1)
print(f"✓ redaction coverage: {len(EGRESS)} egress paths, all scrubbed")
