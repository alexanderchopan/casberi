#!/usr/bin/env python3
"""Harness for the credential tripwire (prd §276).

WHAT THIS PROVES, AND WHAT IT DOESN'T.

Proves: the regexes, thresholds and wordlist that ship in
`Model/SecretScan.swift` + `Model/SecretScanWordlist.swift` classify a set of
fixtures the way the design says they do — and that they still fail when a
threshold is moved (the mutation pass at the end). Everything it tests is READ
OUT OF THE SHIPPED SOURCE, never copied here, so a pattern edited in Swift is
the pattern tested.

Doesn't prove: that the Swift compiles or that its control flow matches. This
harness MIRRORS the algorithm (the run scan, Luhn, the issuer-prefix table) in
Python, because there is no Swift toolchain on the authoring host. Python's
`re` and ICU agree on every construct used here (inline `(?i)`, `\\b`, `\\d`,
`\\S`, bounded and lazy quantifiers), but that agreement is an assumption, not
a measurement. Re-run the in-app `-secretScanProbe` on a simulator before
trusting a change to this detector.

Usage:  scripts/secret-scan-selftest.py [--verbose]
Exit 0 = every fixture classified as designed and the mutation pass failed.
"""

import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCAN = ROOT / "Casberi/Casberi/Model/SecretScan.swift"
WORDS = ROOT / "Casberi/Casberi/Model/SecretScanWordlist.swift"

VERBOSE = "--verbose" in sys.argv
failures = []


def check(name, got, want):
    if got == want:
        if VERBOSE:
            print(f"  ok   {name}")
    else:
        failures.append(f"{name}: got {got!r}, want {want!r}")
        print(f"  FAIL {name}: got {got!r}, want {want!r}")


# ── Extraction ──────────────────────────────────────────────────────────────

def swift_source(path):
    if not path.exists():
        sys.exit(f"missing {path} — the harness tests the SHIPPED source, so this is fatal")
    return path.read_text()


def unescape(literal):
    """Swift string-literal body -> the characters it denotes."""
    out, i = [], 0
    simple = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\", "0": "\0"}
    while i < len(literal):
        c = literal[i]
        if c == "\\" and i + 1 < len(literal):
            nxt = literal[i + 1]
            if nxt in simple:
                out.append(simple[nxt])
                i += 2
                continue
        out.append(c)
        i += 1
    return "".join(out)


LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')


def extract_pattern(src, name):
    """Read `static let <name> = "…" + "…"` however it is line-wrapped."""
    start = re.search(rf"static let {name}\s*=", src)
    if not start:
        sys.exit(f"couldn't find `static let {name}` in SecretScan.swift")
    rest = src[start.end():]
    pieces, consumed = [], 0
    for line in rest.splitlines(keepends=True):
        stripped = line.strip()
        if consumed and not (stripped.startswith('"') or stripped.startswith('+')):
            break
        found = LITERAL.findall(line)
        if not found and consumed:
            break
        pieces += found
        consumed += 1
        if consumed > 40:
            break
    if not pieces:
        sys.exit(f"found `{name}` but no string literal after it")
    return "".join(unescape(p) for p in pieces)


def extract_int(src, name):
    m = re.search(rf"static let {name}\s*=\s*(-?\d+)", src)
    if not m:
        sys.exit(f"couldn't read `{name}` out of SecretScan.swift")
    return int(m.group(1))


def extract_double(src, name):
    m = re.search(rf"static let {name}\s*=\s*([0-9.]+)", src)
    if not m:
        sys.exit(f"couldn't read `{name}` out of SecretScan.swift")
    return float(m.group(1))


def extract_int_set(src, name):
    m = re.search(rf"static let {name}:\s*Set<Int>\s*=\s*\[([^\]]*)\]", src)
    if not m:
        sys.exit(f"couldn't read `{name}` out of SecretScan.swift")
    return {int(x) for x in re.findall(r"\d+", m.group(1))}


def extract_wordlist(src):
    m = re.search(r'private static let raw = """\n(.*?)\n\s*"""', src, re.S)
    if not m:
        sys.exit("couldn't read the wordlist literal out of SecretScanWordlist.swift")
    return set(m.group(1).split())


scan_src = swift_source(SCAN)
words_src = swift_source(WORDS)

PATTERNS = {k: extract_pattern(scan_src, k) for k in (
    "apiKeyPattern", "passwordPattern", "cardCandidatePattern",
    "oneTimeCodePattern", "phraseContextPattern", "wordPattern")}
RUN_FLOOR = extract_int(scan_src, "phraseRunFloor")
DENSITY_FLOOR = extract_double(scan_src, "phraseDensityFloor")
PHRASE_LENGTHS = extract_int_set(scan_src, "phraseLengths")
WORDLIST = extract_wordlist(words_src)

