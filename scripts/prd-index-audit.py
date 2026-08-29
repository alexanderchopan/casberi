#!/usr/bin/env python3
"""PRD ledger index audit (2026-08-11).

`docs/prd.md` is the product ledger — 445 sections, append-only by standing
rule, and cited by `§N` from CLAUDE.md, from every other doc, from the audit
scripts and from ~200 places in the Swift source. Those citations are the only
thing that makes a 20,000-line ledger navigable, and until this ran nothing
checked that a single one of them resolved.

WHY THIS IS MECHANICAL AND NOT A NOTE IN A DOC. Both failures below are
invisible to every other gate here — a wrong `§N` in a comment builds, ships and
reads as perfectly authoritative — and both are caused by CONCURRENT SESSIONS,
which is exactly the class a written reminder cannot fix, because neither
session can see the other's uncommitted work:

  * SIX numbers named two unrelated rulings each (§236, §237, §238, §294, §340,
    §355) — two sessions each taking "the next free §". `§340` was the worst:
    both meanings were 2026-08-07 design rulings, while the forty-eight source
    citations of `prd §340` all meant a 2026-08-08 session about the Cursor
    room. A reader following the reference got a confident wrong answer.
  * A WHOLE DAY of work — nine commits on 2026-08-08 — shipped with no ledger
    entry at all, and its forty-eight citations pointed into that collision.
    Nobody noticed for three days.

Four checks, all static (no build, no network):

  A. No two headings share a section number.
  B. Every section heading is H2. §276 and §277 shipped as H1 for nine days,
     which hides them from the table of contents and from every heading-level
     grep — §277 is the anchor for three shipped audits and is cited 49 times.
  C. Every `§N` cited outside the ledger resolves to a heading inside it.
  D. Every "supersedes / amends / reverses / overturns §N" phrase in the ledger
     has a row in the Superseded index, so a dead ruling is findable as dead.

Three deliberate NON-checks, so this can't become a lint that cries wolf:

  * It never judges whether a citation is SEMANTICALLY right — that a comment
    says `§303` and means it. It can only prove the number resolves.
  * It never demands that an entry be superseded-by-number. Plenty supersede by
    date ("supersedes the 2026-07-14 rolling window"), which is legitimate and
    untabulatable; check D fires only when a `§N` is actually named.
  * It never flags a GAP in the numbering. §224–§226 and §327 were simply never
    written (§327 was a block another session parked and dropped), and a gap
    harms nobody — only a citation OF a gap does, which is check C.

Usage:  scripts/prd-index-audit.py [--self-test | --next]
        --next prints the next section number nobody has taken, counting
        uncommitted claims as taken — the door checks A and C were both
        walked through.
Exit 0 = clean.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LEDGER = ROOT / "docs" / "prd.md"

# Where a `§N` citation may appear. docs/prd.md is excluded — it is the ledger
# itself, and its internal cross-references are checked by the same pass.
CITERS = [ROOT / "CLAUDE.md", ROOT / "docs", ROOT / "scripts", ROOT / "Casberi"]
CITER_SUFFIXES = {".md", ".py", ".sh", ".swift"}

# A `§N` that names a section of ANOTHER document, not this ledger. Each entry
# is a conscious "this citation is correct and points elsewhere."
FOREIGN_DOC_PREFIXES = ("build-brief ", "design-principle ", "agent-brief ")

# Numbers cited that will never have a heading here. An entry is a conscious
# ruling, not a snooze.
KNOWN_DANGLING = {
    "373": "a retired pre-§ numbering scheme, quoted verbatim inside §26",
    "413": "same retired scheme, quoted verbatim inside §229",
    "525": "same retired scheme, cited by scripts/cloudkit-schema.sh",
    "177": "never written; five Composer/AskCommands comments cite it for the "
           "related-follow-up ruling of 2026-07-22",
    "327": "never written; a block another session parked and dropped, named "
           "only by docs/agent-panel-tiles.md's own handoff steps",
}

# WHAT COUNTS AS A SECTION. Only an H2. This matters more than it looks: the
# ledger is full of `### 3. Color rule` and `### 4. The hold lives on the bar` —
# numbered items INSIDE an entry, not entries. The first cut of this audit
# matched any heading level and reported 60 findings over a clean tree, nine of
# them claiming `§1` was defined nine times (the `### 1.` opening every
# multi-part ruling). A lint that cries wolf gets turned off within a week, so
# check the finding list against a tree you believe in before trusting a new
# rule here — the design-motion audit paid for this same lesson in 2026-08-04.
SECTION_HEADING = re.compile(r"^(##)\s+(?:§)?(\d{1,3}[a-z]{0,2})\b(.*)$")

# A sub-entry: `## §319 amendment`, `### §286 follow-up`, `### 165a.`. These
# deliberately re-use their parent's number and are NOT collisions.
SUB_ENTRY = re.compile(r"^\s*(amendment|follow-up|second follow-up)", re.I)

# An H1 carrying a § is always wrong — that is the §276/§277 bug, and the only
# heading-level mistake worth failing a build over. An H3 carrying a § is the
# established sub-entry convention and is fine.
STRAY_H1 = re.compile(r"^#\s+§(\d{1,3}[a-z]{0,2})\b(.*)$")
# A section reference in prose. The optional qualifier lets check D skip a
# reference to a DIFFERENT document that happens to be numbered.
SECTION_REF = re.compile(r"(build-brief |design-principle |agent-brief )?§(\d{1,3}[a-z]{0,2})\b")
SUPERSEDE_VERB = re.compile(
    r"\b(supersedes?|superseding|amends?|amending"
    # ACTIVE VOICE ONLY, and the omissions are deliberate: "superseded BY §N"
    # names the entry doing the changing, so demanding a row for it inverts the
    # rule. `reversing`/`overturning` were simply missing beside their already
    # present siblings — found when a §504 phrase spelled that way slipped the
    # check, and adding the past participles alongside them immediately
    # produced four false findings, which is what proved the narrowing right.
    r"|reverses?|reversing|overturns?|overturning)\b([^.;]{0,70})", re.I)


def headings(text):
    """Every real section: {number: [(line_number, raw), ...]}. H2 only, and
    sub-entries ("§319 amendment") folded into their parent rather than
    counted as a second definition of the number."""
    found = {}
    for i, line in enumerate(text.split("\n"), 1):
        m = SECTION_HEADING.match(line)
        if not m:
            continue
        rest = m.group(3).lstrip(" .—-")
        if SUB_ENTRY.match(rest):
            continue
        found.setdefault(m.group(2), []).append((i, line))
    return found


# An H3 sub-entry that a citation may legitimately name: `### 165a.`,
# `### §204 amendment`, `### §252a`. Qualified by a § or a letter suffix, which
# is what separates it from `### 3. Color rule` — a numbered item inside an
# entry, which nothing cites and which must not count as defining "§3".
SUB_HEADING = re.compile(r"^#{3,6}\s+(§\d{1,3}[a-z]{0,2}|\d{1,3}[a-z]{1,2})\b")


def defined(text):
    """Every number a citation may resolve to: real sections plus the H3
    sub-entries that carry a § or a letter suffix."""
    names = set(headings(text))
    for line in text.split("\n"):
        m = SUB_HEADING.match(line)
        if m:
            names.add(m.group(1).lstrip("§"))
    for line in text.split("\n"):
        m = SECTION_HEADING.match(line)
        if m:
            names.add(m.group(2))
    return names


def stray_h1s(text):
    """Sections that shipped as H1 — invisible to the contents and to every
    heading-level grep. §276/§277 sat like that for nine days."""
    out = []
    for i, line in enumerate(text.split("\n"), 1):
        m = STRAY_H1.match(line)
        if m:
            out.append((m.group(1), i, line))
    return out


def index_rows(text):
    """Section numbers that appear in the Superseded index's own tables."""
    start = text.find("## Superseded index")
    if start < 0:
        return None
    end = text.find("\n## 1. Thesis", start)
    block = text[start:end if end > 0 else len(text)]
    return {m.group(2) for m in SECTION_REF.finditer(block)}


