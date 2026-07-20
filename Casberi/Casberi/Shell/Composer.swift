import SwiftUI
import SwiftData

/// The composer — the hero (principle 4). Full width above the tab bar, glass.
///
/// RULING (2026-07-04): typed text is never saved — typing is TALKING to the
/// assistant, and every send streams an answer. Things enter Casberi through
/// the capture paths: the Paste chip, the mic, the share sheet, screenshots,
/// drop, and bridges. Saving is an OUTCOME those paths report (toast), never
/// a verb the person chooses. The one button is send (↑).
struct Composer: View {
    @Binding var isOpen: Bool
    @Binding var draft: String
    /// Hosted inside a tab (the Actions screen) rather than floating — sheds the
    /// bubble's card surface and morph so the field, chips, and tools read as
    /// native page content, not a stranded card.
    var embedded: Bool = false
    /// Reports the content's natural height (embedded only) so the hosting sheet
    /// can hug it — no stranded empty space.
    var onHeight: (CGFloat) -> Void = { _ in }
    /// Commit carries the parse card's chosen tags (M6: save writes to us).
    var onCommit: ([String]) -> Void
    /// A finished voice note: transcript + the audio file's sourceRef.
    var onCommitVoice: (String, String) -> Void = { _, _ in }
    /// Answers a query, returning the final AnswerStream document (engine
    /// grammar). While a synthesis answer streams, it calls `onProseDoc` with
    /// each growing doc so prose renders live; lookups and the non-AI fallback
    /// never call it and just return the doc to reveal at once.
    var answer: (_ query: String, _ onProseDoc: @escaping ([String]) -> Void) async -> [String] = { _, _ in [] }
    /// The BYO-key retry (prd §67): answers the same question with the person's
    /// own Anthropic key, device→API direct. nil when the key or the network
    /// failed — the composer words that honestly. The verb only shows when a
    /// key is configured; it never fires on its own.
    var answerWithKey: (_ query: String) async -> [String]? = { _ in nil }
    /// Candidate project tags for the parse card, from the corpus.
    var tagCandidates: () -> [String] = { [] }
    /// The connected sources ("Gmail", "Steam") — navigation asks match them.
    var knownSources: () -> [String] = { [] }
    /// The source the person is looking at right now (a Feed filtered to one
    /// app), or nil — lets the ask chips lead with that source's recap so the
    /// composer meets you where you are.
    var contextSource: () -> String? = { nil }
    /// A typed ask that names a place ("show my work stuff") — the shell
    /// closes the composer and goes there.
    var onNavigate: (NavigateIntent) -> Void = { _ in }
    /// Keep a synthesis answer — lands it as a note in the feed so the recap
    /// isn't ephemeral. The composer hands over the answer's plain text.
    /// Labelled "Save as a note" on the button (docs/agent-brief.md, the
    /// 2026-07-19 rename): "Keep" itself is reserved for minting a standing
    /// kept-ask chip — a different verb now, see `onKeep` below.
    var onKeepAnswer: (String) -> Void = { _ in }
    /// The shell's glass namespace — pill and bubble share one glass identity,
    /// so open/close is a morph of the same substance, not a swap.
    var glassNamespace: Namespace.ID? = nil
    /// Resolves a thing id to a real `Thing` for the agent's own drill-down
    /// (docs/agent-brief.md ruling 8 — the Stack session model: tapping
    /// content inside an answer PUSHES a thing-view rather than presenting a
    /// sheet). nil ids, or ids that no longer resolve, render nothing.
    var resolveThing: (String) -> Thing? = { _ in nil }
    /// Lowers the agent (docs/agent-brief.md ruling 9: staying is the
    /// default; a bare tap never ejects you — this is the ONE thing "Open in
    /// app" from inside a pushed thing-view is allowed to do to the agent
    /// itself). Called at the end of every `close()`, so both new exits (✕,
    /// ⌄) and every pre-existing close path lower the agent uniformly.
    var onLowerAgent: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var scheme

    /// The empty field's invitation cycles through what the composer can DO —
    /// ask, find, organize, recap — so it teaches its range instead of reading
    /// as one dead line (delight, 2026-07-12). These are honest capability
    /// invitations, not data claims; the corpus-derived ask CHIPS below carry
    /// the specifics you can tap.
    @State private var placeholderIndex = 0
    private let invitations = [
        "Ask, or say what to do",
        "What did I save this week?",
        "Find that thing I pasted",
        "Recap my month",
        "Tag everything from an app",
    ]
    /// Flips true just after the bubble opens so the ask chips stagger in
    /// rather than snapping (delight, 2026-07-12).
    @State private var chipsAppeared = false
    /// The date NSDataDetector found in the draft (nil when none) — feeds the
    /// Send-to band's receipt line and Calendar's calshow timestamp.
    @State private var detectedDate: Date?
    @FocusState private var fieldFocused: Bool
    @State private var answerStream = GenStream()
    /// The agent's own navigation trail (ruling 8 — the Stack session model).
    /// A thing id pushed here opens a real generative thing-view; the ✕/⌄
    /// exits and the top-trailing ✕ button only show at `path.isEmpty` (the
    /// agent's own root) — a pushed screen's system back chevron pops it.
    @State private var path = NavigationPath()
    /// The composer is a CONVERSATION now (2026-07-12): each answered ask
    /// becomes a turn that stays in view, so you can keep asking follow-ups
    /// without re-opening — the Q&A stacks until you close.
    private struct ConvoTurn: Identifiable {
        let id = UUID()
        let question: String
        let els: GenEls
        /// True when the person's own key produced this answer — the settled
        /// turn keeps its badge (honesty: a keyed answer says so, always).
        var keyed = false
    }
    @State private var turns: [ConvoTurn] = []
    /// The question currently being answered — shown above the live answer
    /// until it settles into a turn.
    @State private var currentQuestion = ""
    /// One-shot: the current answer has been kept, so its Keep affordance
    /// retires (no dead re-tap, no duplicate note). Resets on the next ask.
    @State private var keptCurrent = false
    /// True once the current answer STREAMED as prose — only a real synthesis
    /// is keepable, never a lookup or a "nothing matches" fallback (both of
    /// which are also Insights). Resets on the next ask.
    @State private var currentStreamed = false
    /// True while an answer is actually being produced (model running) — the
    /// after-answer verbs (Keep, Try with your key) wait for the settle.
    @State private var inFlight = false
    /// True when the current answer came from the person's own key — it wears
    /// the badge, and the retry verb retires (one keyed try per ask).
    @State private var keyedCurrent = false
    /// Monotonic ask generation — every new ask (and close) bumps it, and an
    /// answer Task that finishes after a newer ask started must not paint
    /// over the live answer (review 2026-07-13: a slow first answer was
    /// clobbering the follow-up that overtook it).
    @State private var askGeneration = 0
    /// Whether a key is configured, mirrored once per settled answer — the
    /// chip gate can't afford a Keychain round-trip per render (typing a
    /// follow-up re-renders per keystroke).
    @State private var keyAvailable = false
    /// The kept-ask KIND the current question would mint, computed once per
    /// settled answer (same reason `keyAvailable` is settle-cached, not a
    /// per-render computed property: a corpus fetch per render would be
    /// wasteful during a streaming reveal). nil when the question doesn't
    /// match a keepable shape, or it's already kept.
    @State private var keepableAskKind: String?

    /// The keepable text of a synthesis answer — a synthesis is one Insight
    /// carrying the prose (RootShell's proseDoc). Only that shape is worth
    /// keeping: a lookup answer IS the things, which already live in the feed;
    /// a short status line or "Thinking…" isn't a recap. nil otherwise.
    private func keepableText(_ els: GenEls) -> String? {
        guard let insight = els.values.first(where: { $0.comp == "Insight" }) else { return nil }
        let text = insight.str(0)
        return text.count >= 40 ? text : nil
    }

    /// The kept-ask KIND the question would mint, or nil (docs/agent-brief.md
    /// ruling 1). A PURE pattern-match against the same recognizers
    /// `RootShell.answerDocument` checks before any model call — by
    /// construction this can never reach the model, which is the "no LLM in
    /// the kept-ask path" guarantee made structural rather than conventional.
    /// Scoped to exactly the kinds `KeptAskComposers` implements — offering a
    /// kind with no real composer would be a dead control once kept (honesty
    /// rule).
    private func recognizeKeptAskKind(_ question: String, in things: [Thing]) -> String? {
        guard !question.isEmpty else { return nil }
        let q = question.lowercased()
        var kind: String?
        if TokensAsk.matches(question) {
            kind = "watchlist"
        } else if WalletAsk.matches(question) {
            kind = "wallet"
        } else if q.contains("away"), let pulse = StatusAsk.pulse(question, things: things),
                  !pulse.pool.isEmpty {
            kind = "away"
        } else if q.hasPrefix("show "),
                  let tag = tagPool.first(where: { q == "show \($0.lowercased())" }) {
            kind = "showtag:\(tag)"
        } else if q.contains("overdue"),
                  things.contains(where: { $0.mark != .done && ($0.source == "Reminders" || $0.source == "Todoist")
                                            && ($0.dueAt ?? .distantFuture) < .now }) {
            kind = "overdue"
        } else if let name = contextSourceName(q),
                  let source = Set(things.map(\.source)).first(where: { $0.lowercased() == name }) {
            kind = "context:\(source)"
        } else if TagsAsk.parse(question) == nil, AppsAsk.parse(question) == nil,
                  AggregateAsk.parse(question, sources: Array(Set(things.map(\.source)))) == nil,
                  StatusAsk.pulse(question, things: things) == nil,
                  !Retriever.rank(question, in: things, isPoolRefinement: false).isEmpty {
            // Kept SEARCHES (docs/agent-brief.md ruling 13, 2026-07-20) — any
            // free-text ask that actually retrieved something becomes
            // keepable. The exclusions above matter: `answerDocument` checks
            // TagsAsk/AppsAsk/AggregateAsk/StatusAsk BEFORE the general
            // retriever, so a question one of those would have answered
            // must never mint a `search:` kind — its kept re-run (retrieval
            // rows) would silently disagree with what the live answer
            // actually showed (an arithmetic line, a status pulse, …).
            kind = "search:\(q.trimmingCharacters(in: CharacterSet(charactersIn: "? ")))"
        }
        guard let kind, !KeptAskStore.shared.isKept(kind) else { return nil }
        return kind
    }

