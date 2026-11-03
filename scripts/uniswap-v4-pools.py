#!/usr/bin/env python3
"""uniswap-v4-pools.py — measure the Uniswap v4 pools Swap pins (prd §1678, §1680).

Swap asks every pool it knows itself (prd §1542): no indexer, no quote
service. A v4 pool is a key (two tokens, a fee, a tick spacing, a hook), not a
factory's address, and the account's own nodes cannot list keys (Base's public
nodes refuse wide log reads, Robinhood's caps them at 10M blocks). So the keys
that hold money are measured HERE, at a desk, and pinned in
`YourAccountSwap.swift`; the four standard keys are asked for every pair
anyway, so only a non-standard key (a hook, an odd fee or spacing) is listed.

What it does, per network:
  1. GeckoTerminal's busiest Uniswap v4 pools (dev-time only; the app never
     asks it), kept when they hold at least --min-usd.
  2. Each pool's key read off the PoolManager's own `Initialize` log, found by
     its pool id (topic 1), near the block GeckoTerminal says it was created.
  3. The key's pool id recomputed from the key and checked against the log's,
     and the pool quoted for a small amount through the pinned V4Quoter, so a
     pool that does not answer is never pinned.
Prints Swift `V4Pool(...)` lines, one per kept pool, with its pair, fee words
and what it held.

    python3 scripts/uniswap-v4-pools.py [--min-usd 500000] [--network base]

Needs pycryptodome (keccak). Network only; nothing it prints is trusted until
`direct-swap-selftest.sh` and a simulation pass.
"""
import argparse, json, sys, time, urllib.request
from datetime import datetime, timezone
from Crypto.Hash import keccak

INIT = "0xdd466e674ea557f56295e2d0218a125ea4b4f0f6f3307b95f85e6110838d6438"
NETS = {
    "eth": dict(gt="eth", rpc="https://rpc.mevblocker.io", pm="0x000000000004444c5dc75cb358380d2e3de08a90",
                quoter="0x52f0e24d1c21c8a0cb1e5a5dd6198556bd9e1203", window=60_000, blocktime=12),
    "base": dict(gt="base", rpc="https://base.gateway.tenderly.co", pm="0x498581ff718922c3f8e6a244956af099b2652b2b",
                 quoter="0x0d5e0f971ed27fbff6c2837bf31316121532048d", window=1000,
                 genesis=1686789347, blocktime=2),
    "robinhood": dict(gt="robinhood", rpc="https://rpc.mainnet.chain.robinhood.com",
                      pm="0x8366a39cc670b4001a1121b8f6a443a643e40951",
                      quoter="0x8dc178efb8111bb0973dd9d722ebeff267c98f94", window=10_000_000),
}
STANDARD = {(100, 1), (500, 10), (3000, 60), (10000, 200)}
# Each network's WETH: Swap's v4 venue reads it as ETH (`Venue.wethIsETH`),
# so a pool of WETH itself is never asked and is not pinned.
WETH = {"eth": "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", "base": "0x4200000000000000000000000000000000000006",
        "robinhood": "0x0bd7d308f8e1639fab988df18a8011f41eacad73"}
ZERO = "0x" + "0" * 40


def keccak256(b):
    h = keccak.new(digest_bits=256); h.update(b); return h.digest()


