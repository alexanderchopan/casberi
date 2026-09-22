#!/usr/bin/env python3
"""Footnote audit (prd §748, 2026-09-15).

THE RULING. The user, on why the app reads as "vibecoded": copy that explains
itself — state lines, captions under marks, footers under rows, empty-state
sentences, prose next to every control. The rule, in their words: **"one
explaining sentence per screen at most, and only if it says something the
controls don't."**

§708 and §729 applied that to the account pages, and `setup-copy-audit.py`
check 8 holds the setup screens to it. Everywhere else it lived in memory,
which is the thing this repo keeps learning loses: §218b ruled "one gray
sentence per screen" and two passes later the screens held five. So the
sentence has ONE view, `DSFootnote` (`Design/DSFootnote.swift`), and this
script counts it.

FOUR CHECKS, all static — no build, no simulator:

  0. THE ONE VIEW STAYS ONE. `DSFootnote` draws in `DS.textTertiary`, and
     `DSSlabNote` renders THROUGH it. The second half is what makes check 1
     honest: a `DSSlabNote` is counted as a footnote, which is only true while
     it is one.
  1. ONE PER SCREEN. A file under Screens/, Shell/ or GenUI/ draws at most one
     `DSFootnote(` or `DSSlabNote(`, unless `ALLOWANCE` names it with a count
     and a reason. An allowance is a ruling that the sentences are never on
     screen together (exclusive states, separate sheets in one file) or that
     each is a KEPT CATEGORY below — never a snooze. A STALE allowance (the file
     now draws fewer) is a finding too, so the list cannot quietly grow slack.
  2. NO HAND-DRAWN FOOTER. A `footer:` closure's words go through
     `DSFootnote`. A `Text` in tertiary or secondary ink inside one is the
     sentence drawn by hand. (Error copy in `DS.attention`/`DS.destructive`
     is not a footnote and is not flagged.)
  3. NO HAND-DRAWN FOOTNOTE. A `Text` whose literal is a SENTENCE (four words
     or more, ending in a full stop) set at a footnote rung (`subhead12`,
     `label12`, `label12`, `body17`) in `DS.textTertiary` is an explaining
     sentence drawn by hand. A STATUS is not an explanation: a line that
     reports what happened or is happening ("Couldn't …", "Nothing …",
     "Waiting …", "Sign-in cancelled …") matches `STATUS_RE` and passes.

THE KEPT CATEGORIES (why an allowance may exceed one). Each is kept regardless
of the cap, and each allowance below names which it is:
  (a) honesty and overclaim guards — §83's fake-status ban said out loud
      ("Encrypted, but Apple holds the keys…", "… doesn't report token counts
      to us").
  (b) consent, money and signing disclosures — what a signature does, who pays,
      that a key cannot move money, that test ETH has no value (App Review
      3.1.1 / 3.1.5 read these).
  (c) privacy and permission explanations — what leaves the device and to whom.
  (d) error copy that tells the person how to fix something.

DELIBERATE NON-CHECKS, so nobody "improves" this into a lint that cries wolf:
  · It does not read a sentence for QUALITY. Whether a line restates a control
    is a judgement; the audit enforces the count and the one drawing, and the
    ruling carries the judgement.
  · It does not follow `Text(someVariable)`. A computed note (a coverage
    ceiling, a census count) is usually data with a clause attached, and a
    name-based guess ("note", "caption") flags data rows.
  · It does not count `DSEmptyState`. An empty place saying what it would hold
    is the page's only content (§611), not a sentence beside a control.
  · It does not scan `DSToggleRow`/`DSPushRow` details. A row's subtitle is the
    row's own second line.

Run standalone, or via `scripts/verify.sh` (its own step, after the setup
copy audit; `verify-mac.sh` and CI discover it by name). `--self-test` proves
every check catches its own shape first.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "Casberi", "Casberi")
SCAN_DIRS = ("Screens", "Shell", "GenUI")
FOOTNOTE_SRC = os.path.join(APP, "Design", "DSFootnote.swift")
SLAB_SRC = os.path.join(APP, "Design", "DSSlab.swift")

FOOTNOTE_RE = re.compile(r"\b(?:DSFootnote|DSSlabNote)\(")
RUNGS = ("subhead12", "label12", "body17")
STATUS_RE = re.compile(
    r"^(Couldn't|Can't|No |Nothing|Nobody|Not |Sign-in cancelled|Waiting|"
    r"Reading|Asking|Working|Checking|Loading|Pick something)")
MIN_SENTENCE_WORDS = 4

# Files allowed more than one footnote. {file: (count, reason)}. The count is
# exact: a file drawing fewer is a stale entry and fails check 1.
ALLOWANCE = {
    # Three settings cards in one file (Data, Agent key, Notifications). Data
    # holds the librarian disclosure (two exclusive branches, (c)), the ADP
    # line (a) and the redaction line (c); notifications its no-push ceiling (a).
    # The key card's provider disclosure left with the card (prd §871).
    "AccountDetailSheet.swift": (5, "two settings cards; (a)(b)(c)"),
    # The usage card's two honesty lines (a), the librarian's never-shown line
    # (a), the budget control's three conditional lines (a)(b), and the Mac
    # MCP row's one sentence — four separate components in one file.
    "AgentKeyDetail.swift": (7, "four components; (a)(b)"),
    # The rename field's destructive consequence, the empty card, and the name
    # nudge's consequence are three different surfaces of the address book.
    "AddressBookViews.swift": (3, "three surfaces; consequence of an edit (b)"),
    # Three sheets in one file: Advanced (what is signed, (b)), who pays the
    # fee (b), and the pay link's expiry (b).
    "DevnetSendConsole.swift": (3, "three sheets; signing disclosures (b)"),
    # The quote's two lines never show together: "sign there" is the ready
    # state, the price drift is the quote.
    "ENSRenewCard.swift": (2, "exclusive states; signing and money (b)"),
    # The devnet's test-ETH disclosure (b, the 3.1.5 line), and the passkey
    # account's two branches (created vs create), which are exclusive (b).
    "FramesScreen.swift": (3, "test ETH + exclusive key-custody states (b)"),
    # Receipts: what is not recorded (a) and what forgetting does not do (a).
    "NetworkReceiptsScreen.swift": (2, "receipts ceiling and forget; (a)"),
    # A Safe you cannot sign vs one you just signed — exclusive states (b).
    "SafeQueueCard.swift": (2, "exclusive states; signing (b)"),
    # The watch form and the co-signer block: the second is the one place the
    # app says a key has no recovery phrase (b).
    "SafeScreen.swift": (2, "watch form + co-signer key custody (b)"),
    # A mail thing's header-only line (a) and a Home accessory's read-only
    # line (a) are two kinds' content blocks in one file.
    "ThingContent.swift": (2, "two kinds' blocks; (a)"),
    # Connect form and connected state are exclusive (§315's NOTE_ALLOWANCE
    # shape): the form's region fact, the connected state's arrivals.
    "AWSScreen.swift": (2, "exclusive states: form / connected"),
    "AppStoreConnectScreen.swift": (2, "exclusive states: form / connected"),
    # The key form refuses a money-moving key; the verdict says the venue
    # confirmed it cannot trade. Exclusive states, both (b).
    "ExchangeSetupScreen.swift": (2, "exclusive states; money (b)"),
    # GitHub's watch form (privacy (c)) and the device-flow scope line are
    # separate forms in one file.
    "TokenSetupScreen.swift": (2, "separate forms; (c) + a scope"),
}

# Files other sessions are rewriting as of 2026-09-15; their copy comes under
# this audit when that work lands. Named, not globbed, except the room heads.
PENDING = {"ShapedRows.swift", "CursorRow.swift", "WalletbeatRow.swift",
           "L2beatRow.swift", "WalletRow.swift", "SourceChips.swift"}


def strip_comments(src: str) -> str:
    """Blank `//` and `/* */` comments, keeping string literals and offsets."""
    out, i, n = [], 0, len(src)
    while i < n:
        if src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
        elif src.startswith("/*", i):
            j = src.find("*/", i)
            j = n if j < 0 else j + 2
            out.append(re.sub(r"[^\n]", " ", src[i:j]))
            i = j
        elif src[i] == '"':
            if src.startswith('"""', i):
                j = src.find('"""', i + 3)
                j = n if j < 0 else j + 3
            else:
                j = i + 1
                while j < n and src[j] not in '"\n':
                    j += 2 if src[j] == "\\" else 1
                j += 1
            out.append(src[i:j])
            i = j
        else:
            out.append(src[i])
            i += 1
    return "".join(out)


