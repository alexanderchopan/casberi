#!/usr/bin/env bash
#
# cloudkit-schema.sh — inspect and deploy the CloudKit schema from the terminal.
#
# WHY THIS EXISTS. SwiftData auto-creates CloudKit record types in the
# DEVELOPMENT environment when a debug build runs against a signed-in iCloud
# account. It can NEVER create them in PRODUCTION — TestFlight and App Store
# builds sync against a schema that only changes when someone deploys it.
#
# MEASURED 2026-07-27: both environments held ONLY `Users` (CloudKit's own
# built-in type) — no `CD_Thing` anywhere. So the schema had never been
# created at all, let alone deployed: the simulator has no iCloud account
# (prd §525) and every real-device build was TestFlight, i.e. production,
# which cannot auto-create. Sync had never run once, silently.
#
# This stays a per-release chore, not a one-off: `Thing` gains fields
# constantly (14 stored properties at M1, 44 by 2026-07-27), and each one is a
# new CD_ field production won't know about until it is deployed again.
#
# This wraps `xcrun cktool` for the READ half — status and diff are genuinely
# terminal-only, no browser needed:
#
#   status   — what each environment actually has (record types + field counts)
#   diff     — field-level difference, development vs production
#
# MEASURED 2026-07-27: the WRITE half is not available here. Both
# `cktool import-schema` and `cktool validate-schema` reject `--environment
# production` outright — "BadRequestException: endpoint not applicable in the
# environment 'production'" — even though `--environment` itself validates
# production as a real enum value (export-schema reads it fine; only the two
# write-side commands refuse it). This isn't a flag issue on our end; Apple's
# API has no route to promote a schema into production at all. The CloudKit
# Console's "Deploy Schema Changes" button is calling something with no public
# API or cktool equivalent — `deploy` below gets you to the validated file and
# then tells you to click that one button by hand.
#
# ONE-TIME SETUP (the only step that needs a browser for status/diff — the
# management token is Apple-ID authenticated, and there is no API to mint one):
#
#   1. https://icloud.developer.apple.com/dashboard/  →  Settings  →  Tokens
#   2. Create a CloudKit Management Token, copy it
#   3. xcrun cktool save-token --type management
#      (paste at the prompt; it stores in the login keychain)
#
# DEPLOYING IS ONE-WAY. CloudKit production schema changes are additive only:
# once a record type or field exists in production it can never be removed or
# retyped. `deploy` still refuses to run past the local validation without an
# explicit --yes, as a deliberate speed bump before you go click the button.
#
# Usage:
#   scripts/cloudkit-schema.sh status
#   scripts/cloudkit-schema.sh diff
#   scripts/cloudkit-schema.sh deploy --yes   # validates locally, then hands
#                                              # you the one manual console step

set -euo pipefail

TEAM_ID="35428TQK3S"
CONTAINER="iCloud.com.casberi.app"
WORK="${TMPDIR:-/tmp}/casberi-ckschema.$$"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

ck() { xcrun cktool "$@"; }

# Export one environment's schema to $WORK/<env>.ckdb. Returns non-zero and
# leaves an empty file when the environment has no schema at all, which is
# itself a finding (development empty == a debug build never ran with sync on).
fetch() {
  # Two statements, not one `local a=… b=…`: bash expands a `local` command's
  # whole argument list up front, so `$env` there resolves in the CALLER's
  # scope — which happened to exist in `status` (loop variable) and not in
  # `diff`, giving an unbound-variable error in one caller only.
  local env="$1"
  local out="$WORK/$env.ckdb"
  if ! ck export-schema --team-id "$TEAM_ID" --container-id "$CONTAINER" \
        --environment "$env" --output-file "$out" >/dev/null 2>"$WORK/$env.err"; then
    echo "  ! could not read $env schema:" >&2
    sed 's/^/    /' "$WORK/$env.err" >&2
    return 1
  fi
  [ -s "$out" ]
}

# Field names for one record type, one per line. The .ckdb grammar is
#
#     RECORD TYPE <Name> (
#         "___createTime" TIMESTAMP,
#         roles           LIST<INT64>,
#         GRANT WRITE TO "_creator"
#     );
#
# — INDENTED four spaces, fields optionally quoted, and the body closed by an
# indented `);`. An earlier version anchored on `^RECORD TYPE` and silently
# found nothing at all; hence the leading-whitespace strip everywhere here.
# The `___`-prefixed fields are CloudKit's own system columns, not ours.
fields_of() {
  local file="$1" type="$2"
  awk -v want="$type" '
    { line = $0; sub(/^[ \t]+/, "", line) }
    line ~ "^RECORD TYPE " want " *\\(" { inside = 1; next }
    inside && line ~ /^\)/ { inside = 0; next }
    inside {
      n = split(line, parts, /[ \t]+/)
      name = parts[1]
      if (name == "" || name ~ /^(GRANT|PERMISSION)$/) next
      gsub(/,$/, "", name); gsub(/"/, "", name)
      if (name != "") print name
    }
  ' "$file" | sort -u
}

