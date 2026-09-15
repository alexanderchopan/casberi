#!/usr/bin/env python3
"""Room-chassis audit (prd §745, 2026-09-15).

WHY THIS EXISTS. User: "move the other 22 onto the shared template, so every
room's top looks like it came from the same hand". Four source rooms composed
`DSRoomChassis`; twenty-two drew their head cards by hand the day their source
landed, and read side by side they were one anatomy spelled twenty-two ways —
four gap rungs, two footnote rungs, a tap target in half of them. §745 moved
every one onto `DSRoomChassis` (the slot rooms keep `DSRoomSlot`, the others
compose `DSRoomChassis.Head`). §495 is the reason this has to be mechanical:
shared COMPONENTS never held a shared TEMPLATE, and the next room added from
memory is the twenty-third hand-drawn head.

TWO CHECKS, both on the comment- and string-stripped body of every
`struct <Name>RoomCard` in `Casberi/Casberi/Screens/*RoomCard.swift`:

  A. The card's own `var body` names `DSRoomChassis` or `DSRoomSlot` (the
     chassis's slot component, defined beside it). The BODY, not the file: a
     card that keeps a chassis constant in a helper and hand-draws its body
     would pass a file-wide grep, and a doc comment naming the template would
     pass a raw one.
  B. The card's body does not apply `.dsWidgetSurface()` itself. The head's
     layout is the template's (`dsRoomHeadBlock()`), and since prd §758 that
     template paints NO plate — so a body that paints one is not merely a
     second surface, it is the elevated card coming back to the one kind of
     block the user has now asked three times to see without one (§749, §757,
     §758).

WHAT IT CANNOT SEE: whether the card composes the template WELL — a body that
wraps a hand-drawn VStack in one `DSRoomChassis.Block` passes. It reads shapes,
not layouts, and a check that guessed at layout would be argued with and then
disabled (the liveness audit's stated lesson).

EXEMPT is the escape hatch: a card name mapped to the reason it may not
compose the chassis. It is empty, and an entry is a ruling, not a snooze.

`--self-test` plants a good card, a card that names the template only in a
comment, a card whose HELPER uses the chassis while its body does not, a card
that paints its own surface, and an exempt card, and proves each verdict.
"""
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCREENS = "Casberi/Casberi/Screens"

TEMPLATE = re.compile(r"\bDSRoom(?:Chassis|Slot)\b")
SURFACE = re.compile(r"\.dsWidgetSurface\(")

# card struct name → the ruling that lets it stand outside the chassis.
EXEMPT: dict[str, str] = {}


def strip(text: str) -> str:
    """Comments out and string contents blanked, line breaks preserved, so a
    brace or a type name inside either can move neither the depth nor a
    verdict."""
    out, i, n = [], 0, len(text)
    in_block = in_string = False
    while i < n:
        ch, nxt = text[i], text[i + 1] if i + 1 < n else ""
        if in_block:
            if ch == "*" and nxt == "/":
                in_block = False
                i += 2
                continue
            out.append("\n" if ch == "\n" else " ")
            i += 1
            continue
        if in_string:
            if ch == "\\":
                out.append("  ")
                i += 2
                continue
            if ch == '"' or ch == "\n":
                in_string = False
                out.append(ch)
            else:
                out.append(" ")
            i += 1
            continue
        if ch == '"':
            in_string = True
            out.append(ch)
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
        out.append(ch)
        i += 1
    return "".join(out)


def block(src: str, open_at: int) -> str:
    """The text from the `{` at `open_at` to its matching `}`."""
    depth = 0
    for j in range(open_at, len(src)):
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0:
                return src[open_at:j + 1]
    return src[open_at:]


VIEW_MEMBER = re.compile(
    r"(?:var\s+(\w+)\s*:\s*some\s+View|func\s+(\w+)\s*(?:<[^>]*>)?\([^)]*\)\s*->\s*some\s+View)")


def members(struct: str):
    """(name, block) for every `var`/`func` declared at the struct's OWN depth
    that returns `some View`, plus the body itself under the name `body`."""
    depth, k, n = 0, 0, len(struct)
    while k < n:
        ch = struct[k]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        elif depth == 1 and ch in "vf":
            m = VIEW_MEMBER.match(struct, k)
            if m and (k == 0 or not (struct[k - 1].isalnum() or struct[k - 1] == "_")):
                brace = struct.find("{", m.end())
                if brace != -1:
                    body = block(struct, brace)
                    yield (m.group(1) or m.group(2)), body
                    k = brace + len(body)
                    continue
        k += 1


def card_bodies(src: str, stem: str):
    """(head name, what its body composes, or None) for the file's room head.

    The head is every top-level `struct …RoomCard`; a file that declares none is
    a chassis room whose head is `<Stem>RoomFigure` (Frames, Hegotá). "What the
    body composes" is the body plus the struct's own `some View` members the
    body names — ONE hop, so `body → stackedRoom → DSRoomChassis` (vibenet)
    counts and a `CGFloat` helper holding a chassis constant does not. A nested
    helper view's body (Railgun's `DirectionPair`) is never read as the card's:
    only members at the head struct's own depth are considered."""
    heads = list(re.finditer(r"\bstruct\s+(\w+RoomCard)\b[^{]*\{", src))
    if not heads:
        heads = list(re.finditer(r"\bstruct\s+(" + re.escape(stem) + r"RoomFigure)\b[^{]*\{", src))
    for m in heads:
        struct = block(src, m.end() - 1)
        views = dict(members(struct))
        body = views.get("body")
        if body is None:
            yield m.group(1), None, None
            continue
        reached = [body] + [text for name, text in views.items()
                            if name != "body" and re.search(r"\b" + re.escape(name) + r"\b", body)]
        yield m.group(1), body, "\n".join(reached)


