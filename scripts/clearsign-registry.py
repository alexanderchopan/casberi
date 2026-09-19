#!/usr/bin/env python3
"""Casberi clear-signing registry — the bundled snapshot of ERC-7730 descriptors.

WHAT. ERC-7730 is the open format a protocol uses to say how its contract calls
read to a person ("Supply 2 WETH as collateral"). The registry the wallets
share (Ledger, Trezor and the rest of the Ethereum Foundation's clear-signing
coalition) is https://github.com/ethereum/clear-signing-erc7730-registry, CC0.
This script turns a checkout of it into the two files Casberi reads:

  Casberi/Casberi/Resources/ClearSignRegistry.json   what the app bundles
  scripts/support/clearsign-vectors.json             the registry's OWN test
                                                     vectors, for the harness

WHY BUNDLED, NOT FETCHED. A descriptor looked up at signing time would tell a
host which contract this phone is about to sign for, and would make the one
screen where a wrong summary costs money depend on a network answer. A pinned
snapshot is read on the device, carries the commit it came from, and changes
only when this script is re-run and the diff is reviewed.

WHAT IT DOES TO A DESCRIPTOR. Everything the spec leaves to the consumer that
is static is resolved HERE so the Swift renderer stays small:
  - `includes` merged (the including file wins; `fields` merge by `path`)
  - `$ref` to `display.definitions` inlined (the field's own keys win)
  - `$.metadata.constants.*` and `$.metadata.enums.*` references inlined
  - groups flattened into one ordered field list (paths concatenated)
  - only the Safe room's six chains are kept (1, 10, 100, 137, 8453, 42161)
EIP-712 descriptors are not bundled: nothing in Casberi signs a typed message.

  scripts/clearsign-registry.py [<registry checkout>]   (clones HEAD when omitted)
"""
import json, os, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Casberi/Casberi/Resources/ClearSignRegistry.json")
VECTORS = os.path.join(ROOT, "scripts/support/clearsign-vectors.json")
REPO = "https://github.com/ethereum/clear-signing-erc7730-registry"
# `SafeBridge.chains` — the chains a Safe proposal can arrive on.
CHAINS = {1, 10, 100, 137, 8453, 42161}


def load(path, seen=()):
    """A descriptor with its `includes` merged in, recursively."""
    if path in seen:
        raise SystemExit(f"include cycle at {path}")
    with open(path) as f:
        doc = json.load(f)
    inc = doc.pop("includes", None)
    if inc:
        base = load(os.path.normpath(os.path.join(os.path.dirname(path), inc)), seen + (path,))
        doc = merge(base, doc)
    return doc


def merge(base, over):
    """The spec's merge: the including file wins, and a `fields` array merges
    by `path` (a shared path overrides, a new one appends)."""
    if isinstance(base, dict) and isinstance(over, dict):
        out = dict(base)
        for k, v in over.items():
            if k == "fields" and isinstance(v, list) and isinstance(base.get(k), list):
                out[k] = merge_fields(base[k], v)
            elif k in out:
                out[k] = merge(out[k], v)
            else:
                out[k] = v
        return out
    return over


def merge_fields(base, over):
    out = [dict(f) for f in base]
    index = {f.get("path"): i for i, f in enumerate(out) if f.get("path") is not None}
    for f in over:
        p = f.get("path")
        if p is not None and p in index:
            out[index[p]] = merge(out[index[p]], f)
        else:
            out.append(f)
    return out


def lookup(doc, ref):
    """`$.a.b.c` in the merged descriptor, or None."""
    if not isinstance(ref, str) or not ref.startswith("$."):
        return None
    node = doc
    for part in ref[2:].split("."):
        if not isinstance(node, dict) or part not in node:
            return None
        node = node[part]
    return node


def text(v):
    """Every scalar a renderer compares or prints, as a STRING: a JSON number
    decoded as a Double loses a uint256 threshold's low digits, so no number
    reaches the app as a number."""
    if isinstance(v, bool):
        return v
    if isinstance(v, (int, float)):
        return str(int(v)) if float(v).is_integer() else str(v)
    if isinstance(v, list):
        return [text(x) for x in v]
    if isinstance(v, dict):
        return {k: text(x) for k, x in v.items()}
    return v


