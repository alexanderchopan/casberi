#!/bin/zsh
# Casberi Frames-devnet frame-transaction self-test — the SHIPPED encoder for
# EIP-8141 chain 81410 (2026-09-01, prd §548):
#
#   Casberi/Casberi/Model/FramesTransaction.swift  — the 7-field envelope
#   Casberi/Casberi/Model/RLP.swift                — shared with vibenet/Hegotá
#
# Both Foundation-only BY DESIGN and compiled WHOLE AND UNMODIFIED here.
#
# WHY A SECOND HARNESS RATHER THAN A PARAMETER ON HEGOTÁ'S. Both chains run
# ethrex, both serve type 0x06, both call it EIP-8141 — and they hash
# DIFFERENT LISTS. Hegotá: eleven flat fields with keyed nonces and recent-root
# references. Frames: seven, with the three fee fields nested. Signing with the
# wrong one produces a well-formed signature over a different digest that
# recovers to a real address. The build is happy, the screen is right, and the
# money goes somewhere else — the `safetx-selftest.sh` argument, on a chain
# that cannot be reached from a harness.
#
# THE FIXTURES ARE REAL TRANSACTIONS. Measured 2026-09-01 against the whole
# type-0x06 population of this chain (5 transactions — it opened 2026-08-28):
# the encoder re-encodes 5/5 byte-identically, their keccak matches the RPC's
# own `hash` 5/5, and 5/5 signatures recover to their declared signer against
# the elided preimage. Two are pinned below, chosen to DISCRIMINATE: one
# carries a non-zero nonce (the only one that does), the other a different
# sender, fee ceiling and gas pair. A third is synthetic with every field
# distinct, because five near-identical real transactions cannot catch a field
# swap — the lesson `safetx-selftest.sh` paid for, where all five spec vectors
# left the same fields at zero and swapping two reproduced every hash.
#
# Pure, local, deterministic — no network, no simulator, no key.
set -euo pipefail
# Absolute, captured BEFORE the cd below: the mutation fan-out re-invokes this
# script and `$0` is relative to the caller's cwd.
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")/.."

# --- the mutation child ------------------------------------------------------
# One mutation, in its own scratch directory so a concurrent sibling cannot see
# it. Prints ONE line the parent classifies; never exits the whole run, because
# a second broken mutation costs another full pass to discover (`verify.sh`'s
# 2026-08-19 lesson — report ALL failures, not the first).
if [[ "${1:-}" == "--mutate" ]]; then
  SRCDIR="$2"; MID="$3"
  MLABEL="$(cat "$SRCDIR/mut/$MID.label")"
  MFILE="$(cat "$SRCDIR/mut/$MID.file")"
  MW="$(mktemp -d)"
  trap 'rm -rf "$MW"' EXIT
  cp "$SRCDIR"/*.swift "$MW/"
  mkdir -p "$MW/m"; cp "$SRCDIR/m/main.swift" "$MW/m/"
  set +e
  python3 - "$MW/$MFILE" "$SRCDIR/mut/$MID.from" "$SRCDIR/mut/$MID.to" <<'PYM'
import sys, io
p, fa, fb = sys.argv[1], sys.argv[2], sys.argv[3]
src = io.open(p, encoding="utf-8").read()
a = io.open(fa, encoding="utf-8").read()
b = io.open(fb, encoding="utf-8").read()
if a not in src:
    sys.exit(2)
io.open(p, "w", encoding="utf-8").write(src.replace(a, b, 1))
PYM
  applied=$?
  set -e
  # A mutation that matches NOTHING is stale and has silently been testing the
  # shipped code — the failure mode this check exists to prevent in itself.
  if (( applied == 2 )); then echo "STALE|$MID|$MLABEL"; exit 0; fi
  if ( cd "$MW" && swiftc -O -o m/run2 FramesTransaction.swift RLP.swift Keccak256.swift FramesMoney.swift FramesSection.swift FramesReading.swift m/main.swift 2>/dev/null ) \
     && "$MW/m/run2" >/dev/null 2>&1; then
    echo "SURVIVED|$MID|$MLABEL"; exit 0
  fi
  echo "CAUGHT|$MID|$MLABEL"; exit 0
fi

TX="Casberi/Casberi/Model/FramesTransaction.swift"
RLPF="Casberi/Casberi/Model/RLP.swift"
KC="Casberi/Casberi/Model/Keccak256.swift"
MONEY="Casberi/Casberi/Model/FramesMoney.swift"
SECT="Casberi/Casberi/Model/FramesSection.swift"
READ="Casberi/Casberi/Model/FramesReading.swift"
KEY="Casberi/Casberi/Model/FramesKey.swift"
SEND="Casberi/Casberi/Model/FramesSend.swift"
BRIDGE="Casberi/Casberi/Model/FramesBridge.swift"
for f in "$TX" "$RLPF" "$KC" "$MONEY" "$SECT" "$READ" "$KEY" "$SEND" "$BRIDGE"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

strip_comments() { sed -E 's://.*$::' "$1" | sed -E 's:/\*.*\*/::'; }
strip_comments "$TX" > "$WORK/tx.nc"
strip_comments "$KEY" > "$WORK/key.nc"
strip_comments "$SEND" > "$WORK/send.nc"
strip_comments "$BRIDGE" > "$WORK/bridge.nc"
strip_comments "$READ" > "$WORK/read.nc"

# --- drift guards -----------------------------------------------------------
# Read from a COMMENT-STRIPPED copy: this file DOCUMENTS Hegotá's envelope by
# printing it in the type doc, so a raw grep for the fields it must NOT have
# fires on the prose explaining the difference.

# THE DIVERGENCE, both directions. Hegotá's three fields must never appear in
# the encoder, or this file has been "unified" with a chain that hashes a
# different list.
for forbidden in nonceKeys nonceSequence recentRootReferences; do
  if grep -qF "$forbidden" "$WORK/tx.nc"; then
    echo "✗ FramesTransaction names \`$forbidden\` — that is Hegotá's envelope, and this chain implements neither"; exit 1
  fi
done
grep -qF 'static let chainID: UInt64 = 81410' "$WORK/tx.nc" \
  || { echo "✗ FramesTransaction no longer pins chain 81410"; exit 1; }

# --- the key ----------------------------------------------------------------
# Device-only and non-syncing. Worthless money is not a reason to let a signing
# key ride a backup onto another device. `WhenUnlockedThisDeviceOnly`, not
# `WhenPasscodeSet` — §525 measured the latter failing -25308 on a real signed
# Catalyst run, because that class needs an interactive session to ESTABLISH
# and this key's write path never touches biometry.
grep -qF 'kSecAttrAccessibleWhenUnlockedThisDeviceOnly' "$WORK/key.nc" \
  || { echo "✗ FramesKey no longer pins a ThisDeviceOnly accessibility"; exit 1; }
grep -qF 'kSecAttrSynchronizable' "$WORK/key.nc" \
  || { echo "✗ FramesKey no longer names kSecAttrSynchronizable"; exit 1; }
# ITS OWN SERVICE. One key signing both devnets means a nonce read from one
# chain can be spent on the other and a "Remove this key" empties both seats;
# reaching for the Safe signer's would let a devnet bug touch real money.
grep -qF 'casberi-frames-signer' "$WORK/key.nc" \
  || { echo "✗ FramesKey no longer uses its own keychain service"; exit 1; }
for foreign in casberi-hegota-signer casberi-dev-signer; do
  if grep -qF "$foreign" "$WORK/key.nc"; then
    echo "✗ FramesKey is reaching for \`$foreign\` — that key belongs to another chain"; exit 1
  fi
done
grep -qF 'Failure.selfCheck' "$WORK/key.nc" \
  || { echo "✗ FramesKey no longer recovers its own signature before returning it"; exit 1; }
# §531's three-state adoption, transplanted whole. Two answers where the world
# has three is how a LOCKED DEVICE gets read as "these bytes are junk" and this
# phone's real account is deleted.
grep -qF 'case unreadable(OSStatus)' "$WORK/key.nc" \
  || { echo "✗ FramesKey's adoption is no longer three-state — an unreadable keychain will be read as unusable bytes and the real key deleted"; exit 1; }
grep -qF 'adoptStoredKey' "$WORK/key.nc" \
  || { echo "✗ FramesKey no longer adopts an existing key — replacing it strands whatever the chain already gave that account"; exit 1; }
grep -qF 'kSecAttrSynchronizableAny' "$WORK/key.nc" \
  || { echo "✗ FramesKey.delete no longer matches every synchronizability — a survivor becomes the next duplicate"; exit 1; }
python3 - "$WORK/key.nc" <<'PYADOPT' || exit 1
import sys, io
src = io.open(sys.argv[1], encoding="utf-8").read()
start = src.find("switch adoptStoredKey() {")
if start < 0:
    print("✗ create() no longer switches over the adoption outcome"); sys.exit(1)
arm = src[start:src.find("case .unusableBytes", start)]
if "delete()" in arm:
    print("✗ create() deletes the keychain item on an outcome that is not proven-unusable bytes")
    sys.exit(1)
sys.exit(0)
PYADOPT
echo "  ok   drift guards: the key is this chain's own, device-only, and survives a reinstall"

# --- the send path ----------------------------------------------------------
# ONE write verb, counted by OCCURRENCE not by line — `grep -c` counts lines,
# and a second call appended to the same line survives that guard (the
# `SafeSigner` lesson).
sends=$(grep -o 'eth_sendRawTransaction' "$WORK/send.nc" | wc -l | tr -d ' ')
[[ "$sends" == "1" ]] \
  || { echo "✗ FramesSend names eth_sendRawTransaction $sends times — this app makes exactly one signed write to this chain"; exit 1; }
for verb in eth_sendTransaction personal_sign eth_sign; do
  if grep -qF "$verb" "$WORK/send.nc"; then
    echo "✗ FramesSend reaches \`$verb\` — the key never leaves this phone and nothing else signs"; exit 1
  fi
done
# THE MEASURED DIVERGENCE FROM HEGOTÁ, and the one that fails silently. All 5
# type-0x06 transactions on this chain write the signer IN FULL: re-encoding
# matches 5/5 literal and 0/5 empty. Hegotá's `signer: Data()` — "the sender" —
# has never been used here, and it changes the hash the node recomputes, so
# every send comes back "invalid frame transaction signature".
python3 - "$WORK/send.nc" <<'PYSIGNER' || exit 1
import sys, io, re
src = io.open(sys.argv[1], encoding="utf-8").read()
start = src.find("static func sendValue(")
if start < 0:
    print("✗ FramesSend.sendValue is gone"); sys.exit(1)
body = src[start:]
if re.search(r"signer:\s*Data\(\)", body):
    print("✗ FramesSend writes an EMPTY signer — that is Hegotá's convention and it has never been used on this chain; the node will refuse every send")
    sys.exit(1)
if not re.search(r"signer:\s*sender", body):
    print("✗ FramesSend no longer writes the signer literally"); sys.exit(1)
sys.exit(0)
PYSIGNER
# THE ENTRY MUST BE PRESENT WHEN THE DIGEST IS TAKEN — only its signature bytes
# are elided. Appending it after signing hashes `.list([])` instead of a
# one-entry list with a blank signature, so the node's recomputed sigHash never
# matches what this phone signed. §525 paid for this one on the other chain.
python3 - "$WORK/send.nc" <<'PYORDER' || exit 1
import sys, io
src = io.open(sys.argv[1], encoding="utf-8").read()
start = src.find("static func sendValue(")
body = src[start:]
seed = body.find("fields.signatures = [")
pre  = body.find("signingPreimage(fields)")
if seed < 0 or pre < 0:
    print("✗ FramesSend.sendValue no longer seeds a signature entry before hashing"); sys.exit(1)
if seed > pre:
    print("✗ FramesSend takes the digest BEFORE seeding the signature entry — it signs a different list than it broadcasts")
    sys.exit(1)
sys.exit(0)
PYORDER
# The prefix is refused BEFORE the biometric prompt, not after it (§530: a
# refusal that could be made before the prompt should be).
python3 - "$WORK/send.nc" <<'PYPREFIX' || exit 1
import sys, io
src = io.open(sys.argv[1], encoding="utf-8").read()
body = src[src.find("static func sendValue("):]
guard = body.find("prefixWithinBudget")
sign  = body.find("FramesKey.sign")
if guard < 0:
    print("✗ FramesSend no longer checks the validation prefix — the node's own refusal for this names no remedy"); sys.exit(1)
if sign >= 0 and guard > sign:
    print("✗ FramesSend checks the prefix AFTER asking for the signature — the prompt is spent on a transaction already known to be invalid")
    sys.exit(1)
