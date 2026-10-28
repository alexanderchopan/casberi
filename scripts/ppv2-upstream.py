#!/usr/bin/env python3
"""What 0xBow changed in Privacy Pools v2 since we last looked (prd §1583).

Private money runs 0xBow's v2 SDK in the engine's web view (§1540, §1544) and
is live on Ethereum (§1563). Nothing told us when 0xBow shipped: the SDK is
pinned at one version (`tools/privacy-pools-engine/package.json`), its circuits
by hash (`PrivacyArtifactPins.swift`), its contracts by address
(`PrivacyEngineWire.swift`'s `ethereum`). This reads five things against the
reviewed state in `tools/privacy-pools-engine/upstream.json`:

  1. npm      — versions of @0xbow/privacy-pools-v2-sdk past the pinned one.
  2. circuits — the newest version's DEFAULT_CIRCUIT_MANIFEST against the
                pinned version's (the manifest `pins.mjs` reads).
  3. repo     — commits on 0xbow-io/privacy-pools-v2-monorepo past the
                reviewed one, under the paths the engine depends on; new
                files in `audits/`; branches new or moved.
  4. proxies  — each pinned mainnet contract's EIP-1967 implementation and
                beacon slots and a fingerprint of its code: an upgrade changes
                behaviour with no SDK release.
  5. relayer  — the production relayer's `/v1/details/evm/1`: an address it
                names that the app does not pin.

CONTRACT:
  * WARN-ONLY. Always exits 0, as `live-integrations.sh` does: a change
    upstream is information to review, not a broken build. Not in verify.sh.
  * A check whose host cannot be reached says "not reached", never
    "unchanged".
  * It never edits pins, the engine or app code. `--accept` writes the state
    it observed into upstream.json, for after a person reviewed the report;
    a check that was not reached keeps its old reviewed state.
  * Keyless. `PPV2_RPC` overrides the Ethereum node (default: the app's own,
    read from PrivacyEngineWire.swift).

Usage:
  python3 scripts/ppv2-upstream.py            the report, Markdown, on stdout
  python3 scripts/ppv2-upstream.py --accept   the report, then record it
  python3 scripts/ppv2-upstream.py --self-test

Stdlib only. Downloaded content (the npm tarball, the repo) is parsed as text
and never executed.
"""
import hashlib
import datetime
import io
import json
import os
import pathlib
import re
import subprocess
import sys
import tarfile
import tempfile
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
ENGINE = ROOT / "tools" / "privacy-pools-engine"
MARKER = ENGINE / "upstream.json"
WIRE = ROOT / "Casberi" / "Casberi" / "Model" / "PrivacyEngineWire.swift"

PACKAGE = "@0xbow/privacy-pools-v2-sdk"
REPO = "https://github.com/0xbow-io/privacy-pools-v2-monorepo"
# The engine bundles core-sdk and evm-sdk (published together as PACKAGE),
# proves with circuits, and talks to the contracts and the relayer.
WATCHED = ["packages/core-sdk", "packages/evm-sdk", "packages/circuits",
           "packages/contracts", "packages/relayer", "audits", "CHANGELOG.md"]

IMPL_SLOT = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"
BEACON_SLOT = "0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50"
ZERO_WORD = "0x" + "0" * 64
TIMEOUT = 30


class Unreached(Exception):
    """A host the check needs did not answer."""


# ---------------------------------------------------------------- pure parts

def version_key(v):
    """Semver order for x.y.z with an optional -pre suffix (pre sorts first)."""
    core, _, pre = v.partition("-")
    nums = tuple(int(p) if p.isdigit() else 0 for p in core.split("."))
    return nums + ((1,) if not pre else (0, pre))


def newer_versions(versions, pinned):
    return sorted((v for v in versions if version_key(v) > version_key(pinned)), key=version_key)


