#!/usr/bin/env python3
"""Licenses audit (2026-10-30): every library Settings › Licenses lists has
its line, and every line names a library.

`Resources/Licenses.md` is the one text the app ships; `Screens/LicensePage.swift`
splits it at its `# ` lines and draws each named section as a row whose second
line ("MIT · Darren Ford") comes from `Licenses.lines`. A library added to the
file with no line draws its name alone, and a line whose library left the file
is a string with no reader (prd §799). A library `Licenses.underApache` names
must point at the Apache text, or its page appends a license it does not use.

Usage: scripts/licenses-audit.py [--self-test]
"""
import pathlib, re, sys, tempfile, shutil

ROOT = pathlib.Path(__file__).resolve().parent.parent
MD = "Casberi/Casberi/Resources/Licenses.md"
SWIFT = "Casberi/Casberi/Screens/LicensePage.swift"
APACHE = "Apache License, Version 2.0"


def sections(md: str):
    out, name = {}, None
    for line in md.split("\n"):
        if line.startswith("# "):
            name = line[2:].strip()
            out[name] = []
        elif name is not None:
            out[name].append(line)
    return {k: "\n".join(v) for k, v in out.items()}


def audit(root):
    md = (root / MD).read_text()
    src = (root / SWIFT).read_text()
    secs = sections(md)
    libs = {n for n in secs if n != APACHE}
    block = re.search(r"static let lines: \[String: String\] = \[(.*?)\n    \]", src, re.S)
    if not block:
        return [f"{SWIFT}: no `Licenses.lines` table found (the audit's anchor moved)"]
    lines = set(re.findall(r'^\s*"([^"]+)":\s*"', block.group(1), re.M))
    apache = re.search(r"static let underApache: Set<String> = \[(.*?)\]", src, re.S)
    under = set(re.findall(r'"([^"]+)"', apache.group(1))) if apache else set()
    out = []
    for n in sorted(libs - lines):
        out.append(f"{MD}: `{n}` has no line in Licenses.lines, so its row draws its name alone")
    for n in sorted(lines - libs):
        out.append(f"{SWIFT}: Licenses.lines names `{n}`, which Licenses.md does not hold")
    for n in sorted(under):
        if n not in secs:
            out.append(f"{SWIFT}: underApache names `{n}`, which Licenses.md does not hold")
        elif "Apache License" not in secs[n]:
            out.append(f"{SWIFT}: underApache names `{n}`, whose notice never points at the Apache License")
    if under and APACHE not in secs:
        out.append(f"{MD}: libraries point at the Apache License, and its text is not in the file")
    return out


def self_test():
    clean = audit(ROOT)
    if clean:
        print("self-test: the tree itself is not clean:\n  " + "\n  ".join(clean), file=sys.stderr)
        return 1
    cases = [
        (MD, "# Yttrium\n", "# Yttrium\n\nnothing\n\n# A library with no line\n", "has no line"),
        (SWIFT, '        "QRCode": "MIT · Darren Ford",\n', "", "has no line"),
        (SWIFT, '        "Yttrium": "Apache 2.0 · Reown",\n',
         '        "Yttrium": "Apache 2.0 · Reown",\n        "Gone": "MIT",\n', "does not hold"),
        (SWIFT, '["Coinbase Wallet Mobile SDK", "Yttrium"]', '["QRCode", "Yttrium"]', "never points at the Apache"),
        (MD, "# Apache License, Version 2.0\n", "# Apache text, renamed\n", "its text is not in the file"),
    ]
    failed = 0
    for rel, old, new, expect in cases:
        with tempfile.TemporaryDirectory() as tmp:
            copy = pathlib.Path(tmp)
            for f in (MD, SWIFT):
                (copy / f).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy(ROOT / f, copy / f)
            target = copy / rel
            text = target.read_text()
            if old not in text:
                print(f"self-test FAILED: mutation anchor moved in {rel}: {old[:50]!r}", file=sys.stderr)
                failed += 1
                continue
            target.write_text(text.replace(old, new, 1))
            found = audit(copy)
            if not any(expect in f for f in found):
                print(f"self-test FAILED: no finding for {expect!r} ({found})", file=sys.stderr)
                failed += 1
            else:
                print(f"  ok   catches  {expect}")
    if failed:
        return 1
    print(f"licenses audit self-test: ok ({len(cases)} mutations)")
    return 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(self_test())
    findings = audit(ROOT)
    for f in findings:
        print("  " + f)
    if findings:
        print(f"✗ licenses audit: {len(findings)} finding(s)")
        sys.exit(1)
    print("✓ licenses audit: every library in Licenses.md has its line, and every line its library")
