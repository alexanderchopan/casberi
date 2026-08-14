#!/usr/bin/env python3
"""Theme tags audit (2026-08-14).

The Themes treemap at the top of the All feed draws `Thing.tags` clustered by
name — so every tag in the corpus is a candidate THEME, and a theme is supposed
to be what your corpus is ABOUT. Until 2026-08-14 the only tags it refused were
the kind type-tags, so every state label a BRIDGE stamps on its own rows
("Post", "Watchlist", "Silence", "Pending") clustered as a theme and — being
orders of magnitude more numerous than any real subject — crowded the genuine
themes out of all six cells.

`HomeComposition.mechanicalTags` is the fix, and half of it is a HAND LIST: the
facet half derives from `Retriever.facetTags`, but a bridge stamps its status
labels inline and `Thing.tags` records no provenance, so there is no registry
to read for the rest. This audit is what makes that hand list allowed to exist:

  Every literal tag string stamped anywhere in the tree must be RULED — either
  mechanical (excluded from the map) or a real subject (drawn) — and a new
  bridge's status label fails the build until someone decides which it is.

Mechanical rather than remembered because the failure is invisible and slow: a
new status tag renders a perfectly good-looking map, and only someone who knows
what their own corpus is about would notice the cell is bookkeeping. It is the
same shape as `catalog-sync.sh` and `demo-selftest.py`'s checks D/E — a curated
set that must be provably complete.

WHAT IT DELIBERATELY DOES NOT CHECK. Whether a ruling is RIGHT: it cannot tell a
subject from a state label, only that somebody decided. And a tag built at
runtime (`tags: [feed.tag]`, a token symbol, a user's own typed tag) has no
literal to read, which is correct — those are subjects by construction.

Usage:  scripts/theme-tags-audit.py [--self-test]
Exit 0 = clean.
"""

import re
import sys
import pathlib
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = [ROOT / "Casberi/Casberi", ROOT / "Casberi/Shared"]
COMPOSITION = ROOT / "Casberi/Casberi/GenUI/HomeComposition.swift"
RETRIEVER = ROOT / "Casberi/Casberi/Model/Retriever.swift"

# Tags that are real SUBJECTS — they name what a thing is about, so the map is
# right to draw them. Every one of these is a demo seed or a sample feed topic;
# a person's own tags never appear as literals in the tree at all.
KNOWN_SUBJECT = {
    "Book club", "Casberi", "casberi", "Fitness", "Food", "Home",
    "Lisbon trip", "Onchain", "Work",
    "crypto", "economics", "politics", "science", "sports", "tech",
}

# Fragments that are not tags at all: interpolated pieces of a computed label.
# `["B", "D", "A"][i]` builds "Nutri-Score A" — the tag is the interpolation,
# and these are the letters going into it.
KNOWN_FRAGMENT = {"A", "B", "D"}

# `tags: [...]`, `tags = [...]`, `tags.append(...)` — the three ways a tag is
# stamped. Non-greedy to the first `]` or `)`, which is why an interpolated
# entry (no quotes) simply contributes nothing rather than mis-parsing.
STAMP = re.compile(r"tags(?:\s*:\s*\[|\s*=\s*\[|\.append\()([^\]\)]*)")
# A literal NOT being compared against. The negative lookbehind is the whole
# point, and it was earned on this audit's first real run: a stamp may pick its
# tag with a ternary — `tags: [marker == "saved" ? "Saved" : "Liked"]` — where
# `"saved"` is the thing being TESTED and only `"Saved"`/`"Liked"` are ever
# stamped. Without it this reported a perfectly correct importer, and a lint
# that cries wolf gets turned off within a week.
LITERAL = re.compile(r'(?<![=!]=\s)(?<![=!]=)"([A-Za-z][A-Za-z0-9 ]*)"')
# A `String(localized: "…")` tag is still a literal tag.
LOCALIZED = re.compile(r'String\(localized:\s*"([^"]*)"\)')


def strip_comments(text):
    """A doc comment naming a tag it excludes is prose, not a stamp."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return "\n".join(re.sub(r"//.*$", "", line) for line in text.splitlines())


def stamped_tags(sources):
    """Every literal tag string stamped in the tree, with where it came from."""
    found = {}
    for root in sources:
        for path in sorted(root.rglob("*.swift")):
            # The exclusion list itself is a list OF tags, not a stamping of
            # them; reading it back would make the audit vacuously true.
            if path.resolve() == COMPOSITION.resolve():
                continue
            body = strip_comments(path.read_text(errors="ignore"))
            for chunk in STAMP.findall(body):
                for tag in LITERAL.findall(chunk) + LOCALIZED.findall(chunk):
                    found.setdefault(tag, path.name)
    return found


def declared_mechanical(text):
    """The tags `HomeComposition.mechanicalTags` names, hand half only."""
    body = strip_comments(text)
    m = re.search(r"static (?:var|let) mechanicalTags[^\[]*\[(.*?)\]\s*\)", body, re.S)
    if not m:
        return None
    return set(LITERAL.findall(m.group(1)))


def declared_facets(text):
    """The tags `Retriever.facetTable` names — the derived half."""
    body = strip_comments(text)
    m = re.search(r"facetTable[^=]*=\s*\{\s*\[(.*?)\n\s*\]\s*\}\(\)", body, re.S)
    if not m:
        return None
    # Each row is `([phrases…], "Tag")` — the tag is the last literal in it.
    tags = set()
    for row in re.findall(r"\]\s*,\s*\"([^\"]+)\"\s*\)", m.group(1)):
        tags.add(row)
    return tags


def type_tags(sources):
    """`ThingKind.typeTag`'s own returns — already excluded by the map."""
    for root in sources:
        for path in root.rglob("Thing.swift"):
            body = path.read_text(errors="ignore")
            m = re.search(r"var typeTag: String \{(.*?)\n    \}", body, re.S)
            if m:
                return set(re.findall(r'"([^"]+)"', m.group(1)))
    return set()