sys.exit(0)
PYPREFIX
# A refusal must reach the person in the NODE'S OWN WORDS (§530), which means
# the body of a non-200 has to survive. `postJSON` returns nil for any non-200
# and `postJSONStatus` drops the body.
# BOTH writes, not just one. A single-occurrence guard passes while
# `claimFaucet` alone regresses to `postJSON` — and that is §531's bug exactly:
# the faucet's measured hourly rate limit becomes indistinguishable from a dead
# host, and the sheet's "already claimed this hour" branch becomes unreachable.
# Found by mutating this guard rather than by reading it.
bodies=$(grep -o 'postJSONBody' "$WORK/send.nc" | wc -l | tr -d ' ')
[[ "$bodies" == "2" ]] \
  || { echo "✗ FramesSend reads a refusal body $bodies time(s) — both the faucet claim and the broadcast must keep the far end's own words, or a refusal becomes one placeholder sentence"; exit 1; }
if grep -qE '[^B]postJSON\(|IngestSupport\.postJSON\(' "$WORK/send.nc"; then
  echo "✗ FramesSend reaches a helper that drops the body on a non-200 — the reason is the thing worth having here"; exit 1
fi
# ONE faucet classifier for both devnets. A second copy drifts, and then the
# two seats disagree about what "already claimed this hour" looks like.
grep -qF 'HegotaFaucetVerdict' "$WORK/send.nc" \
  || { echo "✗ FramesSend no longer shares the faucet classifier — a forked copy drifts from the shape it classifies"; exit 1; }
# Never the other chain's hosts.
if grep -qF 'hegota.ethrex.xyz' "$WORK/send.nc"; then
  echo "✗ FramesSend reaches a Hegotá host"; exit 1
fi
echo "  ok   drift guards: one signed write, a literal signer, the entry seeded before the digest"

# --- the read side ----------------------------------------------------------
# A frame's execution budget is `gasLimit` here and `executionGasLimit` on
# Hegotá. Reading only one spelling gives a nil budget on the other chain, and
# a frame drawn with a nil budget looks like a frame that had none.
grep -qF 'hexInt(f["gasLimit"])' "$WORK/read.nc" \
  || { echo "✗ FramesRead no longer reads this chain's own gas spelling"; exit 1; }
# `stateGasUsed` is OPTIONAL and must never be defaulted to zero: `0x0` is the
# discriminator that tells a missing STATE budget apart from a too-small
# EXECUTION budget, so reading an absent field as zero asserts that diagnosis
# every time. Measured 2026-09-01: absent on all 5 transactions here.
if grep -qE 'stateGasUsed.*\?\?\s*0' "$WORK/read.nc"; then
  echo "✗ FramesRead defaults stateGasUsed to zero — an absent field would be reported as a state starvation"; exit 1
fi
python3 - "$WORK/read.nc" <<'PYSTARVE' || exit 1
import sys, io
src = io.open(sys.argv[1], encoding="utf-8").read()
body = src[src.find("static func starvation("):]
if "guard let state = outcome.stateGasUsed else { return nil }" not in body:
    print("✗ FramesRead.starvation no longer refuses to judge without a reported stateGasUsed")
    sys.exit(1)
sys.exit(0)
PYSTARVE
echo "  ok   drift guards: this chain's gas spelling, and an absent stateGasUsed is never read as zero"

# --- the scope strip's absences, which are MEASUREMENTS ---------------------
# Read from a COMMENT-STRIPPED copy: this file documents the absent scopes by
# NAMING them, so a raw grep fires on the prose explaining why they are gone.
strip_comments "$SECT" > "$WORK/sect.nc"
# `nonces` and `coins` are absent because THIS CHAIN CANNOT FILL THEM — it
# implements no keyed nonces (measured over its whole type-0x06 population)
# and has no UTXO vault. A case appearing here is either a chain upgrade
# nobody re-measured or a scope copied across from Hegotá that can only ever
# be empty, and §83 bans the empty chip.
for absent in nonces coins accounts permissions; do
  if grep -qE "case $absent" "$WORK/sect.nc"; then
    echo "✗ FramesSection grew a \`$absent\` scope — Hegotá has it and this chain cannot fill it; re-measure before adding one"; exit 1
  fi
done
echo "  ok   drift guards: the strip keeps the four scopes this chain can fill"

# --- the moments (2026-09-01) -----------------------------------------------
# Five small things that are all one class: a room says what JUST HAPPENED, and
# every one of them fails as a false claim rather than as a missing animation.
# Read from COMMENT-STRIPPED copies throughout — all three files document these
# rules by naming what they must not do (the Obsidian/Cursor lesson).
CARD="Casberi/Casberi/Screens/FramesRoomCard.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
for f in "$CARD" "$FEED"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done
strip_comments "$CARD" > "$WORK/card.nc"
strip_comments "$FEED" > "$WORK/feed.nc"

# ARRIVALS ARE SEEDED SILENTLY ON THE FIRST READ. Without the seed, the first
# sweep after launch reports the whole history as news and every landed row
# washes at once — the §306 "did you already know?" failure with an animation
# on it, and the exact bug Hyperliquid shipped (22 positions landing as 22
# "Opened" rows on the day somebody started watching).
python3 - "$WORK/bridge.nc" <<'PYSEED' || exit 1
import sys, io
src = io.open(sys.argv[1], encoding="utf-8").read()
i = src.find("private func noteArrivals(")
if i < 0:
    print("✗ FramesLiveState no longer notes arrivals — nothing can tell a landing apart from a history"); sys.exit(1)
body = src[i:src.find("private func seedArrivals(", i)]
if "guard seeded else" not in body:
    print("✗ noteArrivals no longer seeds silently on the first read — the first sweep of a session would report the whole history as having just landed")
    sys.exit(1)
sys.exit(0)
PYSEED
# The demo must SEED its fixture, never note it: five transactions installed in
# one call are not five transactions arriving, and a demo that celebrates its
# own seed does it in the one place somebody is being SHOWN the app.
python3 - "$WORK/bridge.nc" <<'PYDEMO' || exit 1
import sys, io
src = io.open(sys.argv[1], encoding="utf-8").read()
i = src.find("func installDemo(")
if i < 0:
    print("✗ FramesLiveState.installDemo is gone"); sys.exit(1)
body = src[i:i + 600]
if "seedArrivals(in: fixture)" not in body:
    print("✗ installDemo no longer seeds arrivals — the demo would report its own fixture as having just landed")
    sys.exit(1)
if "noteArrivals(in: fixture)" in body:
    print("✗ installDemo NOTES its fixture as arrivals — every seeded row would wash as news")
    sys.exit(1)
sys.exit(0)
PYDEMO

# THE FIRST SETTLE IS NEVER CLAIMED RETROACTIVELY. An account whose nonce is
# already above zero sent its first transaction before this build existed, so
# the moment has been had and cannot be given back. Both halves: the seed must
# exist, and it must be gated on there being nothing pending, or a send made in
# THIS session could be eaten by the seed that runs before it.
python3 - "$WORK/bridge.nc" <<'PYFIRST' || exit 1
import sys, io
src = io.open(sys.argv[1], encoding="utf-8").read()
i = src.find("private func seedFirstSettleIfAlreadySent(")
if i < 0:
    print("✗ FramesLiveState no longer seeds the first-settle moment — it would fire retroactively for an account that has been sending for weeks")
    sys.exit(1)
body = src[i:i + 700]
if "pending.isEmpty" not in body:
    print("✗ the first-settle seed is no longer gated on nothing being pending — it could eat a real first settle")
    sys.exit(1)
if "nonce > 0" not in body:
    print("✗ the first-settle seed no longer reads the nonce — the count of transactions this account signed is the only evidence it has already sent")
    sys.exit(1)
if "seedFirstSettleIfAlreadySent(read)" not in src:
    print("✗ nothing calls the first-settle seed"); sys.exit(1)
sys.exit(0)
PYFIRST
echo "  ok   drift guards: arrivals seed silently, and the first settle is never claimed retroactively"

# THE TIE IS A DIAL, NEVER A SECOND SOURCE OF TRUTH. `joinProgress` may hide a
# join the run declares and must never draw one it does not — otherwise the
# send preview stops being a picture of what the signer produces and becomes a
# picture of what the toggle says, on the control that decides whether a failed
# batch leaves money with a stranger.
python3 - "$WORK/card.nc" <<'PYTIE' || exit 1
import sys, io
src = io.open(sys.argv[1], encoding="utf-8").read()
i = src.find("if cell.joinedToNext, !last")
if i < 0:
    print("✗ the strip no longer gates its tie on the run's own join — `joinProgress` would be free to invent one")
    sys.exit(1)
if "joinProgress > 0.01" not in src[i:i + 200]:
    print("✗ the tie no longer honours joinProgress"); sys.exit(1)
# One door from `flags` into the drawing. A second reading of the flag would
# make `joinProgress: 0` stop being the non-atomic run.
if src.count("joinedToNext") != 1:
    print("✗ FramesRoomCard reads `joinedToNext` more than once — the preview's licence is that flags reach this drawing through exactly one door")
    sys.exit(1)
if "startsBatch" in src or "atomicFlag" in src:
    print("✗ FramesRoomCard reads the atomic flag directly — it must come through FramesFrameRow.joinedToNext alone")
    sys.exit(1)
sys.exit(0)
PYTIE
# BOTH HALVES OF THE PREVIEW'S LICENCE, because either alone is a lie: the run
# must be built JOINED (so the tie has something to travel over in both
# directions), and the toggle must reach the strip as `joinProgress` (so the
# picture still answers the control).
python3 - "$WORK/feed.nc" <<'PYPREV' || exit 1
import sys, io
src = io.open(sys.argv[1], encoding="utf-8").read()
i = src.find("private func framesPreviewRun(")
if i < 0:
    print("✗ framesPreviewRun is gone"); sys.exit(1)
body = src[i:src.find("\n    }", i)]
if "FramesTransaction.stitched(" not in body:
    print("✗ the send preview no longer builds its run with the shipped encoder — it would promise a shape the signer does not produce")
    sys.exit(1)
if "atomic: true" not in body:
    print("✗ framesPreviewRun no longer asks for the JOINED shape — the tie has nothing to travel over and the toggle's own picture snaps")
    sys.exit(1)
j = src.find("preview: { legs, atomic in")
if j < 0:
    print("✗ the Frames stitch no longer hands the sheet a preview"); sys.exit(1)
if "joinProgress: atomic ? 1 : 0" not in src[j:j + 400]:
    print("✗ the preview no longer dials the tie from the toggle — a run built joined would draw ties with all-or-nothing OFF")
    sys.exit(1)
sys.exit(0)
PYPREV
echo "  ok   drift guards: the tie is a dial over the run's own joins, and the preview declares both halves"

# EVERY DRAWING IN THIS ROOM ARRIVES. Both are a `Canvas`, which is why
# `design-motion-audit` — which looks for proportional shapes and
# GeometryReader — cannot see them, and why a room where everything else
# arrives kept two that simply were. Reduce Motion is `chartWipe`'s own
# contract, so requiring the shared component is requiring the guarantee.
for drawing in FramesSequenceStrip FramesMovementBars; do
  python3 - "$WORK/card.nc" "$drawing" <<'PYENTRY' || exit 1
import sys, io
src, name = io.open(sys.argv[1], encoding="utf-8").read(), sys.argv[2]
i = src.find("struct %s: View" % name)
if i < 0:
    print("✗ %s is gone" % name); sys.exit(1)
body = src[i:src.find("\nstruct ", i + 1)]
if "chartWipe(reduceMotion:" not in body:
    print("✗ %s no longer arrives — a Canvas is invisible to design-motion-audit, so nothing else will say so" % name)
    sys.exit(1)
sys.exit(0)
PYENTRY
done
# A NEW TRANSACTION IS A NEW DRAWING. A chart entrance is one-shot on appear,
# which is right for opening a room and wrong for the moment this room exists
# for — without the key, a send you just made lands by the chart redrawing
# silently between two frames.
grep -qF '.id(newestHash)' "$WORK/card.nc" \
  || { echo "✗ the room's charts are no longer keyed on the newest transaction — a settle would redraw silently"; exit 1; }
echo "  ok   drift guards: both Canvas drawings arrive, and a settle redraws them"

