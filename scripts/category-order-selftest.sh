#!/bin/zsh
# Casberi category-order self-test — the CATEGORY chips' order, now that it is
# the person's and not a constant (prd §533, 2026-08-29):
#
#   Casberi/Casberi/Model/CategoryOrder.swift
#     — defaultOrder  (the 2026-08-11 ruling, kept as the default)
#     — reconcile     (a stored order made safe to sort by)
#     — rank          (where a label sorts; Int.max for one we've never heard of)
#     — set / reset / isCustom
#
# WHY A HARNESS. Every failure here renders as a perfectly ordinary strip in a
# slightly wrong order, which nobody reports and no other check can see —
# `xcodebuild` is happy, the static audits are text checks, and a screen sweep
# proves a strip painted, never that it painted the right sequence:
#
#   • a stored name that is NOT a category surviving `reconcile` — "All" or
#     "Pinned" would claim a slot in a sort those two are split off ahead of,
#     so the setting would look like it did something and do nothing;
#   • a category MISSING from a stored order being dropped instead of
#     appended, so a category added to the catalog after somebody last
#     rearranged their strip is invisible here, falls to `rank`'s Int.max tail
#     and sits behind everything forever with nothing on screen to say why;
#   • the appended remainder taking a nondeterministic order, so two devices
#     reconcile the same stored list into two different strips;
#   • `rank` answering 0 rather than Int.max for an unknown label, which puts
#     every legacy/unresolved source AHEAD of every category — the one thing
#     the `?? Int.max` fallback this replaced existed to prevent;
#   • `set` persisting the default as though it were a choice, which leaves
#     "Reset to the default order" on screen with nothing to do (§83).
#
# `CategoryOrder.swift` is compiled WHOLE AND UNMODIFIED — it is Foundation-only
# by design, so every ordering asserted below is the shipped code's own and not
# a copy that can drift from it.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

ORDER="Casberi/Casberi/Model/CategoryOrder.swift"
MAIN="Casberi/Casberi/Shell/MainSurface.swift"
SHEET="Casberi/Casberi/Screens/CategoryOrderSheet.swift"
SETTINGS="Casberi/Casberi/Screens/AccountScreen.swift"
CHROME="Casberi/Casberi/Shell/ShellChrome.swift"
CATALOG="Casberi/Casberi/Model/BridgeCatalog.swift"
for f in "$ORDER" "$MAIN" "$SHEET" "$SETTINGS" "$CHROME" "$CATALOG"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/category-order-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# Negative guards read a COMMENT-STRIPPED copy (the Obsidian/Cursor lesson,
# earned repeatedly in this tree): all three of these files DOCUMENT the rules
# they must not break by naming them — `CategoryOrder`'s own doc explains why a
# stored "All" or "Pinned" must be dropped, and `MainSurface`'s explains that
# they are split off ahead of the sort — so a guard grepping raw source fires
# against the prose explaining the rule it protects.
strip_comments() {
  python3 - "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
src = re.sub(r'^\s*//.*$', '', src, flags=re.M)
src = re.sub(r'(?<!:)//.*$', '', src, flags=re.M)
print(src)
PY
}
strip_comments "$ORDER"    > "$TMP/order.nc"
strip_comments "$MAIN"     > "$TMP/main.nc"
strip_comments "$SHEET"    > "$TMP/sheet.nc"
strip_comments "$SETTINGS" > "$TMP/settings.nc"
strip_comments "$CHROME"   > "$TMP/chrome.nc"

# --- drift guards -----------------------------------------------------------
# Wiring the compiled functions cannot prove on their own.

# THE LIST MUST COVER THE CATALOG. `defaultOrder` is a hand list and the
# catalog's categories are the real set; a category added or renamed there and
# not here is not an error anywhere — it simply falls to the Int.max tail, in
# an order nobody chose, with no row in Settings to move it. Checked against
# `BridgeCatalog.categories` itself rather than against a second hand list.
python3 - "$CATALOG" "$ORDER" <<'PY3'
import re, sys
catalog = open(sys.argv[1]).read()
order = open(sys.argv[2]).read()
block = re.search(r'static let categories:.*?^    \]', catalog, re.S | re.M)
if not block:
    sys.exit("✗ BridgeCatalog.categories not found — this guard is testing nothing")
