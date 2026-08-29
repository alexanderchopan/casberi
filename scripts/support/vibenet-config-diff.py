#!/usr/bin/env python3
"""What vibenet ADDED since we last looked — the inverse of every other check.

`live-integrations.sh`'s existing vibenet rows ask "does what the room already
reads still work": an allowlist of six eip8130 names plus usdv/nfv, each
asserted present, each proven live. That shape catches a REGRESSION and is
structurally blind to an ADDITION — a contract vibenet deploys tomorrow lands
in the same config, satisfies every one of those assertions, and the nightly
prints green while a feature we could be reading goes unnoticed for as long as
nobody happens to open the endpoint by hand.

So this compares the WHOLE config against a checked-in snapshot rather than
against a hand-named list, and the baseline is "what existed when we last
looked" rather than "what the app reads" — those differ, and getting it wrong
is what makes a check cry wolf: the app already ignores `entryPointV06`, so a
read-set baseline would report it as news every night forever.

Three verdicts, and the severities differ because the consequences do:

  NEW    a key we have never seen. vibenet shipped something. The whole point.
  GONE   a key that vanished. The existing inline row already FAILS for the
         eight we read; this covers the rest, which go quiet rather than break.
  MOVED  an address changed for a key the room READS. vibenet's own premise is
         that it redeploys, so a moved address is routine — but it is the
         moment watched rows start pointing at a contract that no longer
         exists, which from inside the room is indistinguishable from an
         account that has never moved a token (§311's lesson).

An address that moved for a key nothing reads is SILENT, and `_commit` alone
changing is silent too. Both change on every redeploy, and a row that fires
every night is one nobody reads within a week.

  vibenet-config-diff.py              fetch and compare, print one verdict line
  vibenet-config-diff.py --accept     fetch and rewrite the snapshot
  vibenet-config-diff.py --self-test  fixtures, no network

The UA is not decoration: `api.vibes.base.org` sits behind Cloudflare, which
answers a bare `Python-urllib` 403 while serving 200 to a browser UA (measured
2026-08-28) — a naive probe reports a healthy endpoint as dead.
"""

import json
import os
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
SNAPSHOT = os.path.join(HERE, "vibenet-contracts.json")
LIVE_SH = os.path.normpath(os.path.join(HERE, "..", "live-integrations.sh"))

URL = "https://api.vibes.base.org/api/vibenet/contracts"
UA = "Mozilla/5.0 (compatible; Casberi/1.0; +https://casberi.app)"

# The keys the ROOM reads, so a moved address is worth saying out loud. Kept in
# step with `live-integrations.sh`'s own inline shape row by --self-test, since
# two lists of one thing drift and then the two rows disagree about which
# contract matters.
READ = {
    "eip8130.Keystore",
    "eip8130.P256Authenticator",
    "eip8130.WebAuthnAuthenticator",
    "eip8130.DelegateAuthenticator",
    "eip8130.PolicyManager",
    "eip8130.SessionPolicy",
    "usdv",
    "nfv",
}


def flatten(cfg):
    """Config → {dotted key: address}, dropping the `_`-prefixed metadata.

    One level of nesting is all this payload has ever had, and a nested object
    appearing where a string was is itself news — so it is reported as a new
    key rather than walked, which would silently absorb the change.
    """
    out = {}
    for k, v in cfg.items():
        if k.startswith("_"):
            continue
        if isinstance(v, dict):
            for sub, addr in v.items():
                out[f"{k}.{sub}"] = str(addr)
        else:
            out[k] = str(v)
    return out


def compare(now, before):
    """(verdict, detail) for a flattened config against a flattened snapshot."""
    new = sorted(set(now) - set(before))
    gone = sorted(set(before) - set(now))
    moved = sorted(
        k for k in set(now) & set(before)
        if k in READ and now[k].lower() != before[k].lower()
    )
    parts = []
    if new:
        parts.append("NEW=" + ",".join(new))
    if gone:
        parts.append("GONE=" + ",".join(gone))
    if moved:
        parts.append("MOVED=" + ",".join(moved))
    return ("OK", "") if not parts else ("DIFF", " ".join(parts))


def fetch():
    req = urllib.request.Request(URL, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=25) as r:
        return json.loads(r.read())


def load_snapshot():
    with open(SNAPSHOT) as f:
        return json.load(f)