# --- the sheets (prd §548 ninth follow-up) ----------------------------------
# Every list in this room was a `Button` wired to an empty closure — §83's dead
# control multiplied by every transaction on screen. These guards are the
# wiring, and each failure is invisible: a row that highlights and does
# nothing, a sheet that re-derives a rule the model already owns, or a control
# that names the wrong address.
SHEETS="Casberi/Casberi/Screens/FramesSheets.swift"
[[ -f "$SHEETS" ]] || { echo "✗ $SHEETS not found"; exit 1; }
strip_comments "$SHEETS" > "$WORK/sheets.nc"

# THE ROWS REALLY OPEN. The closure was `{ _ in }` for as long as the room has
# existed, and nothing could see it: the build is happy with a closure that
# does nothing, and a screen sweep photographs a room whose rows look tappable.
python3 - "$WORK/feed.nc" <<'PYWIRED' || exit 1
import sys, io, re
src = io.open(sys.argv[1], encoding="utf-8").read()
# The WHOLE room branch, not a window from the list's own mount: the account
# door is on the FIGURE, which is mounted above the list, so a window anchored
# there could only ever see two of the three doors and would pass while one was
# missing.
i = src.find("source == FramesIdentity.source,")
j = src.find("} else if source == HegotaIdentity.source", i)
if i < 0 or j < 0:
    print("✗ FeedScreen no longer mounts the Frames room"); sys.exit(1)
body = src[i:j]
if "FramesRoomList(head:" not in body:
    print("✗ FeedScreen no longer mounts FramesRoomList"); sys.exit(1)
if re.search(r"onOpenMove:\s*\{\s*_\s*in\s*\}", body):
    print("✗ the Frames rows are wired to an empty closure again — every row in three scopes highlights and does nothing")
    sys.exit(1)
# **THE ROUTE BEING ASSIGNED, not the word appearing.** The first cut matched
# the bare case name and passed with the account door DELETED, because
# `framesAccounts` — the scoped-accounts helper two lines above it — contains
# the substring. A guard must prove the condition, not that the words are on
# the page; this repo has paid for that twice (`cursor-selftest`'s
# end-of-line anchor, `safetx-selftest`'s whole-condition rule).
for hook, why in [("feedSheet = .framesMove(", "a transaction"),
                  ("feedSheet = .framesAccount(", "an account"),
                  ("feedSheet = .framesPayer(", "a sponsor")]:
    if hook not in body:
        print("✗ nothing in the Frames room opens %s" % why); sys.exit(1)
sys.exit(0)
PYWIRED

# THE VERDICT HAS ONE HOME. `FramesMoveRow` spelled it out and the sheet would
# have had to derive it again — and this rule drifting means a row and the
# sheet it opens disagreeing about whether somebody's money moved, which is the
# one thing in this seat that costs real trust.
python3 - "$WORK/card.nc" "$WORK/sheets.nc" <<'PYVERDICT' || exit 1
import sys, io
for path, name in [(sys.argv[1], "FramesRoomCard"), (sys.argv[2], "FramesSheets")]:
    src = io.open(path, encoding="utf-8").read()
    if "movedValue == true && !succeeded" in src or "movedValue == true && !move.succeeded" in src:
        print("✗ %s derives the verdict itself — it must come through FramesMove.verdict alone" % name)
        sys.exit(1)
sys.exit(0)
PYVERDICT
grep -qF 'move.verdict' "$WORK/card.nc" \
  || { echo "✗ FramesMoveRow no longer reads FramesMove.verdict"; exit 1; }

# NIL IS NEVER ZERO, on the four readings where a failed read would render as a
# confident claim about somebody's money: the delta, the fee, a sponsor's total
# and a balance. Each is drawn behind an `if let`, never a `?? 0`.
python3 - "$WORK/sheets.nc" "$WORK/card.nc" <<'PYNIL' || exit 1
import sys, io, re
for path in sys.argv[1:]:
    src = io.open(path, encoding="utf-8").read()
    for bad in ["deltaWei ?? 0", "feeWei ?? 0", "gasWei ?? 0", "feeWeiIfSelfPaid ?? 0",
                "balanceWeiHex ?? \"0x0\""]:
        if bad in src:
            print("✗ `%s` — an unread reading drawn as zero, which is a confident claim built on a failed read (§515a)" % bad)
            sys.exit(1)
sys.exit(0)
PYNIL

# THE FLAG REACHES EVERY CONSUMER THROUGH ONE DOOR. The strip's own guard says
# so for the drawing; the sheet states the join in WORDS, which is a second
# reader and must go through the same property — a sheet reading `flags & 0x4`
# itself is how "roped to step 3" and a strip with no tie end up on one screen.
python3 - "$WORK/sheets.nc" <<'PYJOIN' || exit 1
import sys, io
src = io.open(sys.argv[1], encoding="utf-8").read()
if "startsBatch" in src or "0x4" in src or "flags &" in src:
    print("✗ FramesSheets reads the atomic flag directly — it must come through FramesFrameRow.joinedToNext")
    sys.exit(1)
if "joinedToNext" not in src:
    print("✗ the frame sheet no longer says whether a step is roped to its neighbour")
    sys.exit(1)
sys.exit(0)
PYJOIN

# THE PERMISSION IS SAID. `FramesSection`'s own ruling: there is no Permissions
# scope because authority here is granted and spent inside one transaction, so
# "the `frames` scope must always say whether a VERIFY frame approved
# execution, payment or both". Until this sheet existed the only surface that
# ever said it was the send preview — before the fact, never after.
for term in approvesExecution approvesPayment; do
  grep -qF "$term" "$WORK/sheets.nc" \
    || { echo "✗ the frame sheet no longer reads $term — the permission is the frame, and this is the only place it can be read after the fact"; exit 1; }
done

# AN ABSENT `stateGasUsed` IS NEVER DRAWN AS A BAR. Measured across every frame
# on this chain, including one sent to a fresh address (which grows state): the
# field is absent, not zero — and `0x0` is the discriminator that tells a
# missing STATE budget apart from a too-small EXECUTION one, so a bar built on
# a defaulted zero asserts that diagnosis every time.
python3 - "$WORK/sheets.nc" <<'PYSTATE' || exit 1
import sys, io
src = io.open(sys.argv[1], encoding="utf-8").read()
if "stateGasUsed ?? 0" in src:
    print("✗ the frame sheet defaults stateGasUsed to zero — an absent field would be drawn as a state starvation")
    sys.exit(1)
i = src.find("func stateReading(")
if i < 0:
    print("✗ the frame sheet no longer reports the state budget"); sys.exit(1)
if "let used = row.outcome?.stateGasUsed" not in src[i:i + 700]:
    print("✗ the state bar no longer requires a REPORTED stateGasUsed"); sys.exit(1)
sys.exit(0)
PYSTATE

# THE SHEETS DO NOT PRESENT THEMSELVES. Every card that opens one lives inside
# `FeedScreen`'s List, where a `.sheet` resolves to the same presenting
# controller and rises part way before closing again — paid for three times.
grep -q '\.sheet(' "$WORK/sheets.nc" \
  && { echo "✗ a Frames sheet presents its own sheet — it must route through FeedScreen's one .sheet(item:)"; exit 1; }

# THE ROOM'S SIGNATURE DRAWING IS SHARED, NEVER COPIED. A transaction pictured
# one way in the slot and another way in its own sheet is worse than not
# drawing it twice.
grep -qF 'FramesSequenceStrip(runs: [move.rows])' "$WORK/sheets.nc" \
  || { echo "✗ the move sheet no longer draws the room's own strip"; exit 1; }
python3 - "$WORK/sheets.nc" <<'PYCANVAS' || exit 1
import sys, io
src = io.open(sys.argv[1], encoding="utf-8").read()
if "Canvas {" in src:
    print("✗ FramesSheets rolls its own Canvas — the sequence drawing is FramesRoomCard's and must stay one drawing")
    sys.exit(1)
sys.exit(0)
PYCANVAS

# EVERY BAR IN THESE SHEETS IS SIZED FROM DATA, SO IT ARRIVES (design-motion
# law). `design-motion-audit` can see a GeometryReader, so this is belt rather
# than the only guard — but the budget bar is the sheet's whole subject and a
# measurement that simply IS reads as chrome.
python3 - "$WORK/sheets.nc" <<'PYWIPE' || exit 1
import sys, io
src = io.open(sys.argv[1], encoding="utf-8").read()
i = src.find("struct FramesBudgetBar: View")
if i < 0:
    print("✗ FramesBudgetBar is gone"); sys.exit(1)
body = src[i:]
if "chartWipe(reduceMotion:" not in body[:1600]:
    print("✗ FramesBudgetBar no longer arrives"); sys.exit(1)
if "min(1, Double(used) / Double(limit))" not in body[:1600]:
    print("✗ the budget bar no longer clamps — a frame that overran its budget would draw off its own track")
    sys.exit(1)
sys.exit(0)
PYWIPE

# THE SCOPE IS NOT DEAD. `chrome.framesScope` was written on every pick and
# read by NOTHING: the figure, the curve, the crown and every row took the
# whole account list, so the face lit and the room did not change. Both halves
# — the source must narrow, and the memoised head must re-key on it, or the
# card describes rows that are no longer on screen.
python3 - "Casberi/Casberi/Model/FramesRoomSource.swift" "$WORK/feed.nc" <<'PYSCOPE' || exit 1
import sys, io
source = io.open(sys.argv[1], encoding="utf-8").read()
feed = io.open(sys.argv[2], encoding="utf-8").read()
if "static func accounts(scope: String? = nil)" not in source:
    print("✗ FramesRoomSource.accounts no longer takes a scope — the face rail would be a control that changes nothing")
    sys.exit(1)
if "picked.isEmpty ? all : picked" not in source:
    print("✗ a scope matching nothing no longer falls back to every account — a remembered pick whose address has gone would empty the room")
    sys.exit(1)
if "FramesRoomSource.accounts(scope: chrome.framesScope)" not in feed:
    print("✗ the Frames room no longer scopes its accounts"); sys.exit(1)
if "compose(scope: chrome.framesScope)" not in feed:
    print("✗ the Frames head is composed unscoped — the crown would describe an address the room is not showing")
    sys.exit(1)
i = feed.find("private var headIdentity")
key = feed[i:feed.find("\n    }", i)]
if "chrome.framesScope" not in key:
    print("✗ chrome.framesScope is not in headIdentity — a head memoised under one scope would survive the pick that changed it")
    sys.exit(1)
sys.exit(0)
PYSCOPE
echo "  ok   drift guards: the rows open, the verdict has one home, and the face rail really scopes"

cp "$TX" "$WORK/FramesTransaction.swift"
cp "$RLPF" "$WORK/RLP.swift"
cp "$KC" "$WORK/Keccak256.swift"
cp "$MONEY" "$WORK/FramesMoney.swift"
cp "$SECT" "$WORK/FramesSection.swift"
cp "$READ" "$WORK/FramesReading.swift"
mkdir -p "$WORK/m"

cat > "$WORK/m/main.swift" <<'SWIFT'
import Foundation
var fails = 0
func check(_ l: String, _ ok: Bool) { if !ok { print("  ✗ \(l)"); fails += 1 } }
func hx(_ s: String) -> Data { RLP.data(fromHex: s) ?? Data() }
func keccakHex(_ d: Data) -> String {
    "0x" + Keccak256.hash([UInt8](d)).map { String(format: "%02x", $0) }.joined()
}

// ============ VECTOR 1 — real, and the ONLY one on chain with a non-zero
// nonce. A dropped or misplaced nonce reproduces every other transaction's
// hash, so without this fixture that mutation survives.
let s1 = hx("0x80cfe5da326d0ab7a1d2ffc61745c57885dc2e32")
let v1 = FramesTransaction.Fields(
    chainID: 0x13e02, nonce: 1, sender: s1,
    frames: [
        .init(mode: 1, flags: 0x03, target: s1,
              executionGas: 0x186a0, stateGas: 0x3d090, value: Data(), data: Data()),
        .init(mode: 2, flags: 0x00, target: hx("0x00000000000000000000000000000000deadbe02"),
              executionGas: 0x186a0, stateGas: 0x3d090, value: hx("0x01"), data: Data()),
    ],
    signatures: [
        .init(scheme: 1, signer: s1, msg: Data(),
              signature: hx("0x01b3cebf85a905a6f1a3ad77cc780f86c890964c776b4b179a26cf14d43877797d7e8c2dfc753fcc93f47671bbda75f8f670743b14f93f9b51e83760d1e7106d65")),
    ],
    maxPriorityFeePerGas: 0x3b9aca00, maxFeePerGas: 0x2540be400,
    maxFeePerBlobGas: 0, blobVersionedHashes: [])

