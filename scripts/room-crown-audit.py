#!/usr/bin/env python3
"""The three room crowns are one size (prd §552c).

WHY THIS EXISTS.

Wallet, vibenet and Hegotá are the same machine — `DSRoomChassis` says so in
its own header — and each opens on a balance. Reported 2026-09-01: *"wallet,
hegota, and vibenet have different size numbers on their home crown slot. which
size works best for us? pick one and make it consistent."*

Measured, they were TWO RUNGS apart in one room. Wallet and vibenet draw their
Home crown at `price48` inside their own figure; Hegotá passed its balance to
the chassis as a HEADLINE, and `DSRoomSlot` sets a headline in `stat24`. **Money
at 24pt where the same object one room over is 64.**

§532's ramp settles which one wins without anybody needing a taste: 64 is the
crown rung, defined there as "money, one per surface (§506)". `stat24` is what
Hegotá's OTHER scopes put "12 steps" and "3 transactions" in — labels — and the
balance had been quietly filed with them.

**It is a script because a wrong rung renders perfectly.** Nothing clips,
nothing warns, every other audit is green, and the screen sweep photographs a
24pt crown and certifies it. It took a person opening three rooms in a row and
comparing them by eye — which is exactly the comparison nobody makes twice.

TWO CHECKS, both derived from what actually went wrong.

  1. EVERY ROOM DRAWS A CROWN AT THE CROWN RUNG. Each of the three files must
     set `dsText(.price48)` at least once. Hegotá had ZERO — its balance never
     touched the rung at all — so this is the exact shape that shipped.
  3. NO CROWN MAY SHRINK BELOW ITS RUNG. A `minimumScaleFactor` within four
     lines of a `price48` must be at least 0.9. Scoped to the crown's own call
     site rather than the file, because a smaller figure elsewhere is entitled
     to a permissive floor.
  2. EVERY ROOM DECIDES WHO OWNS THE HEADLINE ROW. Each file must name
     `reservesHeadline`. `DSRoomSlot`'s own doc carries the rule — "reserve the
     row only where the CHASSIS draws the headline" — and a room that never
     names it has not made the decision: it takes the default (`true`), which
     hands its crown to the chassis and therefore to `stat24`. That default is
     right for a scope whose headline is a label and wrong for every Home.

WHAT IT DELIBERATELY DOES NOT DO (a lint that cries wolf gets turned off within
a week):

  • It does not try to identify "the Home crown" and check its tier directly.
    Doing that means resolving which `Text` in an 8,000-line SwiftUI file is
    the crown, which is parsing Swift; the two facts above are greppable, and
    together they are what the regression was made of.
  • It says nothing about the OTHER scopes' headlines. `stat24` is correct
    there — those are labels, and the whole point of the ramp is that a label
    and a crown are different rungs.
  • It does not check the figure's height sum. `DSRoomSlot` is a hard 210pt
    with `.clipped()`, and each room writes its own sum down in its own source
    (`crownFigure`, `frameRows`, `balanceHero`); a static check cannot measure
    a rendered face.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# The three rooms that share `DSRoomChassis`, and where each one's Home crown
# is drawn. Wallet's lives in the feed screen with the rest of its room.
# Wallet's crown is drawn in `WalletFeedTiles`, not in the feed screen that
# composes the room — pointing this at `FeedScreen.swift` reported a false
# finding on the audit's first run, which is the check's own lesson: the file
# that COMPOSES a room is not the file that DRAWS its crown.
# **TWO FILES PER ROOM, and the split is the audit's own first lesson.** The
# file that COMPOSES a room is not always the file that DRAWS its crown: Wallet
# composes in `FeedScreen` and draws in `WalletFeedTiles`, while both devnets do
# each in one place. Pointing every check at one file reported a false finding
# on the first run — the crown rung looked absent from Wallet because it lives
# next door. `draws` carries checks 1 and 3, `composes` carries check 2.
ROOMS = {
    "Wallet": ("Casberi/Casberi/Screens/WalletFeedTiles.swift",
               "Casberi/Casberi/Screens/FeedScreen.swift"),
    "vibenet": ("Casberi/Casberi/Screens/VibenetRoomCard.swift",
                "Casberi/Casberi/Screens/VibenetRoomCard.swift"),
    "Hegotá": ("Casberi/Casberi/Screens/HegotaRoomCard.swift",
               "Casberi/Casberi/Screens/HegotaRoomCard.swift"),
}

# A rung that silently shrinks is not that rung — §491's lesson, and check 3.
MIN_SCALE_FLOOR = 0.9
SCALE = re.compile(r"minimumScaleFactor\(([0-9.]+)\)")

CHASSIS = "Casberi/Casberi/Design/DSRoomChassis.swift"
CROWN_RUNG = "dsText(.price48)"


def strip_comments(text: str) -> str:
    """Each of these files documents this rule by naming the rungs it governs."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return "\n".join(re.sub(r"//.*$", "", line) for line in text.splitlines())


