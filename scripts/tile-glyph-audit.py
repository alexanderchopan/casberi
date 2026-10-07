#!/usr/bin/env python3
"""Tile-glyph audit — one glyph, one meaning, for every tile in the app.

WHY THIS EXISTS. A tile's glyph IS its meaning: a room's tiles and the dock's
categories share one vocabulary, so a symbol worn by two meanings reads as one
thing, and a meaning that changes symbol between rooms reads as two (user,
2026-09-18: "you can't reuse an existing icon we use for a different type of
tile, and you can't make up new icons for existing icons we have"). Privy's
Apps wore Frames' glyph for a month with every table check green (prd §831),
because the collision lived in a section enum nobody read. Nothing a build or a
screenshot sweep does can see either failure: the tile draws, in a real symbol.

These rules lived in `room-kind-tiles-selftest.sh` until the kind tiles were
deleted with the merged rooms (prd §1057, §1059). They were never about the
kind tiles; they hold every `DSTileScope` and the dock, so they moved here.

SIX CHECKS, static, no build:

  A. No `DSTileScope` conformance anywhere in the app spells a glyph literal:
     a tile glyph is a `ScopeTileGlyph` constant or the dock's own
     `CategoryFold.glyph(for:)`, never a string typed at the conformance.
  B. In `ScopeTileGlyphs.swift`, a case wears the constant of its OWN name
     (`case .watch: return ScopeTileGlyph.watch`), unless the pair is declared
     in `ALIASES` below with its reason.
  C. A declared alias whose case is gone fails: an allowance that guards
     nothing is deleted, not left.
  D. One symbol, one meaning, across `ScopeTileGlyph`'s table and the dock's
     category glyphs (`CategoryFold.glyphs`).
  E. The symbols the user reserved keep their one owner (the Wallet's card,
     Positions' columns, Review's shield, Risk's shield, Permissions' key).
  F. `ScopeTileGlyph.all` reads the dock's All glyph rather than retyping it,
     and every `ScopeTileGlyph` constant is worn somewhere outside its own
     declaration: a constant nothing reads is a meaning with no tile, the
     model half of a feature deleted from the surface (CLAUDE.md's RULE).

WHAT THIS DELIBERATELY DOES NOT CHECK:

  · Glyphs outside tiles (a row's `KindGlyph`, a seat's mark, a dial's disc).
    They are other vocabularies with their own owners.
  · Whether a symbol exists in SF Symbols: a typo draws nothing, which the
    screen sweep sees and this cannot.
  · A glyph reached through a variable or a helper other than the two named in
    A. None exists; a text check could not follow one.
"""

import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = "Casberi/Casberi"
GLYPHS = f"{APP}/Screens/ScopeTileGlyphs.swift"
FOLD = f"{APP}/Model/CategoryFold.swift"

# A case that wears another name's constant, with the reason it is one meaning.
ALIASES = {
    # (The Wallet's verb was Follow wearing Watch's eye until prd §1105 named
    # it Watch; it wears its own name now, so its alias is gone.)
    # (Reading's Follow wore Watch's eye until prd §1118 made it the first
    # row of its Subscriptions tile, which wears its own name.)
    # Social's Follow (prd §1086) watches a person privately: the same meaning.
    ("SocialScope", "follow"): "watch",
    # You's Today (prd §1168) IS the "All" source, the dock's inbox tray.
}

# Symbols the user named as one meaning's own (2026-09-18; the Wallet's
# moved from the credit card to the dollar sign, prd §1063).
RESERVED = [("building.columns", "positions"), ("dollarsign", "wallet"),
            ("checkmark.shield", "review"),
            ("shield", "risk"), ("key", "permissions")]

# Today reads the dock's All (prd §1168, §1169); every room's All is a stack.
ALL_READ = 'static var feed: String { CategoryFold.glyph(for: "All") }'


