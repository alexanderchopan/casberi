#!/usr/bin/env python3
"""Derive the constants the co-signer's four new doors stand on (prd §913).

WHY THIS EXISTS. §425's co-signer signs ONE thing — a Safe transaction hash —
and `scripts/support/safetx-vectors.py` derives every number that hash rests
on. §913 gives the same key (and a Secure Enclave sibling) three more things
to sign and one more way to be asked, and each brings its own preimage:

  * a Safe MESSAGE (EIP-1271, `SafeMessage(bytes message)`) — a Snapshot vote
    or a sign-in, hashed under the Safe's own domain;
  * a Candide RECOVERY approval (`ExecuteRecovery(...)`) under the module's
    domain, which carries a name and a version the Safe's does not;
  * a WebAuthn assertion the Safe passkey signer contract verifies, which is
    NOT an EIP-712 hash at all but `sha256(authenticatorData ‖ sha256(clientDataJSON))`;
  * and any of them arriving as EIP-712 TYPED DATA over WalletConnect, which
    needs a general encoder to reproduce the hash the requester expects.

A wrong constant in any of these produces a signature that is well-formed
and simply rejected — or, for the recovery hash, valid over a DIFFERENT
owner set than the one previewed. So nothing here is recalled: every type
hash is computed from the contract's own type string, and the few that Safe
and Candide PUBLISH as precomputed constants in their source are asserted
equal to what this derives (the one independent check a hash can have).

The Swift harness (`scripts/safe-signer-selftest.sh`) pins what this prints,
so the Swift and this Python are two implementations that must agree; and
the general EIP-712 encoder here is itself pinned to the spec's own "Ether
Mail" vector before it is trusted with anything.

Keccak-256 is `safetx-vectors.py`'s, imported and self-tested first. SHA-256
is `hashlib`'s — that one IS the FIPS variant, which is what WebAuthn wants.

Run:  python3 scripts/support/safe-signer-vectors.py
      python3 scripts/support/safe-signer-vectors.py --self-test
"""

import base64
import hashlib
import importlib.util
import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("safetx_vectors", HERE / "safetx-vectors.py")
safetx = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(safetx)

keccak256 = safetx.keccak256
kh = safetx.kh
enc_uint = safetx.enc_uint
enc_addr = safetx.enc_addr
enc_bytes32 = safetx.enc_bytes32


def selector(sig: str) -> str:
    return kh(sig)[:10]


def word_hex(b: bytes) -> str:
    return "0x" + b.hex()


# --- General EIP-712 (spec-complete for the shapes a Safe owner meets) -------

ATOMIC_INT = re.compile(r"^(u?int)(\d*)$")
ATOMIC_BYTES = re.compile(r"^bytes(\d+)$")
ARRAY = re.compile(r"^(.*)\[(\d*)\]$")


def _deps(types, primary, found=None):
    found = found if found is not None else []
    if primary in found or primary not in types:
        return found
    found.append(primary)
    for f in types[primary]:
        base = f["type"]
        m = ARRAY.match(base)
        while m:
            base = m.group(1)
            m = ARRAY.match(base)
        if base in types and base not in found:
            _deps(types, base, found)
    return found


def encode_type(types, primary):
    deps = _deps(types, primary)
    ordered = [primary] + sorted(d for d in deps if d != primary)
    return "".join(
        f"{t}(" + ",".join(f"{f['type']} {f['name']}" for f in types[t]) + ")"
        for t in ordered
    )


def type_hash(types, primary):
    return keccak256(encode_type(types, primary).encode())


def _to_int(v):
    if isinstance(v, bool):
        return int(v)
    if isinstance(v, int):
        return v
    s = str(v).strip()
    if s.lower().startswith("0x"):
        return int(s, 16)
    return int(s)


