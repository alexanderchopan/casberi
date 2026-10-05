#!/bin/zsh
# Day's Subscriptions tile (prd §1111), compiled AS SHIPPED.
#
# `Model/MailSubscriptions.swift` is Foundation-only, so this compiles it
# WHOLE — no stubs, no copied logic. Every failure it catches renders as an
# ordinary-looking list of newsletters:
#
#   • one list split into rows because it renamed itself between issues
#   • a list keyed on the whole `List-Id` header, so the name and the id
#     disagree and the same list stands twice
#   • an unsubscribe door that opens an http page, or a mailto when the list
#     offered https
#   • a cadence stated off two mails ("Every day" from one gap)
#   • the loudest list sorted last, so the cleanup question is answered upside
#     down
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/MailSubscriptions.swift"
VERIFY="scripts/verify.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1; }

cat > "$work/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}

let now = Date(timeIntervalSince1970: 1_800_000_000)
func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }
func mail(_ key: String, _ sender: String, _ days: Double, unsubscribe: String? = nil,
          source: String = "Gmail") -> MailSubscriptions.Mail {
    .init(id: UUID(), key: key, sender: sender, address: "\(sender.lowercased())@x.example",
          unsubscribe: unsubscribe, at: ago(days), source: source)
}

// KEY: the id inside the brackets, lowercased; else the whole value; else the
// sender's mailbox; else nothing.
check(MailSubscriptions.key(listID: "The Weekly Fold <Weekly.Fold.Example>", address: nil) == "weekly.fold.example",
      "a List-Id keys on the id inside its brackets, lowercased")
check(MailSubscriptions.key(listID: "Renamed Fold <weekly.fold.example>", address: "a@b.c")
      == MailSubscriptions.key(listID: "The Weekly Fold <weekly.fold.example>", address: "z@y.x"),
      "a list that renamed itself keeps one key")
check(MailSubscriptions.key(listID: "plain.list.example", address: nil) == "plain.list.example",
      "a bracketless List-Id keys on its whole value")
check(MailSubscriptions.key(listID: nil, address: "News@Shop.Example") == "news@shop.example",
      "no List-Id: the sender's mailbox")
check(MailSubscriptions.key(listID: nil, address: "nobody") == nil, "no id and no mailbox: no key")
check(MailSubscriptions.key(listID: "  ", address: nil) == nil, "an empty header is no key")

// UNSUBSCRIBE: https first, else mailto, never http or a bare word.
check(MailSubscriptions.unsubscribeURL(from: "<mailto:leave@x.example>, <https://x.example/u>")?.scheme == "https",
      "https beats mailto whatever the order")
check(MailSubscriptions.unsubscribeURL(from: "<mailto:leave@x.example>")?.scheme == "mailto",
      "a mailto alone is the door")
check(MailSubscriptions.unsubscribeURL(from: "<http://x.example/u>") == nil, "http is no door")
check(MailSubscriptions.unsubscribeURL(from: "https://x.example/u") == nil, "a URI without brackets is not the header's shape")
check(MailSubscriptions.unsubscribeURL(from: nil) == nil, "no header, no door")

// CADENCE: three mails at least; the median gap.
check(MailSubscriptions.cadenceDays([ago(1), ago(8)]) == nil, "two mails state no cadence")
let weekly = MailSubscriptions.cadenceDays([ago(1), ago(8), ago(15), ago(22)])
check(weekly.map { abs($0 - 7) < 0.01 } ?? false, "four weekly mails read every 7 days")
let lumpy = MailSubscriptions.cadenceDays([ago(0), ago(1), ago(2), ago(30)])
check(lumpy.map { abs($0 - 1) < 0.01 } ?? false, "the median, not the mean: one long gap does not stretch it")
check(MailSubscriptions.cadenceWords(7) == "About weekly", "7 days reads About weekly")
check(MailSubscriptions.cadenceWords(1) == "Every day", "1 day reads Every day")
check(MailSubscriptions.cadenceWords(30) == "About monthly", "30 days reads About monthly")
check(MailSubscriptions.cadenceWords(nil) == nil, "no cadence, no words")
check(MailSubscriptions.rateWords(7) == "1 mail a week", "weekly is 1 mail a week")
check(MailSubscriptions.rateWords(30) == "1 mail a month", "monthly is 1 mail a month")

