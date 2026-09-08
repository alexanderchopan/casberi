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

Skipped, and said so: screens whose `AccountPage` name is an expression.

Usage: scripts/catalog-mode-audit.py [--self-test]
"""
import re, sys, os, tempfile, shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = "Casberi/Casberi/Model/BridgeCatalog.swift"
SCREENS = "Casberi/Casberi/Screens"
TOKENS = "Casberi/Casberi/Model/TokenBridges.swift"
HANDLES = "Casberi/Casberi/Screens/HandleSetupScreen.swift"

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
    """(file, name, mode) for every literal AccountPage( call; skipped files."""
    found, skipped = [], []
    for fn in sorted(os.listdir(os.path.join(root, SCREENS))):
        if not fn.endswith(".swift"):
            continue
        src = strip_comments(read(root, os.path.join(SCREENS, fn)))
        for m in re.finditer(r"AccountPage\(", src):
            window = src[m.end():m.end() + 1200]
            name = re.match(r"\s*name: \"([^\"]+)\"", window)
            mode = re.search(r"\bmode: \.(\w+)", window)
            if name and mode:
                found.append((fn, name.group(1), mode.group(1)))
            elif mode:
                skipped.append(fn)
    return found, skipped


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

    # D. Every set entry is an offer.
    for mode, names in sets.items():
        for n in sorted(names):
            if n not in offers:
                problems.append("D  `%s` is in the %s set and is not an offer" % (n, mode))

    # A / E. Literal screens.
    found, skipped = screen_declarations(root)
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

    return problems, found, sorted(set(skipped))


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
    print("catalog-mode-audit: self-test OK")


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        self_test()
        sys.exit(0)
    problems, found, skipped = run(ROOT)
    for p in problems:
        print("✗ " + p)
    print("catalog-mode-audit: %d literal screens checked, %d expression-named skipped (%s)"
          % (len(found), len(skipped), ", ".join(skipped)))
    sys.exit(1 if problems else 0)
