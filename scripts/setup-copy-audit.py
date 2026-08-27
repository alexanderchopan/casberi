#!/usr/bin/env python3
"""Connect-page copy audit (prd §315, 2026-08-06).

WHY THIS EXISTS. The connect screens have now been de-walled TWICE. §218b ruled
"one gray sentence per screen"; by §314 the import screens carried five notes
totalling ~130 words. §314 gave the family a staged shape and a single footer;
by §315 that footer was up to a lede plus four bullets plus a detail paragraph,
and Instagram's connect page ran ~145 words before you had done anything —
reported by the user, again, as *"really wordy and bad with text in different
places"*.

The lesson this repo already writes down everywhere else applies here: a rule
that lives in memory loses. Every other load-bearing rule in CLAUDE.md is a
script. The design system got its first mechanical check in §299 for exactly
this reason. This is the copy equivalent.

SEVEN CHECKS, all static — no build, no simulator:

  1. DECLARED MODE — every connect screen's `BridgeSetupHeader` names a `mode:`.
     The mode is the fact the whole pass exists to surface (does anything arrive
     on its own?), so a screen that omits it has silently opted out.
  2. INTRO BUDGET — the intro is at most MAX_INTRO_SENTENCES sentences and
     MAX_INTRO_WORDS words. This is the whole prose budget of the screen.
  3. STEP BUDGET — a `BridgeStepLines` step is at most MAX_STEP_WORDS words.
     Steps say what to DO; reasons belong in error copy, which is the only
     place they can be acted on.
  4. NOTE COUNT — at most MAX_SLAB_NOTES `DSSlabNote`s per screen, because
     `DSSlabNote`'s own doc says "every manage page gets exactly one" and the
     family has drifted past that twice. Screens serving several bridges get a
     documented allowance in `NOTE_ALLOWANCE`.
  5. NO FOOTER WALL — `BridgeFooterNote` is deleted and must not come back
     under a new name: a `Section { … } footer:` closure on a setup screen
     carrying more than FOOTER_WORD_FLOOR words is the same wall rebuilt.
  6. DOOR IS A VERB — a door's big words say what you will GET, never the route
     you will take. The address rides `detail:` under the verb, and a tab trail
     belongs in the step that follows. See the DOOR section below.
  7. EVERY CONNECT SCREEN HAS A ROOM DOOR, and it opens a real room — every `source:` a `RoomDoor` names
     must be a string some bridge really stamps as `Thing.source`, and every
     `TokenBridge` rawValue must be one too (that enum's `source` forwards it
     for the whole paste-a-token family). See the ROOM DOOR section below.

Run standalone, or via `scripts/verify.sh`'s static head. `--self-test` proves
each check catches its own shape before it certifies the tree — a check that
cannot fail proves nothing (the liveness-audit contract).

DELIBERATE NON-CHECKS, so nobody "improves" this into a lint that cries wolf
and gets turned off within a week:

  · It does not read the intro for QUALITY. It cannot tell a true sentence from
    a false one, and pretending otherwise would be the fake status §83 bans.
  · It does not require an intro at all when there is no `BridgeSetupHeader`.
    `StocktwitsScreen` has none by ruling (§185) and carries its honesty fact
    on the slab note beside the field instead — a real design decision, not an
    omission.
  · It does not count words in `canLine`/`summary`. Those are the CONNECTED
    state and the product page, read in different places for different reasons,
    and holding a capability line to a connect page's budget would delete true
    differentiating information (the §192 ruling).
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCREENS = os.path.join(ROOT, "Casberi", "Casberi", "Screens")
MODEL = os.path.join(ROOT, "Casberi", "Casberi", "Model")

# Budgets. Each is a MEASURED ceiling, not a round number picked from
# intuition — see the header for what the screens actually looked like when
# they were reported. Raising one is a product decision, so raise it here and
# say why, rather than adding an exemption per screen.
MAX_INTRO_SENTENCES = 2
MAX_INTRO_WORDS = 55
MAX_STEP_WORDS = 14
MAX_SLAB_NOTES = 2
FOOTER_WORD_FLOOR = 25

# Screens serving SEVERAL bridges from one file legitimately carry more than
# one note, because the notes belong to different forms on different branches.
# An entry here is a conscious ruling that the notes are not stacked on one
# screen at one time, never a snooze.
NOTE_ALLOWANCE = {
    # GitHub's sign-in path, the manual token path, the feed picker and the
    # private-watch field are four separate forms; at most two are ever on
    # screen together.
    # Trello's two-stage form (key, then token) plus the shared keychain note.
    # Counted above.
    # Jira's own two-stage form (site+email, then token) adds a fifth note
    # (2026-08-08) — its own branch, never on screen at the same time as
    # Trello's or GitHub's, the same "not stacked" ruling this dict exists
    # to record.
    "TokenSetupScreen.swift": 6,
    "HandleSetupScreen.swift": 3,
    # Day One, Apple Journal, Apple Notes and Bookmarks are four screens in
    # one file.
    "NotesImportScreens.swift": 4,
    # The screen has a connect form and a connected state with separate notes.
    "DropboxScreen.swift": 3,
    "PostHogScreen.swift": 3,
}

# Files that hold a `BridgeSetupHeader` call but are not connect screens, or
# are shared components rather than a screen.
SKIP = {"BridgeSetupComponents.swift", "ImportSetupComponents.swift"}


# ── parsing helpers ────────────────────────────────────────────────────────

def strip_comments(src: str) -> str:
    """Comments quote old copy verbatim (this repo documents what it deleted),
    so counting words in them would flag a screen for its own changelog."""
    out, i, n = [], 0, len(src)
    while i < n:
        if src.startswith("//", i):
            j = src.find("\n", i)
            i = n if j < 0 else j
        elif src.startswith("/*", i):
            j = src.find("*/", i + 2)
            i = n if j < 0 else j + 2
        elif src[i] == '"':
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == '"':
                    j += 1
                    break
                j += 1
            out.append(src[i:j])
            i = j
        else:
            out.append(src[i])
            i += 1
    return "".join(out)


def balanced(src: str, open_at: int) -> str:
    """The text inside the parens/braces starting at `open_at`, string-aware —
    a naive depth counter trips on a `)` inside copy, which most of this copy
    has."""
    opener = src[open_at]
    closer = {"(": ")", "{": "}", "[": "]"}[opener]
    depth, i, n = 1, open_at + 1, len(src)
    instr = False
    while i < n and depth:
        ch = src[i]
        if instr:
            if ch == "\\":
                i += 2
                continue
            if ch == '"':
                instr = False
        elif ch == '"':
            instr = True
        elif ch == opener:
            depth += 1
        elif ch == closer:
            depth -= 1
        i += 1
    return src[open_at + 1:i - 1]


def literals(src: str):
    """Every Swift string literal, unescaped enough to count words in."""
    found = re.findall(r'"((?:[^"\\\n]|\\.)*)"', src)
    return [f.replace('\\"', '"').replace("\\n", " ") for f in found]


def words(text: str) -> int:
    # Interpolations are one word when rendered ("\(DS.device)" → "iPhone").
    return len(re.sub(r"\\\([^)]*\)", "X", text).split())


def sentences(text: str) -> int:
    text = re.sub(r"\\\([^)]*\)", "X", text).strip()
    return len([s for s in re.split(r"(?<=[.!?])\s+", text) if s.strip()])



# ── the catalog offer's own budget (added 2026-08-06) ──────────────────────
#
# The connect SCREEN had a budget and the catalog SUMMARY did not, so the same
# sprawl the §315 rules pushed off the screen simply moved one surface over.
# The Apple Wallet offer landed at 131 words in 4 paragraphs — three times the
# median and half again the longest legitimate entry — and nothing could see it.
#
# MEASURED, not chosen (2026-08-06, over the 91 offers that carry a summary):
# median 43 words, p90 75, longest real entry 88 (Gnosis Pay). So the ceiling is
# 90 — above every offer written to date, which means it flags NEW sprawl and
# never re-litigates copy the user already approved. Paragraphs cap at 3, the
# median and the observed maximum.
#
# What it deliberately does NOT check: the QUALITY of a sentence (it cannot
# tell a true one from a false one), the tagline (already one short phrase by
# construction), or the ceilings an offer must state — an honest caveat is
# exactly what a word budget must never squeeze out, which is why the ceiling
# sits above the longest honest entry rather than at the median.
OFFER_MAX_WORDS = 90
OFFER_MAX_PARAGRAPHS = 3
CATALOG = os.path.join(ROOT, "Casberi", "Casberi", "Model", "BridgeCatalog.swift")

# ── the door's own budget (check 6, added 2026-08-14) ──────────────────────
#
# A door's label is a VERB, never a route. It shipped as both: `setupURLLabel`
# put the host AND the tab trail inside the button's big words, so the slab
# read "Open dashboard.stripe.com → API keys" (35 chars) and, at worst,
# "Open pagerduty.com → Integrations → API Access Keys" (51) — reported by the
# user as *"a lot of the CTAs barely fit in their button"*, with a screenshot.
#
# The fix was anatomical, not a shorter string: `DSSlabButton` gained a
# `detail:` subline, so the verb stays short on top and the address sits quiet
# underneath — still on the button, so the door remains checkable against the
# address bar it opens (the honesty rule `setupURLLabel` existed to serve), and
# `doorHost` DERIVES it from `setupURL` so it can never drift from where the
# door goes. The trail moved into the step that follows, or vanished where the
# URL lands on the tab directly.
#
# The check is mechanical for the reason every other rule here is: this family
# has been de-walled three times now (§218b, §314, §315) and each ruling was
# re-broken from memory. THREE sub-rules, each naming a distinct way a route
# gets back into the big words:
#
#   · a route ARROW — a trail is navigation, and navigation belongs in a step;
#   · a HOSTNAME — the address has a slot of its own now (`detail:`);
#   · LENGTH — the backstop for a label that is neither, and the one that
#     catches a verb which simply grew.
#
# MEASURED, not chosen: over every door on a connect screen today the longest
# legitimate label is "Choose conversations.json" at 25 characters, so the
# ceiling is 26 — above every label written to date, which means it flags NEW
# sprawl and never re-litigates copy that already reads fine. Translations are
# NOT the reason for the ceiling (German would blow any number, which is what
# `minimumScaleFactor` is for); the ceiling is about the ENGLISH source being a
# verb rather than a route.
#
# What it deliberately does NOT check: whether the verb is a GOOD one (it
# cannot tell "Get your API key" from "Do the thing"), and it says nothing
# about `detail:`, which is derived from a URL in every case that matters and
# is free to be as long as the address is.
MAX_DOOR_CHARS = 26
# A dotted token with a real TLD tail — never a filename, so "Choose
# conversations.json" and "Choose the .p8 file" stay clean. Extending this list
# is fine; making it `\.[a-z]{2,}` is not, and would flag both of those.
DOOR_HOST_RE = re.compile(
    r"\b[a-z0-9][a-z0-9-]*\.(?:com|org|net|io|ai|app|dev|co|xyz|bot|so|sh|me|gg|tv)\b")
# Where door verbs live outside the screens: the two tables that serve many
# screens at once, so one bad entry is many bad buttons.
DOOR_TABLES = [
    os.path.join(ROOT, "Casberi", "Casberi", "Model", "TokenBridges.swift"),
    os.path.join(ROOT, "Casberi", "Casberi", "Model", "MailBridge.swift"),
]


# `\(walletCount)` is 14 characters of SOURCE and one digit on screen. Counting
# the raw literal made four correct wallet screens the check's first findings —
# the cry-wolf shape this file's header warns about — so an interpolation is
# measured as a short substitution instead. Deliberately a guess: what it really
# renders is unknowable statically, and the ceiling is about the AUTHORED words
# being a verb rather than about predicting a count's width.
DOOR_INTERPOLATION_RE = re.compile(r"\\\([^)]*\)")
DOOR_INTERPOLATION_WIDTH = 3


def audit_door_title(where: str, title: str):
    """The three sub-rules, applied to one door label."""
    findings = []
    if "→" in title:
        findings.append(f"{where}: door says “{title}” — a route trail "
                        f"belongs in the step below, not in the button's big words")
    if DOOR_HOST_RE.search(title.lower()):
        findings.append(f"{where}: door says “{title}” — the address "
                        f"belongs in `detail:` under the verb, not inside it")
    rendered = DOOR_INTERPOLATION_RE.sub("x" * DOOR_INTERPOLATION_WIDTH, title)
    if len(rendered) > MAX_DOOR_CHARS:
        findings.append(f"{where}: door label is {len(rendered)} chars "
                        f"(max {MAX_DOOR_CHARS}) — “{title}”")
    return findings


def audit_doors(name: str, body: str):
    """Door labels written as literals on a screen."""
    findings = []
    pattern = (r'(?:DSSlab(?:Button|Door)\(\s*title:|doorTitle:)\s*'
               r'(?:String\(localized:\s*)?"((?:[^"\\]|\\.)*)"')
    for m in re.finditer(pattern, body):
        findings += audit_door_title(name, m.group(1).replace('\\"', '"'))
    return findings


def audit_door_table(name: str, body: str):
    """Door verbs held in a `doorTitle` property serving many screens."""
    findings = []
    m = re.search(r"var doorTitle:\s*String\s*\{", body)
    if not m:
        return findings
    for lit in literals(balanced(body, m.end() - 1)):
        findings += audit_door_title(name, lit)
    return findings


# ── the room door (check 7, 2026-08-24) ────────────────────────────────────
#
# TWO HALVES, and the SECOND one is the one that was missing. §460 shipped the
# door to seventeen call sites and called it done; the user asked "you only did
# 17? but we have like 90 apps" and the honest answer was that seventeen was a
# count of CALL SITES, not of coverage — thirty-four connect screens still had
# no door at all. A per-door correctness check cannot see an ABSENT door, which
# is exactly the class that shipped. So completeness is checked too, and a
# screen that should not have one says so by name with a reason.
#
# `RoomDoor` pops the pushed stack and asks `MainSurface.go(to:)`
# for a source. Hand it a string no bridge stamps and NOTHING ERRORS: the pop
# happens, the filter is written, and you land in a room that will never hold
# a row — a tap that looks like it worked and didn't, on the one control whose
# whole job is "your things are through here". That is §83 exactly, and it is
# invisible to the build, to the screen sweep and to every other check here.
#
# The trap is specific and already present in the tree: the CATALOG name and
# the SOURCE differ where a seat is branded more fully than it is stamped
# ("0xBow Privacy Pools" vs `source: "Privacy Pools"`), and the note's `name:`
# is the catalog one. Passing `name` for `source` is the natural mistake.
#
# THE CEILING, stated rather than implied: only a LITERAL can be resolved from
# text. A `source:` forwarding a constant (`SafeBridge.sourceName`,
# `VibenetIdentity.source`, `registry.displayName`) is skipped — and that is
# the RIGHT answer, not a gap, because one constant used by both the stamp and
# the door is the pattern that cannot drift at all (§311's own lesson: the
# desync happened because a second file hardcoded the literal instead).
# A source can be REAL and still have no room: `Corpus.searchOnlySources`
# (Contacts, HomeKit) and `chiplessSources` ("You") are stamped on rows and
# deliberately earn no chip and no room — `Corpus.earnsRoom` is the one place
# that answer is declared. A door onto one of those passes the "is it stamped"
# test and still lands nowhere, so it is checked separately and read OUT of
# Thing.swift rather than copied here, or this goes stale the day the rule moves.
NO_ROOM_SET_RE = re.compile(
    r'static let (?:chiplessSources|searchOnlySources): Set<String> = \[([^\]]*)\]')
SOURCE_LITERAL_RE = re.compile(r'source:\s*"([^"]+)"')
SOURCE_CONST_RE = re.compile(r'static let source(?:Name)?\s*=\s*"([^"]+)"')
CHIP_SOURCE_RE = re.compile(r'RoomDoor\((?:[^()]|\([^()]*\))*?source:\s*"([^"]+)"',
                            re.S)


def stamped_sources(model_dir: str) -> set:
    """Every string the bridges really stamp as `Thing.source`.

    Both spellings, because roughly half the bridges land through a literal
    and half through a `sourceName` constant — reading only one form reports
    perfectly correct doors (Railgun, Safe, L2BEAT) as broken, and a lint that
    cries wolf gets turned off within a week.
    """
    found = set()
    for fn in sorted(os.listdir(model_dir)):
        if not fn.endswith(".swift"):
            continue
        body = strip_comments(open(os.path.join(model_dir, fn)).read())
        found |= set(SOURCE_LITERAL_RE.findall(body))
        found |= set(SOURCE_CONST_RE.findall(body))
    return found


# Screens with a `BridgeSetupHeader` and deliberately NO room door. Each entry
# is a conscious ruling, never a snooze — the door is missing because there is
# no room to open, not because nobody got to it.
KNOWN_NO_ROOM_DOOR = {
    # The four BYOK agent-key screens. These configure the AGENT, not a source:
    # they store a key and register a seat, and land no `Thing` at all — there
    # is no source string, so there is nothing for a door to open. Verified: no
    # `source: "Bankr"/"Grok"/"Venice"` literal exists anywhere in Model/.
    "BankrSetupScreen.swift": "agent key — lands no rows, so there is no room",
    "GrokSetupScreen.swift": "agent key — lands no rows, so there is no room",
    "VeniceSetupScreen.swift": "agent key — lands no rows, so there is no room",
    # OpenRouter is the near-miss and the reason this list carries reasons
    # rather than names: `AgentSpend.drainPending` DOES land one `.reminder`
    # under source "OpenRouter" — the credits-running-low alert — so check 7a
    # would happily pass a door here. But that is the only producer, so the
    # room is empty for the life of the install and then holds exactly one
    # row. A door onto that is the §83 dead control with a long fuse.
    "OpenRouterSetupScreen.swift": "agent key — its only row is a credits alert",
    # Two seats whose money is REAL and whose rows do not exist: both fold
    # holdings into `WalletPortfolio` (the Wallet room's balance card) without
    # ever constructing a `Thing`. `Model/ExchangeBridge.swift` and
    # `Model/EthValidatorWatch.swift` contain zero `Thing(` between them. A
    # door would have to point at Wallet, where not one row is theirs.
    "ExchangeSetupScreen.swift": "holdings fold into the Wallet balance; lands no rows",
    "EthValidatorScreen.swift": "balances fold into the Wallet balance; lands no rows",
}

# STATED CEILING: this is per FILE, so a file holding several screens is
# satisfied by ONE door. `NotesImportScreens.swift` is the case in the tree —
# three of its four screens have a door and `NotesShareScreen` correctly has
# none (a note shared out of Apple Notes lands under source "You", which
# `Corpus.earnsRoom` refuses). Splitting this per struct means parsing Swift;
# the honest move is to say so rather than imply a guarantee it cannot make.


def audit_door_presence(name: str, body: str):
    """Check 7b — a connect screen offers the way back to its things."""
    if "BridgeSetupHeader(" not in body:
        return []                      # §185 screens; check 1 already rules here
    if "RoomDoor(" in body:
        return []
    if name in KNOWN_NO_ROOM_DOOR:
        return []
    return [f"{name}: no RoomDoor — a connect screen states where your things "
            f"went and gives no way there (§460). Add one, or name the screen "
            f"in KNOWN_NO_ROOM_DOOR with the reason it has no room."]


def roomless_sources(thing_swift: str) -> set:
    """The sources `Corpus.earnsRoom` answers NO for."""
    out = set()
    for block in NO_ROOM_SET_RE.findall(thing_swift):
        out |= set(re.findall(r'"([^"]+)"', block))
    return out


def audit_room_doors(name: str, body: str, stamped: set, roomless: set = frozenset()):
    findings = []
    for src in CHIP_SOURCE_RE.findall(body):
        if src in roomless:
            findings.append(f"{name}: room door opens “{src}”, which Corpus."
                            f"earnsRoom refuses — that source is stamped but has "
                            f"no chip and no room, so the door lands nowhere")
        elif src not in stamped:
            findings.append(f"{name}: room door opens “{src}”, which no bridge "
                            f"stamps as Thing.source — the room will always be "
                            f"empty (did you pass the catalog name?)")
    return findings


# ── the seat that opens a room (check 7c, 2026-08-26) ──────────────────────
#
# `BridgeRouter.roomSource(forID:)` is `RoomDoor` reached from the other side:
# a connected catalog seat with no screen of its own opens the ROOM its rows
# land in, by popping the stack and asking `MainSurface.go(to:)` for a source.
# So it inherits check 7a's failure mode EXACTLY — hand it a string no bridge
# stamps and nothing errors, the pop happens, the filter is written, and the
# tile lands you in a room that will never hold a row. The natural mistake is
# the same one: passing the CATALOG name ("0xBow Privacy Pools", "Gnosis Pay")
# where the bridge stamps something else.
#
# Two more halves that only exist on this side of the door:
#
#   · The SEAT ID must be a real one. A typo is not a crash and not an empty
#     room — `roomSource` simply answers nil and Open pushes the wallet
#     manager, which is the behaviour this table was written to replace. The
#     feature silently reverts for that seat and looks exactly like shipping.
#   · A seat named here must route to `.wallet`. Listing one that owns a real
#     screen (Peer's fills, Safe's queue) makes that screen UNREACHABLE from
#     the catalog — the room opens instead, and it holds rows, so nothing
#     about it reads as broken.
#
# STATED CEILING, the same one check 7a states and for the same reason: only a
# LITERAL can be resolved from text. A case answering with a constant
# (`EtherFiCash.source`, `GnosisPayBridge.sourceName`) is skipped, and that is
# the right answer rather than a gap — one constant read by both the stamp and
# the door is the pattern that cannot drift at all (§311's lesson).
ROOM_SOURCE_FN_RE = re.compile(
    r'static func roomSource\(forID id: String\) -> String\? \{(.*?)\n    \}', re.S)
ROOM_SOURCE_CASE_RE = re.compile(r'^\s*case\s+(.+?):\s*(.+?)\s*$', re.M)
WALLET_SEAT_ID_RE = re.compile(r'WalletSeat\(id:\s*"([^"]+)"')
ROUTER_ROW_RE = re.compile(r'Row\(offer:\s*"[^"]*",\s*id:\s*"([^"]+)",\s*'
                           r'destination:\s*([.\w]+)')


def room_source_cases(routing_src: str):
    """Every (seat id, value expression) pair in `roomSource(forID:)`."""
    m = ROOM_SOURCE_FN_RE.search(routing_src)
    if not m:
        return None
    out = []
    for ids, value in ROOM_SOURCE_CASE_RE.findall(m.group(1)):
        if ids.strip() == "default":
            continue
        for sid in re.findall(r'"([^"]+)"', ids):
            out.append((sid, value.strip()))
    return out


def audit_seat_rooms(routing_src: str, store_src: str, stamped: set,
                     roomless: set = frozenset()):
    cases = room_source_cases(routing_src)
    if cases is None:
        return ["BridgeRouting.swift: BridgeRouter.roomSource(forID:) is gone — "
                "check 7c can no longer see which seats open a room"]
    seats = set(WALLET_SEAT_ID_RE.findall(store_src))
    rows = dict(ROUTER_ROW_RE.findall(routing_src))
    findings = []
    for sid, value in cases:
        if sid not in seats:
            findings.append(f"BridgeRouting.swift: roomSource names seat “{sid}”, "
                            f"which is not a WalletSeat id — Open silently falls "
                            f"back to pushing the wallet manager")
        if sid in rows and rows[sid] != ".wallet":
            findings.append(f"BridgeRouting.swift: seat “{sid}” routes to "
                            f"{rows[sid]}, a screen of its own — opening its room "
                            f"instead makes that screen unreachable")
        lit = re.fullmatch(r'"([^"]+)"', value)
        if not lit:
            continue                   # a constant — see the ceiling above
        src = lit.group(1)
        if src in roomless:
            findings.append(f"BridgeRouting.swift: seat “{sid}” opens “{src}”, "
                            f"which Corpus.earnsRoom refuses — the door lands "
                            f"nowhere")
        elif src not in stamped:
            findings.append(f"BridgeRouting.swift: seat “{sid}” opens “{src}”, "
                            f"which no bridge stamps as Thing.source — the room "
                            f"will always be empty (did you pass the catalog name?)")
    return findings


def audit_token_sources(tokens_src: str, stamped: set):
    """`TokenBridge.source` is `rawValue` for all of them — prove it.

    This is the whole paste-a-token family behind one property, so a new case
    whose bridge stamps something else would give ~18 screens' worth of door a
    silent hole with nothing else to catch it.
    """
    findings = []
    head = tokens_src.split("var id: String", 1)[0]
    for raw in re.findall(r'case\s+\w+\s*=\s*"([^"]+)"', head):
        if raw not in stamped:
            findings.append(f"TokenBridges.swift: TokenBridge “{raw}” is not "
                            f"stamped as Thing.source anywhere — `TokenBridge.source` "
                            f"returns rawValue, so its room door opens nothing")
    return findings


def audit_catalog(src: str):
    findings = []
    offers = 0
    for m in re.finditer(r'Offer\(name:\s*"([^"]+)".*?summary:\s*"((?:[^"\\]|\\.)*)"',
                         src, re.S):
        name, raw = m.group(1), m.group(2)
        offers += 1
        text = raw.replace('\\"', '"')
        paras = [p for p in text.split("\\n\\n") if p.strip()]
        w = words(text.replace("\\n", " "))
        if w > OFFER_MAX_WORDS:
            findings.append(f"{name}: summary is {w} words (max {OFFER_MAX_WORDS}) — "
                            f"the median offer is 43")
        if len(paras) > OFFER_MAX_PARAGRAPHS:
            findings.append(f"{name}: summary is {len(paras)} paragraphs "
                            f"(max {OFFER_MAX_PARAGRAPHS})")
    return findings, offers

# ── the checks ─────────────────────────────────────────────────────────────

def audit_source(name: str, src: str, stamped: set = None,
                 roomless: set = frozenset()):
    """Returns a list of finding strings for one screen's source text."""
    findings = []
    body = strip_comments(src)

    # 1 + 2: every header declares a mode, and its intro fits the budget.
    for m in re.finditer(r"BridgeSetupHeader\(", body):
        call = balanced(body, m.end() - 1)
        if "mode:" not in call:
            findings.append(f"{name}: BridgeSetupHeader with no `mode:` — "
                            f"every connect screen states how it connects")
            continue
        intro = re.search(r"intro:\s*(.*)", call, re.S)
        if not intro:
            continue
        for lit in literals(intro.group(1))[:1]:
            w, s = words(lit), sentences(lit)
            if w > MAX_INTRO_WORDS:
                findings.append(f"{name}: intro is {w} words "
                                f"(max {MAX_INTRO_WORDS}) — {lit[:60]}…")
            if s > MAX_INTRO_SENTENCES:
                findings.append(f"{name}: intro is {s} sentences "
                                f"(max {MAX_INTRO_SENTENCES}) — {lit[:60]}…")

    # 3: steps are instructions, not explanations.
    for m in re.finditer(r"BridgeStepLines\(", body):
        call = balanced(body, m.end() - 1)
        steps = re.search(r"steps:\s*\[", call)
        block = balanced(call, steps.end() - 1) if steps else call
        for lit in literals(block):
            w = words(lit)
            if w > MAX_STEP_WORDS:
                findings.append(f"{name}: step is {w} words "
                                f"(max {MAX_STEP_WORDS}) — {lit[:60]}…")

    # `steps:` passed as an array literal to `ImportArchiveSection` too.
    for m in re.finditer(r"ImportArchiveSection\(", body):
        call = balanced(body, m.end() - 1)
        steps = re.search(r"steps:\s*\[", call)
        if not steps:
            continue
        for lit in literals(balanced(call, steps.end() - 1)):
            w = words(lit)
            if w > MAX_STEP_WORDS:
                findings.append(f"{name}: step is {w} words "
                                f"(max {MAX_STEP_WORDS}) — {lit[:60]}…")

    # 4: the one-gray-sentence rule, mechanised.
    notes = len(re.findall(r"\bDSSlabNote\(", body))
    cap = NOTE_ALLOWANCE.get(name, MAX_SLAB_NOTES)
    if notes > cap:
        findings.append(f"{name}: {notes} DSSlabNotes (max {cap}) — "
                        f"fine print belongs beside its control or in error copy")

    # 5: the wall, rebuilt under a new name.
    if "BridgeFooterNote" in body:
        findings.append(f"{name}: BridgeFooterNote is deleted (§315) — "
                        f"the intro sentence replaced it")
    for m in re.finditer(r"\}\s*footer:\s*\{", body):
        block = balanced(body, m.end() - 1)
        total = sum(words(l) for l in literals(block))
        if total > FOOTER_WORD_FLOOR:
            findings.append(f"{name}: section footer carries {total} words "
                            f"(max {FOOTER_WORD_FLOOR}) — that is the wall again")

    # 6: the door is a verb, not a route.
    findings += audit_doors(name, body)

    # 7: the room door opens a room that exists.
    if stamped is not None:
        findings += audit_room_doors(name, body, stamped, roomless)
        findings += audit_door_presence(name, body)

    return findings


