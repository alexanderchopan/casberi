#!/bin/zsh
# Casberi Bankr self-test — the SHIPPED logic behind the one keyed agent with a
# wallet behind it (2026-08-29 prd §529; the acting half RETIRED 2026-09-03):
#
#   Casberi/Casberi/Model/BankrAgent.swift
#     — prompt            (the ONE prompt, and its answer-only rail)
#     — ask               (the ONE verb, composed onto one runner)
#     — forget            (the retired permission's cleanup door)
#
# That file is compiled WHOLE AND UNMODIFIED against inert stubs — no
# extraction, no copy — so every assertion is about the bytes the app runs.
#
# WHY A HARNESS, AND WHY THIS ONE MATTERS MORE THAN MOST. Every other keyed
# agent in this app can, at worst, give a bad answer. This one holds a
# credential that can move real money on somebody else's servers, so the whole
# safety argument is a few lines of pure logic that no build, screen sweep or
# simulator run can see:
#
#   • EVERY prompt must carry the answer-only rail. Casberi asks Bankr
#     questions and never instructs it, and the prompt is the only place in
#     this codebase where that is said to the far end. A build with the prefix
#     dropped looks and behaves identically right up until somebody types
#     something that reads as an instruction.
#   • There must be exactly ONE prompt builder and ONE verb. A second path —
#     an `act`, an `actingPrompt`, a probe arm that bypasses `prompt` — is a
#     way to reach Bankr without the rail, which is precisely what that file's
#     header promises does not exist.
#   • An EMPTY instruction must never reach the wire. A blank prompt sent to an
#     agent with a wallet is a blank cheque, and there is no good behaviour to
#     hope for on the far end.
#   • Corpus text must never ride along. A page somebody saved is text a
#     stranger wrote, and it has no business in a message to an agent that
#     holds funds.
#
# Each of those failures renders as a perfectly ordinary screen. That is the
# whole reason this file exists.
#
# WHY THE RAIL IS ASSERTED RATHER THAN ITS ABSENCE (the 2026-08-31 reversal).
# For three days this harness asserted the OPPOSITE — that the prompt must not
# claim a rail it cannot enforce — on the reasoning that a sentence in a prompt
# is an instruction a remote model may ignore, while what really bounds Bankr
# is the scope of the key minted at bankr.bot. That reasoning is still correct
# and is still what the setup copy says. It was the wrong conclusion: the rail
# is not a claim about BANKR, it is a statement about CASBERI — this app does
# not ask an agent to move money — and dropping it left the app with no such
# statement anywhere, which is what Apple's macOS 1.0.11 review reacted to.
#
# NO NETWORK. Every assertion here returns before a byte would leave — the
# stubbed vault answers nil unless a test says otherwise, and the key guard is
# the last checkpoint before the request is built.
#
# Pure, local, deterministic. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

AGENT="Casberi/Casberi/Model/BankrAgent.swift"
ANSWER="Casberi/Casberi/Model/AgentAnswer.swift"
SETUP="Casberi/Casberi/Screens/BankrSetupScreen.swift"
CATALOG="Casberi/Casberi/Model/BridgeCatalog.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
for f in "$AGENT" "$ANSWER" "$SETUP" "$CATALOG" "$REACH"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# A comment-stripped copy for every NEGATIVE guard. These files DOCUMENT the
# rules they keep by naming the very thing they must not do ("no second verb",
# "corpus text never rides an instruction"), so a guard grepping raw source
# fires on the prose explaining it. Earned the hard way on `obsidian-selftest`
# and re-earned since.
strip_comments() { sed -E 's://.*::' "$1" | sed -E 's:/\*.*\*/::'; }
strip_comments "$ANSWER"  > "$WORK/answer.nocomment"
strip_comments "$SETUP"   > "$WORK/setup.nocomment"
strip_comments "$AGENT"   > "$WORK/agent.nocomment"
strip_comments "$CATALOG" > "$WORK/catalog.nocomment"

# --- drift guards -----------------------------------------------------------

# 1. ONE VERB. No acting entry point may come back under any of its old names,
#    and nothing anywhere may call one — `bankrAnswer` runs for every "Try with
#    your key" on Bankr, from a composer where nobody has confirmed anything.
grep -qE '\bstatic func (act|actingPrompt)\b' "$WORK/agent.nocomment" \
  && { echo "✗ BankrAgent grew an acting verb again — there is one verb, and it asks"; exit 1; }
