#!/usr/bin/env python3
"""Content key for a pure-logic harness — the input to `verify.sh`'s skip cache.

WHY. The 51 harnesses are ~600 optimizing `swiftc` runs and they are PURE: the
same harness script over the same source bytes produces the same verdict every
time. So a harness whose script and whose every input file are byte-identical
to a run that PASSED has nothing new to say, and re-running it is the largest
avoidable cost in the pass.

THE KEY IS THE WHOLE SAFETY ARGUMENT, because the failure mode here is a FALSE
GREEN — a source that changed, a harness that was skipped, a pass that prints ✓
over it. So the key covers, and must keep covering:

  * the harness script itself, whole (its stubs, fixtures and mutations are
    written inline, so any change to what it CHECKS changes the key), and
  * every repo file the harness NAMES, whole — not just `.swift`:
    `notify-selftest` reads both entitlements files, and the §383 rule it
    guards is exactly "the code may claim the level only while the key is
    there", which lives in the entitlements and not in Swift, and
  * the Swift compiler version, so a toolchain change re-runs everything.

STATED CEILING, because a check whose limits are not written down gets trusted
past them: this proves the harness's INPUTS are unchanged, never that the input
SET is complete. A harness that read a source file it does not name would be
under-covered, and the cache would skip it after that file changed. That is why
extraction is permissive (any `Casberi/`, `docs/` or `website/` path, any
extension, `$ROOT/`-prefixed or not) and then filtered by what really exists on
disk: over-hashing is free and under-hashing is the bug. Measured 2026-08-19:
all 52 harnesses name their inputs as literal paths, and none yields an empty
set — a harness that DID would be run unconditionally rather than trusted.

`verify.sh` prints every skip and `VERIFY_NO_CACHE=1` disables the cache
outright; CI and the nightly run with it set, so no unattended pass is ever
served a cached verdict.
"""
import hashlib, os, re, subprocess, sys

# Permissive on purpose — `os.path.isfile` below is the real filter, so a
# candidate that is a temp path, a comment fragment or a word inside a string
# simply drops out. Under-matching is the only direction that can hurt.
PATH = re.compile(r'(?<![A-Za-z0-9_.-])(?:Casberi|docs|website|scripts)/[A-Za-z0-9/_.+-]+\.[A-Za-z0-9]+')


def swift_version() -> str:
    try:
        return subprocess.run(['xcrun', 'swiftc', '--version'],
                              capture_output=True, text=True, timeout=30).stdout.strip()
    except Exception:
        return 'unknown'


def inputs_for(harness: str, root: str) -> list:
    """Every repo file the harness names, that exists. Sorted for determinism."""
    text = open(harness, encoding='utf-8', errors='replace').read()
    found = set()
    for rel in PATH.findall(text):
        if os.path.isfile(os.path.join(root, rel)):
            found.add(rel)
    return sorted(found)


def key_for(harness: str, root: str, salt: str) -> tuple:
    ins = inputs_for(harness, root)
    h = hashlib.sha256()
    h.update(salt.encode())
    h.update(open(harness, 'rb').read())
    for rel in ins:
        h.update(rel.encode())          # the NAME too: a rename must re-run
        with open(os.path.join(root, rel), 'rb') as f:
            h.update(f.read())
    return h.hexdigest()[:32], len(ins)


def self_test() -> int:
    import tempfile, shutil
    tmp = tempfile.mkdtemp()
    try:
        root = os.path.join(tmp, 'repo')
        os.makedirs(os.path.join(root, 'Casberi/Casberi/Model'))
        src = os.path.join(root, 'Casberi/Casberi/Model/Foo.swift')
        open(src, 'w').write('let a = 1\n')
        hp = os.path.join(tmp, 'demo-selftest.sh')
        open(hp, 'w').write('SRC="$ROOT/Casberi/Casberi/Model/Foo.swift"\necho hi\n')

        k0, n0 = key_for(hp, root, 'salt')
        assert n0 == 1, f'the $ROOT-prefixed path must be found, got {n0}'

        # 1. stable across calls
        assert key_for(hp, root, 'salt')[0] == k0, 'key must be deterministic'

        # 2. a changed INPUT changes the key (the whole point)
        open(src, 'w').write('let a = 2\n')
        assert key_for(hp, root, 'salt')[0] != k0, 'a changed source must change the key'
        open(src, 'w').write('let a = 1\n')
        assert key_for(hp, root, 'salt')[0] == k0, 'restoring the source must restore the key'

        # 3. a changed HARNESS changes the key
        open(hp, 'a').write('# mutated\n')
        assert key_for(hp, root, 'salt')[0] != k0, 'a changed harness must change the key'
        open(hp, 'w').write('SRC="$ROOT/Casberi/Casberi/Model/Foo.swift"\necho hi\n')

        # 4. a changed TOOLCHAIN changes the key
        assert key_for(hp, root, 'other')[0] != k0, 'a changed swift version must change the key'

        # 5. a RENAME changes the key even at identical bytes
        src2 = os.path.join(root, 'Casberi/Casberi/Model/Bar.swift')
        os.rename(src, src2)
        open(hp, 'w').write('SRC="$ROOT/Casberi/Casberi/Model/Bar.swift"\necho hi\n')
        assert key_for(hp, root, 'salt')[0] != k0, 'a rename must change the key'
        os.rename(src2, src)

        # 6. a file the harness does NOT name is not in the key — the stated
        #    ceiling, asserted so it can never be mistaken for coverage
        open(hp, 'w').write('SRC="$ROOT/Casberi/Casberi/Model/Foo.swift"\necho hi\n')
        other = os.path.join(root, 'Casberi/Casberi/Model/Unnamed.swift')
        open(other, 'w').write('let z = 9\n')
        assert key_for(hp, root, 'salt')[0] == k0, \
            'a file the harness never names must not be in its key (documented ceiling)'

        # 7. an unresolvable/temp path contributes nothing
        open(hp, 'w').write('SRC="$ROOT/Casberi/Casberi/Model/Foo.swift"\ncat "$TMP/main.swift"\n')
        assert key_for(hp, root, 'salt')[1] == 1, 'a temp path must not count as an input'
        print('harness-key: OK — 7 self-tests (determinism, source, harness, toolchain, '
              'rename, the unnamed-file ceiling, temp paths)')
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    if '--self-test' in sys.argv:
        sys.exit(self_test())
    root = os.environ.get('H_ROOT') or os.getcwd()
    salt = swift_version()
    for harness in sys.argv[1:]:
        k, n = key_for(harness, root, salt)
        print(f'{os.path.basename(harness)}\t{k}\t{n}')
