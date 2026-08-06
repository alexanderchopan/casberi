#!/usr/bin/env python3
"""Connect-page copy audit (prd §315, 2026-08-06).

WHY THIS EXISTS. The connect screens have now been de-walled TWICE. §218 ruled
"one gray sentence per screen"; by §314 the import screens carried five notes
totalling ~130 words. §314 gave the family a staged shape and a single footer;
by §315 that footer was up to a lede plus four bullets plus a detail paragraph,
and Instagram's connect page ran ~145 words before you had done anything —
reported by the user, again, as *"really wordy and bad with text in different
places"*.

The lesson this repo already writes down everywhere else applies here: a rule
that lives in memory loses. Every other load-bearing rule in CLAUDE.md is a
script. The design system got its first mechanical check in §299 for exactly
this reason. This is the copy equivalent.

FIVE CHECKS, all static — no build, no simulator:

  1. DECLARED MODE — every connect screen's `BridgeSetupHeader` names a `mode:`.
     The mode is the fact the whole pass exists to surface (does anything arrive
     on its own?), so a screen that omits it has silently opted out.
  2. INTRO BUDGET — the intro is at most MAX_INTRO_SENTENCES sentences and
     MAX_INTRO_WORDS words. This is the whole prose budget of the screen.
  3. STEP BUDGET — a `BridgeStepLines` step is at most MAX_STEP_WORDS words.
     Steps say what to DO; reasons belong in error copy, which is the only
     place they can be acted on.
  4. NOTE COUNT — at most MAX_SLAB_NOTES `DSSlabNote`s per screen, because
     `DSSlabNote`'s own doc says "every manage page gets exactly one" and the
     family has drifted past that twice. Screens serving several bridges get a
     documented allowance in `NOTE_ALLOWANCE`.
  5. NO FOOTER WALL — `BridgeFooterNote` is deleted and must not come back
     under a new name: a `Section { … } footer:` closure on a setup screen
     carrying more than FOOTER_WORD_FLOOR words is the same wall rebuilt.

Run standalone, or via `scripts/verify.sh`'s static head. `--self-test` proves
each check catches its own shape before it certifies the tree — a check that
cannot fail proves nothing (the liveness-audit contract).

DELIBERATE NON-CHECKS, so nobody "improves" this into a lint that cries wolf
and gets turned off within a week:

  · It does not read the intro for QUALITY. It cannot tell a true sentence from
    a false one, and pretending otherwise would be the fake status §83 bans.
  · It does not require an intro at all when there is no `BridgeSetupHeader`.
    `StocktwitsScreen` has none by ruling (§185) and carries its honesty fact
    on the slab note beside the field instead — a real design decision, not an
    omission.
  · It does not count words in `canLine`/`summary`. Those are the CONNECTED
    state and the product page, read in different places for different reasons,
    and holding a capability line to a connect page's budget would delete true
    differentiating information (the §192 ruling).
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCREENS = os.path.join(ROOT, "Casberi", "Casberi", "Screens")

# Budgets. Each is a MEASURED ceiling, not a round number picked from
# intuition — see the header for what the screens actually looked like when
# they were reported. Raising one is a product decision, so raise it here and
# say why, rather than adding an exemption per screen.
MAX_INTRO_SENTENCES = 2
MAX_INTRO_WORDS = 55
MAX_STEP_WORDS = 14
MAX_SLAB_NOTES = 2
FOOTER_WORD_FLOOR = 25

# Screens serving SEVERAL bridges from one file legitimately carry more than
# one note, because the notes belong to different forms on different branches.
# An entry here is a conscious ruling that the notes are not stacked on one
# screen at one time, never a snooze.
NOTE_ALLOWANCE = {
    # GitHub's sign-in path, the manual token path, the feed picker and the
    # private-watch field are four separate forms; at most two are ever on
    # screen together.
    "TokenSetupScreen.swift": 5,
    # Trello's two-stage form (key, then token) plus the shared keychain note.
    # Counted above.
    "HandleSetupScreen.swift": 3,
    # Day One, Apple Journal, Apple Notes and Bookmarks are four screens in
    # one file.
    "NotesImportScreens.swift": 4,
    # The screen has a connect form and a connected state with separate notes.
    "DropboxScreen.swift": 3,
    "PostHogScreen.swift": 3,
}

# Files that hold a `BridgeSetupHeader` call but are not connect screens, or
# are shared components rather than a screen.
SKIP = {"BridgeSetupComponents.swift", "ImportSetupComponents.swift"}


# ── parsing helpers ────────────────────────────────────────────────────────

def strip_comments(src: str) -> str:
    """Comments quote old copy verbatim (this repo documents what it deleted),
    so counting words in them would flag a screen for its own changelog."""
    out, i, n = [], 0, len(src)
    while i < n:
        if src.startswith("//", i):
            j = src.find("\n", i)
            i = n if j < 0 else j
        elif src.startswith("/*", i):
            j = src.find("*/", i + 2)
            i = n if j < 0 else j + 2
        elif src[i] == '"':
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == '"':
                    j += 1
                    break
                j += 1
            out.append(src[i:j])
            i = j
        else:
            out.append(src[i])
            i += 1
    return "".join(out)


def balanced(src: str, open_at: int) -> str:
    """The text inside the parens/braces starting at `open_at`, string-aware —
    a naive depth counter trips on a `)` inside copy, which most of this copy
    has."""
    opener = src[open_at]
    closer = {"(": ")", "{": "}", "[": "]"}[opener]
    depth, i, n = 1, open_at + 1, len(src)
    instr = False
    while i < n and depth:
        ch = src[i]
        if instr:
            if ch == "\\":
                i += 2
                continue
            if ch == '"':
                instr = False
        elif ch == '"':
            instr = True
        elif ch == opener:
            depth += 1
        elif ch == closer:
            depth -= 1
        i += 1
    return src[open_at + 1:i - 1]


def literals(src: str):
    """Every Swift string literal, unescaped enough to count words in."""
    found = re.findall(r'"((?:[^"\\\n]|\\.)*)"', src)
    return [f.replace('\\"', '"').replace("\\n", " ") for f in found]


def words(text: str) -> int:
    # Interpolations are one word when rendered ("\(DS.device)" → "iPhone").
    return len(re.sub(r"\\\([^)]*\)", "X", text).split())


def sentences(text: str) -> int:
    text = re.sub(r"\\\([^)]*\)", "X", text).strip()
    return len([s for s in re.split(r"(?<=[.!?])\s+", text) if s.strip()])



# ── the catalog offer's own budget (added 2026-08-06) ──────────────────────
#
# The connect SCREEN had a budget and the catalog SUMMARY did not, so the same
# sprawl the §315 rules pushed off the screen simply moved one surface over.
# The Apple Wallet offer landed at 131 words in 4 paragraphs — three times the
# median and half again the longest legitimate entry — and nothing could see it.
#
# MEASURED, not chosen (2026-08-06, over the 91 offers that carry a summary):
# median 43 words, p90 75, longest real entry 88 (Gnosis Pay). So the ceiling is
# 90 — above every offer written to date, which means it flags NEW sprawl and
# never re-litigates copy the user already approved. Paragraphs cap at 3, the
# median and the observed maximum.
#
# What it deliberately does NOT check: the QUALITY of a sentence (it cannot
# tell a true one from a false one), the tagline (already one short phrase by
# construction), or the ceilings an offer must state — an honest caveat is
# exactly what a word budget must never squeeze out, which is why the ceiling
# sits above the longest honest entry rather than at the median.
OFFER_MAX_WORDS = 90
OFFER_MAX_PARAGRAPHS = 3
CATALOG = os.path.join(ROOT, "Casberi", "Casberi", "Model", "BridgeCatalog.swift")


def audit_catalog(src: str):
    findings = []
    offers = 0
    for m in re.finditer(r'Offer\(name:\s*"([^"]+)".*?summary:\s*"((?:[^"\\]|\\.)*)"',
                         src, re.S):
        name, raw = m.group(1), m.group(2)
        offers += 1
        text = raw.replace('\\"', '"')
        paras = [p for p in text.split("\\n\\n") if p.strip()]
        w = words(text.replace("\\n", " "))
        if w > OFFER_MAX_WORDS:
            findings.append(f"{name}: summary is {w} words (max {OFFER_MAX_WORDS}) — "
                            f"the median offer is 43")
        if len(paras) > OFFER_MAX_PARAGRAPHS:
            findings.append(f"{name}: summary is {len(paras)} paragraphs "
                            f"(max {OFFER_MAX_PARAGRAPHS})")
    return findings, offers

# ── the checks ─────────────────────────────────────────────────────────────

def audit_source(name: str, src: str):
    """Returns a list of finding strings for one screen's source text."""
    findings = []
    body = strip_comments(src)

    # 1 + 2: every header declares a mode, and its intro fits the budget.
    for m in re.finditer(r"BridgeSetupHeader\(", body):
        call = balanced(body, m.end() - 1)
        if "mode:" not in call:
            findings.append(f"{name}: BridgeSetupHeader with no `mode:` — "
                            f"every connect screen states how it connects")
            continue
        intro = re.search(r"intro:\s*(.*)", call, re.S)
        if not intro:
            continue
        for lit in literals(intro.group(1))[:1]:
            w, s = words(lit), sentences(lit)
            if w > MAX_INTRO_WORDS:
                findings.append(f"{name}: intro is {w} words "
                                f"(max {MAX_INTRO_WORDS}) — {lit[:60]}…")
            if s > MAX_INTRO_SENTENCES:
                findings.append(f"{name}: intro is {s} sentences "
                                f"(max {MAX_INTRO_SENTENCES}) — {lit[:60]}…")

    # 3: steps are instructions, not explanations.
    for m in re.finditer(r"BridgeStepLines\(", body):
        call = balanced(body, m.end() - 1)
        steps = re.search(r"steps:\s*\[", call)
        block = balanced(call, steps.end() - 1) if steps else call
        for lit in literals(block):
            w = words(lit)
            if w > MAX_STEP_WORDS:
                findings.append(f"{name}: step is {w} words "
                                f"(max {MAX_STEP_WORDS}) — {lit[:60]}…")

    # `steps:` passed as an array literal to `ImportArchiveSection` too.
    for m in re.finditer(r"ImportArchiveSection\(", body):
        call = balanced(body, m.end() - 1)
        steps = re.search(r"steps:\s*\[", call)
        if not steps:
            continue
        for lit in literals(balanced(call, steps.end() - 1)):
            w = words(lit)
            if w > MAX_STEP_WORDS:
                findings.append(f"{name}: step is {w} words "
                                f"(max {MAX_STEP_WORDS}) — {lit[:60]}…")

    # 4: the one-gray-sentence rule, mechanised.
    notes = len(re.findall(r"\bDSSlabNote\(", body))
    cap = NOTE_ALLOWANCE.get(name, MAX_SLAB_NOTES)
    if notes > cap:
        findings.append(f"{name}: {notes} DSSlabNotes (max {cap}) — "
                        f"fine print belongs beside its control or in error copy")

    # 5: the wall, rebuilt under a new name.
    if "BridgeFooterNote" in body:
        findings.append(f"{name}: BridgeFooterNote is deleted (§315) — "
                        f"the intro sentence replaced it")
    for m in re.finditer(r"\}\s*footer:\s*\{", body):
        block = balanced(body, m.end() - 1)
        total = sum(words(l) for l in literals(block))
        if total > FOOTER_WORD_FLOOR:
            findings.append(f"{name}: section footer carries {total} words "
                            f"(max {FOOTER_WORD_FLOOR}) — that is the wall again")

    return findings