def hits_key(num):
    """Numeric-then-suffix order, so §36b sorts after §36 and before §102."""
    m = re.match(r"(\d+)([a-z]*)", num)
    return (int(m.group(1)), m.group(2))


def audit(ledger_text, citations):
    """citations: [(where, number)] from outside the ledger. Returns findings."""
    problems = []
    heads = headings(ledger_text)

    # A — one number, one ruling.
    for num, hits in sorted(heads.items(), key=lambda kv: hits_key(kv[0])):
        if len(hits) > 1:
            where = ", ".join(f"line {ln}" for ln, _ in hits)
            problems.append(
                f"§{num}: {len(hits)} headings share this number ({where}). Two "
                f"sessions each took the next free §; give the one the source "
                f"does NOT cite a letter suffix and record the move in the "
                f"Superseded index.")

    # B — no section shipped as an H1.
    for num, ln, raw in stray_h1s(ledger_text):
        problems.append(
            f"§{num} (line {ln}) is an H1, not an H2 — invisible to the "
            f"contents and to any heading-level grep: {raw.strip()[:70]}")

    # C — every outside citation resolves.
    known = defined(ledger_text)
    for where, num in sorted(set(citations)):
        if num in known or num in KNOWN_DANGLING:
            continue
        problems.append(
            f"§{num} is cited by {where} and has no heading in docs/prd.md — "
            f"write the entry, fix the number, or add it to KNOWN_DANGLING "
            f"with a reason.")

    # D — a named supersede is in the index.
    rows = index_rows(ledger_text)
    if rows is None:
        problems.append(
            "docs/prd.md has no '## Superseded index' section — without it an "
            "append-only ledger cannot tell a reader that a ruling is dead.")
    else:
        current = None
        for line in ledger_text.split("\n"):
            m = SECTION_HEADING.match(line)
            if m:
                current = m.group(2)
            if current is None or line.startswith("|"):
                continue          # the index's own table rows are not claims
            for vm in SUPERSEDE_VERB.finditer(line):
                for sm in SECTION_REF.finditer(vm.group(2)):
                    if sm.group(1):
                        continue  # names another document
                    ref = sm.group(2)
                    if ref == current or ref not in heads or ref in rows:
                        continue
                    problems.append(
                        f"§{current} says it {vm.group(1).lower()} §{ref}, but "
                        f"§{ref} has no row in the Superseded index — a reader "
                        f"landing on §{ref} has no way to learn it moved.")
    return problems


