#!/bin/zsh
# Casberi room kind-tiles self-test (prd §815, §816) — the SHIPPED pure logic
# behind the Safe, GitHub, Stripe, App Store Connect, Hugging Face, PostHog,
# L2BEAT and Walletbeat rooms' section tiles, compiled WHOLE and unmodified:
#
#   Casberi/Casberi/Model/RoomKindTiles.swift
#   Casberi/Casberi/Model/GitHubRowTag.swift   (GitHub's kinds)
#   Casberi/Casberi/Model/GitHubLinks.swift    (its URL reader)
#
# Every failure here renders as a perfectly good-looking tile:
#
#   · `hasPrefix("wallet:safe")` claims the outcome, signed and config rows as
#     pending — the Queue tile would list what already went through
#   · a pending row SURVIVES its execution (`SafeBridge.landOutcome` lands a
#     new row and deletes nothing), so a Queue read off the prefix alone lists
#     every transaction the Safe ever executed
#   · `hasPrefix("asc:build")` claims the build-EXPIRY warning as a build
#   · `hasPrefix("posthog:m")` claims a milestone as a metric
#   · a head room that ALSO draws the tiles under a cover draws them twice
#   · All beside ONE kind draws the same list twice (the §805 Privy defect)
#   · a pick whose kind has gone narrows the room to nothing
#   · a glyph worn by two different meanings (user, 2026-09-18: "you can't
#     reuse an existing icon we use for a different type of tile, and you
#     can't make up new icons for existing icons we have")
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

KINDS="Casberi/Casberi/Model/RoomKindTiles.swift"
TAG="Casberi/Casberi/Model/GitHubRowTag.swift"
LINKS="Casberi/Casberi/Model/GitHubLinks.swift"
GLYPHS="Casberi/Casberi/Screens/ScopeTileGlyphs.swift"
FOLD="Casberi/Casberi/Model/CategoryFold.swift"
for f in "$KINDS" "$TAG" "$LINKS" "$GLYPHS" "$FOLD"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# ── Drift guards ────────────────────────────────────────────────────────────
# The room names are literals in the Foundation file; each must equal the
# seat's own source string, or the tiles silently never draw.
grep -qF 'static let sourceName = "Safe"' Casberi/Casberi/Model/SafeBridge.swift \
  || { echo "✗ SafeBridge.sourceName drifted from RoomKindTiles.Room's \"Safe\""; exit 1; }
grep -qF 'static let source = "Stripe"' Casberi/Casberi/Model/StripeBridge.swift \
  || { echo "✗ StripeWatch.source drifted from RoomKindTiles.Room's \"Stripe\""; exit 1; }
grep -qF 'static let source = "Splits"' Casberi/Casberi/Model/SplitsShape.swift \
  || { echo "✗ SplitsShape.source drifted from RoomKindTiles.Room's \"Splits\""; exit 1; }
grep -qF 'static let accountPrefix = "splits:account:"' Casberi/Casberi/Model/SplitsShape.swift \
  || { echo "✗ SplitsShape.accountPrefix drifted — the Accounts tile reads splits:account:"; exit 1; }
grep -qF 'static let waitingTag = "Waiting"' Casberi/Casberi/Model/SplitsShape.swift \
  || { echo "✗ SplitsShape.waitingTag drifted — the Queue tile reads the \"Waiting\" tag"; exit 1; }
grep -qF 'static let txPrefix = "splits:tx:"' Casberi/Casberi/Model/SplitsShape.swift \
  || { echo "✗ SplitsShape.txPrefix drifted — the Activity tile reads splits:tx:"; exit 1; }
grep -qF 'source: "GitHub"' Casberi/Casberi/Model/GitHubFeeds.swift \
  || { echo "✗ the GitHub seat no longer lands rows under \"GitHub\""; exit 1; }
ASC="Casberi/Casberi/Model/AppStoreConnectBridge.swift"
HF="Casberi/Casberi/Model/HuggingFaceBridge.swift"
grep -qF 'static let source = "App Store Connect"' "$ASC" \
  || { echo "✗ ASCShape.source drifted from RoomKindTiles.Room's \"App Store Connect\""; exit 1; }
grep -qF 'source: "Hugging Face"' "$HF" \
  || { echo "✗ the Hugging Face seat no longer lands rows under \"Hugging Face\""; exit 1; }
# App Store Connect's four ref shapes (prd §816) — three kinds and the expiry
# warning the Builds tile must NOT claim.
for r in 'sourceRef: "asc:version:\(id):\(state.rawValue)"' 'sourceRef: "asc:review:\(id)"' \
         'sourceRef: "asc:build:\(id):\(state.rawValue)"' 'sourceRef: "asc:buildexpiry:\(id)"'; do
  grep -qF "$r" "$ASC" || { echo "✗ App Store Connect's ref shape moved: $r"; exit 1; }
done
# Hugging Face: a release is hf:<HuggingFaceRepo raw value>:<id>, a paper
# hf:paper:<arxiv id>; the Models and Datasets tiles read the repo's raw value.
grep -qF 'let ref = "hf:\(repo.rawValue):\(release.id.lowercased())"' "$HF" \
  || { echo "✗ Hugging Face's release ref shape moved — Models/Datasets read hf:<repo>:"; exit 1; }
grep -qF 'let ref = "hf:paper:\(paper.arxivID)"' "$HF" \
  || { echo "✗ Hugging Face's paper ref shape moved — Papers reads hf:paper:"; exit 1; }
grep -qF 'case model, dataset, space' "$HF" \
  || { echo "✗ HuggingFaceRepo's raw values moved — hf:model:/hf:dataset: would match nothing"; exit 1; }
# PostHog, L2BEAT and Walletbeat (prd §816): the source names and the ref
# prefixes the Foundation file spells, at the one place each seat defines them.
PH="Casberi/Casberi/Model/PostHogBridge.swift"
grep -qF 'static let source = "PostHog"' "$PH" \
  || { echo "✗ the PostHog source drifted from RoomKindTiles.Room's \"PostHog\""; exit 1; }
for r in 'static let metricPrefix = "posthog:metric:"' 'sourceRef: "posthog:annotation:\(note.id)"' \
         'sourceRef: "posthog:milestone:\(event):\(reached)"' 'sourceRef: "posthog:silence:\(event):\(today)"'; do
  grep -qF "$r" "$PH" || { echo "✗ PostHog's ref shape moved: $r"; exit 1; }
