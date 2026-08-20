#!/bin/zsh
# Casberi keyed-agent self-test — the pure logic behind what a key may REACH
# and what it may COST (2026-08-20):
#
#   Casberi/Casberi/Model/AgentWebFetch.swift   — which saved links may be
#       shown to a provider that can read a page (compiled WHOLE and
#       unmodified; the file is Foundation-only by design)
#   Casberi/Casberi/Model/AgentBudget.swift     — the month arithmetic behind
#       the ceiling that pauses the librarian (extracted by name)
#
# WHY A HARNESS. No key for any provider is stored on this build host, and
# there is no egress to api.anthropic.com from it, so `-byokProbe` cannot run
# and neither can anything that would notice these being wrong. Both failure
# modes are SILENT and neither shows up in a build, a screen sweep or a
# static audit:
#
#   • a link policy that is too LOOSE hands somebody else's fetcher a
#     `file://` path, a private hostname off a self-hosted bridge, or a signed
#     CDN URL with a token in its query — a leak, rendered as a perfectly
#     ordinary answer;
#   • a link policy that is too TIGHT silently shows the model nothing, and a
#     page it was never offered is indistinguishable from a page it chose not
#     to read;
#   • a month that never re-baselines makes a lifetime total read as this
#     month's spend, so a ceiling fires immediately and organizing stops
#     forever, with the settings row confidently reporting the wrong number.
#
# Pure, local, deterministic — no network, no key, no simulator. Exit non-zero
# on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

FETCH="Casberi/Casberi/Model/AgentWebFetch.swift"
BUDGET="Casberi/Casberi/Model/AgentBudget.swift"
ANSWER="Casberi/Casberi/Model/AgentAnswer.swift"
TOOLS="Casberi/Casberi/Model/AgentCorpusTools.swift"
LIBRARIAN="Casberi/Casberi/Model/AgentLibrarian.swift"
MODELS="Casberi/Casberi/Model/AgentModels.swift"
SPEND="Casberi/Casberi/Model/AgentSpend.swift"
for f in "$FETCH" "$BUDGET" "$ANSWER" "$TOOLS" "$LIBRARIAN" "$MODELS" "$SPEND"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

if [[ "${1:-}" == "--self-test" ]]; then
  # This harness's own demonstration that it can fail lives in the mutation
  # block at the bottom, which runs on every invocation rather than behind a
  # flag — a check that cannot fail proves nothing, and one that only tries
  # when asked proves nothing on the runs that matter.
  echo "agent-keyed-selftest: assertions + mutations run unconditionally below"
fi

