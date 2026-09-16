#!/bin/zsh
# Casberi Rocket Money self-test (2026-09-15) — the READ-ONLY guarantee, and
# the host disclosure this seat owes now that it SHIPS (§780b promoted it out
# of `#if DEBUG`):
#
#   Casberi/Casberi/Model/RocketMoneyLive.swift
#   Casberi/Casberi/Screens/RocketMoneyLoginWebView.swift
#
# WHY THIS EXISTS, and why it is the one harness in this repo that guards a
# real-world CONSEQUENCE rather than a rendering. Rocket Money's web app ships
# 114 GraphQL MUTATIONS beside its 91 queries (counted in its own bundle,
# 2026-09-15) — `CancelSubscription`, `AddBudgetItem`, `AcceptPremiumRetentionOffer`,
# `FixPaymentIssue`. This seat learns its operations by WATCHING the live page,
# because the schema is closed (introspection and field suggestions both off),
# so every one of those mutations passes through the capture hook. Replaying a
# single one would cancel somebody's subscription or move somebody's money.
#
# "Read-only" is therefore not a promise in a comment. It is TWO refusals, and
# this harness exists to prove both still refuse:
#
#   1. at CAPTURE — `RocketMoneyOperations.record` drops a non-read before it
#      reaches the store, so a mutation is never written down at all;
#   2. at REPLAY  — `RocketMoneyLive.run` re-checks the text immediately before
#      building the request, so a catalogue entry is never trusted merely
#      because storing it was once checked.
#
# Either alone is one edit away from being the only one. The point of two is
# that no single change removes the guarantee, and the point of this file is
# that removing either is a build failure.
#
# `RocketMoneyLive.swift` cannot compile as shipped (it calls `TokenVault`,
# `IngestSupport` and SwiftData), so `RocketMoneyOperations` is EXTRACTED from
# the shipped source — never copied into this file — so the harness cannot pass
# against logic the app doesn't run.
#
# Pure, local, deterministic — no network, no simulator. `--self-test` proves
# each guard catches the mutation it claims to.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/RocketMoneyLive.swift"
VIEW="Casberi/Casberi/Screens/RocketMoneyLoginWebView.swift"
REACH="scripts/network-reach-audit.sh"
REGISTRY="Casberi/Casberi/Model/NetworkReach.swift"

SELFTEST=0
[[ "${1:-}" == "--self-test" ]] && SELFTEST=1

for f in "$SRC" "$VIEW" "$REACH" "$REGISTRY"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

fail=0
note() { echo "  ✗ $1"; fail=1; }

STRIPPED="$WORK/stripped.swift"
sed -e 's:^[[:space:]]*//.*$::' -e 's:^[[:space:]]*///.*$::' "$SRC" > "$STRIPPED"
VIEW_STRIPPED="$WORK/view.swift"
sed -e 's:^[[:space:]]*//.*$::' -e 's:^[[:space:]]*///.*$::' "$VIEW" > "$VIEW_STRIPPED"

# --- guard 1: BOTH refusals are still wired --------------------------------
grep -q 'guard !name.isEmpty, isRead(query) else { return }' "$STRIPPED" \
  || note "the CAPTURE refusal is gone — a mutation can now be written to the catalogue"
grep -q 'guard RocketMoneyOperations.isRead(query) else { return .notARead }' "$STRIPPED" \
  || note "the REPLAY refusal is gone — a stored entry is now trusted without re-checking"

# --- guard 2: the filter lives in Swift, not in the injected script ---------
# A page controls its own JavaScript; it does not control ours. The script may
# forward anything, but the decision must be made where it can be audited.
grep -qE 'indexOf\(.mutation.\)|startsWith\(.mutation.\)' "$VIEW_STRIPPED" \
  && note "the mutation filter moved into the injected script — it belongs in Swift (see the header)"
grep -q 'RocketMoneyOperations.record(name: name, query: query)' "$VIEW_STRIPPED" \
  || note "the view no longer records through record() — it may be writing the store directly, past the filter"

# --- guard 3: the seat SHIPS now, so its hosts must be disclosed ------------
# §780b promoted it out of `#if DEBUG`, which inverts what this guard checks.
# The DEBUG-only promise is gone; the obligation it was standing in for — the
# hosts being declared rather than sitting on a denylist — is what remains, and
# it is now a real ship gate rather than a staging one (prd §205).
grep -q 'api.rocketmoney.com' "$REGISTRY" \
  || note "api.rocketmoney.com is not in NetworkReach — the seat reaches it on every foreground (ship gate, prd §205)"
grep -q 'app.rocketmoney.com' "$REGISTRY" \
  || note "app.rocketmoney.com (the sign-in) is not in NetworkReach"
grep -qE '^\s*(app|api)\.rocketmoney\.com\s*$' "$REACH" \
  && note "a rocketmoney host is back on the non-reach denylist — the seat ships and really does reach both"

# --- guard 4: the probe prints shape, never values --------------------------
grep -q 'keys.sorted()' "$STRIPPED" \
  || note "the probe no longer reports KEY NAMES — if it now prints values, it is logging somebody's balances (§780)"
grep -qE 'NSLog\([^)]*(data|value|balance|amount)\[' "$STRIPPED" \
  && note "the probe looks like it prints a value — it may print shape only"

# --- the filter itself, against real operation shapes ----------------------
# Extracted, never copied — with only the STORE swapped for an in-memory one,
# so `record`'s refusal is the shipped line and not a paraphrase of it.
{ echo "import Foundation"
  awk '/^enum RocketMoneyOperations \{/,/^\}$/' "$SRC"
} > "$WORK/ops.raw.swift"
python3 - "$WORK/ops.raw.swift" "$WORK/ops.swift" <<'EXTRACT'
import sys
src, dst = sys.argv[1], sys.argv[2]
t = open(src).read()
subs = [
    ("(UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]", "_store"),
    ("UserDefaults.standard.set(all, forKey: key)", "_store = all"),
    ("UserDefaults.standard.removeObject(forKey: key)", "_store = [:]"),
]
for a, b in subs:
    assert a in t, f"extraction anchor missing: {a}"
    t = t.replace(a, b)
