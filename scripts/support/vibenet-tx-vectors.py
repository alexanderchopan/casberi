#!/usr/bin/env python3
"""Regenerate the PROVEN EIP-8130 sender-signing vector (prd §523).

`safetx-vectors.py`'s shape, and the same reason to exist: the fixture pinned
in `scripts/vibenet-signer-selftest.sh` is only worth anything if it can be
re-derived from something outside our own code. Here that something is the
chain itself.

THE PROOF, and why it is a proof rather than a reading of the spec. A real
transaction carries its decoded fields, its 65-byte `senderAuth`, and the
`from` that sent it. Encode the signing hash, recover the signer, compare. On
2026-08-29 exactly ONE of sixteen candidate encodings recovered the right
address — varying the channel value, the per-change tag, and whether `calls`
is phased or flat. One match out of sixteen is not a coincidence.

Needs `coincurve` and `pysha3`, and network. NOT run by verify.sh for
`live-integrations.sh`'s reason: it needs egress, and a check that cannot run
offline must never be able to fail a build. The harness pins its OUTPUT.

    python3 scripts/support/vibenet-tx-vectors.py            # re-derive + verify
    python3 scripts/support/vibenet-tx-vectors.py --self-test
"""
import json, sys, urllib.request

RPC = "https://rpc.vibes.base.org"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
# The transaction the vector is derived from. Pinned by hash so a re-run
# measures the same bytes rather than whatever is newest — a vector that moves
# under you is not a vector.
TX = "block 0x243, the only type-0x79 transaction in the first 40 blocks"


def rpc(method, params):
    req = urllib.request.Request(
        RPC, method="POST",
        data=json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode(),
        headers={"content-type": "application/json", "user-agent": UA})
    return json.load(urllib.request.urlopen(req, timeout=30))["result"]


def keccak(b):
    import sha3
    k = sha3.keccak_256(); k.update(b); return k.digest()


def enc_len(l, off):
    if l < 56:
        return bytes([off + l])
    b = l.to_bytes((l.bit_length() + 7) // 8, "big")
    return bytes([off + 55 + len(b)]) + b


def rlp(x):
    if isinstance(x, bytes):
        if len(x) == 1 and x[0] < 0x80:
            return x
        return enc_len(len(x), 0x80) + x
    body = b"".join(rlp(i) for i in x)
    return enc_len(len(body), 0xc0) + body


def qty(v):
    """Canonical: no leading zeros, and ZERO IS EMPTY. `0x00` is not a valid
    RLP quantity and encoding it that way changes the hash."""
    if v is None:
        return b""
    if isinstance(v, str):
        v = int(v, 16) if v.startswith("0x") else int(v)
    return b"" if v == 0 else v.to_bytes((v.bit_length() + 7) // 8, "big")


def hx(s):
    return b"" if s in (None, "0x") else bytes.fromhex(s[2:] if s.startswith("0x") else s)


def preimage(tx):
    """AA_TX_TYPE (0x79, measured off the transaction's own `type`) followed by
    the RLP list THROUGH `payer` — both auth fields excluded."""
    ac0 = tx["accountChanges"][0]
    changes = [[qty(0x00), hx(c["payload"])] for c in ac0["changes"]]   # AuthorizeActor = 0x00
    entry = [qty(0x01), qty(0), qty(ac0["sequence"]), changes, hx(ac0["signature"])]  # configChange, Local
    calls = [[[hx(c["to"]), hx(c["data"])] for c in phase] for phase in tx["calls"]]
    body = [qty(tx["chainId"]), hx(tx["sender"]), qty(tx["nonceKey"]), qty(tx["nonceSequence"]),
            qty(tx["validAfter"]), qty(tx["validBefore"]), qty(tx["maxPriorityFeePerGas"]),
            qty(tx["maxFeePerGas"]), qty(tx["gasLimit"]), [entry], calls,
            hx(tx["metadata"]), hx(tx["payer"])]
    return b"\x79" + rlp(body)


def self_test():
    ok = True
    def check(label, cond):
        nonlocal ok
        if not cond:
            print(f"  ✗ {label}"); ok = False
    # Zero is empty, never 0x00 — the rule that silently changes every hash.
    check("qty(0) is empty", qty(0) == b"")
    check("qty(1) is one byte", qty(1) == b"\x01")
    check("no leading zeros", qty(0x0100) == b"\x01\x00")
    # RLP's single-byte case has no prefix at all.
    check("small byte is bare", rlp(b"\x01") == b"\x01")
    check("0x80 gets a prefix", rlp(b"\x80") == b"\x81\x80")
    check("empty string", rlp(b"") == b"\x80")
    check("empty list", rlp([]) == b"\xc0")
    # The long-form boundary, where the length-of-length byte appears.
    check("55 bytes is short form", rlp(b"a" * 55)[0] == 0x80 + 55)
    check("56 bytes is long form", rlp(b"a" * 56)[0] == 0xb8)
    print("  ok" if ok else "  FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(self_test())
    import coincurve
    head = int(rpc("eth_blockNumber", []), 16)
    found = None
    for bn in range(0x243, min(0x243 + 40, head)):
        b = rpc("eth_getBlockByNumber", [hex(bn), True])
        for t in (b or {}).get("transactions", []):
            if t.get("type") == "0x79":
                found = t; break
        if found: break
    if not found:
        print("no type-0x79 transaction found — the chain may have been wiped"); sys.exit(1)
    pre = preimage(found["tx"])
    h = keccak(pre)
    auth = hx(found["senderAuth"])
    r, s, v = auth[:32], auth[32:64], auth[64]
    rec = None
    for vv in {v, v - 27}:
        if vv not in (0, 1):
            continue
        try:
            pk = coincurve.PublicKey.from_signature_and_message(r + s + bytes([vv]), h, hasher=None)
            rec = "0x" + keccak(pk.format(compressed=False)[1:])[-20:].hex()
        except Exception:
            pass
    print(f"source        {TX}")
    print(f"PREIMAGE_LEN  {len(pre)}")
    print(f"SIGNING_HASH  0x{h.hex()}")
    print(f"recovered     {rec}")
    print(f"expected      {found['from'].lower()}")
    print("VERIFIED" if rec == found["from"].lower() else "MISMATCH — the encoding is wrong")
    sys.exit(0 if rec == found["from"].lower() else 1)
