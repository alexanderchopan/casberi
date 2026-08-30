#!/bin/zsh
# Casberi Bankr self-test — the SHIPPED logic behind the agent that can ACT
# (2026-08-29, prd §529):
#
#   Casberi/Casberi/Model/BankrAgent.swift
#     — canAct / forget   (the permission, and its lifetime)
#     — act               (the two refusals, and the ORDER they fire in)
#     — answerOnlyPrefix  (the rail the answer path has carried since §82)
#     — actingPrompt      (the one prompt that deliberately drops that rail)
#     — ask               (composition, so both verbs share one runner)
#
# That file is compiled WHOLE AND UNMODIFIED against inert stubs — no
# extraction, no copy — so every assertion is about the bytes the app runs.
#
# WHY A HARNESS, AND WHY THIS ONE MATTERS MORE THAN MOST. Every other keyed
# agent in this app can, at worst, give a bad answer. This one holds a
# credential that can move real money on somebody else's servers, and the
# whole safety argument is four lines of pure logic that no build, screen
# sweep or simulator run can see:
#
#   • `act` must refuse while the permission is off — and refuse in the MODEL,
#     not by a hidden button. A screen that hides a control is a screen; a
#     guard is a rule, and the rule is what survives the next refactor.
#   • The guards must fire IN ORDER — permission, then empty, then key. Get it
#     backwards and a device with no key reports "no key" for an instruction it
#     should have refused outright, which reads as a configuration problem
#     rather than as the deliberate wall it is.
#   • An EMPTY instruction must never reach the wire. A blank prompt sent to an
#     agent with a wallet is a blank cheque, and there is no good behaviour to
#     hope for on the far end.
#   • `actingPrompt` must NOT carry the answer-only prefix, and `ask` MUST.
#     That single difference is the entire feature. Add the prefix to the
#     acting path and every Do silently becomes an Ask — the app looks
#     perfect, the confirmation sheet still appears, the person taps "Send it",
#     and nothing they asked for ever happens.
#
# Each of those failures renders as a perfectly ordinary screen. That is the
# whole reason this file exists.
#
# The drift guards below cover what the compiled functions cannot prove about
# themselves: that the answer path never reaches the acting verb, that corpus
# text never rides an instruction, that the permission dies with the key, that
# the UI confirms before it acts, and that the host is disclosed.
#
# NO NETWORK. Every assertion here returns before a byte would leave — the
# stubbed vault answers nil unless a test says otherwise, and the one test
# that turns the permission on asserts `.noKey`, which is the last checkpoint
# before the request is built.
#
# Pure, local, deterministic. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

AGENT="Casberi/Casberi/Model/BankrAgent.swift"
ANSWER="Casberi/Casberi/Model/AgentAnswer.swift"
CHAT="Casberi/Casberi/Screens/BankrChatScreen.swift"
BANNER="Casberi/Casberi/Screens/BankrOfferBanner.swift"
SETUP="Casberi/Casberi/Screens/BankrSetupScreen.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
for f in "$AGENT" "$ANSWER" "$CHAT" "$BANNER" "$SETUP" "$REACH"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# A comment-stripped copy for every NEGATIVE guard. Three of these files
# DOCUMENT the rules they keep by naming the very thing they must not do
# ("Do not execute, prepare, or queue…", "corpus text never rides an acting
# instruction"), so a guard grepping raw source fires on the prose explaining
# it. Earned the hard way on `obsidian-selftest` and re-earned since.
strip_comments() { sed -E 's://.*::' "$1" | sed -E 's:/\*.*\*/::'; }
strip_comments "$ANSWER" > "$WORK/answer.nocomment"
strip_comments "$AGENT"  > "$WORK/agent.nocomment"
strip_comments "$CHAT"   > "$WORK/chat.nocomment"

# --- drift guards -----------------------------------------------------------

# 1. The answer path must never reach the acting verb. `bankrAnswer` is called
#    for every "Try with your key" on Bankr, from a composer where nobody has
#    confirmed anything — if it could call `act`, an ordinary question would
#    execute.
grep -q 'BankrAgent.act' "$WORK/answer.nocomment" \
  && { echo "✗ AgentAnswer reaches BankrAgent.act — an ASK must never be able to act"; exit 1; }

