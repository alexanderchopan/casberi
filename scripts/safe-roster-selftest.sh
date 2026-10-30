#!/bin/zsh
# The Safe pick's roster (prd §1614): your account leads, each Safe says who
# signs it and how many must, and "Without a signature" never calls your
# account's own send path a danger nor a stranger's module safe. A wrong word
# here tells someone their money is safer, or less safe, than it is.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="Casberi/Casberi/Model/SafeRoster.swift"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1; }

cat > "$work/main.swift" <<'SWIFT'
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) { if !ok { print("  ✗ \(what)"); failures += 1 } }
typealias R = SafeRoster

let yours = R.Safe(address: "0xaa", seg: nil, name: "Your account", isYourAccount: true,
                   faces: [.phone, .recovery, .coSigner], threshold: 1, spendLimit: "$100 a month", modules: 3)
let team = R.Safe(address: "0xbb", seg: "eth", name: "Studio", isYourAccount: false,
                  faces: [.you, .person("S"), .person("L")], threshold: 2, spendLimit: nil, modules: 0)
let vault = R.Safe(address: "0xcc", seg: "eth", name: "Ada's vault", isYourAccount: false,
                   faces: [.person("A"), .person("B")], threshold: 2, spendLimit: nil, modules: 1)
let unread = R.Safe(address: "0xdd", seg: "base", name: "Another", isYourAccount: false,
                    faces: [.phone], threshold: nil, spendLimit: nil, modules: 0)

// Order: your account first, then A–Z.
check(R.ordered([vault, team, yours]).map(\.name) == ["Your account", "Ada's vault", "Studio"], "your account leads, then A–Z")

// Who signs.
check(R.line(yours) == "Any one signs", "your account with any one key says so")
let yoursTwo = R.Safe(address: "0xaa", seg: nil, name: "Your account", isYourAccount: true,
                      faces: [.phone, .coSigner], threshold: 2, spendLimit: nil, modules: 0)
check(R.line(yoursTwo) == "This iPhone and co-signer", "your account needing two names its keys")
check(R.line(team) == "You and 2 others", "a Safe you share counts the others")
check(R.line(vault) == "2 owners", "a Safe you hold no key to never says you")
check(R.line(unread) == "Only you", "a Safe only you own says so")
check(R.need(team) == "2 of 3", "threshold of owners")
check(R.need(unread) == nil, "an unread threshold is never guessed")

// Without a signature.
check(R.unsigned(yours) == ("$100 a month", .quiet), "your account states its limit, never its modules")
check(R.unsigned(yoursTwo) == ("None", .confirm), "your account with no limit says None")
check(R.unsigned(team) == ("None", .confirm), "a Safe with no module says None")
check(R.unsigned(vault) == ("1 module", .danger), "a module on another Safe is red")

// The box's words.
check(R.statement(R(safes: [yours, team]), waiting: 0) == "in 2 Safes · nothing to sign", "at rest")
check(R.statement(R(safes: [yours]), waiting: 1) == "in 1 Safe · 1 waiting on others", "one waiting on others")
check(R.signStatement(safeName: "Studio", have: 1, required: 2) == "Studio · yours sends it", "the last signature sends")
check(R.signStatement(safeName: "Studio", have: 1, required: 3) == "Studio · yours makes 2 of 3", "a middle signature counts")
check(R.limitWords(dollars: 100, period: "month") == "$100 a month", "the limit in words")
check(R.limitWords(dollars: 0, period: "month") == nil, "no limit, no words")
check(R.entryName("a transfer of 1,500 USDC") == "A transfer of 1,500 USDC", "a queued name is sentence-cased")

if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("  ok   your account leads, who signs, what moves without a signature")
SWIFT

xcrun swiftc -O "$SRC" "$work/main.swift" -o "$work/t" 2>&1 | grep -v "^$" || true
[[ -x "$work/t" ]] || fail "the shipped source did not compile"
"$work/t" || fail "assertions failed against the shipped source"

mutate() {
  local why="$1" expr="$2"
  cp "$SRC" "$work/m.swift"
  perl -0pi -e "$expr" "$work/m.swift"
  cmp -s "$SRC" "$work/m.swift" && fail "mutation matched nothing: $why"
  xcrun swiftc -O "$work/m.swift" "$work/main.swift" -o "$work/m" >/dev/null 2>&1 || fail "mutation did not compile: $why"
  if "$work/m" >/dev/null 2>&1; then fail "mutation SURVIVED — $why"; fi
  print "  ok   catches  $why"
}
mutate "your account's modules counted as a danger" 's/if safe\.isYourAccount \{\n            if let limit/if false {\n            if let limit/'
mutate "a module reads None"                         's/case 0: return \(String\(localized: "None"\), \.confirm\)\n        case 1: return \(String\(localized: "1 module"\), \.danger\)/case 0, 1: return (String(localized: "None"), .confirm)/'
mutate "a stranger's Safe says you"                  's/guard safe\.faces\.contains\(where: \\\.isYours\) else/guard true else/'
mutate "your account no longer leads"                's/if a\.isYourAccount != b\.isYourAccount \{ return a\.isYourAccount \}/if a.isYourAccount != b.isYourAccount { return b.isYourAccount }/'
mutate "an unread threshold guessed"                 's/guard let threshold = safe\.threshold, safe\.ownerCount > 0 else \{ return nil \}/let threshold = safe.threshold ?? 1/'
print "✓ safe-roster self-test"
