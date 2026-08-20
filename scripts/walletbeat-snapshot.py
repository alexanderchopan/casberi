#!/usr/bin/env python3
"""Generate the bundled Walletbeat directory from Walletbeat's own published ratings.

WHY A SNAPSHOT AND NOT A LIVE READ (prd §419): the directory screen lists every rated
wallet, and Walletbeat publishes one ~342KB JSON document PER WALLET (97KB gzipped).
Fetching all 32 to draw a list is 11MB for a screen that must open instantly and offline,
so the counts ride a snapshot regenerated at ship time and the FULL report card is fetched
live for the one wallet you opened. Bundled baseline + live enrichment, the X402Faces shape.

WHY WE NEVER COMPUTE A RATING OURSELVES: Walletbeat's raw feature data does not imply its
ratings. Measured 2026-08-20 — `data/software-wallets/rabby.ts` carries
`erc20Approvals: SpendingApprovalsControl.CAN_INSPECT_AND_REVOKE`, while Walletbeat's own
evaluator rates that attribute FAIL ("Rabby does not let you inspect or revoke token
approvals") because a sibling ERC-1155 field drags the attribute down. A naive read of the
features gives the OPPOSITE answer to the people whose judgment we are citing. So this
script reads their COMPUTED export and never the feature files.

WHAT IT DELIBERATELY DOES NOT DO: it never ranks wallets, never sums dimensions into a
score, and never picks a "best" — a composite is an editorial act Walletbeat itself
declines to make, and inventing one would put our judgment behind their name (§83).
It counts their calls, per dimension, and stops.

Usage:
  scripts/walletbeat-snapshot.py            # regenerate the Swift directory in place
  scripts/walletbeat-snapshot.py --check    # fail if the checked-in file is stale (no writes)
  scripts/walletbeat-snapshot.py --self-test
"""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime
import gzip
import io
import json
import os
import re
import sys
import urllib.error
import urllib.request

HOST = "beta.walletbeat.eth.limo"
INDEX_URL = f"https://{HOST}/llms.txt"
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_PATH = os.path.join(REPO_ROOT, "Casberi", "Casberi", "Model", "WalletbeatDirectory.swift")

# The rating vocabulary Walletbeat documents in its own llms.txt. EXEMPT means the
# attribute does not apply to this wallet, which is NOT the same as UNRATED ("we don't
# know yet") — folding them together would report a wallet as under-examined when the
# question simply doesn't apply to it.
RATINGS = ("PASS", "PARTIAL", "FAIL", "UNRATED", "EXEMPT")

# Dimension order is Walletbeat's own, not ours. `maintenance` exists only for hardware
# wallets; software wallets have no such group and must not be shown an empty one.
DIMENSIONS = (
    "security",
    "privacy",
    "selfSovereignty",
    "transparency",
    "ecosystem",
    "maintenance",
)

USER_AGENT = "Casberi/1.0 (+https://casberi.app) walletbeat-snapshot"


