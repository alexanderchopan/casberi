#!/bin/zsh
# work-stage-selftest.sh — the Work receipt's judgement, compiled AS SHIPPED.
#
# WHY THIS EXISTS. `WorkStage` decides what a Work thing sheet SAYS HAPPENED —
# the status word, its colour, the headline, whether a project is named. Every
# failure it can have renders as a perfectly good-looking receipt: a dispute
# that says "won" when it was lost, a build that reads green when it broke, a
# row labelled "Project: fix the null case" because a commit subject held a
# separator. `xcodebuild` is happy with all of them, the screen sweep passes,
# and nothing in the app can tell. So the judgement is checked here.
#
# HOW. `Model/WorkStage.swift` is Foundation-only BY DESIGN (no SwiftUI, no
# SwiftData, no `Thing`) precisely so this can compile it WHOLE and UNMODIFIED
# — the `ASCShape`/`StripeShape`/`CursorAgentStatus` precedent. There are no
# stubs at all: what runs here is the shipped file, byte for byte.
#
# THE RULE IT PROTECTS (prd §340). Every `leadClause` in this codebase is
# `String(localized:)`, so the title records the outcome in whatever language
# the device was in WHEN THE ROW LANDED. Reading it back means a device that
# changed language reports every past failure as a success. So `outcome` may
# only ever read STABLE signals — English facet tags, the raw state inside a
# `sourceRef`, `mark` — and the localized clause gets exactly one cosmetic job
# (dropping a duplicate word from the headline) that fails safe. Assertion
# group 6 and mutation 4 are that rule as a test.
#
# NOTE the negative guards read a COMMENT-STRIPPED copy. The source DOCUMENTS
# this rule by naming the very thing it must not do ("never parse the title",
# "slicing it out of the title"), so a guard grepping raw source fires on the
# prose explaining it — the Obsidian/Cursor lesson, earned again here.
set -uo pipefail
ROOT="${0:a:h:h}"
SRC="$ROOT/Casberi/Casberi/Model/WorkStage.swift"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[[ -f "$SRC" ]] || { print -u2 "missing $SRC"; exit 1; }

# ── The harness ───────────────────────────────────────────────────────────────
cat > "$WORK/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func eq(_ label: String, _ got: String?, _ want: String?) {
    if got != want { print("FAIL \(label): got \(got ?? "nil") want \(want ?? "nil")"); failures += 1 }
}
func ok(_ label: String, _ cond: Bool) {
    if !cond { print("FAIL \(label)"); failures += 1 }
}
func row(_ source: String, ref: String? = nil, title: String, tags: [String] = [],
         mark: String = "none", project: String? = nil, price: Bool = false) -> WorkStage.Row {
    WorkStage.Row(source: source, sourceRef: ref, title: title, tags: tags,
                  mark: mark, projectField: project, hasPrice: price)
}

// 1 ── Vercel: the outcome comes from the tag, not the word in the title.
let vFail = row("Vercel", ref: "vercel:deploy:1",
                title: "Build failed · casberi/web · fix: guard the null case",
                tags: ["Build failure"], project: "casberi/web")
let rvFail = WorkStage.reading(vFail)!
eq("vercel.failed.word", rvFail.statusWord, "Build failed")
eq("vercel.failed.tone", rvFail.tone.rawValue, "failed")
eq("vercel.failed.subject", rvFail.subject, "fix: guard the null case")
eq("vercel.failed.project", rvFail.project, "casberi/web")
let rvOK = WorkStage.reading(row("Vercel", ref: "vercel:deploy:2",
                                 title: "casberi/web · ship the new feed",
                                 tags: ["Deploy"], project: "casberi/web"))!
eq("vercel.ok.tone", rvOK.tone.rawValue, "landed")
eq("vercel.ok.subject", rvOK.subject, "ship the new feed")