def scan(root: Path):
    findings, cards = [], 0
    for path in sorted((root / SCREENS).glob("*RoomCard.swift")):
        rel = f"{SCREENS}/{path.name}"
        stem = path.name[: -len("RoomCard.swift")]
        src = strip(path.read_text(encoding="utf-8"))
        named = False
        for name, body, reached in card_bodies(src, stem):
            named = True
            cards += 1
            if name in EXEMPT:
                continue
            if body is None:
                findings.append(("A", rel, f"{name} has no `var body` this audit can find"))
                continue
            if not TEMPLATE.search(reached):
                findings.append(("A", rel, f"{name}'s body does not compose DSRoomChassis — "
                                           "a hand-drawn room head (prd §745)"))
            if SURFACE.search(body):
                findings.append(("B", rel, f"{name}'s body paints its own .dsWidgetSurface() — "
                                           "a room head draws no plate (prd §745/§758)"))
        if not named:
            findings.append(("A", rel, f"no `struct …RoomCard` or `{stem}RoomFigure` in a *RoomCard.swift file"))
    return findings, cards


def self_test() -> int:
    planted = {
        "GoodRoomCard.swift": (
            "struct GoodRoomCard: View {\n"
            "  var body: some View { DSRoomChassis.Head(lead: .sentence(\"x\")) { EmptyView() } }\n"
            "}\n"),
        "SlotRoomCard.swift": (
            "struct SlotRoomCard: View {\n"
            "  var body: some View { DSRoomSlot(headline: nil) { Text(\"{\") } }\n"
            "}\n"),
        "CommentRoomCard.swift": (
            "/// Composes DSRoomChassis.Head — or says it does.\n"
            "struct CommentRoomCard: View {\n"
            "  var body: some View { VStack { Text(\"DSRoomChassis\") } }\n"
            "}\n"),
        "HelperRoomCard.swift": (
            "struct HelperRoomCard: View {\n"
            "  var body: some View { VStack { Text(\"a\") }.padding(gap) }\n"
            "  private var gap: CGFloat { DSRoomChassis.headBlockGap }\n"
            "  private struct Inner: View {\n"
            "    var body: some View { DSRoomChassis.Block { EmptyView() } }\n"
            "  }\n"
            "}\n"),
        "DelegateRoomCard.swift": (
            "struct DelegateRoomCard: View {\n"
            "  var body: some View { if flag { stacked } else { Text(\"a\") } }\n"
            "  private var stacked: some View {\n"
            "    VStack(spacing: DSRoomChassis.contentGap) { EmptyView() }\n"
            "  }\n"
            "}\n"),
        "OrphanRoomCard.swift": (
            "struct OrphanRoomCard: View {\n"
            "  var body: some View { Text(\"a\") }\n"
            "  private var unused: some View { DSRoomChassis.Block { EmptyView() } }\n"
            "}\n"),
        "FigureRoomCard.swift": (
            "struct FigureRoomFigure: View {\n"
            "  var body: some View { DSRoomSlot(headline: nil) { EmptyView() } }\n"
            "}\n"),
        "PaintedRoomCard.swift": (
            "struct PaintedRoomCard: View {\n"
            "  var body: some View { DSRoomChassis.Block { EmptyView() }.dsWidgetSurface() }\n"
            "}\n"),
        "ExemptRoomCard.swift": (
            "struct ExemptRoomCard: View {\n"
            "  var body: some View { VStack { } }\n"
            "}\n"),
    }
    EXEMPT["ExemptRoomCard"] = "self-test"
    try:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            screens = root / SCREENS
            screens.mkdir(parents=True)
            for name, body in planted.items():
                (screens / name).write_text(body, encoding="utf-8")
            findings, cards = scan(root)
    finally:
        EXEMPT.pop("ExemptRoomCard", None)
    got = sorted((tag, loc.split("/")[-1]) for tag, loc, _ in findings)
    want = [("A", "CommentRoomCard.swift"),
            ("A", "HelperRoomCard.swift"),
            ("A", "OrphanRoomCard.swift"),
            ("B", "PaintedRoomCard.swift")]
    ok = got == want and cards == len(planted)
    print(f"room-chassis-audit self-test: {'OK' if ok else 'FAIL'} ({got}, {cards} cards)")
    return 0 if ok else 1


def main() -> int:
    if "--self-test" in sys.argv:
        return self_test()
    findings, cards = scan(ROOT)
    for tag, loc, why in findings:
        print(f"  [{tag}] {loc}: {why}")
    if findings:
        print(f"room-chassis-audit: FAIL ({len(findings)} finding(s) across {cards} room heads)")
        return 1
    print(f"room-chassis-audit: OK — all {cards} room heads compose DSRoomChassis")
    return 0


if __name__ == "__main__":
    sys.exit(main())
