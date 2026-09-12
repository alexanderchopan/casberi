#!/bin/zsh
# Casberi account-page self-test — the SHIPPED judgement behind every account
# page (prd §639, 2026-09-06):
#
#   Casberi/Casberi/Model/AccountPageShape.swift   the words and the order
#   Casberi/Casberi/Model/AccountReaders.swift     who may read an account
#   Casberi/Casberi/Model/AccountNotes.swift       the private note, the visit stamp
#
# Foundation-only BY DESIGN, so all three are compiled WHOLE AND UNMODIFIED
# against one stub (`SharedStore.groupDefaults`, a UserDefaults suite) rather
# than extracted — the strongest form of "the harness ran the shipped logic".
#
# WHY A HARNESS. Every failure mode here renders as a perfectly ordinary page:
#
#   · a state line that says "Reading" over a key the provider refused, or
#     "0 today" for a seat that reads nothing
#   · a "What it reaches" row growing back onto the page, restating per
#     account what the privacy screen states once for the whole app (§702)
#   · a key row that shows a character of the key
#   · a deny list written under one seat and read under another, so an agent
#     the person shut out of one account keeps reading it
#   · a default that stops being a default — an agent added later reads
#     nothing because the allow-list was stored as a snapshot of who existed
#   · a roster that swaps two rows between body passes because the sort was
#     not stable, or that heads its Quiet half with a label over nothing
#   · a note that stored "" and now counts as a note, or a Notes row that
#     no longer shows on the page what was typed into it (§708)
#   · a second removal verb ("Unfollow", "Stop watching") creeping back onto
#     a migrated screen, or a slab section drawn on the page that ruled them
#     out ("looks like a SaaS tool")
#   · a reader filter wired at the candidates and not at the tool snapshot,
#     so a search tool hands the agent exactly the rows the candidates hid
#
# Nothing in a build, a screen sweep or any static audit can see one of these.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

SHAPE="Casberi/Casberi/Model/AccountPageShape.swift"
READERS="Casberi/Casberi/Model/AccountReaders.swift"
NOTES="Casberi/Casberi/Model/AccountNotes.swift"
ENFORCE="Casberi/Casberi/Model/AccountReadersEnforce.swift"
PAGE="Casberi/Casberi/Screens/AccountPage.swift"
TOKEN="Casberi/Casberi/Screens/TokenSetupScreen.swift"
HANDLE="Casberi/Casberi/Screens/HandleSetupScreen.swift"
DETAIL="Casberi/Casberi/Screens/BridgeDetailScreen.swift"
DISCONNECT="Casberi/Casberi/Screens/BridgeDisconnectSection.swift"
ROOT="Casberi/Casberi/Shell/RootShell.swift"
MCP="Casberi/Casberi/Model/MCPTools.swift"
TOKENS="Casberi/Casberi/Design/DesignTokens.swift"
SETTINGS="Casberi/Casberi/Screens/AccountDetailSheet.swift"

for f in "$SHAPE" "$READERS" "$NOTES" "$ENFORCE" "$PAGE" "$TOKEN" "$HANDLE" "$DETAIL" \
         "$DISCONNECT" "$ROOT" "$MCP" "$TOKENS" "$SETTINGS"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A comment-stripped copy for the NEGATIVE guards. These files DOCUMENT what
# they must never do — `AccountPage` names the slogan it refuses and the
# verbs it replaced — so a guard grepping raw source fires against the prose
# explaining it (the Obsidian/Cursor lesson).
strip_comments() {
  python3 - "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r'^[ \t]*///?.*$', '', src, flags=re.M)
src = re.sub(r'//.*$', '', src, flags=re.M)
sys.stdout.write(src)
PY
}
strip_comments "$SHAPE"      > "$TMP/shape-bare.swift"
strip_comments "$PAGE"       > "$TMP/page-bare.swift"
strip_comments "$TOKEN"      > "$TMP/token-bare.swift"
strip_comments "$HANDLE"     > "$TMP/handle-bare.swift"
strip_comments "$DETAIL"     > "$TMP/detail-bare.swift"
strip_comments "$DISCONNECT" > "$TMP/disconnect-bare.swift"
strip_comments "$ROOT"       > "$TMP/root-bare.swift"
strip_comments "$MCP"        > "$TMP/mcp-bare.swift"