def audit(rooms: dict[str, tuple[str, str]], chassis: str) -> list[str]:
    out: list[str] = []
    for name, (drawn, composed) in rooms.items():
        code = strip_comments(drawn)
        if CROWN_RUNG not in code:
            out.append(f"{name}: no `{CROWN_RUNG}` anywhere — its crown is not "
                       f"on the crown rung, so it is a different size from the "
                       f"other rooms' (§552c)")
        for m in re.finditer(re.escape(CROWN_RUNG), code):
            window = code[m.end():].split("\n")[:5]
            for line in window:
                found = SCALE.search(line)
                if found and float(found.group(1)) < MIN_SCALE_FLOOR:
                    out.append(f"{name}: its crown declares the crown rung and "
                               f"then allows {found.group(1)} — it can render "
                               f"below the rung it names (§552c)")
                    break
        if "reservesHeadline" not in strip_comments(composed):
            out.append(f"{name}: never names `reservesHeadline`, so it takes "
                       f"the default and hands its crown to the chassis, which "
                       f"sets a headline in `stat24` — a label rung (§552c)")
    # The premise: the chassis's headline really is the label rung. If that ever
    # changes, this audit's whole reasoning needs re-reading rather than
    # silently passing.
    if "dsText(.stat24)" not in strip_comments(chassis):
        out.append("DSRoomChassis no longer sets its headline in `stat24` — "
                   "this audit's premise moved; re-read §552c before trusting "
                   "either check above")
    return out


DRAWS = "Text(t).dsText(.price48)\n  .lineLimit(1).minimumScaleFactor(0.9)"
CLEAN = {
    "Wallet": (DRAWS, "DSRoomSlot(headline: nil, reservesHeadline: false) { hero }"),
    "vibenet": ((DRAWS + "\nDSRoomSlot(headline: nil, reservesHeadline: false) { h }",) * 2),
    "Hegotá": ((DRAWS + "\nDSRoomSlot(headline: h, reservesHeadline: !ownsIt) { f }",) * 2),
}
CLEAN_CHASSIS = "Text(headline).dsText(.stat24).monospacedDigit()"


def self_test() -> int:
    def without(room: str, old: str, new: str = "") -> dict[str, tuple[str, str]]:
        d = dict(CLEAN)
        d[room] = tuple(part.replace(old, new) for part in d[room])
        return d

    cases = [
        ("the shipping shape", CLEAN, CLEAN_CHASSIS, False),
        ("a room whose crown never reaches the crown rung — the shape that shipped",
         without("Hegotá", "Text(t).dsText(.price48)"), CLEAN_CHASSIS, True),
        ("a room that takes the default and hands its crown to the chassis",
         without("Hegotá", "reservesHeadline: !ownsIt", "x: 1"), CLEAN_CHASSIS, True),
        ("Wallet is checked too, not just the devnets",
         without("Wallet", "Text(t).dsText(.price48)"), CLEAN_CHASSIS, True),
        ("a crown allowed to shrink below the rung it declares",
         without("Wallet", "minimumScaleFactor(0.9)", "minimumScaleFactor(0.6)"),
         CLEAN_CHASSIS, True),
        ("a comment naming the wrong rung does not fire",
         {**CLEAN, "Hegotá": tuple("// never .dsText(.stat24) for the crown\n" + p
                                  for p in CLEAN["Hegotá"])},
         CLEAN_CHASSIS, False),
        ("the chassis's headline tier moving invalidates the premise",
         CLEAN, "Text(headline).dsText(.price40)", True),
    ]
    ok = True
    for name, rooms, chassis, should_flag in cases:
        hits = audit(rooms, chassis)
        if bool(hits) == should_flag:
            print(f"  ✓ {name}")
        else:
            print(f"  ✗ {name} — expected {'a finding' if should_flag else 'clean'}, "
                  f"got {hits or '(nothing)'}")
            ok = False
    return 0 if ok else 1


def main() -> int:
    if "--self-test" in sys.argv:
        print("room-crown audit: self-test")
        return self_test()
    if self_test() != 0:
        print("room-crown audit: SELF-TEST FAILED — not certifying the tree")
        return 1

    rooms = {}
    for name, rels in ROOMS.items():
        texts = []
        for rel in rels:
            path = ROOT / rel
            if not path.exists():
                print(f"room-crown audit: FAILED — {rel} is gone")
                return 1
            texts.append(path.read_text(encoding="utf-8"))
        rooms[name] = (texts[0], texts[1])
    chassis_path = ROOT / CHASSIS
    if not chassis_path.exists():
        print(f"room-crown audit: FAILED — {CHASSIS} is gone")
        return 1

    findings = audit(rooms, chassis_path.read_text(encoding="utf-8"))
    if findings:
        print("room-crown audit: FAILED")
        for f in findings:
            print(f"  {f}")
        return 1
    print(f"✓ room-crown audit: {len(rooms)} rooms, one crown rung (price48)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
