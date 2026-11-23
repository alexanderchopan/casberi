#!/usr/bin/env python3
"""Row-pitch audit (prd §1957, 2026-11-23).

WHY THIS EXISTS. The user, after Holdings and Home moved to a 40pt row:
"we need to put contacts and other places we have rows be in the same 40point
... tbh we should sweep the entire app to make sure we aren't handrolling".
The sweep found 140 `.frame(minHeight:)` sites in Screens and Shell, most of
them naming the 44pt tap minimum or a bare number, so a row's height was
decided one file at a time and no change to the one constant reached them.
One Holdings row even drew 48pt beside its neighbours' 40, from its own
padding plus its List row's (caught by eye, not by a check).

THE RULE. A list row's height is `DSFeed.headHeight` (32pt; the List row's
4pt air makes the 40pt pitch), through a template (`DSPushRow`, `DSFeedRow`,
`DSMoreRow`, `DSDoorRow`, `DSSpec`) or by naming the constant. A bare number
or `DS.Hit.min` as a `minHeight` is a control's (a button, a field, a key),
never a row's.

WHAT IT CHECKS, static, no build: every `minHeight:` in Screens/ and Shell/
whose value is a number literal or `DS.Hit.min`, on a line that sizes no
width (a `minWidth` makes it a tap target). The sites left after the sweep
are controls, counted per file in ALLOWED below: a RATCHET. A file with more
than its count fails (a new hand-set height: name `DSFeed.headHeight`, or if
it truly is a control, raise the count here with the reason in the commit).
A file with fewer passes and says the count can come down.

    python3 scripts/row-pitch-audit.py
    python3 scripts/row-pitch-audit.py --self-test
"""
import os
import re
import sys
import tempfile

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DIRS = ["Casberi/Casberi/Screens", "Casberi/Casberi/Shell"]
SITE = re.compile(r"minHeight:\s*([1-9]\d*(?:\.\d+)?|DS\.Hit\.min)\b")

# Controls, not rows, left after the sweep (prd §1957). Filled from the tree.
ALLOWED = {
    "Casberi/Casberi/Screens/AccountDetailSheet.swift": 1,
    "Casberi/Casberi/Screens/AddressBookViews.swift": 2,
    "Casberi/Casberi/Screens/AddressesScreen.swift": 1,
    "Casberi/Casberi/Screens/AztecBrowser.swift": 3,
    "Casberi/Casberi/Screens/CategoryOrderSheet.swift": 1,
    "Casberi/Casberi/Screens/ChatFace.swift": 1,
    "Casberi/Casberi/Screens/CheckSheets.swift": 1,
    "Casberi/Casberi/Screens/FeedScreen+DaySections.swift": 1,
    "Casberi/Casberi/Screens/FeedScreen+HomeHead.swift": 2,
    "Casberi/Casberi/Screens/FeedScreen+WalletAztec.swift": 1,
    "Casberi/Casberi/Screens/LogosChatTray.swift": 1,
    "Casberi/Casberi/Screens/MoveAztecPrivate.swift": 3,
    "Casberi/Casberi/Screens/MoveBack.swift": 2,
    "Casberi/Casberi/Screens/MoveDeck.swift": 3,
    "Casberi/Casberi/Screens/MoveExportKey.swift": 4,
    "Casberi/Casberi/Screens/MoveLend.swift": 1,
    "Casberi/Casberi/Screens/MovePrivate.swift": 3,
    "Casberi/Casberi/Screens/MoveRailgunPrivate.swift": 1,
    "Casberi/Casberi/Screens/MoveScreen.swift": 2,
    "Casberi/Casberi/Screens/MoveSecurity.swift": 3,
    "Casberi/Casberi/Screens/MoveSentence.swift": 21,
    "Casberi/Casberi/Screens/NoteSheetViews.swift": 1,
    "Casberi/Casberi/Screens/OwnNodePage.swift": 3,
    "Casberi/Casberi/Screens/OwnNodeTray.swift": 3,
    "Casberi/Casberi/Screens/PrivateCostLine.swift": 1,
    "Casberi/Casberi/Screens/PurchaseStageView.swift": 1,
    "Casberi/Casberi/Screens/ReceivePlace.swift": 3,
    "Casberi/Casberi/Screens/SafeAskSheet.swift": 1,
    "Casberi/Casberi/Screens/SafeScreen.swift": 5,
    "Casberi/Casberi/Screens/SafeSignDetails.swift": 1,
    "Casberi/Casberi/Screens/SavingsGoalTray.swift": 4,
    "Casberi/Casberi/Screens/ShapedRows.swift": 2,
    "Casberi/Casberi/Screens/SocialPostViews.swift": 1,
    "Casberi/Casberi/Screens/SubscriptionSheets.swift": 1,
    "Casberi/Casberi/Screens/WalletApprovalExposureCard.swift": 1,
    "Casberi/Casberi/Shell/Composer.swift": 2,
    "Casberi/Casberi/Shell/LibrarySearch.swift": 1,
    "Casberi/Casberi/Shell/ToastWindow.swift": 1,
}