let RAW1 = "06f8ce83013e02019480cfe5da326d0ab7a1d2ffc61745c57885dc2e32f846e201039480cfe5da326d0ab7a1d2ffc61745c57885dc2e32c8830186a08303d0908080e202809400000000000000000000000000000000deadbe02c8830186a08303d0900180f85cf85a019480cfe5da326d0ab7a1d2ffc61745c57885dc2e3280b84101b3cebf85a905a6f1a3ad77cc780f86c890964c776b4b179a26cf14d43877797d7e8c2dfc753fcc93f47671bbda75f8f670743b14f93f9b51e83760d1e7106d65cc843b9aca008502540be40080c0"
let HASH1 = "0x70c8c2b7c44ff8f046e1ebb7c925a80724aaad7f65f85d82e97c724cdbfc9bc6"
check("vector 1 re-encodes byte for byte", RLP.hex(FramesTransaction.encoded(v1)) == RAW1)
// THE END-TO-END PROOF: keccak of our bytes IS the hash the chain reports.
// Nothing short of a correct encoder passes this.
check("vector 1's keccak is the transaction hash the RPC reports",
      keccakHex(FramesTransaction.encoded(v1)) == HASH1)
check("the type byte is the measured 0x06", FramesTransaction.txType == 0x06)

// ============ VECTOR 2 — real, a different sender, a different fee ceiling
// and a DIFFERENT gas pair (0x13880/0x30d40, where v1 is 0x186a0/0x3d090), so
// a hardcoded limit or a swapped fee cannot pass both.
let s2 = hx("0x80cfe5da326d0ab7a1d2ffc61745c57885dc2e32")
let v2 = FramesTransaction.Fields(
    chainID: 0x13e02, nonce: 0, sender: s2,
    frames: [
        .init(mode: 1, flags: 0x03, target: s2,
              executionGas: 0x13880, stateGas: 0x30d40, value: Data(), data: Data()),
        .init(mode: 2, flags: 0x00, target: hx("0x00000000000000000000000000000000deadbe02"),
              executionGas: 0x13880, stateGas: 0x30d40, value: hx("0x01"), data: Data()),
    ],
    signatures: [
        .init(scheme: 1, signer: s2, msg: Data(),
              signature: hx("0x0028fc3a1de4b0d5ea0d6e8ef4a56ba0eb4f4ba0f3f8de5ac1a3c9e4bb08a7a9d3e0f4b9f77b3f6a2e6ec2d78e5b6f5cbeb5b6e5f5d5e5d5c5b5a5958575655545")),
    ],
    maxPriorityFeePerGas: 0x3b9aca00, maxFeePerGas: 0x4a817c800,
    maxFeePerBlobGas: 0, blobVersionedHashes: [])
check("vector 2's fee ceiling reaches the bytes",
      RLP.hex(FramesTransaction.encoded(v2)).contains("8504a817c800"))
check("vector 2's distinct gas pair reaches the bytes",
      RLP.hex(FramesTransaction.encoded(v2)).contains("c88301388083030d40"))
check("two real transactions do not encode alike",
      FramesTransaction.encoded(v1) != FramesTransaction.encoded(v2))

// ============ VECTOR 3 — SYNTHETIC, every field a DIFFERENT value, because
// the five real transactions share too much to catch a swap. A fixture only
// tests the rule it names if it FAILS that rule and passes every other one.
let v3 = FramesTransaction.Fields(
    chainID: 0x13e02, nonce: 0x11, sender: hx("0x1111111111111111111111111111111111111111"),
    frames: [
        .init(mode: 1, flags: 0x03, target: hx("0x2222222222222222222222222222222222222222"),
              executionGas: 0x33, stateGas: 0x44, value: hx("0x55"), data: hx("0x66")),
    ],
    signatures: [
        .init(scheme: 1, signer: hx("0x7777777777777777777777777777777777777777"),
              msg: Data(), signature: Data(repeating: 0x88, count: 65)),
    ],
    maxPriorityFeePerGas: 0x99, maxFeePerGas: 0xAA, maxFeePerBlobGas: 0xBB,
    blobVersionedHashes: [Data(repeating: 0xCC, count: 32)])

// THE NESTED FEE LIST is this chain's whole divergence from Hegotá. Flattening
// it yields a six-field envelope that encodes cleanly and is refused.
// `c3 99 aa bb` is a 3-item list; flat, the bytes would read `99 aa bb` bare.
check("the three fees ride a nested list of their own",
      RLP.hex(FramesTransaction.encoded(v3)).contains("c6819981aa81bb"))
// The nonce is a SCALAR here, never Hegotá's [keys] + seq pair.
check("the nonce is a bare scalar",
      RLP.hex(FramesTransaction.encoded(v3)).contains("83013e0211"))
check("every distinct field survives into the bytes",
      RLP.hex(FramesTransaction.encoded(v3)).contains("c233445566"))
check("the blob hash list is carried",
      RLP.hex(FramesTransaction.encoded(v3)).contains("cccccccccccc"))

// A field swap must not reproduce the hash — the safetx lesson, pinned.
var swapped = v3
swapped.maxPriorityFeePerGas = 0xAA; swapped.maxFeePerGas = 0x99
check("swapping the two fee ceilings changes the bytes",
      FramesTransaction.encoded(swapped) != FramesTransaction.encoded(v3))
var gasSwap = v3
gasSwap.frames[0].executionGas = 0x44; gasSwap.frames[0].stateGas = 0x33
check("swapping a frame's two budgets changes the bytes",
      FramesTransaction.encoded(gasSwap) != FramesTransaction.encoded(v3))

// ============ THE ELISION RULE, both directions. An empty msg means "sign the
// sigHash" and that entry's own bytes leave the hash; a 32-byte msg signs
// itself and its bytes STAY. Backwards is a signature over the wrong thing.
check("an empty-msg entry is elided", v1.signatures[0].isElided)
check("elision actually changes the bytes",
      FramesTransaction.signingPreimage(v1) != FramesTransaction.encoded(v1))
check("the elided preimage drops the signature bytes",
      FramesTransaction.signingPreimage(v1).range(of: hx("0x01b3cebf85a905a6f1a3ad77cc780f86")) == nil)
var withMsg = v1
withMsg.signatures[0].msg = Data(repeating: 0xAB, count: 32)
check("a 32-byte-msg entry is NOT elided", !withMsg.signatures[0].isElided)
check("a non-elided entry keeps its bytes in the hash",
      FramesTransaction.signingPreimage(withMsg) == FramesTransaction.encoded(withMsg))
// PER ENTRY, not per transaction.
var mixed = v1
mixed.signatures.append(.init(scheme: 1, signer: hx("0x4fc28b54955dad982c625ca572e9db55c6348ea8"),
                              msg: Data(repeating: 0x5A, count: 32),
                              signature: Data(repeating: 0xCD, count: 65)))
let mixedSig = FramesTransaction.signingPreimage(mixed)
check("a mixed transaction keeps the un-elided entry's bytes",
      mixedSig.range(of: Data(repeating: 0xCD, count: 65)) != nil)
check("a mixed transaction drops the elided entry's bytes",
      mixedSig.range(of: hx("0x01b3cebf85a905a6f1a3ad77cc780f86")) == nil)

// ============ EMPTY MEANS "THE SENDER" and must stay empty in the bytes.
// UNPROVEN on this chain — all 5 write both literally — carried from Hegotá's
// measured rule. Pinned so a "helpful" substitution can't creep in.
check("all five real transactions write their signer literally",
      !v1.signatures[0].signer.isEmpty && !v2.signatures[0].signer.isEmpty)
var emptySigner = v1
emptySigner.signatures[0].signer = Data()
check("an empty signer changes the bytes",
      FramesTransaction.encoded(emptySigner) != FramesTransaction.encoded(v1))
var emptyTarget = v1
emptyTarget.frames[0].target = Data()
check("an empty target changes the bytes",
      FramesTransaction.encoded(emptyTarget) != FramesTransaction.encoded(v1))

// ============ THE TWO-ELEMENT LIMITS FORM, written even when the two budgets
// are EQUAL — one real transaction (0xf70aae…) has execution == state, which
// is exactly where a scalar-form bug hides.
var equalGas = v1
equalGas.frames[0].stateGas = 0x186a0
check("limits stays a two-element list when both budgets are equal",
      RLP.hex(FramesTransaction.encoded(equalGas)).contains("c8830186a0830186a0"))
var zeroState = v1
zeroState.frames[0].stateGas = 0
check("limits stays a two-element list at zero state gas",
      RLP.hex(FramesTransaction.encoded(zeroState)).contains("c5830186a080"))

// ============ THE SMALLEST USEFUL TRANSACTION. Without an APPROVE the
// transaction has no payer and is invalid, so the VERIFY frame is not
// optional and its flags are not decoration.
let built = FramesTransaction.transfer(
    sender: s1, to: hx("0x00000000000000000000000000000000deadbe02"),
    value: hx("0x01"), nonce: 1,
    maxPriorityFeePerGas: 0x3b9aca00, maxFeePerGas: 0x2540be400)
check("a transfer is two frames", built.frames.count == 2)
check("the first frame is VERIFY", built.frames[0].mode == 1)
check("the VERIFY frame targets the sender", built.frames[0].target == s1)
check("the VERIFY frame approves BOTH execution and payment", built.frames[0].flags == 0x03)
check("the second frame is SENDER", built.frames[1].mode == 2)
check("the SENDER frame carries the value", built.frames[1].value == hx("0x01"))
check("the VERIFY frame moves no value", built.frames[0].value.isEmpty)
// A transfer to an address that does not exist yet GROWS STATE. With state: 0
// it halts on that write and burns its whole execution budget, reporting what
// reads as an execution failure. On a devnet whose accounts are minutes old
// that is the common case, not an edge one.
check("a built transfer carries a real state budget", built.frames[1].stateGas >= 250_000)
check("a built transfer pins this chain", built.chainID == 81410)
check("a built transfer starts unsigned", built.signatures.isEmpty)

// ============ THE VALIDATION PREFIX IS BOUNDED at 500,000 here, and only
// mode-1 frames sit in it. Counting every frame refuses transactions the chain
// would have accepted; counting none lets the node refuse with a sentence that
// names no remedy.
check("the measured prefix ceiling is 500,000", FramesTransaction.maxVerifyGas == 500_000)
check("a built transfer fits the prefix", FramesTransaction.prefixWithinBudget(built))
var fatPrefix = built
fatPrefix.frames[0].executionGas = 600_000
check("an oversized VERIFY frame is refused", !FramesTransaction.prefixWithinBudget(fatPrefix))
var fatSender = built
fatSender.frames[1].executionGas = 5_000_000
check("a large SENDER frame does NOT count against the prefix",
      FramesTransaction.prefixWithinBudget(fatSender))
var twoVerify = built
twoVerify.frames.append(.init(mode: 1, flags: 0x03, target: s1,
                              executionGas: 450_000, stateGas: 0,
                              value: Data(), data: Data()))
check("two VERIFY frames are summed against the prefix",
      !FramesTransaction.prefixWithinBudget(twoVerify))


// ============ WEI IS WIDER THAN `UInt64`, and this chain proves it. The
// address this seat offers as its first worked example holds 99,999.999762
// ETH — a genesis-funded dev account, measured 2026-09-01. As wei that is
// 0x152d02c7e14af6612e39c, which `UInt64(_:radix:)` cannot parse.
let genesisWei = "0x152d02c708d9ed097cba"
check("the obvious type really does fail on it",
      UInt64(String(genesisWei.dropFirst(2)), radix: 16) == nil)
check("a genesis balance parses", FramesMoney.decimal(fromHex: genesisWei) != nil)
check("and formats as the chain's own figure",
      FramesMoney.eth(fromWeiHex: genesisWei) == "99,999.9997")
check("one whole ETH", FramesMoney.eth(fromWeiHex: "0xde0b6b3a7640000") == "1.0000")
check("the 0x prefix is optional", FramesMoney.decimal(fromHex: "de0b6b3a7640000")
                                == FramesMoney.decimal(fromHex: "0xde0b6b3a7640000"))
// AN EMPTY READ IS NIL, NEVER ZERO. `eth_getBalance` answering with nothing
// is a read that did not happen, and drawing it as a zero balance is §515a's
// mistake on the one number somebody would act on.
check("an empty body is nil, not zero", FramesMoney.decimal(fromHex: "0x") == nil)
check("a non-hex body is nil", FramesMoney.decimal(fromHex: "0xzz") == nil)
check("an over-wide body is nil", FramesMoney.decimal(fromHex: "0x" + String(repeating: "f", count: 65)) == nil)
check("no balance line without a balance", FramesMoney.balanceLine(weiHex: nil) == nil)
// ROUNDS DOWN. A balance rounded up reads as more than the account holds, and
// on a send screen that is the number somebody acts on.
check("rounding is DOWN, never to-nearest",
      FramesMoney.eth(fromWeiHex: "0xde0893a1f26e000") == "0.9999")