# 2. Corpus text must never ride an instruction. The answer path pastes
#    numbered candidates into its prompt; the acting path must not, because a
#    page somebody saved is text a stranger wrote, and it has no business in a
#    message to an agent that can trade.
grep -qE 'numberedCandidates|OnDeviceModel\.Candidate' "$WORK/agent.nocomment" \
  && { echo "✗ BankrAgent names corpus candidates — an instruction must travel alone"; exit 1; }

# 3. The permission dies with the key. A stored `true` outliving its credential
#    describes a capability that no longer exists AND silently re-arms on the
#    next paste — a permission nobody granted, for a key nobody has seen.
grep -q 'BankrAgent.forget()' "$WORK/answer.nocomment" \
  || { echo "✗ AgentKey.clear no longer forgets Bankr's acting permission"; exit 1; }

# 4. The UI confirms BEFORE it acts. The Do button must stage a pending
#    instruction, never call act directly — a Do wired straight through is a
#    one-tap trade with no sheet, and it looks identical in a screenshot.
grep -q 'pending = draft' "$WORK/chat.nocomment" \
  || { echo "✗ BankrChatScreen's Do no longer stages a pending instruction"; exit 1; }
grep -qE 'send\(p, acting: true\)' "$WORK/chat.nocomment" \
  || { echo "✗ the confirmation's Send it no longer sends the pending instruction"; exit 1; }

# 5. The host is disclosed (prd §205). A bridge whose API host nobody declared
#    makes the app's own privacy screen quietly wrong.
grep -q 'api.bankr.bot' "$REACH" \
  || { echo "✗ api.bankr.bot is not in the reach registry"; exit 1; }

# 6. ONE dismissal, shared. Two @AppStorage keys would mean waving the banner
#    off in the agent and meeting it again in the Wallet room — a dismissal
#    that was never really a dismissal.
DISMISS=$(grep -rl 'agent.bankrOfferDismissed' Casberi/Casberi | wc -l | tr -d ' ')
[[ "$DISMISS" == "1" ]] \
  || { echo "✗ the banner's dismissal key appears in $DISMISS files — it must be shared, not copied"; exit 1; }

# 7. The banner retires itself when Bankr is connected, and never draws a CTA
#    it has no door for (§83's dead control).
grep -q 'AgentKey.isConfigured(.bankr)' "$BANNER" \
  || { echo "✗ BankrOfferBanner no longer stands down once Bankr is connected"; exit 1; }

# 8. The acting switch is only offered once a key exists — a switch governing a
#    credential nobody has pasted is a dead control.
grep -q 'if configured { conversationSection }' "$SETUP" \
  || { echo "✗ BankrSetupScreen offers the acting switch without a key"; exit 1; }

echo "  ✓ 8 drift guards"

# --- the compiled harness ---------------------------------------------------

cat > "$WORK/stubs.swift" <<'SWIFT'
import Foundation

// Inert stubs. The vault answers whatever a test sets; the ledger records
// nothing. Neither can reach a network, which is the point.
enum StubVault { nonisolated(unsafe) static var stored: String? = nil }

enum TokenVault {
    static func get(_ key: String) -> String? { StubVault.stored }
}

enum AgentProvider {
    case bankr
    var vaultKey: String { "token.bankr-key" }
}

final class NetworkLedger: @unchecked Sendable {
    static let shared = NetworkLedger()
    func record(_ request: URLRequest) {}
}
SWIFT

cat > "$WORK/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if !ok { print("  ✗ \(label)"); failures += 1 }
}
func sync<T>(_ op: @escaping () async -> T) -> T {
    let sem = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var out: T!
    Task { out = await op(); sem.signal() }
    sem.wait()
    return out
}

// --- the permission -------------------------------------------------------
BankrAgent.forget()
check("canAct is OFF by default", BankrAgent.canAct == false)
BankrAgent.canAct = true
check("canAct stores true", BankrAgent.canAct == true)
BankrAgent.forget()
check("forget() clears the permission", BankrAgent.canAct == false)

// --- act's refusals, and the ORDER they fire in ---------------------------
// A key IS present for this one: the permission must win over the credential,
// or "I have a key" would be enough to act.
StubVault.stored = "bnkr-a-real-looking-key"
BankrAgent.canAct = false
check("act refuses while the permission is off, even with a key",
      sync { await BankrAgent.act("swap 1 ETH for USDC") } == .failure(.actingOff))

