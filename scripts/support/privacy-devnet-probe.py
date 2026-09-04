#!/usr/bin/env python3
"""What is on `privacy.ethrex.xyz`? — the first measurement (prd §500 follow-up).

ethrex names a devnet by the capability it tests and stands up a full quartet
per name: `{faucet,rpc1,rpc2,rpc3,dora}.<devnet>.ethrex.xyz`. We hold two of
those quartets already — `hegota` (§500) and `frames` (§548) — and a third
appeared: `privacy`. This answers, in ONE run, the questions that decide whether
the Hegotá seat ports to it, forks the way Frames had to, or does neither.

**Why a script rather than a handful of curls.** Four of the six readings below
are censuses over real transactions, and the failure they exist to catch is the
one this repo keeps paying for: an envelope field that moved produces a
signature that is well-formed, recovers to a real address, and is refused by the
chain. `FramesTransaction` is a separate file from `HegotaTransaction` because
both chains serve type `0x6` and hash DIFFERENT LISTS. So the field census is
the deliverable, not the liveness check.

**Read-only, keyless, spends nothing.** Every call is an `eth_*` read plus one
faucet `GET /api/status`, which the vibenet measurement showed costs no
cooldown. The faucet CLAIM is deliberately absent: a probe that spends the
allowance on every run is one nobody can put in a sweep (§548's `claim`-is-a-
word rule).

**It never fails.** Exit 0 always, like `live-integrations.sh` — a third party
being down is information, not a build failure.

Usage:  python3 scripts/support/privacy-devnet-probe.py [devnet]
        (devnet defaults to `privacy`; pass `hegota` to compare against the
         chain we already know, which is the cheapest way to read this report)
"""
import json
import os
import sys
import urllib.error
import urllib.request

TIMEOUT = 15

# What the Hegotá seat pins today. Printed beside every answer so the report
# reads as a DIFF rather than a table of numbers nobody can rank.
HEGOTA_CHAIN_ID = "0x301824"          # 3151908
HEGOTA_GENESIS = "0xc2a34ac020910de9fa78b5089eb9eb91b913fb0f95370ec42601ddb95a5cb213"
VAULT = "0x0000000000000000000000000000000000008312"        # UTXO vault predeploy
NONCE_MANAGER = "0x0000000000000000000000000000000000008250"  # EIP-8250 keyed nonces
TRANSFER_EMITTER = "0xfffffffffffffffffffffffffffffffffffffffe"  # EIP-7708
UTXO_CREATED_TOPIC = "0x3b19241465a47bc187f1d9c7db70834855a907183742a4b63aa824c576296f5e"

# The eleven fields `HegotaTransaction.Fields` encodes, in hash order. A type
# `0x6` transaction here that is MISSING one of these, or carries a name we do
# not know, is the whole reason this probe exists.
HEGOTA_ENVELOPE = ["chainId", "nonceKeys", "nonceSeq", "sender", "frames",
                   "signatures", "maxPriorityFeePerGas", "maxFeePerGas",
                   "maxFeePerBlobGas", "blobVersionedHashes",
                   "recentRootReferences"]

BLOCK_SCAN = 40   # how many blocks back the censuses walk


