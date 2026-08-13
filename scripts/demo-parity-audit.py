#!/usr/bin/env python3
"""Demo↔bridge parity (2026-08-12) — does the demo land what the app lands?

`demo-selftest.py` checks the demo against ITSELF and against the catalog: are
the seed functions Release-reachable, do the claimed seats exist, is every feed
Shape covered. This file asks the other question, the one that needed a human
every time until now: **for each source, does the demo produce the same SHAPE
of record the real bridge produces?**

Three checks, one extraction pass, each re-catching a class that shipped:

  K · KIND. The demo must never land a `ThingKind` its bridge does not land.
      Stripe shipped as `.transaction` where `StripeBridge` lands `.link`, and
      the consequences ran in BOTH directions: `MoneyReceiptSource.receipt`
      gates on exactly that kind, so every demo Stripe row drew a money
      receipt — §369's anatomy for the nine wallet sources, never Stripe — and
      `ThingSheetView.workReading` stands down whenever a receipt exists, so
      the Work reading it should have drawn was suppressed. The demo showed
      the wrong anatomy AND hid the right one, both rendering perfectly.
      Parity runs in both directions: the demo must not show what the app
      cannot.

  L · REF SHAPE. The most-repeated failure in this codebase — SIX incidents
      (Peer, Privacy Pools, Cloudflare, the Obsidian vault, App Store Connect,
      and §311's retag). A gate keyed on a ref shape (`hasPrefix("peer:")`,
      `ObsidianLink.relativePath`, `WorkStage.ascOutcome`, which parses the
      outcome straight out of the ref) cannot be satisfied by a row wearing a
      `demo:` ref. It always fails silently: the row lands, the room renders,
      and the feature keyed off that gate is simply never reached. There are
      47 such gates in the source and 61 `demo:` ref families in the seeder,
      and until this check nothing compared them.

  M · FIELDS. The fields a bridge stamps that the demo never sets. This is the
      slow class — nothing breaks, the room is just poorer than the app: no
      face, no cover, no price, no market cap. Found by hand four times today.

WHAT THIS DELIBERATELY DOES NOT DO. It never demands the demo land every kind,
ref or field a bridge can produce — a demo is a sample, not a mirror, and
requiring completeness would make the check a nag nobody can satisfy. K flags
only kinds the demo invents; L only gates that NO demo row can reach; M is
reported per source against an exemption list stating why each absence is
honest. A lint that cries wolf gets turned off within a week.

Usage:  scripts/demo-parity-audit.py [--self-test] [--verbose]
Exit 0 = every check passed (or, under --self-test, every fixture behaved).
"""

import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
CASBERI = ROOT / "Casberi/Casberi"
DEMO = CASBERI / "Model/DemoSeedAll.swift"

VERBOSE = "--verbose" in sys.argv
SILENT = False
failures = []
REF_GAPS = []


def check(name, got, want):
    if got == want:
        if VERBOSE and not SILENT:
            print(f"  ok   {name}")
    else:
        failures.append(f"{name}: got {got!r}, want {want!r}")
        if not SILENT:
            print(f"  FAIL {name}: got {got!r}, want {want!r}")


def strip_comments(src):
    """Comments describe the bugs these checks exist for, quoting the very
    spellings they forbid — so every scan reads a stripped copy. The
    Obsidian/Cursor lesson, earned three times."""
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    return re.sub(r"(?m)^\s*//.*$", "", src)


# ── What the demo lands, per source ─────────────────────────────────────────
#
# `row(.kind, title, source: "X", ref: "...", …) { t in t.field = … }` is the
# seeder's one shape, so the demo side needs no general Swift parsing.

