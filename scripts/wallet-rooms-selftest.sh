#!/bin/zsh
# Casberi wallet-room self-test — the SHIPPED pure judgement behind the FIVE
# WALLET-RIDING feed-room heads (prd §349, 2026-08-10; Railgun added §350,
# Safe added §349's own amendment, both 2026-08-11):
#
#   Casberi/Casberi/Model/PeerRoom.swift
#   Casberi/Casberi/Model/PrivacyPoolsRoom.swift
#   Casberi/Casberi/Model/GnosisPayRoom.swift
#   Casberi/Casberi/Model/RailgunRoom.swift
#   Casberi/Casberi/Model/SafeRoom.swift
#
# All five are Foundation-only BY DESIGN, so all five are compiled WHOLE AND
# UNMODIFIED rather than extracted — the strongest form of "the harness ran the
# shipped logic". Everything that touches `Thing`/`SafeBridge` lives in the
# `…RoomSource.swift` half, which no harness can compile and which contains no
# judgement to test.
#
# WHY A HARNESS AND NOT A LIVE CHECK. These four seats ride the WATCHED
# WALLETS: there is no key to mint, no account to open, and nothing on this host
# can make a Peer fill settle, a 0xBow screener rule, a Gnosis Pay card get
# swiped, or a Railgun shield land. A room's numbers can only ever be checked by
# somebody who already has the history — and every failure mode here is a
# SILENT WRONG ANSWER that renders perfectly:
#
#   · every SALE counted as a purchase, because `peer:sell:` also starts
#     `peer:` — a card reporting that you only ever buy, on an account that
#     mostly sells
#   · a dormant room dated by a fall-through, whose timestamp records when we
#     LOOKED and not when anything happened
#   · a fill with no rail bucketed under an invented "Unknown" that then ranks
#     beside the real ones
#   · a deposit carrying no state tag reported as "in review", which is a claim
#     about the screener made with no evidence
#   · a cleared deposit counted twice — once as itself, once as its own alert
#   · one deposit stuck on proof-of-innocence ranked below forty that cleared
#   · EUR added to GBP and printed as one figure
#   · "up 400%" against a window the room was never watching
#   · a spend whose amount could not be read folded into a total as zero
#   · a shield with no readable token bucketed under an invented "Unknown"
#   · a token's shielded amount presented as complete when one shield in it
#     carried no readable amount at all
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

PEER="Casberi/Casberi/Model/PeerRoom.swift"
POOLS="Casberi/Casberi/Model/PrivacyPoolsRoom.swift"
GNOSIS="Casberi/Casberi/Model/GnosisPayRoom.swift"
RAILGUN="Casberi/Casberi/Model/RailgunRoom.swift"
SAFE="Casberi/Casberi/Model/SafeRoom.swift"
# The Privacy Pools room's SCOPE enum (prd §486) — Foundation-only for exactly
# this reason, so the rules behind its strip are compiled WHOLE beside the room
# they scope rather than reasoned about.
SECTION="Casberi/Casberi/Model/PrivacyPoolsSection.swift"
for f in "$PEER" "$POOLS" "$GNOSIS" "$RAILGUN" "$SAFE" "$SECTION"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

SRC_PEER="Casberi/Casberi/Model/PeerRoomSource.swift"
SRC_POOLS="Casberi/Casberi/Model/PrivacyPoolsRoomSource.swift"
SRC_GNOSIS="Casberi/Casberi/Model/GnosisPayRoomSource.swift"
SRC_RAILGUN="Casberi/Casberi/Model/RailgunRoomSource.swift"
SRC_SAFE="Casberi/Casberi/Model/SafeRoomSource.swift"
BR_PEER="Casberi/Casberi/Model/PeerBridge.swift"
BR_POOLS="Casberi/Casberi/Model/PrivacyPoolsBridge.swift"
BR_GNOSIS="Casberi/Casberi/Model/GnosisPayBridge.swift"
BR_RAILGUN="Casberi/Casberi/Model/RailgunBridge.swift"
CARD_PEER="Casberi/Casberi/Screens/PeerRoomCard.swift"
CARD_POOLS="Casberi/Casberi/Screens/PrivacyPoolsRoomCard.swift"
CARD_GNOSIS="Casberi/Casberi/Screens/GnosisPayRoomCard.swift"
CARD_RAILGUN="Casberi/Casberi/Screens/RailgunRoomCard.swift"
CARD_SAFE="Casberi/Casberi/Screens/SafeRoomCard.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
PROBES="Casberi/Casberi/Shell/ProbeHooks.swift"
DEMO="Casberi/Casberi/Model/DemoSeedAll.swift"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- drift guards -----------------------------------------------------------
# Wiring facts the compiled functions cannot prove about themselves. A perfect
# `ordered` is worthless if the card draws its own order, and a perfect
# `compose` is worthless if the head is never rendered or the bridge stops
# stamping the field it reads.

# THE BUG THIS PASS FIXED, made mechanical. §311 landed deposits under
# `privacypools:dep:` and had `retag` look them up under
# `privacypools:deposit:`, so the fetch matched nothing on any device, ever:
# every deposit stayed tagged `Pending` for life, cleared ones included.
# Invisible — the alert row still landed and still rained, and the only casualty
# was the tag nobody was reading yet. One constant now, and this guard is what
# keeps it one.
grep -q 'let ref = depositRefPrefix + label' "$BR_POOLS" \
  || { echo "✗ PrivacyPoolsBridge.retag no longer builds its ref from depositRefPrefix — the §311 tag can silently stop moving again"; exit 1; }
grep -q 'let ref = depositRefPrefix + (label ?? deposit.commitment)' "$BR_POOLS" \
  || { echo "✗ PrivacyPoolsBridge no longer LANDS deposits under depositRefPrefix — the constant no longer joins the two halves"; exit 1; }
grep -q 'static let depositRefPrefix = PrivacyPoolsRoom.depositPrefix' "$BR_POOLS" \
  || { echo "✗ the bridge's deposit prefix no longer comes from PrivacyPoolsRoom — the room could count deposits the bridge doesn't land"; exit 1; }

# The negative half of the same guard, and it reads a COMMENT-STRIPPED copy on
# purpose. Both files DOCUMENT the broken spelling by quoting it (that is how
# the fix explains itself), so a guard grepping raw source fires against the
# prose explaining the fix — the Obsidian/Cursor lesson, earned again here on
# this guard's own first run. Line-leading `//` only, which is where all of that
# prose lives; a URL in a string literal survives untouched.
strip_comments() {
  python3 -c 'import sys
for line in open(sys.argv[1]):
    if line.lstrip().startswith("//"): continue
    sys.stdout.write(line)' "$1"
}
for f in "$BR_POOLS" "$POOLS" "$SRC_POOLS"; do
  strip_comments "$f" > "$TMP/stripped.swift"
  if grep -q 'privacypools:deposit:' "$TMP/stripped.swift"; then
    echo "✗ the dead 'privacypools:deposit:' spelling is back in $f — deposits land under 'privacypools:dep:'"; exit 1
  fi
done

# The fields each head reads, still stamped by the bridge that lands them.
# Without these a head composes perfectly over nothing.
grep -q 'thing.authorHandle = story.method' "$BR_PEER" \
  || { echo "✗ PeerBridge no longer stamps the funding rail on a BUY — every purchase would be an unplaced fill"; exit 1; }
grep -q 'thing.authorHandle = signal.method' "$BR_PEER" \
  || { echo "✗ PeerBridge no longer stamps the funding rail on a SELL — the room would rank half its traffic"; exit 1; }
grep -q 'thing.priceValue = amount' "$BR_GNOSIS" \
  || { echo "✗ GnosisPayBridge no longer stamps priceValue — every spend would be unpriced and the card could state no money at all"; exit 1; }
grep -q 'thing.priceCurrency = spend.token.currency' "$BR_GNOSIS" \
  || { echo "✗ GnosisPayBridge no longer stamps priceCurrency — spends would drop out of every total with nothing on screen to say so"; exit 1; }
grep -q 'tags: \["Shielded", "Pending"\]' "$BR_POOLS" \
  || { echo "✗ a Privacy Pools deposit no longer lands wearing a state tag — every deposit would compose as untagged"; exit 1; }

# --- prd §397 (2026-08-17) --------------------------------------------------
# The money the room states. Without BOTH halves every deposit is `unpriced`,
# the holdings line never draws, and the cover line has no asset to join
# against — three readings gone while the card still renders a full standing.
grep -q 'thing.priceValue = value' "$BR_POOLS" \
  || { echo "✗ PrivacyPoolsBridge no longer stamps priceValue — the room could state no money at all, and §349's refusal would be back"; exit 1; }
grep -q 'thing.priceCurrency = pool.symbol' "$BR_POOLS" \
  || { echo "✗ PrivacyPoolsBridge no longer stamps priceCurrency — deposits would drop out of every holding with nothing on screen to say so"; exit 1; }
# THE LOOP. Without this the deposit a ragequit undoes keeps its `Declined`
# tag, so the row and the card disagree about the same deposit forever. (The
# CARD is still right — `PrivacyPoolsRoom` does the join itself — so this
# failing is invisible everywhere except search and the row's own chrome,
# which is exactly why it is mechanical.)
grep -q 'retag(label: exit.label, to: PrivacyPoolsRoom.State.reclaimed.rawValue' "$BR_POOLS" \
  || { echo "✗ a ragequit no longer moves its own deposit's state tag — the row would keep saying Declined after the money came back"; exit 1; }
# Both halves of the join must build the ref from ONE constant, the
# `depositRefPrefix` lesson applied to the exit.
grep -q 'let ref = PrivacyPoolsRoom.reclaimedPrefix + exit.label' "$BR_POOLS" \
  || { echo "✗ the ragequit ref is spelled by hand again — the room's reclaim join keys on PrivacyPoolsRoom.reclaimedPrefix and would silently match nothing"; exit 1; }
# One rounding for one number. The card's cover line and the sheet's §228
# sentence state the same pool's set size on two surfaces; rounding them
# separately is how they end up a hundred deposits apart.
grep -q 'PrivacyPoolsRoom.roundedSet(n)' "$BR_POOLS" \
  || { echo "✗ PrivacyPoolsBridge rounds the anonymity set itself again — the card and the thing sheet can now disagree about the same pool"; exit 1; }
# The cover store is written by the SWEEP, not by drawing. A card that fetched
# its own reading would spend a request per open on the one head whose contract
# says it spends nothing per open.
grep -q 'PrivacyPoolsCover.save(current: bySymbol)' "$BR_POOLS" \
  || { echo "✗ nothing writes the live anonymity sets any more — the cover line would be permanently absent"; exit 1; }
grep -q 'PrivacyPoolsCover.snapshot(label: label, count: c.count)' "$BR_POOLS" \
  || { echo "✗ the set size at landing is no longer snapshotted — cover could never be shown to have GROWN, the one good reading this seat has"; exit 1; }
if grep -q 'URLSession\|IngestSupport\|getJSON' "$SRC_POOLS" "$CARD_POOLS"; then
  echo "✗ the Privacy Pools room head reaches the network — it composes from landed rows and stored numbers only"; exit 1
fi
# §374: a room that states figures must be able to hide them.
# `withheld`, not `hidden` (amended 2026-08-28). §501 renamed the gate the
# cards read: `hidden` is the stored preference, `withheld` is `hidden &&
# !peeking` — the STRICTER answer, and the only correct one on a card, since a
# card reading the bare preference stays masked through the peek gesture. The
# guard demands the current gate rather than accepting either.
grep -q 'BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil' "$CARD_POOLS" \
  || { echo "✗ the Privacy Pools card no longer honours hide-balances — §374 figures would stay on screen on the most stood-next-to surface this app has"; exit 1; }
grep -q 'PrivacyPoolsRoom.holdingsLine(room, mask: mask)' "$CARD_POOLS" \
  || { echo "✗ the card no longer draws what's in the pools, or draws it unmasked"; exit 1; }
grep -q 'PrivacyPoolsRoom.coverLine(room.cover)' "$CARD_POOLS" \
  || { echo "✗ the card no longer draws the anonymity set"; exit 1; }
# The door exists only for the state that needs a person, and opens 0xBow and
# nowhere else — capture-only means the honest affordance is a hand-off.
grep -q 'if room.needsYou != nil {' "$CARD_POOLS" \
  || { echo "✗ the 0xBow door is no longer gated on the one state that needs you — it would be chrome on every other room state"; exit 1; }
grep -q 'respondURL = URL(string: "https://app.0xbow.io")' "$CARD_POOLS" \
  || { echo "✗ the respond door no longer opens 0xBow — a door telling you to respond must land where responding happens"; exit 1; }

# --- prd §486: the three scopes ---------------------------------------------
# The card draws its OWN strip (Vibenet's shape, not Wallet's shell-mounted
# one), so these are the only checks that the control exists at all.
CARD_STRIPPED="$TMP/poolscard.swift"
strip_comments "$CARD_POOLS" > "$CARD_STRIPPED"
grep -q 'DSSectionSwitcher(' "$CARD_STRIPPED" \
  || { echo "✗ the Privacy Pools card no longer draws its scope strip — the room goes back to seven blocks in one slab"; exit 1; }
grep -q 'PrivacyPoolsSection.shows(present: scopes)' "$CARD_STRIPPED" \
  || { echo "✗ the strip is no longer gated on there being more than one scope — one chip is a label, not a control (§83)"; exit 1; }
# PRESENCE AND RENDERING ARE ONE QUESTION, spelled the same way in both files.
# §483 shipped a Risk chip that opened an empty page because they were spelled
# differently two files apart; these are the same two expressions.
grep -q 'private var shieldedHasContent: Bool { !room.holdings.isEmpty }' "$CARD_STRIPPED" \
  || { echo "✗ the shielded scope's render gate moved — it must stay identical to the presence flag FeedScreen passes"; exit 1; }
grep -q '!room.segments.isEmpty || room.untagged > 0' "$CARD_STRIPPED" \
  || { echo "✗ the review scope's render gate moved — a room of untagged deposits would offer a chip its card then declines to fill"; exit 1; }
grep -q 'PrivacyPoolsSection.present(shielded: !room.holdings.isEmpty,' "$FEED" \
  || { echo "✗ FeedScreen's shielded presence no longer matches the card's own gate"; exit 1; }
grep -q 'review: !room.segments.isEmpty || room.untagged > 0)' "$FEED" \
  || { echo "✗ FeedScreen's review presence no longer matches the card's own gate"; exit 1; }
# THE HEADLINE BELONGS TO NO SCOPE. Scoped away, the room could be opened
# without being told the one thing §349 exists to say.
grep -q 'headline$' "$CARD_STRIPPED" \
  || { echo "✗ the headline is no longer drawn above the strip — a scope could hide the room's own standing"; exit 1; }
# THE GAP IN THE BAR AND ITS LEGEND DOT ARE THE SAME COLOUR, which is the whole
# of that row's correctness: the untagged deposits ARE the track showing
# through. `mark.opacity(0.35)` there would file them with the resolved states,
# which is a claim — an untagged review is not over, it is unrecorded.
grep -q 'case .unknown:          return DS.fillFaint' "$CARD_STRIPPED" \
  || { echo "✗ the unknown legend dot no longer takes the bar's own track colour — the gap stops being self-explaining"; exit 1; }
grep -q 'Capsule(style: .continuous).fill(DS.fillFaint)' "$CARD_STRIPPED" \
  || { echo "✗ the split bar's track is no longer DS.fillFaint — it and the unknown legend dot must be one colour"; exit 1; }
grep -q 'ForEach(PrivacyPoolsRoom.legendRows(room))' "$CARD_STRIPPED" \
  || { echo "✗ the legend iterates segments again — the untagged deposits would lose the row that explains the bar's gap"; exit 1; }
# The note is the SPLIT'S caption now, not a second sentence under the
# headline. Drawn in the review body or it is a fact with no home.
grep -q 'Text(PrivacyPoolsRoom.note(room))' "$CARD_STRIPPED" \
  || { echo "✗ the card no longer draws the note — the split bar loses the sentence that says what it shows"; exit 1; }
grep -q 'PrivacyPoolsRoom.shieldedNote(room)' "$CARD_STRIPPED" \
  || { echo "✗ the money line lost its caveats — deposits it could not price would be silently missing from the figure"; exit 1; }
grep -q 'PrivacyPoolsRoom.activityNote(room)' "$CARD_STRIPPED" \
  || { echo "✗ the room's own events lost their caption — the observed review time and the idle clause would be computed and never said"; exit 1; }