def balanced(src: str, open_at: int) -> tuple:
    """The text of the bracket group opening at `open_at`, and its end."""
    pairs = {"(": ")", "{": "}"}
    opener = src[open_at]
    closer = pairs[opener]
    depth, j, n, in_str = 0, open_at, len(src), False
    while j < n:
        c = src[j]
        if in_str:
            if c == "\\":
                j += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c == opener:
            depth += 1
        elif c == closer:
            depth -= 1
            if depth == 0:
                return src[open_at:j + 1], j + 1
        j += 1
    return src[open_at:], n


def modifier_chain(src: str, end: int) -> str:
    """The `.modifier(…)` lines that follow a view expression ending at `end`."""
    chain, j, n = [], end, len(src)
    while j < n:
        m = re.match(r"[ \t]*\n?[ \t]*\.", src[j:])
        if not m:
            break
        k = j + m.end() - 1
        call = re.match(r"\.\w+", src[k:])
        if not call:
            break
        k += call.end()
        if k < n and src[k] == "(":
            _, k = balanced(src, k)
        chain.append(src[j:k])
        j = k
    return "".join(chain)


LITERAL_RE = re.compile(r'"((?:[^"\\\n]|\\.)*)"')


def sentence(lit: str) -> bool:
    words = re.sub(r"\\\([^)]*\)", "X", lit).split()
    return (len(words) >= MIN_SENTENCE_WORDS and lit.rstrip().endswith(".")
            and not STATUS_RE.match(lit))