def manifest_from_bundle(src):
    """DEFAULT_CIRCUIT_MANIFEST out of the SDK's dist/index.js, as pins.mjs reads it."""
    start = src.find("var DEFAULT_CIRCUIT_MANIFEST = {")
    if start < 0:
        return None
    body = src[start:src.find("\n};", start)]
    entries = {}
    for m in re.finditer(r"(\w+): \{([^}]*)\}", body):
        entries[m.group(1)] = dict(re.findall(r'(\w+): "([^"]*)"', m.group(2)))
    return entries


def manifest_diff(old, new):
    """Lines naming each circuit entry added, removed or changed."""
    lines = []
    for name in sorted(set(old) | set(new)):
        if name not in new:
            lines.append(f"removed `{name}`")
        elif name not in old:
            lines.append(f"added `{name}`")
        elif old[name] != new[name]:
            fields = sorted(k for k in set(old[name]) | set(new[name]) if old[name].get(k) != new[name].get(k))
            lines.append(f"changed `{name}` ({', '.join(fields)})")
    return lines


def mainnet_from_wire(swift):
    """The `ethereum` network's URLs and every pinned address, by name."""
    start = swift.find("static let ethereum = PrivacyNetwork(")
    if start < 0:
        raise ValueError("no `static let ethereum` in PrivacyEngineWire.swift")
    end = swift.find("\n        ])", start)
    block = swift[start:end if end > 0 else len(swift)]
    urls = dict(re.findall(r'(rpcUrl|relayerUrl): "([^"]+)"', block))
    addresses = {}
    head = block.split("yield:", 1)[0]
    for name, addr in re.findall(r'(\w+): "(0x[0-9a-fA-F]{40})"', head):
        addresses.setdefault(name, addr)
    for pool in re.finditer(r'YieldPool\(symbol: "(\w+)"(.*?)\)', block, re.S):
        for name, addr in re.findall(r'(\w+): "(0x[0-9a-fA-F]{40})"', pool.group(2)):
            addresses[f"{pool.group(1)}.{name}"] = addr
    return urls, addresses


def word_address(word):
    """The address in a storage word, or None for an empty slot."""
    if not word or word.lower() == ZERO_WORD:
        return None
    return "0x" + word[-40:].lower()


def addresses_in(obj):
    """Every 20-byte hex string anywhere in a JSON value, lowercased."""
    found = set()
    if isinstance(obj, dict):
        for v in obj.values():
            found |= addresses_in(v)
    elif isinstance(obj, list):
        for v in obj:
            found |= addresses_in(v)
    elif isinstance(obj, str):
        found |= {m.lower() for m in re.findall(r"0x[0-9a-fA-F]{40}(?![0-9a-fA-F])", obj)}
    return found


def compare_contracts(reviewed, observed):
    """Lines naming each pinned contract whose implementation, beacon or code moved."""
    lines = []
    for name in sorted(observed):
        was, now = reviewed.get(name), observed[name]
        if was is None:
            lines.append(f"`{name}`: first reading (impl {now.get('impl') or 'none'})")
            continue
        for field in ("impl", "beacon", "code"):
            if was.get(field) != now.get(field):
                lines.append(f"`{name}` {field}: {was.get(field) or 'none'} → {now.get(field) or 'none'}")
    return lines


def compare_branches(reviewed, observed):
    lines = []
    for b in sorted(set(observed) - set(reviewed)):
        lines.append(f"new branch `{b}` at {observed[b][:8]}")
    for b in sorted(set(reviewed) & set(observed)):
        if reviewed[b] != observed[b]:
            lines.append(f"`{b}` moved {reviewed[b][:8]} → {observed[b][:8]}")
    for b in sorted(set(reviewed) - set(observed)):
        lines.append(f"branch `{b}` deleted")
    return lines


# ------------------------------------------------------------------- network

