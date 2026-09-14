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
# **THE CHAIN THOSE FIXTURES CAME FROM WAS RESET (2026-09-08).** Vectors 1 and
# 2 were measured against a generation of chain 81410 that no longer exists:
# the chain id is unchanged, genesis moved to 0x4225d878…27ab, the head fell to
# ~14,000 blocks, and vector 1's transaction now answers `null`. They still
# prove the ENCODER, which is what ships — they are real ethrex type-0x06 bytes
# and a wrong encoder still fails them — but their "keccak matches the RPC's
# own hash" claim can no longer be re-derived from a node.
#
# VECTOR 1R below restores exactly that claim against the chain that exists
# now, and its own block is the record of what was re-measured, including the
# one data-carrying transaction that does not reproduce and is left open (prd
# §654a). Read that block rather than this paragraph for the current state.
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
  # `-Onone`, not `-O`: 97% of a pure-logic harness's wall time is the optimizer,
  # and it buys nothing an assertion can see. NOT a blanket rule — `-O` can change
  # a harness's OBSERVABLE behaviour (a trapping one prints NOTHING under `-O`) —
  # so this file was proven equivalent run-for-run by
  # `scripts/support/harness-opt-probe.sh` before the swap (2026-09-05, 2.9x faster).
  # Re-probe before trusting it again after adding mutations.
  if ( cd "$MW" && swiftc -Onone -o m/run2 FramesTransaction.swift RLP.swift Keccak256.swift FramesMoney.swift FramesSection.swift DevnetTokens.swift RoomFrames.swift FramesReading.swift FramesChainWatch.swift FramesSponsor.swift FramesPasskeyAccount.swift m/main.swift 2>/dev/null ) \
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
# The family's shared frames reading (prd §698) — `FramesFrames` is written
# against it, and one definition of a step is what stopped this room's headline
# disagreeing with its own list.
RFRAMES="Casberi/Casberi/Model/RoomFrames.swift"
# **Foundation-only, and compiled REAL (prd §688).** `FramesAccount` carries
# what it holds beyond the coin now, so the reading file names `DevnetTokens`.
# Stubbing it would let the harness disagree with the app about a type the app
# stores; it is Foundation-only by design for exactly this.
TOKENS="Casberi/Casberi/Model/DevnetTokens.swift"
# **What the chain itself is doing (prd §728)** — relaunch, stall, finality and
# where a pending send is. Foundation-only, compiled whole: nothing on this
# machine can make a devnet stall or relaunch on demand.
CHAINW="Casberi/Casberi/Model/FramesChainWatch.swift"
# **Asking somebody else to pay (prd §728c)** — the sponsored shape, the
# request one phone hands another, and what the sponsor's phone refuses.
SPONSOR="Casberi/Casberi/Model/FramesSponsor.swift"
# **The passkey account (prd §728d)** — its 64 bytes of code, its CREATE2
# address, and the transaction it signs. The code is RUN here, below.
PASSKEY="Casberi/Casberi/Model/FramesPasskeyAccount.swift"
KEY="Casberi/Casberi/Model/FramesKey.swift"
SEND="Casberi/Casberi/Model/FramesSend.swift"
BRIDGE="Casberi/Casberi/Model/FramesBridge.swift"
for f in "$TX" "$RLPF" "$KC" "$MONEY" "$SECT" "$READ" "$KEY" "$SEND" "$BRIDGE" "$CHAINW" "$SPONSOR" "$PASSKEY"; do
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
# **`accounts` LEAVES THIS LIST (prd §689).** The guard's reason was §548's:
# "Hegotá has it and this chain cannot fill it." That was about a ROSTER — a
# list short by construction, one row on most installs, §83's dead control.
# The scope drawn there now is the CONNECTIONS between what you watch, which
# is not a roster, needs two addresses rather than one, and which §688 made
# ordinary here by seeding a second.
# **`permissions` LEAVES THIS LIST TOO (prd §692), and the reason it was on it
# is worth keeping.** The guard read "no standing authority", which is still
# measured and still true: a VERIFY frame's APPROVE is granted and spent inside
# the one transaction carrying it, so nothing survives to revoke. What the
# user's ruling adds is that an EXERCISED permission is still one — a sponsor
# was allowed to pay — so the scope has a real subject and a real empty state.
# The two that stay are absences this chain genuinely cannot fill: no UTXO
# vault, no keyed nonces.
for absent in nonces coins; do
  if grep -qE "case $absent" "$WORK/sect.nc"; then
    echo "✗ FramesSection grew a \`$absent\` scope — Hegotá has it and this chain cannot fill it; re-measure before adding one"; exit 1
  fi
done
echo "  ok   drift guards: the strip keeps only the scopes this chain can fill"

# --- the moments (2026-09-01) -----------------------------------------------
# Five small things that are all one class: a room says what JUST HAPPENED, and
# every one of them fails as a false claim rather than as a missing animation.
# Read from COMMENT-STRIPPED copies throughout — all three files document these
# rules by naming what they must not do (the Obsidian/Cursor lesson).
CARD="Casberi/Casberi/Screens/FramesRoomCard.swift"
# FeedScreen is split across files (prd §718). Checks read the room as ONE text,
# so a guard can neither fail nor pass because its code moved next door.
FEED_DIR="$(mktemp -d -t feedscreen)"
FEED="$FEED_DIR/FeedScreen.swift"
cat Casberi/Casberi/Screens/FeedScreen.swift Casberi/Casberi/Screens/FeedScreen+WalletRoom.swift > "$FEED"
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

# THE LEGS LIST'S TIE COMES FROM THE ENCODER TOO (prd §571). The list now draws
# a tie between joined rows, which is a SECOND drawing of the same flag — and
# the only thing keeping it honest is that `FeedScreen` answers `joins` by
# reading the run it already builds, rather than re-spelling "every leg but the
# last". A re-spelling agrees with the signer right up until somebody edits one
# of them, on the control that decides whether a failed batch leaves money with
# a stranger.
python3 - "$WORK/feed.nc" <<'PYJOIN' || exit 1
import sys, io
src = io.open(sys.argv[1], encoding="utf-8").read()
j = src.find("joins: { legs, atomic in")
if j < 0:
    print("\u2717 the Frames stitch no longer tells the sheet which legs are joined \u2014 the list would draw no tie, or a decorative one")
    sys.exit(1)
body = src[j:j + 500]
if "framesPreviewRun(" not in body:
    print("\u2717 `joins` no longer reads the shipped encoder's own run \u2014 it would be a second spelling of the atomic rule")
    sys.exit(1)
if "joinedToNext" not in body:
    print("\u2717 `joins` no longer comes through FramesFrameRow.joinedToNext")
    sys.exit(1)
if "atomicFlag" in body or "startsBatch" in body or "count - 1" in body:
    print("\u2717 `joins` re-derives the atomic rule instead of asking the encoder")
    sys.exit(1)
sys.exit(0)
PYJOIN
echo "  ok   drift guards: the legs list's tie is the encoder's own join, not a second spelling"

# EVERY DRAWING IN THIS ROOM ARRIVES. Each is a `Canvas`, which is why
# `design-motion-audit` — which looks for proportional shapes and
# GeometryReader — cannot see them, and why a room where everything else
# arrives kept two that simply were. Reduce Motion is `chartWipe`'s own
# contract, so requiring the shared component is requiring the guarantee.
for drawing in FramesSequenceStrip; do
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
# **AND THE DRAWING THAT REPLACED `FramesMovementBars` (prd §687/§688).** The
# signed value bars are deleted with the Activity scope they served, and what
# draws there now is the shared `ActivityBars` — also a `Canvas`, also
# invisible to `design-motion-audit`, so the ruling follows the drawing to the
# file it moved to rather than lapsing with the name it was pinned on.
python3 - "Casberi/Casberi/Screens/RoomActivityChart.swift" <<'PYSHARED' || exit 1
import sys, io
src = io.open(sys.argv[1], encoding="utf-8").read()
i = src.find("struct ActivityBars: View")
if i < 0:
    print("\u2717 ActivityBars is gone \u2014 every Activity scope in the family draws it"); sys.exit(1)
if "chartWipe(reduceMotion:" not in src[i:]:
    print("\u2717 ActivityBars no longer arrives \u2014 a Canvas is invisible to design-motion-audit")
    sys.exit(1)
sys.exit(0)
PYSHARED
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
cp "$RFRAMES" "$WORK/RoomFrames.swift"
cp "$TOKENS" "$WORK/DevnetTokens.swift"
cp "$CHAINW" "$WORK/FramesChainWatch.swift"
cp "$SPONSOR" "$WORK/FramesSponsor.swift"
cp "$PASSKEY" "$WORK/FramesPasskeyAccount.swift"
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