# --- drift guards -----------------------------------------------------------
# Wiring the compiled files cannot prove about themselves.

# 1. The three migrated screens build on the chassis and on nothing older.
for f in "$TMP/token-bare.swift" "$TMP/handle-bare.swift" "$TMP/detail-bare.swift"; do
  grep -q 'AccountPage(' "$f" \
    || { echo "✗ ${f:t} does not build on AccountPage"; exit 1; }
  for old in 'BridgeSetupPage(' 'BridgeSetupHeader(' 'BridgeConnectedState(' 'RoomDoor(' \
             '.dsSlabSection()' 'RecentThingsSection('; do
    grep -qF "$old" "$f" \
      && { echo "✗ ${f:t} still draws $old — the slab-and-section anatomy §639 replaced"; exit 1; }
  done
done

# 2. ONE removal verb, "Remove", on every migrated screen and on the chassis.
for f in "$TMP/page-bare.swift" "$TMP/token-bare.swift" "$TMP/handle-bare.swift" "$TMP/detail-bare.swift"; do
  grep -qE '"(Unfollow|Unwatch|Stop watching|Stop following)"' "$f" \
    && { echo "✗ ${f:t} carries a second removal verb — §639: the verb is Remove, everywhere"; exit 1; }
done
grep -q 'Label("Remove", systemImage: "minus.circle")' "$TMP/page-bare.swift" \
  || { echo "✗ the chassis roster row has no Remove swipe"; exit 1; }
# A swipe has no Mac-mouse equivalent — every swipe is mirrored by a context menu.
swipes=$(grep -c '.swipeActions(' "$TMP/page-bare.swift" || true)
menus=$(grep -c '.contextMenu {' "$TMP/page-bare.swift" || true)
[[ "$swipes" -ge 1 && "$swipes" -eq "$menus" ]] \
  || { echo "✗ AccountPage: $swipes swipeActions but $menus contextMenus — a swipe with no Mac mirror"; exit 1; }

# 3. No cards, no slab fills on the page — the only filled element is the field.
for bad in 'dsListCardRow()' 'dsWell(' 'DSSlabDoor(' 'DSSlabButton(' 'surfaceListRow' 'dsTapCard()'; do
  grep -qF "$bad" "$TMP/page-bare.swift" \
    && { echo "✗ AccountPage draws $bad — §639: no cards, no slabs (\"looks like a SaaS tool\")"; exit 1; }
done
grep -q 'DSSlabField(' "$TMP/token-bare.swift" && grep -q 'DSSlabField(' "$TMP/handle-bare.swift" \
  || { echo "✗ an adopter lost its act field — the one filled element, always first"; exit 1; }

# 4. The key never reaches the page. The chassis draws WHERE the key lives and
#    the verb that replaces it, and it has no way to read the value at all.
grep -q 'TokenVault.get(' "$TMP/page-bare.swift" \
  && { echo "✗ AccountPage reads a key value — the page never shows any part of a key"; exit 1; }
grep -q 'AccountPageShape.keyFact(' "$TMP/page-bare.swift" \
  || { echo "✗ the Your key row no longer reads its fact from the shape"; exit 1; }
grep -q 'secure: true' "$TMP/token-bare.swift" \
  || { echo "✗ the token field lost secure entry"; exit 1; }

# 5. NO reach row on an account page (prd §702, user: "we already have 'what
#    it reaches' in settings"). The app's reaches are stated ONCE, on the
#    privacy screen, which is where a person goes to ask that question about
#    the whole app; a per-account copy asked it again on every page, and
#    settings must keep its door or the question is answered nowhere.
grep -qiE 'leaves? (the|this|your) (phone|device)|routes through|no server' "$TMP/shape-bare.swift" "$TMP/page-bare.swift" \
  && { echo "✗ a privacy slogan is on the account page — the app's reaches live in settings (§702)"; exit 1; }
