#!/bin/zsh
# Casberi vibenet self-test — verifies the SHIPPED pure logic behind the
# Base "vibenet" devnet room (2026-08-23):
#
#   Casberi/Casberi/Model/VibenetRoom.swift
#     — VibenetScope             (permission-bit naming, unknown-bit counting)
#     — VibenetAuthenticatorKind.identify (which key kind an actor's is)
#     — VibenetActorLog.survivors        (the authorize/revoke log UNION)
#     — VibenetAccountItem.orderedActors (a roster's stable order)
#     — VibenetRoom.ordered/headline/note/rowLine/actorSummary/shortAddress
#     — VibenetAccountMapping.links       (the delegate-mapping, 2026-08-24)
#     — VibenetKeyAggregation.compose     (the room-wide key summary, 2026-08-24)
#     — VibenetBalanceFormat.line         (balance display, never USD, 2026-08-24)
#     — VibenetBalanceAggregation.compose (the feed room's own stat block, 2026-08-24)
#
# WHY A HARNESS. `-vibenetProbe` needs a real devnet address with a real actor
# roster to exercise anything interesting, and nothing on this host can make
# vibenet authorize an actor, revoke one, or lock an account — so this harness
# is not the best proof the composition is right, it is the ONLY one.
#
# Every failure here is a SILENT WRONG ANSWER that renders as a perfectly
# ordinary card:
#
#   • an actorId whose most recent event was a REVOKE still reading as live —
#     the card would show a key that can no longer act for the account as
#     though it still could, which is the one security-relevant fact this
#     whole feature exists to get right;
#   • a revoked-then-reauthorized actorId reading as dead, because the union
#     trusted input order instead of the log's own chronology;
#   • a reserved scope bit silently NAMED as one of the five known ones —
#     inventing a permission a key doesn't actually carry;
#   • "Not established yet" printed for an account that IS established but
#     has authorized no actor this build can see — two different facts about
#     the account, conflated into one wrong sentence;
#   • a locked account not leading the card, so the one alarm this room can
#     raise goes unseen underneath a page of quiet accounts.
#
# `VibenetRoom.swift` is Foundation-only by design and is compiled WHOLE AND
# UNMODIFIED — never a copy, never extracted piecemeal — which is the
# strongest form of "the harness ran the shipped logic".
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

ROOM="Casberi/Casberi/Model/VibenetRoom.swift"
# `VibenetEventFacts.swift` is Foundation-only for the same reason and is
# compiled WHOLE beside it — the expiry join it owns is the one place this
# feature can state a permission it cannot prove (prd §467).
FACTS="Casberi/Casberi/Model/VibenetEventFacts.swift"
BRIDGE="Casberi/Casberi/Model/VibenetBridge.swift"
CATALOG="Casberi/Casberi/Model/BridgeCatalog.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
ROUTER="Casberi/Casberi/Model/BridgeRouting.swift"
# prd §465 — the setup/room split. The setup page and the book are two files
# now, and the invariant that keeps them apart is textual, so it is greppable.
SETUP="Casberi/Casberi/Screens/VibenetScreen.swift"
BOOK="Casberi/Casberi/Screens/VibenetAddressBookScreen.swift"
FIELD="Casberi/Casberi/Screens/VibenetWatchViews.swift"
SHELL_SURFACE="Casberi/Casberi/Shell/MainSurface.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
for f in "$ROOM" "$BRIDGE" "$CATALOG" "$REACH" "$ROUTER" "$SETUP" "$BOOK" "$FIELD" "$SHELL_SURFACE" "$FEED"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

if [[ "${1:-}" == "--self-test" ]]; then
  # This harness's own demonstration that it can fail lives in the mutation
  # block at the bottom, which runs on every invocation rather than behind a
  # flag — a check that cannot fail proves nothing, and one that only tries
  # when asked proves nothing on the runs that matter.
  echo "vibenet-selftest: assertions + mutations run unconditionally below"
fi

TMP=$(mktemp -d /tmp/vibenet-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- drift guards ------------------------------------------------------------
# Wiring the compiled functions cannot prove: a perfect composition is worth
# nothing if the catalog never offers the seat, the router never resolves it,
# or the app never discloses the two hosts it reaches.

grep -q 'Offer(name: "Base Vibenet"' "$CATALOG" \
  || { echo "✗ Base Vibenet is not a catalog offer — the seat can never be connected"; exit 1; }
grep -q 'rpc.vibes.base.org' "$REACH" \
  || { echo "✗ rpc.vibes.base.org is not in the reach registry — the privacy screen is wrong"; exit 1; }
grep -q 'api.vibes.base.org' "$REACH" \
  || { echo "✗ api.vibes.base.org is not in the reach registry — the privacy screen is wrong"; exit 1; }
grep -q 'case .vibenet:.*VibenetScreen' "$ROUTER" \
  || { echo "✗ BridgeRouter no longer routes .vibenet to VibenetScreen"; exit 1; }

# THE STANDING CONSTRAINT: vibenet's contracts are redeployed on no fixed
# schedule, so nothing here may ever hardcode one of its addresses outside
# the two the Keystore contract itself declares fixed (K1's address(1), and
# the zero address every revoked actor reads back as). Every real address in
# `eip8130` this build has ever seen begins "0x8130" — six of the eight —
# so a literal starting with it, anywhere outside a comment, is the bug this
# whole feature exists to prevent. Reads a COMMENT-STRIPPED copy of both
# files: the header doc and this very check's reasoning both quote that
# prefix in prose, so a raw grep would flag the documentation explaining the
# rule as a violation of it (the Obsidian/Cursor lesson).
strip_comments() {
  python3 - "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
src = re.sub(r'^[ \t]*//.*$', '', src, flags=re.M)
src = re.sub(r'(?<![:/])//.*$', '', src, flags=re.M)
sys.stdout.write(src)
PY
}
CARD="Casberi/Casberi/Screens/VibenetRoomCard.swift"
DETAIL="Casberi/Casberi/Screens/VibenetAccountDetail.swift"
TRAY="Casberi/Casberi/Screens/VibenetKeyTraySheet.swift"
NOTIFY="Casberi/Casberi/Model/NotifySweep.swift"
for f in "$CARD" "$DETAIL" "$TRAY" "$NOTIFY"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done
strip_comments "$CARD"   > "$TMP/card.nc.swift"
strip_comments "$TRAY"   > "$TMP/tray.nc.swift"
strip_comments "$DETAIL" > "$TMP/detail.nc.swift"
strip_comments "$NOTIFY" > "$TMP/notify.nc.swift"
strip_comments "$ROOM"   > "$TMP/room.nc.swift"
strip_comments "$BRIDGE" > "$TMP/bridge.nc.swift"
strip_comments "$SETUP" > "$TMP/setup.nc.swift"
strip_comments "$BOOK"  > "$TMP/book.nc.swift"

# --- prd §465: setup is what you do ONCE, the room what you do REPEATEDLY ----
# Every check here fails INVISIBLY if it is not made: the screens still build,
# still render and still look finished — they just quietly grow back into the
# one screen this ruling split, which is exactly how they got there the first
# time. Negative greps read the COMMENT-STRIPPED copies, because all three
# files document the rule by naming the very thing they must not do (the
# Obsidian/Cursor lesson).

# The book holds the MANAGING roster. `VibenetRoomCard` draws every watched
# account as a navigable, renameable, removable row only when `onOpen` is
# non-nil; without this the book is a screen with a field and no list.
grep -q 'onOpen:' "$TMP/book.nc.swift" \
  || { echo "✗ VibenetAddressBookScreen no longer passes onOpen — the roster is not in managing mode"; exit 1; }

# The setup page holds NO roster. This is the whole ruling: a VibenetRoomCard
# back on the setup screen is the 385-line screen returning.
if grep -q 'VibenetRoomCard' "$TMP/setup.nc.swift"; then
  echo "✗ VibenetScreen draws VibenetRoomCard again — prd §465: the roster lives in the book,"
  echo "  never on the setup page. Setup is what you do once."
  exit 1
fi

# The setup page offers the first address ONLY while disconnected. Two fields
# writing one list, one tap apart, is the duplication the split exists to end —
# and it renders perfectly, so nothing else can see it.
grep -q 'if !connected' "$TMP/setup.nc.swift" \
  || { echo "✗ VibenetScreen no longer gates its paste field on being disconnected (prd §465)"; exit 1; }

# ONE field, shared. Copied, the two screens answer the same paste with two
# different sentences within a release.
for f in "$TMP/setup.nc.swift" "$TMP/book.nc.swift"; do
  grep -q 'VibenetWatchField' "$f" \
    || { echo "✗ $f no longer uses the shared VibenetWatchField (prd §465)"; exit 1; }
  grep -q 'DSSlabField' "$f" \
    && { echo "✗ $f hand-rolls its own paste field — VibenetWatchField is the one control (prd §465)"; exit 1; }
done

# NO CAP, ever. Wallet's five is a metered-read fact; vibenet's RPC is keyless
# and free, so a limit here would be a control protecting nothing (§83).
if grep -q 'watchLimit\|canWatchMore' "$TMP/book.nc.swift" "$TMP/setup.nc.swift"; then
  echo "✗ a watch cap reached the vibenet screens — prd §465: reads here are free,"
  echo "  so there is no expensive tier to ration and no cap to state"
  exit 1
fi

# The room's rail reaches the book through ONE slot, not two. §461's Wallet
# rail carries both "+" and the book because they lead to two different places
# — the roster's own field, and everyone else. Vibenet's paste field MOVED into
# the book, so both slots would land in the same place, and two doors onto one
# destination is redundant chrome. The add slot is nil here and the book slot
# is the door.
#
# This guard shipped asserting the opposite (`onAdd: { route.push(...) }`) and
# was red on the commit that introduced it — the code took the one-slot ruling
# and the guard kept the two-slot one. Caught by running the harness, which
# that commit had not.
# ANCHORED to the vibenet rail, never a bare grep of the file. §466 gives the
# WALLET rail the same treatment, so `onAdd: nil,` now appears twice in this
# file and a loose match would be satisfied by the wrong one — passing green
# with vibenet's add slot restored. A guard must prove the condition is the
# whole condition, not that the words appear somewhere.
grep -B 4 'onOpenBook: { route.push(.vibenetAddressBook) }' "$SHELL_SURFACE" | grep -q 'onAdd: nil,' \
  || { echo "✗ the vibenet rail grew a second door (prd §465) — the add slot must stay nil,"; echo "  since the paste field lives in the book and both slots would land there"; exit 1; }
grep -q 'onOpenBook: { route.push(.vibenetAddressBook) }' "$SHELL_SURFACE" \
  || { echo "✗ the vibenet rail lost its Address Book slot (prd §465)"; exit 1; }

# The feed room is UNTOUCHED by this ruling and must stay so: `onOpen` nil
# there is what keeps the stat block the user ruled for ("N accounts and
# balance, then the keys, then the events", §463's session). A managing roster
# in the feed room re-adds the rows that ruling removed.
#
# The anchor changed 2026-08-25 (prd §469): `onScope` was deleted entirely —
# it had been unreached since `afda3c10`, and the rail's faces already scope —
# so the guard now pins the surviving shape: the feed call site passes an
# inert `onRemove` and NO `onOpen:` label. The negative half is what carries
# the §463 ruling — an `onOpen:` appearing at this call site is the managing
# roster returning to the feed room.
grep -q 'VibenetRoomCard(room: room, onRemove: { _ in },' "$FEED" \
  || { echo "✗ the FEED room's VibenetRoomCard call site moved — prd §465/§469: it must pass an"; echo "  inert onRemove and never onOpen (the stat-block shape §463 ruled for)"; exit 1; }
if grep -A 1 'VibenetRoomCard(room: room, onRemove: { _ in },' "$FEED" | grep -q 'onOpen:'; then
  echo "✗ the FEED room's VibenetRoomCard passes onOpen — prd §465 leaves the feed room's"
  echo "  stat block exactly as §463 ruled it; the managing roster lives in the book"
  exit 1
fi


if grep -qi '0x8130' "$TMP/room.nc.swift" "$TMP/bridge.nc.swift"; then
  echo "✗ a literal vibenet contract address (0x8130…) is hardcoded outside a comment —"
  echo "  vibenet redeploys its contracts; this must come from VibenetConfig's live fetch"
  exit 1
fi
# The two addresses this file MAY hardcode, named so the check above isn't
# fooled by their own presence: K1's fixed constant and the zero address.
grep -q '0x0000000000000000000000000000000000000001' "$TMP/room.nc.swift" \
  || { echo "✗ K1_AUTHENTICATOR's fixed address is missing — secp256k1 actors can never be identified"; exit 1; }

# Genuinely read-only: no signing key of this app's own may ever touch
# vibenet (unlike the Safe co-signer, prd §425/§426 — there is no counterpart
# here), and no write-shaped RPC method may be requested.
if grep -q 'SignerKey\|SafeSigner' "$TMP/room.nc.swift" "$TMP/bridge.nc.swift"; then
  echo "✗ VibenetRoom/VibenetBridge reference a signing type — this feature must never sign"
  exit 1
fi
for method in 'eth_sendTransaction' 'eth_sendRawTransaction' 'eth_sign' \
              'eth_signTransaction' 'personal_sign' 'eth_signTypedData'; do
  grep -q "$method" "$TMP/bridge.nc.swift" \
    && { echo "✗ VibenetBridge.swift requests $method — this must only ever read"; exit 1; }
done

# The redeploy note ("vibenet redeployed since you last checked") is only
# honest if a first-ever read stays silent — nothing stored yet means nothing
# to compare against, the AddressConnectionsSeen/ChipMemory rule. Without this
# guard the note could tell someone the network "redeployed" on their very
# first open, which is a claim about a past this device never observed.
grep -q 'enum VibenetSeenCommit' "$TMP/bridge.nc.swift" \
  || { echo "✗ VibenetSeenCommit is missing — the redeploy note has nothing to compare against"; exit 1; }
grep -q 'guard let previous else { return false }' "$TMP/bridge.nc.swift" \
  || { echo "✗ VibenetSeenCommit no longer stays silent on a first-ever read — it would report a redeploy on someone's very first open"; exit 1; }

# Balances (2026-08-24): decimals must be READ LIVE off the chain, never
# assumed — this codebase has been burned by hardcoding ERC-20 decimals
# twice already (Solana SPL, Gnosis Pay's USDCe being 6 not 18).
grep -q 'VibenetABI.decimalsCall' "$TMP/bridge.nc.swift" \
  || { echo "✗ VibenetBridge.swift no longer reads decimals() for USDV/NFV — a hardcoded scale would repeat the SOL-decimals bug"; exit 1; }
grep -q 'guard (0...36).contains(value) else { return nil }' "$TMP/bridge.nc.swift" \
  || { echo "✗ VibenetTokenDecimals no longer refuses an implausible decimals() answer — a reverted call could silently scale a balance by 10^0"; exit 1; }
# The native balance is the ONE reading safe to hardcode at 18 decimals —
# an EVM-wide constant, not a per-token guess — so its own scale must
# still be present and distinct from the live-read USDV/NFV path above.
grep -q '/ 1e18' "$TMP/bridge.nc.swift" \
  || { echo "✗ VibenetBridge.swift no longer scales the native balance by 18 decimals"; exit 1; }
# `nativeBalance` must stay OPTIONAL, nil-defaulted — a failed read and a
# genuine zero balance must never look the same (§83).
grep -q 'nativeBalance: Double? = nil' "$TMP/room.nc.swift" \
  || { echo "✗ VibenetAccountItem.nativeBalance is no longer optional/nil-defaulted — a failed read could no longer be told apart from a real zero"; exit 1; }
# Never invent a dollar figure for a devnet token with no real market
# price (§83) — reads COMMENT-STRIPPED copies, since this rule is
# documented by name in the source (the Obsidian/Cursor lesson).
if grep -q 'WalletValue.money\|priceUSD\|usdValue' "$TMP/bridge.nc.swift" "$TMP/room.nc.swift"; then
  echo "✗ a vibenet file appears to price a balance in USD — these are devnet tokens with no real market price (§83)"
  exit 1
fi

echo "drift guards ✓"

# --- prd §468: what the cards are allowed to CLAIM ---------------------------
# Every one of these fails INVISIBLY: the room still builds, still renders and
# still looks finished — it just goes back to stating a three-day-old read as
# current, a two-account total as three, or a failed read as a revocation.
# Negative greps read the COMMENT-STRIPPED copies, because these files document
# each rule by naming the very thing they must not do (the Obsidian/Cursor
# lesson).

# THE STAMP'S ONLY REAL CALL SITE. `readAt` defaults to nil so the two
# placeholder rooms cannot claim to be reads; if the one place that has
# genuinely just read stops passing it, every check above still passes and the
# room silently goes back to drawing three-day-old state with a confident face.
grep -q 'redeployedSinceLastSeen: redeployed, readAt: .now' "$TMP/bridge.nc.swift" \
  || { echo "✗ VibenetRoomSource.compose no longer stamps readAt — prd §468: the room cannot say when it was read"; exit 1; }

# The card must ASK the model for its heading. A literal here is the defect
# this pass fixed: a partial sum under a whole claim.
grep -q 'aggregate.nativeHeading' "$TMP/card.nc.swift" \
  || { echo "✗ the balance card no longer draws aggregate.nativeHeading — prd §468: a partial total must say how partial"; exit 1; }
if grep -q 'Across your accounts' "$TMP/card.nc.swift"; then
  echo "✗ VibenetRoomCard hardcodes the crown's heading again — prd §468: it belongs to"
  echo "  VibenetBalanceAggregate, which is the only thing that knows whether the total is complete."
  exit 1
fi

# Both coverage sentences reach the screen, or the counts above them are floors
# nobody is told about.
grep -q 'unreachedLine' "$TMP/card.nc.swift" \
  || { echo "✗ the room card no longer draws unreachedLine — prd §468: an unread account is never said"; exit 1; }

# The runway. Without it the room's only clock is one sentence again.
grep -q 'WalletRunwayRail(dates: aggregate.futureExpiries)' "$TMP/card.nc.swift" \
  || { echo "✗ the keys card no longer draws the expiry runway — prd §468"; exit 1; }

# ONE definition of the keys block. Two copies drift, and then the same room
# says two different things depending on how many accounts are watched.
# OCCURRENCES, never `grep -c`, which counts LINES — a second call appended to
# the same line survives that spelling, and this harness proved exactly that
# against itself before the guard landed (the Safe-signer lesson, second time).
if [[ $(grep -o 'VibenetPolicyAggregation.compose' "$TMP/card.nc.swift" | wc -l | tr -d ' ') -ne 1 ]]; then
  echo "✗ VibenetRoomCard composes the policy rows more than once — prd §468: keysBody is the"
  echo "  single definition, and a second copy is §418's duplicate-parser class in this card."
  exit 1
fi

# The since-you-last-looked ledger is READ then SPENT, in that order and in one
# place. Advancing before reading erases the answer while it is being shown.
grep -q 'keyChanges = VibenetKeysSeen.changes(in: room.items)' "$TMP/card.nc.swift" \
  || { echo "✗ the room card no longer reads the seen-keys ledger — prd §468"; exit 1; }
grep -q 'VibenetKeysSeen.advance(room.items)' "$TMP/card.nc.swift" \
  || { echo "✗ the room card never marks the room as looked at — prd §468: the marker would never clear"; exit 1; }

# Disconnect forgets it, or a re-watch months later diffs a live roster against
# a year-old ledger and reports the difference as news.
grep -q 'VibenetKeysSeen.forget()' "$TMP/bridge.nc.swift" \
  || { echo "✗ disconnect no longer forgets the seen-keys ledger — prd §468"; exit 1; }

# The facets are stamped at landing, or the four kinds of event stay unaskable.
grep -q 'thing.tags = event.kind.facetTags' "$TMP/bridge.nc.swift" \
  || { echo "✗ landed vibenet events no longer carry their §308 facets — prd §468"; exit 1; }
# ...and the four tags really are in the retriever's vocabulary, or the tag
# exists and no sentence can name it (§375's Photo lesson).
for tag in Revoked Unlocking Key Locked; do
  grep -q "\"$tag\")" "Casberi/Casberi/Model/Retriever.swift" \
    || { echo "✗ the $tag facet is stamped but not in Retriever.facetTable — prd §468"; exit 1; }
done

# THE ALARM IS GATED ON THE TAG, NEVER THE BARE REF. Without the gate every
# key event in this room buzzes — three of the four are things you did
# yourself, which is §306's own did-you-already-know test failing every time.
grep -q 'ref.hasPrefix("vibenet:actor:"), thing.tags.contains("Admin key")' "$TMP/notify.nc.swift" \
  || { echo "✗ the vibenet alarm is no longer gated on the Admin key tag — prd §468"; exit 1; }
grep -q 'thing.tags.append("Admin key")' "$TMP/bridge.nc.swift" \
  || { echo "✗ nothing stamps the Admin key tag — prd §468: the alarm can never fire"; exit 1; }

# The tray is routed through the screen's single sheet. A `.sheet` on this
# card resolves to the same presenting controller as FeedScreen's own and
# rises part way before tearing itself down (ruling 2026-07-28, paid 3 times).
if grep -qE '\.sheet\(' "$TMP/card.nc.swift"; then
  echo "✗ VibenetRoomCard presents a sheet of its own — prd §468: the card lives inside"
  echo "  FeedScreen's List rows, so it must hand the tray out through a closure."
  exit 1
fi
grep -q 'case vibenetKeys(\[VibenetAccountItem\])' "Casberi/Casberi/Screens/FeedScreen.swift" \
  || { echo "✗ FeedSheetRoute no longer carries the key tray — prd §468"; exit 1; }

# The tray mirrors the card, and the chevron only exists where the tray does.
grep -q 'VibenetKeyTray.sections' "$TRAY" \
  || { echo "✗ VibenetKeyTraySheet no longer reads VibenetKeyTray.sections — prd §468"; exit 1; }
grep -q 'if onOpenKeys != nil' "$TMP/card.nc.swift" \
  || { echo "✗ the keys chevron is no longer gated on the tray being reachable — prd §468: a"
       echo "  chevron that opens nothing is the dead control §83 bans"; exit 1; }

# The hero's face stands down only where the rail draws it. Ungated, a
# single-account room and the address book's own sheet both lose their only
# identifying mark.
grep -q 'if showsFace {' "$TMP/detail.nc.swift" \
  || { echo "✗ VibenetAccountDetail no longer gates its hero face — prd §468"; exit 1; }
grep -q 'VibenetScopeRail.shows(source: VibenetIdentity.source, watched: fullItems.count)' "$TMP/card.nc.swift" \
  || { echo "✗ the hero face is no longer gated on the RAIL being present — prd §468: dropping it"; \
       echo "  unconditionally leaves a one-account room with nothing identifying it"; exit 1; }

# --- prd §470: a key's identity, and the developer's paste -------------------
# Each of these fails INVISIBLY: the rows still draw, the tray still opens, the
# doors still work — a key just goes back to being unidentifiable, or a copy
# hands over the wrong thing. Negative greps read COMMENT-STRIPPED copies,
# since both files document these rules by naming what they must not do.

# WHICH KEY THIS IS. Without the id, two same-kind keys on one account are two
# byte-identical rows and nothing in the app can tell them apart.
grep -q 'VibenetKeyIdentity.short(actor.actorId)' "$TMP/detail.nc.swift" \
  || { echo "✗ the detail's key rows lost their id — prd §470: two same-kind keys become one row twice"; exit 1; }
grep -q 'VibenetKeyIdentity.short(key.actor.actorId)' "$TMP/tray.nc.swift" \
  || { echo "✗ the key tray's rows lost their id — prd §470, and it matters MORE there: the tray"; echo "  groups by permission, so same-kind keys on one account land adjacent"; exit 1; }

# THE VALUES, ON DEMAND. The row shows four characters; the whole word has to
# be reachable or the id is decoration.
grep -q 'DSPasteboard.copySensitive(actor.actorId)' "$TMP/detail.nc.swift" \
  || { echo "✗ a key's id is no longer copyable from the detail — prd §470"; exit 1; }
grep -q 'DSPasteboard.copySensitive(key.actor.actorId)' "$TMP/tray.nc.swift" \
  || { echo "✗ a key's id is no longer copyable from the tray — prd §470"; exit 1; }

# GATED, in BOTH places. An unconditional "Copy signer address" is present on
# every row and correct on only the secp256k1 ones — §83 on the screen a
# person reads to find out who can spend their account.
for f in "$TMP/detail.nc.swift" "$TMP/tray.nc.swift"; do
  grep -q 'if let signer = VibenetKeyIdentity.signerAddress(' "$f" \
    || { echo "✗ ${f:t} offers a signer address ungated — prd §470: only an address-shaped"; echo "  actorId has a signer, and a passkey's hash would name nobody"; exit 1; }
done

# NEVER the raw pasteboard: it has no expiry and rides Universal Clipboard to
# every device on the account, which is the default §277 exists to stop.
if grep -q 'UIPasteboard.general.string' "$TMP/detail.nc.swift"; then
  echo "✗ VibenetAccountDetail writes the pasteboard raw again — prd §277/§470: every copy"
  echo "  here goes through DSPasteboard, which sets an expiry and keeps an address local"
  exit 1
fi

# The developer's paste, and the door that produces it.
grep -q 'DSPasteboard.copy(VibenetAccountDebug.text(' "$TMP/detail.nc.swift" \
  || { echo "✗ the 'Copy account state' door is gone — prd §470: the one place spec internals"; echo "  are allowed to go is a paste that is asked for explicitly"; exit 1; }

# THE DOORS MUST WRAP. Every door is .fixedSize(), so a fifth one in an HStack
# pushes the trailing door off a phone's width — and the row is already four
# wide on an undeployed account, which is when the faucet door matters most.
grep -A 2 'private var doorsSection: some View {' "$TMP/detail.nc.swift" | grep -q 'FlowLayout' \
  || { echo "✗ the doors row is not flowing — prd §470: five fixed-size doors in an HStack"; echo "  clip off the trailing one rather than wrapping"; exit 1; }

# A tapped key must reach its account. The tray dead-ended on its own answer
# before this, and the caller owns dismiss-then-scope for RoomDoor's reason.
grep -q 'VibenetKeyTraySheet(items: items, onPick:' "$FEED" \
  || { echo "✗ the key tray's rows no longer scope to their account — prd §470"; exit 1; }
grep -B 2 'chrome.vibenetScope = address' "$FEED" | grep -q 'feedSheet = nil' \
  || { echo "✗ the tray scopes WITHOUT dismissing first — prd §470: vibenetScope re-composes"; echo "  the room behind the sheet, so the change lands under a covered screen"; exit 1; }

# --- compile VibenetRoom.swift WHOLE, unmodified -----------------------------

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}