// NO CURRENCY. Test ETH has no price and no market.
check("the line names test ETH and no currency",
      (FramesMoney.balanceLine(weiHex: "0xde0b6b3a7640000") ?? "").contains("test ETH"))
check("and carries no dollar sign",
      !(FramesMoney.balanceLine(weiHex: "0xde0b6b3a7640000") ?? "").contains("$"))


// ============ THE SCOPE STRIP. Every failure here renders as a perfectly
// ordinary room — a scope that never appears, a remembered scope resolving to
// one nobody picked, or a strip drawn over a single chip.
check("Home leads", FramesSection.order.first == .home)
check("the order covers every case", Set(FramesSection.order) == Set(FramesSection.allCases))
check("and lists each exactly once", FramesSection.order.count == FramesSection.allCases.count)
// THE TAIL RULE, Wallet's: no UNCONDITIONAL scope may sit after a conditional
// one, so the strip's stable head never reflows as an address gains content.
let firstConditional = FramesSection.order.firstIndex { $0.isConditional } ?? FramesSection.order.count
check("no unconditional scope sits after a conditional one",
      FramesSection.order.enumerated().allSatisfy { i, s in i < firstConditional || s.isConditional })
check("home and activity are the constants",
      FramesSection.order.filter { !$0.isConditional } == [.home, .activity])
check("frames leads the conditional tail", FramesSection.order[firstConditional] == .frames)

// PRESENT: the two constants always, the two readings only when they exist.
check("a bare address is home and activity alone",
      FramesSection.present(frames: false, sponsors: false) == [.home, .activity])
check("a frame transaction opens the frames scope",
      FramesSection.present(frames: true, sponsors: false) == [.home, .activity, .frames])
// SPONSORS IS FALSE ON EVERY ADDRESS MEASURED SO FAR — every transaction on
// this chain is self-paid — and that is the correct output rather than a gap.
check("a sponsored transaction opens the sponsors scope",
      FramesSection.present(frames: true, sponsors: true) == [.home, .activity, .frames, .sponsors])
check("sponsors can appear without frames",
      FramesSection.present(frames: false, sponsors: true) == [.home, .activity, .sponsors])

// RESOLVE falls back to `.home`, never to "the first present scope" — an
// unreachable branch that quietly picks `frames` is how a room starts opening
// somewhere nobody chose.
check("an unremembered scope opens Home",
      FramesSection.resolve(nil, present: FramesSection.order) == .home)
check("a remembered scope that is still present is kept",
      FramesSection.resolve(.frames, present: [.home, .activity, .frames]) == .frames)
check("a remembered scope whose content is gone falls back to Home",
      FramesSection.resolve(.sponsors, present: [.home, .activity]) == .home)
check("the fallback is Home and not the first present scope",
      FramesSection.resolve(.sponsors, present: [.activity, .home]) == .home)

// ONE SCOPE IS A LABEL, NOT A CONTROL.
check("a strip over one scope is not drawn", !FramesSection.shows(present: [.home]))
check("a strip over two is", FramesSection.shows(present: [.home, .activity]))
// NO DOTS, EVER: nothing in this room is urgent — no deadline, no expiry, no
// grant to revoke, and the asset is test ETH on a resettable chain.
check("no chip ever wears a dot", FramesSection.attention().isEmpty)

// THE LITERAL TERMS. The chip is where the vocabulary gets learned, and this
// chain is NAMED for frames.
check("the frames chip says Frames", FramesSection.frames.label == "Frames")
check("every scope says what it holds",
      FramesSection.allCases.allSatisfy { !$0.summary.isEmpty && $0.summary != $0.label })


// ============ STATUS IS EXECUTION; ONLY THE EFFECT SAYS WHAT A FRAME DID.
// Measured by sending four transactions: a frame inside an atomic batch
// reports `status: 0x1` AFTER BEING ROLLED BACK — one log when its transfer
// persisted, zero when it was reverted, `0x1` both times.
func out(_ ok: Bool, _ used: UInt64, _ logs: Int) -> FramesRead.FrameOutcome {
    .init(succeeded: ok, gasUsed: used, stateGasUsed: nil, logCount: logs)
}
func frame(_ mode: UInt64, _ flags: UInt64, value: String) -> FramesRead.Frame {
    .init(mode: mode, flags: flags, target: "0x00", executionGas: 100_000,
          stateGas: 250_000, value: value, data: "0x")
}
// The real pair, off this chain: a value frame reporting 0x1 with a log, and
// the SAME shape reporting 0x1 with none because the batch rolled it back.
let landed  = FramesFrameRow(frame: frame(2, 0, value: "0x1"), outcome: out(true, 3000, 1))
let reverted = FramesFrameRow(frame: frame(2, 4, value: "0x1"), outcome: out(true, 3000, 0))
check("a value frame with a log landed", landed.valueLanded == true)
check("THE ROLLED-BACK FRAME did NOT land, despite status 0x1",
      reverted.valueLanded == false)
check("and the two are indistinguishable by status",
      landed.outcome?.succeeded == reverted.outcome?.succeeded)

// NIL IS NOT FALSE. A VERIFY frame moves nothing and has nothing to land;
// collapsing that into "did not move" is a false alarm on the one frame every
// transaction on this chain carries.
let verify = FramesFrameRow(frame: frame(1, 3, value: "0x"), outcome: out(true, 100, 0))
check("a VERIFY frame is not asked whether its value landed", verify.valueLanded == nil)
let zeroValue = FramesFrameRow(frame: frame(2, 0, value: "0x00"), outcome: out(true, 3000, 0))
check("an all-zero value is not a value", zeroValue.valueLanded == nil)
let unread = FramesFrameRow(frame: frame(2, 0, value: "0x1"), outcome: nil)
check("an unread frame answers nil, never false", unread.valueLanded == nil)

// THE TRANSACTION-LEVEL READINGS.
let partial = FramesMove(hash: "0x1", blockNumber: 1, sender: "0xa", payer: "0xa",
                         succeeded: false, gasUsed: 316_273, rows: [verify, landed])
// A TRANSACTION REPORTING FAILURE THAT STILL MOVED MONEY — measured on chain,
// not hypothetical. `status` alone would report this as nothing happening.
check("a failed transaction can still have moved value", partial.movedValue == true)
check("and its own status says it failed", !partial.succeeded)
let rolled = FramesMove(hash: "0x2", blockNumber: 1, sender: "0xa", payer: "0xa",
                        succeeded: false, gasUsed: 1, rows: [verify, reverted])
check("a rolled-back batch moved nothing", rolled.movedValue == false)
check("and names the frame that was rolled back", rolled.rolledBack.count == 1)
check("a landed transaction rolls nothing back", partial.rolledBack.isEmpty)
let unreadable = FramesMove(hash: "0x3", blockNumber: 1, sender: "0xa", payer: "0xa",
                            succeeded: true, gasUsed: nil, rows: [unread])
check("an unread receipt answers nil, never false", unreadable.movedValue == nil)

// SPONSORSHIP is a comparison of two fields on ONE receipt, never an inference.
let sponsored = FramesMove(hash: "0x4", blockNumber: 1, sender: "0xa", payer: "0xB",
                           succeeded: true, gasUsed: 1, rows: [])
check("a different payer is sponsorship", sponsored.sponsored)
check("case never decides it", !FramesMove(hash: "0x5", blockNumber: 1, sender: "0xAa",
                                           payer: "0xaA", succeeded: true,
                                           gasUsed: 1, rows: []).sponsored)

// THE GAS TOTAL IS THE TRANSACTION'S OWN. Measured: frames reported 100 and
// 3,000 against a receipt of 210,790, so a sum of frames is wrong by two
// orders of magnitude in the direction that looks plausible.
check("the move carries the receipt's own gas, not a sum of frames",
      partial.gasUsed == 316_273)

// ===========================================================================
// STITCHING — several payload frames under ONE signature (prd §548 sixth
// follow-up). The failure class here is the worst this file has: a wrong flag
// produces a perfectly valid transaction that the chain accepts, and the
// person is told "all or nothing" about a batch that is not.
let sndr = Data(repeating: 0x11, count: 20)
let legA = FramesTransaction.Leg(recipient: Data(repeating: 0xAA, count: 20),
                                 value: Data([0x01]))
let legB = FramesTransaction.Leg(recipient: Data(repeating: 0xBB, count: 20),
                                 value: Data([0x02]))
let legC = FramesTransaction.Leg(recipient: Data(repeating: 0xCC, count: 20),
                                 value: Data([0x03]))

let loose = FramesTransaction.stitched(sender: sndr, legs: [legA, legB, legC],
                                       atomic: false, nonce: 7,
                                       maxPriorityFeePerGas: 1, maxFeePerGas: 2)
check("a stitch is one VERIFY frame plus one frame per leg", loose.frames.count == 4)
// **THE HEAD IS BUILT, NEVER PICKED.** Every one of this chain's 34 frame
// transactions leads with exactly this frame; a builder that omitted it or
// let it carry value would produce a transaction nothing authorises.
check("the head is the VERIFY frame", loose.frames[0].mode == 1)
check("and it approves execution and payment", loose.frames[0].flags == 0x03)
check("and it targets the sender", loose.frames[0].target == sndr)
check("and it never carries value", loose.frames[0].value.isEmpty)
check("every payload frame is a SENDER frame", loose.frames.dropFirst().allSatisfy { $0.mode == 2 })
// ORDER IS THE WHOLE POINT of stitching: the legs run in the order they were
// built, and a reversal renders identically while sending the wrong amounts to
// the wrong people.
check("the legs keep the order they were built in",
      loose.frames[1].target == legA.recipient
      && loose.frames[2].target == legB.recipient
      && loose.frames[3].target == legC.recipient)
check("each leg keeps its own value",
      loose.frames[1].value == legA.value && loose.frames[3].value == legC.value)
// **OFF MEANS OFF.** Measured on chain: with the flag clear a failed
// transaction leaves the earlier legs SENT.
check("without all-or-nothing no payload frame is flagged",
      loose.frames.dropFirst().allSatisfy { $0.flags == 0x00 })

let atomicTx = FramesTransaction.stitched(sender: sndr, legs: [legA, legB, legC],
                                          atomic: true, nonce: 7,
                                          maxPriorityFeePerGas: 1, maxFeePerGas: 2)
check("the atomic flag is bit 2", FramesTransaction.atomicFlag == 0x04)
// **THE FLAG JOINS A FRAME TO THE NEXT, so the LAST payload frame must not
// carry it.** This assertion was originally written the other way — "every
// payload frame" — and it PASSED, because a harness proves the bytes are the
// bytes we meant and never that the chain accepts them. The node's own words
// on broadcast: `Frame 2: atomic batch flag on last frame`.
check("all-or-nothing flags every payload frame BUT the last",
      atomicTx.frames.dropFirst().dropLast().allSatisfy { $0.flags == FramesTransaction.atomicFlag })
check("and never the last payload frame", atomicTx.frames.last!.flags == 0x00)
// A ONE-leg batch gets no flag at all, and that is correct rather than a hole:
// its only payload frame IS the last frame, and there is nothing to join it to.
let loneAtomic = FramesTransaction.stitched(sender: sndr, legs: [legA], atomic: true,
                                            nonce: 7, maxPriorityFeePerGas: 1, maxFeePerGas: 2)
check("a single-leg atomic batch carries no atomic flag",
      loneAtomic.frames[1].flags == 0x00)
// The VERIFY frame is not a payload frame and must keep its own flags: 0x03 is
// what authorises execution and payment, and overwriting it with 0x04 sends a
// transaction that authorises nothing.
check("and never the VERIFY frame", atomicTx.frames[0].flags == 0x03)

// **THE TWO STITCHED SHAPES DIFFER IN `flags` AND IN NOTHING ELSE.**
//
// This is not a tidiness assertion, it is the whole licence for how the send
// sheet draws its preview (2026-09-01): that screen asks `stitched` for the
// JOINED shape once and scales the ties by the toggle, so flipping
// all-or-nothing GROWS a tie instead of swapping one static Canvas for
// another. That is exact only while the flag is the sole difference — and the
// flag reaches the drawing through one door, `FramesFrameRow.joinedToNext`,
// which is rendered as the tie and nowhere else (guarded separately below).
//
// Give `flags` a second meaning and the preview silently starts promising a
// shape the signer does not produce, on the one control in this app that
// decides whether a failed batch leaves money with a stranger.
check("the two stitched shapes agree on frame count",
      atomicTx.frames.count == loose.frames.count)
