#!/usr/bin/env python3
"""Casberi mutation-liveness audit (2026-09-06).

**A mutation that changed nothing is not a passing mutation — it is a mutation
that did not run, reported as a result.**

This class cost a real false green. `room-perf-selftest.sh` mutated its source
with `perl -0777 -i -pe`, whose substitution is SILENT about a miss. prd §623
put a `#if DEBUG` log line between the two lines one mutation's regex anchored
on; the regex then matched nothing, the "mutant" was byte-identical to the
shipped file, every check passed against it, and the harness printed
`MUTATION SURVIVED` — a correct verdict about a file nobody mutated, and a
completely misleading one about the guard it names. The guard it was supposed
to prove had been unproven for as long as the drift had existed, and the run
was green the whole time.

**A missing mutation is better than a dead one**, because a missing one does
not print a line claiming coverage.

WHAT THIS CHECKS. Every harness that APPLIES a mutation with a perl
substitution must also compare the mutant against the original and fail when
they are identical. Harnesses that mutate by Python string replace get this
for free — they all fail on `if frm not in src` — which is why the perl shape
is the one worth pinning, and why this audit does not simply demand one
spelling of the detector everywhere.

WHAT IT DELIBERATELY DOES NOT CHECK. That a mutation is MEANINGFUL — that it
actually breaks the behaviour the harness cares about rather than something
incidental. No static check can know that. It only refuses the narrower and
completely mechanical failure: a mutant identical to the source.

Exit non-zero on a finding.
"""

import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "scripts"

# Applying a mutation, not merely mentioning perl in a comment. `-i` (in place)
# or `-pi` is what makes it an application.
APPLIES_PERL = re.compile(r"perl\s+(?:-0777\s+-i\s+-pe|-0pi\s+-e|-0777\s+-pi\s+-e|-i\s+-0777\s+-pe)")
# Any of the ways this repo's harnesses say "the mutant equals the source".
DETECTS_NOOP = re.compile(r"cmp -s|diff -q|STALE MUTATION|matched nothing|changed nothing|did not apply")


def strip_comments(text):
    """A harness's own prose names the shapes it forbids — the Obsidian/Cursor
    lesson. Only shell comments; a `#` inside a heredoc of Swift is not one,
    which is why the applier regex demands the flags rather than the word."""
    return "\n".join(re.sub(r"^\s*#.*$", "", line) for line in text.split("\n"))


# The third shape (prd §628): a python applier that DOES detect a missing
# anchor and exits non-zero — and a caller that never looks. Inside a function
# invoked as `mutate … || fail=1`, `set -e` is off, so the exit is dropped on
# the floor, no mutant is written, the compile fails on the missing file, and
# the mutation is counted as caught. The applier line must carry its own `||`
# or `&&`, open an `if`, or be followed by a `$?` check.
APPLIES_PYTHON = re.compile(r"^[^\n#]*\bpython3 - [^\n]*<<'?PY", re.M)


# Only the MUTATION helpers: a harness's other python heredocs (extractors,
# comment strippers) return through the function they end, and their status is
# the caller's business. A helper is one whose name says so.
MUTATE_FN = re.compile(r"^(?:[a-z_]*mutate[a-z_]*|probe)\(\)\s*\{.*?^\}", re.M | re.S)


def python_unchecked(code):
    """An applier whose result nobody reads: the apply line itself carries no
    `||`/`&&`/`if`, and the line after its heredoc terminator reads no `$?`."""
    bodies = "\n".join(m.group(0) for m in MUTATE_FN.finditer(code))
    for m in APPLIES_PYTHON.finditer(bodies):
        code = bodies
        # The WHOLE line: the `|| { … }` sits after the heredoc opener, which
        # is where the match ends. Reading only the match flagged 40 harnesses
        # that were all checking their status on the very same line.
        line = code[code.rfind("\n", 0, m.start()) + 1:code.find("\n", m.end())]
        if "||" in line or "&&" in line or line.lstrip().startswith("if "):
            continue
        end = code.find("\nPY", m.end())
        if end < 0:
            continue
        after = code[end + 3:].lstrip("\n").split("\n", 2)
        nxt = "\n".join(after[:2])
        if "$?" in nxt or "applied" in nxt:
            continue
        return True
    return False