def get(url, data=None):
    req = urllib.request.Request(url, data=data, headers={"content-type": "application/json",
                                                          "user-agent": "casberi-ppv2-upstream"})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return r.read()
    except Exception as e:  # noqa: BLE001 — any failure to reach is one outcome
        raise Unreached(f"{urllib.parse.urlsplit(url).hostname}: {e}") from None


def rpc(url, method, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    answer = json.loads(get(url, body))
    if "error" in answer:
        raise Unreached(f"{method}: {answer['error']}")
    return answer["result"]


def git(*args, cwd=None):
    try:
        return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True,
                              text=True, timeout=300).stdout
    except Exception as e:  # noqa: BLE001
        raise Unreached(f"git {args[0]}: {e}") from None


# -------------------------------------------------------------------- checks

def check_npm(pinned, marker):
    meta = json.loads(get(f"https://registry.npmjs.org/{PACKAGE.replace('/', '%2f')}"))
    versions = list(meta.get("versions", {}))
    latest = meta.get("dist-tags", {}).get("latest")
    newer = newer_versions(versions, pinned)
    lines = [f"`{v}` published {meta.get('time', {}).get(v, '?')[:10]}" for v in newer]
    return {"latest": latest, "newer": newer}, lines, meta


def check_circuits(pinned, newest, meta):
    def bundle(version):
        url = meta["versions"][version]["dist"]["tarball"]
        with tarfile.open(fileobj=io.BytesIO(get(url)), mode="r:gz") as tar:
            member = tar.extractfile("package/dist/index.js")
            return manifest_from_bundle(member.read().decode("utf-8", "replace")) if member else None
    old, new = bundle(pinned), bundle(newest)
    if old is None or new is None:
        raise Unreached("no DEFAULT_CIRCUIT_MANIFEST in a bundle")
    return manifest_diff(old, new)


def check_repo(marker):
    heads = {}
    for line in git("ls-remote", REPO, "refs/heads/*").splitlines():
        sha, ref = line.split("\t")
        heads[ref.removeprefix("refs/heads/")] = sha
    if "main" not in heads:
        raise Unreached("no main branch on the remote")
    reviewed = marker.get("repo", {})
    lines = compare_branches(reviewed.get("branches", {}), {b: s for b, s in heads.items() if b != "main"})
    commits, added = [], []
    base = reviewed.get("main")
    if base and base != heads["main"]:
        with tempfile.TemporaryDirectory() as tmp:
            git("clone", "-q", "--filter=blob:none", "--no-checkout", REPO, tmp)
            known = subprocess.run(["git", "cat-file", "-e", base + "^{commit}"], cwd=tmp).returncode == 0
            if not known:
                lines.append(f"reviewed commit {base[:8]} is no longer on the remote (history rewritten?)")
            else:
                commits = git("log", "--format=%h %cs %s", f"{base}..{heads['main']}", "--", *WATCHED, cwd=tmp).splitlines()
                added = [l.split("\t", 1)[1] for l in git("diff", "--name-status", "--diff-filter=A", base,
                                                          heads["main"], "--", "audits", cwd=tmp).splitlines()]
                total = len(git("rev-list", f"{base}..{heads['main']}", cwd=tmp).split())
                lines.insert(0, f"main moved {base[:8]} → {heads['main'][:8]}: {total} commits, "
                                f"{len(commits)} under the watched paths")
    lines += [f"commit {c}" for c in commits] + [f"new audit file `{a}`" for a in added]
    return {"main": heads["main"], "branches": {b: s for b, s in heads.items() if b != "main"}}, lines


def check_contracts(node, addresses, marker):
    observed = {}
    for name, addr in sorted(addresses.items()):
        if name in ("relayerAddress", "transferProcessor") or name.endswith(".underlying"):
            continue  # an EOA, or a token the pool does not own (WETH, USDC)
        code = rpc(node, "eth_getCode", [addr, "latest"])
        observed[name] = {
            "address": addr,
            "impl": word_address(rpc(node, "eth_getStorageAt", [addr, IMPL_SLOT, "latest"])),
            "beacon": word_address(rpc(node, "eth_getStorageAt", [addr, BEACON_SLOT, "latest"])),
            "code": hashlib.sha256(code.encode()).hexdigest()[:16] if code not in ("0x", None) else None,
        }
    return observed, compare_contracts(marker.get("contracts", {}), observed)


