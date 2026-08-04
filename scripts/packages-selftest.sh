#!/bin/zsh
# Casberi npm/PyPI self-test — verifies the SHIPPED pure logic behind the
# package-registry bridges (2026-08-04):
#
#   Casberi/Casberi/Model/PackageWatchBridge.swift
#     — PackageRegistry.normalize   (what a person actually pastes)
#     — PackageRegistry.pageURL     (the permalink each row opens)
#     — PackageShape.matches        (npm's search is a SEARCH, not a lookup)
#     — PackageShape refs/titles    (two registries, one package name)
#     — PackageFetch.escapePackage  (a scoped npm name keeps its slash)
#
# Unlike the other three bridges landing this session, these two ARE measured
# against their live registries (the endpoint sizes and shapes in
# `PackageWatchBridge.swift`'s file note were run by hand on 2026-08-04). This
# harness covers the half a live measurement can't: the decisions.
#
# Every failure here is a SILENT WRONG ANSWER:
#
#   • `matches` weakened to trust POSITION dates `react`'s release from
#     `react-is`'s — a wrong number that renders perfectly. npm ranks
#     `react-is`, `react-smooth` and `react-router` immediately behind the
#     exact match (measured), and supports no exact-name qualifier at all;
#   • a scoped npm name percent-encoding its slash 404s at the registry, so
#     `@vercel/og` silently never resolves;
#   • the two registries sharing a ref namespace collides `requests` on PyPI
#     with `requests` on npm — both exist, and so do `click` and `attrs`.
#
# `PackageWatchBridge.swift` cannot compile as shipped (it builds `Thing`, uses
# SwiftData and Observation, and reads UserDefaults), so the pure pieces are
# EXTRACTED from the shipped source by name — never copied here.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

PKG="Casberi/Casberi/Model/PackageWatchBridge.swift"
REFRESH="Casberi/Casberi/Model/BridgeRefresh.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
CATALOG="Casberi/Casberi/Model/BridgeCatalog.swift"
for f in "$PKG" "$REFRESH" "$REACH" "$CATALOG"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- drift guards -----------------------------------------------------------
#
# An ABSENCE check must read CODE, not prose. This file's own doc comment names
# both forbidden endpoints — `vnd.npm.install-v1` and `api.npmjs.org` — because
# recording why they were rejected is the whole point of the measurement note,
# and the first cut of this harness failed against its own documentation. Same
# class as the design-motion audit's "a comment naming the modifiers doesn't
# clear the struct", in the opposite direction.
code_of() {  # strip // line comments and /* */ blocks, print what's left
  python3 - "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
src = re.sub(r'^\s*//.*$', '', src, flags=re.M)
src = re.sub(r'(?<![:"\w])//.*$', '', src, flags=re.M)
print(src)
PY
}
absent_in_code() {  # absent_in_code <file> <needle> <message>
  code_of "$1" | grep -q -- "$2" \
    && { echo "✗ $3"; exit 1; }
  return 0
}

# Keyless watch lists don't ride `TokenBridge.allCases`, so without this line
# nothing ever syncs on a foreground and the seats look connected but dead.
grep -q 'PackageIngest.refresh(registry, context: context)' "$REFRESH" \
  || { echo "✗ the foreground sweep no longer drives the package registries — nothing would sync"; exit 1; }
for host in registry.npmjs.org pypi.org; do
  grep -q "$host" "$REACH" \
    || { echo "✗ $host is not in the reach registry — the privacy screen is wrong"; exit 1; }
done
# THE COST GUARD. The obvious npm endpoint (`registry.npmjs.org/<pkg>`) is
# 6.8 MB for `react` — measured — and it is the first thing anyone will reach
# for when "simplifying" the two-request design away. The cheap endpoints are
# `/latest` (2 KB) and the search index (1 KB).
grep -q 'registry.npmjs.org/\\(escaped)/latest' "$PKG" \
  || { echo "✗ the cheap npm endpoint is gone — the full document is 6.8 MB for react"; exit 1; }
absent_in_code "$PKG" 'vnd.npm.install-v1' \
  "the abbreviated npm document appeared — it is 2.8 MB AND carries no dates"
# The date lookup must fire only when something is about to land, or the
# steady-state cost doubles for every watched package forever.
grep -q 'if published == nil, registry == .npm' "$PKG" \
  || { echo "✗ npm's date lookup is no longer gated on a pending landing — cost doubles per package"; exit 1; }