def audit(sources, composition=None, retriever=None):
    problems = []
    comp_text = (composition or COMPOSITION).read_text(errors="ignore")
    retr_text = (retriever or RETRIEVER).read_text(errors="ignore")

    mechanical = declared_mechanical(comp_text)
    if mechanical is None:
        return ["HomeComposition.mechanicalTags not found — did it move or "
                "change shape? The map's exclusion is unverifiable."]
    facets = declared_facets(retr_text)
    if facets is None:
        return ["Retriever.facetTable not found — the derived half of "
                "mechanicalTags is unverifiable."]
    # The union is what the map really excludes, and the audit must reason over
    # the same union rather than the hand list alone, or every facet reads as an
    # unruled tag.
    ruled = mechanical | facets | type_tags(sources) | KNOWN_SUBJECT | KNOWN_FRAGMENT

    for tag, where in sorted(stamped_tags(sources).items()):
        if tag not in ruled:
            problems.append(
                f'"{tag}" ({where}) is stamped as a tag and ruled nowhere — '
                f"add it to HomeComposition.mechanicalTags if it is a state "
                f"label, or to KNOWN_SUBJECT here if it names a subject.")
    return problems


def self_test():
    """A check that cannot fail proves nothing — demonstrate each finding."""
    ok = True
    comp = ('enum HomeComposition {\n'
            '    static var mechanicalTags: Set<String> {\n'
            '        Retriever.facetTags.union([\n'
            '            "Watchlist", "Silence",\n'
            '        ])\n'
            '    }\n}\n')
    retr = ('enum Retriever {\n'
            '    private static let facetTable: [(phrases: [String], tag: String)] = {\n'
            '        [\n'
            '            (["posts", "post"], "Post"),\n'
            '            (["likes", "liked"], "Liked"),\n'
            '        ]\n'
            '    }()\n}\n')

    cases = {
        "Mechanical.swift": ('let t = Thing(tags: ["Watchlist"])\n',
                             False, "a tag the hand list rules mechanical"),
        "Facet.swift": ('let t = Thing(tags: ["Post"])\n',
                        False, "a tag the FACET registry rules, without re-listing it"),
        "Subject.swift": ('let t = Thing(tags: ["Onchain"])\n',
                          False, "a tag ruled a real subject"),
        "Unruled.swift": ('let t = Thing(tags: ["Quarantined"])\n',
                          True, "a new bridge's status label nobody ruled"),
        "Localized.swift": ('let t = Thing(tags: [String(localized: "Escrowed")])\n',
                            True, "an unruled tag written as a localized string"),
        "Appended.swift": ('t.tags.append("Sequestered")\n',
                           True, "an unruled tag added via append"),
        "Computed.swift": ('let t = Thing(tags: [feed.tag, symbol])\n',
                           False, "a runtime tag, which has no literal to rule"),
        "Ternary.swift": ('let t = Thing(tags: [m == "quarantined" ? "Watchlist" : "Post"])\n',
                          False, "a ternary's TEST operand, which is never stamped"),
        "CommentOnly.swift": ('// "Watchlist" and "Nonsuch" are state labels\n'
                              'let t = Thing(tags: ["Onchain"])\n',
                              False, "prose naming a tag it does not stamp"),
    }

    with tempfile.TemporaryDirectory() as tmp:
        base = pathlib.Path(tmp)
        comp_path = base / "HomeComposition.swift"
        retr_path = base / "Retriever.swift"
        comp_path.write_text(comp)
        retr_path.write_text(retr)
        for name, (body, should_flag, why) in cases.items():
            single = base / f"only-{name.lower()}"
            single.mkdir()
            (single / name).write_text(body)
            flagged = bool(audit([single], comp_path, retr_path))
            mark = "ok  " if flagged == should_flag else "FAIL"
            if flagged != should_flag:
                ok = False
            verb = "flags" if should_flag else "passes"
            print(f"  {mark} {verb} {why}")

        # Mutation: deleting the derived half must break the facet case, or the
        # union is being satisfied by something else and the derivation proves
        # nothing.
        broken = base / "broken-retriever.swift"
        broken.write_text("enum Retriever {}\n")
        single = base / "only-facet.swift"
        problems = audit([single], comp_path, broken)
        mark = "ok  " if problems else "FAIL"
        if not problems:
            ok = False
        print(f"  {mark} fails loudly when the facet registry can't be read")

        # Mutation: a hand-list entry must be load-bearing.
        thinned = base / "thin-composition.swift"
        thinned.write_text(comp.replace('"Watchlist", ', ""))
        single = base / "only-mechanical.swift"
        problems = audit([single], thinned, retr_path)
        mark = "ok  " if problems else "FAIL"
        if not problems:
            ok = False
        print(f"  {mark} flags a tag once it is dropped from the hand list")
    return ok


if "--self-test" in sys.argv:
    print("theme-tags-audit self-test")
    sys.exit(0 if self_test() else 1)

problems = audit(SOURCES)
if problems:
    print("✗ theme tag findings:")
    for p in problems:
        print(f"  {p}")
    print("\nThe Themes treemap draws every tag it is not told to exclude. "
          "See HomeComposition.mechanicalTags.")
    sys.exit(1)
print("✓ theme tags audit: every stamped tag is ruled subject or mechanical")
