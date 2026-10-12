#!/usr/bin/env python3
"""Casberi's own ERC-7730 descriptors, merged into the bundled registry (prd §1282).

WHAT. `scripts/support/clearsign-casberi.json` describes calls the Ethereum
Foundation's registry does not: zFi's router and order boards, Tacit's pools
and CoW Protocol's settlement contract. Each is read off the contract's own
published source and says `owner: Casberi`, so the Safe sign block draws
"Described by Casberi", never a protocol's name over words it did not write.

HOW. The bundle (`Casberi/Casberi/Resources/ClearSignRegistry.json`) keeps the
upstream snapshot first and these after it; `casberi.base` records where the
upstream list ends, so a re-run strips the previous merge before adding this
one. An address the upstream registry also describes keeps upstream's words.
`scripts/clearsign-registry.py` runs this after writing a fresh snapshot.

  scripts/clearsign-casberi.py
"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Overridable so `clearsign-casberi-selftest.sh` merges into temp copies.
BUNDLE = os.environ.get("CLEARSIGN_BUNDLE") or os.path.join(ROOT, "Casberi/Casberi/Resources/ClearSignRegistry.json")
SOURCE = os.environ.get("CLEARSIGN_CASBERI") or os.path.join(ROOT, "scripts/support/clearsign-casberi.json")
FORMAT_KEYS = ("key", "intent", "interpolatedIntent", "fields", "when")


def main():
    with open(BUNDLE) as f:
        bundle = json.load(f)
    with open(SOURCE) as f:
        ours = json.load(f)

    # Strip the previous merge: everything at or past `base` is ours.
    base = bundle.get("casberi", {}).get("base", len(bundle["descriptors"]))
    bundle["descriptors"] = bundle["descriptors"][:base]
    bundle["contracts"] = {k: i for k, i in bundle["contracts"].items() if i < base}

    added, skipped = 0, []
    for d in ours["descriptors"]:
        if d.get("owner") != "Casberi":
            sys.exit(f"✗ {d.get('name')}: a Casberi descriptor must say owner Casberi")
        index = len(bundle["descriptors"])
        bundle["descriptors"].append({
            "owner": "Casberi",
            "name": d["name"],
            "formats": [{k: fmt[k] for k in FORMAT_KEYS if k in fmt} for fmt in d["formats"]],
        })
        for chain, addresses in d["deployments"].items():
            for a in addresses:
                key = f"{int(chain)}:{a.lower()}"
                if key in bundle["contracts"]:
                    skipped.append(key)   # upstream describes it: its words win
                    continue
                bundle["contracts"][key] = index
                added += 1
    bundle["casberi"] = {"base": base, "source": "scripts/support/clearsign-casberi.json"}

    with open(BUNDLE, "w") as f:
        json.dump(bundle, f, separators=(",", ":"), sort_keys=True)
        f.write("\n")
    print(f"clearsign-casberi: {len(ours['descriptors'])} descriptors, {added} deployments"
          + (f", {len(skipped)} left to upstream ({', '.join(skipped)})" if skipped else ""))


if __name__ == "__main__":
    main()
