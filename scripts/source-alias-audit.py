#!/usr/bin/env python3
"""Renamed-source alias audit (prd §647, 2026-09-08).

An offer's name is also its rows' `Thing.source` string. So renaming a seat
strands every row already landed under the old name: `BridgeCatalog.offer(forSource:)`
answers nil, and from there the row has NO SEAT — no category, so its chip
escapes `CategoryFold` and draws as a bare circle beside a row of category
words; no mark, so every row of it wears `BridgeGlyph`'s `app` fallback, a blank
rounded square. It reached a device exactly that way: *"there is a random tile in
the nav bar. looks like ethers gegota and should be in the wallet room! icon
missing too"*.

WHY THIS IS MECHANICAL. Every failure below renders as a perfectly good app.
The build is clean, every existing audit passes, and the screen sweep
photographs a strip that looks right to anyone who does not already know which
chip should not be there. Nothing else here can see it:

  * an ALIAS POINTING AT NOTHING — a value that is not a live offer name — is
    the original bug wearing a fix's clothes: resolution still answers nil, and
    now a table asserts that it doesn't;
  * an alias KEY that is also a live offer name would displace a real seat, i.e.
    turn one silent misresolution into a louder one;
  * the WIRING going quiet: `BridgeCatalog.seatNameBySource` folding the table
    in is one line, and deleting it re-creates the whole bug with the table
    still sitting there looking authoritative;
  * an identity resolver forgetting to canonicalise — the chip folds correctly
    while the ROWS stay blank, which is a strictly weirder screen than the
    original and reads as a rendering fault rather than a naming one;
  * the sweep drifting back INSIDE the migration version gate, which is the
    shape §647 exists to reject: a one-shot cannot be complete against a
    CloudKit-mirrored store, because rows arrive after it has run and it never
    runs again.

A SECOND HALF, added by §650. Some renames moved the rows' REF NAMESPACE with
the name (`dexscreener:` → `tokens:`), and converging only the source leaves the
row half-way: it finds its seat, its room and its mark, and stays invisible to
every consumer that matches the ref exactly. That failure renders even better
than the first one — nothing looks wrong at all, and `TokenWatch.add`'s
already-watching guard simply misses the row, so the same coin lands a SECOND
time and the watchlist grows a duplicate nobody can explain.

Nine checks, all static — no build, no simulator, no network.

  A. Every VALUE in `Corpus.renamedSources` is a real `Offer(name:)`.
  B. No KEY is a live offer name (an alias may never shadow a seat).
  C. No KEY is in `Corpus.retiredSources` (a source cannot be both renamed
     onto a live seat and declared to have left the catalog).
  D. `BridgeCatalog.seatNameBySource` reads `Corpus.renamedSources`.
  E. Every source→identity resolver canonicalises: `BridgeIcon.assetName`,
     `BridgeGlyph.symbol`, `BridgeGlyph.glyphTint`, `DS.brandHue` and
     `Notifications.brandAsset` each call `Corpus.canonicalSource`.
  F. `SourceRename.sweep` is called from `RootShell` OUTSIDE the
     `migrationsStored <` gate.
  G. `SourceRename.sweep` APPLIES a declared ref prefix — it reads
     `rename.refPrefix` and assigns `sourceRef`. A pair sitting in the table
     that nothing acts on is the §650 bug with a fix's paperwork filed.
  H. Every declared CURRENT ref prefix is a namespace the tree really writes.
     The ref analogue of check A: rewriting rows into a namespace no producer
     uses moves them from one place no consumer matches to another.
  I. No declared OLD ref prefix is a namespace the tree still writes. The ref
     analogue of check B: aliasing a LIVE namespace would rewrite rows that
     were already correct, every launch, for good.

Checks H and I read ref-namespace literals in the form every ref in this tree is
written in — a string literal that STARTS with the namespace (`"tokens:\(chain)…"`).
Stated as a ceiling, not a claim of completeness: a namespace assembled from
pieces at runtime is invisible to both, the same way `ref-shape-audit.py`'s own
static heads are.

Two deliberate NON-checks:

  * It never demands a table ENTRY for a rename. Nothing static can know that a
    string used to be an offer name — that is the author's knowledge, and the
    check that would need it would have to fire on every string in the tree.
  * It never verifies that a bundled `brand-<name>` asset exists for the value.
    `BridgeIcon` falls back on purpose and several live seats have no asset at
    all; an absent mark is a different question from an unresolvable name.

Checks E and F read a COMMENT-STRIPPED copy of each file — these sources
document the rule by naming the very symbols the checks grep for, so a raw grep
passes on the prose explaining why the code is missing (the standing lesson from
the Obsidian/Cursor guards and `ondevice-selftest.sh`).

Usage:  scripts/source-alias-audit.py [--self-test]
Exit 0 = clean.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
THING = ROOT / "Casberi/Shared/Thing.swift"
CATALOG = ROOT / "Casberi/Casberi/Model/BridgeCatalog.swift"
ROOTSHELL = ROOT / "Casberi/Casberi/Shell/RootShell.swift"
SWEEP = ROOT / "Casberi/Casberi/Model/SourceRename.swift"

# Where a ref namespace may legitimately be produced. Everything under the
# project except the two files that MENTION a namespace without writing one:
# the table that declares the pair, and the sweep that applies it.
REF_CORPUS_ROOT = ROOT / "Casberi"
REF_CORPUS_SKIP = {THING, SWEEP}

# The body of the sweep, for check G.
SWEEP_HEADER = "static func sweep(context: ModelContext) -> Int {"

# file, enclosing declaration, the symbol whose body must canonicalise
RESOLVERS = [
    ("Casberi/Casberi/Design/BridgeIcon.swift", "var assetName: String {"),
    ("Casberi/Casberi/Design/KindGlyph.swift", "static func symbol(for name: String) -> String {"),
    ("Casberi/Casberi/Design/KindGlyph.swift", "static func glyphTint(for name: String) -> Color? {"),
    ("Casberi/Casberi/Design/AppIconTile.swift", "static func brandHue(for source: String) -> Color? {"),
    ("Casberi/Casberi/Model/Notifications.swift", "private static func brandAsset(_ name: String) -> UIImage? {"),
]


def strip_comments(text: str) -> str:
    """Blank out `//` line comments and `/* */` blocks, keeping line structure.

    Deliberately naive about string literals: no source here carries a `//`
    inside one that would change an answer, and the alternative is a Swift
    lexer for a grep.
    """
    out = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)
    return "\n".join(re.sub(r"//.*$", "", line) for line in out.split("\n"))


STR = r'"((?:[^"\\]|\\.)*)"'

RENAME_ENTRY = re.compile(
    STR + r"\s*:\s*Rename\(\s*current:\s*" + STR
    + r"(?:\s*,\s*refPrefix:\s*\.init\(\s*old:\s*" + STR
    + r"\s*,\s*current:\s*" + STR + r"\s*\))?\s*\)")


def bracket_body(text: str, start: int):
    """The `[...]` contents beginning at `start`, brace-balanced."""
    body, depth, i = [], 1, start
    while i < len(text) and depth:
        if text[i] == "[":
            depth += 1
        elif text[i] == "]":
            depth -= 1
            if not depth:
                break
        body.append(text[i])
        i += 1
    return "".join(body)


def swift_renames(text: str):
    """The entries of `static let renamedSources: [String: Rename] = [...]`.

    Returns `(old, current, old_ref_prefix|None, current_ref_prefix|None)` per
    entry. A malformed entry is not silently dropped: the count of `"…":` keys
    in the literal is compared against the entries parsed, and a mismatch is
    reported — otherwise a typo in the `Rename(` shape would make an entry
    invisible to every check below, which is the audit going quiet on exactly
    the thing it exists to watch.
    """
    m = re.search(r"static let renamedSources:\s*\[String:\s*Rename\]\s*=\s*\[", text)
    if not m:
        return None, None
    body = bracket_body(text, m.end())
    entries = [(unescape(k), unescape(v),
                unescape(po) if po else None, unescape(pc) if pc else None)
               for k, v, po, pc in RENAME_ENTRY.findall(body)]
    keys = len(re.findall(STR + r"\s*:", body))
    return entries, keys


def swift_set(text: str, name: str):
    m = re.search(r"static let " + re.escape(name) + r":\s*Set<String>\s*=\s*\[", text)
    if not m:
        return None
    body, depth, i = [], 1, m.end()
    while i < len(text) and depth:
        if text[i] == "[":
            depth += 1
        elif text[i] == "]":
            depth -= 1
            if not depth:
                break
        body.append(text[i])
        i += 1
    return re.findall(r'"((?:[^"\\]|\\.)*)"', "".join(body))


def unescape(s: str) -> str:
    """Resolve the `\\u{XXXX}` escapes a Swift literal may carry."""
    return re.sub(r"\\u\{([0-9A-Fa-f]+)\}", lambda m: chr(int(m.group(1), 16)), s)


def body_of(text: str, header: str):
    """The brace-balanced body following `header`, or None."""
    i = text.find(header)
    if i < 0:
        return None
    i += len(header)
    depth, out = 1, []
    while i < len(text) and depth:
        c = text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if not depth:
                break
        out.append(c)
        i += 1
    return "".join(out)


def audit(thing_src, catalog_src, rootshell_src, resolver_srcs,
          sweep_src, ref_corpus):
    fails = []

    aliases, key_count = swift_renames(strip_comments(thing_src))
    if aliases is None:
        return ["A: `Corpus.renamedSources` not found in Thing.swift"]
    if key_count != len(aliases):
        return [f"A: `Corpus.renamedSources` has {key_count} keys but "
                f"{len(aliases)} parse as `Rename(current:…)` — an entry whose "
                f"shape this cannot read is an entry no check below governs"]

    offers = set(re.findall(r'Offer\(name:\s*"([^"]+)"', catalog_src))
    if not offers:
        return ["A: no `Offer(name:)` literals found in BridgeCatalog.swift"]

    retired = set(unescape(s) for s in (swift_set(strip_comments(thing_src), "retiredSources") or []))

    for old, current, ref_old, ref_current in aliases:
        if current not in offers:
            fails.append(f"A: alias {old!r} → {current!r} names no catalog offer")
        if old in offers:
            fails.append(f"B: alias key {old!r} is a live offer name — it would shadow that seat")
        if old in retired:
            fails.append(f"C: alias key {old!r} is also in `retiredSources`")
        if ref_current is not None:
            where = [path for path, text in ref_corpus if '"' + ref_current in text]
            if not where:
                fails.append(
                    f"H: alias {old!r} rewrites refs into {ref_current!r}, which nothing "
                    f"in the tree writes — the rows move from one namespace no consumer "
                    f"matches to another")
        if ref_old is not None:
            live = [path for path, text in ref_corpus if '"' + ref_old in text]
            if live:
                fails.append(
                    f"I: alias {old!r} rewrites refs OUT of {ref_old!r}, which "
                    f"{live[0]} still writes — the sweep would rewrite rows that are "
                    f"already correct, on every launch")

    seat_map = body_of(strip_comments(catalog_src),
                       "private static let seatNameBySource: [String: String] = {")
    if seat_map is None:
        fails.append("D: `seatNameBySource` not found in BridgeCatalog.swift")
    elif "Corpus.renamedSources" not in seat_map:
        fails.append("D: `seatNameBySource` does not fold `Corpus.renamedSources` in — "
                     "every renamed seat's rows resolve to nothing again")

    for (path, header), src in zip(RESOLVERS, resolver_srcs):
        body = body_of(strip_comments(src), header)
        if body is None:
            fails.append(f"E: {path}: `{header.strip()}` not found")
        elif "Corpus.canonicalSource" not in body:
            fails.append(f"E: {path}: `{header.strip()}` does not canonicalise — "
                         "a renamed seat's rows draw the blank `app` fallback")

    shell = strip_comments(rootshell_src)
    if "SourceRename.sweep(" not in shell:
        fails.append("F: `RootShell` never calls `SourceRename.sweep` — nothing converges")
    else:
        gate = shell.find("if migrationsStored <")
        call = shell.find("SourceRename.sweep(")
        if gate >= 0 and call > gate:
            fails.append("F: `SourceRename.sweep` is called inside the migration version gate — "
                         "a one-shot cannot catch rows that sync in after it runs (§647)")

    # G — only asked when a pair is actually declared, so a tree whose renames
    # all left the ref namespace alone does not have to carry the code.
    if any(ref_old is not None for _, _, ref_old, _ in aliases):
        body = body_of(strip_comments(sweep_src), SWEEP_HEADER)
        if body is None:
            fails.append(f"G: `{SWEEP_HEADER}` not found in SourceRename.swift")
        elif "refPrefix" not in body or "sourceRef =" not in body:
            fails.append("G: `SourceRename.sweep` declares a ref prefix pair it never "
                         "applies — the row converges half-way, finds its seat and its "
                         "mark, and stays invisible to every exact ref match (§650)")

    return fails


def ref_corpus():
    """Every project source that may legitimately PRODUCE a ref namespace."""
    out = []
    for path in sorted(REF_CORPUS_ROOT.rglob("*.swift")):
        if path in REF_CORPUS_SKIP:
            continue
        out.append((str(path.relative_to(ROOT)), path.read_text(encoding="utf-8")))
    return out


def read_all():
    return (THING.read_text(encoding="utf-8"),
            CATALOG.read_text(encoding="utf-8"),
            ROOTSHELL.read_text(encoding="utf-8"),
            [(ROOT / p).read_text(encoding="utf-8") for p, _ in RESOLVERS],
            SWEEP.read_text(encoding="utf-8"),
            ref_corpus())


def self_test():
    """Every check must be shown to FIRE. A check that cannot fail proves nothing."""
    thing, catalog, shell, resolvers, sweep, corpus = read_all()
    cases = []

    # A — an alias pointing at a name no offer carries.
    cases.append(("A", (thing.replace('"Hegota Devnet"', '"Hegota Devnet (old)"', 1),
                        catalog, shell, resolvers, sweep, corpus)))
    # B — an alias key that is a live offer name.
    cases.append(("B", (thing.replace('"Ethrex Hegot\\u{00e1}"', '"Linear"', 1),
                        catalog, shell, resolvers, sweep, corpus)))
    # C — an alias key also declared retired.
    cases.append(("C", (thing.replace('"Kalshi", "Polymarket"',
                                      '"Ethrex Hegot\\u{00e1}", "Polymarket"', 1),
                        catalog, shell, resolvers, sweep, corpus)))
    # D — the wiring deleted from the join.
    cases.append(("D", (thing,
                        catalog.replace(
                            "for (old, rename) in Corpus.renamedSources where map[old] == nil { map[old] = rename.current }",
                            "", 1),
                        shell, resolvers, sweep, corpus)))
    # E — one resolver stops canonicalising (and its COMMENT still names the rule,
    #     which is the whole reason the checks strip comments first).
    broken = list(resolvers)
    broken[0] = broken[0].replace(
        '"brand-" + Corpus.canonicalSource(name).lowercased()',
        '"brand-" + name.lowercased()', 1)
    cases.append(("E", (thing, catalog, shell, broken, sweep, corpus)))
    # F — the sweep drifts back inside the migration gate.
    moved = shell.replace("                SourceRename.sweep(context: modelContext)\n", "", 1)
    moved = moved.replace("if migrationsStored < migrationsCurrent {",
                          "if migrationsStored < migrationsCurrent {\n                    SourceRename.sweep(context: modelContext)", 1)
    cases.append(("F", (thing, catalog, moved, resolvers, sweep, corpus)))
    # G — the pair is declared and the sweep stops applying it. Build 537's own
    #     shape: the source still converges, so the room and the mark are right
    #     and only the ref is wrong, which is the half that renders perfectly.
    gutted = re.sub(
        r"\n *if let prefix = rename\.refPrefix,\n(?:.*\n)*? *\}\n",
        "\n", sweep, count=1)
    cases.append(("G", (thing, catalog, shell, resolvers, gutted, corpus)))
    # H — the rewrite targets a namespace nothing writes.
    cases.append(("H", (thing.replace('current: "tokens:"', 'current: "toknes:"', 1),
                        catalog, shell, resolvers, sweep, corpus)))
    # I — the rewrite takes rows OUT of a namespace that is still live.
    cases.append(("I", (thing.replace('old: "dexscreener:"', 'old: "wallet:"', 1),
                        catalog, shell, resolvers, sweep, corpus)))

    ok = True
    baseline = (thing, catalog, shell, resolvers, sweep, corpus)
    for label, args in cases:
        # A MUTATION THAT CHANGED NOTHING IS NOT A PASSING MUTATION — it is one
        # that did not run. Every anchor below is a literal copied out of a
        # source file, so a refactor that re-words one turns its `replace` into
        # a no-op and this loop would then audit the CLEAN tree, find nothing,
        # and report `DID NOT FIRE` against the check rather than against the
        # mutation — sending the next reader to debug working code. Checked
        # here, where the answer is unambiguous.
        if args == baseline:
            print(f"  check {label}: MUTATION IS DEAD (its anchor no longer matches "
                  f"the source — fix the mutation, not the check)")
            ok = False
            continue
        fails = audit(*args)
        fired = [f for f in fails if f.startswith(label + ":")]
        if fired:
            print(f"  check {label}: fires — {fired[0]}")
        else:
            print(f"  check {label}: DID NOT FIRE (mutation not caught) — {fails}")
            ok = False

    clean = audit(thing, catalog, shell, resolvers, sweep, corpus)
    if clean:
        print(f"  unmutated tree: NOT CLEAN — {clean}")
        ok = False
    else:
        print("  unmutated tree: clean")
    return ok


def main():
    if "--self-test" in sys.argv:
        print("source-alias-audit self-test")
        sys.exit(0 if self_test() else 1)
    fails = audit(*read_all())
    if fails:
        print("source-alias-audit: FAIL")
        for f in fails:
            print("  " + f)
        sys.exit(1)
    print("source-alias-audit: OK")


if __name__ == "__main__":
    main()