    /// "what's new in <source>" / "whats new in <source>" — the bare source
    /// name after the phrase, lowercased and trimmed, or nil if the phrase
    /// doesn't match at all. Matching against a REAL source happens at the
    /// call site (this only strips the phrase).
    private func contextSourceName(_ q: String) -> String? {
        for prefix in ["what's new in ", "whats new in "] where q.hasPrefix(prefix) {
            return String(q.dropFirst(prefix.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "? "))
        }
        return nil
    }
    /// A typed organize command's pending change — rendered as a card, the
    /// write waits for Apply (typed words never write silently).
    @State private var proposal: OrganizeProposal?
    @State private var proseStreaming = false
    @State private var answering = false
    @State private var chosenTags: Set<String> = []
    @State private var voice = VoiceCapture()
    /// True when the draft arrived by paste — the one typed-ish path that
    /// still captures (pasting is bringing a thing in, not talking).
    @State private var pasted = false
    /// DEBUG: guards the one-shot auto-send used to screenshot the in-app
    /// answer render without a physical keyboard.
    @State private var didAutoSend = false

    /// Empty-field ask suggestions — derived from the live corpus on open
    /// (re-ruling 2026-07-08: the dead GENERIC chips stay dead; these are
    /// asks the corpus can actually answer right now). `kind` is the ask's
    /// stable identity, `glyph` is assigned where the ask is created (no
    /// parallel switch to forget), and `memoryKey` keys the decay counters
    /// (see AskMemory) — kind:qualifier where one kind wears many faces,
    /// so "Show recipes" neglect never pre-demotes "Show travel".
    private struct AskOption {
        let kind: String
        let title: String
        let glyph: String
        let memoryKey: String
        init(kind: String, title: String, glyph: String, memoryKey: String? = nil) {
            self.kind = kind
            self.title = title
            self.glyph = glyph
            self.memoryKey = memoryKey ?? kind
        }
    }
    @State private var suggestions: [AskOption] = []
    /// The away window's real count — the librarian chip rolls up to it
    /// (delight 2026-07-13); set beside the gate that shows the chip.
    @State private var awayLanded = 0
    /// The tag list, snapshotted once per open — tagCandidates() walks the
    /// whole store, and computed-per-keystroke it made typing pay a corpus
    /// fetch per character (review 2026-07-08).
    @State private var tagPool: [String] = []
    /// The rest-screen greeting's stat line ("2,481 things, across 14
    /// apps."), ruling 4 — snapshotted once per open alongside `tagPool`
    /// (same corpus walk `computeSuggestions()` already pays for, not a
    /// second one).
    @State private var corpusSummary = ""

    /// One corpus-derived nudge toward the tag command ("Tag your 6
    /// Farcaster things"). Unlike ask chips, tap PREFILLS the command —
    /// the name is the person's to type, and the write still waits behind
    /// the proposal's Apply (ruling 2026-07-10). Count is the source's
    /// WHOLE pile — that's what "tag <source> as X" proposes; the untagged
    /// pile is only the trigger.
    private struct OrganizeHint { let source: String; let count: Int }
    @State private var organizeHint: OrganizeHint?

    /// The invitation cycles only while the field is genuinely idle and empty —
    /// typing, answering, recording, or a proposal all stop it.
    private var cyclingActive: Bool {
        isOpen && !hasDraft && !answering && !isRecording && proposal == nil && !reduceMotion
    }

    /// One ask chip's staggered rise-in on open (delight, 2026-07-12).
    private struct ChipEntrance: ViewModifier {
        let index: Int
        let shown: Bool
        let reduceMotion: Bool
        func body(content: Content) -> some View {
            content
                .opacity(shown || reduceMotion ? 1 : 0)
                .offset(y: shown || reduceMotion ? 0 : 8)
                .animation(reduceMotion ? nil
                           : DS.Motion.standard.delay(Double(min(index, 8)) * 0.05),
                           value: shown)
        }
    }
    /// One-shot guard: a programmatic fill inserts more than 8 characters
    /// at once, which the draft onChange would read as a paste — and paste
    /// CAPTURES on send. fillDraft() sets it; onChange consumes it.
    @State private var prefilled = false

    /// The one door for setting the draft from code — the organize chip,
    /// tag completion, and the debug hooks. Writing `draft` directly trips
    /// the paste heuristic (review 2026-07-10: a completed long tag turned
    /// a typed command into a captured note).
    private func fillDraft(_ text: String) {
        prefilled = true
        draft = text
    }