// MARK: - Scope

print("VibenetScope — naming and the unknown-bit ceiling")
check("scope 0 reads as the ADMIN it is — see the isAdmin block below",
      VibenetScope(raw: 0).summary == "Admin (unrestricted)")
check("a single known bit",
      VibenetScope(raw: VibenetScope.sender).summary == "Sender")
check("every known bit, in the contract's own order",
      VibenetScope(raw: VibenetScope.known).summary
        == "Sender, Policy, Nonce, Self-payer, Sponsor-payer")
check("a reserved bit is COUNTED, never named",
      VibenetScope(raw: 0x0020).summary == "+1 unknown")
check("two reserved bits",
      VibenetScope(raw: 0x0020 | 0x0040).unknownCount == 2)
check("a known bit plus a reserved one names the known and counts the rest",
      VibenetScope(raw: VibenetScope.sender | 0x0020).summary == "Sender, +1 unknown")
check("names() carries no reserved bit",
      VibenetScope(raw: VibenetScope.sender | 0x0020).names == ["Sender"])
check("the highest bit is still just 'unknown', never invented",
      VibenetScope(raw: 0x8000).summary == "+1 unknown")

// MARK: - VibenetScope.grantedCount — byReach's ranking key

check("grantedCount counts named bits AND reserved ones — a bit we can't name is still a power",
      VibenetScope(raw: VibenetScope.sender | VibenetScope.selfPayer | 0x0020).grantedCount == 3)
check("plainSummary words a real grant in plain English",
      VibenetScope(raw: VibenetScope.sender | VibenetScope.selfPayer).plainSummary
        == "Send anywhere, Pay own gas")
check("a reserved bit is still counted, never named, in the plain wording too",
      VibenetScope(raw: VibenetScope.sender | 0x0020).plainSummary == "Send anywhere, +1 unknown")

// MARK: - Scope ZERO is the ADMIN, not the empty set (EIP-8130)
//
// The spec: "A value of 0x00 means unrestricted (admin), while non-zero
// values grant only specific contexts." This file shipped the inverse —
// "No permissions" / "No scope", ranked LAST by byReach — so a key with
// total authority over the account displayed as one with none. Every check
// below fails against that shipped reading, which is the point of having
// them: this is the §83 fake status in the direction that costs the most.

print("")
print("VibenetScope.isAdmin — scope 0 is unrestricted, never empty")
check("scope 0 is the admin",
      VibenetScope(raw: 0).isAdmin)
check("any single bit is a RESTRICTED scope, never the admin",
      !VibenetScope(raw: VibenetScope.sender).isAdmin)
check("even every known bit at once is still restricted — it cannot reach the reserved ones",
      !VibenetScope(raw: VibenetScope.known).isAdmin)
check("the admin's plain summary says so in words",
      VibenetScope(raw: 0).plainSummary == "Admin — no restrictions")
check("the admin's developer summary names the contract's own reading",
      VibenetScope(raw: 0).summary == "Admin (unrestricted)")
check("the admin is ONE chip, never a list of five — it holds bits we cannot name",
      VibenetScope(raw: 0).grantedPlainLabels == ["Admin"])
check("no scope yields an empty chip row, so no caller needs a blank branch",
      !VibenetScope(raw: 0).grantedPlainLabels.isEmpty
        && !VibenetScope(raw: VibenetScope.sender).grantedPlainLabels.isEmpty
        && !VibenetScope(raw: 0x0020).grantedPlainLabels.isEmpty)
check("grantedCount stays a BIT tally — an admin's powers are not a number",
      VibenetScope(raw: 0).grantedCount == 0)

// MARK: - VibenetScope.grantedPlainLabels — R3.1, the matrix's replacement

print("")
print("VibenetScope.grantedPlainLabels — one chip per granted permission, replacing the matrix")
check("a real grant yields one chip label per permission, in the contract's own order",
      VibenetScope(raw: VibenetScope.sender | VibenetScope.selfPayer).grantedPlainLabels
        == ["Send anywhere", "Pay own gas"])
check("a reserved bit appends ONE trailing '+N unknown' label, never an invented name",
      VibenetScope(raw: VibenetScope.sender | 0x0020).grantedPlainLabels == ["Send anywhere", "+1 unknown"])
check("several reserved bits still collapse to ONE trailing chip, plural",
      VibenetScope(raw: VibenetScope.sender | 0x0020 | 0x0040).grantedPlainLabels == ["Send anywhere", "+2 unknown"])

// The plain names are the SPEC's own words for four of the five bits, and
// the room, the account card and the key tray all read this one table — so
// a rename here is a rename everywhere, which is the property that keeps
// those three surfaces from teaching three vocabularies for one permission.
check("SENDER is named for its DESTINATION, so it can never be read as 'unrestricted'",
      VibenetScope(raw: VibenetScope.sender).plainSummary == "Send anywhere")
check("POLICY says it RESTRICTS sending, the spec's 'exactly one target'",
      VibenetScope(raw: VibenetScope.policy).plainSummary == "Send to one contract")
check("SELF_PAYER and SPONSOR_PAYER are told apart by WHOSE gas, not by a bare direction",
      VibenetScope(raw: VibenetScope.selfPayer).plainSummary == "Pay own gas"
        && VibenetScope(raw: VibenetScope.sponsorPayer).plainSummary == "Pay others' gas")
check("NONCE no longer prints the spec's internal word at the reader",
      VibenetScope(raw: VibenetScope.nonce).plainSummary == "Send in order")
check("reserved bits alone (nothing named) still yield exactly one chip",
      VibenetScope(raw: 0x0020).grantedPlainLabels == ["+1 unknown"])

// MARK: - Authenticator identity

print("")
print("VibenetAuthenticatorKind.identify — the five kinds, none invented")
let known = VibenetKnownAuthenticators(
    p256: "0x8130c89f65750431b564a4730397552a11cea256",
    webAuthn: "0x813007b6b1b48e75d91dec5927ab515d12a0f1d0",
    delegate: "0x8130b7d430d041ed4050935814d493299980ade1")
check("K1's fixed address",
      VibenetAuthenticatorKind.identify(authenticator: VibenetAuthenticatorKind.k1Address, known: known) == .secp256k1)
check("K1 matches case-insensitively",
      VibenetAuthenticatorKind.identify(authenticator: "0x0000000000000000000000000000000000000001".uppercased(), known: known) == .secp256k1)
check("the live P256 address",
      VibenetAuthenticatorKind.identify(authenticator: known.p256, known: known) == .p256)
check("the live P256 address, mixed case (an RPC's hex casing isn't a promise)",
      VibenetAuthenticatorKind.identify(authenticator: "0x8130C89F65750431b564A4730397552A11CEA256", known: known) == .p256)
check("the live WebAuthn address",
      VibenetAuthenticatorKind.identify(authenticator: known.webAuthn, known: known) == .webAuthn)
check("the live Delegate address",
      VibenetAuthenticatorKind.identify(authenticator: known.delegate, known: known) == .delegate)
check("an address matching none of the four is custom, never guessed further",
      VibenetAuthenticatorKind.identify(authenticator: "0x000000000000000000000000000000deadbeef", known: known) == .custom)
check("the zero address is not silently read as K1",
      VibenetAuthenticatorKind.identify(authenticator: VibenetAuthenticatorKind.zeroAddress, known: known) == .custom)
check("kind labels are real words",
      VibenetAuthenticatorKind.secp256k1.label == "secp256k1 key"
        && VibenetAuthenticatorKind.webAuthn.label == "Passkey"
        && VibenetAuthenticatorKind.custom.label == "Custom authenticator")

// MARK: - VibenetLogChunking.ranges — the RPC's 100,000-block ceiling, walked correctly

print("")
print("VibenetLogChunking.ranges — MEASURED 2026-08-23: the RPC refuses a wider eth_getLogs window")
check("a chain shorter than one range needs exactly one chunk, covering genesis to tip",
      VibenetLogChunking.ranges(tip: 500, maxRange: 100_000, maxChunks: 50).map { "\($0.from)-\($0.to)" }
        == ["0-500"])
check("a chain exactly as tall as the range still needs only one chunk",
      VibenetLogChunking.ranges(tip: 99_999, maxRange: 100_000, maxChunks: 50).map { "\($0.from)-\($0.to)" }
        == ["0-99999"])
let overByOne = VibenetLogChunking.ranges(tip: 100_000, maxRange: 100_000, maxChunks: 50)
check("one block past the range needs a SECOND chunk, walked tip-backward",
      overByOne.map { "\($0.from)-\($0.to)" } == ["1-100000", "0-0"])
check("no gaps and no overlaps across chunks — every block from genesis to tip covered exactly once",
      overByOne.reduce(0) { $0 + ($1.to - $1.from + 1) } == 100_001)
let real = VibenetLogChunking.ranges(tip: 285_133, maxRange: 100_000, maxChunks: 50)
check("the live chain height measured this session needs exactly 3 chunks",
      real.count == 3)
check("chunks are walked NEWEST first — a just-authorized key is always inside the first chunk read",
      real.first?.to == 285_133)
check("the LAST chunk always reaches genesis",
      real.last?.from == 0)
check("the chunk-count breaker is real — a chain far taller than maxChunks × maxRange truncates rather than looping forever",
      VibenetLogChunking.ranges(tip: 10_000_000, maxRange: 100_000, maxChunks: 5).count == 5)
check("a truncated walk still starts at the tip — the newest history is never what's dropped",
      VibenetLogChunking.ranges(tip: 10_000_000, maxRange: 100_000, maxChunks: 5).first?.to == 10_000_000)
check("nonsense inputs (negative tip, zero range) return no ranges rather than looping or crashing",
      VibenetLogChunking.ranges(tip: -1, maxRange: 100_000, maxChunks: 50).isEmpty
        && VibenetLogChunking.ranges(tip: 500, maxRange: 0, maxChunks: 50).isEmpty)

// MARK: - The actor log union — the sharpest arithmetic in the file

print("")
print("VibenetActorLog.survivors — last-write-wins, by CHRONOLOGY not array order")
func event(_ id: String, _ authorized: Bool, _ block: Int, _ logIndex: Int = 0) -> VibenetActorEvent {
    VibenetActorEvent(actorId: id, authorized: authorized, block: block, logIndex: logIndex)
}
check("a bare authorization survives",
      VibenetActorLog.survivors([event("a1", true, 100)]) == ["a1"])
check("authorize then revoke does NOT survive",
      VibenetActorLog.survivors([event("a1", true, 100), event("a1", false, 200)]).isEmpty)
check("revoke then REAUTHORIZE survives, fed in chronological order",
      VibenetActorLog.survivors([event("a1", false, 100), event("a1", true, 200)]) == ["a1"])
check("revoke then reauthorize survives even fed OUT OF ORDER (the whole point of sorting)",
      VibenetActorLog.survivors([event("a1", true, 200), event("a1", false, 100)]) == ["a1"])
check("log index breaks a same-block tie",
      VibenetActorLog.survivors([
        event("a1", true, 100, 1), event("a1", false, 100, 2),
      ]).isEmpty)
check("two actors are independent",
      VibenetActorLog.survivors([event("a1", true, 100), event("a2", false, 100)]) == ["a1"])
check("no events, no survivors", VibenetActorLog.survivors([]).isEmpty)

// MARK: - Roster order

print("")
print("VibenetAccountItem.orderedActors — the contract's own declaration order")
let a1 = VibenetActor(actorId: "z", authenticator: "0x1", kind: .custom,
                      scope: VibenetScope(raw: 0), expiry: 0)
let a2 = VibenetActor(actorId: "a", authenticator: "0x2", kind: .secp256k1,
                      scope: VibenetScope(raw: 0), expiry: 0)
let a3 = VibenetActor(actorId: "m", authenticator: "0x3", kind: .p256,
                      scope: VibenetScope(raw: 0), expiry: 0)
check("K1 leads, custom trails, regardless of actorId",
      VibenetAccountItem.orderedActors([a1, a3, a2]).map(\.actorId) == ["a", "m", "z"])

// MARK: - VibenetValueHistory — the sparkline's only source

print("")
print("VibenetValueHistory — throttle, series and delta")
let t0 = Date(timeIntervalSince1970: 1_700_000_000)
check("the first reading is always kept",
      VibenetValueHistory.appending([], native: 1.0, now: t0)?.count == 1)
let one = [VibenetValueSample(at: t0, native: 1.0)]
check("a second reading inside the OPENING throttle is REFUSED — nil, not a duplicate point",
      VibenetValueHistory.appending(one, native: 2.0,
                                    now: t0.addingTimeInterval(VibenetValueHistory.openingThrottle - 1)) == nil)
check("a reading past the throttle lands",
      VibenetValueHistory.appending(one, native: 2.0,
                                    now: t0.addingTimeInterval(VibenetValueHistory.throttle + 1))?.count == 2)
// THE CURVE MUST BE REACHABLE ON THE DAY THE BRIDGE SHIPS (2026-08-24,
// reported as "the app still does not have sparkline"). `series` needs two
// readings, so if the settled four-hour throttle governed from the first
// reading, a person who watches their first account cannot see a curve today
// however often they open the room — the chart was never broken, it could not
// yet have anything to draw. The opening interval is what makes it reachable,
// and every point in it is still a real reading of a real balance.
check("a SECOND reading lands minutes after the first, not hours — the curve is reachable",
      VibenetValueHistory.appending(one, native: 2.0,
                                    now: t0.addingTimeInterval(VibenetValueHistory.openingThrottle + 1))?.count == 2)