record_types() {
  sed 's/^[[:space:]]*//' "$1" 2>/dev/null \
    | grep -oE '^RECORD TYPE [A-Za-z0-9_]+' | awk '{print $3}' | sort -u
}

require_token() {
  if ! ck get-teams >/dev/null 2>&1; then
    cat >&2 <<'EOS'
No CloudKit management token found.

One-time setup (needs a browser once — the token is Apple-ID authenticated):
  1. https://icloud.developer.apple.com/dashboard/  →  Settings  →  Tokens
  2. Create a CloudKit Management Token and copy it
  3. xcrun cktool save-token --type management     (paste at the prompt)
EOS
    exit 1
  fi
}

cmd_status() {
  local env count
  for env in development production; do
    echo "== $env"
    if ! fetch "$env"; then echo "  (no schema)"; echo; continue; fi
    count=0
    while read -r t; do
      [ -n "$t" ] || continue
      echo "  $t — $(fields_of "$WORK/$env.ckdb" "$t" | wc -l | tr -d ' ') fields"
      count=$((count + 1))
    done < <(record_types "$WORK/$env.ckdb")
    [ "$count" -eq 0 ] && echo "  (no record types)"
    echo
  done
}

cmd_diff() {
  fetch development || { echo "development has no schema — run a debug build on a real device with iCloud signed in and sync on, then retry." >&2; exit 1; }
  local prod_ok=1
  fetch production || prod_ok=0

  local drift=0
  while read -r t; do
    [ -n "$t" ] || continue
    if [ "$prod_ok" -eq 0 ] || ! record_types "$WORK/production.ckdb" | grep -qx "$t"; then
      echo "MISSING RECORD TYPE in production: $t"
      drift=1
      continue
    fi
    local missing
    missing=$(comm -23 <(fields_of "$WORK/development.ckdb" "$t") \
                       <(fields_of "$WORK/production.ckdb" "$t"))
    if [ -n "$missing" ]; then
      echo "$t — fields in development but NOT in production:"
      echo "$missing" | sed 's/^/  /'
      drift=1
    fi
  done < <(record_types "$WORK/development.ckdb")

  # "In sync" is a true but useless answer when BOTH environments are empty.
  # A virgin container still carries `Users` (CloudKit's own built-in type), so
  # the absence of `CD_Thing` — not the absence of a diff — is what says the
  # mirror has never run anywhere. Call that out rather than reading green.
  if ! record_types "$WORK/development.ckdb" | grep -qx 'CD_Thing'; then
    echo "NOT SET UP — no CD_Thing record type in development."
    echo "SwiftData has never created the schema, so nothing has ever synced."
    echo "Fix: run a DEBUG build on a real iPhone signed into iCloud with the"
    echo "     Data-tray sync toggle ON. That creates CD_Thing in development;"
    echo "     then deploy it to production with:"
    echo "       scripts/cloudkit-schema.sh deploy --yes"
    return 0
  fi

  if [ "$drift" -eq 0 ]; then
    echo "In sync — production carries every development record type and field."
  else
    echo
    echo "Production is behind. Deploy with: scripts/cloudkit-schema.sh deploy --yes"
  fi
  return 0
}

cmd_deploy() {
  [ "${1:-}" = "--yes" ] || {
    echo "Refusing to deploy without --yes." >&2
    echo "Production schema changes are PERMANENT — a field can never be removed or retyped." >&2
    echo "Review first:  scripts/cloudkit-schema.sh diff" >&2
    exit 1
  }
  fetch development || { echo "development has no schema to deploy." >&2; exit 1; }

  # There is no API/cktool route into production for a schema write — both
  # `import-schema` and `validate-schema` 400 against `--environment
  # production` no matter what (measured 2026-07-27; see the file header).
  # `--environment development` on validate-schema is the closest honest
  # check available here: same file, same rules, the one difference being
  # WHICH indexes/environment-specific config it's validated against.
  echo "Validating the development schema…"
  ck validate-schema --team-id "$TEAM_ID" --container-id "$CONTAINER" \
     --environment development --file "$WORK/development.ckdb"

  echo
  echo "Validated locally. The actual production write has no terminal path —"
  echo "click it by hand, once:"
  echo
  echo "  1. https://icloud.developer.apple.com/dashboard/"
  echo "  2. Container: $CONTAINER  →  Schema  →  Deploy Schema Changes"
  echo "  3. Confirm — this copies development's CD_Thing into production,"
  echo "     permanently (fields can be added later, never removed/retyped)."
  echo
  echo "Then verify from here:  scripts/cloudkit-schema.sh diff"
}

require_token
case "${1:-status}" in
  status) cmd_status ;;
  diff)   cmd_diff ;;
  deploy) shift; cmd_deploy "$@" ;;
  *) echo "usage: $0 {status|diff|deploy --yes}" >&2; exit 2 ;;
esac