def encode_value(types, typ, value):
    m = ARRAY.match(typ)
    if m:
        inner = m.group(1)
        return keccak256(b"".join(encode_value(types, inner, v) for v in value))
    if typ in types:
        return hash_struct(types, typ, value)
    if typ == "string":
        return keccak256(str(value).encode())
    if typ == "bytes":
        return keccak256(bytes.fromhex(str(value).removeprefix("0x")))
    if typ == "address":
        return enc_addr(value)
    if typ == "bool":
        return enc_uint(1 if value else 0)
    if ATOMIC_BYTES.match(typ):
        n = int(ATOMIC_BYTES.match(typ).group(1))
        raw = bytes.fromhex(str(value).removeprefix("0x"))
        assert len(raw) == n, f"{typ} value is {len(raw)} bytes"
        return raw + bytes(32 - n)          # right-padded, like the EVM
    if ATOMIC_INT.match(typ):
        n = _to_int(value)
        if n < 0:
            n = (1 << 256) + n              # two's complement
        return enc_uint(n)
    raise ValueError(f"unsupported EIP-712 type {typ}")


def hash_struct(types, primary, data):
    body = type_hash(types, primary)
    for f in types[primary]:
        body += encode_value(types, f["type"], data[f["name"]])
    return keccak256(body)


DOMAIN_ORDER = [("name", "string"), ("version", "string"), ("chainId", "uint256"),
                ("verifyingContract", "address"), ("salt", "bytes32")]


def domain_fields(domain):
    return [{"name": n, "type": t} for n, t in DOMAIN_ORDER if n in domain]


def typed_data_hash(td) -> bytes:
    types = dict(td["types"])
    if "EIP712Domain" not in types:
        types["EIP712Domain"] = domain_fields(td["domain"])
    ds = hash_struct(types, "EIP712Domain", td["domain"])
    sh = hash_struct(types, td["primaryType"], td["message"])
    return keccak256(b"\x19\x01" + ds + sh)


# --- The spec's own vector, so the encoder is trusted before it is used ------

ETHER_MAIL = {
    "types": {
        "EIP712Domain": [{"name": "name", "type": "string"}, {"name": "version", "type": "string"},
                         {"name": "chainId", "type": "uint256"},
                         {"name": "verifyingContract", "type": "address"}],
        "Person": [{"name": "name", "type": "string"}, {"name": "wallet", "type": "address"}],
        "Mail": [{"name": "from", "type": "Person"}, {"name": "to", "type": "Person"},
                 {"name": "contents", "type": "string"}],
    },
    "primaryType": "Mail",
    "domain": {"name": "Ether Mail", "version": "1", "chainId": 1,
               "verifyingContract": "0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC"},
    "message": {"from": {"name": "Cow", "wallet": "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826"},
                "to": {"name": "Bob", "wallet": "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB"},
                "contents": "Hello, Bob!"},
}
ETHER_MAIL_DIGEST = "0xbe609aee343fb3c4b28e1df9e632fca64fcfaede20f02e86244efddf30957bd2"

# --- Safe messages (CompatibilityFallbackHandler) ----------------------------

SAFE_MSG_TYPE = "SafeMessage(bytes message)"
# Precomputed in Safe's own `CompatibilityFallbackHandler.sol` — a PUBLISHED
# check on the derivation, not a source of it.
SAFE_MSG_TYPEHASH_PUBLISHED = "0x60b3cbf8b4a223d68d641b3b6ddf9a298e7f33710cf3d3a9d1146b5a6150fbca"


def eip191_preimage(text: str) -> bytes:
    body = text.encode()
    return b"\x19Ethereum Signed Message:\n" + str(len(body)).encode() + body


def eip191_hash(text: str) -> bytes:
    return keccak256(eip191_preimage(text))


def safe_message_hash(chain_id: int, safe: str, message: bytes) -> bytes:
    """`getMessageHashForSafe(safe, message)`: message is the 32-byte inner hash."""
    struct_hash = keccak256(enc_bytes32(kh(SAFE_MSG_TYPE)) + keccak256(message))
    return keccak256(b"\x19\x01" + safetx.domain_separator(chain_id, safe) + struct_hash)


SAFE = safetx.SAFE
SIWE_TEXT = (
    "app.safe.global wants you to sign in with your Ethereum account:\n"
    f"{SAFE}\n"
    "\n"
    "Sign in to Snapshot with your Safe.\n"
    "\n"
    "URI: https://app.safe.global\n"
    "Version: 1\n"
    "Chain ID: 1\n"
    "Nonce: 32891756\n"
    "Issued At: 2026-09-24T10:00:00.000Z\n"
    "Expiration Time: 2026-09-24T11:00:00.000Z"
)