check("the opening interval is genuinely shorter than the settled one",
      VibenetValueHistory.openingThrottle < VibenetValueHistory.throttle)
check("a room with an established curve is back on the SETTLED interval",
      VibenetValueHistory.interval(forExisting: VibenetValueHistory.minimumForCurve)
          == VibenetValueHistory.throttle)
check("…and one still building is on the opening one",
      VibenetValueHistory.interval(forExisting: VibenetValueHistory.minimumForCurve - 1)
          == VibenetValueHistory.openingThrottle)
// The settled interval still REFUSES a close-together reading once the curve
// exists — the shortcut is for establishing a chart, never a permanent
// change of resolution.
let settledCurve = (0..<VibenetValueHistory.minimumForCurve).map {
    VibenetValueSample(at: t0.addingTimeInterval(Double($0) * 200), native: 1.0)
}
check("an established curve refuses a reading minutes later",
      VibenetValueHistory.appending(settledCurve, native: 2.0,
                                    now: (settledCurve.last?.at ?? t0).addingTimeInterval(600)) == nil)
// ONE point is a flat line, and a flat line on a balance chart reads as "went
// to zero" — the whole reason this returns nil rather than a single-element
// series. Mutation-proven below.
check("a single reading draws NOTHING rather than a flat line",
      VibenetValueHistory.series(one) == nil)
check("two readings are a series",
      VibenetValueHistory.series(one + [VibenetValueSample(at: t0.addingTimeInterval(20_000), native: 2)])?.count == 2)
let rising = [VibenetValueSample(at: t0, native: 1.0),
              VibenetValueSample(at: t0.addingTimeInterval(20_000), native: 1.5)]
check("a real move reports its fraction",
      (VibenetValueHistory.delta(rising) ?? 0) > 0.49)
check("a move that rounds to nothing has no direction, so no delta at all",
      VibenetValueHistory.delta([VibenetValueSample(at: t0, native: 1.0),
                                 VibenetValueSample(at: t0.addingTimeInterval(20_000),
                                                    native: 1.0001)]) == nil)
check("a single reading has no delta either",
      VibenetValueHistory.delta(one) == nil)
// Written as statements, never an inline closure inside `check(...)` — an
// immediately-invoked closure with inference in an argument position is the
// Swift type-checker blowup that took this harness from ~2 minutes to over 10.
var capped: [VibenetValueSample] = []
for i in 0..<VibenetValueHistory.cap {
    let at = t0.addingTimeInterval(Double(i) * 20_000)
    capped.append(VibenetValueSample(at: at, native: Double(i)))
}
let overflowed = VibenetValueHistory.appending(capped, native: 999,
                                               now: t0.addingTimeInterval(1_000_000_000)) ?? capped
check("the cap is enforced, oldest dropped first",
      overflowed.count == VibenetValueHistory.cap && overflowed.last?.native == 999)

// MARK: - DEMO PARITY — every section the room card draws must have data
//
// The room's own version of `demo-selftest.py`'s check F, and the reason it
// exists is that this feature shipped a room whose demo showed a fraction of
// what the room can say. A section with no seeded data renders as nothing,
// which from outside is indistinguishable from a section that does not exist —
// so each of the card's readings is asserted to be non-empty over the SAME
// fixture the demo actually renders.

print("")
print("demoFixture — every room-card section has something to draw")
let demoRoom = VibenetRoom.demoFixture()
let demoPolicies = VibenetPolicyAggregation.compose(demoRoom.items)
check("the keys card's policy rows have data",
      !demoPolicies.isEmpty)
check("ADMIN is among them — the state §463 fixed is visible in the demo",
      demoPolicies.contains { $0.label == "Admin" })
check("more than one permission is represented, so the rows read as a list",
      demoPolicies.count >= 3)
check("no row is ever seeded at zero — a permission nobody holds is dropped",
      demoPolicies.allSatisfy { $0.count > 0 })
if let demoBalance = VibenetBalanceAggregation.compose(demoRoom.items) {
    check("the crown has a native figure to lead with",
          demoBalance.nativeTotal != nil)
    check("the treemap has more than one cell, so it is a drawing not a rectangle",
          VibenetBalanceTreemap.cells(demoBalance).count > 1)
} else {
    check("the demo seeds balances at all", false)
}
check("the linked-accounts spine has a watched-to-watched link to draw",
      !VibenetAccountMapping.links(demoRoom.items).isEmpty)
check("the demo seeds the REAL history store, so the sparkline is not demo-only",
      VibenetValueHistory.series(VibenetDemoHistoryShape.samples(now: .now))?.count ?? 0 >= 2)
check("the seeded curve ends on the fixture's own total, so crown and line agree",
      abs((VibenetDemoHistoryShape.samples(now: .now).last?.native ?? 0) - 2.514) < 0.001)
check("a key is expiring, so the card's one clock line appears",
      VibenetKeyAggregation.compose(demoRoom.items, now: .now)?.soonestExpiry != nil)

// MARK: - policyLine — WHICH contract a gated key may call
//
// "Send to one contract" states the restriction; this is the half that makes
// it meaningful. Every failure renders as an ordinary key row: a gated key
// silently saying nothing, or — the one that matters — a key naming a manager
// it is not actually gated to.

print("")
print("VibenetActor.policyLine — the contract a gated key is limited to")
let mgrAddr = "0x813077055d1110f92191cce13018f51820b40ac1"
let sessAddr = "0x813070914c530d030f4efd8fa99c18e836435e55"
let knownMgrs = VibenetKnownPolicyManagers(policyManager: mgrAddr, sessionPolicy: sessAddr)
func gated(_ scope: UInt16, _ manager: String?) -> VibenetActor {
    VibenetActor(actorId: "a", authenticator: "0x1", kind: .p256,
                 scope: VibenetScope(raw: scope), expiry: 0, policyManager: manager)
}
check("a gated key names a manager the config recognises",
      gated(VibenetScope.policy, mgrAddr).policyLine(known: knownMgrs)
        == "Limited to the policy manager")
check("the session policy is named too — the config's other candidate",
      gated(VibenetScope.policy, sessAddr).policyLine(known: knownMgrs)
        == "Limited to the session policy")
check("a manager this build cannot name falls back to its short address, never a label",
      gated(VibenetScope.policy, "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef").policyLine(known: knownMgrs)
        == "Limited to …beef")
// The gate is the SCOPE BIT, not the presence of a manager. A key that is not
// policy-gated must never claim to be limited, however a manager got onto it —
// that would invert the fact, telling someone a key that can send ANYWHERE is
// restricted to one contract (§83, in the direction that reassures wrongly).
check("a key WITHOUT the policy bit never claims to be limited",
      gated(VibenetScope.sender, mgrAddr).policyLine(known: knownMgrs) == nil)
check("an ADMIN never claims to be limited either",
      gated(0, mgrAddr).policyLine(known: knownMgrs) == nil)
check("a gated key whose manager did not read says nothing rather than guessing",
      gated(VibenetScope.policy, nil).policyLine(known: knownMgrs) == nil)
check("naming is case-insensitive — an RPC's hex casing is not a promise",
      gated(VibenetScope.policy, mgrAddr.uppercased()).policyLine(known: knownMgrs)
        == "Limited to the policy manager")
check("a config that named no manager still resolves, by short address",
      gated(VibenetScope.policy, mgrAddr)
        .policyLine(known: VibenetKnownPolicyManagers(policyManager: nil, sessionPolicy: nil))
        == "Limited to …0ac1")

// MARK: - undeployedExplainer — the mechanism, on the one state that has one

print("")
print("VibenetRoom.undeployedExplainer — why an account is not established")
func acctState(reached: Bool, established: Bool) -> VibenetAccountItem {
    VibenetAccountItem(address: "0xaa", reached: reached, established: established,
                       actors: [], locked: false, hasInitiatedUnlock: false,
                       unlocksAt: nil, unlockDelay: nil)
}
check("an undeployed account is told what deploys it",
      (VibenetRoom.undeployedExplainer(acctState(reached: true, established: false)) ?? "")
        .contains("first transaction"))
check("an established account has nothing to explain",
      VibenetRoom.undeployedExplainer(acctState(reached: true, established: true)) == nil)
// The §83 half: an UNREACHED account must never be told why it is undeployed,
// because the truth is that we could not look. Conflating the two is exactly
// what `rowLine` keeps apart, and this must not undo it one line below.
check("an UNREACHED account is never told it is undeployed — we could not look",
      VibenetRoom.undeployedExplainer(acctState(reached: false, established: false)) == nil)

// MARK: - alphabetical — the roster's order, and deliberately not a ranking

print("")
print("VibenetAccountItem.alphabetical — a reproducible order, never a judgement")
// Titles: "Another contract" (delegate) < "P-256 key" < "Passkey" <
// "Wallet key" (secp256k1). The kind sortRank order is DIFFERENT, so a test
// passing here by accident because both orders agree is impossible.
let aDeleg = VibenetActor(actorId: "d", authenticator: "0x1", kind: .delegate,
                          scope: VibenetScope(raw: VibenetScope.sender), expiry: 0)
let aPass  = VibenetActor(actorId: "p", authenticator: "0x2", kind: .webAuthn,
                          scope: VibenetScope(raw: VibenetScope.sender), expiry: 0)
let aSecp  = VibenetActor(actorId: "s", authenticator: "0x3", kind: .secp256k1,
                          scope: VibenetScope(raw: VibenetScope.sender), expiry: 0)
check("sorted by the title the reader actually sees",
      VibenetAccountItem.alphabetical([aSecp, aPass, aDeleg]).map(\.actorId) == ["d", "p", "s"])
check("the order is TOTAL, so a roster cannot reshuffle between opens",
      VibenetAccountItem.alphabetical([aPass, aDeleg, aSecp]).map(\.actorId)
        == VibenetAccountItem.alphabetical([aSecp, aDeleg, aPass]).map(\.actorId))
// The point of the change: an ADMIN is not floated to the top. Its chip
// inverts instead, so total authority is loud where it sorts rather than
// reordered into prominence by the app.
let aAdminSecp = VibenetActor(actorId: "s", authenticator: "0x3", kind: .secp256k1,
                              scope: VibenetScope(raw: 0), expiry: 0)
check("an ADMIN key is NOT promoted — power does not decide the order",
      VibenetAccountItem.alphabetical([aAdminSecp, aDeleg]).map(\.actorId) == ["d", "s"])
check("a tie in title falls back to actorId, never to input order",
      VibenetAccountItem.alphabetical(
        [VibenetActor(actorId: "z", authenticator: "0x4", kind: .webAuthn,
                      scope: VibenetScope(raw: 0x1), expiry: 0), aPass]).map(\.actorId) == ["p", "z"])

// MARK: - VibenetKeyReuse — shipped 2026-08-24 with NO coverage at all
//
// It could not have had any: `sharedLine` reached `VibenetWatch.shared`, a
// UserDefaults singleton, which broke this file's Foundation-only invariant
// and took the WHOLE harness down from the commit that added it. The name
// resolver is a closure now, so both halves are testable. The risk this
// states is the one delegation cannot: losing or leaking ONE key endangers
// every account listed, and every failure below renders as an ordinary row.

print("")
print("VibenetKeyReuse.sharing — the same KEY (actorId) on several watched accounts")
// THE FIXTURE THAT WAS WRONG UNTIL 2026-08-24, and the reason the bug it
// hid was invisible: it varied the AUTHENTICATOR per account and held the
// actorId fixed at "k", which is the exact inverse of what the chain does.
// Live, 199 authorizations sampled: 127 secp256k1 actors across 112
// DISTINCT accounts ALL carry authenticator 0x…01, and only 118 of them are
// distinct keys. So the shipped comparison reported every ordinary wallet
// key on every pair of watched accounts as reused. The authenticator is now
// held FIXED (as the chain holds it) and the actorId varies, so a fixture
// that passes proves the rule it names.
func reuseAcct(_ address: String, _ keyId: String,
               kind: VibenetAuthenticatorKind = .p256,
               authenticator: String = "0xAUTHCONTRACT") -> VibenetAccountItem {
    VibenetAccountItem(address: address, reached: true, established: true,
                       actors: [VibenetActor(actorId: keyId, authenticator: authenticator,
                                             kind: kind, scope: VibenetScope(raw: 0x1), expiry: 0)],
                       locked: false, hasInitiatedUnlock: false,
                       unlocksAt: nil, unlockDelay: nil)
}
let shared = "0xKEY"
let rOne   = reuseAcct("0xaa", shared)
let rTwo   = reuseAcct("0xbb", shared)
let rThree = reuseAcct("0xcc", shared)
let rAlone = reuseAcct("0xdd", "0xOTHER")
// THE CASE THE OLD FIXTURE COULD NOT EXPRESS, and the one that matters
// most: two accounts each holding their OWN key, both validated by the same
// authenticator contract — the single most ordinary configuration on the
// chain. Nothing is shared, and the shipped code said everything was.
check("two DIFFERENT keys sharing one authenticator CONTRACT are not reuse",
      VibenetKeyReuse.sharing(rOne, in: [rOne, rAlone]).isEmpty)
check("a key on ONE account is not reuse",
      VibenetKeyReuse.sharing(rAlone, in: [rOne, rAlone]).isEmpty)
check("reuse names the OTHER accounts, never the one you are looking at",
      VibenetKeyReuse.sharing(rOne, in: [rOne, rTwo, rThree]).map(\.account) == ["0xbb", "0xcc"])
check("the match is case-insensitive — an RPC's hex casing is not a promise",
      !VibenetKeyReuse.sharing(rOne, in: [rOne, reuseAcct("0xbb", shared.lowercased())]).isEmpty)
check("sharing is TOTAL, so a reuse line cannot reshuffle between opens",
      VibenetKeyReuse.sharing(rOne, in: [rThree, rTwo, rOne]).map(\.account)
        == VibenetKeyReuse.sharing(rOne, in: [rTwo, rOne, rThree]).map(\.account))
// A delegate's authenticator names an ACCOUNT, not a key, so counting it as
// reuse would draw the same pair twice under two headings that disagree
// about what relates them — linked accounts already states that one.
let rDeleg = reuseAcct("0xee", shared, kind: .delegate, authenticator: "0xDELEGATECONTRACT")
check("a DELEGATE is excluded from reuse on both sides",
      VibenetKeyReuse.sharing(rDeleg, in: [rDeleg, rOne]).isEmpty
        && VibenetKeyReuse.sharing(rOne, in: [rOne, rDeleg]).isEmpty)

print("")
print("Array<VibenetSharedKey>.sharedLine — WHERE else the key can act")
let nameFor: (String) -> String = { $0 == "0xbb" ? "Session bot" : VibenetRoom.shortAddress($0) }
check("one other account is named outright, through the caller's resolver",
      VibenetKeyReuse.sharing(rOne, in: [rOne, rTwo]).sharedLine(name: nameFor)
        == "Also authorized on Session bot")
check("several are COUNTED rather than listed — the row has one line to spend",
      VibenetKeyReuse.sharing(rOne, in: [rOne, rTwo, rThree]).sharedLine(name: nameFor)
        == "Also authorized on 2 other accounts")
check("no reuse yields no line at all, never an empty sentence",
      VibenetKeyReuse.sharing(rAlone, in: [rAlone]).sharedLine(name: nameFor) == nil)

// MARK: - actorSummary

print("")
print("VibenetRoom.actorSummary")
check("no actors",
      VibenetRoom.actorSummary([]) == "No actors authorized")
check("one actor",
      VibenetRoom.actorSummary([a2]) == "1 secp256k1 key")
check("two of the same kind pluralize",
      VibenetRoom.actorSummary([a2, VibenetActor(actorId: "b", authenticator: "0x4",
                                                   kind: .secp256k1, scope: VibenetScope(raw: 0), expiry: 0)])
        == "2 secp256k1 keys")
check("mixed kinds, in the roster's own order",
      VibenetRoom.actorSummary([a2, a3]) == "1 secp256k1 key, 1 P-256 key")

// MARK: - rowLine — the "established but zero live actors" edge case

print("")
print("VibenetRoom.rowLine")
func account(address: String = "0x1234567890123456789012345678901234567890",
             reached: Bool = true, established: Bool = true, actors: [VibenetActor] = [],
             locked: Bool = false, hasInitiatedUnlock: Bool = false) -> VibenetAccountItem {
    VibenetAccountItem(address: address,
                       reached: reached, established: established, actors: actors,
                       locked: locked, hasInitiatedUnlock: hasInitiatedUnlock,
                       unlocksAt: nil, unlockDelay: nil)
}
// rowLine NEVER restates "Locked"/"Unlocking" — the badge already carries
// that, in bold, beside it — and it COUNTS the keys rather than naming them,
// because the matrix underneath spells every kind out in full the moment the
// row opens. Naming them here too printed the same five words twice, one
// wrapped line apart.
check("a locked account's row line is its key COUNT, not the word 'Locked' again",
      VibenetRoom.rowLine(account(actors: [a2], locked: true)) == "1 key")
check("several keys pluralize, and still never name a kind the matrix is about to name",
      VibenetRoom.rowLine(account(actors: [a1, a2, a3])) == "3 keys")
check("locked with no keys falls back to the same line an unlocked empty account gets",
      VibenetRoom.rowLine(account(locked: true, hasInitiatedUnlock: true)) == "No keys authorized")
check("unreached reads as unreached",
      VibenetRoom.rowLine(account(reached: false)) == "Couldn't reach the chain")
check("not established",
      VibenetRoom.rowLine(account(established: false)) == "Not established yet")
// THE edge case the feature brief calls out by name: established with NO
// live actors is a real, different state from never having been established
// at all, and must not be reported as the latter.
check("established but ZERO live actors reads as its own state, not 'not established'",
      VibenetRoom.rowLine(account(established: true, actors: [])) == "No keys authorized")
check("established with actors counts them",
      VibenetRoom.rowLine(account(established: true, actors: [a2])) == "1 key")

// MARK: - ordered — the one alarm this room can raise

print("")
print("VibenetRoom.ordered")
// Sorts AFTER every "quiet" fixture's address below, on purpose — an
// ordering bug that only ever ties on the address tie-break (both fixtures
// sharing `account()`'s default address) would pass by accident.
let locked = account(address: "0xzzzz000000000000000000000000000000zzzz", locked: true)
let quietA = VibenetAccountItem(address: "0xaaaa000000000000000000000000000000aaaa",
                                reached: true, established: true, actors: [],
                                locked: false, hasInitiatedUnlock: false,
                                unlocksAt: nil, unlockDelay: nil)
let quietB = VibenetAccountItem(address: "0xbbbb000000000000000000000000000000bbbb",
                                reached: true, established: true, actors: [],
                                locked: false, hasInitiatedUnlock: false,
                                unlocksAt: nil, unlockDelay: nil)
let unreached = VibenetAccountItem(address: "0xcccc000000000000000000000000000000cccc",
                                   reached: false, established: false, actors: [],
                                   locked: false, hasInitiatedUnlock: false,
                                   unlocksAt: nil, unlockDelay: nil)
check("a locked account leads even when it sorts last alphabetically",
      VibenetRoom.ordered([quietB, locked]).first?.address == locked.address)
check("an unreached read outranks a reached-but-quiet one",
      VibenetRoom.ordered([quietA, unreached]).first?.address == unreached.address)
check("ties break on address, alphabetically",
      VibenetRoom.ordered([quietB, quietA]).map(\.address) == [quietA.address, quietB.address])
check("ordering is TOTAL — a second pass over the same set agrees with the first",
      VibenetRoom.ordered([quietB, locked, unreached, quietA])
        == VibenetRoom.ordered([quietA, locked, unreached, quietB]))

