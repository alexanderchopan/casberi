# Your account (a Safe) — design spec (2026-10-12, revised 2026-10-19)

**Status: the user's spec; nothing is built yet.** Apple approved the switch to
an organization account on 2026-10-19 (3.1.5(i); the paperwork is still
finalising), so building can start. Section 6 lists what is decided and what
is still open.

## 0. Principles and goals

### Design principles

1. **Yours, with no server of ours.** Casberi never holds a key, runs no backend for the account, and never stands between you and your money. Third parties we use (a bundler, an RPC, CoW) are interchangeable and hold nothing.
2. **Keys never leave the device.** The key that signs lives in the Secure Enclave and can't be exported. The one exception is the recovery key, and it is a standard phrase you can take elsewhere.
3. **One address, keys that change underneath.** Your address is permanent; the keys behind it rotate freely.
4. **A spending account, not a vault.** Fast over fortified: no recovery delay, one signature. Savings, with delays and two keys, is a separate account later.
5. **Real money runs only on what is live and proven.** Safe on Base and Ethereum today. New technology (Bermuda, 8130, Tempo, Aztec) is layered on once it is on mainnet and measured on an iPhone, never load-bearing before.
6. **Honest privacy.** Every privacy feature says exactly what it hides and what it doesn't ("sweeping links this address to your account").
7. **Read before you sign.** Every transaction is shown in plain words, with balances before and after (clear signing and simulation).
8. **Always a way out.** The 12-word phrase opens the account in Safe's own app without Casberi.
9. **No contract of our own, ever** (prd §1380, user, 2026-10-17: "i do not and will not create our own contracts", "we can't afford audits"). Every contract the account touches is someone else's, already deployed and audited: Safe's, CoW's, the 4337 module's. A feature that would need a contract we wrote is not built.
10. **Nothing permanent behind the address.** Every key that can move money rotates — the device key with every transaction, the recovery key on "New phrase" — so no leaked secret works for long. This is what rules Aztec out for now (§1380): its accounts keep a fixed key and a fixed privacy secret.

### Goals