TMP=$(mktemp -d /tmp/agent-keyed-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- drift guards -----------------------------------------------------------
# Wiring the compiled functions cannot prove. A perfect link policy is worth
# nothing if no tool result ever prints a link, and a perfect month is worth
# nothing if `canRun` stops consulting it.
#
# EVERY NEGATIVE GUARD READS A COMMENT-STRIPPED COPY. All three files below
# document these rules by quoting the very thing they must no longer do — the
# stream reader's comment names the old `server_tool_use` test verbatim — so a
# guard grepping raw source scores the prose explaining the fix as the bug.
# (The Obsidian/Cursor lesson; this is at least its sixth instance.)
strip_comments() {
  python3 - "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
src = re.sub(r'^[ \t]*//.*$', '', src, flags=re.M)
src = re.sub(r'(?<![:/])//.*$', '', src, flags=re.M)
sys.stdout.write(src)
PY
}
strip_comments "$ANSWER"    > "$TMP/answer.nc.swift"
strip_comments "$TOOLS"     > "$TMP/tools.nc.swift"
strip_comments "$LIBRARIAN" > "$TMP/librarian.nc.swift"

# 1. Prompt caching actually reaches the wire, on the one message that matters.
grep -q 'cache_control' "$TMP/answer.nc.swift" \
  || { echo "✗ no cache_control anywhere — every round re-pays for the whole prompt"; exit 1; }
grep -q '"role": "user", "content": cached(content)' "$TMP/answer.nc.swift" \
  || { echo "✗ the current question is no longer a cache breakpoint — the tool loop's"; \
       echo "  candidates, system prompt and screenshots are re-sent whole every round."; exit 1; }
grep -qE 'cacheRead: usage\??\["cache_read_input_tokens"\]' "$TMP/answer.nc.swift" \
  || { echo "✗ the cache hit is no longer read off Anthropic's usage — the saving is unmeasurable"; exit 1; }
grep -q 'cachedInputTokens' "$SPEND" \
  || { echo "✗ AgentSpend no longer keeps the cached-token count — the receipt can't show it"; exit 1; }

# 2. THE FAKE-STATUS GUARD, and the reason this harness earns its place.
# `searchedWeb` is a claim about where an answer came from, printed on the one
# line whose entire job is provenance. The stream reader used to treat ANY
# `server_tool_use` block as a web SEARCH, which was correct only while search
# was the sole server tool. Web fetch made it wrong: a page read from the
# person's own saved links would have claimed the agent went out and searched
# the open web. The block's own `name` is what keeps the two apart.
grep -q 'case "web_search": return .searched' "$TMP/answer.nc.swift" \
  || { echo "✗ the server-tool branch no longer identifies web_search by NAME —"; \
       echo "  a page read will claim the agent searched the web (§83 fake status)."; exit 1; }
grep -qE 'blockType == "server_tool_use" *\|\| *blockType == "web_search_tool_result"' \
     "$TMP/answer.nc.swift" \
  && { echo "✗ the name-blind server-tool test is back — every web_fetch will"; \
       echo "  light the 'searched the web' badge."; exit 1; }
grep -q 'blockType == "web_fetch_tool_result"' "$TMP/answer.nc.swift" \
  || { echo "✗ a finished page read is no longer observed — pagesRead can only ever be 0"; exit 1; }
grep -q 'web_fetch_result' "$TMP/answer.nc.swift" \
  || { echo "✗ a page read is no longer confirmed on its RESULT shape — a REFUSED"; \
       echo "  fetch (blocked domain, URL never in context) would count as a page read."; exit 1; }

# 3. The URLs exist at all. Web fetch can only reach a URL already in the
# transcript, and the tool results are the ONLY place one is ever printed — so
# if this stops being passed, the tool is declared with nothing in reach and
# every attempt is a guaranteed `url_not_in_prior_context`.
grep -q 'includeLinks: fetchOn' "$TMP/answer.nc.swift" \
  || { echo "✗ tool results no longer carry links — web_fetch has nothing it may fetch"; exit 1; }
grep -q 'fetchableLink(snap)' "$TMP/tools.nc.swift" \
  || { echo "✗ AgentCorpusTools no longer gates a printed link through the policy"; exit 1; }
grep -q 'SecretScan.redacted(url) == url' "$TMP/tools.nc.swift" \
  || { echo "✗ a link whose text redacts is no longer dropped — the model would be handed"; \
       echo "  a masked URL and spend a use fetching a page that cannot exist."; exit 1; }
# The fetch tool must stay behind the corpus tools. Offered on the single-shot
# path it declares a tool with an empty reachable set.
grep -q 'let fetchOn = toolsOn && provider.fetchesLinks' "$TMP/answer.nc.swift" \
  || { echo "✗ page reading is no longer gated on the corpus tools being on"; exit 1; }

# 4. The librarian's own model, and the ceiling that stops it.
grep -q 'AgentBudget.pausesLibrarian' "$TMP/librarian.nc.swift" \
  || { echo "✗ AgentLibrarian.canRun no longer consults the monthly ceiling"; exit 1; }
[[ $(grep -c 'task: .librarian' "$TMP/librarian.nc.swift") -ge 2 ]] \
  || { echo "✗ a librarian call is back on the ASK model — naming screenshots is"; \
       echo "  being billed at the model somebody chose for hard questions."; exit 1; }
# An ASK must never be capped: the person is standing there and chose to spend.
grep -q 'AgentBudget' "$TMP/answer.nc.swift" \
  && { echo "✗ the budget reached AgentAnswer — a ceiling that blocks an ask is the"; \
       echo "  dead control the honesty rule bans. It governs the librarian alone."; exit 1; }
# A librarian choice must fall back to the ask choice, never straight to the
# pin, or a model somebody deliberately picked is silently replaced.
grep -q 'return task == .ask ? nil : chosen(provider, task: .ask)' "$MODELS" \
  || { echo "✗ the librarian model no longer falls back to the ask model"; exit 1; }

# --- extract the shipped budget arithmetic ---------------------------------
python3 - "$BUDGET" "$TMP/extracted.swift" <<'PY'
import sys
budget, out = sys.argv[1:3]

def grab(path, signature):
    """The whole declaration whose line contains `signature`, brace-matched
    from the shipped source. Never a copy — if the extraction stops matching,
    the compile fails loudly rather than asserting nothing."""
    src = open(path).read()
    i = src.find(signature)
    if i < 0:
        sys.exit(f"EXTRACT-FAIL: {signature!r} not found in {path}")
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
    "enum AgentBudget {",
    grab(budget, "static func monthKey"),
    grab(budget, "struct Baseline"),
    grab(budget, "static func rebased"),
    grab(budget, "static func spent"),
    grab(budget, "static func exhausted"),
    "}\n",
]
open(out, "w").write("\n".join(pieces))
PY