# ONE GESTURE, ONE ANSWER. The card-wide tap retired with §486: the readings
# are individually tappable rows inside their own cards now, and a whole-card
# target over them is a second answer to the same gesture.
if grep -q 'onTapGesture' "$CARD_STRIPPED"; then
  echo "✗ the Privacy Pools card has a whole-card tap again, over rows that are already buttons"; exit 1
fi
# THE ROWS ARE A SCOPE. Without the gate the stream draws under Shielded and
# Review, and the room is one long scroll again with a control that changes
# only its head.
grep -q 'if privacyPoolsShowsRows(visible) {' "$FEED" \
  || { echo "✗ the Privacy Pools room's rows are no longer gated on its Activity scope"; exit 1; }
grep -q '&& privacyPoolsShowsRows(visible)' "$FEED" \
  || { echo "✗ the caught-up footer no longer respects the scope — it would claim you are all caught up with no stream on screen (§83)"; exit 1; }
# Railgun shares the `.ledger` row shape and has NO scopes, so the gate must
# stay scoped by source or this room's control reaches into its neighbour's.
grep -q 'guard source == PrivacyPoolsRoomSource.source,' "$FEED" \
  || { echo "✗ the row gate is no longer scoped to the Privacy Pools source — it would silently blank the Railgun room"; exit 1; }
grep -q 'var privacyPoolsSection: PrivacyPoolsSection?' "Casberi/Casberi/Shell/ShellChrome.swift" \
  || { echo "✗ the shell no longer remembers which reading is on screen"; exit 1; }
grep -q 'extension PrivacyPoolsSection: DSSectionScope {}' "Casberi/Casberi/Shell/MainSurface.swift" \
  || { echo "✗ PrivacyPoolsSection no longer conforms to the scope protocol — the strip cannot draw"; exit 1; }
# The probe is the only way to see a strip that did not draw, and an empty
# scope list has causes that are invisible from outside.
grep -q 'privacyPoolsScopes|' "$SRC_POOLS" \
  || { echo "✗ -privacyPoolsRoomProbe no longer reports the scopes — a room that draws no control has several causes and only one is a bug"; exit 1; }
grep -q 'privacyPoolsLegend|' "$SRC_POOLS" \
  || { echo "✗ -privacyPoolsRoomProbe no longer reports the legend as drawn — the untagged row's wording could only be checked by screenshot"; exit 1; }

# Demo parity (the standing ship step): every reading above must COMPOSE over
# the seeded corpus, or the demo shows a card the real room would not.
grep -q 'PrivacyPoolsCover.save(current:' "$DEMO" \
  || { echo "✗ the demo no longer seeds the anonymity sets — the cover line would be silently absent from every demo"; exit 1; }
grep -q 'PrivacyPoolsRoom.reclaimedPrefix + "demo6"' "$DEMO" \
  || { echo "✗ the demo no longer seeds a ragequit joined to a deposit — the §397 loop would ship unexercised"; exit 1; }
grep -q '"privacypools:ragequit:demo"' "$DEMO" \
  || { echo "✗ the demo's ragequit ref prefix is missing from refPrefixes — the exit row would outlive the demo and go on joining to a deposit that is real"; exit 1; }
grep -q 'PrivacyPoolsCover.forget(labels:' "$DEMO" \
  || { echo "✗ demo teardown no longer removes the seeded cover snapshots by label — a blanket wipe would destroy a real depositor's own, which cannot be re-read"; exit 1; }

# The source name each room filters on, still the one the bridge lands under.
# The constants exist so the two agree; these check they still describe reality.
grep -q 'static let sourceName = "Peer"' "$BR_PEER" \
  || { echo "✗ PeerBridge.sourceName changed — PeerRoomSource would filter for a source nothing lands under"; exit 1; }
grep -q 'source: "Peer"' "$BR_PEER" \
  || { echo "✗ PeerBridge no longer lands rows under \"Peer\""; exit 1; }
grep -q 'static let sourceName = "Privacy Pools"' "$BR_POOLS" \
  || { echo "✗ PrivacyPoolsBridge.sourceName changed"; exit 1; }
grep -q 'source: "Privacy Pools"' "$BR_POOLS" \
  || { echo "✗ PrivacyPoolsBridge no longer lands rows under \"Privacy Pools\""; exit 1; }
grep -q 'static let sourceName = "Gnosis Pay"' "$BR_GNOSIS" \
  || { echo "✗ GnosisPayBridge.sourceName changed"; exit 1; }
grep -q 'source: "Gnosis Pay"' "$BR_GNOSIS" \
  || { echo "✗ GnosisPayBridge no longer lands rows under \"Gnosis Pay\""; exit 1; }
grep -q 'static let sourceName = "Railgun"' "$BR_RAILGUN" \
  || { echo "✗ RailgunBridge.sourceName changed"; exit 1; }

# The move as DATA, still stamped by the bridge that lands it (prd §350) —
# without this the Railgun head composes perfectly over nothing.
grep -q 'thing.priceValue = move.raw / pow(10, Double(decimals))' "$BR_RAILGUN" \
  || { echo "✗ RailgunBridge no longer stamps priceValue on a move — every shield/unshield would be unpriced"; exit 1; }
grep -q 'thing.priceCurrency = symbol' "$BR_RAILGUN" \
  || { echo "✗ RailgunBridge no longer stamps priceCurrency — moves would drop out of every token grouping"; exit 1; }

# Corollary 4 — filtered live at the boundary, before any stored property is
# read. The caller hands these a debounced snapshot and the foreground sweep
# deletes rows while it is held.
for f in "$SRC_PEER" "$SRC_POOLS" "$SRC_GNOSIS" "$SRC_RAILGUN"; do
  grep -q 'things.live' "$f" \
    || { echo "✗ $f no longer filters live at the boundary (corollary 4)"; exit 1; }
done

# Rendered at all. A head that composes and is never drawn is the §219 social
# roster, which spent weeks that way.
grep -q 'case .peer(let room)' "$FEED" \
  || { echo "✗ the Peer head is no longer rendered from the sourceHead chain"; exit 1; }
grep -q 'case .privacyPools(let room)' "$FEED" \
  || { echo "✗ the Privacy Pools head is no longer rendered from the sourceHead chain"; exit 1; }
grep -q 'case .gnosisPay(let room)' "$FEED" \
  || { echo "✗ the Gnosis Pay head is no longer rendered from the sourceHead chain"; exit 1; }
grep -q 'case .railgun(let room)' "$FEED" \
  || { echo "✗ the Railgun head is no longer rendered from the sourceHead chain"; exit 1; }
grep -q 'case .safe(let room)' "$FEED" \
  || { echo "✗ the Safe head is no longer rendered from the sourceHead chain"; exit 1; }
grep -q 'case PeerRoomSource.source:' "$FEED" \
  || { echo "✗ the sourceHead switch no longer claims the Peer room"; exit 1; }
grep -q 'case PrivacyPoolsRoomSource.source:' "$FEED" \
  || { echo "✗ the sourceHead switch no longer claims the Privacy Pools room"; exit 1; }
grep -q 'case GnosisPayRoomSource.source:' "$FEED" \
  || { echo "✗ the sourceHead switch no longer claims the Gnosis Pay room"; exit 1; }
grep -q 'case RailgunRoomSource.source:' "$FEED" \
  || { echo "✗ the sourceHead switch no longer claims the Railgun room"; exit 1; }
grep -q 'case SafeRoomSource.source:' "$FEED" \
  || { echo "✗ the sourceHead switch no longer claims the Safe room"; exit 1; }

# The cards draw through the SHIPPED arithmetic and honour the row caps, so a
# card cannot quietly re-rank or over-draw what the room composed.
grep -q 'room.rails.prefix(PeerRoomSource.rowCap)' "$CARD_PEER" \
  || { echo "✗ the Peer card no longer honours the rail cap — the footnote would count rows that are drawn anyway"; exit 1; }
grep -q 'room.currencies.prefix(GnosisPayRoomSource.rowCap)' "$CARD_GNOSIS" \
  || { echo "✗ the Gnosis Pay card no longer honours the currency cap"; exit 1; }
grep -q 'room.tokens.prefix(RailgunRoomSource.rowCap)' "$CARD_RAILGUN" \
  || { echo "✗ the Railgun card no longer honours the token cap"; exit 1; }

# --- prd §485 (2026-08-26): the Railgun room's restraint pass ---------------
# The card draws through the SHIPPED pair, and the pair is its only drawing —
# without it a row carries two figures and no picture, which is the state this
# pass replaced (a bar measuring move count under a line stating an amount).
grep -q 'RailgunRoom.pair(token)' "$CARD_RAILGUN" \
  || { echo "✗ the Railgun card no longer draws through the shipped pair() — its rows would carry figures and no drawing"; exit 1; }
# EVERY drawn token gets a row, the lead included. Before this the lead was
# named inside the prose headline and drew a bar with no label of its own, two
# lines below the words it belonged to.
grep -q 'ForEach(Array(drawn.enumerated())' "$CARD_RAILGUN" \
  || { echo "✗ the Railgun card no longer gives every drawn token a row — a lead with a bar and no label is what this pass removed"; exit 1; }
# The negative half, on a COMMENT-STRIPPED copy: both files explain this pass by
# NAMING the deleted function, so a guard grepping raw source fires on the prose
# explaining the fix (the Obsidian/Cursor lesson).
for f in "$RAILGUN" "$CARD_RAILGUN" "$SRC_RAILGUN"; do
  strip_comments "$f" > "$TMP/stripped.swift"
  if grep -q 'RailgunRoom.note\|static func note(\|RailgunRoom.share(\|static func share(' "$TMP/stripped.swift"; then
    echo "✗ the Railgun subline or its move-count bar is back in $f — the card would restate its own rows' totals above them, and measure a count under a line stating an amount"; exit 1
  fi
done
# The rooms whose every row is a transfer read as a LEDGER, not as prose: the
# amount leaves the sentence for a right-aligned figure (`BandRow.moneyColumn`,
# §158's reading). Both had no `Shape` case at all until this pass, so both drew
# the generic band. Gnosis Pay is deliberately absent — see the switch's own
# comment for the two-spellings-of-one-figure reason.
grep -q 'case "Railgun", "Privacy Pools": self = .ledger' "$FEED" \
  || { echo "✗ the wallet-riding money rooms no longer take the ledger shape — their rows would fall back to the generic band and keep the figure inside the sentence"; exit 1; }
grep -q 'case .ledger: BandRow(thing: thing, moneyColumn: true' "$FEED" \
  || { echo "✗ the ledger shape no longer asks for the money column — the shape would exist and change nothing"; exit 1; }
# The stamps that column reads. `transferAmount` has been landed since §369 and
# §397; the SIDE is what this pass added, and without it the pair is half
# stamped and the column can never draw.
grep -q 'thing.transferDirection = "sent"' "$BR_POOLS" \
  || { echo "✗ a Privacy Pools deposit no longer stamps its direction — its rows would keep the amount inside the sentence"; exit 1; }
grep -q 'thing.transferDirection = "received"' "$BR_POOLS" \
  || { echo "✗ a Privacy Pools reclaim no longer stamps its direction"; exit 1; }
grep -q 'thing.transferDirection = direction == .shield ? "sent" : "received"' "$BR_RAILGUN" \
  || { echo "✗ RailgunBridge no longer stamps the direction of a move"; exit 1; }
grep -q 'thing.transferAmount = amountLine' "$BR_RAILGUN" \
  || { echo "✗ RailgunBridge no longer stamps transferAmount — the ledger column reads this and nothing else"; exit 1; }
# THE DEMO'S OWN TRAP, paid for on this pass: the money column lifts the figure
# out of the sentence by SUBSTRING, so a seed whose title and stamp are the same
# NUMBER in two spellings ("0.1500 ETH" / "0.15 ETH") prints it twice. One
# string, spent twice, is the only shape that cannot drift.
grep -q 'row(.transaction, "Put \\(p.amount) into Privacy Pools"' "$DEMO" \
  || { echo "✗ the Privacy Pools demo no longer builds its title from the same string it stamps — the demo would print each amount twice"; exit 1; }
grep -q 't.transferAmount = p.amount' "$DEMO" \
  || { echo "✗ the Privacy Pools demo no longer stamps the amount it put in its own title"; exit 1; }
grep -q 't.transferAmount = r.amount' "$DEMO" \
  || { echo "✗ the Railgun demo no longer stamps transferAmount — every seeded move would keep its figure in its sentence and the ledger column would draw on no row at all"; exit 1; }
grep -q 'room.entries.prefix(SafeRoomSource.rowCap)' "$CARD_SAFE" \
  || { echo "✗ the Safe card no longer honours the entry cap"; exit 1; }
# The strip exists so that superseding `FeedInsight.cardMonths` costs nothing.
# A head outranks the generic registries, so a head that draws less than the
# card it displaced is a regression wearing a new feature.
grep -q 'GnosisPayRoom.monthShare(total: month.total, of: top)' "$CARD_GNOSIS" \
  || { echo "✗ the Gnosis Pay history strip no longer sizes its columns through the shipped monthShare()"; exit 1; }
grep -q 'case "Gnosis Pay":' "Casberi/Casberi/Model/FeedInsight.swift" \
  || { echo "✗ FeedInsight's cardMonths entry for Gnosis Pay is gone — it is the head's FALLBACK below the minimums, not dead code"; exit 1; }
grep -q 'case "Peer":' "Casberi/Casberi/Model/FeedInsight.swift" \
  || { echo "✗ FeedInsight's §311 leaderboard for Peer is gone — it is the head's fallback below minimumFills"; exit 1; }
grep -q 'case "Privacy Pools": return shieldedReview' "Casberi/Casberi/Model/FeedInsight.swift" \
  || { echo "✗ FeedInsight's §311 distribution for Privacy Pools is gone — it is the head's fallback"; exit 1; }
grep -q 'PrivacyPoolsRoom.share(count: segment.count,' "$CARD_POOLS" \
  || { echo "✗ the Privacy Pools split no longer sizes its segments through the shipped share()"; exit 1; }
grep -q 'of: room.deposits' "$CARD_POOLS" \
  || { echo "✗ the Privacy Pools split no longer divides through EVERY deposit — untagged ones would vanish and partial knowledge would draw as complete"; exit 1; }
grep -q 'state.resolved ? Self.mark.opacity' "$CARD_POOLS" \
  || { echo "✗ the Privacy Pools split no longer encodes open-vs-resolved — its two weights are the card's only reading"; exit 1; }

# The §219 failure inverted — see `-roomInsightProbe`'s own comment. A head in
# `shapedSections` with no line here makes the probe confidently report that a
# room "leads with NOTHING" when it leads with a card.
grep -q 'note("peerHead"' "$PROBES" \
  || { echo "✗ -roomInsightProbe no longer mirrors the Peer head"; exit 1; }
grep -q 'note("privacyPoolsHead"' "$PROBES" \
  || { echo "✗ -roomInsightProbe no longer mirrors the Privacy Pools head"; exit 1; }
grep -q 'note("gnosisPayHead"' "$PROBES" \
  || { echo "✗ -roomInsightProbe no longer mirrors the Gnosis Pay head"; exit 1; }
grep -q 'note("railgunHead"' "$PROBES" \
  || { echo "✗ -roomInsightProbe no longer mirrors the Railgun head"; exit 1; }
grep -q 'note("safeHead"' "$PROBES" \
  || { echo "✗ -roomInsightProbe no longer mirrors the Safe head"; exit 1; }
# Each head gets its own probe, because for these five seats an empty room is
# usually the HEALTHY answer and only one or two causes per room are bugs.
for key in peerRoomProbe privacyPoolsRoomProbe gnosisPayRoomProbe railgunRoomProbe safeRoomProbe; do
  grep -q "Hook(key: \"$key\")" "$PROBES" \
    || { echo "✗ -$key is gone — an empty head's several causes would be indistinguishable"; exit 1; }
done

# Safe's own `sourceName` — the 2026-08-11 re-source (SafeBridge's top-of-file
# doc, amendment 8). Change it here and the room head silently stops
# composing over a corpus whose rows still carry the OLD source string.
grep -q 'static let sourceName = "Safe"' "Casberi/Casberi/Model/SafeBridge.swift" \
  || { echo "✗ SafeBridge.sourceName changed"; exit 1; }

# --- 2026-08-17 drift guards ------------------------------------------------
# Wiring the compiled functions above cannot prove about themselves, each one a
# failure that renders as a perfectly good-looking card.

