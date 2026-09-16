#!/usr/bin/env python3
"""Keccak-256 for the harnesses, with no module to install (2026-09-16).

**Why this file exists.** Three harnesses hash bytes in Python to check a Swift
encoder's work: `hegota-tx-selftest.sh`, `vibenet-signer-selftest.sh` and
`support/vibenet-tx-vectors.py`. All three imported `pysha3`, which is on the
dev Mac and on no hosted runner — so `logic-selftests.yml` failed two harnesses
with `ModuleNotFoundError: No module named 'sha3'` on every single run, on
`main` and on every branch, for as long as that workflow has existed.

A check whose verdict depends on what happens to be installed is not a check.
It reads as a real failure when the machine changes and as a real pass when it
does not, and neither verdict is about the code. So the dependency is gone:
this is Keccak-f[1600] in the standard library alone.

**It is still a DIFFERENT keccak than the app's, which is the whole point of
those harnesses.** They exist to catch a Swift encoder that agrees with itself
— hashing the app's own bytes with the app's own `Keccak256` would prove
nothing. This implementation was written against the specification, not against
`Casberi/Casberi/Model/Keccak256.swift`, and shares no line with it.

**And it proves itself before it is believed.** `--self-test` checks the two
published NIST/Ethereum vectors plus the padding boundaries that separate
Keccak from SHA-3 — which is the failure worth guarding, because `hashlib`'s
`sha3_256` is a DIFFERENT function (0x06 padding, not 0x01) that would look
like a working substitute and silently disagree on every input.

    python3 scripts/support/keccak.py --self-test

Usage from a harness (run from the repo root, as every harness does):

    import sys; sys.path.insert(0, "scripts/support")
    from keccak import keccak256_hex
    keccak256_hex("06f8cc…")   # hex in, bare hex digest out
"""

RC = [0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
      0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
      0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
      0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
      0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
      0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008]

# Rotation offsets, indexed [x][y].
R = [[0, 36, 3, 41, 18],
     [1, 44, 10, 45, 2],
     [62, 6, 43, 15, 61],
     [28, 55, 25, 21, 56],
     [27, 20, 39, 8, 14]]

MASK = (1 << 64) - 1
RATE = 136          # 1600 - 2*256 bits, in bytes — the 256-bit capacity
PAD_KECCAK = 0x01   # NOT 0x06. SHA-3 pads 0x06; that one byte is the whole
                    # difference between this function and `hashlib.sha3_256`.


def _rol(x, n):
    n %= 64
    return ((x << n) | (x >> (64 - n))) & MASK


def _keccak_f(A):
    for rnd in range(24):
        # θ
        C = [A[x][0] ^ A[x][1] ^ A[x][2] ^ A[x][3] ^ A[x][4] for x in range(5)]
        D = [C[(x - 1) % 5] ^ _rol(C[(x + 1) % 5], 1) for x in range(5)]
        for x in range(5):
            for y in range(5):
                A[x][y] ^= D[x]
        # ρ and π
        B = [[0] * 5 for _ in range(5)]
        for x in range(5):
            for y in range(5):
                B[y][(2 * x + 3 * y) % 5] = _rol(A[x][y], R[x][y])
        # χ
        for x in range(5):
            for y in range(5):
                A[x][y] = B[x][y] ^ ((~B[(x + 1) % 5][y]) & MASK & B[(x + 2) % 5][y])
        # ι
        A[0][0] ^= RC[rnd]
    return A


def keccak256(data):
    """The 32-byte Keccak-256 digest of `data` (bytes)."""
    A = [[0] * 5 for _ in range(5)]
    padded = bytearray(data)
    padded.append(PAD_KECCAK)
    while len(padded) % RATE != 0:
        padded.append(0x00)
    padded[-1] ^= 0x80
    for off in range(0, len(padded), RATE):
        block = padded[off:off + RATE]
        for i in range(RATE // 8):
            A[i % 5][i // 5] ^= int.from_bytes(block[i * 8:(i + 1) * 8], "little")
        A = _keccak_f(A)
    out = b""
    for i in range(4):
        out += A[i % 5][i // 5].to_bytes(8, "little")
    return out[:32]


def keccak256_hex(hex_or_bytes):
    """Digest as a bare lowercase hex string, no `0x`. Takes hex (with or
    without `0x`) or bytes — every caller here holds hex off a Swift run."""
    if isinstance(hex_or_bytes, (bytes, bytearray)):
        data = bytes(hex_or_bytes)
    else:
        s = hex_or_bytes.strip()
        if s.startswith("0x") or s.startswith("0X"):
            s = s[2:]
        data = bytes.fromhex(s)
    return keccak256(data).hex()


def _self_test():
    fails = 0

    def eq(got, want, what):
        nonlocal fails
        if got != want:
            print(f"  ✗ {what}\n      got  {got}\n      want {want}")
            fails += 1
        else:
            print(f"  ✓ {what}")

    # THE TWO PUBLISHED VECTORS. If either moves, this file is wrong — not the
    # harness that called it.
    eq(keccak256(b"").hex(),
       "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470",
       'keccak256("") is the published empty digest')
    eq(keccak256(b"abc").hex(),
       "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45",
       'keccak256("abc") is the published vector')

    # NOT SHA-3, and this is the mistake worth refusing loudly: `hashlib` ships
    # `sha3_256`, which looks like a drop-in and pads differently, so it agrees
    # with this on NOTHING while importing cleanly on every machine.
    import hashlib
    if hashlib.sha3_256(b"").hexdigest() == keccak256(b"").hex():
        print("  ✗ this is computing SHA-3, not Keccak — check the padding byte")
        fails += 1
    else:
        print("  ✓ distinct from hashlib.sha3_256 (the 0x01 vs 0x06 padding)")

    # A function selector, the shape every caller actually uses.
    eq(keccak256(b"addressVerifiedUntil(address)").hex()[:8], "2bc91fed",
       "a 4-byte function selector matches the one the app derives")

    # THE RATE BOUNDARY. A one-block message, an exactly-full block and a
    # two-block message take different paths through the padding above, and an
    # off-by-one there passes every short vector.
    eq(keccak256(b"\x00" * 135).hex(),
       keccak256_hex("00" * 135), "135 bytes: one block, padding fits")
    eq(len(keccak256(b"\x00" * 136)), 32, "136 bytes: an exactly-full block still digests")
    eq(len(keccak256(b"\x00" * 200)), 32, "200 bytes: two blocks")
    # …and the three lengths must not collide, which an absorb that dropped a
    # block would make them do.
    digests = {keccak256(b"\x00" * n).hex() for n in (135, 136, 200)}
    eq(str(len(digests)), "3", "the three block lengths give three digests")

    # The hex door both spellings of the input go through.
    eq(keccak256_hex("616263"), keccak256(b"abc").hex(), "hex in = bytes in")
    eq(keccak256_hex("0x616263"), keccak256(b"abc").hex(), "a 0x prefix is accepted")
    eq(keccak256_hex(b"abc"), keccak256(b"abc").hex(), "bytes are accepted too")

    print("keccak: self-test passed" if fails == 0 else f"keccak: {fails} FAILED")
    return 1 if fails else 0


if __name__ == "__main__":
    import sys
    if "--self-test" in sys.argv:
        raise SystemExit(_self_test())
    data = sys.stdin.read().strip()
    print(keccak256_hex(data))
