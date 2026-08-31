#!/bin/zsh
# Casberi AWS self-test — verifies the SHIPPED pure logic behind the AWS
# bridge (2026-08-30):
#
#   Casberi/Casberi/Model/AWSBridge.swift
#     — AWSSigV4     (Signature Version 4 signing, CryptoKit + Foundation)
#     — AWSCost      (the median-vs-mean anomaly rule)
#     — AWSAction    (the read-only allowlist)
#   Casberi/Casberi/Model/AWSRoom.swift
#     — the room head's ranking/headline/staleness judgement
#
# WHY A HARNESS. Two reasons.
#
#   1. SigV4 is the single most consequential piece of arithmetic in this
#      bridge: a wrong canonical request, a wrong signing-key HMAC chain
#      order, or standard base64 instead of the URL-safe alphabet all produce
#      a well-formed Authorization header that AWS refuses with a 401
#      indistinguishable from a wrong key. There is no live AWS account to
#      catch that against, so `scripts/support/aws-sigv4-vectors.py` — a
#      SECOND, independent implementation of the published algorithm, written
#      straight from AWS's spec text in Python's stdlib `hashlib`/`hmac`
#      rather than copied from the Swift — supplies fixed test vectors. This
#      harness greps that script's own printed output to prove the pinned
#      values really are what it says (the `safetx-vectors.py` shape).
#
#   2. THE CONDUCT GUARD. AWS genuinely has a read-only IAM policy, unlike
#      Cursor's or App Store Connect's keys — but a policy is configured on
#      AWS's side, not provable by this app, so this file's own conduct is
#      still the backstop. `AWSFetch` may issue only actions on
#      `AWSAction.allowed` (Describe*/List*/Get*) and only GET/POST — never a
#      mutating verb. Prose is what CLAUDE.md calls memory, and memory lost;
#      this makes it mechanical.
#
# `AWSBridge.swift` cannot compile as shipped (it builds `Thing`, a SwiftData
# model), so `AWSSigV4`/`AWSCost`/`AWSAction` are EXTRACTED WHOLE from the
# shipped source by name — never copied — so the harness cannot pass against
# logic the app doesn't run. `AWSRoom.swift` is Foundation-only by design and
# is compiled WHOLE and unmodified.
#
# Pure, local, deterministic — no network, no key, no simulator. Exit non-zero
# on failure. Accepts an optional `--self-test` argument (ignored — every
# assertion and mutation below already runs on every invocation, so there is
# no lighter mode to gate behind the flag; catalog-sync.sh's documented
# precedent for a check with nothing extra to prove first).
set -euo pipefail
cd "$(dirname "$0")/.."

