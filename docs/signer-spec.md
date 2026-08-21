# The Casberi co-signer — build spec

**Status: SPEC ONLY. No Swift written, nothing compiled, nothing measured.**
Authored on Linux with no Xcode and no Swift toolchain. The one thing here
that IS verified is the cryptographic constants — see §3, they are computed
by `scripts/support/safetx-vectors.py`, not recalled.

Ruling: **prd §425**. Read that first — it carries the reasoning and the
refusals. This file carries the mechanics.

---

## 1. What is being built, in one paragraph

Casberi generates a secp256k1 key that lives and dies on this phone, and
that key is added — by the person, from their existing desktop wallet — as
one **owner of a Safe whose threshold is 2 or more**. Casberi can then
approve transactions the desktop proposes, and cannot move money by itself,
because the Safe contract will not execute on one signature. The key holds
no funds, needs no gas, has no seed phrase, and is never exported.

The product sentence: **"Your computer can't spend without your phone's yes."**

---

## 2. What already exists (do not rebuild)

| Piece | Where | State |
|---|---|---|
| Safe detection, owners, threshold, nonce | `Model/SafeBridge.swift` | shipped |
| Pending queue, "2 of 3 collected — your signature is needed" | `Model/SafeBridge.swift` | shipped |
| Owner/threshold/module/guard change alerts | `Model/SafeBridge.swift` | shipped |
| Keccak-256 | `Model/Keccak256.swift` (`Keccak256.hash([UInt8]) -> [UInt8]`) | shipped, harnessed |
| EIP-55 checksum | `Model/Keccak256.swift` (`EIP55.checksum`) | shipped, harnessed |
| Per-chain `eth_call` over public RPC | `WalletApprovals.rpcRead(network:…)` | shipped, measured |
| Money receipt anatomy, torn vs flat edge | `Model/MoneyReceipt.swift` | shipped, harnessed |
| Alarm notifications, quiet hours, time-sensitive | `Model/NotifySweep.swift` | shipped, harnessed |
| Address book with kinds | `Model/AddressBook.swift` | shipped |
| Device-only Keychain policy + audit | `TokenVault`, `scripts/keychain-audit.py` | shipped |

The **read** half of this feature is done. What is missing is a key, a hash,
a signature, and a consent surface.

---

## 3. The numbers (VERIFIED — do not retype from memory)

Derived by `python3 scripts/support/safetx-vectors.py`, whose Keccak-256 is
itself checked against four published vectors first (empty string, `"abc"`,
the ERC-20 `Transfer` event topic, the `transfer(address,uint256)` selector)
so it cannot be quietly running SHA3 instead of Keccak.

```
DOMAIN_SEPARATOR_TYPEHASH (Safe >= 1.3.0)
  keccak256("EIP712Domain(uint256 chainId,address verifyingContract)")
  0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218

SAFE_TX_TYPEHASH
  keccak256("SafeTx(address to,uint256 value,bytes data,uint8 operation,
             uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,
             address gasToken,address refundReceiver,uint256 nonce)")
  0xbb8310d486368db6bd6f849402fdd73ad53d316b5a4b2644ad6efe0f941286d8

LEGACY domain typehash (Safe < 1.3.0) — recognised only in order to REFUSE
  keccak256("EIP712Domain(address verifyingContract)")
  0x035aff83d86937d35b32e04f0ddc6ff469290eef2f1b692d8a815c89404d4749
```

Safe contract selectors (derived the same way):

```
getTransactionHash(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,uint256)
                        0xd8d11f78     <- the cross-check in §5, load-bearing
domainSeparator()       0xf698da25
VERSION()               0xffa1ad74
nonce()                 0xaffed0e0
getOwners()             0xa0e67e2b
getThreshold()          0xe75235b8
```

### The hash