def resolve_params(doc, params):
    out = {}
    for k, v in (params or {}).items():
        if k == "$ref":
            enum = lookup(doc, v)
            if isinstance(enum, dict):
                out["enum"] = {str(a): str(b) for a, b in enum.items()}
            continue
        if isinstance(v, str) and v.startswith("$."):
            v = lookup(doc, v)
            if v is None:
                continue
        elif isinstance(v, list):
            v = [lookup(doc, x) if isinstance(x, str) and x.startswith("$.") else x for x in v]
        out[k] = text(v)
    return out


def join(prefix, path):
    if not prefix:
        return path
    if path is None:
        return prefix
    if path.startswith(("#.", "@.", "$.")):
        return path
    return prefix + "." + path


def flatten(doc, fields, prefix=None):
    """Groups flattened, `$ref`s inlined, constants resolved — one ordered list."""
    out = []
    for f in fields or []:
        if "fields" in f:
            out += flatten(doc, f["fields"], join(prefix, f.get("path")))
            continue
        if "$ref" in f:
            base = lookup(doc, f["$ref"]) or {}
            f = merge(base, {k: v for k, v in f.items() if k != "$ref"})
        field = {}
        if "path" in f:
            field["path"] = join(prefix, f["path"])
        elif "value" in f:
            v = f["value"]
            if isinstance(v, str) and v.startswith("$."):
                v = lookup(doc, v)
                if v is None:
                    continue
            field["value"] = text(v)
        else:
            continue
        for k in ("label", "format", "visible", "separator"):
            if k in f:
                field[k] = text(f[k])
        params = resolve_params(doc, f.get("params"))
        # A `…Path` parameter inside a group is relative to the group, exactly
        # like the field's own path — Paraswap's `tokenPath: "srcToken"` sits
        # in a `swapData` group and means `swapData.srcToken`.
        for k, v in list(params.items()):
            if k.endswith("Path") and isinstance(v, str):
                params[k] = join(prefix, v)
        if params:
            field["params"] = params
        if "encryption" in f:
            field["encrypted"] = f["encryption"].get("fallbackLabel") or "[Encrypted]"
        out.append(field)
    return out


def intent_text(intent):
    if isinstance(intent, dict):
        return ", ".join(f"{k}: {v}" for k, v in intent.items())
    return intent


def compact(doc):
    meta = doc.get("metadata", {})
    formats = []
    for key, spec in sorted(doc.get("display", {}).get("formats", {}).items()):
        entry = {"key": key, "fields": flatten(doc, spec.get("fields"))}
        if spec.get("intent") is not None:
            entry["intent"] = intent_text(spec["intent"])
        if spec.get("interpolatedIntent"):
            entry["interpolatedIntent"] = spec["interpolatedIntent"]
        formats.append(entry)
    out = {"formats": formats}
    name = meta.get("contractName") or doc.get("context", {}).get("$id")
    if meta.get("owner"):
        out["owner"] = meta["owner"]
    if name:
        out["name"] = name
    return out


# --- the registry's own test vectors -------------------------------------------

def rlp(data, i=0):
    """(item, next index). Items are bytes or lists."""
    b = data[i]
    if b < 0x80:
        return data[i:i + 1], i + 1
    if b < 0xb8:
        n = b - 0x80
        return data[i + 1:i + 1 + n], i + 1 + n
    if b < 0xc0:
        ll = b - 0xb7
        n = int.from_bytes(data[i + 1:i + 1 + ll], "big")
        s = i + 1 + ll
        return data[s:s + n], s + n
    if b < 0xf8:
        n, s = b - 0xc0, i + 1
    else:
        ll = b - 0xf7
        n = int.from_bytes(data[i + 1:i + 1 + ll], "big")
        s = i + 1 + ll
    items, j = [], s
    while j < s + n:
        item, j = rlp(data, j)
        items.append(item)
    return items, s + n


def num(b):
    return int.from_bytes(b, "big") if b else 0