# ── self-test ──────────────────────────────────────────────────────────────

DIRTY_NO_MODE = '''
struct S: View { var body: some View { List {
    BridgeSetupHeader(name: "X", connected: true)
} } }
'''

DIRTY_LONG_INTRO = '''
struct S: View { var body: some View { List {
    BridgeSetupHeader(name: "X", mode: .noAccount,
        intro: "One two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty twentyone twentytwo twentythree twentyfour twentyfive twentysix twentyseven twentyeight twentynine thirty thirtyone thirtytwo thirtythree thirtyfour thirtyfive thirtysix thirtyseven thirtyeight thirtynine forty fortyone fortytwo fortythree fortyfour fortyfive fortysix fortyseven fortyeight fortynine fifty fiftyone fiftytwo fiftythree fiftyfour fiftyfive fiftysix.")
} } }
'''

DIRTY_MANY_SENTENCES = '''
struct S: View { var body: some View { List {
    BridgeSetupHeader(name: "X", mode: .noAccount,
        intro: "One sentence here. Two sentences here. Three sentences here.")
} } }
'''

DIRTY_LONG_STEP = '''
struct S: View { var body: some View { List {
    BridgeSetupHeader(name: "X", mode: .pasteKey, intro: "Short.")
    BridgeStepLines(steps: [
        "This step explains far too much about why the format matters and keeps going well past any reasonable budget.",
    ], startingAt: 2)
} } }
'''