COMPILED = {}
for name, pattern in PATTERNS.items():
    try:
        COMPILED[name] = re.compile(pattern)
    except re.error as exc:
        sys.exit(f"{name} does not compile as a regex: {exc}\n  {pattern}")


# ── Mirrored algorithm (see the caveat at the top) ──────────────────────────

def luhn(digits):
    total, double = 0, False
    for ch in reversed(digits):
        v = int(ch)
        if double:
            v *= 2
            if v > 9:
                v -= 9
        total += v
        double = not double
    return total % 10 == 0


def issuer_prefix(digits):
    if len(digits) < 4:
        return False
    one, two, four = digits[0], int(digits[:2]), int(digits[:4])
    return (one == "4" or 51 <= two <= 55 or 22 <= two <= 27
            or two in (34, 37, 35, 65) or four == 6011)


def card_spans(text):
    out = []
    for m in COMPILED["cardCandidatePattern"].finditer(text):
        s, e = m.span()
        if s > 0 and text[s - 1].isdigit():
            continue
        if e < len(text) and text[e].isdigit():
            continue
        digits = "".join(c for c in m.group(0) if c.isdigit())
        if not (13 <= len(digits) <= 19):
            continue
        if issuer_prefix(digits) and luhn(digits):
            out.append((s, e))
    return out


def phrase_span(text, run_floor=None, density_floor=None, lengths=None):
    run_floor = RUN_FLOOR if run_floor is None else run_floor
    density_floor = DENSITY_FLOOR if density_floor is None else density_floor
    lengths = PHRASE_LENGTHS if lengths is None else lengths

    words = list(COMPILED["wordPattern"].finditer(text))
    if len(words) < run_floor:
        return None
    best_start = best_len = run_start = run_len = 0
    for i, w in enumerate(words):
        if w.group(0).lower() in WORDLIST:
            if run_len == 0:
                run_start = i
            run_len += 1
            if run_len > best_len:
                best_len, best_start = run_len, run_start
        else:
            run_len = 0
    if best_len < run_floor:
        return None
    density = best_len / len(words)
    rule_a = best_len in lengths and density >= density_floor
    rule_b = COMPILED["phraseContextPattern"].search(text) is not None
    if not (rule_a or rule_b):
        return None
    return words[best_start].start(), words[best_start + best_len - 1].end()


def kinds_found(text, **kw):
    found = set()
    if COMPILED["apiKeyPattern"].search(text):
        found.add("apiKey")
    if COMPILED["passwordPattern"].search(text):
        found.add("password")
    if COMPILED["oneTimeCodePattern"].search(text):
        found.add("oneTimeCode")
    if card_spans(text):
        found.add("cardNumber")
    if phrase_span(text, **kw):
        found.add("recoveryPhrase")
    return found


# ── Fixtures ────────────────────────────────────────────────────────────────

BIP = sorted(WORDLIST)
FIRST12 = " ".join(BIP[:12])
FIRST24 = " ".join(BIP[:24])

