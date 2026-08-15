#!/bin/bash
# Legible-ink self-test (2026-08-14, the All-feed source tint).
#
# WHY THIS EXISTS. `BandRow`'s trailing label wears its SOURCE's brand hue.
# That slot was colored once before and the color was PULLED on 2026-07-30 for
# two reasons, and only one of them was about taste: the old `ProjectHue` ink
# measured ~3.4:1 at `label11`, under the 4.5:1 bar `DS.textTertiary` was raised
# to meet on 2026-07-21. Nothing caught that — a contrast failure compiles, runs,
# screenshots and ships, and is invisible to every other check in this repo.
#
# So the arithmetic behind the new ink (`DS.solveInk`) is extracted FROM THE
# SHIPPED SOURCE and compiled WHOLE and unmodified, together with the two
# helpers it calls. It is a pure function of five Doubles by design — every
# environment read (the theme, Increase Contrast, the brand table) lives in
# `legibleInk(for:)`, which this deliberately does NOT compile.
#
# WHAT IT PROVES: for every brand hue in the shipped table, on every page the
# themes can produce, the ink either clears the bar or is nil. Never in between.
# WHAT IT CANNOT PROVE: that `legibleInk(for:)` reads the right page, or that
# the row draws the color it is handed. Those are a build's and a screenshot's
# job respectively.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Design/AppIconTile.swift"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- extract the pure half from the shipped source (never a copy) ------------
# `grabfunc <name>` prints the function from its signature line through the
# brace that closes it, counted rather than guessed — the `grabvar` trap
# recorded in x-selftest.sh (brace-matching from the next `{` swallows the
# following declaration on anything closure-less).
grabfunc() {
  awk -v want="$1" '
    index($0, want) && !started { started = 1 }
    started {
      print
      n = gsub(/\{/, "{"); m = gsub(/\}/, "}")
      depth += n - m
      if (depth == 0 && seen) exit
      if (n > 0) seen = 1
    }
  ' "$SRC"
}

{
  echo "import Foundation"
  echo "enum DS {"
  grabfunc "private static func wcagLuminance"
  grabfunc "private static func rgbComponents"
  grabfunc "static func solveInk"
  echo "}"
} > "$WORK/ink.swift"

for fn in wcagLuminance rgbComponents solveInk; do
  grep -q "func $fn" "$WORK/ink.swift" || { echo "FAIL: could not extract $fn from $SRC"; exit 1; }
done

# --- the harness ------------------------------------------------------------
cat > "$WORK/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  FAIL: \(what)"); failures += 1 }
}