// 2 ── (source, tag) keying. "Release" means three different things.
eq("npm.release.tone",
   WorkStage.reading(row("npm", ref: "npm:release:a:1", title: "left-pad 1.0",
                         tags: ["Release"]))!.tone.rawValue, "landed")
ok("hf.release.silent",
   WorkStage.reading(row("Hugging Face", ref: "hf:model:x",
                         title: "x · new model", tags: ["Release"])) == nil)
eq("asc.release.by.ref",
   WorkStage.reading(row("App Store Connect", ref: "asc:version:9:REJECTED",
                         title: "Rejected · Casberi 1.4", tags: ["Release"]))!.tone.rawValue,
   "failed")

// 3 ── App Store Connect reads Apple's own raw constant out of the ref.
for (raw, tone) in [("REJECTED","failed"), ("METADATA_REJECTED","failed"),
                    ("IN_REVIEW","waiting"), ("ACCEPTED","landed"),
                    ("READY_FOR_SALE","landed"), ("PENDING_CONTRACT","waiting")] {
    eq("asc.\(raw)", WorkStage.reading(row("App Store Connect",
        ref: "asc:version:9:\(raw)", title: "x · Casberi 1.4"))?.tone.rawValue, tone)
}
ok("asc.unknown.state.silent",
   WorkStage.reading(row("App Store Connect", ref: "asc:version:9:PREPARE_FOR_SUBMISSION",
                         title: "Casberi 1.5")) == nil)
eq("asc.build.valid", WorkStage.reading(row("App Store Connect",
    ref: "asc:build:3:VALID", title: "Ready to test · Casberi build 267"))?.tone.rawValue,
   "landed")
eq("asc.review.face", WorkStage.reading(row("App Store Connect",
    ref: "asc:review:7", title: "★★☆☆☆ · Casberi · Crashes"))!.face.rawValue, "stars")

// 4 ── Stripe: direction from the stable facet, never the verb.
for (tags, word, tone) in [(["Dispute","Won"], "Dispute won", "landed"),
                           (["Dispute","Lost"], "Dispute lost", "failed"),
                           (["Dispute"], "Dispute opened", "failed"),
                           (["Payout"], "Paid out", "landed"),
                           (["Payout","Failed"], "Payout failed", "failed"),
                           (["Dunning"], "Payment failed", "failed"),
                           (["Dunning","Recovered"], "Payment recovered", "landed")] {
    let r = WorkStage.reading(row("Stripe", title: "x · y", tags: tags))!
    eq("stripe.\(tags).word", r.statusWord, word)
    eq("stripe.\(tags).tone", r.tone.rawValue, tone)
}
// A withdrawn dispute gets NEITHER marker, so it must not claim a direction.
eq("stripe.withdrawn", WorkStage.reading(row("Stripe", title: "Dispute closed · £2",
                                             tags: ["Dispute"]))!.statusWord, "Dispute opened")
eq("stripe.money.face", WorkStage.reading(row("Stripe", title: "x · y",
    tags: ["Dispute"], price: true))!.face.rawValue, "money")
// A row landed before the price fields existed falls back to words, never a
// money hero with nothing in it.
eq("stripe.priceless.face", WorkStage.reading(row("Stripe", title: "x · y",
    tags: ["Dispute"], price: false))!.face.rawValue, "words")

// 5 ── Tickets read `mark`, which was never localized in the first place.
for (mark, word, tone) in [("todo","Open","waiting"), ("doing","In progress","waiting"),
                           ("done","Done","landed")] {
    let r = WorkStage.reading(row("Linear", ref: "linear:1", title: "ENG-1 · Fix it", mark: mark))!
    eq("mark.\(mark).word", r.statusWord, word)
    eq("mark.\(mark).tone", r.tone.rawValue, tone)
}
ok("mark.none.silent",
   WorkStage.reading(row("Jira", ref: "jira:d:K-1", title: "K-1 · thing", mark: "none")) == nil)

