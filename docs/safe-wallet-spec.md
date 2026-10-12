# Your account (a Safe) — design spec (draft, 2026-10-12)

**Status: draft for the user's design pass. Nothing is built.** Building waits
for Apple to confirm the developer account as an organization (3.1.5(i)).

## 1. What it is

A self-custody wallet, created in the app, that is a **Safe from its first
launch**. Casberi runs no server and pays no gas.

- **Daily key:** a Secure Enclave key on each of your devices, unlocked with
  Face ID or Touch ID, never exportable (`SafeEnclaveKey`).
- **Recovery key:** a 12-word key synced through iCloud Keychain. It is a
  **guardian, not an owner**: it can start a recovery that takes 3 days, and any
  of your devices can cancel it.
- **Gas** comes from the Safe's own balance (Safe's 4337 module and a commodity
  bundler). Fees are shown in dollars.
- **Chains: Base and Ethereum** (user, 2026-10-12). **Same address on both.** It can receive money before it
  exists on chain; the first send creates it.

It is the Pro tier's "writing wallet" in the business model.

**Called "Your account" in copy** (user, 2026-10-12); its page says "Secured by Safe" once. "Safe" alone keeps meaning a Safe you watch or co-sign.

**Safe, not Splits (user, 2026-10-12).** Splits' accounts sign with passkeys tied to splits.org, which Casberi can't use, and collect signatures through Splits' API. Splits' split contracts stay open as a later "Split income" feature that pays into the Safe.

## 2. Where it lives (existing law, no new places)

| Need | Existing place | Rule |
|---|---|---|
| Create one | Wallet › Accounts menu, first row **New account** | §1108: a verb that adds an account is that menu's first row |
| Send, Swap, Receive, Add money | **An Actions screen of their own**, opened by **one button in the bottom band beside Search** | Amends §774/§1108, which put money verbs as rows leading Holdings (user, 2026-10-12). No fifth tile: the Wallet keeps four (§1107) |
| Activity | **Home** list (sends, receives, fees) | §1039 |
| Something needs you | **Home › Needs you** (a recovery in progress, a stuck send) | §1111 |
| Recovery, devices, phrase | **The account sheet**, as sections under its tiles | Security keeps its checkup (§1107) |
| Signing | The existing Safe **sign block**: clear signing, simulation, net changes | §834, §1249 |
| Alerts | Wallet notification switch; a recovery **stands alone** | §1237 |

Trays are `DSTray`; verbs are rows (`DSDoorRow`); nothing at the top of a screen (§752).

## 3. Features and their buttons

### v1 — the first release