// ============ VECTOR 1R — THE SAME PROOF, ON THE CHAIN THAT EXISTS NOW
// (2026-09-08, prd §654a). The Frames devnet RESTARTED: genesis moved to
// 0x4225d878…, the head fell from 56,503 blocks to ~14,000, and vector 1's
// transaction above answers `null`. Vectors 1 and 2 still prove the ENCODER —
// they are stored bytes and a wrong encoder still fails them — but their
// headline claim, "keccak matching the RPC's own hash", became unverifiable
// against a chain nobody can query. This vector restores it.
//
// **THE ENVELOPE DID NOT MOVE ACROSS THE RESTART, and that was measured, not
// assumed**: four live type-0x06 transactions were rebuilt from the RPC's own
// JSON and run through this encoder, and three reproduced byte-exactly. The
// fourth is the ONLY transaction on that chain carrying a payload (800 bytes
// in frame 1); every other field on it is structurally identical to the three
// that match, and it is unexplained — not an RLP long-string bug (1..65536
// were checked against the spec) and not a truncated render (no data length
// from 1 to 4096 reproduces its hash). It is recorded rather than hidden.
//
// It blocks nothing, because THE APP CANNOT PRODUCE THAT SHAPE: every frame
// `FramesTransaction` builds passes `data: Data()` — the plain transfer and
// the stitched multi-leg path alike — so the empty-data transfer is the only
// thing this seat ever signs, and that is the shape which reproduces 3 of 3.
// If a future pass gives Frames a data-carrying frame, THIS is the open
// question it must close first.
let s1r = hx("0x2c835d53b4c19cb1dd6c7cf28c4b87240f7e5a15")
let v1r = FramesTransaction.Fields(
    chainID: 0x13e02, nonce: 0x11, sender: s1r,
    frames: [
        .init(mode: 1, flags: 0x03, target: s1r,
              executionGas: 0x186a0, stateGas: 0x3d090, value: Data(), data: Data()),
        .init(mode: 2, flags: 0x00, target: hx("0xfcebeee7116422243d98a585d5337f116ea3ed16"),
              executionGas: 0x186a0, stateGas: 0x3d090, value: hx("0x11c37937e08000"), data: Data()),
    ],
    signatures: [
        .init(scheme: 1, signer: s1r, msg: Data(),
              signature: hx("0x008a1d6fcb467b17b40a8fd350948a6e3e5592ed9b43f174515c89fc885c45fbe61046dd308d58152b647e0a4b8179d7a450bf114ff350d6daf2effff55653beef")),
    ],
    maxPriorityFeePerGas: 0x3b9aca00, maxFeePerGas: 0x2540be400,
    maxFeePerBlobGas: 0, blobVersionedHashes: [])
check("vector 1R's keccak is the POST-RESTART chain's own transaction hash",
      keccakHex(FramesTransaction.encoded(v1r))
        == "0x7b75f255ab1ecc85bd7bb4610606ee92204688b6a902c2a0a7834c06e7b7be63")
// The signer is written LITERALLY here where HegotaSend writes it EMPTY. That
// divergence survived the restart, and it is the one an encoder shared between
// the two chains would get silently wrong.
check("vector 1R still carries a literal signer, not Hegota's empty one",
      RLP.hex(FramesTransaction.encoded(v1r)).contains("942c835d53b4c19cb1dd6c7cf28c4b87240f7e5a1580b841"))

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
// **HOLDINGS LEADS THE TAIL NOW, and `frames` still leads the frame scopes
// (prd §688).** The older ruling was "frames leads the conditional tail,
// because frame transactions are the reason this chain exists" — true, and
// written when Holdings did not exist here. It does now, and the rail's order
// is a FAMILY fact rather than this room's: Wallet, Hegotá and vibenet all put
// Holdings third, so a person moving between rooms finds the same chip in the
// same place. What the old ruling protected is intact and is asserted below:
// nothing about frames has moved relative to the scopes it outranks.
check("holdings leads the conditional tail, as it does in every other room",
      FramesSection.order[firstConditional] == .holdings)
// **ACCOUNTS SITS WHERE THE FAMILY PUTS IT (prd §689)** — straight after
// Holdings, as Wallet, Hegotá and vibenet all have it.
check("accounts follows holdings",
      FramesSection.order.firstIndex(of: .accounts)!
        == FramesSection.order.firstIndex(of: .holdings)! + 1)
check("frames still leads the scopes it outranks",
      FramesSection.order.firstIndex(of: .frames)! < FramesSection.order.firstIndex(of: .permissions)!)
// **SPONSORS BECAME PERMISSIONS (prd §692)** — one chip for one question in
// every room. The scope name is asserted rather than left to the order list,
// because the fold is a ruling and the old name reads as the tidier one.
check("the sponsor scope is called Permissions", FramesSection.permissions.label == "Permissions")
check("`sponsors` is gone as a scope",
      !FramesSection.allCases.contains { $0.rawValue == "sponsors" })

// PRESENT: EVERY scope, on every address (prd §611; user: "it should [show all
// the scopes] even if they are not present"). The gate is gone — a bare address
// still reaches all four chips, each with an empty state of its own.
let full = FramesSection.present()
check("every scope is present, in order", full == FramesSection.order)
check("no scope is hidden from anybody", full.count == FramesSection.allCases.count)
// THE OBLIGATION THAT MAKES THAT HONEST. A chip onto nothing is the dead control
// §83 bans; the two scopes that can be empty are allowed only because each says
// what it would hold.
for s in FramesSection.allCases where s != .home {
    check("\(s.rawValue) names its own empty state", !(s.emptyHeadline ?? "").isEmpty)
    check("\(s.rawValue) says what it would hold", !(s.emptyBody ?? "").isEmpty)
    check("\(s.rawValue)'s empty state is not its summary restated", s.emptyBody != s.summary)
    check("\(s.rawValue)'s empty state teaches rather than labels", (s.emptyBody ?? "").count > 24)
}
let emptyBodies = FramesSection.allCases.compactMap(\.emptyBody)
check("no two scopes explain themselves the same way", Set(emptyBodies).count == emptyBodies.count)
let emptyHeads = FramesSection.allCases.compactMap(\.emptyHeadline)
check("no two scopes name the same empty state", Set(emptyHeads).count == emptyHeads.count)
check("home carries no empty copy, because it can never be empty",
      FramesSection.home.emptyHeadline == nil && FramesSection.home.emptyBody == nil)
for words in emptyBodies {
    let lower = words.lowercased()
    check("an empty scope states a fact and offers no door",
          !lower.contains("tap ") && !lower.contains("top up") && !lower.contains("send "))
}

// RESOLVE falls back to `.home`, never to "the first present scope" — an
// unreachable branch that quietly picks `frames` is how a room starts opening
// somewhere nobody chose.
check("an unremembered scope opens Home",
      FramesSection.resolve(nil, present: FramesSection.order) == .home)
check("a remembered scope that is still present is kept",
      FramesSection.resolve(.frames, present: [.home, .activity, .frames]) == .frames)
check("a remembered scope whose content is gone falls back to Home",
      FramesSection.resolve(.permissions, present: [.home, .activity]) == .home)
check("the fallback is Home and not the first present scope",
      FramesSection.resolve(.permissions, present: [.activity, .home]) == .home)

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

// --- THE CHAIN ITSELF (prd §728) -------------------------------------------
// Measured 2026-09-13: every host reported block 75,685, 142,463 seconds old.
// Nothing on this machine can make a chain stall, relaunch or finalize, so
// these fixtures are the only proof the readings hold.
typealias CW = FramesChainWatch
let genesisNow = "0x4225d87803ea7b0da245a4390c18e8afe373cb0eb1482e218e1cdc200cfc27ab"
let genesisOld = "0x372a923b" + String(repeating: "0", count: 56)
check("a first read ADOPTS its genesis silently — an install that arrives after a relaunch lost nothing",
      CW.verdict(baseline: nil, observed: genesisNow) == .adopt(genesisNow))
check("the same genesis in another case is the same chain",
      CW.verdict(baseline: "0x" + genesisNow.dropFirst(2).uppercased(), observed: genesisNow) == .same)
check("a different genesis is a relaunch",
      CW.verdict(baseline: genesisOld, observed: genesisNow) == .relaunched(genesisNow))
check("an unread genesis is no verdict", CW.verdict(baseline: genesisOld, observed: nil) == .unread)
check("a malformed hash is no verdict", CW.verdict(baseline: genesisOld, observed: "0x1234") == .unread)
let t0 = Date(timeIntervalSince1970: 1_789_300_000)
check("a head number watched for nine minutes is not a stall",
      CW.stallAge(headAt: t0.addingTimeInterval(-540), headSince: t0.addingTimeInterval(-540), now: t0) == nil)
check("eleven minutes without a new block is",
      CW.stallAge(headAt: t0.addingTimeInterval(-660), headSince: t0.addingTimeInterval(-660), now: t0) != nil)
check("AN OLD TIMESTAMP ALONE IS NOT A STALL — a chain catching up makes blocks dated a day and a half ago",
      CW.stallAge(headAt: t0.addingTimeInterval(-142_463), headSince: nil, now: t0) == nil)
check("nor is a head first seen just now, however old its timestamp",
      CW.stallAge(headAt: t0.addingTimeInterval(-142_463), headSince: t0, now: t0) == nil)