AWS_BRIDGE="Casberi/Casberi/Model/AWSBridge.swift"
AWS_ROOM="Casberi/Casberi/Model/AWSRoom.swift"
VECTORS="scripts/support/aws-sigv4-vectors.py"
BRIDGES="Casberi/Casberi/Model/TokenBridges.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
for f in "$AWS_BRIDGE" "$AWS_ROOM" "$VECTORS" "$BRIDGES" "$REACH" "$FEED"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/aws-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- comment-stripped copy, for every negative guard below (the Obsidian/
# Cursor lesson: this file DOCUMENTS the rules it must never break — "never a
# write verb", "only Describe*/List*/Get*" — so a guard grepping raw source
# fires against the very prose explaining it) --------------------------------
CODE="$TMP/code-only.swift"
python3 - "$AWS_BRIDGE" "$CODE" <<'PY'
import sys
src = open(sys.argv[1]).read()
out, i, n = [], 0, len(src)
in_string = in_line = False
block = 0
while i < n:
    two = src[i:i+2]
    if in_line:
        if src[i] == "\n": in_line = False; out.append("\n")
        i += 1; continue
    if block:
        if two == "/*": block += 1; i += 2; continue
        if two == "*/": block -= 1; i += 2; continue
        if src[i] == "\n": out.append("\n")
        i += 1; continue
    if in_string:
        if src[i] == "\\": out.append(src[i:i+2]); i += 2; continue
        if src[i] == '"': in_string = False
        out.append(src[i]); i += 1; continue
    if two == "//": in_line = True; i += 2; continue
    if two == "/*": block = 1; i += 2; continue
    if src[i] == '"': in_string = True
    out.append(src[i]); i += 1
open(sys.argv[2], "w").write("".join(out))
PY

# --- THE CONDUCT GUARD -------------------------------------------------------
for verb in '"PUT"' '"DELETE"' '"PATCH"' 'httpMethod = "PUT"' 'httpMethod = "DELETE"'; do
  grep -qF -- "$verb" "$CODE" \
    && { echo "✗ AWSBridge.swift now sends a WRITE verb ($verb) — the read-only"; \
         echo "  promise ('this only ever reads') is now a lie. Change the copy"; \
         echo "  in the same commit, or drop the write."; exit 1; }
done
# Only GET/POST, matching `IngestSupport`'s own funnel (every AWS action
# here is read-only regardless of HTTP verb — POST carries the JSON-1.1
# operation body, not a mutation).
grep -qE '"GET"|"POST"' "$CODE" \
  || { echo "✗ no HTTP verb literal found at all — extraction likely drifted"; exit 1; }

# Every ACTION-NAMED call (Query-protocol `"Action": "X"`, or a JSON-1.1
# `X-Amz-Target` string interpolation like `"\(prefix).DescribeAlarms"`) must
# be on the allowlist — extracted from the SHIPPED source, never hand-copied,
# so a call site naming an action outside `AWSAction.allowed` fails the build
# instead of silently shipping. ONE DIRECTION ONLY: S3's `ListBuckets` and
# Lambda's `ListFunctions` are REST calls with no literal action name at all
# (inferred from HTTP method + path, not an `Action=` parameter), so demanding
# every allowlisted name appear as a literal would fail on those by
# construction — their conduct is proven by the GET-only check below instead.
python3 - "$CODE" "$AWS_BRIDGE" <<'PY'
import re, sys
code_path, bridge_path = sys.argv[1], sys.argv[2]
code = open(code_path).read()

issued = set(re.findall(r'"Action":\s*"([A-Za-z]+)"', code))
issued |= set(re.findall(r'\)\.([A-Za-z]+)"', code))  # "\(prefix).Operation"

bridge = open(bridge_path).read()
m = re.search(r'enum AWSAction \{.*?\n\}', bridge, re.S)
if not m:
    sys.exit("✗ AWSAction.allowed extraction found nothing — check the anchor")
allowed = set(re.findall(r'"([A-Za-z]+)"', m.group(0)))
if not allowed:
    sys.exit("✗ AWSAction.allowed parsed to an empty set")
if not issued:
    sys.exit("✗ no action-named call found at all — extraction likely drifted")

bad = sorted(issued - allowed)
if bad:
    print("✗ AWSBridge.swift issues an action outside AWSAction.allowed:")
    for a in bad: print(f"    · {a}")
    sys.exit(1)
PY

# ES256/HMAC hygiene: AWS4-HMAC-SHA256 only, never a different algorithm name.
grep -q 'AWS4-HMAC-SHA256' "$AWS_BRIDGE" \
  || { echo "✗ the signing algorithm literal is gone"; exit 1; }

# --- drift guards -------------------------------------------------------------
grep -q 'AWSIngest.refresh(context: context)' "$BRIDGES" \
  || { echo "✗ TokenIngest no longer routes AWS to AWSIngest — the bridge lands nothing"; exit 1; }
grep -q 'amazonaws.com' "$REACH" \
  || { echo "✗ amazonaws.com is not in the reach registry — the privacy screen is wrong"; exit 1; }
grep -q 'AWSRoomSource.compose(things: visible)' "$FEED" \
  || { echo "✗ the AWS head is not wired into shapedSections — it can never draw"; exit 1; }
grep -q 'AWSRoomCard(standing: standing)' "$FEED" \
  || { echo "✗ the head resolves but no card renders it"; exit 1; }

# CloudWatch: only a real transition lands, and first sight seeds in silence
# — else an account with a year of alarm history lands a year of fake news
# the moment it connects (the App Store Connect/Hyperliquid first-sight bug).
grep -qE 'guard !firstSight, previous != state, previous != nil' "$AWS_BRIDGE" \
  || { echo "✗ the alarm transition-only guard is gone or weakened — history would land as news"; exit 1; }
grep -q 'AWSState.alarmsSeeded = true' "$AWS_BRIDGE" \
  || { echo "✗ the alarm seed flag is never set — every pass would re-seed forever"; exit 1; }

# CodePipeline: only terminal executions may land — Cursor's CREATING/RUNNING
# rule, restated because the two bridges share no status type to hang one
# function off.
grep -qE 'status == "Succeeded" \|\| status == "Failed" \|\| status == "Superseded"' "$AWS_BRIDGE" \
  || { echo "✗ the terminal-execution filter is gone or weakened — InProgress would land"; exit 1; }
# The failure LEADS — `IngestSupport.titleLine`'s 80-char clamp eats the END
# of a title, so a trailing outcome is exactly what gets cut.
grep -qE '"Failed · \\\(pipeline\)"' "$AWS_BRIDGE" \
  || { echo "✗ a failed deploy's title no longer leads with the outcome — the §83 fake status"; exit 1; }

# Resource inventory NEVER lands a Thing — only counts into AWSStanding.
grep -qE 'standing\.ec2Count = ec2Rows\?\.count' "$AWS_BRIDGE" \
  || { echo "✗ the resource inventory no longer composes into AWSStanding"; exit 1; }
for kind in 'ec2InstanceIDs' 's3BucketNames' 'rdsInstanceIDs' 'lambdaFunctionNames'; do
  grep -qF "Thing(" <(awk "/static func $kind/,/^    }/" "$AWS_BRIDGE") \
    && { echo "✗ $kind lands a Thing directly — resource inventory must be state-only"; exit 1; }
done

# Cost Explorer is region-pinned to us-east-1 regardless of the account's
# chosen resource region — a real AWS quirk, not a bug, and the one place a
# "just use the region variable everywhere" cleanup would silently break it.
grep -q 'costExplorerHost = "ce.us-east-1.amazonaws.com"' "$AWS_BRIDGE" \
  || { echo "✗ Cost Explorer is no longer pinned to us-east-1"; exit 1; }

# --- extract the shipped pure types ------------------------------------------
python3 - "$AWS_BRIDGE" "$TMP/extracted.swift" <<'PY'
import sys
src_path, out = sys.argv[1], sys.argv[2]

def grab(path, signature):
    src = open(path).read()
    i = src.find(signature)
    if i < 0:
        sys.exit(f"EXTRACTION FAILED: {signature!r} not found in {path}")
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
    "import CryptoKit\n",
    grab(src_path, "enum AWSSigV4"),
    grab(src_path, "enum AWSAction"),
    grab(src_path, "enum AWSCost"),
    grab(src_path, "struct AWSStanding"),
]
open(out, "w").write("\n".join(pieces))
PY

