#!/usr/bin/env python3
"""uniswap-v4-pools.py — measure the Uniswap v4 pools Swap pins (prd §1678, §1680, §1682).

Swap asks every pool it knows itself (prd §1542): no indexer, no quote
service. A v4 pool is a key (two tokens, a fee, a tick spacing, a hook), not a
factory's address, and the account's own nodes cannot list keys (Base's public
nodes refuse wide log reads, Robinhood's caps them at 10M blocks). So the keys
that hold money are measured HERE, at a desk, and pinned in
`YourAccountSwap.swift`; the four standard keys are asked for every pair
anyway, so only a non-standard key (a hook, an odd fee or spacing) is listed.

    python3 scripts/uniswap-v4-pools.py [--network base] [--min-usd 500000]
        Measure, and print Swift `V4Pool(...)` lines to paste.
    python3 scripts/uniswap-v4-pools.py --check
        DRIFT (nightly, through live-integrations.sh, warn-only): every pool
        holding --min-usd that is not pinned, and every pinned key that no
        longer quotes. Exit 0 clean, 1 drift, 2 the networks could not be read.
    python3 scripts/uniswap-v4-pools.py --self-test
        Offline (full verify, a gate): the parser against the real Swift file,
        the key hash against a measured pool id, the sort, the diff.

Measuring, per network:
  1. GeckoTerminal's busiest Uniswap v4 pools (dev-time only; the app never
     asks it), kept when they hold at least --min-usd.
  2. Each pool's key read off the PoolManager's own `Initialize` log, found by
     its pool id (topic 1), near the block GeckoTerminal says it was created.
  3. The key hashed back to the pool id, and the pool quoted for a small amount
     through the pinned quoter, so a pool that does not answer is never pinned.
A pool of the network's WETH itself is never pinned: Swap's v4 venue swaps ETH.
"""
import argparse, json, os, re, sys, time, urllib.request
from datetime import datetime, timezone

INIT = "0xdd466e674ea557f56295e2d0218a125ea4b4f0f6f3307b95f85e6110838d6438"
NETS = {
    "eth": dict(gt="eth", dex="uniswap-v4-ethereum", rpc="https://rpc.mevblocker.io",
                pm="0x000000000004444c5dc75cb358380d2e3de08a90",
                quoter="0x52f0e24d1c21c8a0cb1e5a5dd6198556bd9e1203", window=60_000, blocktime=12,
                swift="ethereumV4Pools"),
    "base": dict(gt="base", dex="uniswap-v4-base", rpc="https://base.gateway.tenderly.co",
                 pm="0x498581ff718922c3f8e6a244956af099b2652b2b",
                 quoter="0x0d5e0f971ed27fbff6c2837bf31316121532048d", window=1000,
                 genesis=1686789347, blocktime=2, swift="baseV4Pools"),
    "robinhood": dict(gt="robinhood", dex="uniswap-v4-robinhood", rpc="https://rpc.mainnet.chain.robinhood.com",
                      pm="0x8366a39cc670b4001a1121b8f6a443a643e40951",
                      quoter="0x8dc178efb8111bb0973dd9d722ebeff267c98f94", window=10_000_000,
                      swift="robinhoodV4Pools"),
}
STANDARD = {(100, 1), (500, 10), (3000, 60), (10000, 200)}
ZERO = "0x" + "0" * 40
# Each network's WETH: Swap's v4 venue reads it as ETH (`Venue.wethIsETH`),
# so a pool of WETH itself is never asked and is not pinned.
WETH = {"eth": "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", "base": "0x4200000000000000000000000000000000000006",
        "robinhood": "0x0bd7d308f8e1639fab988df18a8011f41eacad73"}
SWIFT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Casberi", "Casberi", "Model", "YourAccountSwap.swift")


# ── Keccak-256, pure (the nightly's Python may have no pycryptodome) ─────────
_RC = [0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000, 0x000000000000808B,
       0x0000000080000001, 0x8000000080008081, 0x8000000000008009, 0x000000000000008A, 0x0000000000000088,
       0x0000000080008009, 0x000000008000000A, 0x000000008000808B, 0x800000000000008B, 0x8000000000008089,
       0x8000000000008003, 0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
       0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008]
_ROT = [[0, 36, 3, 41, 18], [1, 44, 10, 45, 2], [62, 6, 43, 15, 61], [28, 55, 25, 21, 56], [27, 20, 39, 8, 14]]
_M = (1 << 64) - 1


