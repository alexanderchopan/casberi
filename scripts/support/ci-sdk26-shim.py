#!/usr/bin/env python3
"""ci-sdk26-shim — let the branch build compile on a runner with no iOS 27 SDK.

The tree calls iOS 27-only API behind `if #available(iOS 27.0, *)`, and
`#available` guards the RUNTIME, not the compiler: an older SDK has no such
symbols, so the build fails before it can check anything else. GitHub's
macOS runners carry Xcode 26 only (measured 2026-09-29: 26.0 through 26.6).

This rewrites THE RUNNER'S CHECKOUT, never the repo: every
`if … #available(iOS 27…) { … }` block becomes `if false { fatalError() }`,
brace-matched, so an `else` after it stays valid and a `let` assigned in both
branches is still definitely initialized. What it hides is exactly the code
an iOS 26 SDK cannot see; everything else is compiled as written.

Usage: scripts/support/ci-sdk26-shim.py <dir>   (prints each file it touched)
"""
import re
import sys
from pathlib import Path

GATE = re.compile(r'\bif\b[^{\n]*#available\(iOS 27[^{\n]*\{')



def shim(src: str) -> tuple[str, int]:
    out, count, i = [], 0, 0
    while True:
        m = GATE.search(src, i)
        if not m:
            out.append(src[i:])
            return ''.join(out), count
        depth, j = 1, m.end()
        while depth and j < len(src):
            c = src[j]
            if c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
            j += 1
        out.append(src[i:m.start()])
        out.append('if false { fatalError() }')
        count += 1
        i = j


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == '--self-test':
        sample = ('let r: Int\nif #available(iOS 27.0, *), let x { r = 1; if y { z() } } else { r = 2 }\n'
                  'if a, #available(iOS 27.0, *) {\n return 3\n}\n')
        got, n = shim(sample)
        want = ('let r: Int\nif false { fatalError() } else { r = 2 }\n'
                'if false { fatalError() }\n')
        ok = n == 2 and got == want and shim('if #available(iOS 26.0, *) { a() }')[1] == 0
        print('ci-sdk26-shim self-test:', 'ok' if ok else f'FAILED\n{got!r}')
        return 0 if ok else 1
    root = Path(sys.argv[1] if len(sys.argv) > 1 else '.')
    for path in sorted(root.rglob('*.swift')):
        text = path.read_text()
        new, n = shim(text)
        if n:
            path.write_text(new)
            print(f'shimmed {path} ({n})')
    return 0


if __name__ == '__main__':
    sys.exit(main())