SHOULD_FLAG = [
    ("phrase, pasted bare", FIRST12, "recoveryPhrase"),
    ("phrase, 24 words", FIRST24, "recoveryPhrase"),
    ("phrase, numbered", "Recovery phrase " + " ".join(
        f"{i + 1}. {w}" for i, w in enumerate(BIP[:12])), "recoveryPhrase"),
    ("phrase in wallet chrome",
     "Write down your secret recovery phrase and keep it safe. Never share it "
     "with anyone. " + FIRST12 + ". Confirm you have saved it.", "recoveryPhrase"),
    ("anthropic key", "key sk-ant-api03-AAAAAAAAAAAAAAAAAAAAAA live", "apiKey"),
    ("github token", "token ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "apiKey"),
    ("google key", "AIzaSyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "apiKey"),
    ("aws key id", "AKIAIOSFODNN7EXAMPLE1234", "apiKey"),
    ("password line", "Password: hunter2000", "password"),
    ("passcode with equals", "passcode = 90210xyz", "password"),
    ("visa, grouped", "card 4242 4242 4242 4242 exp 04/29", "cardNumber"),
    ("visa, solid", "4242424242424242", "cardNumber"),
    ("amex", "3782 822463 10005", "cardNumber"),
    ("verification code", "Your verification code is 481920", "oneTimeCode"),
    ("one-time code", "one-time code: 8172", "oneTimeCode"),
    ("code is, bare form", "Casberi code is 4821 — expires in 10 minutes", "oneTimeCode"),
    ("wifi password note", "wifi password: SunnyDay2026!", "password"),
]

SHOULD_NOT_FLAG = [
    ("ordinary note", "I need to make a note about the movie we saw last night, "
                      "it was really good and the ending was a surprise."),
    ("shopping list", "apple bread butter cheese coffee cream egg fish flour "
                      "fruit garlic ginger honey lemon melon milk olive onion "
                      "orange pepper potato rice salad salmon salt sugar tomato"),
    ("shopping list in app chrome",
     "Notes  Shopping list  apple bread butter cheese coffee cream egg fish "
     "flour fruit garlic ginger honey lemon melon milk olive onion orange "
     "pepper potato rice salad salmon salt sugar tomato  Edit  Share"),
    ("list of common verbs",
     "add ask begin bring call carry change close come cook cross decide draw "
     "drink drive enter exist expand explain"),
    ("animals", "cat dog horse tiger lion monkey rabbit turtle snake eagle owl "
                "fox wolf bear deer"),
    # The corpus this app actually holds — none of these may be redacted.
    ("transaction hash",
     "0x9f2c4a1b8e7d6c5f4a3b2c1d0e9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f"),
    ("ethereum address", "0xa5d1b4e2c3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8"),
    ("wei amount", "transferred 1000000000000000000 wei"),
    ("millisecond timestamp", "Created(microseconds) 1754140800000"),
    ("block number", "block 22153707 on mainnet"),
    ("order number", "Order #100048372910 shipped"),
    ("price and phone", "Total 1,299.00 — call 555 0134 to confirm"),
    ("pin word, no value", "pin: up"),
    # Rows this app's own bridges land, which must never be redacted.
    ("card last four on a receipt", "Netflix.com · $12.99 charged to card ending 4242"),
    ("stripe payout", "Payout of £1,204.50 paid to account ending 8891"),
    ("international phone", "call me on +44 7700 900123 tomorrow"),
    ("calendar entry", "Standup with Sam at 9:30, then dentist 2026-08-14 at 4:15"),
    ("social post", "gm everyone, shipping the new build today — feedback in /design"),
]


def run_fixtures():
    print("Fixtures — should flag")
    for name, text, expected in SHOULD_FLAG:
        check(name, expected in kinds_found(text), True)
    print("Fixtures — should NOT flag")
    for name, text in SHOULD_NOT_FLAG:
        check(name, sorted(kinds_found(text)), [])


def run_units():
    print("Units")
    check("luhn accepts a valid card", luhn("4242424242424242"), True)
    check("luhn rejects a bad digit", luhn("4242424242424243"), False)
    check("issuer rejects a timestamp", issuer_prefix("1754140800000"), False)
    check("issuer rejects round wei", issuer_prefix("1000000000000000000"), False)
    check("issuer accepts visa", issuer_prefix("4242424242424242"), True)
    check("wordlist is 2048 words", len(WORDLIST), 2048)
    check("wordlist has no stray tokens",
          all(w.isalpha() and w.islower() for w in WORDLIST), True)
    check("run floor is below every valid phrase length",
          RUN_FLOOR <= min(PHRASE_LENGTHS), True)
    # A redaction that ate the whole text would "pass" every should-flag
    # fixture, so assert the span is a span.
    span = phrase_span("Recovery phrase " + FIRST12)
    check("phrase span starts after its label", span is not None and span[0] > 0, True)


def run_mutations():
    """A check that cannot fail proves nothing. Move each threshold and
    assert a fixture flips — so the numbers in the Swift are load-bearing."""
    print("Mutations (each must break something)")
    shopping = SHOULD_NOT_FLAG[1][1]
    chrome = SHOULD_FLAG[3][1]

    # Drop the density floor -> the 12-word shopping list reads as a phrase.
    check("density floor is what rejects the shopping list",
          phrase_span(shopping, density_floor=0.0) is not None, True)
    # Confirm it is rejected at the shipped floor.
    check("shopping list rejected as shipped", phrase_span(shopping) is None, True)
    # Raise the run floor above every phrase length -> nothing is ever found.
    check("run floor is load-bearing",
          phrase_span(FIRST12, run_floor=99) is None, True)
    # Empty the valid-length set -> the bare phrase now needs rule B, which
    # a bare phrase has no context for.
    check("valid lengths are load-bearing",
          phrase_span(FIRST12, lengths=set()) is None, True)
    # ...but the chrome-wrapped phrase still passes on rule B alone.
    check("context rule stands alone",
          phrase_span(chrome, lengths=set()) is not None, True)


print(f"SecretScan self-test — {len(PATTERNS)} patterns, "
      f"{len(WORDLIST)} words, run>={RUN_FLOOR}, density>={DENSITY_FLOOR}, "
      f"lengths={sorted(PHRASE_LENGTHS)}")
run_units()
run_fixtures()
run_mutations()

if failures:
    print(f"\n✗ {len(failures)} failure(s)")
    sys.exit(1)
print("\n✓ secret-scan self-test passed")
