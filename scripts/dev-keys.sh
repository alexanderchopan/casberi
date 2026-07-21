#!/bin/bash
# dev-keys.sh — local test keys for keyed probes, stored in the macOS login Keychain.
# Values are fetched at use-time via command substitution so they never enter
# assistant context or session transcripts:
#   xcrun simctl launch booted com.casberi.app -byokKey "venice:$(scripts/dev-keys.sh get venice)"
# Never `get` a key into a plain echo/cat — always inline it into the consuming command.

set -euo pipefail

PREFIX="casberi-dev"

usage() {
  cat >&2 <<'EOF'
usage: dev-keys.sh <command> [name]

  set <name>             store a key (prompts silently; or pipe it in: pbpaste | dev-keys.sh set readwise)
  get <name>             print the key (use ONLY inside $(...) in the consuming command)
  set-file <name> <path> store a key FILE (e.g. an ASC .p8) — base64d into the Keychain
  get-file <name> <dest> restore a stored key file to <dest> (mode 600)
  list                   list stored key names (never values)
  delete <name>          remove a key

Keys live in the login Keychain as generic passwords under service "casberi-dev.<name>".
EOF
  exit 64
}

cmd="${1:-}"; name="${2:-}"

case "$cmd" in
  set)
    [ -n "$name" ] || usage
    if [ -t 0 ]; then
      read -rs -p "value for $name (input hidden): " value; echo >&2
    else
      IFS= read -r value || true  # read exits 1 at EOF when input has no trailing newline
    fi
    value="${value%$'\n'}"
    [ -n "$value" ] || { echo "dev-keys: empty value, nothing stored" >&2; exit 1; }
    security add-generic-password -U -s "$PREFIX.$name" -a "$USER" \
      -l "Casberi dev key: $name" -w "$value"
    echo "dev-keys: stored '$name'"
    ;;
  get)
    [ -n "$name" ] || usage
    security find-generic-password -s "$PREFIX.$name" -w
    ;;
  set-file)
    path="${3:-}"
    { [ -n "$name" ] && [ -r "$path" ]; } || usage
    security add-generic-password -U -s "$PREFIX.$name" -a "$USER" \
      -l "Casberi dev key: $name" -w "$(base64 < "$path" | tr -d '\n')"
    echo "dev-keys: stored file '$name' ($(basename "$path"))"
    ;;
  get-file)
    dest="${3:-}"
    { [ -n "$name" ] && [ -n "$dest" ]; } || usage
    umask 077
    security find-generic-password -s "$PREFIX.$name" -w | base64 -d > "$dest"
    echo "dev-keys: wrote '$name' to $dest" >&2
    ;;
  list)
    security dump-keychain 2>/dev/null \
      | { grep -o "\"svce\"<blob>=\"$PREFIX\.[^\"]*\"" || true; } \
      | sed -e "s/.*$PREFIX\.//" -e 's/"$//' \
      | sort -u
    ;;
  delete)
    [ -n "$name" ] || usage
    security delete-generic-password -s "$PREFIX.$name" >/dev/null 2>&1
    echo "dev-keys: deleted '$name'"
    ;;
  *)
    usage
    ;;
esac
