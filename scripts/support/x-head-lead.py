#!/usr/bin/env python3
"""The X room head must LEAD with `XRoom.note` (prd §451, 2026-08-22).

`XRoom.headline` stood in that slot and named the busiest year and its post
count — which `XRoom.rows` puts one line below verbatim (row one IS `busiest`,
same sort, same tie rule) and the year strip draws as its only full-height
capsule. It was cut; the note took its tier.

A `grep` for the absence of `headline` is only half a guard: a card that
dropped the headline and left the note at `subhead13` compiles, passes that
half, and renders a room head with no lead at all. This asserts the promotion
itself. Comments are stripped first, because the card documents the cut by
naming the tier it moved FROM (the Obsidian/Cursor lesson).
"""
import re
import sys

path = sys.argv[1]
src = re.sub(r'//.*', '', open(path).read())
ok = re.search(r'Text\(XRoom\.note\(room\)\)\s*\n\s*\.dsText\(\.heading22\)', src)
print("  ✓ the X room head leads with the note"
      if ok else "  ✗ the X room head no longer leads with the note (§451)")
sys.exit(0 if ok else 1)