def strip_comments(text: str) -> str:
    """Comments out, strings and line breaks kept, so a doc comment quoting a
    symbol or a `case` is never read as code."""
    out, i, n = [], 0, len(text)
    in_block = in_string = False
    while i < n:
        ch, nxt = text[i], text[i + 1] if i + 1 < n else ""
        if in_block:
            if ch == "*" and nxt == "/":
                in_block = False
                i += 2
                continue
            out.append("\n" if ch == "\n" else "")
            i += 1
            continue
        if in_string:
            if ch == "\\":
                out.append(text[i:i + 2])
                i += 2
                continue
            if ch == '"':
                in_string = False
            out.append(ch)
            i += 1
            continue
        if ch == '"':
            in_string = True
        elif ch == "/" and nxt == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        elif ch == "/" and nxt == "*":
            in_block = True
            i += 2
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def block(text: str, start: int) -> str:
    """The braced body that opens at or after `start`."""
    i = text.find("{", start)
    if i < 0:
        return ""
    depth = 0
    for j in range(i, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[i + 1:j]
    return text[i + 1:]


CONFORMANCE = re.compile(r"\b(?:extension|struct|enum|class)\s+([\w.]+)\s*:\s*[^{]*\bDSTileScope\b")
GLYPH_PROP = re.compile(r"\bvar\s+glyph\s*:\s*String\b")


def audit(root: Path):
    fails = []
    glyphs_path, fold_path = root / GLYPHS, root / FOLD
    if not glyphs_path.exists() or not fold_path.exists():
        return [f"{GLYPHS} or {FOLD} is missing - this audit is blind"]
    raw_glyphs = glyphs_path.read_text(encoding="utf-8")
    glyphs = strip_comments(raw_glyphs)
    fold = strip_comments(fold_path.read_text(encoding="utf-8"))

    sources = {}
    for path in sorted((root / APP).rglob("*.swift")):
        sources[path] = strip_comments(path.read_text(encoding="utf-8"))

    # ── A. no literal glyph at any conformance ──────────────────────────────
    conformers = 0
    for path, text in sources.items():
        rel = path.relative_to(root)
        for m in CONFORMANCE.finditer(text):
            body = block(text, m.end() - 1)
            g = GLYPH_PROP.search(body)
            if not g:
                continue
            conformers += 1
            getter = block(body, g.end())
            if re.search(r'"[^"]*"', getter.replace('"All"', "")):
                fails.append(f"A {rel}: {m.group(1)}'s glyph spells a literal - every tile glyph is a "
                             f"ScopeTileGlyph constant or CategoryFold.glyph(for:)")
    if conformers == 0:
        fails.append("A no DSTileScope conformance was found - this audit is blind")

    # ── B, C. a case wears its own name's constant ──────────────────────────
    seen_aliases = set()
    extensions = list(re.finditer(r"extension\s+([\w.]+)\s*:\s*DSTileScope\s*\{", glyphs))
    if not extensions:
        fails.append(f"B {GLYPHS} holds no DSTileScope extension - this audit is blind")
    for m in extensions:
        owner = m.group(1)
        short = owner.split(".")[0]
        body = block(glyphs, m.end() - 1)
        for case, const in re.findall(r"case \.(\w+):\s*return ScopeTileGlyph\.(\w+)\b", body):
            if case == const:
                continue
            if ALIASES.get((short, case)) == const:
                seen_aliases.add((short, case))
            else:
                fails.append(f"B {owner}.{case} wears ScopeTileGlyph.{const} - a case wears its own "
                             f"name's glyph, or the pair is declared in ALIASES with its reason")
    for (short, case), const in sorted(ALIASES.items()):
        if (short, case) not in seen_aliases:
            fails.append(f"C the declared alias {short}.{case} -> {const} no longer exists - "
                         f"delete it rather than leave an allowance that guards nothing")

    # ── D, E. one symbol, one meaning ───────────────────────────────────────
    t = re.search(r"enum ScopeTileGlyph \{", glyphs)
    if not t:
        return fails + [f"D ScopeTileGlyph is missing from {GLYPHS} - this audit is blind"]
    table = block(glyphs, t.end() - 1)
    constants = re.findall(r'static let (\w+)\s*=\s*"([^"]+)"', table)
    d = re.search(r"private static let glyphs: \[String: String\] = \[(.*?)\]", fold, re.S)
    if not d:
        return fails + ["D CategoryFold's dock glyph table moved - this audit is blind"]
    dock = re.findall(r'"([^"]+)":\s*"([^"]+)"', d.group(1))
    if not constants or not dock:
        fails.append("D a glyph table read empty - this audit is blind")
    meanings = {}
    for name, sym in constants:
        meanings.setdefault(sym, set()).add(name.lower())
    for cat, sym in dock:
        meanings.setdefault(sym, set()).add(cat.lower())
    for sym, names in sorted(meanings.items()):
        if len(names) > 1:
            fails.append(f'D "{sym}" means {sorted(names)} - one glyph may carry one meaning')
    for sym, owner in RESERVED:
        if sym in meanings and meanings[sym] - {owner}:
            fails.append(f'E "{sym}" is {owner}\'s and wears another meaning')

    # ── F. All reads the dock, and every constant is worn ──────────────────
    if ALL_READ not in glyphs:
        fails.append("F ScopeTileGlyph.feed retypes the dock's All glyph instead of reading CategoryFold")
    names = [n for n, _ in constants] + re.findall(r"static var (\w+)\s*:\s*String", table)
    elsewhere = glyphs.replace(table, "") + "".join(v for p, v in sources.items() if p != glyphs_path)
    for name in names:
        if not re.search(r"\bScopeTileGlyph\.%s\b" % re.escape(name), elsewhere):
            fails.append(f"F ScopeTileGlyph.{name} is worn by nothing - a constant no tile reads is a "
                         f"meaning with no tile; delete it with the tile that wore it")
    return fails


# ── Self-test ────────────────────────────────────────────────────────────────
CLEAN_GLYPHS = '''import Foundation
enum ScopeTileGlyph {
    static let home        = "chart.xyaxis.line"
    static let positions   = "building.columns"
    static let review      = "checkmark.shield"
    static let all         = "square.stack"
    /// The dock's own "tray.full", read, never retyped.
    static var feed: String { CategoryFold.glyph(for: "All") }
    static let watch       = "eye"
    static let new         = "plus"
}

// A comment quoting `case .home: return "house"` is not code.
extension WalletSection: DSTileScope {
    var glyph: String {
        switch self {
        case .home:      return ScopeTileGlyph.home
        case .positions: return ScopeTileGlyph.positions
        case .watch:     return ScopeTileGlyph.watch
        }
    }
}

extension NotesScope: DSTileScope {
    var glyph: String {
        switch self {
        case .all: return ScopeTileGlyph.all
        case .new: return ScopeTileGlyph.new
        }
    }
}

extension SocialScope: DSTileScope {
    var glyph: String {
        switch self {
        case .all: return ScopeTileGlyph.all
        case .follow: return ScopeTileGlyph.watch
        }
    }
}

extension YouTile: DSTileScope {
    var glyph: String {
        switch self {
        case .feed: return ScopeTileGlyph.feed
        }
    }
}
'''

CLEAN_FOLD = '''import Foundation
enum CategoryFold {
    private static let glyphs: [String: String] = [
        "Wallet":   "dollarsign",
        "Work":     "laptopcomputer",
        "All":      "tray.full",
    ]
}
'''

CLEAN_SCOPE = '''import Foundation
struct CatalogScope: DSTileScope {
    let name: String?
    var id: String { name ?? "all" }
    var glyph: String { CategoryFold.glyph(for: name ?? "All") }
    var summary: String { name ?? "Every app" }
}

struct ReviewTile: View {
    var body: some View { Image(systemName: ScopeTileGlyph.review) }
}
'''

# Each mutation: (what it proves, file, old, new, the check letter that must fire).
MUTATIONS = [
    ("a conformance outside the glyph file spells a literal",
     "scope", 'var glyph: String { CategoryFold.glyph(for: name ?? "All") }',
     'var glyph: String { name == nil ? "eye" : CategoryFold.glyph(for: name!) }', "A"),
    ("a case in the glyph file returns a literal",
     "glyphs", "case .new: return ScopeTileGlyph.new", 'case .new: return "plus"', "A"),
    ("a case wears another name's constant (Privy's Apps in Frames' glyph)",
     "glyphs", "case .new: return ScopeTileGlyph.new", "case .new: return ScopeTileGlyph.home", "B"),
    ("a declared alias outlives its case",
     "glyphs", "extension SocialScope: DSTileScope {\n    var glyph: String {\n        switch self {\n        case .all: return ScopeTileGlyph.all\n        case .follow: return ScopeTileGlyph.watch\n",
     "extension SocialScope: DSTileScope {\n    var glyph: String {\n        switch self {\n        case .all: return ScopeTileGlyph.all\n", "C"),
    ("two constants share one symbol",
     "glyphs", 'static let new         = "plus"', 'static let new         = "eye"', "D"),
    ("a constant takes a dock category's symbol",
     "glyphs", 'static let new         = "plus"', 'static let new         = "laptopcomputer"', "D"),
    ("a reserved symbol takes another meaning",
     "glyphs", 'static let home        = "chart.xyaxis.line"', 'static let home        = "dollarsign"', "E"),
    ("All retypes the dock's glyph",
     "glyphs", 'static var feed: String { CategoryFold.glyph(for: "All") }',
     'static var feed: String { "tray.full" }', "F"),
    ("a constant nothing wears",
     "scope", "Image(systemName: ScopeTileGlyph.review)", 'Image(systemName: "checkmark")', "F"),
]


def self_test() -> int:
    failures = []
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        files = {"glyphs": root / GLYPHS, "fold": root / FOLD,
                 "scope": root / APP / "Screens/CatalogScope.swift"}
        clean = {"glyphs": CLEAN_GLYPHS, "fold": CLEAN_FOLD, "scope": CLEAN_SCOPE}
        for p in files.values():
            p.parent.mkdir(parents=True, exist_ok=True)

        def run(over=None):
            for k, p in files.items():
                p.write_text((over or {}).get(k, clean[k]), encoding="utf-8")
            return audit(root)

        got = run()
        if got:
            failures.append(f"the clean fixture was flagged: {got}")
        for what, key, old, new, letter in MUTATIONS:
            if old not in clean[key]:
                failures.append(f"mutation anchor drifted, so it would prove nothing: {what}")
                continue
            got = run({key: clean[key].replace(old, new, 1)})
            if not any(f.startswith(letter + " ") for f in got):
                failures.append(f"check {letter} did not fire: {what} (got {got})")
    for f in failures:
        print("  ✗ " + f)
    if failures:
        return 1
    print(f"tile-glyph-audit self-test: clean fixture passes, all {len(MUTATIONS)} mutations caught")
    return 0


def main() -> int:
    if "--self-test" in sys.argv[1:]:
        return self_test()
    fails = audit(ROOT)
    for f in fails:
        print("  ✗ " + f)
    if fails:
        print(f"tile-glyph-audit: {len(fails)} finding(s)")
        return 1
    print("tile-glyph-audit: every tile glyph is one meaning's own")
    return 0


if __name__ == "__main__":
    sys.exit(main())
