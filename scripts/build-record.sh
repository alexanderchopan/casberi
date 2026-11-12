#!/bin/bash
# build-record.sh — which commit a shipped build was made from.
#
# A ship archives a copy of the working tree, so a build matches a commit only
# if the tree was clean when it was copied. This script is the three steps
# that make that checkable by anyone reading the repo:
#
#   build-record.sh check
#       Before the build number is bumped. Prints "clean <sha>" when every
#       tracked file under Casberi/ and Vendor/ equals HEAD. Otherwise it
#       refuses (exit 1), or with ALLOW_DIRTY=1 prints "dirty <sha>" and the
#       files that differ, so the ledger says so.
#
#   build-record.sh add <platform> <build> <version> <clean|dirty> <sha>
#       After the upload. Appends one row to docs/builds.md. Commit that file
#       with the build-number bump.
#
#   build-record.sh tag <build>
#       After that commit is on main. Tags it build-<n> and pushes the tag.
#       Refuses a build the ledger marks dirty: its source is not a commit.
#
#   build-record.sh --self-test
#
# The source of a clean build <n> is the tree of tag build-<n> (the commit
# that carries the bump); the row's "from" column is that commit's parent.
set -euo pipefail

ROOT="${BUILD_RECORD_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
LEDGER="$ROOT/docs/builds.md"
HEADER='| Build | Version | Platform | From | Tree | Date |'

PBX="Casberi/Casberi.xcodeproj/project.pbxproj"

# Tracked files that differ from HEAD. A project file whose only change is the
# build number is not a difference: that is an earlier ship's bump waiting to
# be committed (iOS then Mac), and the number is recorded in the row.
differing() {
  git -C "$ROOT" status --porcelain --untracked-files=no -- Casberi Vendor | while IFS= read -r line; do
    if [ "${line:3}" = "$PBX" ] && ! git -C "$ROOT" diff HEAD -- "$PBX" | grep -E '^[+-][^+-]' | grep -vqE 'CURRENT_PROJECT_VERSION = [0-9]+;'; then
      continue
    fi
    echo "$line"
  done
}

check() {
  local sha dirty
  sha=$(git -C "$ROOT" rev-parse --short=9 HEAD)
  dirty=$(differing)
  if [ -z "$dirty" ]; then echo "clean $sha"; return 0; fi
  if [ "${ALLOW_DIRTY:-0}" = "1" ]; then
    echo "build-record: tracked files differ from HEAD; this build will match no commit:" >&2
    echo "$dirty" | sed 's/^/  /' >&2
    echo "dirty $sha"; return 0
  fi
  echo "✗ build-record: tracked files under Casberi/ or Vendor/ differ from HEAD, so this build would match no commit:" >&2
  echo "$dirty" | sed 's/^/  /' >&2
  echo "  Commit them, ship from a clean worktree, or set ALLOW_DIRTY=1 to ship anyway (the ledger will say dirty)." >&2
  return 1
}

add() {
  local platform="$1" build="$2" version="$3" tree="$4" sha="$5"
  case "$tree" in clean|dirty) ;; *) echo "✗ build-record: tree must be clean or dirty" >&2; return 1;; esac
  [ -f "$LEDGER" ] || { echo "✗ build-record: $LEDGER is missing" >&2; return 1; }
  printf '| %s | %s | %s | `%s` | %s | %s |\n' "$build" "$version" "$platform" "$sha" "$tree" "$(date -u +%Y-%m-%d)" >> "$LEDGER"
  echo "build-record: build $build recorded in docs/builds.md ($tree, from $sha). Commit it with the bump."
}

tag() {
  local build="$1" row commit
  row=$(grep -E "^\| $build \|" "$LEDGER" | tail -1 || true)
  [ -n "$row" ] || { echo "✗ build-record: no row for build $build in docs/builds.md" >&2; return 1; }
  case "$row" in *"| clean |"*) ;; *) echo "✗ build-record: build $build is recorded dirty; it matches no commit and gets no tag" >&2; return 1;; esac
  commit=$(git -C "$ROOT" log -1 --format=%H -S"| $build |" -- docs/builds.md)
  [ -n "$commit" ] || { echo "✗ build-record: the row for build $build is not committed yet" >&2; return 1; }
  if git -C "$ROOT" rev-parse -q --verify "refs/tags/build-$build" >/dev/null; then
    echo "build-record: build-$build already exists"; return 0
  fi
  git -C "$ROOT" tag -a "build-$build" -m "Build $build" "$commit"
  echo "build-record: tagged build-$build at $(git -C "$ROOT" rev-parse --short=9 "$commit")"
  [ "${BUILD_RECORD_NO_PUSH:-0}" = "1" ] || git -C "$ROOT" push -q origin "refs/tags/build-$build"
}