    private var isRecording: Bool { voice.phase == .recording }
    private var hasDraft: Bool { !draft.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Tag completions for the word being typed — your real tags, prefix-
    /// matched on the draft's last token (2+ chars, typed path only).
    private var tagMatches: [String] {
        guard hasDraft, !pasted, !answering, proposal == nil else { return [] }
        guard let last = draft.split(separator: " ").last.map(String.init),
              last.count >= 2 else { return [] }
        let lower = last.lowercased()
        return tagPool
            .filter { $0.lowercased().hasPrefix(lower) && $0.lowercased() != lower }
            .prefix(3).map { $0 }
    }

    private func completeTag(_ tag: String) {
        DSHaptic.selection()
        var words = draft.split(separator: " ").map(String.init)
        if words.isEmpty { words = [tag] } else { words[words.count - 1] = tag }
        fillDraft(words.joined(separator: " ") + " ")
    }

    /// Builds the ask chips from what the corpus can answer TODAY. Empty
    /// corpus → no chips (the field is the invitation).
    private func computeSuggestions() {
        #if DEBUG
        // `-askStats "<key>:<n>[,…]|clear"` — seed the decay counters
        // headlessly (see AskMemory; self-guarded to once per launch), so
        // demotion verifies in one launch.
        AskMemory.seedFromLaunchArgs()
        // `-asksMade "<key>:<n>[,…]|clear"` — seed the proactive-minting
        // counter the same way, so the "keep it?" upgrade verifies in one
        // launch too.
        AskMemory.seedMadeFromLaunchArgs()
        #endif
        tagPool = tagCandidates()   // one corpus walk per open, not per keystroke
        var out: [AskOption] = []
        // One plain fetch, filtered in memory — a #Predicate can't compare
        // the Codable ThingKind enum (it throws at runtime, and try? made
        // the miss silent).
        let all = (try? modelContext.fetch(FetchDescriptor<Thing>())) ?? []
        // The greeting's stat line (ruling 4) — real counts off the fetch
        // just paid for. Empty corpus = empty line (the greeting stands
        // alone; a "0 things" boast would be dishonest warmth).
        if all.isEmpty {
            corpusSummary = ""
        } else {
            let sources = Set(all.map(\.source)).count
            let things = all.count.formatted()
            corpusSummary = "\(things) thing\(all.count == 1 ? "" : "s"), across \(sources) app\(sources == 1 ? "" : "s")."
        }
        // Context-aware lead (2026-07-12): if you opened the composer while
        // looking at one source's feed, its recap leads the chips — the
        // composer meets you where you are. Only when that source actually has
        // things to synthesize (honesty rule: a chip must answer).
        if let src = contextSource(), all.contains(where: { $0.source == src }) {
            out.append(AskOption(kind: "context", title: "What's new in \(src)?",
                                 glyph: "app.badge", memoryKey: "context:\(src)"))
        }
        let dayStart = Calendar.current.startOfDay(for: .now)
        // The feeds' pulse (2026-07-11): "What's going on?" synthesizes the
        // recent window across every source. Gated on the SAME computation
        // that will answer it — the chip can't drift from the ask it
        // teaches — and it needs two things to say anything. When it shows,
        // "What landed today?" sits out (near-duplicate recency asks would
        // crowd out the chips that teach counting and pinning).
        // The librarian's chip (prd §67 ⑥) — LEADS, and only when a real away
        // gap holds enough to say something. Gated on the same computation
        // that answers it, like every chip.
        let awayCount = StatusAsk.pulse("while i was away", things: all)?.pool.count ?? 0
        awayLanded = awayCount
        if awayCount >= 3 {
            out.insert(AskOption(kind: "away", title: "While I was away?",
                                 glyph: "sparkles"), at: 0)
        }
        let pulseChip = StatusAsk.pulse("what's going on", things: all)
            .map { $0.pool.count >= 2 } ?? false
        // The away chip suppresses its near-duplicates — two catch-up chips
        // would crowd out the ones that teach counting and showing.
        if awayCount >= 3 {
            // covered by "While I was away?"
        } else if pulseChip {
            out.append(AskOption(kind: "pulse", title: "What's going on?", glyph: "bolt"))
        } else if all.contains(where: { $0.capturedAt >= dayStart }) {
            out.append(AskOption(kind: "today", title: "What landed today?",
                                 glyph: "tray.and.arrow.down"))
        }
        // The watchlist chip (2026-07-14): watched tokens are the corpus' one
        // LIVE number — teach that the composer reads them. Gated on the same
        // things TokensAsk answers from, so the chip always answers.
        if all.contains(where: { $0.source == "Tokens" }) {
            out.append(AskOption(kind: "watchlist", title: "How's my watchlist?",
                                 glyph: "chart.line.uptrend.xyaxis"))
        }
        // The wallet chip (2026-07-15): gated on a watched address existing, so
        // WalletAsk always has holdings to answer with — the chip can't drift
        // from the ask it triggers.
        if !WalletStore.shared.addresses.isEmpty {
            out.append(AskOption(kind: "wallet", title: "How's my wallet?",
                                 glyph: "wallet.bifold"))
        }
        // Only asks the corpus can honestly answer right now. (Pinning left
        // the composer 2026-07-12: it's per-APP now, placed from the app's own
        // screen, not a phrase. "How many links this week?" died 2026-07-16 —
        // ruling: nobody cares; counting stays a typed power, never a tile.)
        // Top TWO tags now (was one, 2026-07-20) — a chip vocabulary as wide
        // as the corpus means more than one tag gets a one-tap path to kept.
        for tag in tagPool.prefix(2) {
            out.append(AskOption(kind: "showtag", title: "Show \(tag)",
                                 glyph: "tag", memoryKey: "showtag:\(tag)"))
        }
        // The overdue chip (2026-07-20) — mirrors KeptAskComposers.overdue's
        // own filter (light duplication, same precedent as elsewhere in this
        // function) so the tile can't offer what its composer would call
        // empty.
        if all.contains(where: { $0.mark != .done && ($0.source == "Reminders" || $0.source == "Todoist")
                                  && ($0.dueAt ?? .distantFuture) < .now }) {
            out.append(AskOption(kind: "overdue", title: "What's overdue?",
                                 glyph: "exclamationmark.circle"))
        }
        // The Noticed chip (2026-07-20) — the board's old "Noticed" card had
        // no home after the board retired (prd §131); this is its one way
        // back in. Tile-only: there's no natural typed trigger for a
        // spontaneous connection, so it's never in `recognizeKeptAskKind`.
        if let noticed = HomeInsightStore.shared.line, !noticed.isEmpty {
            out.append(AskOption(kind: "noticed", title: "Noticed",
                                 glyph: "sparkle"))
        }
        if !all.isEmpty {
            out.append(AskOption(kind: "week", title: "What's this week?",
                                 glyph: "calendar"))
        }
        // The organize invite (ruling 2026-07-10): the source with the most
        // things still wearing only their type tag (≥3) earns the nudge.
        // The label counts the source's WHOLE pile — what "tag <source> as
        // X" actually proposes. Skipped: "You" (as a query word it matches
        // far beyond its own things) and unfaithful names ("Reminders" is a
        // kind word — the command would match by kind across sources).
        var counts: [String: (untagged: Int, total: Int)] = [:]
        for thing in all where thing.source != "You" {
            counts[thing.source, default: (0, 0)].total += 1
            if thing.tags.count <= 1 { counts[thing.source, default: (0, 0)].untagged += 1 }
        }
        organizeHint = counts
            .filter { $0.value.untagged >= 3 && Organize.faithfulSourceQuery($0.key) }
            // Largest pile wins; the name breaks ties so the invite doesn't
            // change identity between opens.
            .max { ($0.value.total, $1.key) < ($1.value.total, $0.key) }
            .map { OrganizeHint(source: $0.key, count: $0.value.total) }
        // Already-kept asks lead as their own pills now (docs/agent-brief.md
        // ruling 4/5, `keptAskPills`) — offering one here too would show the
        // same question twice, once as a curated pill and once as a
        // suggestion (user ruling 2026-07-19: both coexist, but never for
        // the SAME ask).
        out.removeAll { KeptAskStore.shared.isKept($0.memoryKey) }
        // Tap-learning decay (ruling 2026-07-16, prd 95): an ask offered ten
        // opens without a tap steps behind the next qualifier — demoted by
        // a stable partition, never filtered, so a short grid still fills
        // with it. A tap resets its counter; exemptions (the away chip is
        // timely, not evergreen) live in AskMemory. The organize invite has
        // its own slot and gate.
        let ranked = out.filter { !AskMemory.neglected($0.memoryKey) }
                   + out.filter { AskMemory.neglected($0.memoryKey) }
        // Fill the 2×2 grid: three asks beside the organize invite when it's
        // earned, four when it isn't — the tiles read whole either way.
        suggestions = Array(ranked.prefix(organizeHint == nil ? 4 : 3))
        // A handed-off ask (a status chip's question) fills the field the
        // moment the sheet settles — the tiles never had a chance to be
        // tapped, so that open must not count against them.
        if chrome.askRequest == nil {
            AskMemory.shown(suggestions.map(\.memoryKey))
        }
        #if DEBUG
        NSLog("[Casberi] askTiles: %@%@",
              organizeHint.map { "hint:\($0.source) " } ?? "",
              suggestions.map(\.memoryKey).joined(separator: ","))
        #endif
    }

    /// "Saturday morning." — the day and its moment, ruled as the greeting's
    /// first line (docs/agent-brief.md ruling 4). The weekday comes from the
    /// current calendar/locale; the moment splits the day the way people
    /// actually say it (morning until noon, afternoon until 6, evening
    /// after) — no "Good ..." prefix, the period IS the warmth.
    private func timeGreeting(now: Date = .now) -> String {
        let weekday = now.formatted(.dateTime.weekday(.wide))
        let hour = Calendar.current.component(.hour, from: now)
        let moment = hour < 5 ? String(localized: "night")
                   : hour < 12 ? String(localized: "morning")
                   : hour < 18 ? String(localized: "afternoon")
                   : String(localized: "evening")
        return "\(weekday) \(moment)."
    }

    /// One conversation turn — the question as the answer's own TITLE, then
    /// its answer. Heading weight (was subhead-muted, fixed 2026-07-20):
    /// ruling 8 calls each answer a "sovereign screen", and its question is
    /// that screen's title — one step down from the greeting's own
    /// `.heading34` since this repeats per turn rather than leading the
    /// whole surface.
    @ViewBuilder
    private func convoTurn<Content: View>(question: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            if !question.isEmpty {
                Text(question)
                    .dsText(.heading17)
                    .foregroundStyle(DS.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Space.s4)
            }
            content()
        }
    }