def collect_citations(paths, skip):
    out = []
    for root in paths:
        files = [root] if root.is_file() else sorted(root.rglob("*"))
        for f in files:
            if not f.is_file() or f.suffix not in CITER_SUFFIXES or f == skip:
                continue
            try:
                text = f.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            for m in SECTION_REF.finditer(text):
                if m.group(1) and m.group(1).strip() + " " in FOREIGN_DOC_PREFIXES:
                    continue
                out.append((f.relative_to(ROOT).as_posix(), m.group(2)))
    return out


def sibling_claims():
    """Numbers taken in ANOTHER checkout of this repo — the ceiling, closed.

    `--next` reading one working tree was not a theoretical limit: it was
    demonstrated within the hour of shipping, twice. One session wrote an entry
    in its own git worktree (invisible here, so this tool would have handed the
    number out again) and another had a number taken out from under it between
    two messages.

    A claim is by definition WORK IN PROGRESS, so only a worktree's CHANGED and
    untracked files are read — an unmodified file holds the same citations the
    main tree already has and can contribute nothing new. Measured on this repo:
    61 files instead of 11,111, 2.5s instead of 14.5s. A sibling's own
    `docs/prd.md` is read for HEADINGS rather than citations, because an entry
    appended but not committed there is the strongest claim there is and the one
    a reader of HEAD cannot see at all.

    CONSERVATIVE ON PURPOSE. A stale worktree can hold an abandoned claim, which
    reserves a number nobody will ever write. That is the right way to be wrong:
    section numbers are free and a collision costs a renumbering across every
    citation, so over-reserving is cheap and under-reserving is the bug.

    FAILS SOFT, always. No git, a pruned worktree, an unreadable file — every
    one of those skips silently and leaves the single-tree answer standing. A
    helper that refuses to answer is a helper nobody runs.
    """
    import subprocess
    try:
        listing = subprocess.run(["git", "worktree", "list", "--porcelain"],
                                 cwd=ROOT, capture_output=True, text=True,
                                 timeout=20).stdout
    except (OSError, subprocess.SubprocessError):
        return {}
    trees = [l.split(" ", 1)[1] for l in listing.splitlines() if l.startswith("worktree ")]
    out = {}
    for wt in trees:
        root = pathlib.Path(wt)
        if root == ROOT or not root.is_dir():
            continue
        try:
            status = subprocess.run(
                ["git", "-C", wt, "status", "--porcelain", "--untracked-files=all"],
                capture_output=True, text=True, timeout=20).stdout
        except (OSError, subprocess.SubprocessError):
            continue
        for line in status.splitlines():
            # A DELETED file cannot hold a claim, and its path may not exist.
            if line[:2] in (" D", "D ", "DD"):
                continue
            name = line[3:].strip().strip('"')
            f = root / name
            if f.suffix not in CITER_SUFFIXES or not f.is_file():
                continue
            try:
                text = f.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            if name == "docs/prd.md":
                for m in SECTION_HEADING.finditer(text):
                    out.setdefault(m.group(2), set()).add(f"{root.name}: entry written")
            else:
                for m in SECTION_REF.finditer(text):
                    if m.group(1) and m.group(1).strip() + " " in FOREIGN_DOC_PREFIXES:
                        continue
                    out.setdefault(m.group(2), set()).add(f"{root.name}: cited")
    return out