def self_test():
    base = {"_commit": "aaa", "faucetAddress": "0xF1", "usdv": "0xU1",
            "eip8130": {"Keystore": "0xK1", "SessionPolicy": "0xS1"}}
    flat = flatten(base)
    assert flat == {"faucetAddress": "0xF1", "usdv": "0xU1",
                    "eip8130.Keystore": "0xK1", "eip8130.SessionPolicy": "0xS1"}, flat
    assert "_commit" not in flat, "metadata must not be compared as a contract"

    # Identical is silent.
    assert compare(flat, flat) == ("OK", "")

    # A commit bump alone is silent — it happens on every redeploy.
    bumped = dict(base, _commit="bbb")
    assert compare(flatten(bumped), flat) == ("OK", ""), "a commit bump is not news"

    # A key we have never seen is the whole point.
    added = json.loads(json.dumps(base))
    added["eip8130"]["ReceiptVerifier"] = "0xR1"
    v, d = compare(flatten(added), flat)
    assert (v, d) == ("DIFF", "NEW=eip8130.ReceiptVerifier"), (v, d)

    # A nested object where a string was reads as new, never as a walk.
    nested = json.loads(json.dumps(base))
    nested["usdv"] = {"address": "0xU1"}
    v, d = compare(flatten(nested), flat)
    assert "NEW=usdv.address" in d and "GONE=usdv" in d, d

    # A vanished key.
    less = json.loads(json.dumps(base))
    del less["faucetAddress"]
    v, d = compare(flatten(less), flat)
    assert (v, d) == ("DIFF", "GONE=faucetAddress"), (v, d)

    # A moved address on a key the room READS.
    mv = json.loads(json.dumps(base))
    mv["usdv"] = "0xU2"
    v, d = compare(flatten(mv), flat)
    assert (v, d) == ("DIFF", "MOVED=usdv"), (v, d)

    # A moved address on a key nothing reads is SILENT — this is the assertion
    # that keeps the row from firing on every redeploy, so it is the one whose
    # absence would make the check useless rather than wrong.
    quiet = json.loads(json.dumps(base))
    quiet["faucetAddress"] = "0xF2"
    assert compare(flatten(quiet), flat) == ("OK", ""), "an unread address moving is not news"

    # Case is not a move: these are hex addresses and the endpoint has served
    # both casings for the same contract.
    cased = json.loads(json.dumps(base))
    cased["usdv"] = "0xu1"
    assert compare(flatten(cased), flat) == ("OK", ""), "checksum casing is not a redeploy"

    # The snapshot on disk must parse and must be the shape compare() takes.
    snap = load_snapshot()
    assert isinstance(snap.get("keys"), dict) and snap["keys"], "snapshot has no keys"
    assert all(isinstance(v, str) for v in snap["keys"].values()), "snapshot values must be addresses"

    # DRIFT GUARD. `live-integrations.sh` names its own read-set inline for the
    # red row beside this one; if the two stop agreeing, one row's idea of
    # which contract matters is wrong and nothing else would say so.
    with open(LIVE_SH) as f:
        sh = f.read()
    for key in READ:
        name = key.split(".")[-1]
        assert name in sh, f"{name} is in READ here but not named in live-integrations.sh"

    print("vibenet-config-diff: self-test OK (10 checks)")


def main():
    args = sys.argv[1:]
    if "--self-test" in args:
        self_test()
        return 0

    try:
        cfg = fetch()
    except Exception as e:
        # Unreachable is NOT drift. The row above already warns on a config
        # that did not answer; saying it twice reads as two problems.
        print(f"UNREACHABLE {e.__class__.__name__}")
        return 0

    commit = cfg.get("_commit") or "?"
    flat = flatten(cfg)

    if "--accept" in args:
        with open(SNAPSHOT, "w") as f:
            json.dump({"_commit": commit, "keys": flat}, f, indent=2, sort_keys=True)
            f.write("\n")
        print(f"ACCEPTED {commit} ({len(flat)} keys)")
        return 0

    try:
        before = load_snapshot()["keys"]
    except Exception:
        print("NOSNAPSHOT run --accept once to record today's config as the baseline")
        return 0

    verdict, detail = compare(flat, before)
    print(f"{verdict} {commit} {detail}".rstrip())
    return 0


if __name__ == "__main__":
    sys.exit(main())