check("and differ in `flags` and in nothing else",
      zip(atomicTx.frames, loose.frames).allSatisfy {
          $0.0.mode == $0.1.mode && $0.0.target == $0.1.target
          && $0.0.value == $0.1.value && $0.0.data == $0.1.data
          && $0.0.executionGas == $0.1.executionGas
          && $0.0.stateGas == $0.1.stateGas
      })
check("and really do differ in flags, or the check above proves nothing",
      zip(atomicTx.frames, loose.frames).contains { $0.0.flags != $0.1.flags })

// ONE LEG THROUGH `stitched` IS THE SAME TRANSACTION `transfer` BUILDS. The
// two builders are kept apart on purpose (the fixtures pin `transfer`), so
// this is the only thing standing between them and silent divergence.
let oneLeg = FramesTransaction.stitched(sender: sndr, legs: [legA], atomic: false,
                                        nonce: 7, maxPriorityFeePerGas: 1, maxFeePerGas: 2)
let viaTransfer = FramesTransaction.transfer(sender: sndr, to: legA.recipient,
                                             value: legA.value, nonce: 7,
                                             maxPriorityFeePerGas: 1, maxFeePerGas: 2)
check("one stitched leg encodes byte-identically to a plain transfer",
      FramesTransaction.encoded(oneLeg) == FramesTransaction.encoded(viaTransfer))
// The envelope's own fields must survive the new builder untouched — a stitch
// that quietly reset the nonce or the chain id is refused by the node in a way
// that reads as a signing bug.
check("the stitch carries the chain id", atomicTx.chainID == FramesTransaction.chainID)
check("and the nonce it was given", atomicTx.nonce == 7)
check("and signs nothing by itself", atomicTx.signatures.isEmpty)

// ===========================================================================
// WHO GOT IT, AND WHAT IT COST (2026-09-01). A row said what ran, what it cost
// in gas, and whether it landed — never who received it, and never in money.
let me = "0xAAAA"
let them = "0xBBBB"
func payload(_ to: String, _ value: String) -> FramesFrameRow {
    .init(frame: .init(mode: 2, flags: 0, target: to, executionGas: 1, stateGas: 1,
                       value: value, data: nil),
          outcome: .init(succeeded: true, gasUsed: 1, stateGasUsed: nil, logCount: 1))
}
let verifyRow = FramesFrameRow(
    frame: .init(mode: 1, flags: 3, target: me, executionGas: 1, stateGas: 1,
                 value: "0x0", data: nil),
    outcome: .init(succeeded: true, gasUsed: 1, stateGasUsed: nil, logCount: 0))

let paid = FramesMove(hash: "0xr1", blockNumber: 1, sender: me, payer: me,
                      succeeded: true, gasUsed: 210_790,
                      effectiveGasPriceWei: 1_000_000_000,
                      rows: [verifyRow, payload(them, "0x1"), payload("0xCCCC", "0x2")])
check("recipients name the payload frames", paid.recipients == [them, "0xCCCC"])

// **TWO RULES, TWO FIXTURES, AND THE FIRST ATTEMPT PROVED NEITHER.** One
// fixture where the VERIFY frame targets the sender satisfies BOTH the
// mode check and the sender check, so deleting either one left the suite
// green — both mutations survived. A fixture only tests the rule it names if
// it FAILS that rule and passes every other one.
//
// Isolating the MODE rule: a VERIFY frame pointed somewhere other than the
// sender. Constructed rather than observed — every VERIFY frame on this chain
// targets its sender — precisely so the sender check cannot do this check's
// work for it.
let oddVerify = FramesMove(
    hash: "0xr5", blockNumber: 1, sender: me, payer: me, succeeded: true, gasUsed: 1,
    effectiveGasPriceWei: 1,
    rows: [.init(frame: .init(mode: 1, flags: 3, target: "0xDDDD", executionGas: 1,
                              stateGas: 1, value: "0x0", data: nil),
                 outcome: nil),
           payload(them, "0x1")])
check("a VERIFY frame is never a recipient, wherever it points",
      oddVerify.recipients == [them])

// Isolating the SENDER rule: a PAYLOAD frame that pays the sender — an
// ordinary self-transfer, which this chain permits and a room must not report
// as "you sent to yourself" in the recipient slot.
let selfSend = FramesMove(
    hash: "0xr6", blockNumber: 1, sender: me, payer: me, succeeded: true, gasUsed: 1,
    effectiveGasPriceWei: 1,
    rows: [verifyRow, payload(me, "0x1"), payload(them, "0x2")])
check("the sender is never its own recipient", selfSend.recipients == [them])
let repeated = FramesMove(hash: "0xr2", blockNumber: 1, sender: me, payer: me,
                          succeeded: true, gasUsed: 1, effectiveGasPriceWei: 1,
                          rows: [payload(them, "0x1"), payload("0xbbbb", "0x2")])
// Case-folded for the DEDUPE only: an address's case is a checksum, so the
// spelling that comes back is the one that arrived.
check("two spellings of one address are one recipient", repeated.recipients == [them])

// THE FEE is the receipt's own two terms multiplied — never a frame sum, for
// the reason `gasUsed` carries in its own doc.
check("the fee is gasUsed x effectiveGasPrice",
      paid.feeWei == Decimal(210_790) * Decimal(1_000_000_000))
let noPrice = FramesMove(hash: "0xr3", blockNumber: 1, sender: me, payer: me,
                         succeeded: true, gasUsed: 210_790, rows: [])
// **NIL, NEVER ZERO.** An unread fee and a free transaction must not look
// alike, and on this chain nothing is free.
check("a missing price is an unknown fee, not a free one", noPrice.feeWei == nil)
let theirs = FramesMove(hash: "0xr4", blockNumber: 1, sender: me, payer: them,
                        succeeded: true, gasUsed: 210_790,
                        effectiveGasPriceWei: 1_000_000_000, rows: [])
check("a sponsored transaction still HAS a fee", theirs.feeWei != nil)
// ...but it is not yours, and drawing it under a row whose own second line says
// somebody else paid is the two halves of one row disagreeing.
check("and never presents it as yours", theirs.feeWeiIfSelfPaid == nil)
check("while a self-paid one does", paid.feeWeiIfSelfPaid != nil)

// THE JOIN — the same bit the send now sets, read back.
check("bit 2 reads as joined to the next frame",
      FramesFrameRow(frame: .init(mode: 2, flags: 0x4, target: nil, executionGas: nil,
                                  stateGas: nil, value: nil, data: nil),
                     outcome: nil).joinedToNext)
check("and an unflagged frame is not",
      !FramesFrameRow(frame: .init(mode: 2, flags: 0x0, target: nil, executionGas: nil,
                                   stateGas: nil, value: nil, data: nil),
                      outcome: nil).joinedToNext)
// The strip sizes cells by this, so a VERIFY frame's "0x0" and a real amount
// must not both read as nothing.
check("a zero value is no value", payload(them, "0x0").valueWeiHex == nil)
check("and a real one survives", payload(them, "0x38d7ea4c68000").valueWeiHex != nil)

// --- THE VERDICT, which is what a row and its sheet BOTH say now -------------
// It lived inside `FramesMoveRow` where nothing could reach it; the sheet the
// row opens would have derived the same rule a second time, and this rule
// drifting means a row and its own sheet disagreeing about whether money moved.
func moved(_ landed: Bool, ok: Bool) -> FramesMove {
    // A payload frame carrying value, whose LOG count decides whether the
    // value really landed — status cannot answer this (§548, measured).
    let row = FramesFrameRow(
        frame: .init(mode: 2, flags: 0x0, target: them, executionGas: nil,
                     stateGas: nil, value: "0x38d7ea4c68000", data: nil),
        outcome: .init(succeeded: true, gasUsed: 3_000, stateGasUsed: nil,
                       logCount: landed ? 1 : 0))
    return FramesMove(hash: "0xv", blockNumber: 1, sender: me, payer: me,
                      succeeded: ok, rows: [row])
}
check("a clean transaction reads as Ran", moved(true, ok: true).verdict == .ran)
// **THE TRAP THIS SEAT EXISTS FOR**: it reverted and the money moved anyway,
// because frames are not atomic by default. "Failed" lies about the money and
// "Ran" lies about the outcome.
// **THE ORDER IS ONLY TESTABLE WHERE BOTH BRANCHES ARE TRUE.** The first
// fixture here was `moved(true, ok: false)` — one landed frame, so
// `rolledBack` is EMPTY and swapping the two checks reproduced the same
// answer, green. This is the REAL measured shape (`0x9bb9cfef` on this chain,
// §548's second follow-up): a transaction that reverted, whose first frame's
// transfer persisted and whose later one did not. Both branches fire, and only
// the order decides.
let partlyLanded = FramesMove(
    hash: "0xp", blockNumber: 1, sender: me, payer: me, succeeded: false,
    rows: [
        FramesFrameRow(frame: .init(mode: 2, flags: 0x0, target: them, executionGas: nil,
                                    stateGas: nil, value: "0x38d7ea4c68000", data: nil),
                       outcome: .init(succeeded: true, gasUsed: 3_000,
                                      stateGasUsed: nil, logCount: 1)),
        FramesFrameRow(frame: .init(mode: 2, flags: 0x0, target: them, executionGas: nil,
                                    stateGas: nil, value: "0x38d7ea4c68000", data: nil),
                       outcome: .init(succeeded: true, gasUsed: 3_000,
                                      stateGasUsed: nil, logCount: 0)),
    ])
check("both branches really fire on this fixture",
      partlyLanded.movedValue == true && !partlyLanded.rolledBack.isEmpty)
check("failed-and-moved outranks rolled-back", partlyLanded.verdict == .failedButMoved)
check("and the simple case still reads the same",
      moved(true, ok: false).verdict == .failedButMoved)
// The converse: status says the FRAME succeeded, no log, so the effect was
// rolled back. Drawing this from status alone paints a green tick over money
// that never moved.
check("a rolled-back frame is named, not called failed",
      moved(false, ok: true).verdict == .rolledBack)
// A revert with no value-carrying frame at all — the only shape that can
// reach `.failed`. **A fixture only tests the rule it names if it fails that
// rule and passes every other one**: `moved(false, ok: false)` looks like this
// case and is NOT, because its frame declared a value and emitted no log,
// which is `rolledBack` and outranks it.
let verifyOnly = FramesMove(
    hash: "0xf", blockNumber: 1, sender: me, payer: me, succeeded: false,
    rows: [FramesFrameRow(
        frame: .init(mode: 1, flags: 0x3, target: me, executionGas: nil,
                     stateGas: nil, value: nil, data: nil),
        outcome: .init(succeeded: false, gasUsed: 100, stateGasUsed: nil, logCount: 0))])
check("a revert that carried no value is plainly Failed", verifyOnly.verdict == .failed)
check("and the value-carrying revert beside it is NOT",
      moved(false, ok: false).verdict == .rolledBack)
check("only `ran` is untroubled",
      !FramesMove.Verdict.ran.isTrouble && FramesMove.Verdict.failed.isTrouble
        && FramesMove.Verdict.rolledBack.isTrouble
        && FramesMove.Verdict.failedButMoved.isTrouble)

// --- WHO AN ADDRESS IS ------------------------------------------------------
// The key wins over the watch list: watching your own address does not make it
// somebody else's, and on this chain the account you made is usually both.
check("your own key is you, even when it is also watched",
      FramesParty.of(me, mine: me, watched: [me, them]) == .you(me))
check("a watched address is watched", FramesParty.of(them, mine: me, watched: [them])
        == .watched(them))
check("and anybody else is a stranger",
      FramesParty.of(them, mine: me, watched: []) == .stranger(them))
// **CASE IS A CHECKSUM.** The two spellings are the same address and a name
// given to one must be found for the other — matched case-insensitively, and
// handed BACK in the watch list's own spelling so the name lookup hits.
check("a watched address matches whatever case the receipt used",
      FramesParty.of(them.uppercased(), mine: nil, watched: [them]) == .watched(them))
check("only a stranger is offered a watch door",
      FramesParty.of(them, mine: me, watched: []).isStranger
        && !FramesParty.of(me, mine: me, watched: []).isStranger
        && !FramesParty.of(them, mine: nil, watched: [them]).isStranger)