grep -qiE 'What it reaches|reachFact|AccountReach' "$TMP/page-bare.swift" "$TMP/shape-bare.swift" \
  && { echo "✗ the What it reaches row is back on the account page — it lives in settings alone (§702)"; exit 1; }
grep -q 'NetworkReachScreen()' "$SETTINGS" \
  || { echo "✗ settings no longer opens the reach registry — the one place the app's hosts are stated (§702)"; exit 1; }

# 6. The room door keeps RoomDoor's three writes in RoomDoor's order.
python3 - "$TMP/page-bare.swift" <<'PY' || { echo "✗ the Activity row's door no longer closes, pops, then asks — in that order (RoomDoor's lesson)"; exit 1; }
import sys, re
src = open(sys.argv[1]).read()
m = re.search(r'private func openRoom\(\) \{(.*?)\n    \}', src, re.S)
body = m.group(1) if m else ""
a, b, c = body.find("route.closeConnectForm()"), body.find("route.path = []"), body.find("chrome.sourceRequest = source")
sys.exit(0 if 0 <= a < b < c else 1)
PY

# 7. One presentation on the chassis; the adopters own none of their own.
sheets=$(grep -c '\.sheet(' "$TMP/page-bare.swift" || true)
[[ "$sheets" -eq 1 ]] || { echo "✗ AccountPage has $sheets .sheet modifiers — one screen, one sheet"; exit 1; }
for f in "$TMP/token-bare.swift" "$TMP/handle-bare.swift" "$TMP/detail-bare.swift"; do
  grep -q '\.sheet(' "$f" \
    && { echo "✗ ${f:t} presents a sheet of its own beside the chassis's — the sibling-sheet trap"; exit 1; }
done

# 8. Notes and the visit stamp are wired: the note is loaded on appear and
#    stored on change; the visit is stamped on the way OUT, never in.
grep -q 'AccountNotes.note(for: seatID)' "$TMP/page-bare.swift" \
  || { echo "✗ the Notes row no longer loads the stored note"; exit 1; }
grep -q 'AccountNotes.set(now, for: seatID)' "$TMP/page-bare.swift" \
  || { echo "✗ the Notes row no longer stores what is typed"; exit 1; }
grep -q '.onDisappear { AccountVisits.stamp(seatID) }' "$TMP/page-bare.swift" \
  || { echo "✗ the visit is not stamped on disappearance — the ring would never clear"; exit 1; }
grep -q 'onAppear { AccountVisits.stamp' "$TMP/page-bare.swift" \
  && { echo "✗ the visit is stamped on ARRIVAL — the ring would clear before it was seen"; exit 1; }

# 9. "WHO MAY READ IT" IS GONE FROM THE PAGE (prd §708, user: "it is really
#    confusing and no one cares, we already in settings give receipts"). The
#    marks, the caption and the per-account toggle are deleted; what must NOT
#    go with them is the filter itself, which check 10 pins. A block that
#    grows back here is a control nobody asked for, one screen from the
#    receipts that answer the same question for the whole app.
grep -q 'AccountReaderMark\|Who may read it' "$TMP/page-bare.swift" \
  && { echo "✗ the readers block is back on the account page — §708 deleted it"; exit 1; }
grep -q 'AccountReaders.caption' Casberi --include='*.swift' -r \
  && { echo "✗ the readers caption has a call site again — §708 deleted the copy with the block"; exit 1; }

# 10. ENFORCEMENT — every hand-off to a model passes through the reader filter.
grep -q 'AccountReaders.readable(things, by: reader).map' "$TMP/root-bare.swift" \
  || { echo "✗ RootShell.candidates no longer filters by reader — the answer path ignores the allow-list"; exit 1; }
