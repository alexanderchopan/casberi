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

Re-pointed for prd §745: the card hands `DSRoomChassis.Head` a `Lead`, and the
template's `LeadView` draws every `.sentence` lead at `heading22`. So both halves
are asserted — the card passes the note as the lead, and the template still
draws a sentence lead at the head rung.
"""
import re
import sys
from pathlib import Path

path = sys.argv[1]
src = re.sub(r'//.*', '', open(path).read())
template = Path(__file__).resolve().parents[2] / "Casberi/Casberi/Design/DSRoomHead.swift"
tsrc = re.sub(r'//.*', '', template.read_text()) if template.exists() else ""

card_ok = re.search(r'lead:\s*\.sentence\(XRoom\.note\(room\)\)', src)
rung_ok = re.search(r'case \.sentence\(let sentence\):\s*\n\s*Text\(verbatim: sentence\)\s*\n\s*\.dsText\(\.heading22\)', tsrc)
ok = bool(card_ok and rung_ok)
print("  ✓ the X room head leads with the note"
      if ok else "  ✗ the X room head no longer leads with the note at the head rung (§451/§745)")
sys.exit(0 if ok else 1)
