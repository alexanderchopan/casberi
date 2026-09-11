#!/usr/bin/env python3
"""THE CATALOGUE ROW'S VERB AND THE SETUP SCREEN'S MODE CHIP ARE ONE FACT
(prd §653, 2026-09-08).

`BridgeCatalog.Offer.mode` decides the word a dark catalogue row wears — Allow /
Sign in / Add key / Import / Connect — and every setup screen passes its own
`mode:` literal to `AccountPage` for the §315 chip. Two declarations of how a
seat connects, in two files, is the shape that drifts: the first life of this
table (`Offer.qualifier`) missed Instagram, Snapchat and TikTok when they
landed, and nothing said so because nothing read it. This holds the two in step.

Checks, all static:
  A. Every screen that hands `AccountPage` a LITERAL name and a LITERAL mode
     agrees with `Offer.mode` for that name.
  B. `TokenSetupScreen` covers every `TokenBridge` case: `.pasteKey`, except
     GitHub, which is `.signIn` (its device-flow id ships).
  C. `HandleSetupScreen` covers every `HandleBridge` case: `.noAccount`.
  D. Every name in the catalogue's five seat sets is a real offer (a renamed
     seat leaves a dead entry otherwise — the source-alias lesson).
  E. Nothing a screen declares is `nil` in the catalogue: a seat WITH a screen
     is never the one-tap case.
  F. Every connectable seat that needs setup is ASSERTED by something — a
     literal screen, an expression screen's `EXPRESSION_SEATS` entry, or the
     `TokenBridge`/`HandleBridge` sweeps. Without it the eight expression-named
     screens were merely "skipped, and said so", which left 14 seats resting on
     `Offer.mode`'s `.pasteKey` FALLBACK with nothing agreeing: add a keyless
     registry entry or a new devnet and its row says "Add key", silently. That
     is the first table's Instagram/Snapchat/TikTok failure one indirection
     over, so it gets a check rather than a sentence (prd §653 review).

`EXPRESSION_SEATS` is a second declaration and could itself drift, which is why
it is checked from BOTH ends: check D refuses a name that is not an offer, and
check F refuses an offer that no entry names. Rename a seat and both fire.

Usage: scripts/catalog-mode-audit.py [--self-test]
"""
import re, sys, os, tempfile, shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = "Casberi/Casberi/Model/BridgeCatalog.swift"
SCREENS = "Casberi/Casberi/Screens"
TOKENS = "Casberi/Casberi/Model/TokenBridges.swift"
HANDLES = "Casberi/Casberi/Screens/HandleSetupScreen.swift"

# The seats each EXPRESSION-NAMED screen draws — the ones whose `AccountPage`
# name is `venue.display`, `provider.source`, `registry.displayName` or an
# identity constant, so no regex can read them off the call. The screen's own
# `mode:` literal is still read from source; only WHICH seats it covers is
# stated here. `HandleSetupScreen` is absent on purpose: check C sweeps the
# whole `HandleBridge` enum, which is stronger than a list.
EXPRESSION_SEATS = {
    "ExchangeSetupScreen.swift": ["Binance", "Coinbase", "Kraken", "Gemini Exchange"],
    "FramesScreen.swift": ["Hegotá Frames"],
    "HegotaScreen.swift": ["Hegotá UTXO"],
    "MailScreen.swift": ["Gmail", "iCloud Mail"],
    "PackageWatchScreen.swift": ["npm", "PyPI"],
    "PrivacyDevnetScreen.swift": ["Hegotá Privacy"],
    "VibenetScreen.swift": ["Base Vibenet"],
}

SET_NAMES = {
    "signInSeats": "signIn", "importSeats": "oneTimeImport",
    "onDeviceSeats": "onThisDevice", "walletRidingSeats": "watchedWallets",
    "noAccountSeats": "noAccount",
}


def read(root, rel):
    with open(os.path.join(root, rel), encoding="utf-8") as f:
        return f.read()


def strip_comments(s):
    return re.sub(r"//[^\n]*", "", s)


def parse_offers(src):
    """name -> (connectable, needsSetup) from the Offer literals."""
    out = {}
    for m in re.finditer(r'Offer\(name: "([^"]+)"(.*?)\)\s*,\s*\n', strip_comments(src), re.S):
        body = m.group(2)
        out[m.group(1)] = ("connectable: true" in body, "needsSetup: true" in body)
    return out