done
L2S="Casberi/Casberi/Model/L2beatSheet.swift"
for r in 'static let source = "L2BEAT"' 'static let chainPrefix = "l2beat:chain:"' \
         'static let newsPrefix = "l2beat:news:"' 'static let revisionPrefix = "l2beat:rev:"'; do
  grep -qF "$r" "$L2S" || { echo "✗ L2BEAT's identity moved: $r"; exit 1; }
done
WBS="Casberi/Casberi/Model/WalletbeatSheet.swift"
for r in 'static let source = "Walletbeat"' 'static let walletPrefix = "walletbeat:wallet:"' \
         'static let newsPrefix = "walletbeat:news:"' 'static let revisionPrefix = "walletbeat:rev:"'; do
  grep -qF "$r" "$WBS" || { echo "✗ Walletbeat's identity moved: $r"; exit 1; }
done
# The ref shapes the classification reads, at their one landing site each.
grep -qF 'let ref = "wallet:safe:\(chain.seg):\(safeTxHash)"' Casberi/Casberi/Model/SafeBridge.swift \
  || { echo "✗ SafeBridge's pending ref shape moved — Queue reads wallet:safe:<seg>:<hash>"; exit 1; }
grep -qF 'let ref = "wallet:safeoutcome:\(chain.seg):\(hash)"' Casberi/Casberi/Model/SafeBridge.swift \
  || { echo "✗ SafeBridge's outcome ref shape moved — a resolved pending row would stay in Queue"; exit 1; }
grep -qF 'sourceRef: "stripe:event:\(id)"' Casberi/Casberi/Model/StripeBridge.swift \
  || { echo "✗ Stripe's event ref shape moved — the Stripe tiles read stripe:event:"; exit 1; }
for t in '"Dispute"' '"Payout"' '"Dunning"' '"Churn"'; do
  grep -qF "tag: $t" Casberi/Casberi/Model/StripeBridge.swift \
    || { echo "✗ Stripe no longer tags an event $t — a Stripe tile would lose its rows"; exit 1; }
done
grep -qF 'var title = "Dispute opened' Casberi/Casberi/Model/StripeBridge.swift \
  || { echo "✗ the Stripe dispute title moved — openDisputes reads \"Dispute opened\""; exit 1; }
# The feed wiring: the pick narrows the room, the presence is read BEFORE the
# pick, and the pick dies with the room.
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
grep -qF 'let full = liveVisible(rawOverride: raw, kindPick: false).live' "$FEED" \
  || { echo "✗ the tiles' presence is read off the narrowed list — a picked tile would hide its siblings"; exit 1; }
grep -qF 'RoomKindTiles.allows(pick, kind:' "$FEED" \
  || { echo "✗ the kind pick no longer narrows the room's rows"; exit 1; }
grep -qF 'chrome.roomKind = .all' Casberi/Casberi/Shell/MainSurface.swift \
  || { echo "✗ the kind pick no longer resets on a room change — a room would open on a stale tile"; exit 1; }
# The cover holds the box in EVERY room since prd §904 (the `holdsLead: true`
# these rooms passed is deleted with the flag), so the tiles' anchor is the
# card's own frame: floor and ceiling the one box.
LEDE="Casberi/Casberi/Screens/FeedLedeCard.swift"
grep -qF 'minHeight: box,' "$LEDE" && grep -qF 'maxHeight: box,' "$LEDE" \
  || { echo "✗ the cover no longer holds the box — the kind tiles would move between picks (prd §904)"; exit 1; }
# WHERE A ROOM HAS A HEAD, THE TILES RIDE ITS SCOPES SLOT (prd §816, user: "keep
# the safe head the way it was"). Each head hands them to `DSRoomChassis.Head`
# — its own geometry, no hand-placed frame — and the cover path stands them
# only when no head is drawn, or a head room would draw them twice.
for card in SafeRoomCard StripeRoomCard PostHogRoomCard L2beatRoomCard WalletbeatRoomCard PolarRoomCard DodoPaymentsRoomCard; do
  f="Casberi/Casberi/Screens/$card.swift"
  grep -qF 'var tiles: DSScopeTiles<RoomKindTile>? = nil' "$f" \
    || { echo "✗ $card no longer takes the room's kind tiles"; exit 1; }
  grep -qE '^[[:space:]]*tiles: tiles\) \{' "$f" \
    || { echo "✗ $card no longer hands its tiles to DSRoomChassis.Head's scopes slot"; exit 1; }
done
python3 - "$FEED" <<'PY'
import re, sys
feed = open(sys.argv[1]).read()
bad = [c for c in ["SafeRoomCard", "StripeRoomCard", "PostHogRoomCard", "L2beatRoomCard", "WalletbeatRoomCard",
                   "PolarRoomCard", "DodoPaymentsRoomCard"]
       if not re.search(c + r'\([^{]*tiles: kindTilesInHead\)', feed)]
for c in bad:
    print(f"✗ FeedScreen no longer hands {c} the kind tiles")
sys.exit(1 if bad else 0)
PY
grep -qF 'let scopeTiles = heroShown ? nil : kindTilesInHead' "$FEED" \
  || { echo "✗ the cover path draws the tiles under a drawn head — a head room would show them twice"; exit 1; }
# NOTHING STANDS AT THE TOP OF THE SCREEN (prd §862, §752). A cover holds the
# lead between the picks that HAVE one — and a pick that holds no rows had
# nothing above the tiles at all, so they rose to the top edge, which is the
# one thing §752 bans outright. The empty state holds the lead instead, and
# it is gated on an empty list: over a full one it would be the §83 lie.
python3 - "$FEED" <<'LEAD'
import sys
src = "\n".join("" if l.strip().startswith("//") else l
                 for l in open(sys.argv[1]).read().splitlines())