// --- WHO PAID ---------------------------------------------------------------
func sponsoredBy(_ hash: String, by payer: String, gas: UInt64?) -> FramesMove {
    FramesMove(hash: hash, blockNumber: 1, sender: me, payer: payer,
               succeeded: true, gasUsed: gas,
               effectiveGasPriceWei: gas == nil ? nil : 1_000_000_000, rows: [])
}
let selfPaid = FramesMove(hash: "0xs", blockNumber: 1, sender: me, payer: me,
                          succeeded: true, gasUsed: 100, effectiveGasPriceWei: 1,
                          rows: [])
let third = "0x3333333333333333333333333333333333333333"
let roster = FramesPayers.roster([
    sponsoredBy("0xa", by: them, gas: 100),
    sponsoredBy("0xb", by: third, gas: 500),
    sponsoredBy("0xc", by: them, gas: 100),
    selfPaid,
])
// **SELF-PAID IS DROPPED HERE, NOT ONLY BY THE CALLER.** A roster that trusted
// its caller puts YOU at the top of the list of people who paid for you.
check("a self-paid transaction is not a sponsorship", roster.count == 2)
// A TOTAL ORDER: `Dictionary` iteration order is not stable across runs, and a
// roster that reshuffles between two reads of identical data reads as broken.
check("the biggest sponsor leads", roster.first?.address == third)
check("and their transactions are counted",
      roster.first(where: { $0.id == them.lowercased() })?.count == 2)
check("their spend is the sum of the fees",
      roster.first(where: { $0.id == them.lowercased() })?.gasWei
        == Decimal(200) * Decimal(1_000_000_000))
// **ALL OR NOTHING** — a total missing one term is wrong by that term and says
// so nowhere, and understating a named person's generosity is a specific
// untruth about a specific person.
let partialRoster = FramesPayers.roster([sponsoredBy("0xa", by: them, gas: 100),
                                         sponsoredBy("0xb", by: them, gas: nil)])
check("one unreadable fee abandons the whole total",
      partialRoster.count == 1 && partialRoster[0].gasWei == nil)
check("but the count still stands", partialRoster[0].count == 2)
// An unreadable total sorts LAST rather than as zero.
//
// **THE SENTINEL ITSELF IS UNREACHABLE-BY-CONSTRUCTION AND THAT IS SAID
// RATHER THAN PRETENDED.** A mutation swapping `Decimal(-1)` for `Decimal(0)`
// SURVIVED, and it was right to: a real total is `gasUsed x price` and both
// terms are above zero on any transaction a chain will mine, so nil and zero
// can never be compared against each other. The `-1` is written for the
// intent, not for a case that exists — and no fixture is invented to make it
// look load-bearing, which would be a test proving the wrong thing on purpose.
let mixedTotals = FramesPayers.roster([sponsoredBy("0xa", by: them, gas: nil),
                                       sponsoredBy("0xb", by: third, gas: 1)])
check("an untotalled sponsor sorts below one we could measure",
      mixedTotals.first?.address == third)
// **THE TIEBREAK THAT IS REAL**: two sponsors nobody could total, ordered by
// how many transactions they paid for. The fixture is built so the count and
// the address disagree — `third` sorts first alphabetically and second by
// count — because with both agreeing, dropping the count rule reproduces the
// same order and the mutation survives.
let untotalled = FramesPayers.roster([
    sponsoredBy("0xa", by: third, gas: nil),
    sponsoredBy("0xb", by: them, gas: nil),
    sponsoredBy("0xc", by: them, gas: nil),
])
check("the fixture's count and address orders really disagree",
      third.lowercased() < them.lowercased())
check("two untotalled sponsors are ordered by what they paid for",
      untotalled.first?.address == them && untotalled.count == 2)
check("the moves of one payer are its own",
      FramesPayers.moves(of: them, in: [sponsoredBy("0xa", by: them, gas: 1),
                                        sponsoredBy("0xb", by: third, gas: 1)]).count == 1)
check("and a self-paid move belongs to nobody",
      FramesPayers.moves(of: me, in: [selfPaid]).isEmpty)

// --- SAYING WHEN ------------------------------------------------------------
// **NIL IS A REAL ANSWER.** The header read is bounded, so a move past the
// window has no time — a different thing from a move at the epoch, and
// substituting "now" for a miss is the fake status §83 bans.
check("an unread time is no time", FramesFormat.time(nil) == nil)
let now = Date(timeIntervalSince1970: 1_788_303_520)
check("a fresh block is just now",
      FramesFormat.time(now.addingTimeInterval(-30), now: now) == "just now")
check("an older one is counted in minutes",
      FramesFormat.time(now.addingTimeInterval(-3000), now: now) == "50m ago")
check("and past the hour it stops counting them",
      FramesFormat.time(now.addingTimeInterval(-5508), now: now) == "1h ago")
// **THE BLOCK IS ALWAYS SAID AND THE TIME ONLY WHEN IT WAS READ.** The block
// is the chain's own identity for the moment — exact, and the thing you paste
// into an explorer — so it survives when the time does not.
check("an undated move still names its block",
      FramesFormat.stamp(nil, block: 60_258).contains("60"))
check("and a dated one names both",
      FramesFormat.stamp(now, block: 60_258).contains("60")
        && FramesFormat.stamp(now, block: 60_258).count
             > FramesFormat.stamp(nil, block: 60_258).count)

// --- THE RECEIPT'S HERO FIGURE ----------------------------------------------
let oneETH = Decimal(string: "1000000000000000000")!
// A TRUE MINUS (U+2212), never a hyphen — direction carried only in colour is
// direction lost to anybody who cannot see the colour.
check("money out wears a true minus",
      FramesMoney.signedETH(wei: -oneETH).hasPrefix("\u{2212}"))
check("money in wears a plus", FramesMoney.signedETH(wei: oneETH).hasPrefix("+"))
// **A MOVEMENT OF EXACTLY NOTHING HAS NO DIRECTION** (§83's flat rule).
check("and nothing wears neither",
      !FramesMoney.signedETH(wei: 0).hasPrefix("+")
        && !FramesMoney.signedETH(wei: 0).hasPrefix("\u{2212}"))
// **SIX PLACES, not the balance line's four.** A delta here is routinely the
// fee alone (~0.0002), which four places renders as a flat 0.0000 — a movement
// that happened, shown as nothing, in the largest type on the sheet.
// Asserted on the DIGITS rather than on the whole string: the decimal
// separator is the formatter's locale's, and a fixture that pins it is one
// that fails on a machine set to French for a reason that has nothing to do
// with this rule.
check("a fee-sized delta is still visible",
      FramesMoney.signedETH(wei: Decimal(210_790) * Decimal(1_000_000_000))
        .contains("210"))

if fails > 0 { print("  \(fails) assertion(s) failed"); exit(1) }
print("  ok   encoder: 2 real vectors byte-exact, keccak == the chain's own hash")
SWIFT

build_run() {
  ( cd "$WORK" && swiftc -O -o m/run FramesTransaction.swift RLP.swift Keccak256.swift FramesMoney.swift FramesSection.swift FramesReading.swift m/main.swift 2>&1 )
}
if ! out="$(build_run)"; then echo "✗ harness did not compile"; echo "$out"; exit 1; fi
"$WORK/m/run" || exit 1

# --- mutations --------------------------------------------------------------
# Each is a silent wrong answer: the encoder still compiles, still produces
# bytes, and authorises something nobody asked for.
# RECORD a mutation; the fan-out below runs them. Each is a silent wrong
# answer: the code still compiles, still produces bytes, and authorises
# something nobody asked for.
#
# **They run CONCURRENTLY (2026-09-01).** Every mutation is PURE — it edits its
# own scratch copy and reads nothing the others write — so running them one at
# a time on one core of eight was the whole of this harness's cost: 27
# mutations x a full five-file `-O` compile is ~11 minutes, and it grew every
# time a file was added. `xargs -P`, never a `jobs -r` slot loop: job control
# is OFF in a non-interactive zsh, so `jobs -r` reports NOTHING and the loop
# degrades silently to "launch all 27 at once", which on 8 cores thrashes to
# slower than serial while every check still passes (`verify.sh`'s own paid-for
# trap, 2026-08-19).
MUTN=0
mutate() {
  MUTN=$((MUTN + 1))
  local id
  id="$(printf '%03d' "$MUTN")"
  mkdir -p "$WORK/mut"
  # `printf '%s'`, never `echo`: a trailing newline appended to `from` makes the
  # pattern match nothing, which this harness reports as a STALE mutation — a
  # confusing failure for a mutation that is perfectly correct.
  printf '%s' "$1" > "$WORK/mut/$id.label"
  printf '%s' "$2" > "$WORK/mut/$id.file"
  printf '%s' "$3" > "$WORK/mut/$id.from"
  printf '%s' "$4" > "$WORK/mut/$id.to"
}

F=FramesTransaction.swift
mutate "the fee list flattened to Hegotá's shape" $F \
  '.list([.bytes(RLP.quantity(f.maxPriorityFeePerGas)),
                .bytes(RLP.quantity(f.maxFeePerGas)),
                .bytes(RLP.quantity(f.maxFeePerBlobGas))])' \
  '.bytes(RLP.quantity(f.maxPriorityFeePerGas))'
mutate "the two fee ceilings swapped inside the list" $F \
  'RLP.quantity(f.maxPriorityFeePerGas)),
                .bytes(RLP.quantity(f.maxFeePerGas))' \
  'RLP.quantity(f.maxFeePerGas)),
                .bytes(RLP.quantity(f.maxPriorityFeePerGas))'
mutate "the nonce and sender transposed" $F \
  '.bytes(RLP.quantity(f.nonce)),
         .bytes(f.sender)' \
  '.bytes(f.sender),
         .bytes(RLP.quantity(f.nonce))'
mutate "the nonce dropped from the envelope" $F \
  '.bytes(RLP.quantity(f.nonce)),
         .bytes(f.sender)' \
  '.bytes(f.sender)'
mutate "the blob-hash list dropped" $F \
  ',
         .list(f.blobVersionedHashes.map { .bytes($0) })]' ']'
mutate "the gas slot written as a scalar" $F \
  '.list([.bytes(RLP.quantity(executionGas)),
                          .bytes(RLP.quantity(stateGas))])' \
  '.bytes(RLP.quantity(executionGas))'
mutate "a frame's two budgets transposed" $F \
  'RLP.quantity(executionGas)),
                          .bytes(RLP.quantity(stateGas))' \
  'RLP.quantity(stateGas)),
                          .bytes(RLP.quantity(executionGas))'
mutate "every signature elided, not just empty-msg ones" $F \
  'elided && isElided' 'elided'
mutate "no signature ever elided" $F \
  'elided && isElided' 'false'
mutate "the elision test inverted" $F \
  'var isElided: Bool { msg.isEmpty }' 'var isElided: Bool { !msg.isEmpty }'
mutate "the type byte changed" $F 'txType: UInt8 = 0x06' 'txType: UInt8 = 0x04'
mutate "the chain id changed" $F 'chainID: UInt64 = 81410' 'chainID: UInt64 = 3151908'
mutate "the signature entry's fields reordered" $F \
  '.bytes(signer),
                   .bytes(msg)' \
  '.bytes(msg),
                   .bytes(signer)'
mutate "the VERIFY frame no longer approves payment" $F \
  'Frame(mode: 1, flags: 0x03' 'Frame(mode: 1, flags: 0x01'
mutate "a built transfer sends with no state budget" $F \
  'stateGas: UInt64 = 250_000' 'stateGas: UInt64 = 0'
mutate "the prefix budget counts every frame, not just VERIFY" $F \
  'f.frames.filter { $0.mode == 1 }' 'f.frames.filter { _ in true }'
mutate "the prefix ceiling raised past what the chain allows" $F \
  'maxVerifyGas: UInt64 = 500_000' 'maxVerifyGas: UInt64 = 5_000_000'

F2=FramesMoney.swift
F3=FramesSection.swift
F4=FramesReading.swift
mutate "wei narrowed back to UInt64" $F2 \
  'var total = Decimal(0)' 'var total = Decimal(UInt64(body, radix: 16) ?? 0); if true { return total }; var unused = Decimal(0); _ = unused'
mutate "an empty balance read as zero" $F2 \
  'guard !body.isEmpty, body.count <= 64 else { return nil }' \
  'guard body.count <= 64 else { return nil }
        if body.isEmpty { return Decimal(0) }'
mutate "the balance rounded to nearest" $F2 '.down)' '.plain)'
mutate "the wei-per-ETH divisor losing a zero" $F2 \
  '"1000000000000000000"' '"100000000000000000"'
mutate "a conditional scope ahead of an unconditional one" $F3 \
  '[.home, .activity, .frames, .sponsors]' '[.home, .frames, .activity, .sponsors]'