def next_free(ledger_text, citations, siblings=None):
    """The next section number nobody has taken — headings AND live claims.

    WHY THIS IS HERE AND NOT A NOTE. Checks A and C catch a bad number AFTER it
    lands; this is the door they were both walked through. Every collision this
    file documents (§236, §237, §238, §294, §340, §355) is one session picking
    "the next free §" while another session's claim sat in uncommitted work it
    could not see — and it happened twice more on 2026-08-28, when two live
    sessions each took a number blind within one hour, and a third spent sixteen
    comments citing §494 because that number LOOKED free and had in fact been a
    shipped ruling since 2026-08-26. (Numbers are named here WITHOUT the § form
    where they have no heading yet: check C reads this file too, so citing an
    unwritten number in this docstring fails the very audit it documents —
    which is exactly what the first cut of this function did.)

    A number is TAKEN if it has a heading, or if anything in the working tree
    cites it — an uncommitted claim is a claim. That second half is the whole
    point: a heading-only reading is exactly what every colliding session did.

    STATED CEILING, and it is real: this reads THIS working tree. A session
    working in its own git worktree (or on another machine) is invisible here,
    so the number this prints is the best answer available on this checkout and
    never a lock. Say the number you take out loud to the other sessions.

    Gaps are REPORTED and never recommended. Several numbers (§224-§226 and
    §327 among them) were parked and dropped, and a fresh-looking gap may
    belong to a session still running; handing one out is how a dead claim
    becomes a live collision.
    """
    heads = headings(ledger_text)
    resolvable = defined(ledger_text)
    claimed = {}
    for path, num in citations:
        if num in resolvable or num in KNOWN_DANGLING:
            continue
        claimed.setdefault(num, set()).add(path)

    def as_int(num):
        digits = re.match(r"\d+", num)
        return int(digits.group(0)) if digits else 0

    siblings = siblings or {}
    # KNOWN_DANGLING excluded for the same reason it is in the loop above:
    # a stale ship worktree citing the retired numbering scheme was
    # reserving §327 against a number that will never have a heading.
    elsewhere = {n: w for n, w in siblings.items()
                 if n not in resolvable and n not in KNOWN_DANGLING}
    taken = ({as_int(n) for n in resolvable} | {as_int(n) for n in claimed}
             | {as_int(n) for n in elsewhere})
    taken.discard(0)
    top = max(taken)
    gaps = [n for n in range(1, top) if n not in taken]
    return (top + 1, sorted(claimed.items(), key=lambda kv: as_int(kv[0])),
            gaps, len(heads), sorted(elsewhere.items(), key=lambda kv: as_int(kv[0])))


