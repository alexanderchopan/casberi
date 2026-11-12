# Architecture and threat model

A map for a security review: what the app holds, what signs, what leaves the device, and what it trusts. Each line names the file that implements it. Paths are under `Casberi/Casberi/` unless they start with `docs/`, `scripts/`, `tools/` or `Casberi/Shared/`.

This page describes the design. It is not an audit, and there has been none (`docs/specs/signing-safety-spec.md`).

## Shape

- **No server.** Every request goes from the device straight to the service it names. Casberi runs no backend, relay or account system (`Model/NetworkReach.swift`).
- **One store.** User content is one SwiftData store in the app group. iCloud mirroring through CloudKit is off until the person turns it on (`Casberi/Shared/SharedStore.swift`).
- **No contract of Casberi's on Ethereum.** The account runs on Safe's, Rhinestone's and the ERC-4337 EntryPoint's deployed contracts (`Model/YourAccount.swift`). The one contract Casberi wrote is the Aztec account in `tools/aztec-account/contract/`.
- **Three JavaScript engines** run third-party privacy SDKs in hidden web views with no direct network access (see below).

## The account

"Your account" is a Safe 1.4.1 whose owner is Safe's shared WebAuthn signer, used through Safe's ERC-4337 module and EntryPoint v0.7 (`Model/YourAccount.swift`). Bundlers are public and keyless; there is no paymaster (`Model/YourAccountOp.swift`).

| Role | What it is | Where |
| --- | --- | --- |
| Device key | P-256, made in the Secure Enclave, one per device, rotated on every send. | `Model/YourAccountKey.swift` |
| Recovery key | P-256 in iCloud Keychain. A second owner at threshold 1 with no delay; its job is moving the account to a new device key. | `Model/YourAccountRecovery.swift` |
| Co-signer | Optional. The person's own external wallet, reached over WalletConnect. Turning it on raises the Safe's threshold to 2. | `Model/YourAccountSignerLink.swift`, `Model/YourAccountChain.swift` |
| Exported key | "Export key" adds a fresh secp256k1 owner and shows it once. Nothing secret is stored. | `Model/YourAccountExport.swift` |

No platform passkey or relying party is involved: the app builds the WebAuthn data and the Enclave key signs it (`Model/SafeWebAuthnSignature.swift`).

## Keys and where they live

| Key | Storage | Syncs | User presence |
| --- | --- | --- | --- |
| Account device keys | Secure Enclave; wrapped blob in Keychain, `WhenPasscodeSetThisDeviceOnly` | No | `.biometryCurrentSet` when biometrics were enrolled at creation (`YourAccountKey.swift`) |
| Account recovery key | iCloud Keychain, `AfterFirstUnlock` | Yes | Device-owner authentication, asked by the app before it signs |
| Safe co-signer (Enclave) | Secure Enclave, `WhenPasscodeSetThisDeviceOnly`; creation refused without biometrics | No | `.biometryCurrentSet` (`SafeEnclaveKey.swift`) |
| Safe co-signer (secp256k1) | Keychain, `WhenUnlockedThisDeviceOnly` | No | `.biometryCurrentSet` (`SignerKey.swift`) |
| Aztec root | iCloud Keychain, `AfterFirstUnlock` | Yes | App-level check on reveal (`Model/Aztec/AztecRoot.swift`) |
| Private-money root | iCloud Keychain, `AfterFirstUnlock`. Privacy Pools, Railgun and fresh-address keys derive from it by HKDF. | Yes | App-level check on spend (`PrivateRootKey.swift`, `PrivateRoot.swift`) |
| Note-lock key | iCloud Keychain, `AfterFirstUnlock` | Yes | Device-owner authentication to open a note (`NoteLock.swift`) |
| Logos key | Keychain, `WhenUnlockedThisDeviceOnly`. Testnet only; the file says not to reuse it for real value. | No | See `LogosKey.swift` |

`scripts/keychain-audit.py` fails the build on a Keychain item whose policy is not one of the declared ones, and lists every synchronizable exemption.

### Third-party credentials

API keys, OAuth tokens and web-session cookies go through `Model/TokenVault.swift`. Pasted keys on an allowlist sync through iCloud Keychain; session cookies and refreshing OAuth tokens stay on the device (`AfterFirstUnlockThisDeviceOnly`). Seats that use the person's own web session are read-only by rule.

### Keys in the source

Two shared, read-only data keys ship in the binary and are in the tree on purpose: Alchemy (`Model/IngestSupport.swift`) and Zerion (`Model/ZerionAPI.swift`). They read public chain data; the worst case if abused is quota. The WalletConnect project id and the GitHub and Twitch client ids are public identifiers. No signing key, user credential or developer key is committed; development keys live in the developer's login Keychain (`scripts/dev-keys.sh`).