# --- the driver -------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}

// ===========================================================================
print("AgentWebFetch.fetchable — an ordinary permalink passes")
check("https article",
      AgentWebFetch.fetchable("https://example.com/2026/the-piece") == "https://example.com/2026/the-piece")
check("http passes too (plenty of saved links are old)",
      AgentWebFetch.fetchable("http://example.com/a") == "http://example.com/a")
check("a query that is a real locator survives",
      AgentWebFetch.fetchable("https://example.com/p?id=42&page=3") != nil)
check("surrounding whitespace is trimmed, not refused",
      AgentWebFetch.fetchable("  https://example.com/a  ") == "https://example.com/a")
// The ORIGINAL string comes back, never a re-serialized one: percent-encoding
// is not canonical, and the model hands this exact string back for the fetch.
let encoded = "https://example.com/a%20b?q=%C3%A9"
check("the exact bytes are returned, never a rebuilt URL",
      AgentWebFetch.fetchable(encoded) == encoded)

print("…and every local door is refused")
// Each of these is a real shape in this corpus. A remote fetcher can do
// nothing with one but be told it exists.
for scheme in ["casberi://thing/1234", "obsidian://open?vault=Notes&file=A",
               "file:///Users/me/Documents/a.pdf", "photos-redirect://",
               "shareddocuments:///private/var/mobile", "data:text/html,hi",
               "wc:topic@2", "mailto:someone@example.com"] {
    check("refused: \(scheme)", AgentWebFetch.fetchable(scheme) == nil)
}
// THE FIXTURES THAT MAKE THE SCHEME CHECK LOAD-BEARING, and the harness's own
// first mutation finding. Every case above is ALSO hostless or dotless, so the
// host guard one line down refused all eight — deleting the scheme test
// entirely left the suite green, proving the right result for the wrong
// reason. These two have a perfectly ordinary dotted host and are refused on
// their scheme alone.
check("a dotted-host ftp URL is refused on its scheme",
      AgentWebFetch.fetchable("ftp://files.example.com/report.pdf") == nil)
check("a dotted-host javascript URL is refused on its scheme",
      AgentWebFetch.fetchable("javascript://example.com/%0aalert(1)") == nil)

print("…and a private host is refused (it would leak a network shape for nothing)")
for host in ["http://localhost:8000/notes", "http://127.0.0.1/x",
             "http://192.168.1.14/posthog", "http://10.0.0.5/a",
             "http://169.254.1.1/a", "https://nas.local/share",
             "https://posthog.internal/api", "http://172.16.0.9/a",
             "http://172.31.255.4/a"] {
    check("refused: \(host)", AgentWebFetch.fetchable(host) == nil)
}
// The arithmetic half of the 172 range, in BOTH directions — a prefix test
// would wrongly refuse these two, which are ordinary public addresses.
check("172.15 is public and allowed",  AgentWebFetch.fetchable("http://172.15.0.1/a") != nil)
check("172.32 is public and allowed",  AgentWebFetch.fetchable("http://172.32.0.1/a") != nil)

print("…and a credential is never handed over")
for signed in ["https://cdn.example.com/i.jpg?token=abc123",
               "https://cdn.example.com/i.jpg?Signature=xyz",
               "https://cdn.example.com/i.jpg?x=1&sig=deadbeef",
               "https://api.example.com/v1/a?api_key=sk-live-1",
               "https://example.com/a?access_token=zzz",
               "https://example.com/a?session=abc"] {
    check("refused: \(signed)", AgentWebFetch.fetchable(signed) == nil)
}
check("a credential in the authority is refused",
      AgentWebFetch.fetchable("https://user:pw@example.com/a") == nil)
