#!/usr/bin/env python3
"""Row anatomy audit (prd §1496) — every row in the app, wherever it is drawn,
stands at one pitch.

WHY THIS EXISTS (user, 2026-10-24: "can you sweep the app and make sure we are
using the right font size and line spacing everywhere?"; "i don't want to be
hand rolling any of this. i want to use rules"). `wallet-row-audit.py` held the
Wallet's sixteen row files to §1482's pitch, and nothing held the rest. Swept
on 2026-10-24: 52 rows drawn by hand outside the templates, 33 of them with a
title-to-line gap of 0, 1, 4 or 8 where every template draws 2, and row heads
of 48, 52, 56 and 64 where every Feed and Wallet row's is 44 — Move's choice
lists, Markets' companies and alerts, the four follow and find trays,
Addresses, and every app's account page.

THE RULE. A row is a 17pt title over a 12pt line. Recognised by its anatomy,
not by its file: a `VStack(alignment: .leading, spacing: …)` whose next six
lines draw `.dsText(.body17)` and then `.dsText(.subhead12)` or `.label12`.
  A. Its spacing is 2 — the gap `DSFeedRow`, `DSPushRow` and `WalletRow` draw.
  B. In the 32 lines after it, a `.frame(minHeight:)` names the row's head
     (`DSFeed.headHeight`, `DS.Hit.min`, 44) or `.walletRowPitch()` stands —
     never another number.
  C. The two named pitches outside the templates are the template's: the
     Addresses list's `rowPitch` and `AccountFactRow.height` are 52, the 44pt
     head and 4pt of air either side.

WHAT IT DOES NOT CHECK, said so it stays honest about its reach:
  · A row drawn with no second line (Move's single-line choice rows): they
    were moved to `DSFeed.headHeight` by hand in the same pass; a new one
    is not seen here.
  · Rows built through `DSFeedRow`/`DSPushRow`: the templates hold those
    (`feed-row-skeleton-audit.py`, `wallet-row-audit.py` check E).
  · ALLOWED below: things shaped like a row that are not one, each with its
    reason. A new allowance needs one.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Casberi" / "Casberi"

STACK = re.compile(r"VStack\(alignment: \.leading, spacing: ([^)]+)\)\s*\{")
HEAD = re.compile(r"\.frame\((?:maxWidth: \.infinity, )?minHeight: ([0-9A-Za-z.]+)")
# The two named pitches are good heads only because check C holds their value.
GOOD_HEADS = {"44", "DSFeed.headHeight", "DS.Hit.min", "Self.rowPitch",
              "AddressesSection.rowPitch", "AccountFactRow.height", "Self.height"}

# file stem → why its title-over-line stack is not a list row
ALLOWED = {
    "SourcesLibrary.swift:folder": "a folder's caption under its tile, as an app's name under its icon",
    "DSSlab.swift": "a slab is a control, not a row (§746)",
    "GenRenderer.swift": "generated UI draws the agent's own layout",
    "CasberiIntents.swift": "a Siri snippet, drawn by the system's rules",
}


def allowed(rel: str, lines: list, i: int) -> bool:
    name = Path(rel).name
    if name in ALLOWED:
        return True
    if name == "SourcesLibrary.swift" and "SourcesFolderWords" in "\n".join(lines[max(0, i - 10):i]):
        return True
    # A tray's own body (a sentence, its example, then the tray's control) is
    # a paragraph inside the tray, not a list row: the stack opens directly
    # inside `DSTray(...) {` (Round-ups, MoveSecurity.swift, prd §1578).
    prev = next((l for l in reversed(lines[:i]) if l.strip()), "")
    if "DSTray(" in prev:
        return True
    return False


def strip_comments(text: str) -> str:
    return "\n".join(l if not l.strip().startswith("//") else "" for l in text.split("\n"))


def findings(files):
    out = []
    for rel, text in files:
        lines = strip_comments(text).split("\n")
        for i, line in enumerate(lines):
            m = STACK.search(line)
            if not m:
                continue
            body = "\n".join(lines[i + 1:i + 7])
            a = body.find(".dsText(.body17)")
            b = max(body.find(".dsText(.subhead12)"), body.find(".dsText(.label12)"))
            if a == -1 or b == -1 or b < a or allowed(rel, lines, i):
                continue
            if m.group(1).strip() != "2":
                out.append(f"{rel}:{i + 1}: A a row's title over its line at spacing {m.group(1)} — the gap is 2")
            for l2 in lines[i + 1:i + 33]:
                # The row ends where the next view starts; a minHeight past
                # it is another view's (a foot's button, say).
                if "walletRowPitch()" in l2 or re.match(r"\s*(// MARK|private (var|func)|func |var body)", l2):
                    break
                h = HEAD.search(l2)
                if h:
                    if h.group(1) not in GOOD_HEADS:
                        out.append(f"{rel}:{i + 1}: B a row's head at minHeight {h.group(1)} — it is DSFeed.headHeight")
                    break
    return out


def pitch_findings(addresses: str, account: str):
    out = []
    if "static let rowPitch: CGFloat = DSFeed.headHeight + 2 * FeedScreen.rowAir" not in addresses:
        out.append("AddressesScreen.swift: C the Addresses rowPitch is not the 44pt head and 4pt of air")
    if "static let height: CGFloat = DSFeed.headHeight + 2 * FeedScreen.rowAir" not in account:
        out.append("AccountPage.swift: C AccountFactRow.height is not the 44pt head and 4pt of air")
    return out


SELF_TEST = '''
struct R: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Title")
                    .dsText(.body17)
                Text("Line")
                    .dsText(.subhead12)
            }
        }
        .frame(minHeight: DSFeed.headHeight)
    }
}
'''


def self_test() -> bool:
    ok = True

    def case(name, got, want):
        nonlocal ok
        mark = "ok  " if (len(got) > 0) == want else "FAIL"
        if mark == "FAIL":
            ok = False
        print(f"  {mark} {name} ({len(got)} finding(s))")

    print("row-anatomy-audit self-test")
    case("a row at the 2pt gap and the 44 head is clean", findings([("R.swift", SELF_TEST)]), False)
    case("a 1pt gap is flagged", findings([("R.swift", SELF_TEST.replace("spacing: 2", "spacing: 1"))]), True)
    case("a gap of s1 is flagged", findings([("R.swift", SELF_TEST.replace("spacing: 2", "spacing: DS.Space.s1"))]), True)
    case("a 64pt head is flagged", findings([("R.swift", SELF_TEST.replace("minHeight: DSFeed.headHeight", "minHeight: 64"))]), True)
    case("a slab is allowed", findings([("DSSlab.swift", SELF_TEST.replace("spacing: 2", "spacing: 1"))]), False)
    tray = SELF_TEST.replace("        HStack {", "        DSTray(title: \"T\", height: 420) {").replace("spacing: 2", "spacing: DS.Space.s3")
    case("a tray's own body is allowed", findings([("R.swift", tray)]), False)
    case("a row INSIDE a tray's body is still flagged",
         findings([("R.swift", tray.replace("spacing: DS.Space.s3) {", "spacing: DS.Space.s3) {\n            VStack(alignment: .leading, spacing: 1) {\n                Text(\"A\").dsText(.body17)\n                Text(\"B\").dsText(.subhead12)\n            }", 1))]), True)
    good = ("static let rowPitch: CGFloat = DSFeed.headHeight + 2 * FeedScreen.rowAir",
            "static let height: CGFloat = DSFeed.headHeight + 2 * FeedScreen.rowAir")
    case("the two named pitches on the template's are clean", pitch_findings(*good), False)
    case("Addresses at its old 56 is flagged",
         pitch_findings("static let rowPitch: CGFloat = 56", good[1]), True)
    case("an account fact row at its old 56 is flagged",
         pitch_findings(good[0], "static let height: CGFloat = 56"), True)
    return ok


def main():
    if "--self-test" in sys.argv:
        sys.exit(0 if self_test() else 1)
    if not self_test():
        print("✗ row-anatomy-audit's own self-test failed")
        sys.exit(1)
    files = [(str(p.relative_to(SRC)), p.read_text(encoding="utf-8")) for p in sorted(SRC.rglob("*.swift"))]
    hits = findings(files) + pitch_findings(
        (SRC / "Screens" / "AddressesScreen.swift").read_text(encoding="utf-8"),
        (SRC / "Screens" / "AccountPage.swift").read_text(encoding="utf-8"))
    if hits:
        for h in hits:
            print(f"✗ {h}")
        print(f"row-anatomy-audit: {len(hits)} row(s) off the one pitch (prd §1496)")
        sys.exit(1)
    print("✓ row-anatomy audit: every row in the app at the 2pt gap and the 44pt head (prd §1496)")


if __name__ == "__main__":
    main()
