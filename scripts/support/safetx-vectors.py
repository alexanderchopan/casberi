#!/usr/bin/env python3
"""Derive the SafeTx / EIP-712 constants and test vectors the signer stands on.

WHY THIS EXISTS (prd §425). The Safe co-signer's whole correctness rests on
one number: the `safeTxHash`. Get the domain separator or the type hash wrong
by one byte and the app produces a signature that is perfectly well-formed,
recovers to a real address, and is simply REJECTED by the Safe — or, worse,
is a valid signature over a DIFFERENT transaction than the one previewed.
Nothing in a build, a screen sweep or a UI test can see that.

So the constants must never be RECALLED. This file computes them from the
type strings in Safe's own contract source, using a Keccak-256 written here
from the spec and checked against published vectors first. The Swift harness
(`scripts/safetx-selftest.sh`) then pins what this prints, so the Swift and
this Python are two independent implementations that must agree.

Pure, local, deterministic — no network, no third-party package (the build
host has neither pycryptodome nor a `sha3` module, and `hashlib.sha3_256` is
the NIST padding variant, NOT Keccak — using it here is the single easiest
way to produce confidently wrong constants).

Run:  python3 scripts/support/safetx-vectors.py
      python3 scripts/support/safetx-vectors.py --self-test
"""

import sys

# --- Keccak-256 (original padding, 0x01 — NOT SHA-3's 0x06) ----------------

RC = [
    0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
    0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
    0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
    0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
    0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
    0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
]

ROT = [
    [0, 36, 3, 41, 18],
    [1, 44, 10, 45, 2],
    [62, 6, 43, 15, 61],
    [28, 55, 25, 21, 56],
    [27, 20, 39, 8, 14],
]

MASK = (1 << 64) - 1


def _rotl(x, n):
    n %= 64
    return ((x << n) | (x >> (64 - n))) & MASK


def _permute(a):
    for rnd in range(24):
        c = [a[x][0] ^ a[x][1] ^ a[x][2] ^ a[x][3] ^ a[x][4] for x in range(5)]
        d = [c[(x - 1) % 5] ^ _rotl(c[(x + 1) % 5], 1) for x in range(5)]
        for x in range(5):
            for y in range(5):
                a[x][y] ^= d[x]
        b = [[0] * 5 for _ in range(5)]
        for x in range(5):
            for y in range(5):
                b[y][(2 * x + 3 * y) % 5] = _rotl(a[x][y], ROT[x][y])
        for x in range(5):
            for y in range(5):
                a[x][y] = b[x][y] ^ ((~b[(x + 1) % 5][y]) & b[(x + 2) % 5][y])
        a[0][0] ^= RC[rnd]
    return a