names = re.findall(r'^\s*\("([^"]+)",', block.group(0), re.M)
if len(names) < 5:
    sys.exit("✗ parsed only %d catalog categories — the guard's regex has drifted" % len(names))
listed = re.search(r'static let defaultOrder: \[String\] = \[(.*?)\]', order, re.S)
if not listed:
    sys.exit("✗ CategoryOrder.defaultOrder not found")
have = set(re.findall(r'"([^"]+)"', listed.group(1)))
missing = [n for n in names if n not in have]
if missing:
    sys.exit("✗ catalog categories with no slot in CategoryOrder.defaultOrder: %s\n"
             "  Each would fall to rank()'s Int.max tail in an order nobody chose,\n"
             "  with no row in Settings to move it." % ", ".join(missing))
print("  ✓ every catalog category (%d) has a slot in defaultOrder" % len(names))
PY3

# The strip sorts by THIS order, and the old constant is gone. A constant left
# behind is what the next pass edits, believing it is still the one in force.
grep -q 'CategoryOrder.rank(of:' "$TMP/main.nc" \
  || { echo "✗ the strip no longer sorts by CategoryOrder.rank — a rearrangement would do nothing"; exit 1; }
if grep -qE 'static let categoryOrder' "$TMP/main.nc"; then
  echo "✗ MainSurface carries its own categoryOrder constant again — two orders, and the"
  echo "  one Settings writes is not necessarily the one the strip reads."
  exit 1
fi
# READ ONCE PER WALK, not once per comparison: `current` deserializes a
# UserDefaults array, and an O(n log n) comparator asking for it per compare is
# the mistake `ChipMemory.snapshot()` exists to stop (2026-07-21 audit).
grep -q 'let order = CategoryOrder.current' "$TMP/main.nc" \
  || { echo "✗ the order is no longer hoisted out of the comparator — every comparison would"; \
       echo "  re-read UserDefaults, on the strip's own hot walk."; exit 1; }

# ALL AND PINNED ARE NEVER SORTED. They are split off ahead of the comparator
# and their positions are the two fixed facts of the strip.
grep -q 'folded.prefix(1 + pinned.count)' "$TMP/main.nc" \
  || { echo "✗ All/Pinned are no longer split off ahead of the category sort — a stored order"; \
       echo "  could move the two chips whose position must never move."; exit 1; }

# The strip must RE-FREEZE when the order changes. Settings is pushed inside
# the same scene, so no foreground fires on the way back: without this the new
# order does not appear until the app is next backgrounded, which reads exactly
# like a control that did nothing (§83).
grep -q 'chipOrderPulse' "$TMP/chrome.nc" \
  || { echo "✗ ShellChrome no longer publishes chipOrderPulse"; exit 1; }
grep -q 'onChange(of: chrome.chipOrderPulse)' "$TMP/main.nc" \
  || { echo "✗ MainSurface no longer re-freezes on a rearrangement — the new order would not"; \
       echo "  appear until the app was next backgrounded."; exit 1; }
grep -q 'freezeChips(force: true)' "$TMP/main.nc" \
  || { echo "✗ the re-freeze is no longer forced past the coalescing window — a rearrangement"; \
       echo "  landing within a second of a foreground would be silently dropped."; exit 1; }

# The sheet writes on every MOVE, not on Done: a page sheet can be dismissed by
# swiping down, which never reaches a Done handler, and a rearrangement
# discarded that way is indistinguishable from one that never registered.
grep -q 'onMove(perform: move)' "$TMP/sheet.nc" \
  || { echo "✗ the reorder list no longer has an onMove — the rows would be undraggable"; exit 1; }
python3 - "$TMP/sheet.nc" <<'PY3'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'private func move\(from source: IndexSet, to destination: Int\) \{(.*?)\n    \}', src, re.S)
if not m:
    sys.exit("✗ CategoryOrderSheet.move(from:to:) not found — this guard is testing nothing")
