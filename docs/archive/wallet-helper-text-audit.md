# Wallet helper text — inventory and cut list (2026-10-18)

Every explaining, qualifying or "what we did / can't do" sentence the Wallet draws, sorted.
Paths are under `Casberi/Casberi/`. Row labels, figures, titles and VoiceOver-only strings
(`DSEmptyState words:`, tile tooltips) are left out — they don't draw.

Rule used: **cut** anything that narrates the app's own plumbing (freshness, scans, pricing
gaps, what Casberi can't see or won't do, what a control is). **Shorten** what the person
needs but is told at length. **Keep** what warns about money or signing, or says what a
transaction does.

Note: §748 keeps "honesty, money, signing, privacy and fix-it lines on purpose", and §780b says
a seat must say what it doesn't know. Cutting the STATUS lines below amends both.

## Cut — 47 lines

### Home and the total
| file:line | text |
|---|---|
| Screens/WalletFeedTiles.swift:383 | The line starts at the next reading. |
| Screens/FeedScreen+WalletRoom.swift:582 | Last read: {Place ago, …} |
| Screens/FeedScreen+WalletHome.swift:296 | An address or a name (under Follow a wallet) |
| Screens/FeedScreen+WalletHome.swift:299 | Apple Wallet, Wise and more (under Connect an app) |
| Model/PrivyHomeFeed.swift:635/637/639 | {q} more apps, empty or not used lately · {u} not read yet — they fill in over the next syncs |
| Model/CardSpendRoom.swift:553 | · not following long enough to compare |
| Model/CardSpendRoom.swift:567–572 | {n} spends have no readable amount |
| Model/CardSpendRoom.swift:578 | Settles once a day, so today's spending lands tomorrow |
| Model/CardSpendRoom.swift:349/352 | {n} earlier not drawn / {n} in other currencies |
| Screens/WalletSubscriptionsFigure.swift:44 | not counted: {names} |
| Screens/SubscriptionSheets.swift:108 | Found in: {sources} |
| Screens/SubscriptionSheets.swift:56 | Only what you added goes. A charge a card shows stays. (confirm message — keep the title only) |
| Model/MoneyReceipt.swift:494 | Read from the chain, not a market — so there's no dollar figure. |
| Model/MoneyCommentary.swift:149 | You'll be told when it reaches {n} confirmations. |
| Model/MoneyCommentary.swift:169 | Checked every sync — you'll be told the day it clears. |

### Holdings and Markets
| file:line | text |
|---|---|
| Design/TokenChartView.swift:69/70 | read just now / read {time} (under every chart, always) |
| Design/TokenChartView.swift:958 | 24h · 5 price points |
| Screens/PriceObjectCard.swift:126 | Live (stamp when fresh) |
| Screens/TokenQuickSheet.swift:68 | Token · held in a followed wallet |
| Screens/RoomHoldings.swift:95/97 | {name} isn't on mainnet, so it isn't sized |
| Screens/WalletNFTPickerSheet.swift:90 | Only the ones you pick are loaded. |
| Screens/WalletNFTPickerSheet.swift:115 | Solana and HyperEVM NFTs can't be read yet. |

### Security
| file:line | text |
|---|---|
| Screens/WalletActingPartiesRows.swift:128/130 | One of your accounts is a smart account whose installed modules can't be listed — this app can see that it is one, not what is in it. **Also** drop the `modulesUnreadable` clause at FeedScreen+WalletRoom.swift:862, which shows the Delegations section for this line alone. |
| Screens/WalletApprovalExposureCard.swift:98 | Revoking is free apart from gas. |
| Model/WalletApprovalExposure.swift:153/155 | {spender}'s grant couldn't be priced, so it isn't counted. |
| Screens/ApprovalPrepareCard.swift:49 | A transaction you sign there — never here. (and its twin ENSRenewCard.swift:67) |
| Screens/FlaggedReceiptBox.swift:109–111 | It sent you {amount} to sit in your history · {day} |
| Screens/FlaggedReceiptBox.swift:202 | No market prices it |
| Screens/WalletFeedTiles.swift:1419/1420 | Muted — won't badge your feed / Nothing to do |
| Screens/WalletFeedTiles.swift:1633 | Sign in the Safe app |

### Accounts
| file:line | text |
|---|---|
| Screens/WalletFollowSheet.swift:134 | Not an address or a name yet. |
| Screens/WalletConnectPickerSheet.swift:96–101 | second halves: "Saving names them in your book — nothing is followed or read." / "Following is read-only — it can never trade or move funds." |
| Screens/WalletConnectPickerSheet.swift:160 | Couldn't check whether you sign on any Safes just now. |
| Screens/WalletConnectPickerSheet.swift:163 | This address is named as an owner on more Safes than we checked — these are the ones confirmed live. |
| Screens/WalletScreen.swift:103 | The names you filed stay. |
| Screens/WalletScreen.swift:184 | Read-only — following can never move funds. |
| Screens/WalletConnectionScreen.swift:74 | When you follow one |
| Screens/WalletConnectionScreen.swift:86 | Activity is public, read directly on {device}. |
| Screens/AppleWalletScreen.swift:142 | Never added together. |
| Screens/ThingSheetView.swift:1529/1548 | It rides every future transfer. Blank clears it. / It names them everywhere in the app. Blank removes the name. |
| Screens/AddressBookViews.swift:1153 | A blank name removes it from your book. |
| Screens/AddressBookViews.swift:2256 | It rewrites every transaction you have with this address, everywhere in the app. |