def audit():
    findings = []
    checked = 0
    for path in sorted(SCRIPTS.glob("*-selftest.sh")) + sorted(SCRIPTS.glob("*-audit.sh")):
        raw = path.read_text()
        code = strip_comments(raw)
        if any(APPLIES_PYTHON.search(m.group(0)) for m in MUTATE_FN.finditer(code)):
            checked += 1
            if python_unchecked(code):
                findings.append(
                    f"scripts/{path.name}: applies a mutation with `python3 -` and never reads its\n"
                    "    exit status. Inside a function called as `mutate … || fail=1`, `set -e` is\n"
                    "    off, so an applier that exits on a missing anchor is ignored: no mutant is\n"
                    "    written, the compile fails on the missing file, and the mutation is counted\n"
                    "    as CAUGHT. Put `|| { echo STALE; return 1; }` on the python line."
                )
        if not APPLIES_PERL.search(code):
            continue
        checked += 1
        # The detector may live in a different function from the applier (the
        # spool-and-run shape), so this is file-wide on purpose.
        if not DETECTS_NOOP.search(code):
            findings.append(
                f"scripts/{path.name}: applies mutations with a perl substitution but never\n"
                "    compares the mutant against the original. A perl substitution is silent\n"
                "    about a miss, so a mutation whose anchor has drifted changes nothing,\n"
                "    passes every check, and is reported as SURVIVED — proving nothing while\n"
                "    printing a line that claims coverage. Add a `cmp -s` against the source\n"
                "    right after the substitution and fail on identical."
            )
    return findings, checked


def self_test():
    """Two fixtures: the vulnerable shape must be caught, the guarded one must not."""
    import tempfile, shutil

    failures = 0
    vulnerable = """#!/bin/zsh
mutate() {
  local desc="$1" expr="$2"
  cp "$SRC" "$dir/X.swift"
  perl -0777 -i -pe "$expr" "$dir/X.swift"
  run_checks && print "SURVIVED"
}
"""
    guarded = """#!/bin/zsh
mutate() {
  local desc="$1" expr="$2"
  cp "$SRC" "$dir/X.swift"
  perl -0777 -i -pe "$expr" "$dir/X.swift"
  if cmp -s "$SRC" "$dir/X.swift"; then print "STALE"; return 1; fi
  run_checks && print "SURVIVED"
}
"""
    # A harness that only MENTIONS perl in a comment must not be demanded of.
    mentions_only = """#!/bin/zsh
mutate() {
  # A literal replace, deliberately not perl -0777 -i -pe: `$0` interpolates.
  python3 -c 'pass'
}
"""
    # The third shape: a python applier that exits on a missing anchor, and a
    # caller that never looks (metrics-selftest, 2026-09-06).
    py_unchecked = """#!/bin/zsh
mutate() {
  python3 - "$SRC" "$dir/x.swift" "$from" "$to" <<'PY'
import sys
if sys.argv[3] not in open(sys.argv[1]).read(): sys.exit(1)
PY
  cp main.swift "$dir/"
  if swiftc -o "$dir/run" "$dir/x.swift" && "$dir/run"; then echo SURVIVED; return 1; fi
}
"""
    py_checked = py_unchecked.replace("<<'PY'", "<<'PY' || { echo STALE; return 1; }")
    tmp = pathlib.Path(tempfile.mkdtemp())
    try:
        cases = [("zz-vulnerable-selftest.sh", vulnerable, True),
                 ("zz-guarded-selftest.sh", guarded, False),
                 ("zz-mentions-selftest.sh", mentions_only, False),
                 ("zz-pyunchecked-selftest.sh", py_unchecked, True),
                 ("zz-pychecked-selftest.sh", py_checked, False)]
        for name, body, should_fire in cases:
            target = SCRIPTS / name
            target.write_text(body)
            try:
                findings, _ = audit()
                fired = any(name in f for f in findings)
                if fired != should_fire:
                    print(f"✗ fixture {name}: expected {'a finding' if should_fire else 'no finding'}")
                    failures += 1
            finally:
                target.unlink()
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    findings, checked = audit()
    if findings:
        print("✗ self-test cannot run clean: the tree has findings")
        for f in findings:
            print("   " + f)
        failures += 1
    if failures:
        return 1
    print(f"✓ mutation-liveness self-test: 5 fixtures, {checked} mutating harnesses all detect a no-op and read their applier's status")
    return 0


def main():
    if "--self-test" in sys.argv:
        return self_test()
    findings, checked = audit()
    if findings:
        print("mutation-liveness audit: FINDINGS")
        for f in findings:
            print("  ✗ " + f)
        return 1
    print(f"mutation-liveness audit: ok ({checked} mutating harnesses — each detects a mutation that changed nothing, and reads its applier's status)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