# ── self-test ──────────────────────────────────────────────────────────────

DIRTY_NO_MODE = '''
struct S: View { var body: some View { List {
    BridgeSetupHeader(name: "X", connected: true)
} } }
'''

DIRTY_LONG_INTRO = '''
struct S: View { var body: some View { List {
    BridgeSetupHeader(name: "X", mode: .noAccount,
        intro: "One two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty twentyone twentytwo twentythree twentyfour twentyfive twentysix twentyseven twentyeight twentynine thirty thirtyone thirtytwo thirtythree thirtyfour thirtyfive thirtysix thirtyseven thirtyeight thirtynine forty fortyone fortytwo fortythree fortyfour fortyfive fortysix fortyseven fortyeight fortynine fifty fiftyone fiftytwo fiftythree fiftyfour fiftyfive fiftysix.")
} } }
'''

DIRTY_MANY_SENTENCES = '''
struct S: View { var body: some View { List {
    BridgeSetupHeader(name: "X", mode: .noAccount,
        intro: "One sentence here. Two sentences here. Three sentences here.")
} } }
'''

DIRTY_LONG_STEP = '''
struct S: View { var body: some View { List {
    BridgeSetupHeader(name: "X", mode: .pasteKey, intro: "Short.")
    BridgeStepLines(steps: [
        "This step explains far too much about why the format matters and keeps going well past any reasonable budget.",
    ], startingAt: 2)
} } }
'''