def parse_tx(raw):
    """chainId, to, value, data out of a raw (signed or unsigned) transaction."""
    d = bytes.fromhex(raw[2:] if raw.startswith("0x") else raw)
    if d[0] >= 0xc0:  # legacy
        f, _ = rlp(d)
        v = num(f[6]) if len(f) > 6 else 0
        unsigned = len(f) == 9 and not f[7] and not f[8]   # EIP-155 pre-image: [..., chainId, 0, 0]
        chain = v if unsigned else ((v - 35) // 2 if v >= 35 else None)
        return chain, f[3], num(f[4]), f[5]
    f, _ = rlp(d, 1)
    if d[0] == 0x02:   # [chainId, nonce, maxPriority, maxFee, gas, to, value, data, ...]
        return num(f[0]), f[5], num(f[6]), f[7]
    if d[0] == 0x01:   # [chainId, nonce, gasPrice, gas, to, value, data, ...]
        return num(f[0]), f[4], num(f[5]), f[6]
    return None


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else None
    tmp = None
    if not src:
        tmp = tempfile.mkdtemp()
        src = os.path.join(tmp, "reg")
        subprocess.run(["git", "clone", "-q", "--depth", "1", REPO, src], check=True)
    commit = subprocess.run(["git", "-C", src, "log", "-1", "--format=%H %cs"],
                            capture_output=True, text=True, check=True).stdout.split()

    with open(os.path.join(src, "index.calldata.json")) as f:
        index = json.load(f)
    by_file, contracts, tokens = {}, {}, {}
    for caip, rel in sorted(index.items()):
        _, chain, address = caip.split(":")
        if int(chain) not in CHAINS:
            continue
        path = os.path.join(src, rel)
        if rel not in by_file:
            doc = load(path)
            by_file[rel] = (len(by_file), compact(doc), doc)
        i, _, doc = by_file[rel]
        contracts[f"{chain}:{address.lower()}"] = i
        token = doc.get("metadata", {}).get("token")
        if token and token.get("ticker") and token.get("decimals") is not None:
            tokens[f"{chain}:{address.lower()}"] = {"ticker": token["ticker"],
                                                     "decimals": int(token["decimals"])}
    descriptors = [c for _, c, _ in sorted(by_file.values(), key=lambda t: t[0])]
    bundle = {
        "source": {"repo": REPO, "commit": commit[0], "date": commit[1], "license": "CC0-1.0"},
        "contracts": contracts,
        "tokens": tokens,
        "descriptors": descriptors,
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        json.dump(bundle, f, separators=(",", ":"), sort_keys=True)
        f.write("\n")

    # Vectors: every registry test whose transaction lands on a bundled contract.
    vectors = []
    for rel in sorted(by_file):
        d = os.path.dirname(os.path.join(src, rel))
        stem = os.path.basename(rel)[:-len(".json")]
        for sub in ("tests", "testsv2"):
            tf = os.path.join(d, sub, stem + ".tests.json")
            if not os.path.exists(tf):
                continue
            with open(tf) as f:
                suite = json.load(f)
            provider = suite.get("dataProvider", {})
            for t in suite.get("tests", []):
                exp = t.get("expected")
                if not exp:
                    continue
                parsed = parse_tx(t["rawTx"])
                if not parsed or parsed[0] not in CHAINS or len(parsed[1]) != 20:
                    continue
                chain, to, value, data = parsed
                vectors.append({
                    "file": f"{rel.split('/')[1]}/{sub}/{stem}",
                    "description": t.get("description", ""),
                    "chainId": chain, "to": "0x" + to.hex(), "value": str(value),
                    "data": "0x" + data.hex(), "from": t.get("from"),
                    "tokens": {k.lower(): {"ticker": v.get("symbol"), "decimals": v.get("decimals")}
                               for k, v in provider.get("tokens", {}).items()},
                    "names": {k.lower(): v for k, v in {**provider.get("addressNames", {}),
                                                         **provider.get("ensNames", {})}.items()},
                    "collections": {k.lower(): v for k, v in
                                    provider.get("nftCollectionNames", {}).items()},
                    "expected": exp,
                })
    with open(VECTORS, "w") as f:
        json.dump({"source": bundle["source"], "vectors": vectors}, f, indent=1, sort_keys=True)
        f.write("\n")
    print(f"clearsign-registry: {commit[0][:10]} ({commit[1]}) — {len(descriptors)} descriptors, "
          f"{len(contracts)} deployments, {len(tokens)} tokens, {len(vectors)} vectors, "
          f"{os.path.getsize(OUT) // 1024} KB bundled")


if __name__ == "__main__":
    main()
