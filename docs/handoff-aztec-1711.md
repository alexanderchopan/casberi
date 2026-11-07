# Handoff: test prd §1711 (your Aztec account, finished in six places)

For a Mac session. The work is written and on GitHub. This session builds it, tests it on the simulator and the phone, fixes what breaks, and gets it to `main`.

## Where it is

- Branch `claude/kind-mayer-u8rjwm`, PR #442 (draft): https://github.com/alexanderchopan/casberi/pull/442
- The ruling: `docs/prd.md` §1711. Read it first; it says what each item must do and in which words.
- CLAUDE.md says commit straight to `main`. This work sits on a branch because a cloud session wrote it. Check it out, fix on the branch, and merge the PR when it is green (or fast-forward `main`; ask the user which).

```sh
cd ~/Developer/casberi
git fetch origin claude/kind-mayer-u8rjwm
git checkout claude/kind-mayer-u8rjwm
```

## What is already proven, and what is not

Proven (CI on afbfcd2, the macOS runner):
- `audits`: every `scripts/*-audit.py` and `network-reach-audit.sh` pass.
- `selftests`: 208 run, 0 failed. That includes the new `aztec-tx-selftest.sh` (the engine's `aztec-tx.js` in node against Aztec's own packages: 26 checks, five mutations) and `aztec-words-selftest.sh`, and the extended `move-warnings-selftest.sh`. Those compile `AztecWords.swift` and `MoveWarnings.swift` with `swiftc`.

Not proven:
- **The app target has never been compiled.** It was written on Linux with no Swift toolchain.
- The engine bundle (`tools/aztec-engine`) was never built with Vite. `node --check` parses `main.js`.
- Nothing has been seen on a simulator or a phone.
- aztecscan's `tx-effects` URL is a guess (`AztecActivity.explorer`).
- The new strings are not translated.

## Step 1: build

```sh
scripts/verify.sh
```

If it fails to compile, these are the spots the writer was least sure of:

| File | What to look at |
|---|---|
| `Screens/MoveAztecPrivate.swift` | `let steps = switch AztecAccountStore.priced[...] { case "usdc"?: … }` (a switch expression on an optional); `.task(id: "\(move.mode)\|…")`; `case .ready where move.leadWarning != nil:` with an `if let` inside a `@ViewBuilder` switch; `AztecMove.Option`'s custom init |
| `Model/MoveChecks.swift` | `recipient(…)`: `async let` with `Self.` calls, and `if case .at(let when)? = await made, case let days = …`; `presence(…)`: `(try? await … as? String)?.lowercased()` |
| `Screens/MoveSentence.swift` | `async let crossed = MoveChecks.otherNetworks(…)` inside `recheck()`, awaited after the GoPlus loop |
| `Model/Aztec/AztecActivity.swift` | `@MainActor static var contextProvider` on an enum; the `#Predicate` capturing `key` |
| `Model/Aztec/AztecAccountStore.swift` | `Sent`'s memberwise init with `var calls: [String]? = nil` between other fields (callers omit it); `Holding.sendable` defaulted |
| `Screens/AztecBrowser.swift` | `let held = …` inside the `.send` case of a `@ViewBuilder` switch |
| `Model/Aztec/AztecEngine.swift` | `AztecFeeWords.Payer(rawValue:)`, and the `engineSent` case |

The engine is built by `scripts/aztec-engine.sh ensure`, which `xcb.sh` runs before every build. It needs Shield's interfaces (`tools/aztec-engine/fetch-shield.mjs`, from Shield's site).

## Step 2: what each item should do, and how to see it