fails = []
# The kind-tile rooms' lead, tiles and empty state are one drawing since
# prd §911 (`standaloneLead`, shared with Cursor, Walletbeat and L2BEAT).
for fn, tiles in (("private func standaloneLead", "if let tiles {"),
                  ("private func agentRoomSections", "if let agentTiles {")):
    i = src.find(fn)
    if i < 0:
        fails.append(f"{fn} is gone — this guard is blind"); continue
    body = src[i:i + 4000]
    t = body.find(tiles)
    lead = body.find("emptyLeadRow(")
    if t < 0:
        fails.append(f"{fn}: the tiles' own block moved — this guard is blind"); continue
    if lead < 0 or lead > t:
        fails.append(f"{fn}: nothing holds the lead when the pick is empty — "
                     "the tiles stand at the top of the screen (\u00a7846)")
        continue
    arm = body[max(0, lead - 260):lead]
    if "visible.isEmpty" not in arm and "listEmpty" not in arm:
        fails.append(f"{fn}: the empty lead is not gated on an empty list — "
                     "it would draw a skeleton over a full one (\u00a783)")
for f in fails:
    print("  \u2717 " + f)
if fails:
    sys.exit(1)
print("  \u2713 the lead slot is held wherever the tiles stand, and only over an empty list")
LEAD
# THE BOX IS `FeedLedeCard`'s, PADDING SUBTRACTED. `dsRoomHeadBlock` adds
# `2 × s4` of its own, so a well framed at a bare `leadHeight` stands 30pt
# taller than the cover it stands in for and the tiles move anyway — which is
# how §861's agent-room arm shipped, and why this is pinned rather than trusted.
grep -qF 'minHeight: DSRoomChassis.leadBox' "$FEED" \
  || { echo "✗ the empty lead no longer holds FeedLedeCard's own box — the tiles would sit at two heights (§862)"; exit 1; }
grep -qE '\.frame\(height: DSRoomChassis\.leadHeight\)[[:space:]]*$' "$FEED" \
  && { echo "✗ a lead well is framed at a bare leadHeight inside dsRoomHeadBlock — that is 2 × s4 too tall (§862)"; exit 1; }
grep -qF 'self.scopes = tiles' Casberi/Casberi/Design/DSRoomHead.swift \
  || { echo "✗ DSRoomChassis.Head no longer takes optional tiles — nil must draw the head alone"; exit 1; }
# Every tile glyph is a ScopeTileGlyph name, never a literal in the switch.
python3 - "$GLYPHS" "$FOLD" <<'PY'
import re, sys
glyphs, fold = (open(p).read() for p in sys.argv[1:3])
fails = []
# RoomKindTile's switch names constants only.
m = re.search(r'extension RoomKindTile: DSTileScope \{(.*?)\n\}', glyphs, re.S)
if not m:
    fails.append("RoomKindTile's DSTileScope conformance is missing")
else:
    body = m.group(1)
    if re.search(r'return\s+"', body):
        fails.append("RoomKindTile spells a glyph literal — every tile glyph lives in ScopeTileGlyph")
    for case in ["all", "queue", "activity", "permissions", "pullRequests", "issues",
                 "releases", "payments", "payouts", "disputes",
                 "versions", "reviews", "builds", "models", "datasets", "papers",
                 "metrics", "annotations", "milestones", "chains", "wallets", "news", "revisions", "accounts",
                 "sales", "subscriptions", "errors", "regressions", "deploys", "failed",
                 "alarms", "costs", "incidents", "resolved", "deprecations", "workouts", "sleep", "mood"]:
        if not re.search(r'case \.%s:\s+return ScopeTileGlyph\.%s\b' % (case, case), body):
            fails.append(f"RoomKindTile.{case} does not wear ScopeTileGlyph.{case}")
# All is the dock's own glyph, read from its one table.
if 'static var all: String { CategoryFold.glyph(for: "All") }' not in glyphs:
    fails.append("ScopeTileGlyph.all retypes the dock's All glyph instead of reading CategoryFold")
# One glyph, one meaning, across every tile and every dock seat.
table = re.search(r'enum ScopeTileGlyph \{(.*?)\n\}', glyphs, re.S).group(1)
meanings = {}
def claim(sym, meaning):
    meanings.setdefault(sym, set()).add(meaning)
for name, sym in re.findall(r'static let (\w+)\s*=\s*"([^"]+)"', table):
    claim(sym, name.lower())
dock = re.search(r'private static let glyphs: \[String: String\] = \[(.*?)\]', fold, re.S).group(1)
for cat, sym in re.findall(r'"([^"]+)":\s*"([^"]+)"', dock):
    claim(sym, cat.lower())
for sym, names in sorted(meanings.items()):
    if len(names) > 1:
        fails.append(f'"{sym}" means {sorted(names)} — one glyph may carry one meaning')
# The ones the user named as off-limits for a new meaning.
for sym, owner in [("building.columns", "positions"), ("creditcard", "wallet"),
                   ("creditcard.fill", "wallet"), ("checkmark.shield", "review"),
                   ("shield", "risk"), ("key", "permissions")]:
    if sym in meanings and meanings[sym] - {owner}:
        fails.append(f'"{sym}" is {owner}\'s and wears another meaning')
# A CASE'S NAME AND ITS GLYPH'S NAME ARE THE SAME WORD (2026-09-19, prd 831).
#
# The check above reads the TABLE - one constant, one symbol - so it cannot see
# two meanings pointing at one constant. Privy's Apps returned
# `ScopeTileGlyph.frames` for a month and every guard here was green: the table
# was fine, and the section enum nobody was reading is where the collision
# lived (user: "on the privy screen, you're using the same icon for apps that
# we use for frames"). So every `DSTileScope` conformance in this file is read,
# not just RoomKindTile's, and a case may only wear the constant of its own
# name - unless the pair is declared below, with its reason.
ALIASES = {
    # A Hegota coin IS a UTXO; the room says "Coins" and the vocabulary says
    # utxos - one meaning under two words.
    ("HegotaSection", "coins"): "utxos",
    # A privacy root is the snapshot of the tree it was taken from.
    ("PrivacyDevnetSection", "roots"): "snapshots",
    # GitLab's merge request and Radicle's patch ARE pull requests - one
    # meaning under three words (prd §911), so one glyph.
    ("RoomKindTile", "mergeRequests"): "pullRequests",
    ("RoomKindTile", "patches"): "pullRequests",
}
seen_aliases = set()
for m in re.finditer(r'extension ([\w.]+): DSTileScope \{(.*?)\n\}', glyphs, re.S):
    owner, body = m.group(1), m.group(2)
    short = owner.split(".")[0]
    if re.search(r'return\s+"', body):
        fails.append(f"{owner} spells a glyph literal - every tile glyph lives in ScopeTileGlyph")
    for case, const in re.findall(r'case \.(\w+):\s*return ScopeTileGlyph\.(\w+)\b', body):
        if case == const:
            continue
        if ALIASES.get((short, case)) == const:
            seen_aliases.add((short, case))
        else:
            fails.append(f"{owner}.{case} wears ScopeTileGlyph.{const} - a case wears its own "
                         f"name's glyph, or the pair is declared an alias with its reason")