def _rol(v, n): return ((v << n) | (v >> (64 - n))) & _M if n else v


def keccak256(data):
    rate = 136
    msg = bytearray(data) + b"\x01"
    while len(msg) % rate: msg.append(0)
    msg[-1] |= 0x80
    s = [[0] * 5 for _ in range(5)]
    for off in range(0, len(msg), rate):
        for i in range(rate // 8):
            s[i % 5][i // 5] ^= int.from_bytes(msg[off + 8 * i: off + 8 * i + 8], "little")
        for rc in _RC:
            c = [s[x][0] ^ s[x][1] ^ s[x][2] ^ s[x][3] ^ s[x][4] for x in range(5)]
            d = [c[(x - 1) % 5] ^ _rol(c[(x + 1) % 5], 1) for x in range(5)]
            s = [[s[x][y] ^ d[x] for y in range(5)] for x in range(5)]
            b = [[0] * 5 for _ in range(5)]
            for x in range(5):
                for y in range(5):
                    b[y][(2 * x + 3 * y) % 5] = _rol(s[x][y], _ROT[x][y])
            s = [[b[x][y] ^ ((~b[(x + 1) % 5][y]) & b[(x + 2) % 5][y]) for y in range(5)] for x in range(5)]
            s[0][0] ^= rc
    return b"".join(s[i % 5][i // 5].to_bytes(8, "little") for i in range(4))


def word(n): return int(n).to_bytes(32, "big", signed=n < 0)
def addr(a): return int(a, 16).to_bytes(32, "big")


def pool_id(c0, c1, fee, ts, hook):
    return "0x" + keccak256(addr(c0) + addr(c1) + word(fee) + word(ts) + addr(hook)).hex()


# ── Pure: what is pinned, what is not ─────────────────────────────────────────
def parse_pinned(text):
    """Every measured key in the Swift file, per network: {net: {(c0, c1, fee, ts, hook)}}."""
    out = {}
    for net, n in NETS.items():
        m = re.search(r"static let " + n["swift"] + r" = v4Standard \+ \[(.*?)\n    \]", text, re.S)
        keys = set()
        for entry in re.findall(r"V4Pool\((.*?)\)", m.group(1) if m else "", re.S):
            fee = int(re.search(r"fee:\s*(\d+)", entry).group(1))
            ts = int(re.search(r"tickSpacing:\s*(-?\d+)", entry).group(1))
            h = re.search(r'hooks:\s*"(0x[0-9a-f]{40})"', entry)
            p = re.search(r"pair:\s*\[(.*?)\]", entry, re.S)
            pair = [ZERO if t.strip() == "native" else t.strip().strip('"') for t in p.group(1).split(",")] if p else []
            if len(pair) != 2: continue
            c0, c1 = sorted(pair)
            keys.add((c0, c1, fee, ts, h.group(1) if h else ZERO))
        out[net] = keys
    return out


def classify(net, key):
    """'weth' (never asked), 'standard' (asked for every pair) or 'pin'."""
    c0, c1, fee, ts, hook = key
    if WETH[net] in (c0, c1): return "weth"
    if hook == ZERO and (fee, ts) in STANDARD: return "standard"
    return "pin"


def missing(net, measured, pinned):
    """The measured pools a pin would reach and none does, in the order measured."""
    return [(k, name, usd) for k, name, usd in measured if classify(net, k) == "pin" and k not in pinned]


# ── Network ──────────────────────────────────────────────────────────────────
def get(url, body=None):
    for _ in range(6):
        try:
            req = urllib.request.Request(url, data=json.dumps(body).encode() if body else None,
                                         headers={"content-type": "application/json", "accept": "application/json",
                                                  "user-agent": "curl/8"})
            return json.load(urllib.request.urlopen(req, timeout=40))
        except Exception:
            time.sleep(12)
    return {}


def rpc(net, method, params):
    return get(NETS[net]["rpc"], {"jsonrpc": "2.0", "id": 1, "method": method, "params": params})


def key_of(net, pid, created):
    n = NETS[net]
    ts = int(datetime.fromisoformat(created.replace("Z", "+00:00")).timestamp())
    if net == "eth":
        # Slots are 12s but some are missed, so the block a time names is
        # found near, not at, the estimate: a window either side of it.
        head = rpc(net, "eth_getBlockByNumber", ["latest", False])["result"]
        b = int(head["number"], 16) - (int(head["timestamp"], 16) - ts) // n["blocktime"]
        spans = [(hex(b - n["window"]), hex(b + n["window"]))]
    elif net == "base":
        b = (ts - n["genesis"]) // n["blocktime"]
        spans = [(hex(b - 500), hex(b + 499))]
    else:
        head = int(rpc(net, "eth_blockNumber", [])["result"], 16)
        spans = [(hex(max(0, hi - n["window"] + 1)), hex(hi)) for hi in range(head, 0, -n["window"])]
    for lo, hi in spans:
        # A node that is busy answers an error, never an empty list: ask
        # again, slower, so a throttled read is not taken for no pool.
        for wait in (0, 5, 15, 30, 60):
            time.sleep(wait)
            r = rpc(net, "eth_getLogs", [{"address": n["pm"], "fromBlock": lo, "toBlock": hi, "topics": [INIT, pid]}])
            if "result" in r: break
        else:
            raise RuntimeError(f"{n['rpc']} kept refusing: {r.get('error')}")
        logs = r.get("result") or []
        if logs:
            l = logs[0]; d = bytes.fromhex(l["data"][2:])
            return ("0x" + l["topics"][2][-40:], "0x" + l["topics"][3][-40:], int.from_bytes(d[0:32], "big"),
                    int.from_bytes(d[32:64], "big", signed=True), "0x" + d[76:96].hex())
        time.sleep(0.3)
    return None


def quotes(net, key, amount):
    c0, c1, fee, ts, hook = key
    sel = keccak256(b"quoteExactInputSingle(((address,address,uint24,int24,address),bool,uint128,bytes))")[:4]
    data = sel + word(32) + addr(c0) + addr(c1) + word(fee) + word(ts) + addr(hook) + word(1) + word(amount) + word(256) + word(0)
    r = rpc(net, "eth_call", [{"to": NETS[net]["quoter"], "data": "0x" + data.hex()}, "latest"])
    return "result" in r and int(r["result"][2:66] or "0", 16) > 0


def answers(net, key):
    small = 10 ** 12  # a millionth of an 18-decimal token, or a million units at 6
    return quotes(net, key, small) or quotes(net, key, small * 1000)


def measure(net, min_usd, pages, say):
    """The pools holding min_usd, keyed and quoted: [(key, name, usd)]; says what it skips."""
    out, seen = [], set()
    for page in range(1, pages + 1):
        data = get(f"https://api.geckoterminal.com/api/v2/networks/{NETS[net]['gt']}/dexes/{NETS[net]['dex']}"
                   f"/pools?page={page}&sort=h24_volume_usd_desc").get("data", [])
        time.sleep(2.5)
        for p in data:
            at = p["attributes"]; pid = at["address"]; usd = float(at.get("reserve_in_usd") or 0)
            if usd < min_usd or pid in seen: continue
            seen.add(pid)
            try:
                k = key_of(net, pid, at["pool_created_at"])
            except RuntimeError as e:
                say(f"// ? {at['name']} {pid}: {e}"); continue
            if not k:
                say(f"// ✗ {at['name']} {pid}: no Initialize log found"); continue
            if pool_id(*k) != pid:
                say(f"// ✗ {at['name']} {pid}: the key does not hash to the pool id"); continue
            kind = classify(net, k)
            if kind == "weth": say(f"// · {at['name']} (${usd:,.0f}): a pool of WETH itself, not asked"); continue
            if kind == "standard": say(f"// · {at['name']} (${usd:,.0f}): a standard key, asked for every pair"); continue
            if not answers(net, k):
                say(f"// ✗ {at['name']} {pid}: the quoter does not answer"); continue
            out.append((k, at["name"], usd))
    return out


def swift_line(key, name, usd):
    c0, c1, fee, ts, hook = key
    h = f', hooks: "{hook}"' if hook != ZERO else ""
    pair = ", ".join("native" if t == ZERO else f'"{t}"' for t in (c0, c1))
    return f"V4Pool(fee: {fee}, tickSpacing: {ts}{h},\n       pair: [{pair}]),  // {name}, ${usd:,.0f}"


# ── Self-test (offline) ──────────────────────────────────────────────────────
def self_test():
    bad = []
    def check(ok, what):
        if not ok: bad.append(what)
    check(keccak256(b"").hex() == "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470", "keccak256('') is wrong")
    aztec = (ZERO, "0xa27ec0006e59f245217ff08cd52a7e8b169e62d2", 500, 10, "0xd53006d1e3110fd319a79aeec4c527a0d265e080")
    check(pool_id(*aztec) == "0xce2899b16743cfd5a954d8122d5e07f410305b1aebee39fd73d9f3b9ebf10c2f",
          "AZTEC/ETH's key does not hash to its measured pool id")
    check(classify("eth", aztec) == "pin", "a hooked key is not pinned")
    check(classify("eth", (ZERO, "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", 500, 10, ZERO)) == "standard", "a standard key is pinned")
    check(classify("eth", (ZERO, "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", 500, 11, ZERO)) == "pin", "an odd spacing is not pinned")
    check(classify("base", ("0x20bcbe0d0726dd063caf5ff72fa3ba591c9e7d46", WETH["base"], 0, 60, "0x" + "b" * 40)) == "weth",
          "a pool of WETH itself is pinned")
    sample = '''    static let ethereumV4Pools = v4Standard + [
        V4Pool(fee: 500, tickSpacing: 10, hooks: "0xd53006d1e3110fd319a79aeec4c527a0d265e080",
               pair: [native, "0xa27ec0006e59f245217ff08cd52a7e8b169e62d2"]),  // AZTEC / ETH
        V4Pool(fee: 7, tickSpacing: 1,
               pair: ["0xdac17f958d2ee523a2206206994597c13d831ec7", "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"]),
    ]'''
    parsed = parse_pinned(sample)["eth"]
    usdc_usdt = ("0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", "0xdac17f958d2ee523a2206206994597c13d831ec7", 7, 1, ZERO)
    check(parsed == {aztec, usdc_usdt}, f"the parser misread native, a default hook or an unsorted pair: {parsed}")
    new = ("0x1111111111111111111111111111111111111111", "0x2222222222222222222222222222222222222222", 250, 3, ZERO)
    std = (ZERO, "0x3333333333333333333333333333333333333333", 3000, 60, ZERO)
    found = missing("eth", [(aztec, "AZTEC", 1e7), (new, "NEW", 6e5), (std, "STD", 9e6)], parsed)
    check([k for k, _, _ in found] == [new], f"the drift is not exactly the unpinned non-standard pool: {found}")
    line = swift_line(aztec, "AZTEC / ETH", 1.2e7)
    check(parse_pinned("    static let ethereumV4Pools = v4Standard + [\n        " + line + "\n    ]")["eth"] == {aztec},
          "a printed line does not parse back to its key")
    try:
        real = parse_pinned(open(SWIFT).read())
    except OSError:
        real = {}
    check(all(real.get(n) for n in NETS) and aztec in real.get("eth", set()),
          "the shipped YourAccountSwap.swift no longer parses: every network's list read empty, or AZTEC/ETH is gone")
    check(all(classify(n, k) == "pin" for n in real for k in real[n]),
          "a pinned key is standard or a pool of WETH itself, which v4 never asks")
    for b in bad: print("✗ " + b)
    print("uniswap-v4-pools self-test: " + ("OK" if not bad else f"{len(bad)} failure(s)"))
    return 0 if not bad else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--network", choices=list(NETS), action="append")
    ap.add_argument("--min-usd", type=float, default=500_000)
    ap.add_argument("--pages", type=int, default=3)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    if a.self_test: return self_test()
    nets = a.network or list(NETS)
    if not a.check:
        for net in nets:
            print(f"// {net}: Uniswap v4 pools holding ≥ ${a.min_usd:,.0f}, measured {datetime.now(timezone.utc):%Y-%m-%d}")
            for k, name, usd in measure(net, a.min_usd, a.pages, print):
                print(swift_line(k, name, usd))
        return 0
    pinned = parse_pinned(open(SWIFT).read())
    drift, read = 0, 0
    for net in nets:
        found = measure(net, a.min_usd, a.pages, lambda _: None)
        read += 1 if found or pinned[net] else 0
        for k, name, usd in missing(net, found, pinned[net]):
            drift += 1
            print(f"{net}: {name} (${usd:,.0f}) is not pinned — run scripts/uniswap-v4-pools.py --network {net} and paste:")
            print("    " + swift_line(k, name, usd).replace("\n", "\n    "))
        for k in sorted(pinned[net]):
            if not answers(net, k):
                drift += 1
                print(f"{net}: pinned {k[0][:10]}…/{k[1][:10]}… fee {k[2]} no longer quotes — drop it from {NETS[net]['swift']}")
    if not read:
        print("the networks could not be read"); return 2
    print(f"uniswap-v4-pools: {'no drift' if not drift else f'{drift} drift'} on {', '.join(nets)}")
    return 1 if drift else 0


if __name__ == "__main__":
    sys.exit(main())