def count_sites(root):
    found = {}
    for d in DIRS:
        base = os.path.join(root, d)
        if not os.path.isdir(base):
            continue
        for dirpath, _, files in os.walk(base):
            for name in files:
                if not name.endswith(".swift"):
                    continue
                path = os.path.join(dirpath, name)
                rel = os.path.relpath(path, root)
                with open(path, encoding="utf-8") as f:
                    for line in f:
                        code = line.split("//", 1)[0]
                        if "minWidth" in code or not SITE.search(code):
                            continue
                        found[rel] = found.get(rel, 0) + 1
    return found


def audit(root, allowed):
    found = count_sites(root)
    failures, slack = [], []
    for rel, n in sorted(found.items()):
        cap = allowed.get(rel, 0)
        if n > cap:
            failures.append(f"{rel}: {n} hand-set minHeight (allowed {cap}) — a row names DSFeed.headHeight")
    for rel, cap in sorted(allowed.items()):
        n = found.get(rel, 0)
        if n < cap:
            slack.append(f"{rel}: {n} of {cap} — lower its count")
    return failures, slack


def self_test():
    with tempfile.TemporaryDirectory() as tmp:
        d = os.path.join(tmp, DIRS[0])
        os.makedirs(d)
        f = os.path.join(d, "Rows.swift")
        def write(body):
            with open(f, "w") as h:
                h.write(body)
        rel = os.path.relpath(f, tmp)
        # A row sized by the constant passes with no allowance.
        write("x.frame(minHeight: DSFeed.headHeight)\n")
        assert audit(tmp, {}) == ([], []), "the constant was flagged"
        # A bare number fails.
        write("x.frame(minHeight: 44)\n")
        assert audit(tmp, {})[0], "a literal row height passed"
        # The tap minimum fails.
        write("x.frame(minHeight: DS.Hit.min, alignment: .leading)\n")
        assert audit(tmp, {})[0], "DS.Hit.min as a row height passed"
        # A tap target (width too) passes.
        write("x.frame(minWidth: 44, minHeight: 44)\n")
        assert audit(tmp, {}) == ([], []), "a tap target was flagged"
        # Zero is no height at all (a chart filling its slot).
        write("x.frame(minHeight: 0, maxHeight: .infinity)\n")
        assert audit(tmp, {}) == ([], []), "minHeight 0 was flagged"
        # A comment is not code.
        write("x // .frame(minHeight: 44)\n")
        assert audit(tmp, {}) == ([], []), "a comment was flagged"
        # Within the ratchet passes; over it fails; under it reports slack.
        write("a.frame(minHeight: 48)\nb.frame(minHeight: 48)\n")
        assert audit(tmp, {rel: 2}) == ([], []), "an allowed count failed"
        assert audit(tmp, {rel: 1})[0], "a count over the ratchet passed"
        assert audit(tmp, {rel: 3})[1], "slack under the ratchet went unreported"
    print("✓ row-pitch audit self-test: 9 cases")


def main():
    if "--self-test" in sys.argv:
        self_test()
        return
    if "--counts" in sys.argv:
        for rel, n in sorted(count_sites(ROOT).items()):
            print(f'    "{rel}": {n},')
        return
    failures, slack = audit(ROOT, ALLOWED)
    for s in slack:
        print(f"  note {s}")
    if failures:
        for f in failures:
            print(f"✗ {f}")
        sys.exit(1)
    print(f"✓ row-pitch audit: {sum(ALLOWED.values())} control sites allowed, no hand-set row heights")


if __name__ == "__main__":
    main()