```
domainSeparator = keccak256(abi.encode(
    DOMAIN_SEPARATOR_TYPEHASH, chainId, safeAddress))

structHash = keccak256(abi.encode(
    SAFE_TX_TYPEHASH, to, value, keccak256(data), operation,
    safeTxGas, baseGas, gasPrice, gasToken, refundReceiver, nonce))

safeTxHash = keccak256(0x19 || 0x01 || domainSeparator || structHash)
```

`abi.encode` here is only the static head: every field is one 32-byte word,
addresses left-padded with 12 zero bytes, `uint8 operation` padded to 32.
**`data` is a dynamic `bytes`, so its KECCAK goes in the word, never the
bytes themselves** — inlining it is the classic way to produce a plausible
wrong hash.

### Fixtures the harness must pin

Safe `0x1234567890123456789012345678901234567890`, `gasToken` and
`refundReceiver` zero, all gas fields 0.

| Case | safeTxHash |
|---|---|
| 1 ETH → `0xabcd…abcd`, mainnet, nonce 0 | `0x60551190eef75474ca063ccea91cf3246e92d20bc9eed5808dee6d3d1028818d` |
| same, nonce 1 | `0x7a9bddd1a58aa59b34bf69d88f7210def0dd22cd4cc7822040d8bff3d3e2bd8d` |
| same, chainId 8453 (Base) | `0x7828bf9e6c5d5d73fddb54b51222c9bee3bc4031a0e76c82551b8a3c02e11739` |
| USDC `transfer` calldata, op 0, nonce 7 | `0x7be693d2f7ba83533e3052848cfd6e799dab186e964fcab31e3e4ae19cefcc8d` |
| identical but op 1 (DELEGATECALL) | `0xf563d44af5a41ac0f458c21c2d203ff7da09149720227ac15aff2b345df24d38` |

The last three pairs exist to prove `nonce`, `chainId` and `operation` are
each really inside the preimage. A signer that dropped `nonce` would let a
signature be replayed at a later nonce; one that dropped `chainId` would let
a mainnet signature execute on a testnet Safe at the same address.

---

## 4. The key

`Model/SignerKey.swift` (new).

1. 32 bytes from `SecRandomCopyBytes`. Reject the (astronomically unlikely)
   out-of-range value rather than clamping — a clamped key is a biased key.
2. secp256k1 → uncompressed public key, drop the `0x04` prefix.
3. `address = last 20 bytes of Keccak256(pubkey[1...])`, rendered through the
   existing `EIP55.checksum`.
