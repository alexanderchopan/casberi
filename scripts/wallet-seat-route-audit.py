#!/usr/bin/env python3
"""Every wallet-riding seat must have a real Connect door and a real Open door.

The class this catches shipped on 2026-08-18 and was reported on 2026-08-28:
Altana was added to `BridgeStore.walletSeats` and to the catalog with
`needsSetup: true`, and to NEITHER half of `BridgeRouter`. Connect for a
`needsSetup` offer is `HomeRoute.openSetup`, whose first line is
`guard let dest = BridgeRouter.destination(forOffer: name) else { return }` --
so the button was a SILENT NO-OP for ten days. Nothing here could see it: a
missing switch case is not a compile error, `catalog-sync.sh` checks the
catalog against the website and not against the router, and the screen sweep
proves a page painted, never that its button did anything.

Both directions are checked because they fail differently and both failed here:
  CONNECT  nil  -> the button does nothing at all (a dead control, s83)
  OPEN     nil  -> `destination(forID:)` falls to `.detail(id:)`, the generic
                   page, so the seat opens something that is not its room

A THIRD direction since prd s515 (2026-08-29): every wallet-riding seat must
also have an entry in `WalletSeatStanding.seats`, which is where its product
page gets the word for what the sweep looks for ("No Gnosis Pay card seen
yet"). A seat missing from there wears the right verb and says NOTHING under
it, which is the state s515 removed -- a page that raises a question and does
not answer it. Silent, because a nil sentence renders as no sentence.

Whether the room a seat opens is the seat's OWN is `setup-copy-audit.py`
check 7e: the s515 rule that a catalog seat lands rows under a source of its
own, which is why Aave, Morpho, Uniswap, Hyperliquid and Aerodrome stopped
being seats at all.
"""
import os, re, sys, pathlib

def load(p):
    return pathlib.Path(p).read_text(encoding="utf-8")

def strip_comments(s):
    s = re.sub(r'^\s*///.*$', '', s, flags=re.M)
    s = re.sub(r'^\s*//.*$', '', s, flags=re.M)
    return s

def check(store_src, route_src, standing_src=None):
    problems = []
    store = strip_comments(store_src)
    route = strip_comments(route_src)

    block = re.search(r'walletSeats:\s*\[WalletSeat\](.*?)\n    \]', store, re.S)
    if not block:
        return ["could not find `walletSeats` in BridgeStore.swift -- this check is blind"]
    seats = re.findall(r'WalletSeat\(id:\s*"([^"]+)",\s*name:\s*"([^"]+)"', block.group(1))
    if not seats:
        return ["parsed zero wallet seats -- this check is blind"]

    # The early-return in `destination(forOffer:)`: seats whose Connect is the
    # wallet manager, keyed by CATALOG NAME.
    fo = re.search(r'func destination\(forOffer name: String\) -> Destination\?\s*\{(.*?)\n    \}',
                   route, re.S)
    connect_wallet = set(re.findall(r'name == "([^"]+)"', fo.group(1))) if fo else set()

    rows = set(re.findall(r'Row\(offer:\s*"([^"]+)"', route))
    rs = re.search(r'func roomSource\(forID id: String\) -> String\?\s*\{(.*?)\n    \}', route, re.S)
    room_ids = set(re.findall(r'case\s+((?:"[^"]+"\s*,\s*)*"[^"]+")\s*:', rs.group(1))) if rs else set()
    room_ids = {q.strip('"') for grp in room_ids for q in re.findall(r'"([^"]+)"', grp)}

    for sid, name in seats:
        if name not in connect_wallet and name not in rows:
            problems.append(
                f'{name} ({sid}) is a wallet-riding seat with NO Connect route: '
                f'`destination(forOffer: "{name}")` returns nil, so `HomeRoute.openSetup` '
                f'guards out and the Connect button does nothing at all. Name it in the '
                f'`.wallet` early-return, or give it a `Row(offer:)`.')
        if sid not in room_ids and name not in rows:
            problems.append(
                f'{name} ({sid}) has NO Open route: `roomSource(forID: "{sid}")` is nil and '
                f'there is no `Row(offer: "{name}")`, so Open falls to `.detail(id:)` -- the '
                f'generic page, not the room its rows land in.')

    # The sentence its product page says under the verb (prd s515).
    if standing_src is not None:
        stand = strip_comments(standing_src)
        block = re.search(r'static let seats: \[Seat\] = \[(.*?)\n    \]', stand, re.S)
        if not block:
            problems.append("could not find `WalletSeatStanding.seats` -- "
                            "the standing half of this check is blind")
        else:
            spoken = set(re.findall(r'Seat\(id:\s*"([^"]+)"', block.group(1)))
            for sid, name in seats:
                if sid not in spoken:
                    problems.append(
                        f'{name} ({sid}) has no `WalletSeatStanding.seats` entry, so its '
                        f'product page wears the Automatic verb and says nothing under it '
                        f'-- the unanswered question s515 removed.')
            for sid in sorted(spoken - {s for s, _ in seats}):
                problems.append(
                    f'`WalletSeatStanding.seats` names "{sid}", which is not a wallet '
                    f'seat -- a stale entry describing a seat that no longer rides the '
                    f'wallets.')
    return problems

