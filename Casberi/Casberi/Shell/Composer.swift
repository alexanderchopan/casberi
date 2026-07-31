import SwiftUI
import SwiftData

/// What a keyed answer produced (2026-07-21) — the rendered document, plus
/// what the agent actually DID to make it. `searchedWeb` and `imagesSeen`
/// are observed, never assumed (see `AgentAnswerResult`), so the badge that
/// reports them can't over-claim: an agent that could search but didn't
/// never says it did.
struct KeyedAnswer {
    let doc: [String]
    var searchedWeb = false
    var imagesSeen = 0
}

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
    /// Commit keeps a pasted draft (M6: save writes to us). Tags ride only
    /// as #hashtags inside the text itself (prd §178 — no filing chips).
    var onCommit: () -> Void
    /// A finished voice note: transcript + the audio file's sourceRef.
    var onCommitVoice: (String, String) -> Void = { _, _ in }
    /// Answers a query, returning the final AnswerStream document (engine
    /// grammar). While a synthesis answer streams, it calls `onProseDoc` with
    /// each growing doc so prose renders live; lookups and the non-AI fallback
    /// never call it and just return the doc to reveal at once.
    var answer: (_ query: String, _ onProseDoc: @escaping ([String]) -> Void) async -> [String] = { _, _ in [] }
    /// The BYO-key retry (prd §67): answers the same question with the person's
    /// own agent key, device→API direct. Streams: while the answer is coming
    /// in, `onProseDoc` is called with each growing snapshot so it paints
    /// live, the same contract `answer` gives for the on-device path
    /// (2026-07-21). nil when the key or the network failed — the composer
    /// words that honestly. The verb only shows when a key is configured; it
    /// never fires on its own.
    var answerWithKey: (_ query: String, _ onProseDoc: @escaping ([String]) -> Void) async -> Result<KeyedAnswer, AgentAnswerFailure> = { _, _ in .failure(.noKey) }
    /// Your real tags, from the corpus — typed-ask completion, the "Show
    /// <tag>" chips, and navigation matching read these (never a write).
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
    /// ask, find, recap — so it teaches its range instead of reading as one
    /// dead line (delight, 2026-07-12). These are honest capability
    /// invitations, not data claims; the corpus-derived ask CHIPS below carry
    /// the specifics you can tap.
    @State private var placeholderIndex = 0
    private let invitations = [
        "Ask, or say what to do",
        "What did I save this week?",
        "Find that thing I pasted",
        "Recap my month",
    ]
    /// The cycling pool actually shown: the real-corpus examples when `open`
    /// computed some, else the static invitations (before first compute, or
    /// an empty corpus). Never empty, so the placeholder's modulo is safe.
    private var activeInvitations: [String] {
        invitationPool.isEmpty ? invitations : invitationPool
    }
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
        /// What the agent actually did to make it (2026-07-21) — carried onto
        /// the settled turn so scrolling back doesn't lose the receipt.
        var searchedWeb = false
        var imagesSeen = 0
        /// This turn is a failure notice, not an answer — so it wears NO
        /// provenance badge. Without this a keyed failure fell through to
        /// the on-device badge and claimed "Answered on this iPhone" over a
        /// message that says the opposite (caught on sim, 2026-07-21).
        var failed = false
        /// A FIND, not an answer (2026-07-25) — `Retriever.rank` ran and the
        /// matches are painted as they are. No model saw the question, so the
        /// badge says "Matched" rather than "Answered": the difference between
        /// a ranked list of your own things and a sentence something wrote is
        /// exactly the kind of thing the honesty rule exists to keep visible.
        var found = false
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
    /// What the CURRENT keyed answer actually did (2026-07-21) — observed
    /// from the provider's own stream, so the badge reports rather than
    /// assumes. Reset per ask alongside `keyedCurrent`.
    @State private var keyedSearchedWeb = false
    @State private var keyedImagesSeen = 0
    /// The current "answer" is really a failure notice — no provenance badge
    /// belongs on it (2026-07-21). Reset at the start of every ask.
    @State private var answerFailed = false
    /// The current result came from Find, not from an answer (2026-07-25) —
    /// `Retriever.rank` alone, no model. Drives the badge's wording and is
    /// carried onto the settled turn, so scrolling back never relabels a
    /// deterministic match as something that was written for you.
    @State private var foundCurrent = false
    /// The exact doc the last Find painted — kept only so `-findProbe` can log
    /// it verbatim. Never read by the UI.
    @State private var lastFindDoc: [String] = []
    /// True once a keyed answer has landed in this conversation, so a typed
    /// FOLLOW-UP stays on the agent that just answered instead of silently
    /// dropping back to the on-device model — which never saw the keyed turn
    /// and would answer "which of those…" with no idea what "those" means
    /// (2026-07-21). Cleared by `close()` with the rest of the conversation.
    @State private var conversationIsKeyed = false
    /// Monotonic ask generation — every new ask (and close) bumps it, and an
    /// answer Task that finishes after a newer ask started must not paint
    /// over the live answer (review 2026-07-13: a slow first answer was
    /// clobbering the follow-up that overtook it).
    @State private var askGeneration = 0
    /// Whether a key is configured, mirrored once per settled answer — the
    /// chip gate can't afford a Keychain round-trip per render (typing a
    /// follow-up re-renders per keystroke).
    @State private var keyAvailable = false
    /// The one-tap version of the same consent (2026-07-31, prd §242): a
    /// person who chose "Ask with your key" from the TYPED-DRAFT band, before
    /// either answer exists, gets the on-device answer first (unchanged —
    /// it's free, instant, private, and stays the default source of truth)
    /// and the keyed retry fires itself the moment that settles, via the
    /// `inFlight` watcher below, instead of waiting to be noticed and tapped
    /// a second time in the settled verb row. Set at the SAME moment as a
    /// normal `commit()`, so the tap that sets it IS the consent (prd §67's
    /// rule — nothing leaves this iPhone until a deliberate tap — is kept,
    /// just moved earlier).
    @State private var pendingKeyedFollowUp = false
    /// The kept-ask KIND the current question would mint, computed once per
    /// settled answer (same reason `keyAvailable` is settle-cached, not a
    /// per-render computed property: a corpus fetch per render would be
    /// wasteful during a streaming reveal). nil when the question doesn't
    /// match a keepable shape, or it's already kept.
    @State private var keepableAskKind: String?
    /// The one related follow-up an answer offers (2026-07-22, §177) — a
    /// wallet answer → "What about gas?", a source recap → "Synthesize it
    /// instead" — teaching the next step at the moment it's most wanted. A
    /// small deterministic map (`nextAsk(for:in:)`), never a model; nil when
    /// the answer has no natural follow-up. Set at settle, cleared on the
    /// next send.
    private struct NextAsk { let label: String; let query: String }
    @State private var nextAsk: NextAsk?
    /// One-shot: the Keep chip morphs to a checkmark for a beat before it
    /// retires (delight, 2026-07-21) — the mint earns a felt moment instead
    /// of just vanishing the instant it's tapped.
    @State private var keepJustLanded = false
    /// The first-ever kept ask earns its own line, sibling to "Your first
    /// thing" (RootShell) — persisted so it fires exactly once per install.
    @AppStorage("composer.firstKeptAsk.done") private var firstKeptAskDone = false
    /// A deterministic flavor line under the greeting's corpus stat — an
    /// anniversary or a real threshold just crossed, never invented (delight,
    /// 2026-07-21). nil most opens; recomputed alongside `corpusSummary`.
    @State private var greetingFlavorLine: String?
    /// Deals one small berry shower over a genuinely large "while I was
    /// away" haul — an arrival worth marking, the same vocabulary the wallet
    /// pass already uses for NFT/portfolio arrivals (prd §79).
    @State private var awayRainTrigger = 0
    /// Guards the away rain to once per open — a follow-up re-ask of the
    /// same away question must not replay it.
    @State private var awayRainPlayedThisOpen = false
    /// The FIRST brief ever, deals its own small shower (delight, 2026-07-22)
    /// — a real, provable, one-time event (mirrors the `bloom.seen.<source>`
    /// idiom `MainSurface` already uses for a source's first-ever landing),
    /// so it can never replay. A separate trigger from `awayRainTrigger` on
    /// purpose — that one's name and doc comment are specific to the away
    /// haul; reusing it for an unrelated moment would make a future reader
    /// wonder why "away" rain fired for a brief.
    @State private var firstBriefRainTrigger = 0

    /// The keepable text of a synthesis answer — a synthesis is one Insight
    /// carrying the prose (RootShell's proseDoc). Only that shape is worth
    /// keeping: a lookup answer IS the things, which already live in the feed;
    /// a short status line or "Thinking…" isn't a recap. nil otherwise.
    private func keepableText(_ els: GenEls) -> String? {
        guard let insight = els.values.first(where: { $0.comp == "Insight" }) else { return nil }
        let text = insight.str(0)
        return text.count >= 40 ? text : nil
    }

    /// True when the settled doc is RootShell's honest "nothing matches"
    /// fallback (`retrievalDoc`'s empty branch) — both its lines start
    /// "Nothing " (genSafe strips quotes/newlines, never the leading word).
    /// Gates the settle haptic and the away-haul rain (delight, 2026-07-21):
    /// a real find earns the tick, a miss earns nothing.
    private func docHasFallback(_ lines: [String]) -> Bool {
        lines.contains { $0.contains("Insight(\"Nothing ") }
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
        if TodayBrief.matches(question), !things.isEmpty {
            // Gated on a non-empty corpus for the same reason every other
            // recognizer is gated on its own answer existing — keeping a
            // "How's my day?" that can only ever say "nothing landed" would
            // be a dead pill.
            kind = "today"
        } else if TokensAsk.matches(question) {
            kind = "watchlist"
        } else if WalletAsk.matches(question) {
            kind = "wallet"
        } else if WalletDeFiAsk.matches(question) {
            kind = "walletdefi"
        } else if UniswapAsk.matches(question) {
            kind = "walletuniswap"
        } else if WalletGasAsk.matches(question) {
            kind = "walletgas"
        } else if SafeAsk.matches(question) {
            kind = "walletsafe"
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
        } else if KeptAskComposers.matchesUpcoming(q),
                  things.contains(where: { $0.mark != .done && ($0.dueAt ?? .distantPast) >= .now }) {
            // Gated on a real future deadline existing, the same way every other
            // recognizer is gated on its own answer being non-empty — typing it
            // with nothing ahead falls through to the normal answer path rather
            // than minting a keepable ask that would only ever say "nothing".
            kind = "upcoming"
        } else if let (target, _) = KeptAskComposers.namedAskTarget(question, things: things),
                  target.hasRealThings(in: things) {
            // A named source/publisher/category ask (2026-07-22: "synthesize
            // my Verge feed", "what happened in BBC" — widened from the
            // original "what's new in Calendar"/"how's my GitHub" shape,
            // which only ever recognized a whole BRIDGE, never a publisher
            // within one). The verb ("synthesize" vs "what's new") only
            // matters to the LIVE answer path (`RootShell.answerDocument`,
            // same recognizer) — a kept pill always re-runs the deterministic
            // recap regardless of which verb minted it, so the `_` here is
            // correct: keeping never cares whether this was a synthesis ask.
            kind = target.keptKind
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

    /// The one related follow-up to offer after an answer (§177) — a small
    /// deterministic map from the answer's own shape to the next natural ask,
    /// the same job the composer's context-aware lead chip does at open,
    /// extended to the moment just after an answer. nil when there's no clean
    /// pairing. Never the model; each pairing is a fixed, always-answerable
    /// next step (the paired ask honestly handles its own empty case).
    private func nextAsk(for question: String, in things: [Thing]) -> NextAsk? {
        // Wallet ⇄ its sibling reads.
        if WalletGasAsk.matches(question) {
            return NextAsk(label: "How's my wallet?", query: "how's my wallet")
        }
        if WalletAsk.matches(question) {
            return NextAsk(label: "What about gas?", query: "what have I spent on gas")
        }
        if TokensAsk.matches(question), !WalletStore.shared.addresses.isEmpty {
            return NextAsk(label: "How's my wallet?", query: "how's my wallet")
        }
        // The day brief → the overnight catch-up (its natural neighbor).
        if TodayBrief.matches(question) {
            return NextAsk(label: "While I was away?", query: "while I was away")
        }
        // A source/publisher RECAP → offer the synthesis of the same thing
        // (the verb it didn't use). Skipped when it already synthesized.
        if let (target, synth) = KeptAskComposers.namedAskTarget(question, things: things),
           !synth, OnDeviceModel.isAvailable {
            return NextAsk(label: "Synthesize it instead", query: "synthesize \(target.name)")
        }
        return nil
    }

    @State private var proseStreaming = false
    @State private var answering = false
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
    /// The DOOR a chip opens — used only to keep the four slots from filling
    /// with four flavors of the same thing (2026-07-22): the diversity pass
    /// prefers spanning shapes over stacking one. Derived from `kind`, never
    /// stored, so no call site has to name it.
    private enum AskShape { case recency, money, tasks, entity, insight }

    private struct AskOption {
        let kind: String
        let title: String
        let glyph: String
        let memoryKey: String
        /// A cheap, SYNCHRONOUS digest ("· 3") computed at open (2026-07-22)
        /// — parity with the kept pills, which have carried a digest since
        /// §132. nil where no honest cheap count exists (wallet/watchlist read
        /// live prices/holdings async; §83 forbids a stale number wearing a
        /// fresh face, so they simply show none rather than a lie).
        var signal: String?

        /// An event-driven chip (2026-07-22) — a busy publisher, a real
        /// moment. It LEADS, is exempt from neglect decay (it's timely, not
        /// evergreen, like "away"), and wears a tint dot so "happening now"
        /// reads as happening. Derived from `kind`, not stored — one source of
        /// truth, so a new timely kind is a one-line switch, never a
        /// remembered constructor flag.
        var timely: Bool { kind == "handle" }

        /// What the tap actually SENDS — the display `title` for every chip
        /// except the timely publisher one, which shows a SHORTENED name but
        /// must send the CANONICAL full handle (from `memoryKey`) so the
        /// answer path resolves the exact publisher the chip named, not a
        /// fuzzy near-match by total volume (§174's `bestHandle` ranks by
        /// history; `busyPublisher` ranks by recency — they can disagree).
        /// Mirrors the away chip's own label/query split.
        var query: String {
            guard kind == "handle" else { return title }
            return "What happened in \(memoryKey.dropFirst("handle:".count))?"
        }

        var shape: AskShape {
            switch kind {
            case "wallet", "watchlist":        return .money
            case "overdue", "upcoming":        return .tasks
            case "away", "pulse", "today", "week": return .recency
            case "noticed":                    return .insight
            default:                           return .entity  // context/category/showtag/handle
            }
        }

        init(kind: String, title: String, glyph: String, memoryKey: String? = nil,
             signal: String? = nil) {
            self.kind = kind
            self.title = title
            self.glyph = glyph
            self.memoryKey = memoryKey ?? kind
            self.signal = signal
        }
    }
    @State private var suggestions: [AskOption] = []
    /// Real-corpus example phrasings mixed into the empty field's cycling
    /// invitation (2026-07-22) — teaches the widened ask vocabulary
    /// ("synthesize my Verge feed") by naming things that actually exist and
    /// would answer, never a canned claim. Recomputed per open alongside
    /// `tagPool`/`corpusSummary`.
    @State private var invitationPool: [String] = []
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

    /// The one predicate for "the composer is idle and showing its rest-screen
    /// chrome" — open, nothing typed, nothing recording, no answer in flight.
    /// The ask chips, the kept pills, and the placeholder cycle all read it, so
    /// they can't drift (they each hand-rolled this conjunction before §181).
    /// `keepBrief` folds in the brief LANDING (prd §181) — the one answer state
    /// that KEEPS its chips — for the two that dock beside the brief; the
    /// placeholder cycle passes `false`, deliberately, because the landing's
    /// field already reads a static "Ask about this…" rather than cycling.
    private func restChrome(keepBrief: Bool) -> Bool {
        isOpen && !hasDraft && !isRecording && (!answering || (keepBrief && briefLanding))
    }

    /// The invitation cycles only while the field is genuinely idle and empty —
    /// typing, answering, or recording all stop it (and the brief landing, whose
    /// field reads "Ask about this…" statically — `keepBrief: false`).
    private var cyclingActive: Bool {
        restChrome(keepBrief: false) && !reduceMotion
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

    /// The one door for setting the draft from code — tag completion and
    /// the debug hooks. Writing `draft` directly trips the paste heuristic
    /// (review 2026-07-10: a completed long tag turned a typed command into
    /// a captured note).
    private func fillDraft(_ text: String) {
        prefilled = true
        draft = text
    }

    private var isRecording: Bool { voice.phase == .recording }
    private var hasDraft: Bool { !draft.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The Today brief shown as the composer's LANDING — auto-seeded on open
    /// (RootShell's agent-bar tap) or tapped from the whisper, settled, and not
    /// yet followed up (prd §181, user: "make daily brief be the default when a
    /// user opens the agent"). This is the one answer state that still shows
    /// the docked ask chips and keeps the keyboard down: opening the agent
    /// should read as "here's your day, ask anything" — the brief as a screen
    /// to take in, with every ask still one glance away. The moment a follow-up
    /// is asked (turns grows) or a keyed retry runs, it's an ordinary
    /// conversation and the docked chips retire, exactly as before.
    private var briefLanding: Bool {
        answering && !inFlight && answerStream.completed && turns.isEmpty
            && TodayBrief.matches(currentQuestion)
    }

    /// The ask kinds the Today brief ALREADY answers on screen — its money hero
    /// is "how's my wallet", its movers tile is "how's my watchlist", its next
    /// tile is "what's overdue", and the whole screen is "what landed today".
    private static let briefAnswers: Set<String> = ["wallet", "watchlist", "overdue", "today"]

    /// The chips as actually docked. Beneath the brief LANDING they drop the
    /// asks the brief is already answering in view (prd §187, user: "it also
    /// has two wallet chips which is redundant" — the money hero and the
    /// watchlist tile were both on screen while chips offered to fetch each
    /// again). Offering a chip for an answer the person is looking at is the
    /// chip-shaped form of a dead control: it can only ever re-state what's
    /// already there, so the row spends its width on what the brief DIDN'T say.
    /// Everywhere else the full set stands.
    private var dockedSuggestions: [AskOption] {
        guard briefLanding else { return suggestions }
        return suggestions.filter { !Self.briefAnswers.contains($0.kind) }
    }

    /// Tag completions for the word being typed — your real tags, prefix-
    /// matched on the draft's last token (2+ chars, typed path only).
    private var tagMatches: [String] {
        guard hasDraft, !pasted, !answering else { return [] }
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
            greetingFlavorLine = nil
        } else {
            let sources = Set(all.map(\.source)).count
            let things = all.count.formatted()
            corpusSummary = "\(things) thing\(all.count == 1 ? "" : "s"), across \(sources) app\(sources == 1 ? "" : "s")."
            greetingFlavorLine = Self.greetingFlavor(all: all)
        }
        // One busy-publisher scan per open, shared by the timely chip below
        // and the placeholder examples (both want the same dominant handle).
        let busy = busyPublisher(in: all)
        invitationPool = computeInvitationPool(all, busy: busy)
        // Context-aware lead (2026-07-12): if you opened the composer while
        // looking at one source's feed, its recap leads the chips — the
        // composer meets you where you are. Only when that source actually has
        // things to synthesize (honesty rule: a chip must answer).
        if let src = contextSource(), all.contains(where: { $0.source == src }) {
            // A source with its own signature ask leads with THAT ask, not the
            // generic recap (user ruling 2026-07-21, prd §149: one ask per
            // subject — standing on the Wallet feed, "What's new in Wallet?"
            // recaps the feed already behind the sheet while "How's my
            // wallet?" reads what the feed can't, and the grid can't afford
            // both). The signature chips' own appends below skip themselves
            // once one has led here.
            if src == "Wallet", !WalletStore.shared.addresses.isEmpty {
                out.append(AskOption(kind: "wallet", title: "How's my wallet?",
                                     glyph: "wallet.bifold"))
            } else if src == "Tokens" {
                out.append(AskOption(kind: "watchlist", title: "How's my watchlist?",
                                     glyph: "chart.line.uptrend.xyaxis"))
            } else {
                let recent = all.filter { $0.source == src
                    && $0.capturedAt >= Date.now.addingTimeInterval(-3 * 86_400) }.count
                out.append(AskOption(kind: "context", title: "What's new in \(src)?",
                                     glyph: "app.badge", memoryKey: "context:\(src)",
                                     signal: sig(recent)))
            }
            // A category sibling (2026-07-20) — only when it's a meaningfully
            // BROADER ask than the single-source lead above (more than one
            // source in the category), else it would just repeat the same
            // question in different words.
            if let offer = BridgeCatalog.offers.first(where: { $0.name == src }) {
                let cat = BridgeCatalog.category(of: offer)
                let sourcesInCat = Set(BridgeCatalog.offers
                    .filter { BridgeCatalog.category(of: $0) == cat }.map(\.name))
                if sourcesInCat.count > 1, all.contains(where: { sourcesInCat.contains($0.source) }) {
                    out.append(AskOption(kind: "category", title: "How's my \(cat) stuff?",
                                         glyph: "square.grid.2x2", memoryKey: "category:\(cat)"))
                }
            }
        }
        // A TIMELY chip (2026-07-22): a publisher unusually busy in the recent
        // window — a feed that dropped a burst of stories, an account that
        // went off. Event-driven, so it LEADS and is neglect-exempt; it also
        // does double duty as the teaching chip for the widened per-publisher
        // vocabulary (§174), naming a REAL entity that answers ("What happened
        // in The Verge?"). Honest by construction: it fires only when one
        // handle genuinely dominates a recent burst, and ages out on its own
        // as that burst recedes past the window. Skipped once kept, like any
        // chip (the `handle:` kind matches the kept store).
        if let busy, !KeptAskStore.shared.isKept("handle:\(busy.handle)") {
            // Display the SHORT name ("DealNews", not "DealNews - DealNews:
            // Best Daily Deals…") — a feed pads its title, and the raw one
            // overflows the chip. The tap still resolves: `namedAskTarget`
            // fuzzy-matches "dealnews" back to the full handle (§174), and the
            // memoryKey keeps the full handle so keep/dedup stay exact.
            out.append(AskOption(kind: "handle",
                                 title: "What happened in \(shortPublisher(busy.handle))?",
                                 glyph: "newspaper", memoryKey: "handle:\(busy.handle)",
                                 signal: sig(busy.count)))
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
        let awayPulse = StatusAsk.pulse("while i was away", things: all)
        let awayCount = awayPulse?.pool.count ?? 0
        awayLanded = awayCount
        if awayCount >= 3 {
            // The away chip's signal names WHAT landed, not just how many
            // (2026-07-22) — a mention count is the fact worth teasing (the
            // module doctrine, §166, at chip scale). Mentions computed off
            // the same pool that answers, so it can't drift.
            let mentions = awayPulse?.pool.filter { $0.socialContext == "mention" }.count ?? 0
            // Names WHAT landed, not a bare count — the away chip's signal is
            // richer than `sig()`'s "· N" (it earns "· N new, M mentions").
            let awaySignal = mentions > 0 ? "· \(awayCount) new, \(mentions) mentions"
                                          : "· \(awayCount) new"
            out.insert(AskOption(kind: "away", title: "While I was away?",
                                 glyph: "sparkles", signal: awaySignal), at: 0)
        }
        let todayCount = all.filter { $0.capturedAt >= dayStart }.count
        // The "What's going on?" chip RETIRED with §193: that phrase is now the
        // name of the screen the agent opens onto, and a chip offering to fetch
        // the screen you are already looking at is a dead control wearing a
        // pill. `TodayBrief.matches` routes the typed phrase to that screen, so
        // nothing is lost — the ask just stopped being worth a chip.
        //
        // The away chip still suppresses its near-duplicate: two catch-up chips
        // would crowd out the ones that teach counting and showing.
        if awayCount < 3, todayCount > 0 {
            out.append(AskOption(kind: "today", title: "What landed today?",
                                 glyph: "tray.and.arrow.down", signal: sig(todayCount)))
        }
        // The watchlist chip (2026-07-14): watched tokens are the corpus' one
        // LIVE number — teach that the composer reads them. Gated on the same
        // things TokensAsk answers from, so the chip always answers.
        if all.contains(where: { $0.source == "Tokens" }),
           !out.contains(where: { $0.kind == "watchlist" }) {
            out.append(AskOption(kind: "watchlist", title: "How's my watchlist?",
                                 glyph: "chart.line.uptrend.xyaxis"))
        }
        // The wallet chip (2026-07-15): gated on a watched address existing, so
        // WalletAsk always has holdings to answer with — the chip can't drift
        // from the ask it triggers.
        if !WalletStore.shared.addresses.isEmpty,
           !out.contains(where: { $0.kind == "wallet" }) {
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
            let n = all.filter { thing in
                thing.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
            }.count
            out.append(AskOption(kind: "showtag", title: "Show \(tag)",
                                 glyph: "tag", memoryKey: "showtag:\(tag)",
                                 signal: sig(n)))
        }
        // The overdue chip (2026-07-20) — mirrors KeptAskComposers.overdue's
        // own filter (light duplication, same precedent as elsewhere in this
        // function) so the tile can't offer what its composer would call
        // empty.
        let overdueCount = all.filter { $0.mark != .done && ($0.source == "Reminders" || $0.source == "Todoist")
            && ($0.dueAt ?? .distantFuture) < .now }.count
        if overdueCount > 0 {
            out.append(AskOption(kind: "overdue", title: "What's overdue?",
                                 glyph: "exclamationmark.circle", signal: sig(overdueCount)))
        }
        // …and its forward half (2026-07-21). Same duplication precedent, same
        // week horizon `KeptAskComposers.upcoming` uses, so the tile and its
        // composer can never disagree about whether there's anything to say.
        if let horizon = Calendar.current.date(byAdding: .day, value: 7, to: .now) {
            let upcomingCount = all.filter { t in
                guard t.mark != .done, let when = t.dueAt else { return false }
                return when >= .now && when <= horizon
            }.count
            if upcomingCount > 0 {
                out.append(AskOption(kind: "upcoming", title: "What's coming up?",
                                     glyph: "clock.badge", signal: sig(upcomingCount)))
            }
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
            let weekAgo = Date.now.addingTimeInterval(-7 * 86_400)
            let weekCount = all.filter { $0.capturedAt >= weekAgo }.count
            out.append(AskOption(kind: "week", title: "What's this week?",
                                 glyph: "calendar", signal: sig(weekCount)))
        }
        // Already-kept asks lead as their own pills now (docs/agent-brief.md
        // ruling 4/5, `keptAskPills`) — offering one here too would show the
        // same question twice, once as a curated pill and once as a
        // suggestion (user ruling 2026-07-19: both coexist, but never for
        // the SAME ask).
        out.removeAll { KeptAskStore.shared.isKept($0.memoryKey) }
        // Tap-learning decay (ruling 2026-07-16, prd 95): an ask offered ten
        // opens without a tap steps behind the next qualifier — demoted by
        // a stable partition, never filtered, so a short grid still fills
        // with it. A tap resets its counter; exemptions (a timely chip is
        // timely, not evergreen) live in AskMemory.
        let ranked = out.filter { !AskMemory.neglected($0.memoryKey) }
                   + out.filter { AskMemory.neglected($0.memoryKey) }
        // 7, not 4, since the row became a horizontal SCROLL (§187): width no
        // longer costs height, and the brief landing filters several of these
        // back out (`dockedSuggestions` drops what the brief already answers),
        // so a 4-slot set could dock as a single lonely chip.
        suggestions = selectSuggestions(from: ranked, slots: 7)
        // What this open actually OFFERED, for the decay counters (§175). A
        // handed-off ask (a status chip's question) fills the field and HIDES
        // the chip row — the tiles never had a chance to be tapped, so that
        // open must not count against them.
        //
        // The brief landing is the one exception (§187): it hands off an ask
        // AND docks the chips in view, so those chips genuinely were offered.
        // Without this branch the decay would have quietly stopped running
        // altogether the moment the agent started opening onto the brief —
        // every open now hands off, so `askRequest == nil` would never again
        // be true on the main path and no chip could ever decay. Counted
        // MINUS the kinds the brief answers, since `dockedSuggestions` drops
        // those and they never appear.
        if let handedOff = chrome.askRequest {
            if TodayBrief.matches(handedOff) {
                AskMemory.shown(suggestions
                    .filter { !Self.briefAnswers.contains($0.kind) }
                    .map(\.memoryKey))
            }
        } else {
            AskMemory.shown(suggestions.map(\.memoryKey))
        }
        #if DEBUG
        NSLog("[Casberi] askTiles: %@",
              suggestions.map { $0.memoryKey + ($0.timely ? "*" : "") + ($0.signal ?? "") }
                  .joined(separator: ","))
        #endif
    }

    /// Fills the grid so the slots span DOORS, not four flavors of one
    /// (2026-07-22). Timely chips lead (they earned their slot by a real
    /// moment); a daypart nudge floats the moment's natural ask up; then the
    /// rest fill by ROUND-ROBIN across shapes, so a pool heavy in one kind
    /// (three tag chips, say) doesn't crowd out the money/time/task doors.
    /// A shape only doubles up once every other shape is exhausted — the grid
    /// still fills to `slots` when the pool is thin, never leaving a hole.
    private func selectSuggestions(from ranked: [AskOption], slots: Int) -> [AskOption] {
        var leads = ranked.filter { $0.timely || $0.kind == "away" }
        var rest = ranked.filter { !($0.timely || $0.kind == "away") }
        // Daypart nudge (2026-07-22): the moment's natural ask floats to the
        // front of `rest` (never past a timely lead) so the top slot tends to
        // match the hour — "What landed today?" in the evening, the week recap
        // on Friday. A stable move, not a reshuffle: everything else keeps its
        // rank. The morning belongs to "How's my day?", which the whisper
        // already owns on the shell — so the chips defer there rather than
        // competing, and only the evening/Friday nudges live here.
        if let preferred = daypartPreferredKind(),
           let i = rest.firstIndex(where: { $0.kind == preferred }) {
            rest.insert(rest.remove(at: i), at: 0)
        }
        // Round-robin across shapes as one STABLE SORT: tag each option with
        // how many of its own shape preceded it (its "round"), then sort by
        // round. Swift's sort is stable, so within a round the original rank
        // order holds — which is the whole point. Round 0 is one-of-each-shape
        // in rank order, round 1 the second-of-each, and so on, so a pool
        // heavy in one shape only doubles up after every other shape has had
        // a turn.
        var seen: [AskShape: Int] = [:]
        let diversified = rest
            .map { opt -> (round: Int, opt: AskOption) in
                defer { seen[opt.shape, default: 0] += 1 }
                return (seen[opt.shape, default: 0], opt)
            }
            .sorted { $0.round < $1.round }
            .map(\.opt)
        // Timely leads first, then the diversified rest; the whole list is
        // capped to the grid. `leads` is already rank-ordered by `ranked`.
        leads.append(contentsOf: diversified)
        return Array(leads.prefix(slots))
    }

    /// The kind whose ask best matches the current hour, or nil. Deliberately
    /// tiny: evening leans to "what landed today", Friday to the week recap.
    /// Morning is intentionally absent — the whisper capsule owns the day
    /// brief there, so a competing chip would just say the same thing twice.
    private func daypartPreferredKind() -> String? {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: .now)
        // 18:00 = "evening", the same boundary `timeGreeting` already uses.
        // weekday 6 = Friday, a Sun–Thu/Fri work-week assumption baked in as
        // a bare literal — fine for a low-stakes ranking nudge; revisit if it
        // ever needs locale sensitivity (`Calendar.firstWeekday`).
        let weekday = cal.component(.weekday, from: .now)
        if weekday == 6 { return "week" }
        if hour >= 18 { return "today" }
        return nil
    }

    /// The publisher (RSS feed, Substack, watched social account — all in
    /// `Thing.authorHandle`) that dominated the recent window, when one
    /// clearly did (2026-07-22). "Recent" is the frozen away window when one
    /// holds, else the last 24h; "dominated" means ≥5 things AND at least
    /// double the next-busiest handle, so an ordinarily-chatty feed doesn't
    /// trip it every day — only a genuine burst. nil otherwise (no chip).
    private func busyPublisher(in all: [Thing]) -> (handle: String, count: Int)? {
        let start = AppVisit.away?.lowerBound ?? Date.now.addingTimeInterval(-24 * 3600)
        var counts: [String: Int] = [:]
        for t in all where t.capturedAt >= start {
            guard let raw = t.authorHandle?.trimmingCharacters(in: .whitespaces),
                  !raw.isEmpty else { continue }
            counts[raw, default: 0] += 1
        }
        let sorted = counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
        guard let top = sorted.first, top.value >= 5 else { return nil }
        let runnerUp = sorted.count > 1 ? sorted[1].value : 0
        guard top.value >= runnerUp * 2 else { return nil }
        return (top.key, top.value)
    }

    /// The cycling placeholder's pool for THIS open — the static invitations
    /// plus real-corpus examples that teach the widened vocabulary by naming
    /// things that exist and would answer (2026-07-22). A busy publisher
    /// earns "Try: synthesize my <feed> feed"; a watched token earns a
    /// per-token ask. Honest by construction: every added line names a real
    /// entity the answer path resolves.
    private func computeInvitationPool(_ all: [Thing],
                                       busy: (handle: String, count: Int)?) -> [String] {
        var pool = invitations
        if let busy {
            pool.append(String(localized: "Try: synthesize my \(shortPublisher(busy.handle)) feed"))
        }
        if let token = all.first(where: { $0.source == "Tokens" }),
           !token.title.isEmpty {
            // `TokensAsk.symbol(of:)` — the one parser of the "Name · $TICKER"
            // watch-title format (a bare space-split grabs the NAME's first
            // word, so "Wrapped Bitcoin · $WBTC" would read "Wrapped").
            pool.append(String(localized: "How's \(TokensAsk.symbol(of: token.title)) doing?"))
        }
        return pool
    }

    /// A chip's trailing count signal ("· 3"), or nil for zero — the one
    /// place the "· " glyph format lives, so the separator changes in one
    /// spot, not eight.
    private func sig(_ n: Int) -> String? { n > 0 ? "· \(n)" : nil }

    /// A publisher's name trimmed to something that reads in a one-line
    /// invitation — "Ars Technica - All content" → "Ars Technica". Cuts at
    /// the first separator publishers pad their feed titles with.
    private func shortPublisher(_ handle: String) -> String {
        for sep in [" - ", " – ", " — ", " | ", ": "] {
            if let r = handle.range(of: sep) { return String(handle[..<r.lowerBound]) }
        }
        return handle
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

    /// A real, deterministic flavor line under the greeting's corpus stat —
    /// never a canned line, same register as §5's "Quiet so far today."
    /// Two honest sources, checked in order (at most one line per open):
    /// the corpus's actual anniversary (its oldest capture's month/day
    /// falling today, one-plus years on), or a real count threshold just
    /// crossed. Neither claims anything that isn't literally true of the
    /// corpus right now.
    private static let milestoneThresholds = [50, 100, 500, 1_000, 5_000, 10_000, 25_000, 50_000]
    private static let milestoneSeenKey = "composer.greetingMilestoneSeen"

    private static func greetingFlavor(all: [Thing], now: Date = .now) -> String? {
        let cal = Calendar.current
        if let oldest = all.map(\.capturedAt).min() {
            let oldComps = cal.dateComponents([.month, .day], from: oldest)
            let nowComps = cal.dateComponents([.month, .day], from: now)
            let years = cal.dateComponents([.year], from: oldest, to: now).year ?? 0
            if oldComps.month == nowComps.month, oldComps.day == nowComps.day, years >= 1 {
                return "\(years) year\(years == 1 ? "" : "s") since your first thing."
            }
        }
        let count = all.count
        if let crossed = milestoneThresholds.last(where: { $0 <= count }) {
            let seen = UserDefaults.standard.integer(forKey: milestoneSeenKey)
            if crossed > seen {
                UserDefaults.standard.set(crossed, forKey: milestoneSeenKey)
                return "\(crossed.formatted()) things banked."
            }
        }
        return nil
    }

    /// One conversation turn — the question as the answer's own TITLE, then
    /// its answer. Heading weight (was subhead-muted, fixed 2026-07-20):
    /// ruling 8 calls each answer a "sovereign screen", and its question is
    /// that screen's title — one step down from the greeting's own
    /// `.heading34` since this repeats per turn rather than leading the
    /// whole surface.
    @ViewBuilder
    private func convoTurn<Content: View>(question: String, animateIn: Bool = false,
                                          @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            if !question.isEmpty {
                Group {
                    // The Today brief wears a MASTHEAD, not the typed question
                    // (2026-07-22). The whisper capsule promises "Your
                    // Wednesday brief"; landing on a screen titled "How's my
                    // day?" broke that continuity — §165a's lesson (name the
                    // artifact) applied one screen deeper. The eyebrow states
                    // the window the brief actually covers, which no other
                    // answer needs to say.
                    if TodayBrief.matches(question) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(briefWindowLine())
                                .dsText(.subhead13)
                                .foregroundStyle(DS.textTertiary)
                            Text(DayBrief.title())
                                .dsText(.heading22)
                                .foregroundStyle(DS.textPrimary)
                                // The capsule's words travel here (prd §167a)
                                // — the SAME id RootShell's proxy title (and,
                                // before it, the whisper capsule's own title)
                                // carry, so when this real masthead mounts it
                                // simply takes over the geometry pairing and
                                // the proxy quietly fades away underneath it.
                                .modifier(WhisperTitleMorph(ns: glassNamespace))
                        }
                    } else {
                        Text(question)
                            .dsText(.heading17)
                            .foregroundStyle(DS.textPrimary)
                    }
                }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Space.s4)
                    // The question lift (delight, 2026-07-21): a freshly-sent
                    // ask rises into its header rather than popping cold —
                    // the felt hand-off from field to answer. Settled turns
                    // (scroll-back) never animate; this plays once, for the
                    // turn that just became live.
                    .transition(animateIn
                                ? .move(edge: .bottom).combined(with: .opacity)
                                : .identity)
            }
            content()
        }
    }

    /// A follow-up asked from INSIDE an answer (the Today brief's residue
    /// line). Sends through the same `commit()` every other ask uses, so it
    /// pushes a fresh answer onto the agent's Stack (ruling 8) instead of
    /// ejecting anywhere — `fillDraft`, not a raw `draft` write, so the paste
    /// heuristic can't read the programmatic set as a capture.
    private func askFromAnswer(_ query: String) {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        DSHaptic.selection()
        fillDraft(query)
        commit()
    }

    /// "since 9:40 pm" — the eyebrow. Names the WINDOW the screen measured,
    /// which is the one thing a reader can't infer from the modules themselves
    /// (an overnight window and a since-midnight one produce the same-looking
    /// screen from very different spans).
    ///
    /// The weekday and date used to lead this line, back when the screen was
    /// "Your Wednesday brief" and a dated edition is what it was. With the
    /// rename (§193) the date became the wrong lede twice over: it re-asserted
    /// the daily framing the title just dropped, and it was the least useful
    /// half of the line — a person knows what day it is; what they can't know
    /// is how far back "going on" reaches. So the span stands alone, and a
    /// window that IS just the calendar day says so plainly rather than
    /// printing a start time that only restates midnight.
    private func briefWindowLine() -> String {
        guard let away = AppVisit.away else { return String(localized: "today so far") }
        return String(localized: "since \(away.lowerBound.formatted(.dateTime.hour().minute()))")
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
                    .accessibilityLabel("Close")
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
            if embedded, turns.isEmpty, !answering {
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
                    // The longest weekday+moment pairs ("Wednesday
                    // morning.") still don't fit the line reserved above at
                    // full display size — scale down rather than truncate
                    // (the type ramp still carries hierarchy; this is fit,
                    // not a new size step). Caught on sim, 2026-07-22.
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .settleIn()
                if !corpusSummary.isEmpty {
                    Text(corpusSummary)
                        .dsText(.callout15)
                        .foregroundStyle(DS.textSecondary)
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, 2)
                        .settleIn(delay: 0.05)
                }
                // A real anniversary or a real threshold just crossed — never
                // a canned line (delight, 2026-07-21).
                if let flavor = greetingFlavorLine {
                    Text(flavor)
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textTertiary)
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, 1)
                        .settleIn(delay: 0.08)
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
                                            .environment(\.genAskRequest, askFromAnswer)
                                            // Mac polish (2026-07-28): applied
                                            // ONCE at the root rather than
                                            // inside GenRenderer's own
                                            // recursive component switch —
                                            // .textSelection is an environment
                                            // value, so it cascades to every
                                            // Text the whole document tree
                                            // renders without adding any new
                                            // nesting depth to a view already
                                            // erased via AnyView for exactly
                                            // that stack-depth reason.
                                            .textSelection(.enabled)
                                        if !turn.failed {
                                            provenanceBadge(keyed: turn.keyed,
                                                            searchedWeb: turn.searchedWeb,
                                                            imagesSeen: turn.imagesSeen,
                                                            found: turn.found)
                                        }
                                    }
                                }
                            }
                            if answering {
                                convoTurn(question: currentQuestion, animateIn: true) {
                                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                                        // The librarian at work: the berry
                                        // breathes while the answer is in
                                        // flight — alive, not a spinner
                                        // (delight 2026-07-13).
                                        if inFlight {
                                            CasberiMark(size: 20)
                                                .breathing()
                                                .padding(.horizontal, DS.Space.s4)
                                                // A quick settle — scale down
                                                // as it fades, a small "found
                                                // it" beat rather than a flat
                                                // vanish (delight, 2026-07-21).
                                                .transition(.asymmetric(
                                                    insertion: .opacity,
                                                    removal: .scale(scale: 0.6).combined(with: .opacity)))
                                                .accessibilityLabel("Thinking")
                                        }
                                        GenRender(id: "root", els: answerStream.els)
                                            .textSelection(.enabled)
                                            .environment(\.genProseStreaming, proseStreaming)
                                            // Cited rows glint once as they
                                            // mount — "I went and found
                                            // these", as a gesture. Live
                                            // answer only, so a scroll-back
                                            // never replays it.
                                            .environment(\.genCitationGlint, true)
                                            .environment(\.genAgentAnswerContext, true)
                                            .environment(\.genAskRequest, askFromAnswer)
                                        // A keyed answer says so, always — the
                                        // badge is the honesty rule applied to
                                        // where the answer was made.
                                        if !inFlight, !answerFailed {
                                            provenanceBadge(keyed: keyedCurrent,
                                                            searchedWeb: keyedSearchedWeb,
                                                            imagesSeen: keyedImagesSeen,
                                                            found: foundCurrent)
                                        }
                                        if !proseStreaming, !inFlight {
                                            // FlowRow, not HStack (2026-07-21):
                                            // three chips don't fit one line once
                                            // Keep wears its long proactive label
                                            // ("You ask this a lot — keep it?"),
                                            // and the HStack squeezed them until
                                            // "Try with your key" broke across two
                                            // lines mid-phrase. Chips wrap as whole
                                            // chips now, the way the ask chips
                                            // already do.
                                            FlowRow(spacing: DS.Space.s2) {
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
                                                        DSHaptic.success()
                                                        KeptAskStore.shared.keep(kind, title: currentQuestion)
                                                        if !firstKeptAskDone {
                                                            firstKeptAskDone = true
                                                            chrome.flash("Your first standing question — I'll keep it fresh.",
                                                                         tone: .success)
                                                        } else {
                                                            chrome.flash("Kept — it'll stay fresh on your rest screen",
                                                                         tone: .success)
                                                        }
                                                        // The chip morphs to its own receipt for
                                                        // a beat before it retires (delight,
                                                        // 2026-07-21) — Keep earns a felt moment
                                                        // instead of just vanishing.
                                                        withAnimation(.spring(response: 0.22, dampingFraction: 0.6)) {
                                                            keepJustLanded = true
                                                        }
                                                        Task { @MainActor in
                                                            try? await Task.sleep(for: .milliseconds(420))
                                                            keepableAskKind = nil
                                                            keepJustLanded = false
                                                        }
                                                    } label: {
                                                        // Tint is reserved for what genuinely
                                                        // wants attention (design pass
                                                        // 2026-07-21): the just-landed receipt,
                                                        // and the proactive "you ask this a lot"
                                                        // prompt. A plain Keep is a routine save
                                                        // and sits at neutral — so the row's one
                                                        // consequential verb (Try with your key,
                                                        // which sends your things off this
                                                        // iPhone and spends your own money) can
                                                        // be the thing that stands out.
                                                        // A composed SCREEN gets a verb that
                                                        // names it (2026-07-22) — a bare "Keep"
                                                        // under the day brief undersold what
                                                        // keeping would do. "this view", not
                                                        // "this brief", since §193 (the screen
                                                        // stopped being a daily brief).
                                                        Chip(text: keepJustLanded ? "Kept"
                                                                : (askedOften
                                                                   ? "You ask this a lot — keep it?"
                                                                   : (kind == "today" ? "Keep this view" : "Keep")),
                                                             style: (keepJustLanded || askedOften) ? .tint : .neutral,
                                                             glyph: keepJustLanded ? "checkmark"
                                                                : (askedOften ? "sparkles" : "pin.fill"))
                                                    }
                                                    .buttonStyle(.plain)
                                                    .scaleEffect(keepJustLanded ? 1.08 : 1)
                                                    .disabled(keepJustLanded)
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
                                                        Chip(text: "Save as a note", style: .neutral,
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
                                                        // The row's one consequential verb wears
                                                        // its weight (design pass 2026-07-21):
                                                        // it sends the question and its matched
                                                        // things off this iPhone and spends the
                                                        // person's own key. It read as the
                                                        // QUIETEST chip in the row while two
                                                        // routine saves shouted.
                                                        Chip(text: "Try with your key",
                                                             style: .tint, glyph: "key.fill")
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                                // The related follow-up (§177) — the next
                                                // natural ask, offered where the thumb is,
                                                // teaching the vocabulary at the moment it's
                                                // most wanted. A bare tap sends it, the same
                                                // as any chip; neutral, so it never competes
                                                // with the row's real verbs. Suppressed on
                                                // the brief LANDING (prd §181): the docked
                                                // suggestion row below already carries the
                                                // next asks (the away chip among them), so
                                                // showing it here too would double it.
                                                if let next = nextAsk, !briefLanding {
                                                    Button {
                                                        DSHaptic.selection()
                                                        draft = next.query
                                                        commit()
                                                    } label: {
                                                        Chip(text: next.label, style: .neutral,
                                                             glyph: "arrow.turn.down.right")
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
                    // The conversation settles at the BOTTOM (design pass
                    // 2026-07-21). Top-anchored, a one-answer conversation
                    // left more than half the screen empty below it and put
                    // the answer's own verbs — Keep, Save, Try with your key
                    // — at the far top of the display, the furthest possible
                    // point from the thumb that just typed the question. Now
                    // the answer rises out of the composer it was asked from
                    // and its verbs land within reach; a long conversation
                    // still scrolls exactly as before.
                    .defaultScrollAnchor(.bottom)
                    .dsAdaptiveContentWidth()
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
                    // The completion tick (delight, 2026-07-22) — a single
                    // SOFT haptic when the brief finishes visibly assembling,
                    // distinct from the louder "real content landed" tick that
                    // already fires the moment the doc is COMPOSED (well
                    // before the typewriter finishes painting it — see the
                    // settle block's own `DSHaptic.success()`). `.selection()`
                    // on purpose: `.success()` again here would be a second,
                    // redundant buzz for the same answer. Scoped to the Today
                    // brief only — every other answer's completion already
                    // reads as "done" the moment the settle haptic fires, so
                    // adding a second tick there would be noise, not delight.
                    .onChange(of: answerStream.completed) { _, done in
                        guard done, TodayBrief.matches(currentQuestion) else { return }
                        DSHaptic.selection()
                    }
                    .onChange(of: answerStream.progress) { _, _ in
                        withAnimation(DS.Motion.standard) { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                    .onChange(of: turns.count) { _, _ in
                        withAnimation(DS.Motion.standard) { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                    // The deferred half of the ask-time keyed tap (prd §242):
                    // fires strictly AFTER commit()'s own Task has fully
                    // settled (inFlight true → false) and returned, rather
                    // than calling askWithKey() from inside that Task —
                    // which would race its own later settle work
                    // (keepableAskKind, nextAsk) against askWithKey()'s state
                    // writes. Watching the value drop from the OUTSIDE, once
                    // SwiftUI has already delivered the settled state, avoids
                    // that race entirely.
                    .onChange(of: inFlight) { was, now in
                        guard was, !now, pendingKeyedFollowUp else { return }
                        pendingKeyedFollowUp = false
                        askWithKey()
                    }
                }
                .padding(.top, DS.Space.s2)
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
                Text("No mic access — allow Casberi in \(DS.settingsAppName)")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s2)
            }

            // Parse card — only for PASTED content (the capture path): it
            // previews what keeping will write. Typed words get answers, not
            // filing previews.
            if hasDraft && !answering && pasted {
                ParseCard(draft: draft)
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
        // A genuinely large "while I was away" haul deals one small berry
        // shower over the answer (delight, 2026-07-21) — an arrival worth
        // marking, contained to the bubble's own bounds by the clip below.
        .overlay { BerryRain(trigger: awayRainTrigger) }
        .overlay { BerryRain(trigger: firstBriefRainTrigger) }
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
                // Raised by the bar's magnifier (2026-07-30): the field takes
                // focus and nothing else happens — no brief, no ask. Cleared
                // on read so an ordinary later open doesn't inherit it.
                if chrome.focusDraftOnOpen {
                    chrome.focusDraftOnOpen = false
                    fieldFocused = true
                }
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
                    placeholderIndex = (placeholderIndex + 1) % activeInvitations.count
                }
            }
        }
    }

    /// A doc trivial enough to land WITHOUT the typewriter — a root `Stack`
    /// over exactly one `Insight` and nothing else (2026-07-22). Structural,
    /// not a kind whitelist: any deterministic answer that composes to a
    /// single bare line ("Nothing overdue.", a status count) qualifies, and
    /// nothing with rows/charts/a treemap ever does — those still stream so
    /// their modules assemble one by one. Parses the SHAPE (via `GenParser`,
    /// the same engine the renderer uses) rather than sniffing line strings,
    /// so it's indifferent to the ref name or line count — `keepableText`
    /// already checks a doc's Insight-ness this way one screen up.
    private func isInstantDoc(_ doc: [String]) -> Bool {
        let joined = doc.joined(separator: "\n")
        let els = GenParser.parse(prefix: joined[...], isComplete: true)
        guard let root = els["root"], root.comp == "Stack" else { return false }
        let refs = root.refs(0)
        guard refs.count == 1, els[refs[0]]?.comp == "Insight" else { return false }
        return true
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
        // the typed text, before it's sent (no answer yet).
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
        // `-findProbe "<query>"` fills the field and fires FIND — the
        // deterministic door, headless. NSLogs the doc it painted, so the
        // "nothing was synthesized" promise is checkable: a `findProbe:` line
        // carrying Row(...) entries and no prose IS the guarantee, and the
        // same run proves the chip's action is wired to `Retriever.rank` and
        // not quietly to the answer path.
        if isOpen, !didAutoSend,
           let q = UserDefaults.standard.string(forKey: "findProbe"), !q.isEmpty {
            didAutoSend = true
            fillDraft(q)
            try? await Task.sleep(for: .milliseconds(500))
            runFind()
            try? await Task.sleep(for: .milliseconds(300))
            NSLog("[Casberi] findProbe: query=%@ keepable=%@", q, keepableAskKind ?? "(none)")
            // One NSLog PER LINE — a joined multi-line message gets truncated
            // mid-document by the log reader (the lesson `-todayProbe` paid
            // for on 2026-07-22).
            for line in lastFindDoc { NSLog("[Casberi] findDoc| %@", line) }
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
        pasted = false
        chipsAppeared = false
        placeholderIndex = 0
        turns = []
        currentQuestion = ""
        keptCurrent = false
        keyedCurrent = false
        keyedSearchedWeb = false
        keyedImagesSeen = 0
        answerFailed = false
        foundCurrent = false
        conversationIsKeyed = false
        // Cleared HERE, not just at askWithKey()'s own entry (2026-07-31):
        // askDirectly() sets this true BEFORE commit() runs, and commit()'s
        // voice/paste/navigate branches never set `inFlight` true at all —
        // so a keyed tap on a draft that turns out to be a navigation
        // command would otherwise leave this flag stranded true, and the
        // NEXT ask's unrelated inFlight-false transition would fire
        // askWithKey() out of context. `inFlight = false` two lines below
        // would itself spuriously trigger the watcher on a stale flag too.
        pendingKeyedFollowUp = false
        inFlight = false
        keepJustLanded = false
        awayRainPlayedThisOpen = false
        askGeneration += 1   // any in-flight answer Task retires silently
        path = NavigationPath()
        onLowerAgent()
    }

    /// FIND — the deterministic door (2026-07-25, the composer's third exit).
    ///
    /// The corpus has always been searchable: `Retriever.rank` is the engine
    /// behind every free-text ask, and a kept `search:<query>` re-runs it
    /// verbatim. What it never had was a way to ASK FOR IT. Typing "climate
    /// links" into the composer offered to send those two words to Messages,
    /// Mail or Google — the outbound exits — while the one thing the app is
    /// actually for, finding it in your own things, had no affordance at all.
    /// Spotlight, Visual Intelligence and Shortcuts all reach this corpus from
    /// OUTSIDE; inside, it was reachable only by phrasing a question and
    /// hoping. This is that door, named.
    ///
    /// It is deliberately NOT the Ask button with a different label. Ask routes
    /// through `RootShell.answerDocument`, which may reach the on-device model
    /// or the person's own key. Find runs `KeptAskComposers.search` and nothing
    /// else: the same deterministic engine, on the same terms, painting the
    /// matches as they are. Instant, no model, nothing synthesized — and the
    /// badge says so. That distinction is the whole reason it earns a control
    /// of its own instead of being folded into Ask.
    ///
    /// The result is keepable through the existing Keep affordance, which mints
    /// exactly the `search:<query>` kind this engine already serves — so a
    /// find that proves useful becomes a standing search with one more tap, and
    /// no new machinery.
    private func runFind() {
        let query = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !inFlight else { return }
        DSHaptic.selection()
        let things = (try? modelContext.fetch(FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        ))) ?? []
        guard let result = KeptAskComposers.search(query, things: things) else { return }

        withAnimation(DS.Motion.standard) {
            // A find lands mid-conversation like any other turn — the one
            // already live settles first, exactly as `commit()` does.
            if answering {
                turns.append(ConvoTurn(question: currentQuestion, els: answerStream.els,
                                       keyed: keyedCurrent, searchedWeb: keyedSearchedWeb,
                                       imagesSeen: keyedImagesSeen, failed: answerFailed,
                                       found: foundCurrent))
            }
            answering = true
            currentQuestion = query
            keptCurrent = false
            currentStreamed = false
            keyedCurrent = false
            keyedSearchedWeb = false
            keyedImagesSeen = 0
            answerFailed = false
            foundCurrent = true
            // Nothing is in flight: the retriever already ran, synchronously.
            // Leaving `inFlight` true would breathe a loading berry over a
            // result that is already complete.
            inFlight = false
        }
        // Retires any answer Task still streaming — its doc must not paint
        // over the matches that just landed.
        askGeneration += 1
        nextAsk = nil
        draft = ""
        answerStream.paint(result.doc)
        lastFindDoc = result.doc
        // Keepable as a standing search — the kind `KeptAskComposers` already
        // serves, so the Keep pill's whole path exists.
        keepableAskKind = "search:\(query)"
        AskMemory.asked("search:\(query)")
        DSHaptic.success()
    }

    /// The small honest mark every answer wears — where it was made, and what
    /// was actually done to make it, on the answer itself and on its settled
    /// turn.
    ///
    /// BOTH paths are marked now (2026-07-21). The keyed answer always said
    /// so; the on-device answer said nothing — which left the app's own
    /// promise (this ran free, on your iPhone, and nothing left it) as the
    /// silent default while the exception got all the words. `searchedWeb`
    /// and `imagesSeen` are OBSERVED — the provider's own stream reported the
    /// tool running — so this states what happened rather than what was
    /// offered: an agent that could search but didn't never claims it did.
    private func provenanceBadge(keyed: Bool, searchedWeb: Bool = false,
                                 imagesSeen: Int = 0, found: Bool = false) -> some View {
        var parts: [String] = []
        if searchedWeb { parts.append(String(localized: "searched the web")) }
        if imagesSeen == 1 {
            parts.append(String(localized: "read 1 screenshot"))
        } else if imagesSeen > 1 {
            parts.append(String(localized: "read \(imagesSeen) screenshots"))
        }
        let detail = parts.isEmpty ? "" : " · " + parts.joined(separator: " · ")
        // A find gets its own words, not "Answered": nothing wrote this — the
        // retriever ranked your own things and they're shown as they are.
        // Collapsing the two would let the most trustworthy result in the app
        // wear the same label as the least.
        let glyph = found ? "magnifyingglass" : (keyed ? "key.fill" : "lock.iphone")
        let words = found ? String(localized: "Matched on \(DS.device) — nothing was written")
                          : (keyed ? String(localized: "Answered with your key\(detail)")
                                   : String(localized: "Answered on \(DS.device)"))
        return HStack(spacing: DS.Space.s1) {
            Image(systemName: glyph)
                .font(.system(size: 10))
                .accessibilityHidden(true)
            Text(words)
                .fixedSize(horizontal: false, vertical: true)
        }
        .dsText(.label12)
        .foregroundStyle(DS.textTertiary)
        .padding(.horizontal, DS.Space.s4)
    }

    /// The ask-time form of the same consent (2026-07-31, prd §242) — a
    /// normal `commit()`, plus a flag so the keyed retry fires ITSELF the
    /// moment the on-device answer settles (the `onChange(of: inFlight)`
    /// watcher above), instead of waiting for a second, separate tap on a
    /// chip in the settled verb row. `commit()` is unchanged and does
    /// everything it always does — this only decides what happens next.
    private func askDirectly() {
        pendingKeyedFollowUp = true
        commit()
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
                                       keyed: keyedCurrent, searchedWeb: keyedSearchedWeb,
                                       imagesSeen: keyedImagesSeen, failed: answerFailed,
                                       found: foundCurrent))
            }
            answering = true
            inFlight = true
            keyedCurrent = true
            keptCurrent = false
            currentStreamed = false
            keyedSearchedWeb = false   // observed per answer, never carried over
            keyedImagesSeen = 0
            answerFailed = false
            foundCurrent = false       // a keyed retry is an answer, not a find
            // keepableAskKind is NOT reset here: askWithKey() re-asks the
            // SAME currentQuestion, so the kind commit() already recognized
            // for it is still correct throughout the retry.
        }
        askGeneration += 1
        let gen = askGeneration
        // Bankr answers through an async job that can genuinely run a minute
        // (submit → poll), so it says so rather than leaving the same
        // "Asking…" line sitting for 90 seconds looking stuck.
        let waitLine = AgentKey.active == .bankr
            ? "Asking Bankr — reading your wallet and the market. This can take a minute."
            : "Asking with your key…"
        answerStream.paint(["root = Stack([w])", "w = Insight(\"\(waitLine)\")"])
        Task { @MainActor in
            // Prose arrives live over the network now (2026-07-21) — paint
            // each growing snapshot the same way the on-device path does
            // (commit()'s onProseDoc), with the same stale-ask guard.
            var streamed = false
            let outcome = await answerWithKey(q) { partialDoc in
                guard gen == askGeneration else { return }
                streamed = true
                currentStreamed = true   // a real synthesis — keepable
                proseStreaming = true
                answerStream.paint(partialDoc)
            }
            // Closed, or a newer ask overtook this one — retire silently.
            guard isOpen, gen == askGeneration else { return }
            withAnimation(DS.Motion.standard) { proseStreaming = false; inFlight = false }
            keyAvailable = AgentKey.isConfigured
            switch outcome {
            case .success(let answer):
                currentStreamed = true   // a keyed synthesis is keepable too
                keyedSearchedWeb = answer.searchedWeb
                keyedImagesSeen = answer.imagesSeen
                // From here a typed follow-up stays on the agent that just
                // answered — it has the context the on-device model doesn't.
                conversationIsKeyed = true
                DSHaptic.success()   // a real keyed answer landed — the honest tick
                // Prose already painted its way in live; settle on the final
                // doc instantly (it may add a grounded "Found" row after the
                // prose). A doc that never streamed (an early failure before
                // any text arrived) still gets the typewriter reveal.
                if streamed { answerStream.paint(answer.doc) }
                else { answerStream.stream(answer.doc) }
            case .failure(let failure):
                keyedCurrent = false     // no keyed answer arrived — no badge
                answerFailed = true      // …and this isn't an answer at all
                // Each failure says what actually happened (2026-07-21). The
                // old single line blamed the key for every one of them, which
                // is a lie when the model simply declined or the network
                // dropped — and it sent people to Settings to "fix" a key
                // that was never the problem.
                answerStream.stream(["root = Stack([w])",
                                     "w = Insight(\"\(failure.line)\")"])
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
        // Docked beneath the brief LANDING too (prd §181) — a kept standing
        // ask must stay reachable when the agent opens onto the brief, not
        // only from the old empty state.
        if restChrome(keepBrief: true), !KeptAskStore.shared.order.isEmpty {
            let sorted = KeptAskStore.shared.order.sorted { a, b in
                let store = KeptAskStore.shared
                let changedA = store.changed(a, digest: store.currentDigests[a] ?? "")
                let changedB = store.changed(b, digest: store.currentDigests[b] ?? "")
                return changedA != changedB ? changedA && !changedB
                                            : (store.titles[a] ?? "") < (store.titles[b] ?? "")
            }
            // Horizontal scroll, matching `askChips` (§187) — the two docked
            // rows are one chip language and must not wrap differently.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s2) {
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
                                // A changed pill's number climbs from what
                                // was last seen to what's current (delight,
                                // 2026-07-21) — the roll IS the dot's promise
                                // made visible, restoring the digit-climb the
                                // 2026-07-20 pill unification traded away.
                                DigestRoll(text: "· \(digest)",
                                          previous: changed ? store.lastSeenDigest(kind).map { "· \($0)" } : nil)
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
                // The inset rides the content, not the scroll view — see
                // `askChips` for why.
                .padding(.horizontal, DS.Space.s4)
            }
            .padding(.top, DS.Space.s3)
        }
    }

    // MARK: - Ask chips + input bar (chat grammar: by the bottom)

    /// The ask chips — asks the corpus can answer now, as pills while the
    /// field is empty. Unified with `keptAskPills` (2026-07-20, user: "your
    /// chips design was better") — was a 2×2 `AskTile` grid; now the SAME pill
    /// vocabulary the kept asks above already wear, so the whole rest screen
    /// reads as one language instead of two. Every specific query is unchanged;
    /// the ONE trade made explicit: the away chip's rolling-digit-climb delight
    /// (`AskTile.rollCount`) is gone, replaced by the same static "· N" digest
    /// suffix every kept pill already shows.
    ///
    /// ONE horizontally scrolling row since §187 (user: "i thought the mockup
    /// we did had scrolling horizontal chips, but in my app they are stacked").
    /// The `FlowRow` it used to be WRAPS, and these chips are wide once they
    /// wear their signals ("What's going on? · 44") — so under the brief they
    /// stacked one-per-line into a tall column instead of the single docked row
    /// the design called for. A scroll row also lets the set stay generous
    /// without costing height: what doesn't fit slides.
    @ViewBuilder
    private var askChips: some View {
        // Also shown docked beneath the brief LANDING (prd §181) — the one
        // answer state that keeps its chips, so opening the agent onto the
        // brief never costs the person the "what else can I ask" row.
        if restChrome(keepBrief: true), !dockedSuggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s2) {
                ForEach(Array(dockedSuggestions.enumerated()), id: \.element.memoryKey) { i, ask in
                    // "While I was away?" wears its own display label ("Catch
                    // me up") but sends the canonical query — matching the
                    // tile version's own distinction.
                    let isAway = ask.kind == "away" && awayLanded >= 3
                    Button {
                        DSHaptic.selection()
                        if !isAway { AskMemory.tapped(ask.memoryKey) }
                        // `query` is the display title for every chip but the
                        // timely publisher one, which sends its canonical full
                        // handle (see AskOption.query).
                        draft = ask.query
                        commit()
                    } label: {
                        HStack(spacing: DS.Space.s2) {
                            // A timely chip wears a tint dot instead of its
                            // glyph (2026-07-22): "happening now" reads as
                            // happening, the same grammar a changed kept pill
                            // uses — the row's one live signal.
                            if ask.timely {
                                Circle().fill(DS.tint).frame(width: 7, height: 7)
                            } else {
                                Image(systemName: isAway ? "sparkles" : ask.glyph)
                                    .accessibilityHidden(true)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(DS.tint)
                                    // The Noticed chip is the agent's one
                                    // spontaneous connection — it earns a single
                                    // sparkle as the chips settle in, so the most
                                    // surprising chip acts surprising too
                                    // (delight, 2026-07-21). Plays once per open.
                                    .symbolEffect(.bounce, value: ask.kind == "noticed" && chipsAppeared)
                            }
                            Text(isAway ? "Catch me up" : ask.title)
                                .dsText(.callout15)
                                .foregroundStyle(DS.textPrimary)
                                .lineLimit(1)
                            // The signal — parity with the kept pills
                            // (2026-07-22). Every chip carrying a cheap
                            // synchronous count shows it; a chip without one
                            // (wallet/watchlist, read live) shows nothing
                            // rather than a stale or invented number.
                            if let signal = ask.signal {
                                Text(signal)
                                    .dsText(.subhead13)
                                    .foregroundStyle(DS.textTertiary)
                            }
                        }
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.vertical, DS.Space.s3)
                        // Timely chips wear the same tintDim wash a changed
                        // kept pill does, so a live moment reads as filled
                        // against the steady gray of the evergreen chips.
                        .background(ask.timely ? AnyShapeStyle(DS.tintDim) : AnyShapeStyle(DS.gray100),
                                    in: RoundedRectangle(cornerRadius: DS.Radius.control,
                                                         style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .modifier(ChipEntrance(index: i, shown: chipsAppeared, reduceMotion: reduceMotion))
                }
                }
                // The inset rides the CONTENT, not the ScrollView — padding the
                // scroll view itself would clip the first and last chip against
                // the inset edge instead of letting them scroll past it.
                .padding(.horizontal, DS.Space.s4)
            }
            // Clear air between the greeting and the chips — a separate
            // band (ask), not stuck to the header.
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
                    let pool = activeInvitations
                    Text(answering || !turns.isEmpty ? String(localized: "Ask about this…")
                                                     : pool[min(placeholderIndex, pool.count - 1)])
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

    /// The typed-draft band (2026-07-16, fourth form — see TakeTool), in the
    /// ask chips' slot. Two verbs now, in the order the app's own priorities
    /// put them (2026-07-25):
    ///
    ///   **Find** — keep it here. Searches your own things, deterministically.
    ///   Leads the row because it is the app's own job; the outbound jumps are
    ///   the guest verbs. Shown for ANY draft, a question included: "climate
    ///   links" and "what did I save about climate?" are the same search to
    ///   `Retriever.rank`, and hiding the door behind a grammar check would
    ///   reintroduce exactly the guess-the-phrasing problem it exists to fix.
    ///
    ///   **Send to** — take it there. What you typed is a FACT bound for
    ///   another app; the text rides the jump (Messages/Mail body, Google
    ///   query, Calendar at the detected date) or the clipboard where no URL
    ///   carries it (the flash says so). Still sits out for a question, so a
    ///   question's one honest exit stays obvious. A found date earns a
    ///   receipt line — proof the Calendar jump lands on the right day.
    @ViewBuilder
    private var takeChips: some View {
        // Three independent gates, so each is purely ADDITIVE — the older
        // two bands' own visibility rules are byte-for-byte what they were.
        // Find sits out for a PASTE: that's a capture path on its way to being
        // kept, not a phrase to search for.
        let offerFind = !pasted
        let offerSend = !answering && !draftIsQuestion
        // The ask-time keyed tap (2026-07-31, prd §242) — the discoverability
        // fix: today's only door to "Try with your key" is a chip in the
        // SETTLED verb row, which means asking, reading the whole on-device
        // answer, and noticing a chip among three others before the option
        // is even visible. This puts the SAME consent tap where the intent
        // already is — needs a real question (mirrors `askWithKey()`'s own
        // "the same question" framing; a capture-a-link paste has nothing
        // for an agent to answer) and a configured key. Mutually exclusive
        // with Send-to by construction (that band explicitly excludes
        // questions), so the row never crowds.
        let offerKeyed = !pasted && draftIsQuestion && AgentKey.isConfigured
        if isOpen && hasDraft && !isRecording, offerFind || offerSend || offerKeyed {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.s2) {
                        // Find leads, and wears the tint FILL where the other
                        // chips wear tint only in their glyph — this is the one
                        // verb that keeps you in the app, so it reads primary.
                        if offerFind {
                        Button { runFind() } label: {
                            HStack(spacing: DS.Space.s2) {
                                Image(systemName: "magnifyingglass")
                                    .accessibilityHidden(true)
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Find")
                                    .dsText(.callout15).fontWeight(.semibold)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, DS.Space.s3 + 2)
                            .frame(height: 40)
                            .background(DS.tint, in: Capsule(style: .continuous))
                        }
                        .buttonStyle(PressSpring())
                        .accessibilityLabel("Find in your things")
                        }

                        // Same tint-on-tintDim language "Try with your key"
                        // already wears downstream (`Chip(style: .tint)`),
                        // resized to this row's 40pt capsule so it scrolls
                        // evenly beside Find and Send-to rather than reading
                        // as a smaller, different kind of control.
                        if offerKeyed {
                        Button { askDirectly() } label: {
                            HStack(spacing: DS.Space.s2) {
                                Image(systemName: "key.fill")
                                    .accessibilityHidden(true)
                                    .font(.system(size: 14, weight: .medium))
                                Text("Ask \(AgentKey.active?.agent ?? "your key")")
                                    .dsText(.callout15).fontWeight(.semibold)
                            }
                            .foregroundStyle(DS.tint)
                            .padding(.horizontal, DS.Space.s3 + 2)
                            .frame(height: 40)
                            .background(DS.tintDim, in: Capsule(style: .continuous))
                        }
                        .buttonStyle(PressSpring())
                        .accessibilityLabel("Ask with your key")
                        }

                        if offerSend {
                            Text("Send to")
                                .dsText(.subhead13)
                                .foregroundStyle(DS.textTertiary)
                            // Chunkier pills than the shell Chip — the same
                            // bold grammar as the ask tiles (option A,
                            // 2026-07-16), so the field's exits read as one
                            // design.
                            ForEach(TakeTool.all) { tool in
                                Button { runTake(tool) } label: {
                                    HStack(spacing: DS.Space.s2) {
                                        Image(systemName: tool.glyph)
                                            .accessibilityHidden(true)
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
                    }
                    .padding(.horizontal, DS.Space.s4)
                }
                if offerSend, let date = detectedDate {
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

    private func commit() {
        if isRecording {
            // Voice is a capture path — send keeps the piece.
            if let piece = voice.stop(keep: true) {
                onCommitVoice(piece.transcript, piece.sourceRef)
            }
            close()
        } else if pasted {
            // Paste is a capture path — send keeps what came in.
            onCommit()
            close()
        } else if let intent = NavigateCommand.parse(draft, tags: tagPool,
                                                     sources: knownSources()) {
            // A place, named — go there. Reads only (a navigation), so no
            // proposal needed; the composer closes and the shell moves.
            DSHaptic.selection()
            draft = ""
            onNavigate(intent)
            close()
        } else {
            // Typed words are an utterance — the answer streams. A follow-up
            // first settles the current LIVE answer into the thread so the Q&A
            // stacks (2026-07-12); the last answer stays live until the next
            // ask or close, so its typewriter reveal never gets cut.
            if answering {
                turns.append(ConvoTurn(question: currentQuestion, els: answerStream.els,
                                       keyed: keyedCurrent, searchedWeb: keyedSearchedWeb,
                                       imagesSeen: keyedImagesSeen, failed: answerFailed,
                                       found: foundCurrent))
            }
            // A follow-up in a conversation the person already took to their
            // own agent stays there (2026-07-21). Before this, a typed
            // follow-up after a keyed answer silently dropped back to the
            // on-device model — which never saw the keyed turn, so "which of
            // those…" was answered by a model with no idea what "those" meant.
            let stayKeyed = conversationIsKeyed && keyAvailable
            // The question lift (delight, 2026-07-21): the header's entrance
            // and the berry's fade-in ride the same animated commit as the
            // rest of "a new ask just started."
            withAnimation(DS.Motion.standard) {
                answering = true
                currentQuestion = draft
                keptCurrent = false
                currentStreamed = false
                keyedCurrent = stayKeyed
                keyedSearchedWeb = false   // observed per answer
                keyedImagesSeen = 0
                answerFailed = false
                foundCurrent = false       // this is an ANSWER, not a find
                inFlight = true
            }
            keepableAskKind = nil   // recomputed at settle, for THIS question
            nextAsk = nil           // same — the prior answer's follow-up is stale
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
                var streamed = false
                let paintPartial: ([String]) -> Void = { partialDoc in
                    // Prose arriving live — paint each growing snapshot; the
                    // Insight breathes its dot while this fires (§2). A stale
                    // ask's partials never paint over a newer one.
                    guard gen == askGeneration else { return }
                    streamed = true
                    currentStreamed = true   // a real synthesis — keepable
                    proseStreaming = true
                    answerStream.paint(partialDoc)
                }
                let finalDoc: [String]
                if stayKeyed {
                    // The follow-up stays on the agent that answered last. A
                    // failure here falls back to the on-device answer rather
                    // than dead-ending the conversation — the local model
                    // still knows the corpus, it just lacks the keyed turn.
                    // Bound as `keyed`, not `answer` — `answer` is the
                    // on-device closure this same block falls back to, and
                    // one name for both reads as a bug.
                    switch await answerWithKey(q, paintPartial) {
                    case .success(let keyed):
                        keyedSearchedWeb = keyed.searchedWeb
                        keyedImagesSeen = keyed.imagesSeen
                        finalDoc = keyed.doc
                    case .failure:
                        // The agent didn't answer, so the on-device model
                        // does — and the badge correctly reads "on this
                        // iPhone", because that's who actually answered.
                        keyedCurrent = false
                        finalDoc = await answer(q, paintPartial)
                    }
                } else {
                    finalDoc = await answer(q, paintPartial)
                }
                // A newer ask (or close) overtook this one — its answer owns
                // the stream now; this one retires silently.
                guard gen == askGeneration else { return }
                // Prose already painted its way in; settle on the final text.
                // A lookup or the fallback never streamed, so reveal it with
                // the typewriter (unchanged behaviour).
                withAnimation(DS.Motion.standard) {
                    proseStreaming = false
                    inFlight = false
                }
                keyAvailable = AgentKey.isConfigured   // one read per settle
                // One more fetch per settle (not per keystroke) — same
                // precedent `computeSuggestions()` already sets for a plain
                // corpus-wide read.
                let settledThings = (try? modelContext.fetch(FetchDescriptor<Thing>())) ?? []
                keepableAskKind = recognizeKeptAskKind(q, in: settledThings)
                // The one related follow-up this answer offers (§177) — nil
                // for an answer with no natural next step. Skipped on the
                // honest "nothing matches" fallback: a dead-end answer has no
                // follow-up worth teaching.
                nextAsk = docHasFallback(finalDoc) ? nil : nextAsk(for: q, in: settledThings)
                // Proactive minting (2026-07-20): count each keepable ask
                // actually made, so a question asked often can upgrade its
                // quiet Keep pill to a "you ask this a lot" prompt. Counted
                // ONLY for keepable kinds — the counter's key space IS the
                // kind space, so an unkeepable ask has nothing to count
                // toward.
                if let kind = keepableAskKind { AskMemory.asked(kind) }
                // The settle haptic is keyed to honesty (delight, 2026-07-21):
                // real content earns the tick, the "nothing matches" fallback
                // earns nothing — celebrating a miss would violate the
                // honesty rule. A genuinely large away haul earns a small
                // berry shower too, the same arrival vocabulary the wallet
                // pass already uses (prd §79) — once per open, even across
                // follow-up re-asks of the same question.
                if !docHasFallback(finalDoc) {
                    DSHaptic.success()
                }
                if keepableAskKind == "away", !awayRainPlayedThisOpen,
                   let count = StatusAsk.pulse(q, things: settledThings)?.pool.count, count >= 20 {
                    awayRainPlayedThisOpen = true
                    awayRainTrigger += 1
                }
                // The first brief ever, marked (delight, 2026-07-22) — the
                // SAME persisted-flag idiom `MainSurface`'s `bloom.seen.
                // <source>` uses for a source's first-ever landing, so it can
                // only ever fire once, ever, ON THIS DEVICE (a fresh install
                // sees it again, which is correct — it's a new relationship
                // with the brief, not a global server-side fact).
                // The persisted KEY keeps its old name on purpose — renaming it
                // would re-fire this once-ever delight for everyone who already
                // saw it. The COPY is what changed (§193): it promised "every
                // morning" back when this was a daily brief, and it now lands
                // on every open.
                if TodayBrief.matches(q), !docHasFallback(finalDoc),
                   !UserDefaults.standard.bool(forKey: "today.firstBriefShown") {
                    UserDefaults.standard.set(true, forKey: "today.firstBriefShown")
                    firstBriefRainTrigger += 1
                    chrome.flash(String(localized: "I'll have this ready every time you open."),
                                tone: .success)
                }
                // A cheap deterministic ONE-LINER lands instantly (2026-07-22)
                // — a chip whose whole answer is a single Insight ("Nothing
                // overdue.", a status count) has nothing to assemble, so the
                // typewriter only adds a beat of latency before an answer the
                // person could already have read. A real composition (the day
                // brief, a rows doc) still streams module by module. `streamed`
                // marks a LIVE prose synthesis (paints as it arrives); this
                // handles the opposite end — the trivially-short deterministic
                // doc — and everything between still streams as before.
                if streamed { answerStream.paint(finalDoc) }
                else if isInstantDoc(finalDoc) { answerStream.paint(finalDoc) }
                else { answerStream.stream(finalDoc) }
                // Every answer readies the field for a follow-up — EXCEPT the
                // brief landing (prd §181), which is a screen to take in, not a
                // prompt to answer. Popping the keyboard over the brief the
                // instant the agent opens would bury the very thing the person
                // opened it to see; they tap the field when they're ready to
                // ask. `q`, not `currentQuestion`: a newer ask could have
                // overtaken, but this closure already guarded `gen` above.
                if !(turns.isEmpty && TodayBrief.matches(q)) {
                    fieldFocused = true
                }
            }
        }
    }
}

/// The parse card — what keeping the pasted draft will write (kind + title
/// preview). No candidate-tag chips (prd §178 — the filing surface retired;
/// a #hashtag typed in the text itself still rides in via Capture).
struct ParseCard: View {
    let draft: String

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
        }
        .padding(DS.Space.s3)
        .background(DS.fillFaint,
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}

/// A digest string that rolls its leading number from a previous reading to
/// the current one (delight, 2026-07-21) — a kept pill's "· 12" climbing to
/// "· 19" instead of popping cold, the same `.numericText()` grammar
/// `CountUpText` already uses elsewhere. Falls back to a plain, unanimated
/// `Text` whenever there's no real delta to show: no previous reading, no
/// leading number in either string, an unchanged value, or Reduce Motion —
/// motion only plays when it's telling the truth about a real change.
private struct DigestRoll: View {
    let text: String
    let previous: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// nil until the roll starts, then the mid-roll value climbing to
    /// `cur.n` — one Text node throughout, so `.numericText()` has a stable
    /// identity to interpolate (mirrors `CountUpText`'s own shape).
    @State private var shown: Int?

    /// The FIRST number wherever it sits in the string (not necessarily the
    /// head — digests read "· 12 new" or "$12,480 · 3 wallets"), split into
    /// what comes before/after it. nil when there's no digit run to animate.
    private func split(_ s: String) -> (prefix: String, n: Int, suffix: String)? {
        guard let range = s.rangeOfCharacter(from: .decimalDigits) else { return nil }
        var end = range.upperBound
        while end < s.endIndex, s[end].isNumber || s[end] == "," { end = s.index(after: end) }
        guard let n = Int(String(s[range.lowerBound..<end].filter(\.isNumber))) else { return nil }
        return (String(s[s.startIndex..<range.lowerBound]), n, String(s[end...]))
    }

    var body: some View {
        if !reduceMotion, let cur = split(text), let prevText = previous,
           let prev = split(prevText), prev.n != cur.n {
            Text("\(cur.prefix)\((shown ?? prev.n).formatted())\(cur.suffix)")
                .contentTransition(.numericText(value: Double(shown ?? prev.n)))
                .onAppear {
                    shown = prev.n
                    // A follow-up main-actor hop, same fix `ConnectBloom`
                    // documents: setting the start value and animating the
                    // end value in one synchronous call coalesces, so the
                    // start frame never commits and nothing rolls.
                    Task { @MainActor in
                        withAnimation(DS.Motion.standard) { shown = cur.n }
                    }
                }
        } else {
            Text(text)
        }
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
                    .accessibilityHidden(true)
            }
            // A chip is a capsule — its label never breaks across lines
            // (2026-07-21: a squeezed row wrapped "Try with your key" into
            // "Try with / your key" inside a 28pt capsule).
            Text(text).dsText(.label12).lineLimit(1)
        }
        .foregroundStyle(style == .tint ? DS.tint : DS.textPrimary)
        .padding(.horizontal, DS.Space.s3)
        .frame(height: 28)
        .fixedSize(horizontal: true, vertical: false)
        .background(style == .tint ? DS.tintDim : DS.gray100,
                    in: Capsule(style: .continuous))
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
