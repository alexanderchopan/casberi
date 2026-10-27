#!/bin/zsh
# private-money-selftest.sh — Move to private and the private rows (prd §1554).
#
# Compiles the pure halves WHOLE and drives them:
#   - the ASP's answer: pending and unknown are waiting, approved, rejected,
#     poi_required; anything else changes nothing; asked by the label's HASH;
#   - Holdings' rows: one per token and state, summed, private first, a
#     waiting row dated by its oldest note;
#   - amounts: "0.001" ⇄ base units ⇄ 0x-hex, the ladder the balance allows
#     after the gas a first move keeps back;
#   - the testnet transaction's bytes, against viem 2.45.3's own
#     serialisation (unsigned, signed with each parity, a 70-byte payload so
#     the long-length head is used), and no transaction for a non-testnet;
#   - where the engine's node requests go: logs to the node that keeps them,
#     back to the network's own node past its head, a 429 waited out;
#   - a fresh address (prd §1560): its keys against Node's HMAC, the next
#     index never reused, which are watched, the deposit planned out of what
#     arrived (its gas and 0xBow's vetting fee), too little to move, the
#     prepared deposit checked against the plan, the Entrypoint's terms.
# It also asserts the USE: the act is Move's sentence and Holdings' rows its
# door (no sheet of Holdings' own), the address drawn by its tail; the store asks by `labelHash`, the engine's door
# routes before it sends, the deposit is kept with the engine's label hash,
# Sepolia's first block is the keystore's, the sender is DEBUG-only and its
# key device-only, and the bundle carries the label hash. Mutations prove the
# assertions bite, each checked to have CHANGED the source.
set -euo pipefail
cd "$(dirname "$0")/.."
PM="Casberi/Casberi/Model/PrivateMoney.swift"
TX="Casberi/Casberi/Model/TestnetTx.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
WIRE="Casberi/Casberi/Model/PrivacyEngineWire.swift"
ART="Casberi/Casberi/Model/PrivacyArtifacts.swift"
PINS="Casberi/Casberi/Model/PrivacyArtifactPins.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
STORE="Casberi/Casberi/Model/PrivateMoneyStore.swift"
MOVE="Casberi/Casberi/Model/PrivateMove.swift"
SENDER="Casberi/Casberi/Model/PrivacyTestnetSender.swift"
ENGINE="Casberi/Casberi/Model/PrivacyEngine.swift"
FRESH="Casberi/Casberi/Model/FreshAddress.swift"
ROOT="Casberi/Casberi/Model/PrivateRoot.swift"
ENGJS="tools/privacy-pools-engine/src/engine.js"
BUNDLE="Casberi/Casberi/Resources/privacy-engine.js"
for f in "$PM" "$TX" "$FRESH" "$ROOT" "$KECCAK" "$WIRE" "$ART" "$PINS" "$REACH" "$STORE" "$MOVE" "$SENDER" "$ENGINE" "$ENGJS" "$BUNDLE"; do
    [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done
echo "private-money self-test"

use() { grep -qF -- "$2" "$1" || { echo "✗ $3"; exit 1; } }
use "$STORE" 'let url = PrivateMoney.statusURL(aspUrl: network.aspUrl, labelHash: note.labelHash),' "the store no longer asks the note's own network's ASP by the label's hash"
use "$MOVE" 'labelHash: deposit.labelHash' "a deposit is no longer kept with the engine's label hash"
use "$ENGINE" 'let routed = network.logsUrl.map { PrivacyEngineWire.routed(url, body: text, rpcUrl: network.rpcUrl, logsUrl: $0) } ?? url' "the engine's door no longer routes log reads"
use "$ENGINE" 'await Self.send(request, to: routed, fallback: url, relayerUrl: network.relayerUrl)' "the engine's door no longer sends the routed request"
use "$WIRE" 'fromBlock: 10_932_354)' "Sepolia's first block is no longer the keystore's (10,932,354)"
use "$ENGJS" 'labelHash: await labelHashOf(r.pendingNote.label),' "the engine no longer returns a deposit's label hash"
use "$BUNDLE" 'labelHash' "the shipped bundle has no label hash — rebuild with tools/privacy-pools-engine/build.mjs"
[[ $(head -1 "$SENDER") == "#if DEBUG" && $(tail -1 "$SENDER") == "#endif" ]] || { echo "✗ the testnet sender is not DEBUG-only"; exit 1; }
! grep -q "SecItemAdd" "$SENDER" || { echo "✗ the testnet sender makes a device-only key again (prd §1562: it is the root's owner)"; exit 1; }
use "$SENDER" "return try PrivateAccount.ownerAddress(try PrivateRootKey.ensure())" "the testnet sender is no longer the private root's owner"
use "$SENDER" 'guard let tx = TestnetTx.Tx(chainId: network.chainId,' "the sender no longer builds through TestnetTx's testnet guard"
use "$MOVE" 'static var available: Bool { PrivacyNetwork.current(debugAsks: debugNetwork) != nil }' "Move to private no longer follows the network this build serves"
# Receive to a fresh address on Ethereum (prd §1567): wherever private money
# is, with your account on the phone as the note's owner.
awk '/static var freshAvailable: Bool/,/^    }$/' "$MOVE" | grep -q 'return network.isTest || PrivateOnEthereum.owner != nil' \
    || { echo "✗ Receive to a fresh address is offered on Ethereum with no account to own the note"; exit 1; }
echo "  ok   asked by hash, routed before sent, the keystore's first block, a DEBUG-only sender owned by the root"

# One root for private money (prd §1562): in iCloud Keychain, synchronizable,
# AfterFirstUnlock, in the app id's shared group, each root its own item (a
# new phone's root never overwrites the old one); the seed, the owner and the
# fresh addresses derived from it; spending asks for the device owner, money
# moving IN does not; a new phone finds the notes and walks the addresses
# back; the device-only account's money is withdrawn to a fresh address of
# the root; the background watch goes through Tor or asks nothing.
RKEY="Casberi/Casberi/Model/PrivateRootKey.swift"
RACC="Casberi/Casberi/Model/PrivateAccount.swift"
WATCH="Casberi/Casberi/Model/PrivateWatch.swift"
SEC="Casberi/Casberi/Screens/MoveSecurity.swift"
FRESHM="Casberi/Casberi/Model/FreshReceive.swift"
for f in "$RKEY" "$RACC" "$WATCH" "$SEC"; do [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }; done
use "$RKEY" 'kSecAttrSynchronizable as String: true,' "the private root no longer syncs through iCloud Keychain"
use "$RKEY" 'add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock' "the private root is not readable after first unlock (a synced item cannot be device-only)"
use "$RKEY" 'add[kSecAttrAccessGroup as String] = TokenVault.sharedAccessGroup' "the private root is not in the app id's shared group"
use "$RKEY" 'var add = query("root-" + id)' "a root is no longer its own item, named by its id"
! grep -qE 'SecItemUpdate|SecItemDelete' "$RKEY" || { echo "✗ the private root can be overwritten or deleted"; exit 1; }
use "$RKEY" '.sorted { $0.made < $1.made }' "new money no longer goes to the oldest root"
use "$RACC" 'guard let derived = PrivateRoot.derive(root, .poolSeed) else' "the private account's seed no longer comes from the root"
use "$RACC" 'if let reason { try await PrivateRootKey.unlock(reason: reason) }' "opening to spend no longer asks for the device owner"
use "$MOVE" 'try await PrivateAccount.open(account, reason: String(localized: "Send from your private balance"))' "a private send no longer asks for the device owner"
use "$MOVE" 'let account = try PrivateRootKey.ensure()' "a deposit no longer goes to the root's account"
use "$FRESHM" 'try await PrivateAccount.open(account, reason: nil)' "a fresh move asks for you (it cannot run in the background)"
use "$FRESHM" 'while let batch = PrivateRoot.nextBatch(seen) {' "a new phone no longer walks the fresh addresses back"
use "$FRESHM" 'async let nonce = PrivateRPC.decimal(network, "eth_getTransactionCount", [address, "latest"])' "the walk no longer asks whether an address moved"
use "$WATCH" 'store.reconcile(found, root: root, network: network)' "a new phone no longer keeps the notes it found"
use "$WATCH" 'await store.fillLabelHashes()' "a note found again is never asked about its approval"
use "$WATCH" 'let spend = try await engine.prepareWithdraw(tokenId: PrivateMove.eth, amount: hex, to: to.address)' "the device-only account's money is no longer withdrawn"
use "$WATCH" 'guard let to = FreshReceive.shared.unusedCurrent() else' "the device-only account's money no longer goes to an unused fresh address of the root"
use "$WATCH" 'guard isReady(TorStatus.shared.state) else {' "the background watch no longer waits for Tor"
awk '/guard isReady\(TorStatus.shared.state\) else \{/,/^            \}$/' "$WATCH" | grep -q 'return false' || { echo "✗ the background watch asks something without Tor"; exit 1; }
use "$WATCH" 'await WalletBackgroundRefresh.runNotifySweep()' "the background watch tells through something other than the Wallet's one pass"
! grep -q 'UNUserNotificationCenter\|Notifications.submit' "$WATCH" || { echo "✗ the private watch notifies on its own"; exit 1; }
use "Casberi/Casberi/Info.plist" '<string>com.casberi.app.privatewatch</string>' "the watch's identifier is not permitted in Info.plist"
use "Casberi/Casberi/CasberiApp.swift" 'PrivateWatchTask.register()' "the watch is not registered at launch"
use "Casberi/Casberi/Shell/RootShell.swift" 'PrivateWatchTask.schedule()' "the watch is never scheduled"
use "Casberi/Casberi/Shell/ProbeHooks.swift" 'Hook(key: "backgroundRefreshProbe")' "the watch has no probe"
use "$SEC" 'if privateBackup != .fine {' "Security draws the private balance's row when nothing needs you"
use "$SEC" 'value: String(localized: "Not backed up"),' "the private balance's row lost its state word"
use "$SEC" 'tone: DS.attentionInk, verb: privateBackupVerb)' "the private balance's state is not amber, or has no fix"
echo "  ok   one root in iCloud Keychain: the seed, the owner and the fresh addresses from it, found again, the watch through Tor"

# Private is Send's, never a verb (prd §1554): "Your private balance" leads
# Send's recipients, the Private switch stands under Send's sentence (off, and
# never remembered on: its binding reads false), the verbs are Move's five,
# Holdings' header and rows open Send, and Holdings raises no sheet of its own.
SENT="Casberi/Casberi/Screens/MoveSentence.swift"
MSCREEN="Casberi/Casberi/Screens/MoveScreen.swift"
MPRIV="Casberi/Casberi/Screens/MovePrivate.swift"
HOLD="Casberi/Casberi/Screens/FeedScreen+WalletPrivate.swift"
use "$SENT" '}) { verbs }' "the private sentence is no longer drawn under Move's verbs"
use "$SENT" 'listRow(String(localized: "Your private balance"), sub: (PrivacyNetwork.current(debugAsks: PrivateMove.debugNetwork) ?? .ethereum).name, symbol: "eye.slash") {' "your private balance is no longer a recipient"
use "$SENT" 'MovePrivateSwitch(isOn: Binding(get: { false }, set: { if $0 { goPrivate(.send) } }))' "the Private switch is not off on arrival under Send"
awk '/MovePrivateSwitch\(isOn: Binding\(get: \{ false \}/{print prev} {prev=$0}' "$SENT" | grep -q 'if verb == .send, receipt == nil, PrivateMove.available {' \
    || { echo "✗ the Private switch stands somewhere other than Send, or where the sender cannot move"; exit 1; }
! grep -qE 'case (swap|send|receive|buy|sweep), private|case private' "$SENT" || { echo "✗ Private became a verb"; exit 1; }
! grep -q 'PrivateMove.available ? \[nil\]' "$SENT" || { echo "✗ Private is in the verbs row"; exit 1; }
use "$MPRIV" 'if move.mode == .send, !isDone {' "the switch shows on a deposit, or is gone from a private send"
use "$MSCREEN" 'privately: chrome.movePrivately, receivePrivately: chrome.moveFreshReceive)' "Move no longer opens Send privately when asked"
use "$MSCREEN" 'onDismiss: { chrome.movePrivately = nil; chrome.moveFreshReceive = false }' "a closed Move keeps opening privately"
grep -q 'Button { walletOpenPrivate(.deposit) } label:' "$HOLD" && grep -q 'return Button { walletOpenPrivate(.send) } label:' "$HOLD" \
    || { echo "✗ Holdings' header no longer sends to your private balance, or a row no longer sends from it"; exit 1; }
! grep -q 'feedSheet' "$HOLD" || { echo "✗ Holdings raises a private flow of its own"; exit 1; }
[[ ! -e Casberi/Casberi/Screens/MovePrivateSheet.swift ]] || { echo "✗ the standalone Move to private sheet is back"; exit 1; }
use "$MPRIV" 'MoveWord(YourAccount.short(address), ink: DS.pickInk)' "the address to fund is no longer drawn by its tail"
use "$MPRIV" 'MoveWord(YourAccount.short(to), ink: live ? DS.pickInk : DS.textPrimary)' "the recipient is no longer drawn by its tail"
! grep -qE 'prefix\([0-9]+\)' "$MPRIV" || { echo "✗ the sentence draws an address's head"; exit 1; }
use "Casberi/Casberi/Model/PrivateMove.swift" 'let relayed = try await engine.relay(handle: spend.handle)' "a private send no longer goes through the relayer"
use "Casberi/Casberi/Model/PrivateMove.swift" 'let held = PrivateMoneyStore.shared.spendable(chainId: network.chainId)' "a private send's amounts are not the approved private balance"
use "tools/privacy-pools-engine/src/engine.js" 'const r = await s.relayWithdraw(option);' "the engine no longer relays a withdrawal"
use "Casberi/Casberi/Resources/privacy-engine.js" 'relayWithdraw' "the shipped bundle cannot relay — rebuild with tools/privacy-pools-engine/build.mjs"
use "Casberi/Casberi/Design/BridgeIcon.swift" 'if PrivateMoney.isActivity(thing.sourceRef) { return "eye.slash" }' "a private move's Activity row lost its eye"
use "Casberi/Casberi/Model/WalletIngest.swift" 'venues: cash + privy + privately,' "private money no longer counts in the Wallet's total"
use "Casberi/Casberi/Screens/FeedScreen+WalletPages.swift" '.filter { $0.symbol != PrivateMoney.walletSymbol }' "the Tokens rows count private money twice"
use "Casberi/Casberi/Screens/FeedScreen+Sheets.swift" 'positions: portfolio.positions.filter { $0.symbol != PrivateMoney.walletSymbol }' "the Tokens sheet counts private money twice"
use "Casberi/Casberi/Design/HoldingsTreemap.swift" 'if tile.id == PrivateMoney.walletSymbol {' "the box's Private block lost its eye"
# Needs you and Take it back (prd §1561): the rows stand on Needs you's page
# and in its count, the act is a word in a push row behind a dialog, the
# ragequit is proved, checked against the chain BEFORE it is signed, and pays
# the owner; discovery keeps a deposit waiting or refused.
TAKE="Casberi/Casberi/Model/PrivateTakeBack.swift"
PAGES="Casberi/Casberi/Screens/FeedScreen+WalletPages.swift"
use "$PAGES" 'if walletShowsPrivate { WalletPrivateAsks() }' "Needs you's page no longer draws the private deposits"
use "$PAGES" 'let deposits = walletShowsPrivate ? PrivateMoneyStore.shared.asks().count : 0' "Needs you's count leaves out the private deposits"
use "$HOLD" 'return DSPushRow(title: Text(verbatim: ask.title), subtitle: line(ask, stage: stage),' "a deposit's ask is no longer the push row"
use "$HOLD" 'let act = Text("Take it back").foregroundStyle(' "Take it back is no longer a word in the row's line"
awk '/if ask.canTakeBack \{/{getline; print}' "$HOLD" | grep -q 'confirming = ask' || { echo "✗ Take it back opens without the dialog, or where it is not offered"; exit 1; }
use "$ENGJS" 'const r = await s.prepareRageQuit({ commitment: note.commitment });' "the engine no longer proves a ragequit"
use "$BUNDLE" 'prepareRagequit' "the shipped bundle cannot take back — rebuild with tools/privacy-pools-engine/build.mjs"
use "$TAKE" 'guard quit.recipient.lowercased() == owner.lowercased() else {' "a ragequit paying someone else is signed"
sim=$(grep -n 'try await PrivacyTestnetSender.simulate(quit.tx)' "$TAKE" | cut -d: -f1)
snd=$(grep -n 'let hash = try await (note.root == nil' "$TAKE" | cut -d: -f1)
[[ -n "$sim" && -n "$snd" && "$sim" -lt "$snd" ]] || { echo "✗ Take it back is signed before it is simulated"; exit 1; }
use "$TAKE" 'PrivateMoneyStore.shared.remove(commitment: note.commitment)' "a taken-back note stays in Needs you"
use "$STORE" 'let unspent = found.notes.filter { ["ACTIVE", "PENDING", "REJECTED"].contains($0.status.uppercased())' "discovery drops a deposit waiting or refused"
echo "  ok   Needs you: the deposits counted and drawn, Take it back a word behind a dialog, simulated before it is signed"

# Round-ups into your private balance (prd §1561): offered only where a
# pool is, a send elsewhere sets nothing aside, the batch rides a deposit you
# confirmed, and its Activity row has no verb.
SEC="Casberi/Casberi/Screens/MoveSecurity.swift"
use "$SEC" 'ForEach(RoundUps.privatePools.filter { PrivacyNetwork.forChain($0) != nil }.sorted(), id: \.self) { chain in' "the private target is offered where there is no pool, or with the kill switch off"
use "$SEC" 'Label { Text("Your private balance") } icon: { Image(systemName: "eye.slash") }' "the private target is no longer its words and the eye"
use "$SENT" 'guard RoundUps.applies(setting, on: network.chainId), !network.isTest else { return nil }' "a send rounds up toward a private balance its network has no pool for"
mv=$(grep -n 'await Self.moveRoundUps(engine: engine, context: context)' "$MOVE" | cut -d: -f1)
dn=$(grep -n '            stage = .done(hash)$' "$MOVE" | tail -1 | cut -d: -f1)
[[ -n "$mv" && -n "$dn" && "$mv" -lt "$dn" ]] || { echo "✗ due round-ups no longer ride the deposit you confirmed"; exit 1; }
use "$MOVE" 'PrivateActivity.land(hash: hash, title: PrivateMoney.roundUpsTitle(figure: figure), context: context)' "moved round-ups land no Activity row"
use "$MOVE" 'let batch = RoundUps.privateMove(saved: RoundUps.privateSaved(on: chain), at: RoundUps.privateMoveAt),' "round-ups move per send, not together"
# Swaps and Buy round up (prd §1561): the swap's plan reads what it sells,
# a wrap and an unpriced token never; the buy rides only what can carry it;
# a Buy counts its change once paid.
use "$SENT" 'return s.quote.wrap == nil ? soldDollars(s) : nil' "a swap's round-up no longer reads what it sells, or rounds up a wrap"
use "$SENT" 'guard !privateRoundUps, !RoundUps.setting.movesPrivately, RoundUps.carriesBuy(roundUpAct),' "a swap or a Buy carries a buy it cannot pay, or a private target buys publicly"
use "$SENT" 'let bought = !toPrivate && buy != nil && !done.roundUpWaits' "a send or swap that did not carry the buy empties the count"
use "$SENT" 'RoundUps.setSaved(RoundUps.savedAfter(roundUp, bought: bought), on: net.chainId)' "a send or swap that did not carry the buy empties the count"
use "$SENT" 'if let roundUp { RoundUps.setSaved(RoundUps.savedAfter(roundUp, bought: false), on: net.chainId) }' "a paid Buy's change is not counted"
use "$SENT" 'case .swap: [soldPrint, quotePrint, swapFeePrint].compactMap { $0 } + roundUpPrint' "a swap's small print says nothing of its round-up"
echo "  ok   round-ups to private: offered where a pool is (Ethereum; Sepolia in DEBUG), moved together on a deposit you confirmed"
echo "  ok   swaps and Buy round up: what is sold, carried only where the dollar pays, a Buy counted"
echo "  ok   private is Send's: a recipient and a switch, opened from Holdings, relayed, the address by its tail"

# Receive to a fresh address (prd §1560): Receive's Private switch, off on
# arrival and only on your own account's Receive; the fresh sentence draws
# the address by its tail with the code carrying it whole on Sepolia, New
# address grey and Share pink; the move is an ordinary deposit for your own
# account (never depositFor), checked against the plan and the gas budget,
# signed by the fresh address's own key and sent from it; its root is
# DEBUG-only and device-only; Holdings looks too.
FRESHM="Casberi/Casberi/Model/FreshReceive.swift"
FRESHK="Casberi/Casberi/Model/FreshAddressKey.swift"
FRESHV="Casberi/Casberi/Screens/MoveFreshReceive.swift"
use "$SENT" 'MovePrivateSwitch(isOn: Binding(get: { false }, set: { if $0 { goFresh() } }))' "Receive's Private switch is not off on arrival"
awk '/set: \{ if \$0 \{ goFresh\(\) \} \}/{print prev} {prev=$0}' "$SENT" | grep -q 'if verb == .receive, receipt == nil, elsewhere == nil, !fresh, PrivateMove.freshAvailable {' \
    || { echo "✗ Receive's Private switch stands somewhere other than your own account's Receive"; exit 1; }
use "$SENT" 'freshReceive = false' "a verb no longer leaves the fresh address"
use "$FRESHV" 'Text(verbatim: copied ? String(localized: "Copied") : YourAccount.short(address))' "the fresh address is no longer drawn by its tail"
use "$FRESHV" 'SignerRequestSheet.code("ethereum:\(address)@\(network.chainId)")' "the code no longer carries the whole address on its network"
use "$FRESHV" 'Text("New address").dsText(.heading24).foregroundStyle(DS.textSecondary)' "New address is not the foot's grey word"
use "$FRESHV" 'ShareLink(item: entry.address) {' "Share no longer shares the whole address"
use "$FRESHV" 'MovePrivateSwitch(isOn: Binding(get: { true }, set: { on in if !on { leave() } }))' "the fresh sentence's switch no longer leaves when turned off"
! grep -qE 'prefix\([0-9]+\)' "$FRESHV" || { echo "✗ the fresh sentence draws an address's head"; exit 1; }
use "$FRESHM" 'return try await PrivacyEngine.shared.prepareDeposit(tokenId: PrivateMove.eth, value: value)' "a fresh move is no longer an ordinary deposit for your own account"
! grep -qi 'depositFor' "$FRESHM" || { echo "✗ a fresh move deposits for someone (depositFor)"; exit 1; }
use "$FRESHM" 'FreshAddress.matches(to: deposit.tx.to, value: deposit.tx.value, plan: plan, entrypoint: network.entrypoint)' "a fresh move is no longer checked against its plan"
use "$FRESHM" 'guard estimate > 0, estimate <= FreshAddress.gasBudget else' "a fresh move is no longer held to its gas budget"
use "$FRESHM" 'key: try FreshAddressKey.key(entry.index, root: entry.root), from: entry.address,' "a fresh move is no longer signed by the fresh address itself"
use "$FRESHM" 'gas: FreshAddress.gasBudget, tip: fees.tip, maxFee: fees.maxFee)' "a fresh move no longer sends at the fees it was planned with"
use "$FRESHM" 'if case .failed = entry.state, !force { continue }' "a failed fresh move asks Face ID every 15 s"
use "$SENDER" 'guard let tx = TestnetTx.Tx(chainId: network.chainId, nonce: nonce,' "a fresh key no longer signs through TestnetTx's testnet guard"
[[ $(head -1 "$FRESHK") == "#if DEBUG" && $(tail -1 "$FRESHK") == "#endif" ]] || { echo "✗ the fresh addresses' root is not DEBUG-only"; exit 1; }
! grep -q "SecItemAdd" "$FRESHK" || { echo "✗ the fresh addresses make a device-only root again (prd §1562)"; exit 1; }
use "Casberi/Casberi/Model/FreshSigner.swift" "guard var fresh = PrivateRoot.derive(privateRoot, .freshAddresses) else" "the fresh addresses no longer come from the private root"
use "$FRESHK" "if let root { return try FreshSigner.key(index, root: root) }" "a root's fresh key is made somewhere other than FreshSigner"
use "$HOLD" 'await FreshReceive.shared.check(context: modelContext)' "Holdings no longer looks at the fresh addresses"
echo "  ok   a fresh address: Receive's switch, its tail and code, your own deposit sent from it, its root the private root"

# ── prd §1567: every gap closed on Ethereum ────────────────────────────────
# Receive privately on Ethereum: the fresh key, from the root, signs only what
# FreshTx can make (a router's deposit, a token's approval of its router);
# the deposit is checked against the plan and its gas budget before it signs;
# "too little" is computed from the pool and today's fees; a USDC payment's gas
# comes from your private ETH only while you look, and only when it covers it.
FSIGN="Casberi/Casberi/Model/FreshSigner.swift"
FTX="Casberi/Casberi/Model/FreshTx.swift"
ETH="Casberi/Casberi/Model/PrivateOnEthereum.swift"
CHAIN="Casberi/Casberi/Model/YourAccountChain.swift"
TMPF=$(mktemp /tmp/private-money-fresh.XXXXXX)
for f in "$FSIGN" "$FTX"; do [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }; done
! grep -q '#if DEBUG' "$FSIGN" "$FTX" || { echo "✗ the fresh addresses' mainnet signer is DEBUG-only (it must ship)"; exit 1; }
use "$FSIGN" 'guard let tx = FreshTx.Tx(network: network, nonce: nonce,' "a fresh key signs something FreshTx did not make"
! grep -q 'TestnetTx.Tx(\|PrivacyTestnetSender' "$FSIGN" || { echo "✗ the mainnet fresh signer goes through the testnet sender"; exit 1; }
use "$FSIGN" 'guard SignerKey.ethereumAddress(uncompressedPublicKey: [UInt8](k.publicKey.dataRepresentation))?.lowercased() == from.lowercased() else {' "a fresh key signs as another address"
use "$FRESHM" 'guard FreshAddress.matchesYield(to: d.tx.to, value: d.tx.value, approvals: d.approvals.count, budget: plan.budget, pool: pool) else {' "a fresh deposit on Ethereum is not checked against its plan"
use "$FRESHM" 'let plan = FreshAddress.yieldPlan(balance: balance, maxFee: String(fees.maxFee), minimumBudget: floor)' "too little to move on Ethereum is not the pool's minimum plus today's gas"
awk '/private func moveEthereum\(/,/^    }$/' "$FRESHM" > "$TMPF"
est=$(grep -n 'guard estimate > 0, estimate <= FreshAddress.gasBudget else' "$TMPF" | cut -d: -f1)
snd=$(grep -n 'let hash = try await FreshSigner.send(' "$TMPF" | cut -d: -f1)
[[ -n "$est" && -n "$snd" && "$est" -lt "$snd" ]] || { echo "✗ a fresh deposit on Ethereum is signed before its gas is estimated within the budget"; exit 1; }
grep -q 'from: entry.address, network: network, gas: FreshAddress.gasBudget,' "$TMPF" || { echo "✗ a fresh deposit on Ethereum is not sent from the fresh address at its planned gas"; exit 1; }
grep -q 'try await PrivateOnEthereum.open(account, reason: nil)' "$TMPF" || { echo "✗ a fresh move on Ethereum asks for you (it runs in the background)"; exit 1; }
use "$FRESHM" 'guard interactive, spendable >= cost else {' "a USDC payment's gas is paid from private ETH in the background, or beyond what it holds"
use "$FRESHM" 'reason: String(localized: "Move \(symbol) to private"))' "paying a USDC payment's gas from private money does not ask for you"
use "$FRESHM" 'set(entry.id, .needsGas(amount: held), symbol: symbol)' "USDC with no gas and too little private ETH says nothing"
use "$FRESHV" 'arrived; needs a little private ETH to move' "the line no longer says a USDC payment needs private ETH"
! grep -qi 'depositFor' "$FRESHM" || { echo "✗ a fresh move deposits for someone (depositFor)"; exit 1; }
# USDC in Move's sentence; balance to balance; round-ups riding a Face ID
# operation, simulated whole before signing; the watch in every build; the
# restoring line.
use "$MOVE" 'return PrivateMoney.choices(balance: usdcBalance, reserve: "0", decimals: 6, ladder: PrivateMoney.usdcLadder, minimum: usdcMinimum)' "USDC's amounts do not start at the pool's minimum"
use "$MOVE" 'let hash = try await PrivateOnEthereum.send(token: token, amount: value, to: to, balanceToBalance: balanceToBalance == true)' "a private send on Ethereum ignores the token or the recipient's private account"
use "$ETH" 'let spend = balanceToBalance ? try await engine.prepareTransfer(tokenId: token, amount: hex, to: to)' "balance to balance is not a transfer inside the pool"
use "$ETH" 'return PrivateMoney.hasViewingKey(answer)' "a recipient's private account is not read off the keystore"
awk '/static func hasPrivateAccount\(/,/^    }$/' "$ETH" | grep -q 'return nil' || { echo "✗ an unanswered keystore read is taken for no private account (it would pay out publicly)"; exit 1; }
awk '/    func run\(\) async \{/,/^    }$/' "$MOVE" | grep -q 'guard balanceToBalance != nil else {' || { echo "✗ a private send runs without knowing where it goes"; exit 1; }
use "$MPRIV" 'if move.balanceToBalance == true {' "the line does not say a send goes balance to balance"
use "$ENGJS" "recipientDiscoveryData: { evmAddress: getAddress(recipient.toLowerCase()) } });" "the engine's transfer finds the recipient some other way than the keystore"
! grep -q 'allowOutOfBandFallback' "$ENGJS" || { echo "✗ the engine falls back to secrets the app would have to deliver"; exit 1; }
use "$BUNDLE" 'sharesForUnderlying' "the shipped bundle cannot transfer on a yield pool — rebuild with tools/privacy-pools-engine/build.mjs"
awk '/static func transact\(_ items:/,/^    }$/' "$CHAIN" > "$TMPF"
ride=$(grep -n 'switch await Self.rideVerdict(ride, check: { extra in' "$TMPF" | cut -d: -f1)
rreq=$(grep -n 'a.calls += extra' "$TMPF" | cut -d: -f1)
rop=$(grep -n 'let outcome = try await operate(' "$TMPF" | cut -d: -f1)
[[ -n "$ride" && -n "$rreq" && -n "$rop" && "$ride" -lt "$rreq" && "$rreq" -lt "$rop" ]] || { echo "✗ round-ups riding an operation are signed before the whole is simulated"; exit 1; }
# The review of 2026-10-26, finding 5: a ride that does not check out is
# DROPPED and the send goes alone (never `throw`, never `require` on the ride).
awk '/switch await Self.rideVerdict\(ride, check:/,/^        }$/' "$TMPF" | grep -qE 'throw|try require' && { echo "✗ a failing round-up ride refuses the whole send"; exit 1; }
grep -q 'rode: rode)' "$TMPF" || { echo "✗ a dropped ride still reads as ridden"; exit 1; }
awk '/static func rideVerdict\(_ ride:/,/^    }$/' "$CHAIN" | grep -q 'let verdict = RoundUps.rideVerdict(written: true, checked: checked)' || { echo "✗ the ride's verdict is not RoundUps.rideVerdict's"; exit 1; }
grep -q 'let kept = ride.isEmpty ? await Prepared.take(' "$TMPF" || { echo "✗ a riding deposit signs the preview's operation without it"; exit 1; }
use "$SENT" 'try await Self.spend(batch, on: net, account: account, roundUp: buy, ride: ride?.calls ?? [], reason: reason,' "round-ups into private no longer ride the Face ID operation"
use "$SENT" 'RoundUps.setPrivateSaved(RoundUps.savedAfter(roundUp, bought: moved), on: net.chainId)' "round-ups that did not ride are emptied"
use "$SENT" 'guard !privateRoundUps, !RoundUps.setting.movesPrivately, RoundUps.carriesBuy(roundUpAct),' "private round-ups also buy a token"
use "$ETH" 'guard d.tx.to.lowercased() == pool.router.lowercased(), d.share.lowercased() == pool.share.lowercased(),' "round-ups ride a deposit to something other than ppUSDC's router"
awk '/static func schedule\(\)/,/^    }$/' "$WATCH" | grep -q '#if DEBUG' && { echo "✗ the background watch is scheduled in DEBUG builds only"; exit 1; }
awk '/private static func handle\(/,/^    }$/' "$WATCH" | grep -q '#if DEBUG' && { echo "✗ the background watch's pass runs in DEBUG builds only"; exit 1; }
awk '/static func restoreNotes\(\)/,/^    }$/' "$WATCH" | grep -q 'if await findNotes(of: root, on: network) { PrivateRootKey.markFound(root) }' || { echo "✗ a new phone does not find its notes"; exit 1; }
awk '/static func findNotes\(of root: String/,/^    }$/' "$WATCH" | grep -q 'try await PrivateOnEthereum.open(root, reason: nil)' || { echo "✗ a new phone does not find its notes on Ethereum"; exit 1; }
use "$HOLD" 'Text("Restoring your private balance")' "a new phone's restore says nothing in Holdings"
use "$HOLD" 'if store.restoring {' "the restoring line is not tied to the restore"
grep -q 'store.beginRestore()' "$WATCH" && grep -q 'store.beginRestore()' "$FRESHM" || { echo "✗ a restore does not mark itself"; exit 1; }
! grep -q 'ProgressView' "$HOLD" || { echo "✗ Holdings draws a spinner for private money"; exit 1; }
rm -f "$TMPF"
echo "  ok   Ethereum, every gap: fresh addresses sign their own deposit, USDC, balance to balance, round-ups ride, the watch, restoring"
# No lime (prd §1561, user: "why not the one we already use our pink"):
# private money is marked in the app's pink, and the token is gone.
! grep -rq 'privateMark' Casberi/Casberi || { echo "✗ private money has a colour of its own again"; exit 1; }
use "$MPRIV" 'DSToggleRow(title: Text("Private"), isOn: $isOn)' "the Private switch is tinted apart from every other switch"
echo "  ok   private money counts once: in the total and the box, never in Tokens; marked in the app's pink"

# ETHEREUM (prd §1563): your account sends, Face ID signs, and nothing is
# signed before it is simulated; the owner is your account; every deposit
# earns (the token's own yield pool and router, at most the budget); Take it
# back is the ragequit FROM your account (the pool lets only the owner) with
# the zap after it; a relayed send asks for the device owner; the row's
# rate is read live; the DEBUG test sender is never used; no step hides
# behind DEBUG (the kill switch is the one way off); every mainnet move was
# run against mainnet in simulation, with five mutations caught.
TMP0=$(mktemp /tmp/private-money-chain.XXXXXX)
ETH="Casberi/Casberi/Model/PrivateOnEthereum.swift"
YIELD="Casberi/Casberi/Model/PrivateYield.swift"
CHAIN="Casberi/Casberi/Model/YourAccountChain.swift"
SIMREC="tools/privacy-pools-engine/mainnet-sim.json"
for f in "$ETH" "$YIELD" "$CHAIN" "$SIMREC"; do [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }; done
! grep -q '#if DEBUG' "$ETH" "$YIELD" || { echo "✗ a mainnet step is DEBUG-only (it must ship; the kill switch is the way off)"; exit 1; }
! grep -q 'PrivacyTestnetSender\|TestnetTx' "$ETH" || { echo "✗ the DEBUG test sender reaches mainnet"; exit 1; }
use "$ETH" 'static var owner: String? { YourAccountKey.address }' "the owner on Ethereum is no longer your account"
use "$ETH" '_ = try await PrivacyEngine.shared.open(seed: seed, owner: owner, network: network)' "the private account no longer opens with your account as its owner"
use "$ETH" 'guard PrivateMainnet.on else { throw PrivacyNetwork.Refusal.notServed(network.chainId) }' "Ethereum opens with the kill switch off"
use "$ETH" 'guard tx.to.lowercased() == network.keystore.lowercased() else { throw Failure.notOwner }' "the registration may call something other than the keystore"
use "$ETH" 'guard d.tx.to.lowercased() == pool.router.lowercased(), d.share.lowercased() == pool.share.lowercased(),' "a deposit may go somewhere other than its token's yield router"
use "$ETH" 'carried <= most else { throw Failure.noPool }' "a deposit may carry more than its budget"
use "$ETH" 'guard quit.recipient.lowercased() == owner.lowercased() else { throw Failure.notOwner }' "a ragequit paying someone other than your account is signed"
use "$ETH" 'reason: String = String(localized: "Send from your private balance")) async throws -> String {' "a relayed send no longer asks for the device owner"
awk '/static func send\(token: String/,/^    }$/' "$ETH" | grep -q 'try await open(account, reason: reason)' || { echo "✗ a relayed send opens without asking for the device owner"; exit 1; }
[[ $(grep -c 'try await YourAccountChain.privateCalls(' "$ETH") -ge 2 ]] || { echo "✗ a deposit or Take it back no longer goes through your account"; exit 1; }
awk '/static func privateCalls\(/,/^    }$/' "$CHAIN" > "$TMP0"
grep -q 'throw Failure(message: String(localized: "\\(net.name) could not check this, so nothing was signed"))' "$TMP0" || { echo "✗ a private call no node would simulate is signed"; exit 1; }
sim=$(grep -n 'let simulated = await check(net, account: account' "$TMP0" | cut -d: -f1)
req=$(grep -n 'try require(simulated, on: net, swaps: false)' "$TMP0" | cut -d: -f1)
op=$(grep -n 'let outcome = try await operate(' "$TMP0" | cut -d: -f1)
[[ -n "$sim" && -n "$req" && -n "$op" && "$sim" -lt "$req" && "$req" -lt "$op" ]] || { echo "✗ a private call is signed before its simulation is required to land"; exit 1; }
use "$HOLD" 'case .held: (nil, DS.textSecondary, PrivateMoneyStore.shared.yieldLine(row) ?? PrivateMoney.network(row.chainId), DS.textSecondary)' "a private row no longer says its rate"
use "$HOLD" 'await store.readYield()' "Holdings no longer reads the rate live"
! grep -q 'apys\[.*\] = [0-9]' "$STORE" || { echo "✗ a rate is written in, not read"; exit 1; }
use "$TAKE" 'let (hash, figure, pending) = try await PrivateOnEthereum.takeBack(note)' "Take it back on Ethereum is not your account's"
grep -qF 'router: "0x68b3465833fb72a70ecdf485e0e4c7bd8665fc45",' Casberi/Casberi/Model/YourAccountSwap.swift \
    || { echo "✗ Swap's Ethereum SwapRouter02 is no longer the one Take it back unwraps through"; exit 1; }
python3 -I - "$SIMREC" <<'PY' || { echo "✗ the mainnet simulation record is not nine landed moves from a real Safe proxy"; exit 1; }
import json, sys
r = json.load(open(sys.argv[1]))
s = r["scenarios"]
assert r.get("mutation") is None
assert all(s[k]["ok"] for k in ("eth", "usdc", "ragequit", "withdraw", "fresh", "transfer", "usdcsend", "freshusdc", "roundups")), s
f = s["fresh"]
assert int(f["paid"]) > int(f["threshold"]) == int(f["minUnderlying"]) + int(f["reserve"]), "the fresh deposit was not planned from the minimum and the gas"
assert int(f["dust"]) >= 0 and f["validatedGas"] <= 1250000, "the fresh address could not pay its gas"
assert s["transfer"]["refusedUnregistered"] == "RecipientViewingKeyUnregistered" and int(s["transfer"]["sharesToB"]) > 0, "balance to balance"
assert int(s["usdcsend"]["received"]) >= int(s["usdcsend"]["amount"]), "private USDC paid out"
assert int(s["freshusdc"]["gasPaidWei"]) >= int(s["freshusdc"]["needWei"]), "private ETH paid the fresh address's gas"
assert all(g <= 1250000 for g in s["freshusdc"]["gas"]), "the fresh address's USDC moves fit their gas"
assert int(s["roundups"]["batch"]) >= int(s["roundups"]["minUnderlying"]), "round-ups moved under the pool's minimum"
assert int(s["ragequit"]["ethBack"]) >= int(s["eth"]["spentWei"]) * 999 // 1000, "Take it back returns the deposit"
assert int(s["withdraw"]["received"]) == int(s["withdraw"]["amount"]), "the recipient gets the amount"
assert s["withdraw"]["processor"].lower() == "0x77613d670bb9fd48a9898d0eac8ebf21b566f960", "the router is the withdrawal's processor"
# The review of 2026-10-26: the account is a real SafeL2 1.4.1 proxy, each move
# checked as the app checks it and run as the operation; Take it back unwraps
# through SwapRouter02; ppETH's router refunded into the cold proxy.
a = r["account"]
assert "proxy" in a["kind"] and a["singleton"].lower() == "0x29fcb43b46531bca003ddc8fcb67ffe91900c762" and a["threshold"] == 1, "the account is not the app's Safe proxy"
calls = s["ragequit"]["calls"]
assert any(c.endswith("0xa9059cbb") and c.startswith("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2") for c in calls), "Take it back's WETH does not go to the router"
assert any(c == "0x68b3465833fb72a70ecdf485e0e4c7bd8665fc45 0x49404b7c" for c in calls), "Take it back is not unwrapped by the router"
assert not any(c.endswith("0x2e1a7d4d") for c in calls), "Take it back calls WETH's own withdraw"
assert int(s["eth"]["refundWei"]) > 0, "ppETH's refund into the proxy is unproven"
assert s["roundups"].get("refusedRideDroppedSendLands") is True, "a refused ride is not shown dropped with the send landing alone"
assert s["withdraw"].get("relayedAfterAnotherOpen") is True, "a relay after another account opened is unproven"
PY
rm -f "$TMP0"
echo "  ok   Ethereum: your account sends what was simulated, owns and takes back; every deposit earns; the rate read live"

TMP=$(mktemp -d /tmp/private-money-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
enum DS { static let device = "Casberi" }
var failures = 0
func check(_ ok: Bool, _ what: String) { if !ok { print("  ✗ \(what)"); failures += 1 } }
typealias P = PrivateMoney

// The ASP's answer.
func asp(_ s: String) -> P.Status? { P.status(asp: Data(s.utf8)) }
check(asp(#"{"status":"pending"}"#) == .waiting, "pending is waiting")
check(asp(#"{"status":"unknown"}"#) == .waiting, "unknown is waiting (not indexed yet)")
check(asp(#"{"status":"approved","timestamp":1}"#) == .approved, "approved")
check(asp(#"{"status":"rejected"}"#) == .rejected, "rejected")
check(asp(#"{"status":"poi_required"}"#) == .needsProof, "poi_required needs proof")
check(asp(#"{"status":"teapot"}"#) == nil && asp("<html>") == nil && asp("{}") == nil, "anything else changes nothing")
check(P.statusURL(aspUrl: "https://api-dev.0xbow.io", labelHash: "1926704")?.absoluteString == "https://api-dev.0xbow.io/labels/1926704/status",
      "the status URL carries the hash")
check(P.statusURL(aspUrl: "https://api-dev.0xbow.io", labelHash: "0x1a2b") == nil, "a hex label is never asked")
check(P.statusURL(aspUrl: "https://api-dev.0xbow.io", labelHash: "12/../x") == nil, "a path is never asked")

// Rows.
let t0 = Date(timeIntervalSince1970: 1_000_000), t1 = t0.addingTimeInterval(60)
func note(_ c: String, _ amount: String, _ s: P.Status, _ at: Date = t0, _ sym: String = "ETH") -> P.Note {
    .init(commitment: c, label: "0x1", labelHash: "1", symbol: sym, amount: amount, decimals: 18, chainId: 11155111, tx: "0x", at: at, status: s)
}
let notes = [note("a", "1000000000000000", .approved), note("b", "3000000000000000", .approved),
             note("c", "1000000000000000", .waiting, t1), note("d", "500000000000000", .needsProof, t0),
             note("e", "2000000000000000", .rejected, t0.addingTimeInterval(-10)), note("f", "7", .approved, t0, "USDC"),
             note("g", "500000000000000", .waiting, t0)]
let rows = P.rows(notes)
check(rows.map(\.id) == ["0:ETH:11155111", "0:USDC:11155111", "1:ETH:11155111", "2:ETH:11155111"], "private first, then waiting, then refused, A–Z within (\(rows.map(\.id)))")
check(rows.first?.amount == "4000000000000000", "a token's private notes are summed")
check(rows[2].amount == "1500000000000000" && rows[2].since == t0, "a waiting row sums its notes and dates from the oldest")
check(rows[3].amount == "2500000000000000", "poi_required is not approved either: drawn with the refused (prd §1561)")
check(rows[0].since == nil, "a private row has no since")
check(rows[0].title == "ETH, private" && rows[2].title == "ETH, moving in" && rows[3].title == "ETH, not approved", "the rows' names")
check(P.rows([note("z", "0", .approved), note("y", "x", .approved)]).isEmpty, "a zero or unreadable amount draws nothing")
check(P.anyWaiting(notes) && !P.anyWaiting([note("a", "1", .approved)]), "waiting is asked again, approved is not")
check(P.anyWaiting([note("p", "1", .needsProof)]) && !P.anyWaiting([note("r", "1", .rejected)]), "poi_required is asked again, rejected is not")

// Needs you (prd §1561): every deposit not approved, refused first, oldest
// first; Take it back on a refusal, and on a deposit waiting past a week.
let now0 = t1.addingTimeInterval(3600)
let asks = P.asks(notes, now: now0)
check(asks.map(\.id) == ["e", "d", "g", "c"], "refused first, then waiting, oldest first (\(asks.map(\.id)))")
check(asks.map(\.title) == ["0.002 ETH not approved", "0.0005 ETH not approved", "0.0005 ETH waiting for approval", "0.001 ETH waiting for approval"],
      "the rows' words (\(asks.map(\.title)))")
check(asks.filter(\.canTakeBack).map(\.id) == ["e", "d"], "only a refusal is taken back within the week")
check(P.asks(notes, now: t0.addingTimeInterval(8 * 86_400)).filter(\.canTakeBack).map(\.id) == ["e", "d", "g", "c"],
      "a deposit waiting past a week is not offered back")
check(P.asks(notes, now: t0.addingTimeInterval(6 * 86_400)).filter(\.canTakeBack).count == 2, "a week is a week")
check(P.asks([note("a", "1", .approved)], now: now0).isEmpty, "an approved deposit still needs you")
check(P.asks([note("z", "0", .rejected)], now: now0).isEmpty, "an empty note needs you")
var utc = Calendar(identifier: .gregorian)
utc.timeZone = TimeZone(identifier: "UTC")!
let at = Date(timeIntervalSince1970: 1_793_024_040)  // 2026-10-26 14:14 UTC
func since(_ now: Date) -> String {
    P.since(at, now: now, calendar: utc, locale: Locale(identifier: "en_US")).replacingOccurrences(of: "\u{202F}", with: " ")
}
check(since(at.addingTimeInterval(3 * 3600)) == "Since 2:14 PM", "today's wait says its time (\(since(at.addingTimeInterval(3 * 3600))))")
check(since(at.addingTimeInterval(86_400)) == "Since Oct 26", "an older wait says its day (\(since(at.addingTimeInterval(86_400))))")
check(P.takenBackTitle(figure: "0.0001 ETH", to: "...DeBb") == "0.0001 ETH back to ...DeBb", "a taken-back deposit's Activity row, with no verb")
check(P.roundUpsTitle(figure: "0.00012 ETH") == "0.00012 ETH round-ups to private", "round-ups moved in, with no verb")
check(P.held(notes, symbol: "ETH") == Decimal(string: "4000000000000000"), "held counts approved notes only")

// In the Wallet's number (prd §1554): approved notes on a network with value, once.
func onChain(_ n: P.Note, _ chain: Int) -> P.Note {
    .init(commitment: n.commitment, label: n.label, labelHash: n.labelHash, symbol: n.symbol, amount: n.amount, decimals: n.decimals,
          chainId: chain, tx: n.tx, at: n.at, status: n.status)
}
let mainnet = notes.map { onChain($0, 1) }
let prices = ["eth": 2000.0, "usdc": 1.0]
check(abs(P.worthUSD(mainnet, prices: prices) - 8) < 1e-9, "approved mainnet notes are worth their price (\(P.worthUSD(mainnet, prices: prices)))")
check(P.worthUSD(notes, prices: prices) == 0, "Sepolia's notes count nothing")
check(P.worthUSD([onChain(note("w", "1000000000000000", .waiting), 1)], prices: prices) == 0, "a deposit waiting for approval counts nothing yet")
check(P.worthUSD(mainnet, prices: ["usdc": 1]) < 1e-9, "a token with no price counts nothing")
check(P.rows(mainnet).first.map { P.rowUSD($0, prices: prices) } == 8, "a mainnet row's dollars")
check(rows.first.map { P.rowUSD($0, prices: prices) } == .some(nil), "a Sepolia row states its quantity")
check(P.rows([note("a", "1", .approved), onChain(note("b", "1", .approved), 1)]).count == 2, "one row per network")
check(P.network(11155111) == "Sepolia" && P.network(1) == "Ethereum", "the row's network")

// Sending from it (prd §1554).
let details = #"{"assets":[{"address":"0xEeee","ticker":"ETH","fixedFeeAmount":"21000","feeBPS":"10"},{"ticker":"USDC","fixedFeeAmount":"21000"}]}"#
let terms = P.relayerTerms(Data(details.utf8))
check(terms == P.RelayerTerms(feeBPS: 10, fixed: "21000"), "the relayer's ETH terms (\(String(describing: terms)))")
check(P.relayerTerms(Data("{}".utf8)) == nil && P.relayerTerms(Data("<html>".utf8)) == nil, "no terms, no fee")
check(terms.map { P.relayFee("50000000000000", terms: $0) } == "50000021000", "10 bps of 0.00005 ETH plus the fixed part (the trial's 0.00000005)")
check(terms.map { P.relayFee("1", terms: $0) } == "21001", "a share is rounded up, never to nothing")
check(P.spendable(notes, chainId: 11155111) == "4000000000000000", "only approved notes are spendable")
check(P.spendable(notes, chainId: 1) == "0", "another network's notes are not")
check(P.isAddress("0xEB3e3961008952348445513e418ad6F43C23ca9a") && !P.isAddress("0xEB3e") && !P.isAddress("vitalik.eth"), "an address is 0x and forty hex digits")
check(P.decimal(hex: "0x38d7ea4c68000") == "1000000000000000" && P.decimal(hex: "0x0") == "0" && P.decimal(hex: "12") == "0", "hex to decimal")
check(P.activityTitle(figure: "0.001 ETH", to: nil) == "0.001 ETH to your private balance", "moving in, with no verb")
check(P.activityTitle(figure: "0.001 ETH", to: "...ca9a") == "0.001 ETH to ...ca9a", "a private send, with no verb")
check(P.isActivity("private:0xab") && !P.isActivity("privacypools:dep:1") && !P.isActivity(nil), "an Activity row is its own ref")

// Amounts.
check(P.figure("1000000000000000", decimals: 18, symbol: "ETH") == "0.001 ETH", "0.001 ETH (\(P.figure("1000000000000000", decimals: 18, symbol: "ETH")))")
check(P.baseUnits("0.001", decimals: 18) == "1000000000000000", "0.001 ETH in wei")
check(P.baseUnits("1", decimals: 18) == "1000000000000000000", "1 ETH in wei")
check(P.baseUnits("0.0000000000000000001", decimals: 18) == nil, "more places than the token has is refused")
check(P.baseUnits("0", decimals: 18) == nil && P.baseUnits("abc", decimals: 18) == nil && P.baseUnits("-1", decimals: 18) == nil, "nothing that is not a positive amount")
check(P.hex("1000000000000000") == "0x38d7ea4c68000", "wei to 0x-hex")
check(P.hex("0") == "0x0" && P.hex("255") == "0xff" && P.hex("0x1") == nil, "0, 255 and a non-decimal")
check(P.reserve(gasPrice: "1000") == "4400000000", "the reserve is the budget at twice the price")
check(P.choices(balance: "6000000000000000", reserve: "1000000000000000") == ["0.00001", "0.00005", "0.0001", "0.0005", "0.001", "0.005"], "the ladder the balance allows after the reserve")
check(P.choices(balance: "1000000000000000", reserve: "1000000000000000").isEmpty, "nothing when the reserve takes it all")

// The testnet transaction, against viem.
let data70 = "0x" + String(repeating: "ab", count: 70)
let tx = TestnetTx.Tx(chainId: 11155111, nonce: "0x7", maxPriorityFeePerGas: "0xf4240", maxFeePerGas: "0x9502f900", gas: "0x10c8e0",
                      to: "0xEB3e3961008952348445513e418ad6F43C23ca9a", value: "0x38d7ea4c68000", data: data70)!
check(TestnetTx.hex(tx.unsigned) == "0x02f87883aa36a707830f4240849502f9008310c8e094eb3e3961008952348445513e418ad6f43c23ca9a87038d7ea4c68000b846" + String(repeating: "ab", count: 70) + "c0",
      "the unsigned payload is viem's")
check(TestnetTx.hex(tx.signingHash) == "0xdd20d0f8081f4084fbd091675298005740de494d2802dbc7224054e2407b54cf", "the signing hash is viem's")
let r1 = [UInt8(0)] + [UInt8](repeating: 0x11, count: 31), s1 = [UInt8](repeating: 0x22, count: 32)
check(tx.signed(yParity: 1, r: r1, s: s1).map(TestnetTx.hex) == "0x02f8ba83aa36a707830f4240849502f9008310c8e094eb3e3961008952348445513e418ad6f43c23ca9a87038d7ea4c68000b846" + String(repeating: "ab", count: 70) + "c0019f" + String(repeating: "11", count: 31) + "a0" + String(repeating: "22", count: 32),
      "signed, parity 1, a leading zero byte dropped from r")
let tx0 = TestnetTx.Tx(chainId: 11155111, nonce: "0x0", maxPriorityFeePerGas: "0xf4240", maxFeePerGas: "0x9502f900", gas: "0x10c8e0",
                       to: "0xEB3e3961008952348445513e418ad6F43C23ca9a", value: "0x0", data: "0x")!
check(TestnetTx.hex(tx0.unsigned) == "0x02ea83aa36a780830f4240849502f9008310c8e094eb3e3961008952348445513e418ad6f43c23ca9a8080c0", "zero nonce, value and data")
check(tx0.signed(yParity: 0, r: [UInt8](repeating: 0x33, count: 32), s: [0, 0] + [UInt8](repeating: 0x44, count: 30)).map(TestnetTx.hex)
      == "0x02f86b83aa36a780830f4240849502f9008310c8e094eb3e3961008952348445513e418ad6f43c23ca9a8080c080a0" + String(repeating: "33", count: 32) + "9e" + String(repeating: "44", count: 30),
      "signed, parity 0")
check(tx.signed(yParity: 2, r: r1, s: s1) == nil && tx.signed(yParity: 0, r: [1], s: s1) == nil, "a bad signature is refused")
for chain in [1, 8453, 4663, 84532] {
    check(TestnetTx.Tx(chainId: chain, nonce: "0x0", maxPriorityFeePerGas: "0x1", maxFeePerGas: "0x1", gas: "0x1",
                       to: "0xEB3e3961008952348445513e418ad6F43C23ca9a", value: "0x0", data: "0x") == nil, "no transaction on chain \(chain)")
}
check(TestnetTx.Tx(chainId: 11155111, nonce: "0x0", maxPriorityFeePerGas: "0x1", maxFeePerGas: "0x1", gas: "0x1",
                   to: "0xEB3e", value: "0x0", data: "0x") == nil, "a short address is refused")

// Where the engine's node requests go.
typealias W = PrivacyEngineWire
let node = "https://ethereum-sepolia-rpc.publicnode.com", logs = PrivacyNetwork.sepoliaLogsUrl
func route(_ url: String, _ body: String?) -> String { W.routed(URL(string: url)!, body: body, rpcUrl: node, logsUrl: logs).absoluteString }
check(route(node, #"{"jsonrpc":"2.0","id":1,"method":"eth_getLogs","params":[]}"#) == logs, "a log read goes to the node that keeps them")
check(route(node, #"[{"method":"eth_blockNumber"},{"method":"eth_getLogs"}]"#) == logs, "a batch with a log read goes there too")
check(route(node, #"{"method":"eth_call"}"#) == node, "anything else stays on the network's node")
check(route("https://api-dev.0xbow.io/x", #"{"method":"eth_getLogs"}"#) == "https://api-dev.0xbow.io/x", "another host is never routed")
check(route(node, nil) == node && route(node, "not json") == node, "no body stays")
check(W.missesHead(#"{"error":{"message":"block range extends beyond current head block"}}"#), "past the head goes back")
check(!W.missesHead(#"{"result":[]}"#), "an answer stays")
check(W.throttled(status: 429, body: "") && W.throttled(status: 200, body: #"{"error":{"message":"Too Many Requests"}}"#), "a 429 is waited out")
check(!W.throttled(status: 200, body: #"{"result":"0x1"}"#), "an answer is not throttled")
check(PrivacyNetwork.sepolia.fromBlock == 10_932_354, "Sepolia scans from the keystore's first block")
check(PrivacyNetwork.sepolia.hosts.contains("sepolia.gateway.tenderly.co"), "the logs node is the network's host")
let engine = NetworkReach.endpoint(forService: "Privacy Pools engine")
check(engine.map { W.allows(URL(string: logs + "/")!, declared: $0.hosts) } == true, "the logs node is declared for the engine")
check(engine?.refusesTor.contains("sepolia.gateway.tenderly.co") == true, "the logs node is listed as refusing Tor")

// Receive to a fresh address (prd §1560).
typealias F = FreshAddress
let root = (0..<32).map { UInt8($0) }
func hexs(_ b: [UInt8]?) -> String { b.map { $0.map { String(format: "%02x", $0) }.joined() } ?? "nil" }
// Node's HMAC-SHA256 over the same message; viem names the addresses
// 0xA9DF8B0f78AfBE9bddfC89984C49EBC6b7ce3073, 0xA95f85e7…5077, 0xF25a6861…84FC.
check(hexs(F.key(root: root, index: 0)) == "509aaeef20ef6d071e0970e8bc2e4a3f11292a99d990439c44958ceaff1f26c5", "address 0's key is Node's")
check(hexs(F.key(root: root, index: 1)) == "7c947401fc56e518b433bdf6f07dff2cee21e0e132f89706d31b1b3c1ab71971", "address 1's key is Node's")
check(hexs(F.key(root: root, index: 7)) == "d23263a05a3d4b6a6ff04393f339c335ce30bd47cfab6cd39dcaab040ecbfd57", "address 7's key is Node's")
check(F.key(root: Array(root.prefix(31)), index: 0) == nil, "a root that is not 32 bytes makes nothing")
check(!F.isScalar(F.curveOrder) && !F.isScalar([UInt8](repeating: 0, count: 32)) && !F.isScalar([1]), "n, zero and a short key are not keys")
check(F.isScalar(Array(F.curveOrder.dropLast()) + [0x40]) && F.isScalar([UInt8](repeating: 0, count: 31) + [1]), "n − 1 and 1 are keys")
func entry(_ i: UInt32, _ s: F.State = .waiting) -> F.Entry { .init(index: i, address: "0x\(i)", made: t0, state: s) }
check(F.nextIndex([]) == 0 && F.nextIndex([entry(0), entry(7), entry(1)]) == 8, "the next address is one past the highest, never reused")
let book = (0..<12).map { entry(UInt32($0)) } + [entry(12, .moving(amount: "5"))]
check(F.watched(book).map(\.index) == [11, 10, 9, 8, 7, 6, 5, 4], "the newest eight are watched, a move under way is not (\(F.watched(book).map(\.index)))")
// The plan: what arrived, less the most its gas can cost, less the vetting fee.
let p0 = F.plan(balance: "100000000000000", maxFee: "42", vettingBPS: 0, minimum: "1")
check(p0 == F.Plan(value: "99999947500000", msgValue: "99999947500000", reserve: "52500000"), "0.0001 ETH at 42 wei a gas (\(String(describing: p0)))")
let p1 = F.plan(balance: "100000000000000", maxFee: "42", vettingBPS: 100, minimum: "1")
check(p1 == F.Plan(value: "99009849009900", msgValue: "99999947499999", reserve: "52500000"), "a 1% vetting fee fits under what arrived (\(String(describing: p1)))")
check(F.plan(balance: "104999999", maxFee: "42", vettingBPS: 0, minimum: "1") == nil, "gas costing more than what moves moves nothing")
check(F.plan(balance: "105000000", maxFee: "42", vettingBPS: 0, minimum: "1")?.value == "52500000", "gas costing what moves moves it")
check(F.plan(balance: "100000000000000", maxFee: "42", vettingBPS: 0, minimum: "100000000000000") == nil, "below the pool's minimum moves nothing")
check(F.plan(balance: "100", maxFee: "42", vettingBPS: 0, minimum: "1") == nil, "less than the gas moves nothing")
check(F.plan(balance: "100000000000000", maxFee: "42", vettingBPS: 10_001, minimum: "1") == nil, "a fee past 100% is refused")
if let p0 {
    check(F.matches(to: "0xEB3e3961008952348445513e418ad6F43C23ca9a", value: "0x5af30d5929e0", plan: p0,
                    entrypoint: "0xeb3e3961008952348445513e418ad6f43c23ca9a"), "the prepared deposit is the planned one")
    check(!F.matches(to: "0xEB3e3961008952348445513e418ad6F43C23ca9a", value: "0x5af3107a4000", plan: p0,
                     entrypoint: "0xEB3e3961008952348445513e418ad6F43C23ca9a"), "a deposit carrying another value is refused")
    check(!F.matches(to: "0x09b94d3127019298757A6ceeB7911922085f7C01", value: "0x5af30d5929e0", plan: p0,
                     entrypoint: "0xEB3e3961008952348445513e418ad6F43C23ca9a"), "a deposit to anything but the Entrypoint is refused")
    check(F.decide(entry(0), balance: "100000000000000", plan: p0) == .move(p0), "paid enough, it moves")
}
check(F.decide(entry(0), balance: "104999999", plan: nil) == .tooLittle, "paid too little, it says so")
check(F.decide(entry(0, .moved(amount: "1", tx: "0x")), balance: "12000000", plan: nil) == .nothing, "a move's dust never says too little")
check(F.decide(entry(0), balance: "0", plan: nil) == .nothing, "nothing arrived")
// The pool's terms, read off the Entrypoint (Sepolia's answers, 2026-10-26).
check(F.assetsCall(token: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE") == "0xf11b8188000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee", "assets(ETH)'s call")
check(F.assetsCall(token: "0xEeee") == nil, "no call for a short address")
let w = { (n: String) in String(repeating: "0", count: 64 - n.count) + n }
check(F.assetConfig("0x" + w("1") + w("1") + w("0") + String(repeating: "f", count: 64)) == F.AssetConfig(enabled: true, minimum: "1", vettingBPS: 0), "ETH on Sepolia: on, 1 wei, no fee")
check(F.assetConfig("0x" + w("1") + w("1") + w("64") + String(repeating: "f", count: 64))?.vettingBPS == 100, "USDC on Sepolia: 1%")
check(F.assetConfig("0x" + w("0") + w("1") + w("0") + w("0"))?.enabled == false, "an asset switched off")
check(F.assetConfig("0x" + w("1") + w("1")) == nil && F.assetConfig("nope") == nil, "a short answer is no terms")
check(TestnetTx.fees(gasPrice: 21, tip: 0) == (1, 43) && TestnetTx.fees(gasPrice: 21, tip: 5) == (5, 47), "the fee cap leaves the price room to double")

// One root (prd §1562), every derivation against Node's crypto.hkdfSync
// (salt "casberi private money root v1"; scratch vec.mjs in the PRD entry).
typealias R = PrivateRoot
check(hexs(R.derive(root, .poolSeed)) == "87ded0d942e85e131c31c1f6c7c5d4940c55f1c421194b782e0ae77a2a33cc0c", "the pool seed is Node's HKDF")
check(hexs(R.derive(root, .freshAddresses)) == "ebfe5265a0746feed62a0421eeaf78063178350a8505bc35c12fda60f8961a41", "the fresh root is Node's HKDF")
check(hexs(R.ownerKey(root)) == "b7bcb8cdd801a5cf9a96288b02f1a97e23092fe06a0a1de4db0d513d4a41c437", "the owner's key is Node's HKDF, counter 0")
check(R.id(root) == "1690d3193e46c034", "the root's public id is Node's SHA-256")
let freshRoot = R.derive(root, .freshAddresses) ?? []
check(hexs(F.key(root: freshRoot, index: 0)) == "366ef074fb49a96e1924bf68ff0d069cf717d8317a84c7c2ca5480f3398ca327", "fresh address 0 under the root is Node's")
check(hexs(F.key(root: freshRoot, index: 1)) == "5801f562b6383af432e1b3ffef89f239f4bfe7411b9eeb1a1a479810684209d2", "fresh address 1 under the root is Node's")
check(Set(R.Purpose.allCases.compactMap { R.derive(root, $0).map(hexs) }).count == R.Purpose.allCases.count, "each use takes its own bytes")
check(R.derive(Array(root.prefix(31)), .poolSeed) == nil && R.id([1, 2]) == nil && R.ownerKey([]) == nil, "a root that is not 32 bytes derives nothing")
check(R.derive(root, .poolSeed) != root && R.id(root) != hexs(Array(root.prefix(8))), "nothing derived is the root")
// Each root counts its own addresses; an entry's id names its root.
let mixed = [entry(0), entry(1), F.Entry(index: 0, address: "0xa", made: t0, state: .waiting, root: "r1"),
             F.Entry(index: 4, address: "0xb", made: t0, state: .waiting, root: "r1")]
check(F.nextIndex(mixed) == 2 && F.nextIndex(mixed, root: "r1") == 5 && F.nextIndex(mixed, root: "r2") == 0, "each root counts its own addresses")
check(Set(mixed.map(\.id)).count == 4 && mixed[2].id == "r1:0" && mixed[0].id == "legacy:0", "an entry's id names its root")
// The walk back: twenty unused past the last used, then done.
func seen(_ i: UInt32, _ b: String = "0", _ n: Int = 0) -> R.Seen { .init(index: i, balance: b, nonce: n) }
check(R.nextBatch([]) == 0...19, "a new phone asks 0 to 19 first")
check(R.nextBatch((0...19).map { seen($0) }) == nil, "twenty unused: done")
let walk1 = (0...19).map { $0 == 3 ? seen(3, "0", 1) : seen($0) }
check(R.nextBatch(walk1) == 20...23, "a used address at 3 asks to 23 (\(String(describing: R.nextBatch(walk1))))")
check(R.nextBatch(walk1 + (20...23).map { seen($0) }) == nil, "and then is done")
check(R.nextBatch((0...19).map { $0 == 19 ? seen(19, "5") : seen($0) }) == 20...39, "a payment at 19 asks twenty more")
let book1 = R.restored((0...23).map { $0 == 3 ? seen(3, "37260729", 1) : $0 == 1 ? seen(1, "40000000000000") : seen($0) })
check(book1.map(\.index) == [0, 1, 2, 3, 4], "the book: every address to the last used, and one more (\(book1.map(\.index)))")
check(book1[1].state == .waiting, "paid and never moved: waiting, so the watch moves it")
check(book1[3].state == .moved(amount: "0", tx: ""), "moved before: its dust never says too little")
check(book1[4].state == .waiting && book1[0].state == .waiting, "the next never used is the one Receive shows")
check(R.restored((0...19).map { seen($0) }).map(\.index) == [0], "nothing used: address 0 alone")
check(seen(0, "1").used && seen(0, "0", 1).used && !seen(0).used, "used is paid or moved")
// The device-only account's money, moved in.
check(R.migrationAmount(spendable: "89999937500000", terms: P.measuredTerms) == "89909937541500", "the balance less the relayer's fee on all of it (\(String(describing: R.migrationAmount(spendable: "89999937500000", terms: P.measuredTerms))))")
check(R.migrationAmount(spendable: "42000", terms: P.measuredTerms) == nil, "a balance the fee would mostly eat stays")
check(R.migrationAmount(spendable: "0", terms: P.measuredTerms) == nil, "nothing, nothing")
// What needs you on Security.
check(R.backup(holdsPrivate: false, deviceOnlyHolds: true, iCloud: false) == .fine, "nothing private: no row")
check(R.backup(holdsPrivate: true, deviceOnlyHolds: true, iCloud: true) == .deviceOnly, "money on the device-only account: Back up")
check(R.backup(holdsPrivate: true, deviceOnlyHolds: false, iCloud: false) == .noICloud, "no iCloud account: on this phone only")
check(R.backup(holdsPrivate: true, deviceOnlyHolds: false, iCloud: true) == .fine, "under the root, on iCloud: no row")
// One send spends from one account.
var r1n = note("r", "5000000000000000", .approved); r1n.root = "r1"
let byAccount = P.spendableByAccount(notes + [r1n], chainId: 11155111)
check(byAccount.count == 2 && byAccount.first { $0.root == nil }?.amount == "4000000000000000"
      && byAccount.first { $0.root == "r1" }?.amount == "5000000000000000", "approved money by account (\(byAccount))")

// Ethereum earns (prd §1563): the rate, the worth, the line, Take it back's calls.
typealias Y = PrivateYield
let measured = Y.apy(liquidityRateRay: "12967460578352220962271503", feeBps: 2000)   // ppETH, read 2026-10-26
check(measured.map { abs($0 - 0.010442) < 0.00001 } == true, "Aave's 1.3052% less the share's 20% is 1.0442% (\(String(describing: measured)))")
check(Y.apy(liquidityRateRay: "36825976994563936832332265", feeBps: 2000).map { abs($0 - 0.030010) < 0.00001 } == true, "ppUSDC: 3.0010%")
check(Y.apy(liquidityRateRay: "12967460578352220962271503", feeBps: 0).map { abs($0 - 0.013052) < 0.00001 } == true, "no fee: Aave's own")
check(Y.apy(liquidityRateRay: "x", feeBps: 2000) == nil && Y.apy(liquidityRateRay: "1", feeBps: 10_001) == nil
      && Y.apy(liquidityRateRay: "2000000000000000000000000000", feeBps: 0) == nil, "an unreadable rate, a fee past 100% or a rate past 100% is no rate")
check(Y.line(apy: measured) == "1.0% on Aave", "the line: \(String(describing: Y.line(apy: measured)))")
check(Y.line(apy: nil) == nil && Y.line(apy: 0) == nil, "no rate, no line")
check(Y.liquidityRate(reserveData: "0x" + String(repeating: "0", count: 64) + String(repeating: "0", count: 63) + "1"
      + String(repeating: "0", count: 63) + "7") == "7", "the reserve's third word is the supply rate")
check(Y.reserveDataCall(underlying: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2") == "0x35ea6a75000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", "getReserveData(WETH)")
// Worth: mainnet-sim's own deposit, at the rate read that day.
check(Y.underlying(shares: "9987480271160279", exchangeRate: "1001252552889022892", shareDecimals: 18) == "9999990118427979",
      "0.009987 ppETH is 0.00999999 ETH (\(String(describing: Y.underlying(shares: "9987480271160279", exchangeRate: "1001252552889022892", shareDecimals: 18))))")
check(Y.underlying(shares: "19907525330476718936", exchangeRate: "1004644", shareDecimals: 18) == "19999975", "19.9 ppUSDC is 19.999975 USDC")
let ppETH = PrivacyNetwork.ethereum.yield[0], ppUSDC = PrivacyNetwork.ethereum.yield[1]
var yn = note("y", "9987480271160279", .approved); yn = P.Note(commitment: "y", label: "0x1", labelHash: "1", symbol: "ETH", amount: "9987480271160279",
    decimals: 18, chainId: 1, tx: "0x", at: t0, status: .approved, share: ppETH.share)
let un = P.Note(commitment: "u", label: "0x2", labelHash: "2", symbol: "USDC", amount: "19907525330476718936", decimals: 18, chainId: 1,
    tx: "0x", at: t0, status: .approved, share: ppUSDC.share)
let rates = [ppETH.share.lowercased(): "1001252552889022892", ppUSDC.share.lowercased(): "1004644"]
check(P.worth(yn, rates: rates) == ("9999990118427979", 18), "a ppETH note is worth its ETH at the rate")
check(P.worth(un, rates: rates) == ("19999975", 6), "a ppUSDC note is worth its USDC, at USDC's decimals")
check(P.worth(un, rates: [:]) == ("19907525", 6), "before the rate: the shares as USDC, never more than it is worth")
check(P.worth(yn, rates: [:]) == ("9987480271160279", 18), "before the rate: the ETH shares themselves")
let yrows = P.rows([yn, un], rates: rates)
check(yrows.map(\.symbol) == ["ETH", "USDC"] && yrows[1].amount == "19999975" && yrows[1].decimals == 6, "rows draw what the shares are worth")
check(P.spendable([yn], chainId: 1, rates: rates) == "9999990118427979", "spendable is the token, yield included")
check(abs(P.worthUSD([un], prices: ["usdc": 1], rates: rates) - 19.999975) < 0.000001, "the total counts the worth")
// Take it back on a yield pool: approve the zap, redeem to the token, unwrap ETH.
let tb = Y.takeBackCalls(pool: ppETH, shares: "9987480271160279", owner: "0x746dA2D4849B90571be2974454b3b712a5eb9d3F", worth: "9999990118427979")
check(tb?.count == 4 && tb?[0].to == ppETH.share && tb?[0].data.hasPrefix("0x095ea7b3") == true && tb?[0].data.contains(ppETH.zap.dropFirst(2).lowercased()) == true,
      "first the share approves the zap")
check(tb?[1].to == ppETH.zap && tb?[1].data.hasPrefix("0x7aa6a9fd") == true && tb?[1].data.hasSuffix("746da2d4849b90571be2974454b3b712a5eb9d3f") == true,
      "then the zap redeems to the account")
// The review of 2026-10-26, finding 1: WETH's own `withdraw` pays a cold Safe
// proxy 2,300 gas and the check refuses it, so the WETH goes through the
// pinned SwapRouter02 (§1559): `transfer(router, worth)`, `unwrapWETH9(worth, owner)`.
check(Y.unwrapRouter.lowercased() == "0x68b3465833fb72a70ecdf485e0e4c7bd8665fc45", "the unwrap router is not Ethereum's SwapRouter02")
check(tb?[2].to == ppETH.underlying && tb?[2].data == "0xa9059cbb" + String(repeating: "0", count: 24) + "68b3465833fb72a70ecdf485e0e4c7bd8665fc45" + Y.uint("9999990118427979")!,
      "then the WETH goes to the router, exactly what the shares were worth")
check(tb?[3].to == Y.unwrapRouter && tb?[3].data == "0x49404b7c" + Y.uint("9999990118427979")! + String(repeating: "0", count: 24) + "746da2d4849b90571be2974454b3b712a5eb9d3f",
      "then the router unwraps it to the account with a full-gas call")
check(tb?.contains { $0.data.hasPrefix("0x2e1a7d4d") } == false, "Take it back calls WETH's own withdraw, which a cold Safe proxy cannot take")
check(Y.takeBackCalls(pool: ppETH, shares: "1", owner: "0x746dA2D4849B90571be2974454b3b712a5eb9d3F", worth: "0") == nil, "a worthless unwrap is written")
check(Y.takeBackCalls(pool: ppUSDC, shares: "1", owner: "0x746dA2D4849B90571be2974454b3b712a5eb9d3F", worth: "1")?.count == 2, "USDC needs no unwrap")
check(Y.uint("255") == String(repeating: "0", count: 62) + "ff" && Y.uint("-1") == nil && Y.uint("") == nil, "one word")
// What Move offers on Ethereum: from the pool's smallest deposit up.
check(P.choices(balance: "100000000000000000", reserve: "1000000000000000", ladder: P.mainnetLadder, minimum: "4000000000000000")
      == ["0.005", "0.01", "0.025", "0.05"], "Ethereum's amounts start at the pool's smallest deposit")

// ── prd §1567 ──────────────────────────────────────────────────────────────
// A fresh address's own transaction on Ethereum, against viem 2.45.3: the
// ppETH router's deposit (unsigned, its hash, signed with parity 1) and a
// USDC approval of ppUSDC's router.
let eth = PrivacyNetwork.ethereum, ppRouter = ppETH.router
let depData = "0x31c09bb4" + String(repeating: "ab", count: 66)
let ftx = FreshTx.Tx(network: eth, nonce: "0x3", maxPriorityFeePerGas: "0x143", maxFeePerGas: "0x4983e9a", gas: "0x1312d0",
                     to: ppRouter, value: "0xef8f7d83b18d4", data: depData)
check(ftx.map { TestnetTx.hex($0.unsigned) } == "0x02f87401038201438404983e9a831312d09477613d670bb9fd48a9898d0eac8ebf21b566f960870ef8f7d83b18d4b846" + String(depData.dropFirst(2)) + "c0",
      "a fresh deposit's payload on Ethereum is viem's")
check(ftx.map { TestnetTx.hex($0.signingHash) } == "0x4e32c41c3db6491bee9ada43eee180cb6b0d7e2d2915f10db685a7ad51f65c83", "its signing hash is viem's")
check(ftx?.signed(yParity: 1, r: r1, s: s1).map(TestnetTx.hex) == "0x02f8b601038201438404983e9a831312d09477613d670bb9fd48a9898d0eac8ebf21b566f960870ef8f7d83b18d4b846" + String(depData.dropFirst(2)) + "c0019f" + String(repeating: "11", count: 31) + "a0" + String(repeating: "22", count: 32),
      "signed, it is viem's")
let usdcApprove = FreshTx.approval(pool: ppUSDC, amount: "25000000")
check(usdcApprove?.to == ppUSDC.underlying && usdcApprove.flatMap { FreshTx.Tx(network: eth, nonce: "0x0", maxPriorityFeePerGas: "0x1", maxFeePerGas: "0x4983e9a", gas: "0x13880", to: $0.to, value: "0x0", data: $0.data) }.map { TestnetTx.hex($0.unsigned) }
      == "0x02f8690180018404983e9a8301388094a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4880b844095ea7b3000000000000000000000000e76e793d776c1e207ad7a7fa7c57d27420d8511000000000000000000000000000000000000000000000000000000000017d7840c0",
      "a fresh address's USDC approval of ppUSDC's router is viem's")
// Nothing else can be made: no payment, no other call, no other chain.
func made(_ to: String, _ data: String, _ value: String, _ net: PrivacyNetwork = eth) -> Bool {
    FreshTx.Tx(network: net, nonce: "0x0", maxPriorityFeePerGas: "0x1", maxFeePerGas: "0x2", gas: "0x5208", to: to, value: value, data: data) != nil
}
check(!made("0x4a1a2b3c4d5e6f708192a3b4c5d6e7f809102030", "0x", "0x1"), "a fresh key pays someone")
check(!made(ppRouter, depData, "0x1", PrivacyNetwork.sepolia), "a fresh key signs on a test network through FreshTx")
var testnetWithPools = PrivacyNetwork.sepolia
testnetWithPools.yield = eth.yield
check(!made(ppRouter, depData, "0x1", testnetWithPools), "a test network's chain id is signed for by FreshTx")
check(!made(ppRouter, "0x12345678" + String(repeating: "ab", count: 66), "0x1"), "a fresh key calls the router's other functions")
check(!made(ppRouter, depData, "0x0"), "a native deposit carries no ETH")
check(!made(ppUSDC.router, "0xc63148e8" + String(repeating: "ab", count: 66), "0x1") && made(ppUSDC.router, "0xc63148e8" + String(repeating: "ab", count: 66), "0x0"),
      "a token deposit carries ETH, or the token router's deposit is refused")
let otherSpender = "0x095ea7b3" + String(repeating: "0", count: 24) + "4a1a2b3c4d5e6f708192a3b4c5d6e7f809102030" + String(repeating: "0", count: 63) + "1"
check(!made(ppUSDC.underlying, otherSpender, "0x0"), "a fresh key approves anyone but its token's router")
check(usdcApprove.map { !made($0.to, $0.data, "0x1") } == true, "an approval carries ETH")
check(!made(ppUSDC.underlying, "0xa9059cbb" + String(repeating: "0", count: 128), "0x0"), "a fresh key transfers USDC away")
check(!made(ppETH.share, depData, "0x1"), "a fresh key calls the share")
// "Too little to move", computed from the pool and today's fees (the mainnet
// simulation's numbers: 0.004 ppETH at 1.001254 and 0.048 gwei, cap 0.096).
let floorETH = F.minimumBudget(minimumShares: "4000000000000000", exchangeRate: "1001254019271464000", shareDecimals: 18)
check(floorETH == "4005020082101944", "ppETH's smallest budget: the minimum at the rate, the router's headroom (\(String(describing: floorETH)))")
check(F.minimumBudget(minimumShares: "10000000000000000000", exchangeRate: "1004644", shareDecimals: 18) == "10046461", "ppUSDC's: about $10.05")
check(F.tooLittleBelow(minimumBudget: "4005020082101944", maxFee: "95972657") == "4124985903351944", "too little below 0.004125 ETH that day")
check(F.yieldPlan(balance: "4124985903351943", maxFee: "95972657", minimumBudget: "4005020082101944") == nil, "a wei under the threshold moves")
check(F.yieldPlan(balance: "4331231026453544", maxFee: "95972657", minimumBudget: "4005020082101944")
      == F.YieldPlan(budget: "4211265205203544", reserve: "119965821250000"), "the budget is what arrived less the gas at the cap (the simulation's)")
check(F.yieldPlan(balance: "200000000000000", maxFee: "95972657", minimumBudget: "1") == nil, "gas costing more than what moves moves it")
check(F.matchesYield(to: ppRouter, value: "0xef61f969c7258", approvals: 0, budget: "4211265205203544", pool: ppETH), "the planned deposit matches")
check(!F.matchesYield(to: ppRouter, value: "0xef61f969c7258", approvals: 0, budget: "4211265205203543", pool: ppETH), "a deposit carrying more than the budget matches")
check(!F.matchesYield(to: ppUSDC.router, value: "0x1", approvals: 0, budget: "10", pool: ppETH), "a deposit to another router matches")
check(!F.matchesYield(to: ppRouter, value: "0x1", approvals: 1, budget: "10", pool: ppETH), "an ETH deposit with an approval matches")
check(!F.matchesYield(to: ppUSDC.router, value: "0x1", approvals: 1, budget: "10", pool: ppUSDC), "a USDC deposit carrying ETH matches")
let gasNeed = F.tokenGas(ethHeld: "0", maxFee: "95972657")
check(gasNeed?.need == "127643633810000" && gasNeed?.shortfall == "127643633810000", "a USDC move's gas: the approval and the deposit at the cap")
check(F.tokenGas(ethHeld: "200000000000000", maxFee: "95972657")?.shortfall == "0", "ETH already there pays it")
check(F.tokenGas(ethHeld: "27643633810000", maxFee: "95972657")?.shortfall == "100000000000000", "private ETH pays only the shortfall")
// USDC's amounts start at the pool's minimum.
check(P.choices(balance: "25000000", reserve: "0", decimals: 6, ladder: P.usdcLadder, minimum: "10046461") == ["20"],
      "10 USDC is under ppUSDC's minimum; 20 of 25 is offered")
// Balance to balance: the keystore's viewing key.
check(P.viewingKeyCall(owner: "0x38db9f602274AFB7c9c87E2942C43c0781A3BC82") == "0x03bb850a00000000000000000000000038db9f602274afb7c9c87e2942c43c0781a3bc82",
      "viewingKeys(owner)'s call")
check(P.hasViewingKey("0xe53c39d8d674804fdef03da07227977ef56bccba73635f619e0be3f553a76f5c"), "B's registered key on Sepolia is a private account")
check(!P.hasViewingKey("0x" + String(repeating: "0", count: 64)) && !P.hasViewingKey("0x") && !P.hasViewingKey(nil) && !P.hasViewingKey("0x12"),
      "a zero, empty or unreadable key is a private account")


// ── The review of 2026-10-26 ───────────────────────────────────────────────
// Findings 2 and 3: an operation of your account sent and not seen. Landed by
// its receipt or its note in the pool; failed by a failed receipt, or — for a
// note — the nonce taken and the pool silent past the grace; a buy whose nonce
// was taken counts as landed (never bought twice); a nonce still free waits,
// however long, and an unanswered read is never a verdict.
let grace = P.pendingGrace
check(P.pendingVerdict(receipt: true, nonceMoved: true, inPool: false, carriesNote: true, age: 0) == .landed, "a successful receipt is not landed")
check(P.pendingVerdict(receipt: false, nonceMoved: true, inPool: false, carriesNote: true, age: 0) == .failed, "a failed receipt is not failed")
check(P.pendingVerdict(receipt: nil, nonceMoved: nil, inPool: true, carriesNote: true, age: 0) == .landed, "a note found in the pool is not landed")
check(P.pendingVerdict(receipt: nil, nonceMoved: false, inPool: false, carriesNote: true, age: 30 * 86_400) == .waiting,
      "an operation whose nonce is still free is called failed by its age (it may still land)")
check(P.pendingVerdict(receipt: nil, nonceMoved: nil, inPool: false, carriesNote: false, age: 30 * 86_400) == .waiting, "an unanswered read is a verdict")
check(P.pendingVerdict(receipt: nil, nonceMoved: true, inPool: false, carriesNote: true, age: grace - 1) == .waiting,
      "a note is called failed before the pool had its time to show it")
check(P.pendingVerdict(receipt: nil, nonceMoved: true, inPool: false, carriesNote: true, age: grace + 1) == .failed,
      "a note never in the pool long after its nonce was taken still waits (its round-ups never come back)")
check(P.pendingVerdict(receipt: nil, nonceMoved: true, inPool: false, carriesNote: false, age: grace + 1) == .landed,
      "a buy that may have landed is put back on the count (bought twice)")
check(grace >= 10 * 60, "the pool gets under ten minutes to show a note")
// Findings 2 and 6: a fresh address's transaction out. Landed or reverted by
// its receipt; waiting while the node knows it or its nonce is taken; dropped
// only when unknown past its time with the nonce free; unknown is no verdict.
let da = F.droppedAfter
check(F.sentVerdict(receipt: "0x1", known: nil, nonceTaken: nil, age: 0, after: da) == .landed
      && F.sentVerdict(receipt: "0x0", known: nil, nonceTaken: nil, age: 0, after: da) == .reverted, "a receipt is read wrong")
check(F.sentVerdict(receipt: nil, known: nil, nonceTaken: nil, age: 1e9, after: da) == .waiting, "an unanswered read drops a transaction (sent twice)")
check(F.sentVerdict(receipt: nil, known: true, nonceTaken: false, age: 1e9, after: da) == .waiting, "a transaction the node holds is dropped (sent twice)")
check(F.sentVerdict(receipt: nil, known: false, nonceTaken: true, age: 1e9, after: da) == .waiting, "a mined transaction whose receipt is late is dropped")
check(F.sentVerdict(receipt: nil, known: false, nonceTaken: false, age: da - 1, after: da) == .waiting
      && F.sentVerdict(receipt: nil, known: false, nonceTaken: false, age: da + 1, after: da) == .dropped, "a lost transaction is dropped too soon, or never")
check(F.relayDroppedAfter >= 86_400 && da >= 3600, "a relayed gas payment is asked for again within a day, or a lost one within the hour")
// A transaction out is looked at however many newer addresses there are.
let made0 = Date(timeIntervalSince1970: 1_800_000_000)
var outBook: [F.Entry] = (0..<10).map { F.Entry(index: UInt32($0 + 1), address: "0x\($0)", made: made0.addingTimeInterval(Double($0 + 1)), state: .waiting) }
outBook.append(F.Entry(index: 0, address: "0xsent", made: made0, state: .sent(amount: "1", tx: "0xab", step: .deposit, nonce: "0", at: made0)))
check(F.watched(outBook).contains { $0.address == "0xsent" }, "a transaction out on an older address is never asked about again")
check(F.watched(outBook).count == F.watchCap + 1, "the look asks about more than the newest few and those out")
// Finding 4: ETH and USDC apart, ETH first; USDC dust never hides ETH.
check(F.lookOrder(eth: "4300000000000000", usdc: "1", usdcPool: true) == .both, "USDC dust hides the ETH beside it")
check(F.lookOrder(eth: "0", usdc: "25000000", usdcPool: true) == .usdc && F.lookOrder(eth: "1", usdc: "0", usdcPool: true) == .eth
      && F.lookOrder(eth: "0", usdc: "0", usdcPool: true) == .nothing && F.lookOrder(eth: "1", usdc: "5", usdcPool: false) == .eth,
      "a look asks about a token the address does not hold, or one with no pool")

if failures > 0 { print("✗ \(failures) failure(s)"); exit(1) }
print("ok")
SWIFT

compile_and_run() {
    swiftc -Onone "$1" "$2" "$3" "$4" "$5" "${6:-$YIELD}" "${7:-$FTX}" "$KECCAK" "$ART" "$PINS" "$REACH" "$TMP/main.swift" -o "$TMP/run" 2>"$TMP/err" \
        || { head -20 "$TMP/err"; return 2; }
    "$TMP/run"
}
compile_and_run "$PM" "$TX" "$WIRE" "$FRESH" "$ROOT" || { echo "✗ Move to private's rules fail their own self-test"; exit 1; }
echo "  ok   the ASP's answer, the rows, amounts, viem's bytes and the node routes"

mutate() {
    local name="$1" file="$2" perl_expr="$3"
    cp "$file" "$TMP/mut.swift"
    perl -0pi -e "$perl_expr" "$TMP/mut.swift"
    if cmp -s "$file" "$TMP/mut.swift"; then echo "✗ mutation did not apply: $name"; exit 1; fi
    local pm="$PM" tx="$TX" wire="$WIRE" fresh="$FRESH" root="$ROOT" yld="$YIELD" ftx="$FTX"
    case "$file" in
        "$FTX") ftx="$TMP/mut.swift" ;;
        "$PM") pm="$TMP/mut.swift" ;;
        "$TX") tx="$TMP/mut.swift" ;;
        "$WIRE") wire="$TMP/mut.swift" ;;
        "$FRESH") fresh="$TMP/mut.swift" ;;
        "$ROOT") root="$TMP/mut.swift" ;;
        "$YIELD") yld="$TMP/mut.swift" ;;
    esac
    local ok
    ok=$(compile_and_run "$pm" "$tx" "$wire" "$fresh" "$root" "$yld" "$ftx" >/dev/null 2>&1 && echo y || echo n)
    [[ "$ok" == n ]] || { echo "✗ SURVIVED  $name"; exit 1; }
    echo "  ok   catches  $name"
}
mutate "unknown no longer waits" "$PM" 's/case "pending", "unknown": return \.waiting/case "pending": return .waiting/'
mutate "the ASP is asked by any label" "$PM" 's/guard labelHash\.range\(of: #"\^\[0-9\]\{1,80\}\$"#/guard labelHash.range(of: #".+"#/'
mutate "a waiting row dates from its newest note" "$PM" 's/min\(had\.since, note\.at\)/max(had.since, note.at)/'
mutate "a refused deposit is not taken back" "$PM" 's/return Ask\(note: note, kind: \.refused, canTakeBack: true\)/return Ask(note: note, kind: .refused, canTakeBack: false)/'
mutate "a deposit waiting a month is never offered back" "$PM" 's/canTakeBack: now\.timeIntervalSince\(note\.at\) > takeBackAfter/canTakeBack: false/'
mutate "an approved deposit still needs you" "$PM" 's/case \.approved: return nil/case .approved: return Ask(note: note, kind: .waiting, canTakeBack: false)/'
mutate "poi_required waits in Needs you" "$PM" 's/case \.rejected, \.needsProof:\n                return Ask\(note: note, kind: \.refused/case .rejected, .needsProof:\n                return Ask(note: note, kind: .waiting/'
mutate "an older wait says only its time" "$PM" 's/let shown = calendar\.isDate\(at, inSameDayAs: now\)/let shown = true/'
mutate "poi_required is never asked again" "$PM" 's/status == \.waiting \|\| status == \.needsProof/status == .waiting/'
mutate "a waiting note is spendable" "$PM" 's/notes\.filter \{ \$0\.status == \.approved && \$0\.chainId == chainId/notes.filter { $0.chainId == chainId/'
mutate "the relayer's share rounds down" "$PM" 's/NSDecimalRound\(&up, &share, 0, \.up\)/NSDecimalRound(\&up, \&share, 0, .down)/'
mutate "a waiting deposit counts in the total" "$PM" 's/guard note\.status == \.approved, !testnets/guard !testnets/'
mutate "test money counts in the total" "$PM" 's/guard note\.status == \.approved, !testnets\.contains\(note\.chainId\),/guard note.status == .approved,/'
mutate "two networks share a row" "$PM" 's/let key = "\\\(k\.rawValue\):\\\(note\.symbol\):\\\(note\.chainId\)"/let key = "\\(k.rawValue):\\(note.symbol)"/'
mutate "more places than the token has" "$PM" 's/guard fraction\.count <= decimals else \{ return nil \}\n//'
mutate "the reserve forgets the price can double" "$PM" 's/plain\(gasBudget \* price \* 2\)/plain(gasBudget * price)/'
mutate "any chain gets a transaction" "$TX" 's/guard TestnetTx\.testnets\.contains\(chainId\) else \{ return nil \}\n//'
mutate "the long-length head" "$TX" 's/if length < 56 \{/if length < 256 {/'
mutate "parity 0 is a zero byte" "$TX" 's/\.bytes\(yParity == 0 \? \[\] : \[1\]\)/.bytes([UInt8(yParity)])/'
mutate "r keeps its leading zero" "$TX" 's/\.bytes\(TestnetTx\.stripped\(r\)\)/.bytes(r)/'
mutate "every request goes to the logs node" "$WIRE" 's/rpcMethods\(body\)\.contains\("eth_getLogs"\)/!rpcMethods(body).isEmpty/'
mutate "past the head is an answer" "$WIRE" 's/body\.range\(of: "beyond current head", options: \.caseInsensitive\) != nil/body.isEmpty/'
mutate "the fee cap forgets the price can double" "$TX" 's/max\(gasPrice \* 2, t\) \+ t/max(gasPrice, t) + t/'
mutate "the fresh key ignores its index" "$FRESH" 's/let message = domain \+ bigEndian\(index\) \+ bigEndian\(counter\)/let message = domain + bigEndian(counter)/'
mutate "a fresh key may be n or more" "$FRESH" 's/ && k\.lexicographicallyPrecedes\(curveOrder\)//'
mutate "a fresh address is reused" "$FRESH" 's/\}\.map\(\\\.index\)\.max\(\)\.map \{ \$0 \+ 1 \}/}.map(\\.index).max()/'
mutate "a move under way is asked again" "$FRESH" 's/entries\.filter \{ if case \.moving = \$0\.state \{ false \} else \{ true \} \}/entries/'
mutate "the gas is not taken out of what arrived" "$FRESH" 's/let spare = have - reserve/let spare = have/'
mutate "the vetting fee is not left room for" "$FRESH" 's/Decimal\(10_000 \+ vettingBPS\)/Decimal(10_000)/'
mutate "gas may cost more than what moves" "$FRESH" 's/value >= max\(floor, reserve, 1\)/value >= max(floor, 1)/'
mutate "a move's dust says too little" "$FRESH" 's/        default: return \.nothing\n        \}\n    \}/        default: return .tooLittle\n        }\n    }/'
mutate "the prepared deposit is not checked against the plan" "$FRESH" 's/ && PrivateMoney\.decimal\(hex: value\) == plan\.msgValue//'
mutate "the vetting fee is read from the wrong word" "$FRESH" 's/guard let bps = Int\(word\(2\)\)/guard let bps = Int(word(1))/'
mutate "the root's salt changes" "$ROOT" 's/static let salt = Array\("casberi private money root v1"/static let salt = Array("casberi private money root v2"/'
mutate "the pool seed and the fresh root share their bytes" "$ROOT" 's/case freshAddresses = "fresh addresses"/case freshAddresses = "privacy pools seed "/'
mutate "the owner's counter is not in its info" "$ROOT" 's/if let counter \{ info \+=/if let counter, counter > 99 { info +=/'
mutate "the owner takes the fresh root's bytes" "$ROOT" 's/derive\(root, \.testnetOwner, counter: counter\)/derive(root, .freshAddresses)/'
mutate "the id is the root's own bytes" "$ROOT" 's/let digest = SHA256\.hash\(data: Array\("casberi private root id v1"\.utf8\) \+ root\)/let digest = root/'
mutate "the walk stops one short of the gap" "$ROOT" 's/let end = lastUsed\.map \{ \$0 \+ gap \} \?\? \(gap - 1\)/let end = lastUsed.map { $0 + gap - 1 } ?? (gap - 1)/'
mutate "a moved address is waiting again" "$ROOT" 's/guard let s = byIndex\[i\], s\.nonce > 0 else/guard let s = byIndex[i], s.nonce > 99 else/'
mutate "Receive shows a used address" "$ROOT" 's/        out\.append\(\(last \+ 1, \.waiting\)\)\n//'
mutate "the migration forgets the relayer's fee" "$ROOT" 's/let amount = held - fee\n/let amount = held\n/'
mutate "money on the device-only account needs nothing" "$ROOT" 's/if deviceOnlyHolds \{ return \.deviceOnly \}/if deviceOnlyHolds, !iCloud { return .deviceOnly }/'
mutate "one send spends two accounts" "$PM" 's/spendable\(notes\.filter \{ \$0\.root == r \}, chainId: chainId, symbol: symbol, rates: rates\)/spendable(notes, chainId: chainId, symbol: symbol, rates: rates)/'
mutate "each root shares one count" "$FRESH" 's/entries\.filter \{ \$0\.root == root \}\.map/entries.map/'
mutate "the rate forgets the share's fee" "$YIELD" 's/return gross \* \(1 - Double\(feeBps\) \/ 10_000\)/return gross/'
mutate "the worth forgets the share's decimals" "$YIELD" 's/for _ in 0\.\.<shareDecimals \{ scale \*= 10 \}/for _ in 0..<(shareDecimals - 1) { scale *= 10 }/'
mutate "Take it back leaves WETH" "$YIELD" 's/            calls\.append\(\(unwrapRouter, "0x49404b7c" \+ worthWord \+ ownerWord\)\)\n//'
mutate "Take it back unwraps by WETH's own withdraw (finding 1)" "$YIELD" 's/calls\.append\(\(pool\.underlying, "0xa9059cbb" \+ routerWord \+ worthWord\)\)\n            calls\.append\(\(unwrapRouter, "0x49404b7c" \+ worthWord \+ ownerWord\)\)/calls.append((pool.underlying, "0x2e1a7d4d" + worthWord))/'
mutate "the unwrap goes to the zap, not the router" "$YIELD" 's/let routerWord = String\(repeating: "0", count: 24\) \+ unwrapRouter/let routerWord = String(repeating: "0", count: 24) + pool.zap/'
mutate "USDC's shares count as 18-place USDC" "$PM" 's/pool\.underlyingDecimals < pool\.shareDecimals,/pool.underlyingDecimals > 99,/'
mutate "Ethereum offers less than the pool takes" "$PM" 's/return units \+ keep <= have && units >= floor/return units + keep <= have/'
mutate "a rate past 100% is a rate" "$YIELD" 's/guard apr < 1 else \{ return nil \}//'
# prd §1567
mutate "a fresh key may make any transaction" "$FTX" 's/guard FreshTx\.allowed\(to: to, data: data, value: value, network: network\) else \{ return nil \}//'
mutate "a fresh key approves any spender" "$FTX" 's/return spender == String\(repeating: "0", count: 24\) \+ pool\.router\.dropFirst\(2\)\.lowercased\(\)/return true/'
mutate "a fresh key signs on a test network" "$FTX" 's/guard !network\.isTest, PrivateMoney/guard PrivateMoney/'
mutate "a native deposit may carry nothing" "$FTX" 's/d\.hasPrefix\(nativeDeposit\) && !carried\.isEmpty/d.hasPrefix(nativeDeposit)/'
mutate "the fresh gas is not kept back on Ethereum" "$FRESH" 's/let budget = have - reserve\n/let budget = have\n/'
mutate "too little forgets the pool's minimum" "$FRESH" 's/guard budget >= max\(floor, reserve, 1\) else/guard budget >= max(reserve, 1) else/'
mutate "the minimum forgets the rate" "$FRESH" 's/var worth = shares \* rate \/ scale, up = Decimal\(\)/var worth = shares, up = Decimal()/'
mutate "a USDC move's gas forgets the approval" "$FRESH" 's/Decimal\(FreshTx\.approveGas \+ gasBudget\) \* fee/Decimal(gasBudget) * fee/'
mutate "a zero viewing key is a private account" "$PM" 's/ && body\.contains \{ \$0 != "0" \}//'
mutate "a deposit carrying more than its budget matches" "$FRESH" 's/approvals == 0 && carried <= most && carried > 0/approvals == 0 \&\& carried > 0/'
# The review of 2026-10-26, findings 2, 4 and 6: mutations of the pure rules.
mutate "a nonce still free fails an operation by its age (finding 2)" "$PM" 's/guard nonceMoved == true else \{ return \.waiting \}/guard nonceMoved == true || age > pendingGrace else { return .waiting }/'
mutate "a note is failed the moment its nonce is taken (finding 2)" "$PM" 's/return age > pendingGrace \? \.failed : \.waiting/return .failed/'
mutate "a buy that may have landed is put back (finding 3)" "$PM" 's/guard carriesNote else \{ return \.landed \}/guard carriesNote else { return .failed }/'
mutate "the pool's note is not proof of landing (finding 2)" "$PM" 's/if inPool \|\| receipt == true \{ return \.landed \}/if receipt == true { return .landed }/'
mutate "an unknown transaction is dropped at once (finding 2)" "$FRESH" 's/return age > after \? \.dropped : \.waiting/return .dropped/'
mutate "a transaction the node holds is dropped (finding 6)" "$FRESH" 's/if nonceTaken == true \|\| known != false \{ return \.waiting \}/if nonceTaken == true { return .waiting }/'
mutate "a transaction out on an older address is never asked about (finding 2)" "$FRESH" 's/return newest \+ open\.dropFirst\(watchCap\)\.filter\(\\\.isSent\)/return newest/'
mutate "USDC dust hides the ETH beside it (finding 4)" "$FRESH" 's/case \(true, true\): return \.both/case (true, true): return .usdc/'

# Finding 8: one flow at a time through the engine. `PrivacyEngineQueue`
# compiled whole and driven by three flows whose awaits interleave: each
# must see only its own open from its proof to its relay, a nested flow runs
# in place (no deadlock), and a flow that throws hands the engine on.
QUEUE="Casberi/Casberi/Model/PrivacyEngineQueue.swift"
[[ -f "$QUEUE" ]] || { echo "✗ $QUEUE not found"; exit 1; }
use "$ENGINE" 'guard Self.accountFree.contains(method) || PrivacyEngineQueue.holding else {' "the engine serves an account-bound call outside PrivacyEngine.exclusive"
use "$ENGINE" 'static let accountFree: Set<Wire.Method> = [.info, .close, .bench, .labelHash]' "the engine lets an account-bound method run outside the queue"
use "$ENGJS" 'prepared.set(h, { ...value, acct: account });' "a prepared handle no longer remembers the account it was made under"
use "$ENGJS" 'const s = await session(p.kind, p.acct);' "a relay goes through whichever account is open, not its own"
use "$ENGJS" 'const tx = await p.acct.relayer.relayWithdrawal(p.relayer, p.result.relayParams);' "a yield withdrawal is relayed through whichever account is open"
[[ $(grep -c 'prepared.clear();' "$ENGJS") -eq 1 ]] || { echo "✗ opening an account wipes another account's prepared handles (only close may)"; exit 1; }
use "$BUNDLE" '.acct.relayer.relayWithdrawal(' "the shipped bundle's handles are not keyed to their account — rebuild with tools/privacy-pools-engine/build.mjs"
for f in "$ETH" "Casberi/Casberi/Model/FreshReceive.swift" "$WATCH"; do
    grep -q 'PrivacyEngine.exclusive {' "$f" || { echo "✗ $f opens the engine outside the queue"; exit 1; }
done
mkdir -p "$TMP/q"; cat > "$TMP/q/main.swift" <<'SWIFT'
import Foundation
DispatchQueue.global().asyncAfter(deadline: .now() + 15) { print("  ✗ the engine queue deadlocked (a nested flow waits on itself)"); exit(1) }
@MainActor final class Page { var open: String?; var log: [String] = [] }
struct Boom: Error {}
@MainActor func test() async -> Int {
    var failures = 0
    func check(_ ok: Bool, _ what: String) { if !ok { print("  ✗ \(what)"); failures += 1 } }
    let q = PrivacyEngineQueue(), page = Page()
    func flow(_ name: String) async {
        await q.run {
            page.open = name; page.log.append("\(name) open")
            for _ in 0..<3 { await Task.yield(); try? await Task.sleep(nanoseconds: 1_000_000) }
            page.log.append("\(name) prove under \(page.open ?? "-")")
            await q.run { page.log.append("\(name) nested under \(page.open ?? "-")") }
            await Task.yield()
            page.log.append("\(name) relay under \(page.open ?? "-")")
        }
    }
    await withTaskGroup(of: Void.self) { group in
        for name in ["A", "B", "C"] { group.addTask { @MainActor in await flow(name) } }
    }
    for n in ["A", "B", "C"] {
        check(page.log.contains("\(n) prove under \(n)") && page.log.contains("\(n) relay under \(n)"),
              "flow \(n) proved or relayed under another flow's open account: \(page.log)")
        check(page.log.contains("\(n) nested under \(n)"), "a nested flow did not run in place")
        let mine = page.log.enumerated().filter { $0.element.hasPrefix("\(n) ") }.map(\.offset)
        check(mine.count == 4 && mine.last! - mine.first! == 3, "flow \(n)'s steps interleave with another's: \(page.log)")
    }
    check(!PrivacyEngineQueue.holding, "the queue's hold leaks out of run")
    do { try await q.run { throw Boom() } } catch {}
    var after = false
    await q.run { after = true }
    check(after, "a flow that threw kept the engine")
    return failures
}
let failures = await test()
if failures > 0 { exit(1) }
print("queue ok")
SWIFT
run_queue() { swiftc -Onone "$1" "$TMP/q/main.swift" -o "$TMP/queue" 2>"$TMP/queue-err" || { head -20 "$TMP/queue-err"; return 2; }; "$TMP/queue" >/dev/null 2>&1; }
swiftc -Onone "$QUEUE" "$TMP/q/main.swift" -o "$TMP/queue" 2>"$TMP/queue-err" || { head -20 "$TMP/queue-err"; echo "✗ PrivacyEngineQueue does not compile alone"; exit 1; }
"$TMP/queue" || { echo "✗ the engine queue lets flows swap the open account"; exit 1; }
echo "  ok   one flow at a time through the engine: three interleaved flows each keep their own account, a nested one runs in place"
qmutate() {
    local name="$1" perl_expr="$2"
    cp "$QUEUE" "$TMP/queue-mut.swift"
    perl -0pi -e "$perl_expr" "$TMP/queue-mut.swift"
    if cmp -s "$QUEUE" "$TMP/queue-mut.swift"; then echo "✗ mutation did not apply: $name"; exit 1; fi
    if run_queue "$TMP/queue-mut.swift"; then echo "✗ SURVIVED  $name"; exit 1; fi
    echo "  ok   catches  $name"
}
qmutate "a flow runs while another holds the engine (finding 8)" 's/        if busy \{\n            await withCheckedContinuation \{ waiters\.append\(\$0\) \}\n        \} else \{\n            busy = true\n        \}/        busy = true/'
qmutate "a nested flow waits on itself (finding 8)" 's/        if Self\.holding \{ return try await body\(\) \}\n//'
qmutate "a release forgets the next flow (finding 8)" 's/            waiters\.removeFirst\(\)\.resume\(\)/            busy = false; waiters.removeAll()/'
# The review's fixes in USE, not only in the rules (2026-10-26):
PEND="Casberi/Casberi/Model/PrivatePending.swift"
[[ -f "$PEND" ]] || { echo "✗ $PEND not found"; exit 1; }
# 2: a fresh transaction is kept before it goes and never failed by a wait;
# a `.sent` address is asked about before anything new is sent for it.
awk '/static func send\(to: String, data: String, value: String, index: UInt32/,/^    }$/' "$FSIGN" > "$TMP/fsend"
k=$(grep -n 'kept(hash, PrivateMoney.decimal(hex: nonce))' "$TMP/fsend" | cut -d: -f1)
b=$(grep -n '"eth_sendRawTransaction"' "$TMP/fsend" | cut -d: -f1)
[[ -n "$k" && -n "$b" && "$k" -lt "$b" ]] || { echo "✗ a fresh transaction is broadcast before it is kept (finding 2)"; exit 1; }
! grep -q 'waitFor' "$TMP/fsend" || { echo "✗ a fresh send waits, and its wait's end is a failure (finding 2)"; exit 1; }
awk '/    func check\(context: ModelContext, force: Bool = false\) async \{/,/^    }$/' "$FRESHM" > "$TMP/fcheck"
r=$(grep -n 'await resolveSent(entry,' "$TMP/fcheck" | cut -d: -f1)
g=$(grep -n '"eth_getBalance"' "$TMP/fcheck" | cut -d: -f1)
[[ -n "$r" && -n "$g" && "$r" -lt "$g" ]] || { echo "✗ an address with a transaction out is moved again before it is asked about (findings 2, 6)"; exit 1; }
use "$FRESHM" 'if try await FreshSigner.landed(hash, on: network) {' "a fresh deposit's wait decides its fate (finding 2)"
# 2: a deposit, a round-up ride and Take it back not seen in two minutes are kept and followed.
use "$ETH" 'if case .pending = sent.outcome, let id = followed.id {' "a deposit not seen in two minutes is not followed (finding 2)"
use "$ETH" 'tx: hash ?? "", at: Date(),' "a deposit that landed with no transaction named is not kept (finding 2)"
use "$SENT" 'PrivatePending.shared.add(.init(id: id, chainId: net.chainId, account: account, nonceKey: SafeABI.hex(followed.nonceKey),' "a round-up ride not seen in two minutes is not followed (findings 2, 3)"
use "$SENT" 'if moved, let ride { Self.landPrivateRoundUps(ride, tx: tx, context: context) }' "a ride that landed with no transaction named drops its note (finding 2)"
use "$CHAIN" 'if let followed = following {' "submit no longer names the operation it sent (findings 2, 3)"
# 2: every root's notes on a cadence: Holdings, Needs you, the background pass.
use "$HOLD" 'await PrivateWatch.findNotes(context: modelContext)' "Holdings no longer finds every root's notes on a cadence (finding 2)"
use "$HOLD" 'await PrivateWatch.findNotes(context: context)' "Needs you no longer finds every root's notes on a cadence (finding 2)"
use "$WATCH" 'if left() > 15 { await findNotes(context: context) }' "the background pass no longer finds every root's notes (finding 2)"
awk '/static func findNotes\(context: ModelContext\?, force: Bool = false\) async \{/,/^    }$/' "$WATCH" | grep -q 'await PrivatePending.shared.resolve(context: context)' \
    || { echo "✗ what was sent and not seen is never asked about (finding 2)"; exit 1; }
# 3: a ride on its way empties the count and reserves it; failed, the reserve comes back.
awk '/case \.pending:/,/case \.dryRun:/' "$SENT" | grep -q 'RoundUps.setPrivateSaved(RoundUps.savedAfter(roundUp, bought: true), on: net.chainId)' \
    || { echo "✗ a ride still on its way leaves the count whole: the next send rides it again (finding 3)"; exit 1; }
use "$SENT" 'reserved: RoundUps.reserve(roundUp), toPrivate: toPrivate))' "a ride on its way reserves nothing (finding 3)"
use "$PEND" 'RoundUps.setPrivateSaved(RoundUps.released(reserved, onto: RoundUps.privateSaved(on: op.chainId)), on: op.chainId)' "a failed ride's round-ups never come back (finding 3)"
# 6: the gas payment is kept before the relayer is asked.
awk '/private func lookToken\(/,/^    }$/' "$FRESHM" > "$TMP/ftoken"
sg=$(grep -n 'set(entry.id, .sent(amount: held, tx: "", step: .gas, nonce: nil, at: Date()), symbol: symbol)' "$TMP/ftoken" | cut -d: -f1)
rl=$(grep -n 'let tx = try await PrivateOnEthereum.send(token: PrivateMove.eth, amount: gas.shortfall' "$TMP/ftoken" | cut -d: -f1)
[[ -n "$sg" && -n "$rl" && "$sg" -lt "$rl" ]] || { echo "✗ a fresh address's gas is relayed before it is kept: it can be paid twice (finding 6)"; exit 1; }
! grep -q 'PrivateRPC.waitFor' "$TMP/ftoken" || { echo "✗ a gas payment's wait decides its fate (finding 6)"; exit 1; }
use "$FRESHM" 'if !(await allowanceCovers(pool, owner: entry.address, amount: most, network: network)) {' "an approval that landed is sent again (finding 2)"
# 4: ETH and USDC apart.
use "$FRESHM" 'switch FreshAddress.lookOrder(eth: balance, usdc: usdc, usdcPool: usdcPool != nil) {' "a fresh address's USDC still decides for its ETH (finding 4)"
# 7: a private target counts on Ethereum whatever is available, and rides only where it can move.
awk '/private var privateRoundUps: Bool \{/,/^    }$/' "$SENT" | grep -q 'PrivateMove.available\|owner != nil' && { echo "✗ a private target with private money unavailable falls back to a public buy (finding 7)"; exit 1; }
awk '/private var privateRide: String\? \{/,/^    }$/' "$SENT" | grep -q 'RoundUps.privateRoute(on: network.chainId, bySession: false) == .deposit,' \
    || { echo "✗ round-ups ride where private money is not available (finding 7)"; exit 1; }
echo "  ok   the review's fixes in use: kept before sent, followed past two minutes, reserved, the gas paid once, ETH apart from USDC, never public"
echo "  ok   74 mutations"