    // The bubble's asymmetric corners: 24 / 24 / 10 / 24 (TL/TR/BR/BL).
    private var bubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 24, bottomLeadingRadius: 24,
            bottomTrailingRadius: 10, topTrailingRadius: 24,
            style: .continuous
        )
    }

    var body: some View {
        // The agent's own Stack (ruling 8): a real NavigationStack, not a
        // sheet — tapping content inside an answer pushes a generative
        // thing-view; the system back chevron pops it. genThingOpen is the
        // SAME environment hook Home's pinned rows already use (GenRenderer),
        // so every existing doc shape gets tap-to-drill-down for free.
        NavigationStack(path: $path) {
            Group {
                if isOpen { openBubble }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Opens UNFOCUSED (2026-07-12): the tray leads with the field's
            // invitation and the ask chips visible — tapping the field is
            // what raises the keyboard to ask.
            .overlay(alignment: .topTrailing) {
                // ✕ — the first exit (ruling 7). Only at the agent's own
                // root; a pushed thing-view relies on its system back chevron.
                if path.isEmpty {
                    Button {
                        close()
                    } label: {
                        Image(systemName: "xmark")
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textSecondary)
                            .padding(10)
                            .background(DS.fillFaint, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, DS.Space.s3)
                    .padding(.trailing, DS.Space.s4)
                }
            }
            .navigationDestination(for: String.self) { id in
                // Real generative thing-view — the real `ThingSheetView`,
                // reused as-is rather than a slimmer push-only variant (it
                // already dispatches every kind; a lighter copy would drift).
                // "Open in app" (its own existing verb machinery,
                // VerbDerivation) is the one thing allowed to lower the
                // agent from inside pushed content (ruling 9) — wrapping its
                // openURL environment is a plain SwiftUI hook, zero
                // ThingSheetView changes needed.
                if let thing = resolveThing(id) {
                    ThingSheetView(thing: thing)
                        .environment(\.openURL, OpenURLAction { url in
                            openURL(url)
                            onLowerAgent()
                            return .handled
                        })
                }
            }
        }
        .environment(\.genThingOpen) { id in path.append(id) }
    }

    // MARK: - Open

    private var openBubble: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The greeting (embedded sheet only) — frames the whole surface as
            // one question the tools and the field both answer, and gives the
            // sheet its warmth (design pass 2026-07-12, "B: greeting-led").
            // Hidden once a conversation is underway: the answer is the header.
            if embedded, turns.isEmpty, !answering, proposal == nil {
                // The greeting, as RULED (docs/agent-brief.md ruling 4,
                // built 2026-07-20 — the static "What now?" that shipped
                // first was a placeholder for this): the day and its moment
                // ("Saturday morning."), then the corpus as one warm stat
                // ("2,481 things, across 14 apps."). Deterministic, real,
                // recomputed each open — never a canned line.
                Text(timeGreeting())
                    .dsText(.heading34)
                    .foregroundStyle(DS.textPrimary)
                    .padding(.leading, DS.Space.s4)
                    // Clears the ✕ pinned top-trailing — "Wednesday
                    // afternoon." at display scale runs the full width and
                    // collided with it (caught on sim, 2026-07-20).
                    .padding(.trailing, 64)
                    .padding(.top, DS.Space.s2)
                    .settleIn()
                if !corpusSummary.isEmpty {
                    Text(corpusSummary)
                        .dsText(.callout15)
                        .foregroundStyle(DS.textSecondary)
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, 2)
                        .settleIn(delay: 0.05)
                }
                // The pairing line — teaches the sheet's dual nature (ask a
                // question, or write a fact and send it out) and keeps the
                // greeting from reading as an orphan label.
                Text("Ask about your things, or write something and send it to another app.")
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s2)
                    .settleIn(delay: 0.1)
            }
            // The content sizes to ITSELF (no filling scroll) so the sheet can
            // hug it — no stranded empty space. The answer conversation carries
            // its own capped scroll, so nothing overflows. (2026-07-12)
              VStack(alignment: .leading, spacing: 0) {

            // Ask chips moved DOWN to sit by the input (2026-07-12) — rendered
            // as `askChips` just above the bottom bar, near where you compose.

            // Tag completions — your real tags finish the word being typed.
            if !tagMatches.isEmpty {
                HStack(spacing: DS.Space.s2) {
                    ForEach(tagMatches, id: \.self) { tag in
                        Button { completeTag(tag) } label: {
                            Chip(text: tag, style: .tint, glyph: "tag")
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal, DS.Space.s4)
                .padding(.top, DS.Space.s2)
            }

            // The conversation (2026-07-12): answered asks stack as turns you
            // can keep following up on. The last answer stays LIVE (answerStream)
            // until you ask the next one or close — so a typewriter reveal never
            // gets cut. The scroll keeps the newest in view.
            if !turns.isEmpty || answering {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: DS.Space.s4) {
                            ForEach(turns) { turn in
                                convoTurn(question: turn.question) {
                                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                                        GenRender(id: "root", els: turn.els)
                                            .environment(\.genAgentAnswerContext, true)
                                        if turn.keyed { keyedBadge }
                                    }
                                }
                            }
                            if answering {
                                convoTurn(question: currentQuestion) {
                                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                                        // The librarian at work: the berry
                                        // breathes while the answer is in
                                        // flight — alive, not a spinner
                                        // (delight 2026-07-13).
                                        if inFlight {
                                            CasberiMark(size: 20)
                                                .breathing()
                                                .padding(.horizontal, DS.Space.s4)
                                                .transition(.opacity)
                                                .accessibilityLabel("Thinking")
                                        }
                                        GenRender(id: "root", els: answerStream.els)
                                            .environment(\.genProseStreaming, proseStreaming)
                                            // Cited rows glint once as they
                                            // mount — "I went and found
                                            // these", as a gesture. Live
                                            // answer only, so a scroll-back
                                            // never replays it.
                                            .environment(\.genCitationGlint, true)
                                            .environment(\.genAgentAnswerContext, true)
                                        // A keyed answer says so, always — the
                                        // badge is the honesty rule applied to
                                        // where the answer was made.
                                        if keyedCurrent, !inFlight { keyedBadge }
                                        if !proseStreaming, !inFlight {
                                            HStack(spacing: DS.Space.s2) {
                                                // The standing-ask verb (docs/agent-brief.md
                                                // ruling 5/12): mints a KEPT ASK — a pill on
                                                // the agent's rest screen that recomposes
                                                // fresh every open, wearing a dot when its
                                                // answer changed. Only offered when the
                                                // question matches a real, deterministic
                                                // composer (KeptAskComposers) — no dead
                                                // control once kept.
                                                if let kind = keepableAskKind {
                                                    // Proactive minting (2026-07-20): asked
                                                    // often enough (AskMemory.askedOften, the
                                                    // neglect counter's inverse), the quiet
                                                    // pill upgrades to a prompt that names WHY
                                                    // — same action, same component, just the
                                                    // label earning the attention a repeated
                                                    // ask deserves.
                                                    let askedOften = AskMemory.askedOften(kind)
                                                    Button {
                                                        DSHaptic.tap()
                                                        KeptAskStore.shared.keep(kind, title: currentQuestion)
                                                        keepableAskKind = nil
                                                    } label: {
                                                        Chip(text: askedOften
                                                                ? "You ask this a lot — keep it?"
                                                                : "Keep",
                                                             style: .tint,
                                                             glyph: askedOften ? "sparkles" : "pin.fill")
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                                // Save a settled synthesis as a note
                                                // (2026-07-12; relabelled 2026-07-19 — "Keep"
                                                // above is a different verb now): lands the
                                                // recap in the corpus so it isn't ephemeral.
                                                // The consent tap IS the save, like the parse
                                                // card's save-on-send.
                                                if !keptCurrent, currentStreamed,
                                                   let text = keepableText(answerStream.els) {
                                                    Button {
                                                        DSHaptic.tap()
                                                        keptCurrent = true
                                                        onKeepAnswer(text)
                                                    } label: {
                                                        Chip(text: "Save as a note", style: .tint,
                                                             glyph: "tray.and.arrow.down")
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                                // The BYO-key retry (prd §67) — a verb,
                                                // never a fallback: the question and its
                                                // matched things leave this iPhone only
                                                // on this tap, straight to the agent's
                                                // provider (Claude/ChatGPT/Gemini/Venice).
                                                if !keyedCurrent, keyAvailable,
                                                   !currentQuestion.isEmpty {
                                                    Button { askWithKey() } label: {
                                                        Chip(text: "Try with your key",
                                                             glyph: "key.fill")
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                            .padding(.horizontal, DS.Space.s4)
                                            // One settled VERB ROW (2026-07-20):
                                            // clear air above and below so
                                            // Keep / Save / Try-with-key read
                                            // as the answer's own action band,
                                            // not trailing content stuck to
                                            // the last row.
                                            .padding(.top, DS.Space.s3)
                                            .padding(.bottom, DS.Space.s2)
                                        }
                                    }
                                }
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    // The 300pt cap made sense hugging a SHEET's height; on
                    // the full-screen agent (ruling 3) there's a whole screen
                    // to use instead.
                    .frame(maxHeight: .infinity)
                    // Tapping empty space puts the keyboard away WITHOUT
                    // lowering the agent — a separate action from the ✕/⌄
                    // exits (ruling 7). Without this, the only tap that
                    // reached past the keyboard was wired to lowering the
                    // whole agent, so asking something and wanting to just
                    // SEE the answer meant leaving the agent entirely to get
                    // there (found and fixed in the throwaway prototype,
                    // ported verbatim). Buttons inside (Keep, chips, a
                    // drill-down row) still take their own tap first.
                    .onTapGesture { fieldFocused = false }
                    .onChange(of: answerStream.progress) { _, _ in
                        withAnimation(DS.Motion.standard) { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                    .onChange(of: turns.count) { _, _ in
                        withAnimation(DS.Motion.standard) { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
                .padding(.top, DS.Space.s2)
            }

            if let proposal {
                OrganizeProposalCard(
                    proposal: proposal,
                    onApply: { applyProposal(proposal) },
                    onCancel: {
                        withAnimation(DS.Motion.standard) { self.proposal = nil }
                    }
                )
                .padding(.top, DS.Space.s2)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Recording — the red dot, the clock, and the words arriving live.
            // Save keeps the piece; the chevron discards it.
            if isRecording {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    HStack(spacing: DS.Space.s2) {
                        Circle().fill(DS.destructive).frame(width: 8, height: 8)
                            .opacity(0.4 + 0.6 * abs(sin(voice.elapsed * 2)))
                        Text(String(format: "%d:%02d", Int(voice.elapsed) / 60, Int(voice.elapsed) % 60))
                            .dsText(.label12).foregroundStyle(DS.textSecondary)
                            .contentTransition(.numericText())
                        Text("Listening")
                            .dsText(.label12).foregroundStyle(DS.textTertiary)
                        Spacer()
                    }
                    if !voice.transcript.isEmpty {
                        Text(voice.transcript)
                            .dsText(.callout15).foregroundStyle(DS.textPrimary)
                            .lineLimit(4)
                    }
                }
                .padding(DS.Space.s3)
                .background(DS.fillFaint,
                            in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .padding(.horizontal, DS.Space.s4)
                .padding(.top, DS.Space.s3)
                .animation(DS.Motion.standard, value: voice.elapsed)
            }
            if voice.phase == .denied {
                Text("No mic access — allow Casberi in iOS Settings")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s2)
            }

            // Parse card — only for PASTED content (the capture path): it
            // previews what keeping will write. Typed words get answers, not
            // filing previews.
            if hasDraft && !answering && pasted {
                ParseCard(draft: draft, candidates: tagPool,
                          chosen: $chosenTags)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s3)
            }

              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.top, DS.Space.s3)

            // Kept asks (docs/agent-brief.md ruling 4/5) — the standing
            // questions someone chose to keep, leading the empty-field chips
            // as B1 pills wearing their own one-line signal. The existing
            // ranked/decayed suggestion grid still follows for asks not yet
            // kept (user ruling 2026-07-19: both coexist).
            keptAskPills
            // Chips sit right by the input — asks/commands you can fire from
            // where you compose (moved down 2026-07-12). The two bands are
            // mutually exclusive: askChips while the field is empty, takeChips
            // once there's typed text to carry out.
            askChips
            takeChips
            // The input, pinned to the bottom — a friendly rounded bar.
            inputBar
        }
        .frame(maxWidth: .infinity, alignment: .top)
        // Report the content's natural height so the hosting sheet hugs it.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
            if embedded { onHeight(h) }
        }
        // The bubble's surface, restructured (2026-07-11, device report:
        // keyboard up, no bubble — this time on Home; prd 44's underlay
        // didn't hold). Root cause: glassEffect renders the whole modified
        // view AS the glass element's content, so when the hardware morph
        // glitches, the content — and prd 44's underlay riding the same
        // view — vanish with it. Now the field and chips never enter the
        // glass: the solid ink is one background layer, the glass a clear
        // VENEER above it carrying the morph id. A failed morph can only
        // lose the veneer — the composer itself cannot disappear. Same
        // look (glass over ink), same FAB→bubble morph when it works.
        // The bubble's surface, third pass (2026-07-11): SOLID ink, no glass.
        // prd 44 put glass ON the content (device: bubble vanished — a
        // glitched morph loses the glass element's whole content); prd 52
        // split the glass into a clear veneer behind the content (sim: the
        // veneer FROSTS the bubble — iOS 26 hoists glass into its own layer
        // above app content, so "behind" isn't behind). Both failures are
        // the same lesson: the open composer cannot depend on the glass
        // pipeline. The FAB keeps its glass; the bubble is ink, and the
        // scale animation carries the open. Glass on the floating layer is
        // permitted, not required (§8).
        .background(embedded ? Color.clear : DS.surfaceSheet.opacity(0.97), in: bubbleShape)
        .clipShape(embedded ? AnyShape(Rectangle()) : AnyShape(bubbleShape))
        .scaleEffect(embedded ? 1 : (isOpen ? 1 : 0.3), anchor: .bottomTrailing)
        // The bar→surface morph (2026-07-20, `glassNamespace`) — a PLAIN
        // frame interpolation, deliberately NOT another glass-pipeline morph
        // (see the lesson just above: prd 44/52 both tried tying the open
        // animation to `glassEffect`/`glassEffectID` and broke on real
        // devices twice, because a glitched glass morph took the content
        // down with it). `matchedGeometryEffect` never touches glass
        // compositing — it only interpolates this container's own frame
        // from `AgentBar`'s last position, while the ink background above
        // and the content within render normally throughout. Embedded only —
        // the non-embedded bubble already has its own scale-driven open.
        .modifier(MorphMatch(ns: embedded ? glassNamespace : nil))
        .task(id: isOpen) {
            if isOpen {
                computeSuggestions()
                // Kept asks share AskMemory's own decay counters with the
                // suggestion tiles (ruling 5: "ignored asks decay dim") —
                // bumped once per open here, exactly how computeSuggestions()
                // bumps the tiles it actually shows. Never double-counted:
                // a kept kind is always excluded from `suggestions` (see
                // computeSuggestions()'s `KeptAskStore.shared.isKept` filter),
                // so a given key's counter only ever moves from one side.
                if !KeptAskStore.shared.order.isEmpty {
                    AskMemory.shown(KeptAskStore.shared.order)
                }
                // Kept asks' signal dots refresh on open too (not just on
                // foreground, docs/agent-brief.md Step 5) — the same
                // granularity AskMemory's own decay counters already use
                // (recomputed per open, never per keystroke). Fired
                // DETACHED, not awaited inline — a network-backed kept ask
                // (wallet/watchlist) can take several real seconds, and that
                // must never delay the chip-reveal animation below. Cheap,
                // synchronous kinds (away/showtag) update near-instantly
                // anyway; `KeptAskStore` is @Observable, so `keptAskPills`
                // simply re-renders whenever `currentDigests` lands, exactly
                // `HomeInsightStore`'s own "kick async, repaint on arrival"
                // shape.
                Task { @MainActor in
                    let all = (try? modelContext.fetch(FetchDescriptor<Thing>())) ?? []
                    await KeptAskStore.shared.refreshDigests(things: all, context: modelContext)
                }
                // Reset then reveal so the ask chips stagger in on each open.
                chipsAppeared = false
                try? await Task.sleep(for: .milliseconds(90))
                chipsAppeared = true
                #if DEBUG
                // `-composerDraft "<text>"` pre-fills the field on open —
                // headless reach for the typed state (the Open-in chips)
                // for screenshots and the screen sweep.
                if draft.isEmpty,
                   let text = UserDefaults.standard.string(forKey: "composerDraft"),
                   !text.isEmpty {
                    fillDraft(text)
                }
                #endif
            }
            await consumeAskRequest()
            await autoSendIfProbed()
            await pushIfProbed()
        }
        // The empty invitation cycles while the field is genuinely idle.
        .task(id: cyclingActive) {
            guard cyclingActive else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                if Task.isCancelled { break }
                withAnimation(DS.Motion.standard) {
                    placeholderIndex = (placeholderIndex + 1) % invitations.count
                }
            }
        }
    }

    /// A surface handed the shell an ask (chrome.ask — the weekend cover's
    /// week synthesis, prd 54): consume it once the bubble is up and send
    /// through the real answer path. fillDraft keeps the paste heuristic
    /// from reading the programmatic set as a capture.
    private func consumeAskRequest() async {
        guard isOpen, let query = chrome.askRequest else { return }
        chrome.askRequest = nil
        fillDraft(query)
        try? await Task.sleep(for: .milliseconds(400))   // let the bubble settle
        // Closing the bubble inside the settle window cancels this task; the
        // try? above swallows that CancellationError, so without this guard
        // commit() would fire an empty ask into a CLOSED composer and strand
        // "Thinking…" for the next open (review 2026-07-11).
        guard !Task.isCancelled, isOpen else { return }
        commit()
    }

    /// DEBUG hook: `simctl launch ... -uiAnswerProbe "what's my week"` opens
    /// the composer and sends that query through the real send path, so the
    /// in-app answer render can be screenshotted without a keyboard. Empty in
    /// release builds.
    private func autoSendIfProbed() async {
        #if DEBUG
        // `-composerDraft "…"` fills the field and stops — for a screenshot of
        // the typed command, before it's sent (no proposal, no answer).
        if isOpen, !didAutoSend,
           let d = UserDefaults.standard.string(forKey: "composerDraft") {
            didAutoSend = true
            // fillDraft, not `pasted = false`: onChange runs AFTER this
            // block, so a post-hoc reset was clobbered right back to true.
            fillDraft(d)
            return
        }
        // `-composerType "…"` types the string character by character (for a
        // screen recording of real typing), then sends after a beat.
        if isOpen, !didAutoSend,
           let t = UserDefaults.standard.string(forKey: "composerType") {
            didAutoSend = true
            try? await Task.sleep(for: .milliseconds(700))   // let the bubble settle
            for ch in t {
                draft.append(ch)
                try? await Task.sleep(for: .milliseconds(70))
            }
            try? await Task.sleep(for: .milliseconds(700))
            pasted = false
            commit()
            return
        }
        guard isOpen, !didAutoSend,
              let q = UserDefaults.standard.string(forKey: "uiAnswerProbe") else { return }
        didAutoSend = true
        // The probe is an utterance — answer, never save. fillDraft keeps
        // the paste heuristic from reading the one-shot set as a capture.
        fillDraft(q)
        try? await Task.sleep(for: .milliseconds(500))
        commit()
        #endif
    }

    /// DEBUG hook: `-agentThingProbe "<title prefix>"` pushes the agent's own
    /// Stack straight to a real thing's drill-down (`resolveThing` → the same
    /// `genThingOpen` path a tapped row takes) — the headless route to verify
    /// the NavigationStack push + real `ThingSheetView` render without a
    /// keyboard or a tap (mirrors RootShell's own `-openThing` title-prefix
    /// match, since a UUID changes every install but a title doesn't).
    private func pushIfProbed() async {
        #if DEBUG
        guard isOpen, path.isEmpty,
              let prefix = UserDefaults.standard.string(forKey: "agentThingProbe"),
              !prefix.isEmpty else { return }
        let all = (try? modelContext.fetch(FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]))) ?? []
        guard let match = all.first(where: { $0.title.hasPrefix(prefix) }) else {
            NSLog("[Casberi] agentThingProbe: no match for \"%@\"", prefix)
            return
        }
        NSLog("[Casberi] agentThingProbe: pushing \"%@\" (%@)", match.title, match.id.uuidString)
        path.append(match.id.uuidString)
        #endif
    }

    // MARK: - Actions

    /// Names what pasting would capture — "Paste link" beats "Paste" when the
    /// clipboard holds a URL. Detection never reads the pasteboard, so no
    /// system banner fires until the person chooses.
    private func close() {
        if isRecording { voice.stop(keep: false) }   // the chevron discards
        fieldFocused = false
        withAnimation(DS.Motion.standard) { isOpen = false }
        draft = ""      // close clears the draft (composer spec)
        answering = false
        proposal = nil
        chosenTags = []
        pasted = false
        chipsAppeared = false
        placeholderIndex = 0
        turns = []
        currentQuestion = ""
        keptCurrent = false
        keyedCurrent = false
        inFlight = false
        askGeneration += 1   // any in-flight answer Task retires silently
        path = NavigationPath()
        onLowerAgent()
    }

    /// The small honest mark a keyed answer wears — where it was made, stated
    /// plainly, on the answer itself and on its settled turn.
    private var keyedBadge: some View {
        HStack(spacing: DS.Space.s1) {
            Image(systemName: "key.fill").font(.system(size: 10))
            Text("Answered with your key")
        }
        .dsText(.label12)
        .foregroundStyle(DS.textTertiary)
        .padding(.horizontal, DS.Space.s4)
    }

    /// The BYO-key retry: the same question, re-answered by the person's own
    /// agent key (Claude, ChatGPT, Gemini, or Venice). The on-device answer
    /// settles into the thread first, so the two sit side by side — the tap
    /// is the consent, the badge is the receipt, and a failure is worded
    /// plainly (never faked).
    private func askWithKey() {
        let q = currentQuestion
        guard !q.isEmpty, !inFlight else { return }
        DSHaptic.tap()
        withAnimation(DS.Motion.standard) {
            if answering {
                turns.append(ConvoTurn(question: currentQuestion, els: answerStream.els,
                                       keyed: keyedCurrent))
            }
            answering = true
            inFlight = true
            keyedCurrent = true
            keptCurrent = false
            currentStreamed = false
            // keepableAskKind is NOT reset here: askWithKey() re-asks the
            // SAME currentQuestion, so the kind commit() already recognized
            // for it is still correct throughout the retry.
        }
        askGeneration += 1
        let gen = askGeneration
        answerStream.paint(["root = Stack([w])", "w = Insight(\"Asking with your key…\")"])
        Task { @MainActor in
            let doc = await answerWithKey(q)
            // Closed, or a newer ask overtook this one — retire silently.
            guard isOpen, gen == askGeneration else { return }
            inFlight = false
            keyAvailable = AgentKey.isConfigured
            if let doc {
                currentStreamed = true   // a keyed synthesis is keepable too
                answerStream.stream(doc)
            } else {
                keyedCurrent = false     // no keyed answer arrived — no badge
                answerStream.stream(["root = Stack([w])",
                                     "w = Insight(\"That didn't go through — check your key in Settings, or your connection.\")"])
            }
        }
    }

    // MARK: - Kept-ask pills (docs/agent-brief.md ruling 4/5 — B1)

    /// The standing questions someone chose to keep, as pill chips — a
    /// FAMILIAR pattern (over a plainer list) and DIFFERENTIATED from the
    /// app's own rows (user ruling 2026-07-19: chips are agent-language,
    /// rows/cards are app-language). Changed-first sort; a dot only when the
    /// kept ask's current digest doesn't match what was last seen (never a
    /// model judgment — a plain string compare, `KeptAskStore.changed`).
    /// Ruling 5's other half, wired in now: a pill nobody's tapped in
    /// `AskMemory.neglectThreshold` opens decay-dims, same counters the
    /// empty-composer suggestion tiles already use — `computeSuggestions()`
    /// excludes kept kinds, so a key's counter only ever moves from one side.
    /// A pill whose answer just changed never dims, even if it was neglected
    /// before — a fresh signal is worth noticing regardless of history.
    @ViewBuilder
    private var keptAskPills: some View {
        if isOpen, !hasDraft, !answering, !isRecording, proposal == nil,
           !KeptAskStore.shared.order.isEmpty {
            let sorted = KeptAskStore.shared.order.sorted { a, b in
                let store = KeptAskStore.shared
                let changedA = store.changed(a, digest: store.currentDigests[a] ?? "")
                let changedB = store.changed(b, digest: store.currentDigests[b] ?? "")
                return changedA != changedB ? changedA && !changedB
                                            : (store.titles[a] ?? "") < (store.titles[b] ?? "")
            }
            FlowRow(spacing: DS.Space.s2) {
                ForEach(sorted, id: \.self) { kind in
                    let store = KeptAskStore.shared
                    let digest = store.currentDigests[kind] ?? ""
                    let title = store.titles[kind] ?? kind
                    let changed = store.changed(kind, digest: digest)
                    let neglected = !changed && AskMemory.neglected(kind)
                    Button {
                        DSHaptic.selection()
                        store.markSeen(kind, digest: digest)
                        AskMemory.tapped(kind)
                        draft = title
                        commit()
                    } label: {
                        // Hero treatment (2026-07-20): these pills ARE the
                        // board's replacement — the standing per-app glance
                        // surface — so they earn real presence: callout-size
                        // title, roomier padding, and a CHANGED pill wears a
                        // full tint wash (not just its dot) so a live signal
                        // reads as a filled element against the steady gray
                        // of its unchanged neighbors. Still text-only chips
                        // (ruling 5's tripwire: never a thumbnail).
                        HStack(spacing: DS.Space.s2) {
                            if changed {
                                Circle().fill(DS.tint).frame(width: 7, height: 7)
                            }
                            Text(title)
                                .dsText(.callout15)
                                .foregroundStyle(changed ? DS.textPrimary : DS.textSecondary)
                            if !digest.isEmpty {
                                Text("· \(digest)")
                                    .dsText(.subhead13)
                                    .foregroundStyle(changed ? DS.textSecondary : DS.textTertiary)
                            }
                        }
                        .opacity(neglected ? 0.55 : 1)
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.vertical, DS.Space.s3)
                        .background(changed ? AnyShapeStyle(DS.tintDim) : AnyShapeStyle(DS.gray100),
                                    in: RoundedRectangle(cornerRadius: DS.Radius.control,
                                                         style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s3)
        }
    }

    // MARK: - Ask chips + input bar (chat grammar: by the bottom)

    /// The ask tiles (option A, 2026-07-16) — asks the corpus can answer now,
    /// plus the organize invite, as a bold 2×2 grid while the field is empty.
    /// The chip strip died here: it clipped its own labels ("How's m…"), and
    /// a suggestion you can't read isn't one. Each tile states its whole ask,
    /// wears a glyph naming what kind of answer it is, and is a real thumb
    /// target; the ONE featured tile (the organize invite) wears the solid
    /// tint — the grid's single accent, per the one-tint law.
    @ViewBuilder
    private var askChips: some View {
        if isOpen && !hasDraft && !answering && !isRecording,
           proposal == nil, !suggestions.isEmpty || organizeHint != nil {
            let hintLead = organizeHint != nil ? 1 : 0
            LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Space.s3),
                                GridItem(.flexible(), spacing: DS.Space.s3)],
                      spacing: DS.Space.s3) {
                if let hint = organizeHint {
                    AskTile(glyph: "tag",
                            title: "Tag your \(hint.count) \(hint.source) things",
                            featured: true) {
                        DSHaptic.selection()
                        fillDraft("tag \(hint.source.lowercased()) as ")
                        fieldFocused = true
                    }
                    .modifier(ChipEntrance(index: 0, shown: chipsAppeared, reduceMotion: reduceMotion))
                }
                ForEach(Array(suggestions.enumerated()), id: \.offset) { i, ask in
                    // The librarian's tile rolls its real count up as it
                    // appears — "Catch me up — 14 things" arriving digit by
                    // digit (delight 2026-07-13). The tap still sends the
                    // canonical "While I was away?" ask.
                    if ask.kind == "away", awayLanded >= 3 {
                        AskTile(glyph: "sparkles", title: "Catch me up",
                                rollCount: awayLanded) {
                            DSHaptic.selection()
                            draft = ask.title
                            commit()
                        }
                        .modifier(ChipEntrance(index: i + hintLead, shown: chipsAppeared, reduceMotion: reduceMotion))
                    } else {
                        AskTile(glyph: ask.glyph, title: ask.title) {
                            DSHaptic.selection()
                            AskMemory.tapped(ask.memoryKey)
                            draft = ask.title
                            commit()
                        }
                        .modifier(ChipEntrance(index: i + hintLead, shown: chipsAppeared, reduceMotion: reduceMotion))
                    }
                }
            }
            .padding(.horizontal, DS.Space.s4)
            // Clear air between the greeting and the grid — the tiles are a
            // separate band (ask), not stuck to the header.
            .padding(.top, DS.Space.s4)
            .padding(.bottom, DS.Space.s2)
        }
    }

    // MARK: - Input bar (chat grammar: pinned to the bottom)

    /// The mic, the ask field, and a send button that appears once there's
    /// something to send — a soft rounded bar so the surface feels inviting.
    private var inputBar: some View {
        HStack(spacing: DS.Space.s2) {
            // ⌄ — the second exit (ruling 7): the thing that raised the
            // agent lowers it. Only ever visible at the agent's own root —
            // this bar is part of `openBubble`, which a NavigationStack push
            // hides behind the pushed screen automatically. A bare glyph, no
            // drawn circle (fix 2026-07-20) — the mic is the one true
            // circular button beside the field now; ruling 7 already has
            // this exit "on trial" against ✕, so it reads as the lighter of
            // the two.
            Button {
                close()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.textTertiary)
                    .frame(width: 32, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Lower")

            Button {
                if isRecording { commit() }   // the live mic is STOP + keep
                else { DSHaptic.tap(); Task { await voice.start() } }
            } label: {
                Image(systemName: isRecording ? "stop.circle.fill" : "mic")
                    .font(.system(size: 17))
                    .foregroundStyle(isRecording ? DS.destructive : DS.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(DS.fillFaint, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRecording ? "Stop and keep" : "Record a voice note")

            TextField("", text: $draft, axis: .vertical)
                // The invitation cycles through what the composer can DO —
                // ask, find, recap, tag — so the empty field teaches its
                // range instead of reading as one dead line (wired to the
                // long-standing `invitations` cycle, 2026-07-16). While a doc
                // is up, it reads "Ask about this…" instead (ruling 8: a
                // follow-up grounds in the current answer, via the SAME
                // `lastAnswerHits` mechanism the answer closures already use).
                .placeholder(when: !hasDraft) {
                    Text(answering || !turns.isEmpty ? String(localized: "Ask about this…")
                                                     : invitations[placeholderIndex])
                        .dsText(.body17).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                        .id(placeholderIndex)
                        .transition(.opacity)
                }
                .dsText(.body17)
                .foregroundStyle(DS.textPrimary)
                .tint(DS.tint)
                .focused($fieldFocused)
                .onChange(of: draft) { old, new in
                    // Return SENDS (chat grammar). A vertical-axis field's
                    // return key types "\n" and never submits — so hitting the
                    // keyboard's return silently did nothing, the heart of the
                    // "send rarely fires" report (2026-07-12). The one-character
                    // newline insertion IS the send gesture; a paste keeps its
                    // newlines (it inserts more than one character at once).
                    if new.count - old.count == 1, new.hasSuffix("\n") {
                        draft = String(new.dropLast())
                        if hasDraft { commit() }
                        return
                    }
                    if prefilled { prefilled = false }
                    else if new.count - old.count > 8 { pasted = true }
                    if new.isEmpty { pasted = false }
                    detectDraftDate()
                }
                .lineLimit(1...5)

            // The send dot is ALWAYS present — grey and waiting when the field
            // is empty (tap = focus the field), springing to tint the moment
            // there's something to send. A visible affordance beats a control
            // that pops out of nowhere (v2 pass, 2026-07-12). With typed text
            // it wears the word "Ask" (2026-07-16): the verb was invisible,
            // and "does typing save?" was a real question — the label answers
            // it. A live recording keeps the bare arrow: stopping SAVES the
            // voice note, and an "Ask" label there would lie.
            Button {
                if hasDraft || isRecording { commit() } else { fieldFocused = true }
            } label: {
                HStack(spacing: DS.Space.s1) {
                    if hasDraft && !isRecording {
                        Text("Ask")
                            .dsText(.label12).fontWeight(.semibold)
                    }
                    Image(systemName: "arrow.up")
                        .font(.system(size: hasDraft && !isRecording ? 12 : 15, weight: .bold))
                        .symbolEffect(.bounce, value: hasDraft || isRecording)
                }
                .foregroundStyle(hasDraft || isRecording ? .white : DS.textTertiary)
                .padding(.horizontal, hasDraft && !isRecording ? DS.Space.s3 : 0)
                .frame(minWidth: 32)
                .frame(height: 32)
                .background(hasDraft || isRecording ? AnyShapeStyle(DS.tint)
                                                    : AnyShapeStyle(DS.fillFaint),
                            in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(hasDraft && !isRecording ? "Ask" : "Send")
        }
        .padding(.leading, DS.Space.s2)
        .padding(.trailing, DS.Space.s2)
        .padding(.vertical, DS.Space.s2)
        // The hero of the sheet, by tone and shadow alone (the ladder — never
        // by line): an elevated field, no ring. Focus shows in the cursor and
        // the keyboard; state shows in the send dot.
        .background(DS.background100, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: DS.cardShadow, radius: 10, x: 0, y: 3)
        .animation(DS.Motion.standard, value: hasDraft || isRecording)
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
    }

    // MARK: - Send to (the typed text leaves with the jump)

    /// A question is the Ask button's job — the Send-to band sits out so the
    /// one honest exit is obvious. Conservative: a trailing "?" or a leading
    /// question word.
    private var draftIsQuestion: Bool {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasSuffix("?") { return true }
        let first = text.split(separator: " ").first.map(String.init) ?? ""
        return ["what", "who", "when", "where", "why", "how", "how's",
                "did", "does", "do", "is", "are", "can", "show", "find"].contains(first)
    }

    /// The "Send to" chips (2026-07-16, third form of this band — see
    /// TakeTool): shown the moment there's typed text that isn't a question,
    /// in the ask chips' slot — the two bands are the field's two exits, and
    /// only one is ever visible. What you typed is a FACT bound for another
    /// app; the text rides the jump (Messages/Mail body, Google query,
    /// Calendar at the detected date) or the clipboard where no URL carries
    /// it (the flash says so). A found date earns a receipt line — proof the
    /// Calendar jump will land on the right day.
    @ViewBuilder
    private var takeChips: some View {
        if isOpen && hasDraft && !answering && !isRecording, proposal == nil,
           !draftIsQuestion {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.s2) {
                        Text("Send to")
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textTertiary)
                        // Chunkier pills than the shell Chip — the same bold
                        // grammar as the ask tiles (option A, 2026-07-16), so
                        // the field's two exits read as one design.
                        ForEach(TakeTool.all) { tool in
                            Button { runTake(tool) } label: {
                                HStack(spacing: DS.Space.s2) {
                                    Image(systemName: tool.glyph)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(DS.tint)
                                    Text(tool.label)
                                        .dsText(.callout15).fontWeight(.semibold)
                                        .foregroundStyle(DS.textPrimary)
                                }
                                .padding(.horizontal, DS.Space.s3 + 2)
                                .frame(height: 40)
                                .background(DS.gray100, in: Capsule(style: .continuous))
                            }
                            .buttonStyle(PressSpring())
                        }
                    }
                    .padding(.horizontal, DS.Space.s4)
                }
                if let date = detectedDate {
                    Text("Found a time: \(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute()))")
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                        .padding(.horizontal, DS.Space.s4)
                }
            }
            .padding(.top, DS.Space.s4)
            .padding(.bottom, DS.Space.s2)
        }
    }

    /// Re-reads the draft for a date (NSDataDetector) — called on each edit.
    /// Cheap at typing cadence; cached in `detectedDate` so the band and the
    /// Calendar jump read one value.
    private func detectDraftDate() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            detectedDate = nil
            return
        }
        let range = NSRange(text.startIndex..., in: text)
        detectedDate = detector.firstMatch(in: text, range: range)?.date
    }

    /// A Send-to chip jumps out to that app with the typed text and closes
    /// the composer — it never writes there and nothing lands in Casberi
    /// (rulings: people create in their own tools; we jump, we don't write).
    /// Where no URL can carry the text, the chip copies it first and the
    /// flash says exactly that (honesty rule: no silent blank jump).
    private func runTake(_ tool: TakeTool) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let url = tool.makeURL(text, detectedDate) else { return }
        DSHaptic.tap()
        if tool.copiesFirst {
            UIPasteboard.general.string = text
            chrome.flash("Copied — paste it in \(tool.label)")
        }
        openURL(url)
        close()
    }

    private func applyProposal(_ proposal: OrganizeProposal) {
        guard proposal.canApply else { return }
        let (summary, undo) = Organize.apply(proposal, context: modelContext)
        chrome.flash(summary, tone: .success, action: .init(label: "Undo", run: undo))
        close()
    }

    private func commit() {
        if isRecording {
            // Voice is a capture path — send keeps the piece.
            if let piece = voice.stop(keep: true) {
                onCommitVoice(piece.transcript, piece.sourceRef)
            }
            close()
        } else if pasted, OrganizeCommand.parse(draft) == nil {
            // Paste is a capture path — send keeps what came in. A command-
            // shaped draft wins over the flag, though: the organize chip
            // prefills "tag <source> as " and the person may PASTE the name
            // (review 2026-07-10) — that paste must not turn the command
            // into a captured note. The proposal card stays the consent.
            onCommit(Array(chosenTags))
            close()
        } else if let intent = NavigateCommand.parse(draft, tags: tagPool,
                                                     sources: knownSources()) {
            // A place, named — go there. Reads only (a navigation), so no
            // proposal needed; the composer closes and the shell moves.
            DSHaptic.selection()
            draft = ""
            onNavigate(intent)
            close()
        } else if let command = OrganizeCommand.parse(draft) {
            // An organize command — propose, never execute. The card below
            // shows exactly what would change; Apply is the consent.
            let proposed = Organize.propose(command, context: modelContext)
            fieldFocused = false   // input phase is over — dismiss the cursor
            withAnimation(DS.Motion.standard) {
                answering = false
                proposal = proposed
            }
            draft = ""
            #if DEBUG
            // `-organizeApply YES` shows the proposal for a beat, then fires
            // the real Apply — so a screen recording captures the whole flow:
            // proposal → Apply → toast → the renamed tag on Home.
            if UserDefaults.standard.bool(forKey: "organizeApply") {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(2200))
                    applyProposal(proposed)
                    NSLog("Organize probe: %@ · applied=%d", proposed.headline,
                          proposed.canApply ? 1 : 0)
                }
            }
            #endif
        } else {
            // Typed words are an utterance — the answer streams. A follow-up
            // first settles the current LIVE answer into the thread so the Q&A
            // stacks (2026-07-12); the last answer stays live until the next
            // ask or close, so its typewriter reveal never gets cut.
            if answering {
                turns.append(ConvoTurn(question: currentQuestion, els: answerStream.els,
                                       keyed: keyedCurrent))
            }
            answering = true
            currentQuestion = draft
            keptCurrent = false
            currentStreamed = false
            keyedCurrent = false
            keepableAskKind = nil   // recomputed at settle, for THIS question
            inFlight = true
            askGeneration += 1
            let gen = askGeneration
            let q = draft
            draft = ""              // clear the field so a follow-up is ready
            // No placeholder doc while in flight (fix 2026-07-20): the old
            // `Insight("Thinking…")` painted the answer card's full tintDim
            // chrome around a word — an empty-looking navy card. The
            // breathing berry beside the question header (rendered whenever
            // `inFlight`, just above the GenRender) is the whole loading
            // state now; the first real content to appear IS the answer.
            answerStream.paint([])
            Task { @MainActor in
                // Organize-ish wording the strict parser missed ("put
                // everything about lisbon under Trip") — the model fills the
                // SAME proposal form; the write still waits for Apply.
                if OrganizeLLM.looksOrganizeish(q),
                   let command = await OrganizeLLM.extract(q) {
                    // Closed, or a newer ask overtook this one mid-extraction.
                    guard isOpen, gen == askGeneration else { return }
                    let proposed = Organize.propose(command, context: modelContext)
                    fieldFocused = false
                    withAnimation(DS.Motion.standard) {
                        answering = false
                        inFlight = false
                        proposal = proposed
                    }
                    draft = ""
                    return
                }
                var streamed = false
                let finalDoc = await answer(q) { partialDoc in
                    // Prose arriving live — paint each growing snapshot; the
                    // Insight breathes its dot while this fires (§2). A stale
                    // ask's partials never paint over a newer one.
                    guard gen == askGeneration else { return }
                    streamed = true
                    currentStreamed = true   // a real synthesis — keepable
                    proseStreaming = true
                    answerStream.paint(partialDoc)
                }
                // A newer ask (or close) overtook this one — its answer owns
                // the stream now; this one retires silently.
                guard gen == askGeneration else { return }
                // Prose already painted its way in; settle on the final text.
                // A lookup or the fallback never streamed, so reveal it with
                // the typewriter (unchanged behaviour).
                proseStreaming = false
                inFlight = false
                keyAvailable = AgentKey.isConfigured   // one read per settle
                // One more fetch per settle (not per keystroke) — same
                // precedent `computeSuggestions()` already sets for a plain
                // corpus-wide read.
                let settledThings = (try? modelContext.fetch(FetchDescriptor<Thing>())) ?? []
                keepableAskKind = recognizeKeptAskKind(q, in: settledThings)
                // Proactive minting (2026-07-20): count each keepable ask
                // actually made, so a question asked often can upgrade its
                // quiet Keep pill to a "you ask this a lot" prompt. Counted
                // ONLY for keepable kinds — the counter's key space IS the
                // kind space, so an unkeepable ask has nothing to count
                // toward.
                if let kind = keepableAskKind { AskMemory.asked(kind) }
                if streamed { answerStream.paint(finalDoc) }
                else { answerStream.stream(finalDoc) }
                fieldFocused = true     // ready for the next follow-up
            }
        }
    }
}