def check_relayer(relayer_url, addresses, marker):
    details = json.loads(get(relayer_url.rstrip("/") + "/v1/details/evm/1"))
    named = addresses_in(details)
    pinned = {a.lower() for a in addresses.values()}
    seen = set(marker.get("relayer", {}).get("addresses", []))
    lines = [f"names `{a}`, which the app does not pin" + ("" if a not in seen else " (seen before)")
             for a in sorted(named - pinned)]
    lines += [f"no longer names pinned `{a}`" for a in sorted((pinned & seen) - named)]
    return {"addresses": sorted(named)}, lines


# -------------------------------------------------------------------- report

def run(accept):
    marker = json.loads(MARKER.read_text()) if MARKER.exists() else {}
    pinned = json.loads((ENGINE / "package.json").read_text())["dependencies"][PACKAGE]
    urls, addresses = mainnet_from_wire(WIRE.read_text())
    node = os.environ.get("PPV2_RPC") or urls["rpcUrl"]
    sections, state = [], dict(marker)

    def section(title, fn):
        try:
            observed, lines = fn()
            sections.append((title, "changed" if lines else "unchanged", lines))
            return observed
        except Unreached as e:
            sections.append((title, "not reached", [str(e)]))
            return None

    npm_meta = {}

    def npm():
        observed, lines, meta = check_npm(pinned, marker)
        npm_meta["meta"] = meta
        return observed, lines

    npm_state = section(f"npm ({PACKAGE}, pinned {pinned})", npm)
    if npm_state and npm_state["newer"]:
        section(f"circuits ({pinned} → {npm_state['newer'][-1]})",
                lambda: (None, check_circuits(pinned, npm_state["newer"][-1], npm_meta["meta"])))
    else:
        sections.append(("circuits", "unchanged" if npm_state else "not reached",
                         [] if npm_state else ["npm was not reached"]))
    repo_state = section("repo (0xbow-io/privacy-pools-v2-monorepo)", lambda: check_repo(marker))
    contracts = section(f"mainnet contracts (via {urllib.parse.urlsplit(node).hostname})",
                        lambda: check_contracts(node, addresses, marker))
    relayer = section("production relayer", lambda: check_relayer(urls["relayerUrl"], addresses, marker))

    print(f"# Privacy Pools v2 upstream — reviewed {marker.get('reviewedAt', 'never')}\n")
    for title, status, lines in sections:
        print(f"## {title}: {status}")
        for l in lines:
            print(f"- {l}")
        print()

    if accept:
        if npm_state:
            state["npm"] = {"latest": npm_state["latest"]}
        if repo_state:
            state["repo"] = repo_state
        if contracts:
            state["contracts"] = contracts
        if relayer:
            state["relayer"] = relayer
        state["reviewedAt"] = datetime.date.today().isoformat()
        MARKER.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
        print(f"Recorded in {MARKER.relative_to(ROOT)}.")
    return 0


# ----------------------------------------------------------------- self-test

