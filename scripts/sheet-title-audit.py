#!/usr/bin/env python3
"""A SHEET'S HEAD MUST NOT REPEAT ITS TRAY'S TITLE (prd §538/§539, 2026-08-31).

`DSTray(title:)` renders the sheet's name at `heading34`. `DSSheetHead(title:)`
renders a title at `heading22` directly beneath it. When both are handed the
same words the sheet opens on its own name, twice, in two sizes — and whatever
the sheet actually has to say is pushed below it, sometimes below the fold.

**That "at `heading22`" was true when this was written, FALSE for a day, and is
true again by construction (check C, 2026-09-02).** §560 raised the head to
`heading34` — right for a head standing alone, and inside a tray it made the
sentence above describe a pair that no longer existed: two heads at one rung,
120pt of headline before the first fact, on five of the six sheets that draw
both. A file whose own premise has gone stale is how the next reader is misled,
so the mechanism that keeps it true is now checked rather than described.

**Mechanical because memory lost four times in one afternoon**, which is this
repo's standing bar for turning a rule into a check:

  · `VibenetKeySheet`     — tray and head were passed the byte-identical
                            expression `actor.kind.plainTitle`, twenty lines
                            apart. The block the sheet exists to show ("What it
                            can do") opened at or below the fold as a result.
  · `VibenetAuthorizeSheet` — same, one expression further out: the tray built
                            `editing == nil ? "Authorize a key" : "Edit
                            permissions"` and `headTitle` rebuilt it verbatim.
  · `VibenetCreateSheet`  — "Create an account" over "A new account", with the
                            network line under THAT repeating the head's own
                            secondary.
  · `HegotaKeySheet`      — "This phone's account" over "Your account on this
                            phone": the same sentence, reordered.

Two checks, both OBJECTIVE, because a lint that cries wolf gets turned off
within a week (this file's own §299 lesson):

  A. EXPRESSION IDENTITY — the tray's title expression and the head's are the
     same text after normalisation, resolving a bare identifier one level
     through a same-file `private var <name>: String` or `-> String`. This is
     the form that needs no judgement at all: one expression, two call sites.

  B. LITERAL INTERSECTION — a `String(localized: "…")` literal is reachable
     from BOTH. A phase word shared between the tray and the head is the same
     fault wearing a switch statement.

  C. THE RUNG, not the words — one `heading34` per surface. A COMPONENT check,
     run once rather than per file: `DSTray` declares that it has spent the head
     rung and `DSSheetHead` steps down when it reads that, so no caller can get
     it wrong and there is no per-sheet shape to scan. See `rung_findings`.

**STATED CEILING, and it is real: this cannot catch a PARAPHRASE.** The Hegotá
case above shares no literal and no expression — "This phone's account" against
"Your account on this phone" — so nothing here would have found it; it was found
by reading. The honest scope is "the same words, provably", not "words that mean
the same thing".

**A word-overlap tier was written, MEASURED, and REFUSED — and the measurement
is the point, because it went the OPPOSITE way to the guess twice.** Run it with
`--measure`.

  · First run, before the fallback below was fixed: ONE finding, and it was a
    TRUE POSITIVE nobody had spotted — `HegotaKeySheet.headTitle` still
    returned "Your account on this phone" on its nil-address branch, so the
    hand fix for that sheet had missed a live path. The instrument paid for
    itself on its first run (§318's "build the cheap instrument before the
    plausible fix"), which is why it is kept runnable rather than deleted.
  · Second run, after that branch was given a state's words: it STILL fires on
    the same file, now on the head's OTHER phases — "This phone's key is gone"
    and "No account yet" against a tray reading "This phone's account". Those
    sentences are CORRECT. A head that names the sheet's own subject while
    saying something new about it is ordinary English, and a check cannot tell
    that apart from a repetition by counting words.

So the tier is a one-off instrument, not a gate: it fires on a healthy tree for
a reason no threshold fixes, and a lint that cries wolf gets turned off within a
week (§299). Reach for `--measure` when auditing by hand; never wire it into a
build.

Comments are stripped before every check, because three of the four files above
now DOCUMENT this rule by quoting the expression they must no longer pass — the
Obsidian/Cursor lesson, which this repo has paid for eight times.

Usage:
  sheet-title-audit.py              # audit the tree
  sheet-title-audit.py --self-test  # prove the checks catch what they claim
  sheet-title-audit.py --measure    # the refused tier's finding count, for the record
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = [ROOT / "Casberi" / "Casberi" / "Screens"]
DSTRAY = ROOT / "Casberi" / "Casberi" / "Design" / "DSTray.swift"
DSSHEETHEAD = ROOT / "Casberi" / "Casberi" / "Design" / "DSSheetHead.swift"

# A conscious "these two really are different things said in the same words".
# Empty by design — an entry is a ruling, not a snooze, and must carry its
# reason.
KNOWN_OK: dict[str, str] = {}

LITERAL = re.compile(r'String\(localized:\s*"((?:[^"\\]|\\.)*)"\s*\)')
BARE_LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')


def strip_comments(src: str) -> str:
    """Line and block comments out, string literals kept.

    Deliberately simple and deliberately conservative: it tracks whether it is
    inside a string so a `//` in a URL survives, and it does not try to handle
    nested block comments (Swift allows them; none of these files use them, and
    a miss here can only leave MORE text to match, never less).
    """
    out: list[str] = []
    i, n = 0, len(src)
    in_str = in_line = in_block = False
    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ""
        if in_line:
            if c == "\n":
                in_line = False
                out.append(c)
        elif in_block:
            if c == "*" and nxt == "/":
                in_block = False
                i += 1
        elif in_str:
            out.append(c)
            if c == "\\":
                if i + 1 < n:
                    out.append(nxt)
                    i += 1
            elif c == '"':
                in_str = False
        else:
            if c == "/" and nxt == "/":
                in_line = True
                i += 1
            elif c == "/" and nxt == "*":
                in_block = True
                i += 1
            elif c == '"':
                in_str = True
                out.append(c)
            else:
                out.append(c)
        i += 1
    return "".join(out)


def balanced_arg(src: str, start: int) -> str | None:
    """The argument text beginning at `start`, cut at the comma or paren that
    closes it — respecting nesting and strings, so a ternary holding a
    `String(localized:)` call comes back whole."""
    depth = 0
    in_str = False
    out: list[str] = []
    i = start
    while i < len(src):
        c = src[i]
        if in_str:
            out.append(c)
            if c == "\\":
                if i + 1 < len(src):
                    out.append(src[i + 1])
                    i += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
            out.append(c)
        elif c in "([{":
            depth += 1
            out.append(c)
        elif c in ")]}":
            if depth == 0:
                return "".join(out)
            depth -= 1
            out.append(c)
        elif c == "," and depth == 0:
            return "".join(out)
        else:
            out.append(c)
        i += 1
    return None


def arg_after(src: str, call: str, label: str) -> str | None:
    """The `label:` argument of the first `call(` in `src`."""
    m = re.search(re.escape(call) + r"\s*\(", src)
    while m:
        seg = src[m.end():]
        lm = re.search(r"\b" + re.escape(label) + r":\s*", seg)
        if lm:
            # Only accept a label at this call's own argument depth — a nested
            # call's `title:` must not be mistaken for this one's.
            head = seg[: lm.start()]
            if head.count("(") == head.count(")"):
                return balanced_arg(seg, lm.end())
        m = re.search(re.escape(call) + r"\s*\(", src[m.end():])
        if m is None:
            return None
        m = re.match(r"", "")  # unreachable; kept explicit for the linter
        return None
    return None


def normalise(expr: str) -> str:
    return re.sub(r"\s+", " ", expr).strip().rstrip(",").strip()


def resolve(expr: str, src: str) -> tuple[str, set[str]]:
    """(expression text, the localized literals reachable from it).

    A bare identifier is followed ONE level into a same-file computed property
    — `headTitle` is the shape all four historical cases used to put distance
    between the two call sites. One level and no further on purpose: a deeper
    walk starts guessing, and every real instance of this fault has been one
    hop.
    """
    e = normalise(expr)
    lits = set(LITERAL.findall(e))
    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", e):
        m = re.search(
            r"(?:private\s+)?var\s+" + re.escape(e) + r"\s*:\s*String\??\s*\{",
            src,
        )
        if m:
            body = balanced_body(src, m.end())
            if body is not None:
                return e, set(LITERAL.findall(body))
        m = re.search(
            r"func\s+" + re.escape(e) + r"\s*\([^)]*\)\s*->\s*String\??\s*\{", src
        )
        if m:
            body = balanced_body(src, m.end())
            if body is not None:
                return e, set(LITERAL.findall(body))
    return e, lits


def balanced_body(src: str, start: int) -> str | None:
    depth = 1
    out: list[str] = []
    i = start
    while i < len(src):
        c = src[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return "".join(out)
        out.append(c)
        i += 1
    return None


def findings_for(path: Path, raw: str) -> list[str]:
    src = strip_comments(raw)
    if "DSTray(" not in src or "DSSheetHead(" not in src:
        return []
    tray = arg_after(src, "DSTray", "title")
    head = arg_after(src, "DSSheetHead", "title")
    if tray is None or head is None:
        return []
    name = path.name
    if name in KNOWN_OK:
        return []

    tray_expr, tray_lits = resolve(tray, src)
    head_expr, head_lits = resolve(head, src)

    out: list[str] = []
    # A — the same expression, twice.
    if tray_expr and tray_expr == head_expr:
        out.append(
            f"{name}: the tray title and the sheet head are the SAME expression "
            f"`{tray_expr}` — the sheet opens on its own name in two sizes."
        )
    # B — a shared word.
    shared = tray_lits & head_lits
    if shared:
        for s in sorted(shared):
            out.append(
                f'{name}: "{s}" is passed to BOTH DSTray(title:) and '
                f"DSSheetHead(title:) — the head is restating the tray."
            )
    return out


def files() -> list[Path]:
    out: list[Path] = []
    for d in SOURCES:
        if d.exists():
            out.extend(sorted(d.rglob("*.swift")))
    return out


def rung_findings(tray_src: str, head_src: str) -> list[str]:
    """CHECK C — THE HEAD MUST NOT REPEAT ITS TRAY'S RUNG EITHER (2026-09-02).

    Checks A and B are about the WORDS. This is the same relationship's other
    half, and it went wrong the day after they were written: §560 raised
    `DSSheetHead.title` from `heading22` to `heading34` on the reasoning that
    "a `DSSheetHead` has no amount, so its title is the largest thing on the
    paper" — true of a head standing alone, false inside a `DSTray`, which
    draws its own `heading34` four points above. **Five of the six heads in the
    app are inside a tray**, so that raise gave five sheets two heads: 120pt of
    headline before the first fact, which on `VibenetCreateSheet` pushed the
    new account's address under the pinned action and sliced it through the
    middle. Nothing could see it — each rung is right on its own, and this
    file's own header prose went stale describing the pair.

    A COMPONENT-level check, run once rather than per file, because the fix is
    structural: the tray declares that it has spent the rung and the head reads
    it, so no caller can get it wrong and there is no per-sheet shape to scan.
    Reads a comment-stripped copy — both files document the rule by naming the
    symbols that carry it (the Obsidian/Cursor lesson).
    """
    out: list[str] = []
    tray = strip_comments(tray_src)
    head = strip_comments(head_src)
    if "dsSurfaceHasHead, true" not in tray:
        out.append(
            "DSTray no longer tells its content it has spent the head rung "
            "(environment(\\.dsSurfaceHasHead, true)) — without it every "
            "DSSheetHead inside a tray draws a second heading34 under the first."
        )
    if "dsSurfaceHasHead" not in head:
        out.append(
            "DSSheetHead no longer reads dsSurfaceHasHead — its title is "
            "heading34 unconditionally again, which is a second head on every "
            "sheet that is inside a tray."
        )
    elif "surfaceHasHead ? .heading22 : .heading34" not in head:
        out.append(
            "DSSheetHead reads dsSurfaceHasHead but no longer steps its title "
            "rung by it — the flag is set, the head is still heading34."
        )
    return out


def audit() -> int:
    findings: list[str] = []
    checked = 0
    for f in files():
        raw = f.read_text(encoding="utf-8", errors="replace")
        if "DSTray(" in raw and "DSSheetHead(" in raw:
            checked += 1
        findings.extend(findings_for(f, raw))
    if DSTRAY.exists() and DSSHEETHEAD.exists():
        findings.extend(rung_findings(
            DSTRAY.read_text(encoding="utf-8", errors="replace"),
            DSSHEETHEAD.read_text(encoding="utf-8", errors="replace")))
    else:
        findings.append("DSTray.swift or DSSheetHead.swift is gone — check C "
                        "cannot run, which is a finding rather than a pass.")
    if findings:
        for line in findings:
            print("  ✗ " + line)
        print(
            f"\nsheet-title-audit: {len(findings)} finding(s) — prd §538: the tray "
            "names the thing, the head carries the ANSWER and never the name again."
        )
        return 1
    print(
        f"✓ sheet-title audit: {checked} sheets draw both a tray title and a head; "
        "no head repeats its tray's words, and none repeats its rung"
    )
    return 0


# --------------------------------------------------------------------------
# The refused tier, kept runnable so the refusal stays checkable (§318's
# "build the cheap instrument" rule — a decision backed by a number rather
# than by a story about one).
# --------------------------------------------------------------------------

STOP = {"a", "an", "the", "this", "that", "your", "my", "of", "on", "in", "is",
        "it", "to", "for", "and", "or", "no", "not", "yet", "new"}


def content_words(lits: set[str]) -> set[str]:
    words: set[str] = set()
    for s in lits:
        for w in re.findall(r"[A-Za-z']+", s.lower()):
            if w not in STOP and len(w) > 2:
                words.add(w)
    return words


def measure() -> int:
    hits = 0
    for f in files():
        raw = f.read_text(encoding="utf-8", errors="replace")
        src = strip_comments(raw)
        if "DSTray(" not in src or "DSSheetHead(" not in src:
            continue
        tray = arg_after(src, "DSTray", "title")
        head = arg_after(src, "DSSheetHead", "title")
        if tray is None or head is None:
            continue
        _, tl = resolve(tray, src)
        _, hl = resolve(head, src)
        tw, hw = content_words(tl), content_words(hl)
        if not tw or not hw:
            continue
        overlap = len(tw & hw) / len(tw | hw)
        if overlap >= 0.3:
            hits += 1
            print(f"  · {f.name}: overlap {overlap:.2f} — {sorted(tw & hw)}")
    print(f"\nword-overlap tier would report {hits} finding(s) on this tree.")
    return 0


# --------------------------------------------------------------------------
# Self-test. A check that cannot demonstrate it catches anything certifies
# nothing, so every fixture FAILS the rule it names and passes every other one.
# --------------------------------------------------------------------------

CLEAN = '''
struct S: View {
    var body: some View {
        DSTray(title: String(localized: "Create an account"), height: h) {
            DSSheetHead(disc: { d }, title: headTitle, secondary: nil)
        }
    }
    private var headTitle: String { String(localized: "Paid by the faucet") }
}
'''

SAME_EXPR = '''
struct S: View {
    var body: some View {
        DSTray(title: actor.kind.plainTitle, height: h) {
            DSSheetHead(disc: { d }, title: actor.kind.plainTitle, secondary: nil)
        }
    }
}
'''

SHARED_LITERAL = '''
struct S: View {
    var body: some View {
        DSTray(title: String(localized: "Authorize a key"), height: h) {
            DSSheetHead(disc: { d }, title: headTitle, secondary: nil)
        }
    }
    private var headTitle: String {
        switch phase {
        case .done: String(localized: "Authorized")
        case .form: String(localized: "Authorize a key")
        }
    }
}
'''

RESOLVED_IDENTITY = '''
struct S: View {
    var body: some View {
        DSTray(title: headTitle, height: h) {
            DSSheetHead(disc: { d }, title: headTitle, secondary: nil)
        }
    }
    private var headTitle: String { String(localized: "Keys") }
}
'''

COMMENT_ONLY = '''
struct S: View {
    // This used to pass String(localized: "Create an account") to the head as
    // well, which was the §538 fault — do not put it back.
    var body: some View {
        DSTray(title: String(localized: "Create an account"), height: h) {
            DSSheetHead(disc: { d }, title: headTitle, secondary: nil)
        }
    }
    private var headTitle: String { String(localized: "Paid by the faucet") }
}
'''

NO_HEAD = '''
struct S: View {
    var body: some View {
        DSTray(title: String(localized: "Note"), height: 220) { field }
    }
}
'''

PARAPHRASE = '''
struct S: View {
    var body: some View {
        DSTray(title: String(localized: "This phone's account"), height: h) {
            DSSheetHead(disc: { d }, title: headTitle, secondary: nil)
        }
    }
    private var headTitle: String { String(localized: "Your account on this phone") }
}
'''


def self_test() -> int:
    cases = [
        ("a clean sheet passes", CLEAN, 0),
        ("the same expression twice is caught", SAME_EXPR, 1),
        ("a literal shared through a computed property is caught", SHARED_LITERAL, 1),
        ("both sides resolving to one property is caught", RESOLVED_IDENTITY, 1),
        ("a comment quoting the old fault does NOT fire", COMMENT_ONLY, 0),
        ("a tray with no head is not this check's business", NO_HEAD, 0),
        # The stated ceiling, asserted so it can never be mistaken for coverage.
        ("a PARAPHRASE is NOT caught — the ceiling, on purpose", PARAPHRASE, 0),
    ]
    bad = 0
    for label, src, want in cases:
        got = len(findings_for(Path("Fixture.swift"), src))
        ok = (got > 0) == (want > 0)
        print(f"  {'✓' if ok else '✗'} {label}")
        if not ok:
            bad += 1
            print(f"      expected {'a finding' if want else 'none'}, got {got}")
    # CHECK C — the mechanism that keeps one head rung per surface. Fixtures
    # rather than the real files, so the cases can be shown to FAIL: a check
    # that only ever reads a healthy tree proves nothing about what it catches.
    TRAY_OK = 'content().environment(\\.dsSurfaceHasHead, true)'
    # The head must DECLARE the read and USE it. Spelling the declaration into
    # the fixture is not padding: without it "the mechanism intact" fires the
    # missing-read arm and every case below passes for the wrong reason — which
    # is exactly what the first cut of these fixtures did.
    HEAD_READ = '@Environment(\\.dsSurfaceHasHead) private var surfaceHasHead'
    HEAD_OK = HEAD_READ + "\n.dsText(surfaceHasHead ? .heading22 : .heading34)"
    rung_cases = [
        ("the mechanism intact passes", TRAY_OK, HEAD_OK, 0),
        ("a tray that stops declaring the rung is caught",
         "content()", HEAD_OK, 1),
        ("a head that stops reading the flag is caught",
         TRAY_OK, ".dsText(.heading34)", 1),
        ("a head that reads the flag and ignores it is caught",
         TRAY_OK, HEAD_READ + "\n.dsText(.heading34)", 1),
        ("both halves gone is caught, not silently halved",
         "content()", ".dsText(.heading34)", 2),
        # Both files explain the rule by naming the symbols that carry it, so a
        # raw grep would score prose as compliance (the Obsidian/Cursor lesson).
        ("the rule described in a COMMENT is not compliance",
         "// content().environment(\\.dsSurfaceHasHead, true)\ncontent()",
         "// " + HEAD_READ + "\n.dsText(.heading34)", 2),
    ]
    for label, tray, head, want in rung_cases:
        got = len(rung_findings(tray, head))
        ok = got == want
        print(f"  {'✓' if ok else '✗'} {label}")
        if not ok:
            bad += 1
            print(f"      expected {want} finding(s), got {got}")
    # The stripper must not eat a real literal.
    if 'String(localized: "Create an account")' not in strip_comments(COMMENT_ONLY):
        print("  ✗ strip_comments ate a live literal")
        bad += 1
    else:
        print("  ✓ strip_comments keeps live literals while dropping commented ones")
    if bad:
        print(f"\nsheet-title-audit --self-test: {bad} case(s) wrong")
        return 1
    print("\n✓ sheet-title-audit self-test passed")
    return 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(self_test())
    if "--measure" in sys.argv:
        sys.exit(measure())
    if self_test() != 0:
        sys.exit(1)
    print()
    sys.exit(audit())
