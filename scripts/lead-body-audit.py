#!/usr/bin/env python3
"""Lead-body audit (prd §772, 2026-09-15).

WHY THIS EXISTS. §766 ruled that a room's lead is one well with three zones and
that "nothing in it is air it could honestly fill". The zone in the middle then
shipped with exactly ONE filler — `thing.summary` — which an article has and
almost nothing else does, so the ruling reached RSS and left every other kind
drawing a sentence over 176pt of black. It took a screenshot of an X notice
naming eight people, with one face drawn, for anybody to see it.

That is the shape of defect a script catches and a screen sweep does not: the
lead renders perfectly, every audit is green, and what is wrong is what ISN'T
there. §772's answer is a LADDER — cast, quote, lede, parts, tags — and a ladder
is only worth anything if every face reaches it and every rung keeps drawing.

FIVE CHECKS, static, no build.

  A. **Every `FeedLedeFace.Kind` arm reaches the body.** The four faces are
     spelled in one `switch` in `FeedLedeCard.cover`, and the body block is
     drawn OUTSIDE it, once, for all of them — because a picture cover with a
     cast still has a cast. A body drawn inside an arm is how three of the four
     faces silently lose the ladder, which is exactly how the summary came to be
     the only filler in the first place.

  B. **The fit candidates are literal, never a loop.** `ViewThatFits` measures
     its SUBVIEWS, and a `ForEach` is one subview however many rows it makes —
     so `ViewThatFits { ForEach(fits) { ... } }` compiles, renders, and silently
     always picks the first candidate. There is no way to see that in a
     screenshot: the lead looks right for every thing short enough not to need
     the fit.

  C. **The cast is a shelf, not a pile.** `FacePile` is the overlapping 20pt
     proof-line detail; the lead's cast is the body's whole payload and
     overlapping hides all but the first face. The two are one grep apart and a
     reviewer reading `DSLeadCast` cannot tell which was meant.

  D. **The lead's quote draws no well.** `SocialQuoteCard` is `dsWell`, correct
     in a row (rows stand on nothing, §749) and wrong in a lead, which since
     §766 IS a well — a well inside a well is the plate-on-a-plate §759 spent a
     pass deleting. So `DSLeadQuote` may not call `dsWell`, and `FeedLedeCard`
     may not reach for `SocialQuoteCard`.

  E. **Every rung of the ladder is drawn.** A `BodyRung` case with no arm in
     `rungView` is a rung the model offers and the view silently swallows —
     which, because `rungCap` only draws the richest two, would show up as "the
     lead just doesn't fill for this kind" and nothing louder.

WHAT THIS DELIBERATELY DOES NOT CHECK, so it stays honest about its reach.

  · **Whether the rungs are the RIGHT ones, or in the right order.** That is
    §772's ruling and a person's judgement; a script can only hold the wiring.
  · **Whether anything FITS.** Whether twelve candidates are enough at AX5 type
    on an SE is a layout question, and layout needs a device. This file cannot
    see a clipped shelf and does not pretend to.
  · **Whether the box is filled.** Every cover holds `leadHeight` since prd
    §904; whether the ladder fills it or leaves air is a device question.
  · **Other leads.** A room `Head` fills its box through `LeadFit` and its own
    rows, which `room-chassis-audit.py` already governs. This is the COVER's
    ladder only.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CARD = Path("Casberi/Casberi/Screens/FeedLedeCard.swift")
BODY = Path("Casberi/Casberi/Design/DSLeadBody.swift")
FACE = Path("Casberi/Casberi/Model/FeedLedeFace.swift")


def strip_comments(text: str) -> str:
    """Comments out, string literals kept.

    This repo documents its rules by NAMING the symbols they govern — the
    header above says `FacePile` and `dsWell` and `ForEach` out loud — so a
    check reading raw source fires on the prose explaining it. The lesson
    `ondevice-selftest.sh` and `category-fold-selftest.sh` each record paying
    for, and this file would have paid for it on its first run. Line breaks are
    preserved so a reported line number is the real one.
    """
    out, line = [], []
    in_block = in_string = False
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if in_block:
            if ch == "*" and nxt == "/":
                in_block = False
                i += 2
                continue
            if ch == "\n":
                out.append("".join(line))
                line = []
            i += 1
            continue
        if in_string:
            if ch == "\\":
                line.append("  ")
                i += 2
                continue
            if ch == '"':
                in_string = False
            line.append(ch)
            i += 1
            continue
        if ch == '"':
            in_string = True
            line.append(ch)
            i += 1
            continue
        if ch == "/" and nxt == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if ch == "/" and nxt == "*":
            in_block = True
            i += 2
            continue
        if ch == "\n":
            out.append("".join(line))
            line = []
            i += 1
            continue
        line.append(ch)
        i += 1
    out.append("".join(line))
    return "\n".join(out)


def block(text: str, header: re.Pattern) -> str:
    """The braced body of the first declaration matching `header`.

    Brace-counted rather than indentation-counted: this codebase nests view
    builders deep enough that an indentation heuristic reads the wrong closing
    line, and a check that measures the wrong region reports confidently and
    wrongly — the thing `prd-index-audit`'s own header calls worse than no
    check.
    """
    m = header.search(text)
    if not m:
        return ""
    i = text.find("{", m.end() - 1)
    if i < 0:
        return ""
    depth, j = 0, i
    while j < len(text):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[i : j + 1]
        j += 1
    return text[i:]


def audit(root: Path):
    findings = []
    card_path, body_path, face_path = root / CARD, root / BODY, root / FACE
    for p in (card_path, body_path, face_path):
        if not p.exists():
            findings.append((str(p.relative_to(root)), "the file §772 names is gone"))
            return findings
    card = strip_comments(card_path.read_text())
    body = strip_comments(body_path.read_text())
    face = strip_comments(face_path.read_text())

    # --- A. every face arm reaches the body -----------------------------------
    cover = block(card, re.compile(r"func\s+cover\s*\("))
    if not cover:
        findings.append((str(CARD), "`cover(...)` is gone — §772's ladder is drawn from it"))
    else:
        kinds = set(re.findall(r"case\s+(\w+)", block(face, re.compile(r"enum\s+Kind"))))
        drawn = set(re.findall(r"case\s+\.(\w+)\s*:", cover))
        missing = kinds - drawn
        if kinds and missing:
            findings.append(
                (str(CARD), "the cover draws no arm for " + ", ".join(sorted(missing))))
        if "bodyBlock(" not in cover:
            findings.append(
                (str(CARD), "`cover` never calls `bodyBlock` — no face reaches the ladder"))
        else:
            # Drawn ONCE, outside the switch: a call inside an arm gives the
            # ladder to that face alone, which is the defect §772 exists to end.
            switch = block(cover, re.compile(r"switch\s+face"))
            if "bodyBlock(" in switch:
                findings.append(
                    (str(CARD), "`bodyBlock` is called inside the face switch — "
                                "the other faces lose the ladder"))
            if cover.count("bodyBlock(") != 1:
                findings.append(
                    (str(CARD), "`bodyBlock` is called more than once in `cover`"))

    # --- B. the fit candidates are literal ------------------------------------
    fits = block(card, re.compile(r"ViewThatFits\s*\("))
    if not fits:
        findings.append((str(CARD), "the cover no longer fits its box — `ViewThatFits` is gone"))
    else:
        if "ForEach" in fits:
            findings.append(
                (str(CARD), "`ViewThatFits` holds a `ForEach` — that is ONE subview, "
                            "so the fit silently always picks the first candidate"))
        if fits.count("cover(") < 2:
            findings.append(
                (str(CARD), "`ViewThatFits` offers fewer than two candidates — nothing gives way"))

    # --- C. the cast is a shelf, not a pile -----------------------------------
    cast = block(body, re.compile(r"struct\s+DSLeadCast"))
    if not cast:
        findings.append((str(BODY), "`DSLeadCast` is gone — §772's cast has nowhere to draw"))
    else:
        if "FacePile" in cast:
            findings.append(
                (str(BODY), "the lead's cast draws `FacePile` — an overlapping pile hides "
                            "every face but the first, and here the faces ARE the body"))
        if "DS.Face." not in cast:
            findings.append(
                (str(BODY), "`DSLeadCast`'s size is not a `DS.Face` rung (face-ramp-audit's rule)"))

    # --- D. no well inside the well -------------------------------------------
    quote = block(body, re.compile(r"struct\s+DSLeadQuote"))
    if not quote:
        findings.append((str(BODY), "`DSLeadQuote` is gone — the cover would draw no post"))
    elif "dsWell" in quote:
        findings.append(
            (str(BODY), "`DSLeadQuote` draws `dsWell` inside the lead, which IS a well (§766) — "
                        "a plate on a plate (§759)"))
    if "SocialQuoteCard" in card:
        findings.append(
            (str(CARD), "the cover reaches for `SocialQuoteCard`, which is `dsWell` — "
                        "use `DSLeadQuote`"))

    # --- E. every rung is drawn ------------------------------------------------
    rungs = set(re.findall(r"case\s+(\w+)", block(card, re.compile(r"enum\s+BodyRung"))))
    rungs -= {"self"}
    view = block(card, re.compile(r"func\s+rungView\s*\("))
    if rungs and not view:
        findings.append((str(CARD), "`rungView` is gone — no rung of the ladder draws"))
    elif rungs:
        undrawn = {r for r in rungs if not re.search(r"case\s+\.%s\b" % re.escape(r), view)}
        if undrawn:
            findings.append(
                (str(CARD), "the ladder offers rungs nothing draws: " + ", ".join(sorted(undrawn))))
    return findings


def self_test() -> int:
    """Each check, broken on purpose, against a copy of the real tree.

    A check that cannot demonstrate it catches anything certifies nothing —
    `verify.sh`'s own rule, and the reason every script here carries one.
    """
    import shutil
    import tempfile

    failures = []
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        for rel in (CARD, BODY, FACE):
            (root / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(ROOT / rel, root / rel)

        if audit(root):
            failures.append("the real tree does not pass its own audit")

        def mutate(rel: Path, old: str, new: str, want: str, label: str):
            p = root / rel
            keep = p.read_text()
            if old not in keep:
                failures.append(f"{label}: the text to mutate is not in the tree")
                p.write_text(keep)
                return
            p.write_text(keep.replace(old, new, 1))
            hits = audit(root)
            if not any(want in msg for _, msg in hits):
                failures.append(f"{label}: not caught")
            p.write_text(keep)

        mutate(CARD, "bodyBlock(face.takesLadder ? rungs : [], fit: fit)", "EmptyView()",
               "never calls `bodyBlock`", "a cover with no ladder")
        mutate(CARD, "cover(face, receipt: receipt, rungs: rungs, fit: Self.fits[1])",
               "ForEach(Self.fits, id: \\.self) { f in EmptyView() }",
               "ONE subview", "a `ForEach` inside `ViewThatFits`")
        mutate(BODY, "RemoteThumb(urlString: url, size: size, fallback: source, circular: true)",
               "FacePile(urls: [url], fallback: source)",
               "overlapping pile", "the cast drawn as a pile")
        mutate(BODY, ".frame(maxWidth: .infinity, alignment: .leading)\n    }\n\n    /// Whether a card",
               ".dsWell()\n    }\n\n    /// Whether a card",
               "plate on a plate", "a well inside the lead's well")
        mutate(CARD, "case .tags(let tags):", "case .unusedTagsArm(let tags):",
               "rungs nothing draws", "a rung the view swallows")

    if failures:
        for f in failures:
            print(f"self-test FAILED: {f}", file=sys.stderr)
        return 1
    print("lead-body audit self-test: ok (5 mutations)")
    return 0


def main() -> int:
    if "--self-test" in sys.argv[1:]:
        return self_test()
    findings = audit(ROOT)
    if not findings:
        print("lead-body audit: ok — every face reaches the ladder, "
              "the fit is literal, the cast is a shelf, the lead holds one well")
        return 0
    print("A lead's body would draw air (prd §772):\n")
    for rel, msg in findings:
        print(f"  {rel}: {msg}")
    print("\nThe ladder is the rule: a lead draws what the thing can honestly say, "
          "or it stops claiming the height.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