// COMPOSE: one row per key, the newest name, the newest door, loudest first.
let mails = [
    mail("fold", "Old Fold", 22), mail("fold", "Old Fold", 15),
    mail("fold", "The Weekly Fold", 1, unsubscribe: "<https://fold.example/new>"),
    mail("fold", "The Weekly Fold", 8, unsubscribe: "<https://fold.example/old>"),
    mail("eats", "Eats", 0.5), mail("eats", "Eats", 2), mail("eats", "Eats", 3), mail("eats", "Eats", 5),
    mail("eats", "Eats", 6, source: "iCloud Mail"),
    mail("rare", "Rare", 200), mail("rare", "Rare", 100),
]
let items = MailSubscriptions.compose(mails, now: now)
check(items.count == 3, "three lists, one row each")
check(items.first?.id == "eats", "the list with the most mail this month leads")
check(items.last?.id == "rare", "a list silent this month sorts last")
let fold = items.first { $0.id == "fold" }
check(fold?.name == "The Weekly Fold", "a list is named by its newest mail")
check(fold?.unsubscribe?.absoluteString == "https://fold.example/new", "the door is the newest mail's")
check(fold?.count == 4 && fold?.lastMonth == 4, "every issue counted, all inside the month")
check(fold?.since == ago(22) && fold?.last == ago(1), "since the oldest, last the newest")
check(items.first { $0.id == "eats" }?.sources == ["Gmail", "iCloud Mail"], "each inbox it lands in, once")
check(items.first { $0.id == "rare" }?.lastMonth == 0, "a mail outside the window is not this month's")
check(fold?.mailIDs.count == 4, "every mail is on the row, for the sheet's Recent")

if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("  ok   keys, doors, cadence, compose")
SWIFT

build() { swiftc -Onone -o "$work/run" "$1" "$work/main.swift" 2>"$work/err" || return 1 }

cp "$SRC" "$work/MailSubscriptions.swift"
build "$work/MailSubscriptions.swift" || { cat "$work/err"; fail "the shipped source does not compile"; }
"$work/run" || fail "assertions failed against the shipped source"

mutate() {
  local why="$1" expr="$2"
  cp "$SRC" "$work/m.swift"
  perl -0pi -e "$expr" "$work/m.swift"
  cmp -s "$SRC" "$work/m.swift" && fail "mutation matched nothing: $why"
  if build "$work/m.swift" && "$work/run" >/dev/null 2>&1; then
    fail "mutation SURVIVED — $why"
  fi
  echo "  ok   catches  $why"
}

mutate "a List-Id keyed on its whole header (a rename splits the list)" \
  's/if !inner\.isEmpty \{ return inner\.lowercased\(\) \}/_ = inner/'
mutate "mailto preferred over https" \
  's/if let https = urls\.first\(where: \{ \$0\.scheme\?\.lowercased\(\) == "https" \}\) \{ return https \}\n//'
mutate "an http link offered as the way out" \
  's/\$0\.scheme\?\.lowercased\(\) == "https" \}\) \{ return https \}/["https", "http"].contains(\$0.scheme?.lowercased() ?? "") }) { return https }/'
mutate "a cadence stated off two mails" \
  's/guard dates\.count >= 3 else \{ return nil \}/guard dates.count >= 2 else { return nil }/'
mutate "the quietest list sorted first" \
  's/return \$0\.lastMonth > \$1\.lastMonth/return \$0.lastMonth < \$1.lastMonth/'
mutate "a list named by its oldest mail" \
  's/return Item\(id: key, name: newest\.sender/return Item(id: key, name: oldest.sender/'

# Wiring: the ingest keeps the headers through this key and door; the reading
# composes through this function; the tile draws the reading; the pass runs
# this harness.
grep -q "MailSubscriptions.key(listID: listID, address: address)" Casberi/Casberi/Model/MailBridge.swift \
  || fail "drift: MailIngest no longer keys a list through MailSubscriptions.key"
grep -q "MailSubscriptions.unsubscribeURL(from: unsubscribe)" Casberi/Casberi/Model/MailBridge.swift \
  || fail "drift: MailIngest no longer keeps the door through MailSubscriptions.unsubscribeURL"
grep -q "MailMIME.listHeaders" Casberi/Casberi/Model/IMAPClient.swift \
  || fail "drift: the IMAP client no longer reads the list headers off the fetched bytes"
grep -q "MailSubscriptions.compose(mails, now: now)" Casberi/Casberi/Model/MailSubscriptionsReading.swift \
  || fail "drift: the reading no longer composes through MailSubscriptions.compose"
grep -q "case .reminder, .edited, .list, .unsubscribe: return true" Casberi/Shared/Thing.swift \
  || fail "drift: a list's facts are no longer rowless — the mail's sheet prints its key and its link"
grep -q "mail-subscriptions-selftest.sh" "$VERIFY" \
  || fail "not wired into verify.sh — the completeness guard requires it, with its reason"

echo "✓ mail subscriptions: keys, doors, cadence, compose, 6 mutations"