# THE LANDED ROW AND THE HEAD MUST AGREE. `syncPending` skipped an
# already-landed row entirely while `trackPending` kept refreshing the same
# counts for the head, so the feed said "2 of 3 — your signature is needed"
# after two more people had signed, one line under a head that said otherwise.
grep -q 'heals.append(Heal(' "Casberi/Casberi/Model/SafeBridge.swift" \
  || { echo "✗ SafeBridge no longer heals an already-landed pending row — its title and tag would freeze at landing while the room head stays live"; exit 1; }
# ONE definition of the three states. Two copies of "what does ready mean"
# drift, and then a row and the head above it describe the same transaction
# differently.
grep -q 'SafeRoom.Entry(ref: "", safeAddress: ""' "Casberi/Casberi/Model/SafeBridge.swift" \
  || { echo "✗ SafeBridge.rowFace no longer derives ready/awaitsYou from SafeRoom — the feed row and the room head would each carry their own copy of the rule"; exit 1; }
# The notification tag rides `awaitsYou`, never the raw `yourTurn` — otherwise
# a threshold already met without you fires a lock-screen alarm asking for a
# signature nobody needs.
grep -q 'if entry.awaitsYou {' "Casberi/Casberi/Model/SafeBridge.swift" \
  || { echo "✗ the 'Your turn' tag no longer rides awaitsYou — a fully-signed transaction would alarm for a signature it does not need"; exit 1; }
# The nonce is what makes a rival a rival. Stop stamping it and the collision
# warning silently never fires again, with the card still rendering perfectly.
grep -q 'nonce: tx\["nonce"\] as? Int' "Casberi/Casberi/Model/SafeBridge.swift" \
  || { echo "✗ SafeBridge no longer stamps the queue nonce — same-nonce rivals become undetectable"; exit 1; }

# THE DEAD CONTROL. `compose` returns a card on module risk ALONE, and both of
# the card's tap paths used to resolve through `room.lead` — so that exact card
# announced "Opens this Safe" and did nothing.
grep -q 'room.lead?.ref ?? fallbackRef' "$CARD_SAFE" \
  || { echo "✗ the Safe card no longer falls back to a real destination — a module-only card would announce a door it does not have"; exit 1; }
grep -q 'SafeRoomSource.fallbackRef(things:' "$FEED" \
  || { echo "✗ FeedScreen no longer hands the Safe card its fallback ref"; exit 1; }
# ...and when there is no destination at all, BOTH the gesture and the
# accessibility action must be withheld rather than left announcing one.
grep -q 'if let destination {' "$CARD_SAFE" \
  || { echo "✗ the Safe card's tap is no longer gated on having somewhere to go"; exit 1; }
# The card must draw the state line, or a nonce collision is computed and never
# said — the one fact nothing else in this app surfaces.
grep -q 'SafeRoom.stateNote(room)' "$CARD_SAFE" \
  || { echo "✗ the Safe card no longer draws the state note — rival transactions would be detected and never mentioned"; exit 1; }
grep -q 'room.isContested(entry)' "$CARD_SAFE" \
  || { echo "✗ the Safe card no longer marks WHICH rings collide — the sentence says two of these contest and nothing says which"; exit 1; }

# --- 2026-08-24: rows, not a rail (prd §464) --------------------------------
# THE CLIP. The rings were a horizontal ScrollView of 60pt cells, and `rowCap`
# is 3 — so it could never scroll, spent ~150pt of a ~330pt card on emptiness,
# and clipped in three places for want of the width it was throwing away. A
# card that goes back to a fixed-width cell goes straight back to truncating
# `waitLabel` with no ellipsis, invisibly at the default size and for every
# accessibility size and most non-English.
strip_comments "$CARD_SAFE" > "$TMP/safecard.swift"
if grep -q 'ScrollView(.horizontal' "$TMP/safecard.swift"; then
  echo "✗ the Safe card's entries are back in a horizontal rail — three items cannot scroll, and the cell is what clipped"; exit 1
fi
if grep -qE 'frame\(width: [0-9]+\)' "$TMP/safecard.swift"; then
  echo "✗ the Safe card has a fixed-width text box again — nothing on a row may carry a hardcoded width"; exit 1
fi
# The subject was cached on every entry and drawn ONLY in the VoiceOver label,
# so a sighted reader got strictly less than a VoiceOver one. Both readers go
# through the same function now, and this is what keeps them from drifting
# apart again.
grep -q 'Text(verbatim: SafeRoom.subject(entry))' "$TMP/safecard.swift" \
  || { echo "✗ the Safe card no longer draws the transaction's subject — the row would say 2/3 and a wait and never what it is about"; exit 1; }
grep -q 'var parts = \[SafeRoom.subject(entry)\]' "$TMP/safecard.swift" \
  || { echo "✗ the Safe card's VoiceOver label no longer shares the row's own subject — the spoken card and the drawn one can drift"; exit 1; }
# STATE IS A WORD BEFORE IT IS A COLOUR. Without this the row's three states are
# one row in greyscale, in a PDF export, and to a red-green viewer.
grep -q 'SafeRoom.stateLabel(entry)' "$TMP/safecard.swift" \
  || { echo "✗ the Safe card no longer says the state — it would be carried by tint alone, which §83 forbids"; exit 1; }
# The rival pair, said. It was a 9pt glyph offset off a ring's corner: the
# smallest mark on the card carrying its highest-stakes fact, unlabelled.
grep -q 'SafeRoom.positionLabel(entry)' "$TMP/safecard.swift" \
  || { echo "✗ the Safe card no longer names the contested queue position — the pairing is drawn adjacent and never explained"; exit 1; }
# THE DISC'S OWN CLIP, and its two halves. The frame was a frozen 44 holding a
# `label12`, which goes through `dsText` and grows with the text setting — so
# "10/12" outgrew the inner circle and met its own stroke. Scaling the frame is
# half the fix; the count STEPPING OUT above accessibilityMedium is the other,
# because a label that scales inside a frame that also scales still collides at
# the top of the range. The card must then carry the fraction in words, or it
# is simply lost.
QUEUE="Casberi/Casberi/Screens/SafeQueueCard.swift"
strip_comments "$QUEUE" > "$TMP/safequeue.swift"
grep -q 'UIFontMetrics(forTextStyle: .caption1).scaledValue(for: size)' "$TMP/safequeue.swift" \
  || { echo "✗ SafeSignatureDisc's frame is frozen again — its own scaling label will outgrow it at an accessibility size"; exit 1; }
grep -q 'frame(width: scaled, height: scaled)' "$TMP/safequeue.swift" \
  || { echo "✗ SafeSignatureDisc computes a scaled size and no longer uses it"; exit 1; }
grep -q 'showsCount && !sizeCategory.isAccessibilityCategory' "$TMP/safequeue.swift" \
  || { echo "✗ SafeSignatureDisc no longer steps its count out of the ring at an accessibility size"; exit 1; }
grep -q 'sizeCategory.isAccessibilityCategory, entry.required > 0' "$TMP/safecard.swift" \
  || { echo "✗ the Safe card no longer carries the fraction when the ring stops drawing it — the count would be lost at an accessibility size"; exit 1; }

# The chip's long-press peek must preview the room it opens. Safe's head is a
# FIGURE (rings), not a text hero, so it belongs in this chain for X's exact
# reason — without it the peek drew a blank.
grep -q 'source == SafeRoomSource.source, let room = SafeRoomSource.compose' \
  "Casberi/Casberi/Model/RoomFigure.swift" \
  || { echo "✗ the Safe chip peek no longer previews the Safe head — long-pressing the chip would draw nothing"; exit 1; }

# The widget half. A your-turn signature has NO due date, so it can never be a
# WidgetDeadline without inventing one — and an invented date would sort among
# real deadlines and draw itself late.
grep -q 'static func safeCall(things:' "Casberi/Casberi/Model/WidgetPublish.swift" \
  || { echo "✗ the Needs-you tile no longer receives the Safe signature call"; exit 1; }
grep -q 'enum WidgetSafe {' "Casberi/Shared/WidgetPayload.swift" \
  || { echo "✗ the WidgetSafe payload is gone"; exit 1; }
# It is a READING, so it takes the short window. Sharing the deadlines' 36
# hours would leave a count on the Home Screen a day and a half after it
# stopped being true.
grep -q 'static let freshness: TimeInterval = 6 \* 3600' "Casberi/Shared/WidgetPayload.swift" \
  || { echo "✗ the Safe call no longer carries the READING freshness window — a stale count would sit on the Home Screen for 36 hours"; exit 1; }
# "Nothing due" while a signature waits is the bug this payload exists to fix.
grep -q 'var isEmpty: Bool { rows.isEmpty && (safe?.awaitsYou ?? 0) == 0 }' \
  "Casberi/CasberiWidgets/NeedsYouWidget.swift" \
  || { echo "✗ the Needs-you tile can say 'Nothing due' while a signature is waiting on you"; exit 1; }

# The brief's rung — the ONLY surface that can re-raise a your-turn signature,
# since §306's news window forbids a second notification forever after.
grep -q 'safeStuckLine(now: now)' "Casberi/Casberi/Model/TodayBrief.swift" \
  || { echo "✗ the Today brief no longer carries the stuck-signature rung — a request nobody answered would have no surface at all after its landing day"; exit 1; }

# The demo has to be able to SHOW all three states, or they ship unseen — the
# standing demo-parity rule, and what verify.sh's room-head check reads.
grep -q 'wallet:safe:eth:demo3' "Casberi/Casberi/Model/DemoSeedAll.swift" \
  || { echo "✗ the demo no longer seeds a rival pair / fully-signed Safe queue — the three states would ship unseen"; exit 1; }


cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}

let cal = Calendar.current
let t0 = cal.startOfDay(for: Date(timeIntervalSince1970: 1_780_000_000))
func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: t0)! }
// A locale pinned so money strings are assertable at all — the app never
// passes one.
let us = Locale(identifier: "en_US")

// ===========================================================================
print("Peer — reading a row")
// ===========================================================================

// THE ordering fact: every ref begins `peer:`, so a bare-prefix-first table
// reads every sale as a purchase.
check("a buy is read from its ref", PeerRoom.kind(ref: "peer:0xabc") == .bought)
check("a SELL is not read as a buy", PeerRoom.kind(ref: "peer:sell:0xabc") == .sold)
check("an expired fill is its own kind", PeerRoom.kind(ref: "peer:expired:0xabc") == .fellThrough)
check("a ref this build doesn't know is nil, never guessed",
      PeerRoom.kind(ref: "peer2:0xabc") == nil)
check("no ref at all is nil", PeerRoom.kind(ref: nil) == nil)
check("a fall-through settled nothing", PeerRoom.Kind.fellThrough.settled == false)
check("a sale settled", PeerRoom.Kind.sold.settled)

func fill(_ ref: String, rail: String? = nil, at: Date = t0) -> PeerRoom.Sighting {
    PeerRoom.Sighting(ref: ref, rail: rail, at: at)
}

print("")
print("Peer — composing")
let peer = PeerRoom.compose(fills: [
    fill("peer:1", rail: "Venmo", at: day(-1)),
    fill("peer:2", rail: "Venmo", at: day(-3)),
    fill("peer:sell:3", rail: "Venmo", at: day(-5)),
    fill("peer:4", rail: "Cash App", at: day(-2)),
    fill("peer:5", at: day(-6)),                    // no rail at all
    fill("peer:expired:6", at: day(0)),             // "dated" today, but isn't
])
check("buys are counted", peer.bought == 4)
check("sells are counted apart", peer.sold == 1)
// Counted as a buy AND as unplaced: the fill is real, the rail is not known.
check("a fill with no rail is counted, not bucketed", peer.unplaced == 1)
check("a fall-through is counted", peer.fellThrough == 1)
check("a fall-through is NOT a fill", peer.fills == 5)
check("no 'Unknown' rail was invented", peer.rails.allSatisfy { $0.name != "Unknown" })
check("two real rails", peer.rails.count == 2)
check("the busiest rail leads", peer.lead?.name == "Venmo")
check("a rail counts both directions", peer.lead?.fills == 3)
// THE date fact: an expired row is stamped when we looked. Letting it date the
// room makes a dormant account read as active this morning.
check("a fall-through never dates the room", peer.newest == day(-1))

print("")
print("Peer — ranking is total")
func rail(_ n: String, b: Int, s: Int = 0, at: Date = t0) -> PeerRoom.Rail {
    PeerRoom.Rail(name: n, bought: b, sold: s, newest: at)
}
check("more fills wins",
      PeerRoom.ordered([rail("a", b: 1), rail("b", b: 9)]).first?.name == "b")
check("a tie on fills breaks on recency",
      PeerRoom.ordered([rail("a", b: 2, at: day(-9)), rail("b", b: 2, at: day(-1))]).first?.name == "b")
// Without this the order comes off a dictionary, and the card reshuffles
// between opens over identical rows — which reads as broken.
check("a tie on fills AND recency breaks on name",
      PeerRoom.ordered([rail("zulu", b: 2), rail("alpha", b: 2)]).first?.name == "alpha")

print("")
print("Peer — the bar")
check("a share is a fraction of the busiest", PeerRoom.share(fills: 3, of: 6) == 0.5)
check("the busiest is full", PeerRoom.share(fills: 6, of: 6) == 1)
// A zero denominator draws as a NaN-width capsule, which SwiftUI renders as
// nothing (the AgentPanel lesson).
check("a zero denominator can't divide by zero", PeerRoom.share(fills: 3, of: 0) == 0)
check("a share never exceeds one", PeerRoom.share(fills: 9, of: 6) == 1)

print("")
print("Peer — words")
check("both directions are named when both happened",
      PeerRoom.railLine(rail("a", b: 3, s: 2)) == "3 in · 2 out")
check("a sell-only rail says sales", PeerRoom.railLine(rail("a", b: 0, s: 2)) == "2 sales")
check("a buy-only rail says purchases", PeerRoom.railLine(rail("a", b: 4)) == "4 purchases")
check("one purchase is singular", PeerRoom.railLine(rail("a", b: 1)) == "1 purchase")
check("the headline names the leading rail",
      PeerRoom.headline(peer).contains("Venmo"))
check("the headline counts every settled fill, placed or not",
      PeerRoom.headline(peer).contains("5 fills"))
check("one rail gets a simpler sentence",
      PeerRoom.headline(PeerRoom.compose(fills: [fill("peer:1", rail: "Revolut"),
                                                 fill("peer:2", rail: "Revolut")]))
        == "2 fills settled through Revolut")
// Naming a rail here would be the invention `unplaced` exists to refuse.
check("fills with no rail at all still get an honest headline",
      PeerRoom.headline(PeerRoom.compose(fills: [fill("peer:1"), fill("peer:2")]))
        == "2 fills settled on Peer")
check("the note carries the direction, not the rail",
      PeerRoom.note(peer) == "4 bought · 1 sold")
check("a cash-out-only room says so",
      PeerRoom.note(PeerRoom.compose(fills: [fill("peer:sell:1", rail: "Venmo")]))
        == "Cashing out — 1 sold, nothing bought")

print("")
print("Peer — the footnote never hides a row")
let footnote = PeerRoom.footnote(peer, drawn: 1, now: t0) ?? ""
check("undrawn rails are counted", footnote.contains("1 more rail"))
check("unplaced fills are counted", footnote.contains("1 fill has no rail"))
check("fall-throughs are counted", footnote.contains("1 sale fell through"))
// Never dated, never called recent — see PeerRoom's own type note.
check("a fall-through is never dated in the footnote",
      !footnote.contains("day") || footnote.contains("nothing for"))
check("a busy room needs no idle clause",
      PeerRoom.idleNote(newest: day(-3), now: t0) == nil)
check("a long silence is stated",
      PeerRoom.idleNote(newest: day(-40), now: t0) == "nothing for 40 days")
check("a fortnight is not a fact about anything",
      PeerRoom.idleNote(newest: day(-14), now: t0) == nil)

print("")
print("Peer — when there is no card")
check("one fill is a row, not a card",
      PeerRoom.compose(fills: [fill("peer:1", rail: "Venmo")]).isEmpty)
check("two fills earn a card",
      !PeerRoom.compose(fills: [fill("peer:1", rail: "Venmo"), fill("peer:2")]).isEmpty)
// Real fills nobody could place still have plenty to say, and hiding the card
// would leave no hint that anything is missing.
check("unplaced fills still earn a card",
      !PeerRoom.compose(fills: [fill("peer:1"), fill("peer:2")]).isEmpty)
// `unplaced` is a SUBSET of `fills`, not a sibling: a fill is counted as bought
// or sold before its rail is looked at. Adding the two makes ONE unplaced fill
// clear the minimum on its own and draw a card over a single row.
check("one unplaced fill is one fill, not two",
      PeerRoom.compose(fills: [fill("peer:1")]).isEmpty)
