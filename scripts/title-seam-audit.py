#!/usr/bin/env python3
"""A TITLE CARRIES NO SEPARATORS (prd §915).

A thing's title names its OBJECT. What the bridge knows beside the object —
the verb, the kind, the board, the ticker, the game — is a QUALIFIER, and the
row draws it on the line under the name. The one seam between the two is
` — `, joined by `TitleSeam.join` and split by `TitleSeam.split` at every
drawing site (the band, the cover, the media well, the sheet). A bridge that
composes a title with ` · ` is putting two facts in one slot, which is what
"Alarm · prod-api-5xx", "Opened · Fix login · casberi" and "Bitcoin · $BTC"
all were on 2026-09-24.

**Why a script and not a memory.** Every failure this catches renders as a
perfectly ordinary row: the words are all there, in one slot instead of two.
Nothing breaks a build, trips the ramp audit, or shows in a screen sweep, and
the next bridge is written by copying the last one — which is how fifteen
bridges came to spell the same shape fifteen ways.

Two checks.

**(1) No composed title carries ` · `.** In `Model/` and `Shared/`, a
`title:` argument or a `title =` assignment whose string literal contains
` · ` is a finding — unless the file is on the allowance below, with its
reason, and its count has not grown. A MONEY title ("Ada Lovelace · $49.00")
is allowed by design: `BandRow.titleMoney` reads the figure out of it into
the trailing slot (§900), so the dot there is a seam the row already
understands. A stale allowance (fewer than allowed) fails too, so the list
shrinks as bridges are converted and cannot quietly overstate.

**(2) `TitleSeam` is the one spelling of the seam.** No file in `Model/`,
`Screens/` or `Design/` may split a title on `" — "` by hand
(`components(separatedBy: " — ")`); `MusicRow` and the media cover did, and a
third copy is the drift this file exists to stop.

**STATED CEILINGS.**

  • It cannot tell an object from a qualifier. A bridge that joins the two
    the wrong way round ("Opened — Fix login") passes here and is wrong on
    screen; the harnesses that pin a bridge's title (`github-event-selftest`,
    `appstoreconnect-selftest`, `radicle-selftest`) are where the ORDER is
    held.
  • It reads string literals only. A title built from a joined array
    (`parts.joined(separator: " · ")`) is invisible here unless the literal
    appears in the same statement.
"""

import re
import sys
import tempfile
from pathlib import Path

ROOTS = ("Casberi/Casberi/Model", "Casberi/Shared")
SPLIT_ROOTS = ("Casberi/Casberi/Model", "Casberi/Casberi/Screens", "Casberi/Casberi/Design")

# file → (allowed count of dotted title literals, reason). A count is a
# CEILING and a FLOOR: over it is a new dotted title, under it is a stale
# allowance to lower.
ALLOWED = {
    # Money titles: the dot is read back by `BandRow.titleMoney` (§900) and
    # the figure lands in the trailing slot. Not a qualifier.
    "PrivacyBridge.swift": (1, "merchant · money — titleMoney's own seam (§900)"),
    "BitrefillBridge.swift": (1, "the refill's money tail (titleMoney, §900)"),
    "LinkTitle.swift": (1, "a product page's price tail (titleMoney, §900)"),
    "DodoPaymentsBridge.swift": (4, "name · money and verb · money — every dot is the money tail titleMoney reads (§900)"),
    "PolarBridge.swift": (2, "a refund's and a subscription's money tail (titleMoney, §900)"),
    "StripeBridge.swift": (5, "verb · money, then the dispute's reason and the invoice's customer after the figure — money grammar (§900, §912)"),
    "PostHogBridge.swift": (1, "an annotation's delta — a figure beside the note, not a kind"),
    "WalletIngest.swift": (1, "the ledger's own grammar: `Moved 1 ETH · Alice → Bob` is one sentence, and the amount is the row's trailing figure (§158)"),
    # The demo's money rows and its receipts (titleMoney), the X archive's
    # `To @handle · words` reply lead (read back by `repliedTo`), and the
    # Walletbeat incident's severity, which mirrors the bridge's own line.
    "DemoSeedAll.swift": (15, "money titles the demo lands for Polar, Dodo, Stripe, Bitrefill and the cards (titleMoney), the X reply lead the archive parses back, and Walletbeat's severity"),
}

# A `title:` argument or a `title =` assignment and the first string literal
# on its line, through any wrapper (`titleLine(`, `String(localized:`, a
# `.map { "…" }`); and the demo seeder's `row(.kind, "…"` whose second
# argument IS the title.
TITLE_LITERAL = re.compile(r'(?:\btitle(?::|\s*\+?=)|\brow\(\.\w+,)[^"\n]{0,80}"((?:[^"\\]|\\.)*)"')
HAND_SPLIT = re.compile(r'components\(separatedBy:\s*" (?:—|\\u\{2014\}) "\)')


def strip_comments(src: str) -> str:
    out = []
    for line in src.splitlines():
        s = line.lstrip()
        if s.startswith("//"):
            out.append("")
        else:
            out.append(line)
    return "\n".join(out)


def dotted_titles(src: str) -> list[str]:
    """Every title literal in the source that carries ` · `."""
    hits = []
    for m in TITLE_LITERAL.finditer(strip_comments(src)):
        # The literal AFTER `TitleSeam.join(object,` is the qualifier, whose
        # own dots are the line's ("Opened · casberi"), never a title's.
        if "TitleSeam.join(" in m.group(0):
            continue
        if " · " in m.group(1):
            hits.append(m.group(1))
    return hits