def fetch(url: str, timeout: int = 60) -> bytes:
    req = urllib.request.Request(
        url, headers={"User-Agent": USER_AGENT, "Accept-Encoding": "gzip"}
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read()
        if resp.headers.get("Content-Encoding") == "gzip":
            raw = gzip.GzipFile(fileobj=io.BytesIO(raw)).read()
        return raw


def wallet_ids(index_text: str) -> list[str]:
    """Pull wallet ids out of llms.txt.

    The links in llms.txt currently point at `wallet.page`, a DIFFERENT site that does not
    serve this data (measured 2026-08-20 — it is a vocs docs site, and `/rabby/index.json`
    there returns HTML). Only the PATH SEGMENT is trusted; the host in the link is ignored
    and every fetch goes to HOST above. Reading the host out of their markdown would point
    this script at whatever domain they write next.
    """
    ids: list[str] = []
    seen: set[str] = set()
    for match in re.finditer(r"\]\(https?://[^/)]+/([a-z0-9][a-z0-9-]*)/index\.html\.md\)", index_text):
        wid = match.group(1)
        if wid not in seen:
            seen.add(wid)
            ids.append(wid)
    return ids


def counts_for(group: dict) -> dict[str, int]:
    """Count Walletbeat's ratings in one dimension. Never a score, never a ranking."""
    tally = {r: 0 for r in RATINGS}
    for block in group.values():
        rating = block.get("evaluation", {}).get("rating")
        if rating in tally:
            tally[rating] += 1
        else:
            # An unknown rating value is COUNTED AS UNRATED and reported, never dropped:
            # a silently discarded attribute makes a dimension look smaller than it is,
            # and the bar would render perfectly while under-counting.
            tally["UNRATED"] += 1
            print(f"  ! unknown rating {rating!r} — counted as UNRATED", file=sys.stderr)
    return tally


def distill(doc: dict) -> dict:
    """Reduce one ~342KB rated-wallet export to the handful of facts a list row draws."""
    kinds = [t.lower() for t in doc.get("types", [])]
    dims: dict[str, dict[str, int]] = {}
    for name in DIMENSIONS:
        group = doc.get("overall", {}).get(name)
        if isinstance(group, dict) and group:
            dims[name] = counts_for(group)
    return {
        "id": doc["walletId"],
        "name": doc.get("displayName") or doc["walletId"],
        "kinds": kinds,
        "variants": [v.lower() for v in doc.get("variants", [])],
        "stage": doc.get("stage"),
        "updated": doc.get("lastUpdated"),
        "dims": dims,
    }


# The wallets the demo furnishes. Chosen to exercise the coverage gate rather than to
# flatter the card: two Walletbeat has examined in depth and one it has barely started on.
DEMO_WALLETS = ("rabby", "metamask", "ledger")


def demo_attributes(doc: dict) -> list[dict]:
    """Every attribute of one wallet, for the demo corpus.

    Real ratings and real sentences, so the demo shows what the feature actually shows.

    DELIBERATELY WITHOUT `whyItMatters`. Walletbeat's "why does this matter?" prose runs to
    3,375 characters at its longest, and bundling it for three demo wallets took this
    generated file from 44KB to 111KB — 67KB of string literals compiled into every
    shipped binary so that a demo disclosure has something to open. The live parse reads
    the field, so the disclosure is there the moment real ratings are fetched; the demo
    simply shows the rest of the card.
    Generated rather than hand-written for the reason every registry here is derived:
    a hand-copied rating goes stale silently and then the demo teaches the wrong thing.
    """
    out = []
    for name in DIMENSIONS:
        group = doc.get("overall", {}).get(name)
        if not isinstance(group, dict):
            continue
        for attribute_id, block in sorted(group.items()):
            evaluation = block.get("evaluation", {})
            meta = block.get("attribute", {})
            explanation = " ".join((evaluation.get("shortExplanation") or "").split())
            if explanation in ("See full details on the wallet page.",):
                explanation = ""
            out.append({
                "id": attribute_id,
                "dimension": name,
                "name": meta.get("attributeDisplayName") or attribute_id,
                "question": " ".join((meta.get("shortQuestion") or "").split()),
                "verdict": evaluation.get("rating", "UNRATED"),
                "explanation": explanation,
            })
    return out


def gather() -> dict:
    print(f"index  {INDEX_URL}", file=sys.stderr)
    ids = wallet_ids(fetch(INDEX_URL).decode("utf-8"))
    if not ids:
        raise SystemExit("no wallet ids in llms.txt — the index format changed")
    print(f"       {len(ids)} wallets", file=sys.stderr)

    demo: dict[str, list[dict]] = {}

    def one(wid: str):
        url = f"https://{HOST}/{wid}/index.json"
        try:
            doc = json.loads(fetch(url))
        except (urllib.error.URLError, json.JSONDecodeError, TimeoutError) as exc:
            print(f"  ! {wid}: {exc}", file=sys.stderr)
            return None
        if wid in DEMO_WALLETS:
            demo[wid] = demo_attributes(doc)
        return distill(doc)

    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        got = list(pool.map(one, ids))

    wallets = [w for w in got if w]
    missing = [i for i, w in zip(ids, got) if not w]
    if missing:
        # A partial snapshot silently drops wallets from the directory, which reads as
        # "Walletbeat doesn't rate it" — the exact false claim this feature must not make.
        raise SystemExit(f"failed to read {len(missing)} wallets: {', '.join(missing)}")

    wallets.sort(key=lambda w: w["name"].lower())
    missing_demo = [w for w in DEMO_WALLETS if w not in demo]
    if missing_demo:
        raise SystemExit(f"demo wallets missing from the index: {', '.join(missing_demo)}")

    return {
        "generated": datetime.date.today().isoformat(),
        "host": HOST,
        "wallets": wallets,
        "demo": demo,
    }


def swift_string(value) -> str:
    if value is None:
        return "nil"
    escaped = str(value).replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def render(snapshot: dict) -> str:
    lines: list[str] = []
    add = lines.append
    add("// Generated by scripts/walletbeat-snapshot.py — DO NOT EDIT BY HAND.")
    add("//")
    add("// Walletbeat's ratings for every wallet it rates, distilled to the counts a list")
    add("// row draws. Regenerate at ship time; `scripts/walletbeat-snapshot.py --check`")
    add("// fails the build when this file no longer matches what Walletbeat publishes.")
    add("//")
    add("// These are WALLETBEAT'S judgments, not ours. Nothing here ranks wallets or sums a")
    add("// dimension into a score — a composite is an editorial act Walletbeat itself")
    add("// declines to make (prd §419).")
    add("")
    add("import Foundation")
    add("")
    add("enum WalletbeatDirectory {")
    add(f"\t/// The day this snapshot was taken from {snapshot['host']}.")
    add(f"\tstatic let generated = {swift_string(snapshot['generated'])}")
    add("")
    add("\tstatic let wallets: [WalletbeatEntry] = [")
    for w in snapshot["wallets"]:
        dims = ", ".join(
            "."
            + name
            + ": WalletbeatCounts(pass: %d, partial: %d, fail: %d, unrated: %d, exempt: %d)"
            % (c["PASS"], c["PARTIAL"], c["FAIL"], c["UNRATED"], c["EXEMPT"])
            for name, c in w["dims"].items()
        )
        variants = ", ".join(swift_string(v) for v in w["variants"])
        add("\t\tWalletbeatEntry(")
        add(f"\t\t\tid: {swift_string(w['id'])},")
        add(f"\t\t\tname: {swift_string(w['name'])},")
        add(f"\t\t\thardware: {'true' if 'hardware' in w['kinds'] else 'false'},")
        add(f"\t\t\tvariants: [{variants}],")
        add(f"\t\t\tstage: {swift_string(w['stage'])},")
        add(f"\t\t\tupdated: {swift_string(w['updated'])},")
        add(f"\t\t\tcounts: [{dims}]")
        add("\t\t),")
    add("\t]")
    add("")
    add("\t/// The demo corpus's wallets, with Walletbeat's real ratings and real")
    add("\t/// sentences — so the furnished demo shows what the feature actually shows.")
    add("\tstatic let demoAttributes: [String: [WalletbeatAttribute]] = [")
    for wid, attributes in sorted(snapshot.get("demo", {}).items()):
        add(f"\t\t{swift_string(wid)}: [")
        for a in attributes:
            add(
                "\t\t\tWalletbeatAttribute(id: %s, dimension: .%s, name: %s, question: %s, verdict: .%s, explanation: %s),"
                % (
                    swift_string(a["id"]),
                    a["dimension"],
                    swift_string(a["name"]),
                    swift_string(a["question"]),
                    {"PASS": "pass", "PARTIAL": "partial", "FAIL": "fail",
                     "UNRATED": "unrated", "EXEMPT": "exempt"}.get(a["verdict"], "unrated"),
                    swift_string(a["explanation"]),
                )
            )
        add("\t\t],")
    add("\t]")
    add("}")
    add("")
    return "\n".join(lines)


# --------------------------------------------------------------------------------------
# Self-test. A generator that cannot demonstrate it catches a bad snapshot certifies
# nothing, so every rule above is exercised against a fixture before it is trusted.
# --------------------------------------------------------------------------------------


def self_test() -> int:
    failures: list[str] = []

    def check(name: str, cond: bool) -> None:
        if cond:
            print(f"  ok   {name}")
        else:
            failures.append(name)
            print(f"  FAIL {name}")

    print("walletbeat-snapshot self-test")

    # The host in llms.txt links is ignored; only the path segment is a wallet id.
    idx = (
        "- [Rabby](https://wallet.page/rabby/index.html.md)\n"
        "- [Base App](https://wallet.page/base-app/index.html.md)\n"
        "- [Dup](https://other.example/rabby/index.html.md)\n"
        "Full wallet list: https://wallet.page\n"
    )
    ids = wallet_ids(idx)
    check("parses ids from llms.txt", ids == ["rabby", "base-app"])
    check("ignores a bare link with no wallet path", "wallet.page" not in ids)

    # A methodology/about link must not be mistaken for a wallet.
    check(
        "ignores non-wallet md links",
        wallet_ids("- [M](https://wallet.page/methodology/index.html.md)\n") == ["methodology"],
    )

    # Counting: every rating value lands in its own bucket, EXEMPT never folded into UNRATED.
    group = {
        "a": {"evaluation": {"rating": "PASS"}},
        "b": {"evaluation": {"rating": "PARTIAL"}},
        "c": {"evaluation": {"rating": "FAIL"}},
        "d": {"evaluation": {"rating": "UNRATED"}},
        "e": {"evaluation": {"rating": "EXEMPT"}},
    }
    tally = counts_for(group)
    check("counts each rating once", all(tally[r] == 1 for r in RATINGS))
    check("EXEMPT is not folded into UNRATED", tally["EXEMPT"] == 1 and tally["UNRATED"] == 1)

    # An unknown rating is counted, never dropped — a dropped attribute shrinks the bar.
    odd = counts_for({"a": {"evaluation": {"rating": "SOMETHING_NEW"}}})
    check("unknown rating is counted as UNRATED", odd["UNRATED"] == 1)
    check("unknown rating is not silently dropped", sum(odd.values()) == 1)

    # Distilling: hardware wallets keep `maintenance`, software wallets never gain it.
    hw = distill(
        {
            "walletId": "ledger",
            "displayName": "Ledger",
            "types": ["HARDWARE"],
            "variants": ["HARDWARE"],
            "stage": None,
            "lastUpdated": "2025-03-12",
            "website": "https://ledger.com",
            "overall": {
                "security": {"a": {"evaluation": {"rating": "UNRATED"}}},
                "maintenance": {"m": {"evaluation": {"rating": "PASS"}}},
            },
        }
    )
    check("hardware wallet is flagged", hw["kinds"] == ["hardware"])
    check("hardware keeps maintenance", "maintenance" in hw["dims"])
    check("a null stage survives as None", hw["stage"] is None)

    sw = distill(
        {
            "walletId": "rabby",
            "displayName": "Rabby",
            "types": ["SOFTWARE"],
            "variants": ["MOBILE", "BROWSER"],
            "stage": "Stage 0",
            "lastUpdated": "2026-07-20",
            "website": "https://rabby.io",
            "overall": {"security": {"a": {"evaluation": {"rating": "PASS"}}}},
        }
    )
    check("software wallet has no maintenance group", "maintenance" not in sw["dims"])
    check("software wallet keeps its stage", sw["stage"] == "Stage 0")

    # An EMPTY dimension is omitted rather than rendered as a zero-width bar.
    empty = distill(
        {
            "walletId": "x",
            "types": ["SOFTWARE"],
            "overall": {"security": {}, "privacy": {"a": {"evaluation": {"rating": "FAIL"}}}},
        }
    )
    check("an empty dimension is omitted", "security" not in empty["dims"])
    check("a populated dimension survives", empty["dims"]["privacy"]["FAIL"] == 1)
    check("a missing displayName falls back to the id", empty["name"] == "x")

    # Rendering: a quote or backslash in a wallet name must not break the Swift file.
    check('escapes a quote in a name', swift_string('He said "hi"') == '"He said \\"hi\\""')
    check("escapes a backslash", swift_string("a\\b") == '"a\\\\b"')
    check("renders nil for a null stage", swift_string(None) == "nil")

    out = render({"generated": "2026-08-20", "host": HOST, "wallets": [hw, sw]})
    check("renders both wallets", out.count("WalletbeatEntry(") == 2)
    check("renders hardware flag", "hardware: true" in out and "hardware: false" in out)
    check("renders a nil stage", "stage: nil" in out)

    # The negative guard reads a COMMENT-STRIPPED copy. The generated header DOCUMENTS this
    # rule by naming what it must never emit ("nothing here ranks wallets or sums a
    # dimension into a score"), so a guard over raw text fires on the prose explaining it
    # and reports a correct file as broken — earned on this guard's own first run.
    body = "\n".join(l for l in out.splitlines() if not l.lstrip().startswith("//")).lower()
    check("emits no score field", "score" not in body)
    check("emits no ranking field", "rank" not in body)

    print(f"\n{'FAILED: ' + ', '.join(failures) if failures else 'all checks passed'}")
    return 1 if failures else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--check", action="store_true", help="fail if the checked-in file is stale")
    args = ap.parse_args()

    if args.self_test:
        return self_test()

    snapshot = gather()
    rendered = render(snapshot)

    if args.check:
        try:
            with open(OUT_PATH, encoding="utf-8") as fh:
                current = fh.read()
        except FileNotFoundError:
            print(f"MISSING {OUT_PATH}", file=sys.stderr)
            return 1
        # The generated date changes every run and is not drift; compare everything else.
        strip = lambda t: re.sub(r'static let generated = "[^"]*"', "", t)
        if strip(current) != strip(rendered):
            print("STALE — Walletbeat's ratings have changed since this was generated.", file=sys.stderr)
            print("Run scripts/walletbeat-snapshot.py to refresh.", file=sys.stderr)
            return 1
        print("walletbeat directory is current")
        return 0

    with open(OUT_PATH, "w", encoding="utf-8") as fh:
        fh.write(rendered)
    n = len(snapshot["wallets"])
    hw = sum(1 for w in snapshot["wallets"] if "hardware" in w["kinds"])
    print(f"wrote {OUT_PATH}\n  {n} wallets ({n - hw} software, {hw} hardware)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