func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
func lum(_ r: Double, _ g: Double, _ b: Double) -> Double {
    0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
}
func hexLum(_ hex: String) -> Double {
    var v: UInt64 = 0
    Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
    return lum(Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
}
// HSB -> RGB, written independently of the shipped `rgbComponents` on purpose:
// a harness that reuses the function under test cannot catch that function
// being wrong.
func hsb(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
    let i = (h * 6).rounded(.down), f = h * 6 - i
    let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
    switch Int(i) % 6 {
    case 0: return (v, t, p)
    case 1: return (q, v, p)
    case 2: return (p, v, t)
    case 3: return (p, q, v)
    case 4: return (t, p, v)
    default: return (v, p, q)
    }
}
func ratio(_ a: Double, _ b: Double) -> Double {
    (max(a, b) + 0.05) / (min(a, b) + 0.05)
}
func inkRatio(_ ink: (hue: Double, saturation: Double, brightness: Double), _ page: Double) -> Double {
    let (r, g, b) = hsb(ink.hue, ink.saturation, ink.brightness)
    return ratio(lum(r, g, b), page)
}

// Every page the themes can produce (ThemeStore.backgrounds, dark + light).
let PAGES: [(String, String)] = [
    ("Default dark", "#000000"), ("Default light", "#f2f2f7"),
    ("Purple dark", "#8a3ffc"),  ("Purple light", "#c9a8ff"),
    ("Pink dark", "#ff2d78"),    ("Pink light", "#ffa5c4"),
    ("Red dark", "#ff3b30"),     ("Red light", "#ff9f99"),
    ("Orange dark", "#ff7a00"),  ("Orange light", "#ffc584"),
    ("Teal dark", "#00b3bf"),    ("Teal light", "#8fe0e6"),
    ("Green dark", "#18b84a"),   ("Green light", "#8fe0a6"),
]

// A spread of real brand hues from the shipped table, as (h, s, b).
// Named so a failure says which brand broke.
// The four marked DESAT are load-bearing, not filler: a deep blue cannot get
// bright enough on its own (pure blue tops out at 0.07 luminance), so only
// those exercise the brighten branch's saturation search. Without one in this
// list that whole search is untested and its mutations survive.
let BRANDS: [(String, Double, Double, Double)] = [
    ("farcaster", 0.7262, 0.5463, 0.8039),
    ("bluesky",   0.5804, 0.9922, 1.0000),
    ("rss",       0.0537, 0.8595, 0.9490),
    ("wallet",    0.6202, 0.8588, 1.0000),  // DESAT
    ("kalshi",    0.4105, 0.5460, 0.6824),
    ("snapchat",  0.1647, 1.0000, 1.0000),  // the 1.1:1 worst case for a raw wash
    ("spotify",   0.3921, 0.8432, 0.7255),
    ("youtube",   0.0000, 1.0000, 1.0000),
    ("stripe",    0.6748, 0.6431, 1.0000),  // DESAT
    ("obsidian",  0.7281, 0.7553, 0.9294),  // DESAT
    ("instagram", 0.9435, 0.7867, 0.8824),
    ("gnosispay", 0.6944, 0.7500, 0.7529),  // DESAT
    ("aerodrome", 0.6348, 0.9843, 1.0000),  // DESAT
    ("uniswap",   0.9203, 1.0000, 1.0000),
    ("morpho",    0.6095, 0.8353, 1.0000),
]

print("legible-ink self-test")

// ===== 1. THE INVARIANT: cleared or nil, never in between ==================
for bar in [4.5, 7.0] {
    for (pname, phex) in PAGES {
        let page = hexLum(phex)
        for (bname, h, s, v) in BRANDS {
            guard let ink = DS.solveInk(hue: h, saturation: s, brightness: v,
                                        pageLuminance: page, bar: bar) else { continue }
            let r = inkRatio(ink, page)
            check(r >= bar - 0.001,
                  "\(bname) on \(pname) at bar \(bar): returned an ink measuring \(String(format: "%.2f", r)):1")
        }
    }
}

// ===== 2. THE DEFAULT THEME TINTS EVERY HONEST HUE =========================
// The theme almost everyone runs must not fall back to gray — a tint that is
// usually absent is a bug that looks like a design choice.
for (pname, phex) in [("Default dark", "#000000"), ("Default light", "#f2f2f7")] {
    let page = hexLum(phex)
    for (bname, h, s, v) in BRANDS {
        check(DS.solveInk(hue: h, saturation: s, brightness: v, pageLuminance: page, bar: 4.5) != nil,
              "\(bname) got no tint on \(pname)")
    }
}

// ===== 3. A NEAR-NEUTRAL MARK IS NEVER TINTED ==============================
// X's black, ChatGPT's white, Cursor, Tokens: no honest hue, so no ink.
for (name, s) in [("x/black", 0.0), ("chatgpt/white", 0.0), ("near-neutral", 0.14)] {
    for page in [hexLum("#000000"), hexLum("#f2f2f7")] {
        check(DS.solveInk(hue: 0.6, saturation: s, brightness: 0.5,
                          pageLuminance: page, bar: 4.5) == nil,
              "\(name) (saturation \(s)) was tinted")
    }
}
check(DS.solveInk(hue: 0.6, saturation: 0.15, brightness: 0.9,
                  pageLuminance: hexLum("#000000"), bar: 4.5) != nil,
      "saturation exactly 0.15 should tint (the bar is >=, matching washHue)")

// ===== 4. THE IDENTITY FLOORS HOLD =========================================
// Past them the result is gray-with-a-tinge, not the brand, and painting that
// is the decoration the color law forbids.
for (bname, h, s, v) in BRANDS {
    for (_, phex) in PAGES {
        guard let ink = DS.solveInk(hue: h, saturation: s, brightness: v,
                                    pageLuminance: hexLum(phex), bar: 4.5) else { continue }
        check(ink.saturation >= 0.25 - 0.001, "\(bname) desaturated past the identity floor")
        check(ink.brightness >= 0.35 - 0.001, "\(bname) darkened past the identity floor")
        check(ink.hue == h, "\(bname) had its HUE moved — only s/v may move")
    }
}

// ===== 5. THE HUE IS PRESERVED, NOT RE-PICKED ==============================
// The whole justification is identity: an ink whose hue drifts is decoration.
for target in stride(from: 0.0, through: 0.95, by: 0.05) {
    guard let ink = DS.solveInk(hue: target, saturation: 0.8, brightness: 0.8,
                                pageLuminance: hexLum("#000000"), bar: 4.5) else { continue }
    check(ink.hue == target, "hue \(target) drifted to \(ink.hue)")
}

// ===== 6. RAW washHue AS INK WOULD FAIL — the measurement that motivates ====
// Snapchat's yellow at washHue's own clamp measures ~1.1:1 on the light page.
// If this ever passes, washHue became safe as ink and this whole solve is moot.
do {
    let page = hexLum("#f2f2f7")
    let (r, g, b) = hsb(0.1647, 1.0, 0.95)   // washHue(snapchat): s>=0.65, b clamped to 0.95
    check(ratio(lum(r, g, b), page) < 4.5,
          "raw washHue snapchat now clears 4.5:1 on light — re-read the ruling")
}

// ===== 7. THE SOLVE KEEPS AS MUCH BRAND AS THE BAR ALLOWS =================
// Clearing the bar is necessary and not sufficient. A search that gives up and
// returns the identity FLOOR also clears it — and washes every deep hue to the
// same pale tint, so Wallet blue, Stripe indigo and Aerodrome blue arrive
// indistinguishable. Whenever the solve moved a channel at all, it must have
// stopped AT the boundary: one more step toward the brand has to break the bar.
// (Found by a surviving mutation — inverting the binary search still returned a
// passing ink, so sections 1–6 scored it green.)
func meets(_ h: Double, _ s: Double, _ v: Double, _ page: Double, _ bar: Double) -> Bool {
    let (r, g, b) = hsb(h, s, v)
    return ratio(lum(r, g, b), page) >= bar
}
let step = 0.05
for (pname, phex) in PAGES {
    let page = hexLum(phex)
    for (bname, h, s, v) in BRANDS {
        guard let ink = DS.solveInk(hue: h, saturation: s, brightness: v,
                                    pageLuminance: page, bar: 4.5) else { continue }
        let startSat = max(s, 0.65)
        let startBright = min(max(v, 0.60), 0.95)
        // Desaturated to clear a dark page: more saturation must break it.
        if ink.saturation < startSat - 0.001 {
            check(!meets(h, min(ink.saturation + step, startSat), ink.brightness, page, 4.5),
                  "\(bname) on \(pname): desaturated to \(String(format: "%.2f", ink.saturation)) "
                  + "when \(String(format: "%.2f", ink.saturation + step)) also clears the bar")
        }
        // Darkened to clear a light page: more brightness must break it.
        if ink.brightness < startBright - 0.001 {
            check(!meets(h, ink.saturation, min(ink.brightness + step, startBright), page, 4.5),
                  "\(bname) on \(pname): darkened to \(String(format: "%.2f", ink.brightness)) "
                  + "when \(String(format: "%.2f", ink.brightness + step)) also clears the bar")
        }
    }
}

if failures == 0 {
    print("  OK — invariant, defaults, neutrals, floors, hue, motivation, boundary")
}
exit(failures == 0 ? 0 : 1)
SWIFT

swiftc -O -o "$WORK/run" "$WORK/ink.swift" "$WORK/main.swift" 2>&1 | grep -v "^$" || true
[ -x "$WORK/run" ] || { echo "FAIL: harness did not compile"; exit 1; }
"$WORK/run" || exit 1

# --- mutations: each must FAIL, or the assertions above prove nothing -------
mutate() {
  local desc="$1" from="$2" to="$3"
  local m="$WORK/m.swift"
  sed "s|$from|$to|" "$WORK/ink.swift" > "$m"
  if cmp -s "$m" "$WORK/ink.swift"; then
    echo "  STALE MUTATION (matched nothing): $desc"; return 1
  fi
  if ! swiftc -O -o "$WORK/mrun" "$m" "$WORK/main.swift" 2>/dev/null; then
    echo "  MUTATION DID NOT COMPILE: $desc"; return 1
  fi
  if "$WORK/mrun" >/dev/null 2>&1; then
    echo "  MUTATION SURVIVED: $desc"; return 1
  fi
  return 0
}

echo "  mutations..."
bad=0
# The bar itself: a solve that stops one step short renders identically.
mutate "returns an ink one notch under the bar"          ">= bar" "> bar * 0.75" || bad=1
# The gamma linearization — the exact error that makes a ratio look right and
# measure wrong (and the reason wcagLuminance is separate from `luminance`).
mutate "wcag luminance stops linearizing sRGB"           "c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)" "c" || bad=1
# The honest-hue gate: a near-neutral mark must never be tinted.
mutate "near-neutral marks get tinted"                   "saturation >= 0.15" "saturation >= -1" || bad=1
# Both identity floors.
mutate "saturation floor removed (gray-with-a-tinge)"    "satFloor = 0.25" "satFloor = 0.0" || bad=1
mutate "brightness floor removed (crushed to near-black)" "brightFloor = 0.35" "brightFloor = 0.0" || bad=1
# The search directions.
mutate "brighten branch pinned below full brightness"    "meets(startSat, 1)" "meets(startSat, 0.5)" || bad=1
# The binary search must actually converge on a passing value.
mutate "binary search keeps the FAILING half"            "if meets(mid, 1) { pass = mid } else { fail = mid }" "if meets(mid, 1) { fail = mid } else { pass = mid }" || bad=1
# Hue must never move — the identity claim rests on it.
mutate "hue re-picked instead of preserved"              "return (hue, startSat, 1)" "return (hue + 0.1, startSat, 1)" || bad=1

[ $bad -eq 0 ] || { echo "legible-ink self-test: MUTATION CHECK FAILED"; exit 1; }
echo "legible-ink self-test: OK"