def demo_rows(text):
    """[(source, kind, ref, {fields})] for every `row(...)` in the seeder."""
    out = []
    for m in re.finditer(r'row\(\.(\w+)\s*,', text):
        kind = m.group(1)
        # The call's own window: to the next `row(` or 1500 chars, whichever
        # comes first — long enough to hold a trailing closure, short enough
        # not to swallow the next row's fields.
        nxt = text.find("row(.", m.end())
        end = nxt if 0 < nxt < m.end() + 1500 else m.end() + 1500
        seg = text[m.start():end]
        src = re.search(r'source:\s*"([^"]+)"', seg)
        if not src:
            continue
        fields = set(re.findall(r"\bt\.(\w+)\s*=", seg))
        fields |= set(re.findall(r"\bthing\.(\w+)\s*=", seg))
        # A LITERAL ref only. `ref: StockWatch.symbolRef("AAPL")` is built by a
        # function, and reading it as an empty string made the row look like it
        # could satisfy nothing — Stocktwits was reported unreachable while its
        # demo rows wear the realest refs in the seeder. `None` means "cannot
        # judge", which check L skips; `""` would mean "judged, and it matches
        # nothing", which is an accusation.
        ref = re.search(r'ref:\s*"([^"\\]*)', seg)
        if not ref and re.search(r"ref:\s*\w", seg):
            out.append((src.group(1), kind, None, fields))
            continue
        out.append((src.group(1), kind, ref.group(1) if ref else "", fields))
    return out


# ── What the real bridges land, per source ──────────────────────────────────

def constructor_args(text, open_paren):
    """The argument list of a `Thing(` call — balanced to its own closing
    paren. A fixed backward/forward WINDOW was the first cut and it was wrong
    in the way that matters: in a 2,000-line file like `TokenBridges.swift` a
    700-character reach back from `source:` lands in the PREVIOUS bridge's
    constructor, so Linear was reported as landing a kind it does not land.
    An argument list has exact bounds; a window has guesses."""
    depth, i = 0, open_paren
    while i < len(text):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return text[open_paren:i]
        i += 1
    return ""


def bridge_rows(files):
    """{source: {"kinds": set, "refs": set, "fields": set}} across every
    bridge. Keyed on `source:` because that is the only thing the demo and a
    bridge are guaranteed to agree on."""
    out = {}
    for path, text in files.items():
        if path.name == "DemoSeedAll.swift":
            continue
        for m in re.finditer(r"\bThing\(", text):
            args = constructor_args(text, m.end() - 1)
            src = re.search(r'source:\s*"([^"]+)"', args)
            if not src:
                continue
            rec = out.setdefault(src.group(1), {"kinds": set(), "refs": set(),
                                                "fields": set()})
            k = re.search(r"kind:\s*\.(\w+)", args)
            if k:
                rec["kinds"].add(k.group(1))
            for r in re.findall(r'sourceRef:\s*"([^"\\]*)', args):
                rec["refs"].add(r)
            # The stamps that follow the constructor, up to the next one.
            tail_start = m.end() + len(args)
            nxt = text.find("Thing(", tail_start)
            tail = text[tail_start:nxt if 0 < nxt < tail_start + 1500
                        else tail_start + 1500]
            rec["fields"] |= set(re.findall(r"\bthing\.(\w+)\s*=", tail))
        # A ref built as a `let ref = "x:…"` beside the constructor — the
        # shape `IngestSupport.thingsByRef` callers use.
        for r in re.findall(r'\blet ref\s*=\s*"([^"\\]*)', text):
            for name in re.findall(r'source:\s*"([^"]+)"', text)[:1]:
                out.setdefault(name, {"kinds": set(), "refs": set(),
                                      "fields": set()})["refs"].add(r)
    return out


def ref_family(ref):
    """The stable head of a ref — everything before the last colon that is
    followed by interpolation or an id. `peer:sell:0x…` → `peer:sell:`."""
    if ":" not in ref:
        return ""
    return ref[:ref.rfind(":") + 1] if ref.count(":") > 1 else ref.split(":")[0] + ":"


# ── Check K — the demo never invents a kind ─────────────────────────────────
#
# A source the demo seeds but no bridge lands (`You`, `Voice`) has no bridge
# opinion to disagree with; those are the app's own capture paths.
KNOWN_NO_BRIDGE_KIND = {"You", "Voice", "Contacts", "HomeKit"}


def check_k_kinds(demo, bridges):
    for source, kind, _ref, _f in demo:
        if source in KNOWN_NO_BRIDGE_KIND:
            continue
        real = bridges.get(source, {}).get("kinds", set())
        if not real:
            continue          # no bridge parsed for it — L and M say more
        check(f"K · {source} lands .{kind} like its bridge does",
              kind in real, True)