SNAPSHOT_VOTE = {
    "types": {
        "EIP712Domain": [{"name": "name", "type": "string"}, {"name": "version", "type": "string"}],
        "Vote": [{"name": "from", "type": "address"}, {"name": "space", "type": "string"},
                 {"name": "timestamp", "type": "uint64"}, {"name": "proposal", "type": "bytes32"},
                 {"name": "choice", "type": "uint32"}, {"name": "reason", "type": "string"},
                 {"name": "app", "type": "string"}, {"name": "metadata", "type": "string"}],
    },
    "primaryType": "Vote",
    "domain": {"name": "snapshot", "version": "0.1.4"},
    "message": {"from": SAFE, "space": "ens.eth", "timestamp": 1790000000,
                "proposal": "0x" + "ab" * 32, "choice": 1, "reason": "", "app": "snapshot",
                "metadata": "{}"},
}

# --- Candide's SocialRecoveryModule ------------------------------------------

RECOVERY_DOMAIN_TYPE = "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
RECOVERY_TYPE = "ExecuteRecovery(address wallet,address[] newOwners,uint256 newThreshold,uint256 nonce)"
# Both precomputed in Candide's `SocialRecoveryModule.sol` — published checks.
RECOVERY_DOMAIN_TYPEHASH_PUBLISHED = "0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f"
RECOVERY_TYPEHASH_PUBLISHED = "0x124b64921a7c7e677c6cc3b132eaaa57130bc6fc05ab157f35fe5264a7c198d5"
RECOVERY_NAME = "Social Recovery Module"

MODULE = "0x949d01d424be050d09c16025dd007cb59b3a8c66"
WALLET = SAFE
NEW_OWNERS = ["0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
              "0x1111111111111111111111111111111111111111"]


def recovery_domain_separator(chain_id, module, name, version):
    return keccak256(enc_bytes32(kh(RECOVERY_DOMAIN_TYPE)) + keccak256(name.encode())
                     + keccak256(version.encode()) + enc_uint(chain_id) + enc_addr(module))


def recovery_hash(*, chain_id, module, name, version, wallet, new_owners, new_threshold, nonce):
    owners_packed = b"".join(enc_addr(o) for o in new_owners)   # encodePacked pads array items
    struct_hash = keccak256(enc_bytes32(kh(RECOVERY_TYPE)) + enc_addr(wallet)
                            + keccak256(owners_packed) + enc_uint(new_threshold) + enc_uint(nonce))
    return keccak256(b"\x19\x01"
                     + recovery_domain_separator(chain_id, module, name, version) + struct_hash)


RECOVERY_FIXTURE = dict(chain_id=1, module=MODULE, name=RECOVERY_NAME, version="0.2.0",
                        wallet=WALLET, new_owners=NEW_OWNERS, new_threshold=1, nonce=3)


def recovery_typed_data(fx):
    return {
        "types": {
            "EIP712Domain": [{"name": "name", "type": "string"}, {"name": "version", "type": "string"},
                             {"name": "chainId", "type": "uint256"},
                             {"name": "verifyingContract", "type": "address"}],
            "ExecuteRecovery": [{"name": "wallet", "type": "address"},
                                {"name": "newOwners", "type": "address[]"},
                                {"name": "newThreshold", "type": "uint256"},
                                {"name": "nonce", "type": "uint256"}],
        },
        "primaryType": "ExecuteRecovery",
        "domain": {"name": fx["name"], "version": fx["version"], "chainId": fx["chain_id"],
                   "verifyingContract": fx["module"]},
        "message": {"wallet": fx["wallet"], "newOwners": fx["new_owners"],
                    "newThreshold": fx["new_threshold"], "nonce": fx["nonce"]},
    }


# --- Safe passkey signer (SafeWebAuthnSignerFactory 0.2.1) --------------------