DIRTY_FOOTER = '''
struct S: View { var body: some View { List {
    BridgeSetupHeader(name: "X", mode: .noAccount, intro: "Short.")
    Section { row } footer: {
        Text("Read-only: nothing here ever places a trade, and the odds are public.")
        Text("No account, no key — fetched directly by this device through each exchange's own public feed, with no ranking of ours applied anywhere.")
    }
} } }
'''

DIRTY_NOTES = '''
struct S: View { var body: some View { List {
    BridgeSetupHeader(name: "X", mode: .noAccount, intro: "Short.")
    DSSlabNote(text: "One.")
    DSSlabNote(text: "Two.")
    DSSlabNote(text: "Three.")
} } }
'''

CLEAN = '''
struct S: View { var body: some View { List {
    // A comment quoting the OLD wall verbatim, which must not be counted:
    // "One-time import — nothing arrives on its own afterwards, and
    // re-importing later adds only what's new, and your captions and comments
    // arrive as searchable text, and saves and likes arrive as links."
    BridgeSetupHeader(
        name: "X", mode: .oneTimeImport,
        intro: "X has no live connection — download your export, bring it here, and search everything in it. Re-import any time for what's new.")
    BridgeStepLines(steps: [
        "Choose Download or transfer information, then Some of your information.",
        "Set Format to JSON, not HTML, then Download to device.",
    ], startingAt: 2)
    DSSlabNote(text: "Your token stays in this iPhone's Keychain.")
} } }
'''