self_test() {
  local tmp fails=0; tmp=$(mktemp -d /tmp/build-record.XXXXXX)
  ok() { echo "  ✓ $1"; }; bad() { echo "  ✗ $1"; fails=$((fails + 1)); }
  run() { BUILD_RECORD_ROOT="$tmp" BUILD_RECORD_NO_PUSH=1 "$0" "$@"; }
  git -C "$tmp" init -q; git -C "$tmp" config user.email t@example.com; git -C "$tmp" config user.name t
  mkdir -p "$tmp/Casberi/Casberi.xcodeproj" "$tmp/Vendor" "$tmp/docs"
  printf 'CURRENT_PROJECT_VERSION = 6;\nMARKETING_VERSION = 1.0;\n' > "$tmp/$PBX"
  echo a > "$tmp/Casberi/a.swift"; printf '%s\n| --- | --- | --- | --- | --- | --- |\n' "$HEADER" > "$tmp/docs/builds.md"
  git -C "$tmp" add -A; git -C "$tmp" commit -qm base
  local sha; sha=$(git -C "$tmp" rev-parse --short=9 HEAD)

  [ "$(run check)" = "clean $sha" ] && ok "a clean tree is clean" || bad "a clean tree is clean"
  echo untracked > "$tmp/Casberi/new.txt"
  [ "$(run check)" = "clean $sha" ] && ok "an untracked file is not a difference" || bad "an untracked file is not a difference"
  echo b >> "$tmp/Casberi/a.swift"
  if run check >/dev/null 2>&1; then bad "a changed tracked file is refused"; else ok "a changed tracked file is refused"; fi
  [ "$(ALLOW_DIRTY=1 run check 2>/dev/null)" = "dirty $sha" ] && ok "ALLOW_DIRTY ships and says dirty" || bad "ALLOW_DIRTY ships and says dirty"
  git -C "$tmp" checkout -q -- Casberi/a.swift
  printf 'CURRENT_PROJECT_VERSION = 7;\nMARKETING_VERSION = 1.0;\n' > "$tmp/$PBX"
  [ "$(run check)" = "clean $sha" ] && ok "a build-number bump alone is not a difference" || bad "a build-number bump alone is not a difference"
  printf 'CURRENT_PROJECT_VERSION = 7;\nMARKETING_VERSION = 1.1;\n' > "$tmp/$PBX"
  if run check >/dev/null 2>&1; then bad "any other project change is refused"; else ok "any other project change is refused"; fi
  git -C "$tmp" checkout -q -- "$PBX"

  run add iOS 7 1.0 clean "$sha" >/dev/null
  grep -q "^| 7 | 1.0 | iOS | \`$sha\` | clean | " "$tmp/docs/builds.md" && ok "add writes the row" || bad "add writes the row"
  if run tag 7 >/dev/null 2>&1; then bad "an uncommitted row gets no tag"; else ok "an uncommitted row gets no tag"; fi
  git -C "$tmp" commit -qam "Bump build number to 7"
  run tag 7 >/dev/null
  [ "$(git -C "$tmp" rev-list -n1 build-7)" = "$(git -C "$tmp" rev-parse HEAD)" ] && ok "the tag is the commit that carries the row" || bad "the tag is the commit that carries the row"
  run add iOS 8 1.0 dirty "$sha" >/dev/null; git -C "$tmp" commit -qam "Bump build number to 8"
  if run tag 8 >/dev/null 2>&1; then bad "a dirty build gets no tag"; else ok "a dirty build gets no tag"; fi
  if run tag 99 >/dev/null 2>&1; then bad "an unknown build gets no tag"; else ok "an unknown build gets no tag"; fi
  if run add iOS 9 1.0 spotless "$sha" >/dev/null 2>&1; then bad "a made-up tree state is refused"; else ok "a made-up tree state is refused"; fi

  rm -rf "$tmp"
  [ "$fails" -eq 0 ] && echo "✓ build-record self-test passed" || { echo "✗ build-record self-test: $fails failed"; return 1; }
}

case "${1:-}" in
  check) check ;;
  add) [ $# -eq 6 ] || { echo "usage: build-record.sh add <platform> <build> <version> <clean|dirty> <sha>" >&2; exit 2; }; add "$2" "$3" "$4" "$5" "$6" ;;
  tag) [ $# -eq 2 ] || { echo "usage: build-record.sh tag <build>" >&2; exit 2; }; tag "$2" ;;
  --self-test) self_test ;;
  *) sed -n '2,24p' "$0"; exit 2 ;;
esac
