#!/usr/bin/env python3
"""Does the keyed-nonce storage slot still resolve on Ethrex Hegotá? (prd §509)

**The one read in this seat that is REVERSE-ENGINEERED rather than specified.**
The nonce manager predeploy's entire runtime is five bytes — `0x60006000fd`,
`PUSH0 PUSH0 REVERT` — so every `eth_call` against it reverts and there is no
getter to ask. Its state is public regardless, and `HegotaNonceStorage.slot`
reads a keyed counter straight out of storage at

    keccak256(pad32(address) ‖ pad32(key))

which was derived by measurement on 2026-08-28: the only address on this devnet
that sends on named keys reads a non-zero counter at that slot for BOTH of its
keys, while four rival layouts (key-first, the Solidity nested-mapping form, and
two packed forms) all read zero.

**Why it needs a nightly.** If the layout ever moves, the slot reads a
legitimate-looking ZERO — not an error — so the lane silently falls back to its
observed send count and nothing anywhere says why. That is §311's class exactly:
the room does not break, it goes quiet.

Prints the number of example keys whose counter reads non-zero (0–2). Two is
healthy; anything less means the derivation no longer holds.
"""
import importlib.util
import json
import pathlib
import sys
import urllib.request
from typing import Optional

HOST = "https://rpc1.hegota.ethrex.xyz"
MANAGER = "0x0000000000000000000000000000000000008250"
# The only address on this chain sending on named keys, and the two keys it uses.
ADDRESS = "8943545177806ed17b9f23f0a21ee5948ecaa776"
KEYS = (0xBEEF01, 0x1234)


def keccak256(data: bytes) -> bytes:
    """Borrowed from the Safe vector generator rather than reimplemented — one
    keccak in this repo, so a bug in it is a bug both places notice."""
    here = pathlib.Path(__file__).resolve().parent / "safetx-vectors.py"
    spec = importlib.util.spec_from_file_location("stv", here)
    module = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(module)
    except SystemExit:
        pass
    return module.keccak256(data)


def storage_at(slot: str) -> Optional[str]:
    body = json.dumps({"id": 1, "jsonrpc": "2.0", "method": "eth_getStorageAt",
                       "params": [MANAGER, slot, "latest"]}).encode()
    request = urllib.request.Request(HOST, body, {"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return json.load(response).get("result")
    except Exception:
        return None


def main() -> int:
    address = bytes.fromhex(ADDRESS)
    resolved = 0
    for key in KEYS:
        slot = "0x" + keccak256(b"\x00" * 12 + address + key.to_bytes(32, "big")).hex()
        value = storage_at(slot)
        if value and int(value, 16) > 0:
            resolved += 1
    print(resolved)
    return 0


if __name__ == "__main__":
    sys.exit(main())