4. Store the 32 private bytes in the Keychain:
   - `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
   - `kSecAttrSynchronizable = false`
   - `SecAccessControlCreateWithFlags(..., [.biometryCurrentSet, .privateKeyUsage])`
     so **every signature costs a Face ID**, and enrolling a new face
     invalidates the item rather than silently widening who can sign.

`scripts/keychain-audit.py` already fails the build on a `SecItemAdd` that
omits a device-only policy or `kSecAttrSynchronizable` — this key must
satisfy it with no `KNOWN_EXEMPT` entry.

**No export, no seed phrase, no iCloud copy, ever.** This is the security
model, not a missing feature: the guarantee is "this phone's yes", and a
phrase in a drawer is a second phone. Recovery is one level up — the Safe's
other owners `swapOwner` a lost phone out. The setup copy must say this
plainly, because every other wallet app trains the opposite expectation.

**Curve library.** `21-DOT-DEV/swift-secp256k1` — a thin SPM wrapper around
bitcoin-core's `libsecp256k1`, with the `recovery` module in its default
traits (Ethereum's 65-byte signature needs the recoverable form). Pin an
exact revision in `Package.resolved` like every other dependency. It builds
for Linux too, which means the signing selftest can run in CI, not only on a
Mac. Never a pure-Swift curve implementation: no constant-time guarantee, no
audit history. Consider vendoring the C sources in-tree before TestFlight —
the app needs roughly four calls (context create, pubkey create, pubkey
serialize, recoverable sign).

**Catalyst.** Add the package and build Catalyst immediately —
`verify.sh` step 1b compiles it and hard-fails, which is exactly the gate
that caught ReownAppKit. Do not assume a C package is portable.

---

## 5. The rail that makes the encoder safe: ask the Safe

**Never sign a hash Casberi computed alone.** Before signing, `eth_call`
`getTransactionHash(...)` (`0xd8d11f78`) on the Safe itself with the same ten
fields, and require the answer to equal the locally computed `safeTxHash`.
Refuse to sign on any mismatch, and on any failure to read.

This is the whole safety argument for §3 in one call:

- It makes a wrong domain separator, a wrong type hash, a wrong ABI padding
  or an inlined `data` field **impossible to ship silently** — the two
  disagree and the app declines rather than producing a valid signature over
  the wrong transaction.
- It handles Safe version drift for free. A Safe < 1.3.0 uses the legacy
  domain in §3 and its `getTransactionHash` will disagree with our modern
  separator, so old Safes are refused automatically rather than by a version
  string we have to maintain.
- It costs one `eth_call` on a screen the person is already waiting on.

The local encoder is still required — it is what the cross-check compares
*against*, and a lone remote answer is a number handed to us by whatever RPC
host answered.

---

## 6. Signature format

- Sign the 32-byte `safeTxHash` **directly** (EIP-712 path). Do NOT
  `personal_sign` it.
- Serialize `r (32) || s (32) || v (1)` with **v = 27 or 28**.
  - Safe reads `v` as a discriminator: `0` = contract/EIP-1271 signature,
    `1` = pre-approved hash, `> 30` = `eth_sign` with the
    `"\x19Ethereum Signed Message:\n32"` prefix, and 27/28 = a plain
    EIP-712 signature over the hash. Emitting 31/32 here means the Safe
    verifies against a *prefixed* hash and recovers the wrong address.
- **Low-s only.** libsecp256k1 normalizes by default; assert it in the
  harness rather than trusting the default (`s <= n/2`).
- Casberi produces exactly ONE signature and hands it off. Packing several
  owners' signatures for `execTransaction` is the executor's job — but note
  for the record that Safe requires them **sorted by owner address
  ascending**, which matters if Casberi ever gains an execute path (it does
  not, in this ruling).

---

## 7. Transport — build tier 1, keep tier 0

**Tier 1 (default).** Safe's own transaction service, which `SafeBridge`
already reads. `POST /api/v1/safes/{address}/multisig-transactions/{safeTxHash}/confirmations/`
with the signature. Keyless — the signature is its own authorization.

This is Casberi's **first outbound write in its history**, so it takes the
conduct-guard treatment the read-only bridges already have: the signing file
may reach exactly this one endpoint shape, and
`scripts/safetx-selftest.sh` fails the build on any other write verb or host
appearing in it. `Model/NetworkReach.swift` must declare the host, and the
setup copy must say plainly that a confirmation is posted to Safe's service.

**Tier 0 (fallback, keep it working).** Paste / share sheet / `casberi://`
deep link carrying the proposed transaction in, signature out. No
third-party service at all. This is the honest degraded path when the
service is down, and it is what keeps the "no server" claim true in the
strongest reading. QR is optional and was never load-bearing.

**Tier 2 (not now).** `ReownWalletKit` is already inside the pinned
`reown-swift` package but unlinked, so Casberi could act as a WalletConnect
*wallet* peer and take requests straight from Safe's web app. Explicitly out
of scope for the first ship; note it exists so nobody re-researches it.

---

## 8. The refusals (each one a harness assertion)

1. **Refuse if `threshold < 2`.** A 1-of-N Safe where Casberi is an owner is
   a custodial wallet wearing a multisig's clothes — the entire promise is
   void. Check the threshold from the chain at sign time, not from a cached
   config.
2. **Refuse if Casberi's key is not currently an owner** — read from the
   chain, never a local flag.