/// The parse card — chip label + fields + candidate tags, assembling with a
/// stagger as the person types. The chip stays a label until the parse earns
/// correction (PRD: intent switch parked).
struct ParseCard: View {
    let draft: String
    let candidates: [String]
    @Binding var chosen: Set<String>

    private var isLink: Bool { Capture.detectURL(in: draft) != nil }
    private var kindLabel: String { isLink ? "Link" : "Note" }
    private var titlePreview: String {
        let line = draft.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? draft
        return line.count > 60 ? String(line.prefix(60)) + "…" : line
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s2) {
                Chip(text: kindLabel, style: .tint)
                Text(titlePreview)
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }
            .mountIn()

            if !candidates.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.s2) {
                        ForEach(candidates, id: \.self) { tag in
                            let active = chosen.contains(tag)
                            // A Button, not .onTapGesture (same fix the Feed
                            // source chips carry, 2026-07-12): tap recognition
                            // for a chip inside a horizontal ScrollView is flaky
                            // — taps drop and the toggle "sticks."
                            Button {
                                if active { chosen.remove(tag) } else { chosen.insert(tag) }
                            } label: {
                                Chip(text: tag, style: active ? .tint : .neutral)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .mountIn()
            }
        }
        .padding(DS.Space.s3)
        .background(DS.fillFaint,
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}

/// A pill chip — the composer's and shell's smallest interactive unit.
struct Chip: View {
    enum Style { case tint, neutral }
    let text: String
    var style: Style = .neutral
    var glyph: String? = nil

    var body: some View {
        HStack(spacing: DS.Space.s1) {
            if let glyph {
                Image(systemName: glyph).font(.system(size: 12))
            }
            Text(text).dsText(.label12)
        }
        .foregroundStyle(style == .tint ? DS.tint : DS.textPrimary)
        .padding(.horizontal, DS.Space.s3)
        .frame(height: 28)
        .background(style == .tint ? DS.tintDim : DS.gray100,
                    in: Capsule(style: .continuous))
    }
}

/// One bold ask tile (option A, 2026-07-16) — the empty sheet's 2×2 grid
/// unit. The glyph sits top-leading, the whole ask reads unclipped at the
/// bottom (the chip strip's mid-word truncation died with it). `featured`
/// is the grid's single solid-tint tile — the organize invite. The optional
/// rolling count is the librarian's catch-up tile: the digits climb to the
/// real away total right after the tile lands (numericText, once).
struct AskTile: View {
    let glyph: String
    let title: String
    var featured = false
    /// When set, the title reads "<title> — N things" with N rolling in.
    var rollCount: Int? = nil
    let action: () -> Void
    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Image(systemName: glyph)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(featured ? AnyShapeStyle(.white) : AnyShapeStyle(DS.tint))
                Spacer(minLength: 0)
                Group {
                    if rollCount != nil {
                        Text("\(title) — \(shown) things")
                            .contentTransition(.numericText(value: Double(shown)))
                    } else {
                        Text(title)
                    }
                }
                .dsText(.callout15).fontWeight(.semibold)
                .foregroundStyle(featured ? Color.white : DS.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.Space.s3 + 2)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .background(featured ? AnyShapeStyle(DS.tint) : AnyShapeStyle(DS.gray100),
                        in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        }
        .buttonStyle(PressSpring())
        .onAppear { roll(to: rollCount) }
        // The suggestions rebuild while the composer is open — a grown away
        // pool re-rolls to the new count instead of going stale (review
        // catch 2026-07-13).
        .onChange(of: rollCount) { _, new in roll(to: new) }
        .accessibilityLabel(rollCount.map { "\(title) — \($0) things" } ?? title)
    }

    private func roll(to count: Int?) {
        guard let count else { return }
        if reduceMotion { shown = count } else {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.9).delay(0.35)) {
                shown = count
            }
        }
    }
}