grep -qE 'BankrAgent\.(act|actingPrompt)\b' "$WORK/answer.nocomment" \
  && { echo "✗ AgentAnswer reaches an acting verb — there is one verb now"; exit 1; }
grep -q 'canAct' "$WORK/answer.nocomment" \
  && { echo "✗ AgentAnswer consults canAct — the acting permission is retired"; exit 1; }

# 2. ONE PROMPT BUILDER. A second one is a second path to the wire, and the
#    rail asserted below only covers the builder it is asserted on.
BUILDERS=$(grep -cE '^[[:space:]]*static func prompt\(' "$WORK/agent.nocomment" || true)
[[ "$BUILDERS" == "1" ]] \
  || { echo "✗ BankrAgent has $BUILDERS prompt builders — one, or the rail can be walked around"; exit 1; }

# 3. Corpus text must never ride along. The ANSWER path pastes numbered
#    candidates into its own extra material upstream; this file must never
#    name them itself.
grep -qE 'numberedCandidates|OnDeviceModel\.Candidate' "$WORK/agent.nocomment" \
  && { echo "✗ BankrAgent names corpus candidates — the prompt must travel alone"; exit 1; }

# 4. The retired permission's cleanup door survives. A stored `bankr.canAct`
#    left on a device that ran one of the 2026-08-29..09-03 builds describes a
#    capability that no longer exists AND would silently re-arm if the code
#    ever came back.
grep -q 'BankrAgent.forget()' "$WORK/answer.nocomment" \
  || { echo "✗ AgentKey.clear no longer clears the retired Bankr permission"; exit 1; }
grep -q 'bankr.canAct' "$WORK/agent.nocomment" \
  || { echo "✗ forget() no longer removes the stale bankr.canAct default"; exit 1; }

# 5. There is ONE chat, and it is the fab (2026-08-31). The separate Bankr chat
#    screen is deleted — it duplicated the composer's whole surface to hold a
#    second send button.
[ -e "Casberi/Casberi/Screens/BankrChatScreen.swift" ] \
  && { echo "✗ a second Bankr conversation screen is back — the fab is the only chat"; exit 1; }
grep -q 'composerRequest' "$WORK/setup.nocomment" \
  || { echo "✗ the Bankr door no longer raises the one composer"; exit 1; }
grep -q 'canAct' "$WORK/setup.nocomment" \
  && { echo "✗ an acting switch is back in the setup screen"; exit 1; }

# 6. NO PROMOTION, ANYWHERE (2026-09-03). `BankrOfferBanner` put a "Set up
#    Bankr" call to action at the head of the Wallet room and inside the risen
#    agent, advertising that an agent could act onchain — the surface Apple's
#    macOS review named. Bankr keeps its ordinary catalog seat and nothing more.
[ -e "Casberi/Casberi/Screens/BankrOfferBanner.swift" ] \
  && { echo "✗ the Bankr offer banner is back — this seat is not promoted"; exit 1; }
PROMO=$( { grep -rl 'BankrOfferBanner' Casberi/Casberi 2>/dev/null || true; } | wc -l | tr -d ' ')
[[ "$PROMO" == "0" ]] \
  || { echo "✗ $PROMO files still reference BankrOfferBanner"; exit 1; }

# 7. THE COPY MAY NOT OFFER AN ACTION. The catalog summary and features are
#    read on the product page and in the connect flow; a sentence there
#    inviting somebody to tell Bankr what to do is the same claim the banner
#    made, one screen over.
grep -nE 'tell it what to do|a full key can act|and acts onchain' "$WORK/catalog.nocomment" \
  && { echo "✗ the Bankr catalog copy still offers an action"; exit 1; }
grep -nE 'tell it what to do|a full key can act|and acts onchain' "$WORK/setup.nocomment" \
  && { echo "✗ the Bankr setup copy still offers an action"; exit 1; }

# 8. The host is disclosed (prd §205), and the receipts screen says what the
#    request carries — which is now the rail itself.
grep -q 'api.bankr.bot' "$REACH" \
  || { echo "✗ api.bankr.bot is not in the reach registry"; exit 1; }
grep -q 'answer only — never execute' "$REACH" \
  || { echo "✗ the reach registry no longer states the answer-only rail"; exit 1; }

# 9. The door to the composer is only offered once a key exists — a "Ask
#    Bankr" row with no credential behind it is a dead control.
grep -q 'if configured { conversationSection }' "$SETUP" \
  || { echo "✗ BankrSetupScreen offers the chat door without a key"; exit 1; }