// Case-insensitive, or the check is a formality: `?TOKEN=` is the same leak.
check("the query-key test ignores case",
      AgentWebFetch.fetchable("https://example.com/a?TOKEN=abc") == nil)

print("…and a URL that could only ever fail is never printed")
// Anthropic answers `url_too_long` above 250 characters. Showing the model one
// costs input tokens to buy a guaranteed error.
let long = "https://example.com/" + String(repeating: "a", count: 250)
check("the fixture really is over the cap (or this proves nothing)", long.count > 250)
check("an over-long URL is refused", AgentWebFetch.fetchable(long) == nil)
check("nil in, nil out", AgentWebFetch.fetchable(nil) == nil)
check("empty in, nil out", AgentWebFetch.fetchable("   ") == nil)
check("two URLs in one string is not one URL",
      AgentWebFetch.fetchable("https://a.example.com/x https://b.example.com/y") == nil)
check("a bare hostless string is refused", AgentWebFetch.fetchable("https:///path") == nil)
check("a schemeless string is refused", AgentWebFetch.fetchable("example.com/a") == nil)

print("the billing bounds are bounds")
// These are BILLING decisions, not capability ones — see the file's own
// arithmetic. A research-paper PDF is ~125,000 tokens; unbounded, one saved
// link turns a question into a dollar. Pinned so a later raise is a deliberate
// edit to a test rather than a number nobody re-reads.
check("at most 2 pages per answer", AgentWebFetch.maxUses <= 2)
check("at most 12k tokens per page", AgentWebFetch.maxContentTokens <= 12_000)
check("the declaration carries BOTH bounds",
      (AgentWebFetch.anthropicDeclaration()["max_uses"] as? Int) == AgentWebFetch.maxUses
      && (AgentWebFetch.anthropicDeclaration()["max_content_tokens"] as? Int) == AgentWebFetch.maxContentTokens)
check("the declaration names the tool version that supports filtering",
      (AgentWebFetch.anthropicDeclaration()["type"] as? String)?.hasPrefix("web_fetch_2026") == true)
check("the declaration is named web_fetch",
      (AgentWebFetch.anthropicDeclaration()["name"] as? String) == "web_fetch")
// Citations stay OFF: this app paints its own grounding rows, and a citation
// arrives as prose the stream reader concatenates — tokens spent to render
// identically.
check("citations are not requested",
      AgentWebFetch.anthropicDeclaration()["citations"] == nil)

// ===========================================================================
print("")
print("AgentBudget.monthKey — the person's own calendar")
var utc = Calendar(identifier: .gregorian)
utc.timeZone = TimeZone(identifier: "UTC")!
func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
}
check("zero-padded so a month is one comparable token",
      AgentBudget.monthKey(day(2026, 8, 20), calendar: utc) == "2026-08")
check("December is not truncated",
      AgentBudget.monthKey(day(2026, 12, 1), calendar: utc) == "2026-12")
check("two months in one year differ",
      AgentBudget.monthKey(day(2026, 8, 1), calendar: utc)
        != AgentBudget.monthKey(day(2026, 9, 1), calendar: utc))
check("the same month a year apart differs",
      AgentBudget.monthKey(day(2026, 8, 1), calendar: utc)
        != AgentBudget.monthKey(day(2027, 8, 1), calendar: utc))

print("rebased — the three cases that are NOT the same case")
// 1. First sight. The key's lifetime total is whatever it is; this month's
// spend starts at zero, which understates rather than inventing.
check("first sight baselines at the reading",
      AgentBudget.rebased(nil, reported: 41.20, month: "2026-08")
        == AgentBudget.Baseline(month: "2026-08", usd: 41.20))
// 2. Same month, higher reading: hold the line, or the month resets on every
// foreground and a ceiling can never be reached.
let august = AgentBudget.Baseline(month: "2026-08", usd: 41.20)
check("same month holds its baseline",
      AgentBudget.rebased(august, reported: 43.80, month: "2026-08") == august)
// 3. New month: re-baseline, or last month's spend is charged to this one
// forever and the cap fires on day one.
check("a new month takes a fresh baseline",
      AgentBudget.rebased(august, reported: 43.80, month: "2026-09")
        == AgentBudget.Baseline(month: "2026-09", usd: 43.80))