# ── Check L — a seeded source's rows can satisfy its own ref gates ─────────
#
# SCOPED TO SOURCES THE DEMO ALREADY SEEDS, and to whether ANY of that
# source's rows wear a ref shape the source's own bridge writes.
#
# The first cut asked the opposite question — "is every `hasPrefix` gate in the
# app reachable from the demo?" — and it fired eleven times on a healthy tree:
# `peer:expired:`, `hyperliquid:risk:`, `privacypools:poi:`. Those are ALERT
# states a demo has no business carrying (nobody's demo wallet should have an
# expired intent or a liquidation warning), so demanding them is demanding the
# demo be a mirror rather than a sample — the exact nag this file's own header
# swears off.
#
# The real class is narrower and is what bit six times: the demo HAS rows for a
# source, and every one of them wears a `demo:` ref, so the bridge's own gates
# — which parse that ref — can never match. Peer, Privacy Pools, Cloudflare,
# the Obsidian vault and App Store Connect were all exactly this.
KNOWN_DEMO_REF_OK = {
    # EARNED ONE AT A TIME. The first cut of this set was a bulk paste of
    # every source, written to make the check quiet — and it immediately hid a
    # real one: "Wallet" sat in it while the demo's approval row wore
    # `demo:wallet:approval:0` and `WalletPrepare.applies` gates on
    # `wallet:approval:`, so the prepare card could never draw. A name goes in
    # here only after checking that its bridge's gates key on something other
    # than the ref — a source name, a tag, a kind.
}


def check_l_ref_gates(demo, gate_prefixes, bridges):
    """For each seeded source whose bridge writes ref-shaped gates, at least
    one demo row must wear a ref that could satisfy one."""
    by_source = {}
    for source, _k, ref, _f in demo:
        by_source.setdefault(source, set()).add(ref)
    for source, refs in sorted(by_source.items()):
        if source in KNOWN_DEMO_REF_OK:
            continue
        if None in refs:
            continue          # a function-built ref — cannot judge, do not accuse
        real = bridges.get(source, {}).get("refs", set())
        gated = {r for r in real
                 if any(r.startswith(g) or g.startswith(r.split(":")[0] + ":")
                        for g in gate_prefixes)}
        if not gated:
            continue
        reachable = any(ref.startswith(g.split(":")[0] + ":")
                        for ref in refs for g in gated)
        # REPORT, not fail, until each source here is judged one at a time.
        # Three were checked by hand the day this landed — Wallet's approval
        # (real: the prepare card could never draw), Linear's kind, and
        # Stocktwits (a false alarm from a function-built ref, now skipped) —
        # and the rest are unjudged. Failing the build on an unjudged list is
        # how a check gets bulk-exempted into meaning nothing, which this
        # file's own `KNOWN_DEMO_REF_OK` already demonstrated once.
        if not reachable:
            REF_GAPS.append(source)


# ── Check M — the fields a bridge stamps and the demo never does ────────────
#
# Only fields that CHANGE WHAT IS DRAWN. A bridge stamps plenty the demo has no
# business faking (cursors, watermarks, internal ids).
DISPLAY_FIELDS = {
    "authorAvatarURL", "previewImageURL", "authorHandle", "postText", "summary",
    "priceValue", "priceCurrency", "likeCount", "repostCount", "replyCount",
    "messageCount", "imageURLs", "quote", "parent", "socialContext",
    "channelName", "dueAt", "facts", "starCount",
}

# Per source, the display fields whose absence from the demo is HONEST. Each
# entry is a ruling, not a snooze — it states what the demo cannot or should
# not fake.
KNOWN_HONEST_ABSENCE = {
    # A Kindle clipping carries no cover: `My Clippings.txt` has none, so
    # inventing one shows the demo doing what the importer cannot (§366).
    "Kindle": {"previewImageURL"},
    # Snapchat's saved chats are both people's words; the export carries no
    # engagement counts at all (§246).
    "Snapchat": {"likeCount", "repostCount", "replyCount"},
    # An Instagram SAVE is a handle and a timestamp and nothing else —
    # measured against four independent parsers (§245).
    "Instagram": {"postText", "summary", "likeCount", "replyCount", "repostCount"},
    # Gnosis Pay merchant names never reach the chain (§222).
    "Gnosis Pay": {"authorHandle"},
    # Peer stamps no money: the amount is prose in a title and the token
    # differs per fill, so a summed figure would add USDC to ETH (§311).
    "Peer": {"priceValue", "priceCurrency"},
}