Each goal: how every option does it **today**, the problem with that, and our answer. Options: an ordinary wallet (EOA, e.g. MetaMask), Safe as it ships, Tempo (Stripe's chain), Base's EIP-8130 Keystore, Aztec, Bermuda, and the live privacy pools (Privacy Pools, Railgun). Details measured or read 2026-10-11 to 10-13; sources at the end. Railgun's and Privacy Pools' figures are from memory and should be re-checked before any decision rests on them.

#### 1. Rotate keys

| Option | How it works today |
|---|---|
| Ordinary wallet | One key for life. EIP-7702 adds smart-account code, but the original key still works forever |
| Safe | Swap an owner at any time (`swapOwner`); one transaction |
| Tempo | Access keys are authorized and revoked freely; the **root key can never change** |
| Base 8130 | Authorize and revoke "actors" natively, but the Keystore is gated to Zenith, a test-chain-only upgrade, not Base mainnet |
| Aztec | The standard account's key (EcdsaRAccount) is **immutable**; rotating needs a custom account contract |
| Bermuda | Each owner registers its own Bermuda key; rotation not documented |

**Problem:** where rotation exists, nobody does it routinely, and a key that leaked works until someone notices.
**Our answer (v1):** a **new Secure Enclave key for every transaction**, batched atomically with the transaction itself; the old key never works again (section 3b). The recovery key rotates too ("New phrase"). Safe does both with its own audited `swapOwner`, so principle 9 holds; Aztec's stock accounts can do neither, and a contract of ours is ruled out, so Aztec waits (§1380; the phone itself is proven: `tools/aztec-phone-spike`, 2.1 s a proof).

#### 2. Rotate keys, keep the same address

| Option | How it works today |
|---|---|
| Ordinary wallet | New key = new address: move every token, tell everyone who pays you |
| Safe | **The address never changes**; owners change behind it |
| Tempo | Address comes from the root key: access keys change, the root and the address can't |
| Base 8130 | Address fixed, actors change (not on mainnet) |
| Aztec | The address commits to its protocol keys; only a custom account can change its signing key |
| Bermuda | The shielded address is built from its keys: new keys, new address |

**Problem:** without a fixed address, rotating keys means re-telling everyone where to pay you.
**Our answer (v1):** Safe; with the shared passkey signer the rotation is a storage write, not even an owner swap (section 3b).

#### 3. Sign with the iPhone's Secure Enclave (passkeys)

| Option | How it works today |
|---|---|
| Ordinary wallet | secp256k1 only; the Enclave speaks P-256, so it can't |
| Safe | Through Safe's passkey signer contract; **already built in Casberi** (`SafeEnclaveKey`, §913) |
| Tempo | Native: P-256 and WebAuthn are built-in signature types, even for the root |
| Base 8130 | Native in the Keystore; not on mainnet |
| Aztec | Native P-256 account; **measured with our Enclave key on testnet** (§1276) |
| Bermuda | Works: the passkey is untouched, and each owner registers a separate Bermuda key |

**Problem:** seed-phrase wallets keep the signing key in app memory, where it can be copied.
**Our answer (v1):** the Enclave key signs everything and can't be exported.

#### 4. Recover a lost phone

| Option | How it works today |
|---|---|
| Ordinary wallet | Type the seed phrase into a new phone, if you still have it |
| Safe | Any remaining owner swaps a new key in; optional recovery modules add a delay |
| Tempo | No protocol recovery: keep the root key safe; an admin key can revoke the lost device's access key |
| Base 8130 | Admin actors can re-authorize (not on mainnet) |
| Aztec | Depends on the account contract; the standard one can't recover |
| Bermuda | Its key can derive from any seed (supported, not in their UI yet) |

**Problem:** the phrase is either lost or stored somewhere unsafe, and recovery is slow when you need money now.
**Our answer (v1):** the 12-word recovery key in iCloud Keychain is a **second owner with no delay**: Recover, Face ID, done. Hot-wallet tradeoff: whoever gets into your iCloud can spend (section 1).

#### 5. Gas

| Option | How it works today |
|---|---|
| Ordinary wallet | Hold ETH on every chain |
| Safe | An owner pays in ETH, or an ERC-4337 bundler with a paymaster |
| Tempo | **Fees in dollar stablecoins** natively, with no gas token; sponsorship is one field |
| Base 8130 | A payer field natively (secp256k1 only on mainnet today) |
| Aztec | Fee Juice, bridged from Ethereum; a sponsor contract on testnet |
| Bermuda | A gas tank funded from the shielded balance; shielding on arrival is gasless |

**Problem:** stuck tokens and failed sends when you hold no ETH.
**Our answer (v1):** gas from the account's own balance through Safe's 4337 module; swaps take their fee from the token sold (CoW).

#### 6. Private receiving

| Option | How it works today |
|---|---|
| Ordinary wallet / Safe / Tempo | One public address: every payer sees every payment and your balance |
| Stealth addresses (ERC-5564, Fluidkey, Umbra) | A fresh address per payment; amounts and senders still visible |
| Privacy Pools / Railgun | The deposit is visible; inside the pool is private |
| Aztec | Private by default inside the network; bridging in is visible |
| Bermuda | A fresh address that **shields on arrival** in one gasless transaction (mainnet Q4) |

**Problem:** one public address is a public bank statement.
**Our answer (v1):** fresh addresses derived from your phrase, one per payer; **sweep** into the account when you spend, and the app says that sweeping links that address (section 3a). v2: Bermuda's shield on arrival.

#### 7. Private balance and spending

| Option | How it works today |
|---|---|
| Ordinary wallet / Safe / Tempo | Fully public |
| Privacy Pools (0xBow) | Unlinks deposit from withdrawal; **slow** (deposits wait for review, often hours); Ethereum |
| Railgun | Private balances, transfers and **swaps**; 0.25% in and out; about an hour's wait after depositing; no Base; Railway proves on an iPhone |
| Aztec | Everything private, but its own network: few apps, mainnet "Alpha" (zk.money caps moves at $2,500), a version behind testnet |
| Bermuda | A shielded pool on Base and Ethereum with one-time accounts for normal DeFi; mainnet Q4; iPhone proving unmeasured |

**Problem:** today's options are too slow, too costly, or too far from where your money and apps are.
**Our answer (v2):** Bermuda once on mainnet and measured on an iPhone; Railgun is the live comparison for that measurement (section 3a).

#### 8. Multi-sign

| Option | How it works today |
|---|---|
| Ordinary wallet | One key, no co-signing |
| Safe | N-of-M natively; collecting signatures usually runs through Safe's transaction service, a server whose free quota is used up (§789) |
| Tempo | Several keys, any one signs; no threshold documented |
| Base 8130 | Not documented |
| Aztec | Possible in a custom account contract |
| Bermuda | **Private multisig** through FROST threshold signing |

**Problem:** co-signing means someone else's server, or no co-signing at all.
**Our answer:** **your devices (v1.1)**: each device's Enclave key is an owner and any one signs; added by approving on a device you already have, over iCloud. **Other people (later):** a separate 2-of-N account, signatures passed through a share link and executed by whoever completes it; Casberi already co-signs Safes (§425, §1249).

#### 9. Savings

Every option today puts one hot key over everything, unless you set up a separate vault yourself. **Our answer (later):** a separate savings account with a recovery delay or two keys required, beside the spending account.

#### 10. Know what you sign

Most wallets show hex and a Confirm button; Safe's app decodes some calls. **Our answer (v1):** the sign block: plain words (ERC-7730 clear signing), simulation, balances before and after (§834, §1249).

## 1. What it is

A self-custody wallet, created in the app, that is a **Safe from its first
launch**. Casberi runs no server and pays no gas.

- **Daily key:** a Secure Enclave key on each of your devices, unlocked with
  Face ID or Touch ID, never exportable (`SafeEnclaveKey`).
- **Recovery key:** a 12-word key synced through iCloud Keychain. It is a
  **second owner, with no delay** (user, 2026-10-12: "lets do no delay. this is
  a hot wallet"): one signature from either key moves money, so a new phone
  recovers at once. It never signs day to day; the app uses it only to replace
  a device key. Whoever holds your iCloud Keychain or the phrase can spend:
  this is a spending account, not savings.
- **The phrase is standard** (BIP-39, 12 words, the owner key on
  `m/44'/60'/0'/0/0`), so it is also **the way out**: imported into MetaMask
  or any wallet, that key owns your Safe in Safe's own app (app.safe.global),
  without Casberi.
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

## 2a. The account sheet: a page of live modules

**The sheet the Wallet button raises IS the account** (user, 2026-10-13). It is not a menu of tiles that open trays: it is a stack of **modules you act in directly**, so sending is typing into Move, not tapping Send first ("if the tray or sheet has a send and swap module already there … that is easier. same for signing, rotating keys"). The same idea as the tray's page of modules (§1207 item 5).

- **No balance** (user: "we already have that on the wallet"): the Wallet behind the sheet shows it.
- **The account is one line, not a module** (user, 2026-10-13: "it needs to be one line"): a disc, the name, a pink ⌄ and the short address, **+ New** on the right. Tapped, it opens in place: the accounts (pick one, a check on the current), then **Addresses** with **+ New address**: your address and every fresh address with what it holds. Fresh addresses live here, under the account, not under Receive (user: "those would be under my account … a selection there").

**Every module stays expanded; none collapses** (user, 2026-10-13: "if we can do all these not collapsed that would be amazing"). To keep the sheet manageable, only **Send · Swap** is a full card; the other two are short rows, each a summary that opens its list, never a verb per item (user: "someone may have 20 tokens to revoke. it could be one line summary"). The sheet is the account line and about 1.2 screens below it. **Level 1 first:** the lists the rows open are designed after these three.

| Module | User goal | Level 1 |
|---|---|---|
| **Send · Swap** | Pay someone, or change what I hold | The header's two words are the toggle (the picked one white, the other grey, no pill); **+ Add** puts this move in one transaction with the next. A card: an amount and token, then **to** (Send) or **for ≈** (Swap), and the result in pink as the button ("Send 100 USDC to Ana", "Swap to 0.0408 ETH", "Sign 3 in one transaction"); the batch listed under it, "In this transaction" |
| **Add · Receive** | Put money in, or get paid | Two rows. **Add** — "From an exchange, a card or a bank" (where it comes from is unruled: no from row until we know the vendor, user: "we don't yet know what we will use"); its button reads "Add 250 USDC", never "Deposit". **Receive** — the address picked on the account line, "· Base · Ethereum", and a pink **Copy** on the row (user, 2026-10-13), as Signers carries **Add**; the QR and Share are one level down |
| **Security** | Control what I allow and keep my keys | One header, "1 waiting" in amber when something is. Rows: **Sign** (what waits, the newest named, the count in amber), **Revoke** (apps that can spend your tokens, the count), **Signers** (who can sign and how many must, **Add**), **Rotate** (a new key every transaction, the key number, devices), **Recover** (the recovery key, guardians, "add a guardian" when none) |

**Signers are not guardians** (user, 2026-10-13: "guardians is just recover, but not same as multi sig"). A signer is a Safe owner and counts toward the signatures a transaction needs; with one needed, any signer spends alone. A guardian can only start a key change, which waits out a delay you can cancel from your phone (a Safe recovery module, e.g. Candide's); a guardian never signs a payment. The recovery key is a SIGNER (section 6: a second owner, no delay), so holding the 12 words is holding the money. Adding a signer asks how many must sign: two makes it a joint account ("Joint with Sam"), and a joint account is a different hot/cold trade from this one.

No balance and **no Activity module** (user: "we have that in the wallet already"). **Needs you stays on the Wallet** as the one list of what waits across every app; your account's items appear there and open this sheet at Security.

**Direction set** (user, 2026-10-13: "directionally this is what we want"): the dark design canvas, https://claude.ai/artifact/8gcCuMvJHWVk4eq4Zob5Qv (private to the owner). No backings on buttons or row glyphs; the coloured circles are avatars.

**Redrawn bare after the 2026-10-17/18 redesign** (§1382, §1393, §1396, §1385, §1386): https://claude.ai/artifact/2HbVMQfk1MP4bLuU6teKTX. Row one: no panels or boxes, 32pt seams, 60pt rows, pink for state and verb, grey chevrons for doors (user, 2026-10-18: "i like what you did"). Row two, "the Apple pass", for the user to rule on: the centred head (§1397: face, name as the title's menu, address), no glyph on the blocks (§1396), verbs as words with no "+", a row's trailing value a count. Not yet picked.

**Open:**
1. ~~Module order~~ **Decided: fixed** (user, 2026-10-13): Send · Swap, Add · Receive, Security. Something waiting shows inside its module, never by moving it.
2. Typing: the card you type in expands to fill the sheet while the keyboard is up, then settles back (proposed).
3. §1178 caps a sheet at four tiles; modules are a different shape, so this sheet is a new pattern to record as a ruling.
4. Guardians' delay length, and whether adding a second required signer is offered here or only as a new joint account.

## 3. Features and their buttons

### v1 — the first release

**The Actions screen** (the tiles below are superseded by section 2a's modules, 2026-10-13; the door stands). Send, Swap, Receive and Add money live together on one sheet of their own, not as rows in Holdings (user, 2026-10-12).
- **Its door: the Wallet button**, the band's trailing seat on every page (face · Search · Wallet, §1278, §1280, shipped in 3.0.4). Today it opens the Wallet on Home. Once you have an account of your own it opens the Wallet **with the account sheet on top**, so it always lands in the Wallet. After a key change you didn't make it carries the attention dot.
- **The sheet:** the Holdings sheet's anatomy. Your account's box, then **four tiles: Send · Swap · Receive · Add money** (a sheet's acts are tiles, four at most, §1178), then sections: **Recovery** (recovery key, Show recovery phrase, New recovery phrase), **Devices** (each owner, Add a device), **Account** (address, name, notifications, activity) and one footnote on who holds the keys.
- Mockup: `design/mockups/wallet-account-button.html`. Frames 1 and 7 predate §1278 (the button there is Wallet-only) and frames 6 and 7 draw the 3-day recovery the no-delay ruling removed; the sheet, Send, Review and Swap frames stand.
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
  - **New address**: a fresh, unlinked address for one payer (section 3a), with an optional "For" name
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
  - Tray: one sentence on what happens
  - **Recover** (Face ID) → the recovery key swaps this device's new Enclave key in, in one transaction; the account is usable at once

**7. A key change you didn't make**
- Every device: Home › Needs you, in attention ink: "This account's key was changed from another device"
  - It cannot be undone (no delay, by ruling). While this device is still an owner the row offers **Move your money** to an account you control; once it has been removed, the row says so and points to changing your Apple Account password. Honest about the race: whoever moves first wins
  - Notification that stands alone, when the app next sees it

**8. The account sheet's Recovery section**
- Rows:
  - **Recovery key**: "In iCloud Keychain · on 3 devices"
  - **Show recovery phrase** (Face ID → the 12 words, blurred until held, **Copy** off by default)
- One footnote: the phrase restores the recovery key, and anyone holding it can spend from this account

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
- **Pay fees in USDC from your main account too**: the paymaster v1 brings for fresh addresses (section 3a) could pay any transaction's gas
- **A savings account**: a second Safe for larger balances, with a recovery delay or two keys required

## 3a. Fresh addresses (stealth): receiving in v1, private spending in v2

**In v1 (user, 2026-10-12: "yes" to fresh receiving addresses in v1).** Receiving at a fresh address, spending from it, and its gas. **In v2:** spending privately through Bermuda (below), waiting on their mainnet and answers.

**What it is.** A new address for each payer or each request, so payments can't be linked to each other or to your account on chain. Each fresh address is a **stealth Safe**: a Safe that doesn't exist on chain until it first spends, owned by a one-time key derived for that address alone.

**How the keys work (no server).**
- Every fresh address's owner key is derived from the **12-word phrase** on its own path (index 0, 1, 2…), as an HD wallet does. Recovering the phrase recovers every fresh address; the app walks the indexes with a gap limit, as the Bitcoin reader already does (§1097).
- The app makes each address itself (Fluidkey's approach), so it already knows every address it handed out: **nothing to scan**, no viewing key to share.
- Owners are derived secp256k1 keys, **not the Secure Enclave key**: Enclave keys can't be derived, and reusing your one Enclave owner with a different salt would link every address the moment the first one is created on chain.
- **No shared recovery owner on a fresh Safe.** Owners are written into the Safe at creation, so one recovery key on every fresh Safe would link them all. The phrase is the recovery: it re-derives every fresh owner.

**Buttons.**
- Actions › **Receive** → tray gains **New address** beside your main one: an optional "For" name (Ana, rent), then the address, its QR, Copy · Share. Each one is new.
- Your account sheet gains a **Fresh addresses** section: one row per address, "From Ana · $120", newest first, with its own Send.
- The account's box counts them in the total, so they're one balance to you and separate on chain.

**The two hard parts.**
1. **Gas (decided for v1: a paymaster that takes USDC).** A fresh address holds the token it was paid, not ETH, so its first spend pays gas in that token through Circle's paymaster (ERC-4337, the same bundler the account already uses), and creating the Safe rides that same first transaction. It is a third party, keyless as far as known, and its hosts go in `NetworkReach`. Measure it before promising: which tokens and chains it takes (USDC on Base and Ethereum is the case that matters), its fee, and that it pays for a Safe's first deployment. Fallbacks: a CoW swap out of the token (a first sale still needs a one-time approval), or asking payers for a little ETH.
2. **Linking.** Moving several fresh addresses into one place, or paying their gas from your main account, links them on chain. The app never consolidates on its own; Send spends from one address, and a move between your own addresses warns "This links these addresses on chain".

**Spending from fresh addresses: Bermuda, the leading option (2026-10-12, unmeasured).** Bermuda (docs.bermudabay.xyz), working with the Safe team, is a shielded pool on the same chains. Money sits in the pool; for an action it steps out to a one-time account (an EIP-7702 burner, or for a Safe a "JIT-Safe" whose owners are stealth keys derived from the Safe's owners), acts, and can step back in. That answers both hard parts above: gas comes from a gas tank funded out of the pool, and nothing links back to your Safe. Receiving at a fresh address from a normal wallet stays ours for now.

**Bermuda's answers (2026-10-12, from the team):**
1. **Passkey owners: yes.** The passkey is never tweaked; each owner registers a separate Bermuda key that signs private multisig transactions (in their UI soon). So we hold a second secret per device, and it needs a backup story (derive it from the 12-word phrase?).
2. **Mainnet: Q4 2026**, Ethereum, Base and other L2s, after audits.
3. **iOS: no Swift SDK.** The TypeScript SDK runs on iOS with on-device proving, so we'd host it in a hidden web view or JavaScriptCore. Proving time, memory and bundle size on an iPhone are unmeasured.
4. **Servers: the relayer is optional**; any wallet or relayer can submit (ours through the 4337 bundler). The compliance check is required at deposit (their engine) and at withdrawal (no engine needed).
5. **Receiving: a fresh address that shields incoming funds in one gasless transaction**, and Bermuda accounts can make one-time addresses. A service that writes the deposit proof and shields on arrival is possible but not in the SDK yet.

**What it changes.** v1 keeps our stealth Safes for fresh receiving (no dependency, works before Q4). After Bermuda's mainnet, and once iOS proving is measured, fresh addresses can **shield on arrival** and spend privately, which also retires the USDC paymaster for them. **Second round (2026-10-12):** the Bermuda key **can derive from an arbitrary seed** (supported, not yet in their UI), so the 12-word phrase can be the one backup. The SDK runs on iOS but they have **no current guides or numbers**, and it also runs on **Bare** (bare.pears.com, Holepunch's small embeddable JavaScript runtime), suggested for mobile. Unanswered: who pays the gasless shield and its cost, what the deposit compliance call sends, whether the audits will be public.

**Next step, a measurement on their testnet:** run their SDK on an iPhone two ways (a hidden WKWebView, and Bare) and record proof time, memory, app-size cost and battery for a shield, a private transfer and an unshield. That decides whether private spending is buildable at all.

**Privacy, three kinds.**

| Kind | Hides | Example |
|---|---|---|
| Fresh / stealth addresses | Who received; amounts and senders visible | Our stealth Safes, Fluidkey, Umbra |
| Shielded pool on an existing chain | Balances and who paid whom inside it; entry and exit visible | Bermuda, Railgun, Privacy Pools |
| Private chain | Everything inside by default, apps included; bridging visible | Aztec |

Bermuda fits your account (same chains, Safe, normal DeFi through one-time accounts; its relayer and compliance check; testnet). Aztec is a second account on another network (no Safe, only Aztec apps; no company servers; our Enclave key already signs an Aztec testnet account, §1276), a later "private account" rather than a feature of the Safe.

**Also possible, later:** sending to other people's stealth meta-addresses (ERC-5564, Umbra and Fluidkey users), and publishing your own in the ERC-6538 registry. That direction needs scanning announcements with a viewing key, on the phone.

## 3b. Rotating keys

**What it is.** Replacing the key that controls your account **without changing its address**, the one thing a Safe does that an EOA can't: `swapOwner` on chain, one Face ID. Separate from fresh addresses: rotation keeps one address and changes its keys; fresh addresses keep making new addresses.

**When a key rotates.**
- **A new phone, or Face ID re-enrolled:** the old Enclave key is gone (§427), so recovery or another device swaps in the new one. This is rotation already, built into recovery and Devices.
- **On purpose:** you think a device or the phrase was exposed.
- **On a schedule** (open question below): e.g. the device key every year.

**Buttons** (the account sheet).
- Devices › a device's row › **Replace this key** (Face ID): a new Enclave key on this device, `swapOwner` old → new, one transaction.
- Recovery › **New recovery phrase** (Face ID): a new 12-word key replaces the old one as owner (`swapOwner`), the old phrase stops working on chain, and the new words show once. Fresh addresses derived from the old phrase keep their owners (section 3a), so this asks first: keep the old phrase for them, or move each one's funds (which links them).
- History: each rotation is a row on Home, "Replaced this iPhone's key", dated.

**A new key for every transaction (user, 2026-10-12: "everywhere. rotate at will. user should see it").**
- Every send, swap and approval is batched with a key change, atomically: the key that signed never works again, and a failed transaction rotates nothing. The next key is born in the Secure Enclave just before signing.
- **Everywhere**, Base and Ethereum. With Safe's shared passkey signer the change is the stored public key (`SafeWebAuthnSharedSigner.configure`), a couple of storage writes rather than an owner swap; a second device rotates its own signer with `swapOwner`.
- A CoW order is approved on chain (`setPreSignature`) in the same batch, so a rotation can't void an order still waiting to fill.
- **The user sees it**: each transaction's row and receipt say "New key", and the account sheet's Devices section shows this device's key count ("Key 42 · changed with your last send").
- **The recovery phrase does not rotate with it.** The device key and the recovery key are separate: the recovery key is its own owner, untouched when the device key changes, so the phrase keeps working through every rotation. It changes only when you ask (New recovery phrase, "rotate at will").

**No delay anywhere** (user, 2026-10-12): New recovery phrase is Face ID on a device that owns the account, effective at once.

## 4. Every button, in one table

| Button | Where | Face ID | Goes on chain |
|---|---|---|---|
| New account | Accounts menu, first row | — | No |
| Wallet button (raises the account sheet) | Band's trailing seat, every page | — | No |
| Create | New account tray | Yes | No |
| Receive | Actions screen | — | No |
| Copy · Share | Receive tray | — | No |
| Add money | Actions screen | — | No |
| Send | Actions screen | — | No |
| New address | Receive tray | — | No (it exists on chain at its first spend) |
| Send from a fresh address | Account sheet › Fresh addresses | Yes | Yes (creates that Safe; gas in USDC) |
| Paste · Scan · Max | Send tray | — | No |
| Swap | Actions screen | — | No |
| Max · token pickers | Swap tray | — | No |
| Swap (confirm) | Review | Yes | Yes (an off-chain order, settled by CoW) |
| Send (confirm) | Review | Yes | Yes (creates the Safe the first time) |
| Recover "My account" | Accounts menu, new device | — | No |
| Recover | Recovery tray, new device | Yes | Yes |
| Move your money | Needs you, after a key change you didn't make | Yes | Yes |
| Show recovery phrase | Account sheet › Recovery | Yes | No |
| Add a device · Approve | Account sheet › Devices (v1.1) | Yes | Yes |
| Remove device | Account sheet › Devices (v1.1) | Yes | Yes |

## 5. States to design

- **Empty**: just created, $0. The Actions screen leads with Receive and Add money; the box reads "$0.00", never a fake chart (§769).
- **Not yet on chain**: has money, never sent. Nothing to say; the first send creates it.
- **No ETH for fees**: as in Send step 4. Swap still works for any token sold before.
- **Swap waiting**: Home row until the order fills; an order that expires says so and costs nothing.
- **Pending send**: Home row, then the receipt.
- **A key change you didn't make**: Needs you on every device, attention ink, with Move your money.
- **This device is not an owner**: iCloud key present, no daily key. The Safe reads as a watched wallet plus the Recover row.
- **Face ID re-enrolled**: the Enclave key is destroyed (§427). The account says so and offers Add a device or Recover.

## 6. Rulings

Decided (user, 2026-10-12):
- **Name:** "Your account", "Secured by Safe" once on its page.
- **Chains:** Base and Ethereum. Ethereum fees are dollars, not cents; Review shows the fee before Face ID, and Send defaults to Base when a token is on both.
- **Recovery:** no delay; the recovery key is a second owner. A hot wallet, not savings (was 3 days, fixed).
- **Swap fee:** none at launch; only CoW's own.

Decided (user, 2026-10-17):
- **Safe stays the account** ("ya this is what we want this safe model"): owners rotate at will with Safe's own `swapOwner`, nothing permanent behind the address.
- **No contract of our own, ever; Aztec accounts parked** (prd §1380).
- **Signers are not guardians**; the recovery key is a signer (section 2a).

Still open:
0. **The sheet's look**: row one (bare) or row two (the Apple pass) of the 2026-10-18 canvas, and with it whether this sheet's blocks wear a glyph.
1. **Card and Apple Pay top-up.** Skip in v1, or accept one vendor's server.
2. **Pro-only, or free.** The business model puts the writing wallet in Pro ($20).
3. **§112.** Spending from the app amends "signatures happen elsewhere"; record it as a ruling.
4. **The account button's glyph.** Proposed `wallet.bifold`, no word, because the sheet holds more than money moves. Decided: the door is this button, not a fifth tile (user, 2026-10-12).
5. **Guardians' delay** (section 2a, open 4), and whether Add a signer offers "two must sign" or a joint account is only ever made through New account.
6. **Where New account lives now that §1410 gives the Wallet's + two rows** (Follow an account, Connect an app): a third row there, the sheet's account line, or both.
7. **The stack**, before the first screen is built: the bundler, the RPC for P-256 verification, and whether CoW's keyless API is enough (section 7).

## 7. Technical notes (for the build, not the design)

- **Contracts:** Safe 1.4.1 L2, `Safe4337Module`, `SafeWebAuthnSharedSigner` for the first passkey (4337 deployment rules), and the recovery key as a second owner at threshold 1 (no recovery module).
- **Address:** CREATE2 from `SafeProxyFactory` with a fixed set-up and salt, so it is identical on every chain.
- **Swap:** CoW Protocol (`api.cow.fi`, keyless). An order is signed, not sent: the Safe signs it through `isValidSignature` (EIP-1271), and CoW's solvers settle it and take the fee from the sell token. Needs the Safe on chain and a one-time approval of each sell token to CoW's vault relayer, batched with the first swap. `api.cow.fi` goes in `NetworkReach` (§205).
- **P-256 verification:** the RIP-7212 precompile on L2s, EIP-7951 on Ethereum mainnet.
- **Reads:** straight from the chain over the RPC the Wallet already uses; Safe's Transaction Service is not needed for a one-owner Safe (and its keyless quota is gone, §789).
- **Push:** there is none, so a key change is noticed at app open and background refresh. With no delay there is nothing to cancel in time; the alert's job is to say it happened.
- **Already built:** `SafeEnclaveKey`, `SafeEnclaveSigner`, `SafeWebAuthnSignature`, `SafeTransaction` (the SafeTx hash), `ClearSign`, the sign block and its simulation, `P256K`, `KeyValueMirror`.
- **To recover from git:** EIP-1559 signing from `FramesTransaction` at `8fc6db30^` (§1206), for the recovery key's own transactions.

## 8. Sources

- Safe passkeys and modules: Casberi's own `SafeEnclaveKey`, `SafeWebAuthnSignature` (§913), and the co-signer (§425, §1249).
- Tempo accounts: tempo.xyz/developers/docs/accounts/keys, /accounts/create; Tempo Transactions spec (tempo.xyz/developers/docs/protocol/transactions/spec-tempo-transaction).
- Base EIP-8130: github.com/ethereum/EIPs EIP-8130; base/base PR #5293 (closed) and #5366 (merged 2026-09-29: the Keystore gated to Zenith).
- Aztec: measured by Casberi (§1270, §1276, §1277, §1279); zk.money (§1273).
- Bermuda: docs.bermudabay.xyz (introduction, tech/architecture, tech/key-generation, tech/frost-dkg, sdk/quickstart, sdk/defi, sdk/accounts) and the team's two rounds of answers (2026-10-12).