check("the counts don't double up",
      PeerRoom.compose(fills: [fill("peer:1")]).fills == 1
        && PeerRoom.compose(fills: [fill("peer:1")]).unplaced == 1)
check("fall-throughs alone do not earn a card",
      PeerRoom.compose(fills: [fill("peer:expired:1"), fill("peer:expired:2")]).isEmpty)

// ===========================================================================
print("")
print("Privacy Pools — reading a row")
// ===========================================================================

func pp(_ ref: String, _ tags: [String] = [], at: Date = t0) -> PrivacyPoolsRoom.Sighting {
    PrivacyPoolsRoom.Sighting(ref: ref, tags: tags, at: at)
}

// The mirror the whole card rests on: these raw values ARE the tag strings
// `PrivacyPoolsBridge.retag` writes.
check("the tag vocabulary is the bridge's",
      PrivacyPoolsRoom.states == ["Pending", "Cleared", "Declined", "Needs proof", "Reclaimed"])
check("a state is read off the tag", PrivacyPoolsRoom.state(tags: ["Shielded", "Cleared"]) == .cleared)
check("the shielded marker is not a state", PrivacyPoolsRoom.state(tags: ["Shielded"]) == nil)
// Defaulting to pending is a claim about the screener made with no evidence —
// a deposit that cleared two months ago reported as still waiting.
check("no state tag is nil, never pending", PrivacyPoolsRoom.state(tags: []) == nil)
check("only proof needs YOU", PrivacyPoolsRoom.State.needsProof.needsYou)
check("a decline is a decision already made", PrivacyPoolsRoom.State.declined.needsYou == false)
check("cleared and declined are both over",
      PrivacyPoolsRoom.State.cleared.resolved && PrivacyPoolsRoom.State.declined.resolved)
check("pending is not resolved", PrivacyPoolsRoom.State.pending.resolved == false)

print("")
print("Privacy Pools — composing")
let pools = PrivacyPoolsRoom.compose(rows: [
    pp("privacypools:dep:1", ["Shielded", "Pending"], at: day(-2)),
    pp("privacypools:dep:2", ["Shielded", "Pending"], at: day(-4)),
    pp("privacypools:dep:3", ["Shielded", "Cleared"], at: day(-9)),
    pp("privacypools:dep:4", ["Shielded", "Needs proof"], at: day(-6)),
    pp("privacypools:dep:5", ["Shielded"], at: day(-20)),          // pre-§311
    pp("privacypools:ragequit:6", at: day(-1)),
    // The announcement of deposit 3 clearing. Counting it would report that
    // deposit twice — once as itself, once as its own news.
    pp("privacypools:status:3", at: day(-9)),
    pp("privacypools:poi:4", at: day(-6)),
])
check("deposits are counted", pools.deposits == 5)
check("an untagged deposit is counted apart", pools.untagged == 1)
check("an alert is NOT a deposit", pools.deposits == 5 && pools.segments.reduce(0) { $0 + $1.count } == 4)
// Ragequit 6 has no deposit 6 in this room, so it stays an orphan rather than
// resolving anything — see the loop-closing block below for the joined case.
check("a reclaim with no deposit here is counted apart", pools.unattachedReclaims == 1)
check("what is still open is counted", pools.waiting == 3)
check("a reclaim never dates the room", pools.newest == day(-2))

print("")
print("Privacy Pools — the ranking that matters")
// One stuck deposit outranks forty that cleared: the forty need nothing from
// anybody, and the one is the entire reason to look.
check("proof-required leads everything", pools.lead?.state == .needsProof)
check("the stuck deposit is found", pools.needsYou?.count == 1)
check("a decline outranks a pending", PrivacyPoolsRoom.rank(.declined) > PrivacyPoolsRoom.rank(.pending))
check("a pending outranks a cleared", PrivacyPoolsRoom.rank(.pending) > PrivacyPoolsRoom.rank(.cleared))
let lopsided = PrivacyPoolsRoom.compose(rows:
    (0..<40).map { pp("privacypools:dep:c\($0)", ["Cleared"]) }
    + [pp("privacypools:dep:stuck", ["Needs proof"])])
check("one stuck deposit still leads forty cleared ones", lopsided.lead?.state == .needsProof)
check("and the headline says so",
      PrivacyPoolsRoom.headline(lopsided, now: t0) == "A deposit needs your proof")

print("")
print("Privacy Pools — oldest-in-state and observed review time")
let staleRoom = PrivacyPoolsRoom.compose(rows: [
    pp("privacypools:dep:old", ["Pending"], at: day(-10)),
])
check("the headline names the wait once it clears the floor",
      PrivacyPoolsRoom.headline(staleRoom, now: t0).contains("10 days"))
let freshRoom = PrivacyPoolsRoom.compose(rows: [
    pp("privacypools:dep:new", ["Pending"], at: day(-1)),
])
check("a wait under the floor says nothing extra",
      PrivacyPoolsRoom.headline(freshRoom, now: t0) == "1 deposit is still in review")

// A deposit and its own status alert share the SAME label suffix — that is
// what lets the room pair "when it landed" to "when we saw it resolve" with
// no new field and no new read.
let reviewed = PrivacyPoolsRoom.compose(rows: [
    pp("privacypools:dep:r1", ["Cleared"], at: day(-9)),
    pp("privacypools:status:r1", [], at: day(-4)),
])
check("a deposit paired with its own status alert yields a real review time",
      reviewed.reviewDays == 5)
let unresolved = PrivacyPoolsRoom.compose(rows: [
    pp("privacypools:dep:r2", ["Pending"], at: day(-9)),
])
check("no observed resolution means no review-time claim", unresolved.reviewDays == nil)
let reversed = PrivacyPoolsRoom.compose(rows: [
    pp("privacypools:dep:r3", ["Cleared"], at: day(-1)),
    pp("privacypools:status:r3", [], at: day(-9)),
])
check("a resolution dated before its own deposit is never used", reversed.reviewDays == nil)
check("median, not mean, over several observed reviews",
      PrivacyPoolsRoom.medianDays([1, 3, 100]) == 3)

print("")
print("Privacy Pools — the split")
// The denominator is EVERY deposit, so the drawn segments legitimately fall
// short and the gap is the unknown. Dividing through the tagged count alone
// would present partial knowledge as complete.
check("the split divides through every deposit including untagged ones",
      abs(PrivacyPoolsRoom.share(count: 1, of: pools.deposits) - 0.2) < 0.0001)
check("the drawn segments deliberately do not fill the bar",
      abs(pools.segments.reduce(0.0) {
          $0 + PrivacyPoolsRoom.share(count: $1.count, of: pools.deposits) } - 0.8) < 0.0001)
check("a zero denominator can't divide by zero", PrivacyPoolsRoom.share(count: 2, of: 0) == 0)

print("")
print("Privacy Pools — words")
check("a state's line says what it MEANS, not just the verdict",
      PrivacyPoolsRoom.meaning(.declined) == "reclaim to your wallet")
check("cleared says what you can now do",
      PrivacyPoolsRoom.meaning(.cleared) == "ready to withdraw privately")
check("the note carries the shape of the rest",
      PrivacyPoolsRoom.note(pools) == "3 of 5 still waiting on the screener")
check("an all-resolved room says so",
      PrivacyPoolsRoom.note(PrivacyPoolsRoom.compose(rows: [pp("privacypools:dep:1", ["Cleared"])]))
        == "Every review is finished")
check("a wholly unruled room says so",
      PrivacyPoolsRoom.note(PrivacyPoolsRoom.compose(rows: [pp("privacypools:dep:1", ["Pending"])]))
        == "None of them have been ruled on yet")
// §486 split the old single `footnote` into two scope captions and moved the
// untagged clause into the legend. Nothing was dropped — these check that.
check("untagged deposits are named in the legend, beside the gap they are",
      PrivacyPoolsRoom.legendRows(pools).contains {
          if case .unknown = $0.slice { return true }; return false })
check("the unknown row says what it is",
      PrivacyPoolsRoom.unknownLine(1) == "1 deposit's status is unknown")
check("the unknown row pluralises",
      PrivacyPoolsRoom.unknownLine(3) == "3 deposits' status is unknown")
check("unknown is the LAST legend row, never ranked among the verdicts",
      PrivacyPoolsRoom.legendRows(pools).last.map {
          if case .unknown = $0.slice { return true }; return false } == true)
check("a room with everything tagged grows no unknown row",
      PrivacyPoolsRoom.legendRows(
          PrivacyPoolsRoom.compose(rows: [pp("privacypools:dep:1", ["Cleared"])])).count == 1)
check("the legend forwards a state row to the segment wording",
      PrivacyPoolsRoom.legendLine(
          .init(slice: .state(.pending), count: 1, oldestAt: nil), now: t0) == "1 in review")
check("a slice's id is stable enough to key a ForEach",
      PrivacyPoolsRoom.Slice.state(.cleared).id == "Cleared"
        && PrivacyPoolsRoom.Slice.unknown.id == "Unknown")
check("the unknown row is NAMED, not left blank",
      PrivacyPoolsRoom.name(.unknown) == "Unknown")
let ppAct = PrivacyPoolsRoom.activityNote(pools, now: t0) ?? ""
check("orphan reclaims are named", ppAct.contains("1 reclaimed before you watched"))
check("a room of pre-tag deposits gets an honest headline",
      PrivacyPoolsRoom.headline(PrivacyPoolsRoom.compose(rows: [
          pp("privacypools:dep:1"), pp("privacypools:dep:2")]))
        == "2 deposits in Privacy Pools")
check("a fully reclaimed room still draws",
      !PrivacyPoolsRoom.compose(rows: [pp("privacypools:ragequit:1")]).isEmpty)
check("an alert on its own is no card",
      PrivacyPoolsRoom.compose(rows: [pp("privacypools:status:1")]).isEmpty)

print("")
print("Privacy Pools — the loop closes (prd §397)")
// THE BUG THIS EXISTS FOR: before the join, a deposit that was declined and
// then reclaimed kept its `Declined` tag for life, so `rank` went on putting
// it at the top of the card telling the person to reclaim it — permanently,
// on the one card whose whole job is to say what still needs them.
let closed = PrivacyPoolsRoom.compose(rows: [
    pp("privacypools:dep:x", ["Shielded", "Declined"], at: day(-30)),
    pp("privacypools:ragequit:x", at: day(-25)),
])
check("a reclaimed deposit stops being declined", closed.lead?.state == .reclaimed)
check("and the headline stops asking for a reclaim already done",
      PrivacyPoolsRoom.headline(closed, now: t0) == "Your deposit is back in your wallet")
// The double-count the whole room is careful about everywhere else: the
// ragequit resolved a deposit, so it is reported once, as that deposit.
check("a joined ragequit is not ALSO counted as its own thing",
      closed.deposits == 1 && closed.unattachedReclaims == 0)
check("nothing is left in the pools", closed.inPools == 0)
check("and the note says that, not that reviews finished",
      PrivacyPoolsRoom.note(closed) == "All of it has been taken back out")
// Evidence beats the record: the stored tag is untouched and still reads
// `Declined`. The card is right because it joined, not because anything
// rewrote history.
check("the stale tag itself still says declined",
      PrivacyPoolsRoom.state(tags: ["Shielded", "Declined"]) == .declined)
// A reclaim is over, so it must never outrank something still open.
check("a reclaim ranks below everything still open",
      PrivacyPoolsRoom.rank(.reclaimed) < PrivacyPoolsRoom.rank(.cleared))
check("a reclaim is resolved and out of the pool",
      PrivacyPoolsRoom.State.reclaimed.resolved
        && PrivacyPoolsRoom.State.reclaimed.inPool == false)
// A DECLINE is not an exit — the money sits there until it is reclaimed,
// which is the entire reason these are two states.
check("a decline is still in the pool", PrivacyPoolsRoom.State.declined.inPool)
// Only the deposit the evidence names moves. Getting this wrong the other way
// — every declined deposit going quiet because one was reclaimed — is the
// same bug with the sign flipped.
let mixedReclaims = PrivacyPoolsRoom.compose(rows: [
    pp("privacypools:dep:a", ["Declined"], at: day(-30)),
    pp("privacypools:dep:b", ["Declined"], at: day(-20)),
    pp("privacypools:ragequit:a", at: day(-25)),
])
check("only the deposit the ragequit names moves",
      mixedReclaims.lead?.state == .declined && mixedReclaims.lead?.count == 1)
check("and the reclaimed one is reported exactly once",
      mixedReclaims.segments.first { $0.state == .reclaimed }?.count == 1)
check("a ragequit sorted BEFORE its own deposit still joins",
      PrivacyPoolsRoom.compose(rows: [
          pp("privacypools:ragequit:z", at: day(-25)),
          pp("privacypools:dep:z", ["Declined"], at: day(-30)),
      ]).lead?.state == .reclaimed)

print("")
print("Privacy Pools — what's in the pools (prd §397)")
func ppa(_ ref: String, _ tags: [String], _ asset: String?, _ amount: Double?,
         at: Date = t0) -> PrivacyPoolsRoom.Sighting {
    PrivacyPoolsRoom.Sighting(ref: ref, tags: tags, asset: asset, amount: amount, at: at)
}
let held = PrivacyPoolsRoom.compose(rows: [
    ppa("privacypools:dep:h1", ["Pending"], "ETH", 0.07, at: day(-2)),
    ppa("privacypools:dep:h2", ["Cleared"], "ETH", 0.25, at: day(-5)),
    ppa("privacypools:dep:h3", ["Cleared"], "USDC", 250, at: day(-6)),
    // Declined AND reclaimed — its 0.15 must not be counted as shielded.
    ppa("privacypools:dep:h4", ["Declined"], "ETH", 0.15, at: day(-9)),
    pp("privacypools:ragequit:h4", at: day(-8)),
    // Landed before the bridge stamped the pair: counted, never bucketed.
    ppa("privacypools:dep:h5", ["Pending"], nil, nil, at: day(-3)),
])
check("assets are separate holdings", held.holdings.count == 2)
check("the leading asset is the one with the most deposits",
      held.leadHolding?.symbol == "ETH")
check("money already taken back out is not counted as still in there",
      abs((held.leadHolding?.amount ?? 0) - 0.32) < 0.0001)
check("an unpriced deposit is counted, never dropped", held.unpriced == 1)
check("an unpriced deposit is not bucketed under a guessed symbol",
      held.holdings.map(\.symbol).sorted() == ["ETH", "USDC"])
check("open deposits are counted per asset", held.leadHolding?.waiting == 1)
// The one arithmetic this room must never do.
check("assets are never summed",
      PrivacyPoolsRoom.holdingsLine(held) == "0.32 ETH · 250 USDC in the pools")
// A partial sum presented as a total is the failure this stays silent for.
let partial = PrivacyPoolsRoom.compose(rows: [
    ppa("privacypools:dep:p1", ["Pending"], "ETH", 0.07),
    ppa("privacypools:dep:p2", ["Pending"], "ETH", nil),
])
check("a sum missing one of its parts is never stated",
      partial.leadHolding?.amount == nil)
check("and it falls back to a count, which is not a balance",
      PrivacyPoolsRoom.holdingText(partial.leadHolding!) == "2 ETH deposits")
// §374 rule 3: figures go, shapes stay.
check("hide-balances masks the figure and keeps the asset",
      PrivacyPoolsRoom.holdingText(held.leadHolding!, mask: "••••") == "•••• ETH")
check("a room with nothing in it has no holdings line",
      PrivacyPoolsRoom.holdingsLine(closed) == nil)
// Amounts in different tokens do not compare, so ranking by them would imply
// a conversion this room refuses to make.
check("holdings rank by deposit count, never by amount",
      PrivacyPoolsRoom.orderedHoldings([
          .init(symbol: "USDC", deposits: 1, waiting: 0, amount: 250),
          .init(symbol: "ETH", deposits: 2, waiting: 0, amount: 0.32),
      ]).first?.symbol == "ETH")
// Without the last tiebreak the order comes off a dictionary and the card
// reshuffles between opens over identical data.
check("equal counts fall back to a stable name order",
      PrivacyPoolsRoom.orderedHoldings([
          .init(symbol: "USDC", deposits: 1, waiting: 0, amount: 250),
          .init(symbol: "DAI", deposits: 1, waiting: 0, amount: 10),
      ]).first?.symbol == "DAI")

print("")
print("Privacy Pools — cover (prd §397)")
check("no reading, no line", PrivacyPoolsRoom.coverLine(nil) == nil)
check("an empty set is not a reading",
      PrivacyPoolsRoom.coverLine(.init(symbol: "ETH", current: 0, atLanding: nil)) == nil)