// The matrix column headers are `shortLabel` — the ONE place a kind name
// must fit a narrow column. It stays a real word ("secp256k1", "Passkey"),
// never an abbreviation and never a glyph: both of those shipped once and
// both were undecodable on the device.
print("")
print("VibenetAuthenticatorKind.shortLabel — matrix column headers")
check("shortLabel is a real word, just without the key/authenticator suffix",
      VibenetAuthenticatorKind.secp256k1.shortLabel == "secp256k1"
        && VibenetAuthenticatorKind.custom.shortLabel == "Custom"
        && !VibenetAuthenticatorKind.secp256k1.shortLabel.contains("key"))

// The single-key sentence's own title — plain words over spec jargon, but
// each line is the WHOLE claim this build is willing to make.
print("")
print("VibenetAuthenticatorKind.plainTitle / plainDetail — meaning over jargon")
check("secp256k1 reads as a wallet key, not the scheme name",
      VibenetAuthenticatorKind.secp256k1.plainTitle == "Wallet key")
check("a delegate reads as another contract signing, not spec jargon",
      VibenetAuthenticatorKind.delegate.plainTitle == "Another contract")
check("P-256 names the CURVE only, never where a particular key lives",
      VibenetAuthenticatorKind.p256.plainDetail == "the curve passkeys and secure enclaves use")
check("an unidentified authenticator gets no invented detail",
      VibenetAuthenticatorKind.custom.plainDetail == nil)
check("every kind but custom carries a detail clause",
      [VibenetAuthenticatorKind.secp256k1, .p256, .webAuthn, .delegate]
        .allSatisfy { $0.plainDetail != nil })

// MARK: - headline / note

print("")
print("VibenetRoom.headline / note — the lead-based shape (2026-08-23, the ASCRoom precedent)")
let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
check("an unreachable config says so",
      VibenetRoom.headline(VibenetRoom.compose(items: [], branch: nil, commit: nil, configReached: false), now: fixedNow)
        == "Couldn't read vibenet's current contracts")
check("nothing watched",
      VibenetRoom.headline(VibenetRoom.compose(items: [], branch: nil, commit: nil, configReached: true), now: fixedNow)
        == "Nothing watched on vibenet yet")
let oneLocked = VibenetRoom.compose(items: [locked], branch: "main", commit: "abc", configReached: true)
check("the lead's own address and state, no rolled-up count",
      VibenetRoom.headline(oneLocked, now: fixedNow) == "…zzzz · Locked")
let twoLocked = VibenetRoom.compose(items: [locked, account(locked: true)], branch: nil, commit: nil, configReached: true)
check("two locked accounts still name only the LEAD — ordered's own address tie-break decides which",
      VibenetRoom.headline(twoLocked, now: fixedNow) == "…7890 · Locked")
// The reported case, now moot by construction: the card's hero used to draw
// EVERY watched face while the sentence counted only the locked ones, which
// read as a contradiction. There is no hero stack and no rolled-up count
// anymore — the headline names the ONE account it's actually about.
let twoOfFour = VibenetRoom.compose(
    items: [locked, account(locked: true), account(address: "0xaaa"), account(address: "0xbbb")],
    branch: nil, commit: nil, configReached: true)
check("a bigger room still leads with the same one account — size never changes WHO leads",
      VibenetRoom.headline(twoOfFour, now: fixedNow) == "…7890 · Locked")

// MARK: - VibenetRoom.scoped — the face rail narrows the CARD, as wallet's does
check("no pick leaves the room whole",
      twoOfFour.scoped(to: nil).items.count == 4)
check("a pick narrows the card to that one account",
      twoOfFour.scoped(to: "0xaaa").items.map(\.address) == ["0xaaa"])
check("scoping is case-insensitive — a watch list may hold any case",
      twoOfFour.scoped(to: "0xAAA").items.count == 1)
check("an address no longer watched scopes to NOTHING, never silently to everything",
      twoOfFour.scoped(to: "0xdead").items.isEmpty)
// Scoping to the alarmed account's OWN address collapses the room to just
// its lead — the mechanism the card's "click one you see one" relies on.
check("scoping to the locked account leaves it as its own lead",
      twoOfFour.scoped(to: "0xzzzz000000000000000000000000000000zzzz").lead?.address
        == "0xzzzz000000000000000000000000000000zzzz")

let allUnreached = VibenetRoom.compose(items: [unreached], branch: nil, commit: "xyz", configReached: true)
check("an unreached lead says so, in the same slot a locked one's state would sit",
      VibenetRoom.headline(allUnreached, now: fixedNow) == "…cccc · Couldn't reach the chain")
let notEstablished = VibenetRoom.compose(items: [account(established: false)], branch: nil, commit: nil, configReached: true)
check("reached, nothing established yet",
      VibenetRoom.headline(notEstablished, now: fixedNow) == "…7890 · Not established yet")
let established = VibenetRoom.compose(items: [account(established: true, actors: [a2])], branch: nil, commit: nil, configReached: true)
check("an established lead states its key count",
      VibenetRoom.headline(established, now: fixedNow) == "…7890 · 1 key")

// The lead's own clock — appended as a THIRD clause, never invented for an
// account with nothing ticking. `.relative(presentation:)` formats against
// the REAL wall clock, never the `now:` PARAMETER (see `urgentLine`'s own
// tests below for why `fixedNow`, a fixed 2023 timestamp, can't anchor
// these two — it would print "N years ago" against today's real clock) —
// so these anchor on `Date.now` and check a PREFIX, the same shape every
// other relative-time assertion in this file already uses.
let headlineLiveNow = Date.now
let futureExpiry = UInt64(headlineLiveNow.timeIntervalSince1970) + 2 * 86_400
let expiringActor = VibenetActor(actorId: "e", authenticator: "0x9", kind: .secp256k1,
                                 scope: VibenetScope(raw: 0), expiry: futureExpiry)
let expiringLead = VibenetRoom.compose(items: [account(established: true, actors: [expiringActor])],
                                       branch: nil, commit: nil, configReached: true)
check("an established lead with a key inside the urgency window appends its own expiry",
      VibenetRoom.headline(expiringLead, now: headlineLiveNow).hasPrefix("…7890 · 1 key · Key expires"))
let unlockingLead = VibenetAccountItem(
    address: "0x1234567890123456789012345678901234567890",
    reached: true, established: true, actors: [], locked: true, hasInitiatedUnlock: true,
    unlocksAt: UInt64(headlineLiveNow.timeIntervalSince1970) + 3600, unlockDelay: 7200)
let unlockingRoom = VibenetRoom.compose(items: [unlockingLead], branch: nil, commit: nil, configReached: true)
check("an unlocking lead appends its own countdown, ahead of any key expiry",
      VibenetRoom.headline(unlockingRoom, now: headlineLiveNow).hasPrefix("…7890 · Unlocking · Unlocks"))

check("note states branch and commit — no hidden-count clause when nothing is hidden",
      VibenetRoom.note(oneLocked, drawn: oneLocked.items.count) == "As of vibenet's main branch, commit abc")
check("note falls back to commit alone",
      VibenetRoom.note(allUnreached, drawn: allUnreached.items.count) == "As of vibenet commit xyz")
check("note falls back further with neither",
      VibenetRoom.note(twoLocked, drawn: twoLocked.items.count) == "Read live from vibenet — addresses redeploy often")
check("note over an unreachable config says so plainly, regardless of drawn count",
      VibenetRoom.note(VibenetRoom.compose(items: [], branch: nil, commit: nil, configReached: false), drawn: 0)?
        .contains("redeploy") == true)
// The ASCRoom shape this was built from: how many more aren't drawn, joined
// ahead of the provenance fragment.
check("a capped room states how many more are watched, joined ahead of the provenance",
      VibenetRoom.note(twoOfFour, drawn: 2) == "2 more watched · Read live from vibenet — addresses redeploy often")
check("a singular hidden count doesn't pluralize",
      VibenetRoom.note(twoOfFour, drawn: 3) == "1 more watched · Read live from vibenet — addresses redeploy often")

// A redeploy the device has already seen leads the note over the plain
// provenance line — the single most on-theme fact this room can report.
let redeployed = VibenetRoom.compose(items: [], branch: "main", commit: "def456789",
                                      configReached: true, redeployedSinceLastSeen: true)
check("a seen redeploy leads the note, not the plain provenance line",
      VibenetRoom.note(redeployed, drawn: 0)?.contains("vibenet redeployed") == true)
check("the redeploy note still carries the new commit",
      VibenetRoom.note(redeployed, drawn: 0)?.contains("def456789") == true)
// A commit-less redeploy report can't happen from the real compose path (the
// bridge only ever flags a redeploy when it has a commit to compare), but a
// future caller getting that wrong must fall back to the plain line rather
// than draw a broken sentence with no commit in it.
let redeployedNoCommit = VibenetRoom.compose(items: [], branch: nil, commit: nil,
                                              configReached: true, redeployedSinceLastSeen: true)
check("a redeploy flag with no commit falls back to the plain note, never a broken sentence",
      VibenetRoom.note(redeployedNoCommit, drawn: 0) == "Read live from vibenet — addresses redeploy often")

// MARK: - demoFixture — every state the card can draw, in one snapshot

print("")
print("VibenetRoom.demoFixture")
let demo = VibenetRoom.demoFixture()
check("four accounts, matching the four addresses DemoSeedAll seeds",
      demo.items.count == 4)
check("exactly two locked (one plain, one mid-unlock)",
      demo.lockedCount == 2)
check("all five nameable authenticator kinds appear somewhere in the roster",
      Set(demo.items.flatMap { $0.actors.map(\.kind) }) ==
        Set([.secp256k1, .p256, .webAuthn, .delegate, .custom]))
check("the roster's own unknown-scope actor reports an unknown count, never an invented name",
      demo.items.flatMap(\.actors).contains { $0.scope.unknownCount > 0 })
check("one account is reachable but not yet established",
      demo.items.contains { $0.reached && !$0.established })
check("the fixture reports its own redeploy, so the note shows it off too",
      VibenetRoom.note(demo, drawn: demo.items.count)?.contains("vibenet redeployed") == true)
check("at least one actor carries a future expiry — the matrix's own sub-label, otherwise never demoed",
      demo.items.flatMap(\.actors).contains { $0.expiry > UInt64(Date.now.timeIntervalSince1970) })
check("a single-actor account ALSO carries an expiry — singleKeyLine's own code path, not just the matrix's",
      demo.items.contains { $0.actors.count == 1 && ($0.actors.first?.expiry ?? 0) > 0 })
check("at least one account carries a non-nil changeSequences — the multichain footer line, otherwise never demoed",
      demo.items.contains { $0.changeSequences != nil })
check("R2: at least one account carries a multi-moment history — the strip's own dots, otherwise never demoed",
      demo.items.contains { $0.history.count > 1 })
check("R2: at least one account carries EXACTLY one history moment — the strip's no-strip floor",
      demo.items.contains { $0.history.count == 1 })
check("R2: at least one account has a key inside the 7-day urgency window — the collapsed row's own alarm",
      demo.items.contains { $0.urgentLine(now: .now)?.hasPrefix("Key expires") == true })
check("the demo carries one real watched-to-watched delegate link — otherwise the mapping section never demos",
      VibenetAccountMapping.links(demo.items).count == 1)
check("the demo's aggregate key summary is non-nil — otherwise that section never demos either",
      VibenetKeyAggregation.compose(demo.items, now: .now) != nil)

// MARK: - VibenetActor.expiryLabel / VibenetAccountItem.unlockLabel

print("")
print("VibenetActor.expiryLabel / unlockLabel — the two clocks that were read and thrown away")
let refNow = Date(timeIntervalSince1970: 1_000_000_000)
func actorWithExpiry(_ expiry: UInt64) -> VibenetActor {
    VibenetActor(actorId: "e", authenticator: "0x1", kind: .secp256k1,
                 scope: VibenetScope(raw: 0), expiry: expiry)
}
check("expiry == 0 is Keystore.sol's own convention for 'never', not a date",
      actorWithExpiry(0).expiryLabel(now: refNow) == "Never expires")
check("a future expiry counts down",
      actorWithExpiry(UInt64(refNow.timeIntervalSince1970) + 3600).expiryLabel(now: refNow)
        .hasPrefix("Expires"))
check("a past expiry reads as expired, not as a countdown that went negative",
      actorWithExpiry(UInt64(refNow.timeIntervalSince1970) - 3600).expiryLabel(now: refNow)
        .hasPrefix("Expired"))

check("no unlock initiated yet — the badge has nothing to count down to",
      account(locked: true, hasInitiatedUnlock: false).unlockLabel(now: refNow) == nil)
let readyItem = VibenetAccountItem(address: "0x1", reached: true, established: true, actors: [],
                                    locked: true, hasInitiatedUnlock: true,
                                    unlocksAt: UInt64(refNow.timeIntervalSince1970) - 60, unlockDelay: nil)
check("an unlock time already in the past reads as ready, not a negative countdown",
      readyItem.unlockLabel(now: refNow) == "Unlock ready")
let countingItem = VibenetAccountItem(address: "0x1", reached: true, established: true, actors: [],
                                       locked: true, hasInitiatedUnlock: true,
                                       unlocksAt: UInt64(refNow.timeIntervalSince1970) + 3600, unlockDelay: nil)
check("a future unlock time counts down",
      countingItem.unlockLabel(now: refNow)?.hasPrefix("Unlocks") == true)

// MARK: - VibenetAccountItem.unlockProgress — nil unless BOTH endpoints are known

print("")
print("VibenetAccountItem.unlockProgress — a bar with a guessed start is fake status, §83")
check("no unlock initiated — nothing to show a bar for",
      account(locked: true, hasInitiatedUnlock: false).unlockProgress(now: refNow) == nil)
check("unlocksAt known but unlockDelay missing — no start point, so no bar",
      countingItem.unlockProgress(now: refNow) == nil)
func unlockingItem(delaySeconds: UInt16, secondsIntoDelay: Double) -> VibenetAccountItem {
    // start = now - secondsIntoDelay (so `elapsed` at `now` is exactly
    // secondsIntoDelay); end = start + delay.
    let start = refNow.timeIntervalSince1970 - secondsIntoDelay
    let end = start + Double(delaySeconds)
    return VibenetAccountItem(address: "0x1", reached: true, established: true, actors: [],
                               locked: true, hasInitiatedUnlock: true,
                               unlocksAt: UInt64(end), unlockDelay: delaySeconds)
}
check("right at the start of the timelock reads as 0",
      unlockingItem(delaySeconds: 3600, secondsIntoDelay: 0).unlockProgress(now: refNow) == 0)
check("right at the end reads as 1",
      unlockingItem(delaySeconds: 3600, secondsIntoDelay: 3600).unlockProgress(now: refNow) == 1)
let midway = unlockingItem(delaySeconds: 3600, secondsIntoDelay: 1800).unlockProgress(now: refNow)
check("midway through reads as ~0.5",
      midway != nil && abs(midway! - 0.5) < 0.001)
check("clamped — never negative even if the delay reads slightly off",
      unlockingItem(delaySeconds: 3600, secondsIntoDelay: -600).unlockProgress(now: refNow) == 0)
check("clamped — never past 1 even past the unlock moment",
      unlockingItem(delaySeconds: 3600, secondsIntoDelay: 9000).unlockProgress(now: refNow) == 1)

// MARK: - VibenetAccountItem.urgentLine — R2.2, the collapsed row's own alarm clock

print("")
print("VibenetAccountItem.urgentLine — the time-critical fact surfaces before you open anything")
func itemWithExpiries(_ expiries: [UInt64]) -> VibenetAccountItem {
    let actors = expiries.enumerated().map { i, e in
        VibenetActor(actorId: "e\(i)", authenticator: "0x1", kind: .secp256k1,
                    scope: VibenetScope(raw: 0), expiry: e)
    }
    return VibenetAccountItem(address: "0x1", reached: true, established: true, actors: actors,
                              locked: false, hasInitiatedUnlock: false, unlocksAt: nil, unlockDelay: nil)
}
let day = 86_400.0
check("nothing dated at all — no urgency to report",
      itemWithExpiries([0]).urgentLine(now: refNow) == nil)
check("a key expiring well outside the 7-day window says nothing",
      itemWithExpiries([UInt64(refNow.timeIntervalSince1970 + 8 * day)]).urgentLine(now: refNow) == nil)
check("a key expiring inside the window leads the row",
      itemWithExpiries([UInt64(refNow.timeIntervalSince1970 + 6 * day)]).urgentLine(now: refNow)?.hasPrefix("Key expires") == true)
// `.relative(presentation:)` formats against the REAL wall clock, not the
// `now:` PARAMETER — so two dates that are both merely "in the past
// relative to `refNow`" (a fixed 2001 timestamp) both print "N years ago"
// at real-world granularity and a text comparison can't tell them apart.
// Anchored to `Date.now` here for exactly that reason (`expiryLabel`'s own
// doc already names this; the demo fixture is the other sanctioned spot).
let liveNow = Date.now
let nearOnly = UInt64(liveNow.timeIntervalSince1970 + 1 * day)
let farOnly = UInt64(liveNow.timeIntervalSince1970 + 6 * day)
check("of two future expiries, the SOONEST wins — matches the near-only line, not the far-only one",
      itemWithExpiries([nearOnly, farOnly]).urgentLine(now: liveNow) == itemWithExpiries([nearOnly]).urgentLine(now: liveNow)
        && itemWithExpiries([nearOnly, farOnly]).urgentLine(now: liveNow) != itemWithExpiries([farOnly]).urgentLine(now: liveNow))
check("a ticking clock outranks an already-expired key on the same account",
      itemWithExpiries([UInt64(refNow.timeIntervalSince1970 - day),
                        UInt64(refNow.timeIntervalSince1970 + 2 * day)])
        .urgentLine(now: refNow)?.hasPrefix("Key expires") == true)
check("nothing ticking, one already expired — counted, singular",
      itemWithExpiries([UInt64(refNow.timeIntervalSince1970 - day)]).urgentLine(now: refNow) == "1 key expired")
check("nothing ticking, several expired — counted, plural",
      itemWithExpiries([UInt64(refNow.timeIntervalSince1970 - day),
                        UInt64(refNow.timeIntervalSince1970 - 2 * day)])
        .urgentLine(now: refNow) == "2 keys expired")
check("expiry == 0 (Keystore's own 'never') never counts toward either half",
      itemWithExpiries([0, UInt64(refNow.timeIntervalSince1970 - day)]).urgentLine(now: refNow) == "1 key expired")

// MARK: - VibenetKeyHistory — R2.1, the account's own story as a sequence strip

print("")
print("VibenetKeyHistory — a SEQUENCE strip, never a time-proportional axis")
func moment(_ block: Int, _ logIndex: Int, authorized: Bool, date: Date? = nil) -> VibenetKeyMoment {
    VibenetKeyMoment(block: block, logIndex: logIndex, authorized: authorized, kind: authorized ? .secp256k1 : nil, date: date)
}
let unordered = [moment(5, 1, authorized: true), moment(5, 0, authorized: false), moment(3, 0, authorized: true)]
check("ordered is TOTAL — block first, then logIndex — a second pass agrees with the first",
      VibenetKeyHistory.ordered(unordered).map(\.id) == VibenetKeyHistory.ordered(VibenetKeyHistory.ordered(unordered)).map(\.id))
check("ordered sorts by block then logIndex, oldest first",
      VibenetKeyHistory.ordered(unordered).map { "\($0.block),\($0.logIndex)" } == ["3,0", "5,0", "5,1"])

check("summaryLine is nil when there is nothing to summarize",
      VibenetKeyHistory.summaryLine([]) == nil)
check("summaryLine counts adds alone, singular",
      VibenetKeyHistory.summaryLine([moment(1, 0, authorized: true)]) == "1 key added")
check("summaryLine counts both halves, correct plurals, added leads",
      VibenetKeyHistory.summaryLine([moment(1, 0, authorized: true), moment(2, 0, authorized: true),
                                     moment(3, 0, authorized: false)]) == "2 keys added · 1 revoked")