BankrAgent.canAct = true
check("act refuses an empty instruction",
      sync { await BankrAgent.act("   \n  ") } == .failure(.emptyInstruction))

// With the permission on and a real instruction, the LAST checkpoint before a
// request is built is the key. Reaching exactly here proves the order.
StubVault.stored = nil
check("act reaches the key check only after both guards pass",
      sync { await BankrAgent.act("swap 1 ETH for USDC") } == .failure(.noKey))
StubVault.stored = nil
BankrAgent.canAct = false
check("ask needs a key too", sync { await BankrAgent.ask("what do I hold?") } == .failure(.noKey))

// --- the prompts ----------------------------------------------------------
let rail = BankrAgent.answerOnlyPrefix
check("the answer-only rail still forbids execution",
      rail.contains("ANSWER ONLY") && rail.contains("Do not execute"))
check("the rail names the command case it exists for",
      rail.contains("even if the question reads like a command"))

let acting = BankrAgent.actingPrompt("  limit order: sell 500 USDC of ETH at $4,100  ")
check("THE WHOLE FEATURE: an acting prompt does NOT carry the answer-only rail",
      !acting.contains("ANSWER ONLY") && !acting.contains("Do not execute"))
check("the acting prompt carries the instruction, trimmed",
      acting.hasPrefix("limit order: sell 500 USDC of ETH at $4,100"))
check("the acting prompt asks for a report of what was really done",
      acting.contains("what you actually") && acting.contains("did not do it"))

// The twin. A single missing rail here is the difference between a question
// and an instruction, so both directions are asserted rather than one.
let asking = BankrAgent.askPrompt("what do I hold?")
check("an ASKING prompt DOES carry the rail", asking.hasPrefix(rail))
check("the asking prompt quotes the question", asking.contains("\"what do I hold?\""))
check("extra material rides below the question, not above the rail",
      BankrAgent.askPrompt("q", extra: "ZZTOP").hasSuffix("ZZTOP"))

print(failures == 0 ? "  ✓ 15 assertions" : "  \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

build_and_run() {
  local src="$1" out="$2"
  swiftc -O -o "$out" "$WORK/stubs.swift" "$src" "$WORK/main.swift" 2>"$WORK/build.err" || {
    echo "✗ compile failed:"; head -20 "$WORK/build.err"; return 2
  }
  "$out"
}

cp "$AGENT" "$WORK/BankrAgent.swift"
build_and_run "$WORK/BankrAgent.swift" "$WORK/harness" || exit 1

# --- mutations --------------------------------------------------------------
# Each edits a scratch copy and must make the suite FAIL. A check that cannot
# fail proves nothing.
mutate() {
  local label="$1" sed_expr="$2"
  cp "$AGENT" "$WORK/mut.swift"
  sed -i '' -E "$sed_expr" "$WORK/mut.swift"
  if ! cmp -s "$AGENT" "$WORK/mut.swift"; then
    if build_and_run "$WORK/mut.swift" "$WORK/mutbin" > /dev/null 2>&1; then
      echo "  ✗ mutation SURVIVED: $label"; return 1
    else
      echo "  ✓ caught: $label"; return 0
    fi
  else
    echo "  ✗ mutation matched nothing (stale): $label"; return 1
  fi
}

MUT_FAIL=0
mutate "act no longer checks the permission" \
  's:guard canAct else \{ return \.failure\(\.actingOff\) \}::' || MUT_FAIL=1
mutate "act accepts an empty instruction" \
  's:guard !trimmed\.isEmpty else \{ return \.failure\(\.emptyInstruction\) \}::' || MUT_FAIL=1
mutate "the acting prompt regains the answer-only rail" \
  's:^        \\\(instruction.trimmingCharacters:        \\(answerOnlyPrefix)\\n\\n\\(instruction.trimmingCharacters:' || MUT_FAIL=1
mutate "forget() stops clearing the permission" \
  's#UserDefaults\.standard\.removeObject\(forKey: canActKey\)##' || MUT_FAIL=1
mutate "the acting prompt stops asking what was done" \
  's:what you actually :what you nearly :' || MUT_FAIL=1
mutate "the rail stops forbidding execution" \
  's:Do not execute, prepare, or queue:Feel free to run:' || MUT_FAIL=1

[[ $MUT_FAIL == 0 ]] || { echo "✗ a mutation survived"; exit 1; }
echo "bankr-selftest: OK"