// 4. A reading BELOW the baseline. A lifetime total cannot go backwards, so
// the key was replaced or the provider reset it; continuing to subtract the
// old baseline reports a negative spend forever.
check("a backwards reading re-baselines",
      AgentBudget.rebased(august, reported: 2.00, month: "2026-08")
        == AgentBudget.Baseline(month: "2026-08", usd: 2.00))
check("an equal reading is NOT a reset",
      AgentBudget.rebased(august, reported: 41.20, month: "2026-08") == august)

print("spent — a delta, and nil when it isn't knowable")
check("the delta is this month's spend",
      AgentBudget.spent(august, reported: 44.20, month: "2026-08") == 3.00)
check("nothing read yet → unknown, never zero",
      AgentBudget.spent(august, reported: nil, month: "2026-08") == nil)
check("no baseline → unknown",
      AgentBudget.spent(nil, reported: 44.20, month: "2026-08") == nil)
// A stale baseline is not a small error, it is last month's number. Unknown is
// the honest answer until `observe` re-baselines.
check("a baseline from another month → unknown",
      AgentBudget.spent(august, reported: 44.20, month: "2026-09") == nil)
check("never negative even if a caller skipped rebased",
      AgentBudget.spent(august, reported: 2.00, month: "2026-08") == 0)

print("exhausted — not knowing is not a reason to stop")
check("over the cap pauses",      AgentBudget.exhausted(spent: 5.10, cap: 5.00) == true)
check("exactly at the cap pauses", AgentBudget.exhausted(spent: 5.00, cap: 5.00) == true)
check("under the cap runs",       AgentBudget.exhausted(spent: 4.99, cap: 5.00) == false)
// The two nils are the honesty rule: a bad network must not stop the app, and
// no cap set must not behave like a cap of zero.
check("an unknown spend never pauses", AgentBudget.exhausted(spent: nil, cap: 5.00) == false)
check("no cap never pauses",           AgentBudget.exhausted(spent: 900, cap: nil) == false)
check("a zero cap is treated as no cap, not as stop-everything",
      AgentBudget.exhausted(spent: 0.01, cap: 0) == false)

print("")
if failures == 0 {
    print("✓ agent keyed self-test: all assertions passed")
} else {
    print("✗ agent keyed self-test: \(failures) assertion(s) failed")
    exit(1)
}
SWIFT

swiftc -O -o "$TMP/run" "$FETCH" "$TMP/extracted.swift" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ the keyed-agent logic did not compile"; exit 1; }
"$TMP/run"

# --- mutations (each must be caught) ---------------------------------------
echo
echo "mutations (each must be caught)"