check("summaryLine omits a zero half rather than saying '0 revoked'",
      !VibenetKeyHistory.summaryLine([moment(1, 0, authorized: true)])!.contains("revoked"))

let refDate = Date(timeIntervalSince1970: 2_000_000_000)
// Live-anchored (the same reason `urgentLine`'s soonest-wins test is,
// above): `.relative` formats against the REAL wall clock, and two
// `refDate`-relative endpoints only 8 days apart both round to the same
// "N years ago" at that granularity — collapsing `newest` to nil for a
// reason that has nothing to do with the function under test.
let liveDated = [moment(1, 0, authorized: true, date: liveNow.addingTimeInterval(-10 * day)),
                 moment(2, 0, authorized: false, date: liveNow.addingTimeInterval(-2 * day))]
let liveLabels = VibenetKeyHistory.endpointLabels(liveDated, now: liveNow)
check("endpointLabels resolves both real endpoints, distinctly",
      liveLabels.oldest != nil && liveLabels.newest != nil && liveLabels.oldest != liveLabels.newest)
check("an endpoint with no date is omitted, never guessed",
      VibenetKeyHistory.endpointLabels([moment(1, 0, authorized: true, date: nil),
                                        moment(2, 0, authorized: false, date: refDate)],
                                       now: refDate).oldest == nil)
check("a single moment's newest label collapses to nil rather than repeating the oldest",
      VibenetKeyHistory.endpointLabels([moment(1, 0, authorized: true, date: refDate)], now: refDate).newest == nil)
check("newest wraps the newest cap-worth of events, chronologically ordered",
      VibenetKeyHistory.newest([VibenetActorEvent(actorId: "a", authorized: true, block: 1, logIndex: 0),
                                VibenetActorEvent(actorId: "b", authorized: true, block: 2, logIndex: 0),
                                VibenetActorEvent(actorId: "c", authorized: true, block: 3, logIndex: 0)],
                               cap: 2).map(\.block) == [2, 3])

// MARK: - VibenetChangeSequences.chips — R2.3

print("")
print("VibenetChangeSequences.chips — number-hero chips, replacing the single-chain sentence")
let cs = VibenetChangeSequences(multichain: 12, localEpoch: 2, localSequence: 5)
check("two chips, multichain first",
      cs.chips.map(\.value) == ["12", "5"])
check("a zero standing is a real reading, never hidden",
      VibenetChangeSequences(multichain: 0, localEpoch: 0, localSequence: 0).chips.map(\.value) == ["0", "0"])
check("labels carry the epoch, not just a bare 'local'",
      cs.chips[1].label.contains("2"))

// MARK: - VibenetChangeSequences.plainLine — the sentence that replaced the chips

print("")
print("VibenetChangeSequences.plainLine — English, or silence")
check("nothing changed at all says NOTHING — a stat of two zeros has no reading",
      VibenetChangeSequences(multichain: 0, localEpoch: 0, localSequence: 0).plainLine == nil)
check("this chain only, once — singular",
      VibenetChangeSequences(multichain: 0, localEpoch: 0, localSequence: 1).plainLine
        == "Changed once, on this chain only")
check("this chain only, several — plural",
      VibenetChangeSequences(multichain: 0, localEpoch: 1, localSequence: 4).plainLine
        == "Changed 4 times, on this chain only")
check("shared across chains, once — singular",
      VibenetChangeSequences(multichain: 1, localEpoch: 0, localSequence: 0).plainLine
        == "Changed once, shared across chains")
check("both kinds names both, never silently drops one",
      VibenetChangeSequences(multichain: 3, localEpoch: 0, localSequence: 2).plainLine
        == "Changed 2 times here, 3 shared across chains")

// MARK: - VibenetKeyHistory.isSequence — dots only when there IS an order

print("")
print("VibenetKeyHistory.isSequence — two keys in ONE transaction are one moment, not two")
check("two moments sharing a block are NOT a sequence — no order to draw",
      !VibenetKeyHistory.isSequence([moment(204532, 0, authorized: true),
                                     moment(204532, 1, authorized: true)]))
check("two moments in different blocks ARE a sequence",
      VibenetKeyHistory.isSequence([moment(204532, 0, authorized: true),
                                    moment(204999, 0, authorized: false)]))
check("a lone moment is never a sequence",
      !VibenetKeyHistory.isSequence([moment(1, 0, authorized: true)]))
check("no moments at all is never a sequence",
      !VibenetKeyHistory.isSequence([]))

// MARK: - VibenetMultichainSync

print("")
print("VibenetMultichainSync — honestly a one-chain reading until 8130 has a second live chain")
let oneChain = [VibenetChainStanding(chainName: "vibenet",
                                     sequences: VibenetChangeSequences(multichain: 3, localEpoch: 0, localSequence: 3))]
check("with one chain there is nothing to compare — never guesses at a sync gap",
      VibenetMultichainSync.summary(oneChain) == "Only one EIP-8130 chain to compare — nothing to sync yet")
check("laggingChains is empty below two chains, the same honesty rule",
      VibenetMultichainSync.laggingChains(oneChain).isEmpty)

let leader = VibenetChainStanding(chainName: "vibenet",
                                  sequences: VibenetChangeSequences(multichain: 5, localEpoch: 0, localSequence: 5))
let laggard = VibenetChainStanding(chainName: "sepolia-8130",
                                   sequences: VibenetChangeSequences(multichain: 3, localEpoch: 0, localSequence: 3))
check("a chain behind the leading multichain count is named as lagging",
      VibenetMultichainSync.laggingChains([leader, laggard]).map(\.chainName) == ["sepolia-8130"])
check("summary counts the lagging chains, singular wording",
      VibenetMultichainSync.summary([leader, laggard])
        == "1 chain hasn't applied the latest multichain change yet")
let caughtUp = VibenetChainStanding(chainName: "sepolia-8130",
                                    sequences: VibenetChangeSequences(multichain: 5, localEpoch: 0, localSequence: 1))
check("two chains at the same multichain count read as fully caught up",
      VibenetMultichainSync.summary([leader, caughtUp]).hasPrefix("Every chain has applied"))

// MARK: - VibenetEventKind — the feed-landing titles

print("")
print("VibenetEventKind.title — the feed's own door into this room")
check("a new key lands with its resolved kind when one was confirmed",
      VibenetEventKind.actorAuthorized.title(shortAddress: "…0b1c", keyLabel: "secp256k1 key")
        == "New secp256k1 key authorized for …0b1c")
check("a new key still lands honestly with no invented kind when the re-read couldn't confirm one",
      VibenetEventKind.actorAuthorized.title(shortAddress: "…0b1c", keyLabel: nil)
        == "New key authorized for …0b1c")
check("a revocation names no kind at all — the key that's gone isn't re-read to find one",
      VibenetEventKind.actorRevoked.title(shortAddress: "…0b1c", keyLabel: "secp256k1 key")
        == "Key revoked for …0b1c")
check("a lock event",
      VibenetEventKind.locked.title(shortAddress: "…0b1c", keyLabel: nil) == "…0b1c locked on vibenet")

// MARK: - shortAddress

print("")
print("VibenetRoom.shortAddress")
check("a real address is tail-only elided — one truncation, not two",
      VibenetRoom.shortAddress("0x8130931874c894ac4963e128d6273ae520dafa57") == "…fa57")
check("a short string passes through untouched",
      VibenetRoom.shortAddress("0xabc") == "0xabc")

// MARK: - VibenetAccountMapping.links — the ONE real account-to-account signal

print("")
print("VibenetAccountMapping.links")
// THE FIXTURE THAT COULD NEVER HAVE FAILED, fixed 2026-08-24. It used to
// put the delegate's address in the AUTHENTICATOR field. The chain puts it
// in the actorId — `DelegateAuthenticator.authenticate` returns
// `actorId = ActorId.fromAddress(delegate)` and the authenticator is the
// DelegateAuthenticator CONTRACT, the same address for all 5 live delegates
// on vibenet. So `links` matched a field the chain never varies, could not
// have produced one link on a real read, and this suite proved it worked.
//
// Addresses here are FULL 40-hex now, not "0xa1": `delegateAddress` decodes
// a real 32-byte word, so a fixture using a short pretend address would
// take the nil branch and every check below would pass vacuously.
func padActorId(_ address: String) -> String {
    "0x" + String(repeating: "0", count: 24) + String(address.dropFirst(2))
}
func delegateActor(to address: String) -> VibenetActor {
    VibenetActor(actorId: padActorId(address), authenticator: "0xDELEGATEAUTHENTICATORCONTRACT",
                 kind: .delegate, scope: VibenetScope(raw: 0), expiry: 0)
}
let alice = "0xa100000000000000000000000000000000000001"
let bob = "0xb200000000000000000000000000000000000002"
let carol = "0xc300000000000000000000000000000000000003"
let stranger = "0xdead000000000000000000000000000000000004"

check("no items at all — nothing to derive a mapping from",
      VibenetAccountMapping.links([]).isEmpty)

let aliceDelegatesToBob = account(address: alice, actors: [delegateActor(to: bob)])
let bobPlain = account(address: bob)
check("a delegate actorId naming a WATCHED account produces a link",
      VibenetAccountMapping.links([aliceDelegatesToBob, bobPlain])
        == [VibenetDelegateLink(from: alice, to: bob)])

let aliceDelegatesToStranger = account(address: alice, actors: [delegateActor(to: stranger)])
check("a delegate actorId naming NO watched account produces no link — never fabricated",
      VibenetAccountMapping.links([aliceDelegatesToStranger, bobPlain]).isEmpty)

// A plain key whose actorId is address-derived and happens to name bob —
// which is NORMAL, not exotic: a secp256k1 key's actorId IS its signer
// address, so most k1 actorIds decode to a real address. Only `.delegate`
// may ever produce a link.
let aliceHoldsAPlainKeyPointingAtBob = account(address: alice, actors: [
    VibenetActor(actorId: padActorId(bob), authenticator: "0x0000000000000000000000000000000000000001",
                 kind: .secp256k1, scope: VibenetScope(raw: 0), expiry: 0)])
check("a non-delegate actor never produces a link, however its actorId reads",
      VibenetAccountMapping.links([aliceHoldsAPlainKeyPointingAtBob, bobPlain]).isEmpty)

// THE UPPERCASE MUST BE ON THE WATCHED ITEM'S OWN ADDRESS, not on the
// delegate id. `VibenetActorId.address` lowercases what it decodes, so an
// uppercased actorId comes back already normalized and a case-SENSITIVE
// compare would pass it — the mutation survived exactly that way on this
// check's first run. It is the stored address, which arrives from a watch
// list a person pasted into, that can carry checksummed casing.
let bobPlainChecksummed = account(address: bob.uppercased())
check("the compare is case-insensitive — an RPC's (or a paste's) hex casing is not a promise",
      VibenetAccountMapping.links([aliceDelegatesToBob, bobPlainChecksummed])
        == [VibenetDelegateLink(from: alice, to: bob.uppercased())])

// Order must be TOTAL — a mapping section that reshuffles between opens
// over an unchanged room reads as broken, the standard every roster here
// already holds.
let bobDelegatesToAlice = account(address: bob, actors: [delegateActor(to: alice)])
let carolDelegatesToAlice = account(address: carol, actors: [delegateActor(to: alice)])
let alicePlain = account(address: alice)
check("links sort by `from`, then `to`, regardless of input order",
      VibenetAccountMapping.links([carolDelegatesToAlice, bobDelegatesToAlice, alicePlain])
        == [VibenetDelegateLink(from: bob, to: alice), VibenetDelegateLink(from: carol, to: alice)])

// MARK: - VibenetActorId — the decode both bugs above turned on
//
// `ActorId.fromAddress(addr)` is `bytes32(uint256(uint160(addr)))`. The
// high-12-zero test is the WHOLE guard: without it every 32-byte hash
// yields a plausible 20-byte "address" belonging to nobody, and that value
// is then compared against real watched addresses.

print("")
print("VibenetActorId")
let addrA = "0x2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c"
check("an address-derived actorId decodes back to its address",
      VibenetActorId.address(fromActorId: padActorId(addrA)) == addrA)
check("the round trip closes both ways",
      VibenetActorId.actorId(forAddress: addrA) == padActorId(addrA))
check("a HASH-shaped actorId names no address — a P-256 key's id is not an address",
      VibenetActorId.address(
        fromActorId: "0xbecca764da7d7c3bc31d77c515cd3d5d3ac31a33becca764da7d7c3bc31d77c5") == nil)
check("an all-zero actorId is the zero address, never a real account",
      VibenetActorId.address(fromActorId: "0x" + String(repeating: "0", count: 64)) == nil)
check("a short/garbage id decodes to nothing rather than to a truncated guess",
      VibenetActorId.address(fromActorId: "0xdeadbeef") == nil
        && VibenetActorId.actorId(forAddress: "0xnothex") == nil)
check("casing is not a promise — an uppercased id still decodes",
      VibenetActorId.address(fromActorId: padActorId(addrA).uppercased()) == addrA.lowercased())
check("a delegate actor names its target; a non-delegate never does",
      delegateActor(to: bob).delegateAddress == bob
        && VibenetActor(actorId: padActorId(bob), authenticator: "0x1", kind: .secp256k1,
                        scope: VibenetScope(raw: 0), expiry: 0).delegateAddress == nil)

// MARK: - VibenetPolicyUse — the one live fact a session key publishes
//
// The CAP is not on chain (`VibenetPolicyReadability`): `SessionPolicy`
// stores mutable spend usage only, and the config carrying the limit,
// period and recipients is committed as a hash. What IS readable is
// whether the key ever ran, so these lines are the whole of the claim —
// a count and a date, never a rate, an average or a projection.

print("")
print("VibenetPolicyUse")
let useNow = Date(timeIntervalSince1970: 1_000_000_000)
let usedFour = VibenetPolicyUse(commitment: "0xC0", count: 4,
                                lastUsed: useNow.addingTimeInterval(-2 * 86_400))
check("a used key states the count AND when it last ran",
      usedFour.line(now: useNow).hasPrefix("Used 4 times · last "))
check("once is singular",
      VibenetPolicyUse(commitment: "0xC0", count: 1, lastUsed: nil).line(now: useNow) == "Used once")
check("a zero count is SPOKEN — on a subscription key, never having charged is the reading",
      VibenetPolicyUse(commitment: "0xC0", count: 0, lastUsed: nil).line(now: useNow) == "Never used")
check("a failed block-time lookup drops the clause, never dates it to now",
      VibenetPolicyUse(commitment: "0xC0", count: 4, lastUsed: nil).line(now: useNow) == "Used 4 times")
let gatedActor = VibenetActor(actorId: "g", authenticator: "0x1", kind: .secp256k1,
                              scope: VibenetScope(raw: VibenetScope.policy), expiry: 0,
                              policyManager: "0xMGR", policyCommitment: "0xc0")
check("usage joins to a key by its COMMITMENT, case-insensitively",
      [usedFour].use(for: gatedActor)?.count == 4)
check("an UNGATED key can never pick up someone else's usage",
      [usedFour].use(for: VibenetActor(actorId: "u", authenticator: "0x1", kind: .secp256k1,
                                       scope: VibenetScope(raw: VibenetScope.sender), expiry: 0)) == nil)

// MARK: - VibenetSubAccounts — Base's "Spending Account", read in reverse

print("")
print("VibenetSubAccounts")
let subWatched = VibenetSubAccount(address: "0xaa1", watched: true,
                                   authorizedAt: useNow.addingTimeInterval(-9 * 86_400))
let subNew = VibenetSubAccount(address: "0xbb2", watched: false,
                               authorizedAt: useNow.addingTimeInterval(-3 * 86_400))
let subOld = VibenetSubAccount(address: "0xcc3", watched: false,
                               authorizedAt: useNow.addingTimeInterval(-30 * 86_400))
check("no sub-accounts earns no line at all",
      VibenetSubAccounts.line([]) == nil)
check("all watched — the count alone, with no 'not watched' clause to add",
      VibenetSubAccounts.line([subWatched]) == "Can act for 1 account")
check("an unwatched one is CALLED OUT — it is the whole reason for the read",
      VibenetSubAccounts.line([subWatched, subNew]) == "Can act for 2 accounts · 1 not watched")
check("unwatched sort FIRST, then newest — the discovery leads",
      VibenetSubAccounts.ordered([subWatched, subOld, subNew]).map(\.address) == ["0xbb2", "0xcc3", "0xaa1"])
check("ordering is TOTAL, so the list cannot reshuffle between opens",
      VibenetSubAccounts.ordered([subOld, subNew, subWatched]).map(\.address)
        == VibenetSubAccounts.ordered([subWatched, subNew, subOld]).map(\.address))
check("an undated sub-account sorts after a dated one, never ahead of it",
      VibenetSubAccounts.ordered([VibenetSubAccount(address: "0xdd4", watched: false, authorizedAt: nil), subNew])
        .map(\.address) == ["0xbb2", "0xdd4"])

// MARK: - VibenetKeyGrouping — owners vs session keys (Base's own split)

print("")
print("VibenetKeyGrouping")
func groupActor(_ id: String, _ raw: UInt16, _ kind: VibenetAuthenticatorKind = .secp256k1) -> VibenetActor {
    VibenetActor(actorId: id, authenticator: "0x1", kind: kind, scope: VibenetScope(raw: raw), expiry: 0)
}
let ownerKey = groupActor("o", 0)
let sessionKey = groupActor("s", VibenetScope.policy | VibenetScope.nonce)
let scopedKey = groupActor("c", VibenetScope.sender)
check("scope 0 is an OWNER — the spec's own unrestricted admin",
      VibenetKeyGroup.of(ownerKey) == .owner)
check("the POLICY bit makes a SESSION key, whatever else is set",
      VibenetKeyGroup.of(sessionKey) == .session)
check("scoped-but-ungated is its own third case, never folded into either",
      VibenetKeyGroup.of(scopedKey) == .scoped)
check("groups draw owners first, then session, then limited",
      VibenetKeyGrouping.sections([scopedKey, sessionKey, ownerKey]).map(\.group)
        == [.owner, .session, .scoped])
check("an EMPTY group is omitted, never a heading with nothing under it",
      VibenetKeyGrouping.sections([ownerKey]).map(\.group) == [.owner])
check("no key is lost or duplicated by grouping",
      VibenetKeyGrouping.sections([scopedKey, sessionKey, ownerKey])
        .flatMap(\.actors).map(\.actorId).sorted() == ["c", "o", "s"])
check("WITHIN a group the judgement-free alphabetical order survives",
      VibenetKeyGrouping.sections([groupActor("z", 0, .webAuthn), groupActor("a", 0, .delegate)])
        .flatMap(\.actors).map(\.actorId) == ["a", "z"])

// MARK: - VibenetKeyAggregation.compose — the room-wide key summary

print("")
print("VibenetKeyAggregation.compose")
let refNowAgg = Date(timeIntervalSince1970: 1_000_000_000)
check("an empty room has nothing to aggregate — the empty state this codebase omits rather than shows",
      VibenetKeyAggregation.compose([], now: refNowAgg) == nil)
check("an account with no actors contributes nothing — still nil",
      VibenetKeyAggregation.compose([account(actors: [])], now: refNowAgg) == nil)

let ak1 = VibenetActor(actorId: "1", authenticator: "0x1", kind: .secp256k1, scope: VibenetScope(raw: 0), expiry: 0)
let ak2 = VibenetActor(actorId: "2", authenticator: "0x2", kind: .p256, scope: VibenetScope(raw: 0), expiry: 0)
let ak3 = VibenetActor(actorId: "3", authenticator: "0x3", kind: .secp256k1, scope: VibenetScope(raw: 0), expiry: 0)
let roomA = account(address: "0xa", actors: [ak1, ak2])
let roomB = account(address: "0xb", actors: [ak3])
let agg = VibenetKeyAggregation.compose([roomA, roomB], now: refNowAgg)
check("total counts every actor across every account",
      agg?.total == 3)