def parse_sets(src):
    sets = {}
    for swift, mode in SET_NAMES.items():
        m = re.search(r"static let %s: Set<String> = \[(.*?)\]" % swift, src, re.S)
        if not m:
            raise SystemExit("✗ %s: no `%s` set" % (CATALOG, swift))
        sets[mode] = set(re.findall(r'"([^"]+)"', m.group(1)))
    return sets


def catalog_mode(name, offers, sets):
    """A re-statement of `Offer.mode`'s precedence. Keep in step by hand — it is
    five lines, and the audit's whole value is that it is a SECOND reading."""
    connectable, needs = offers[name]
    if not connectable or not needs:
        return None
    for mode in ("signIn", "oneTimeImport", "onThisDevice", "watchedWallets", "noAccount"):
        if name in sets[mode]:
            return mode
    return "pasteKey"


def screen_declarations(root):
    """(file, name, mode) for every AccountPage( call.

    A literal name is read off the call. An expression name is resolved through
    `EXPRESSION_SEATS`, so those screens are CHECKED rather than skipped; a file
    with neither is returned in `unresolved` and reported."""
    found, unresolved = [], []
    for fn in sorted(os.listdir(os.path.join(root, SCREENS))):
        if not fn.endswith(".swift"):
            continue
        src = strip_comments(read(root, os.path.join(SCREENS, fn)))
        for m in re.finditer(r"AccountPage\(", src):
            window = src[m.end():m.end() + 1200]
            name = re.match(r"\s*name: \"([^\"]+)\"", window)
            mode = re.search(r"\bmode: \.(\w+)", window)
            if not mode:
                continue
            if name:
                found.append((fn, name.group(1), mode.group(1)))
            elif fn in EXPRESSION_SEATS:
                for seat in EXPRESSION_SEATS[fn]:
                    found.append((fn, seat, mode.group(1)))
            elif fn == os.path.basename(HANDLES):
                pass  # check C sweeps the whole enum, which is stronger
            else:
                unresolved.append(fn)
    return found, sorted(set(unresolved))


def enum_names(src, enum):
    m = re.search(r"enum %s: String[^{]*\{(.*?)\n\}" % enum, src, re.S)
    if not m:
        raise SystemExit("✗ no `enum %s`" % enum)
    return re.findall(r'case \w+\s*=\s*"([^"]+)"', m.group(1))


def run(root):
    problems = []
    cat = read(root, CATALOG)
    offers = parse_offers(cat)
    sets = parse_sets(cat)

    # D. Every set entry is an offer — and so is every seat an expression
    #    screen's entry claims, since that table is a second declaration too.
    for mode, names in sets.items():
        for n in sorted(names):
            if n not in offers:
                problems.append("D  `%s` is in the %s set and is not an offer" % (n, mode))
    for fn, names in sorted(EXPRESSION_SEATS.items()):
        for n in names:
            if n not in offers:
                problems.append("D  `%s` is named for %s in EXPRESSION_SEATS and is not an offer" % (n, fn))

    # A / E. Every screen whose seats can be resolved.
    found, unresolved = screen_declarations(root)
    for fn in unresolved:
        problems.append("F  %s names its seat with an expression and has no EXPRESSION_SEATS entry" % fn)
    for fn, name, mode in found:
        if name not in offers:
            continue  # a sheet/room the catalogue does not list (audited elsewhere)
        want = catalog_mode(name, offers, sets)
        if want is None:
            problems.append("E  %s declares `%s` as .%s but the catalogue says one-tap (mode nil)" % (fn, name, mode))
        elif want != mode:
            problems.append("A  %s: `%s` screen says .%s, catalogue says .%s" % (fn, name, mode, want))

    # B. TokenBridge seats.
    for n in enum_names(read(root, TOKENS), "TokenBridge"):
        if n not in offers:
            continue
        want = catalog_mode(n, offers, sets)
        expect = "signIn" if n == "GitHub" else "pasteKey"
        if want != expect:
            problems.append("B  TokenBridge `%s`: screen says .%s, catalogue says .%s" % (n, expect, want))

    # C. HandleBridge seats.
    for n in enum_names(read(root, HANDLES), "HandleBridge"):
        if n not in offers:
            continue
        want = catalog_mode(n, offers, sets)
        if want != "noAccount":
            problems.append("C  HandleBridge `%s`: screen says .noAccount, catalogue says .%s" % (n, want))

    # F. NOTHING RESTS ON THE FALLBACK UNCHECKED. `Offer.mode` returns
    #    `.pasteKey` for any connectable seat that needs setup and is in none of
    #    the five sets, so a seat nothing else asserts wears "Add key" on the
    #    strength of a default. Every one must be named by a screen (literal or
    #    through EXPRESSION_SEATS) or swept by B / C.
    asserted = {name for _, name, _ in found}
    asserted |= set(enum_names(read(root, TOKENS), "TokenBridge"))
    asserted |= set(enum_names(read(root, HANDLES), "HandleBridge"))
    # Naming a seat in one of the five sets IS an assertion — that is where
    # `Offer.mode` reads it from. Only the seats that reach the final
    # `return .pasteKey` need a second voice.
    asserted |= set().union(*sets.values())
    for n, (connectable, needs) in sorted(offers.items()):
        if connectable and needs and n not in asserted:
            problems.append("F  `%s` connects with setup, sits in no seat set, and no screen "
                            "or enum sweep names it — its \"Add key\" comes from "
                            "`Offer.mode`'s fallback with nothing agreeing" % n)

    return problems, found, unresolved


