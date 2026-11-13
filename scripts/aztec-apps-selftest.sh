#!/bin/zsh
# Aztec apps self-test (prd §1757) — the Aztec apps you have connected stand
# as tiles in Library's Wallet folder. What a screen cannot show:
#
#   - a tile named by the page's own title, so any site can call itself
#     RavenHouse over its own address
#   - a tile whose door is not the site's front page over https
#   - the same site twice, or a list that grows without end
#   - a site kept when the answer to Connect was no
#
# Compiles Casberi/Casberi/Model/Aztec/AztecAppsShape.swift (Foundation only)
# against the checks below, then proves each check can fail.
#
#   scripts/aztec-apps-selftest.sh            run it
#   scripts/aztec-apps-selftest.sh --self-test   the same (the pass's name for it)
set -u
cd "$(dirname "$0")/.."
SHAPE="Casberi/Casberi/Model/Aztec/AztecAppsShape.swift"
BROWSER="Casberi/Casberi/Screens/AztecBrowser.swift"
LIBRARY="Casberi/Casberi/Screens/SourcesLibrary.swift"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
var failed = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failed += 1 }
}
let now = Date(timeIntervalSince1970: 1_800_000_000)
func url(_ s: String) -> URL? { URL(string: s) }

check(AztecAppsShape.name(host: "app.ravenhouse.xyz") == "RavenHouse", "a site the directory names takes that name")
check(AztecAppsShape.name(host: "APP.OLLA.FINANCE") == "Olla" && AztecAppsShape.name(host: "www.nemi.fi") == "Nemi",
      "…whatever its case, and behind www")
check(AztecAppsShape.name(host: "privateinference.gg") == "Galactica", "Galactica is called what the directory calls it, not by its address")
check(AztecAppsShape.renamed([AztecAppsShape.App(host: "privateinference.gg", name: "Private Inference", door: "https://privateinference.gg/", at: now)]).map(\.name) == ["Galactica"],
      "a tile kept under an old name reads the table's name when the list is read back")
check(AztecAppsShape.name(host: "ravenhouse.evil.example") == "ravenhouse.evil.example",
      "a site the directory does not name is called by its own address")
check(AztecAppsShape.door(url("https://app.ravenhouse.xyz/collections/7?x=1#top")) == "https://app.ravenhouse.xyz/",
      "a tile opens the site's front page, whatever page you connected on")
check(AztecAppsShape.door(url("http://app.ravenhouse.xyz/")) == nil && AztecAppsShape.door(url("https://user:pw@nemi.fi/")) == nil
      && AztecAppsShape.door(nil) == nil, "nothing but plain https is kept")
check(AztecAppsShape.door(url("https://localhost:8443/x")) == "https://localhost:8443/", "a port that is not 443 stays in the door")

var apps: [AztecAppsShape.App] = []
apps = AztecAppsShape.connected(apps, url: url("https://app.ravenhouse.xyz/"), at: now)
apps = AztecAppsShape.connected(apps, url: url("https://rolling.chat/board"), at: now.addingTimeInterval(60))
check(apps.map(\.host) == ["rolling.chat", "app.ravenhouse.xyz"], "the newest connect leads")
apps = AztecAppsShape.connected(apps, url: url("https://app.ravenhouse.xyz/mint"), at: now.addingTimeInterval(120))
check(apps.map(\.host) == ["app.ravenhouse.xyz", "rolling.chat"] && apps.count == 2, "a site connected again moves up, never listed twice")
check(AztecAppsShape.connected(apps, url: url("http://nemi.fi/"), at: now) == apps, "a site that is not https changes nothing")
var many: [AztecAppsShape.App] = []
for i in 0..<12 { many = AztecAppsShape.connected(many, url: url("https://app\(i).example/"), at: now.addingTimeInterval(Double(i))) }
check(many.count == AztecAppsShape.cap && many.first?.host == "app11.example" && !many.contains { $0.host == "app0.example" },
      "the folder holds eight, and the oldest connect goes first")
check(AztecAppsShape.removed(apps, host: "ROLLING.CHAT").map(\.host) == ["app.ravenhouse.xyz"], "Remove takes one off, by its address")
exit(failed == 0 ? 0 : 1)
SWIFT

if ! swiftc -Onone -o "$TMP/run" "$SHAPE" "$TMP/main.swift" > "$TMP/build.log" 2>&1; then
  echo "✗ the Aztec apps harness does not compile"; tail -20 "$TMP/build.log"; exit 1
fi
"$TMP/run" || { echo "✗ Aztec apps self-test failed"; exit 1; }

# Each check must be able to fail: a change that breaks the rule must turn a check red.
mutate() {
  local what="$1" old="$2" new="$3"
  grep -qF -- "$old" "$SHAPE" || { echo "✗ mutation '$what' has nothing to change: its anchor is gone"; exit 1; }
  python3 - "$SHAPE" "$TMP/Mut.swift" "$old" "$new" <<'PY' || { echo "✗ mutation '$what' is STALE: its anchor is missing or not unique"; exit 1; }
import sys
src, dst, old, new = sys.argv[1:5]
text = open(src, encoding="utf-8").read()
assert text.count(old) == 1, "anchor is not unique"
open(dst, "w", encoding="utf-8").write(text.replace(old, new))
PY
  if ! swiftc -Onone -o "$TMP/mut" "$TMP/Mut.swift" "$TMP/main.swift" > /dev/null 2>&1; then
    echo "✗ mutation '$what' does not compile, so it proves nothing"; exit 1
  fi
  if "$TMP/mut" > /dev/null 2>&1; then echo "✗ mutation '$what' still passes: no check catches it"; exit 1; fi
  echo "  ✓ $what"
}
mutate "a site kept over plain http" \
  'guard let url, url.scheme == "https", let host' \
  'guard let url, url.scheme != nil, let host'
mutate "the same site listed twice" \
  'let rest = apps.filter { $0.host != host }' \
  'let rest = apps'
mutate "a list with no end" \
  '+ rest).prefix(cap))' \
  '+ rest).prefix(1000))'
mutate "a kept tile left under its old name" \
  'apps.map { var app = $0; app.name = name(host: app.host); return app }' \
  'apps.map { $0 }'
mutate "a tile opening the page you happened to be on" \
  'return "https://\(host)\(port)/"' \
  'return url.absoluteString'

# Read: what the screens must still do with it.
grep -q 'if yes { switch ask { case .connect, .ethConnect: rememberApp(); default: break } }' "$BROWSER" \
  || { echo "✗ a site is kept without a yes to Connect, or a connect is no longer kept at all"; exit 1; }
awk '/private func rememberApp\(\) \{/,/^    }/' "$BROWSER" | grep -q 'AztecAppsStore.shared.connected(url)' \
  || { echo "✗ a connected site no longer reaches the store"; exit 1; }
grep -q 'Text(verbatim: app.name)' "$LIBRARY" && ! grep -q 'page.title' "$BROWSER" \
  || { echo "✗ a tile is named by something other than the kept name, or the page title is read"; exit 1; }
grep -q 'AztecAppsShape.renamed(' Casberi/Casberi/Model/Aztec/AztecAppsStore.swift \
  || { echo "✗ the kept list is read back without its names corrected"; exit 1; }
grep -q "canvas.toDataURL('image/png')" "$BROWSER" && grep -q 'if !now { self?.askIconIfMissing() }' "$BROWSER" \
  || { echo "✗ a vector icon is no longer drawn, or a tile with no icon is never asked again"; exit 1; }
echo "✓ Aztec apps self-test passed"
