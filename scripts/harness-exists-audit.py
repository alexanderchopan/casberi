#!/usr/bin/env python3
"""A HARNESS THAT IS RUN MUST EXIST — the missing half of the completeness guard.

`verify.sh` already globs `scripts/*-selftest.*` and `scripts/*-audit.*` and
fails on a check the pass never RUNS. That guard runs one way only. This is the
reverse: a check the pass runs that **is not in the repository**.

**It broke main for ten minutes on 2026-09-08 and no local build could see it.**
A commit took one session's `verify.sh` harness wiring, its ledger entry and its
index lines, but not the three files doing the work, because those were still
untracked — and `git add -A` picks untracked files up while a plain
`git commit -a` does not. So HEAD wired a harness that was not in the repo and
cited a fix it did not contain. Every session's own build stayed green
throughout, because every working tree had both halves; only a fresh clone would
have failed, at the self-test-completeness step, with a confusing error.

This is the same class as build 176's "caller without callee" and it generalises
past scripts, but scripts are where it is cheap and exact to check.

**(1) Every cited script exists on disk.** Catches a rename or a deletion that
left `verify.sh` calling a path that is not there — the ordinary, local form.

**(2) Every script HEAD's `verify.sh` cites exists at HEAD.** This is the one
that catches the commit above, and the reason it is framed HEAD-against-HEAD
matters: it never sees your uncommitted work, so writing a new harness and
wiring it before committing does NOT fail the pass. It fires only when the
COMMITTED tree is genuinely inconsistent — which is exactly when everyone else
is broken and nobody local can tell. Deliberately not "cited and untracked",
which would fire on ordinary mid-work and push people toward `git add` in a
repo where a shared index makes that the dangerous move.

**Comments are stripped before extracting.** A comment naming a retired script
is history, not a call, and cannot break a run — this repo has paid for the
opposite reading four times (the Obsidian/Cursor lesson).

**STATED CEILINGS.** It reads `verify.sh` only, not `verify-mac.sh` or the
nightly wrappers. It cannot see a script reached through a variable
(`"$ROOT/scripts/$name.sh"`), and it says nothing about whether a cited script
WORKS — only that it is there to be run.

`--self-test` runs first and is required, per this repo's rule that a check
which cannot demonstrate it catches anything certifies nothing.
"""
import re
import subprocess
import sys
import pathlib

DRIVER = "scripts/verify.sh"
CITE = re.compile(r"scripts/[A-Za-z0-9._-]+\.(?:py|sh)")


def strip_comments(text):
    """Shell comments out. A retired script named in a comment is history."""
    return "\n".join(re.sub(r"#.*$", "", line) for line in text.splitlines())


def cited(text):
    return sorted(set(CITE.findall(strip_comments(text))))


def audit(root):
    out = []

    driver = root / DRIVER
    if not driver.exists():
        return [f"{DRIVER} not found — this audit reads it and cannot run"]

    # (1) on disk
    for path in cited(driver.read_text(encoding="utf-8", errors="replace")):
        if not (root / path).exists():
            out.append(f"{DRIVER} runs {path}, which does not exist on disk")

    # (2) at HEAD, HEAD-against-HEAD so local work-in-progress is invisible
    def git(*args):
        return subprocess.run(["git", "-C", str(root), *args],
                              capture_output=True, text=True)

    head = git("show", f"HEAD:{DRIVER}")
    if head.returncode != 0:
        return out  # no HEAD, or not a repo — check 1 still stands
    tracked = git("ls-tree", "-r", "--name-only", "HEAD")
    if tracked.returncode != 0:
        return out
    at_head = set(tracked.stdout.split("\n"))
    for path in cited(head.stdout):
        if path not in at_head:
            out.append(f"HEAD's {DRIVER} runs {path}, which is NOT in HEAD — "
                       f"a fresh clone fails; commit the script")
    return out


# ---------------------------------------------------------------- fixtures

CLEAN = 'step "x"\npython3 "$ROOT/scripts/real-audit.py" || fail "…"\n'
MISSING = 'step "x"\npython3 "$ROOT/scripts/ghost-audit.py" || fail "…"\n'
COMMENTED = '# scripts/retired-audit.sh was deleted 2026-08-01, see prd §1\n' + CLEAN
BOTH = MISSING + CLEAN


def self_test():
    ok = True
    cases = [
        ("finds the one real citation", CLEAN, ["scripts/real-audit.py"]),
        ("finds a citation that will not resolve", MISSING, ["scripts/ghost-audit.py"]),
        ("ignores a retired script named in a comment", COMMENTED, ["scripts/real-audit.py"]),
        ("finds both, sorted", BOTH, ["scripts/ghost-audit.py", "scripts/real-audit.py"]),
        ("an empty driver cites nothing", "", []),
    ]
    for label, text, want in cases:
        got = cited(text)
        mark = "ok  " if got == want else "FAIL"
        if got != want:
            ok = False
            print(f"       · got {got}, wanted {want}")
        print(f"  {mark} {label}")

    # The live check, mutation-tested against a tree that really lacks the file.
    import tempfile, os
    with tempfile.TemporaryDirectory() as d:
        t = pathlib.Path(d)
        (t / "scripts").mkdir()
        (t / DRIVER).write_text(MISSING, encoding="utf-8")
        found = audit(t)
        hit = any("ghost-audit.py" in f and "does not exist on disk" in f for f in found)
        print(f"  {'ok  ' if hit else 'FAIL'} flags a cited script missing from a real tree")
        ok = ok and hit

        (t / "scripts" / "ghost-audit.py").write_text("", encoding="utf-8")
        clean = audit(t)
        print(f"  {'ok  ' if not clean else 'FAIL'} passes once that script exists")
        ok = ok and not clean
    return ok


def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    if "--self-test" in sys.argv:
        print("harness-exists-audit self-test")
        if not self_test():
            print("SELF-TEST FAILED")
            return 1
        print("  self-test passed")

    findings = audit(root)
    if findings:
        print(f"harness-exists-audit: {len(findings)} finding(s)")
        for f in findings:
            print(f"  ✗ {f}")
        return 1
    n = len(cited((root / DRIVER).read_text(encoding="utf-8", errors="replace")))
    print(f"harness-exists-audit: clean — all {n} scripts verify.sh runs exist, on disk and at HEAD")
    return 0


if __name__ == "__main__":
    sys.exit(main())