Logs to watch: `aztecActivity|`, `aztecEngine|` (the engine's `feeUnknown`, `sentPrivately … via:`), `moveWarn|`. Aztec needs the prover: an iPhone, or the simulator (the spike and §1700 step 1 ran there). The Mac has no prover, so Mac checks are limited to the Activity rows and Send's other-network warning.

### 1. Activity

Every Aztec transaction the account sends lands one Wallet › Activity row. Its `sourceRef` is `aztectx:<kind>:<hash>`.

| Do | Expect |
|---|---|
| A gas deposit, once Aztec claims it | "30 Fee Juice as gas — 0.31 Fee Juice fee" (fee from the receipt), no eye-slash |
| A Shield deposit, once claimed | "25 USDC to your private account — … fee", eye-slash |
| A private send to an Aztec address | "25 USDC to ...a91c on Aztec — … fee", eye-slash |
| An exit to Ethereum | "25 USDC to ...e07a on Ethereum — … fee", eye-slash |
| A transaction an Aztec app asked for | "Swap on nemi.fi — … fee" (first call's name, the site) |
| Relaunch | No duplicates; a row recorded while no store was there lands at launch (`landAll`) |
| Tap a row | aztecscan opens on that transaction. **If it 404s, fix `AztecActivity.explorer`** |

### 2. The fee on an app's approval sheet

Wallet Home › Apps on Aztec, open an app, do a transaction.

| Case | The sheet's line |
|---|---|
| Normal | "About 0.31 Fee Juice, from your Fee Juice." Compare it with the fee the Activity row then shows. |
| Fee Juice short | Amber: "About 0.31 Fee Juice. Your Fee Juice holds 0.1 Fee Juice: not enough." / "You have no Fee Juice to pay it." |
| The app sponsors the fee | "The app pays the fee." |
| Simulation failed (`feeUnknown` in the log) | "Paid from your Fee Juice. Casberi could not price it." |

Also note how long the sheet takes to rise: the engine simulates first, 20 s at most.

### 3. Any token

The account needs a private token that is not Shield's USDC or WETH (one an app minted or taught the wallet).

- Move › Send from "Aztec · Private": the amount list offers it, in 1/2/5 steps up to what is held, then all of it.
- To an Aztec address: it sends (`sentPrivately … via: transfer_private_to_private` or `transfer`), and Activity gets its row.
- To an Ethereum address: amber "Only USDC and WETH can leave Aztec." and Send stays dim.
- A token whose contract offers no private transfer is not offered at all.

### 4. An exit's recipient is checked

Send from Aztec · Private to an Ethereum address. The foot reads "Checking…" until the answer is in, then:

| Recipient | Expect |
|---|---|
| One your account never paid | Amber "First send to this address."; Send stays "Send" |
| A lookalike of a book entry (same `...xxxx` tail, different address) | Amber lookalike line; "Send anyway" takes two taps |
| An address from `Resources/OFACSanctionedETH.json` | Red "On the US sanctions list."; "Send anyway" |
| A Base-only contract (see item 6) | Amber "A contract on Base, not on Ethereum. Money sent here may be stuck." |

### 5. An Aztec address is checked

| Recipient | Expect |
|---|---|
| `0x198c84feae0509fd9b6da6f9469574260531d720f752dca3f0c22ebcb2aa1082` (off the curve; made for this test) | Red "No one can receive at this Aztec address. Check it."; Send dim. The engine refuses it too |
| `0x17e171cd06bf9fce7c73418ef6eddad7d1aa46c91230ddcbb02c6c071e985654` (valid, nobody's) | Amber "First send to this address."; sending to it would lose the money, so stop there |
| An account you already paid | No line |
| An address sharing the last four with one you paid | Amber lookalike line; two taps |

### 6. A 0x recipient used on another network

Move › Send, on one network, to an address used only on another. A demo account reads none of this; use your own account.

- A contract on Base only. Aerodrome's router is a candidate: `0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43`. Confirm first:

  ```sh
  for rpc in https://mainnet.base.org https://ethereum-rpc.publicnode.com https://rpc.mainnet.chain.robinhood.com; do
    curl -s $rpc -H 'content-type: application/json' \
      -d '{"jsonrpc":"2.0","id":1,"method":"eth_getCode","params":["0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43","latest"]}' | head -c 80; echo
  done
  ```

  Code on Base only → sending on Robinhood says "A contract on Base, not on Robinhood. Money sent here may be stuck."
- An address used on Base and never on Robinhood (any Base sender; check `eth_getTransactionCount` is 0 on Robinhood) → "Used on Base, never on Robinhood. Check they can take it on Robinhood."
- Your own Safe, or an address used on the network you send on → no line.
- An EIP-7702 delegated account (code starting `0xef0100`) → never the "contract" line.

Each is a second tap ("Send anyway"). `-moveSendDraft "<amount>|<address>|USDC@Robinhood"` with `-openMove YES` fills the sentence; `-moveWarnProbe` logs `moveWarn|`.

## Step 3: finish

- Fix what fails on the branch. Re-run `scripts/verify.sh`.
- Add the new strings to `Localizable.xcstrings` in Spanish, Japanese, Korean and Chinese, as the 3.0.23 commit did.
- Record what was measured in §1711, or in a new lettered entry after it: the explorer URL, whether the fee estimate matched the charge, a non-Shield token sent, and screens seen.
- Then TestFlight (`scripts/testflight.sh`) when the user says so.