grep -q 'let all = AccountReaders.readable((try? modelContext.fetch(descriptor)) ?? \[\]' "$TMP/root-bare.swift" \
  || { echo "✗ RootShell.toolSnapshot no longer filters by reader — a search tool would hand back the hidden rows"; exit 1; }
grep -q 'reader: reader)' "$TMP/root-bare.swift" \
  || { echo "✗ the keyed synthesize no longer names its agent as the reader"; exit 1; }
grep -q 'AccountReaders.ID.agent(\$0.rawValue)' "$TMP/root-bare.swift" \
  || { echo "✗ the keyed reader id is not derived from the provider"; exit 1; }
mcp_reads=$(grep -c 'by: AccountReaders.ID.mcp' "$TMP/mcp-bare.swift" || true)
[[ "$mcp_reads" -eq 2 ]] \
  || { echo "✗ MCPTools filters by the mcp reader $mcp_reads times, expected 2 (search_things, week_synthesis)"; exit 1; }

# 11. The disconnect is the SHARED one, worn plain — never a second dialog.
grep -q 'BridgeDisconnectSection(bridgeID: seatID, name: source' "$TMP/page-bare.swift" \
  || { echo "✗ the chassis no longer ends in BridgeDisconnectSection"; exit 1; }
grep -q 'plain: true)' "$TMP/page-bare.swift" \
  || { echo "✗ the chassis draws the disconnect as a card row"; exit 1; }
grep -q 'var plain = false' "$TMP/disconnect-bare.swift" \
  || { echo "✗ BridgeDisconnectSection lost its plain ground"; exit 1; }
grep -q 'confirmationDialog' "$TMP/detail-bare.swift" \
  && { echo "✗ BridgeDetailScreen re-implements the keep-or-purge dialog"; exit 1; }
grep -qF 'Remove \(bridge.name)' "$TMP/detail-bare.swift" \
  && { echo "✗ BridgeDetailScreen says Remove where every other screen says Disconnect"; exit 1; }

# 12. The mark has its own rung, and the page wears it.
grep -q 'static let account: CGFloat = 76' "$TOKENS" \
  || { echo "✗ DS.Mark.account is not 76 — the account page's head has one rung"; exit 1; }
grep -q 'BridgeIcon(name: name, size: DS.Mark.account)' "$TMP/page-bare.swift" \
  || { echo "✗ the header's mark is not on DS.Mark.account"; exit 1; }

# 13. THE ACT DRAWS ROWS (prd §640). The flag that turns every slab primitive
#     into its row form is set in exactly three places, all on this chassis —
#     the act slot, its second acts, and the key sheet that draws the same
#     block. Anywhere else and a slab elsewhere in the app silently becomes a
#     row, which is a design change nobody made, in a file nobody looked at.
acts=$(grep -c 'dsAccountAct()' "$TMP/page-bare.swift" || true)
[[ "$acts" -eq 3 ]] \
  || { echo "✗ AccountPage sets dsAccountAct() $acts times, expected 3 (act, more, key sheet)"; exit 1; }
stray=$(grep -rl 'dsAccountAct()' Casberi --include='*.swift' | grep -v 'Screens/AccountPage.swift' \
        | grep -v 'Design/DSAccountAct.swift' || true)
[[ -z "$stray" ]] \
  || { echo "✗ dsAccountAct() is set outside the chassis: $stray — §640: two places, nowhere else"; exit 1; }

# 14. NOTES IS AN INLINE ENTRY ROW that GROWS (prd §708, user: "having a way to
#     add the note inline is better… someone may want to come back to this
#     page and see it, not have to click another time"; §640's reason kept:
#     "they may have an actual note to paste"). Two ways to lose it, both of
#     which render fine: a one-line cap truncates a pasted paragraph into the
#     row, and a sheet hides it behind a tap. It also must not wear a fill —
#     the box is what §708 removed.
grep -q 'lineLimit(1\.\.\.10)' "$TMP/page-bare.swift" \
  || { echo "✗ the Notes field no longer grows 1...10 — a pasted note truncates, or a box is back"; exit 1; }
