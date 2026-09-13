#!/usr/bin/env python3
"""Design-template audit (prd §715, 2026-09-13).

WHY THIS EXISTS. User: "where if anywhere in the app do we have hand rolled
things we should be using templates for" → "do all". The sweep found the
design system mostly honoured and a dozen clusters drawn by hand beside it,
most of them copy-paste twins. §715 extracted what was missing into
`Design/` and moved the call sites. Most of those shapes cannot be told apart
from a legitimate one by text (a chevron row vs a pager, a capsule button vs
a bar), so they are NOT checked here. Three can, objectively:

  A. A plain indeterminate `ProgressView()` outside `Design/` → `DSSpinner`.
     `ProgressView(value:)` is a different control and is not matched.
  B. `.presentationDetents([.medium, .large]` outside `Design/` → the reading
     sheet's chassis, `dsReadSheet(detent:)`.

A third check — a copy capsule's "Copied"/"Copy" state pair → `DSCopyCapsule`
— was written and REMOVED the same day. The bare word matched nine sites of
which two were capsules (the rest were toasts and longer verbs), and the
exact pair matched only `AddressCopyButton`, which is itself a reusable
three-style copy control and not a duplicate. A check with no true positive
left is a check that can only ever cry wolf.

Scans the app target only: `Design/` is app-only, so a finding in the share
extension or the widgets would be a demand nobody could satisfy.

`--self-test` proves each check fires on a planted file and stays quiet on
the template's own shapes.
"""
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = "Casberi/Casberi"

CHECKS = [
    ("A", re.compile(r"\bProgressView\(\s*\)"),
     "a plain ProgressView() — use DSSpinner(size:onFill:)"),
    ("B", re.compile(r"\.presentationDetents\(\s*\[\s*\.medium\s*,\s*\.large\s*\]"),
     "the reading sheet's detents by hand — use .dsReadSheet(detent:)"),
]


def strip_comments(text: str) -> str:
    """Comments out, strings kept, line breaks preserved."""
    out, i, n = [], 0, len(text)
    in_block = in_string = False
    while i < n:
        ch, nxt = text[i], text[i + 1] if i + 1 < n else ""
        if in_block:
            if ch == "*" and nxt == "/":
                in_block = False
                i += 2
                continue
            out.append("\n" if ch == "\n" else "")
            i += 1
            continue
        if in_string:
            if ch == "\\":
                out.append(text[i:i + 2])
                i += 2
                continue
            if ch == '"' or ch == "\n":
                in_string = False
            out.append(ch)
            i += 1
            continue
        if ch == '"':
            in_string = True
            out.append(ch)
            i += 1
            continue
        if ch == "/" and nxt == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if ch == "/" and nxt == "*":
            in_block = True
            i += 2
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def scan(root: Path):
    findings = []
    app = root / APP
    for path in sorted(app.rglob("*.swift")):
        rel = path.relative_to(app)
        if rel.parts and rel.parts[0] == "Design":
            continue
        lines = strip_comments(path.read_text(encoding="utf-8")).split("\n")
        for no, line in enumerate(lines, 1):
            for tag, rx, why in CHECKS:
                if rx.search(line):
                    findings.append((tag, f"{APP}/{rel}:{no}", why))
    return findings


def self_test() -> int:
    planted = {
        "Screens/Bad.swift": (
            'struct Bad: View { var body: some View { VStack {\n'
            '  ProgressView()\n'
            '}.presentationDetents([.medium, .large]) } }\n'),
        "Screens/Good.swift": (
            '// ProgressView() and .presentationDetents([.medium, .large]) in a comment\n'
            'struct Good: View { var body: some View { VStack {\n'
            '  DSSpinner()\n  ProgressView(value: 0.5)\n'
            '}.dsReadSheet().presentationDetents([.large]) } }\n'),
        "Design/DSSpinner.swift": 'struct DSSpinner { var body: some View { ProgressView() } }\n',
    }
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        for rel, body in planted.items():
            p = root / APP / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(body)
        got = scan(root)
    tags = sorted(t for t, _, _ in got)
    files = {loc.split(":")[0] for _, loc, _ in got}
    ok = tags == ["A", "B"] and files == {f"{APP}/Screens/Bad.swift"}
    print(f"ds-template-audit self-test: {'OK' if ok else 'FAIL'} ({tags}, {sorted(files)})")
    return 0 if ok else 1


def main() -> int:
    if "--self-test" in sys.argv:
        return self_test()
    findings = scan(ROOT)
    for tag, loc, why in findings:
        print(f"  [{tag}] {loc}: {why}")
    if findings:
        print(f"ds-template-audit: FAIL ({len(findings)} hand-rolled template sites)")
        return 1
    print("ds-template-audit: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