// 6 ── §340: a row that landed in ANOTHER LANGUAGE still reports the right
//      outcome, and keeps its title whole rather than being mis-sliced.
let fr = row("Vercel", ref: "vercel:deploy:3",
             title: "Échec de la compilation · casberi/web · corrige le cas nul",
             tags: ["Build failure"], project: "casberi/web")
let rfr = WorkStage.reading(fr)!
eq("fr.tone.survives", rfr.tone.rawValue, "failed")
eq("fr.title.whole", rfr.subject,
   "Échec de la compilation · casberi/web · corrige le cas nul")

// 7 ── The clause strip is prefix + separator, so an ordinary sentence that
//      merely STARTS with the word is never cut.
// The fixture has to be one where the status word really IS the title's first
// word, or it proves nothing: an npm RELEASE row's clause is "Released", so a
// title beginning "Deprecated" was never a candidate for its strip and the
// boundary mutation sailed past it. An open ticket titled "Open …" is the
// realistic collision, and it is a common way to word a ticket.
eq("no.false.strip",
   WorkStage.reading(row("Linear", ref: "linear:9", title: "Open the drawer on tap",
                         mark: "todo"))!.subject, "Open the drawer on tap")
eq("real.strip",
   WorkStage.reading(row("npm", ref: "npm:deprecated:a", title: "Deprecated · left-pad",
                         tags: ["Deprecated"]))!.subject, "left-pad")
// A title that is ONLY its clause keeps it — a blank hero is worse.
eq("never.empty",
   WorkStage.reading(row("Stripe", title: "Payments stopped", tags: ["Silence"]))!.subject,
   "Payments stopped")

// 8 ── PagerDuty's duration survives as the detail, and the project it also
//      names is not left duplicated in the headline.
let pd = row("PagerDuty", ref: "pagerduty:resolved:1",
             title: "Resolved after 2 hours · casberi-api · API latency above 2s",
             tags: ["Resolved"], project: "casberi-api")
eq("pd.subject", WorkStage.reading(pd)!.subject, "API latency above 2s")
eq("pd.detail", WorkStage.statusDetail(pd, clause: "Resolved"), "Resolved after 2 hours")
eq("pd.project", WorkStage.reading(pd)!.project, "casberi-api")
// No duration → nothing extra to say.
ok("pd.no.detail", WorkStage.statusDetail(
    row("PagerDuty", title: "Resolved · api · x", tags: ["Resolved"]), clause: "Resolved") == nil)

// 9 ── A project is drawn ONLY from a field. A seat with no project field
//      must answer nil even though its title obviously contains one.
ok("project.field.only",
   WorkStage.reading(row("Sentry", ref: "sentry:issue:1",
                         title: "my-app · TypeError: undefined", tags: ["Issue"]))!.project == nil)
ok("project.not.for.tickets",
   WorkStage.reading(row("Linear", ref: "linear:2", title: "ENG-2 · x",
                         mark: "todo", project: "someone"))!.project == nil)
eq("sentry.code.face",
   WorkStage.reading(row("Sentry", ref: "sentry:issue:1", title: "a · b",
                         tags: ["Issue"]))!.face.rawValue, "code")

// 10 ── Chips are the PERSON's labels; our shape marks and the kind tag go.
eq("labels.filtered",
   WorkStage.labels(row("Linear", title: "x", tags: ["Bug", "Release", "Link", "Urgent"]),
                    typeTags: ["Link"]).joined(separator: ","), "Bug,Urgent")
ok("labels.empty.when.only.chrome",
   WorkStage.labels(row("Vercel", title: "x", tags: ["Build failure", "Link"]),
                    typeTags: ["Link"]).isEmpty)