WORK="$TMP/work"
# `file` is which shipped source to corrupt: the fetch policy is compiled
# whole, the budget is extracted, so the two rebuild differently.
mutate() {
  local name="$1" which="$2" from="$3" to="$4"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$FETCH" "$WORK/AgentWebFetch.swift"
  cp "$BUDGET" "$WORK/AgentBudget.swift"
  local target="$WORK/AgentWebFetch.swift"
  [[ "$which" == "budget" ]] && target="$WORK/AgentBudget.swift"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$target" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]]; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  # Re-extract from the mutated budget so a budget mutation really reaches the
  # compiled code rather than the pristine copy.
  if ! python3 - "$WORK/AgentBudget.swift" "$WORK/extracted.swift" <<'PY' 2>/dev/null
import sys
budget, out = sys.argv[1:3]
def grab(path, signature):
    src = open(path).read()
    i = src.find(signature)
    if i < 0: sys.exit(1)
    start = src.rfind("\n", 0, i) + 1
    j = src.index("{", i); depth, k = 0, j
    while k < len(src):
        if src[k] == "{": depth += 1
        elif src[k] == "}":
            depth -= 1
            if depth == 0: break
        k += 1
    return src[start:k+1].replace("private ", "")
open(out, "w").write("\n".join([
    "import Foundation\n", "enum AgentBudget {",
    grab(budget, "static func monthKey"), grab(budget, "struct Baseline"),
    grab(budget, "static func rebased"), grab(budget, "static func spent"),
    grab(budget, "static func exhausted"), "}\n"]))
PY
  then
    echo "  ✓ $name (rejected at extraction)"; return
  fi
  if ! swiftc -O -o "$WORK/mut" "$WORK/AgentWebFetch.swift" "$WORK/extracted.swift" \
        "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$WORK/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# 1. THE LEAK. Drop the scheme gate and every local door in the corpus —
# `file://`, `obsidian://`, `casberi://` — is handed to somebody else's
# fetcher, which is the worst outcome this file exists to prevent.
mutate "scheme gate removed → local doors leak" fetch \
  'scheme == "https" || scheme == "http" else { return nil }' \
  'scheme == "https" || scheme == "http" || true else { return nil }'

# 2. Private hosts. A self-hosted PostHog or a followed LAN feed would put a
# private hostname into a provider's context window to buy nothing at all.
mutate "private-host gate removed" fetch \
  'guard !isPrivateHost(host) else { return nil }' \
  'guard !isPrivateHost(host) || true else { return nil }'

# 3. The 172 range as a PREFIX rather than arithmetic — the plausible-looking
# simplification that wrongly refuses 172.15 and 172.32, two ordinary public
# addresses. Caught by the two assertions that allow them.
mutate "172/12 range widened to all of 172" fetch \
  'if parts.count > 1, let second = Int(parts[1]), (16...31).contains(second) {' \
  'if parts.count > 1, let second = Int(parts[1]), (0...255).contains(second) {'

# 4. Signed URLs. Instagram's og:image and Snapchat's memory downloads are
# both signed and both in this corpus.
mutate "credential query keys no longer refused" fetch \
  'if credentialQueryKeys.contains(item.name.lowercased()) { return nil }' \
  'if credentialQueryKeys.contains(item.name) && false { return nil }'

# 5. Case sensitivity on that same check — `?TOKEN=` is the same leak.
mutate "credential query keys become case-sensitive" fetch \
  'credentialQueryKeys.contains(item.name.lowercased())' \
  'credentialQueryKeys.contains(item.name)'

# 6. userinfo in the authority.
mutate "user:password in the URL no longer refused" fetch \
  'guard components.user == nil, components.password == nil else { return nil }' \
  'guard true else { return nil }'

# 7. The length cap. Over 250 the fetch is a guaranteed `url_too_long`, so
# printing one spends input tokens to buy an error.
mutate "URL length cap removed" fetch \
  'guard !trimmed.isEmpty, trimmed.count <= urlLengthCap else { return nil }' \
  'guard !trimmed.isEmpty else { return nil }'

# 8. THE BILLING BOUND. Raising this is exactly the edit that turns one saved
# PDF into a dollar, and it renders identically.
mutate "page budget raised past its stated bound" fetch \
  'static let maxContentTokens = 12_000' \
  'static let maxContentTokens = 100_000'

# 9. THE MONTH THAT NEVER ROLLS. Without the month test a baseline taken in
# January is subtracted forever: the cap fires on day one of every later month
# and organizing stops for good, with the settings row confidently wrong.
mutate "rebased ignores the month → the cap fires forever" budget \
  'guard let current, current.month == month, current.usd <= reported else {' \
  'guard let current, current.usd <= reported else {'

# 10. The backwards reading. A replaced key reports a lower lifetime total, and
# without this the delta goes negative for the rest of the month.
mutate "rebased ignores a backwards reading" budget \
  'guard let current, current.month == month, current.usd <= reported else {' \
  'guard let current, current.month == month else {'

# 11. A stale baseline silently answering. Last month's number rendered as this
# month's is the single most believable wrong figure on that screen.
mutate "spent answers from another month's baseline" budget \
  'guard let reported, let baseline, baseline.month == month else { return nil }' \
  'guard let reported, let baseline else { return nil }'

# 12. NOT KNOWING TREATED AS STOP. A bad network would pause organizing, which
# is the failure a ceiling must never cause.
# Spelled to flip only the UNKNOWN case and leave the binding intact — the
# first cut deleted the `let spent` binding too, so it was rejected at compile,
# which proves the code doesn't build rather than that anything tests this.
mutate "an unknown spend pauses the librarian" budget \
  'guard let cap, cap > 0, let spent else { return false }' \
  'guard let cap, cap > 0, let spent else { return true }'

# 13. The boundary itself.
mutate "exhausted becomes strictly-greater at the cap" budget \
  'return spent >= cap' \
  'return spent > cap'

echo
echo "✓ agent keyed self-test: assertions and mutations all pass"