t = t.replace("enum RocketMoneyOperations {",
              "enum RocketMoneyOperations {\n    nonisolated(unsafe) static var _store: [String: String] = [:]", 1)
open(dst, "w").write(t)
EXTRACT
grep -q 'static func isRead' "$WORK/ops.swift" || { echo "✗ could not extract isRead"; exit 1; }

cat > "$WORK/main.swift" <<'MAIN'
import Foundation

var bad = 0
func expect(_ query: String, _ want: Bool, _ what: String) {
    let got = RocketMoneyOperations.isRead(query)
    if got == want { print("  ✓ \(what)") }
    else { print("  ✗ \(what) — isRead returned \(got), wanted \(want)"); bad += 1 }
}

// Reads the seat wants. Names are real (from the publisher's own bundle).
expect("query Subscriptions { viewer { subscriptions { id } } }", true, "a named query is a read")
expect("query TransactionsPage($id: ID!) { transactions { amount } }", true, "a parameterised query is a read")
expect("  \n  query NetWorthQuery { netWorth }", true, "leading whitespace does not hide a read")

// Mutations. Every one of these names is real, and every one is an act.
expect("mutation CancelSubscription($input: CancelSubscriptionInput!) { ok }", false, "a mutation is refused")
expect("  mutation AddBudgetItem { ok }", false, "leading whitespace does not sneak a mutation past")
expect("MUTATION FixPaymentIssue { ok }", false, "an upper-case mutation is refused")
expect("mutation AcceptPremiumRetentionOffer { ok }", false, "a retention-offer mutation is refused")

// The shape that defeats a naive prefix check: one document, two operations.
expect("query Viewer { me } mutation CancelSubscription { ok }", false,
       "a document carrying BOTH a query and a mutation is refused")

// Conservative by design: an anonymous shorthand IS a read, but accepting it
// would mean accepting anything that merely fails to say `mutation`.
expect("{ viewer { id } }", false, "an anonymous shorthand is refused — conservative on purpose")
expect("subscription OnTransaction { id }", false, "a subscription operation is refused")
expect("", false, "empty text is refused")

// The bug this harness caught on its first run: a FIELD named like a keyword
// is not a keyword. The first `isRead` asked `contains("subscription")` and so
// refused `query Subscriptions`, the single read this seat most wants.
expect("query Subscriptions { viewer { subscriptions { id } } }", true,
       "a field called `subscriptions` does not make a read look like a subscription")
expect("query X { viewer { mutationLog { id } } }", true,
       "a field whose name merely starts with `mutation` is not a mutation")
// The case that actually exercises the DEPTH check: a field spelled exactly
// like the keyword, singular, inside a selection set. Only depth separates
// this from a real subscription operation.
expect("query X { viewer { subscription { id } } }", true,
       "a field spelled exactly `subscription` is still a read inside a selection set")
expect("query X($s: String = \"a{b\") { viewer { id } }", true,
       "a brace inside a string literal does not skew the depth")
expect("query A { a }\nmutation B { b }", false,
       "a second operation after the first is still refused")

print(bad == 0 ? "  filter: ok" : "  filter: \(bad) failed")
exit(bad == 0 ? 0 : 1)
MAIN

swiftc -O "$WORK/ops.swift" "$WORK/main.swift" -o "$WORK/run" 2>"$WORK/swiftc.log" \
  || { echo "✗ could not compile the extracted filter:"; tail -5 "$WORK/swiftc.log"; exit 1; }
"$WORK/run" || fail=1

# --- the self-test: every guard must catch its own mutation ----------------
if (( SELFTEST )); then
  echo "  — self-test —"
  probe() {
    local name="$1" target="$2" expr="$3"
    local sandbox="$WORK/sandbox"
    rm -rf "$sandbox"; mkdir -p "$sandbox"
    # A COPY of the tree, never the tracked file: a concurrent session's
    # `git add -A` would otherwise commit the mutation.
    cp -R Casberi scripts "$sandbox/" 2>/dev/null
    sed -i '' "$expr" "$sandbox/$target"
    if ( cd "$sandbox" && zsh scripts/rocketmoney-selftest.sh >/dev/null 2>&1 ); then
      echo "  ✗ self-test: '$name' was NOT caught"; fail=1
    else
      echo "  ✓ catches $name"
    fi
  }
  probe "the capture refusal being dropped" "$SRC" \
        's|guard !name.isEmpty, isRead(query) else { return }|guard !name.isEmpty else { return }|'
  probe "the replay refusal being dropped" "$SRC" \
        's|guard RocketMoneyOperations.isRead(query) else { return .notARead }||'
  probe "the filter accepting a mutation" "$SRC" \
        's|guard text.lowercased().hasPrefix("query") else { return false }|guard !text.isEmpty else { return false }|'
  probe "the multi-operation document slipping through" "$SRC" \
        's|if wordIsOperation() { return false }||'
  probe "the depth check being dropped (which refuses a Subscriptions read)" "$SRC" \
        's|guard depth == 0, !word.isEmpty else { return false }|guard !word.isEmpty else { return false }|'
  probe "a host quietly leaving the reach registry" "Casberi/Casberi/Model/NetworkReach.swift" \
        's|api.rocketmoney.com|api.example-removed.com|'
fi

if (( fail )); then
  echo "rocketmoney-selftest: FAILED"
  exit 1
fi
echo "rocketmoney-selftest: ok"
