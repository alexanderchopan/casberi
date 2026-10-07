#!/bin/zsh
# Casberi key-shape self-test — whose key a pasted string is (prd §1162):
#
#   Casberi/Casberi/Model/KeyShape.swift   (compiled whole)
#
# WHY A HARNESS. Both failures look like a working field. A prefix list that
# claims too much refuses a person's real key before the provider is ever
# asked (a bare `sk_` would turn every Splits key into "That's a Stripe key");
# a list in the wrong order names the wrong issuer (`sk-` before `sk-ant-`).
# And the check must be WIRED: a function no connect path calls catches
# nothing.
#
# Pure, local, deterministic. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

SHAPE="Casberi/Casberi/Model/KeyShape.swift"
[[ -f "$SHAPE" ]] || { echo "✗ $SHAPE not found"; exit 1; }
TOKEN="Casberi/Casberi/Screens/TokenSetupScreen.swift"
grep -q 'KeyShape.belongsElsewhere(' "$TOKEN" \
  || { echo "✗ the token connect no longer checks whose key was pasted"; exit 1; }
FAILURE="Casberi/Casberi/Model/ConnectFailure.swift"
grep -q 'ConnectFailure.from(status:' "$TOKEN" \
  || { echo "✗ a failed paste no longer says what the provider answered"; exit 1; }
# The read must be THIS key's: the record is cleared before the key is stored.
perl -0ne 'exit((/healthKeys\.forEach\(BridgeHealth\.forget\)(?:(?!TokenIngest\.refresh)[\s\S]){0,900}?TokenVault\.set\(token, for: bridge\.tokenKey\)/) ? 0 : 1)' "$TOKEN" \
  || { echo "✗ the paste no longer clears the health record first — a failure would read the last key's status"; exit 1; }
# A failed REPLACE puts the old key back: keys sync, so a delete there would
# disconnect every device on one mistaken Paste.
grep -q 'replacedToken = TokenVault.get(bridge.tokenKey)' "$TOKEN" \
  && grep -q 'TokenVault.set(previous, for: bridge.tokenKey)' "$TOKEN" \
  || { echo "✗ a failed replace no longer restores the key it replaced"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$SHAPE" "$FAILURE" "$TMP/"
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { failures += 1; print("✗ \(what)") }
}

// Another service's key, named.
check(KeyShape.belongsElsewhere("sk_live_abc123", pastedInto: "Linear") == "Stripe", "a Stripe key in Linear's field is Stripe's")
check(KeyShape.belongsElsewhere("github_pat_11AB", pastedInto: "GitLab") == "GitHub", "a GitHub token in GitLab's field is GitHub's")
check(KeyShape.belongsElsewhere("  glpat-xyz\n", pastedInto: "GitHub") == "GitLab", "whitespace around a pasted key does not hide its prefix")
// Longest first: Anthropic's and OpenRouter's keys both start `sk-`.
check(KeyShape.issuer(of: "sk-ant-api03-xyz") == "Anthropic", "sk-ant- is Anthropic's, not a shorter prefix's")
check(KeyShape.issuer(of: "sk-or-v1-xyz") == "OpenRouter", "sk-or- is OpenRouter's")
// This service's own key passes.
check(KeyShape.belongsElsewhere("lin_api_xyz", pastedInto: "Linear") == nil, "Linear's own key passes")
check(KeyShape.belongsElsewhere("gho_device", pastedInto: "GitHub") == nil, "a GitHub OAuth token passes GitHub")
// An unstamped key is never refused: the provider decides.
check(KeyShape.belongsElsewhere("0123456789abcdef0123456789abcdef01234567", pastedInto: "Todoist") == nil, "a 40-hex Todoist key passes")
check(KeyShape.belongsElsewhere("sk_9f8e7d", pastedInto: "Splits") == nil, "a bare sk_ (Splits) is nobody's by prefix")
check(KeyShape.belongsElsewhere("sk-abc", pastedInto: "Venice") == nil, "a bare sk- is nobody's by prefix")
check(KeyShape.issuer(of: "") == nil, "an empty paste names no one")
// The list is longest-first, so no prefix is shadowed by a shorter one.
let ps = KeyShape.prefixes.map(\.prefix)
check(zip(ps, ps.dropFirst()).allSatisfy { $0.count >= $1.count }, "prefixes are ordered longest first")

// What a failed paste says, by what the provider answered.
check(ConnectFailure.from(status: nil) == .unreachable, "no answer at all is unreachable")
check(ConnectFailure.from(status: 401) == .refused, "401 is a refused key")
check(ConnectFailure.from(status: 403) == .missingAccess, "403 is a key missing access")
check(ConnectFailure.from(status: 429) == .rateLimited, "429 is being asked to slow down")
check(ConnectFailure.from(status: 200) == .unknown, "a 200 that still failed says neither 'refused' nor 'connection'")
check(ConnectFailure.from(status: 500) == .unknown, "a 500 is not the key's fault")
let all: [ConnectFailure] = [.refused, .missingAccess, .rateLimited, .unreachable, .unknown]
check(Set(all.map { $0.sentence("Linear") }).count == all.count, "every failure has its own sentence")
check(all.allSatisfy { $0.sentence("Linear").contains("Linear") }, "every sentence names the service")

if failures > 0 { print("✗ key-shape self-test: \(failures) failed"); exit(1) }
print("✓ key-shape self-test passed")
SWIFT
xcrun swiftc -O "$TMP"/*.swift -o "$TMP/run" 2>&1 | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ key-shape harness did not compile"; exit 1; }
"$TMP/run"