# PyPI's RSS feed is the whole read (10 KB vs the JSON endpoint's 190 KB).
grep -q 'pypi.org/rss/project/\\(escaped)/releases.xml' "$PKG" \
  || { echo "✗ PyPI's release feed is gone — its JSON endpoint is 190 KB per package per pass"; exit 1; }
# Neither registry may be asked for downloads. `api.npmjs.org` is the counts
# host and this app must never touch it — a tally is not news, and the catalog
# copy says so in those words.
absent_in_code "$PKG" 'api\.npmjs\.org' \
  "the npm DOWNLOADS host appeared — the catalog promises counts never land"
# Both seats must exist in the catalog, or a connected bridge has no product
# page and `catalog-sync` has nothing to check against the website.
for name in '"npm"' '"PyPI"'; do
  grep -q "Offer(name: $name," "$CATALOG" \
    || { echo "✗ $name has no catalog offer"; exit 1; }
done
# The silent-seed rule: a first sight with no knowable date must land NOTHING
# rather than a row stamped `.now`, which would claim a 2019 release happened
# today.
grep -q 'if firstSight, published == nil' "$PKG" \
  || { echo "✗ the silent-seed branch is gone — first sight could stamp an old release as today"; exit 1; }

TMP=$(mktemp -d /tmp/packages-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

python3 - "$PKG" "$TMP/extracted.swift" <<'PY'
import sys
pkg, out = sys.argv[1:3]

def grab(path, signature):
    src = open(path).read()
    i = src.find(signature)
    if i < 0:
        sys.exit(f"✗ extraction failed: {signature!r} not found in {path}")
    start = src.rfind("\n", 0, i) + 1
    j = src.index("{", i)
    depth, k = 0, j
    while k < len(src):
        if src[k] == "{": depth += 1
        elif src[k] == "}":
            depth -= 1
            if depth == 0: break
        k += 1
    return src[start:k+1].replace("private ", "")

pieces = [
    "import Foundation\n",
    # The registry enum whole — normalize, pageURL, bridgeID, displayName.
    grab(pkg, "enum PackageRegistry"),
    grab(pkg, "enum PackageShape"),
    "",
    "enum PackageFetch {",
    grab(pkg, "static func escapePackage"),
    grab(pkg, "static func nonEmpty"),
    "}\n",
]
open(out, "w").write("\n".join(pieces))
PY

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}

print("matches — npm's search is a SEARCH, not a lookup")
// THE assertion this whole guard exists for. Measured 2026-08-04:
// `text=react&size=5` returns react, react-is, react-smooth, react-router,
// react-dom — and `name:` qualifiers return ZERO results, so there is no exact
// lookup to fall back on. Trusting position dates `react`'s release from
// `react-is`'s: a wrong number that renders perfectly.
check("the exact name matches",     PackageShape.matches(asked: "react", answered: "react"))
check("react-is does NOT match",    PackageShape.matches(asked: "react", answered: "react-is") == false)
check("react-dom does NOT match",   PackageShape.matches(asked: "react", answered: "react-dom") == false)
check("react-router does NOT match", PackageShape.matches(asked: "react", answered: "react-router") == false)
// A prefix/contains implementation passes the three above only if written
// carefully; this is the one that kills it outright.
check("a SUPERSTRING does not match", PackageShape.matches(asked: "react", answered: "preact") == false)
check("nil does not match",         PackageShape.matches(asked: "react", answered: nil) == false)
// npm lowercases new names but old scoped ones can carry mixed case.
check("case is folded", PackageShape.matches(asked: "@Vercel/OG", answered: "@vercel/og"))

print("normalize — what a person actually pastes")
check("a bare npm name",  PackageRegistry.npm.normalize("react") == "react")
check("npm folds case",   PackageRegistry.npm.normalize("React") == "react")
check("a scoped name keeps BOTH components",
      PackageRegistry.npm.normalize("@vercel/og") == "@vercel/og")
check("a pasted npm page",
      PackageRegistry.npm.normalize("https://www.npmjs.com/package/react") == "react")
check("a pasted SCOPED npm page",
      PackageRegistry.npm.normalize("https://www.npmjs.com/package/@vercel/og") == "@vercel/og")
check("a pasted PyPI page",
      PackageRegistry.pypi.normalize("https://pypi.org/project/requests/") == "requests")