check("accountCount only counts accounts that contribute at least one key",
      agg?.accountCount == 2)
check("byKind counts within each kind",
      agg?.byKind.first(where: { $0.kind == .secp256k1 })?.count == 2)
check("an account holding NO keys is excluded from accountCount",
      VibenetKeyAggregation.compose([roomA, account(address: "0xc", actors: [])], now: refNowAgg)?.accountCount == 1)
check("plainLine spans several accounts",
      agg?.plainLine == "3 keys authorized across 2 accounts")
check("a single-account aggregate has no 'across' clause",
      VibenetKeyAggregation.compose([roomA], now: refNowAgg)?.plainLine == "2 keys authorized")

let webAuthnOnlyAccount = account(address: "0xw1", actors: [
    VibenetActor(actorId: "w", authenticator: "0x5", kind: .webAuthn, scope: VibenetScope(raw: 0), expiry: 0)])
let secpOnlyAccount = account(address: "0xw2", actors: [
    VibenetActor(actorId: "s", authenticator: "0x6", kind: .secp256k1, scope: VibenetScope(raw: 0), expiry: 0)])
check("byKind orders by the contract's own sortRank, never by which ACCOUNT was iterated first",
      VibenetKeyAggregation.compose([webAuthnOnlyAccount, secpOnlyAccount], now: refNowAgg)?.byKind.map(\.kind)
        == [.secp256k1, .webAuthn])

func expiringActor(_ expiry: UInt64, id: String = "e") -> VibenetActor {
    VibenetActor(actorId: id, authenticator: "0x9", kind: .secp256k1, scope: VibenetScope(raw: 0), expiry: expiry)
}
check("expiry == 0 (never) never counts toward the soonest reading",
      VibenetKeyAggregation.compose([account(address: "0xa", actors: [expiringActor(0)])], now: refNowAgg)?.soonestExpiry == nil)
// `expiry == 0` must be excluded by its OWN explicit check, not merely by
// falling out of the ">now" comparison — the two coincide for any ordinary
// clock (0 is always before a real "now"), so this needs a `now` that
// ISN'T ordinary to actually separate the two: before the epoch, where
// TimeInterval(0) > now.timeIntervalSince1970 alone would wrongly read
// "never expires" as the soonest-ticking key in the room.
let beforeEpoch = Date(timeIntervalSince1970: -100)
check("expiry == 0 stays excluded even against a 'now' before the epoch, where 0 would otherwise read as future",
      VibenetKeyAggregation.compose([account(address: "0xa", actors: [expiringActor(0)])], now: beforeEpoch)?.soonestExpiry == nil)

let pastExpiry = UInt64(refNowAgg.timeIntervalSince1970) - 60
check("an already-expired key never counts as the soonest — it's a standing fact, not a countdown",
      VibenetKeyAggregation.compose([account(address: "0xa", actors: [expiringActor(pastExpiry)])], now: refNowAgg)?.soonestExpiry == nil)

let soonExpiry = UInt64(refNowAgg.timeIntervalSince1970) + 3600
let laterExpiry = UInt64(refNowAgg.timeIntervalSince1970) + 7200
let soonestAgg = VibenetKeyAggregation.compose([
    account(address: "0xa", actors: [expiringActor(laterExpiry, id: "late")]),
    account(address: "0xb", actors: [expiringActor(soonExpiry, id: "soon")]),
], now: refNowAgg)
check("the soonest FUTURE expiry wins across accounts, regardless of input order",
      soonestAgg?.soonestExpiry?.actor.actorId == "soon")
check("the soonest expiry's line names the account it belongs to",
      soonestAgg?.soonestExpiry?.line(now: refNowAgg).hasPrefix("0xb's key") == true)

let tieAgg = VibenetKeyAggregation.compose([
    account(address: "0xb", actors: [expiringActor(soonExpiry, id: "tie-b")]),
    account(address: "0xa", actors: [expiringActor(soonExpiry, id: "tie-a")]),
], now: refNowAgg)
check("a tied soonest expiry breaks deterministically by address, not input order",
      tieAgg?.soonestExpiry?.address == "0xa")

// MARK: - VibenetBalanceFormat.line — never currency-formatted (§83)

print("")
print("VibenetBalanceFormat.line")
check("a whole number prints bare, no trailing zeros or decimal point",
      VibenetBalanceFormat.line(100.0) == "100")
check("zero prints as a bare zero",
      VibenetBalanceFormat.line(0.0) == "0")
check("a clean fraction keeps exactly its own digits",
      VibenetBalanceFormat.line(2.5) == "2.5")
check("rounds to at most 4 decimal places",
      VibenetBalanceFormat.line(1.23456789) == "1.2346")
check("a non-finite amount never prints garbage — falls back to a bare zero",
      VibenetBalanceFormat.line(.infinity) == "0")
check("a NaN amount falls back the same way",
      VibenetBalanceFormat.line(.nan) == "0")
check("no currency symbol or thousands grouping ever appears — devnet tokens have no real price",
      !VibenetBalanceFormat.line(1234.5).contains("$") && !VibenetBalanceFormat.line(1234.5).contains(","))

// MARK: - VibenetBalanceAggregation.compose — the feed room's own stat block

print("")
print("VibenetBalanceAggregation.compose")
check("no accounts at all — nothing to aggregate",
      VibenetBalanceAggregation.compose([]) == nil)

let balAgg = VibenetBalanceAggregation.compose([
    VibenetAccountItem(address: "0xa", reached: true, established: true, actors: [],
                        locked: false, hasInitiatedUnlock: false, unlocksAt: nil, unlockDelay: nil,
                        nativeBalance: 1.0,
                        tokenBalances: [VibenetTokenBalance(symbol: "USDV", amount: 10)]),
    VibenetAccountItem(address: "0xb", reached: true, established: true, actors: [],
                        locked: true, hasInitiatedUnlock: false, unlocksAt: nil, unlockDelay: nil,
                        nativeBalance: 2.5,
                        tokenBalances: [VibenetTokenBalance(symbol: "USDV", amount: 5),
                                        VibenetTokenBalance(symbol: "NFV", amount: 3)]),
    VibenetAccountItem(address: "0xc", reached: true, established: true, actors: [],
                        locked: false, hasInitiatedUnlock: false, unlocksAt: nil, unlockDelay: nil),
])
check("accountCount counts every item, including one with no balance reading at all",
      balAgg?.accountCount == 3)
check("lockedCount counts the alarmed accounts",
      balAgg?.lockedCount == 1)
check("nativeTotal SUMS every landed reading — never treats a missing one as zero",
      balAgg?.nativeTotal == 3.5)
check("tokenTotals sum WITHIN a symbol, never across symbols",
      balAgg?.tokenTotals.first(where: { $0.symbol == "USDV" })?.amount == 15)
check("a symbol only one account holds is still totalled correctly",
      balAgg?.tokenTotals.first(where: { $0.symbol == "NFV" })?.amount == 3)
check("tokenTotals are sorted by symbol — a TOTAL order, not input/iteration order",
      balAgg?.tokenTotals.map(\.symbol) == ["NFV", "USDV"])

check("nativeTotal is nil when NOT ONE account has a reading — never a guessed 0",
      VibenetBalanceAggregation.compose([
        VibenetAccountItem(address: "0xa", reached: true, established: true, actors: [],
                            locked: false, hasInitiatedUnlock: false, unlocksAt: nil, unlockDelay: nil)
      ])?.nativeTotal == nil)
check("tokenTotals is empty when no account holds any token balance",
      VibenetBalanceAggregation.compose([
        VibenetAccountItem(address: "0xa", reached: true, established: true, actors: [],
                            locked: false, hasInitiatedUnlock: false, unlocksAt: nil, unlockDelay: nil)
      ])?.tokenTotals.isEmpty == true)

check("plainLine: several accounts, none locked, never prints '0 locked'",
      VibenetBalanceAggregate(accountCount: 3, lockedCount: 0, readCount: 3, unreachedCount: 0,
                              nativeTotal: nil, tokenTotals: [])
        .plainLine == "3 accounts")
check("plainLine: a real locked count IS printed",
      VibenetBalanceAggregate(accountCount: 3, lockedCount: 1, readCount: 3, unreachedCount: 0,
                              nativeTotal: nil, tokenTotals: [])
        .plainLine == "3 accounts · 1 locked")
check("plainLine: singular account, singular locked",
      VibenetBalanceAggregate(accountCount: 1, lockedCount: 1, readCount: 1, unreachedCount: 0,
                              nativeTotal: nil, tokenTotals: [])
        .plainLine == "1 account · 1 locked")

print("")

// MARK: - VibenetEventFacts — the expiry join (prd §467)

print("")
print("VibenetEventFacts — what a key event may claim")
let keyExpiry: UInt64 = 4_102_444_800
let expiringKey = VibenetActor(
    actorId: "0x01", authenticator: "0xa", kind: .secp256k1,
    scope: VibenetScope(raw: VibenetScope.sender | VibenetScope.selfPayer),
    expiry: keyExpiry)
let neverKey = VibenetActor(
    actorId: "0x02", authenticator: "0xb", kind: .p256,
    scope: VibenetScope(raw: VibenetScope.sender), expiry: 0)
let due = Date(timeIntervalSince1970: TimeInterval(keyExpiry))

check("a UNIQUE expiry match names that key's permissions",
      VibenetEventFacts.matchedPermissions(actors: [expiringKey, neverKey], dueAt: due)
      == ["Send anywhere", "Pay own gas"])
// THE WHOLE POINT OF THE TYPE. Two keys minted in one block with one lifetime
// is a real shape (a session and its sponsor), and there is no id to tell them
// apart — so the card must say NOTHING rather than pick one. A wrong chip is a
// claim about what somebody can do with money, made where nobody can check it.
let twin = VibenetActor(
    actorId: "0x03", authenticator: "0xc", kind: .webAuthn,
    scope: VibenetScope(raw: VibenetScope.policy), expiry: keyExpiry)
check("an AMBIGUOUS match names nothing — never a guess between two keys",
      VibenetEventFacts.matchedPermissions(actors: [expiringKey, twin], dueAt: due).isEmpty)
check("no expiry on the event names nothing",
      VibenetEventFacts.matchedPermissions(actors: [expiringKey], dueAt: nil).isEmpty)
check("a never-expiring key is never matched by a zero",
      VibenetEventFacts.matchedPermissions(actors: [neverKey],
                                           dueAt: Date(timeIntervalSince1970: 0)).isEmpty)
check("an expiry that matches no key names nothing",
      VibenetEventFacts.matchedPermissions(actors: [expiringKey, neverKey],
                                           dueAt: Date(timeIntervalSince1970: 12345)).isEmpty)

let facts = VibenetEventFacts.compose(
    account: "0xabc", accountName: "Treasury",
    actors: [expiringKey, neverKey], dueAt: due, concernsKey: true)
check("compose counts the account's LIVE keys", facts.keysNow == 2)
check("compose carries the expiry through", facts.expires == due)
// A lock or an unlock is about the ACCOUNT. It must never borrow a key's
// permissions just because the expiry happens to line up.
let lockFacts = VibenetEventFacts.compose(
    account: "0xabc", accountName: "Treasury",
    actors: [expiringKey, neverKey], dueAt: due, concernsKey: false)
check("an event that is NOT about a key claims no permissions",
      lockFacts.permissions.isEmpty)
check("an account with no actors reports no key count",
      VibenetEventFacts.compose(account: "0xabc", accountName: "T",
                                actors: [], dueAt: nil, concernsKey: true).keysNow == nil)


// MARK: - prd §468: WHEN was this read?
//
// The room's snapshot is drawn synchronously by the feed head on every scroll
// and `VibenetRoomSource.compose` returns early WITHOUT saving when the config
// fetch fails — so a device offline for three days kept drawing the last good
// read behind a confident "As of vibenet's main branch, commit a9ae95e1b".
// Every check below fails against that shipped reading.

print("")
print("VibenetRoom.readAt — the staleness the provenance line never carried")
let readNow = Date(timeIntervalSince1970: 1_800_000_000)
func roomRead(_ ago: TimeInterval?) -> VibenetRoom {
    VibenetRoom.compose(items: [], branch: "main", commit: "abc123456", configReached: true,
                         readAt: ago.map { readNow.addingTimeInterval(-$0) })
}
check("a read minutes old says nothing — a timestamp on a current card is noise",
      VibenetRoom.freshnessLine(roomRead(60), now: readNow) == nil)
check("no readAt at all says nothing — a pre-§468 snapshot has no date to report",
      VibenetRoom.freshnessLine(roomRead(nil), now: readNow) == nil)
// The floor is 45 minutes and the wording is in whole HOURS, so the naive
// `Int(age / 3600)` prints "read 0h ago" for every read in that quarter hour —
// a caption saying a room is both stale and zero hours old.
check("46 minutes rounds UP to an hour, never down to zero",
      VibenetRoom.freshnessLine(roomRead(46 * 60), now: readNow) == "read 1h ago")
check("three hours reads as three",
      VibenetRoom.freshnessLine(roomRead(3 * 3_600), now: readNow) == "read 3h ago")
check("a day is named, not counted in hours",
      VibenetRoom.freshnessLine(roomRead(26 * 3_600), now: readNow) == "read yesterday")
check("under a week counts days",
      VibenetRoom.freshnessLine(roomRead(3 * 86_400), now: readNow) == "read 3 days ago")
check("past a week the caption becomes a DATE — 'read 43 days ago' is arithmetic nobody does",
      VibenetRoom.freshnessLine(roomRead(40 * 86_400), now: readNow)?.hasPrefix("read ") == true)
check("past a week it is no longer a day count",
      VibenetRoom.freshnessLine(roomRead(40 * 86_400), now: readNow)?.contains("days ago") == false)
// A device whose clock moved backwards between the read and the draw.
check("a read stamped in the FUTURE says nothing, never a negative age",
      VibenetRoom.freshnessLine(roomRead(-3_600), now: readNow) == nil)
check("the note carries the age AFTER the provenance — the commit says what, this says when",
      VibenetRoom.note(roomRead(5 * 3_600), drawn: 0, now: readNow)?.hasSuffix("read 5h ago") == true)
check("a fresh room's note is unchanged — no clause where there is nothing to say",
      VibenetRoom.note(roomRead(60), drawn: 0, now: readNow)?.contains("read") == false)
// A scoped room is the same read; losing the stamp there would make every
// scoped room look permanently fresh.
check("scoped() carries the stamp through",
      VibenetRoom.compose(items: [], branch: nil, commit: nil, configReached: true,
                           readAt: readNow).scoped(to: nil).readAt == readNow)

// MARK: - prd §468: a PARTIAL read stated as a whole one

print("")
print("Coverage — a sum missing part of itself may not claim to be everything")
func balanceItem(_ address: String, reached: Bool, native: Double?) -> VibenetAccountItem {
    VibenetAccountItem(address: address, reached: reached, established: true, actors: [],
                        locked: false, hasInitiatedUnlock: false, unlocksAt: nil, unlockDelay: nil,
                        nativeBalance: native)
}
let partial = VibenetBalanceAggregation.compose([
    balanceItem("0xa", reached: true, native: 1.0),
    balanceItem("0xb", reached: true, native: 2.0),
    balanceItem("0xc", reached: false, native: nil),
])
check("readCount counts the accounts that CONTRIBUTED, not the accounts watched",
      partial?.readCount == 2)
check("accountCount still counts every watched account",
      partial?.accountCount == 3)
check("unreachedCount is the accounts whose read never landed",
      partial?.unreachedCount == 1)
check("a PARTIAL total says how partial — never 'Across your accounts'",
      partial?.nativeHeading == "Across 2 of 3 accounts")
check("and it says so in words underneath too",
      partial?.unreachedLine == "1 account couldn't be read")
let whole = VibenetBalanceAggregation.compose([
    balanceItem("0xa", reached: true, native: 1.0),
    balanceItem("0xb", reached: true, native: 2.0),
])
check("a COMPLETE total keeps the plain heading",
      whole?.nativeHeading == "Across your accounts")
check("and says nothing about unreached accounts",
      whole?.unreachedLine == nil)
// An unread total has nothing to qualify — "Across 0 of 3" over no figure is
// arithmetic about an absence.
check("no figure at all keeps the plain heading rather than qualifying nothing",
      VibenetBalanceAggregation.compose([balanceItem("0xa", reached: true, native: nil)])?
        .nativeHeading == "Across your accounts")
// An account can be REACHED and still have no native reading — that one call
// failing alone. It reduces the coverage and is not an unreachable account.
let oneCallFailed = VibenetBalanceAggregation.compose([
    balanceItem("0xa", reached: true, native: 1.0),
    balanceItem("0xb", reached: true, native: nil),
])
check("a reached account with no balance reading lowers coverage",
      oneCallFailed?.nativeHeading == "Across 1 of 2 accounts")
check("...but is NOT reported as unreachable — two different facts, two sentences",
      oneCallFailed?.unreachedLine == nil)

func keyedItem(_ address: String, reached: Bool, actors: [VibenetActor]) -> VibenetAccountItem {
    VibenetAccountItem(address: address, reached: reached, established: true, actors: actors,
                        locked: false, hasInitiatedUnlock: false, unlocksAt: nil, unlockDelay: nil)
}
let soon = UInt64(readNow.timeIntervalSince1970) + 3_600
let later = UInt64(readNow.timeIntervalSince1970) + 30 * 86_400
let past = UInt64(readNow.timeIntervalSince1970) - 3_600
func keyActor(_ id: String, _ expiry: UInt64, _ raw: UInt16 = VibenetScope.sender) -> VibenetActor {
    VibenetActor(actorId: id, authenticator: "0x0", kind: .secp256k1,
                  scope: VibenetScope(raw: raw), expiry: expiry)
}
let keyAgg = VibenetKeyAggregation.compose([
    keyedItem("0xa", reached: true, actors: [keyActor("0x1", later), keyActor("0x2", soon)]),
    keyedItem("0xb", reached: true, actors: [keyActor("0x3", 0)]),
    keyedItem("0xc", reached: false, actors: []),
], now: readNow)
check("an unreached account's empty roster is not silently 'authorized nothing'",
      keyAgg?.unreachedCount == 1)
check("and the card says so, so the key count reads as the floor it is",
      keyAgg?.unreachedLine == "1 account couldn't be read")
// The runway's dates. Same rule as the sentence beside it or the two disagree.
check("futureExpiries excludes Keystore's own 'never' (expiry 0)",
      keyAgg?.futureExpiries.count == 2)
check("futureExpiries is ASCENDING — soonest first",
      keyAgg?.futureExpiries.first == Date(timeIntervalSince1970: TimeInterval(soon)))
check("an already-lapsed key is not 'ahead' and never reaches the rail",
      VibenetKeyAggregation.compose([keyedItem("0xa", reached: true, actors: [keyActor("0x1", past)])],
                                     now: readNow)?.futureExpiries.isEmpty == true)

// MARK: - prd §468: what changed since you last looked

print("")
print("VibenetKeySeenDiff — the three refusals")
let rosterA = keyedItem("0xAbC", reached: true, actors: [keyActor("0x1", 0), keyActor("0x2", 0)])
check("keyID is account-qualified — an actorId is unique within an account, not across them",
      VibenetKeySeenDiff.keyID(address: "0xAbC", actorId: "0X1") == "0xabc|0x1")
// 1. FIRST SIGHT SEEDS SILENTLY. Without this a newly-watched account reports
//    every key it has ever had as new — the Hyperliquid bug, fifth bridge.
check("an account with no ledger entry reports NOTHING — first sight is silent",
      VibenetKeySeenDiff.since(seen: [:], items: [rosterA]).isEmpty)
let seenBoth = VibenetKeySeenDiff.advanced(seen: [:], items: [rosterA])
check("advanced() files both keys under the lowercased address",
      seenBoth["0xabc"]?.count == 2)
check("a roster that has not moved reports nothing",
      VibenetKeySeenDiff.since(seen: seenBoth, items: [rosterA]).isEmpty)