3. **Refuse on any `getTransactionHash` mismatch or read failure** (§5).
4. **Refuse to sign anything that is not a SafeTx.** No `personal_sign` of
   arbitrary text, no raw `eth_sign`, no free-form typed data, no
   `eth_sendTransaction`. The signing file must contain no other signing
   entry point, guarded negatively on a comment-stripped copy (this file
   documents the forbidden methods by naming them — the Obsidian/Cursor
   lesson, which has now bitten six times).
5. **Refuse to summarise calldata that could not be decoded.** Show the
   selector and the hash and say so. §83 in the one place a fluent wrong
   summary costs real money.
6. **No export path** — assert no code reads the private bytes out of the
   Keychain except the signing function.

---

## 9. Surfaces

**Setup.** On a watched Safe's room: *"Make this phone a signer."* One tap →
key generated → the address with a copy button and one sentence: *"Add this
address as an owner from your other wallet, and set the threshold to 2.
Casberi will notice when you have."* No form, no toggle (§217's tripwire —
the moment it grows a toggle it is the connect screen §96 deleted). The
address joins the address book as its own row labelled "This phone".
Connected state is read off the chain.

**The ask.** Alarm notification: *"Your signature is needed — 1 of 2
collected."* Opens the pending transaction drawn as a **money receipt with a
flat bottom edge** (`MoneyReceipt` already means "still in the machine" by
that edge). Subject disc, decoded action in plain words, amount, signature
progress, one **Sign** button → Face ID → posted. The edge tears when the
transaction executes.

**Afterwards.** The signature lands as a `Thing` — the corpus ends up
holding proposed → signed → executed. Use the existing `sourceRef` shape and
declare it against `scripts/ref-shape-audit.py`.

**Leaving.** Data tray, beside the two existing delete verbs: delete the
key, with the honest sentence that the other owner should `swapOwner` first.

**No app-open Face ID lock.** The key is gated at the only moment that
matters. An open lock protects the corpus, not the key, and that is a
separate question this feature must not smuggle in.

---

## 10. Build order

| # | Step | Verifiable where |
|---|---|---|
| 1 | `Model/SafeTransaction.swift` — Foundation-only encoder | Linux or Mac |
| 2 | `scripts/safetx-selftest.sh` — compile it WHOLE, pin §3's fixtures, mutation-test each field out of the preimage | needs `swiftc` |
| 3 | Add `swift-secp256k1`, pin revision, **build Catalyst immediately** | Mac |
| 4 | `Model/SignerKey.swift` — keygen, address, Keychain with biometric gate | Mac |
| 5 | Signing + low-s + v=27/28, test vectors, recover-back assertion | Mac (or Linux CI) |
| 6 | The `getTransactionHash` cross-check rail (§5) | Mac + live RPC |
| 7 | Surfaces (§9), `NetworkReach` entry, prd facets, demo seeds | Mac + simulator |
| 8 | Tier-1 POST with its conduct guard | Mac |
| 9 | **Device test against a real 2-of-3 Safe holding trivial funds** | iPhone |

Step 9 is not optional and nothing before it is evidence. No simulator has a
Secure Enclave gesture, and no harness here can make a Safe execute.

### Mutations step 2 must survive

Each of these must turn the harness RED, or the assertion is decorative:
drop `nonce` from the struct hash; drop `chainId` from the domain; inline
`data` instead of its keccak; swap `baseGas`/`safeTxGas` order; use the
legacy domain typehash; emit `v = 31` instead of 27; return a high-s
signature; let `threshold == 1` through.

---

## 11. Known unknowns

- **Nothing here has been compiled.** The constants are verified; the Swift
  is unwritten.
- Whether `swift-secp256k1` builds clean for Mac Catalyst is **unmeasured**.
- The exact current shape of Safe's confirmations POST body should be
  re-read from Safe's live API docs before writing tier 1; `SafeBridge`'s
  existing reads are measured, this write is not.
- Safe deployments differ per chain; the cross-check in §5 makes that safe
  by construction rather than by a table we maintain.