check("the current set is stated on its own",
      PrivacyPoolsRoom.coverLine(.init(symbol: "ETH", current: 3947, atLanding: nil))
        == "Your ETH hides among about 3,900 accepted deposits.")
check("growth is stated when the rounded figures differ",
      (PrivacyPoolsRoom.coverLine(.init(symbol: "ETH", current: 3947, atLanding: 2410)) ?? "")
        .contains("up from 2,400"))
// At two significant figures 3,947 → 3,961 renders as "up from 3,900 to
// 3,900", which reads as a broken sentence rather than the honest "no
// material change" it is.
check("growth inside the rounding is not narrated",
      (PrivacyPoolsRoom.coverLine(.init(symbol: "ETH", current: 3961, atLanding: 3947)) ?? "")
        .contains("up from") == false)
// A shrinking set is real but alarming, and this reading does not know why.
check("a set that shrank is never narrated",
      (PrivacyPoolsRoom.coverLine(.init(symbol: "ETH", current: 3000, atLanding: 4000)) ?? "")
        .contains("up from") == false)
// Locale-independent: the grouping separator differs by region, the digits do
// not.
check("two significant figures, rounded down",
      PrivacyPoolsRoom.roundedSet(3947).filter(\.isNumber) == "3900")
check("a small set is stated exactly", PrivacyPoolsRoom.roundedSet(12) == "12")
// One asset, deliberately: several cover lines would stack separate pools'
// set sizes into something that reads as one aggregate privacy figure.
let covered = PrivacyPoolsRoom.compose(rows: [
    ppa("privacypools:dep:c1", ["Pending"], "ETH", 0.07),
    ppa("privacypools:dep:c2", ["Cleared"], "ETH", 0.25),
    ppa("privacypools:dep:c3", ["Cleared"], "USDC", 250),
], covers: [.init(symbol: "USDC", current: 700, atLanding: nil),
            .init(symbol: "ETH", current: 4000, atLanding: 3000)])
check("cover follows the leading asset and no other", covered.cover?.symbol == "ETH")
check("a pool we have no reading for gets no line",
      PrivacyPoolsRoom.cover(for: covered.leadHolding,
                             in: [.init(symbol: "DAI", current: 9, atLanding: nil)]) == nil)

print("")
print("Privacy Pools — the legend's wait (prd §397)")
let waitingSeg = staleRoom.lead!
check("the legend names how long the oldest has waited",
      PrivacyPoolsRoom.legendLine(waitingSeg, now: t0).contains("oldest 10 days"))
// A cleared or reclaimed deposit finished waiting; saying how long it took is
// not the fact that matters once it has.
check("a resolved state says nothing about waiting",
      PrivacyPoolsRoom.legendLine(
          .init(state: .cleared, count: 2, oldestAt: day(-40)), now: t0)
        == PrivacyPoolsRoom.segmentLine(.init(state: .cleared, count: 2, oldestAt: day(-40))))
check("a wait under the floor is not worth naming",
      PrivacyPoolsRoom.legendLine(
          .init(state: .pending, count: 1, oldestAt: day(-1)), now: t0)
        == "1 in review")

print("")
print("Privacy Pools — the scopes (prd §486)")
// The room's three readings behind one control. Every failure here renders as
// an ordinary room: a chip that opens an empty page, a remembered scope
// resolving somewhere nobody chose, or a strip that reshuffles between opens.
let ppAll = PrivacyPoolsSection.present(shielded: true, review: true)
check("the order is events → state → hazard, and it is total",
      ppAll == [.activity, .shielded, .review])
check("activity is always there — the room always has a feed",
      PrivacyPoolsSection.present(shielded: false, review: false) == [.activity])
check("both readings past activity are conditional",
      PrivacyPoolsSection.allCases.filter(\.isConditional).sorted { $0.rawValue < $1.rawValue }
        == [PrivacyPoolsSection.review, .shielded].sorted { $0.rawValue < $1.rawValue })
check("one scope is not a control",
      !PrivacyPoolsSection.shows(present: [.activity]))
check("two are", PrivacyPoolsSection.shows(present: [.activity, .review]))
// A remembered scope whose content has gone must land on the FEED, never on
// "whatever is first" — the two differ only when activity is somehow absent,
// which is the branch that would quietly open a room somewhere nobody chose.
check("a scope that no longer exists falls back to activity",
      PrivacyPoolsSection.resolve(.shielded, present: [.activity, .review]) == .activity)
// THE FIXTURE ABOVE CANNOT TELL THE RULE FROM ITS MUTATION, and this one is
// why it is here: `order` puts `.activity` first, so "fall back to the feed"
// and "fall back to whatever is first" give the same answer for every list
// production can actually build — the mutation swapping one for the other
// survived on the first run, green. The discriminating case is the branch the
// type's own doc says cannot happen: a `present` without `.activity` in it.
// That is exactly the point of naming the fallback rather than taking the
// head — an unreachable branch that quietly picks a different scope is how a
// room starts opening somewhere nobody chose.
//
// Standing rule, earned again: a fixture only tests the rule it names if it
// FAILS that rule and passes every other one.
check("the fallback is the feed by NAME, not whatever happens to be first",
      PrivacyPoolsSection.resolve(.shielded, present: [.review]) == .activity)
check("nothing remembered opens the feed",
      PrivacyPoolsSection.resolve(nil, present: ppAll) == .activity)
check("a remembered scope that still exists is honoured",
      PrivacyPoolsSection.resolve(.review, present: ppAll) == .review)
// EARNED, never mere presence: a deposit in review is this room's NORMAL
// state, and a dot on every one of them is a dot nobody reads.
check("being in review earns no dot",
      PrivacyPoolsSection.attention(needsProof: false, declined: false, present: ppAll).isEmpty)
check("proof required earns one",
      PrivacyPoolsSection.attention(needsProof: true, declined: false, present: ppAll) == [.review])
check("a decline earns one too — the money sits there until you reclaim it",
      PrivacyPoolsSection.attention(needsProof: false, declined: true, present: ppAll) == [.review])
check("no dot on a scope that isn't offered",
      PrivacyPoolsSection.attention(needsProof: true, declined: true,
                                    present: [.activity]).isEmpty)
// Presence and rendering are one question. The card draws the shielded reading
// on exactly `holdingsLine != nil`, and the review reading on segments-or-
// untagged; a room that offers a chip its card then declines to fill is §83's
// dead control wearing a scope's clothes (§483 shipped exactly that once).
check("shielded presence is exactly the money line's own gate",
      (PrivacyPoolsRoom.holdingsLine(held) != nil) == !held.holdings.isEmpty)
check("a room of only untagged deposits still earns Review — the legend has a row",
      { let bare = PrivacyPoolsRoom.compose(rows: [pp("privacypools:dep:1")])
        return bare.segments.isEmpty && bare.untagged > 0
      }())

print("")
print("Privacy Pools — the two scope captions (prd §486)")
check("the shielded caption names deposits it could not price",
      (PrivacyPoolsRoom.shieldedNote(PrivacyPoolsRoom.compose(rows: [
          ppa("privacypools:dep:1", ["Pending"], "ETH", 0.07),
          pp("privacypools:dep:2", ["Pending"]),
      ])) ?? "").contains("1 deposit's size is unknown"))
check("a room with nothing to qualify says nothing",
      PrivacyPoolsRoom.shieldedNote(PrivacyPoolsRoom.compose(rows: [
          ppa("privacypools:dep:1", ["Pending"], "ETH", 0.07)])) == nil)
// The clauses went to the scope each is ABOUT. A review time and an idle gap
// are facts about what happened; an unreadable size is a caveat on a figure.
check("the activity caption carries the observed review time, not the money one",
      (PrivacyPoolsRoom.activityNote(pools, now: t0) ?? "").contains("review has taken")
        && !(PrivacyPoolsRoom.shieldedNote(pools) ?? "").contains("review has taken"))
check("a room with nothing to add says nothing",
      PrivacyPoolsRoom.activityNote(PrivacyPoolsRoom.compose(rows: [
          pp("privacypools:dep:1", ["Pending"], at: day(-1))]), now: t0) == nil)

// THE NOTE MUST NOT CLAIM A REVIEW FINISHED THAT WAS NEVER RECORDED. `waiting`
// counts SEGMENTS, and a room of pre-§311 deposits has none — so the
// `waiting == 0` branch fired and announced "Every review is finished" over
// deposits whose standing is entirely unknown, one line under a headline that
// had just correctly declined to say it (found and fixed 2026-08-26).
check("a wholly untagged room says its standing isn't recorded",
      PrivacyPoolsRoom.note(PrivacyPoolsRoom.compose(rows: [
          pp("privacypools:dep:1"), pp("privacypools:dep:2")]))
        == "Where these stand isn't recorded")

// ===========================================================================
print("")
print("Gnosis Pay — composing")
// ===========================================================================

func spend(_ amount: Double?, _ code: String?, at: Date) -> GnosisPayRoom.Sighting {
    GnosisPayRoom.Sighting(amount: amount, currency: code, at: at)
}

let gnosis = GnosisPayRoom.compose(spends: [
    spend(12.50, "EUR", at: day(-1)),
    spend(30.00, "EUR", at: day(-10)),
    spend(7.50,  "GBP", at: day(-3)),
    spend(nil,   "EUR", at: day(-5)),      // decimals never resolved
    spend(9.99,  nil,   at: day(-5)),      // no currency
    spend(20.00, "EUR", at: day(-40)),     // the window before
    spend(5.00,  "EUR", at: day(-200)),    // old enough to prove we were watching
], now: t0)
check("the window's spends are summed per currency",
      gnosis.lead?.code == "EUR" && abs((gnosis.lead?.total ?? 0) - 42.50) < 0.0001)
// EUR + GBP is an exchange rate this app does not have.
check("currencies are never summed into one figure", gnosis.currencies.count == 2)
check("the second currency keeps its own total",
      abs((gnosis.currencies.last?.total ?? 0) - 7.50) < 0.0001)
// A zero is a spend of nothing, which is a different and false claim. BOTH
// shapes land here: no amount, and an amount with no currency to put it in.
check("an unreadable amount is counted, never treated as zero", gnosis.unpriced == 2)
check("a missing amount alone is counted",
      GnosisPayRoom.compose(spends: [spend(nil, "EUR", at: day(-1))], now: t0).unpriced == 1)
check("a missing CURRENCY alone is counted too — it drops from every total",
      GnosisPayRoom.compose(spends: [spend(9.99, nil, at: day(-1))], now: t0).unpriced == 1)
check("the window's spend count excludes the unpriced", gnosis.lead?.spends == 2)
check("all-time counts every row the room holds", gnosis.allTime == 7)
check("the oldest spend is remembered", gnosis.oldest == day(-200))

print("")
print("Gnosis Pay — the comparison is refused rather than estimated")
check("the prior window is known when history reaches past it",
      GnosisPayRoom.knowsPriorWindow(oldest: day(-200), now: t0))
// A first sync backfills about six days. The prior window is then not quiet,
// it is unobserved — and "up 400%" against it would be a fabrication.
check("a young room knows nothing about the window before",
      GnosisPayRoom.knowsPriorWindow(oldest: day(-6), now: t0) == false)
check("a room with no spends at all knows nothing",
      GnosisPayRoom.knowsPriorWindow(oldest: nil, now: t0) == false)
check("the prior total is carried when it is knowable",
      abs((gnosis.lead?.prior ?? 0) - 20.00) < 0.0001)
let young = GnosisPayRoom.compose(spends: [spend(10, "EUR", at: day(-2))], now: t0)
check("a young room carries no prior at all", young.lead?.prior == nil)
check("and says so out loud rather than leaving a blank",
      GnosisPayRoom.note(young).contains("not watching long enough to compare"))

print("")
print("Gnosis Pay — the change")
func cur(_ total: Double, prior: Double?, spends: Int = 3) -> GnosisPayRoom.Currency {
    GnosisPayRoom.Currency(code: "EUR", total: total, spends: spends, prior: prior, newest: t0)
}
check("a rise is a fraction", abs((GnosisPayRoom.delta(cur(120, prior: 100)) ?? 0) - 0.2) < 0.0001)
check("a fall is negative", (GnosisPayRoom.delta(cur(80, prior: 100)) ?? 0) < 0)
// Coming back from nothing has no percentage, and printing +100% for it is an
// arithmetic accident.
check("a zero prior window does not divide", GnosisPayRoom.delta(cur(50, prior: 0)) == nil)
check("an unknown prior claims nothing", GnosisPayRoom.delta(cur(50, prior: nil)) == nil)
// Card spending is lumpy — one weekly shop lands differently in two windows.
check("a small move is noise and gets no word", GnosisPayRoom.deltaLabel(cur(105, prior: 100)) == nil)
check("a real rise is stated in words",
      GnosisPayRoom.deltaLabel(cur(130, prior: 100)) == "30% more than the 30 days before")
check("a real fall is stated in words",
      GnosisPayRoom.deltaLabel(cur(70, prior: 100)) == "30% less than the 30 days before")

print("")
print("Gnosis Pay — the history strip")
// This head OUTRANKS `FeedInsight.cardMonths`, the 12-month leaderboard the
// room drew before it. A head that showed less than the card it displaced would
// be a regression wearing a new feature, so the months come with it.
func monthsOf(_ n: Int, _ code: String = "EUR", each: Double = 10) -> [GnosisPayRoom.Sighting] {
    (0..<n).map { spend(each, code, at: cal.date(byAdding: .month, value: -$0, to: t0)!) }
}
let hist = GnosisPayRoom.compose(spends: monthsOf(5), now: t0)
check("a month per month of history", hist.months.count == 5)
// Oldest first, so the strip reads left to right as time.
check("the strip runs oldest to newest",
      hist.months.map(\.key) == hist.months.map(\.key).sorted())
check("each month carries its own total and count",
      hist.months.allSatisfy { $0.spends == 1 && abs($0.total - 10) < 0.0001 })
// A month key must survive a year boundary, which a bare month number does not.
let dec = cal.date(from: DateComponents(year: 2025, month: 12, day: 15))!
let jan = cal.date(from: DateComponents(year: 2026, month: 1, day: 15))!
check("December sorts before the January after it",
      GnosisPayRoom.monthKey(dec)! < GnosisPayRoom.monthKey(jan)!)
check("a key round-trips to the month it names",
      GnosisPayRoom.monthKey(GnosisPayRoom.monthStart(key: GnosisPayRoom.monthKey(dec)!)!)
        == GnosisPayRoom.monthKey(dec))
// A one-column history is not a history — one lone bar reads as a level.
check("one month draws no strip", GnosisPayRoom.compose(spends: monthsOf(1), now: t0).months.isEmpty)
// Silent truncation: a dropped month looks exactly like a quiet one.
let long = GnosisPayRoom.compose(spends: monthsOf(20), now: t0)
check("the strip is capped", long.months.count == GnosisPayRoom.monthCap)
check("and the months it dropped are COUNTED, not silently truncated",
      long.monthsHidden == 20 - GnosisPayRoom.monthCap)
check("the cap keeps the NEWEST months",
      long.months.last?.key == GnosisPayRoom.monthKey(t0))
// The strip follows the currency the HEADLINE states, so one card is never
// about two different sorts of money.
let mixed = GnosisPayRoom.compose(spends:
    monthsOf(4, "EUR") + monthsOf(4, "GBP") + [spend(1, "EUR", at: day(-1))], now: t0)
check("the strip follows the lead currency", mixed.lead?.code == "EUR")
check("spends in another currency are counted, not folded in",
      mixed.monthsOtherCurrency == 4)
check("the caption names the currency it drew",
      (GnosisPayRoom.historyNote(mixed) ?? "").contains("EUR"))
check("and says what it left out",
      (GnosisPayRoom.historyNote(mixed) ?? "").contains("in other currencies"))
check("no strip, no caption",
      GnosisPayRoom.historyNote(GnosisPayRoom.compose(spends: monthsOf(1), now: t0)) == nil)
// Scaled against the biggest DRAWN month: scaling to one off the end of the
// strip would flatten every visible column against something nobody can see.
check("the tallest drawn month is full height", GnosisPayRoom.monthShare(total: 50, of: 50) == 1)
check("half is half", GnosisPayRoom.monthShare(total: 25, of: 50) == 0.5)
check("a zero peak can't divide by zero", GnosisPayRoom.monthShare(total: 5, of: 0) == 0)
check("a month abbreviates", GnosisPayRoom.monthLabel(dec, locale: us) == "Dec")