def self_test():
    failures = []

    def ok(cond, what):
        print(("  ok   " if cond else "  FAIL ") + what)
        if not cond:
            failures.append(what)

    ok(newer_versions(["1.0.0", "1.0.2", "1.0.10", "1.1.0-rc.1", "0.9.9"], "1.0.2") == ["1.0.10", "1.1.0-rc.1"],
       "versions past the pin, in semver order (1.0.10 after 1.0.2)")
    ok(version_key("1.1.0-rc.1") < version_key("1.1.0"), "a prerelease sorts before its release")

    bundle = ('x\nvar DEFAULT_CIRCUIT_MANIFEST = {\n  deposit: { wasm: "a", zkey: "b" },\n'
              '  transact_1x1: { wasm: "c", zkey: "d" }\n};\n')
    old = manifest_from_bundle(bundle)
    ok(old == {"deposit": {"wasm": "a", "zkey": "b"}, "transact_1x1": {"wasm": "c", "zkey": "d"}},
       "the manifest parses as pins.mjs parses it")
    new = {"deposit": {"wasm": "a", "zkey": "B"}, "transact_2x2": {"wasm": "e", "zkey": "f"}}
    ok(manifest_diff(old, new) == ["changed `deposit` (zkey)", "removed `transact_1x1`", "added `transact_2x2`"],
       "a changed key, a removed circuit and an added one are each named")
    ok(manifest_diff(old, old) == [], "an unchanged manifest names nothing")
    ok(manifest_from_bundle("no manifest here") is None, "a bundle without a manifest is None, not empty")

    swift = ('    static let ethereum = PrivacyNetwork(\n        rpcUrl: "https://node.example",\n'
             '        relayerUrl: "https://relayer.example",\n'
             '        entrypoint: "0x' + "a" * 40 + '",\n        pool: "0x' + "b" * 40 + '",\n'
             '        yield: [\n            YieldPool(symbol: "ETH", native: true,\n'
             '                      share: "0x' + "c" * 40 + '", router: "0x' + "d" * 40 + '"),\n'
             '            YieldPool(symbol: "USDC", native: false,\n'
             '                      share: "0x' + "e" * 40 + '"),\n        ])\n'
             '    static let sepolia = PrivacyNetwork(\n        pool: "0x' + "f" * 40 + '",\n')
    urls, addrs = mainnet_from_wire(swift)
    ok(urls == {"rpcUrl": "https://node.example", "relayerUrl": "https://relayer.example"}, "the network's URLs")
    ok(addrs == {"entrypoint": "0x" + "a" * 40, "pool": "0x" + "b" * 40, "ETH.share": "0x" + "c" * 40,
                 "ETH.router": "0x" + "d" * 40, "USDC.share": "0x" + "e" * 40},
       "mainnet addresses by name, yield pools by symbol, Sepolia's left out")

    ok(word_address(ZERO_WORD) is None, "an empty slot is no implementation")
    ok(word_address("0x" + "0" * 24 + "ab" * 20) == "0x" + "ab" * 20, "an implementation is the word's low 20 bytes")

    reviewed = {"pool": {"impl": "0x1", "beacon": None, "code": "aa"}}
    ok(compare_contracts(reviewed, {"pool": {"impl": "0x1", "beacon": None, "code": "aa"}}) == [],
       "an unmoved contract names nothing")
    ok(compare_contracts(reviewed, {"pool": {"impl": "0x2", "beacon": None, "code": "aa"}}) ==
       ["`pool` impl: 0x1 → 0x2"], "an upgrade names the old and new implementation")
    ok(len(compare_contracts({}, {"pool": {"impl": None}})) == 1, "a contract with no reviewed state is a first reading")

    ok(compare_branches({"a": "1" * 40, "b": "2" * 40}, {"a": "3" * 40, "c": "4" * 40}) ==
       ["new branch `c` at 44444444", "`a` moved 11111111 → 33333333", "branch `b` deleted"],
       "new, moved and deleted branches are each named")

    ok(addresses_in({"x": ["0x" + "Ab" * 20, {"y": "to 0x" + "cd" * 20 + " and 0x12"}]}) ==
       {"0x" + "ab" * 20, "0x" + "cd" * 20}, "every address in nested JSON, lowercased, none shorter")
    ok(addresses_in("0x" + "a" * 64) == set(), "a 32-byte hash is not an address")

    print(f"{'✓' if not failures else '✗'} ppv2-upstream self-test: {len(failures)} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(self_test())
    sys.exit(run("--accept" in sys.argv))