let grown = keyedItem("0xAbC", reached: true,
                       actors: [keyActor("0x1", 0), keyActor("0x2", 0), keyActor("0x3", 0)])
check("a key not in the ledger is NEW",
      VibenetKeySeenDiff.since(seen: seenBoth, items: [grown]).added.count == 1)
let shrunk = keyedItem("0xAbC", reached: true, actors: [keyActor("0x1", 0)])
check("a key that has left the roster is a REVOCATION",
      VibenetKeySeenDiff.since(seen: seenBoth, items: [shrunk]).revokedCount == 1)
// 2. NEVER PRUNE ON AN EMPTY READ. An unreached account's roster is empty
//    because the read failed, and reading that as revocation announces a
//    security event that did not happen every time the devnet has a bad
//    minute. `ScreenshotIngest.pruneDeleted`'s rule in a room that draws.
let unreachedRoster = keyedItem("0xAbC", reached: false, actors: [])
check("AN UNREACHED ACCOUNT REPORTS NO REVOCATION — its empty roster is a failed read",
      VibenetKeySeenDiff.since(seen: seenBoth, items: [unreachedRoster]).revokedCount == 0)
check("...and contributes nothing at all",
      VibenetKeySeenDiff.since(seen: seenBoth, items: [unreachedRoster]).isEmpty)
check("advanced() KEEPS an unreached account's old set — overwriting it would make every one of its keys read as new next time",
      VibenetKeySeenDiff.advanced(seen: seenBoth, items: [unreachedRoster])["0xabc"]?.count == 2)
// 3. An account you stopped watching contributes no revocations — its keys
//    did not go anywhere.
check("an unwatched account drops out of the ledger entirely",
      VibenetKeySeenDiff.advanced(seen: seenBoth, items: [])["0xabc"] == nil)
check("added and revoked are counted APART — one window can do both",
      VibenetKeySeenDiff.since(
        seen: seenBoth,
        items: [keyedItem("0xAbC", reached: true, actors: [keyActor("0x1", 0), keyActor("0x9", 0)])])
        == VibenetKeyChanges(added: ["0xabc|0x9"], revokedCount: 1))

print("")
print("VibenetKeyChanges — the words")
check("nothing moved, nothing said",
      VibenetKeyChanges(added: [], revokedCount: 0).line == nil)
check("one new key",
      VibenetKeyChanges(added: ["a"], revokedCount: 0).line == "1 key new since you last looked")
check("several",
      VibenetKeyChanges(added: ["a", "b"], revokedCount: 0).line == "2 keys new since you last looked")
// A revocation ALONE has to stand as a sentence — "1 revoked" under nothing
// else is a fragment.
check("a revocation alone is a whole sentence",
      VibenetKeyChanges(added: [], revokedCount: 1).line == "1 key revoked since you last looked")
check("beside an addition it is the short clause",
      VibenetKeyChanges(added: ["a"], revokedCount: 2).line
        == "1 key new since you last looked · 2 revoked")

// MARK: - prd §468: the key tray

print("")
print("VibenetKeyTray — which keys are in which category")
let adminKey = keyActor("0xadmin", 0, 0)
let sender = keyActor("0xsend", 0, VibenetScope.sender)
let both = keyActor("0xboth", 0, VibenetScope.sender | VibenetScope.selfPayer)
let reservedOnly = keyActor("0xres", 0, 0x0400)
let trayItems = [keyedItem("0xa", reached: true, actors: [adminKey, sender]),
                 keyedItem("0xb", reached: true, actors: [both, reservedOnly])]
let tray = VibenetKeyTray.sections(trayItems)
check("Admin leads — scope 0 is unrestricted and is never one of the five bits",
      tray.first?.label == "Admin")
check("and holds exactly the admin key",
      tray.first?.count == 1)
// THE INVARIANT: the tray and the card must never disagree about a number.
// Two derivations of one grouping drift, and then a card says 4 and the list
// it opens shows 3.
let counts = VibenetPolicyAggregation.compose(trayItems)
check("every section mirrors the card's own count, label for label",
      tray.map { [$0.label, "\($0.count)"] } == counts.map { [$0.label, "\($0.count)"] })
check("an ADMIN is excluded from every bit section — it is not five permissions, it is one word",
      tray.first(where: { $0.label == "Send anywhere" })?.keys.contains(where: { $0.actor.actorId == "0xadmin" }) == false)
check("a key holding two bits appears under BOTH — which is the question this screen answers",
      tray.first(where: { $0.label == "Pay own gas" })?.keys.first?.actor.actorId == "0xboth")
// A key with only reserved bits is in no section at all. COUNTED AND SAID —
// never given an invented category, and never silently missing.
check("a key holding only reserved bits is counted, never filed under an invented name",
      VibenetKeyTray.unnamedKeyCount(trayItems) == 1)
check("the footnote says how many keys there really are",
      VibenetKeyTray.footnote(trayItems)?.hasPrefix("4 keys") == true)
check("...and warns that one key can appear more than once",
      VibenetKeyTray.footnote(trayItems)?.contains("appears under each") == true)
check("...and names the unnameable one rather than losing it",
      VibenetKeyTray.footnote(trayItems)?.contains("can't name") == true)
check("no keys at all, no sections",
      VibenetKeyTray.sections([]).isEmpty)
check("alsoLine names the OTHER permissions, never the section's own",
      VibenetKeyTray.alsoLine(VibenetTrayKey(address: "0xb", actor: both), besides: "Send anywhere")
        == "Also: Pay own gas")
check("a key with nothing else to say says nothing",
      VibenetKeyTray.alsoLine(VibenetTrayKey(address: "0xa", actor: sender), besides: "Send anywhere") == nil)

// MARK: - prd §470: a key's own identity, and the developer's paste

print("")
print("VibenetKeyIdentity — which key is this")
// A secp256k1 actorId IS an address right-aligned into a 32-byte word, so it
// has a real signer to name. A passkey's is a HASH of a public key, and the
// high-bytes-are-zero test is the only thing standing between that and a
// plausible address belonging to nobody being offered as "the signer".
let signerAddr = "0x1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b"
let k1 = VibenetActor(
    actorId: VibenetActorId.actorId(forAddress: signerAddr)!,
    authenticator: "0x0000000000000000000000000000000000000001",
    kind: .secp256k1, scope: VibenetScope(raw: VibenetScope.sender), expiry: 0)
let passkey = VibenetActor(
    actorId: "0xfeedfacedeadbeef0123456789abcdeffedcba98765432100112233445566778",
    authenticator: "0x00000000000000000000000000000000000000aa",
    kind: .webAuthn, scope: VibenetScope(raw: VibenetScope.policy), expiry: 0)
check("an address-shaped actorId names its signer",
      VibenetKeyIdentity.signerAddress(k1) == signerAddr)
check("A HASHED actorId names NOBODY — never a plausible address that is not one",
      VibenetKeyIdentity.signerAddress(passkey) == nil)
// The row draws this and nothing else, so it must be the SAME truncation
// grammar addresses use — a room that elides two kinds of hex two ways makes
// a reader parse before they can compare, and comparing is the whole job.
check("the short form is the tail, matching shortAddress exactly",
      VibenetKeyIdentity.short(passkey.actorId) == VibenetRoom.shortAddress(passkey.actorId))
check("and it really is the last four",
      VibenetKeyIdentity.short(passkey.actorId) == "…6778")
// THE FAILURE THIS EXISTS FOR: two keys of one kind on one account are
// otherwise byte-identical rows — same title, same clause, same chips.
let twinA = VibenetActor(actorId: "0x" + String(repeating: "a", count: 60) + "1111",
                          authenticator: "0x00", kind: .webAuthn,
                          scope: VibenetScope(raw: VibenetScope.sender), expiry: 0)
let twinB = VibenetActor(actorId: "0x" + String(repeating: "a", count: 60) + "2222",
                          authenticator: "0x00", kind: .webAuthn,
                          scope: VibenetScope(raw: VibenetScope.sender), expiry: 0)
check("two same-kind keys on one account are TELLABLE APART by their short ids",
      VibenetKeyIdentity.short(twinA.actorId) != VibenetKeyIdentity.short(twinB.actorId))

print("")
print("VibenetAccountDebug — the raw read, for the clipboard only")
// Padded to the full 16-bit word: these are compared by eye against
// `Scopes.sol`'s constants and against each other, and a ragged column is one
// the reader has to right-align in their head.
check("scope is the zero-padded hex word, never 0x13",
      VibenetAccountDebug.scopeWord(VibenetScope(raw: 0x0013)) == "0x0013")
check("admin's scope word is zero, and says so as a word",
      VibenetAccountDebug.scopeWord(VibenetScope(raw: 0)) == "0x0000")
check("a reserved bit survives into the word — the paste is RAW",
      VibenetAccountDebug.scopeWord(VibenetScope(raw: 0x0400)) == "0x0400")

let dbgExpiry: UInt64 = 4_102_444_800
let dbgKey = VibenetActor(
    actorId: VibenetActorId.actorId(forAddress: signerAddr)!,
    authenticator: "0x0000000000000000000000000000000000000001",
    kind: .secp256k1,
    scope: VibenetScope(raw: VibenetScope.sender | VibenetScope.selfPayer),
    expiry: dbgExpiry)
let keyLine = VibenetAccountDebug.keyLine(dbgKey)
// BOTH SPELLINGS OF EACH FACT. The hex/unix is for working against the
// contract; the words are for checking the paste describes the card you were
// just looking at. Either alone makes the reader do a conversion.
check("the key line carries the FULL actorId, never the short form",
      keyLine.contains(dbgKey.actorId))
check("...the raw scope word",
      keyLine.contains("scope 0x0009"))
check("...AND the plain wording beside it",
      keyLine.contains("Send anywhere, Pay own gas"))
check("...the unix expiry, for the contract",
      keyLine.contains("(\(dbgExpiry))"))
check("...and an ISO stamp beside it, for a human",
      keyLine.contains("2100-01-01T00:00:00Z"))
check("a signer is named when there is one",
      keyLine.contains("signer \(signerAddr)"))
check("the authenticator is always named — it is the validating CONTRACT",
      keyLine.contains("authenticator 0x0000000000000000000000000000000000000001"))
// A bare `0` in a paste reads as an epoch DATE, not as Keystore's "never".
let neverLine = VibenetAccountDebug.keyLine(VibenetActor(
    actorId: passkey.actorId, authenticator: "0x00", kind: .webAuthn,
    scope: VibenetScope(raw: 0), expiry: 0))
check("expiry 0 is spelled 'never', never rendered as an epoch date",
      neverLine.contains("expires never (0)"))
check("...and a hashed actorId names no signer in the paste either",
      !neverLine.contains("signer "))

let dbgItem = VibenetAccountItem(
    address: signerAddr, reached: true, established: true, actors: [dbgKey, passkey],
    locked: false, hasInitiatedUnlock: false, unlocksAt: nil, unlockDelay: nil,
    changeSequences: VibenetChangeSequences(multichain: 12, localEpoch: 2, localSequence: 5),
    nativeBalance: 2.5)
let dump = VibenetAccountDebug.text(for: dbgItem, name: "Treasury", now: readNow)
check("the dump leads with the account it is about",
      dump.hasPrefix("vibenet account \(signerAddr)"))
check("a name is carried when the account has one",
      dump.contains("name: Treasury"))
check("every key gets a line",
      dump.contains(dbgKey.actorId) && dump.contains(passkey.actorId))
check("the key count is stated so a truncated paste is detectable",
      dump.contains("keys: 2"))
check("changeSequences carries all three of the contract's own fields",
      dump.contains("changeSequences: multichain 12, localEpoch 2, localSequence 5"))
// EVERY UNKNOWN SAID AS UNKNOWN. A paste reads as a complete record, so an
// omitted line reads as "this account has none of that" when the truth is
// "the read failed" — the same distinction `nativeBalance`'s own nil carries.
let unreadItem = VibenetAccountItem(
    address: signerAddr, reached: false, established: false, actors: [],
    locked: false, hasInitiatedUnlock: false, unlocksAt: nil, unlockDelay: nil)
let unreadDump = VibenetAccountDebug.text(for: unreadItem, name: nil, now: readNow)
check("an unreached account SAYS the read failed, high up",
      unreadDump.contains("reached: no"))
check("...and warns that everything under it is a floor, not a census",
      unreadDump.contains("not a census"))
check("an unread balance is 'unread', never a zero",
      unreadDump.contains("native: unread"))
check("unread change sequences say so rather than vanishing",
      unreadDump.contains("changeSequences: unread"))
check("a nameless account carries no empty name line",
      !unreadDump.contains("name:"))
// The paste must not rank keys — that would be the app making a judgement in
// the one artifact whose whole point is being raw (§463's own user ruling).
let ordered = VibenetAccountDebug.text(
    for: VibenetAccountItem(address: signerAddr, reached: true, established: true,
                             actors: [passkey, dbgKey], locked: false,
                             hasInitiatedUnlock: false, unlocksAt: nil, unlockDelay: nil),
    name: nil, now: readNow)
// ALPHABETICAL BY THE KEY'S OWN DISPLAYED TITLE — "Passkey" before "Wallet
// key" — which is `VibenetAccountItem.alphabetical`'s rule, not this
// harness's guess at one. The fixture is deliberately handed the keys in the
// OPPOSITE order so the sort is what decides, and both titles are asserted
// first so a future rename cannot leave this passing while testing nothing.
check("the fixture's own premise: Passkey really does sort before Wallet key",
      VibenetAuthenticatorKind.webAuthn.plainTitle < VibenetAuthenticatorKind.secp256k1.plainTitle)
check("keys are in the same judgement-free order the screen uses, whatever order they arrived in",
      ordered.range(of: passkey.actorId)!.lowerBound < ordered.range(of: dbgKey.actorId)!.lowerBound)

// MARK: - prd §468: the facets

print("")
print("VibenetEventKind.facetTags")
check("an authorization is a KEY event",
      VibenetEventKind.actorAuthorized.facetTags == ["Key"])
// BOTH, and the order matters for nothing but reading: a revoke is a key event
// (so "keys on vibenet" must reach it) and the revocation is the narrower
// question asked on top.
check("a revoke is a key event AND a revocation",
      VibenetEventKind.actorRevoked.facetTags == ["Key", "Revoked"])
check("a lock is about the ACCOUNT — it carries no key facet at all",
      VibenetEventKind.locked.facetTags == ["Locked"])
check("an unlock is its own state",
      VibenetEventKind.unlockInitiated.facetTags == ["Unlocking"])

if failures == 0 {
    print("✓ vibenet self-test: all assertions passed")
} else {
    print("✗ vibenet self-test: \(failures) assertion(s) failed")
    exit(1)
}
SWIFT

echo "Assertions"
if ! swiftc -O -o "$TMP/run" "$ROOM" "$FACTS" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ VibenetRoom.swift did not compile with the harness"
  tail -25 "$TMP/build.log"
  exit 1
fi
"$TMP/run"

# --- mutations — a check that cannot fail proves nothing ---------------------

echo ""
echo "Mutations (each must be caught)"