## The signing path

1. **Preview.** Before Face ID the person can open Details: recipient, fee, nonce, the simulation's result, the calls in words, the hash and the bytes (`Model/YourAccountPreview.swift`). Calls are described from ERC-7730 descriptors bundled with the app and decoded on the device (`Model/ClearSign.swift`).
2. **Warnings.** Sanctions-list, token and address warnings do not block; they require a second tap (`Model/MoveWarnings.swift`, `Model/MoveChecks.swift`).
3. **Blocking checks** (`Model/YourAccountChain.swift`):
   - a simulation that fails, or a swap that would pay less than quoted, is refused;
   - Safe's module must return the same hash the phone computed;
   - after signing, the signer contract must accept the signature (ERC-1271);
   - with a co-signer, the Safe's own `checkSignatures` must pass.
4. **Signature.** Produced by the Secure Enclave key (`Model/YourAccountKey.swift`).

Signing an external Safe's queued transaction as its co-signer is a separate path: `Model/SafeSignChecks.swift`, `Model/SafeSigner.swift`, `Model/SafeTransaction.swift`. Its simulation is information only and never blocks (`Model/SafeSimulator.swift`).

Checked by `scripts/safe-signer-selftest.sh`, `scripts/safetx-selftest.sh`, `scripts/clearsign-selftest.sh`, `scripts/safe-sign-checks-selftest.sh`, `scripts/move-warnings-selftest.sh`.

## Network

- **Declared hosts.** Every host the app may contact is listed in `Model/NetworkReach.swift`. `scripts/network-reach-audit.sh` fails the build on a host literal that is not declared.
- **Recorded hosts.** `Model/NetworkLedger.swift` records host, count and time at runtime, shown in the app. It does not cover row images, WalletConnect's socket or SDK-internal hosts.
- **Tor.** On iOS, requests that would link a wallet address to an IP go through an embedded Tor client, one circuit per wallet, with no direct fallback except for hosts that refuse Tor (`Model/TorRoute.swift`, `Model/TorClient.swift`, `Vendor/TorKit`). The Mac build has no Tor.

## The JavaScript engines

| Engine | SDK | Loaded as | Network |
| --- | --- | --- | --- |
| Privacy Pools | 0xBow's v2 SDK | Hidden web view, own URL scheme, non-persistent store, circuit files pinned by SHA-256 | Through Swift only (`Model/PrivacyEngine.swift`) |
| Railgun | Railgun's wallet SDK | Hidden web view, own URL scheme | Through Swift only; undeclared hosts refused; broadcaster sockets over Tor (`Model/RailgunEngine.swift`) |
| Aztec | Aztec's wallet SDK, native prover | Hidden web view served from a loopback server on 127.0.0.1 | Through the loopback server (`Model/Aztec/AztecEngine.swift`, `AztecEngineServer.swift`) |

Each page's Content-Security-Policy allows no outside host. Key material crosses into JavaScript in each engine: the derived seed for Privacy Pools and Railgun, the root for Aztec. How to reproduce the committed bundles: `tools/README.md`.

## Data at rest

- The store and the Keychain rely on iOS data protection. Explicit file protection is set for the Privacy Pools engine's files and the note trash.
- A locked note's title, words, picture and links are sealed with ChaChaPoly under the note-lock key. Copies that reached CloudKit or a backup before locking are not covered (`Model/NoteLock.swift`).
- The share extension and widgets have the app group and nothing else (`Casberi/ShareExtension/`, `Casberi/CasberiWidgets/`).

## Trust assumptions and known limits

- **iCloud Keychain is the recovery boundary.** Whoever holds the person's iCloud Keychain holds the recovery key, and can move the account (`docs/specs/safe-wallet-spec.md`). The same holds for the Aztec and private-money roots.
- **The co-signer is enforced on chain for the Safe, by the app for Aztec.** An altered app could skip the Aztec co-signer (`docs/specs/aztec-security-model.md`).
- **Third parties in the path.** Public bundlers, Safe's transaction service, Railgun broadcasters, the Privacy Pools relayer and association-set provider, Alchemy and Zerion for balances. Each can withhold or delay; none holds a key.
- **Warnings depend on outside data** (GoPlus, Blockscout, the OFAC list) and do not block.
- **Marked UNMEASURED in the source.** Some paths have not been exercised against the live service; each says so at the top of its file. Search for `UNMEASURED`.
- **Aztec private send and exit have not moved real money** (`docs/specs/aztec-security-model.md`).
- **No audit and no bug bounty.** Reporting: `SECURITY.md`.