def audit_file(name: str, src: str, allowance=None) -> list:
    allowance = ALLOWANCE if allowance is None else allowance
    body = strip_comments(src)
    findings = []

    # 1: one per screen.
    count = len(FOOTNOTE_RE.findall(body))
    cap, _ = allowance.get(name, (1, ""))
    if count > cap:
        findings.append(f"{name}: {count} footnotes (max {cap}) — one explaining "
                        f"sentence per screen; delete what a control already says, "
                        f"or merge two into one")
    elif name in allowance and count < cap:
        findings.append(f"{name}: allowance says {cap} footnotes, the file draws "
                        f"{count} — lower ALLOWANCE to {max(count, 1)} "
                        f"(or remove the entry)")

    # 2: a footer drawn by hand.
    for m in re.finditer(r"\bfooter:\s*\{", body):
        closure, _ = balanced(body, m.end() - 1)
        for t in re.finditer(r"\bText\(", closure):
            _, tend = balanced(closure, t.end() - 1)
            chain = modifier_chain(closure, tend)
            if re.search(r"DS\.text(Tertiary|Secondary)", chain):
                line = body.count("\n", 0, m.start()) + 1
                findings.append(f"{name}:{line}: a footer drawn by hand — "
                                f"use DSFootnote(…, scale: .page)")

    # 3: an explaining sentence drawn by hand at a footnote rung.
    for t in re.finditer(r"\bText\(", body):
        arg, tend = balanced(body, t.end() - 1)
        lits = [l for l in LITERAL_RE.findall(arg) if sentence(l)]
        if not lits:
            continue
        chain = modifier_chain(body, tend)
        rung = re.search(r"\.dsText\(\.(\w+)\)", chain)
        if rung and rung.group(1) in RUNGS and "DS.textTertiary" in chain:
            line = body.count("\n", 0, t.start()) + 1
            findings.append(f"{name}:{line}: an explaining sentence drawn by hand "
                            f"— route it through DSFootnote, or delete it "
                            f"— {lits[0][:60]}")
    return findings


def audit_component(footnote_src: str, slab_src: str) -> list:
    """Check 0: the one view keeps its ink, and DSSlabNote draws through it."""
    findings = []
    fn = strip_comments(footnote_src)
    if "struct DSFootnote" not in fn or "DS.textTertiary" not in fn:
        findings.append("DSFootnote.swift: DSFootnote must exist and draw in "
                        "DS.textTertiary")
    slab = strip_comments(slab_src)
    m = re.search(r"struct DSSlabNote\b", slab)
    if not m:
        findings.append("DSSlab.swift: DSSlabNote is gone — update check 1, "
                        "which counts it as a footnote")
    else:
        body, _ = balanced(slab, slab.index("{", m.end()))
        if "DSFootnote(" not in body:
            findings.append("DSSlab.swift: DSSlabNote no longer renders through "
                            "DSFootnote, so counting it as one is a lie")
    return findings


# ── self-test ──────────────────────────────────────────────────────────────