// MARK: - Placeholder helper

private extension View {
    @ViewBuilder
    func placeholder<P: View>(when show: Bool, @ViewBuilder _ placeholder: () -> P) -> some View {
        ZStack(alignment: .leading) {
            if show { placeholder() }
            self
        }
    }
}

/// The organize proposal — what a typed command would change, waiting on
/// Apply. The matched things list plainly; the write is one tap away and
/// the toast it earns carries Undo.
private struct OrganizeProposalCard: View {
    let proposal: OrganizeProposal
    let onApply: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if let blocked = proposal.blocked {
                Text(blocked)
                    .dsText(.callout15).foregroundStyle(DS.attention)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // The headline states the change and its scope ("… — 8 things");
                // the itemised list left the card (ruling) — the count is the
                // consent, and the toast carries Undo if it's wrong.
                Text(proposal.headline)
                    .dsText(.heading17).foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if proposal.things.isEmpty {
                    Text("Nothing to change.")
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                }
            }
            HStack(spacing: DS.Space.s2) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .dsText(.label12).foregroundStyle(DS.textSecondary)
                    .padding(.horizontal, DS.Space.s3).frame(height: 30)
                    .background(DS.gray100, in: Capsule(style: .continuous))
                    .buttonStyle(PressSpring())
                if proposal.canApply {
                    Button("Apply", action: onApply)
                        .dsText(.label12).foregroundStyle(.white)
                        .padding(.horizontal, DS.Space.s4).frame(height: 30)
                        .background(DS.tint, in: Capsule(style: .continuous))
                        .buttonStyle(PressSpring())
                }
            }
        }
        .padding(DS.Space.s3)
        .background(DS.surfaceSheet,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// A minimal wrapping row — kept-ask pills flow onto several lines and
/// SwiftUI has no built-in for it at this deployment target.
private struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 {
                x = 0
                y += lineH + spacing
                lineH = 0
            }
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
        }
        return CGSize(width: maxW, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineH + spacing
                lineH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
        }
    }
}