grep -q 'multilineTextAlignment(.trailing)' "$TMP/page-bare.swift" \
  && { echo "✗ the Notes field is right-aligned again — that is the row shape §640 replaced"; exit 1; }
grep -q 'AccountNotesSheet\|case .notes' "$TMP/page-bare.swift" \
  && { echo "✗ Notes opens a sheet — §708: the note stays on the page"; exit 1; }

echo "✓ drift guards"

# --- the compiled judgement --------------------------------------------------
cat > "$TMP/stub.swift" <<'SWIFT'
import Foundation
// Inert: the real `SharedStore` is a SwiftData container factory; these
// three files only ever read its app-group suite.
enum SharedStore {
    static let groupDefaults: UserDefaults? = UserDefaults(suiteName: "group.com.casberi.selftest.accountpage")
}
SWIFT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}
let suite = UserDefaults(suiteName: "group.com.casberi.selftest.accountpage")!
suite.removePersistentDomain(forName: "group.com.casberi.selftest.accountpage")

let now = Date(timeIntervalSince1970: 1_800_000_000)   // a fixed clock
func ago(_ s: TimeInterval) -> Date { now.addingTimeInterval(-s) }

// ── the state line ────────────────────────────────────────────────────────
print("the state line")
typealias S = AccountPageShape
check("not connected", S.stateLine(.notConnected, now: now) == "Not connected")
check("reading, no read yet", S.stateLine(.reading(lastRead: nil), now: now) == "Reading")
check("reading · 8m ago", S.stateLine(.reading(lastRead: ago(8 * 60)), now: now) == "Reading · 8m ago")
check("reading · just now", S.stateLine(.reading(lastRead: ago(20)), now: now) == "Reading · just now")
check("reading · 3h ago", S.stateLine(.reading(lastRead: ago(3 * 3600)), now: now) == "Reading · 3h ago")
check("reading · 2d ago", S.stateLine(.reading(lastRead: ago(2 * 86_400)), now: now) == "Reading · 2d ago")
check("past a week says the date", !S.stateLine(.reading(lastRead: ago(40 * 86_400)), now: now).hasSuffix("ago"))
check("paused", S.stateLine(.paused, now: now) == "Paused")
check("needs reconnecting · reason", S.stateLine(.needsReconnecting(reason: "key refused"), now: now) == "Needs reconnecting · key refused")
check("needs reconnecting, blank reason", S.stateLine(.needsReconnecting(reason: "  "), now: now) == "Needs reconnecting")
check("connected covers reading, paused, needs-reconnecting",
      S.State.reading(lastRead: nil).connected && S.State.paused.connected
      && S.State.needsReconnecting(reason: "").connected && !S.State.notConnected.connected)
check("needsReconnecting is only that case",
      S.State.needsReconnecting(reason: "x").needsReconnecting && !S.State.paused.needsReconnecting)

// ── the meta line ─────────────────────────────────────────────────────────
print("the meta line")
check("nothing known → nil", S.metaLine(connectedAt: nil, keyExpires: nil, lastRead: nil, missingSince: nil, now: now) == nil)
let expiry = now.addingTimeInterval(30 * 86_400)
let m1 = S.metaLine(connectedAt: ago(5 * 86_400), keyExpires: expiry, lastRead: nil, missingSince: nil, now: now) ?? ""
check("connected · key expires in 30 days", m1.hasPrefix("Connected ") && m1.hasSuffix(" · key expires in 30 days"))
let m2 = S.metaLine(connectedAt: nil, keyExpires: nil, lastRead: ago(3 * 86_400), missingSince: ago(2 * 86_400), now: now) ?? ""
check("last read · 2 days of activity missing", m2.hasPrefix("Last read ") && m2.hasSuffix(" · 2 days of activity missing"))
let m3 = S.metaLine(connectedAt: nil, keyExpires: nil, lastRead: nil, missingSince: ago(90_000), now: now) ?? ""
check("one day missing is singular", m3 == "1 day of activity missing")
check("expiry today", S.metaLine(connectedAt: nil, keyExpires: now, lastRead: nil, missingSince: nil, now: now) == "key expires today")
check("connected wins over last read when both known",
      (S.metaLine(connectedAt: ago(10), keyExpires: nil, lastRead: ago(5), missingSince: nil, now: now) ?? "").hasPrefix("Connected "))