check("once observed, a stall's age is the head block's own when that is longer",
      CW.stallAge(headAt: t0.addingTimeInterval(-142_463), headSince: t0.addingTimeInterval(-700), now: t0) == 142_463)
check("the same head number keeps its first sighting",
      CW.headSince(previousBlock: 75_685, previousSince: t0.addingTimeInterval(-900),
                   observedBlock: 75_685, now: t0).since == t0.addingTimeInterval(-900))
check("a new head number starts a new sighting",
      CW.headSince(previousBlock: 75_685, previousSince: t0.addingTimeInterval(-900),
                   observedBlock: 75_704, now: t0).since == t0)
check("an unread head keeps what was known",
      CW.headSince(previousBlock: 75_685, previousSince: t0.addingTimeInterval(-900),
                   observedBlock: nil, now: t0).since == t0.addingTimeInterval(-900))
check("the measured stall reads in hours",
      CW.headline(.stalled(age: 142_463), now: t0) == "Stalled for 39 hours")
check("a relaunch outranks a stall — a wiped chain is not one to wait for",
      CW.alert(relaunchObservedAt: t0.addingTimeInterval(-3600), headAt: t0.addingTimeInterval(-142_463),
               headSince: t0.addingTimeInterval(-3600), now: t0)
        == .relaunched(observedAt: t0.addingTimeInterval(-3600)))
check("a relaunch a week old stops being said, and the stall is still said",
      CW.alert(relaunchObservedAt: t0.addingTimeInterval(-8 * 86_400), headAt: t0.addingTimeInterval(-142_463),
               headSince: t0.addingTimeInterval(-3600), now: t0)
        == .stalled(age: 142_463))
check("a healthy chain says nothing",
      CW.alert(relaunchObservedAt: nil, headAt: t0.addingTimeInterval(-6), headSince: t0.addingTimeInterval(-6), now: t0) == nil)
check("a relaunch 'observed' in the future is not said",
      CW.alert(relaunchObservedAt: t0.addingTimeInterval(60), headAt: nil, headSince: nil, now: t0) == nil)
check("the block at the finalized head is final", CW.isFinal(block: 100, finalized: 100) == true)
check("the one above it is not yet", CW.isFinal(block: 101, finalized: 100) == false)
check("an unread finalized head says nothing", CW.isFinal(block: 1, finalized: nil) == nil)

// --- WHERE A PENDING SEND IS (prd §728) --------------------------------------
let sentAt = t0.addingTimeInterval(-60)
check("a block wins outright",
      CW.pendingState(sentAt: sentAt, deadline: t0.addingTimeInterval(-600), now: t0,
                      sightings: [.absent, .mined, nil]) == .mined)
check("past its deadline it cannot land, even while a node still pools it",
      CW.pendingState(sentAt: sentAt, deadline: t0.addingTimeInterval(-30), now: t0,
                      sightings: [.pooled, .pooled, .pooled]) == .expired)
check("inside the clock grace it is still queued",
      CW.pendingState(sentAt: sentAt, deadline: t0.addingTimeInterval(-5), now: t0,
                      sightings: [.pooled, .absent, .absent]) == .queued)
check("every host answering absent, late enough, is dropped",
      CW.pendingState(sentAt: sentAt, deadline: nil, now: t0,
                      sightings: [.absent, .absent, .absent]) == .dropped)
check("ONE SILENT HOST keeps it sending — a host that did not answer did not say no",
      CW.pendingState(sentAt: sentAt, deadline: nil, now: t0,
                      sightings: [.absent, nil, .absent]) == .sending)
check("absent everywhere seconds after sending is propagation, not loss",
      CW.pendingState(sentAt: t0.addingTimeInterval(-5), deadline: nil, now: t0,
                      sightings: [.absent, .absent, .absent]) == .sending)
check("a node answering null is absent", CW.sighting(answered: true, transaction: nil) == .absent)
check("a node not answering is no sighting", CW.sighting(answered: false, transaction: nil) == nil)
check("a null block number is pooled",
      CW.sighting(answered: true, transaction: ["blockNumber": NSNull()]) == .pooled)
check("a block number is mined",
      CW.sighting(answered: true, transaction: ["blockNumber": "0x1e0d"]) == .mined)
check("the countdown is minutes and seconds",
      CW.pendingLine(state: .queued, deadline: t0.addingTimeInterval(125), now: t0)
        == "Waiting for a block · 2:05 left")
check("dropped and expired are final words and queued is not",
      CW.PendingState.dropped.isFinal && CW.PendingState.expired.isFinal && !CW.PendingState.queued.isFinal)

// --- SKIPPED IS NOT FAILED (prd §728) ------------------------------------------
let batchReceipt: [String: Any] = ["frameReceipts": [
    ["status": "0x1", "gasUsed": "0x64", "logs": [[String: Any]]()],
    ["status": "0x0", "gasUsed": "0x186a0", "logs": [[String: Any]]()],
    ["status": "0x2", "gasUsed": "0x0", "logs": [[String: Any]]()],
]]
let batchOut = FramesRead.outcomes(inReceipt: batchReceipt)
check("status 0x2 reads as skipped", batchOut.count == 3 && batchOut[2].skipped && !batchOut[2].succeeded)
check("a reverted frame is not skipped", !batchOut[1].skipped)
check("a success is neither", batchOut[0].succeeded && !batchOut[0].skipped)
func payFrame(_ to: String, value: String = "0x1", data: String = "0x") -> FramesRead.Frame {
    .init(mode: 2, flags: 0, target: to, executionGas: 100_000, stateGas: 250_000, value: value, data: data)
}
let batchRuns = FramesFrames.runs([FramesMove(
    hash: "0xk", blockNumber: 1, sender: "0xa", payer: "0xa", succeeded: false,
    rows: [FramesFrameRow(frame: payFrame("0xb"), outcome: batchOut[1]),
           FramesFrameRow(frame: payFrame("0xc"), outcome: batchOut[2])],
    deltaWei: 0)])
check("a skipped step is its own outcome in the census",
      batchRuns.first?.steps.map(\.outcome) == [.failed, .skipped])
let skipMix = RoomFrames.mix(batchRuns)
check("and it is counted apart from the failure", skipMix?.skipped == 1 && skipMix?.failed == 1)

// --- WHO SIGNED (prd §728) ----------------------------------------------------
let signedTx: [String: Any] = ["signatures": [
    ["scheme": "0x1", "signer": "0x2c835d53b4c19cb1dd6c7cf28c4b87240f7e5a15", "msg": "0x", "signature": "0x00"],
    ["scheme": "0x2", "signer": "0x", "msg": "0x" + String(repeating: "ab", count: 32), "signature": "0x00"],
]]
let readSigs = FramesRead.signatures(inTransaction: signedTx)
check("signatures read in the envelope's order", readSigs.map(\.scheme) == [1, 2])
check("a literal signer is kept", readSigs.first?.signer == "0x2c835d53b4c19cb1dd6c7cf28c4b87240f7e5a15")
check("an empty signer is no address, and resolves to the sender",
      readSigs.last?.signer == nil && readSigs.last?.resolvedSigner(sender: "0xS") == "0xS")
check("an empty msg signs the transaction and a digest does not",
      readSigs.first?.signsTransaction == true && readSigs.last?.signsTransaction == false)
check("an arbitrary entry speaks for no address",
      FramesRead.Signature(scheme: 0, signer: nil, signsTransaction: true).resolvedSigner(sender: "0xS") == nil)
check("no signatures field reads none", FramesRead.signatures(inTransaction: [:]).isEmpty)

// --- THE DEADLINE, AND A TOKEN PAYMENT (prd §728) -----------------------------
let expiryAddress = "0x0000000000000000000000000000000000008141"
func verifyFrame(_ to: String, data: String) -> FramesRead.Frame {
    .init(mode: 1, flags: 0, target: to, executionGas: 20_000, stateGas: 0, value: "0x0", data: data)
}
check("an expiry frame's 8 bytes are its deadline",
      verifyFrame(expiryAddress, data: "0x000000006aa5f05c").deadline == Date(timeIntervalSince1970: 0x6aa5f05c))
check("nine bytes is no deadline — the node refuses that frame, so it never ran",
      verifyFrame(expiryAddress, data: "0x00000000006aa5f05c").deadline == nil)
check("a sender frame to that address is not a deadline",
      payFrame(expiryAddress, value: "0x0", data: "0x000000006aa5f05c").deadline == nil)
let bob = "61c93cfd66431c2d6f5e29d224fd29afd4550f2e"
let dai = "0x7d6fa7c366f36046656b019dc9a27f171628cf3f"
let fiveDAI = String(repeating: "0", count: 48) + "4563918244f40000"
let transferData = "0xa9059cbb" + String(repeating: "0", count: 24) + bob + fiveDAI
let transfer = payFrame(dai, value: "0x0", data: transferData).tokenTransfer
check("a transfer's recipient is its ARGUMENT, not the contract", transfer?.recipient == "0x" + bob)
check("and its amount is exact", transfer?.raw == Decimal(string: "5000000000000000000"))
check("a verify frame never carries a payment",
      verifyFrame(dai, data: transferData).tokenTransfer == nil)