# Expected addresses from the module's CHANGELOG (deployed through Safe's
# singleton factory, so one address on every chain it reached). The app never
# TRUSTS these: it reads code at both before offering the route, and the
# signer address itself is read back from the factory's own `getSigner`.
WEBAUTHN_FACTORY = "0x1d31F259eE307358a26dFb23EB365939E8641195"
P256_PRECOMPILE = 0x100                                            # RIP-7212
P256_FALLBACK_VERIFIER = "0xc2b78104907F722DABAc4C69f826a522B2754De4"  # Daimo
VERIFIERS = (P256_PRECOMPILE << 160) + int(P256_FALLBACK_VERIFIER, 16)   # uint176

RP_ID = "casberi.app"
CLIENT_DATA_FIELDS = '"origin":"https://casberi.app","crossOrigin":false'
AUTHENTICATOR_DATA = hashlib.sha256(RP_ID.encode()).digest() + bytes([0x05]) + bytes(4)


def b64url(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).decode().rstrip("=")


def client_data_json(challenge: bytes) -> str:
    return '{"type":"webauthn.get","challenge":"' + b64url(challenge) + '",' + CLIENT_DATA_FIELDS + "}"


def signing_digest(challenge: bytes) -> bytes:
    message = AUTHENTICATOR_DATA + hashlib.sha256(client_data_json(challenge).encode()).digest()
    return hashlib.sha256(message).digest()


def abi_dynamic(b: bytes) -> bytes:
    pad = (32 - len(b) % 32) % 32
    return enc_uint(len(b)) + b + bytes(pad)


def webauthn_signature_bytes(r: int, s: int) -> bytes:
    """abi.encode(bytes authenticatorData, string clientDataFields, uint256 r, uint256 s)."""
    auth = abi_dynamic(AUTHENTICATOR_DATA)
    return (enc_uint(0x80) + enc_uint(0x80 + len(auth)) + enc_uint(r) + enc_uint(s)
            + auth + abi_dynamic(CLIENT_DATA_FIELDS.encode()))


def contract_signature(signer: str, data: bytes) -> bytes:
    """Safe's contract-signature envelope: r = signer, s = offset 65, v = 0, then len ‖ data."""
    return enc_addr(signer) + enc_uint(65) + bytes([0]) + enc_uint(len(data)) + data


def get_signer_calldata(x: int, y: int) -> str:
    return selector("getSigner(uint256,uint256,uint176)") + (enc_uint(x) + enc_uint(y) + enc_uint(VERIFIERS)).hex()


def is_valid_for_signer_calldata(message: bytes, sig: bytes, x: int, y: int) -> str:
    head = message + enc_uint(5 * 32) + enc_uint(x) + enc_uint(y) + enc_uint(VERIFIERS)
    return selector("isValidSignatureForSigner(bytes32,bytes,uint256,uint256,uint176)") + (head + abi_dynamic(sig)).hex()


CHALLENGE = bytes.fromhex("60551190eef75474ca063ccea91cf3246e92d20bc9eed5808dee6d3d1028818d")
X = int("0x" + "11" * 32, 16)
Y = int("0x" + "22" * 32, 16)
R = int("0x" + "33" * 32, 16)
S = int("0x" + "44" * 32, 16)
SIGNER = "0x5555555555555555555555555555555555555555"


# --- self-test ----------------------------------------------------------------