// PyPI names are case-insensitive by PEP 503 but the site accepts any
// spelling; folding case here would make the row's title disagree with what
// was typed, for no gain.
check("PyPI keeps the spelling you typed",
      PackageRegistry.pypi.normalize("Flask-SQLAlchemy") == "Flask-SQLAlchemy")
check("a trailing version path is dropped",
      PackageRegistry.pypi.normalize("https://pypi.org/project/requests/2.34.2/") == "requests")
check("a query string is dropped",
      PackageRegistry.npm.normalize("react?activeTab=versions") == "react")
check("padding is trimmed", PackageRegistry.npm.normalize("  react  ") == "react")
check("empty stays empty",  PackageRegistry.npm.normalize("   ") == "")

print("pageURL — where a row opens")
check("an npm page",  PackageRegistry.npm.pageURL("react") == "https://www.npmjs.com/package/react")
check("a PyPI page",  PackageRegistry.pypi.pageURL("requests") == "https://pypi.org/project/requests/")

print("refs — two registries, and packages that exist on both")
// `requests`, `click` and `attrs` all exist on npm AND PyPI. A shared ref
// namespace would dedupe one against the other, so whichever synced second
// would land nothing, forever.
check("the same name on both registries does NOT collide",
      PackageShape.releaseRef(.npm, name: "requests", version: "1.0.0")
      != PackageShape.releaseRef(.pypi, name: "requests", version: "1.0.0"))
check("a release ref carries the version",
      PackageShape.releaseRef(.npm, name: "react", version: "19.2.8") == "npm:release:react:19.2.8")
// Two versions must be two things, or only the first release ever lands.
check("two versions are DIFFERENT refs",
      PackageShape.releaseRef(.npm, name: "react", version: "19.2.9")
      != PackageShape.releaseRef(.npm, name: "react", version: "19.2.8"))
check("a deprecation ref is one per package, forever",
      PackageShape.deprecationRef(.npm, name: "request") == "npm:deprecated:request")
// A deprecation must never dedupe against a release of the same package.
check("a deprecation never collides with a release",
      PackageShape.deprecationRef(.npm, name: "request")
      != PackageShape.releaseRef(.npm, name: "request", version: "2.88.2"))
// The ref is lowercased so a re-typed name in different case can't re-land
// every version already in the corpus.
check("refs fold case", PackageShape.releaseRef(.pypi, name: "Flask", version: "3.0.0")
      == "pypi:release:flask:3.0.0")

print("titles — the version trails, a deprecation leads")
// Both a package name and a semver are short, so the 80-char clamp isn't in
// play and "react 19.2.8" is how a person says it.
check("a release", PackageShape.releaseTitle(name: "react", version: "19.2.8") == "react 19.2.8")
check("a scoped release",
      PackageShape.releaseTitle(name: "@vercel/og", version: "0.8.1") == "@vercel/og 0.8.1")
// A deprecation is an OUTCOME, so it leads — the one place these two bridges
// follow the rest of the catalog's clamp rule.
check("a deprecation leads", PackageShape.deprecationTitle(name: "request") == "Deprecated · request")

print("escapePackage — a scoped name keeps its slash")
// THE npm quirk. Percent-encoding the separator into %2F is a 404 at the
// registry, so `@vercel/og` would silently never resolve — the package would
// sit in the watch list looking watched and never land anything.
check("a scoped name keeps its slash", PackageFetch.escapePackage("@vercel/og") == "@vercel/og")
check("a plain name is unchanged",     PackageFetch.escapePackage("react") == "react")
check("empty → nil",                   PackageFetch.escapePackage("") == nil)
// Whatever the person typed goes into a URL path, so a space must be escaped
// rather than building a malformed request.
check("a space is escaped",            PackageFetch.escapePackage("my package")?.contains("%20") == true)

print("bridgeID — the seat id the router and the store agree on")
check("npm",  PackageRegistry.npm.bridgeID == "npm")
check("pypi", PackageRegistry.pypi.bridgeID == "pypi")
check("npm's display name",  PackageRegistry.npm.displayName == "npm")
check("PyPI's display name", PackageRegistry.pypi.displayName == "PyPI")

print("")
if failures == 0 {
    print("✓ packages self-test: all assertions passed")
} else {
    print("✗ packages self-test: \(failures) assertion(s) failed")
    exit(1)
}
SWIFT

swiftc -O -o "$TMP/run" "$TMP/extracted.swift" "$TMP/main.swift" 2>&1 \
  | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ the extracted package logic did not compile"; exit 1; }
"$TMP/run"