mutate() { # mutate <name> <from> <to>
  local name="$1" from="$2" to="$3"
  local target="$TMP/m-room.swift"
  cp "$ROOM" "$target"
  if ! MUT_FROM="$from" MUT_TO="$to" python3 - "$target" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  # `$FACTS` IS NOT OPTIONAL HERE, and leaving it out made every mutation
  # below pass for the wrong reason (found 2026-08-25, prd §468). The
  # assertion build compiles ROOM + FACTS + main; this one compiled ROOM +
  # main, so from the day `VibenetEventFacts` assertions entered `main.swift`
  # every single mutated build failed with "cannot find 'VibenetEventFacts' in
  # scope" and was reported as "(rejected at compile)" — the harness's own
  # word for a mutation the TYPE SYSTEM caught. Thirty-four checks, all green,
  # none of them testing anything. A check that cannot fail proves nothing;
  # this one could not even run.
  if ! swiftc -O -o "$TMP/mut" "$target" "$FACTS" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# A revoked actorId reading as live is the sharpest possible failure here —
# it would tell someone a key can still act for an account when it can't.
# An off-by-one here either re-reads one block twice (harmless but wasteful)
# or SKIPS one block silently — and a skipped block can hide the one event
# that would have kept a live actor in the roster. Both are real failures
# of the "no gaps, no overlaps" contract chunking exists for.
mutate "VibenetLogChunking.ranges must not skip the boundary block between chunks" \
  'let from = max(0, to - maxRange + 1)' \
  'let from = max(0, to - maxRange)'

# Without the chunk-count breaker, an oversized `tip` (a devnet that
# outgrows every bound this file assumes) spins forever against a shared
# public RPC — exactly the unbounded crawl this whole design exists to
# refuse.
mutate "VibenetLogChunking.ranges must stop at maxChunks, never loop unbounded" \
  'while to >= 0, chunk < maxChunks {' \
  'while to >= 0 {'

# A key row's whole content is its granted-permission chips — losing the
# NAMED ones while keeping only the unknown-count tail would show a key
# that can send transactions and pay its own gas as a row with a single
# "+1 unknown" chip, hiding the powers that actually matter.
mutate "grantedPlainLabels must include the NAMED permissions, not just the unknown tail" \
  'var parts = plainNames' \
  'var parts: [String] = []'

# Two keys authorized in one transaction share a block. Counting MOMENTS
# instead of BLOCKS makes that read as a sequence, and the sheet draws two
# dots side by side claiming an order that never happened.
mutate "isSequence must count distinct BLOCKS, not moments" \
  'Set(moments.map(\.block)).count > 1' \
  'moments.count > 1'

# A zero/zero standing means nothing has changed. Rendering it as a
# sentence instead of silence puts a line on the sheet that says nothing
# and reads as though it does.
mutate "plainLine must stay SILENT when nothing has changed" \
  'case (0, 0):' \
  'case (99, 99):'

mutate "a revoked actorId must NOT survive its own revoke" \
  'return Set(latest.filter(\.value).map(\.key))' \
  'return Set(latest.map(\.key))'

# Without the sort, the union trusts whatever order the RPC happened to
# return logs in, which is not a promise `eth_getLogs` makes.
mutate "survivorship must be decided by CHRONOLOGY, not array order" \
  'let chronological = events.sorted { ($0.block, $0.logIndex) < ($1.block, $1.logIndex) }' \
  'let chronological = events'

# A reserved scope bit silently counted as a KNOWN one is exactly the
# invented permission this file's whole design refuses to state.
mutate "a reserved scope bit must never be folded into the known set" \
  'static let known: UInt16 = sender | policy | nonce | selfPayer | sponsorPayer' \
  'static let known: UInt16 = sender | policy | nonce | selfPayer | sponsorPayer | 0x0020'

# The one alarm this room can raise must actually lead the card.
# The matrix's columns are ranked by REACH so the most-privileged key is
# read first. Inverted, the card leads with the key that can do the LEAST —
# which renders perfectly and buries the one worth looking at.
mutate "a key without the POLICY bit must never claim to be limited" \
  'guard scope.raw & VibenetScope.policy != 0, let manager = policyManager else { return nil }' \
  'guard let manager = policyManager else { return nil }'

mutate "an unreached account must never be told why it is undeployed" \
  'guard item.reached, !item.established else { return nil }' \
  'guard !item.established else { return nil }'

mutate "scope 0 must name itself, never expand into the named bits" \
  'guard !isAdmin else { return [String(localized: "Admin")] }
        return VibenetScope.named.filter { raw & $0.bit != 0 }.map(\.plain)' \
  'return VibenetScope.named.filter { raw & $0.bit != 0 }.map(\.plain)'

mutate "the headline must say Locked/Unlocking itself — the row's own badge doesn't draw beside it" \
  'return item.hasInitiatedUnlock ? String(localized: "Unlocking") : String(localized: "Locked")' \
  'return String(localized: "")'

# The `hidden` count is what makes the note say "N more watched" — losing it
# collapses back to a bare provenance line with no signal that the card
# capped its own row count.
mutate "the note must count what the card didn't draw" \
  'let hidden = room.items.count - drawn' \
  'let hidden = 0'

# A stale pick falling back to the whole room is indistinguishable from no
# pick at all, while the rail sits lit on a face it is not describing.
mutate "scoped() must not fall back to the whole room on an unwatched address" \
  'items: items.filter { $0.address.caseInsensitiveCompare(address) == .orderedSame },' \
  'items: items,'

mutate "a locked account must rank first" \
  'if a.alarmed != b.alarmed { return a.alarmed }' \
  'if false { return a.alarmed }'

# The edge case named in the feature brief: dropping this guard collapses
# "established with nothing authorized" into "not established at all".
mutate "established-with-no-actors must not read as not-established" \
  'guard item.established else { return String(localized: "Not established yet") }' \
  ' '

# The clamp is the whole reason unlockProgress is safe to draw as a bar —
# without it a delay measured slightly wrong by the chain draws past either
# end of the track.
mutate "unlockProgress must clamp — never draw past either end of the bar" \
  'return min(1, max(0, elapsed / total))' \
  'return elapsed / total'

# A detail clause on `.custom` would be an invented fact about an
# authenticator this build could never actually identify.
mutate "an unidentified authenticator must never get an invented detail clause" \
  'case .custom:    nil' \
  'case .custom:    String(localized: "unknown")'

# The row's own alarm clock must lead with the SOONEST ticking key, not the
# LATEST — a swap here buries the key someone actually needs to act on
# behind one that has months left.
mutate "urgentLine must pick the SOONEST future expiry, never the latest" \
  '.min()' \
  '.max()'

# Without the logIndex tiebreak, two events in the SAME block sort however
# the array happened to arrive — the strip reshuffling between opens over
# an unchanged history is exactly the fault ordering exists to prevent.
mutate "VibenetKeyHistory.ordered must break ties by logIndex, not array order" \
  'if $0.logIndex != $1.logIndex { return $0.logIndex < $1.logIndex }' \
  'if false { return $0.logIndex < $1.logIndex }'

# Counting a revocation as an addition would tell someone their roster grew
# when a key was actually taken away — the sharpest possible wrong reading
# of a security-relevant summary line.
mutate "summaryLine must count adds and revokes separately, never conflate them" \
  'let added = moments.filter(\.authorized).count' \
  'let added = moments.count'

# Swapping the chip order puts the local-epoch count where the cross-chain
# count belongs — the two numbers mean structurally different things
# (§the EIP's own split) and reading the wrong one as the other is a real
# misreading, not a cosmetic reorder.
mutate "VibenetChangeSequences.chips must lead with multichain, not local" \
  '[(String(multichain), String(localized: "cross-chain changes")),' \
  '[(String(localSequence), String(localized: "cross-chain changes")),'

# A case-sensitive compare would tell someone their account has NO
# delegate relationship the moment a live RPC happens to hand back the
# other address's hex in a different casing than this build stored it —
# the exact "an RPC's hex casing is not a promise" failure this file's own
# doc calls out.
mutate "VibenetAccountMapping.links must compare delegate addresses case-INSENSITIVELY" \
  '$0.address.caseInsensitiveCompare(delegate) == .orderedSame' \
  '$0.address == delegate'

# THE BUG THIS SUITE PROVED ABSENT FOR A DAY. A delegate's authenticator is
# the DelegateAuthenticator CONTRACT — identical for all 5 live delegates on
# vibenet — so reading the target from there matches no watched account
# ever, and "Linked accounts" is silently dead on every real read while the
# demo fixture keeps it looking healthy.
mutate "VibenetAccountMapping.links must take the delegate from the actorId, never the authenticator" \
  'guard let delegate = actor.delegateAddress,' \
  'guard let delegate = Optional(actor.authenticator),'

# Dropping the `.delegate` filter invents relationships out of ordinary
# keys, and it is WORSE now than when links read authenticators: a
# secp256k1 key's actorId IS its signer address, so most plain keys decode
# to a real address and every one of them naming a watched account would
# draw as a delegation nobody granted.
#
# AIMED AT `delegateAddress`, NOT at the loop's `where` clause, and the
# difference is the whole point: the `where` is an early-out that saves a
# string decode per actor, but it is REDUNDANT — `delegateAddress` returns
# nil for every non-delegate kind, so removing the `where` alone changes no
# output and no fixture could ever catch it. This mutation removes the guard
# that actually decides, which `aliceHoldsAPlainKeyPointingAtBob` then
# catches. A guard must prove the condition is the WHOLE condition.
mutate "VibenetActor.delegateAddress must only ever answer for a .delegate actor" \
  'guard kind == .delegate else { return nil }' \
  'guard true else { return nil }'

# The mapping section must never reshuffle between opens — flipping the
# primary sort to descending is exactly the kind of drift a card comparison
# across two composes of an unchanged room would catch as "broken".
mutate "VibenetAccountMapping.links must sort by from ascending, not descending" \
  'let f = a.from.localizedCaseInsensitiveCompare(b.from)
            if f != .orderedSame { return f == .orderedAscending }' \
  'let f = a.from.localizedCaseInsensitiveCompare(b.from)
            if f != .orderedSame { return f == .orderedDescending }'

# `expiry == 0` is Keystore.sol's own convention for "never expires" —
# folding it into the soonest reading would report a key that can never
# lapse as the most urgent one in the entire room.
mutate "VibenetKeyAggregation.compose must never count expiry == 0 toward the soonest reading" \
  '$0.1.expiry > 0 && TimeInterval($0.1.expiry) > now.timeIntervalSince1970' \
  'TimeInterval($0.1.expiry) > now.timeIntervalSince1970'

# The whole point of a "soonest expiry" callout is to point at what needs
# attention FIRST — swapping the comparator points at whatever lapses
# LAST instead, burying the one key someone actually needs to act on.
mutate "VibenetKeyAggregation.compose must pick the SOONEST future expiry, never the latest" \
  'if a.1.expiry != b.1.expiry { return a.1.expiry < b.1.expiry }' \
  'if a.1.expiry != b.1.expiry { return a.1.expiry > b.1.expiry }'

# Without this filter, an account that authorized nothing would still be
# counted in "N keys across M accounts" — inflating M and understating how
# concentrated the room's keys actually are.
mutate "VibenetKeyAggregation.compose's accountCount must exclude accounts with no actors" \
  'let accountCount = items.filter { !$0.actors.isEmpty }.count' \
  'let accountCount = items.count'

# byKind must read the Keystore's own declared order (ascending sortRank).
# Reversing it silently swaps which kind leads the summary — a cosmetic
# change on a two-kind room, but a real misreading on one with several,
# where the least-capable kind would lead instead of the most standard one.
mutate "VibenetKeyAggregation.compose's byKind must sort sortRank ASCENDING, not descending" \
  'VibenetAuthenticatorKind.allCases
            .sorted { $0.sortRank < $1.sortRank }' \
  'VibenetAuthenticatorKind.allCases
            .sorted { $0.sortRank > $1.sortRank }'

# Owners must lead. Reversing this buries the keys that can spend the
# account under the ones that cannot — the wrong end of a list somebody
# opens to find out who has control.
mutate "VibenetKeyGrouping.sections must draw owners FIRST, never last" \
  'VibenetKeyGroup.allCases
            .sorted { $0.sortRank < $1.sortRank }' \
  'VibenetKeyGroup.allCases
            .sorted { $0.sortRank > $1.sortRank }'

# An admin (scope 0) has no POLICY bit set, so testing the bit FIRST files
# every owner key under "Limited keys" — the §463 inversion again, wearing
# a new hat: total authority displayed as the most restricted group there is.
mutate "VibenetKeyGroup.of must test isAdmin BEFORE the policy bit" \
  'if actor.scope.isAdmin { return .owner }' \
  'if false { return .owner }'

# An empty group drawn as a heading with nothing under it is the empty
# state this codebase omits rather than prints — and worse here, it would
# claim the account HAS a category of key it does not have.
mutate "VibenetKeyGrouping.sections must omit an EMPTY group, never draw its heading" \
  'guard let members = buckets[group], !members.isEmpty else { return nil }' \
  'let members = buckets[group] ?? []'

# A coarser round loses real precision — the whole reason 4 decimal places
# was chosen (enough to separate "some" from "dust" on a devnet) rather
# than the 2 places a currency figure would use, which this format is
# explicitly NOT.
mutate "VibenetBalanceFormat.line must round to 4 decimal places, not fewer" \
  'let rounded = (amount * 10_000).rounded() / 10_000' \
  'let rounded = (amount * 1).rounded() / 1'

# Without the finite guard, a non-finite amount reaches `String(format:)`
# directly and prints whatever Foundation happens to render for infinity/
# NaN — an unreadable balance on the one card this feature exists to make
# trustworthy, instead of the honest "0" this file promises on failure.
mutate "VibenetBalanceFormat.line must guard non-finite input before formatting" \
  'guard amount.isFinite else { return "0" }' \
  ' '

# A nil-guard dropped here turns "nobody's native balance ever landed"
# into a confidently-wrong "0 ETH" — the guessed-zero failure §83 exists
# to prevent, on the one card this feature is building trust around.
mutate "VibenetBalanceAggregation.compose must never guess 0 when no account has a native reading" \
  'let nativeTotal = natives.isEmpty ? nil : natives.reduce(0, +)' \
  'let nativeTotal: Double? = natives.reduce(0, +)'

# Summing every symbol into one bucket would add USDV to NFV — two
# different assets with no shared unit, exactly the "never combined"
# rule this room's own model already enforces per account.
mutate "VibenetBalanceAggregation.compose must sum tokenTotals WITHIN a symbol, never merge symbols" \
  'sums[balance.symbol, default: 0] += balance.amount' \
  'sums["all", default: 0] += balance.amount'

# Without a TOTAL order, the token chips would reorder between opens
# depending on which watched account the walk happened to reach first —
# the same standing rule every other roster/chip list in this file holds.
mutate "VibenetBalanceAggregation.compose's tokenTotals must sort by symbol ascending, not descending" \
  '.sorted { $0.symbol < $1.symbol }' \
  '.sorted { $0.symbol > $1.symbol }'

# A locked count of zero is a real, unalarming state — printing "· 0
# locked" on every quiet room is noise pretending to be a finding.
mutate "VibenetBalanceAggregate.plainLine must never print a zero locked count" \
  'if lockedCount > 0 {' \
  'if true {'

# --- prd §468 mutations -----------------------------------------------------

# A room read three days ago and one read a second ago must not draw the same
# confident face. Without the floor a CURRENT room grows a timestamp; without
# the rounding a 46-minute-old read says "0h ago", a caption claiming the room
# is both stale and no time old.
mutate "freshnessLine must stay silent while the read is current" \
  'guard age >= freshnessFloor else { return nil }' \
  'guard age >= 0 else { return nil }'

mutate "freshnessLine must ROUND to the hour, never truncate to zero" \
  'let hours = max(1, Int((age / 3_600).rounded()))' \
  'let hours = Int(age / 3_600)'

# A device whose clock moved backwards between the read and the draw.
mutate "a read stamped in the future must not report a negative age" \
  'guard age >= freshnessFloor else { return nil }' \
  'guard abs(age) >= freshnessFloor else { return nil }'

# THE §468 FIX IN ONE LINE: the crown heads a partial sum with a whole claim.
# §349 ruled this out for Gnosis Pay and Railgun; this was the same defect in a
# third room.
mutate "nativeHeading must not claim the whole roster over a partial sum" \
  'guard readCount < accountCount else { return String(localized: "Across your accounts") }' \
  'guard readCount < 0 else { return String(localized: "Across your accounts") }'

# readCount is what the total actually covers. Counting items instead makes
# every partial read look complete while the figure stays short.
mutate "readCount must count the readings that landed, not the accounts watched" \
  'readCount: natives.count, unreachedCount: items.filter { !$0.reached }.count,' \
  'readCount: items.count, unreachedCount: items.filter { !$0.reached }.count,'

# The key count is a FLOOR whenever an account went unread, and the only thing
# that says so is this clause. (First occurrence in the file is
# `VibenetKeyAggregate`'"'"'s; the balance twin has its own assertions above.)
mutate "the key card must say when an account could not be read" \
  'guard unreachedCount > 0 else { return nil }' \
  'guard unreachedCount > 99 else { return nil }'

# The rail and the sentence beside it must obey ONE rule: expiry 0 is
# Keystore-for-never and is not a date, and a lapsed key is not ahead.
# NOT A MUTATION HERE, on purpose — found running this harness against the
# real tree (2026-08-25): `$0 > 0` in `futureExpiries`'s filter is REDUNDANT
# with the `> now` clause beside it, because Keystore's "never" is epoch 0 and
# epoch 0 is never after any real `now` — so no fixture built from a real
# clock can ever tell the two clauses apart, and a mutation dropping `$0 > 0`
# passed every assertion for the right reason rather than the wrong one. The
# standing rule this codebase states repeatedly (`safetx-selftest.sh`,
# `x-selftest.sh`): a fixture only tests the rule it names if it fails that
# rule and passes every other one — this one could not, by construction, ever
# fail differently with the guard removed. `$0 > 0` stays in the shipped
# source as documentation of the Keystore convention (removing it changes
# nothing observable), and the assertion above
# ("futureExpiries excludes Keystore's own 'never' (expiry 0)") is the
# correctness proof; this is not.

mutate "futureExpiries must exclude an already-lapsed key" \
  'filter { $0 > 0 && TimeInterval($0) > now.timeIntervalSince1970 }' \
  'filter { $0 > 0 }'

# THE SHARPEST ONE HERE. An unreached account has an empty roster because the
# read failed — reading that as revocation announces a security event that did
# not happen, every time the devnet has a bad minute. It is
# `ScreenshotIngest.pruneDeleted`'"'"'s never-prune-on-an-empty-read rule in a
# room that draws rather than deletes, and it fails in the direction that
# invents alarming news.
mutate "an UNREACHED account must never read as having had its keys revoked" \
  'guard item.reached else { continue }' \
  'guard true else { continue }'

# First sight seeds silently or a newly-watched account reports every key it
# has ever had as new — the Hyperliquid first-sight bug, fifth bridge.
mutate "an account with no ledger entry must seed SILENTLY" \
  'guard let before = seen[key] else { continue }' \
  'let before = seen[key] ?? []'

# The write half of the same rule. Overwriting an unreached account with the
# failed read yields nothing, which makes the NEXT successful read report every
# one of its keys as new.
mutate "advanced must keep an unreached account set, never overwrite it with nothing" \
  '} else if let before = seen[key] {
                out[key] = before
            }' \
  '}'

# An actorId is unique WITHIN an account and nothing says it is across them, so
# an unqualified key lets one account key mark another as seen — which HIDES a
# change rather than inventing one, i.e. silently.
mutate "the ledger key must be account-qualified" \
  '"\(address.lowercased())|\(actorId.lowercased())"' \
  '"\(actorId.lowercased())"'

# The tray mirrors the card grouping or a card that says 4 opens a list of 3.
# NOT A MUTATION HERE EITHER, same shape as the futureExpiries note above
# (found running this harness, 2026-08-25): `!$0.actor.scope.isAdmin` is
# REDUNDANT with `.raw & bit != 0` beside it, because an admin's `raw` is 0
# (isAdmin's own definition) and 0 ANDed with any nonzero bit is always 0 — so
# an admin key can never satisfy `raw & bit != 0` for ANY of the five named
# bits regardless of the isAdmin clause, and no fixture can make the two
# clauses disagree. Same standing rule: a fixture only tests the rule it
# names if it fails that rule and passes every other one. The clause stays in
# the shipped source as documentation of intent (and because
# `VibenetPolicyAggregation.compose`'"'"'s own count is written the identical,
# equally-redundant way — the two must keep matching TEXT, not just behavior,
# or a future reader "simplifying" one first breaks the mirror this tray
# depends on). The assertion above ("an ADMIN is excluded from every bit
# section — it is not five permissions, it is one word") is the correctness
# proof; this is not.

# A key in no section at all is either said or lost. Losing it is the silent
# half of §83 — the tray looks complete and is not.
mutate "a key holding only reserved bits must be COUNTED, never dropped in silence" \
  'filter { !$0.scope.isAdmin && $0.scope.raw & VibenetScope.known == 0 }' \
  'filter { false }'

# Without the note the tray row count reads as a contradiction of the card
# above it — fourteen rows over eight keys.
mutate "the tray footnote must warn that one key appears under several permissions" \
  'line += String(localized: " · a key with several permissions appears under each")' \
  'line += ""'

# A revoke is a KEY event as well as a revocation. Losing the Key facet makes
# "keys on vibenet" answer with the live ones only — plausible, and wrong.
mutate "a revoke must keep its Key facet, not only its Revoked one" \
  'case .actorRevoked: return ["Key", "Revoked"]' \
  'case .actorRevoked: return ["Revoked"]'

# A lock is about the ACCOUNT.
mutate "a lock must carry no key facet" \
  'case .locked: return ["Locked"]' \
  'case .locked: return ["Locked", "Key"]'

# --- prd §470 mutations -----------------------------------------------------

# A passkey actorId is a HASH. Without the high-bytes-are-zero test it decodes
# to a plausible 20-byte address belonging to nobody — and this build would
# then offer "Copy signer address" on that row, handing a developer an address
# that signs for no one, on the screen they read to find out who can spend
# their account.
mutate "a hashed actorId must name NO signer — never a plausible address that is not one" \
  'guard s.prefix(24).allSatisfy({ $0 == "0" }) else { return nil }' \
  'guard s.count == 64 else { return nil }'

# Ragged-width hex is a column the reader right-aligns in their head, and
# `0x13` vs `0x0013` is exactly the comparison this word exists for.
mutate "the scope word must be zero-padded to the full 16 bits" \
  'String(format: "0x%04x", scope.raw)' \
  'String(format: "0x%x", scope.raw)'

# THE SHARPEST ONE HERE. A bare `0` in a paste reads as an epoch DATE — a key
# that never expires would document itself as having expired in 1970, in the
# artifact a developer trusts precisely because it is raw.
mutate "expiry 0 must be spelled 'never', never rendered as a date" \
  'parts.append("expires never (0)")' \
  'parts.append("expires \(iso(Date(timeIntervalSince1970: TimeInterval(actor.expiry)))) (0)")'

# The whole word or nothing: the row already shows the tail, and a paste that
# repeated the tail would hand back exactly what the reader already had.
mutate "the key line must carry the FULL actorId, not the short form" \
  'var parts: [String] = [actor.actorId, actor.kind.label]' \
  'var parts: [String] = [VibenetKeyIdentity.short(actor.actorId), actor.kind.label]'

# An omitted line reads as "this account has none of that". The truth may be
# "the read failed", and only saying so keeps the two apart.
mutate "an unread balance must say so, never be silently omitted" \
  'lines.append("native: unread")' \
  '()'

mutate "unread change sequences must say so rather than vanishing" \
  'lines.append("changeSequences: unread")' \
  '()'

# `reached: no` leads so a reader knows everything under it is a floor. Losing
# the clause turns a partial record into one that reads as complete.
mutate "an unreached account must warn that its record is not a census" \
  'no — everything below is what we last saw, not a census' \
  'no'

# Ranking keys in the paste is the app making a judgement in the one artifact
# whose entire point is being raw (§463's own user ruling, carried through).
mutate "the paste must use the judgement-free order, never arrival order" \
  'for actor in VibenetAccountItem.alphabetical(item.actors) {' \
  'for actor in item.actors {'

# The short form is the tail of the id. Taking the head instead makes every
# secp256k1 key render as "…0000" — the zero padding — so every wallet key on
# every account would draw an identical id, which is the exact failure the id
# was added to fix.
mutate "the short id must be the TAIL, never the head" \
  'VibenetRoom.shortAddress(actorId)' \
  'String(actorId.prefix(6))'

echo ""
echo "✓ vibenet-selftest: drift guards, assertions and mutations all passed"