def audit(files: dict[str, str]) -> list[str]:
    """files: relative path → text. Returns findings."""
    findings = []
    seen = set()
    for path, src in files.items():
        name = Path(path).name
        if name == "TitleSeam.swift":
            continue
        under_roots = any(path.startswith(r) for r in ROOTS)
        if under_roots:
            hits = dotted_titles(src)
            allowed, reason = ALLOWED.get(name, (0, ""))
            seen.add(name)
            if len(hits) > allowed:
                shown = "; ".join(f'"{h}"' for h in hits[:4])
                findings.append(
                    f"{path}: {len(hits)} title literal(s) carry ` · ` (allowed {allowed}"
                    f"{' — ' + reason if reason else ''}) — a qualifier goes after the seam,"
                    f" `TitleSeam.join(object, qualifier)`: {shown}")
            elif len(hits) < allowed:
                findings.append(
                    f"{path}: {len(hits)} dotted title literal(s), allowance says {allowed} —"
                    f" lower the allowance in title-seam-audit.py")
        if any(path.startswith(r) for r in SPLIT_ROOTS):
            n = len(HAND_SPLIT.findall(strip_comments(src)))
            if n:
                findings.append(
                    f"{path}: splits a title on \" — \" by hand ({n}×) — read `TitleSeam.split`")
    for name, (allowed, _) in ALLOWED.items():
        if name not in seen and allowed:
            findings.append(f"{name}: on the allowance list but not in the tree — remove the row")
    return findings


def self_test() -> bool:
    ok = True

    def expect(label, cond):
        nonlocal ok
        print(f"  {'✓' if cond else '✗'} {label}")
        ok = ok and cond

    clean = {
        "Casberi/Casberi/Model/Good.swift": 'let t = Thing(title: TitleSeam.join(name, verb), content: "")\nlet line = "a · b"\n',
        "Casberi/Casberi/Model/PrivacyBridge.swift": 'let title = cents.flatMap(money).map { "\\(name) · \\($0)" } ?? name\n',
    }
    # Fill every other allowance so the self-test's tree is not "stale".
    for name, (allowed, _) in ALLOWED.items():
        key = f"Casberi/Casberi/Model/{name}"
        if key not in clean:
            clean[key] = ("title: \"a · b\"\n" * allowed)
    expect("a clean tree has no findings", audit(clean) == [])

    joined = dict(clean)
    joined["Casberi/Casberi/Model/Good.swift"] = 'title: TitleSeam.join(title, "\\(verb) · \\(repo)"),\n'
    expect("a qualifier handed to the seam is not a title", audit(joined) == [])

    dotted = dict(clean)
    dotted["Casberi/Casberi/Model/Good.swift"] = 'let t = Thing(title: "Alarm · \\(name)", content: "")\n'
    f = audit(dotted)
    expect("a dotted title in a new file is a finding", len(f) == 1 and "Good.swift" in f[0])

    seeded = dict(clean)
    seeded["Casberi/Casberi/Model/Good.swift"] = 'out.append(row(.link, "Alarm · prod-api-5xx", source: "AWS"))\n'
    expect("the demo seeder's row title is read", len(audit(seeded)) == 1)

    mapped = dict(clean)
    mapped["Casberi/Casberi/Model/Good.swift"] = 'title: ident.map { "\\($0) · \\(title)" } ?? title,\n'
    expect("a title built through a map is read", len(audit(mapped)) == 1)

    localized = dict(clean)
    localized["Casberi/Casberi/Model/Good.swift"] = 'let title = String(localized: "Failed · \\(pipeline)")\n'
    expect("a localized dotted title is a finding", len(audit(localized)) == 1)

    grown = dict(clean)
    grown["Casberi/Casberi/Model/PrivacyBridge.swift"] += 'let t2 = "\\(x) · \\(y)"\ntitle: "\\(a) · \\(b)"\n'
    expect("an allowance that grew is a finding", any("PrivacyBridge" in x for x in audit(grown)))

    stale = dict(clean)
    stale["Casberi/Casberi/Model/PrivacyBridge.swift"] = "let title = name\n"
    expect("a stale allowance is a finding", any("lower the allowance" in x for x in audit(stale)))

    commented = dict(clean)
    commented["Casberi/Casberi/Model/Good.swift"] = '// title: "Alarm · \\(name)"\n'
    expect("a comment is not a title", audit(commented) == [])

    hand = dict(clean)
    hand["Casberi/Casberi/Screens/Row.swift"] = 'let comps = thing.title.components(separatedBy: " — ")\n'
    expect("a hand split of the seam is a finding", any("by hand" in x for x in audit(hand)))

    outside = dict(clean)
    outside["Casberi/Casberi/Shell/Probe.swift"] = 'title: "a · b"\n'
    expect("a file outside the roots is not read", audit(outside) == [])
    return ok


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    print("title-seam-audit self-test")
    if not self_test():
        print("SELF-TEST FAILED")
        return 1
    if "--self-test" in sys.argv:
        print("  self-test passed")
        return 0
    files = {}
    for r in set(ROOTS + SPLIT_ROOTS):
        for p in sorted((root / r).rglob("*.swift")):
            files[str(p.relative_to(root))] = p.read_text(encoding="utf-8", errors="replace")
    findings = audit(files)
    if findings:
        print(f"title-seam-audit: {len(findings)} finding(s)")
        for f in findings:
            print(f"  ✗ {f}")
        return 1
    print(f"title-seam-audit: clean — {len(files)} files, no dotted title outside the money allowances, one seam")
    return 0


if __name__ == "__main__":
    sys.exit(main())
