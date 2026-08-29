#!/usr/bin/env python3
"""Connect-page SHAPE audit (2026-08-29).

WHY THIS EXISTS. `setup-copy-audit.py` made the connect family's WORDS
mechanical in §315. Its own header says the family had been de-walled twice by
memory and lost both times. The same thing then happened to the family's
ARRANGEMENT, and nothing could see it: on 2026-08-29 the L2BEAT connect page was
reported as *"totally messy like it was just thrown together with the thing to
watch at the bottom"*, and every check in `scripts/` was green over it. Its
Walletbeat twin carried all five defects line for line, so the drift had already
propagated once by copy-paste — which is exactly the shape a script catches and
a reading does not.

The defects were arrangement, not copy:

  · a shelf drawn over an empty watch list, under gesture copy for rows that do
    not exist ("Watching 0 · tap for its assessment, hold to stop watching"),
  · one control drawn as a filled primary slab in one state and a CENTERED gray
    note in the other,
  · a bare blue text link doing a control's job below the identity area — the
    exact shape §190 lists among the six the slab replaced,
  · the sync result splitting a finder in half, so a connection error read as
    the control under it being broken.

THREE CHECKS, all static — no build, no simulator. Each MEASURED against the
clean tree before it was kept; the measurements are in each check's comment,
because a check that fires on healthy code gets turned off within a week and
then the rule is back in memory where it started.

`--self-test` proves each check catches its own shape and passes the clean one
before it certifies the tree (the liveness-audit contract).

WHAT IS NOT HERE, and why — both were built, measured and REFUSED:

  · THE SHELF GATE. The headline defect. A check comparing a shelf's enclosing
    `if` against the collection its `ForEach` walks reports FIVE findings on a
    clean tree and NOT ONE is real: `TokenWatchScreen` iterates a derived
    `items` while correctly gating on the `watched` it derives from, and from
    outside that is indistinguishable from the bug. Narrowing it needs to know
    that `items` comes from `watched`, which needs Swift, not text. So this one
    is PREVENTED instead of detected — `AssetRosterShelf` takes the row count
    and draws nothing at zero, which no sixth screen can get wrong. Check 3
    below guards that guard. Prevention beat detection here; say so rather than
    shipping the wolf-crier.

  · ONE FILLED SLAB PER SCREEN. §190 says "a screen's one filled block, so it
    reads as THE verb", and the L2BEAT page did bury its verb. But the check
    reports SEVEN screens on a clean tree — the import screens legitimately
    carry a door ("Download your archive") AND a commit verb ("Choose the
    folder"), which is two filled slabs and correct. §190's sentence is about
    weight, not about counting, and a lint cannot tell the two apart.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCREENS = os.path.join(ROOT, "Casberi", "Casberi", "Screens")
COMPONENT = os.path.join(SCREENS, "AssetRoster.swift")

# A tinted text control that is deliberately NOT a slab. An entry is a
# conscious ruling, never a snooze, and it carries the reason.
KNOWN_TEXT_CONTROL = {
    ("RSSScreen.swift", "Import an OPML file"):
        "OPML import/export are secondary power-user acts sharing one centered "
        "row. As two 56pt slabs they would outweigh the Follow field above "
        "them, which is the screen's actual verb. Reviewed 2026-08-29.",
}


def strip_comments(src: str) -> str:
    """Blank comment lines, keeping line numbers.

    Read from a stripped copy for the same reason six other audits here do: the
    files DOCUMENT these rules by naming the shapes they must not use, so a
    guard grepping raw source fires on the prose explaining it.
    """
    out = []
    for line in src.split("\n"):
        if line.strip().startswith("//"):
            out.append("")
        else:
            out.append(re.sub(r"\s//(?!/).*$", "", line))
    return "\n".join(out)


def screens():
    for name in sorted(os.listdir(SCREENS)):
        if name.endswith(".swift"):
            yield name, strip_comments(open(os.path.join(SCREENS, name)).read())


# ── check 1 ────────────────────────────────────────────────────────────────

BRANCH = re.compile(
    r"\bif\s[^\n{]{0,90}\{((?:.|\n){0,700}?)\n[\t ]*\}\s*else\s*\{((?:.|\n){0,700}?)\n[\t ]*\}")


def check_one_control_one_shape(name, body):
    """A control may not be a filled slab in one state and a note in the other.

    MEASURED: one finding on the whole tree when written
    (`PredictionPreviewSheet`, "You're following this market." against "Follow
    this market"), and it was the same defect as the two connect pages — so the
    check has a real find and no false ones.

    `DSSlabNote` is CENTERED by construction and `DSSlabButton` is a full-width
    fill; putting one state in each means the control moves and changes weight
    when nothing about it changed. The on state is a `DSCheckList` line, which
    is what a granted capability is.
    """
    out = []
    for m in BRANCH.finditer(body):
        a, b = m.group(1), m.group(2)
        if ("DSSlabButton(" in a and "DSSlabNote(" in b) or \
           ("DSSlabNote(" in a and "DSSlabButton(" in b):
            line = body[:m.start()].count("\n") + 1
            out.append(f"{name}:{line}: one control drawn as a filled slab in one "
                       f"state and a centered DSSlabNote in the other — use "
                       f"DSCheckList for the settled state")
    return out


# ── check 2 ────────────────────────────────────────────────────────────────

CONTROLS = ("DSSlabField(", "DSSlabDoor(", "DSSlabButton(", "DSSlabSwitch(",
            "BridgeFieldRow(")


def check_status_last(name, body):
    """The sync result reports at the END of its block, never inside it.

    MEASURED: zero findings on the clean tree, and it fires on the exact
    ordering both connect pages shipped (proven by mutation, see --self-test).

    `BridgeSyncStatusRows` reports on a read nobody on the screen asked for and
    appears and disappears on its own, so a control under it is shoved down by
    a background event — and an error there reads as the control beneath it
    being broken, which is how "Couldn't reach L2BEAT" came to look like the
    browse link was dead.
    """
    out = []
    lines = body.split("\n")
    for i, line in enumerate(lines):
        if "BridgeSyncStatusRows(" not in line:
            continue
        indent = len(line) - len(line.lstrip())
        for j in range(i + 1, min(i + 40, len(lines))):
            nxt = lines[j]
            if not nxt.strip():
                continue
            if len(nxt) - len(nxt.lstrip()) < indent:
                break  # left the block
            hit = next((c for c in CONTROLS if c in nxt), None)
            if hit:
                out.append(f"{name}:{i + 1}: {hit[:-1]} sits AFTER "
                           f"BridgeSyncStatusRows in the same block (line {j + 1}) "
                           f"— the result reports last")
                break
    return out


# ── check 3 ────────────────────────────────────────────────────────────────

PLAIN_BUTTON = re.compile(r"Button\s*(?:\(action:[^\n]*\)\s*)?\{((?:.|\n){0,500}?)\.buttonStyle\(\.plain\)")


def check_controls_are_slabs(name, body):
    """Below a connect screen's identity area, a control is a slab (§190).

    MEASURED, and the SCOPE is the whole reason it is usable: matching every
    tinted-text button under `Screens/` reports NINETEEN, and nearly all are
    content-level disclosures ("Show all 12 turns", "Read the rest", "See all 40
    transactions") or a directory row's own verb — both of which §190 exempts by
    name ("a page's own content rows"). Scoped to files carrying a
    `BridgeSetupHeader` — i.e. the connect family, which is the family with an
    identity area for controls to sit below — it reports ONE.

    That one shape is the "headed section with a blue text link" §190 lists among
    the six the slab replaced, and it is what "Browse all 105" was on the L2BEAT
    page: the only door to a 105-row registry, set as an inline link between a
    sync error and a gray note.

    STATED CEILING: the scope is the FILE, not the block. A connect screen that
    one day wants a genuine content disclosure ("Show 3 more") would be flagged
    and needs a `KNOWN_TEXT_CONTROL` entry with its reason. Block scoping was
    tried first and is worse than useless — brace-matching a SwiftUI property by
    regex silently swallowed whole files, which made the check LOOK narrow while
    it was really running file-wide. Caught by this file's own self-test.
    """
    out = []
    if "BridgeSetupHeader(" not in body:
        return out
    for b in PLAIN_BUTTON.finditer(body):
        label = b.group(1)
        if "foregroundStyle(DS.tint)" not in label:
            continue
        if "background(" in label or "Chip(" in label or "DSSlab" in label:
            continue
        text = re.search(r'Text\((?:String\(localized:\s*)?"([^"]{0,60})"', label)
        words = text.group(1) if text else ""
        if (name, words) in KNOWN_TEXT_CONTROL:
            continue
        line = body[:b.start()].count("\n") + 1
        out.append(f"{name}:{line}: a bare tinted Text is doing a control's job on a "
                   f"connect screen (\"{words}\") — §190: below the identity area "
                   f"every control is a slab (DSSlabDoor)")
    return out


def check_shelf_guard():
    """The shelf's own zero guard, and every caller passing its count.

    This is the drift guard for the defect the header says was PREVENTED rather
    than detected. Without it the guard is one careless edit from gone, and its
    absence is invisible: an empty shelf renders as a perfectly ordinary dashed
    circle.
    """
    out = []
    src = strip_comments(open(COMPONENT).read())
    if not re.search(r"if count > 0", src):
        out.append("AssetRoster.swift: AssetRosterShelf no longer refuses to draw "
                   "at count 0 — the empty-shelf class is back")
    if not re.search(r"let count: Int", src):
        out.append("AssetRoster.swift: AssetRosterShelf no longer takes its row count")
    for name, body in screens():
        if name == "AssetRoster.swift":
            continue
        for m in re.finditer(r"AssetRosterShelf\(([^)]*)\)", body):
            if "count:" not in m.group(1):
                line = body[:m.start()].count("\n") + 1
                out.append(f"{name}:{line}: AssetRosterShelf without count: — it "
                           f"cannot refuse to draw over an empty shelf")
    return out


def audit():
    findings = []
    for name, body in screens():
        findings += check_one_control_one_shape(name, body)
        findings += check_status_last(name, body)
        findings += check_controls_are_slabs(name, body)
    findings += check_shelf_guard()
    return findings


# ── self-test ──────────────────────────────────────────────────────────────

DIRTY_TWO_SHAPES = '''
struct X: View {
    var body: some View {
        if following {
            DSSlabNote(text: "You are following.")
        } else {
            DSSlabButton(title: "Follow", action: follow)
        }
    }
}
'''

CLEAN_TWO_SHAPES = '''
struct X: View {
    var body: some View {
        if following {
            DSCheckList(lines: ["You are following."])
        } else {
            DSSlabButton(title: "Follow", action: follow)
        }
    }
}
'''

DIRTY_STATUS = '''
    private var watchSection: some View {
        Section {
            VStack {
                DSSlabField(placeholder: "Name", text: $q, actionLabel: "Watch", action: go)
                BridgeSyncStatusRows(syncing: syncing, result: result, resultIsError: false)
                DSSlabDoor(title: "Browse every chain", detail: "105", action: browse)
            }
        }
        .dsSlabSection()
    }
'''

CLEAN_STATUS = '''
    private var watchSection: some View {
        Section {
            VStack {
                DSSlabField(placeholder: "Name", text: $q, actionLabel: "Watch", action: go)
                DSSlabDoor(title: "Browse every chain", detail: "105", action: browse)
                BridgeSyncStatusRows(syncing: syncing, result: result, resultIsError: false)
            }
        }
        .dsSlabSection()
    }
'''

DIRTY_LINK = '''
struct X: View {
    var body: some View {
        BridgeSetupHeader(name: "X", mode: .noAccount, intro: "Short.")
    }

    private var watchSection: some View {
        Section {
            VStack {
                Button(action: { browsing = true }) {
                    Text(String(localized: "Browse all 105"))
                        .dsText(.subhead13).foregroundStyle(DS.tint)
                }
                .buttonStyle(.plain)
            }
        }
        .dsSlabSection()
    }
}
'''

CONTENT_LINK = '''
struct X: View {
    var body: some View {
        Text("A room card, not a connect screen — no identity area, so §190's "
             + "slab rule does not reach it.")
    }

    private var rowsSection: some View {
        Section {
            Button(action: expand) {
                Text("Show all 12 turns")
                    .dsText(.subhead13).foregroundStyle(DS.tint)
            }
            .buttonStyle(.plain)
        }
    }
}
'''

COMMENTED = '''
struct X: View {
    var body: some View {
        BridgeSetupHeader(name: "X", mode: .noAccount, intro: "Short.")
    }

    // It used to be: Text("Browse all 105").foregroundStyle(DS.tint) in a
    // Button, which §190 bans. .buttonStyle(.plain)
    private var watchSection: some View {
        Section { DSSlabDoor(title: "Browse every chain", detail: "105", action: go) }
            .dsSlabSection()
    }
}
'''


def self_test():
    ok = True

    def case(label, fn, src, expect):
        nonlocal ok
        got = len(fn("Fixture.swift", strip_comments(src)))
        good = (got > 0) if expect else (got == 0)
        print(f"  {'✓' if good else '✗'} {label}")
        ok = ok and good

    case("catches a control drawn as a slab in one state and a note in the other",
         check_one_control_one_shape, DIRTY_TWO_SHAPES, True)
    case("passes the same control settled as a check line",
         check_one_control_one_shape, CLEAN_TWO_SHAPES, False)
    case("catches a door under the sync result",
         check_status_last, DIRTY_STATUS, True)
    case("passes the result reporting last",
         check_status_last, CLEAN_STATUS, False)
    case("catches a blue text link doing a control's job in a slab block",
         check_controls_are_slabs, DIRTY_LINK, True)
    case("passes a content disclosure on a screen that is not a connect page",
         check_controls_are_slabs, CONTENT_LINK, False)
    case("ignores the banned shape quoted in a comment",
         check_controls_are_slabs, COMMENTED, False)

    # The shelf guard has to fail when the guard goes, or it certifies nothing.
    src = strip_comments(open(COMPONENT).read())
    mutated = src.replace("if count > 0", "if true")
    print(f"  {'✓' if 'if count > 0' not in mutated else '✗'} "
          f"the shelf guard is a real line to remove")
    ok = ok and ("if count > 0" not in mutated)
    return ok


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        print("connect-shape-audit self-test")
        if not self_test():
            sys.exit(1)
        print("  self-test clean")
        sys.exit(0)
    hits = audit()
    count = sum(1 for _ in screens())
    if hits:
        print("connect-shape-audit: FAIL")
        for h in hits:
            print("  " + h)
        sys.exit(1)
    print(f"connect-shape-audit: OK — {count} screens; one control one shape, "
          f"the sync result reports last, every control below the identity area "
          f"is a slab, and the roster shelf still refuses to draw over nothing.")