// Every shape-tag FAMILY needs its own case here, not just one: a mutation
// deleting the money row from `shapeTags` survived the first cut of this
// harness because the only label assertions used Linear's and Vercel's tags.
// A test that passes for the wrong reason proves nothing (the
// retriever-selftest lesson).
ok("labels.money.chrome.stripped",
   WorkStage.labels(row("Stripe", title: "x",
                        tags: ["Dispute", "Won", "Payout", "Dunning", "Churn",
                               "Silence", "Runway", "Link"]),
                    typeTags: ["Link"]).isEmpty)
ok("labels.outcome.chrome.stripped",
   WorkStage.labels(row("Cursor", title: "x",
                        tags: ["Agent run", "Failed", "Expired", "Cancelled", "PR"]),
                    typeTags: []).isEmpty)
ok("labels.shape.chrome.stripped",
   WorkStage.labels(row("App Store Connect", title: "x",
                        tags: ["Review", "Build", "Release", "Issue", "Regression",
                               "Incident", "Resolved", "Deploy", "Deprecated",
                               "Annotation", "Milestone", "Watchlist", "Paper",
                               "Lost", "Recovered", "Build failure"]),
                    typeTags: []).isEmpty)

// 11 ── Non-Work seats are untouched, which is what lets this land safely.
for source in ["Slack", "Notion", "Wallet", "Bluesky", "Photos", "GitHub"] {
    if source == "GitHub" { continue }
    ok("silent.\(source)", WorkStage.reading(row(source, title: "x · y")) == nil)
}

if failures == 0 { print("work-stage-selftest: all assertions passed") }
exit(failures == 0 ? 0 : 1)
SWIFT

build_and_run() {  # $1 = source file to compile
  local out="$WORK/bin"
  swiftc -O "$1" "$WORK/main.swift" -o "$out" 2>"$WORK/err" || return 2
  "$out" >"$WORK/out" 2>&1
}

# ── 1. The shipped file must pass ─────────────────────────────────────────────
cp "$SRC" "$WORK/WorkStage.swift"
build_and_run "$WORK/WorkStage.swift"
case $? in
  0) : ;;
  2) print -u2 "work-stage-selftest: the SHIPPED source did not compile"; cat "$WORK/err"; exit 1 ;;
  *) print -u2 "work-stage-selftest: the shipped source FAILED its own assertions";
     cat "$WORK/out"; exit 1 ;;
esac

# ── 2. Mutations — each one a silent wrong answer this must catch ─────────────
# A mutation that fails to COMPILE, or that matches nothing (so it silently
# tests the shipped file and scores it green), is itself a failure. Both traps
# are real: `retriever-selftest` and `cursor-selftest` each paid for one.
mutate() {  # $1 = label, $2 = sed program
  local f="$WORK/mut.swift"
  sed "$2" "$SRC" > "$f"
  if cmp -s "$f" "$SRC"; then
    print -u2 "work-stage-selftest: mutation '$1' matched NOTHING — it proves nothing"
    exit 1
  fi
  build_and_run "$f"
  case $? in
    0) print -u2 "work-stage-selftest: mutation '$1' SURVIVED — the harness cannot see it";
       exit 1 ;;
    2) print -u2 "work-stage-selftest: mutation '$1' did not compile — rewrite it";
       cat "$WORK/err"; exit 1 ;;
    *) : ;;   # died as it should
  esac
}

# The §340 rule itself: strip the clause without checking it matches, i.e. go
# back to trusting the title. A French row loses its first segment.
mutate "clause strip stops checking the language" \
  's|guard matches(head) else { return title }|_ = matches;|'

# Tone read from a tag alone rather than (source, tag).
mutate "Stripe stops distinguishing won from lost" \
  's|if tags.contains("Lost") { return (word("Dispute lost"), .failed) }||'

# The project stops being field-only — the exact bug the design refuses.
mutate "project accepts any source" \
  's|guard \["Cursor", "Vercel", "Sentry", "PagerDuty"\].contains(row.source),|guard true \|\| ["x"].contains(row.source),|'

# ASC stops reading Apple's raw constant.
mutate "ASC rejection reads as nothing" \
  's|case "REJECTED":                     return (word("Rejected"), .failed)||'