# A stale allowance fails too: an alias whose case is gone guards nothing.
for (short, case), const in sorted(ALIASES.items()):
    if (short, case) not in seen_aliases:
        fails.append(f"the declared alias {short}.{case} -> {const} no longer exists - "
                     f"delete it rather than leaving an allowance that guards nothing")
for f in fails:
    print("✗ " + f)
sys.exit(1 if fails else 0)
PY
# prd §911 — the twelve rooms' ref and tag shapes, at the one place each
# bridge spells them. A moved shape makes a tile silently claim nothing.
POL="Casberi/Casberi/Model/PolarBridge.swift"; DODO="Casberi/Casberi/Model/DodoPaymentsBridge.swift"
for r in 'static let source = "Polar"' 'static let orderRefPrefix = "polar:order:"' 'sourceRef: "polar:refund:\(id)"' \
         'sourceRef: "polar:dispute:\(refundID):opened"' 'sourceRef: "polar:subscription:\(id):\(status)"' \
         'tag: "Dispute"' 'tag: "Refund"' 'tag: "Sale"' 'tag: "Subscription"'; do
  grep -qF "$r" "$POL" || { echo "✗ Polar's shape moved: $r"; exit 1; }
done
for r in 'static let source = "Dodo Payments"' 'sourceRef: "dodopayments:payment:\(id)"' 'sourceRef: "dodopayments:refund:\(id)"' \
         'sourceRef: "dodopayments:dispute:\(id):opened"' 'sourceRef: "dodopayments:subscription:\(id):\(status)"' \
         'tag: "Payment"' 'tag: "Refund"' 'tag: "Dispute"' 'tag: "Subscription"'; do
  grep -qF "$r" "$DODO" || { echo "✗ Dodo Payments' shape moved: $r"; exit 1; }
done
TB="Casberi/Casberi/Model/TokenBridges.swift"
for r in 'source: "GitLab"' 'sourceRef: "gitlab:\(refPrefix):\(id)"' 'refPrefix: "issue"' 'refPrefix: "mr"'; do
  grep -qF "$r" "$TB" || { echo "✗ GitLab's shape moved: $r"; exit 1; }
done
RAD="Casberi/Casberi/Model/RadicleBridge.swift"
for r in 'source: "Radicle"' 'let ref = "radicle:patch:\(rid):\(patch.id):opened"' 'let ref = "radicle:issue:\(rid):\(issue.id):opened"' \
         'tags: ["Patch", "Proposed"]' 'tags: ["Issue", "Opened"]'; do
  grep -qF "$r" "$RAD" || { echo "✗ Radicle's shape moved: $r"; exit 1; }
done
SEN="Casberi/Casberi/Model/SentryBridge.swift"
for r in 'source: "Sentry"' 'static func newRef(id: String) -> String { "sentry:issue:\(id)" }' \
         '"sentry:\(substatus.rawValue):\(id):\(crossing)"' 'case regressed   = "regressed"' 'case escalating  = "escalating"'; do
  grep -qF "$r" "$SEN" || { echo "✗ Sentry's shape moved: $r"; exit 1; }
done
VER="Casberi/Casberi/Model/VercelBridge.swift"
for r in 'source: "Vercel"' 'sourceRef: "vercel:deploy:\(uid)"' '"Build failure"'; do
  grep -qF "$r" "$VER" || { echo "✗ Vercel's shape moved: $r"; exit 1; }
done
PDB="Casberi/Casberi/Model/PagerDutyBridge.swift"
for r in 'source: "PagerDuty"' '{ "pagerduty:incident:\(id)" }' '{ "pagerduty:resolved:\(id)" }'; do
  grep -qF "$r" "$PDB" || { echo "✗ PagerDuty's shape moved: $r"; exit 1; }
done
PKG="Casberi/Casberi/Model/PackageWatchBridge.swift"
for r in '"\(registry.rawValue):release:\(name.lowercased()):\(version)"' '"\(registry.rawValue):deprecated:\(name.lowercased())"' \
         'case npm' 'case pypi' 'case .npm:  "npm"' 'case .pypi: "PyPI"'; do
  grep -qF "$r" "$PKG" || { echo "✗ the package registries' shape moved: $r"; exit 1; }
done
AWSB="Casberi/Casberi/Model/AWSBridge.swift"
for r in 'static let source = "AWS"' 'sourceRef: "aws:alarm:' 'sourceRef: "aws:pipeline:\(id)"' 'sourceRef: "aws:costanomaly:\(day)"'; do
  grep -qF "$r" "$AWSB" || { echo "✗ AWS's shape moved: $r"; exit 1; }
done
CUR="Casberi/Casberi/Model/CursorBridge.swift"
for r in 'source: "Cursor"' 'sourceRef: "cursor:agent:\(id)"' '"Failed"' '"Expired"' '"Cancelled"' 'tags.append("PR")'; do
  grep -qF "$r" "$CUR" || { echo "✗ Cursor's shape moved: $r"; exit 1; }
done
HKI="Casberi/Casberi/Model/HealthIngest.swift"
for r in 'source: "Apple Health"' '"hkworkout:\(record.activityID)"' 'let ref = "hksleep:\(night.dayKey)"' 'let ref = "hkmood:\(mood.uuid.uuidString)"'; do
  grep -qF "$r" "$HKI" || { echo "✗ Apple Health's shape moved: $r"; exit 1; }
done
# The Cursor room draws its tiles by hand inside its repository shape, and
# Walletbeat's and L2BEAT's stand alone when their head is nil (prd §911).
grep -qF 'private func standaloneLead(cover: Thing?, tiles: DSScopeTiles<RoomKindTile>?,' "$FEED" \
  || { echo "✗ FeedScreen lost standaloneLead — the cover, empty lead and tiles in one drawing"; exit 1; }
[[ $(grep -c 'standaloneLead(cover:' "$FEED") -ge 4 ]] \
  || { echo "✗ fewer than four rooms draw the standalone lead (kind-tile rooms, Cursor, Walletbeat, L2BEAT)"; exit 1; }