def self_test():
    """Each case is a failure that has really shipped in this repo."""
    index = ("## Superseded index\n\n| Ruling | What | Changed by |\n|---|---|---|\n"
             "| §61 | the ladder | superseded by §97 |\n\n## 1. Thesis\n")
    clean = index + "## §61 — The elevation ladder\n\nThis supersedes §61.\n\n## §97 — Doors\n"

    cases = {
        "collision": (
            index + "## §340 — The bar moves to the corner\n\n## §340 — A source name\n",
            [], True, "two headings sharing §340 (the real 2026-08-07 collision)"),
        "h1 heading": (
            index + "# §277 — Five privacy passes\n",
            [], True, "a section shipped as H1 (§277, invisible for nine days)"),
        "numbered sub-list": (
            clean + "\n### 1. Apple grammar\n\n### 2. One tint\n\n### 3. Color rule\n",
            [], False, "`### 3.` items INSIDE an entry (the first cut's 60 false findings)"),
        "h3 sub-entry is citable": (
            index + "## §165 — The whisper\n\n### 165a. The whisper names itself\n",
            [("Model/DayBrief.swift", "165a")], False,
            "a citation of an H3 sub-entry (§165a), which is a real target"),
        "h3 list item is not citable": (
            index + "## §61 — The ladder\n\n### 3. Color rule\n",
            [("CLAUDE.md", "3")], True,
            "a citation of `### 3.`, a list item that defines no section"),
        "sub-entry reuses its number": (
            index + "## §319 — The agent economy\n\n## §319 amendment — the x402 room\n",
            [], False, "an `amendment` heading deliberately re-using its parent's number"),
        "dangling citation": (
            index + "## §61 — The ladder\n",
            [("Model/CursorRoom.swift", "340")], True,
            "a source citation with no heading (the 2026-08-08 session)"),
        "known dangling": (
            index + "## §61 — The ladder\n",
            [("scripts/cloudkit-schema.sh", "525")], False,
            "a KNOWN_DANGLING citation of the retired numbering scheme"),
        "unindexed supersede": (
            index + "## §61 — The ladder\n\n## §97 — Doors\n\nThis supersedes §61 "
                    "and also supersedes §102.\n\n## §102 — Token surfaces\n",
            [], True, "a named supersede with no row in the index"),
        "supersede by date": (
            clean + "\nThis supersedes the 2026-07-14 rolling window.\n",
            [], False, "a supersede named by DATE, which is untabulatable"),
        "foreign doc supersede": (
            clean + "\nThis amends build-brief §8's type ramp.\n",
            [], False, "a supersede naming another document"),
        "no index at all": (
            "## §61 — The ladder\n", [], True,
            "a ledger with no Superseded index section"),
        "clean": (clean, [("CLAUDE.md", "61")], False, "a correct ledger"),
    }

    ok = True
    for name, (text, cites, should_flag, why) in cases.items():
        flagged = bool(audit(text, cites))
        if flagged != should_flag:
            ok = False
        mark = "ok  " if flagged == should_flag else "FAIL"
        verb = "flags " if should_flag else "passes"
        print(f"  {mark} {verb} {why}")

    # --next, proven on the one property that is its whole reason to exist: an
    # uncommitted claim counts as TAKEN. A heading-only reading of this fixture
    # answers §62 — the number another session is already writing comments
    # against — which is the collision, handed out by the tool meant to prevent
    # it. The gap at §60 must NOT be offered, and §525 (KNOWN_DANGLING) must not
    # push the answer into the 500s.
    ledger = index + "## §59 — Ladder\n\n## §61 — Doors\n"
    claims = [("Casberi/Casberi/Model/Thing.swift", "62"),
              ("scripts/cloudkit-schema.sh", "525")]
    nxt, claimed, gaps, _, elsewhere = next_free(
        ledger, claims, siblings={"64": {"other-tree: entry written"},
                                  "61": {"x: cited"},
                                  "525": {"stale-ship-tree: cited"}})
    for why, got in (("counts an entry written in ANOTHER worktree as taken",
                      nxt == 65 and [n for n, _ in elsewhere] == ["64"]),
                     ("ignores a sibling claim that already has a heading here",
                      "61" not in [n for n, _ in elsewhere]),
                     ("ignores a stale worktree citing a KNOWN_DANGLING number",
                      "525" not in [n for n, _ in elsewhere] and nxt == 65),
                     ("offers the number after the highest claim once siblings are gone",
                      next_free(ledger, claims)[0] == 63),
                     ("names the claim so nobody takes it twice", [n for n, _ in claimed] == ["62"]),
                     ("reports the gap without offering it", 60 in gaps and nxt != 60),
                     ("ignores a KNOWN_DANGLING citation", nxt < 500)):
        if not got:
            ok = False
        print(f"  {'ok  ' if got else 'FAIL'} --next {why}")
    return ok