DIRTY_FOOTER = '''
struct S: View { var body: some View { List {
    BridgeSetupHeader(name: "X", mode: .noAccount, intro: "Short.")
    Section { row } footer: {
        Text("Read-only: nothing here ever places a trade, and the odds are public.")
        Text("No account, no key — fetched directly by this device through each exchange's own public feed, with no ranking of ours applied anywhere.")
    }
} } }
'''

DIRTY_NOTES = '''
struct S: View { var body: some View { List {
    BridgeSetupHeader(name: "X", mode: .noAccount, intro: "Short.")
    DSSlabNote(text: "One.")
    DSSlabNote(text: "Two.")
    DSSlabNote(text: "Three.")
} } }
'''

CLEAN = '''
struct S: View { var body: some View { List {
    // A comment quoting the OLD wall verbatim, which must not be counted:
    // "One-time import — nothing arrives on its own afterwards, and
    // re-importing later adds only what's new, and your captions and comments
    // arrive as searchable text, and saves and likes arrive as links."
    BridgeSetupHeader(
        name: "X", mode: .oneTimeImport,
        intro: "X has no live connection — download your export, bring it here, and search everything in it. Re-import any time for what's new.")
    BridgeStepLines(steps: [
        "Choose Download or transfer information, then Some of your information.",
        "Set Format to JSON, not HTML, then Download to device.",
    ], startingAt: 2)
    DSSlabNote(text: "Your token stays in this iPhone's Keychain.")
} } }
'''