# 10. THE SIMULATOR IS DEBUG-ONLY, and this is the sharpest guard in the file.
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

# 11. The simulation returns BEFORE a request is built. Reached after the
#     submit it would be unreachable in the state it exists for (a stale key
#     never gets that far), and a `NetworkLedger` record for a request nobody
#     made is a receipt claiming a reach that never happened.
FAKE_AT=$(grep -n 'if let simulated = await fakeOutcome' "$AGENT" | head -1 | cut -d: -f1)
SUBMIT_AT=$(grep -n 'api.bankr.bot/agent/prompt' "$AGENT" | head -1 | cut -d: -f1)
[[ -n "$FAKE_AT" && -n "$SUBMIT_AT" && "$FAKE_AT" -lt "$SUBMIT_AT" ]] \
  || { echo "✗ the Bankr simulator no longer returns before the submit request"; exit 1; }

echo "  ✓ 11 drift guards"

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

// --- the one verb ---------------------------------------------------------
BankrAgent.forget()
check("an empty instruction never leaves",
      sync { await BankrAgent.ask("   \n  ") } == .failure(.emptyInstruction))
check("no key is its own failure, not a refusal",
      sync { await BankrAgent.ask("swap 1 ETH for USDC") } == .failure(.noKey))

// --- THE RAIL -------------------------------------------------------------
// This app asks Bankr questions and never instructs it. The prompt is the one
// place that is said to the far end, so it is asserted from several angles: a
// missing prefix, a prefix that no longer forbids the verbs that move money,
// and a prefix that has drifted below the question (where a model reads it as
// part of what was asked rather than as the frame around it).
let p = BankrAgent.prompt("what is my balance?")
check("the prompt opens with the answer-only rail",
      p.hasPrefix("Answer only — never execute."))
check("the rail comes BEFORE the question",
      p.range(of: "Answer only")!.lowerBound < p.range(of: "what is my balance?")!.lowerBound)
for verb in ["send", "swap", "bridge", "buy", "sell", "approve", "stake", "sign"] {
    check("the rail forbids \(verb)", p.lowercased().contains(verb))
}
check("the rail forbids queueing one for later",
      p.lowercased().contains("schedule") && p.lowercased().contains("queue"))
check("the rail survives an instruction-shaped question",
      BankrAgent.prompt("swap 1 ETH for USDC").hasPrefix("Answer only — never execute."))
check("the rail survives extra material",
      BankrAgent.prompt("q", extra: "CTX").hasPrefix("Answer only — never execute."))

// --- what the prompt still promises ---------------------------------------
check("the prompt keeps the no-invention promise", p.contains("Never invent a number"))
check("the prompt asks for plain sentences", p.contains("no bullet points"))
check("the question is carried verbatim",
      BankrAgent.prompt("what do I hold?").contains("what do I hold?"))
check("extra material rides below the question",
      BankrAgent.prompt("q", extra: "ZZTOP").hasSuffix("ZZTOP"))

print(failures == 0 ? "  ✓ 20 assertions" : "  \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

build_and_run() {
  local src="$1" out="$2"
  swiftc -Onone -o "$out" "$WORK/stubs.swift" "$src" "$WORK/main.swift" 2>"$WORK/build.err" || {
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
mutate "the answer-only rail is dropped from the prompt" \
  's:Answer only — never execute\.:Please help.:' || MUT_FAIL=1
mutate "the rail stops naming the verbs that move money" \
  's:Do not send, swap, bridge, buy, sell, \\:Do not misbehave, \\:' || MUT_FAIL=1
mutate "the rail stops covering a queued action" \
  's:and do not schedule or queue any \\:and nothing else matters \\:' || MUT_FAIL=1
mutate "the rail drifts below the question" \
  's:^        Answer only — never execute\. Do not send, swap, bridge, buy, sell, \\$:        \\:' || MUT_FAIL=1
mutate "an empty instruction is allowed to leave" \
  's:guard !trimmed.isEmpty else \{ return \.failure\(\.emptyInstruction\) \}::' || MUT_FAIL=1
mutate "the no-invention promise is dropped" \
  's:Never invent a number or a detail\.::' || MUT_FAIL=1
mutate "the prompt stops asking for plain sentences" \
  's:no bullet points:bullet points welcome:' || MUT_FAIL=1

[[ $MUT_FAIL == 0 ]] || { echo "✗ a mutation survived"; exit 1; }
echo "bankr-selftest: OK"
