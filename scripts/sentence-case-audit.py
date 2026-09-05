#!/usr/bin/env python3
"""No display LABEL is set in Title Case (build-brief §8, prd §453).

§8's rule is "headers are sentence case", and until 2026-09-01 only half of it
was mechanical: `allcaps-audit.py` catches a label that SHOUTS, and nothing
caught the far commoner drift — a label that Title Cases every word. The two
failures are the same failure at different volumes, and this one is quieter, so
it spreads further before anyone notices.

**What it had already cost, measured on the tree the day this landed.** The
address book's screen title read "Address Book" — the ONE Title Case entry among
sixty-one `dsScreenTitle` calls, every other one of which is either a brand name
or sentence case. Beside it, "Copy Address" and "Move to Front" sat in context
menus whose siblings read "Copy all as text", "Remove from book" and "Rename
group". Worst of all, BOTH casings were live at once: `Localizable.xcstrings`
carried "Address Book" AND "Address book" as separate keys, each translated into
four languages, because a drifted label does not collide with its twin — it
quietly doubles it, and the translator bills for both.

**Why this is mechanical rather than remembered.** A Title Cased label renders
perfectly. It survives the build, every screen sweep, the design-ramp audit
(which reads type SIZES, not the letters in them), the allcaps audit (whose test
is on the WHOLE literal, so "Address Book" has lowercase in it and is invisible
there) and every `swiftc` harness. Nothing about it is wrong except that it is
against the house style — and this repo's own history is that a house style with
no check drifts one label at a time, each one justified by the last.

**The rule, and why it is spelled this narrowly.** A finding is a LABEL-shaped
display literal — 2 to `MAX_WORDS` words, carrying no sentence punctuation —
with a non-first word that is capitalized and is not a proper noun. Every part
of that narrowing is MEASURED, not guessed:

  * **Label-shaped, not prose.** Running the same test over sentences reports
    ~200 literals on a healthy tree, essentially all of them a legitimate
    mid-sentence proper noun or a second sentence's first word. Prose is where
    capitals are supposed to appear; a label is where they are not.
  * **Sentence punctuation disqualifies.** A literal carrying `.`/`!`/`?` is
    prose by its own punctuation, whatever its length.
  * **The first word is never judged.** A label starts with a capital by
    definition; Title Case is a claim about the words AFTER it.
  * **`MAX_WORDS`.** Past it a literal is a sentence missing its full stop, and
    judging those is what turns this into the lint that cries wolf.

**The proper-noun lexicon is DERIVED first, hand-listed second.** Every word in
`BridgeCatalog.offers` is a proper noun by construction, so a new seat is
covered the day it lands and needs no entry here — which matters, because the
catalog is the list this repo grows fastest. `KNOWN_PROPER` is for the rest, and
an entry is a conscious "this word names a thing, and lowercasing it would
invent a spelling its owner does not use."

**What it deliberately does NOT check**, so it cannot become the lint it warns
about:

  * **The macOS menu bar** (`MENU_BAR`). Apple's HIG specifies title-style
    capitalization for menu items, and Casberi's commands render directly
    beneath Apple's own File/Edit/View/Window/Help. That menu is INTERNALLY
    CONSISTENT in Title Case today, which is the tell that it is a convention
    rather than drift — drift is one Title Case label among sixty sentence-case
    ones, which is exactly what this found everywhere else.
  * **Generated third-party directories.** `L2beatDirectory`/
    `WalletbeatDirectory` are `DO NOT EDIT BY HAND` snapshots of somebody
    else's names and incident titles. Re-casing them would be editing a
    quotation, and the next regeneration would revert it anyway.
  * **The demo corpus.** Its titles stand in for real-world content — a
    security disclosure, a Hacker News post — and those really are Title Cased
    in the world. A demo that renders them in sentence case is a demo that
    misrepresents what the feed will hold.
  * **Prose, ALL CAPS, and `.uppercased()`** — the first is not this rule's
    business, and the other two are `allcaps-audit.py`'s.
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

# The macOS menu bar. Apple's convention, not our drift — see the docstring.
MENU_BAR = {"Casberi/Casberi/CasberiApp.swift"}

# `DO NOT EDIT BY HAND` snapshots of a third party's own names, and the demo
# fixtures that stand in for real-world content.
QUOTED_CONTENT = {
    "Casberi/Casberi/Model/L2beatDirectory.swift",
    "Casberi/Casberi/Model/WalletbeatDirectory.swift",
    "Casberi/Casberi/Model/DemoCorpus.swift",
    "Casberi/Casberi/Model/DemoSeedAll.swift",
    "Casberi/Casberi/Model/PredictionDemoBook.swift",
}

EXEMPT_FILES = MENU_BAR | QUOTED_CONTENT

# Where a display string is written. `dsScreenTitle` is this app's own header
# modifier and is named explicitly because it takes a bare `String` — which is
# how "Address Book" sat as the one Title Case screen title in the tree.
DISPLAY = re.compile(
    r'(?:Text|String\(localized:|Label|Button|\.dsScreenTitle|\.navigationTitle'
    r'|LocalizedStringResource\s*=|IntentDescription)'
    r'\s*\(?\s*=?\s*"((?:[^"\\]|\\.)*)"'
)

# A LABEL POSITION: every literal on the line is display text. Mirrors
# `allcaps-audit.py`'s second pass, and for its reason — a label is routinely a
# ternary or a labelled argument, where a regex anchored to one keyword sees the
# first arm and nothing else.
LABEL_ARG = re.compile(
    r'\b(?:title|label|header|eyebrow|subtitle|heading|verb|actionLabel'
    r'|secondaryLabel|placeholder|footer|caption)\s*:'
)
ANY_LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')

# A Swift property/parameter DECLARATION — `let title: String`, `var label: X`.
# The name matches `LABEL_ARG`, but nothing on the line is display text.
DECLARATION = re.compile(r'^\s*(?:@\w+\s+)*(?:private\s+|static\s+)*(?:let|var|case)\s')

# On a label line a literal is display text UNLESS it is being COMPARED — the
# `allcaps-audit.py` lesson: reporting the thing being tested is how this
# becomes the lint that cries wolf.
COMPARED = re.compile(
    r"""(?:[=!~]=|\b(?:contains|hasPrefix|hasSuffix|starts)\s*\(\s*(?:with:\s*)?)\s*$"""
)

# A word may carry digits INSIDE it, so `L2BEAT`, `P2SH` and `x402` are one word
# rather than a letter and a shout. Splitting them was this file's own first bug.
WORD = re.compile(r"[A-Za-z][A-Za-z0-9]*(?:'[A-Za-z]+)?")

# A Swift unicode escape is a CHARACTER, not two words. DECODED rather than
# stripped, because the commonest one in this tree is `\u{00B7}` — the `·` that
# separates two phrases — so stripping it would silently join them and report
# the second phrase's first word. Found on this file's own first real run,
# which read `Hegotá \u{00B7} devnet` as Title Casing "B7".
UNICODE_ESCAPE = re.compile(r'\\u\{([0-9A-Fa-f]{1,8})\}')

# A Swift interpolation, matched GREEDILY to the last `)` and, failing that,
# from `\(` to end of string: `\(String(format: x))` NESTS, so a non-greedy
# `[^)]*` stops inside it and reports the type name as a Title Cased word —
# and a literal cut mid-expression by the line scan has no closing paren at all.
INTERPOLATION = re.compile(r'\\\(.*\)')
UNTERMINATED = re.compile(r'\\\(.*$')
FORMAT_SPEC = re.compile(r'%(?:\d+\$)?[@a-zA-Z]+')

# Prose punctuation. A literal carrying any of these is a sentence, not a label.
PROSE = re.compile(r'[.!?\n]')

# A SEGMENT separator. A label routinely carries several phrases at once —
# "Not watched · Watch it", "Settings → Advanced → Export Telegram data" — and
# each phrase begins a fresh label, so its own first word is capitalized by the
# same right the literal's first word has. Without this the second phrase's
# verb is reported every time.
SEGMENT = re.compile(r'\s*(?:·|—|–|→|\||>|,|;|:|\(|\)|\[|\]|/)\s*')

# A single capital letter is an INITIAL, a curve name (`P-256`), a grade
# ("A to E") or an axis label — never evidence of Title Case. Requiring two
# letters retires a fistful of one-letter lexicon entries that would each
# otherwise have had to be argued for.
MIN_WORD = 2

# Past this a literal is a sentence missing its full stop.
MAX_WORDS = 8

# A conscious ruling per entry: "this NAMES something, and lowercasing it would
# invent a spelling its owner does not use." Words already in
# `BridgeCatalog.offers` are derived at run time and need no entry here.
#
# PHRASES COME FIRST, and the split is load-bearing rather than tidy. A
# word-level exemption is blunt: `Address` had to be exempted so that "Add to
# Address book" — where it opens the SCREEN'S NAME — reads clean, and that one
# entry immediately made "Copy Address" invisible, which is the very finding
# this audit was written for. Mutation caught it; nothing else would have.
# So a word whose capital is earned only IN A PHRASE is exempted as that
# phrase, and stands alone as a finding everywhere else.
KNOWN_PHRASES: tuple[str, ...] = (
    # An in-app surface name. "Copy Address" is still a finding.
    "Address book",
    # Apple's own feature names — lowercasing these renames Apple's feature.
    "Secure Enclave", "Face ID", "Touch ID", "Advanced Data Protection",
    "Private Relay", "Camera Uploads",
    # NOT "Reading List". Safari capitalises it, but this app's own house
    # spelling is "Reading list" (`ShapedRows` draws it, and the sibling picker
    # row reads "All bookmarks") — exempting Apple's casing here would make the
    # re-cased label impossible to regress-catch. Mutation found this one too.
    # A third party's OWN field and permission names, printed so somebody can
    # find the control in that product's UI. Re-casing makes the instruction
    # wrong. Exempted as phrases so `Key`, `Access` and `View` stay findings
    # on their own.
    "Access Key ID", "Secret Access Key", "Key ID", "Issuer ID",
    "Daily Papers", "Power-Up", "Telegram Desktop", "Proving System",
    # Hugging Face capitalises "Space" — it is a product name there, not a
    # common noun, and `HuggingFaceBridge.noun` carries that ruling in a
    # comment. Exempted as the phrase so a bare "Space" stays a finding.
    "new Space",
    "Security Council", "My Clippings", "Entries folder",
    # Proper nouns that happen to be two ordinary words.
    "Kansas City", "Apple Inc", "Smart Chain", "Nutri-Score",
    # The two .wei/.gwei registries' own names (prd §597). `serviceName` is the
    # copy with room to be explicit, so it prints the owner's spelling.
    # Exempted as PHRASES so `Name` and `Service` — two of the most ordinary
    # words this app has — stay findings everywhere else.
    "Wei Name Service", "Gwei Name Service",
)

KNOWN_PROPER: set[str] = {
    # Protocols, chains and companies with no catalog seat of their own.
    "Morpho", "Uniswap", "Aave", "Spark", "Hyperliquid", "Aerodrome",
    "Bitcoin", "Ethereum", "Solana", "Base", "Optimism", "Polygon", "Arbitrum",
    "Gnosis", "Monad", "Robinhood", "HyperEVM", "Etherscan", "Solscan",
    "Ethrex", "Reown", "WalletConnect", "Visa", "Metamask", "Delegator",
    "Rabby", "SafePal", "Trezor", "Raycast", "Takeout", "SteamID", "Venmo",
    "BNB", "SegWit", "MyActivity", "AuthKey", "Siri", "Mac", "Safari",
    "Spotlight", "Keychain",
    # In-app surfaces referenced by name — the chips and screens a sentence
    # points at ("add one from Apps", "washes the top of All").
    "All", "Apps", "Pinned", "Home", "Settings",
    # Facet tags (§308) — naming a tag, not describing an action.
    "Release", "Review",
    # Weekday and month abbreviations: a date stamp, not a shout.
    "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun",
    "Jan", "Feb", "Mar", "Apr", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    # Initialisms. Under the WORD rule these are single words, so one entry
    # covers every phrase they appear in.
    "ID", "API", "URL", "URI", "JSON", "XML", "HTML", "CSV", "TSV", "RSS",
    "OPML", "MCP", "DNS", "IAM", "HTTP", "HTTPS", "TLS", "NFT", "NFTs",
    "UTXO", "UTXOs", "EIP", "ERC", "RPC", "ENS", "CDN", "PDF", "OCR", "AI",
    "UI", "UX", "CLI", "SDK", "JWT", "OAuth", "PKCE", "SIWE", "US", "UK",
    "EU", "EEA", "UTC", "IP", "VPN", "SSH", "P2SH", "OVM", "PoS", "PRT",
    "L2", "TXT", "IMAP", "AM", "PM", "BEGIN", "END", "AKIA", "Bearer",
    # Tickers. Re-casing one invents a spelling no exchange or explorer uses.
    "ETH", "BTC", "SOL", "USDC", "USDT", "DAI", "HYPE", "AERO", "AAPL",
    "NASA", "COLOR", "ALARM",
}


def catalog_proper_nouns() -> set[str]:
    """Every word of every catalog offer name is a proper noun by construction.

    DERIVED rather than listed so a new seat is covered the day it lands — the
    `mac-parity-audit.py` ruling, in the registry this repo grows fastest.
    """
    path = ROOT / "Casberi/Casberi/Model/BridgeCatalog.swift"
    if not path.exists():
        return set()
    text = path.read_text(encoding="utf-8")
    words: set[str] = set()
    for m in re.finditer(r'name: "([^"]+)"', text):
        words.update(WORD.findall(m.group(1)))
    return words


def _bare(word: str) -> str:
    return word[:-2] if word.endswith("'s") else word


def _normalise(literal: str) -> str:
    """Decode escapes, and blank out everything that is code rather than words."""
    def _decode(m):
        try:
            return chr(int(m.group(1), 16))
        except (ValueError, OverflowError):
            return " "
    text = UNICODE_ESCAPE.sub(_decode, literal)
    text = INTERPOLATION.sub(" · ", text)
    text = UNTERMINATED.sub(" ", text)
    return FORMAT_SPEC.sub(" ", text)


def _strip_phrases(text: str) -> str:
    """Blank out known proper PHRASES so only their context is judged.

    Longest first, so "Access Key ID" is spent before "Key ID" can claim part
    of it. Case-SENSITIVE: the point is that these words earn their capitals
    here and nowhere else.
    """
    for phrase in sorted(KNOWN_PHRASES, key=len, reverse=True):
        text = text.replace(phrase, " ")
    return text


def title_cased(literal: str, proper: set[str]) -> list[str]:
    """The capitalized non-first words this literal cannot account for."""
    text = _strip_phrases(_normalise(literal))
    if PROSE.search(text):
        return []
    if not 2 <= len(WORD.findall(text)) <= MAX_WORDS:
        return []
    found: list[str] = []
    for segment in SEGMENT.split(text):
        words = WORD.findall(segment)
        # The first word of each segment is capitalized by definition; Title
        # Case is a claim about the words AFTER it.
        for w in words[1:]:
            if not w[0].isupper() or len(w) < MIN_WORD:
                continue
            if w in proper or _bare(w) in proper:
                continue
            found.append(w)
    return found


def _strip_trailing_comment(line: str) -> str:
    """Drop a trailing `//` comment, QUOTE-AWARE.

    A blind `//` cut lands inside `"https://…"`; this walks the line tracking
    string state so only a `//` outside a literal ends it.
    """
    in_string = False
    i = 0
    while i < len(line):
        c = line[i]
        if c == "\\" and in_string:
            i += 2
            continue
        if c == '"':
            in_string = not in_string
        elif not in_string and c == "/" and line[i + 1:i + 2] == "/":
            return line[:i]
        i += 1
    return line


def scan_text(text: str, proper: set[str]):
    """Yield (line number, literal, unexplained capitals)."""
    for n, line in enumerate(text.splitlines(), 1):
        # Whole-line comments only. A trailing `//` strip would cut inside a
        # `"https://…"` literal, and this file's neighbours document their
        # rules by quoting the very strings they ban.
        if line.lstrip().startswith("//"):
            continue
        line = _strip_trailing_comment(line)
        # `let title: String` is a DECLARATION, not a label position. Without
        # this, `LABEL_ARG` matches the property name and every literal on the
        # line — including one in a trailing `// e.g. "Kansas City"` comment —
        # is read as display text. Two of this file's first-run findings.
        in_label = bool(LABEL_ARG.search(line)) and not DECLARATION.search(line)
        source = ANY_LITERAL if in_label else DISPLAY
        seen = set()
        for m in source.finditer(line):
            literal = m.group(1)
            if in_label and COMPARED.search(line[:m.start()]):
                continue
            if literal in seen:
                continue
            seen.add(literal)
            caps = title_cased(literal, proper)
            if caps:
                yield n, literal, caps


def run() -> int:
    proper = catalog_proper_nouns() | KNOWN_PROPER | {"Casberi"}
    findings = []
    scanned = 0
    for root in SOURCES:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.swift")):
            rel = str(path.relative_to(ROOT))
            if rel in EXEMPT_FILES:
                continue
            scanned += 1
            for n, literal, caps in scan_text(path.read_text(encoding="utf-8"), proper):
                findings.append((rel, n, literal, caps))
    if findings:
        for rel, n, literal, caps in findings:
            print(f"  {rel}:{n}: {literal!r} is Title Case ({', '.join(caps)})")
        print()
        print(f"sentence-case-audit: FAILED — {len(findings)} label(s) in Title Case.")
        print("  build-brief §8: headers are sentence case. Lowercase the word — or,")
        print("  if it NAMES something (a product, a third party's own field, an")
        print("  in-app surface), add it to KNOWN_PROPER with the reason.")
        print("  Renaming a shipped label? Carry its translations across in")
        print("  Localizable.xcstrings, or the old key is orphaned and paid for twice.")
        return 1
    print(f"✓ sentence-case audit: {scanned} files, no display label is Title Case")
    return 0


def self_test() -> int:
    """A check that cannot fail proves nothing."""
    # A stand-in for the shipped lexicon, holding only the words these cases
    # turn on. Every one of them is really in `KNOWN_PROPER` or derived from the
    # catalog — a fixture lexicon that is MISSING a word tests the lexicon
    # rather than the rule, which is how this file's own first run reported two
    # correct labels as findings.
    proper = {"Casberi", "Apple", "Wallet", "Safe", "ID", "All", "Apps",
              "Release", "ETH"}
    cases = [
        # (literal, is a finding?, why)
        ("Address Book", True, "the screen title this was written for"),
        ("Copy Address", True, "the context-menu verb beside 'Copy all as text'"),
        ("Move to Front", True, "a swipe action beside 'Remove from book'"),
        ("See in Feed", True, "'feed' is a common noun — the sibling is 'Open in app'"),
        ("Getting Started", True, "the classic drift §8 names"),
        # The PHRASE-vs-WORD split, proven in BOTH directions. An exemption
        # that cannot fail is a snooze wearing a registry's clothes — and the
        # word-level version of this pair really did swallow "Copy Address",
        # caught by mutation and by nothing else.
        ("Add to Address book", False, "'Address book' is the screen's own name"),
        ("Full Address book", False, "same phrase, different verb"),
        ("Copy Address", True, "the SAME word, standing alone, is still a finding"),
        ("Reading list only", False, "the re-cased picker row"),
        ("Access Key ID (AKIA…)", False, "AWS's own field name, as a phrase"),
        ("Give it View access", True, "'View' alone is not exempt"),
        # Sentence case is the whole point.
        ("Address book", False, "the house spelling"),
        ("Copy all as text", False, "the sibling that stayed correct"),
        ("Move to front", False, "the re-cased action"),
        ("Watch a wallet", False, "an ordinary sentence-case label"),
        # Proper nouns must not be findings, or the lint cries wolf.
        ("Apple Wallet", False, "a catalog seat name, derived not listed"),
        ("Open in Safe", False, "a brand name trailing a verb"),
        ("Add to Casberi", False, "our own name"),
        ("Show Release", False, "'Release' names a §308 facet tag"),
        ("Scope to All wallets", False, "'All' is the chip's name"),
        # Prose is not this rule's business — that is where capitals belong.
        ("They appeared in a transfer. You have not named them.", False,
         "a second sentence's first word is not Title Case"),
        ("Your key was turned down — check it in Settings.", False,
         "punctuation makes it prose"),
        ("Reading needs no key. Sending signs with a key held here.", False,
         "two sentences, both correct"),
        # Shape guards.
        ("Watch", False, "one word cannot be Title Case"),
        ("", False, "no words at all"),
        ("2026", False, "digits are not words"),
        ("A B C D E F G H I J", False, "past MAX_WORDS it is prose"),
        # An interpolation carries an IDENTIFIER, not display text — reading it
        # as content is how `\(String(format:))` reports as a finding.
        (r"Health \(String(format: x))", False, "the interpolation is code"),
        (r"\(provider.company) reports a problem", False, "same, leading"),
        ("Balance %@ ETH", False, "a ticker, and a format specifier"),
    ]
    failures = 0
    for literal, want, why in cases:
        got = bool(title_cased(literal, proper))
        ok = got == want
        failures += not ok
        print(f"  {'✓' if ok else '✗'} {literal[:52]!r} → {got} ({why})")

    # The EXTRACTION half. It must SEE a bare-String header modifier and a
    # labelled argument, and must NOT see a comparison — the three shapes that
    # decide whether the rule above is ever reached.
    extraction = [
        ('    .dsScreenTitle("Address Book")', 1, "the bare-String header modifier"),
        ('  Label("Copy Address", systemImage: "doc.on.doc")', 1, "a Label verb"),
        ('  Text("Move to Front")', 1, "a plain Text label"),
        ('  static let title: LocalizedStringResource = "Open Thing"', 1,
         "an App Intent title"),
        ('  title: checking ? "Getting Started" : "Address Book"', 2,
         "BOTH arms of a ternary in a label position"),
        ('  if source == "Apple Wallet" { }', 0,
         "a COMPARISON is not display text"),
        ('    // .dsScreenTitle("Address Book") is the old spelling', 0,
         "a whole-line comment is prose about the rule"),
        ('  let ref = "gh:event:Foo Bar"', 0,
         "a ref string is not in a display position"),
    ]
    for line, want, why in extraction:
        got = len(list(scan_text(line, proper)))
        ok = got == want
        failures += not ok
        print(f"  {'✓' if ok else '✗'} extract {line.strip()[:48]!r} → {got}, want {want} ({why})")

    # The lexicon must really be DERIVED, or a new seat needs a hand entry and
    # this becomes the registry that goes stale.
    derived = catalog_proper_nouns()
    for word in ("Dropbox", "Obsidian", "Stripe"):
        ok = word in derived
        failures += not ok
        print(f"  {'✓' if ok else '✗'} {word!r} derived from BridgeCatalog ({ok})")

    print()
    if failures:
        print(f"sentence-case-audit --self-test: FAILED ({failures})")
        return 1
    print(f"sentence-case-audit --self-test: {len(cases) + len(extraction) + 3} checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(self_test() if "--self-test" in sys.argv else run())