echo "room-kind-tiles-selftest: drift guards ✓"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}

typealias T = RoomKindTile

// ── Rooms ────────────────────────────────────────────────────────────────
check(RoomKindTiles.Room(source: "Safe") == .safe
      && RoomKindTiles.Room(source: "GitHub") == .github
      && RoomKindTiles.Room(source: "Stripe") == .stripe
      && RoomKindTiles.Room(source: "App Store Connect") == .appStoreConnect
      && RoomKindTiles.Room(source: "Hugging Face") == .huggingFace
      && RoomKindTiles.Room(source: "PostHog") == .posthog
      && RoomKindTiles.Room(source: "L2BEAT") == .l2beat
      && RoomKindTiles.Room(source: "Walletbeat") == .walletbeat, "the eight rooms resolve from their sources")
// prd §911 — the twelve rooms whose rows already carried a kind.
for (source, room) in [("Polar", RoomKindTiles.Room.polar), ("Dodo Payments", .dodoPayments),
                       ("GitLab", .gitlab), ("Radicle", .radicle), ("Sentry", .sentry),
                       ("Vercel", .vercel), ("PagerDuty", .pagerduty), ("npm", .npm),
                       ("PyPI", .pypi), ("AWS", .aws), ("Cursor", .cursor),
                       ("Apple Health", .appleHealth)] {
    check(RoomKindTiles.Room(source: source) == room, "\(source) resolves to its room (§911)")
}
check(RoomKindTiles.Room(source: "Wallet") == nil && RoomKindTiles.Room(source: "All") == nil,
      "no other room grows kind tiles")
// The room §816 held: its lead is a figure with no scopes slot (Cloudflare's
// runway), so tiles there would be hand-placed. Apple Health left this list
// in §911 — the heatmap that held it is gone, and the room leads with its
// cover like every other tile room.
for held in ["Cloudflare"] {
    check(RoomKindTiles.Room(source: held) == nil, "\(held) grows no kind tiles — its lead has no scopes slot")
}
// The social rooms DECLINED tiles (§821): nearly everyone has only the live
// door, which is one kind, and the notifications already lead by date.
for declined in ["Instagram", "X", "TikTok"] {
    check(RoomKindTiles.Room(source: declined) == nil, "\(declined) has no kind tiles (§821, declined)")
}
// ONE MEANING, ONE CASE: News and Revisions are the same case in both rating
// rooms, so they cannot wear two glyphs.
check(RoomKindTiles.Room.l2beat.order.contains(.news) && RoomKindTiles.Room.walletbeat.order.contains(.news)
      && RoomKindTiles.Room.l2beat.order.contains(.revisions) && RoomKindTiles.Room.walletbeat.order.contains(.revisions),
      "News and Revisions are one case each, shared by L2BEAT and Walletbeat")
// Every tile is offered by at least one room: a case no room orders is a
// meaning with a glyph and no door.
for tile in T.allCases {
    check(RoomKindTiles.Room.allCases.contains { $0.order.contains(tile) },
          "\(tile.rawValue) is offered by some room")
}
for room in RoomKindTiles.Room.allCases {
    check(room.order.first == .all, "\(room.source): All is the first tile")
    check(RoomKindTiles.Room(source: room.source) == room, "\(room.source): source round-trips")
}

// ── Safe: the prefix trap and the surviving pending row ─────────────────
let safeRefs: [String?] = [
    "wallet:safe:eth:0xAAA",          // pending, still open
    "wallet:safe:eth:0xBBB",          // pending, since executed
    "wallet:safeoutcome:eth:0xbbb",   // its outcome (case differs on purpose)
    "wallet:safesigned:eth:0xAAA",    // you signed the open one
    "wallet:safeconfig:eth:0xsafe:",  // an owner/threshold/module change
    nil,
]
let safe = RoomKindTiles.Census(room: .safe, refs: safeRefs)
func sk(_ ref: String?) -> T? { safe.kind(ref: ref, url: nil, tags: []) }
check(sk("wallet:safe:eth:0xAAA") == .queue, "an open pending transaction is Queue")
check(sk("wallet:safe:eth:0xBBB") == nil, "a pending row whose outcome landed is NOT Queue — it survives execution")
check(sk("wallet:safeoutcome:eth:0xbbb") == .activity, "an outcome is Activity, never Queue (prefix trap)")
check(sk("wallet:safesigned:eth:0xAAA") == .activity, "your signature is Activity, never Queue (prefix trap)")
check(sk("wallet:safeconfig:eth:0xsafe:") == .permissions, "a config change is Permissions, never Queue (prefix trap)")
check(sk("wallet:safe:") == nil, "a pending ref with no tail claims nothing")
check(sk(nil) == nil && sk("gh:star:x") == nil, "a row with no Safe ref is All only")
let safeNone = RoomKindTiles.Census(room: .safe, refs: ["wallet:safe:eth:0xBBB"])
check(safeNone.kind(ref: "wallet:safe:eth:0xBBB", url: nil, tags: []) == .queue,
      "with no outcome landed, the pending row stays in Queue")

// ── GitHub: the URL decides, the feed's leftovers are All only ──────────
let gh = RoomKindTiles.Census(room: .github, refs: [])
check(gh.kind(ref: "gh:1", url: "https://github.com/a/b/pull/7", tags: []) == .pullRequests, "a PR URL is Pull requests")
check(gh.kind(ref: "gh:2", url: "https://github.com/a/b/issues/7", tags: []) == .issues, "an issue URL is Issues")
check(gh.kind(ref: "gh:3", url: "https://github.com/a/b/releases/tag/v1", tags: []) == .releases, "a release URL is Releases")
check(gh.kind(ref: "gh:star:a/b", url: "https://github.com/a/b", tags: []) == nil, "a star is All only")
check(gh.kind(ref: "gh:gist:1", url: nil, tags: []) == nil, "a gist is All only")
check(gh.kind(ref: "gh:event:1", url: nil, tags: []) == nil, "activity is All only")