print("")
print("Gnosis Pay — ranking never compares magnitudes across currencies")
func c(_ code: String, spends: Int, total: Double, at: Date = t0) -> GnosisPayRoom.Currency {
    GnosisPayRoom.Currency(code: code, total: total, spends: spends, prior: nil, newest: at)
}
// 400 EUR against 380 GBP is the cross-currency sum this file refuses, wearing
// a sort instead of a plus.
check("more spends wins, even against a bigger total in another currency",
      GnosisPayRoom.ordered([c("GBP", spends: 2, total: 9000),
                             c("EUR", spends: 9, total: 10)]).first?.code == "EUR")
check("a tie breaks on recency",
      GnosisPayRoom.ordered([c("GBP", spends: 2, total: 1, at: day(-9)),
                             c("EUR", spends: 2, total: 1, at: day(-1))]).first?.code == "EUR")
check("a full tie breaks on code",
      GnosisPayRoom.ordered([c("USD", spends: 2, total: 1),
                             c("EUR", spends: 2, total: 1)]).first?.code == "EUR")
check("the bar is a share of the spend COUNT", GnosisPayRoom.share(spends: 3, of: 6) == 0.5)
check("a zero denominator can't divide by zero", GnosisPayRoom.share(spends: 3, of: 0) == 0)

print("")
print("Gnosis Pay — words")
check("money is rendered in its own currency",
      GnosisPayRoom.money(42.5, code: "GBP", locale: us) == "£42.50")
check("a zero-decimal currency is not forced to two",
      GnosisPayRoom.money(1200, code: "JPY", locale: us) == "¥1,200")
check("a single-currency headline states the money and the window",
      GnosisPayRoom.headline(young, locale: us) == "€10.00 on your card in 30 days")
check("several currencies are named as several, never added",
      GnosisPayRoom.headline(gnosis, locale: us).contains("plus another currency"))
// The honest reading a list of old rows never states.
let quiet = GnosisPayRoom.compose(spends: [spend(10, "EUR", at: day(-90))], now: t0)
check("a quiet window on a real room says so",
      GnosisPayRoom.headline(quiet) == "Nothing spent in the last 30 days")
check("and the room still draws rather than vanishing", !quiet.isEmpty)
check("an unused card is stated once the gap outruns the window",
      GnosisPayRoom.idleNote(newest: day(-90), now: t0) == "unused for 90 days")
// It must never contradict a headline that just reported spending in the
// window.
check("a card used inside the window is never called unused",
      GnosisPayRoom.idleNote(newest: day(-3), now: t0) == nil)
check("a room with no spends at all is no card", GnosisPayRoom.compose(spends: [], now: t0).isEmpty)
let gpFoot = GnosisPayRoom.footnote(gnosis, now: t0) ?? ""
check("unreadable spends are named — that is money missing from the total above",
      gpFoot.contains("2 spends have no readable amount"))

print("")
print("Railgun — reading a row")
check("a shield is read from its ref", RailgunRoom.direction(ref: "railgun:shield:0xabc:0") == .shield)
check("an unshield is read from its ref", RailgunRoom.direction(ref: "railgun:unshield:0xabc:0") == .unshield)
check("a ref this build doesn't know is nil, never guessed",
      RailgunRoom.direction(ref: "railgun:0xabc") == nil)
check("no ref at all is nil", RailgunRoom.direction(ref: nil) == nil)

func move(_ ref: String, token: String? = nil, amount: Double? = nil, at: Date = t0) -> RailgunRoom.Sighting {
    RailgunRoom.Sighting(ref: ref, token: token, amount: amount, at: at)
}

print("")
print("Railgun — composing")
let railgun = RailgunRoom.compose(moves: [
    move("railgun:shield:1:0", token: "ETH", amount: 1.0, at: day(-1)),
    move("railgun:shield:2:0", token: "ETH", amount: 2.0, at: day(-3)),
    move("railgun:unshield:3:0", token: "ETH", amount: 0.5, at: day(-5)),
    move("railgun:shield:4:0", token: "USDC", amount: 100, at: day(-2)),
    move("railgun:shield:5:0", at: day(-6)),                    // no token at all
    move("railgun:shield:6:0", token: "WBTC", at: day(-1)),     // token known, amount not
])
check("shields are counted", railgun.shields == 5)
check("unshields are counted apart", railgun.unshields == 1)
// Counted as a shield AND as unplaced: the move is real, the token is not known.
check("a move with no readable token is counted, not bucketed", railgun.unplaced == 1)
check("no 'Unknown' token was invented", railgun.tokens.allSatisfy { $0.symbol != "Unknown" })
check("three real tokens", railgun.tokens.count == 3)
check("the busiest token leads", railgun.lead?.symbol == "ETH")
check("a token counts both directions", railgun.lead?.moves == 3)
check("the newest move dates the room, regardless of token", railgun.newest == day(-1))

print("")
print("Railgun — token amounts")
let eth = railgun.tokens.first { $0.symbol == "ETH" }!
check("a token's shielded amount sums only its shields", eth.shieldedAmount == 3.0)
check("a token's unshielded amount sums only its unshields", eth.unshieldedAmount == 0.5)
let wbtc = railgun.tokens.first { $0.symbol == "WBTC" }!
check("a token with an unknown amount states no total at all, never a partial one",
      wbtc.shieldedAmount == nil)

print("")
print("Railgun — ranking is total")
func rgToken(_ s: String, shields: Int, unshields: Int = 0, at: Date = t0) -> RailgunRoom.Token {
    RailgunRoom.Token(symbol: s, shields: shields, unshields: unshields,
                      shieldedAmount: nil, unshieldedAmount: nil, newest: at)
}
check("more moves wins",
      RailgunRoom.ordered([rgToken("A", shields: 1), rgToken("B", shields: 9)]).first?.symbol == "B")
check("more moves wins even against a fresher runner-up",
      RailgunRoom.ordered([rgToken("A", shields: 9, at: day(-9)),
                           rgToken("B", shields: 1, at: day(-1))]).first?.symbol == "A")
check("a tie on moves breaks on recency",
      RailgunRoom.ordered([rgToken("A", shields: 2, at: day(-9)),
                           rgToken("B", shields: 2, at: day(-1))]).first?.symbol == "B")
check("a full tie breaks on symbol",
      RailgunRoom.ordered([rgToken("B", shields: 2, at: t0),
                           rgToken("A", shields: 2, at: t0)]).first?.symbol == "A")

print("")
print("Railgun — words")
check("the headline names the leading token", RailgunRoom.headline(railgun).contains("ETH"))
// One token means one row labelled with it, so a headline naming it too said
// the same word twice within fourteen points (2026-08-26).
check("a single-token room does not name that token in the headline as well",
      RailgunRoom.headline(RailgunRoom.compose(moves: [
        move("railgun:shield:a:0", token: "ETH", amount: 1),
        move("railgun:shield:b:0", token: "ETH", amount: 2),
      ])) == "2 moves through Railgun")
check("a card with no moves at all says so",
      RailgunRoom.headline(RailgunRoom.compose(moves: [])) == "Nothing has moved yet")
let rgFoot = RailgunRoom.footnote(railgun, drawn: 3, now: t0) ?? ""
check("unplaced moves are named — a move missing from every token bucket above",
      rgFoot.contains("1 move has no readable token"))
check("a room with no moves at all is no card", RailgunRoom.compose(moves: []).isEmpty)

print("")
print("Railgun — the direction pair (2026-08-26)")
// The drawing that REPLACED `share`, which was a fraction of the busiest
// token's MOVE COUNT sitting under a line of text stating an AMOUNT — a bar
// that read as a picture of the number printed beside it. This one is scaled
// to the token's OWN maximum, because no two tokens here share a unit.
func rgFull(_ s: String, shields: Int, unshields: Int,
            shielded: Double?, back: Double?) -> RailgunRoom.Token {
    RailgunRoom.Token(symbol: s, shields: shields, unshields: unshields,
                      shieldedAmount: shielded, unshieldedAmount: back, newest: t0)
}
let ethPair = RailgunRoom.pair(eth)          // 3.0 shielded, 0.5 back
check("the bigger side fills the row", ethPair?.into == 1)
check("the other side is drawn against it, on this token's own scale",
      abs((ethPair?.back ?? 0) - 0.5 / 3.0) < 0.0001)
check("a side whose amount could not be read draws NOTHING — half a pair is not a comparison",
      RailgunRoom.pair(wbtc) == nil)
// A direction with no moves is a real zero, and telling that apart from an
// unknown is the whole reason `pair` reads the COUNT before the amount: a
// token nothing ever came back from must draw its one line, not vanish.
let rgBackOnly = rgFull("BACK", shields: 0, unshields: 1, shielded: nil, back: 2)
check("a direction with no moves is a real zero, never an unknown",
      RailgunRoom.pair(rgBackOnly)?.into == 0)
check("…and the side that did move fills the row", RailgunRoom.pair(rgBackOnly)?.back == 1)
// MORE CAME BACK THAN WENT IN is the COMMON case here, not a corner:
// `RailgunBridge`'s own ceiling is that only about half of shields are
// attributable at all, so the in-side is routinely the short one.
let rgMoreBack = rgFull("MORE", shields: 1, unshields: 1, shielded: 1, back: 4)
check("more back than in still fits inside the row", RailgunRoom.pair(rgMoreBack)?.back == 1)
check("…and the shorter side is drawn against the longer one",
      RailgunRoom.pair(rgMoreBack)?.into == 0.25)
check("a token that moved nothing on either side draws nothing",
      RailgunRoom.pair(rgFull("ZERO", shields: 0, unshields: 0, shielded: nil, back: nil)) == nil)

print("")
print("Safe — ranking is your-turn first, then ready, then oldest first")
func safeEntry(_ ref: String, have: Int = 1, required: Int = 3, yourTurn: Bool = false,
               submittedAt: Date? = nil, nonce: Int? = nil,
               safe: String = "0xSafe", description: String = "a transfer") -> SafeRoom.Entry {
    SafeRoom.Entry(ref: ref, safeAddress: safe, have: have, required: required,
                   yourTurn: yourTurn, submittedAt: submittedAt, descriptionText: description,
                   nonce: nonce)
}
check("your turn always outranks waiting on others, even when it arrived later",
      SafeRoom.ordered([safeEntry("a", yourTurn: false, submittedAt: day(-9)),
                        safeEntry("b", yourTurn: true, submittedAt: day(-1))]).first?.ref == "b")
check("within the same group, the longest-waiting entry leads",
      SafeRoom.ordered([safeEntry("a", submittedAt: day(-1)),
                        safeEntry("b", submittedAt: day(-9))]).first?.ref == "b")
check("a nil submittedAt sorts as if it arrived at the dawn of time — never hides a real wait behind an unknown one",
      SafeRoom.ordered([safeEntry("a", submittedAt: day(-1)),
                        safeEntry("b", submittedAt: nil)]).first?.ref == "b")
check("a full tie breaks on ref, for a total order that never reshuffles on identical data",
      SafeRoom.ordered([safeEntry("b"), safeEntry("a")]).first?.ref == "a")

print("")
print("Safe — fully signed is not pending (2026-08-17)")
// THE FALSE ALARM THIS FIXES. `yourTurn` is `!hasSigned(you)` alone, so a
// 2-of-3 whose other two owners both signed said "your signature is needed",
// ranked it first, and fired a lock-screen alarm — for a transaction that
// needs nothing from you.
check("a met threshold is ready, not pending",
      safeEntry("a", have: 3, required: 3).isReady)
check("an unread threshold is never 'ready' — 0/0 is no evidence at all",
      !safeEntry("a", have: 0, required: 0).isReady)
check("more signatures than required is still ready, never a fourth state",
      safeEntry("a", have: 4, required: 3).isReady)
check("your signature can't be needed on something already fully signed without you",
      !safeEntry("a", have: 2, required: 2, yourTurn: true).awaitsYou)
check("your signature IS needed when the threshold is genuinely short",
      safeEntry("a", have: 1, required: 2, yourTurn: true).awaitsYou)
// The ready candidate is given the STRONGER raw position on purpose — it is
// really yourTurn and really newer — so this can only pass because `isReady`
// is being honoured, not because raw wait already ordered them.
let safeReadyRank = SafeRoom.ordered([
    safeEntry("ready", have: 3, required: 3, yourTurn: true, submittedAt: day(-1)),
    safeEntry("short", have: 1, required: 3, yourTurn: true, submittedAt: day(-9)),
])
check("a genuinely-short signature outranks a fully-signed one — only you can add yours",
      safeReadyRank.first?.ref == "short")
let safeReadyOverWaiting = SafeRoom.ordered([
    safeEntry("waiting", have: 1, required: 3, yourTurn: false, submittedAt: day(-9)),
    safeEntry("ready", have: 3, required: 3, yourTurn: false, submittedAt: day(-1)),
])
check("fully-signed outranks still-collecting even when it arrived later",
      safeReadyOverWaiting.first?.ref == "ready")
let safeRoomReady = SafeRoom.compose(
    entries: [safeEntry("a", have: 3, required: 3, submittedAt: day(-2))], safeCount: 1)
check("a fully-signed queue says 'ready to execute', never 'waiting on others'",
      SafeRoom.headline(safeRoomReady).contains("ready to execute")
      && !SafeRoom.headline(safeRoomReady).contains("waiting on others"))
check("a fully-signed transaction is not counted as a pending signature",
      safeRoomReady.readyCount == 1 && safeRoomReady.awaitsYouCount == 0)
let safeRoomBoth = SafeRoom.compose(
    entries: [safeEntry("a", have: 1, required: 3, yourTurn: true, submittedAt: day(-2)),
              safeEntry("b", have: 3, required: 3, submittedAt: day(-2))], safeCount: 1)
check("the ready count the headline couldn't carry lands in the state note",
      SafeRoom.stateNote(safeRoomBoth)?.contains("ready to execute") == true)
check("the state note never restates a headline that already led with ready",
      SafeRoom.stateNote(safeRoomReady) == nil)

print("")
print("Safe — rival transactions at one nonce (2026-08-17)")
// A Safe executes exactly ONE transaction per nonce, so a signature spent on
// the loser is spent for nothing (§238). Rivals share a Safe AND a nonce.
// The unrelated entry sits BETWEEN the pair by age on purpose. The first
// version of this fixture dated them -2/-1/-3, which plain age-sorting
// already returns as c,a,b — so the pair was adjacent by accident and the
// regroup mutation survived while the check read green (the harness trap this
// file's siblings have paid for twice).
let safeRivals = [safeEntry("a", submittedAt: day(-9), nonce: 7),
                  safeEntry("b", submittedAt: day(-1), nonce: 7),
                  safeEntry("c", submittedAt: day(-5), nonce: 8)]
let safeRivalRoom = SafeRoom.compose(entries: safeRivals, safeCount: 1)
check("two transactions at one nonce are contested", safeRivalRoom.contestedCount == 2)
check("a lone transaction at its own nonce is not contested",
      !safeRivalRoom.isContested(safeEntry("c", submittedAt: day(-5), nonce: 8)))
check("an unknown nonce is never called a rival — we can't prove a collision we can't see",
      SafeRoom.contestedKeys(in: [safeEntry("a", nonce: nil), safeEntry("b", nonce: nil)]).isEmpty)
check("the same nonce on two DIFFERENT Safes is not a collision",
      SafeRoom.contestedKeys(in: [safeEntry("a", nonce: 7, safe: "0xOne"),
                                  safeEntry("b", nonce: 7, safe: "0xTwo")]).isEmpty)
// The regroup is the point: ranked strictly by wait this is a, c, b — the
// unrelated entry wedged between the rivals — and a pair that reads as two
// unrelated rings invites exactly the wasted signature this warning exists to
// prevent.
check("rivals are drawn adjacent, even when an unrelated entry sorts between them",
      Array(safeRivalRoom.entries.map { $0.ref }.prefix(3)) == ["a", "b", "c"])
check("the regroup keeps every entry exactly once",
      Set(safeRivalRoom.entries.map { $0.ref }).count == 3)
check("a rival pair is said out loud, and says only one of them can execute",
      SafeRoom.stateNote(safeRivalRoom)?.contains("only one of them can execute") == true)
let safeTwoGroups = SafeRoom.compose(
    entries: [safeEntry("a", nonce: 7), safeEntry("b", nonce: 7),
              safeEntry("c", nonce: 9), safeEntry("d", nonce: 9)], safeCount: 1)
check("two contested positions are counted as positions, not folded into one",
      SafeRoom.stateNote(safeTwoGroups)?.contains("2 queue positions") == true)
check("a rival warning outranks the ready count in the one note slot",
      SafeRoom.stateNote(SafeRoom.compose(
        entries: [safeEntry("a", have: 1, required: 3, yourTurn: true, nonce: 7),
                  safeEntry("b", have: 1, required: 3, nonce: 7),
                  safeEntry("c", have: 3, required: 3)],
        safeCount: 1))?.contains("only one of them can execute") == true)