def word(n): return int(n).to_bytes(32, "big", signed=n < 0) if n < 0 else int(n).to_bytes(32, "big")
def addr(a): return int(a, 16).to_bytes(32, "big")


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
    topics = [INIT, pid]
    if net == "eth":
        # Slots are 12s but some are missed, so the block a time names is
        # found near, not at, the estimate: a window either side of it.
        ts = int(datetime.fromisoformat(created.replace("Z", "+00:00")).timestamp())
        head = rpc(net, "eth_getBlockByNumber", ["latest", False])["result"]
        b = int(head["number"], 16) - (int(head["timestamp"], 16) - ts) // n["blocktime"]
        spans = [(hex(b - n["window"]), hex(b + n["window"]))]
    elif net == "base":
        ts = int(datetime.fromisoformat(created.replace("Z", "+00:00")).timestamp())
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
            r = rpc(net, "eth_getLogs", [{"address": n["pm"], "fromBlock": lo, "toBlock": hi, "topics": topics}])
            if "result" in r: break
        else:
            raise RuntimeError(f"{n['rpc']} kept refusing: {r.get('error')}")
        logs = r.get("result") or []
        if logs:
            l = logs[0]; d = bytes.fromhex(l["data"][2:])
            fee = int.from_bytes(d[0:32], "big")
            ts = int.from_bytes(d[32:64], "big", signed=True)
            hook = "0x" + d[76:96].hex()
            c0 = "0x" + l["topics"][2][-40:]; c1 = "0x" + l["topics"][3][-40:]
            return c0, c1, fee, ts, hook
        time.sleep(0.3)
    return None


def quotes(net, c0, c1, fee, ts, hook, amount):
    sel = keccak256(b"quoteExactInputSingle(((address,address,uint24,int24,address),bool,uint128,bytes))")[:4]
    data = sel + word(32) + addr(c0) + addr(c1) + word(fee) + word(ts) + addr(hook) + word(1) + word(amount) + word(256) + word(0)
    r = rpc(net, "eth_call", [{"to": NETS[net]["quoter"], "data": "0x" + data.hex()}, "latest"])
    return "result" in r and int(r["result"][2:66] or "0", 16) > 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--network", choices=list(NETS), action="append")
    ap.add_argument("--min-usd", type=float, default=500_000)
    ap.add_argument("--pages", type=int, default=3)
    a = ap.parse_args()
    for net in a.network or list(NETS):
        print(f"// {net}: Uniswap v4 pools holding ≥ ${a.min_usd:,.0f}, measured {datetime.now(timezone.utc):%Y-%m-%d}")
        seen = set()
        for page in range(1, a.pages + 1):
            data = get(f"https://api.geckoterminal.com/api/v2/networks/{NETS[net]['gt']}/dexes/uniswap-v4-{NETS[net]['gt'] if net != 'eth' else 'ethereum'}/pools?page={page}&sort=h24_volume_usd_desc").get("data", [])
            time.sleep(2.5)
            for p in data:
                at = p["attributes"]; pid = at["address"]; usd = float(at.get("reserve_in_usd") or 0)
                if usd < a.min_usd or pid in seen: continue
                seen.add(pid)
                try:
                    k = key_of(net, pid, at["pool_created_at"])
                except RuntimeError as e:
                    print(f"// ? {at['name']} {pid}: {e}"); continue
                if not k:
                    print(f"// ✗ {at['name']} {pid}: no Initialize log found"); continue
                c0, c1, fee, ts, hook = k
                again = "0x" + keccak256(addr(c0) + addr(c1) + word(fee) + word(ts) + addr(hook)).hex()
                if again != pid:
                    print(f"// ✗ {at['name']} {pid}: the key does not hash to the pool id"); continue
                if WETH[net] in (c0, c1):
                    print(f"// · {at['name']} (${usd:,.0f}): a pool of WETH itself, not asked"); continue
                if hook == ZERO and (fee, ts) in STANDARD:
                    print(f"// · {at['name']} (${usd:,.0f}): a standard key, asked for every pair"); continue
                small = 10 ** 12  # a millionth of an 18-decimal token, or a millionth of a dollar at 6
                if not (quotes(net, c0, c1, fee, ts, hook, small) or quotes(net, c0, c1, fee, ts, hook, small * 1000)):
                    print(f"// ✗ {at['name']} {pid}: the quoter does not answer"); continue
                print(f'V4Pool(fee: {fee}, tickSpacing: {ts}, hooks: "{hook}",\n'
                      f'       pair: ["{c0}", "{c1}"]),  // {at["name"]}, ${usd:,.0f}')


if __name__ == "__main__":
    main()