def self_test() -> int:
    failures = 0

    def check(label, got, want):
        nonlocal failures
        if got == want:
            print(f"  ✓ {label}")
        else:
            print(f"  ✗ {label}\n      got  {got}\n      want {want}")
            failures += 1

    # The Keccak this leans on must prove itself first.
    if safetx.self_test() != 0:
        print("  ✗ safetx-vectors.py's own self-test failed — nothing below is evidence")
        return 1

    # SHA-256, the FIPS vectors, because a WebAuthn digest is SHA-256 and the
    # Swift side carries its own implementation pinned to these same three.
    check("sha256(\"\")", hashlib.sha256(b"").hexdigest(),
          "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    check("sha256(\"abc\")", hashlib.sha256(b"abc").hexdigest(),
          "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    check("sha256(56-byte message, the two-block case)",
          hashlib.sha256(b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq").hexdigest(),
          "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")

    # The general encoder against the spec's own vector.
    check("EIP-712 spec 'Ether Mail' digest", word_hex(typed_data_hash(ETHER_MAIL)), ETHER_MAIL_DIGEST)
    check("EIP-712 encodeType orders dependencies alphabetically after the primary",
          encode_type(ETHER_MAIL["types"], "Mail"),
          "Mail(Person from,Person to,string contents)Person(string name,address wallet)")

    # …and against the SafeTx encoder it must agree with: the first pinned
    # safeTxHash fixture, rebuilt as typed data.
    label, kw = safetx.FIXTURES[0]
    td = {
        "types": {"SafeTx": [{"name": n, "type": t} for n, t in [
            ("to", "address"), ("value", "uint256"), ("data", "bytes"), ("operation", "uint8"),
            ("safeTxGas", "uint256"), ("baseGas", "uint256"), ("gasPrice", "uint256"),
            ("gasToken", "address"), ("refundReceiver", "address"), ("nonce", "uint256")]]},
        "primaryType": "SafeTx",
        "domain": {"chainId": kw["chain_id"], "verifyingContract": kw["safe"]},
        "message": {"to": kw["to"], "value": str(kw["value"]), "data": "0x" + kw["data"].hex(),
                    "operation": kw["operation"], "safeTxGas": kw["safe_tx_gas"],
                    "baseGas": kw["base_gas"], "gasPrice": kw["gas_price"],
                    "gasToken": kw["gas_token"], "refundReceiver": kw["refund_receiver"],
                    "nonce": kw["nonce"]},
    }
    check("general encoder reproduces safetx fixture #1", word_hex(typed_data_hash(td)),
          word_hex(safetx.safe_tx_hash(**kw)))

    # Safe messages: the derived typehash equals the one Safe published.
    check("SAFE_MSG_TYPEHASH matches CompatibilityFallbackHandler.sol", kh(SAFE_MSG_TYPE),
          SAFE_MSG_TYPEHASH_PUBLISHED)
    check("EIP-191 preimage prefix", eip191_preimage("hi")[:26], b"\x19Ethereum Signed Message:\n")
    # Two different inner messages, two different Safe message hashes.
    h1 = safe_message_hash(1, SAFE, eip191_hash(SIWE_TEXT))
    h2 = safe_message_hash(1, SAFE, typed_data_hash(SNAPSHOT_VOTE))
    check("a sign-in and a vote hash differently", h1 != h2, True)
    check("the chain is inside the Safe message hash",
          safe_message_hash(8453, SAFE, eip191_hash(SIWE_TEXT)) != h1, True)

    # Recovery: both published constants reproduce.
    check("recovery DOMAIN_SEPARATOR_TYPEHASH matches SocialRecoveryModule.sol",
          kh(RECOVERY_DOMAIN_TYPE), RECOVERY_DOMAIN_TYPEHASH_PUBLISHED)
    check("EXECUTE_RECOVERY_TYPEHASH matches SocialRecoveryModule.sol",
          kh(RECOVERY_TYPE), RECOVERY_TYPEHASH_PUBLISHED)
    check("the contract's own struct hash and the general encoder agree on ExecuteRecovery",
          word_hex(recovery_hash(**RECOVERY_FIXTURE)),
          word_hex(typed_data_hash(recovery_typed_data(RECOVERY_FIXTURE))))
    reordered = dict(RECOVERY_FIXTURE, new_owners=list(reversed(NEW_OWNERS)))
    check("owner ORDER is inside the recovery hash",
          recovery_hash(**reordered) != recovery_hash(**RECOVERY_FIXTURE), True)
    check("the nonce is inside the recovery hash",
          recovery_hash(**dict(RECOVERY_FIXTURE, nonce=4)) != recovery_hash(**RECOVERY_FIXTURE), True)

    # WebAuthn: the JSON shape the contract rebuilds byte for byte.
    cdj = client_data_json(CHALLENGE)
    check("clientDataJSON is 82 + fields bytes, as WebAuthn.sol computes",
          len(cdj.encode()), 82 + len(CLIENT_DATA_FIELDS))
    check("challenge is base64url, 43 chars, no padding", len(b64url(CHALLENGE)), 43)
    check("authenticatorData is 37 bytes with UP|UV set", (len(AUTHENTICATOR_DATA), AUTHENTICATOR_DATA[32]),
          (37, 0x05))
    sig = webauthn_signature_bytes(R, S)
    check("signature bytes are under WebAuthn.castSignature's bound",
          len(sig) < 193 + 64 + ((len(CLIENT_DATA_FIELDS) + 31) & ~31), True)
    env = contract_signature(SIGNER, sig)
    check("contract signature envelope: v byte is 0", env[64], 0)
    check("contract signature envelope: s word is 65", int.from_bytes(env[32:64], "big"), 65)
    check("verifiers packs the precompile above the fallback", VERIFIERS >> 160, P256_PRECOMPILE)
    return failures


def main() -> int:
    if "--self-test" in sys.argv:
        print("safe-signer-vectors self-test")
        failures = self_test()
        print("  all good" if failures == 0 else f"  {failures} failure(s)")
        return 1 if failures else 0

    print("safe-signer-vectors self-test")
    if self_test() != 0:
        print("  refusing to print constants from an unverified derivation")
        return 1

    print("\nSelectors")
    for sig in ["getMessageHash(bytes)", "getRecoveryHash(address,address[],uint256,uint256)",
                "isGuardian(address,address)", "threshold(address)", "guardiansCount(address)",
                "getGuardians(address)", "nonce(address)", "NAME()", "VERSION()",
                "isModuleEnabled(address)", "getRecoveryRequest(address)",
                "getSigner(uint256,uint256,uint176)",
                "isValidSignatureForSigner(bytes32,bytes,uint256,uint256,uint176)",
                "isValidSignature(bytes32,bytes)"]:
        print(f"  {sig:<72} {selector(sig)}")

    print("\nType hashes")
    print(f"  SAFE_MSG_TYPEHASH               {kh(SAFE_MSG_TYPE)}")
    print(f"  RECOVERY_DOMAIN_TYPEHASH        {kh(RECOVERY_DOMAIN_TYPE)}")
    print(f"  EXECUTE_RECOVERY_TYPEHASH       {kh(RECOVERY_TYPE)}")

    print("\nEIP-712 general encoder")
    print(f"  Ether Mail (spec vector)        {word_hex(typed_data_hash(ETHER_MAIL))}")
    print(f"  Snapshot vote fixture           {word_hex(typed_data_hash(SNAPSHOT_VOTE))}")

    print("\nSafe message fixtures (chainId 1, safe " + SAFE + ")")
    h = eip191_hash(SIWE_TEXT)
    print(f"  SIWE EIP-191 hash               {word_hex(h)}")
    print(f"  SIWE safeMessageHash            {word_hex(safe_message_hash(1, SAFE, h))}")
    v = typed_data_hash(SNAPSHOT_VOTE)
    print(f"  vote safeMessageHash            {word_hex(safe_message_hash(1, SAFE, v))}")

    print("\nRecovery fixture")
    print(f"  domainSeparator                 {word_hex(recovery_domain_separator(1, MODULE, RECOVERY_NAME, '0.2.0'))}")
    print(f"  recoveryHash                    {word_hex(recovery_hash(**RECOVERY_FIXTURE))}")

    print("\nWebAuthn fixture")
    print(f"  verifiers                       {word_hex(enc_uint(VERIFIERS))}")
    print(f"  authenticatorData               0x{AUTHENTICATOR_DATA.hex()}")
    print(f"  clientDataJSON                  {client_data_json(CHALLENGE)}")
    print(f"  signingDigest                   0x{signing_digest(CHALLENGE).hex()}")
    sig = webauthn_signature_bytes(R, S)
    print(f"  signature bytes                 0x{sig.hex()}")
    print(f"  contract signature              0x{contract_signature(SIGNER, sig).hex()}")
    print(f"  getSigner calldata              {get_signer_calldata(X, Y)}")
    print(f"  isValidSignatureForSigner       {is_valid_for_signer_calldata(CHALLENGE, sig, X, Y)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
