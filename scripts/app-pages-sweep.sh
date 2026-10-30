#!/bin/zsh
# THE APP-PAGE SWEEP (prd §1622, user: "Yes, add it"): every app's page opened
# over the poured demo — each catalogue app's own page (Library's door), and
# each Wallet app on Home, Holdings, Activity and Spending — and judged from
# the line the app logs as the page settles (`-appPageProbe`, `appPage|`).
# The Wallet's app pages regressed for four weeks because no check ever opened
# one (§1618): this is that check.
#
# A page FAILS when it did not land (the app opened something else), holds no
# rows, or stands on Holdings as "Nothing held" over money it has. Under three
# rows is THIN: reported, never a failure (a quiet app is allowed to be quiet).
#
# Usage: scripts/app-pages-sweep.sh [--self-test]
#   APP_PAGES="GitHub,wallet:Privy"  narrows the run to those targets.
#   APP_PAGES_DEVICE=<udid>          runs on that simulator (default: verify's).
# Output: scripts/output/app-pages-<ts>/ — results.tsv (target, verdict, note),
#   report.txt, one screenshot and the app's log per target. Exits 1 on a FAIL.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ── The verdict, apart so the self-test can hold it to its rules ──────────────
CLASSIFY='
import sys
def choose(kind, target, lines):
    """The line of the target page itself. Every mounted page logs (the Feed
    tab under an app page keeps reporting), so the newest line can be the
    Feed: take the newest line naming the target, else the newest at all."""
    lines = [l for l in lines if l.strip()]
    if kind == "app":
        mine = [l for l in lines if l.split("|")[0].strip() == target]
    else:
        app = target.split("|")[0]
        mine = [l for l in lines if l.split("|")[0].strip() == "Wallet" and "pick=%s " % app in l + " "]
    return (mine or lines or [""])[-1]

def classify(kind, target, line):
    """kind: app | wallet; target: the app (and for wallet "<app>|<tile>")."""
    if not line:
        return "fail", "no appPage line: the page never settled, or the probe is gone"
    f = dict(p.split("=", 1) for p in [x.strip() for x in line.split("|")[1:]] if "=" in p)
    room = line.split("|")[0].strip()
    rows = int(f.get("rows", "0") or 0)
    if kind == "app":
        if room != target:
            return "fail", f"landed on {room}, not {target}"
    else:
        app, tile = target.split("|")
        if room != "Wallet" or f.get("pick") != app:
            return "fail", "landed on %s · %s, not Wallet · %s" % (room, f.get("pick"), app)
        if f.get("held") == "empty":
            return "fail", "Holdings says nothing held"
    if rows == 0:
        return "fail", "no rows"
    if rows < 3:
        return "thin", f"{rows} rows"
    return "ok", "%d rows" % rows + (" · %s" % f.get("tile") if kind == "wallet" else "")
'

if [[ "${1:-}" == --self-test ]]; then
  python3 - <<EOF
$CLASSIFY
cases = [
    ("app", "GitHub", "GitHub | pick=- | tile=- | rows=7 | held=-", "ok"),
    ("app", "GitHub", "All | pick=- | tile=- | rows=40 | held=-", "fail"),
    ("app", "npm", "npm | pick=- | tile=- | rows=0 | held=-", "fail"),
    ("app", "PyPI", "PyPI | pick=- | tile=- | rows=2 | held=-", "thin"),
    ("app", "Sentry", "", "fail"),
    ("wallet", "Privy|holdings", "Wallet | pick=Privy | tile=holdings | rows=9 | held=full", "ok"),
    ("wallet", "Acorns|holdings", "Wallet | pick=Acorns | tile=holdings | rows=3 | held=empty", "fail"),
    ("wallet", "Wise|home", "Wallet | pick=- | tile=home | rows=80 | held=-", "fail"),
    ("wallet", "Peer|activity", "Wallet | pick=Peer | tile=activity | rows=0 | held=-", "fail"),
]
# The newest line is another mounted page's (the Feed tab under GitHub's).
mixed = ["All | pick=- | tile=- | rows=127 | held=-", "GitHub | pick=- | tile=- | rows=5 | held=-",
         "All | pick=- | tile=- | rows=538 | held=-"]
cases.append(("app", "GitHub", choose("app", "GitHub", mixed), "ok"))
cases.append(("app", "npm", choose("app", "npm", mixed), "fail"))
wmixed = ["Wallet | pick=- | tile=home | rows=150 | held=-", "Wallet | pick=Acorns | tile=holdings | rows=3 | held=full",
          "All | pick=- | tile=- | rows=538 | held=-"]
cases.append(("wallet", "Acorns|holdings", choose("wallet", "Acorns|holdings", wmixed), "ok"))
cases.append(("wallet", "Privy|home", choose("wallet", "Privy|home", wmixed), "fail"))
bad = 0
for kind, target, line, want in cases:
    got, note = classify(kind, target, line)
    ok = got == want
    bad += not ok
    print(("  ✓ " if ok else "  ✗ ") + f"{target}: {got} ({note}), want {want}")
import sys
print("app-pages self-test:", "OK" if not bad else f"{bad} wrong")
sys.exit(1 if bad else 0)
EOF
  exit $?
fi

# The verdict's own rules first: a check that cannot show it catches an
# empty page certifies nothing (CLAUDE.md, the pass's rule).
zsh "$0" --self-test >/dev/null || { print -P "%F{red}✗ the sweep's own self-test failed — the check is broken, not the app%f"; exit 1; }