check("an address word with its high bytes set is not an address",
      payFrame(dai, value: "0x0", data: "0xa9059cbb" + "01" + String(repeating: "0", count: 22) + bob + fiveDAI).tokenTransfer == nil)
check("a truncated call is not a transfer",
      payFrame(dai, value: "0x0", data: String(transferData.dropLast(2))).tokenTransfer == nil)
let daiOut = FramesTokenMove(contract: dai, raw: -Decimal(string: "5000000000000000000")!, symbol: "DAI", decimals: 18)
let tokenSend = FramesMove(hash: "0xt", blockNumber: 1, sender: "0xa", payer: "0xa", succeeded: true,
                           rows: [FramesFrameRow(frame: payFrame(dai, value: "0x0", data: transferData), outcome: nil)],
                           deltaWei: -210_790, tokenMoves: [daiOut])
check("a token send's recipient is the person paid", tokenSend.recipients == ["0x" + bob])
check("a token payment leads with the token", tokenSend.leadToken?.symbol == "DAI")
check("in the token's own unit, with a true minus", tokenSend.leadToken?.signedLine == "\u{2212}5 DAI")
let coinAndToken = FramesMove(hash: "0xu", blockNumber: 1, sender: "0xa", payer: "0xa", succeeded: true,
                              rows: [FramesFrameRow(frame: payFrame("0xb", value: "0x1"),
                                                    outcome: .init(succeeded: true, gasUsed: 1, stateGasUsed: nil, logCount: 1))],
                              deltaWei: -1, tokenMoves: [daiOut])
check("a coin payment that also touched a token leads with the coin", coinAndToken.leadToken == nil)
let daiIn = FramesMove(hash: "0xv", blockNumber: 1, sender: "0xz", payer: "0xz", succeeded: true,
                       rows: [], deltaWei: 0,
                       tokenMoves: [FramesTokenMove(contract: dai, raw: Decimal(string: "5000000000000000000")!, symbol: "DAI", decimals: 18)])
check("tokens received lead with the token", daiIn.leadToken?.signedLine == "+5 DAI")
check("a token that never said its decimals is not scaled by a guess",
      FramesTokenMove(contract: dai, raw: 42, symbol: nil, decimals: nil).signedLine == "+42 0x7d6f…cf3f")
check("a move's deadline is its expiry frame's",
      FramesMove(hash: "0xw", blockNumber: 1, sender: "0xa", payer: "0xa", succeeded: true,
                 rows: [FramesFrameRow(frame: verifyFrame(expiryAddress, data: "0x000000006aa5f05c"), outcome: nil)],
                 deltaWei: 0).deadline == Date(timeIntervalSince1970: 0x6aa5f05c))

// --- EVERY SEND CARRIES A DEADLINE, AND A TOKEN IS A CALL (prd §728b) ---------
// **THREE PREIMAGES A NODE VERIFIED A SIGNATURE OVER.** Computed by an
// independent encoder and broadcast on 2026-09-13 from an unfunded key: the
// node refused all three with "Nonce mismatch: expected 0, got N", a check it
// makes only AFTER every signature validates. So each preimage below is one
// the node agrees with, and these builders must reproduce it byte for byte.
let senderA = hx("0x285dc41e452865032197bd1d44e4a9e1179c994c")
let bobAddr = hx("0x61c93cfd66431c2d6f5e29d224fd29afd4550f2e")
let deadAddr = hx("0x000000000000000000000000000000000000dead")
let daiAddr = hx("0x7d6fa7c366f36046656b019dc9a27f171628cf3f")
let oneGwei = hx("0x3b9aca00")
let fixedDeadline: UInt64 = 0x6aa5f05c
func signedBy(_ fields: FramesTransaction.Fields, _ who: Data) -> FramesTransaction.Fields {
    var out = fields
    out.signatures = [.init(scheme: 1, signer: who, msg: Data(), signature: Data())]
    return out
}
let vDeadline = signedBy(FramesTransaction.transfer(
    sender: senderA, to: deadAddr, value: oneGwei, nonce: 3,
    maxPriorityFeePerGas: 1_000_000_000, maxFeePerGas: 10_000_000_000,
    deadline: fixedDeadline), senderA)
check("V-DEADLINE: a transfer under a deadline is the preimage the node verified",
      keccakHex(FramesTransaction.signingPreimage(vDeadline))
        == "0x730c502c1d349fc3ce6c7ac582f5164fbff3f995dfe9cf08f0ad6c79bfb4f573")
let expiryFrameBuilt = vDeadline.frames[0]
check("the deadline frame leads: VERIFY, flags 0, no value, no state budget, 8 big-endian bytes, at 0x8141",
      expiryFrameBuilt.mode == 1 && expiryFrameBuilt.flags == 0 && expiryFrameBuilt.value.isEmpty
        && expiryFrameBuilt.stateGas == 0 && expiryFrameBuilt.data == hx("0x000000006aa5f05c")
        && expiryFrameBuilt.target == hx("0x0000000000000000000000000000000000008141"))
check("no deadline is still the pinned two-frame transfer",
      FramesTransaction.transfer(sender: senderA, to: deadAddr, value: oneGwei, nonce: 3,
                                 maxPriorityFeePerGas: 1, maxFeePerGas: 1).frames.count == 2)
let daiLeg = FramesTransaction.tokenLeg(contract: daiAddr, to: bobAddr, amount: hx("0x4563918244f40000"))!
let vToken = signedBy(FramesTransaction.stitched(
    sender: senderA, legs: [daiLeg], atomic: false, nonce: 4,
    maxPriorityFeePerGas: 1_000_000_000, maxFeePerGas: 10_000_000_000,
    deadline: fixedDeadline), senderA)
check("V-TOKEN: five DAI to Bob under a deadline is the preimage the node verified",
      keccakHex(FramesTransaction.signingPreimage(vToken))
        == "0xebba1b3911663f9e6eacd3bdfe0b67e0ac522352f8d1c78c3b2a79507d1fa128")
check("a token leg targets the CONTRACT and moves no coin",
      daiLeg.recipient == daiAddr && daiLeg.value.isEmpty && daiLeg.data.count == 68)
check("and reads back as a payment to the person",
      FramesRead.Frame(mode: 2, flags: 0, target: "0x7d6fa7c366f36046656b019dc9a27f171628cf3f",
                       executionGas: 1, stateGas: 1, value: "0x0",
                       data: "0x" + RLP.hex(daiLeg.data)).tokenTransfer?.recipient
        == "0x61c93cfd66431c2d6f5e29d224fd29afd4550f2e")
let vMixed = signedBy(FramesTransaction.stitched(
    sender: senderA, legs: [.init(recipient: deadAddr, value: oneGwei), daiLeg], atomic: true, nonce: 5,
    maxPriorityFeePerGas: 1_000_000_000, maxFeePerGas: 10_000_000_000,
    deadline: fixedDeadline), senderA)
check("V-STITCH: a coin leg joined to a token leg, under a deadline, is the preimage the node verified",
      keccakHex(FramesTransaction.signingPreimage(vMixed))
        == "0xf534109cf8b23f70624cb33a864e3c310db7db8f2b8f74147d3fcbc2c68d138b")
check("the join still skips the last payload frame, and the deadline frame is never joined",
      vMixed.frames.map(\.flags) == [0, 3, 4, 0])
check("a token leg refuses an amount wider than a word",
      FramesTransaction.tokenLeg(contract: daiAddr, to: bobAddr, amount: Data(repeating: 1, count: 33)) == nil)
check("and an empty amount",
      FramesTransaction.tokenLeg(contract: daiAddr, to: bobAddr, amount: Data()) == nil)
check("the verify budget still fits with the deadline frame in the prefix",
      FramesTransaction.prefixWithinBudget(vMixed))

// --- ASKING SOMEBODY ELSE TO PAY (prd §728c) ----------------------------------
// **THE PREIMAGE BOTH SIGNATURES WERE VERIFIED OVER.** An independent encoder
// built a sponsored transfer under a deadline, both keys signed it, and the
// node refused it with "Nonce mismatch" — which it checks only after both
// signatures validate at their fixed indices.
let sponsoredLeg = FramesTransaction.Leg(recipient: deadAddr, value: oneGwei)
let vSponsored = FramesTransaction.sponsored(
    sender: senderA, sponsor: bobAddr, legs: [sponsoredLeg], atomic: false, nonce: 7,
    maxPriorityFeePerGas: 1_000_000_000, maxFeePerGas: 10_000_000_000, deadline: fixedDeadline)
let sponsoredHash = "0xa898994ad6d82bd1d5eb9fc5e2d3b54a9a0ec3f92d9653a91af64434de0e9e3a"
check("V-SPONSORED: somebody else paying is the preimage the node verified both signatures over",
      keccakHex(FramesTransaction.signingPreimage(vSponsored)) == sponsoredHash)
check("the sender approves running only, the sponsor paying only",
      vSponsored.frames.map(\.flags) == [0, 2, 1, 0])