if "--next" in sys.argv:
    if not self_test():
        print("✗ prd index: SELF-TEST FAILED — not answering with a number the "
              "audit cannot stand behind")
        sys.exit(1)
    nxt, claimed, gaps, count, elsewhere = next_free(
        LEDGER.read_text(encoding="utf-8"), collect_citations(CITERS, skip=LEDGER),
        siblings=sibling_claims())
    print(f"next free section: §{nxt}")
    print(f"  {count} sections written")
    if claimed:
        print("  claimed but unwritten (someone is mid-work — do NOT take these):")
        for num, paths in claimed:
            where = ", ".join(sorted(paths)[:3])
            more = f" +{len(paths) - 3} more" if len(paths) > 3 else ""
            print(f"    §{num} — cited by {where}{more}")
    if elsewhere:
        print("  taken in ANOTHER checkout on this machine (do NOT take these):")
        for num, where in elsewhere:
            print(f"    §{num} — {', '.join(sorted(where))}")
    if gaps:
        print(f"  gaps, reported only, never reuse: {', '.join('§' + str(g) for g in gaps[-6:])}")
    print("  CEILING: this reads working trees on THIS machine. A checkout "
          "elsewhere is invisible, and an entry that exists only as an "
          "uncommitted append is invisible to anyone reading HEAD — so say the "
          "number you take out loud.")
    sys.exit(0)


if "--self-test" in sys.argv:
    print("prd-index-audit self-test")
    sys.exit(0 if self_test() else 1)

if not LEDGER.exists():
    print(f"✗ prd index: {LEDGER} not found")
    sys.exit(1)

if not self_test():
    print("✗ prd index: SELF-TEST FAILED — the audit is not trustworthy, so "
          "the tree was not checked")
    sys.exit(1)

ledger = LEDGER.read_text(encoding="utf-8")
findings = audit(ledger, collect_citations(CITERS, skip=LEDGER))
if findings:
    print("✗ PRD ledger index findings:")
    for f in findings:
        print(f"  {f}")
    print("\nA `§N` citation is the only thing that makes a 20,000-line "
          "append-only ledger navigable. A number that resolves to the wrong "
          "ruling, or to nothing, is worse than no citation — it answers "
          "confidently and wrongly, and no build or screen sweep can see it.")
    sys.exit(1)

heads = headings(ledger)
print(f"✓ prd index: {len(heads)} sections, every number unique, every heading "
      f"H2, every citation resolves, every named supersede indexed")
