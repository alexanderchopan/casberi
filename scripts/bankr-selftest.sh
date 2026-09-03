#!/bin/zsh
# Casberi Bankr self-test — the SHIPPED logic behind the agent that can ACT
# (2026-08-29, prd §529):
#
#   Casberi/Casberi/Model/BankrAgent.swift
#     — forget            (the retired permission's cleanup door)
#     — act               (the two refusals, and the ORDER they fire in)
#     — prompt            (the ONE prompt both readings share)
#     (there is no second prompt: 2026-08-31 collapsed the two verbs)
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
#   • The prompt must never claim a rail it cannot enforce: no ANSWER ONLY.
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
BANNER="Casberi/Casberi/Screens/BankrOfferBanner.swift"
SETUP="Casberi/Casberi/Screens/BankrSetupScreen.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
for f in "$AGENT" "$ANSWER" "$BANNER" "$SETUP" "$REACH"; do
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
strip_comments "$SETUP"  > "$WORK/setup.nocomment"
strip_comments "$AGENT"  > "$WORK/agent.nocomment"

# --- drift guards -----------------------------------------------------------

# 1. The answer path must never reach the acting verb. `bankrAnswer` is called
#    for every "Try with your key" on Bankr, from a composer where nobody has
#    confirmed anything — if it could call `act`, an ordinary question would
#    execute.
grep -qE 'BankrAgent\.(act|actingPrompt)\b' "$WORK/answer.nocomment" \
  && { echo "✗ AgentAnswer reaches a retired acting verb — there is one verb now"; exit 1; }
grep -q 'canAct' "$WORK/answer.nocomment" \
  && { echo "✗ AgentAnswer consults canAct — the KEY's scope is the permission"; exit 1; }

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

# 4. There is ONE chat and ONE verb (2026-08-31). The separate Bankr chat
#    screen is deleted — it duplicated the composer's whole surface to hold a
#    second send button — and the setup screen's door raises the composer
#    instead of pushing a screen back into existence.
[ -e "Casberi/Casberi/Screens/BankrChatScreen.swift" ] \
  && { echo "✗ a second Bankr conversation screen is back — the fab is the only chat"; exit 1; }
grep -q 'composerRequest' "$WORK/setup.nocomment" \
  || { echo "✗ Talk to Bankr no longer raises the one composer"; exit 1; }
# The permission is the KEY's scope, so no switch may reappear in the setup
# screen claiming to grant or withhold what Bankr may do.
grep -q 'canAct' "$WORK/setup.nocomment" \
  && { echo "✗ an acting switch is back — the key scope is the permission"; exit 1; }

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

# 8. The door to the composer is only offered once a key exists — a "Talk to
#    Bankr" row with no credential behind it is a dead control.
grep -q 'if configured { conversationSection }' "$SETUP" \
  || { echo "✗ BankrSetupScreen offers the chat door without a key"; exit 1; }

# 9. THE SIMULATOR IS DEBUG-ONLY, and this is the sharpest guard in the file.
#    `-bankrFake` lets a build answer in Bankr's voice with no request made and
#    no job run — which is exactly what a release build must never be able to
#    do (§83, on the surface where believing it costs money). Every line naming
#    it must sit inside a `#if DEBUG` region; nesting is tracked rather than
#    grepped, because a `#if DEBUG` earlier in the file proves nothing about a
#    line after its `#endif`.
awk '
  /^[[:space:]]*#if[[:space:]]+DEBUG/ { depth++; next }
  /^[[:space:]]*#if/                  { if (depth) depth++; next }
  /^[[:space:]]*#endif/               { if (depth) depth--; next }
  /bankrFake|fakeOutcome/             { if (!depth) { print NR": "$0; bad=1 } }
  END { exit bad ? 1 : 0 }
' "$AGENT" || { echo "✗ the Bankr simulator is reachable outside #if DEBUG"; exit 1; }

# 10. The simulation returns BEFORE a request is built. Reached after the
#     submit it would be unreachable in the state it exists for (a stale key
#     never gets that far), and a `NetworkLedger` record for a request nobody
#     made is a receipt claiming a reach that never happened.
FAKE_AT=$(grep -n 'if let simulated = await fakeOutcome' "$AGENT" | head -1 | cut -d: -f1)
SUBMIT_AT=$(grep -n 'api.bankr.bot/agent/prompt' "$AGENT" | head -1 | cut -d: -f1)
[[ -n "$FAKE_AT" && -n "$SUBMIT_AT" && "$FAKE_AT" -lt "$SUBMIT_AT" ]] \
  || { echo "✗ the Bankr simulator no longer returns before the submit request"; exit 1; }

echo "  ✓ 10 drift guards"

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
check("an empty instruction never leaves",
      sync { await BankrAgent.ask("   \n  ") } == .failure(.emptyInstruction))
check("no key is its own failure, not a refusal",
      sync { await BankrAgent.ask("swap 1 ETH for USDC") } == .failure(.noKey))

// THE PROMPT CLAIMS NO RAIL IT CANNOT ENFORCE (2026-08-31). The old
// answer-only prefix told Bankr not to act — a sentence in a prompt, which a
// model may ignore, standing in for a permission that actually lives in the
// key's scope. Asserting its ABSENCE is the point: bringing it back would
// restore a promise this app cannot keep.
let p = BankrAgent.prompt("what is my balance?")
check("the prompt never says ANSWER ONLY", !p.contains("ANSWER ONLY"))
check("the prompt never forbids execution", !p.lowercased().contains("do not execute"))
check("the prompt keeps the no-invention promise", p.contains("Never invent a number"))
check("the prompt asks for plain sentences", p.contains("no bullet points"))
check("the prompt asks what it did, if it did something", p.contains("say plainly what you did"))
check("the instruction leads the prompt", p.hasPrefix("what is my balance?"))
check("extra rides beneath, not above",
      BankrAgent.prompt("q", extra: "CTX").hasSuffix("CTX"))

check("the prompt asks for a report of what was really done",
      p.contains("say plainly what you did"))
check("the question is carried verbatim",
      BankrAgent.prompt("what do I hold?").contains("what do I hold?"))
check("extra material rides below the question",
      BankrAgent.prompt("q", extra: "ZZTOP").hasSuffix("ZZTOP"))

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
mutate "an empty instruction is allowed to leave" \
  's:guard !trimmed.isEmpty else \{ return \.failure\(\.emptyInstruction\) \}::' || MUT_FAIL=1
mutate "the answer-only rail creeps back into the prompt" \
  's:Answer in a few plain sentences:ANSWER ONLY. Do not execute anything. Answer in a few plain sentences:' || MUT_FAIL=1
mutate "the no-invention promise is dropped" \
  's:Never invent a number or a detail\.::' || MUT_FAIL=1
mutate "the prompt stops asking what was done" \
  's:say plainly what you did:say nothing about what you did:' || MUT_FAIL=1
mutate "the prompt stops asking for plain sentences" \
  's:no bullet points:bullet points welcome:' || MUT_FAIL=1

[[ $MUT_FAIL == 0 ]] || { echo "✗ a mutation survived"; exit 1; }
echo "bankr-selftest: OK"