# mark stops being read, so every ticket goes silent.
mutate "tickets lose their state" \
  's|case "doing": return (word("In progress"), .waiting)||'

# The shape tags stop being chrome, so the status line repeats as a chip.
mutate "shape tags leak into the person's labels" \
  's|"Dispute", "Payout", "Dunning", "Churn", "Silence", "Runway",||'

# The clause boundary loosens from the " · " separator to any space, so an
# ordinary sentence that merely STARTS with the word ("Deprecated APIs in 3.0")
# gets its first word eaten. Note the first attempt at this mutation fell back
# to an EMPTY range, which still fails the match and so changed nothing — a
# mutation has to actually produce the bug it names.
mutate "clause strip no longer needs a separator" \
  's|guard let sep = title.range(of: " · ") else { return title }|guard let sep = title.range(of: " · ") ?? title.range(of: " ") else { return title }|'

# Money face claims a hero for a row with no stored amount.
mutate "money face ignores whether a price exists" \
  's|case "Stripe": return row.hasPrice ? .money : .words|case "Stripe": return .money|'

# ── 3. Drift guards — the wiring the compiled functions cannot prove ──────────
# Comment-stripped, because the source explains this rule by naming it.
STRIPPED="$WORK/stripped.swift"
sed -E 's@^[[:space:]]*///.*$@@; s@^[[:space:]]*//.*$@@' "$SRC" > "$STRIPPED"

guard() {  # $1 = label, $2 = pattern that MUST be present
  grep -qE "$2" "$STRIPPED" \
    || { print -u2 "work-stage-selftest: drift — $1"; exit 1; }
}
deny() {   # $1 = label, $2 = pattern that must NOT appear
  grep -qE "$2" "$STRIPPED" \
    && { print -u2 "work-stage-selftest: drift — $1"; exit 1; }
  return 0
}

# The type must stay Foundation-only, or this harness stops being able to
# compile it as shipped and the whole proof evaporates.
deny "WorkStage imported SwiftUI — it must stay Foundation-only" '^import SwiftUI'
deny "WorkStage imported SwiftData — it must stay Foundation-only" '^import SwiftData'
deny "WorkStage reached for Thing directly — it takes primitives (Row)" '\bThing\b'

# The three bridges this pass taught to stamp their project must keep doing it,
# or `project` silently answers nil forever and the slab row just disappears.
for pair in "VercelBridge:project" "SentryBridge:issue.project" "PagerDutyBridge:incident.service"; do
  file="$ROOT/Casberi/Casberi/Model/${pair%%:*}.swift"
  want="${pair##*:}"
  grep -qE "thing\.authorHandle = ${want//./\\.}" "$file" \
    || { print -u2 "work-stage-selftest: drift — ${pair%%:*} stopped stamping its project"; exit 1; }
done

# Stripe's stable facets and its price stamp — both invisible from outside.
grep -qE 'tags: \[shaped\.tag\] \+ shaped\.facets' "$ROOT/Casberi/Casberi/Model/StripeBridge.swift" \
  || { print -u2 "work-stage-selftest: drift — Stripe stopped landing its facet tags"; exit 1; }
grep -qE 'thing\.priceValue = value' "$ROOT/Casberi/Casberi/Model/StripeBridge.swift" \
  || { print -u2 "work-stage-selftest: drift — Stripe stopped stamping priceValue"; exit 1; }

# The sheet must actually draw it. A perfect WorkStage nothing renders is the
# §311/§340 shape: the reading composes, and no screen shows it.
grep -qE 'WorkStageView\(thing:' "$ROOT/Casberi/Casberi/Screens/ThingSheetView.swift" \
  || { print -u2 "work-stage-selftest: drift — the sheet stopped drawing the Work receipt"; exit 1; }

print "work-stage-selftest: shipped source passes, 8 mutations caught, drift guards clean"