### Safe
| file:line | text |
|---|---|
| Screens/SafeScreen.swift:121/122 | Signs behind Face ID. It can never execute. / This phone holds no funds. |
| Screens/SafeScreen.swift:718/720 | Safe paused reads, so the queue wasn't checked. [It reopens {t}.] |
| Model/SafeRoom.swift:480/482 | Safe paused reads — this may be out of date / — last checked {t} |
| Model/SafeRoom.swift:459/462/464 | A guard checks every transaction on this Safe |
| Screens/SafeQueueCard.swift:463 | Casberi signs; it can't execute. Another owner sends it. |
| Screens/SafeQueueCard.swift:532 | Described by {owner} |
| Screens/SafeQueueCard.swift:722 | Simulated as the Safe's call, before signatures and gas. |

## Shorten — 16 lines
| file:line | now | to |
|---|---|---|
| Screens/FeedScreen+WalletTiles.swift:80–96 | No answer from Base; Couldn't price Kraken EUR — not in this total | Not counting Base, EUR |
| Screens/WalletFeedTiles.swift:505 | as of {ago} (stale total) | keep, as a stamp beside the figure, not a line |
| Screens/ThingSheetView.swift:3036/3044/3050 | Looks like a copy of an address you've used — this is a different wallet. / You didn't send this. A spam token can announce any transfer it likes — it's advertising, not money that moved. | the box's own title: "A copy of an address you've used" / "You didn't send this" |
| Screens/MarketsViews.swift:440–442 | Higher than now alerts on the way up, lower on the way down. Once. | Alerts once. |
| Screens/MarketsViews.swift:259/260/263 | Up or down, once a day at most / The last 24 hours, once a day at most | Once a day |
| Model/MarketsWatch.swift:74 | Not traded, so there's nothing to follow | Not traded |
| Screens/WalletFollowSheet.swift:80 | You follow 5 addresses, the most there is. Stop following one on its account page first. | Following 5 of 5. |
| Screens/WalletFollowSheet.swift:83 | 0x, Solana or Bitcoin, or a name like casberi.eth. | move into the field's placeholder |
| Screens/WalletConnectPickerSheet.swift:109/112 | You're following 5 already — the cap. Unfollow one first; naming an address stays free. | Following 5 of 5. |
| Screens/SafeScreen.swift:231 | Following {n} Safe — a pending signature lands in your feed the moment it's proposed. | Following {n} Safe |
| Screens/SafeScreen.swift:386/387 | Signing for {n} Safes. Losing this phone would still leave enough owners to change that ({spare} to spare). | Signing for {n} Safes |
| Screens/SafeQueueCard.swift:757–765 | Not simulated — Casberi can't simulate on this chain. (+4 reasons) | Not simulated |
| Screens/SafeAskSheet.swift:223 | A statement, not a transaction — nothing moves. Casberi signs only what it can name. | Nothing moves. |
| Screens/SafeAskSheet.swift:298 | {why} Casberi signs only what it can name. | {why} |
| Screens/SafeAskSheet.swift:427 | An approval, not a transaction. The module waits out its delay, and the current owners can cancel until then. | The owners can cancel until it runs. |
| Screens/AppleWalletScreen.swift:90–92 | three promise lines | before Connect only; gone once connected |

## Your call
- **Price card sentences** (Model/PriceObject.swift:200–251) — "Quiet — it hasn't moved more than a percent across this 1D window." Commentary, not plumbing; Stocks has none.
- **Money commentary** (Model/MoneyCommentary.swift:89–130) — "You and Ana have moved funds 5 times. Mostly them sending you." / "You usually spend about $12 at Blue Bottle."
- **Account page meta** (Model/AccountPageShape.swift:55–118, BridgeCatalog.swift:1039–1043) — "Reading · 3m ago", "Connected 12 Oct", "Last read …", "No sign-in · Reads your wallets". Shared chassis: cutting it changes every app's page, not just Wallet's.
- **Address timeline root** (Model/AddressSpine.swift:190–267) — "You have not named this address".

## Keep
Poisoning, look-alike and checksum warnings; the pasted-private-key refusal; every Safe
transaction reading (what it sends, who it adds, delegatecall, module enable); "Don't sign
this anywhere" hash mismatches; N-of-N and lone-guardian refusals; key-delete confirms;
"can fall N%", liquidation and out-of-range lines; Needs you rows; price-rise notes; Safe
setup steps (SafeScreen.swift:298/299/474/551 — fix-it, needed to finish setup).

## Dead code found on the way
- `WalletWatchSyncSection` (Screens/WalletWatching.swift:113–168) — never instantiated.
- `counterpartyHistory` (Screens/ThingSheetView.swift:2953–2967) — no reader.
- `WalletWarnings` subtitles at :515, :543 and `WalletPermissions.phrase`/`word` — not drawn.
- `WalletApprovalAge` — probe-only caller.