print("")
print("Safe — words")
let safeRoomYourTurn = SafeRoom.compose(
    entries: [safeEntry("a", have: 2, required: 3, yourTurn: true, submittedAt: day(-2))],
    safeCount: 1)
check("your-turn count leads the headline over a bare pending count",
      SafeRoom.headline(safeRoomYourTurn).contains("Your signature is needed"))
let safeRoomWaiting = SafeRoom.compose(
    entries: [safeEntry("a", have: 1, required: 3, yourTurn: false, submittedAt: day(-2))],
    safeCount: 1)
check("nobody's turn but something is pending — 'waiting on others', not the your-turn wording",
      SafeRoom.headline(safeRoomWaiting).contains("waiting on others"))
let safeRoomQuiet = SafeRoom.compose(entries: [], safeCount: 2)
check("a quiet room with more than one Safe pluralises 'Safes'",
      SafeRoom.headline(safeRoomQuiet).contains("Safes"))
let safeRoomModule = SafeRoom.compose(entries: [], safeCount: 1,
                                      moduleSafes: [.init(label: "treasury.eth", count: 1)])
check("a module warning is stated even with nothing pending — the highest-stakes fact this bridge can carry",
      SafeRoom.note(safeRoomModule)?.contains("without a signature") == true)
check("with only one Safe watched there is nothing to disambiguate, so the name would be noise",
      SafeRoom.note(safeRoomModule)?.contains("treasury.eth") == false)
// Naming it is the whole point once there is more than one: "1 module can move
// funds without a signature" says a drain is possible and not WHERE.
let safeRoomModuleNamed = SafeRoom.compose(entries: [], safeCount: 3,
                                           moduleSafes: [.init(label: "treasury.eth", count: 1)])
check("with several Safes watched the module warning names the one it means",
      SafeRoom.note(safeRoomModuleNamed)?.contains("treasury.eth") == true)
let safeRoomModulesSpread = SafeRoom.compose(
    entries: [], safeCount: 3,
    moduleSafes: [.init(label: "treasury.eth", count: 2), .init(label: "ops.eth", count: 1)])
check("modules across several Safes count both the modules and the Safes",
      SafeRoom.note(safeRoomModulesSpread)?.contains("3 modules across 2 Safes") == true)
check("a Safe carrying no modules is not counted as a carrier",
      SafeRoom.note(SafeRoom.compose(entries: [], safeCount: 2,
                                     moduleSafes: [.init(label: "a.eth", count: 0)])) == nil)
check("no module means no note at all — a second sentence that says nothing doesn't get to exist",
      SafeRoom.note(safeRoomWaiting) == nil)
check("a Safe never detected at all is no card", SafeRoom.compose(entries: [], safeCount: 0).isEmpty)
check("today reads as 'today', not '0 days'",
      SafeRoom.waitLabel(safeEntry("a", submittedAt: t0), now: t0) == "today")
check("a nil submittedAt reads as 'waiting', never a fabricated duration",
      SafeRoom.waitLabel(safeEntry("a", submittedAt: nil), now: t0) == "waiting")
let safeFoot = SafeRoom.footnote(SafeRoom.compose(entries: [safeEntry("a"), safeEntry("b"), safeEntry("c"), safeEntry("d")],
                                                  safeCount: 1), drawn: 3)
check("entries beyond the row cap are counted in the footnote, never silently dropped",
      safeFoot == "1 more pending")

print("")
print("Safe — the row's own words (2026-08-24, prd §464)")
// The card drew a 60pt ring per entry and said the state in COLOUR alone —
// tint for your turn, green for ready, tertiary for everything else, painted
// onto the wait caption. Three rings reading "3 days" in three tints are one
// ring in greyscale, in a PDF export, and to a red-green viewer. Every failure
// here renders as a perfectly ordinary row.
check("your turn is a WORD, not a tint",
      SafeRoom.stateLabel(safeEntry("a", have: 1, required: 3, yourTurn: true)) == "Your turn")
check("a met threshold says the act, not the wait",
      SafeRoom.stateLabel(safeEntry("a", have: 3, required: 3)) == "Ready to execute")
// Your turn OUTRANKS ready in the sentence exactly as it does in `ordered`:
// anybody can execute a signed transaction and only you can add your signature.
check("a transaction that is BOTH yours and short still leads with your turn",
      SafeRoom.stateLabel(safeEntry("a", have: 2, required: 3, yourTurn: true)) == "Your turn")
check("a fully-signed transaction you never signed is ready, never your turn",
      SafeRoom.stateLabel(safeEntry("a", have: 2, required: 2, yourTurn: true)) == "Ready to execute")
// It counts SIGNATURES and never people: this card holds no owner roster (that
// is SafeQueueCard's, one screen deeper), so "2 others" would be a claim about
// WHO built from a number that only says how many more.
check("the waiting form counts signatures still needed",
      SafeRoom.stateLabel(safeEntry("a", have: 1, required: 3)) == "2 more signatures needed")
check("one short is singular",
      SafeRoom.stateLabel(safeEntry("a", have: 2, required: 3)) == "1 more signature needed")
// A transaction whose `confirmationsRequired` never parsed arrives as 0/0 —
// `isReady`'s own guard, one rung down. "0 more signatures needed" would be a
// claim about a threshold we could not read.
check("an unread threshold gets the bare word, never a fabricated shortfall",
      SafeRoom.stateLabel(safeEntry("a", have: 0, required: 0)) == "Waiting")

// The subject. It was cached on every entry and drawn ONLY inside the card's
// VoiceOver label, so a sighted reader got strictly less than a VoiceOver one.
check("the row is about what the transaction IS",
      SafeRoom.subject(safeEntry("a", description: "a transfer of 1,500 USDC to alice.eth"))
        == "a transfer of 1,500 USDC to alice.eth")
check("a description the bridge never cached falls back to a noun, not to nothing",
      SafeRoom.subject(safeEntry("a", description: "")) == "Pending transaction")

// The queue position, for the pair the card used to mark with a 9pt glyph in a
// ring's corner. THE NONCE IS AN IDENTIFIER, NOT A QUANTITY: interpolating an
// Int into String(localized:) groups it, so position 1042 renders as
// "position 1,042" — §375's own defect (a year set as "2,019") in a second
// place, and one that renders perfectly.
check("a queue position is printed as a slot, never grouped as a quantity",
      SafeRoom.positionLabel(safeEntry("a", nonce: 1042)) == "position 1042")
check("a small nonce is unaffected either way",
      SafeRoom.positionLabel(safeEntry("a", nonce: 7)) == "position 7")
check("a nonce the wire never carried names no position rather than inventing one",
      SafeRoom.positionLabel(safeEntry("a", nonce: nil)) == nil)

print("")
print("Safe — the stuck-signature line the brief and the widget read")
// A your-turn signature notifies ONCE at landing and §306's 36-hour news
// window forbids a second buzz forever after, so this is the only surface that
// can ever re-raise a request nobody answered.
let safeStuck = SafeRoom.compose(
    entries: [safeEntry("a", have: 1, required: 3, yourTurn: true, submittedAt: day(-6),
                        description: "a transfer of 1,500 USDC to payroll.eth")],
    safeCount: 1)
check("a signature waiting past the floor is measured in whole days",
      SafeRoom.stuckDays(safeStuck, now: t0) == 6)
check("the line names what is actually being asked of you",
      SafeRoom.stuckLine(safeStuck, now: t0)?.contains("payroll.eth") == true)
check("a request from this morning is not 'stuck' — that would just repeat yesterday's notification",
      SafeRoom.stuckLine(SafeRoom.compose(
        entries: [safeEntry("a", have: 1, required: 3, yourTurn: true, submittedAt: day(-1))],
        safeCount: 1), now: t0) == nil)
check("nothing awaiting you means nothing stuck, however old the queue is",
      SafeRoom.stuckDays(SafeRoom.compose(
        entries: [safeEntry("a", have: 1, required: 3, yourTurn: false, submittedAt: day(-40))],
        safeCount: 1), now: t0) == nil)
check("a fully-signed transaction is never reported as a stuck signature",
      SafeRoom.stuckDays(SafeRoom.compose(
        entries: [safeEntry("a", have: 3, required: 3, yourTurn: true, submittedAt: day(-40))],
        safeCount: 1), now: t0) == nil)
check("an unknown submission date yields no duration rather than a fabricated one",
      SafeRoom.stuckDays(SafeRoom.compose(
        entries: [safeEntry("a", have: 1, required: 3, yourTurn: true, submittedAt: nil)],
        safeCount: 1), now: t0) == nil)

print("")
if failures > 0 { print("\(failures) failed"); exit(1) }
print("all assertions passed")
SWIFT

echo "wallet-rooms-selftest: compiling the five heads and the scope enum WHOLE and unmodified…"
swiftc -O -o "$TMP/run" "$PEER" "$POOLS" "$GNOSIS" "$RAILGUN" "$SAFE" "$SECTION" "$TMP/main.swift" \
  || { echo "✗ the shipped room heads do not compile Foundation-only — something reached Thing/SwiftUI"; exit 1; }
"$TMP/run" || exit 1

# --- mutation pass ----------------------------------------------------------
# Every mutation below is a silent wrong answer that renders perfectly. A
# mutation that survives means nothing here was testing that line.
echo ""
echo "mutations (each must be caught):"

mutate() {
  local name="$1" which="$2" frm="$3" to="$4"
  cp "$PEER" "$TMP/PeerRoom.swift"
  cp "$POOLS" "$TMP/PrivacyPoolsRoom.swift"
  cp "$GNOSIS" "$TMP/GnosisPayRoom.swift"
  cp "$RAILGUN" "$TMP/RailgunRoom.swift"
  cp "$SAFE" "$TMP/SafeRoom.swift"
  cp "$SECTION" "$TMP/PrivacyPoolsSection.swift"
  local a="$TMP/PeerRoom.swift" b="$TMP/PrivacyPoolsRoom.swift" c="$TMP/GnosisPayRoom.swift" d="$TMP/RailgunRoom.swift" e="$TMP/SafeRoom.swift" g="$TMP/PrivacyPoolsSection.swift"
  local target
  case "$which" in
    peer)    target="$a" ;;
    pools)   target="$b" ;;
    gnosis)  target="$c" ;;
    railgun) target="$d" ;;
    safe)    target="$e" ;;
    section) target="$g" ;;
  esac
  FRM="$frm" TO="$to" python3 - "$target" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["FRM"], os.environ["TO"]
if frm not in src:
    sys.exit(1)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$target"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/mut" "$a" "$b" "$c" "$d" "$e" "$g" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# THE Peer bug: every ref begins `peer:`, so testing the bare prefix first folds
# the whole sell side into the buy side. A room reporting that you only ever
# buy, on an account that mostly sells, renders perfectly.
mutate "the bare peer: prefix is tested before peer:sell:" peer \
  '        ("peer:sell:", .sold),
        ("peer:expired:", .fellThrough),
        ("peer:", .bought),' \
  '        ("peer:", .bought),
        ("peer:sell:", .sold),
        ("peer:expired:", .fellThrough),'
# An expired row is stamped when we LOOKED. Letting it date the room makes a
# dormant account read as active this morning.
mutate "a fall-through is allowed to date the room" peer \
  '            guard kind.settled else { fellThrough += 1; continue }
            // Over SETTLED fills only — an expired row'"'"'s date is when we
            // looked, not when anything happened.
            if newest == nil || sighting.at > newest! { newest = sighting.at }' \
  '            if newest == nil || sighting.at > newest! { newest = sighting.at }
            guard kind.settled else { fellThrough += 1; continue }'
# A rail nobody named, invented and then ranked beside the real ones. Written
# to COMPILE rather than to trip the type-checker: a mutation rejected at build
# proves the edit was malformed, not that anything was testing the behaviour.
mutate "an unplaced fill is bucketed under an invented rail" peer \
  '            let name = sighting.rail?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let name, !name.isEmpty else { unplaced += 1; continue }' \
  '            let name = sighting.rail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown"'
# Without the last tiebreak the order comes off a dictionary and the card
# reshuffles between opens over identical data.
mutate "the rail order stops being total" peer \
  'return a.name < b.name' \
  'return a.name > b.name'
# Caught in this pass's own review: `unplaced` is a subset of `fills`, so adding
# them lets ONE unplaced fill clear the minimum and draw a card over a single
# row — the exact thing `minimumFills` exists to prevent.
mutate "unplaced fills are added to a total that already contains them" peer \
  'var isEmpty: Bool { fills < PeerRoom.minimumFills }' \
  'var isEmpty: Bool { fills + unplaced < PeerRoom.minimumFills }'
# A NaN-width capsule, which SwiftUI draws as nothing.
mutate "a zero denominator divides anyway" peer \
  'guard top > 0 else { return 0 }
        return min(max(Double(fills) / Double(top), 0), 1)' \
  'return min(max(Double(fills) / Double(top), 0), 1)'

# A claim about the screener made with no evidence — a deposit that cleared two
# months ago reported as still waiting.
mutate "an untagged deposit defaults to pending" pools \
  '    static func state(tags: [String]) -> State? {
        for tag in tags {
            if let found = State(rawValue: tag) { return found }
        }
        return nil
    }' \
  '    static func state(tags: [String]) -> State? {
        for tag in tags {
            if let found = State(rawValue: tag) { return found }
        }
        return .pending
    }'
# A cleared deposit counted twice — once as itself, once as its own alert.
mutate "an alert is counted as a second deposit" pools \
  'if ref.hasPrefix(statusPrefix) || ref.hasPrefix(poiPrefix) { return .alert }' \
  'if ref.hasPrefix(statusPrefix) || ref.hasPrefix(poiPrefix) { return .deposit(state(tags: tags)) }'
# One deposit stuck on proof, buried under forty that cleared — exactly on the
# accounts that use this seat most.
mutate "proof-required stops outranking everything" pools \
  'case .needsProof: return 4' \
  'case .needsProof: return 0'
# Partial knowledge drawn as complete: the bar fills, and the deposits nobody
# could place vanish out of the denominator.
mutate "untagged deposits drop out of the split's denominator" pools \
  'var deposits: Int { segments.reduce(0) { $0 + $1.count } + untagged }' \
  'var deposits: Int { segments.reduce(0) { $0 + $1.count } }'
# The mirror the whole card rests on. A raw value that stops matching the tag
# `retag` writes reads every deposit as untagged.
mutate "a state's raw value stops mirroring the bridge's tag" pools \
  'case needsProof   = "Needs proof"' \
  'case needsProof   = "NeedsProof"'
# A resolution dated before its own deposit is not evidence of anything, and
# using it anyway would let a clock oddity invent a negative — or worse, a
# fabricated positive — review time.
mutate "a review-time pair no longer checks the resolution came after the deposit" pools \
  'guard let resolved = resolvedAt[label], resolved >= landed else { return nil }' \
  'guard let resolved = resolvedAt[label] else { return nil }'

# --- prd §397: the loop, the money, the cover ------------------------------
# THE BUG THIS PASS EXISTS FOR. Without the join a deposit that was declined
# and then reclaimed keeps its `Declined` tag for life, so the card goes on
# telling the person to reclaim money already in their wallet — forever, in the
# largest type on the room whose whole job is to say what still needs them.
mutate "a reclaimed deposit is no longer joined to its own ragequit" pools \
  'let out = label.map { reclaimed.contains($0) } ?? false' \
  'let out = false'
# The other direction: a ragequit that resolved a deposit is reported once, as
# that deposit. Counting it again is the same double-count the alert exclusion
# already refuses one line up.
mutate "a joined ragequit is counted a second time as an orphan" pools \
  'unattachedReclaims: max(reclaimRows - attachedReclaims, 0),' \
  'unattachedReclaims: reclaimRows,'
# A decline is NOT an exit — the money sits in the pool until it is reclaimed,
# which is the entire reason the two are separate states.
mutate "a reclaimed deposit is treated as still inside the pool" pools \
  'var inPool: Bool { self != .reclaimed }' \
  'var inPool: Bool { true }'
# Money already back in the wallet, counted as still shielded: a balance
# overstated by exactly the amount that left.
mutate "money taken back out is still counted as in the pools" pools \
  '                guard state?.inPool ?? true else { continue }' \
  '                guard true else { continue }'
# The note has to say "taken back out" BEFORE it says "every review is
# finished" — once it is all out, whether the reviews finished is not the fact.
mutate "an emptied room reports finished reviews instead of an empty pool" pools \
  'if room.inPools == 0 {' \
  'if room.inPools < 0 {'