check("signatures are sender then sponsor — the default code reads 0 to run and 1 to pay",
      vSponsored.signatures.map(\.signer) == [senderA, bobAddr])
check("the paying frame carries the state budget, for a sender that does not exist yet",
      vSponsored.frames[2].stateGas == 250_000 && vSponsored.frames[1].stateGas == 0)
let aliceSig = hx("0x010afe41ede03a018aa0646893a82f638bc9e6548b0cfa26b14adf4d4529312d6830469b9383fca8430da0a0fae4edfb3c0268d3a907950baedfabacd2f9fb2f31")
let ask = FramesSponsor.request(for: vSponsored, sponsor: bobAddr, legs: [sponsoredLeg], atomic: false,
                                deadline: fixedDeadline, senderSignature: aliceSig)
let askLink = FramesSponsor.link(ask)
check("a request travels as a casberi link",
      askLink?.absoluteString.hasPrefix("casberi://frames/sponsor?r=") == true)
let askBack = askLink.flatMap(FramesSponsor.request(from:))
check("and arrives identical", askBack == ask)
check("and rebuilds the exact transaction the sender signed",
      askBack.flatMap(FramesSponsor.fields).map { keccakHex(FramesTransaction.signingPreimage($0)) } == sponsoredHash)
check("with the sender's signature in place and the sponsor's empty",
      askBack.flatMap(FramesSponsor.fields)?.signatures.map(\.signature) == [aliceSig, Data()])
let bobHex = "0x61c93cfd66431c2d6f5e29d224fd29afd4550f2e"
let inTime = Date(timeIntervalSince1970: TimeInterval(fixedDeadline) - 60)
check("a readable request for this phone, in time, at the sender's nonce, is payable",
      FramesSponsor.refusal(ask, mine: bobHex, now: inTime, senderNonce: 7) == nil)
check("an unread nonce refuses nothing yet",
      FramesSponsor.refusal(ask, mine: bobHex, now: inTime, senderNonce: nil) == nil)
check("a request for another account is refused",
      FramesSponsor.refusal(ask, mine: "0x285dc41e452865032197bd1d44e4a9e1179c994c", now: inTime, senderNonce: 7)
        == .notForThisPhone)
check("past its deadline it is refused",
      FramesSponsor.refusal(ask, mine: bobHex, now: inTime.addingTimeInterval(120), senderNonce: 7) == .expired)
check("a sender who has sent something since makes it stale",
      FramesSponsor.refusal(ask, mine: bobHex, now: inTime, senderNonce: 8) == .stale)
var futureFormat = ask; futureFormat.format = 2
check("malformed outranks everything else",
      FramesSponsor.refusal(futureFormat, mine: nil, now: inTime.addingTimeInterval(9_999), senderNonce: 0) == .malformed)
let daiHex = "0x7d6fa7c366f36046656b019dc9a27f171628cf3f"
var approveCall = ask
approveCall.legs = [.init(target: daiHex, value: "0x",
                          data: "0x095ea7b3" + String(repeating: "0", count: 24) + "61c93cfd66431c2d6f5e29d224fd29afd4550f2e" + String(repeating: "f", count: 64))]
check("a call a sponsor cannot read is malformed — approve(), not transfer()",
      FramesSponsor.fields(approveCall) == nil)
var tokenAsk = ask
tokenAsk.legs = [.init(target: daiHex, value: "0x", data: "0x" + RLP.hex(daiLeg.data))]
check("a plain token transfer is payable", FramesSponsor.fields(tokenAsk) != nil)
var tokenAndCoin = tokenAsk
tokenAndCoin.legs[0].value = "0x3b9aca00"
check("a token transfer that also sends coin is malformed", FramesSponsor.fields(tokenAndCoin) == nil)
var selfSponsor = ask; selfSponsor.sponsor = ask.sender
check("asking yourself to pay is malformed", FramesSponsor.fields(selfSponsor) == nil)
var tooManyLegs = ask; tooManyLegs.legs = Array(repeating: ask.legs[0], count: 9)
check("nine legs is past what a sponsor is asked to read", FramesSponsor.fields(tooManyLegs) == nil)
check("a link whose request is not JSON is no request",
      FramesSponsor.request(from: URL(string: "casberi://frames/sponsor?r=bm90IGpzb24")!) == nil)
check("the fee ceiling covers every budget the frames were given",
      FramesTransaction.maxGas(vSponsored)
        >= vSponsored.frames.reduce(UInt64(0)) { $0 + $1.executionGas + $1.stateGas })

// --- THE PASSKEY ACCOUNT (prd §728d) -----------------------------------------
// The key's public half and every expected byte below were produced by an
// independent implementation. A valid P-256 signature over V-PASSKEY passed
// the node's signature check and a corrupted one was refused as "Invalid frame
// transaction signature" (2026-09-13).
let pkX = "c2de27efb59662488b4b6d6ff699c2dccd148510c6eda3f9c99eb8e17c464adb"
let pkY = "49c9e8b7f98a71150bf175a22c49278c0a8dde08496efcdb321496e340df34cc"
let passkeyOwner = FramesPasskeyAccount.owner(publicKey: hx("0x" + pkX + pkY))
check("a P-256 signer is keccak(qx ‖ qy)[12:]",
      passkeyOwner == hx("0x33d79af4cbc639f33ba44457f4fedd1d9268c468"))
let ownerBytes = passkeyOwner ?? Data()
check("the account's code is the 64 bytes that were measured",
      "0x" + RLP.hex(FramesPasskeyAccount.runtime(owner: ownerBytes))
        == "0x3360aa14600857005b60015fb460021460025fb415165f5fb47333d79af4cbc639f33ba44457f4fedd1d9268c46814166036575f5ffd5b6006600ab0b35f5faa")
check("its constructor copies and returns exactly that code",
      "0x" + RLP.hex(FramesPasskeyAccount.initcode(owner: ownerBytes).prefix(10)) == "0x6040600a5f3960405ff3")
check("its address is fixed by CREATE2 before it exists",
      FramesPasskeyAccount.address(owner: ownerBytes) == hx("0x9c2e4702d6209ab2ce4f1aa2c9bb08a62133195d"))
let deployF = FramesPasskeyAccount.deployFrame(owner: ownerBytes)
check("the deploy frame is DEFAULT, to the proxy, salt then initcode, with the state budget",
      deployF.mode == 0 && deployF.flags == 0 && deployF.target == FramesPasskeyAccount.deployer
        && deployF.data.count == 32 + 74 && deployF.stateGas == 450_000)
let vPasskey = FramesPasskeyAccount.transaction(
    owner: ownerBytes, deploy: true, legs: [.init(recipient: deadAddr, value: oneGwei)], atomic: false,
    nonce: 0, maxPriorityFeePerGas: 1_000_000_000, maxFeePerGas: 10_000_000_000, deadline: fixedDeadline)
check("V-PASSKEY: the first send — deadline, deploy, verify, send — is the preimage the node checked a P-256 signature over",
      keccakHex(FramesTransaction.signingPreimage(vPasskey))
        == "0xf2e4e15d557ff4ae2759bd6b84dae2bc5139740a0e8469eb1015692ac4424cdb")
check("its one signature entry is P-256, naming the owner",
      vPasskey.signatures.count == 1 && vPasskey.signatures[0].scheme == 2
        && vPasskey.signatures[0].signer == ownerBytes)
let vPasskeyNext = FramesPasskeyAccount.transaction(
    owner: ownerBytes, deploy: false, legs: [.init(recipient: deadAddr, value: oneGwei)], atomic: false,
    nonce: 2, maxPriorityFeePerGas: 1_000_000_000, maxFeePerGas: 10_000_000_000, deadline: fixedDeadline)
check("V-PASSKEY-NEXT: once the code exists, no deploy frame",
      keccakHex(FramesTransaction.signingPreimage(vPasskeyNext))
        == "0x804194e5fc2152a02ee4e68707d0e94889766e5140164d84c401e76758fdc8ac")
check("the deploy frame is inside the verify budget", FramesTransaction.prefixWithinBudget(vPasskey))
// Low-s: EIP-8141 refuses a high-s P-256 signature, and the Enclave signs either half.
let halfN = FramesPasskeyAccount.curveHalfOrder
let r32 = Data(repeating: 0x11, count: 32)
var highS = halfN; highS[31] = highS[31] &+ 1
let folded = FramesPasskeyAccount.lowS(r32 + Data(highS))
check("s just above n/2 is folded to n - s", Data(folded.suffix(32)) != Data(highS) && folded.prefix(32) == r32)
func add256(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: 32); var carry = 0
    for i in stride(from: 31, through: 0, by: -1) { let v = Int(a[i]) + Int(b[i]) + carry; out[i] = UInt8(v & 0xff); carry = v >> 8 }
    return out
}
check("and the folded s plus the original is exactly n",
      add256([UInt8](folded.suffix(32)), highS) == FramesPasskeyAccount.curveOrder)
