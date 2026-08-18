#!/usr/bin/env python3
"""`XArchiveImport.run`'s category shape (2026-08-18, prd §396).

Two facts a grep can't state on its own, both of which fail invisibly:

  · the account's own beginning and its renames are LANDED at all;
  · and neither of them sets `foundAnyCategory`.

The second is the load-bearing one. `account.js` is in every archive and in
nothing else, so counting it as a category makes "this isn't an X archive at
all" unreachable — any folder holding one file would import as a success with
nothing in it, and the screen would say "nothing new" instead of saying the
pick was wrong.

Comments are stripped before anything is matched: this file's own source
documents the rule by naming the flag, which is the guard-fires-on-the-prose
trap this repo has now paid for three times.
"""
import re
import sys


def main(path: str) -> int:
    src = open(path, encoding="utf-8").read()
    try:
        body = src[src.index("static func run(folder"):src.index("private static func finish")]
    except ValueError:
        print("✗ XArchiveImport.run could not be located")
        return 1
    body = re.sub(r"//.*", "", body)

    for call in ("landOrigin(", "landRenames(", "landApps("):
        if call not in body:
            print(f"✗ {call[:-1]} is never called from run — that category never lands")
            return 1

    # Everything after the likes read up to the origin landing is the new
    # block; exactly one category in it (the connected apps) may claim to be
    # one.
    start = body.index("landLikes(data")
    segment = body[start:body.index("landOrigin(")]
    claims = segment.count("foundAnyCategory = true")
    if claims != 1:
        print("✗ account.js now counts as a category — "
              "'this isn't an X archive' became unreachable "
              f"({claims} category claims after the likes read, expected 1)")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1
                  else "Casberi/Casberi/Model/XArchiveImport.swift"))
