# "wallet" → "account": copy inventory (2026-10-18)

The rule (user): **Wallet** is the place — the tab, the category, the room.
The things in it are **accounts**. "Follow a wallet" is wrong twice: it is not a
wallet, and the verb is not what happens.

Scope: every user-facing string literal in `Casberi/` (Swift, minus tests, probe
hooks and log lines), the String Catalog, and the website. Code identifiers
(`WalletStore`, `walletFollow`, `wallet:` refs) are out of scope — renaming them
changes nothing anyone reads.

Counts: ~490 literals contain "wallet". About **95 are wrong** (section 1), ~45
mean a wallet *app* and are right (section 2), ~120 are the place's name and are
right (section 3), ~200 are Walletbeat's own review text (section 4), the rest are
debug lines (section 5).

---

## 1. Wrong — "wallet" means one of the person's accounts

### 1a. The verb: "Follow a wallet" and kin
| Where | Says now |
|---|---|
| `Shell/RoomsTray.swift:1739` | Follow a wallet (the tray's Wallet row action) |
| `Shell/RoomsTray.swift:1165` | Follow this wallet (tray search hit) |
| `Screens/WalletFollowSheet.swift:35` | Follow a wallet (tray title) |
| `Screens/FeedScreen+WalletRoom.swift:281` | Follow a wallet (Accounts menu's first row) |
| `Screens/FeedScreen+WalletHome.swift:295` | Follow a wallet (Home section +) |
| `Screens/SettingsHome.swift:582` | Follow a wallet (empty kind's act) |
| `Screens/StartWaysIn.swift:46` | Follow a wallet (first-run step) |
| `Screens/ThingSheetView.swift:3508` | Couldn't follow this wallet |
| `Screens/PeerScreen.swift:88` | Following a wallet is all it takes. |
| `Screens/WalletConnectPickerSheet.swift:329` | Following 1 more wallet. |
| `Screens/WalletConnectPickerSheet.swift:96–101` | …nothing is followed or read / Following is read-only… |
| `Screens/ConnectWalletRow.swift:159` | …Nothing was followed. |
| `Screens/SafeScreen.swift:232` | Follow a Safe, or a wallet that signs for one. |
| `Model/WalletConnectBridge.swift:162` | Follow a wallet's activity — read-only. |
| `Shell/RootShell.swift:3501, 3593, 3604, 3612, 3620` | Nothing … yet — follow an address from Apps → Wallet. |

### 1b. "your wallet(s)" / "a wallet" as the account
| Where | Says now |
|---|---|
| `Screens/SettingsHome.swift:975` | Your wallets (Settings count tile) |
| `Screens/SettingsHome.swift:1262` | Wallets |
| `Screens/SettingsHome.swift:1270` | The wallets you follow, and their apps |
| `Screens/AccountDetailSheet.swift:498` | Hide wallet balances |
| `Screens/WalletWatching.swift:162`, `Model/BridgeStore.swift:648` | Reads your wallet's activity. |
| `Model/BridgeCatalog.swift:1042` | Reads your wallets |
| `Model/BridgeStore.swift:259, 263, 267, 277, 285, 316` | Reads … for the wallets you follow (Peer, Privacy Pools, Railgun, MetaMask Card, Plasma One, ether.fi) |
| `Screens/PrivacyPoolsScreen.swift:91` | Deposits are read off the wallets you follow. |
| `Screens/RailgunScreen.swift:91` | Read off the wallets you follow. |
| `Screens/BankrSetupScreen.swift:99` | It can't see the wallets you follow here. |
| `Model/AskSubject.swift:113` | %@ acts on its own account — not the wallets you follow here. |
| `Screens/ENSScreen.swift:138` | From your wallets |
| `Screens/ENSScreen.swift:145` | Found on a wallet you follow |
| `Screens/TokenQuickSheet.swift:68` | Token · held in a followed wallet |
| `Screens/WalletbeatDirectoryScreen.swift:96` | …followed wallets are read live. |
| `Screens/ExchangeSetupScreen.swift:216` | your %@ balance now joins your wallets. |
| `Model/WalletAsk.swift:48, 62–63` | your wallet(s) / %@ across your wallets / %@ in your wallet |
| `Model/KeptAskComposers.swift:278` | Across your wallets (allocation bar) |
| `Model/KeptAskComposers.swift:219` | Couldn't reach your wallet right now. |
| `Model/MoneyReceipt.swift:1103` | In your wallet |
| `Screens/FlaggedReceiptBox.swift:93` | Same last four. A different wallet. |
| `Screens/FlaggedReceiptBox.swift:239` | Nothing left your wallet |
| `Screens/ThingSheetView.swift:3036` | …this is a different wallet. |
| `Screens/WalletFlowBand.swift:521` | an unnamed wallet, %@ |
| `Screens/WalletActingPartiesRows.swift:111` | this wallet |
| `Model/WalletActingParties.swift:132` | Runs as your wallet |
| `Model/WalletPermissions.swift:74, 95` | Can act as your wallet / Acts as your wallet |
| `Model/WalletSafety.swift:189, 191, 201, 204` | Your wallet now delegates to… / Your wallet's delegation was removed |
| `Model/BitcoinBridge.swift:688` | This wallet hasn't moved since %@ |
| `Model/PrivacyPoolsRoom.swift:588, 591, 729, 730` | reclaim to / back in your wallet; …deposits are back in your wallet |
| `Model/PrivacyPoolsBridge.swift:855` | …reclaim it to your wallet |
| `Model/Verbs.swift:295` | Wallet …44b1 (sheet verb for an unnamed account) |
| `CasberiApp.swift:402–403` | Scope to All Wallets / Scope to Wallet %lld (Mac ⌘-menu) |
| `Model/DayBrief.swift:64, 84, 108, 222` | ", wallet +1.2%" (day line) |
| `Screens/PrivyAppHead.swift:110` | %lld wallets |
| `Screens/NewContactSheet.swift:25, 45` | Email or wallet address / An email, a wallet address or a name… |
| `Model/AgentAnswer.swift:357` | …grounds on your wallet and live markets… |

### 1c. An account TYPE called a wallet
| Where | Says now |
|---|---|
| `Model/WalletFollow.swift:71`, `Model/BitcoinHD.swift:76` | Bitcoin wallet (an xpub you follow) |
| `Model/BitcoinHD.swift:125` | Multisig wallets aren't read yet. |
| `Screens/AddressBookViews.swift:1719` | World App wallet |
| `Model/WalletFollow.swift:53` | %@ is a zk.money wallet… show on the wallets that make them. |
| `Model/SafeAsk.swift:37` | No Safe wallets detected. |
| `Screens/SafeScreen.swift:174, 185` | Stop guarding this wallet? / This forgets the wallet… the wallet's owner… |
| `Screens/SafeAskSheet.swift:474, 476, 478` | The wallet doesn't list this module… / guardian of this wallet / This wallet's recovery… |

### 1d. Privy's "app wallets" (accounts an app made for you)
| Where | Says now |
|---|---|
| `Screens/ThingSheetView.swift:1925` | App wallet · made %@ ago |
| `Model/RoomAccounts.swift:183` | App wallets (Accounts menu group) |
| `Model/NotifyPlan.swift:283, 314, 364` | New app wallet / app wallet(s) |
| `Model/PrivyHomeFeed.swift:433, 434, 616, 617, 622` | Every app that made you a wallet / What moved in your app wallets / …made you a wallet with Privy / in %lld app wallets |
| `Screens/PrivyScreen.swift:107` | Reads which apps made you a wallet… |
| `Model/BridgeCatalog.swift:229` | Every app wallet you've made (Privy tagline — also on the website) |

### 1e. Demo copy (`Model/DemoSeedAll.swift`, `Model/DemoCorpus.swift`)
`DemoSeedAll:1021` How's my wallet doing this week? · `:1024` the wallet room's approvals card ·
`:5661–5665` Rides your wallet (×5) · `:5699` Reads which apps made you a wallet. ·
`:5733` Reads your wallet's shielded moves. · `DemoCorpus:212` Sent 0.2 ETH to cold wallet.

---

## 2. Right — "wallet" means a wallet APP (MetaMask, Rabby, a Lightning wallet)
These talk about the software that holds keys and signs, which Casberi never is.
Keep the word; consider **"wallet app"** wherever "your wallet" could be misread
as an account.

`ConnectWalletRow.swift:47, 63, 64, 79, 142, 149, 155, 159, 163` · `WalletWatchField.swift:356` ·
`WalletConnectPickerSheet.swift:96–101, 230–231` ("Your wallet shared N addresses", "From your wallet") ·
`LightningScreen.swift:67, 79, 87, 133`, `LightningBridge.swift:80, 199–207` · `TokenBridges.swift:310` ·
`SafeScreen.swift:298, 299, 458, 474`, `SafeAskSheet.swift:304`, `SafeQueueCard.swift:778, 793` ("your other wallet") ·
`ENSRenewCard.swift:129` · `BankrSetupScreen.swift:98` (Bankr's own wallet) · `TokenWatchScreen.swift:196` ·
`BridgeCatalog.swift:150` · `WalletbeatViews.swift:233–234` · `NotifyPlan.swift:258, 348`.

## 3. Right — "Wallet" the place
Tab, category, room title, widget, "In Wallet", "Paid in Wallet", "Subscription in Wallet",
"From your Wallet" (`WatchAddSheet:67`), "Apps → Wallet", "Wallet · Holdings". ~120 hits,
no change. Apple's "Wallet" (`AppleWalletBridge:245`) is Apple's name.

## 4. Right — Walletbeat's subject is wallet apps
`WalletbeatDirectory.swift` (Walletbeat's own questions, verbatim), `WalletbeatRoom.swift`,
`WalletbeatCardScreen.swift`, `WalletbeatScreen.swift`, `WalletbeatBridge.swift`. One
exception: `WalletbeatCardScreen.swift:102` "Follow this wallet" — the verb here follows a
wallet *app's* reviews, so the noun is right; whether "Follow" is right is the verb question below.

## 5. Not user-facing
Probe/log lines ("no EVM wallets watched", "followed wallet(s)", `WorldIDSource:195–198`,
`WeiNamesSource:180–183`, `*RoomSource` compose=nil lines). Rename with the rest for
consistency, not urgency.

## 6. The String Catalog
`Localizable.xcstrings` holds **74 "wallet" keys no source string uses any more** — the
old "watch" spellings ("Watch a wallet", "The wallets you watch", "Watching 1 more wallet"),
"Add a wallet", "One of your wallets", "Wallet balance", "Disconnect Wallet", "Count in
Wallet total", "Wallet key". They go at the next catalog sync; don't hand-edit them.

## 7. Website (`website/docs.html`, `llms.txt`, `index.html`)
- docs.html: "Watch your wallets", "Follow a wallet from the Wallet row in the tray",
  "Your own wallets under Apps", "Naming a wallet is free; following is capped at five",
  "Watching a wallet is read-only…" (×2), "a wallet needs only an address",
  "Nothing at all for wallets", "My wallet shows no balance", "every token across every
  wallet and chain", "the category's own action, like Follow a wallet",
  "Privy — Every app wallet you've made", "Lightning — Your Lightning wallet".
- llms.txt:10 "one balance across self-custody wallets".
- index.html "scattered across apps, agents, wallets" and "a wallet to save" mean the
  product category — fine.

---

## Open question: the verb
"Follow" is wrong for an account that is yours (prd §1412: a wallet you watch is yours).
Candidates: **Add an account** (matches Accounts' "+", and Connect an app beside it),
or Watch an account. The ledger has moved Follow ↔ Watch twice (§1105, §1118–§1121),
so the pick needs a new § entry either way.