**The Actions screen.** Send, Swap, Receive and Add money live together on one sheet of their own, not as rows in Holdings (user, 2026-10-12).
- **Its door:** the band's trailing seat. On every other page it is ✎; on the Wallet, once you have an account of your own, it is **your account**: the face's glass and size, `wallet.bifold`, no word (as Notes and Markets put their own controls there, §1207a). With no account, ✎ stays. While a recovery waits it carries the attention dot.
- **The sheet:** the Holdings sheet's anatomy. Your account's box, then **four tiles: Send · Swap · Receive · Add money** (a sheet's acts are tiles, four at most, §1178), then sections: **Recovery** (recovery key, waiting period, Show recovery phrase), **Devices** (each owner, Add a device), **Account** (address, name, notifications, activity) and one footnote on who holds the keys.
- Mockup: `design/mockups/wallet-account-button.html` (frames 1 and 7 are today's build with the button drawn in).
- Each action opens its own tray, below.

**1. Create**
- Accounts menu → **New account** → tray "New account"
  - Name field (default "My account")
  - One footnote: what Face ID and iCloud do here
  - **Create** (Face ID) → makes the Enclave key and the iCloud recovery key, then shows the address
- Nothing goes on chain and nothing is paid until the first send.

**2. Receive**
- Actions › **Receive** → tray
  - Address, large, with a QR code
  - The chains it works on, as a line of icons ("Base · Ethereum")
  - **Copy** · **Share**
  - One footnote: send only on the chains listed

**3. Add money**
- Actions › **Add money** → tray
  - **From an exchange**: the address and the chain to pick
  - **From another wallet**: the same, plus a QR code
  - Card or Apple Pay is **open question 1**: every major onramp now needs a signed session from a server

**4. Send**
- Actions › **Send** → tray, one step at a time:
  1. **To:** search field (an address, ENS name, or someone in Addresses), **Paste**, **Scan**
  2. **Amount:** token picker, an amount field in dollars or token, **Max**
  3. **Review**: the existing sign block, with recipient, amount, fee in dollars, the balance change, and warnings (first send to this address, a lookalike of a saved address, a contract)
  4. **Send** (Face ID)
- After sending, a pending row on Home that settles into the receipt.
- No gas: Send stays drawn, and Review says "Add about $0.05 of ETH on Base to pay fees" with **Add money** (no dead control, §83).

**5. Swap**
- Actions › **Swap** → tray, one screen:
  - **From:** a token you hold (defaults to the largest), an amount field, **Max**
  - **To:** a token picker; your holdings first, then a search over a token list. A token Security calls fake is never offered; an unlisted one asks you to confirm
  - The quote, live: "You get about 1,204 USDC", minimum received, the fee in dollars, price impact once it passes 1%
  - **Review**: the sign block, drawn as one swap ("Swap 0.5 ETH for at least 1,198 USDC"), never as its raw calls
  - **Swap** (Face ID)
- After swapping, a pending row on Home ("Swapping ETH for USDC"), which settles into one row with both sides.
- Swaps pay their fee **out of the token you sell**, so once a token has been sold before, swapping it needs no ETH. The first swap of each token needs a little ETH, once, to approve it (and to create the Safe, if it isn't on chain yet). Unverified: whether a USDC permit can skip that approval for a Safe; measure before promising "no ETH needed".

**6. Recovery, on a new phone**
- New device, iCloud key present, no daily key → Accounts menu row **Recover "My account"**
  - Tray: what will happen and the 3 days
  - **Start recovery** (Face ID) → Home › Needs you: "Recovery finishes Oct 15"
  - After 3 days: **Finish recovery** → this device becomes the owner

**7. Stopping a recovery you didn't start**
- Every device: Home › Needs you, in attention ink: "Someone started recovering My account · 2 days left"
  - **Cancel recovery** (Face ID)
  - Notification that stands alone, at once and again each day of the wait. A local notification can only be scheduled by a device that has already seen the recovery, so the background check is what matters (§7, Push)

**8. The account sheet's Recovery section**
- Rows:
  - **Recovery key**: "In iCloud Keychain · on 3 devices"
  - **Waiting period**: "3 days"
  - **Show recovery phrase** (Face ID → the 12 words, blurred until held, **Copy** off by default)
- One footnote: the phrase restores the recovery key, not the daily key; anyone holding it can start a recovery

### v1.1 — next

**9. Your devices** (each device's Enclave key is its own owner; your Mac counts)
- The account sheet's Devices section: one row per device, "This iPhone", "MacBook Pro"
- **Add a device**: the new device posts its key over iCloud key-value storage (`KeyValueMirror`, no server); an existing device shows "MacBook Pro wants to join" → **Approve** (Face ID)
- Swipe or long-press a device → **Remove** (Face ID, refused for the last device)

**10. Spending limit** (Safe's allowance module)
- The account sheet › **Spending limit**: "Up to $500 a day without Face ID"
- Possibly never: a limit that skips Face ID weakens the design

### Later — each its own ruling

- **Bridge**: move a token between chains (LI.FI or Across), a second kind of swap
- **Connect to apps**: Casberi as a wallet for websites (WalletConnect as the wallet side); this amends §112's "signatures happen elsewhere"
- **Pay fees in USDC**: Circle's paymaster
- **More guardians**: a friend's address as a second guardian, two of two to start a recovery

## 4. Every button, in one table

| Button | Where | Face ID | Goes on chain |
|---|---|---|---|
| New account | Accounts menu, first row | — | No |
| Account button | Band's trailing seat, on the Wallet | — | No |
| Create | New account tray | Yes | No |
| Receive | Actions screen | — | No |
| Copy · Share | Receive tray | — | No |
| Add money | Actions screen | — | No |
| Send | Actions screen | — | No |
| Paste · Scan · Max | Send tray | — | No |
| Swap | Actions screen | — | No |
| Max · token pickers | Swap tray | — | No |
| Swap (confirm) | Review | Yes | Yes (an off-chain order, settled by CoW) |
| Send (confirm) | Review | Yes | Yes (creates the Safe the first time) |
| Recover "My account" | Accounts menu, new device | — | No |
| Start recovery | Recovery tray | Yes | Yes |
| Finish recovery | Needs you | Yes | Yes |
| Cancel recovery | Needs you, every device | Yes | Yes |
| Show recovery phrase | Account sheet › Recovery | Yes | No |
| Add a device · Approve | Account sheet › Devices (v1.1) | Yes | Yes |
| Remove device | Account sheet › Devices (v1.1) | Yes | Yes |

## 5. States to design

- **Empty**: just created, $0. The Actions screen leads with Receive and Add money; the box reads "$0.00", never a fake chart (§769).
- **Not yet on chain**: has money, never sent. Nothing to say; the first send creates it.
- **No ETH for fees**: as in Send step 4. Swap still works for any token sold before.
- **Swap waiting**: Home row until the order fills; an order that expires says so and costs nothing.
- **Pending send**: Home row, then the receipt.
- **Recovery in progress**: Needs you on every device, attention ink, a countdown in days.
- **This device is not an owner**: iCloud key present, no daily key. The Safe reads as a watched wallet plus the Recover row.
- **Face ID re-enrolled**: the Enclave key is destroyed (§427). The account says so and offers Add a device or Recover.

## 6. Rulings

Decided (user, 2026-10-12):
- **Name:** "Your account", "Secured by Safe" once on its page.
- **Chains:** Base and Ethereum. Ethereum fees are dollars, not cents; Review shows the fee before Face ID, and Send defaults to Base when a token is on both.
- **Waiting period:** 3 days, fixed.
- **Swap fee:** none at launch; only CoW's own.

Still open:
1. **Card and Apple Pay top-up.** Skip in v1, or accept one vendor's server.
2. **Pro-only, or free.** The business model puts the writing wallet in Pro ($20).
3. **§112.** Spending from the app amends "signatures happen elsewhere"; record it as a ruling.
4. **The account button's glyph.** Proposed `wallet.bifold`, no word, because the sheet holds more than money moves. Decided: the door is this button, not a fifth tile (user, 2026-10-12).

## 7. Technical notes (for the build, not the design)

- **Contracts:** Safe 1.4.1 L2, `Safe4337Module`, `SafeWebAuthnSharedSigner` for the first passkey (4337 deployment rules), a recovery module with a delay (Candide's `SocialRecoveryModule` or Zodiac Delay, both audited; pick at build).
- **Address:** CREATE2 from `SafeProxyFactory` with a fixed set-up and salt, so it is identical on every chain.
- **Swap:** CoW Protocol (`api.cow.fi`, keyless). An order is signed, not sent: the Safe signs it through `isValidSignature` (EIP-1271), and CoW's solvers settle it and take the fee from the sell token. Needs the Safe on chain and a one-time approval of each sell token to CoW's vault relayer, batched with the first swap. `api.cow.fi` goes in `NetworkReach` (§205).
- **P-256 verification:** the RIP-7212 precompile on L2s, EIP-7951 on Ethereum mainnet.
- **Reads:** straight from the chain over the RPC the Wallet already uses; Safe's Transaction Service is not needed for a one-owner Safe (and its keyless quota is gone, §789).
- **Push:** there is none, so a recovery is noticed at app open and background refresh. **3 days is tight for that:** iOS runs background refresh at its own discretion and rarely for an app left unopened, so someone away from the app for three days could miss a recovery started with a stolen iCloud account. Measure how often the existing background task actually runs on a device before shipping; if it is unreliable, the fallbacks are a longer wait or a second guardian.
- **Already built:** `SafeEnclaveKey`, `SafeEnclaveSigner`, `SafeWebAuthnSignature`, `SafeTransaction` (the SafeTx hash), `ClearSign`, the sign block and its simulation, `P256K`, `KeyValueMirror`.
- **To recover from git:** EIP-1559 signing from `FramesTransaction` at `8fc6db30^` (§1206), for the recovery key's own transactions.