mutate "the remembered scope falling back to the first present one" $F3 \
  'guard let wanted, present.contains(wanted) else { return .home }' \
  'guard let wanted, present.contains(wanted) else { return present.first ?? .home }'
mutate "a strip drawn over a single chip" $F3 'present.count > 1' 'present.count > 0'
mutate "sponsors shown on every address" $F3 'case .sponsors: return sponsors' 'case .sponsors: return true'
mutate "frames marked unconditional" $F3 \
  'case .frames, .sponsors: return true' 'case .frames, .sponsors: return false'
mutate "a chip growing a dot that can never honestly light" $F3 \
  'static func attention() -> Set<FramesSection> { [] }' \
  'static func attention() -> Set<FramesSection> { [.frames] }'


mutate "money read from status instead of effect" $F4 \
  'return outcome.logCount > 0' 'return outcome.succeeded'
mutate "a rolled-back frame reported as landed" $F4 \
  'return outcome.logCount > 0' 'return true'
mutate "a VERIFY frame asked whether its value landed" $F4 \
  'guard body.contains(where: { $0 != "0" }) else { return nil }' \
  'if body.isEmpty { return false }'
mutate "an unread frame answering false instead of nil" $F4 \
  'guard let outcome else { return nil }' \
  'guard let outcome else { return false }'
mutate "an unread receipt reported as nothing moved" $F4 \
  'guard answerable else { return nil }' 'if !answerable { return false }'
mutate "the gas total summed from the frames" $F4 \
  'var gasUsed: UInt64?' 'var gasUsedRaw: UInt64?
    var gasUsed: UInt64? { rows.compactMap { $0.outcome?.gasUsed }.reduce(0, +) }'
mutate "sponsorship decided by case" $F4 \
  'payer.lowercased() != sender.lowercased()' 'payer != sender'

# --- stitching (prd §548 sixth follow-up) ------------------------------------
# The most expensive failure in this file: each of these compiles, produces a
# transaction the chain accepts, and makes the all-or-nothing control a lie.
mutate "the atomic flag being the wrong bit" $F \
  'static let atomicFlag: UInt64 = 0x04' \
  'static let atomicFlag: UInt64 = 0x02'
mutate "all-or-nothing flagging nothing at all" $F \
  'let joined = atomic && index < last' \
  'let joined = false'
# **THE ONE THE CHAIN CAUGHT AND THE HARNESS DID NOT.** Flagging the last frame
# too is a transaction this node refuses outright — `Frame N: atomic batch flag
# on last frame` — so the off-by-one here is not a subtle wrongness, it is a
# send that cannot go at all.
mutate "the atomic flag reaching the last payload frame" $F \
  'let joined = atomic && index < last' \
  'let joined = atomic'
mutate "the VERIFY frame dropped from a stitch" $F \
  'frames: [Frame(mode: 1, flags: 0x03, target: sender,
                                     executionGas: executionGas, stateGas: stateGas,
                                     value: Data(), data: Data())]
                          + legs.enumerated().map { index, leg in' \
  'frames: legs.enumerated().map { index, leg in'
mutate "the VERIFY frame no longer approving payment" $F \
  'frames: [Frame(mode: 1, flags: 0x03, target: sender,
                                     executionGas: executionGas, stateGas: stateGas,
                                     value: Data(), data: Data())]' \
  'frames: [Frame(mode: 1, flags: 0x01, target: sender,
                                     executionGas: executionGas, stateGas: stateGas,
                                     value: Data(), data: Data())]'
mutate "a payload frame built as a VERIFY frame" $F \
  'return Frame(mode: 2, flags: joined ? atomicFlag : 0x00,' \
  'return Frame(mode: 1, flags: joined ? atomicFlag : 0x00,'
mutate "the legs reversed" $F \
  '+ legs.enumerated().map { index, leg in' \
  '+ legs.reversed().enumerated().map { index, leg in'
# **THE PREVIEW'S LICENCE, AS A MUTATION.** The send sheet draws its
# all-or-nothing preview by asking `stitched` for the joined shape once and
# scaling the ties by the toggle, which is exact only while `flags` is the sole
# difference between the two. Give the atomic path a second effect and that
# preview silently starts promising a shape the signer does not produce.
mutate "all-or-nothing quietly changing a frame's budget too" $F \
  'executionGas: executionGas, stateGas: stateGas,
                                           value: leg.value' \
  'executionGas: joined ? executionGas &* 2 : executionGas, stateGas: stateGas,
                                           value: leg.value'

# --- the row's new readings -------------------------------------------------
mutate "the VERIFY frame counted as a recipient" $F4 \
  'for row in rows where row.frame.mode != 1 {' \
  'for row in rows {'
mutate "the sender not excluded from its own recipients" $F4 \
  'guard to.lowercased() != sender.lowercased() else { continue }' \
  'if false { continue }'
mutate "an unread fee reported as zero" $F4 \
  'guard let gasUsed, let price = effectiveGasPriceWei else { return nil }' \
  'guard let gasUsed else { return nil }; let price = effectiveGasPriceWei ?? 0'
mutate "a sponsor's fee presented as yours" $F4 \
  'var feeWeiIfSelfPaid: Decimal? { sponsored ? nil : feeWei }' \
  'var feeWeiIfSelfPaid: Decimal? { feeWei }'


# --- the sheets' readings (prd §548 ninth follow-up) -------------------------
# Every one of these renders as a perfectly ordinary sheet. That is the point:
# a wrong verdict, a stranger named as you, a sponsor's spend understated and a
# guessed timestamp all draw exactly like the right answer.
mutate "a rolled-back transaction called Ran" $F4 \
  'if movedValue == true && !succeeded { return .failedButMoved }
        if !rolledBack.isEmpty { return .rolledBack }' \
  'if movedValue == true && !succeeded { return .failedButMoved }'
mutate "failed-and-moved demoted below rolled-back" $F4 \
  'if movedValue == true && !succeeded { return .failedButMoved }
        if !rolledBack.isEmpty { return .rolledBack }' \
  'if !rolledBack.isEmpty { return .rolledBack }
        if movedValue == true && !succeeded { return .failedButMoved }'
mutate "the verdict read from status alone" $F4 \
  'if movedValue == true && !succeeded { return .failedButMoved }' \
  'if false { return .failedButMoved }'
mutate "a rolled-back verdict treated as untroubled" $F4 \
  'var isTrouble: Bool { self != .ran }' \
  'var isTrouble: Bool { self == .failed }'
mutate "the watch list beating your own key" $F4 \
  'if let mine, mine.lowercased() == key { return .you(mine) }' \
  'if false, let mine { return .you(mine) }'
mutate "an address matched case-sensitively" $F4 \
  'if let match = watched.first(where: { $0.lowercased() == key }) { return .watched(match) }' \
  'if let match = watched.first(where: { $0 == address }) { return .watched(match) }'
mutate "your own address offered a watch door" $F4 \
  'var isStranger: Bool { if case .stranger = self { return true }; return false }' \
  'var isStranger: Bool { if case .watched = self { return false }; return true }'
mutate "a self-paid transaction counted as a sponsorship" $F4 \
  'for move in moves where move.sponsored {' \
  'for move in moves {'
mutate "an unreadable fee treated as zero in a sponsor total" $F4 \
  'if let fee = move.feeWei { totals[key]! += fee } else { complete[key] = false }' \
  'totals[key]! += move.feeWei ?? 0'
mutate "the sponsor roster left in dictionary order" $F4 \
  'if x != y { return x > y }
            if a.count != b.count { return a.count > b.count }
            return a.id < b.id' \
  'return false'
mutate "the sponsor roster's count tiebreak dropped" $F4 \
  'if a.count != b.count { return a.count > b.count }' \
  'if false { return a.count > b.count }'
mutate "a sponsor's moves taken from the wrong payer" $F4 \
  '$0.sponsored && $0.payer.lowercased() == payer.lowercased()' \
  '$0.sponsored && $0.sender.lowercased() == payer.lowercased()'
mutate "an unread time rendered as the epoch" $F4 \
  'guard let date else { return nil }
        let seconds = max(0, now.timeIntervalSince(date))' \
  'let seconds = max(0, now.timeIntervalSince(date ?? Date(timeIntervalSince1970: 0)))'
mutate "the dateline dropping the block it could always state" $F4 \
  'guard let date else { return String(localized: "Block \(number)") }' \
  'guard let date else { return "" }'
mutate "a signed figure losing its minus" $F2 \
  'let sign = wei < 0 ? "\u{2212}" : (wei > 0 ? "+" : "")' \
  'let sign = wei > 0 ? "+" : ""'
mutate "a movement of nothing given a direction" $F2 \
  'let sign = wei < 0 ? "\u{2212}" : (wei > 0 ? "+" : "")' \
  'let sign = wei < 0 ? "\u{2212}" : "+"'
mutate "the receipt hero rounded to the balance line's four places" $F2 \
  'NSDecimalRound(&rounded, &quotient, 6, .down)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 6
        formatter.maximumFractionDigits = 6
        formatter.usesGroupingSeparator = true
        let text = formatter.string(from: rounded as NSDecimalNumber) ?? "0"
        // A movement of exactly nothing has no direction' \
  'NSDecimalRound(&rounded, &quotient, 4, .down)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 4
        formatter.maximumFractionDigits = 4
        formatter.usesGroupingSeparator = true
        let text = formatter.string(from: rounded as NSDecimalNumber) ?? "0"
        // A movement of exactly nothing has no direction'

# --- the fan-out must be LAST, and this proves it -----------------------------
# **A mutation recorded AFTER this block is never dispatched, and the run still
# goes green** — measured on this file, 2026-09-01: seven `$F4` mutations were
# appended below the fan-out, so the completeness guard ran while `MUTN` was
# still 27, agreed with itself, passed, and the summary then printed "34
# mutations". Seven checks silently not run, under a tick.
#
# It is a FILE-ORDER bug, so no amount of care inside the block can catch it —
# only the file can. This reads itself: the last `mutate` call must precede the
# fan-out. It is the completeness guard the completeness guard needed.
MUT_LAST="$(grep -n '^mutate ' "$SELF" | tail -1 | cut -d: -f1)"
FANOUT_AT="$(grep -n '^# --- run every recorded mutation, concurrently' "$SELF" | head -1 | cut -d: -f1)"
if [[ -n "$MUT_LAST" && -n "$FANOUT_AT" ]] && (( MUT_LAST > FANOUT_AT )); then
  echo "✗ a mutation is declared at line $MUT_LAST, BELOW the fan-out at line $FANOUT_AT — it would never run and the pass would still go green. Move it above."
  exit 1
fi

# --- run every recorded mutation, concurrently -------------------------------
# One core per mutation up to the machine's count. Output is KEPT and sorted by
# id so the report reads in declaration order regardless of which finished
# first — `xargs` interleaves, and a mutation list that reshuffles between runs
# is one nobody can diff.
: > "$WORK/mut-results"
ls "$WORK"/mut/*.label | sed 's#.*/##; s#\.label$##' \
  | xargs -P "$(sysctl -n hw.ncpu)" -I{} zsh "$SELF" --mutate "$WORK" {} \
  >> "$WORK/mut-results" 2>&1

MUT_FAILS=0
MUT_OK=0
while IFS='|' read -r verdict mid label; do
  case "$verdict" in
    CAUGHT)   printf '  ok   catches  %s\n' "$label"; MUT_OK=$((MUT_OK + 1)) ;;
    SURVIVED) printf '✗ mutation SURVIVED: %s\n' "$label"; MUT_FAILS=$((MUT_FAILS + 1)) ;;
    STALE)    printf "✗ mutation '%s' matched nothing — it is stale and has been testing the shipped code\n" "$label"
              MUT_FAILS=$((MUT_FAILS + 1)) ;;
    *)        [[ -n "$verdict" ]] && printf '  %s\n' "$verdict" ;;
  esac
done < <(sort "$WORK/mut-results")

# Every mutation must have reported. A child that died without a line is a
# mutation nobody ran, and a silently skipped mutation is exactly the false
# green this whole file exists to prevent.
if (( MUT_OK + MUT_FAILS != MUTN )); then
  echo "✗ $((MUTN - MUT_OK - MUT_FAILS)) of $MUTN mutation(s) never reported — they did not run"
  exit 1
fi
(( MUT_FAILS == 0 )) || { echo "  $MUT_FAILS mutation(s) failed"; exit 1; }
echo "  ok   drift guards: the envelope stays seven fields and never grows Hegotá's three"
echo "✓ frames transaction self-test passed — encoder, 2 real vectors, $MUTN mutations"