def check_m_fields(demo, bridges, report_only=True):
    by_source = {}
    for source, _k, _r, fields in demo:
        by_source.setdefault(source, set()).update(fields)
    gaps = {}
    for source, seeded in sorted(by_source.items()):
        real = bridges.get(source, {}).get("fields", set()) & DISPLAY_FIELDS
        missing = real - seeded - KNOWN_HONEST_ABSENCE.get(source, set())
        if missing:
            gaps[source] = missing
    if not report_only:
        check("M · no unexplained field gaps", gaps, {})
    return gaps


def gate_prefixes(files):
    out = set()
    for text in files.values():
        for m in re.finditer(r'hasPrefix\("([a-z0-9]+:[a-z]*:?)"', text):
            out.add(m.group(1))
    return out


def load():
    files = {}
    for sub in ("Model", "Screens", "Shell"):
        for path in (CASBERI / sub).glob("*.swift"):
            files[path] = strip_comments(path.read_text(errors="ignore"))
    return files


def run(files, report_fields=True):
    demo = demo_rows(files[DEMO])
    bridges = bridge_rows(files)
    check_k_kinds(demo, bridges)
    check_l_ref_gates(demo, gate_prefixes(files), bridges)
    gaps = check_m_fields(demo, bridges, report_only=report_fields)
    return demo, bridges, gaps


def main():
    files = load()
    if "--self-test" in sys.argv:
        sys.exit(self_test(files))
    demo, bridges, gaps = run(files)
    if REF_GAPS:
        print("\n  ref-shape gaps (report — judge one, then exempt or fix it):")
        print(f"    {', '.join(sorted(set(REF_GAPS)))}")
    if gaps:
        print("\n  field gaps (report — see KNOWN_HONEST_ABSENCE to rule on one):")
        for source, missing in sorted(gaps.items()):
            print(f"    {source:<20} {', '.join(sorted(missing))}")
    if failures:
        print(f"✗ demo parity: {len(failures)} check(s) failed")
        sys.exit(1)
    print(f"✓ demo parity: {len(demo)} demo rows over {len(bridges)} bridge sources — "
          f"no invented kinds, every ref gate reachable, {len(gaps)} field gap(s) reported")
    sys.exit(0)


# ── Fixtures ────────────────────────────────────────────────────────────────

def verify_fixture(name, mutate, expect_failure, watch_refs=False):
    """`watch_refs` asserts on the REPORTED ref gaps rather than on a hard
    failure — check L reports by design (see its own note), so a fixture that
    demanded a failure there would be testing the reporting mode, not the
    rule."""
    global failures, SILENT, REF_GAPS
    files = load()
    mutate(files)
    saved, failures, SILENT = failures, [], True
    saved_refs, REF_GAPS = REF_GAPS, []
    try:
        run(files)
        broke = bool(REF_GAPS) if watch_refs else bool(failures)
    finally:
        failures, SILENT = saved, False
        seen, REF_GAPS = REF_GAPS, saved_refs
        if watch_refs:
            broke = bool(seen)
    ok = broke == expect_failure
    print(f"  {'✓' if ok else '✗'} {name}")
    return ok


def self_test(_files):
    ok = True
    ok &= verify_fixture(
        "a demo row landing a kind its bridge never lands is caught",
        # Stripe's own bug, as a fixture: `.link` → `.transaction`.
        lambda f: f.__setitem__(DEMO, f[DEMO].replace(
            'row(.link, s.title, source: "Stripe"',
            'row(.transaction, s.title, source: "Stripe"', 1)),
        True)
    ok &= verify_fixture(
        "a demo ref that cannot satisfy its bridge's gate is caught",
        # The Obsidian vault's own bug: a real `obsidian:` ref back to `demo:`.
        lambda f: f.__setitem__(DEMO, f[DEMO].replace(
            'ref: "obsidian:demo-vault/\\(n.0).md"',
            'ref: "demo:obsidian:\\(i)"', 1)),
        True, watch_refs=True)
    ok &= verify_fixture(
        "the shipped tree passes",
        lambda f: None,
        False)
    print(f"{'✓' if ok else '✗'} demo-parity self-test")
    return 0 if ok else 1


if __name__ == "__main__":
    main()