def rpc(host, method, params, _id=1):
    """One JSON-RPC read. Returns (result, error_message).

    An unreached host and a host that answered with an error are kept APART:
    the seat's own rule is that an unreached read is not evidence of an empty
    chain, and a report that collapses them would call a firewall an empty
    devnet."""
    body = json.dumps({"id": _id, "jsonrpc": "2.0",
                       "method": method, "params": params}).encode()
    req = urllib.request.Request(host, data=body,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            root = json.load(resp)
    except urllib.error.HTTPError as exc:
        # A node answers a rejected read with a 400 and the reason in the BODY
        # (§530's lesson) — so read it rather than reporting the status alone.
        try:
            return None, json.load(exc).get("error", {}).get("message", f"http {exc.code}")
        except Exception:
            return None, f"http {exc.code}"
    except Exception as exc:
        return None, f"unreachable ({type(exc).__name__})"
    if "error" in root:
        return None, str(root["error"].get("message", root["error"]))[:80]
    return root.get("result"), None


def get(url):
    try:
        with urllib.request.urlopen(url, timeout=TIMEOUT) as resp:
            return resp.read().decode("utf-8", "replace"), None
    except urllib.error.HTTPError as exc:
        try:
            return exc.read().decode("utf-8", "replace"), f"http {exc.code}"
        except Exception:
            return None, f"http {exc.code}"
    except Exception as exc:
        return None, f"unreachable ({type(exc).__name__})"


def head(text):
    print(f"\n\033[36m{text}\033[0m")
    print("\033[90m" + "─" * 68 + "\033[0m")


def row(label, value, note=""):
    print(f"  {label:<28} {value}" + (f"   \033[90m{note}\033[0m" if note else ""))


def main():
    devnet = sys.argv[1] if len(sys.argv) > 1 else "privacy"
    hosts = [f"https://rpc{i}.{devnet}.ethrex.xyz" for i in (1, 2, 3)]
    faucet = f"https://faucet.{devnet}.ethrex.xyz"
    # Overrides so this script can be exercised against a mock before it is
    # trusted against a chain. A probe whose parse has never run is a probe
    # whose first real output nobody can grade.
    if os.environ.get("ETHREX_PROBE_RPC"):
        hosts = [os.environ["ETHREX_PROBE_RPC"]]
    if os.environ.get("ETHREX_PROBE_FAUCET"):
        faucet = os.environ["ETHREX_PROBE_FAUCET"]

    print(f"\n\033[1methrex `{devnet}` devnet — first measurement\033[0m")
    print(f"\033[90mcompared against the Hegotá seat's pins ({HEGOTA_CHAIN_ID} / 3151908)\033[0m")

    # ── 1. Are the hosts there, and is this a chain we already know? ─────────
    head("1. Hosts")
    live = None
    chain_ids = set()

    def label(url):
        """`rpc1` for a real host, the whole authority for an override."""
        auth = url.split("//")[-1].rstrip("/")
        first = auth.split(".")[0]
        return first if first.startswith("rpc") else auth

    for host in hosts:
        cid, err = rpc(host, "eth_chainId", [])
        if err:
            row(label(host), f"\033[31m{err}\033[0m")
            continue
        chain_ids.add(cid)
        ver, _ = rpc(host, "web3_clientVersion", [])
        blk, _ = rpc(host, "eth_blockNumber", [])
        height = int(blk, 16) if blk else "?"
        row(label(host),
            f"chain {cid} ({int(cid, 16)})",
            f"head {height} · {ver or 'no version'}")
        live = live or host

    if live is None:
        print("\n  \033[31mNo host answered.\033[0m Either the devnet is not up, the "
              "quartet is named\n  differently, or this machine cannot reach it. "
              "Nothing below can run.")
        return
    if len(chain_ids) > 1:
        row("VERDICT", "\033[31mhosts disagree on chain id\033[0m",
            "one is serving a different chain")

    cid = next(iter(chain_ids))
    if cid == HEGOTA_CHAIN_ID:
        row("VERDICT", "\033[33mSAME CHAIN ID AS HEGOTÁ\033[0m",
            "a re-host, not a new devnet — the seat's hosts move")
    else:
        row("VERDICT", f"\033[32mnew chain {int(cid, 16)}\033[0m",
            "a third devnet — Hegotá's seat is untouched")

    # ── 2. Genesis — a relaunch answers everything and with nothing ──────────
    head("2. Genesis")
    gen, err = rpc(live, "eth_getBlockByNumber", ["0x0", False])
    if err or not gen:
        row("genesis", f"\033[33munread ({err})\033[0m")
    else:
        h = gen.get("hash", "")
        same = h == HEGOTA_GENESIS
        row("hash", h[:26] + "…")
        row("", "\033[33mIDENTICAL to Hegotá's\033[0m" if same
                else "\033[32mdistinct chain\033[0m")

    # ── 3. Do the predeploys we read exist here? ─────────────────────────────
    head("3. Predeploys the Hegotá seat reads")
    for label, addr in (("UTXO vault (0x…8312)", VAULT),
                        ("keyed nonces (0x…8250)", NONCE_MANAGER),
                        ("EIP-7708 emitter", TRANSFER_EMITTER)):
        code, err = rpc(live, "eth_getCode", [addr, "latest"])
        if err:
            row(label, f"\033[33munread ({err})\033[0m")
        elif code in (None, "0x", ""):
            row(label, "\033[31mNO CODE\033[0m", "that scope cannot draw here")
        else:
            row(label, f"\033[32mcode, {(len(code) - 2) // 2} bytes\033[0m")

    # ── 4. Which contracts actually emit? The cheapest way to find a NEW one ─
    # One `eth_getLogs` with no address filter over a recent window, grouped by
    # emitter. A shielded pool (EIP-8182) would show up here as a predeploy we
    # do not know, which is exactly the thing no spec-reading can tell us.
    head(f"4. Log emitters, last {BLOCK_SCAN} blocks")
    blk, _ = rpc(live, "eth_blockNumber", [])
    tip = int(blk, 16) if blk else 0
    frm = max(0, tip - BLOCK_SCAN)
    logs, err = rpc(live, "eth_getLogs",
                    [{"fromBlock": hex(frm), "toBlock": hex(tip)}])
    if err:
        row("logs", f"\033[33munread ({err})\033[0m")
    elif not logs:
        row("logs", "none in this window", "quiet chain, or nothing deployed")
    else:
        emitters, topics = {}, {}
        for lg in logs:
            emitters[lg.get("address", "?")] = emitters.get(lg.get("address", "?"), 0) + 1
            t = (lg.get("topics") or ["?"])[0]
            topics[t] = topics.get(t, 0) + 1
        for addr, n in sorted(emitters.items(), key=lambda kv: -kv[1])[:8]:
            known = {VAULT: "the UTXO vault",
                     TRANSFER_EMITTER: "EIP-7708 transfers"}.get(addr.lower(), "")
            row(addr[:24] + "…", f"{n} logs",
                known or "\033[35mUNKNOWN — look at this one\033[0m")
        print()
        for t, n in sorted(topics.items(), key=lambda kv: -kv[1])[:5]:
            known = "UtxoCreated" if t == UTXO_CREATED_TOPIC else ""
            row("topic " + t[:18] + "…", f"{n}", known)

    # ── 5. THE ONE THAT MATTERS: the envelope ───────────────────────────────
    # Both Hegotá and Frames serve type `0x6` and hash different lists. A field
    # census over real transactions is what separates them, and getting it wrong
    # produces a signature that recovers to a real address on a chain that
    # refuses it.
    head(f"5. Transaction envelope, last {BLOCK_SCAN} blocks")
    types, sample = {}, None
    for n in range(tip, frm, -1):
        blkobj, _ = rpc(live, "eth_getBlockByNumber", [hex(n), True])
        for tx in (blkobj or {}).get("transactions", []) or []:
            ty = tx.get("type", "?")
            types[ty] = types.get(ty, 0) + 1
            if ty == "0x6" and sample is None:
                sample = tx
        if sample and sum(types.values()) > 30:
            break
    if not types:
        row("transactions", "none in this window")
    else:
        row("type census", "  ".join(f"{k}×{v}" for k, v in sorted(types.items())),
            "0x6 is the frame transaction")

    if sample is None:
        row("envelope", "\033[33mno type-0x6 transaction to read\033[0m",
            "the field census cannot run")
    else:
        got = set(sample.keys())
        missing = [f for f in HEGOTA_ENVELOPE if f not in got]
        extra = sorted(got - set(HEGOTA_ENVELOPE) - {
            "hash", "blockHash", "blockNumber", "transactionIndex", "from",
            "to", "gas", "gasPrice", "input", "nonce", "value", "type",
            "v", "r", "s", "yParity", "accessList"})
        row("hash", sample.get("hash", "?")[:26] + "…")
        row("Hegotá fields present", f"{len(HEGOTA_ENVELOPE) - len(missing)}/11")
        if missing:
            row("  MISSING", "\033[31m" + ", ".join(missing) + "\033[0m",
                "the envelope is NOT Hegotá's")
        if extra:
            row("  UNKNOWN", "\033[35m" + ", ".join(extra) + "\033[0m",
                "fields we do not encode")
        # `limits` forks shape mid-chain on Hegotá (trap 3) and is NESTED on
        # Frames. Which one this chain serves decides whether the encoder ports.
        frames = sample.get("frames") or []
        if frames and isinstance(frames[0], dict):
            f0 = frames[0]
            row("frame keys", ", ".join(sorted(f0.keys())))
            for k in ("limits", "gasLimit", "executionGasLimit", "stateGas",
                      "stateGasLimit"):
                if k in f0:
                    row(f"  {k}", json.dumps(f0[k])[:52])
        sigs = sample.get("signatures") or []
        if sigs and isinstance(sigs[0], dict):
            s0 = sigs[0]
            row("signature keys", ", ".join(sorted(s0.keys())))
            signer = s0.get("signer", "")
            row("  signer", ("EMPTY (Hegotá's shape)" if signer in ("", "0x", None)
                             else f"literal {str(signer)[:20]}… (Frames' shape)"))
        row("recentRootReferences", json.dumps(sample.get("recentRootReferences"))[:52],
            "EIP-8272 — the field we encode empty and never read")
        row("nonceKeys", json.dumps(sample.get("nonceKeys"))[:52],
            "EIP-8250 — keyed nonces")

    # ── 6. The faucet, without spending its allowance ────────────────────────
    head("6. Faucet")
    body, err = get(faucet + "/api/status")
    if body is None:
        row("/api/status", f"\033[33m{err}\033[0m")
    else:
        try:
            data = json.loads(body)
            for k, v in list(data.items())[:8]:
                row(k, json.dumps(v)[:52])
            row("classifier", "vibenet's shape (cooldown seconds)"
                if any("cooldown" in k for k in data) else "Hegotá's shape")
        except Exception:
            row("/api/status", (err or "200") + f" — not JSON ({len(body)}b)",
                "the claim endpoint may differ")

    print("\n\033[90mRead-only. No transaction signed, no faucet allowance spent.\033[0m\n")


if __name__ == "__main__":
    main()