def self_test():
    """Each mutation is applied to a COPY of the tree and must be flagged."""
    def copy_tree():
        d = tempfile.mkdtemp(prefix="catalog-mode-")
        for rel in (CATALOG, TOKENS, HANDLES):
            os.makedirs(os.path.dirname(os.path.join(d, rel)), exist_ok=True)
            shutil.copy(os.path.join(ROOT, rel), os.path.join(d, rel))
        os.makedirs(os.path.join(d, SCREENS), exist_ok=True)
        for fn in os.listdir(os.path.join(ROOT, SCREENS)):
            if fn.endswith(".swift"):
                shutil.copy(os.path.join(ROOT, SCREENS, fn), os.path.join(d, SCREENS, fn))
        return d

    # A red tree is the AUDIT's finding, not the self-test's: each mutation
    # must add a problem beyond the base, so verify.sh's "the check is
    # broken" line is never printed for a seat somebody simply forgot.
    base, _, _ = run(ROOT)
    base = set(base)

    def mutate(rel, old, new, tag):
        d = copy_tree()
        p = os.path.join(d, rel)
        s = open(p).read()
        assert old in s, "mutation anchor missing: %s" % old
        open(p, "w").write(s.replace(old, new, 1))
        probs, _, _ = run(d)
        shutil.rmtree(d)
        added = [p for p in probs if p not in base]
        assert any(p.startswith(tag) for p in added), "mutation not caught (%s): %r" % (tag, probs)
        print("  ok   flags  %s" % new.strip()[:70])

    mutate(os.path.join(SCREENS, "StripeScreen.swift"), "mode: .pasteKey", "mode: .signIn", "A")
    mutate(CATALOG, '"Dropbox", "Slack"', '"Slack"', "A")
    mutate(CATALOG, '"Dropbox", "Slack"', '"Dropbox", "Slack", "Stripe"', "B")
    mutate(CATALOG, '"Farcaster", "Bluesky"', '"Farcaster"', "C")
    mutate(CATALOG, '"Dropbox", "Slack"', '"Dropbox", "Slack", "Nobody"', "D")
    mutate(os.path.join(SCREENS, "StripeScreen.swift"), 'name: "Stripe"', 'name: "Photos"', "E")
    # F, both ways: a seat no screen and no sweep names, and an expression
    # screen whose mode drifts from the catalogue (which check A can only see
    # BECAUSE the expression table resolves it — this is the case that used to
    # be silently "skipped").
    mutate(CATALOG, 'Offer(name: "Trello"', 'Offer(name: "Trelloo"', "F")
    mutate(os.path.join(SCREENS, "MailScreen.swift"), "mode: .pasteKey", "mode: .noAccount", "A")
    print("catalog-mode-audit: self-test OK")


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        self_test()
        sys.exit(0)
    problems, found, unresolved = run(ROOT)
    for p in problems:
        print("✗ " + p)
    print("catalog-mode-audit: %d seat declarations checked across screens, "
          "%d expression-named unresolved%s"
          % (len(found), len(unresolved),
             (" (%s)" % ", ".join(unresolved)) if unresolved else ""))
    sys.exit(1 if problems else 0)