def selftest():
    STORE_OK = '''
    private static let walletSeats: [WalletSeat] = [
        WalletSeat(id: "peer", name: "Peer",
                   count: { x }, noun: "wallet", can: []),
        WalletSeat(id: "gnosispay", name: "Gnosis Pay",
                   count: { x }, noun: "card", can: []),
    ]
'''
    ROUTE_OK = '''
        Row(offer: "Peer", id: "peer", destination: .peer),
        Row(offer: "Gnosis Pay", id: "gnosispay", destination: .wallet),
    static func destination(forOffer name: String) -> Destination? {
        if name == "Peer" { return .wallet }
        return rows.first { $0.offer == name }?.destination
    }
    static func roomSource(forID id: String) -> String? {
        switch id {
        case "aave", "morpho": "Wallet"
        case "gnosispay": GnosisPayBridge.sourceName
        default: nil
        }
    }
'''
    cases = []
    # A clean pair passes.
    cases.append((not check(STORE_OK, ROUTE_OK), "a wired pair passes"))
    # A seat with neither door is flagged TWICE, once per direction -- the
    # exact shape Altana shipped in.
    store_bad = STORE_OK.replace('    ]', '''        WalletSeat(id: "altana", name: "Altana",
                   count: { x }, noun: "wallet", can: []),
    ]''')
    p = check(store_bad, ROUTE_OK)
    cases.append((any("NO Connect route" in x for x in p), "a seat with no Connect route is flagged"))
    cases.append((any("NO Open route" in x for x in p), "...and its missing Open route too"))
    # Connect wired, Open not: the half-fix.
    route_half = ROUTE_OK.replace('if name == "Peer"', 'if name == "Peer" || name == "Altana"')
    p = check(store_bad, route_half)
    cases.append((not any("NO Connect route" in x for x in p), "naming it in the .wallet return fixes Connect")) 
    cases.append((any("NO Open route" in x for x in p), "...and does NOT silently fix Open"))
    # Open wired via roomSource.
    route_full = route_half.replace('case "gnosispay": GnosisPayBridge.sourceName',
                                    'case "gnosispay": GnosisPayBridge.sourceName\n        case "altana": AltanaKeystore.source')
    cases.append((not check(store_bad, route_full), "both doors wired passes"))
    # A seat carrying its own Row satisfies both.
    route_row = ROUTE_OK.replace('Row(offer: "Gnosis Pay"',
                                 'Row(offer: "Altana", id: "altana", destination: .safe),\n        Row(offer: "Gnosis Pay"')
    cases.append((not check(store_bad, route_row), "a seat with its own Row satisfies both"))
    # A multi-id `case` line must count every id on it, or aave/morpho read as unrouted.
    store_multi = STORE_OK.replace('WalletSeat(id: "peer", name: "Peer"',
                                   'WalletSeat(id: "morpho", name: "Peer"')
    cases.append((not any("NO Open route" in x for x in check(store_multi, ROUTE_OK)),
                  "a folded `case a, b:` line routes every id on it"))
    # Blindness must be loud, never green.
    cases.append((bool(check("", ROUTE_OK)), "an unparseable seat table fails rather than passing"))

    # The standing half (prd s515).
    STAND_OK = '''
    static let seats: [Seat] = [
        Seat(id: "peer", thing: "Peer trade"),
        Seat(id: "gnosispay", thing: "Gnosis Pay card"),
    ]
'''
    cases.append((not check(STORE_OK, ROUTE_OK, STAND_OK), "a seat that also speaks passes"))
    cases.append((any("says nothing under it" in x
                      for x in check(STORE_OK, ROUTE_OK,
                                     STAND_OK.replace('Seat(id: "peer"', 'Seat(id: "peerX"', 1))),
                  "a seat with no standing entry is flagged"))
    cases.append((any("not a wallet seat" in x
                      for x in check(STORE_OK, ROUTE_OK, STAND_OK.replace(
                          '    ]', '        Seat(id: "aave", thing: "Aave position"),\n    ]'))),
                  "a standing entry for a retired seat is flagged"))
    cases.append((any("blind" in x for x in check(STORE_OK, ROUTE_OK, "enum WalletSeatStanding {}")),
                  "a missing standing table fails rather than passing"))

    bad = [n for ok, n in cases if not ok]
    for ok, n in cases:
        print(("  \u2713 " if ok else "  \u2717 ") + n)
    if bad:
        print(f"x wallet-seat-route self-test: {len(bad)} of {len(cases)} FAILED"); return 1
    print(f"\u2713 wallet-seat-route self-test: {len(cases)} checks passed"); return 0

if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(selftest())
    os.chdir(pathlib.Path(__file__).resolve().parents[1])
    probs = check(load("Casberi/Casberi/Model/BridgeStore.swift"),
                  load("Casberi/Casberi/Model/BridgeRouting.swift"),
                  load("Casberi/Casberi/Model/WalletSeatStanding.swift"))
    for p in probs:
        print("\u2717 " + p)
    if not probs:
        print("\u2713 wallet-seat routes: every seat has a Connect door, an Open door "
              "and a sentence")
    sys.exit(1 if probs else 0)