// ── Stripe: tags, events only ───────────────────────────────────────────
let st = RoomKindTiles.Census(room: .stripe, refs: [])
func sp(_ ref: String?, _ tags: [String]) -> T? { st.kind(ref: ref, url: nil, tags: tags) }
check(sp("stripe:event:1", ["Dispute"]) == .disputes, "a dispute opened is Disputes")
check(sp("stripe:event:2", ["Dispute", "Won"]) == .disputes, "a dispute closed is Disputes")
check(sp("stripe:event:3", ["Payout"]) == .payouts, "a payout is Payouts")
check(sp("stripe:event:4", ["Payout", "Failed"]) == .payouts, "a failed payout is Payouts")
check(sp("stripe:event:5", ["Dunning"]) == .payments, "a failed invoice is Payments")
check(sp("stripe:event:6", ["Dunning", "Recovered"]) == .payments, "a recovered invoice is Payments")
check(sp("stripe:event:7", ["Churn"]) == .payments, "a canceled subscription is Payments")
check(sp("stripe:runway:low:1", ["Runway"]) == nil, "the runway alert is All only")
check(sp("stripe:silence:2026-09-18", ["Silence"]) == nil, "the silence alert is All only")
check(sp("stripe:runway:low:1", ["Dispute"]) == nil, "a non-event ref never claims a kind, whatever its tags")

// ── App Store Connect: the build-expiry trap ────────────────────────────
let asc = RoomKindTiles.Census(room: .appStoreConnect, refs: [])
func ak(_ ref: String?) -> T? { asc.kind(ref: ref, url: nil, tags: []) }
check(ak("asc:version:123:IN_REVIEW") == .versions, "a version verdict is Versions")
check(ak("asc:version:123:READY_FOR_SALE") == .versions, "a released version is Versions")
check(ak("asc:review:abc") == .reviews, "a customer review is Reviews")
check(ak("asc:build:999:VALID") == .builds, "a processed build is Builds")
check(ak("asc:buildexpiry:999") == nil, "a build-EXPIRY warning is All only, never Builds (prefix trap)")
check(ak("asc:versionx:1") == nil && ak("asc:reviews:1") == nil, "a ref that only STARTS like a kind claims nothing")
check(ak(nil) == nil && ak("hf:model:a/b") == nil, "a row with no App Store Connect ref is All only")

// ── Hugging Face: releases by repo, papers, Spaces All only ─────────────
let hf = RoomKindTiles.Census(room: .huggingFace, refs: [])
func hk(_ ref: String?) -> T? { hf.kind(ref: ref, url: nil, tags: []) }
check(hk("hf:model:google/gemma-3") == .models, "a model release is Models")
check(hk("hf:dataset:allenai/c4") == .datasets, "a dataset release is Datasets")
check(hk("hf:paper:2509.01234") == .papers, "a daily paper is Papers")
check(hk("hf:space:gradio/demo") == nil, "a Space is All only")
check(hk("hf:models:x") == nil && hk("hf:modelx:y") == nil, "a ref that only STARTS like a kind claims nothing")
check(hk(nil) == nil && hk("asc:review:1") == nil, "a row with no Hugging Face ref is All only")
check(RoomKindTiles.present(room: .huggingFace, kinds: [.papers]) == [],
      "papers alone draw no tiles — All and Papers would be the same list (§805)")
check(RoomKindTiles.present(room: .github, kinds: [.pullRequests], hasUnkinded: true) == [.all, .pullRequests],
      "one kind beside All-only rows draws its tile — Activity plus pull requests narrows (§822)")
check(RoomKindTiles.present(room: .github, kinds: [.pullRequests], hasUnkinded: false) == [],
      "one kind that IS the whole room draws nothing — §805")
check(RoomKindTiles.present(room: .github, kinds: [], hasUnkinded: true) == [],
      "no kind at all draws nothing, however many All-only rows")
check(RoomKindTiles.present(room: .huggingFace, kinds: [.papers, .models]) == [.all, .models, .papers],
      "Hugging Face keeps Models · Datasets · Papers order")
check(RoomKindTiles.present(room: .appStoreConnect, kinds: [.builds, .reviews, .versions]) == [.all, .versions, .reviews, .builds],
      "App Store Connect keeps Versions · Reviews · Builds order")
check(RoomKindTiles.present(room: .appStoreConnect, kinds: [.builds, .models]) == [],
      "a kind from another room never makes up the second tile")

// ── PostHog: the metric/milestone trap, silence All only ────────────────
let ph = RoomKindTiles.Census(room: .posthog, refs: [])
func pk(_ ref: String?) -> T? { ph.kind(ref: ref, url: nil, tags: []) }
check(pk("posthog:metric:signup") == .metrics, "a watched metric is Metrics")
check(pk("posthog:annotation:42") == .annotations, "an annotation is Annotations")
check(pk("posthog:milestone:signup:1000") == .milestones, "a milestone is Milestones, never Metrics (prefix trap)")
check(pk("posthog:silence:signup:2026-09-18") == nil, "a silence alert is All only")
check(pk("posthog:metrics:x") == nil, "a ref that only STARTS like a kind claims nothing")

// ── L2BEAT and Walletbeat: one News, one Revisions ──────────────────────
let l2 = RoomKindTiles.Census(room: .l2beat, refs: [])
func lk(_ ref: String?) -> T? { l2.kind(ref: ref, url: nil, tags: []) }
check(lk("l2beat:chain:base") == .chains, "a watched chain is Chains")
check(lk("l2beat:news:base:2026-09-01:stage-1") == .news, "a milestone or incident is News")
check(lk("l2beat:rev:base:stage:2026-09-01") == .revisions, "a rating change is Revisions")
check(lk("walletbeat:news:x") == nil, "a Walletbeat ref claims nothing in L2BEAT")
let wb = RoomKindTiles.Census(room: .walletbeat, refs: [])
func wk(_ ref: String?) -> T? { wb.kind(ref: ref, url: nil, tags: []) }
check(wk("walletbeat:wallet:rabby") == .wallets, "a watched wallet is Wallets")
check(wk("walletbeat:news:rabby-incident") == .news, "an incident is News — the SAME case as L2BEAT's")
check(wk("walletbeat:rev:rabby:appIsolation:FAIL:2026-07-20") == .revisions, "a rating change is Revisions — the SAME case as L2BEAT's")
check(wk("l2beat:chain:base") == nil, "an L2BEAT ref claims nothing in Walletbeat")
check(RoomKindTiles.present(room: .walletbeat, kinds: [.revisions, .wallets, .news]) == [.all, .wallets, .news, .revisions],
      "Walletbeat keeps Wallets · News · Revisions order")