def self_test() -> bool:
    cases = [
        ("no mode declared", DIRTY_NO_MODE, "no `mode:`"),
        ("intro too long", DIRTY_LONG_INTRO, "words"),
        ("too many sentences", DIRTY_MANY_SENTENCES, "sentences"),
        ("step too long", DIRTY_LONG_STEP, "step is"),
        ("footer wall", DIRTY_FOOTER, "footer carries"),
        ("too many notes", DIRTY_NOTES, "DSSlabNotes"),
    ]
    ok = True
    for label, src, expect in cases:
        found = audit_source("fixture.swift", src)
        if not any(expect in f for f in found):
            print(f"  SELF-TEST FAIL: '{label}' was not caught "
                  f"(expected {expect!r}, got {found})")
            ok = False
        else:
            print(f"  ✓ catches {label}")
    clean = audit_source("fixture.swift", CLEAN)
    if clean:
        print(f"  SELF-TEST FAIL: clean fixture flagged — {clean}")
        ok = False
    else:
        print("  ✓ passes a clean screen (and ignores copy quoted in comments)")

    # The catalog budget's own fixtures. A check that cannot fail proves
    # nothing — and this one guards a rule that was broken the day it was
    # written (a 131-word, 4-paragraph offer), so it has to demonstrate it
    # catches both shapes and clears an ordinary entry.
    long_summary = " ".join(["word"] * (OFFER_MAX_WORDS + 5))
    dirty_words = f'Offer(name: "Bloaty", tagline: "x", group: "g", connectable: true, summary: "{long_summary}", needsSetup: true),'
    f, _ = audit_catalog(dirty_words)
    if not any("words" in x for x in f):
        print(f"  SELF-TEST FAIL: an over-long summary was not caught — {f}")
        ok = False
    else:
        print("  ✓ catches an over-long catalog summary")

    dirty_paras = 'Offer(name: "Wally", tagline: "x", group: "g", connectable: true, summary: "One.\\n\\nTwo.\\n\\nThree.\\n\\nFour.", needsSetup: true),'
    f, _ = audit_catalog(dirty_paras)
    if not any("paragraphs" in x for x in f):
        print(f"  SELF-TEST FAIL: a 4-paragraph summary was not caught — {f}")
        ok = False
    else:
        print("  ✓ catches a catalog summary with too many paragraphs")

    clean = 'Offer(name: "Tidy", tagline: "x", group: "g", connectable: true, summary: "Lands your things.\\n\\nNo account, no key.\\n\\nRead-only.", needsSetup: true),'
    f, n = audit_catalog(clean)
    if f or n != 1:
        print(f"  SELF-TEST FAIL: an ordinary offer was flagged — {f} (parsed {n})")
        ok = False
    else:
        print("  ✓ passes an ordinary catalog offer")

    # The door's fixtures. Each dirty one is a REAL label this shipped with, so
    # the check is proven against the exact strings that were reported rather
    # than against invented ones — and each clean one is a label the tree
    # carries today, because the way this lint dies is by crying wolf.
    door_cases = [
        ("a route arrow in the big words",
         'DSSlabButton(title: "Open dashboard.stripe.com → API keys", systemImage: "x") { }',
         "route trail"),
        ("a host inside the verb",
         'DSSlabButton(title: "Approve on twitch.tv/activate", systemImage: "x") { }',
         "belongs in `detail:`"),
        ("a verb that simply grew",
         'DSSlabDoor(title: "Open the page where your key lives", systemImage: "x") { }',
         "chars"),
        ("a long door passed to the import family",
         'ImportArchiveSection(source: "X", doorTitle: "Open x.com → Your account", steps: [])',
         "route trail"),
    ]
    for label, src, expect in door_cases:
        found = audit_doors("fixture.swift", src)
        if not any(expect in f for f in found):
            print(f"  SELF-TEST FAIL: '{label}' was not caught "
                  f"(expected {expect!r}, got {found})")
            ok = False
        else:
            print(f"  ✓ catches {label}")

    # A filename is not a hostname, and a real verb is not sprawl. Both of
    # these are in the tree right now; flagging either would end this check.
    clean_doors = ('DSSlabButton(title: "Choose conversations.json", systemImage: "x") { }\n'
                   'DSSlabButton(title: "Choose the .p8 file", systemImage: "x") { }\n'
                   'DSSlabDoor(title: "Import a newer archive", systemImage: "x") { }\n'
                   'DSSlabButton(title: String(localized: "Get your API key")) { }\n'
                   # 30 chars of source, one digit on screen — the four wallet
                   # screens this check flagged on its very first run.
                   'DSSlabDoor(title: "Watching \\(walletCount) wallet") { }\n')
    f = audit_doors("fixture.swift", clean_doors)
    if f:
        print(f"  SELF-TEST FAIL: an ordinary door was flagged — {f}")
        ok = False
    else:
        print("  ✓ passes ordinary doors (a .json filename is not a hostname, "
              "an interpolation is not its source width)")

    # The room door's fixtures. The dirty one is the exact mistake the tree
    # invites — `name:` is the CATALOG name and `source:` is not, so passing
    # the one you already typed is the natural slip; and it renders perfectly,
    # so nothing but this can catch it.
    stamped = {"Privacy Pools", "Peer", "Deals"}
    dirty_room = ('RoomDoor(name: "0xBow Privacy Pools",\n'
                  '         source: "0xBow Privacy Pools")')
    f = audit_room_doors("fixture.swift", dirty_room, stamped)
    if not any("no bridge" in x for x in f):
        print(f"  SELF-TEST FAIL: a room door onto a non-existent room was "
              f"not caught — {f}")
        ok = False
    else:
        print("  ✓ catches a room door that names the catalog name, not the source")

    # Both shapes that must NOT fire: a correct literal, and a source handed
    # over as a constant (which is the drift-proof form and unresolvable from
    # text — flagging it would punish the better pattern).
    clean_room = ('RoomDoor(name: "0xBow Privacy Pools",\n'
                  '         source: "Privacy Pools")\n'
                  'RoomDoor(name: "Peer", source: "Peer")\n'
                  'RoomDoor(name: "Safe", source: SafeBridge.sourceName)\n')
    f = audit_room_doors("fixture.swift", clean_room, stamped)
    if f:
        print(f"  SELF-TEST FAIL: an ordinary room door was flagged — {f}")
        ok = False
    else:
        print("  ✓ passes ordinary room doors (a constant is not a literal)")

    # The absent door — the half that was missing on check 7's first day, and
    # the reason §460 shipped believing seventeen call sites was coverage.
    f = audit_door_presence("Ghost.swift",
                            'BridgeSetupHeader(name: "Ghost", mode: .noAccount, intro: "Short.")')
    if not any("no RoomDoor" in x for x in f):
        print(f"  SELF-TEST FAIL: a connect screen with no door was not caught — {f}")
        ok = False
    else:
        print("  ✓ catches a connect screen with no room door at all")
    if audit_door_presence("Ghost.swift",
                           'BridgeSetupHeader(name: "Ghost", mode: .noAccount, intro: "S.")\n'
                           'RoomDoor(name: "Ghost", source: "Ghost")'):
        print("  SELF-TEST FAIL: a screen WITH a door was flagged")
        ok = False
    else:
        print("  ✓ passes a connect screen that has one")

    # A source that IS stamped and still has no room — the half check 7 was
    # blind to on its first day, found by reading `Corpus.earnsRoom` rather
    # than by a failure.
    # ── check 7c — the seat that opens a room ─────────────────────────────
    routing_ok = ('    static func roomSource(forID id: String) -> String? {\n'
                  '        switch id {\n'
                  '        case "aave", "morpho": "Wallet"\n'
                  '        case "gnosispay": GnosisPayBridge.sourceName\n'
                  '        default: nil\n'
                  '        }\n'
                  '    }\n'
                  '        Row(offer: "Aave", id: "aave", destination: .wallet),\n'
                  '        Row(offer: "Morpho", id: "morpho", destination: .wallet),\n'
                  '        Row(offer: "Gnosis Pay", id: "gnosispay", destination: .wallet),\n')
    seats_ok = ('WalletSeat(id: "aave", name: "Aave",\n'
                'WalletSeat(id: "morpho", name: "Morpho",\n'
                'WalletSeat(id: "gnosispay", name: "Gnosis Pay",\n')
    stamped_w = {"Wallet", "Peer"}
    if audit_seat_rooms(routing_ok, seats_ok, stamped_w):
        print("  ✗ flagged a correct seat-room table"); ok = False
    else:
        print("  ✓ passes a correct seat-room table (a constant is not a literal)")

    # The catalog name where the source was wanted — check 7a's trap, reached
    # from the other side. "Gnosis Pay" happens to be both here, so the fixture
    # uses a seat whose two spellings really differ.
    routing_catalog_name = routing_ok.replace('case "aave", "morpho": "Wallet"',
                                              'case "aave", "morpho": "0xBow Privacy Pools"')
    f = audit_seat_rooms(routing_catalog_name, seats_ok, stamped_w)
    if not any("no bridge stamps" in x for x in f):
        print("  ✗ missed a seat opening an unstamped source"); ok = False
    else:
        print("  ✓ catches a seat that opens a source no bridge stamps")

    # A typo in the seat id is not a crash and not an empty room — Open just
    # goes back to pushing the manager, which looks exactly like shipping.
    routing_typo = routing_ok.replace('case "aave", "morpho": "Wallet"',
                                      'case "aav", "morpho": "Wallet"')
    f = audit_seat_rooms(routing_typo, seats_ok, stamped_w)
    if not any("not a WalletSeat id" in x for x in f):
        print("  ✗ missed a seat id that does not exist"); ok = False
    else:
        print("  ✓ catches a seat id no WalletSeat carries")

    # A seat that owns a real screen must not be listed — the room opens and
    # holds rows, so the unreachable screen reads as nothing at all.
    routing_has_screen = (routing_ok
        .replace('case "aave", "morpho": "Wallet"', 'case "peer": "Peer"')
        .replace('        Row(offer: "Aave", id: "aave", destination: .wallet),\n',
                 '        Row(offer: "Peer", id: "peer", destination: .peer),\n'))
    f = audit_seat_rooms(routing_has_screen,
                         seats_ok + 'WalletSeat(id: "peer", name: "Peer",\n',
                         stamped_w)
    if not any("makes that screen unreachable" in x for x in f):
        print("  ✗ missed a seat whose own screen it would hide"); ok = False
    else:
        print("  ✓ catches a seat that already owns a screen")

    # A source that is stamped and still has no room (Corpus.earnsRoom says no).
    f = audit_seat_rooms(routing_ok.replace('case "aave", "morpho": "Wallet"',
                                            'case "aave", "morpho": "You"'),
                         seats_ok, stamped_w | {"You"}, roomless={"You"})
    if not any("earnsRoom refuses" in x for x in f):
        print("  ✗ missed a seat opening a roomless source"); ok = False
    else:
        print("  ✓ catches a seat opening a stamped-but-roomless source")

    # The function itself going away must be a finding, not a silent pass —
    # otherwise a refactor turns this whole check off with nothing to say so.
    if not audit_seat_rooms("enum BridgeRouter {}", seats_ok, stamped_w):
        print("  ✗ a missing roomSource() passed silently"); ok = False
    else:
        print("  ✓ catches roomSource() disappearing")

    f = audit_room_doors("fixture.swift",
                         'RoomDoor(name: "Contacts", source: "Contacts")',
                         {"Contacts", "Peer"}, {"Contacts", "You"})
    if not any("earnsRoom refuses" in x for x in f):
        print(f"  SELF-TEST FAIL: a door onto a roomless source was not caught — {f}")
        ok = False
    else:
        print("  ✓ catches a room door onto a stamped-but-roomless source")

    rl = roomless_sources('static let searchOnlySources: Set<String> = ["Contacts", "HomeKit"]\n'
                          'static let chiplessSources: Set<String> = ["You"]\n')
    if rl != {"Contacts", "HomeKit", "You"}:
        print(f"  SELF-TEST FAIL: roomless set parsed as {rl}")
        ok = False
    else:
        print("  ✓ reads the roomless sources out of Thing.swift")

    # And the token family behind one property.
    f = audit_token_sources('case ghost = "Ghost"\nvar id: String { rawValue }', {"Peer"})
    if not any("not stamped" in x for x in f):
        print(f"  SELF-TEST FAIL: a TokenBridge case with no matching source "
              f"was not caught — {f}")
        ok = False
    else:
        print("  ✓ catches a TokenBridge case whose room does not exist")
    f = audit_token_sources('case peer = "Peer"\nvar id: String { rawValue }', {"Peer"})
    if f:
        print(f"  SELF-TEST FAIL: a real TokenBridge case was flagged — {f}")
        ok = False
    else:
        print("  ✓ passes a TokenBridge case that is really stamped")

    # And the table form, which serves many screens from one entry.
    f = audit_door_table("fixture.swift",
                         'var doorTitle: String { switch self {\n'
                         'case .stripe: "Open dashboard.stripe.com → API keys"\n} }')
    if not any("route trail" in x for x in f):
        print(f"  SELF-TEST FAIL: a bad door TABLE entry was not caught — {f}")
        ok = False
    else:
        print("  ✓ catches a bad entry in a door table")

    return ok