# A partial sum presented as a total, which renders as a confident balance.
mutate "a sum missing one of its parts is presented as a total" pools \
  'amount: $0.value.complete ? $0.value.sum : nil' \
  'amount: $0.value.sum'
# An asset nobody named, invented and then ranked beside the real ones — the
# `PeerRoom` "Unknown rail" mutation, one room over.
mutate "an unpriced deposit is bucketed under an invented symbol" pools \
  '                guard let asset = sighting.asset, !asset.isEmpty else {
                    unpriced += 1
                    continue
                }' \
  '                let asset = sighting.asset ?? "Unknown"'
# Ranking assets by amount implies a conversion between them that this room
# refuses to make: it would put 500 USDC above 0.4 ETH on no basis at all.
mutate "holdings are ranked by amount across different tokens" pools \
  'if a.deposits != b.deposits { return a.deposits > b.deposits }' \
  'if (a.amount ?? 0) != (b.amount ?? 0) { return (a.amount ?? 0) > (b.amount ?? 0) }'
# Without the last tiebreak the order comes off a dictionary and the card
# reshuffles between opens over identical data.
mutate "the holdings order stops being total" pools \
  'return a.symbol < b.symbol' \
  'return a.symbol > b.symbol'
# At two significant figures a set that moved 3,947 → 3,961 renders as "up from
# 3,900 to 3,900" — a sentence that reads as broken rather than as the honest
# "no material change" it is.
mutate "growth is claimed when both figures round to the same number" pools \
  'guard let landed = cover.atLanding, landed > 0, cover.current > landed,
              roundedSet(landed) != now else {' \
  'guard let landed = cover.atLanding, landed > 0, cover.current > landed else {'
# A set that SHRANK narrated as growth — the one cover claim that would be
# flatly false rather than merely unhelpful.
mutate "a shrinking anonymity set is narrated as growth" pools \
  'guard let landed = cover.atLanding, landed > 0, cover.current > landed,' \
  'guard let landed = cover.atLanding, landed > 0, cover.current != landed,'
# Cover belongs to ONE pool. Joined to whatever reading came first, the card
# states some other pool'"'"'s set size as the cover for your asset.
mutate "cover is joined to whatever pool answered first" pools \
  'return covers.first { $0.symbol == holding.symbol }' \
  'return covers.first'
# A cleared deposit finished waiting; how long it took is not the fact that
# matters once it has, and stating it makes every legend row look urgent.
mutate "a resolved state reports how long it waited" pools \
  'guard !segment.state.resolved, let oldestAt = segment.oldestAt else { return nil }' \
  'guard let oldestAt = segment.oldestAt else { return nil }'

# --- prd §486: the scopes, and the legend row that replaced the footnote -----
# A room whose every deposit's standing is unrecorded announcing "Every review
# is finished" — a claim about the screener made with no evidence, one line
# under a headline that had just correctly declined to make it.
mutate "an unrecorded standing is reported as a finished review" pools \
  'if room.segments.isEmpty {' \
  'if false, room.segments.isEmpty {'
# The untagged deposits ARE the gap in the split bar. Drop their legend row and
# the one unlabelled part of the drawing goes back to being undecodable — the
# §486 complaint restored, with the card still rendering perfectly.
mutate "the untagged deposits lose their legend row" pools \
  'if room.untagged > 0 {' \
  'if false, room.untagged > 0 {'
# Unknown is not a verdict, so it trails them. Ranked among them it would
# assert where "we do not know" sits relative to a decline.
mutate "unknown leads the legend instead of trailing it" pools \
  'rows.append(LegendRow(slice: .unknown, count: room.untagged, oldestAt: nil))' \
  'rows.insert(LegendRow(slice: .unknown, count: room.untagged, oldestAt: nil), at: 0)'
# The old single footnote became two captions, and each clause went to the
# reading it qualifies. Lose the review time and the Activity scope has nothing
# to say about what has actually happened here.
mutate "the observed review time drops out of the activity caption" pools \
  'if let reviewDays = room.reviewDays {' \
  'if false, let reviewDays = room.reviewDays {'
# A figure the card could not read, unsaid — the money line then presents
# partial knowledge as complete, which is the rule this room applies
# everywhere else.
mutate "an unreadable deposit size is no longer named beside the figure" pools \
  'if room.unpriced > 0 {' \
  'if false, room.unpriced > 0 {'
# THE SCOPE RULES. Each renders as a perfectly ordinary room.
mutate "a remembered scope resolves to whatever is first instead of the feed" section \
  'guard let wanted, present.contains(wanted) else { return .activity }' \
  'guard let wanted, present.contains(wanted) else { return present.first ?? .activity }'
mutate "the strip draws over a single scope" section \
  'static func shows(present: [PrivacyPoolsSection]) -> Bool { present.count > 1 }' \
  'static func shows(present: [PrivacyPoolsSection]) -> Bool { present.count > 0 }'
mutate "a conditional scope leads the strip" section \
  'static let order: [PrivacyPoolsSection] = [.activity, .shielded, .review]' \
  'static let order: [PrivacyPoolsSection] = [.review, .shielded, .activity]'
mutate "the dot fires on ordinary progress" section \
  'guard present.contains(.review), needsProof || declined else { return [] }' \
  'guard present.contains(.review) else { return [] }'
mutate "a dot is drawn on a scope the strip does not offer" section \
  'guard present.contains(.review), needsProof || declined else { return [] }' \
  'guard needsProof || declined else { return [] }'
mutate "the shielded scope is offered over an empty page" section \
  'case .shielded: return shielded' \
  'case .shielded: return true'

# The cross-currency sum this file exists to refuse.
mutate "every currency lands in one bucket" gnosis \
  'var bucket = buckets[code] ?? (total: 0, spends: 0, newest: sighting.at)' \
  'let code = "ALL"; var bucket = buckets[code] ?? (total: 0, spends: 0, newest: sighting.at)'
# "Up 400%" against a window the room was never watching.
mutate "a comparison is claimed against an unobserved window" gnosis \
  'guard let oldest else { return false }
        return oldest <= windowStart(now, back: 2, calendar: calendar)' \
  'return true'
# Coming back from nothing has no percentage.
mutate "a zero prior window divides anyway" gnosis \
  'guard let prior = currency.prior, prior > 0 else { return nil }' \
  'guard let prior = currency.prior else { return nil }'
# A zero is a spend of nothing, which is a different and false claim. Again
# written to compile, so the catch is behavioural.
mutate "an unreadable amount is folded into the total as zero" gnosis \
  '            let code = sighting.currency?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let amount = sighting.amount, let code, !code.isEmpty else {
                if sighting.at >= start { unpriced += 1 }
                continue
            }' \
  '            let code = sighting.currency?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "EUR"
            let amount = sighting.amount ?? 0'
# A dropped month looks exactly like a quiet one, which is the failure the
# import drop counters exist to prevent, one room over.
mutate "the strip truncates its history silently" gnosis \
  'return (months, keys.count - drawn.count, other)' \
  'return (months, 0, other)'
# The oldest months kept instead of the newest — a "history" that stops a year
# ago and renders perfectly.
mutate "the strip keeps the oldest months instead of the newest" gnosis \
  'let drawn = Array(keys.suffix(monthCap))' \
  'let drawn = Array(keys.prefix(monthCap))'
# A month key that resets each year sorts December after the January following
# it, so the strip runs backwards across every year boundary.
mutate "a month key stops surviving the year boundary" gnosis \
  'return year * 12 + (month - 1)' \
  'return month - 1'
# One card, two sorts of money: the strip drawn in a currency the headline is
# not talking about.
mutate "spends in another currency are folded into the strip" gnosis \
  'for (otherCode, otherCells) in monthly where otherCode != code {' \
  'for (otherCode, otherCells) in monthly where otherCode == "\u{0}" && otherCode != code {'
# Ranking by amount compares 400 EUR against 380 GBP as if they were on one
# scale — the refused sum, wearing a sort instead of a plus.
mutate "currencies are ranked by amount instead of count" gnosis \
  'if a.spends != b.spends { return a.spends > b.spends }' \
  'if a.total != b.total { return a.total > b.total }'

# A partial sum presented as complete — the failure `PeerRoom.Token` and
# `RailgunRoom.Token` both exist to refuse. One shield with an unreadable
# amount would otherwise silently understate the token's real total rather
# than say nothing.
mutate "a token's shielded amount is shown even when one shield's amount is unknown" railgun \
  'shieldedAmount: (b.shields > 0 && b.shieldedKnown) ? b.shieldedAmount : nil,' \
  'shieldedAmount: (b.shields > 0) ? b.shieldedAmount : nil,'
# Reordering the rank so recency beats volume — the same class of bug
# `PeerRoom.ordered` and `GnosisPayRoom.ordered` are both mutation-tested
# against: a token with nine moves losing to one with a single, fresher move.
mutate "tokens are ranked by recency before move count" railgun \
  'if a.moves != b.moves { return a.moves > b.moves }
            if a.newest != b.newest { return a.newest > b.newest }' \
  'if a.newest != b.newest { return a.newest > b.newest }
            if a.moves != b.moves { return a.moves > b.moves }'

# THE PAIR SCALED TO WHAT WENT IN, instead of to the bigger of the two. It
# renders perfectly and is wrong exactly where this seat is weakest: only about
# half of Railgun's shields are attributable, so a token that received more than
# we ever saw shielded is ordinary — and against an in-side scale both its lines
# draw full, which says "all of it came back" over any ratio at all.
mutate "the pair is scaled to what went in rather than to the bigger side" railgun \
  'let top = max(into, back)' \
  'let top = into'
# A direction with NO moves reading as an unknown rather than as zero. The pair
# then goes nil for every token that has only ever been shielded — which is most
# of them — so the card's drawing silently disappears from the common case.
mutate "a direction with no moves reads as unknown instead of zero" railgun \
  'let into: Double? = token.shields == 0 ? 0 : token.shieldedAmount' \
  'let into: Double? = token.shieldedAmount'

# A signature request only YOU can unblock loses its priority — the exact bug
# that would make the room's own reason for existing (surfacing what's
# waiting on you) silently stop working while every other reading stays
# correct.
mutate "your turn no longer outranks waiting on others" safe \
  'if a.awaitsYou != b.awaitsYou { return a.awaitsYou && !b.awaitsYou }' \
  'if false { return a.awaitsYou && !b.awaitsYou }'
# The longest-waiting entry within a group loses its lead — a transaction
# that has sat for nine days ranks behind one from yesterday, which is
# exactly backwards for a card whose whole point is surfacing what has been
# ignored longest.
mutate "the oldest pending entry no longer leads within its group" safe \
  'if da != db { return da < db }' \
  'if da != db { return da > db }'

# --- 2026-08-17: the three states, and the rivals ---------------------------

# THE FALSE ALARM. `yourTurn` is `!hasSigned(you)` with no check that the
# threshold isn't already met WITHOUT you, so a 2-of-3 whose other two owners
# both signed claimed your signature was needed, ranked it first, and — since
# §349's (7) — fired a lock-screen alarm for a transaction that needs nothing
# from you. Dropping the `isReady` term restores exactly that bug.
mutate "your signature is 'needed' on a transaction already fully signed without you" safe \
  'var awaitsYou: Bool { yourTurn && !isReady }' \
  'var awaitsYou: Bool { yourTurn }'
# A transaction whose `confirmationsRequired` didn't parse arrives as 0/0.
# Reading that as a met threshold reports something ready to execute on no
# evidence at all — and it renders as a full green ring.
mutate "an unread threshold counts as fully signed" safe \
  'var isReady: Bool { required > 0 && have >= required }' \
  'var isReady: Bool { have >= required }'
# Fully-signed folded back into the pending count: "3 of 3 signatures pending —
# waiting on others", which is false twice in one line (nobody's signature is
# pending, and it isn't the others holding it up).
mutate "fully-signed transactions are counted as pending signatures again" safe \
  'if room.readyCount > 0 {' \
  'if false {'
# Ready loses its rank and sorts purely by age, so the one transaction anybody
# can finish right now falls below one still collecting.
mutate "a fully-signed transaction no longer outranks one still collecting" safe \
  'if a.isReady != b.isReady { return a.isReady && !b.isReady }' \
  'if false { return a.isReady && !b.isReady }'
# A nonce we could not read becomes a rival of every other unreadable one —
# a collision warning asserted on the absence of evidence, on the card whose
# whole job is telling you which signature not to waste.
mutate "an unknown nonce is treated as a queue position" safe \
  'nonce.map { "\(safeAddress.lowercased())#\($0)" }' \
  '"\(safeAddress.lowercased())#\(nonce ?? -1)"'
# The same nonce on two DIFFERENT Safes reads as a collision. They are separate
# queues; only the pair (Safe, nonce) is a position.
mutate "a queue position stops being scoped to its own Safe" safe \
  '"\(safeAddress.lowercased())#\($0)"' \
  '"#\($0)"'
# Rivals stop being pulled adjacent. The sentence still says two of these
# collide and nothing on screen says WHICH two — worse than silence, since it
# invites the wasted signature.
mutate "rivals are no longer drawn beside each other" safe \
  'guard !contested.isEmpty else { return sorted }' \
  'return sorted; guard !contested.isEmpty else { return sorted }'
# The rival warning yields the note slot to the ready count — losing the one
# fact nothing else in this app surfaces, in favour of one the rings already
# show.
mutate "the ready count outranks a nonce collision in the one note slot" safe \
  'if room.contestedCount > 1 {' \
  'if false {'
# The module warning stops naming its Safe once several are watched, so a
# person told their funds can move without a signature is not told where.
# --- 2026-08-24: the row's own words (prd §464) -----------------------------
# Your turn stops outranking ready IN THE SENTENCE, so a transaction that needs
# your signature and has most of them announces itself as ready to execute —
# the state word is the loudest thing on the row and it names the wrong act.
mutate "the state word stops leading with your turn" safe \
  'if entry.awaitsYou { return String(localized: "Your turn") }' \
  'if false { return String(localized: "Your turn") }'
# The shortfall is computed the wrong way round: a 1-of-3 reports that it needs
# minus-two more, which the guard below then swallows into the bare "Waiting" —
# so the one row genuinely furthest from executing looks the least urgent.
mutate "the signatures still needed are counted backwards" safe \
  'let short = entry.required - entry.have' \
  'let short = entry.have - entry.required'
# An unread 0/0 threshold claims a shortfall it has no evidence for. Same
# reasoning as `isReady`'s own `required > 0`, one rung down.
mutate "an unread threshold states a shortfall anyway" safe \
  'guard entry.required > 0, short > 0 else { return String(localized: "Waiting") }' \
  'guard true else { return String(localized: "Waiting") }'
# A row whose description never reached the tracking store leads with an empty
# line — a row with a ring, a state and no subject, which reads as a rendering
# bug rather than as a missing field.
mutate "a missing description leaves the row with no subject at all" safe \
  'entry.descriptionText.isEmpty' \
  'false'
# THE GROUPING BUG. `String(localized: "position \(n)")` over an Int renders
# 1042 as "position 1,042" — a queue slot printed as a quantity, on the one row
# where the number IS the identity of the collision. §375's year-as-quantity
# defect in a second place, and it renders perfectly.
mutate "the queue position is grouped like a quantity" safe \
  'let plain = String(nonce)' \
  'let plain = nonce.formatted(.number.grouping(.automatic))'
mutate "the module warning stops naming which Safe it means" safe \
  'guard room.safeCount > 1, let only = carriers.first else {' \
  'guard false, let only = carriers.first else {'
# A Safe with zero modules counts as a carrier, so a room with no module risk
# at all grows an alarm sentence about nothing.
mutate "a Safe carrying no modules is counted as a carrier" safe \
  'let carriers = room.moduleSafes.filter { $0.count > 0 }' \
  'let carriers = room.moduleSafes'
# The stuck floor disappears, so the brief repeats yesterday's notification as
# today's headline, every day, forever.
mutate "a signature asked for this morning is already 'stuck'" safe \
  'guard let days = stuckDays(room, now: now), days >= stuckFloor,' \
  'guard let days = stuckDays(room, now: now), days >= 0,'
# The brief's lede reports a fully-signed transaction as a signature waiting on
# you — the false alarm again, one surface over.
mutate "a fully-signed transaction is reported as a stuck signature" safe \
  'let dates = room.entries.filter(\.awaitsYou).compactMap(\.submittedAt)' \
  'let dates = room.entries.filter(\.yourTurn).compactMap(\.submittedAt)'
echo ""
echo "wallet-rooms-selftest: OK — assertions pass and every mutation is caught."