check(RoomKindTiles.present(room: .l2beat, kinds: [.wallets, .news]) == [],
      "Walletbeat's Wallets never make up L2BEAT's second tile")
// ── Splits: refs decide, dust never landed so nothing to test here ───────
let sx = RoomKindTiles.Census(room: .splits, refs: [])
check(RoomKindTiles.Room(source: "Splits") == .splits, "Splits resolves from its source")
check(sx.kind(ref: "splits:account:0xabc", url: nil, tags: []) == .accounts, "an account row is Accounts")
check(sx.kind(ref: "splits:tx:1", url: nil, tags: ["Transfer", "Waiting"]) == .queue, "a proposal waiting on signatures is Queue")
check(sx.kind(ref: "splits:tx:2", url: nil, tags: ["Transfer"]) == .activity, "a transaction that went through is Activity")
check(sx.kind(ref: "splits:tx:3", url: nil, tags: ["Transfer", "Not executed"]) == .activity, "a proposal that failed is Activity, never Queue")
check(sx.kind(ref: "splits:contact:0xabc", url: nil, tags: []) == nil, "anything else is All only")
check(sx.kind(ref: nil, url: nil, tags: []) == nil, "a row with no ref claims nothing")
check(RoomKindTiles.present(room: .splits, kinds: [.activity, .queue, .accounts]) == [.all, .accounts, .queue, .activity],
      "Splits: All · Accounts · Queue · Activity")
check(RoomKindTiles.present(room: .splits, kinds: [.activity, .accounts]) == [.all, .accounts, .activity],
      "Splits with nothing waiting: no Queue tile")
check(RoomKindTiles.present(room: .splits, kinds: [.accounts]) == [],
      "a team with accounts and no activity draws no tiles (§805)")

// ── prd §911: the twelve rooms, one census each ─────────────────────────
let polar = RoomKindTiles.Census(room: .polar, refs: [])
check(polar.kind(ref: "polar:order:1", url: nil, tags: ["Sale"]) == .sales, "Polar: an order is Sales")
check(polar.kind(ref: "polar:subscription:1:active", url: nil, tags: ["Subscription", "New"]) == .subscriptions, "Polar: a subscription")
check(polar.kind(ref: "polar:refund:1", url: nil, tags: ["Refund"]) == nil, "Polar: a refund is All only (four tiles, one row)")
check(polar.kind(ref: "polar:dispute:1:opened", url: nil, tags: ["Dispute", "Opened"]) == .disputes, "Polar: a dispute")
check(polar.kind(ref: "demo:polar:1", url: nil, tags: ["Sale", "New subscriber"]) == .sales, "Polar: the demo's row sorts by its tag")
check(polar.kind(ref: "polar:silence:1", url: nil, tags: []) == nil, "Polar: anything else is All only")
check(RoomKindTiles.present(room: .polar, kinds: [.disputes, .sales, .subscriptions])
      == [.all, .sales, .subscriptions, .disputes], "Polar: All · Sales · Subscriptions · Disputes")
let dodo = RoomKindTiles.Census(room: .dodoPayments, refs: [])
check(dodo.kind(ref: "dodopayments:payment:1", url: nil, tags: ["Payment"]) == .sales, "Dodo: a payment is Sales")
check(dodo.kind(ref: "dodopayments:subscription:1:failed", url: nil, tags: ["Subscription", "Failed"]) == .subscriptions, "Dodo: a subscription")
check(dodo.kind(ref: "dodopayments:refund:1", url: nil, tags: ["Refund"]) == nil, "Dodo: a refund is All only")
check(dodo.kind(ref: "dodopayments:dispute:1:closed", url: nil, tags: ["Dispute", "Won"]) == .disputes, "Dodo: a dispute")
let gl = RoomKindTiles.Census(room: .gitlab, refs: [])
check(gl.kind(ref: "gitlab:mr:61", url: nil, tags: []) == .mergeRequests, "GitLab: an MR")
check(gl.kind(ref: "gitlab:issue:58", url: nil, tags: []) == .issues, "GitLab: an issue")
check(gl.kind(ref: nil, url: nil, tags: ["Issue"]) == nil, "GitLab: the ref decides, never a tag")
let rad = RoomKindTiles.Census(room: .radicle, refs: [])
check(rad.kind(ref: "radicle:patch:rad:1:abc:merged", url: nil, tags: ["Patch", "Merged"]) == .patches, "Radicle: a patch")
check(rad.kind(ref: "radicle:issue:rad:1:abc:opened", url: nil, tags: ["Issue", "Opened"]) == .issues, "Radicle: an issue")
check(rad.kind(ref: "demo:radicle:1", url: nil, tags: ["Patch", "Proposed"]) == .patches, "Radicle: the demo's row sorts by its tag")
let sen = RoomKindTiles.Census(room: .sentry, refs: [])
check(sen.kind(ref: "sentry:issue:1", url: nil, tags: ["Issue"]) == .errors, "Sentry: a new issue is Errors")
check(sen.kind(ref: "sentry:regressed:1:2", url: nil, tags: ["Regression"]) == .regressions, "Sentry: a regression")
check(sen.kind(ref: "sentry:escalating:1:1", url: nil, tags: ["Regression"]) == .regressions, "Sentry: an escalation is Regressions")
check(sen.kind(ref: "sentry:ongoing:1:1", url: nil, tags: []) == nil, "Sentry: another crossing is All only")
let ver = RoomKindTiles.Census(room: .vercel, refs: [])
check(ver.kind(ref: "vercel:deploy:1", url: nil, tags: ["Deploy"]) == .deploys, "Vercel: a deploy")
check(ver.kind(ref: "vercel:deploy:2", url: nil, tags: ["Build failure"]) == .failed, "Vercel: a build failure is Failed")
check(ver.kind(ref: "vercel:other:2", url: nil, tags: ["Build failure"]) == nil, "Vercel: only a deploy row sorts")
let pd = RoomKindTiles.Census(room: .pagerduty, refs: [])
check(pd.kind(ref: "pagerduty:incident:1", url: nil, tags: ["Incident"]) == .incidents, "PagerDuty: triggered")
check(pd.kind(ref: "pagerduty:resolved:1", url: nil, tags: ["Resolved"]) == .resolved, "PagerDuty: resolved")
let npmc = RoomKindTiles.Census(room: .npm, refs: [])
let pypic = RoomKindTiles.Census(room: .pypi, refs: [])
check(npmc.kind(ref: "npm:release:left-pad:1.3.0", url: nil, tags: ["Release"]) == .releases, "npm: a release")
check(npmc.kind(ref: "npm:deprecated:left-pad", url: nil, tags: ["Deprecated"]) == .deprecations, "npm: a deprecation")
check(pypic.kind(ref: "pypi:release:requests:2.32.0", url: nil, tags: ["Release"]) == .releases, "PyPI: a release")
check(npmc.kind(ref: "pypi:release:requests:2.32.0", url: nil, tags: ["Release"]) == nil, "npm's room never claims a PyPI row")
let awsc = RoomKindTiles.Census(room: .aws, refs: [])
check(awsc.kind(ref: "aws:alarm:prod:ALARM:1", url: nil, tags: ["Alarme"]) == .alarms, "AWS: the ref decides under a localized tag")
check(awsc.kind(ref: "aws:pipeline:1", url: nil, tags: ["Deploy", "Failed"]) == .deploys, "AWS: a pipeline is Deploys")
check(awsc.kind(ref: "aws:costanomaly:2026-09-24", url: nil, tags: ["Cost"]) == .costs, "AWS: a cost anomaly")
check(awsc.kind(ref: "demo:aws:1", url: nil, tags: ["Alarm"]) == .alarms, "AWS: the demo's row sorts by its tag")
let cur = RoomKindTiles.Census(room: .cursor, refs: [])
check(cur.kind(ref: "cursor:agent:1", url: nil, tags: ["Agent run", "PR"]) == .pullRequests, "Cursor: a run with a PR")
check(cur.kind(ref: "cursor:agent:2", url: nil, tags: ["Agent run", "Failed"]) == .failed, "Cursor: a failed run")
check(cur.kind(ref: "cursor:agent:3", url: nil, tags: ["Agent run", "Expired", "PR"]) == .failed, "Cursor: Failed wins over PR")
check(cur.kind(ref: "cursor:agent:4", url: nil, tags: ["Agent run"]) == nil, "Cursor: a finished run is All only")
let hk = RoomKindTiles.Census(room: .appleHealth, refs: [])
check(hk.kind(ref: "hkworkout:1", url: nil, tags: []) == .workouts, "Health: a workout")
check(hk.kind(ref: "hksleep:2026-09-24", url: nil, tags: []) == .sleep, "Health: a night")
check(hk.kind(ref: "hkmood:ABC", url: nil, tags: []) == .mood, "Health: a mood")
check(hk.kind(ref: "demo:health:1", url: nil, tags: []) == nil, "Health: the demo's rows are All only")