OUT="$ROOT/scripts/output/app-pages-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
BUNDLE="com.casberi.app"
DD="$HOME/Library/Developer/Xcode/DerivedData/CasberiAppPages"
DEV="${APP_PAGES_DEVICE:-$(python3 "$ROOT/scripts/sim-device.py" "iPhone 17 Pro")}" || {
  print -P "%F{red}✗ could not resolve a simulator%f"; exit 1; }
WAIT="${APP_PAGES_WAIT:-16}"

# The targets: every catalogue app by its group, read off the catalogue itself
# so a new app is swept the night it lands. The Wallet's apps open inside the
# Wallet (its menu, prd §1048b) on each of four tiles; the Wallet itself and
# Contacts (Social's page, §1612) are no app page.
TARGETS=("${(@f)$(python3 - "$ROOT/Casberi/Casberi/Model/BridgeCatalog.swift" <<'EOF'
import re, sys
s = open(sys.argv[1]).read()
for name, group in re.findall(r'Offer\(name: "([^"]+)",\s*tagline: "[^"]*",\s*group: "([^"]+)"', s):
    if name in ("Wallet", "Contacts"):
        continue
    if group == "Wallet":
        for tile in ("home", "holdings", "activity", "spending"):
            print(f"wallet\t{name}|{tile}")
    else:
        print(f"app\t{name}")
EOF
)}")
if [[ -n "${APP_PAGES:-}" ]]; then
  typeset -a keep; keep=("${(@s:,:)APP_PAGES}")
  TARGETS=(${(M)TARGETS:#*(${(j:|:)~${keep//wallet:/}})*})
fi
print -r -- "app-pages: ${#TARGETS} pages on $DEV"

# Build once into the sweep's own DerivedData (never verify's, prd §1308's
# reason), through the build lock like every build here.
"$ROOT/scripts/xcb.sh" -project "$ROOT/Casberi/Casberi.xcodeproj" -scheme Casberi \
  -destination "id=$DEV" -derivedDataPath "$DD" build > "$OUT/xcodebuild.log" 2>&1
print -r -- "XCODEBUILD_EXIT=$?" >> "$OUT/xcodebuild.log"
grep -q "XCODEBUILD_EXIT=0" "$OUT/xcodebuild.log" || { print -P "%F{red}✗ build failed — $OUT/xcodebuild.log%f"; exit 1; }
APP="$DD/Build/Products/Debug-iphonesimulator/Casberi.app"

xcrun simctl boot "$DEV" 2>/dev/null; xcrun simctl bootstatus "$DEV" -b >/dev/null
xcrun simctl terminate "$DEV" "$BUNDLE" 2>/dev/null
xcrun simctl install "$DEV" "$APP" || { print -P "%F{red}✗ install failed%f"; exit 1; }
for p in photos calendar reminders contacts; do xcrun simctl privacy "$DEV" grant "$p" "$BUNDLE" 2>/dev/null; done
# A fresh pour, so a seed changed today is what is judged (the stale-demo
# lesson: a retired seat's rows keep a check green).
xcrun simctl launch "$DEV" "$BUNDLE" -onboarded YES -demoExit 4 >/dev/null; sleep 10
xcrun simctl terminate "$DEV" "$BUNDLE" 2>/dev/null
xcrun simctl launch "$DEV" "$BUNDLE" -onboarded YES -demoEnter YES -demo.corpusAllowed NO >/dev/null; sleep 30
xcrun simctl terminate "$DEV" "$BUNDLE" 2>/dev/null

: > "$OUT/results.tsv"
for entry in "${TARGETS[@]}"; do
  kind=${entry%%$'\t'*}; target=${entry#*$'\t'}
  slug=$(print -r -- "$target" | tr ' |' '__')
  if [[ $kind == wallet ]]; then
    args=(-openRoom Wallet -walletScope "seat:${target%%|*}" -openSection "${target##*|}")
  else
    args=(-openRoom "$target")
  fi
  xcrun simctl terminate "$DEV" "$BUNDLE" 2>/dev/null
  xcrun simctl launch --console-pty "$DEV" "$BUNDLE" -onboarded YES -appPageProbe YES \
    -theme.light NO "${args[@]}" > "$OUT/$slug.log" 2>&1 &
  pid=$!
  sleep "$WAIT"
  xcrun simctl io "$DEV" screenshot "$OUT/$slug.png" >/dev/null 2>&1
  xcrun simctl terminate "$DEV" "$BUNDLE" 2>/dev/null
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  grep -a "appPage|" "$OUT/$slug.log" | sed 's/.*appPage| //' > "$OUT/$slug.lines"
  verdict=$(python3 -c "$CLASSIFY
lines = open(sys.argv[3]).read().splitlines()
v, n = classify(sys.argv[1], sys.argv[2], choose(sys.argv[1], sys.argv[2], lines)); print(v + '\t' + n)" "$kind" "$target" "$OUT/$slug.lines")
  print -r -- "$target	$verdict" >> "$OUT/results.tsv"
done

FAILS=$(awk -F'\t' '$2=="fail"' "$OUT/results.tsv" | wc -l | tr -d ' ')
THIN=$(awk -F'\t' '$2=="thin"' "$OUT/results.tsv" | wc -l | tr -d ' ')
{
  print -r -- "${#TARGETS} pages · $FAILS failed · $THIN thin"
  awk -F'\t' '$2!="ok" { printf "%s %s — %s\n", ($2=="fail" ? "✗" : "·"), $1, $3 }' "$OUT/results.tsv"
} > "$OUT/report.txt"
cat "$OUT/report.txt"
xcrun simctl terminate "$DEV" "$BUNDLE" 2>/dev/null
(( FAILS == 0 ))