// ── the facts on the rows ─────────────────────────────────────────────────
print("the facts")
check("activity", S.activityFact(today: 14, week: 96, connected: true) == "14 today · 96 this week")
check("activity, not connected, is a dash — never 0 today", S.activityFact(today: 0, week: 0, connected: false) == "—")
check("key fact names the place, never the key", S.keyFact(device: "this iPhone", expires: nil) == "Keychain, this iPhone · Replace")
check("key fact with expiry", S.keyFact(device: "this iPhone", expires: expiry).hasPrefix("Expires ") && S.keyFact(device: "this iPhone", expires: expiry).hasSuffix(" · Replace"))

// ── the roster ────────────────────────────────────────────────────────────
print("the roster")
func row(_ id: String, _ week: Int) -> S.Row {
    S.Row(id: id, title: id, subline: "", weekCount: week, hasNew: false, isYou: false, avatarURL: nil)
}
let rows = [row("a", 0), row("b", 3), row("c", 0), row("d", 1), row("e", 3)]
let split = S.split(rows)
check("active first, in the caller's order", split.active.map(\.id) == ["b", "d", "e"])
check("quiet after, in the caller's order", split.quiet.map(\.id) == ["a", "c"])
check("equal counts never swap (stable)", S.split(rows).active.map(\.id) == split.active.map(\.id))
check("labels", S.watchingLabel(5) == "Watching · 5" && S.quietLabel(2) == "Quiet · 2")

// ── ONE BAR, TWO JOBS (§639 amendment) ───────────────────────────────────
// The field is the add verb AND the roster's filter, and the words have to
// say so: a second search field under the roster was tried and withdrawn
// ("i don't think someone would see that as a search"), and labelling the
// halves "Yours | New" was rejected before that. What is left has to hold:
// the placeholder names both jobs, the roster's label becomes the MATCH
// count under a query (a label saying 140 over three rows is a lie), and
// matching ignores case and accents so a typed name finds the row it names.
check("the placeholder names both jobs, in the order they happen",
      S.findPlaceholder("a repo") == "Find a repo, or search yours")
check("the roster's own labels swap under a query",
      S.yoursLabel(3) == "Yours · 3" && S.onLabel("GitHub") == "On GitHub")
let mRows = [
    S.Row(id: "a", title: "Casberi", subline: "", weekCount: 4, hasNew: false, isYou: false, avatarURL: nil),
    S.Row(id: "b", title: "cásberi-web", subline: "", weekCount: 0, hasNew: false, isYou: false, avatarURL: nil),
    S.Row(id: "c", title: "vitalik", subline: "", weekCount: 1, hasNew: false, isYou: false, avatarURL: nil),
]
check("an empty query is the page at rest", S.matches(mRows, query: "").count == 3)
check("a query matches case- and accent-blind",
      S.matches(mRows, query: "casberi").map(\.id) == ["a", "b"])
check("whitespace alone is not a query", S.matches(mRows, query: "   ").count == 3)
check("a query that names nothing yours leaves the roster empty",
      S.matches(mRows, query: "zzz").isEmpty)
check("the split runs over the MATCHES, not the whole roster",
      S.split(S.matches(mRows, query: "casberi")).quiet.map(\.id) == ["b"])
check("subline, active", S.subline(nouns: "casts", weekCount: 27) == "casts · 27 this week")
check("subline, quiet", S.subline(nouns: "posts", weekCount: 0) == "posts · quiet this week")
check("paused subline", S.pausedSubline == "paused")

