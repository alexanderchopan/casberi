# Signing safety: the build spec (prd §1509)

**For a Mac session.** Build what prd §1509 ruled, from the canvas
`design/mockups/signing-details-and-warnings.html` (published:
https://claude.ai/artifact/BE7QHqYKtPC9C6cTv8thbJ). Written 2026-10-25 in a
cloud session that could read the code but not build it, so every file and
symbol below was read, and none of it was compiled against these changes.
Where this spec and the code disagree, the code wins: say so, then follow it.

Read first: `CLAUDE.md`, prd §1509 and §1508, `docs/law.md` §11 (Signing and
Safe), `docs/safe-wallet-spec.md`, the canvas.

## Ground rules (from the user and the repo)

- **Simple first.** The sentence stays the screen. Nothing technical shows
  until Details is opened, or until something is wrong (user, 2026-10-25:
  "showing nonce and all that stuff should be in a details toggle"; "we want to
  stay simple for the user").
- **UI is shown as a canvas before it is built.** The canvas above is ruled.
  Anything this spec leaves undrawn (the Raw page on the Mac, an empty state)
  gets a canvas and the user's word before it is built.
- **One goal at a time, with a checkpoint.** Each phase below ends with a
  build, `scripts/verify.sh` green, simulator screenshots with the demo
  (`-demoEnter YES`) and a real account where it can be had, `/code-review`
  on the diff, a prd entry marked BUILT with how it was seen, then the user.
- Build through `scripts/xcb.sh`. Commit straight to `main`.
- **§83:** no fake status. "Checked" only when this exact operation was
  simulated; a fee is an estimate and says "≈" or "about" where it can move;
  a warning names its evidence (the date you paid the real address, the
  list's date).
- **Ink:** amber is `DS.attentionInk`, red `DS.destructiveInk`, green
  `DS.confirmInk` (`status-ink-audit.py`). No plates, no hairlines, one
  explaining sentence per screen (`footnote-audit.py`).
- **Privacy:** every request naming a wallet or the contract you are about to
  touch goes through Tor (§1495); lists are downloaded whole and matched on
  the phone; Relay stays direct (`refusesTor`). New hosts go in
  `Model/NetworkReach.swift` (`network-reach-audit.sh`).
- **The demo** (`YourAccountDemo`, §1475) gets data for every new state, so
  each one can be seen without money.
- **The Mac half** of every change is stated in its prd entry (§1402).
- New DEBUG hooks get one index line in `CLAUDE.md` (keep it under 100KB).
- Every new pure function gets a `--self-test`-backed harness in `scripts/`
  (the pass discovers `*-selftest.sh`); see `scripts/your-account-selftest.sh`.

## Phase 1: Details (Move)

Today: `Screens/MoveSentence.swift` draws the grey line in the `print` switch
(`case .send: [soldPrint] …`, `case .swap: [soldPrint, quotePrint, feeTotal]`).
A send shows no fee. `faceIDWords(_:)` is the Face ID reason. The swap fee is
Relay's only (`YourAccountSwap.Quote.fee`).

1. **The fee on a send.** Estimate the operation before the tap, the way
   `send(_:dryRun:)` already walks to the bundler's estimate
   (`YourAccountChain.transact`, `eth_estimateUserOperationGas`). Fee =
   (verification + call + preVerification gas) × the network's max fee per
   gas, in its coin and in dollars at the Wallet's price. Debounce it with the
   sentence (it changes with amount, token and recipient). The first operation
   on a network also creates the account and sets up keys (`setupCalls`), so
   it costs more: the estimate must be of that operation, not a plain send.
   Grey line: `$25.00 · Fee $0.01 · Details`. Under a cent: "Fee under a cent"
   (the swap's existing words).
2. **The swap fee split.** Total in the grey line (network + Relay). In
   Details: one Fee row, total over "Network $0.01 · Relay $0.04 (0.04%)" and
   "Casberi none". Relay's percentage is its fee over the sold amount.
3. **Simulate sends.** `YourAccountChain.simulate` runs the account's calls
   through `eth_simulateV1` for swaps only. Run it for every batch before
   Face ID. If a call reverts: the grey line becomes the red reason, the verb
   dims (canvas figure 9). If simulation is unavailable on a node, say
   "Not checked" in Details, never "Lands as written".
4. **Details, inline.** "Details" is the last word of the grey line, in
   primary ink with a chevron; a tap opens rows under the sentence (where a
   word's choices open, §1438) and a second tap closes. Rows, in order:
   - To: the full checksummed address, monospaced, wrapped (send only;
     the sentence shows the name).
   - From: "Your account …3416".
   - Network fee: dollars over the coin amount.
   - Nonce: `YourAccountChain.nonce(_:_:key:)`. Note the nonce KEY: with a
     spend limit the operation may use Smart Sessions' key (see the comment
     near `YourAccountChain` line ~709); show the sequence the operation uses.
   - Checked: what simulation found, green "Lands as written" / for a swap
     "Returns at least …".
   - Swap only: You get at least; Fee (split, above); Approves: "Exactly 100
     USDC" over "to Relay, used in the same step".
   - A door: Raw transaction.
   Copy uses `DSCopyRow`. Rows reuse the Wallet row pitch (`walletListRow()`,
   §1482) and `body17`. Details stays open across edits of the sentence and
   closes when the verb changes.
5. **Raw transaction, a page deeper.** Pushed like Your account's pages.
   - "What it does": each call in words, numbered. Every send carries the key
     change (`YourAccountOp`, the shared signer re-configured to the next
     Enclave key): "Moves your account to a new key" over "This iPhone's key 5.
     The old key stops working." With a co-signer or limit, name those calls.
   - Operation hash: the hash Face ID signs (`YourAccountOp.safeOpHash`), with
     Copy. **Read ERC-8213 first** (the Walletbeat checklist cites it for the
     calldata and EIP-712 digests). If it defines a digest or display format,
     use it and name it; if it does not apply to a 4337 SafeOp, say so in the
     prd entry and show the SafeOp hash.
   - Calldata: byte count, the hex in a box (clipped, scrolls), Copy.
6. **Demo:** the demo account's estimate and nonce come off its table
   (`YourAccountDemo`), never a node.

Hooks: `-moveDetails YES` (open Details at mount), `-moveRawProbe YES` (log
the decoded calls, hash and byte count). Self-test: the fee arithmetic and the
call words.

## Phase 2: Warnings (Move)

Today: `MoveSentence.resolve()` checks EIP-55 and `AddressBook.lookalikes`,
sets `Recipient.imitates`, shakes, and `lineNote` returns "Looks like \(name)'s
— check it". The verb is withheld while `imitates != nil` (the `guard r.imitates
== nil, stands(r)` near line ~267). `YourAccountTokens` marks a token "Not
verified by Relay".

1. **Second tap, not a block** (§1509 item 2, amends §1438b). On any amber or
   red warning the verb reads "Send anyway" / "Swap anyway" in the warning's
   ink; the first tap does nothing but arm it (a haptic), the second signs.
   Remove the `imitates == nil` gate.
2. **First send to an address:** amber "First send to this address." Verb
   unchanged. "Known" = any address this account has sent to, any address in
   the book, any of your own accounts. Use
   `WalletSafety.knownGoodCounterparties(context:owners:)`, which already
   builds the set of addresses each wallet has SENT to (the poisoning tagger's
   trust anchor), plus the book. Received-from does NOT make an address known:
   that is what a poisoner controls (WalletSafety's own rule).
3. **Lookalike of history:** compare the typed address against that known set
   with `AddressSafety`'s display-form rule (same leading/trailing hex,
   different address). Amber: "Looks like 0x71C7…49A2, which you paid on
   Oct 3. They differ in the middle. Check it." (the date of the newest send
   to the real one). The To word turns amber and shakes once, as today.
4. **Reported scam address:** red "Reported as a scam address." Source: a
   list downloaded whole once a day on the foreground sweep, bundled as a
   starting copy, matched on the phone. Candidate: ScamSniffer's
   `scam-database` (`blacklist/address.json`). **Measure before building:**
   its license, how far the public copy lags, its size, and whether
   raw.githubusercontent.com answers through Tor (fetch through Tor if it
   does; the request names no wallet, so direct is allowed if it refuses).
   Keep the last good copy; reject an empty, malformed or sharply smaller
   fetch. Details shows the list and its date. The same list feeds a swap's
   For token.
5. **New or unused contract** (a swap's For token, or a send to a contract):
   amber, folded into the existing line: "Not verified by Relay. Its contract
   is 2 days old, and you've never used it." "Never used" is from your
   history; the age from the contract's creation: Blockscout's
   `/api/v2/addresses/{address}` (`creation_transaction_hash`, then the
   transaction's timestamp) on base.blockscout.com, eth.blockscout.com,
   robinhoodchain.blockscout.com. Through Tor. **Measure first** that each
   answers through Tor and what it returns for a contract and an EOA.
   Threshold for "new": under 30 days (put the number in the prd entry).
6. **Would fail:** from Phase 1's simulation (red line, verb dimmed). If the
   result depends on state that moves (the swap's minimum aside), the line
   says so in amber and the verb stays.
7. **Order when several apply:** red over amber; one line only; Details lists
   every finding.

Hooks: `-moveWarnProbe first|lookalike|scam|newContract|fails` (fill a sentence
that triggers it, log `moveWarn|`). Self-tests: the lookalike match against
history, the known set's one-way rule, the list guard (empty, malformed,
shrunk), the warning order.

## Phase 3: The co-signer (someone else's Safe)

1. **Verify at pairing.** `Model/SafePeer.swift` subscribes
   `Sign.instance.sessionProposalPublisher` and drops the second element
   (`.sink { proposal, _ in … }`). In reown-swift 2.3.0 that element is
   `VerifyContext?` (`origin`, `validation: unknown | valid | invalid | scam`).
   Pass it to `handle(proposal:)` and draw (canvas figure 10):
   - valid: nothing new;
   - unknown or invalid: amber "Couldn't confirm it's <claimed host>";
   - scam: red "Reported as a scam site. It isn't <claimed host>.", rows
     "Says it is" / "Really is", the slab "Don't pair", "Pair anyway" above.
   A nil context reads as unknown. **Measure:** whether Verify needs
   configuration on our side (the client is configured in
   `WalletConnectBridge`), and whether it works on Mac Catalyst; if not on
   the Mac, the Mac says unknown.
2. **Unlimited approval in words.** `ClearSign` renders the descriptor's
   "Unlimited" label. In the sign block (`Screens/SafeQueueCard.swift`,
   `SafeSignBlock`), an `approve`/`increaseAllowance`/Permit2 call for the max
   value, or `setApprovalForAll(…, true)`, adds a red line: "Lets 0xdef1…c0de
   spend all of this Safe's USDC, with no end." (name the spender as the book
   or ClearSign names it).
3. **Details on the sign block.** The grey line under the call words ends in
   Details: Nonce, Safe tx hash, Domain hash, Message hash (each copyable,
   from `SafeTypedData`/`SafeTransaction`), and the Raw transaction door
   (Phase 1's page, fed the Safe's calls). The canvas shows them; ERC-8213's
   reading applies here too.

Hooks: reuse `-signerProbe`; add `-pairVerifyProbe valid|unknown|scam` to draw
each pairing state without a live site.

## Phase 4: The monthly recovery check

Today: `Model/YourAccountRecovery.swift` (an iCloud Keychain P-256 key, the
account's second owner through its own Safe passkey signer, device-owner
auth before it signs), `Model/YourAccountProtection.swift` and
`RecoveryKeyNudge` in `Screens/MoveSecurity.swift` (asks only about networks
holding money without the key).

1. **Due:** 30 days after the last check (or after the key was made). One row
   in the Wallet's Needs you: "Check your recovery key". No notification, no
   badge (§1490).
2. **The check** (canvas figure 13), no fee, nothing sent: device-owner auth;
   the Keychain item is present and readable; sign a random challenge with it
   and verify locally against its public half; on each network, the Safe's
   owners include the recovery key's signer proxy (read through Tor, as the
   account's other reads). Do NOT verify on chain with `isValidSignature`:
   with the spend limit the threshold is two keys (§1456), so one key alone
   would read as a failure.
3. **The page:** "Your recovery key works on Base and Ethereum." (green
   "works"), "In iCloud Keychain. Checked today with Face ID.", one row per
   network (An owner / Not on yet / Not an owner), and the existing fix door
   for a network without it. Any failure turns the sentence red and names
   it. Done.
4. Store the date of the last good check (UserDefaults through
   `DefaultsWrite`, `defaults-lock-audit.py`).

Hook: `-recoveryCheck due|run|fail`. Self-test: the due rule and the verdict
per network.

## Phase 5: Your own node

Today: `YourAccountOp.Network` pins `rpcs` and `bundlers` per network; reads
go through `IngestSupport`'s transport and Tor (§1495).

1. **Nodes,** a page under Your account › Keys (canvas figure 14): a switch
   "Your own node"; per network an address field or "Casberi's list".
2. A typed address is checked before use: `eth_chainId` must equal the
   network's id, and `eth_blockNumber` must answer. Show "Chain 8453 · block
   31,882,104" in green, or the refusal.
3. Reads use your node first, then nothing else for that network (falling
   back to the list would send your address where you said not to). Bundlers
   stay the list (a node is not a bundler); say so on the page only if the
   user asks for a line.
4. Your node is reached directly, not through Tor (a home node is on your
   network). The page's one sentence: "Your node sees your address. Tor
   doesn't hide it from your own node."
5. Record the host with `NetworkLedger.record(host:as:)` under a declared
   family in `NetworkReach`.

Hook: `-ownNode "<chainId>|<url>"|clear`.

## Phase 6 (separate, measure first): Tor on the Mac

§1495 left the Mac without Tor ("the Mac has no Tor yet and says so").
Find why in `Model/TorClient.swift` / `TorRoute.swift` and the §1495 entry,
measure whether the same client runs under Catalyst, and bring a finding to
the user before building.

## Not in scope

A bug bounty and an audit (cost), hardware wallets (their own project),
LI.FI (prd §1509 item 6), Reown's commercial-license threshold (§1508 item 4).