check("s at exactly n/2 is already low", FramesPasskeyAccount.lowS(r32 + Data(halfN)) == r32 + Data(halfN))
check("a signature entry is r ‖ s ‖ qx ‖ qy",
      FramesPasskeyAccount.signatureBytes(rs: r32 + Data(halfN), publicKey: hx("0x" + pkX + pkY))?.count == 128)

// **THE CODE, RUN.** A small interpreter for exactly the opcodes those 64
// bytes use, reading EIP-8141's stack orders as the pinned text states them
// (SIGPARAM and FRAMEPARAM: index on top, param beneath; APPROVE: offset, then
// length, then scope). It proves the jumps land and the checks gate what they
// should under that reading — the chain is what proves the reading.
enum Halt: Equatable { case stop, revert, approve(UInt64), invalid }
struct VerifyContext {
    var caller: UInt64 = 0xaa
    var scheme: UInt64 = 2
    var msgEmpty = true
    var signer: Data
    var allowedScope: UInt64 = 3
}
func word(_ v: UInt64) -> [UInt8] { var w = [UInt8](repeating: 0, count: 32); var x = v; for i in stride(from: 31, through: 24, by: -1) { w[i] = UInt8(x & 0xff); x >>= 8 }; return w }
func wordData(_ d: Data) -> [UInt8] { [UInt8](repeating: 0, count: 32 - d.count) + [UInt8](d) }
func small(_ w: [UInt8]) -> UInt64? { guard w.prefix(24).allSatisfy({ $0 == 0 }) else { return nil }; return w.suffix(8).reduce(0) { $0 << 8 | UInt64($1) } }
func runVerify(_ code: [UInt8], _ c: VerifyContext) -> Halt {
    var pc = 0; var st: [[UInt8]] = []; var steps = 0
    func pop() -> [UInt8]? { st.popLast() }
    while pc < code.count, steps < 200 {
        steps += 1
        let op = code[pc]
        switch op {
        case 0x00: return .stop
        case 0x33: st.append(word(c.caller)); pc += 1
        case 0x5f: st.append(word(0)); pc += 1
        case 0x60: guard pc + 1 < code.count else { return .invalid }; st.append(word(UInt64(code[pc + 1]))); pc += 2
        case 0x73: guard pc + 20 < code.count else { return .invalid }; st.append(wordData(Data(code[(pc + 1)...(pc + 20)]))); pc += 21
        case 0x14: guard let a = pop(), let b = pop() else { return .invalid }; st.append(word(a == b ? 1 : 0)); pc += 1
        case 0x15: guard let a = pop() else { return .invalid }; st.append(word(a.allSatisfy { $0 == 0 } ? 1 : 0)); pc += 1
        case 0x16: guard let a = pop(), let b = pop() else { return .invalid }; st.append(zip(a, b).map { $0 & $1 }); pc += 1
        case 0x57:
            guard let dest = pop().flatMap(small), let cond = pop() else { return .invalid }
            if cond.contains(where: { $0 != 0 }) {
                guard Int(dest) < code.count, code[Int(dest)] == 0x5b else { return .invalid }
                pc = Int(dest)
            } else { pc += 1 }
        case 0x5b: pc += 1
        case 0xfd: _ = pop(); _ = pop(); return .revert
        case 0xb4: // SIGPARAM: signatureIndex on top, param beneath
            guard let index = pop().flatMap(small), let param = pop().flatMap(small), index == 0 else { return .invalid }
            switch param {
            case 0: st.append(wordData(c.signer))
            case 1: st.append(word(c.scheme))
            case 2: st.append(word(c.msgEmpty ? 0 : 0xabcdef))
            default: return .invalid
            }
            pc += 1
        case 0xb0: // TXPARAM: one param
            guard let param = pop().flatMap(small), param == 0x0a else { return .invalid }
            st.append(word(1)); pc += 1
        case 0xb3: // FRAMEPARAM: frameIndex on top, param beneath
            guard let index = pop().flatMap(small), let param = pop().flatMap(small),
                  index == 1, param == 0x06 else { return .invalid }
            st.append(word(c.allowedScope)); pc += 1
        case 0xaa: // APPROVE: offset on top, then length, then scope
            guard pop() != nil, pop() != nil, let scope = pop().flatMap(small) else { return .invalid }
            return .approve(scope)
        default: return .invalid
        }
    }
    return .invalid
}
let accountCode = [UInt8](FramesPasskeyAccount.runtime(owner: ownerBytes))
check("the entry point with this owner's P-256 signature over the transaction approves the frame's scope",
      runVerify(accountCode, VerifyContext(signer: ownerBytes)) == .approve(3))
check("a sponsored frame that allows running only approves running only",
      runVerify(accountCode, VerifyContext(signer: ownerBytes, allowedScope: 2)) == .approve(2))
check("another key's P-256 signature reverts",
      runVerify(accountCode, VerifyContext(signer: hx("0x285dc41e452865032197bd1d44e4a9e1179c994c"))) == .revert)
check("a secp256k1 signature naming the owner reverts",
      runVerify(accountCode, VerifyContext(scheme: 1, signer: ownerBytes)) == .revert)
check("a P-256 signature over some other digest reverts",
      runVerify(accountCode, VerifyContext(msgEmpty: false, signer: ownerBytes)) == .revert)
check("anybody but the entry point is an ordinary receive",
      runVerify(accountCode, VerifyContext(caller: 0x1234, signer: ownerBytes)) == .stop)

// --- EXECUTED ON CHAIN (prd §728d) --------------------------------------------
// **FOUR TRANSACTIONS THAT RAN**, sent from scratch keys on 2026-09-13 after the
// chain resumed, each returning the hash it was predicted to have. Every field
// below is read back off the node, signature bytes included, and the builders
// this app ships must reproduce the node's own hash byte for byte.
let executedSponsorSigA = hx("0x010671a039dec54217e54ff6a0aa52be7cc9907d7bdf2533d044234486fca678df111e3d1f7de32464f857cf48571a12610f5de019c52c24be06a42029f2c4402c")
let executedSponsorSigB = hx("0x01a4498bd019ce4e55df468e894554099cd418f0679fec6da4d0fc4a0a4ff475dc68fb4acd08d4fd2c252915ca32f8bef57bb5563b2de7401bf8aafd5cd6097c73")
var executedPasskey = FramesPasskeyAccount.transaction(
    owner: ownerBytes, deploy: true, legs: [.init(recipient: deadAddr, value: oneGwei)], atomic: false,
    nonce: 0, maxPriorityFeePerGas: 1_000_000_000, maxFeePerGas: 10_000_000_000, deadline: 0x6aa8326c)
executedPasskey.signatures[0].signature = hx("0x9bb0f1baad24b97bcc41e9412a4363924bbf4d12fe1e682ce4c42c466ffe05ba4f0a111085ac106fd5f9adb3bb6c1ab0b221becf6c05be0c3e9e7090ee11baedc2de27efb59662488b4b6d6ff699c2dccd148510c6eda3f9c99eb8e17c464adb49c9e8b7f98a71150bf175a22c49278c0a8dde08496efcdb321496e340df34cc")
check("EXECUTED: the passkey account's first transaction — deploy, P-256 verify, send — is the one that ran (block 75,719)",
      keccakHex(FramesTransaction.encoded(executedPasskey))
        == "0x176065d6cd418811c1349e9259d18b49b546a510f3413a243dd89a229bf2dcb3")
var executedSponsored = FramesTransaction.sponsored(
    sender: senderA, sponsor: bobAddr, legs: [.init(recipient: deadAddr, value: oneGwei)], atomic: false,
    nonce: 1, maxPriorityFeePerGas: 1_000_000_000, maxFeePerGas: 10_000_000_000, deadline: 0x6aa83316)
executedSponsored.signatures[0].signature = executedSponsorSigA
executedSponsored.signatures[1].signature = executedSponsorSigB
check("EXECUTED: a transfer somebody else paid for is the one that ran, payer the sponsor (block 75,720)",
      keccakHex(FramesTransaction.encoded(executedSponsored))
        == "0xaeef4a327474272a42689a1e1ff4acafbfad7b7fac086021cf1f00bba0f17a4e")
var executedToken = FramesTransaction.stitched(
    sender: senderA,
    legs: [.init(recipient: daiAddr, value: Data(),
                 data: FramesTransaction.erc20TransferSelector + Data(repeating: 0, count: 12) + bobAddr + Data(repeating: 0, count: 32))],
    atomic: false, nonce: 2, maxPriorityFeePerGas: 1_000_000_000, maxFeePerGas: 10_000_000_000, deadline: 0x6aa83318)
executedToken.signatures = [.init(scheme: 1, signer: senderA, msg: Data(),
    signature: hx("0x01e418028ed673b4dd4df5f2406000d5f4e4c3b0e536db49c6955b5f508518ad8d5794705a74455625a3f119f4f7402fcf940f5a840f45fdc405004252fd121cf7"))]
check("EXECUTED: a frame CARRYING CALLDATA reproduces the chain's own hash — §654a's open question, closed for this encoder (block 75,722)",
      keccakHex(FramesTransaction.encoded(executedToken))
        == "0xbfa7da5cd4385a591875ffe8f50b7b7c6c9c505d6f834b5cf0732736dd0172cd")