// ── notes ─────────────────────────────────────────────────────────────────
print("notes")
check("no note yet", AccountNotes.note(for: "gh", defaults: suite) == nil)
AccountNotes.set("  work token, rotate quarterly  ", for: "gh", defaults: suite)
check("stored, trimmed", AccountNotes.note(for: "gh", defaults: suite) == "work token, rotate quarterly")
AccountNotes.set("Sam's repo", for: "bsky", defaults: suite)
check("two seats, two notes", AccountNotes.all(defaults: suite).count == 2)
AccountNotes.set("   ", for: "gh", defaults: suite)
check("blank text REMOVES the note", AccountNotes.note(for: "gh", defaults: suite) == nil
      && AccountNotes.all(defaults: suite).count == 1)
AccountNotes.forgetAll(defaults: suite)
check("forgetAll", AccountNotes.all(defaults: suite).isEmpty)

// ── the visit stamp ───────────────────────────────────────────────────────
print("the visit stamp")
check("never visited reads nil (a fresh install rings nothing)", AccountVisits.lastLooked("gh", defaults: suite) == nil)
AccountVisits.stamp("gh", at: now, defaults: suite)
check("stamped", AccountVisits.lastLooked("gh", defaults: suite) == now)
check("per seat", AccountVisits.lastLooked("bsky", defaults: suite) == nil)

// ── readers ───────────────────────────────────────────────────────────────
print("readers")
typealias R = AccountReaders
let device = R.Reader(id: R.ID.device, name: "On-device", mark: nil)
let claude = R.Reader(id: R.ID.agent("anthropic"), name: "Claude", mark: "Claude")
let venice = R.Reader(id: R.ID.agent("venice"), name: "Venice", mark: "Venice")
check("default: everyone may read", R.mayRead(claude.id, seat: "gh", defaults: suite) && R.denied(seat: "gh", defaults: suite).isEmpty)
// The CAPTION and its sentence builder went with the page block (§708). What
// is tested here is the deny book and the per-source lookups the ANSWER PATH
// reads — every one of these failures is silent and none of them renders.
R.setMayRead(claude.id, false, seat: "gh", source: "GitHub", defaults: suite)
check("denied under its seat", !R.mayRead(claude.id, seat: "gh", defaults: suite))
check("another seat untouched", R.mayRead(claude.id, seat: "bsky", defaults: suite))
check("device still reads", R.mayRead(device.id, seat: "gh", defaults: suite))
check("an agent added LATER is allowed by default (deny list, not a snapshot)",
      R.mayRead(venice.id, seat: "gh", defaults: suite))
R.setMayRead(device.id, false, seat: "gh", source: "GitHub", defaults: suite)
check("two denials under one seat", R.denied(seat: "gh", defaults: suite) == [claude.id, device.id])
check("denied sources for claude name the SOURCE, not the seat", R.deniedSources(for: claude.id, defaults: suite) == ["GitHub"])
check("denied sources for venice are empty", R.deniedSources(for: venice.id, defaults: suite).isEmpty)
R.setMayRead(claude.id, true, seat: "gh", source: "GitHub", defaults: suite)
check("allowed again", R.mayRead(claude.id, seat: "gh", defaults: suite)
      && R.deniedSources(for: claude.id, defaults: suite).isEmpty)
R.setMayRead(device.id, true, seat: "gh", source: "GitHub", defaults: suite)
check("an empty deny set leaves no entry behind", suite.data(forKey: R.key) == nil)
R.setMayRead(R.ID.mcp, false, seat: "bsky", source: "Bluesky", defaults: suite)
R.setMayRead(R.ID.mcp, false, seat: "fc", source: "Farcaster", defaults: suite)
check("mcp shut out of two sources", R.deniedSources(for: R.ID.mcp, defaults: suite) == ["Bluesky", "Farcaster"])
R.setMayRead(R.ID.mcp, false, seat: "fc", source: "Farcaster (renamed)", defaults: suite)
check("a rename re-stamps the source on the next write",
      R.deniedSources(for: R.ID.mcp, defaults: suite) == ["Bluesky", "Farcaster (renamed)"])
