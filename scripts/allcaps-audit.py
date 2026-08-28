#!/usr/bin/env python3
"""No display string is set in ALL CAPS (build-brief §8, prd §453).

§8's rule is "headers are words in sentence case" — never
"G E T T I N G  S T A R T E D" and never "GETTING STARTED" — and until
2026-08-22 nothing checked it. `.kerning()` was banned in writing and the caps
half of the same sentence was left to memory, which lost: `AddressSpine.eyebrow`
ran EVERY day stamp through `localizedUppercase`, so the address spine printed
TODAY on every event, and its own doc carried a carve-out arguing that was fine
("only a date stamp, three characters of month and a number") which was false
for the two commonest strings `dayText` returns. That exemption then set the
house style beside it: `FIRST` and `STANDING · NOW` were written in caps to
match, and twelve more labels had accumulated across the tree.

**Why this is mechanical rather than remembered.** A shouting label renders
perfectly. It survives the build, every screen sweep, the design-ramp audit
(which reads type SIZES, not the letters in them) and every `swiftc` harness,
because nothing about it is wrong except that it is against the house style —
and a house style with no check is a house style that drifts one label at a
time, each one justified by the last.

**The rule, and why it is spelled this narrowly.** A finding is a display
literal whose alphabetic content, once interpolations are removed, has NO
lowercase letter and contains a word of 3+ letters. The narrowing is MEASURED,
not guessed: matching any all-caps WORD inside a string reports 124 literals on
a healthy tree, of which ~112 are initialisms and brand names the app is right
to print — API, DNS, TLS, RSS, MCP, URL, OPML, NFT, HTTP, IMAP, CFTC, ETH,
HYPE, AERO, and L2BEAT, which is how L2BEAT spells itself. A lint that cries
wolf gets turned off within a week, so the test is on the WHOLE literal: a
sentence carrying an acronym has lowercase in it and is invisible here, while a
label that is nothing but capitals is exactly the thing §8 bans.

The 3-letter floor is what lets a genuine short acronym stand alone — `P2SH`,
an `ID` field label — without an exemption. `KNOWN_ACRONYMS` is for the rest:
an entry is a conscious "this WORD is an initialism, not emphasis", judged per
word so a ticker exempted once stays exempt in every phrase it appears in
while everything else in that phrase is still read.

A label position is read WHOLE — see `LABEL_ARG`. That second pass was added
after the first one shipped blind to ternaries and helper-composed verbs, which
is where nine of this rule's own violations were hiding; the lesson is that the
narrowing which keeps a lint honest is also where it goes blind, so the
narrowing has to be measured in both directions.

**What it deliberately does NOT check**, so it can't become the lint it warns
about: text a bridge received (a third party may shout in its own data and that
is a quotation, not our typography), a monogram or single-letter avatar, an
enum raw value, an HTTP verb, a ticker symbol, and `.uppercased()` applied to
anything — that call is right for `AssetMark`'s two-letter marks and wrong for
an eyebrow, and no static rule separates them. The spine's own harness guards
its `localizedUppercase` directly instead.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

SOURCES = [
    ROOT / "Casberi/Casberi",
    ROOT / "Casberi/Shared",
    ROOT / "Casberi/CasberiWidgets",
    ROOT / "Casberi/ShareExtension",
]

# The call sites that put a string on screen. `actionLabel`/`secondaryLabel`
# are `DSSlabField`'s two verbs and `placeholder` its empty state — named
# explicitly because they take a bare `String`, so a caller can hand them a
# literal without `Text` or `String(localized:)` anywhere near it, which is
# how nine of the twelve labels this landed with were spelled.
DISPLAY = re.compile(
    r'(?:Text|String\(localized:)\s*\(?\s*"((?:[^"\\]|\\.)*)"'
)

# A LABEL POSITION: every literal on the line is display text, wherever it sits
# in the expression. This is the second pass, and it exists because the first
# one missed a whole class on its own first run — `DSSlabField`'s verb is
# routinely a ternary (`checking ? "CHECKING…" : (configured ? "UPDATE" :
# "CONNECT")`), so a regex anchored to the literal immediately after the label
# keyword sees the first arm and nothing else. Four verbs across nine setup
# screens were invisible to it, on the exact control the rule was written for.
LABEL_ARG = re.compile(r'\b(?:actionLabel|secondaryLabel|placeholder)\s*:')

# …and a label composed in a helper, which is the same class one level up:
# `HandleSetupScreen.omniButtonLabel` returns its verb from four branches, so
# no call site carries a literal at all. Matched on the DECLARATION, then the
# next few lines of its body — a `String`-typed property named for a label is
# display text by its own name.
LABEL_PROP = re.compile(r'\bvar\s+\w*(?:Label|Title|Verb)\s*:\s*String')
LABEL_PROP_LINES = 9

ANY_LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')

# On a label line a literal is display text UNLESS it is being COMPARED — a
# ternary routinely tests a symbol or a raw value to pick the verb
# (`symbol == "ETH" ? "Watch" : "Add"`), and reporting the thing being tested
# is exactly how this becomes the lint that cries wolf. Caught by this file's
# own self-test while widening it, which is the argument for keeping a clean
# fixture beside every dirty one.
COMPARED = re.compile(
    r"""(?:[=!~]=|\b(?:contains|hasPrefix|hasSuffix|starts)\s*\(\s*(?:with:\s*)?)\s*$"""
)

WORD = re.compile(r"[A-Za-z][A-Za-z']*")
INTERPOLATION = re.compile(r'\\\(.*?\)')

# A conscious ruling per entry: "this literal is an initialism, not emphasis."
#
# "ETH" — a CURRENCY TICKER, the same class of thing as USDV or NFV beside it
# on the very same card. Those two are never flagged only because they arrive
# as `VibenetTokenBalance.symbol`, i.e. as data, while the native symbol is the
# one written in the source; the difference is where the string comes from, not
# what it is. Re-casing it to "Eth" would invent a spelling no exchange, wallet
# or explorer uses, which is a worse §8 outcome than the shout it fixes. The
# entry is the ticker itself rather than the whole label, so any other ALL-CAPS
# phrase on that card is still a finding.
KNOWN_ACRONYMS: set[str] = {
    "ETH",
    # An initialism, and the chain's OWN word for the thing (prd §500): EIP-8312
    # names the frame, the predeploy is the UTXO vault, and the RPC says so.
    # "Coins" was the friendly gloss and was deliberately retired — the scope
    # chip, the frame mode and the sheets all say UTXO, so exempting the word
    # here is what keeps the ruling and this lint from contradicting each other.
    "UTXO",
}

MIN_WORD = 3


def shouts(literal: str) -> bool:
    """Is this literal set in ALL CAPS, in the sense §8 bans?"""
    # An interpolation carries an IDENTIFIER, not display text — `DS.device`
    # renders as "iPhone". Reading it as content reports every sentence that
    # names a type as shouting, which was 40 of the first run's findings.
    bare = INTERPOLATION.sub("", literal)
    if any(c.islower() for c in bare):
        return False
    # Exempt PER WORD, not per literal. A ticker rarely stands alone — it sits
    # beside a figure, as "\(total) ETH" — so a whole-literal match would need
    # an entry per phrase the ticker ever appears in, and each new phrasing
    # would reopen a ruling already made about the word. Dropping the exempt
    # words and re-judging what remains keeps every OTHER shout in the same
    # label a finding, which a literal-level pass would have swallowed.
    words = [w for w in WORD.findall(bare) if w not in KNOWN_ACRONYMS]
    if not words:
        return False
    return max(len(w) for w in words) >= MIN_WORD


def scan_text(text: str):
    """Yield (line number, literal) for every shouting display literal."""
    lines = text.splitlines()
    body_left = 0
    for n, line in enumerate(lines, 1):
        # Whole-line comments only. A trailing `//` strip would cut inside a
        # `"https://…"` literal, and this file's neighbours document their
        # rules by quoting the very strings they ban.
        if line.lstrip().startswith("//"):
            continue
        if LABEL_PROP.search(line):
            body_left = LABEL_PROP_LINES
        in_label = LABEL_ARG.search(line) or body_left > 0
        if body_left > 0:
            body_left -= 1
        seen = set()
        source = ANY_LITERAL if in_label else DISPLAY
        for m in source.finditer(line):
            literal = m.group(1)
            if in_label and COMPARED.search(line[:m.start()]):
                continue
            if literal in seen:
                continue
            seen.add(literal)
            if shouts(literal):
                yield n, literal


def run() -> int:
    findings = []
    scanned = 0
    for root in SOURCES:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.swift")):
            scanned += 1
            text = path.read_text(encoding="utf-8")
            for n, literal in scan_text(text):
                findings.append((path.relative_to(ROOT), n, literal))
    if findings:
        for path, n, literal in findings:
            print(f"  {path}:{n}: {literal!r} is set in ALL CAPS")
        print()
        print(f"allcaps-audit: FAILED — {len(findings)} display string(s) shout.")
        print("  build-brief §8: headers are words in sentence case. Re-case the")
        print("  label, or — if it is an initialism rather than emphasis — add it")
        print("  to KNOWN_ACRONYMS with the reason.")
        return 1
    print(f"✓ allcaps audit: {scanned} files, no display string is set in ALL CAPS")
    return 0


def self_test() -> int:
    """A check that cannot fail proves nothing."""
    cases = [
        # (literal, shouts?, why)
        ("WATCH", True, "the bare shouting verb this was written for"),
        ("NEEDS YOU", True, "two words, both capitals"),
        ("Watch", False, "sentence case is the whole point"),
        ("Standing · now", False, "a separator does not make it shout"),
        ("Add all", False, "the re-cased two-word label"),
        # Initialisms the app is RIGHT to print.
        ("ID", False, "under the 3-letter floor, so no exemption needed"),
        ("P2SH", False, "its longest word is SH — two letters"),
        ("Your Cloudflare API token has expired", False,
         "a sentence carrying an acronym has lowercase in it"),
        ("Export as OPML", False, "same, with the acronym trailing"),
        # The word-level exemption, proven in BOTH directions — an exemption
        # that cannot fail is a snooze wearing a registry's clothes.
        (r"\(total) ETH", False, "a ticker beside its figure — the exempted word"),
        ("ETH BALANCE", True, "the ticker is exempt; the word shouting beside it is not"),
        ("BTC", True, "a ticker nobody has ruled on is still a finding"),
        # Interpolations carry identifiers, not display text.
        ("Signed in on \\(DS.device)", False,
         "DS is a type name, not a word on screen"),
        ("\\(WalletIngest.format(x)) ETH is ready", False,
         "the readable half is lowercase"),
        ("\\(DS.device)", False, "nothing but an interpolation"),
        ("", False, "no letters at all"),
        ("2026", False, "digits are not shouting"),
        ("· — ·", False, "punctuation only"),
    ]
    failures = 0
    for literal, want, why in cases:
        got = shouts(literal)
        ok = got == want
        failures += not ok
        print(f"  {'✓' if ok else '✗'} {literal!r} → {got} ({why})")

    # The extraction half: it must SEE a bare-String label and must NOT see a
    # commented-out one — this file's own neighbours quote what they ban.
    src = '\n'.join([
        'DSSlabField(placeholder: String(localized: "Name or link"),',
        '            actionLabel: String(localized: "WATCH"),',
        '            secondaryLabel: "NAME")',
        'Text("SAVE")',
        '// Text("FOLLOW") — the old spelling, named so the rule is legible',
        'let method = "POST"   // not a display literal at all',
        # The ternary and the helper — the two shapes the first cut missed.
        'actionLabel: checking ? "CHECKING…" : (configured ? "UPDATE" : "CONNECT"),',
        'private var omniButtonLabel: String {',
        '    if bridge.supportsMultiple { return "ADD" }',
        '    return "Connect"',
        '}',
    ])
    found = sorted(lit for _, lit in scan_text(src))
    want_found = ["ADD", "CHECKING…", "CONNECT", "NAME", "SAVE", "UPDATE", "WATCH"]
    ok = found == want_found
    failures += not ok
    print(f"  {'✓' if ok else '✗'} extraction found {found} (want {want_found})")

    # And it must find nothing in a clean file.
    clean = '\n'.join([
        'Text("Save")',
        'actionLabel: String(localized: "Watch")',
        'actionLabel: checking ? "Checking…" : "Connect",',
        # A label position must not report the non-display literals beside it:
        # a symbol, a currency code and an enum raw value all live on these
        # lines legitimately, and reporting them is how this becomes the lint
        # that cries wolf.
        'actionLabel: symbol == "ETH" ? "Watch" : "Add",',
    ])
    ok = list(scan_text(clean)) == []
    failures += not ok
    print(f"  {'✓' if ok else '✗'} a re-cased file yields no findings")

    if failures:
        print(f"\nallcaps-audit self-test: {failures} FAILED")
        return 1
    print("\nallcaps-audit self-test: OK")
    return 0


if __name__ == "__main__":
    sys.exit(self_test() if "--self-test" in sys.argv else run())