var executedSkip = FramesTransaction.stitched(
    sender: senderA,
    legs: [.init(recipient: bobAddr, value: hx("0x01")),
           .init(recipient: bobAddr, value: hx("0x0c9f2c9cd04674edea40000000")),
           .init(recipient: bobAddr, value: hx("0x01"))],
    atomic: true, nonce: 3, maxPriorityFeePerGas: 1_000_000_000, maxFeePerGas: 10_000_000_000, deadline: 0x6aa8331f)
executedSkip.signatures = [.init(scheme: 1, signer: senderA, msg: Data(),
    signature: hx("0x003f61939dcc7a95b7d5d0e0beb37c37e29b32da01267db47bcac9a99332d6b2794953434922a89dcf74c5eb3faef2ed53cbc75149b5a85106c1833536b24ded43"))]
check("EXECUTED: an atomic batch whose middle leg could not pay is the one that ran (block 75,724)",
      keccakHex(FramesTransaction.encoded(executedSkip))
        == "0x55625eafb20f47a9f36c109bc4bf5237b7ba525dcffcbb7c3ad1e0a756f6b883")
// Its receipt, as the node reported it: deadline, verify, then the three legs —
// the first ran and was undone (no log), the second failed, the third never ran.
let executedSkipOut = FramesRead.outcomes(inReceipt: ["frameReceipts": [
    ["status": "0x1", "gasUsed": "0xbeb", "stateGasUsed": "0x0", "logs": [[String: Any]]()],
    ["status": "0x1", "gasUsed": "0x64", "stateGasUsed": "0x0", "logs": [[String: Any]]()],
    ["status": "0x1", "gasUsed": "0xbb8", "stateGasUsed": "0x0", "logs": [[String: Any]]()],
    ["status": "0x0", "gasUsed": "0x64", "stateGasUsed": "0x0", "logs": [[String: Any]]()],
    ["status": "0x2", "gasUsed": "0x0", "stateGasUsed": "0x0", "logs": [[String: Any]]()],
]])
check("the chain's own 0x2 reads as skipped, and only on the leg that never ran",
      executedSkipOut.map(\.skipped) == [false, false, false, false, true])

// --- A SPONSOR'S OWN SIDE (prd §728c, code review 2026-09-14) ----------------
let paidForBob = FramesMove(hash: "0xpf", blockNumber: 1, sender: "0xaaaa", payer: "0xBBBB", succeeded: true,
                            rows: [], deltaWei: -210_790, reader: "0xbbbb")
check("a fee this account paid for somebody else is not 'somebody else paid'", !paidForBob.sponsored)
check("…it is paying for somebody else", paidForBob.paidForSomeoneElse)
check("so the sponsor never appears in its own list of sponsors", FramesPayers.roster([paidForBob]).isEmpty)
let paidForMe = FramesMove(hash: "0xpm", blockNumber: 1, sender: "0xaaaa", payer: "0xbbbb", succeeded: true,
                           rows: [], deltaWei: 0, reader: "0xAAAA")
check("read by the sender, the same transaction IS sponsored", paidForMe.sponsored && !paidForMe.paidForSomeoneElse)

// --- THE SPEC'S OWN STEP NAMES (prd §728e) -----------------------------------
let namedExpiry = verifyFrame(expiryAddress, data: "0x000000006aa5f05c")
let namedDeploy = FramesRead.Frame(mode: 0, flags: 0, target: "0x4E59b44847b379578588920ca78fbf26c0b4956c",
                                   executionGas: 150_000, stateGas: 450_000, value: "0x0", data: "0x00")
check("an expiry verifier frame is named Expiry, not Verify", namedExpiry.stepName == "Expiry")
check("a DEFAULT frame to the deployment proxy is named Deploy, not Call", namedDeploy.stepName == "Deploy")
check("a DEFAULT frame to any other contract is not a deploy — this app cannot know it installs anything",
      FramesRead.Frame(mode: 0, flags: 0, target: "0x7d6fa7c366f36046656b019dc9a27f171628cf3f",
                       executionGas: 1, stateGas: 1, value: "0x0", data: "0x00").stepName == "Default")
check("an ordinary verify frame keeps its mode's name",
      verifyFrame("0x285dc41e452865032197bd1d44e4a9e1179c994c", data: "0x").stepName == "Verify")
let namedRuns = FramesFrames.runs([FramesMove(
    hash: "0xn", blockNumber: 1, sender: "0xa", payer: "0xa", succeeded: true,
    rows: [FramesFrameRow(frame: namedExpiry, outcome: nil),
           FramesFrameRow(frame: namedDeploy, outcome: nil),
           FramesFrameRow(frame: verifyFrame("0x9c2e4702d6209ab2ce4f1aa2c9bb08a62133195d", data: "0x"), outcome: nil),
           FramesFrameRow(frame: payFrame("0xb"), outcome: nil)],
    deltaWei: 0)])
check("the census counts a send's expiry check and its deploy apart from verification",
      namedRuns.first?.steps.map(\.modeName) == ["Expiry", "Deploy", "Verify", "Send"])

if fails > 0 { print("  \(fails) assertion(s) failed"); exit(1) }
print("  ok   encoder: 3 real vectors byte-exact, keccak == the chain's own hash (1 on the post-restart chain)")
SWIFT