# ── main ───────────────────────────────────────────────────────────────────

def main() -> int:
    if "--self-test" in sys.argv:
        print("setup-copy-audit self-test")
        ok = self_test()
        print("  self-test PASSED" if ok else "  self-test FAILED")
        return 0 if ok else 1

    print("setup-copy-audit (prd §315)")
    if not self_test():
        print("  refusing to certify: the audit's own self-test failed")
        return 1

    stamped = stamped_sources(MODEL)
    roomless = roomless_sources(
        open(os.path.join(ROOT, "Casberi", "Shared", "Thing.swift")).read())
    findings, screens = [], 0
    for fn in sorted(os.listdir(SCREENS)):
        if not fn.endswith(".swift") or fn in SKIP:
            continue
        src = open(os.path.join(SCREENS, fn)).read()
        if "BridgeSetupHeader(" not in src and "BridgeStepLines(" not in src:
            continue
        screens += 1
        findings += audit_source(fn, src, stamped, roomless)

    findings += audit_token_sources(
        strip_comments(open(os.path.join(MODEL, "TokenBridges.swift")).read()), stamped)

    # Check 7c — the door reached from the catalog side.
    findings += audit_seat_rooms(
        strip_comments(open(os.path.join(MODEL, "BridgeRouting.swift")).read()),
        strip_comments(open(os.path.join(MODEL, "BridgeStore.swift")).read()),
        stamped, roomless)

    catalog_findings, offers = audit_catalog(strip_comments(open(CATALOG).read()))
    findings += catalog_findings

    # The door verbs that serve many screens from one table.
    tables = 0
    for path in DOOR_TABLES:
        tables += 1
        findings += audit_door_table(os.path.basename(path),
                                     strip_comments(open(path).read()))

    print(f"  {screens} connect screens, {offers} catalog offers, "
          f"{tables} door tables checked")
    if findings:
        print(f"\n  {len(findings)} finding(s):")
        for f in findings:
            print(f"    · {f}")
        return 1
    print("  clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