def self_test() -> bool:
    cases = [
        ("no mode declared", DIRTY_NO_MODE, "no `mode:`"),
        ("intro too long", DIRTY_LONG_INTRO, "words"),
        ("too many sentences", DIRTY_MANY_SENTENCES, "sentences"),
        ("step too long", DIRTY_LONG_STEP, "step is"),
        ("footer wall", DIRTY_FOOTER, "footer carries"),
        ("too many notes", DIRTY_NOTES, "DSSlabNotes"),
    ]
    ok = True
    for label, src, expect in cases:
        found = audit_source("fixture.swift", src)
        if not any(expect in f for f in found):
            print(f"  SELF-TEST FAIL: '{label}' was not caught "
                  f"(expected {expect!r}, got {found})")
            ok = False
        else:
            print(f"  ✓ catches {label}")
    clean = audit_source("fixture.swift", CLEAN)
    if clean:
        print(f"  SELF-TEST FAIL: clean fixture flagged — {clean}")
        ok = False
    else:
        print("  ✓ passes a clean screen (and ignores copy quoted in comments)")

    # The catalog budget's own fixtures. A check that cannot fail proves
    # nothing — and this one guards a rule that was broken the day it was
    # written (a 131-word, 4-paragraph offer), so it has to demonstrate it
    # catches both shapes and clears an ordinary entry.
    long_summary = " ".join(["word"] * (OFFER_MAX_WORDS + 5))
    dirty_words = f'Offer(name: "Bloaty", tagline: "x", group: "g", connectable: true, summary: "{long_summary}", needsSetup: true),'
    f, _ = audit_catalog(dirty_words)
    if not any("words" in x for x in f):
        print(f"  SELF-TEST FAIL: an over-long summary was not caught — {f}")
        ok = False
    else:
        print("  ✓ catches an over-long catalog summary")

    dirty_paras = 'Offer(name: "Wally", tagline: "x", group: "g", connectable: true, summary: "One.\\n\\nTwo.\\n\\nThree.\\n\\nFour.", needsSetup: true),'
    f, _ = audit_catalog(dirty_paras)
    if not any("paragraphs" in x for x in f):
        print(f"  SELF-TEST FAIL: a 4-paragraph summary was not caught — {f}")
        ok = False
    else:
        print("  ✓ catches a catalog summary with too many paragraphs")

    clean = 'Offer(name: "Tidy", tagline: "x", group: "g", connectable: true, summary: "Lands your things.\\n\\nNo account, no key.\\n\\nRead-only.", needsSetup: true),'
    f, n = audit_catalog(clean)
    if f or n != 1:
        print(f"  SELF-TEST FAIL: an ordinary offer was flagged — {f} (parsed {n})")
        ok = False
    else:
        print("  ✓ passes an ordinary catalog offer")

    return ok


# ── main ───────────────────────────────────────────────────────────────────

def main() -> int:
    if "--self-test" in sys.argv:
        print("setup-copy-audit self-test")
        ok = self_test()
        print("  self-test PASSED" if ok else "  self-test FAILED")
        return 0 if ok else 1

    print("setup-copy-audit (prd §315)")
    if not self_test():
        print("  refusing to certify: the audit's own self-test failed")
        return 1

    findings, screens = [], 0
    for fn in sorted(os.listdir(SCREENS)):
        if not fn.endswith(".swift") or fn in SKIP:
            continue
        src = open(os.path.join(SCREENS, fn)).read()
        if "BridgeSetupHeader(" not in src and "BridgeStepLines(" not in src:
            continue
        screens += 1
        findings += audit_source(fn, src)

    catalog_findings, offers = audit_catalog(strip_comments(open(CATALOG).read()))
    findings += catalog_findings

    print(f"  {screens} connect screens, {offers} catalog offers checked")
    if findings:
        print(f"\n  {len(findings)} finding(s):")
        for f in findings:
            print(f"    · {f}")
        return 1
    print("  clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