if "commit()" not in m.group(1):
    sys.exit("✗ a move no longer commits — a rearrangement would be lost on a swipe-down dismiss.")
c = re.search(r'private func commit\(\) \{(.*?)\n    \}', src, re.S)
if not c:
    sys.exit("✗ CategoryOrderSheet.commit() not found")
body = c.group(1)
if "CategoryOrder.set(order)" not in body:
    sys.exit("✗ commit no longer stores the order.")
if "chipOrderPulse" not in body:
    sys.exit("✗ commit no longer tells the strip — the setting would not take effect until\n"
             "  the app was next backgrounded.")
PY3

# The door. A setting nothing opens is a setting nobody has.
grep -q 'CategoryOrderSheet()' "$TMP/settings.nc" \
  || { echo "✗ Settings no longer opens the chip-order screen"; exit 1; }

# --- the compiled half ------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

// `CategoryOrder` is `@MainActor` (it is read from the strip's own walk and
// written from a SwiftUI screen, both main-actor). Top-level code in a
// `swiftc` main.swift is NOT main-actor isolated, so the whole run is hoisted
// into one isolated function and entered through `assumeIsolated` — valid
// because top-level code really does run on the main thread, and cheaper than
// dropping the annotation from the shipped type just to make a harness happy.
@MainActor func runAll() -> Never {

var failures = 0
func check(_ what: String, _ ok: Bool) {
    if !ok { failures += 1; print("  ✗ \(what)") }
}

let d = CategoryOrder.defaultOrder

// The RAW UserDefaults value, bypassing `current`'s own reconciliation. Two
// of the mutation checks below need this: `current` reconciles on every
// READ, which means a broken WRITE-side reconcile in `set` is invisible to
// anything that only calls `current`/`isCustom` — the read path silently
// repairs whatever the write path got wrong. That is not a reason the
// write-side reconcile is pointless (a bare UserDefaults read from anywhere
// else, or a future direct migration, would see the unreconciled value), it
// is a reason THIS test needs to look past `current` to catch it. The key
// literal is duplicated from `CategoryOrder.swift` (`private`, so there is no
// way to share it) — a rename there without a matching rename here fails
// closed: `rawStored()` reads nil forever and every check below that expects
// a stored value fails loudly, it does not silently stop testing anything.
func rawStored() -> [String]? { UserDefaults.standard.stringArray(forKey: "chips.categoryOrder") }

// --- the default itself -----------------------------------------------------
check("the default order is the 2026-08-11 ruling, unchanged", d.count == 11)
check("no duplicate slot", Set(d).count == d.count)
check("Wallet leads (user: 'more important to users')", d.first == "Wallet")
check("Social sits after Life and before Media (user ruling)",
      d.firstIndex(of: "Life")! < d.firstIndex(of: "Social")!
      && d.firstIndex(of: "Social")! < d.firstIndex(of: "Media")!)
check("All is not a category slot", !d.contains("All"))
check("Pinned is not a category slot", !d.contains("Pinned"))

// --- reconcile: nothing stored ---------------------------------------------
check("an empty stored order is the default", CategoryOrder.reconcile([]) == d)
check("the default reconciles to itself", CategoryOrder.reconcile(d) == d)

// --- reconcile: a real rearrangement ---------------------------------------
// One name moved to the front is the commonest thing anybody will do here.
let moved = CategoryOrder.reconcile(["Life"])
check("a partial stored order leads with what it names", moved.first == "Life")
check("…and still lists every category", Set(moved) == Set(d))
check("…with the remainder in DEFAULT order, not stored or hash order",
      Array(moved.dropFirst()) == d.filter { $0 != "Life" })

// --- reconcile: names this file has never heard of --------------------------
// "All" and "Pinned" are the two that matter: both are real chips, both are
// split off AHEAD of the sort in `computedChips`, so a stored one would look
// like it should move something and could not.
let dirty = CategoryOrder.reconcile(["All", "Pinned", "Atlantis", "Media", "Wallet"])
check("a stored non-category is dropped", !dirty.contains("All") && !dirty.contains("Pinned"))
check("…including one that is not a chip at all", !dirty.contains("Atlantis"))
check("…and the real names it was mixed with still lead",
      Array(dirty.prefix(2)) == ["Media", "Wallet"])
check("…with nothing lost", Set(dirty) == Set(d))

// --- reconcile: a stored list that repeats itself ---------------------------
let dupes = CategoryOrder.reconcile(["Notes", "Notes", "Wallet", "Notes"])
check("a repeated name takes one slot", dupes.filter { $0 == "Notes" }.count == 1)
check("…at its FIRST appearance", Array(dupes.prefix(2)) == ["Notes", "Wallet"])
check("…and the list is still complete", Set(dupes) == Set(d) && dupes.count == d.count)

// --- reconcile: a category the stored order predates ------------------------
// The forward-compatibility case, and the one nobody would ever see reported:
// somebody rearranges their strip, a later build adds a category, and their
// stored list has no opinion about it.
let older = CategoryOrder.reconcile(d.filter { $0 != "Shopping" && $0 != "Notes" })
check("a category missing from a stored order still appears", older.contains("Shopping") && older.contains("Notes"))
check("…at the tail, in default order",
      Array(older.suffix(2)) == d.filter { $0 == "Notes" || $0 == "Shopping" })

// --- rank -------------------------------------------------------------------
check("rank follows the order given", CategoryOrder.rank(of: "Wallet", in: d) == 0)
check("…and reads the ORDER, not the default",
      CategoryOrder.rank(of: "Media", in: ["Media", "Wallet"]) == 0)
// The whole point of Int.max: a label with no slot keeps its learned position
// at the TAIL. Zero would put every legacy source ahead of every category.
check("an unknown label sorts last, not first",
      CategoryOrder.rank(of: "Gopher", in: d) == Int.max)
check("…so it really does sort behind a category",
      CategoryOrder.rank(of: "Gopher", in: d) > CategoryOrder.rank(of: "Shopping", in: d))

// The sort as the strip performs it, over a mixed list — categories plus one
// uncategorized source that has no slot anywhere.
let mixed = ["Shopping", "Gopher", "Wallet", "Media"]
let sorted = mixed.sorted { CategoryOrder.rank(of: $0, in: d) < CategoryOrder.rank(of: $1, in: d) }
check("the strip's own sort puts categories in order and strangers last",
      sorted == ["Wallet", "Media", "Shopping", "Gopher"])

// --- set / reset / isCustom -------------------------------------------------
CategoryOrder.reset()
check("nothing stored reads as the default", CategoryOrder.current == d)
check("…and not as custom", !CategoryOrder.isCustom)

CategoryOrder.set(["Media"])
check("a stored rearrangement is in force", CategoryOrder.current.first == "Media")
check("…and reads as custom", CategoryOrder.isCustom)

// Set is reconciled on the way IN, so a screen handing over a stray name
// cannot persist one — checked against the RAW store, not `current`, because
// `current` reconciles on every read and would repair a broken write-side
// reconcile silently.
CategoryOrder.set(["All", "Pinned", "Notes"])
check("set drops a non-category before PERSISTING it", rawStored()?.first == "Notes")
check("…and never persists what it was handed", rawStored()?.contains("All") != true)
check("set drops a non-category before storing", CategoryOrder.current.first == "Notes")
check("…and stores nothing else it was handed", !CategoryOrder.current.contains("All"))

// Storing the default IS resetting — otherwise somebody who drags a chip and
// drags it back leaves "Reset to the default order" on screen with nothing to
// do (§83), AND a later app update that changes `defaultOrder` would find a
// stale explicit copy of the OLD default sitting in UserDefaults, reading as
// a custom order nobody chose. Checked against the raw store for the same
// reason as above — `current` reconciles the stale copy right back to
// looking like the default, so only the raw value can show it was left there
// at all.
CategoryOrder.set(d)
check("storing the default writes NOTHING to UserDefaults", rawStored() == nil)
check("storing the default is not a custom order", !CategoryOrder.isCustom)
check("…and the order is the default", CategoryOrder.current == d)

CategoryOrder.set(["Life"])
CategoryOrder.reset()
check("reset really restores the default", CategoryOrder.current == d && !CategoryOrder.isCustom)

print(failures == 0 ? "category-order-selftest: OK" : "category-order-selftest: \(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
}

MainActor.assumeIsolated { runAll() }
SWIFT

echo "category-order-selftest: compiling CategoryOrder.swift as shipped…"
swiftc -O -o "$TMP/run" "$ORDER" "$TMP/main.swift" 2>&1 | grep -v '^ *$' || true
[[ -x "$TMP/run" ]] || { echo "✗ compile failed — CategoryOrder.swift no longer builds Foundation-only"; exit 1; }
"$TMP/run" || exit 1

# --- mutation pass ----------------------------------------------------------
# Each mutation is a plausible edit that must be CAUGHT. A check that cannot
# fail proves nothing (the `--self-test` doctrine used by every audit here).
mutate() {
  local label="$1" expr="$2"
  python3 - "$ORDER" "$TMP/mutated.swift" "$expr" <<'PY'
import sys
src = open(sys.argv[1]).read()
old, new = sys.argv[3].split("|||")
if old not in src:
    sys.exit(f"✗ mutation anchor not found: {old!r} — this harness is testing stale code")
open(sys.argv[2], "w").write(src.replace(old, new, 1))
PY
  if swiftc -O -o "$TMP/mrun" "$TMP/mutated.swift" "$TMP/main.swift" 2>/dev/null \
     && "$TMP/mrun" >/dev/null 2>&1; then
    echo "  ✗ mutation SURVIVED: $label"
    return 1
  fi
  echo "  ✓ mutation caught: $label"
}

echo "category-order-selftest: mutation pass…"
mfail=0
mutate "reconcile trusts a stored order whole — 'All' and 'Pinned' claim slots they can never use" \
  'let clean = reconcile(order)|||let clean = order' || mfail=1
mutate "an unknown stored name survives reconcile" \
  'for name in stored where known.contains(name) && seen.insert(name).inserted {|||for name in stored where seen.insert(name).inserted {' || mfail=1
mutate "a repeated stored name takes two slots" \
  'known.contains(name) && seen.insert(name).inserted|||known.contains(name)' || mfail=1
mutate "a category missing from a stored order is DROPPED instead of appended" \
  'let missing = defaultOrder.filter { !seen.contains($0) }
        return kept + missing|||return kept' || mfail=1
# Deterministically wrong, never a Set's hash order: a mutation that swaps a
# stable order for one that is merely unstable survives at random (the
# 2026-08-28 lesson, three instances in one day). Reversed is a real order and
# never the default's.
mutate "the appended remainder comes back in a different order than the default" \
  'let missing = defaultOrder.filter { !seen.contains($0) }|||let missing = defaultOrder.filter { !seen.contains($0) }.reversed().map { $0 }' || mfail=1
mutate "rank answers 0 for a label it has never heard of — every stranger leads the strip" \
  'order.firstIndex(of: label) ?? Int.max|||order.firstIndex(of: label) ?? 0' || mfail=1
mutate "rank reads the default instead of the order it was handed — a rearrangement does nothing" \
  'order.firstIndex(of: label) ?? Int.max|||defaultOrder.firstIndex(of: label) ?? Int.max' || mfail=1
mutate "set stores the default as though it were a choice — Reset stays on screen with nothing to do" \
  'if clean == defaultOrder {|||if false {' || mfail=1
mutate "current ignores what was stored" \
  'return reconcile(stored)|||return defaultOrder' || mfail=1
mutate "reset leaves the stored order in place" \
  'static func reset() { UserDefaults.standard.removeObject(forKey: key) }|||static func reset() { }' || mfail=1

[[ $mfail -eq 0 ]] || { echo "category-order-selftest: a mutation SURVIVED — a check above proves nothing"; exit 1; }
echo "category-order-selftest: OK — default, reconcile, rank and the store all pinned."