CLEAN = '''
struct S: View {
    var body: some View {
        VStack {
            // DSFootnote("a comment is not a footnote.") DSFootnote(
            DSFootnote("Test ETH has no value, and the network may be reset.")
            Text("Couldn't read this pack just now.")
                .dsText(.body17).foregroundStyle(DS.textTertiary)
            Text("\\(count) things · \\(apps) apps")
                .dsText(.subhead12).foregroundStyle(DS.textTertiary)
            Text("Waiting for your approval…")
                .dsText(.subhead12).foregroundStyle(DS.textTertiary)
            Text("A title in primary ink says a lot of words here.")
                .dsText(.body17).foregroundStyle(DS.textPrimary)
            Section { row } footer: {
                Text("A bug in the list, not a hidden service.")
                    .dsText(.body17).foregroundStyle(DS.attention)
            }
        }
    }
}
'''
DIRTY_SECOND = '''
VStack {
    DSFootnote("One sentence that is needed here.")
    DSFootnote(Text("A second one that says the same thing."))
}
'''
DIRTY_SLAB_PLUS = '''
VStack {
    DSSlabNote(text: "A slab note.", plain: true)
    DSFootnote("And a footnote beside it.")
}
'''
DIRTY_HAND = '''
VStack {
    Text("Watching puts it in this room with your other accounts.")
        .dsText(.label12)
        .foregroundStyle(DS.textTertiary)
}
'''
DIRTY_HAND_LOCALIZED = '''
Text(String(localized: "Sends in different channels don't queue behind each other."))
    .dsText(.label12).foregroundStyle(DS.textTertiary)
    .fixedSize(horizontal: false, vertical: true)
'''
DIRTY_FOOTER = '''
Section { rows } footer: {
    Text(ceiling).dsText(.body17).foregroundStyle(DS.textTertiary)
}
'''
FOOTNOTE_OK = 'struct DSFootnote: View { var body: some View { text.foregroundStyle(DS.textTertiary) } }'
SLAB_OK = 'struct DSSlabNote: View { var body: some View { DSFootnote(Text(x)) } }'
SLAB_HAND = 'struct DSSlabNote: View { var body: some View { Text(x).foregroundStyle(DS.textTertiary) } }'


def self_test() -> bool:
    ok = True

    def expect(label, findings, want, needle=""):
        nonlocal ok
        hit = any(needle in f for f in findings) if needle else bool(findings)
        if hit != want:
            print(f"  SELF-TEST FAIL: {label} — {findings}")
            ok = False
        else:
            print(f"  ✓ {label}")

    expect("passes one footnote, statuses, data, error ink and comments",
           audit_file("Clean.swift", CLEAN, {}), False)
    expect("catches a second footnote on one screen",
           audit_file("Two.swift", DIRTY_SECOND, {}), True, "2 footnotes")
    expect("counts DSSlabNote as a footnote",
           audit_file("Slab.swift", DIRTY_SLAB_PLUS, {}), True, "2 footnotes")
    expect("an allowance admits exactly its count",
           audit_file("Two.swift", DIRTY_SECOND, {"Two.swift": (2, "r")}), False)
    expect("a stale allowance is a finding",
           audit_file("Two.swift", DIRTY_SECOND, {"Two.swift": (3, "r")}), True,
           "lower ALLOWANCE")
    expect("an allowance does not leak to another file",
           audit_file("Other.swift", DIRTY_SECOND, {"Two.swift": (2, "r")}), True,
           "2 footnotes")
    expect("catches a hand-drawn footnote",
           audit_file("Hand.swift", DIRTY_HAND, {}), True, "drawn by hand")
    expect("catches a hand-drawn footnote through String(localized:)",
           audit_file("Hand.swift", DIRTY_HAND_LOCALIZED, {}), True, "drawn by hand")
    expect("catches a footer drawn by hand",
           audit_file("Foot.swift", DIRTY_FOOTER, {}), True, "footer drawn by hand")
    expect("check 0 passes the real shape",
           audit_component(FOOTNOTE_OK, SLAB_OK), False)
    expect("check 0 catches DSSlabNote drawing its own Text",
           audit_component(FOOTNOTE_OK, SLAB_HAND), True, "no longer renders")
    expect("check 0 catches a footnote in the wrong ink",
           audit_component(FOOTNOTE_OK.replace("textTertiary", "textPrimary"), SLAB_OK),
           True, "DS.textTertiary")
    return ok


def main() -> int:
    if "--self-test" in sys.argv:
        print("footnote-audit self-test")
        ok = self_test()
        print("  self-test PASSED" if ok else "  self-test FAILED")
        return 0 if ok else 1

    print("footnote-audit (prd §748)")
    if not self_test():
        print("  refusing to certify: the audit's own self-test failed")
        return 1

    findings = audit_component(open(FOOTNOTE_SRC).read(), open(SLAB_SRC).read())
    files = footnotes = 0
    seen = set()
    for d in SCAN_DIRS:
        for fn in sorted(os.listdir(os.path.join(APP, d))):
            if not fn.endswith(".swift") or fn in PENDING or fn.endswith("RoomCard.swift"):
                continue
            src = open(os.path.join(APP, d, fn)).read()
            files += 1
            seen.add(fn)
            footnotes += len(FOOTNOTE_RE.findall(strip_comments(src)))
            findings += audit_file(fn, src)
    for fn in sorted(set(ALLOWANCE) - seen):
        findings.append(f"{fn}: named in ALLOWANCE but not found — remove the entry")

    print(f"  {files} files, {footnotes} footnotes, {len(ALLOWANCE)} allowances")
    if findings:
        print(f"\n  {len(findings)} finding(s):")
        for f in findings:
            print(f"    · {f}")
        return 1
    print("  clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