# --- the SigV4 fixture, from the independent Python vectors ------------------
VEC_OUT="$TMP/vectors.txt"
python3 "$VECTORS" > "$VEC_OUT"
V1_SIG=$(awk '/Vector 1/,/Vector 2/' "$VEC_OUT" | grep '^signature:' | awk '{print $2}')
V2_SIG=$(awk '/Vector 2/,0' "$VEC_OUT" | grep '^signature:' | awk '{print $2}')
[[ ${#V1_SIG} -eq 64 && ${#V2_SIG} -eq 64 ]] \
  || { echo "✗ couldn't extract both signatures from $VECTORS's own output"; exit 1; }

# --- the driver -------------------------------------------------------------
cat > "$TMP/main.swift" <<SWIFT
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \\(label)") } else { print("  ✗ \\(label)"); failures += 1 }
}

let V1_EXPECTED = "$V1_SIG"
let V2_EXPECTED = "$V2_SIG"
let ACCESS_KEY = "AKIAIOSFODNN7EXAMPLE"
let SECRET_KEY = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"

func fixedDate() -> Date {
    var comps = DateComponents()
    comps.year = 2025; comps.month = 1; comps.day = 15
    comps.hour = 12; comps.minute = 0; comps.second = 0
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal.date(from: comps)!
}

print("AWSSigV4 — matches an INDEPENDENT Python implementation of the published algorithm")
let v1 = AWSSigV4.sign(method: "GET", host: "rds.us-east-1.amazonaws.com", path: "/",
                       query: ["Action": "DescribeDBInstances", "Version": "2014-10-31"],
                       body: Data(), service: "rds", region: "us-east-1",
                       accessKeyID: ACCESS_KEY, secretKey: SECRET_KEY, date: fixedDate())
check("Vector 1 (GET, query string, empty body): the amzDate matches",
      v1.amzDate == "20250115T120000Z")
check("Vector 1: the signature matches Python's hashlib/hmac reference EXACTLY",
      v1.authorization.hasSuffix("Signature=\\(V1_EXPECTED)"))
check("Vector 1: the credential scope names the right service/region",
      v1.authorization.contains("Credential=\\(ACCESS_KEY)/20250115/us-east-1/rds/aws4_request"))

let jsonBody = "{\\"StateValue\\":\\"ALARM\\"}".data(using: .utf8)!
let v2 = AWSSigV4.sign(method: "POST", host: "monitoring.us-east-1.amazonaws.com", path: "/",
                       query: [:], body: jsonBody, service: "monitoring", region: "us-east-1",
                       accessKeyID: ACCESS_KEY, secretKey: SECRET_KEY, date: fixedDate())
check("Vector 2 (POST, JSON body): the signature matches Python's reference EXACTLY",
      v2.authorization.hasSuffix("Signature=\\(V2_EXPECTED)"))
check("Vector 2: content-type is NOT signed (SigV4 doesn't require every sent header to be)",
      v2.authorization.contains("SignedHeaders=host;x-amz-content-sha256;x-amz-date"))

print("AWSSigV4.uriEncode — RFC 3986 unreserved characters only")
check("unreserved characters pass through", AWSSigV4.uriEncode("abcXYZ019-_.~") == "abcXYZ019-_.~")
check("a space becomes %20, never +", AWSSigV4.uriEncode("a b") == "a%20b")
check("a slash is encoded by default (query values, never a path)",
      AWSSigV4.uriEncode("a/b") == "a%2Fb")
check("a slash survives when told not to encode it (a path)",
      AWSSigV4.uriEncode("/a/b", encodeSlash: false) == "/a/b")
check("uppercase hex, AWS's own rule", AWSSigV4.uriEncode("*") == "%2A")

print("AWSSigV4.canonicalQuery — sorted by the ENCODED key")
check("two params sort correctly",
      AWSSigV4.canonicalQuery(["Version": "1", "Action": "X"]) == "Action=X&Version=1")
check("empty params yields empty string", AWSSigV4.canonicalQuery([:]) == "")

print("AWSSigV4.sha256Hex — the well-known empty-string digest")
check("sha256('') is the constant every AWS example quotes",
      AWSSigV4.sha256Hex(Data())
        == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")

print("AWSCost — median, never the mean (StripeSilence's lesson)")
check("odd count takes the middle", AWSCost.median([1, 5, 100]) == 5)
check("even count averages the two middle values", AWSCost.median([1, 3, 5, 7]) == 4)
check("a single burst day does NOT drag the median the way it would a mean",
      AWSCost.median([1, 1, 1, 1, 1, 1, 100]) == 1)
check("empty input is 0, not a crash", AWSCost.median([]) == 0)

print("AWSCost.isAnomaly — a real multiple AND a real floor, both required")
check("a real jump above the floor is an anomaly",
      AWSCost.isAnomaly(today: 20, baseline: 5, multiplier: 2.0, floor: 5.0))
check("a jump BELOW the floor is not, however large the multiple",
      !AWSCost.isAnomaly(today: 4, baseline: 0.5, multiplier: 2.0, floor: 5.0))
check("above the floor but under the multiplier is not an anomaly",
      !AWSCost.isAnomaly(today: 8, baseline: 5, multiplier: 2.0, floor: 5.0))
check("a zero baseline with real spend above the floor still flags",
      AWSCost.isAnomaly(today: 10, baseline: 0, multiplier: 2.0, floor: 5.0))
check("a zero baseline with spend under the floor does not",
      !AWSCost.isAnomaly(today: 2, baseline: 0, multiplier: 2.0, floor: 5.0))

print("")
if failures == 0 {
    print("✓ aws self-test: all assertions passed")
} else {
    print("✗ aws self-test: \\(failures) assertion(s) failed")
    exit(1)
}
SWIFT

if ! swiftc -O -o "$TMP/run" "$TMP/extracted.swift" "$AWS_ROOM" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ the extracted AWS logic did not compile"
  grep -E 'error:' "$TMP/build.log" | head -20
  exit 1
fi
"$TMP/run"

# --- mutations ---------------------------------------------------------------
echo
echo "mutations (each must be caught)"

WORK="$TMP/work"
mutate() {
  local name="$1" from="$2" to="$3"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$AWS_BRIDGE" "$WORK/AWSBridge.swift"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/AWSBridge.swift" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$WORK/AWSBridge.swift"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  local extracted="$WORK/extracted.swift"
  if ! python3 - "$WORK/AWSBridge.swift" "$extracted" <<'PY' 2>/dev/null
import sys
src_path, out = sys.argv[1], sys.argv[2]
def grab(path, signature):
    src = open(path).read()
    i = src.find(signature)
    if i < 0: sys.exit(1)
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
pieces = ["import Foundation\n", "import CryptoKit\n",
          grab(src_path, "enum AWSSigV4"), grab(src_path, "enum AWSAction"),
          grab(src_path, "enum AWSCost"), grab(src_path, "struct AWSStanding")]
open(out, "w").write("\n".join(pieces))
PY
  then
    echo "  ✓ $name (rejected at extraction)"; return
  fi
  if ! swiftc -O -o "$TMP/mut" "$extracted" "$AWS_ROOM" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# 1. THE URL-SAFE ALPHABET, relaxed to standard base64. The token looks right
#    and every request is refused.
mutate "base64url relaxed toward standard base64 in uriEncode" \
  'var allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")' \
  'var allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~/+=")'

# 2. The signing-key HMAC chain shortened — the single most likely "let's
#    simplify this" mistake, and one that produces a signature AWS refuses
#    with no clue why.
mutate "the AWS4 signing-key chain shortened by one link" \
  'let kService = hmac(key: kRegion, service)
        return hmac(key: kService, "aws4_request")' \
  'return hmac(key: kRegion, "aws4_request")'

# 3. Query parameters sorted the WRONG WAY — AWS's canonicalization is
#    order-sensitive, and a mis-ordered query string signs a DIFFERENT
#    request than the one actually sent whenever two parameters exist.
#
#    REVERSED rather than DELETED, and that is the whole point (2026-08-31):
#    this mutation used to remove the `.sorted` outright, which made it FLAKY
#    and it duly survived a real run — `canonicalQuery` takes a
#    `[String: String]`, and a Swift Dictionary's iteration order is
#    unspecified, so an unsorted two-key fixture comes out already in sorted
#    order a good share of the time. The harness then printed a green tick
#    over a signing rule nothing was testing. A reversed comparator is
#    deterministic: it can never coincide with the sorted answer for a
#    fixture whose keys differ, so the mutation is caught every run.
#    Standing lesson: never mutate a stable order into a Dictionary's order.
mutate "canonical query sorted the wrong way" \
  'params.map { (uriEncode($0.key), uriEncode($0.value)) }
            .sorted { $0.0 < $1.0 }' \
  'params.map { (uriEncode($0.key), uriEncode($0.value)) }
            .sorted { $0.0 > $1.0 }'

# 4. THE MEDIAN QUIETLY BECOMES A MEAN — the exact StripeSilence-class
#    regression this file's header warns about by name.
mutate "the cost baseline becomes a mean instead of a median" \
  'guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]' \
  'guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)'

# 5. The anomaly floor dropped — a $0.02 → $0.06 day on a near-empty account
#    reads as a spend anomaly, the noise this floor exists to filter.
mutate "the cost anomaly floor removed" \
  'guard today >= floor else { return false }' \
  'guard today >= 0 else { return false }'

echo
echo "✓ aws self-test: assertions and mutations all passed"