// ── Open disputes ───────────────────────────────────────────────────────
let d1 = "https://dashboard.stripe.com/disputes/dp_1"
let d2 = "https://dashboard.stripe.com/disputes/dp_2"
check(RoomKindTiles.openDisputes([(d1, ["Dispute"], "Dispute opened · $10.00")]) == 1, "an opened dispute is open")
check(RoomKindTiles.openDisputes([(d1, ["Dispute"], "Dispute opened · $10.00"),
                                  (d1, ["Dispute", "Won"], "Dispute won · $10.00")]) == 0,
      "a dispute with its closing row is not open")
check(RoomKindTiles.openDisputes([(d1, ["Dispute"], "Dispute opened · $10.00"),
                                  (d2, ["Dispute"], "Dispute closed · $5.00")]) == 1,
      "a closing row for ANOTHER dispute closes nothing")
check(RoomKindTiles.openDisputes([(d1, ["Payout"], "Dispute opened")]) == 0, "only Dispute rows count")

// ── Tiles: All first, two kinds or none ─────────────────────────────────
check(RoomKindTiles.present(room: .safe, kinds: []) == [], "no kinds, no tiles")
check(RoomKindTiles.present(room: .safe, kinds: [.queue]) == [],
      "ONE kind draws no tiles — All and Queue would be the same list (§805)")
check(RoomKindTiles.present(room: .safe, kinds: [.permissions, .queue]) == [.all, .queue, .permissions],
      "two kinds: All first, then the room's own order")
check(RoomKindTiles.present(room: .stripe, kinds: [.disputes, .payouts, .payments]) == [.all, .payments, .payouts, .disputes],
      "Stripe keeps Payments · Payouts · Disputes order")
check(RoomKindTiles.present(room: .github, kinds: [.releases, .issues, .queue]) == [.all, .issues, .releases],
      "a kind from another room is never drawn")
check(RoomKindTiles.present(room: .github, kinds: [.all, .issues]) == [],
      "All is not a kind — it cannot make up the second tile")

// ── Resolve and allow ───────────────────────────────────────────────────
let present: [T] = [.all, .queue, .activity]
check(RoomKindTiles.resolve(.queue, present: present) == .queue, "a present pick stands")
check(RoomKindTiles.resolve(.permissions, present: present) == .all, "a pick whose kind has gone falls back to All")
check(RoomKindTiles.resolve(.queue, present: []) == .all, "no tiles at all means All")
check(RoomKindTiles.allows(.all, kind: nil) && RoomKindTiles.allows(.all, kind: .queue), "All holds every row")
check(RoomKindTiles.allows(.queue, kind: .queue), "a tile holds its kind")
check(!RoomKindTiles.allows(.queue, kind: .activity) && !RoomKindTiles.allows(.queue, kind: nil),
      "a tile holds nothing else — the All-only rows included")

// ── Words ───────────────────────────────────────────────────────────────
for tile in T.allCases {
    check(!tile.label.isEmpty && tile.label.first!.isUppercase
          && tile.label.dropFirst().split(separator: " ").allSatisfy { $0.lowercased() == $0 },
          "\(tile.rawValue): label is sentence case (\(tile.label))")
    check(!tile.summary.isEmpty, "\(tile.rawValue): has a summary")
}

print(failures == 0 ? "room-kind-tiles-selftest: all checks ✓" : "room-kind-tiles-selftest: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

if ! swiftc -Onone -o "$TMP/run" "$KINDS" "$TAG" "$LINKS" "$TMP/main.swift" 2>"$TMP/build.log"; then
  cat "$TMP/build.log"; echo "✗ room-kind-tiles-selftest: compile failed"; exit 1
fi
"$TMP/run"
