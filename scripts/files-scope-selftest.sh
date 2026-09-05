#!/bin/zsh
# The connected folder's byte reads must open the security scope THEMSELVES
# (prd §604, 2026-09-04).
#
# A file inside a picked folder is readable only inside an active
# `startAccessingSecurityScopedResource` window on that folder. Outside one the
# read is REFUSED, and refused is indistinguishable from "no bytes yet":
# `CGImageSourceCreateWithURL` returns nil either way, `ocrRead` reports
# `attempted == false`, `ocrAt` stays nil, and the same file is re-read and
# re-fails on every foreground pass for the life of the install. From outside
# that is a folder of screenshots drawn as a wall of filenames — the room's own
# §283 failure, with nothing on any screen saying why.
#
# It has happened. The scope used to sit at the top of `FilesIngest.heal` and
# cover the read loop; on 2026-07-29 the walk moved into a detached task and
# took the scope with it, so every read below ran unscoped. Five weeks, two
# reports, and one fix aimed at the wrong cause before it was found — because
# the two reads that KEPT working (a video's poster frame, a text file's
# preview) are the two that carry a scope of their own, and because on the
# simulator a picked folder is usually in-sandbox, so the scope is never needed
# and the whole class is invisible to every check that runs here.
#
# So the rule is that the scope belongs to the READ, never to whichever caller
# happens to enclose it — and this is that rule, mechanically.
#
# `--self-test` mutates a COPY of the real source four ways, one per shape this
# is meant to catch, and requires each to go red. A check that cannot be shown
# to fail certifies nothing.
set -uo pipefail
cd "$(dirname "$0")/.."

BRIDGE="Casberi/Casberi/Model/FilesBridge.swift"
MEDIA="Casberi/Casberi/Model/ImportMedia.swift"

fail() { echo "✗ $1"; exit 1; }

# The body of one Swift func, by name — from its `func` line to the closing
# brace at declaration indentation. Enough to ask "does THIS function open the
# scope", which a whole-file grep cannot: the file opens a scope elsewhere (the
# walk, the audio handle), so a file-level check passes vacuously — and that is
# precisely the check that would have called the five-weeks-broken tree clean.
body() {
  awk -v name="$1" '
    index($0, "func " name "(") { on=1 }
    on { print }
    on && /^    }$/ { exit }
  ' "$2"
}

check_reader() {
  local fn="$1" src="$2" b
  b="$(body "$fn" "$src")"
  [[ -n "$b" ]] || fail "$fn not found in the bridge — this guard now checks nothing"
  print -r -- "$b" | grep -q 'folder: URL' \
    || fail "$fn no longer takes the folder, so it cannot open the scope — every read it makes on a picked folder is refused and reads as 'no bytes yet'"
  print -r -- "$b" | grep -q 'folder.startAccessingSecurityScopedResource()' \
    || fail "$fn does not open the security scope — a picked folder's bytes are unreadable outside one, silently and permanently"
  print -r -- "$b" | grep -q 'folder.stopAccessingSecurityScopedResource()' \
    || fail "$fn opens the security scope and never closes it — the scope is refcounted, so a leaked start holds it open for the life of the process"
}

run_checks() {
  local bridge="$1" media="$2"
  [[ -f "$bridge" ]] || fail "$bridge not found"
  [[ -f "$media"  ]] || fail "$media not found"

  check_reader thumbnail "$bridge"
  check_reader ocrRead   "$bridge"

  # The call sites must actually hand the folder over. A reader that takes one
  # and a caller that omits it cannot compile — but a caller passing some OTHER
  # folder can, so both sites are pinned to `heal`'s own resolved root.
  grep -qF 'await thumbnail(url: fileURL, folder: folder)' "$bridge" \
    || fail "heal no longer passes its own folder to thumbnail"
  grep -qF 'await ocrRead(url: fileURL, folder: folder)' "$bridge" \
    || fail "heal no longer passes its own folder to ocrRead"

  # The video half is the same rule kept where it lives: `posterFrame` opens the
  # scope itself, which is the precedent this guard generalises — and the reason
  # videos went on tiling while images stopped. If it ever stops, a folder's
  # videos lose their tiles the same silent way.
  grep -q 'startAccessingSecurityScopedResource' "$media" \
    || fail "ImportMedia.posterFrame no longer opens the security scope itself"
  grep -qF 'ImportMedia.posterFrame(url: fileURL, folder: folder)' "$bridge" \
    || fail "heal no longer hands posterFrame the folder its scope needs"

  # The walk still needs its own window: it is what turns the bookmark into
  # URLs, it runs detached, and so it can never borrow a caller's.
  grep -q 'let scoped = folder.startAccessingSecurityScopedResource()' "$bridge" \
    || fail "the folder walk no longer opens a scope"
}

if [[ "${1:-}" == "--self-test" ]]; then
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  ok=0
  probe() {  # name, sed program applied to the bridge
    cp "$BRIDGE" "$tmp/b.swift"; cp "$MEDIA" "$tmp/m.swift"
    perl -0pi -e "$2" "$tmp/b.swift"
    if ( run_checks "$tmp/b.swift" "$tmp/m.swift" ) >/dev/null 2>&1; then
      echo "✗ self-test: mutation '$1' SURVIVED — this guard proves nothing"; exit 1
    fi
    ok=$((ok + 1))
  }
  # 1. The 2026-07-29 regression itself: the reader stops opening the scope.
  probe "thumbnail drops its scope" \
    's/(func thumbnail\(.*?\n.*?\n.*?\n)            let scoped = folder\.startAccessingSecurityScopedResource\(\)\n/$1/s'
  # 2. The same, one function over — a mutation must not pass because its
  #    SIBLING is still correct, which is how a loose grep scores a broken tree.
  probe "ocrRead drops its scope" \
    's/(func ocrRead\(.*?\n.*?\n.*?\n)            let scoped = folder\.startAccessingSecurityScopedResource\(\)\n/$1/s'
  # 3. A leaked scope: opened, never closed.
  probe "a reader never closes its scope" \
    's/(func thumbnail\(.*?\n.*?\n.*?\n.*?\n)            defer \{ if scoped \{ folder\.stopAccessingSecurityScopedResource\(\) \} \}\n/$1/s'
  # 4. A call site stops handing the folder over.
  probe "heal stops passing the folder to a reader" \
    's/await ocrRead\(url: fileURL, folder: folder\)/await ocrRead(url: fileURL)/s'
  # And the real tree must PASS, or every red above is red for the wrong reason.
  ( run_checks "$BRIDGE" "$MEDIA" ) >/dev/null 2>&1 \
    || fail "self-test: the unmutated tree fails its own checks"
  echo "✓ files-scope self-test: $ok mutations caught, clean tree passes"
  exit 0
fi

run_checks "$BRIDGE" "$MEDIA"
echo "✓ files-scope: both image reads own their security scope (2 readers, 4 call sites)"
