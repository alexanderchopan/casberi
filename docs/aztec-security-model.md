# Your private account on Aztec: the security model (prd §1700–§1700g)

What Casberi trusts, what it checks instead, who can move money, and what is
not proven yet. The user-facing version is the website's Security and Privacy
sections (`website/docs.html`, `website/privacy.html`); this is the long form
for whoever changes the code.

## The three parts of your account

| | Public account | Private balance | Private account |
|---|---|---|---|
| What | a Safe (4337 / 7579 adapter) | 0xBow Privacy Pools notes | an Aztec account (Schnorr, initializerless) |
| Where | Base, Ethereum, Robinhood | Ethereum | Aztec |
| Signs with | this iPhone's Secure Enclave key (passkey), plus the co-signer when required | keys derived from one iCloud Keychain secret | keys derived from one iCloud Keychain secret |
| Co-signer | enforced on chain (threshold 2) | n/a | enforced by Casberi (`AztecCoSign`) |

## Keys

- **The root** (`Model/Aztec/AztecRoot.swift`): 32 random bytes, a synchronizable
  generic password in iCloud Keychain, `AfterFirstUnlock`, in the app id's shared
  group (`TokenVault.sharedAccessGroup`), so only Casberi-signed apps read it.
  Exempt in `keychain-audit.py` with that reason.
- **Derived on the device, never stored**: SHA-512(root ‖ label) reduced into each
  field — `casberi/aztec/v1/secret` (the account secret), `…/signing` (the Schnorr
  key), `feejuice/<nonce>` and `shield/<nonce>` (deposit claim secrets). They live
  only in the engine page's memory.
- **A used account never gets a new root**: once `AztecAccountStore.snapshot.used`,
  the engine asks `AztecRoot.ensure(create: false)`. A missing root (iCloud Keychain
  off, not yet synced) makes Your account say "Aztec key not on this iPhone"
  instead of quietly starting a different, empty account.
- **Reveal key** (`MoveExportKey`): Face ID, then the co-signer, then the engine's
  `exportKeys` (Casberi's own call, never an app's): secret key, signing key, salt
  0, account kind, shown once behind a hold.

## The engine

- Aztec's own `EmbeddedWallet` (a PXE) in a hidden `WKWebView` served from
  `127.0.0.1:48713` (`AztecEngineServer`), its storage the origin's OPFS.
- Proofs on Aztec's native iOS prover (`libbb-external`, v6.0.0, fetched by
  `scripts/aztec-engine.sh`, never committed); none on Mac Catalyst
  (`AztecProver.isAvailable` is false there, and nothing Aztec is offered).
- Every request the page makes goes through `/net`, which refuses any host
  `NetworkReach` does not declare for "Your Aztec account" or "Aztec proving
  parameters", and sends the rest through `IngestSupport` (Tor, receipts). Your
  own Aztec node (Nodes) is the one exception: reached directly, as every own node.
  The page's CSP allows `connect-src 'self' data: blob:` only.

## Who can move money

- **Without the co-signer**: this iPhone after Face ID. Anyone holding your Apple
  account and a device passcode holds the root, so can spend from Aztec.
- **With the co-signer required**: Casberi asks it before every Aztec transaction it
  makes (a private send, an exit's Aztec half, an Aztec app's transaction, Reveal
  key): a readable EIP-712 statement through its wallet, recovered and checked
  against the Signer before proving; fails closed. **Aztec does not enforce this.**
  Casberi does, and the root is readable only by Casberi, so it stands on every
  ordinary path. A jailbroken phone or an altered copy of Casberi could skip it.
  The on-chain version (a two-signature Aztec account) is a later option (§1700f
  item 4); it would be a new address.
- Claims of your own deposits (gas, Shield) do not ask: they only bring your own
  money in.

## Moving money in and out (Shield, §1700d)

- Shield's Ethereum portals are unverified and its Aztec contracts published only
  in its web app: a knowing exception. human.tech closed the source in 2026 and
  says it may reopen it at a stable Aztec release (their reply, 2026-11-05); the
  addresses Casberi pins match their live `6.0.0_2026-11-02` deployment (checked
  that day). What Casberi checks instead: every address
  is pinned; on Aztec each contract's class id read from the node must equal the
  class computed from the interface Casberi carries (`fetch-shield.mjs`: bridge,
  token, minter proxy), else it is refused; every Ethereum leg is a Safe operation
  with its simulation and Face ID (and the co-signer); every Aztec leg is proved on
  the phone after the ask.
- Shield gates both directions with a human.tech signature, public mode too: under
  $1,000 a Human Passport score of 20 on the signed-in Ethereum address, above it
  Proof of Clean Hands. Their verify panel (`id.human.tech`, an iframe) offers only
  those two; zkEmail and zkPassport are stamps toward the score.
- The human.tech signature: Casberi asks for the
  Passport method only, never Proof of Clean Hands (government ID). The Safe signs
  Shield's and Human Passport's sign-ins with ERC-1271 (`YourAccountMessage`): a
  20-byte zero validator through the 7579 adapter, both keys at threshold 2.
- Gas goes through Aztec's own Fee Juice portal, open and unchecked.
- An exit pays exactly the Ethereum address in its sentence; anyone may finish it
  (`caller_on_l1` zero), and it pays only that address.

## Apps

- An Aztec app opened in Casberi's browser (from a link to a host in `AztecApps`)
  talks to the engine through Aztec's wallet-sdk relay, injected into an isolated
  content world the page cannot reach; the shell names the page's origin, never
  the page. Every connect, the emoji check (Aztec's own `hashToEmoji`) and every
  transaction ask, then the co-signer.
- Discovery is answered unasked (prd §1700j): the page learns Casberi's name, id
  and icon, which it knows already by being in Casberi's browser, and no address.
  Connect and the emoji check are asked when the person picks Casberi in the app,
  and every call of the app's waits until both are yes
  (`tools/aztec-engine/src/connect-gate.js`, `aztec-connect-selftest.sh`).
- The Ethereum provider (`BrowserEthereum`, Human Passport's door) connects on an
  ask, signs only messages (personal_sign, Ethereum typed data), never sends.
- In Apps on Aztec's browser (the directory door and a saved Aztec app's link)
  the same provider also sends (prd §1700k): one `eth_sendTransaction` call at a
  time, from your account on Ethereum to a named address, never a raw
  transaction or a batch. The sheet says what it does (an approval read with its
  limit, any other call through `ClearSign`, or "Casberi cannot read what this
  call does"); the call runs against the real state first and nothing is signed
  if it would fail; then Face ID, and the Signer when the account needs both
  keys (`YourAccountChain.appCalls`).

## Proven, and not yet

- **Proven on mainnet, on the phone (2026-11-04)**: the gas deposit and its claim
  (30 AZTEC; claim tx `0x20c0b759…`); Human Passport's sign-in by the Safe with
  the co-signer.
- **Proven off chain**: the 7579 zero-validator signature (state-override replay
  against the account); every Shield calldata against viem
  (`shield-bridge-selftest.sh`).
- **Not yet moved real money**: a Shield deposit and claim, a private send, an exit
  and its Finish. They wait on a Human Passport score of 20.