def keccak256(data: bytes) -> bytes:
    rate = 136  # 1088 bits
    padded = bytearray(data)
    padded.append(0x01)
    while len(padded) % rate != 0:
        padded.append(0x00)
    padded[-1] ^= 0x80

    a = [[0] * 5 for _ in range(5)]
    for off in range(0, len(padded), rate):
        block = padded[off:off + rate]
        for i in range(rate // 8):
            lane = int.from_bytes(block[i * 8:(i + 1) * 8], "little")
            a[i % 5][i // 5] ^= lane
        _permute(a)

    out = bytearray()
    for i in range(4):  # 32 bytes
        out += a[i % 5][i // 5].to_bytes(8, "little")
    return bytes(out[:32])


def kh(data) -> str:
    if isinstance(data, str):
        data = data.encode()
    return "0x" + keccak256(data).hex()


# --- ABI encoding helpers (static head only — enough for SafeTx) -----------

def enc_uint(n: int) -> bytes:
    return n.to_bytes(32, "big")


def enc_addr(a: str) -> bytes:
    return bytes(12) + bytes.fromhex(a.lower().removeprefix("0x"))


def enc_bytes32(h: str) -> bytes:
    return bytes.fromhex(h.lower().removeprefix("0x"))


# --- The Safe type strings, verbatim from Safe's contract source ----------
#
# Safe >= 1.3.0 dropped `name`/`version` from its EIP712Domain and added
# `chainId`. A 1.1.x Safe uses a domain of `(address verifyingContract)`
# ALONE, so its separator differs — the signer must refuse a Safe whose
# version it does not recognise rather than sign against a guessed domain.

DOMAIN_TYPE = "EIP712Domain(uint256 chainId,address verifyingContract)"
SAFE_TX_TYPE = (
    "SafeTx(address to,uint256 value,bytes data,uint8 operation,"
    "uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,"
    "address refundReceiver,uint256 nonce)"
)


def domain_separator(chain_id: int, safe: str) -> bytes:
    return keccak256(
        enc_bytes32(kh(DOMAIN_TYPE)) + enc_uint(chain_id) + enc_addr(safe)
    )


def safe_tx_hash(*, chain_id, safe, to, value, data: bytes, operation,
                 safe_tx_gas, base_gas, gas_price, gas_token,
                 refund_receiver, nonce) -> bytes:
    struct_hash = keccak256(
        enc_bytes32(kh(SAFE_TX_TYPE))
        + enc_addr(to)
        + enc_uint(value)
        + enc_bytes32(kh(data))       # `bytes` is hashed, never inlined
        + enc_uint(operation)
        + enc_uint(safe_tx_gas)
        + enc_uint(base_gas)
        + enc_uint(gas_price)
        + enc_addr(gas_token)
        + enc_addr(refund_receiver)
        + enc_uint(nonce)
    )
    return keccak256(
        b"\x19\x01" + domain_separator(chain_id, safe) + struct_hash
    )


# --- Fixtures the Swift harness pins --------------------------------------

ZERO = "0x0000000000000000000000000000000000000000"
SAFE = "0x1234567890123456789012345678901234567890"

FIXTURES = [
    ("plain ETH send, mainnet, nonce 0", dict(
        chain_id=1, safe=SAFE, to="0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
        value=1_000_000_000_000_000_000, data=b"", operation=0,
        safe_tx_gas=0, base_gas=0, gas_price=0, gas_token=ZERO,
        refund_receiver=ZERO, nonce=0)),
    ("same tx, nonce 1 (nonce must change the hash)", dict(
        chain_id=1, safe=SAFE, to="0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
        value=1_000_000_000_000_000_000, data=b"", operation=0,
        safe_tx_gas=0, base_gas=0, gas_price=0, gas_token=ZERO,
        refund_receiver=ZERO, nonce=1)),
    ("same tx, Base (chainId must change the hash)", dict(
        chain_id=8453, safe=SAFE, to="0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
        value=1_000_000_000_000_000_000, data=b"", operation=0,
        safe_tx_gas=0, base_gas=0, gas_price=0, gas_token=ZERO,
        refund_receiver=ZERO, nonce=0)),
    ("ERC-20 transfer calldata, operation 0", dict(
        chain_id=1, safe=SAFE, to="0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
        value=0,
        data=bytes.fromhex(
            "a9059cbb"
            "000000000000000000000000abcdefabcdefabcdefabcdefabcdefabcdefabcd"
            "00000000000000000000000000000000000000000000000000000000000f4240"),
        operation=0, safe_tx_gas=0, base_gas=0, gas_price=0, gas_token=ZERO,
        refund_receiver=ZERO, nonce=7)),
    # SIXTH FIXTURE (added while writing scripts/safetx-selftest.sh, 2026-08-21).
    # The five above leave `safeTxGas`, `baseGas`, `gasPrice`, `gasToken` and
    # `refundReceiver` all at zero, which makes the last five words of the
    # struct hash INDISTINGUISHABLE from each other — so a signer that
    # transposed `safeTxGas` and `baseGas`, or `gasToken` and
    # `refundReceiver`, reproduced all five fixtures exactly. The harness's
    # own mutation pass found that: swapping the two gas fields left every
    # assertion green. A fixture only tests the rule it names if it FAILS
    # that rule and passes every other one, so this one gives every field a
    # distinct value.
    ("every field distinct (the gas words must not be transposable)", dict(
        chain_id=1, safe=SAFE, to="0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
        value=1_000_000_000_000_000_000,
        data=bytes.fromhex("deadbeef"), operation=0,
        safe_tx_gas=100_000, base_gas=21_000, gas_price=3,
        gas_token="0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
        refund_receiver="0x1111111111111111111111111111111111111111",
        nonce=42)),
    ("DELEGATECALL (operation 1 must change the hash)", dict(
        chain_id=1, safe=SAFE, to="0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
        value=0,
        data=bytes.fromhex(
            "a9059cbb"
            "000000000000000000000000abcdefabcdefabcdefabcdefabcdefabcdefabcd"
            "00000000000000000000000000000000000000000000000000000000000f4240"),
        operation=1, safe_tx_gas=0, base_gas=0, gas_price=0, gas_token=ZERO,
        refund_receiver=ZERO, nonce=7)),
]


def self_test() -> int:
    """Prove the Keccak here is really Keccak before trusting anything it says."""
    failures = 0

    def check(label, got, want):
        nonlocal failures
        if got == want:
            print(f"  ✓ {label}")
        else:
            print(f"  ✗ {label}\n      got  {got}\n      want {want}")
            failures += 1

    # Published Keccak-256 vectors. If these pass, the padding and the
    # permutation are right; SHA3-256 gives a completely different answer for
    # the empty string (a7ffc6f8bf1ed766…), so this also proves we are not
    # accidentally running the NIST variant.
    check("keccak256(\"\")", kh(b""),
          "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
    check("keccak256(\"abc\")", kh("abc"),
          "0x4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45")
    # Crosses the 136-byte rate boundary, so it exercises multi-block absorb.
    check("keccak256(200 * \"a\") is 32 bytes", str(len(keccak256(b"a" * 200))), "32")

    # A vector every Ethereum developer can recognise on sight: the ERC-20
    # Transfer event topic. Independent confirmation that this hashes the way
    # the chain does.
    check("keccak256(\"Transfer(address,address,uint256)\")",
          kh("Transfer(address,address,uint256)"),
          "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef")
    # And the ERC-20 transfer(address,uint256) selector.
    check("selector of transfer(address,uint256)",
          kh("transfer(address,uint256)")[:10], "0xa9059cbb")

    # Determinism: the same input twice must give the same answer (guards a
    # permutation that mutates shared state across calls).
    check("deterministic across calls", kh("casberi"), kh("casberi"))

    # Every fixture must produce a DISTINCT hash — the three near-identical
    # ones exist precisely to prove nonce, chainId and operation are each
    # inside the preimage. A signer that ignored `nonce` would let a replay
    # at a later nonce reuse a signature.
    hashes = {}
    for label, kw in FIXTURES:
        h = "0x" + safe_tx_hash(**kw).hex()
        if h in hashes:
            print(f"  ✗ fixture collision: {label} == {hashes[h]}")
            failures += 1
        hashes[h] = label
    check("all fixtures distinct", str(len(hashes)), str(len(FIXTURES)))

    return failures


def main() -> int:
    if "--self-test" in sys.argv:
        print("safetx-vectors self-test")
        failures = self_test()
        print("  all good" if failures == 0 else f"  {failures} failure(s)")
        return 1 if failures else 0

    print("safetx-vectors self-test")
    if self_test() != 0:
        print("  refusing to print constants from an unverified Keccak")
        return 1

    print("\nType hashes (computed from Safe's own type strings)")
    print(f"  DOMAIN_SEPARATOR_TYPEHASH  {kh(DOMAIN_TYPE)}")
    print(f"  SAFE_TX_TYPEHASH           {kh(SAFE_TX_TYPE)}")

    print("\nDomain separators")
    for cid, name in ((1, "mainnet"), (8453, "base"), (100, "gnosis")):
        print(f"  chainId {cid:<6} {name:<8} safe {SAFE}")
        print(f"    {'0x' + domain_separator(cid, SAFE).hex()}")

    print("\nsafeTxHash fixtures")
    for label, kw in FIXTURES:
        print(f"  {label}")
        print(f"    {'0x' + safe_tx_hash(**kw).hex()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