check("denying twice does not double the entry", R.denied(seat: "fc", defaults: suite).count == 1)
R.forget(seat: "bsky", defaults: suite)
check("forget one seat", R.deniedSources(for: R.ID.mcp, defaults: suite) == ["Farcaster (renamed)"])
R.forgetAll(defaults: suite)
check("forgetAll", R.deniedSources(for: R.ID.mcp, defaults: suite).isEmpty)

suite.removePersistentDomain(forName: "group.com.casberi.selftest.accountpage")
if failures > 0 { print("\(failures) failure(s)"); exit(1) }
print("all checks passed")
SWIFT

xcrun swiftc -Onone -o "$TMP/run" "$SHAPE" "$READERS" "$NOTES" "$TMP/stub.swift" "$TMP/main.swift" 2>&1 \
  | grep -v "^$" | grep -v "warning:" || true
[[ -x "$TMP/run" ]] || { echo "✗ compile failed"; exit 1; }
"$TMP/run"

# --- mutations ----------------------------------------------------------------
# Each proves an assertion above is LIVE by breaking the shipped file and
# demanding the run go red. Applied by Python string replace, which fails
# loudly on a miss — a mutant identical to the source is not a passing
# mutation (`mutation-liveness-audit.py`).
mutate() {
  local file="$1" frm="$2" to="$3" label="$4"
  local dir; dir=$(mktemp -d "$TMP/mut.XXXXXX")
  cp "$SHAPE" "$READERS" "$NOTES" "$TMP/stub.swift" "$TMP/main.swift" "$dir/"
  python3 - "$dir/${file:t}" "$frm" "$to" <<'PY'
import sys
path, frm, to = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(path).read()
if frm not in src:
    print(f"✗ mutation anchor not found in {path}: {frm!r}"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  # The applier's exit status is READ: a stale anchor writes no mutant, and a
  # compile over the unmodified copy that then fails for some other reason
  # would be counted as caught (`mutation-liveness-audit.py`).
  [[ $? -eq 0 ]] || { echo "✗ STALE mutation anchor: $label"; exit 1; }
  if xcrun swiftc -Onone -o "$dir/run" "$dir/AccountPageShape.swift" "$dir/AccountReaders.swift" \
       "$dir/AccountNotes.swift" "$dir/stub.swift" "$dir/main.swift" >/dev/null 2>&1 \
     && "$dir/run" >/dev/null 2>&1; then
    echo "✗ MUTATION SURVIVED: $label"; exit 1
  fi
  echo "  ✓ mutation caught: $label"
}
mutate "$SHAPE" 'guard connected else { return "—" }' 'let _ = connected' \
       "a not-connected seat says 0 today"
mutate "$SHAPE" '(rows.filter { $0.weekCount > 0 }, rows.filter { $0.weekCount <= 0 })' \
       '(rows.filter { $0.weekCount > 0 }.reversed(), rows.filter { $0.weekCount <= 0 })' \
       "the active half loses the caller's order"
mutate "$READERS" '        if entry.denied.isEmpty { book.removeValue(forKey: seat) } else { book[seat] = entry }' \
       '        book[seat] = entry' \
       "an empty deny set leaves an entry behind"
mutate "$NOTES" 'if trimmed.isEmpty { book.removeValue(forKey: seat) } else { book[seat] = trimmed }' \
       'book[seat] = trimmed' \
       "a blank note is stored as a note"
# The one-bar filter (§639 amendment). Its two failure modes are opposite and
# both silent: a query that filters nothing leaves the person scrolling 140
# rows they just searched, and a filter that ignores the trim turns a stray
# space into an empty roster.
mutate "$SHAPE" 'guard !q.isEmpty else { return rows }' 'let _ = q' \
       "a query no longer filters the roster"
mutate "$SHAPE" 'let q = query.trimmingCharacters(in: .whitespaces)' 'let q = query' \
       "whitespace alone reads as a query"

echo "✓ account-page-selftest passed"