build_run() {
  ( cd "$WORK" && swiftc -Onone -o m/run FramesTransaction.swift RLP.swift Keccak256.swift FramesMoney.swift FramesSection.swift DevnetTokens.swift RoomFrames.swift FramesReading.swift FramesChainWatch.swift FramesSponsor.swift FramesPasskeyAccount.swift m/main.swift 2>&1 )
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
# **PINNED TO THE BALANCE'S OWN ROUNDING, not the first `.down` in the file
# (prd §688).** `FramesMoney` grew `hex(wei:)` above this one, which also
# rounds down — and a bare `.down)` mutation then rewrote THAT, left the
# balance untouched, and reported SURVIVED against code it never changed. The
# "dead mutation prints a passing line" class, caught by its own harness.
mutate "the balance rounded to nearest" $F2 \
  'NSDecimalRound(&rounded, &quotient, places, .down)' \
  'NSDecimalRound(&rounded, &quotient, places, .plain)'
mutate "the wei-per-ETH divisor losing a zero" $F2 \
  '"1000000000000000000"' '"100000000000000000"'
mutate "a conditional scope ahead of an unconditional one" $F3 \
  '[.home, .activity, .holdings, .accounts, .frames, .permissions]' '[.home, .holdings, .activity, .accounts, .frames, .permissions]'
mutate "the remembered scope falling back to the first present one" $F3 \
  'guard let wanted, present.contains(wanted) else { return .home }' \
  'guard let wanted, present.contains(wanted) else { return present.first ?? .home }'
mutate "a strip drawn over a single chip" $F3 'present.count > 1' 'present.count > 0'
mutate "every scope gated again, so two chips vanish on the address that most needs them" $F3 \
  'static func present() -> [FramesSection] { order }' \
  'static func present() -> [FramesSection] { order.filter { !$0.isConditional } }'
mutate "an empty scope left with nothing to say — the dead control this ruling depends on avoiding" $F3 \
  'A framed transaction runs its work in numbered steps, each with a budget of its own. Nothing here has run any — a plain transfer runs none.' ' '
mutate "frames marked unconditional" $F3 \
  'case .holdings, .accounts, .frames, .permissions: return true' 'case .holdings, .accounts, .frames, .permissions: return false'
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
  'frames: expiryPrefix(deadline) + [Frame(mode: 1, flags: 0x03, target: sender,
                                     executionGas: executionGas, stateGas: stateGas,
                                     value: Data(), data: Data())]
                          + legs.enumerated().map { index, leg in' \
  'frames: expiryPrefix(deadline) + legs.enumerated().map { index, leg in'
mutate "the VERIFY frame no longer approving payment" $F \
  'frames: expiryPrefix(deadline) + [Frame(mode: 1, flags: 0x03, target: sender,
                                     executionGas: executionGas, stateGas: stateGas,
                                     value: Data(), data: Data())]' \
  'frames: expiryPrefix(deadline) + [Frame(mode: 1, flags: 0x01, target: sender,
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

mutate "the deadline written little-endian" FramesTransaction.swift \
  'var bigEndian = deadline.bigEndian' 'var bigEndian = deadline.littleEndian'
mutate "the deadline frame given a state budget (the node refuses it)" FramesTransaction.swift \
  'executionGas: expiryExecutionGas, stateGas: 0,' 'executionGas: expiryExecutionGas, stateGas: 250_000,'
mutate "the deadline silently dropped from every send" FramesTransaction.swift \
  'deadline.map { [expiryFrame(deadline: $0)] } ?? []' '[]'
mutate "a token leg calling transferFrom" FramesTransaction.swift \
  'Data([0xa9, 0x05, 0x9c, 0xbb])' 'Data([0x23, 0xb8, 0x72, 0xdd])'
mutate "a token amount sent as coin value too" FramesTransaction.swift \
  'return Leg(recipient: contract, value: Data(), data: data)' 'return Leg(recipient: contract, value: amount, data: data)'
mutate "a stitched leg losing its calldata" FramesTransaction.swift \
  'value: leg.value, data: leg.data)' 'value: leg.value, data: Data())'
F7=FramesSponsor.swift
mutate "the sender approving payment as well as running" $F7 \
  'Frame(mode: 1, flags: 0x02, target: sender,' 'Frame(mode: 1, flags: 0x03, target: sender,'
mutate "the sponsor's signature placed first" $F7 \
  'signatures: [Signature(scheme: 1, signer: sender, msg: Data(), signature: Data()),
                         Signature(scheme: 1, signer: sponsor, msg: Data(), signature: Data())],' \
  'signatures: [Signature(scheme: 1, signer: sponsor, msg: Data(), signature: Data()),
                         Signature(scheme: 1, signer: sender, msg: Data(), signature: Data())],'
mutate "any 68-byte call payable" $F7 \
  'guard data.count == 68, data.starts(with: FramesTransaction.erc20TransferSelector),' 'guard data.count == 68,'
mutate "an expired request payable" $F7 \
  'if now.timeIntervalSince1970 > TimeInterval(request.deadline) { return .expired }' ''
mutate "a stale request payable" $F7 \
  'if let senderNonce, senderNonce != request.nonce { return .stale }' ''
mutate "another account's request payable" $F7 \
  'guard let mine, mine.caseInsensitiveCompare(request.sponsor) == .orderedSame' 'guard let mine, !mine.isEmpty'
mutate "asking yourself to pay allowed" $F7 \
  '              sender != sponsor,
' ''
mutate "the sender's signature filed as the sponsor's" $F7 \
  'fields.signatures[0].signature = signature' 'fields.signatures[1].signature = signature'
F8=FramesPasskeyAccount.swift
mutate "the approve jump landing a byte short" $F8 \
  'code += [0x60, 0x36, 0x57]' 'code += [0x60, 0x35, 0x57]'
mutate "a secp256k1 signature accepted as the owner's" $F8 \
  'code += [0x60, 0x02, 0x14]' 'code += [0x60, 0x01, 0x14]'
mutate "SIGPARAM's index and param swapped" $F8 \
  'code += [0x60, 0x01, 0x5f, 0xb4]' 'code += [0x5f, 0x60, 0x01, 0xb4]'
mutate "RETURN instead of APPROVE" $F8 \
  'code += [0x5f, 0x5f, 0xaa]' 'code += [0x5f, 0x5f, 0xf3]'
mutate "CREATE2's 0xff prefix wrong" $F8 \
  'let preimage = [UInt8]([0xff])' 'let preimage = [UInt8]([0xfe])'
mutate "a high s left high" $F8 \
  'high = s[i] > curveHalfOrder[i]' 'high = s[i] < curveHalfOrder[i]'
mutate "the passkey signature entry written as secp256k1" $F8 \
  'Signature(scheme: 2, signer: owner,' 'Signature(scheme: 1, signer: owner,'
mutate "a sponsor listed as its own sponsor" FramesReading.swift \
  'var sponsored: Bool { payer.lowercased() != sender.lowercased() && !paidForSomeoneElse }' \
  'var sponsored: Bool { payer.lowercased() != sender.lowercased() }'
mutate "an expiry check counted as Verify in the census" FramesReading.swift \
  'RoomFrames.Step(modeName: row.frame.isExpiry ? String(localized: "Expiry")' \
  'RoomFrames.Step(modeName: false ? String(localized: "Expiry")'
mutate "a deploy frame recognised by mode alone" FramesReading.swift \
  'var isDeploy: Bool { mode == 0 && target?.lowercased() == Self.deploymentProxy }' \
  'var isDeploy: Bool { mode == 0 }'
F5=FramesChainWatch.swift
mutate "an install's first genesis called a relaunch" $F5 \
  'guard let baseline, !baseline.isEmpty else { return .adopt(observed) }' \
  'guard let baseline, !baseline.isEmpty else { return .relaunched(observed) }'
mutate "every head called a stall" $F5 \
  'guard watched > stallAfter else { return nil }' 'guard watched > 0 else { return nil }'
mutate "an old timestamp alone called a stall" $F5 \
  'guard let headSince else { return nil }' 'guard let headSince = headSince ?? headAt else { return nil }'
mutate "a new head number keeping the old sighting" $F5 \
  'if observedBlock == previousBlock, let previousSince { return (observedBlock, previousSince) }' \
  'if let previousSince { return (observedBlock, previousSince) }'
mutate "a relaunch from the future said" $F5 \
  'if age >= 0, age <= sayRelaunchFor {' 'if age <= sayRelaunchFor {'
mutate "a stall outranking a relaunch" $F5 \
  '        if let seen = relaunchObservedAt {
            let age = now.timeIntervalSince(seen)
            if age >= 0, age <= sayRelaunchFor { return .relaunched(observedAt: seen) }
        }
        if let age = stallAge(headAt: headAt, headSince: headSince, now: now) { return .stalled(age: age) }' \
  '        if let age = stallAge(headAt: headAt, headSince: headSince, now: now) { return .stalled(age: age) }
        if let seen = relaunchObservedAt {
            let age = now.timeIntervalSince(seen)
            if age >= 0, age <= sayRelaunchFor { return .relaunched(observedAt: seen) }
        }'
mutate "a pooled send past its deadline called queued" $F5 \
  '        if let deadline, now.timeIntervalSince(deadline) > deadlineGrace { return .expired }
        if sightings.contains(.pooled) { return .queued }' \
  '        if sightings.contains(.pooled) { return .queued }
        if let deadline, now.timeIntervalSince(deadline) > deadlineGrace { return .expired }'
mutate "a silent host read as a host that said no" $F5 \
  'if !sightings.isEmpty, answered.count == sightings.count,' 'if !sightings.isEmpty,'
mutate "propagation read as loss" $F5 \
  'now.timeIntervalSince(sentAt) > droppedAfter {' 'now.timeIntervalSince(sentAt) >= 0 {'
mutate "a null answer read as silence" $F5 \
  'guard let transaction else { return .absent }' 'guard let transaction else { return nil }'
mutate "the finalized block itself not final" $F5 \
  'return block <= finalized' 'return block < finalized'
F6=FramesReading.swift
mutate "a reverted frame called skipped" $F6 \
  'var skipped: Bool { status == 2 }' 'var skipped: Bool { status == 0 }'
mutate "a skipped step drawn as a failure" $F6 \
  '        if landed.skipped { return .skipped }
' ''
mutate "a nine-byte expiry read as a deadline" $F6 \
  'guard body.count == 16, let seconds = UInt64(body, radix: 16) else { return nil }' \
  'guard let seconds = UInt64(body, radix: 16) else { return nil }'
mutate "a dirty address word read as an address" $F6 \
  'guard addressWord.prefix(24).allSatisfy({ $0 == "0" }),' 'guard addressWord.prefix(24).count == 24,'
mutate "a token contract listed as the person paid" $F6 \
  'guard let to = row.frame.tokenTransfer?.recipient ?? row.frame.target,' 'guard let to = row.frame.target,'
mutate "a coin payment led by a token it merely touched" $F6 \
  'return movedCoin ? nil : first' 'return first'
mutate "an empty signer kept as an address" $F6 \
  'let signer = (entry["signer"] as? String).flatMap { $0.count == 42 ? $0 : nil }' \
  'let signer = entry["signer"] as? String'
mutate "a skip counted as a failure" RoomFrames.swift \
  'case .skipped:     skipped += 1' 'case .skipped:     failed += 1'

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

# HOW MANY AT ONCE, and why it is not simply `ncpu`. This harness may be run
# TWO ways: on its own, where it should take the whole machine, and inside
# `verify.sh` / `verify-mac.sh`, which already run the harnesses themselves
# under `xargs -P ncpu`. Nested at full width that is ncpu x ncpu — 64 `swiftc`
# processes on 8 cores here — and the cost is not merely scheduling: each is
# hundreds of MB against 16 GB, so the failure mode is memory pressure and swap,
# which looks like the machine hanging rather than like a test being slow. The
# outer runners export `HARNESS_INNER_JOBS`; standalone there is no outer swarm
# and the default is the whole machine.
MUT_JOBS="${HARNESS_INNER_JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || print 4)}"

# --- run every recorded mutation, concurrently -------------------------------
# One core per mutation up to the machine's count. Output is KEPT and sorted by
# id so the report reads in declaration order regardless of which finished
# first — `xargs` interleaves, and a mutation list that reshuffles between runs
# is one nobody can diff.
: > "$WORK/mut-results"
ls "$WORK"/mut/*.label | sed 's#.*/##; s#\.label$##' \
  | xargs -P "$MUT_JOBS" -I{} zsh "$SELF" --mutate "$WORK" {} \
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
echo "✓ frames transaction self-test passed — encoder, 3 real vectors (1 post-restart), $MUTN mutations"
