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
    /// How many extra billed rounds the agent spent searching the corpus
    /// itself (2026-08-06, `AgentCorpusTools`). 0 means it answered from the
    /// evidence it was handed, which is the common case and not a failure —
    /// the badge only mentions this when it happened.
    var toolRounds = 0
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
    ///
    /// `onPartialDoc` is a SECOND channel, and the split is not tidiness
    /// (2026-08-12). Both paint a document snapshot, but `onProseDoc` also
    /// means "a model wrote this": it marks the answer a real synthesis, which
    /// is what offers the Keep-this-text button. The Today brief paints its
    /// corpus half early too, and it is deterministic and keeps as a standing
    /// ASK (`keepableAskKind`), so routing it through the prose channel would
    /// put a second Keep on screen that keeps a different thing.
    var answer: (_ query: String,
                 _ onProseDoc: @escaping ([String]) -> Void,
                 _ onPartialDoc: @escaping ([String]) -> Void) async -> [String] = { _, _, _ in [] }
    /// The BYO-key retry (prd §67): answers the same question with the person's
    /// own agent key, device→API direct. Streams: while the answer is coming
    /// in, `onProseDoc` is called with each growing snapshot so it paints
    /// live, the same contract `answer` gives for the on-device path
    /// (2026-07-21). nil when the key or the network failed — the composer
    /// words that honestly. The verb only shows when a key is configured; it
    /// never fires on its own.
    /// `provider` names which configured agent answers THIS ask (2026-08-06)
    /// — nil means the app-wide active one. Passed rather than read from a
    /// shared pointer so choosing a second agent for one question can never
    /// change what the next question runs on.
    var answerWithKey: (_ query: String, _ provider: AgentProvider?, _ onProseDoc: @escaping ([String]) -> Void) async -> Result<KeyedAnswer, AgentAnswerFailure> = { _, _, _ in .failure(.noKey) }
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
        "Ask anything",
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
        /// How many extra billed rounds it spent searching your own things
        /// (2026-08-06). Carried onto the settled turn like the rest.
        var toolRounds = 0
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
    /// How many times the CURRENT keyed answer went back to the corpus with a
    /// tool (2026-08-06). Observed from the loop, never assumed — a model that
    /// answered from the evidence it was handed reports 0 and the badge stays
    /// quiet about it.
    @State private var keyedToolRounds = 0
    /// Which configured agent the next keyed ask runs on (2026-08-06, prd
    /// §242's "Make active" without the app-wide flip). nil is the app-wide
    /// active provider, and stays nil unless the person deliberately picks a
    /// different one from the verb's own menu — so the default behaviour is
    /// exactly what it was, and a second opinion costs one long-press rather
    /// than a trip to Settings and back.
    ///
    /// It persists for the open conversation rather than resetting per ask:
    /// having chosen to ask Gemini, the follow-up almost always belongs to
    /// Gemini too — and `keyedHistory` upstream threads the prior turns, which
    /// would otherwise be handed to a different model than wrote them.
    @State private var askProvider: AgentProvider?
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
        } else if KeptAskComposers.matchesSpend(question),
                  KeptAskComposers.hasSpendToReport(things) {
            // Gated on the composer's OWN conditions, not a weaker proxy —
            // a first cut asked only whether a card row existed, so someone
            // whose card rows were all pending, or all older than the window,
            // could mint a pill that composed nothing every time it was
            // tapped: the dead control this gate exists to prevent.
            kind = "spend"
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
        // A SCOPE ask is never keepable (2026-08-10, user: "why would it show
        // on how's my work stuff if that is already a default chip"). Money /
        // Work / Life have a permanent, always-visible chip row of their own
        // (`categoryChipsRow`), so keeping one mints a pin that duplicates a
        // control already on screen — and, since a pinned ask sorts above the
        // chips, pushes the real chip down under a copy of itself. This was
        // right before the scoped briefs shipped, when `category:Work` was the
        // only door to that room; the chips replaced that door and nothing
        // told this recognizer. Other `category:` kinds are untouched — a
        // catalog category with no chip (there are none today, but the
        // mapping is data) is still a legitimate thing to pin.
        if let scope = kind.hasPrefix("category:")
            ? String(kind.dropFirst("category:".count)) : nil,
           BriefScope.scopes.contains(scope) {
            return nil
        }
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

    // MARK: - Find's live read (2026-08-13)

    /// The filters `Retriever.find` would apply to the draft as it stands, and
    /// how many things would match. Recomputed on a debounce, and BOTH are
    /// honestly absent rather than stale: a superseded pass writes nothing.
    @State private var liveScopes: [Retriever.Scope] = []
    @State private var liveCount: Int?
    /// Filters the person has waved off. Survives editing the draft (so a
    /// dropped scope stays dropped while you refine the words) and is cleared
    /// when the field is.
    ///
    /// The whole `Scope` is kept, not just the `Kind` the engine needs, so the
    /// chip can be offered BACK. A control that can only ever be turned off is
    /// a trap: dropping the wrong one would otherwise mean retyping the query
    /// to get the filter back, which is the problem this feature exists to end.
    @State private var droppedScopes: [Retriever.Scope] = []
    private var droppedKinds: Set<Retriever.Scope.Kind> { Set(droppedScopes.map(\.kind)) }
    /// Debounce for the live read. 400ms of quiet, because the read is not
    /// cheap — see `liveReadCeiling`.
    @State private var liveReadTask: Task<Void, Never>?
    /// The last query a find actually ran, so refining one search doesn't count
    /// as asking it several times — see `runFind`.
    @State private var lastFoundQuery: String?

    /// The corpus size past which the draft's live read is SKIPPED — the chip
    /// shows its plain "Find" and no scope chips appear until a find has run.
    ///
    /// MEASURED 2026-08-13, `-O`, on a synthetic corpus with realistic body
    /// text: `Retriever.find` costs roughly **77ms per 1,000 things** for a
    /// two-word query and scales with term count (500 → 38ms, 2,000 → 152ms,
    /// 5,000 → 384ms, 10,000 → 769ms; six terms over 5,000 things → 1,137ms).
    /// A phone is slower and this runs on the main actor, where SwiftData
    /// lives — so per-keystroke ranking over a real archive would freeze
    /// typing outright, which is a far worse bug than the missing number.
    ///
    /// 1,200 keeps a live pass near ~90ms on the measuring machine. It is a
    /// bound on OUR cost, not a claim about the corpus: above it the feature
    /// simply says nothing rather than saying something slow or wrong.
    ///
    /// TO RAISE IT, make the engine cheaper rather than moving this number:
    /// the hot spot is the phrase-adjacency bonus, which runs a substring scan
    /// over every candidate's whole body once PER adjacent query pair (hence
    /// the term-count scaling above), and the per-thing tokenization, which is
    /// redone on every call even though the corpus is identical between
    /// keystrokes.
    private static let liveReadCeiling = 1_200

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
            case "noticed", "observation":     return .insight
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
    /// A scoped "What's going on" chip (scoped-brief-spec.md) — one per BRIEF
    /// SCOPE (`BriefScope.scopes`: Money, Work, Life) the corpus holds a
    /// connected app in. No "Everything" chip (user, 2026-08-08) — that
    /// brief is already the default you get by asking nothing in particular,
    /// reachable via the whisper capsule or the kept "today" pill. Deliberately
    /// a SEPARATE small type from `AskOption` rather than another `kind` on
    /// it: `AskOption.query` special-cases "handle" to send a canonical
    /// string different from its display title, and folding a second special
    /// case in there for "send the recognized phrase, show the bare scope
    /// name" risked disturbing the existing away/handle/today display-vs-send
    /// split this file already leans on elsewhere. `query` here is a phrase
    /// `KeptAskComposers.namedAskTarget` already recognizes, so firing it
    /// runs the exact same pipeline a typed ask would.
    private struct CategoryChip: Identifiable {
        let id: String
        let title: String
        let query: String
    }
    @State private var categoryChips: [CategoryChip] = []
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
    /// The tag list, snapshotted once per open — derived from the same corpus
    /// walk `computeSuggestions()` already pays for, so typing never pays a
    /// fetch per character (review 2026-07-08; the separate `tagCandidates()`
    /// closure that used to do its OWN full-corpus fetch here retired
    /// 2026-08-11, see `corpusScan`).
    /// The corpus-wide chip counters, kept across opens (PERF 2026-08-12) —
    /// see `computeSuggestions()`'s fetch for why. Nil means "never computed
    /// on this launch", which is the one open that pays the full walk;
    /// `composeBoard` refreshes it behind the board on every open after.
    private var cachedChipFacts: AgentChipFacts? {
        get { AgentOpenCache.shared.facts }
        nonmutating set { AgentOpenCache.shared.facts = newValue }
    }
    @State private var tagPool: [String] = []
    /// The day's own sentence, shown as the rest screen's lead card
    /// (2026-07-31) — snapshotted once per open alongside `tagPool`, off the
    /// same corpus walk `computeSuggestions()` already pays for. This replaced
    /// ruling 4's stat line ("2,481 things, across 14 apps."): the room's
    /// first sentence should be what happened, not how much you own.
    @State private var dayLede = ""

    /// The agent's room as composed for this open (prd §332, 2026-08-07) —
    /// the noticing, the kept asks wearing their answers, the threaded window,
    /// the fold. Built once per open on the SAME corpus walk
    /// `computeSuggestions()` already pays for, so the whole board costs one
    /// extra pass over an array that is already in memory.
    ///
    /// Empty is a real state, not a failure: a new install has nothing to
    /// synthesize, and the greeting-and-chips rest screen this replaced is
    /// still exactly right there. `AgentOpen.Composition.isEmpty` is the gate.
    /// The feed's own filter — the panel's tap target. Injected by `RootShell`
    /// alongside the route and the detail selection, so this is the same object
    /// the source chips and `NavigateIntent.source` already drive.
    @Environment(FeedFilter.self) private var filter

    /// Proxied onto `AgentOpenCache` (2026-08-12) rather than held in
    /// `@State`: `RootShell` destroys this whole view on every lower, so a
    /// `@State` board was rebuilt from nothing on every raise. Same spelling
    /// at every call site; only its lifetime changed.
    private var composition: AgentPanel.Composition {
        get { AgentOpenCache.shared.board }
        nonmutating set { AgentOpenCache.shared.board = newValue }
    }
    /// True from the moment `.task(id: isOpen)` starts computing the panel
    /// until `composition` actually has cards (2026-08-09, measured live:
    /// ~720ms of unbroken synchronous work over a real corpus, entirely on
    /// the main actor with no yield point — nothing could paint until it
    /// finished, which is what "opens on a black screen, then everything
    /// appears at once" actually was). `boardShowing` requires `!composition
    /// .isEmpty`, so `AgentOpenBoard` never even mounts during that window —
    /// this flag exists to show something IN that gap, not after it.
    @State private var panelLoading = false

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
            && TodayBrief.matchesAny(currentQuestion)
    }

    /// The brief as the turn being answered RIGHT NOW — true from the moment it
    /// commits, through the whole assembly and paint, until a follow-up makes it
    /// an ordinary conversation. Distinct from `briefLanding`, which is the
    /// SETTLED state (it waits on `answerStream.completed`) and so can't speak
    /// for the window where the document is still painting — which is exactly
    /// the window the scroll behaviour below has to get right.
    /// Any brief — the whole day OR one scope (2026-08-10). It was
    /// `matches`, which only ever recognised the UNSCOPED question, so every
    /// Money/Work/Life brief took the `.bottom` scroll anchor and opened at
    /// its own footer after the document painted.
    private var briefInView: Bool {
        turns.isEmpty && TodayBrief.matchesAny(currentQuestion)
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
    /// Returns the corpus it fetched, so the kept-ask digest refresh below can
    /// reuse it instead of fetching the whole store a second time on the same
    /// open (PERF 2026-08-11). Safe to hand on by the contract
    /// `KeptAskComposers.compose` already states in its own header: it filters
    /// `.live` at that one door, on every call, precisely because
    /// `refreshDigests` holds one array across a suspension per kind.
    private func computeSuggestions() async -> [Thing] {
        #if DEBUG
        // `-askStats "<key>:<n>[,…]|clear"` — seed the decay counters
        // headlessly (see AskMemory; self-guarded to once per launch), so
        // demotion verifies in one launch.
        AskMemory.seedFromLaunchArgs()
        // `-asksMade "<key>:<n>[,…]|clear"` — seed the proactive-minting
        // counter the same way, so the "keep it?" upgrade verifies in one
        // launch too.
        AskMemory.seedMadeFromLaunchArgs()
        let composerT0 = Date.now
        #endif
        var out: [AskOption] = []
        // One plain fetch, filtered in memory — a #Predicate can't compare
        // the Codable ThingKind enum (it throws at runtime, and try? made
        // the miss silent), and one over the transformable `tags` array traps.
        //
        // THE FULL WALK IS THE OPEN'S WHOLE COST, so it runs at most once per
        // launch (PERF 2026-08-12). Measured on a 13,412-row corpus: ~761ms
        // median, against ~90ms for everything else this function does. It is
        // a single `modelContext.fetch` — one uninterruptible call on the main
        // actor, with no yield point inside it — so it does not merely delay
        // the chips, it freezes the agent's rise animation while it runs.
        // That stutter is what "the agent is laggy opening" actually is.
        //
        // What still needs it: the tag vocabulary and per-tag counts behind
        // the two "Show <tag>" chips. `tags` is a transformable array, so it
        // can be neither predicated (it traps, see CLAUDE.md) nor counted in
        // SQL — every other counter here could be a `fetchCount` or a
        // date-predicated read. Two chips were costing the entire open.
        //
        // So the facts are CACHED and refreshed behind the board, which does
        // its own full fetch off the critical path anyway (`composeBoard`).
        // The freshness cost is one open: a chip count can be one arrival
        // stale before the refresh lands — the same trade the debounced feed
        // and the retained board already make, and a count that is briefly one
        // behind is a different thing from a count that is wrong.
        //
        // NOT projected, and that too is measured rather than assumed:
        // `propertiesToFetch` is what fixed the feed's and MainSurface's
        // per-body re-fetches, so narrowing this to the ten columns the chips
        // read was the obvious move. A/B'd on the same corpus it was
        // consistently SLOWER — ~1009ms against ~761ms — and it pushed the
        // board's fetch up with it. The heavy blobs are already
        // `.externalStorage` and were never in the row; what is left is inline
        // text SQLite reads either way, and the partial-fault bookkeeping
        // costs more than it saves. Don't re-add it without re-running that.
        let all: [Thing]
        if cachedChipFacts == nil {
            all = (try? modelContext.fetch(FetchDescriptor<Thing>())) ?? []
        } else {
            // Only the recent window the day-lede and the away pulse read —
            // both are windowed by construction, so this is small at any
            // corpus size. The counters come from the cache below.
            let floor = min(AppVisit.away?.lowerBound ?? .distantFuture,
                            Date.now.addingTimeInterval(-7 * 86_400))
            var recent = FetchDescriptor<Thing>(
                predicate: #Predicate { $0.capturedAt >= floor },
                sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
            recent.fetchLimit = 2000
            all = (try? modelContext.fetch(recent)) ?? []
        }
        #if DEBUG
        NSLog("[Casberi] composerPerfDEBUG| afterFetch=%dms count=%d",
              Int(Date.now.timeIntervalSince(composerT0) * 1000), all.count)
        #endif
        // ONE walk of the corpus for every counter the chips need (PERF
        // 2026-08-11). Each counter below used to be its own
        // `all.filter { … }.count` / `all.contains { … }` / `all.first { … }`
        // — TEN separate traversals of the whole corpus, on the main actor,
        // per composer open — plus an ELEVENTH inside `tagCandidates()`,
        // which was `RootShell.projectTags`: its own unbounded, fully
        // hydrated `fetch(FetchDescriptor<Thing>())` of the very rows this
        // line had already fetched. So a composer open materialised the whole
        // corpus twice and then walked it eleven times.
        //
        // Why that costs more than it looks: a `Thing` property read is not a
        // struct field read. It goes through CoreData's
        // `_PF_Handler_Public_GetProperty`, which is exactly the frame the
        // 6,000-row main-thread profile found underneath `things.getter` at
        // 26.6% (`scripts/output/profile-ios-cold-6k.txt`). The cost is per
        // (row × property read), so folding eleven walks into one divides
        // that traffic by eleven. Same numbers, same order, one walk.
        //
        // `now` is snapshotted rather than re-read per filter — the old form
        // called `.now` inside each closure, so the "today", "this week",
        // "overdue" and "upcoming" windows were each measured from a slightly
        // different instant. One clock for one open.
        let standingIn = contextSource()
        // The cache, or the one full walk that seeds it. `contextSourceRecent`
        // is the one counter that depends on WHERE you opened the agent from,
        // so it is recomputed per open off the recent rows rather than cached.
        var scan = cachedChipFacts ?? AgentChipFacts.scan(all, contextSource: standingIn, now: .now)
        if cachedChipFacts != nil {
            scan.contextSourceRecent = all.reduce(into: 0) { n, t in
                if let standingIn, t.source == standingIn,
                   t.capturedAt >= Date.now.addingTimeInterval(-3 * 86_400) { n += 1 }
            }
        }
        cachedChipFacts = scan
        tagPool = scan.tagPool
        // NOTHING about the corpus itself goes under the greeting (user
        // ruling 2026-07-31: "casberi is about insight and management, over
        // tons of stuff, seeing numbers is just annoyance"). Three lines died
        // here in one day, and they died for one reason, not three: the stat
        // line ("2,481 things, across 14 apps."), the milestone ("1,000
        // things banked.") and the anniversary ("3 years since your first
        // thing.") were all FACTS ABOUT THE PILE — a scoreboard for having
        // saved things, on the surface whose job is to tell you what the pile
        // MEANS. The day's own sentence below is the room's lead now.
        // The day, in the agent's own room (2026-07-31). Prefers the brief's
        // ranked lede — risk, then money, then a person, then a deadline —
        // which `TodayBrief.compose` republishes to the app group on every
        // foreground for the widget; anyone who hasn't kept the `today` ask
        // never publishes one, so the whisper's own line (synchronous, off
        // the fetch just paid for) stands in. Empty = nothing to say today,
        // and the card doesn't draw.
        dayLede = WidgetLede.current() ?? DayBrief.whisper(things: all)?.detail ?? ""
        // One busy-publisher scan per open, shared by the timely chip below
        // and the placeholder examples (both want the same dominant handle).
        // Counted in the single walk above rather than in a pass of its own.
        let busy = scan.busyPublisher
        invitationPool = computeInvitationPool(tokenTitle: scan.firstTokenTitle, busy: busy)
        // Context-aware lead (2026-07-12): if you opened the composer while
        // looking at one source's feed, its recap leads the chips — the
        // composer meets you where you are. Only when that source actually has
        // things to synthesize (honesty rule: a chip must answer).
        if let src = standingIn, scan.sourcesSeen.contains(src) {
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
                out.append(AskOption(kind: "context", title: "What's new in \(src)?",
                                     glyph: "app.badge", memoryKey: "context:\(src)",
                                     signal: sig(scan.contextSourceRecent)))
            }
            // A category sibling (2026-07-20) — only when it's a meaningfully
            // BROADER ask than the single-source lead above (more than one
            // source in the category), else it would just repeat the same
            // question in different words.
            if let offer = BridgeCatalog.offers.first(where: { $0.name == src }) {
                let cat = BridgeCatalog.category(of: offer)
                let sourcesInCat = Set(BridgeCatalog.offers
                    .filter { BridgeCatalog.category(of: $0) == cat }.map(\.name))
                if sourcesInCat.count > 1, !sourcesInCat.isDisjoint(with: scan.sourcesSeen) {
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
        let todayCount = scan.todayCount
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
        if scan.sourcesSeen.contains("Tokens"),
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
            // Case-insensitively, exactly as the old per-tag `filter` did —
            // `scan.tagCounts` is keyed by the lowercased tag and counts each
            // thing once per distinct tag, so "Recipes" and "recipes" on one
            // thing still count as one.
            let n = scan.tagCounts[tag.lowercased()] ?? 0
            out.append(AskOption(kind: "showtag", title: "Show \(tag)",
                                 glyph: "tag", memoryKey: "showtag:\(tag)",
                                 signal: sig(n)))
        }
        // The overdue chip (2026-07-20) — mirrors KeptAskComposers.overdue's
        // own filter (light duplication, same precedent as elsewhere in this
        // function) so the tile can't offer what its composer would call
        // empty.
        let overdueCount = scan.overdueCount
        if overdueCount > 0 {
            out.append(AskOption(kind: "overdue", title: "What's overdue?",
                                 glyph: "exclamationmark.circle", signal: sig(overdueCount)))
        }
        // …and its forward half (2026-07-21). Same duplication precedent, same
        // week horizon `KeptAskComposers.upcoming` uses, so the tile and its
        // composer can never disagree about whether there's anything to say.
        if scan.upcomingCount > 0 {
            out.append(AskOption(kind: "upcoming", title: "What's coming up?",
                                 glyph: "clock.badge", signal: sig(scan.upcomingCount)))
        }
        // The Noticed chip (2026-07-20) — the board's old "Noticed" card had
        // no home after the board retired (prd §131); this is its one way
        // back in. Tile-only: there's no natural typed trigger for a
        // spontaneous connection, so it's never in `recognizeKeptAskKind`.
        if let noticed = HomeInsightStore.shared.line, !noticed.isEmpty {
            out.append(AskOption(kind: "noticed", title: "Noticed",
                                 glyph: "sparkle"))
        }
        // The deterministic notice behind the bar's glint (prd §384,
        // `AgentNoticed`) — LEADS while today's observation stands, because it
        // is the one chip that exists only on a day something real happened.
        // Its query routes to `RootShell.answerDocument`'s `AgentNoticed`
        // branch: the line plus its evidence rows, checkable, no model.
        if AgentNoticed.shared.notice != nil {
            out.insert(AskOption(kind: "observation", title: "Noticed today",
                                 glyph: "sparkles"), at: 0)
        }
        if !scan.sourcesSeen.isEmpty {
            out.append(AskOption(kind: "week", title: "What's this week?",
                                 glyph: "calendar", signal: sig(scan.weekCount)))
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
        // THE GENERIC ASK CHIPS RETIRED (user ruling 2026-08-14, prd §386b:
        // "the chips we have need to go too … beyond that we just had chips
        // to have them"). The whole suggestion machine above still runs — it
        // feeds the decay counters and the recognizers — but the only chip
        // that RENDERS is the observation one, because it is the opposite of
        // a chip-for-chips'-sake: it exists only on a day something real
        // happened, and it is the glint's landing. Everything evergreen
        // ("What's this week?", the recaps, the wallet ask) is a typed ask
        // away, and the kept pills remain the person's own standing set.
        suggestions = selectSuggestions(from: ranked, slots: 7)
            .filter { $0.kind == "observation" }
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
        // Category chips (scoped-brief-spec.md) — one per BRIEF SCOPE the
        // corpus holds at least one connected thing in. ALWAYS offered rather
        // than ranked/decayed/capped like `suggestions` above: the spec
        // frames these as a fixed row of scope pickers under the input, not
        // a suggestion competing for a slot.
        categoryChips = Self.computeCategoryChips(sourcesSeen: scan.sourcesSeen)
        #if DEBUG
        NSLog("[Casberi] composerPerfDEBUG| beforeBuildPanel=%dms",
              Int(Date.now.timeIntervalSince(composerT0) * 1000))
        #endif
        // The board does NOT get built here (PERF 2026-08-12). It used to be
        // the last thing this function did, which meant the ask chips — ~90ms
        // of work, and the whole reason the agent has anything to show at
        // once — waited on it, because `chipsAppeared` only flips after this
        // function returns. Measured on a 12,000-row corpus: chips ready at
        // 721ms, board at 2,270ms, and the person looked at nothing for the
        // whole 2.3s. The caller reveals the chips and THEN composes the board
        // (see the `.task(id: isOpen)` below).
        #if DEBUG
        NSLog("[Casberi] composerPerfDEBUG| chipsReady=%dms",
              Int(Date.now.timeIntervalSince(composerT0) * 1000))
        NSLog("[Casberi] askTiles: %@",
              suggestions.map { $0.memoryKey + ($0.timely ? "*" : "") + ($0.signal ?? "") }
                  .joined(separator: ","))
        #endif
        return all
    }

    /// The board, composed after the chips are already on screen — see
    /// `computeSuggestions()`'s tail for why the two are no longer one call.
    ///
    /// Takes its OWN, unprojected fetch and returns it. The chips read a
    /// narrow projection now, and the panel's room figures plus every kept-ask
    /// composer read far more widely than that — handing either of them the
    /// chip projection would fault a column at a time, per row, which is
    /// slower than the full fetch it was meant to save. Paying a full fetch
    /// HERE is free in the way it wasn't before: nothing is waiting on it.
    @discardableResult
    private func composeBoard() async -> [Thing] {
        #if DEBUG
        let t0 = Date.now
        #endif
        let corpus = (try? modelContext.fetch(FetchDescriptor<Thing>())) ?? []
        // The chip counters ride this fetch rather than buying their own — the
        // next open then costs no full walk at all. `contextSourceRecent` is
        // left to the open that reads it (it depends on which room you were
        // standing in, which this pass cannot know).
        cachedChipFacts = AgentChipFacts.scan(corpus, contextSource: nil, now: .now)
        composition = await buildPanel(all: corpus)
        #if DEBUG
        NSLog("[Casberi] composerPerfDEBUG| boardReady=+%dms cards=%d",
              Int(Date.now.timeIntervalSince(t0) * 1000), composition.cards.count)
        AgentPanelProbe.log(composition)
        #endif
        return corpus
    }

    /// Every BRIEF SCOPE with at least one thing in the corpus, as chips —
    /// three (`BriefScope.scopes`: Money, Work, Life), deliberately fewer
    /// than the app catalog's own ten categories (user, 2026-08-08: "how many
    /// categories do we... want to offer to search across, lets limit
    /// those"). "Connected" needs no separate check for the same reason
    /// `computeSuggestions`' own category-sibling chip doesn't (line ~700
    /// above): a source with no connected bridge can never have landed a
    /// `Thing`. A scope with nothing connected simply has no chip (spec's
    /// edge case — "don't render its chip").
    ///
    /// NO "Everything" chip (user, 2026-08-08: "do we need an everything
    /// chip? i mean everything is the default") — the unscoped brief is
    /// already reachable two other ways (the whisper capsule, the kept
    /// "today" pill), and a fourth door to it crowded a row whose whole
    /// point is three tight, purposeful choices. `TodayBrief.title` and
    /// `.matches` are UNCHANGED — typing "what's going on" or tapping either
    /// of those still works exactly as before; only the dedicated CHIP for
    /// it is gone.
    ///
    /// `query` sends a phrase already wired to resolve to this exact scope —
    /// "How's my <scope> stuff?", the same phrase `namedAskTarget`'s "how's
    /// my " prefix already resolves to `.category(scope)`
    /// (`KeptAskComposers.swift`) — so a tap runs through the identical
    /// pipeline a typed ask would, never a shortcut that could answer
    /// differently.
    ///
    /// Takes the source set `corpusScan` already built rather than the corpus
    /// (PERF 2026-08-12): `Set(all.map(\.source))` was a full-corpus walk plus
    /// a 12,000-element intermediate, and it is the same set the single scan
    /// above already has. The scope→sources join is `categorySources`, the one
    /// definition four readers now share.
    private static func computeCategoryChips(sourcesSeen present: Set<String>) -> [CategoryChip] {
        guard !present.isEmpty else { return [] }
        // ONE overview, not three scoped screens (user, 2026-08-14, prd §386:
        // "we need one composer screen for money work life day overview, not
        // three separate ones… we have good stuff in each but each is not all
        // good"). The unscoped Today brief already carries each scope's good
        // half — the money hero and movers, the deadlines runway, the alerts,
        // Life's contact sheet, the themes map — so three doors that each
        // opened a narrower, weaker version of it were three chances to land
        // on the junk half (the scoped facts paragraph, which is also where
        // the prompt-echo leak lived). The scoped composes themselves survive
        // for a TYPED "how's my money stuff" — capability kept, doors
        // consolidated. `TodayBrief.title` is the canonical question, the
        // same string the whisper and the kept pill send, so this chip runs
        // exactly the pipeline those do.
        return [CategoryChip(id: "day", title: TodayBrief.title,
                             query: TodayBrief.title)]
    }

    // MARK: - The panel (prd §334)


    /// Compose the open: the lead, then every connected room's own figure.
    ///
    /// Synchronous, off the corpus walk `computeSuggestions()` already paid
    /// for. Every registry below is pure over `[Thing]` by contract and every
    /// per-room reading it needs is already in memory or in UserDefaults, so
    /// there is nothing to await — which matters, because the alternative
    /// (kick a task, repaint on arrival) shows a visible frame of empty panel
    /// on every single open.
    @MainActor
    private func buildPanel(all: [Thing]) async -> AgentPanel.Composition {
        // `.live` at this one door — every value below is read off these models
        // and then never touched again (liveness corollary 4).
        let corpus = all.filter(\.isLive)
        var out = AgentPanel.Composition()

        // Group by room. Import receipts are excluded everywhere here for the
        // reason every aggregate in this app excludes them: the app's own row
        // about a sync is not something the person captured.
        var bySource: [String: [Thing]] = [:]
        for thing in corpus where !Corpus.isImportReceipt(thing) {
            bySource[thing.source, default: []].append(thing)
        }

        // STARTED FIRST, awaited last (PERF 2026-08-12). The semantic map is
        // the one figure whose cost is arithmetic rather than a walk — power
        // iteration over N × 512 — and `scripts/main-thread-profile.sh` put it
        // at 521 of `buildPanel`'s 707 samples on a 12,000-row corpus: the
        // largest single thing the agent's open does, and the only part of it
        // that never needed the main thread.
        //
        // Two changes together, and BOTH are needed. Moving it off the main
        // actor stops it blocking paint and touch; starting it here, before
        // the room loop, is what takes it off the critical PATH — awaited
        // where it was computed, an off-actor task costs exactly the same wall
        // clock as an inline one, which is what the first cut of this measured
        // (2837ms → 2932ms, i.e. nothing). Now it overlaps every room figure
        // below and the open pays whichever half is slower, not their sum.
        let mapEntries = semanticEntries(corpus)
        let semanticMap = Task.detached(priority: .userInitiated) {
            AgentPanelFigures.scatter(mapEntries)
        }

        var cards: [AgentPanel.Card] = []
        // YIELDS between rooms (2026-08-10). This loop composes a figure per
        // connected room — on a real corpus that is ~40 rooms and measured
        // ~800ms of the 870ms `computeSuggestions` costs, all of it
        // uninterrupted main-actor work. The cost is not the bug; the
        // UNINTERRUPTEDNESS is: nothing can paint and no touch can be handled
        // for the whole run, so the composer's own loading skeleton — a
        // SwiftUI opacity animation, driven by the main run loop — freezes
        // solid at whatever frame it was on. Measured on the sim: a
        // frame-to-frame pixel diff of EXACTLY 0.00 across the window, i.e.
        // the screen is not being redrawn at all, which is what the report
        // "a black screen loads and hangs, then the stuff paints" actually is.
        //
        // Yielding every few rooms hands the run loop back often enough to
        // draw and to stay responsive to touch. It does NOT make the work
        // faster — the panel still costs what it costs — it makes the wait
        // animated and interruptible instead of a hang.
        for (i, entry) in bySource.enumerated() {
            if i % 5 == 0 { await Task.yield() }
            guard let card = roomFigure(source: entry.key, things: entry.value) else { continue }
            cards.append(card)
        }
        await Task.yield()
        if let wallet = walletCurve() { cards.append(wallet) }
        // The money's sankey (§240's flow band), whenever the window holds a
        // band worth drawing — the user's ruling by name: "i want for example
        // the sankey diagram to show when its populated". `WalletFlowSource`
        // is pure over `[Thing]` and declines an unpriceable or single-sided
        // window itself, so the panel inherits the room's own honesty gates.
        if let flow = walletFlow(corpus: corpus) { cards.append(flow) }
        cards.append(contentsOf: await crossSourceCards(corpus, semanticMap: semanticMap))
        cards.append(contentsOf: roomHeadCards(corpus))
        for social in ["Farcaster", "Bluesky"] {
            if let card = socialChannelCard(corpus, source: social) { cards.append(card) }
        }
        // Dictionary iteration above is per-process in its order; `rank` is a
        // TOTAL sort, which is what makes the panel identical across launches
        // (the §332 hashing bug, one surface over).
        out.cards = AgentPanel.rank(cards)
        return out
    }

    /// The per-source ROOM HEADS that draw (user, 2026-08-07: "if we have a
    /// visualization in the app that is active some form of it should by and
    /// large be in the agent").
    ///
    /// These live outside `FeedInsight` because their subject is bridge state
    /// in UserDefaults rather than corpus rows, so no registry can reach them —
    /// which is exactly why they were missing from the panel. Only the ones
    /// that genuinely DRAW are lifted: Stripe's and Cloudflare's heads are a
    /// time rail whose own doc calls it a restatement of the rows beneath it,
    /// and §334 says a card earns its slot by drawing something.
    @MainActor
    private func roomHeadCards(_ corpus: [Thing]) -> [AgentPanel.Card] {
        var out: [AgentPanel.Card] = []
        // Circle x402 — sellers by service count, the treemap the room leads
        // with. Reuses the room's OWN composer, so the tile and the room can
        // never disagree about who is biggest.
        if let room = X402Room.compose(sellers: X402State.sellers,
                                       listings: X402State.listings,
                                       typical: X402State.medianPrice) {
            let cells = room.cells.map {
                AgentPanel.Cell(label: $0.label, weight: $0.services)
            }
            out.append(AgentPanel.Card(source: "Circle x402", key: "x402.sellers",
                                       title: String(localized: "Who sells the most"),
                                       caption: "", figure: .treemap(cells),
                                       affinity: ChipMemory.weight(for: "Circle x402"),
                                       reading: nil, rising: nil))
        }
        // PostHog — the busiest watched metric's own seven-day curve. The room
        // draws it inside a milestone ring (`MetricDisc`); the panel draws the
        // curve alone, because a ring at tile scale is two readings competing
        // in 118pt and the curve is the half that answers "is this moving".
        let metrics = PostHogState.all()
        if let busiest = metrics
            .filter({ $0.value.series.count >= 3 })
            .max(by: { $0.value.total < $1.value.total }) {
            let series = busiest.value.series.map(Double.init)
            let first = series.first ?? 0, last = series.last ?? 0
            out.append(AgentPanel.Card(source: "PostHog", key: "posthog.metric",
                                       title: busiest.key, caption: "",
                                       figure: .curve(series),
                                       affinity: ChipMemory.weight(for: "PostHog"),
                                       reading: nil,
                                       // §83's flat rule — an unmoved metric
                                       // gets no direction and no colour.
                                       rising: abs(last - first) < 0.5 ? nil : last > first))
        }
        // Apple Wallet — where the money actually went, as the room's own
        // merchant share bars. `share` is already the fraction of settled
        // spend, so the panel re-derives nothing and the two can't disagree.
        let spends = AppleWalletRoomSource.spends(from: corpus)
        if let card = AppleWalletRoom.compose(spends: spends, now: .now),
           !card.merchants.isEmpty {
            let bars = card.merchants.prefix(4).map {
                AgentPanel.Bar(label: $0.name,
                               value: Int(($0.share * 1000).rounded()),
                               detail: String(format: "%.0f%%", $0.share * 100))
            }
            out.append(AgentPanel.Card(source: "Apple Wallet", key: "wallet.merchants",
                                       title: String(localized: "Where you spend"),
                                       caption: "", figure: .bars(Array(bars)),
                                       affinity: ChipMemory.weight(for: "Apple Wallet"),
                                       reading: nil, rising: nil))
        }
        // Stripe and Cloudflare (prd §338, user: "they have cool visuals. and
        // since they are not too complicated they could be smaller in size").
        // §337 left both out because their FULL cards are mostly rows and the
        // rail's own doc calls it a restatement of them — but that reasoning
        // was about the whole card. The RAIL ALONE is the half that draws, and
        // it is the one figure here that gains from being small: one axis,
        // dots, no labels to clip.
        if let stripe = StripeRoomSource.compose(things: corpus) {
            let days = stripe.items.map(\.days)
            let span = StripeRoom.span(days: days)
            let marks = days.map {
                AgentPanel.RunwayMark(position: StripeRoom.position(days: $0, span: span),
                                      overdue: $0 < 0, urgent: $0 >= 0 && $0 <= 3)
            }
            out.append(AgentPanel.Card(source: "Stripe", key: "stripe.runway",
                                       title: String(localized: "What's due"),
                                       caption: "",
                                       figure: .runway(marks: marks,
                                                       span: StripeRoom.spanLabel(span: span)),
                                       affinity: ChipMemory.weight(for: "Stripe"),
                                       reading: nil, rising: nil))
        }
        if let cf = CloudflareRunwaySource.compose(things: corpus) {
            // Cloudflare's items carry an OPTIONAL day count — a certificate
            // with no published expiry has no place on an axis, so it is
            // dropped rather than pinned somewhere invented.
            let days = cf.items.compactMap(\.days)
            let span = StripeRoom.span(days: days)
            let marks = days.map {
                AgentPanel.RunwayMark(position: StripeRoom.position(days: $0, span: span),
                                      overdue: $0 < 0, urgent: $0 >= 0 && $0 <= 3)
            }
            out.append(AgentPanel.Card(source: "Cloudflare", key: "cloudflare.runway",
                                       title: String(localized: "Expiring"),
                                       caption: "",
                                       figure: .runway(marks: marks,
                                                       span: StripeRoom.spanLabel(span: span)),
                                       affinity: ChipMemory.weight(for: "Cloudflare"),
                                       reading: nil, rising: nil))
        }
        return out
    }

    /// The social rooms' channel treemap (prd §337) — the answer to "the
    /// farcaster casting summary is a really weak visualization".
    ///
    /// Those rooms lead with `SocialRosterHero`, an avatar scroller rather than
    /// a chart, so with the year-wall demoted they contributed nothing at all.
    /// `channelName` has been stamped on every cast since §81 and nothing has
    /// ever drawn it — which makes this the topic map the user prefers, over a
    /// field that already exists.
    @MainActor
    private func socialChannelCard(_ corpus: [Thing], source: String) -> AgentPanel.Card? {
        var counts: [String: Int] = [:]
        for thing in corpus where thing.source == source {
            guard let channel = thing.channelName, !channel.isEmpty else { continue }
            counts[channel, default: 0] += 1
        }
        guard counts.count >= 2 else { return nil }
        let cells = counts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(4)
            .map { AgentPanel.Cell(label: $0.key, weight: $0.value) }
        return AgentPanel.Card(source: source, key: "\(source).channels",
                               title: String(localized: "Where you post"),
                               caption: "", figure: .treemap(Array(cells)),
                               affinity: ChipMemory.weight(for: source),
                               reading: nil, rising: nil)
    }

    /// The vectors the semantic map projects, read on the main actor because
    /// `thing.embedding` is a stored property — but found by PREDICATE rather
    /// than by walking the corpus (PERF 2026-08-12).
    ///
    /// `scatterCap`'s note is right that unpacking every vector would blow the
    /// open's budget, and it capped the unpacking — but the FILTER that fed
    /// the cap still read `embedding` on every row, and `embedding` is an
    /// `.externalStorage` attribute: the one column class where touching a row
    /// is a separate read rather than a field access. So the cap bounded the
    /// arithmetic and not the I/O, which on a 12,000-row corpus is the larger
    /// half. Asking SQLite for the newest rows that HAVE one touches exactly
    /// as many as the map can draw.
    ///
    /// Falls back to the old in-memory walk if the predicate is refused, so
    /// the worst case is the cost we had rather than a missing figure.
    private func semanticEntries(_ corpus: [Thing]) -> [AgentPanelFigures.Entry] {
        var embedded = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.embedding != nil },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        // Fetched a little wide: import receipts are dropped below, and they
        // are the one class that can hold a vector without belonging on a map
        // of what the person kept.
        embedded.fetchLimit = Self.scatterCap * 2
        let rows = (try? modelContext.fetch(embedded))
            ?? corpus.filter { $0.embedding != nil }.sorted { $0.capturedAt > $1.capturedAt }
        return rows
            .filter { $0.isLive && !Corpus.isImportReceipt($0) }
            .prefix(Self.scatterCap)
            .compactMap { thing -> AgentPanelFigures.Entry? in
                guard let packed = thing.embedding,
                      let vector = EmbeddingIndex.unpack(packed) else { return nil }
                return AgentPanelFigures.Entry(source: thing.source, at: thing.capturedAt,
                                               terms: thing.ocrTopics + thing.tags,
                                               vector: vector)
            }
    }

    /// The three figures no ROOM can draw (prd §337) — the clock, the weeks,
    /// and meaning. Composed over the whole corpus rather than one room's
    /// slice, which is exactly why `FeedInsight`'s registries can't produce
    /// them and why the All feed has never had a hero.
    ///
    /// Built from one flat pass: `AgentPanelFigures` is Foundation-only over
    /// `Entry`, so nothing here hands a `Thing` across a boundary.
    ///
    /// `semanticMap` is handed in already RUNNING (PERF 2026-08-12) — see
    /// `buildPanel`, which starts it before the room loop so the projection
    /// overlaps every other figure instead of following them.
    @MainActor
    private func crossSourceCards(
        _ corpus: [Thing],
        semanticMap: Task<(dots: [AgentPanel.Dot], clusters: [AgentPanel.DotCluster]), Never>
    ) async -> [AgentPanel.Card] {
        // Only rows either figure can actually reach (PERF 2026-08-12).
        //
        // `dial` filters to the last 7 days and `river` to the last 10 weeks,
        // both with an explicit `entry.at >= start` — so a row older than the
        // WIDER of the two windows contributes nothing to anything here. It
        // was still being mapped into an `Entry`, and that map is not free:
        // `thing.ocrTopics + thing.tags` reads two stored arrays and
        // allocates a third, per row, and this ran over the whole corpus.
        // `scripts/main-thread-profile.sh` put `crossSourceCards` at 506 of
        // `buildPanel`'s 743 samples on a 12,000-row corpus — the single
        // biggest piece of the agent's open.
        //
        // Not an approximation: same rows in, same figures out. The window is
        // taken from `river`'s own default so the two can't drift — if that
        // default ever widens, this widens with it.
        //
        // No upper bound here on purpose. Both consumers cap themselves at
        // `now` (a calendar event carries a FUTURE `capturedAt`), so clamping
        // it twice would just be a second place to get it wrong.
        let riverStart = Calendar.current.date(byAdding: .day,
                                               value: -7 * AgentPanelFigures.riverWeeks,
                                               to: .now) ?? .distantPast
        let entries = corpus
            .filter { !Corpus.isImportReceipt($0) && $0.capturedAt >= riverStart }
            .map { thing in
                AgentPanelFigures.Entry(source: thing.source,
                                        at: thing.capturedAt,
                                        terms: thing.ocrTopics + thing.tags,
                                        vector: nil)
            }
        guard !entries.isEmpty else { return [] }
        var out: [AgentPanel.Card] = []
        func card(_ key: String, _ title: String, _ caption: String,
                  _ figure: AgentPanel.Figure) -> AgentPanel.Card {
            // Source "You" so the corner glyph and hue read as the app's own
            // rather than borrowing a room's — these belong to no room, which
            // is the whole point of them. The tap lands on the All feed.
            AgentPanel.Card(source: "All", key: key, title: title,
                            caption: AgentPanel.clamp(caption), figure: figure,
                            affinity: 0, reading: nil, rising: nil)
        }
        let marks = AgentPanelFigures.dial(entries)
        if !marks.isEmpty {
            // The dial's own caption says what its SHAPE means — a tile-scale
            // dial can carry no legend, and "when things land" said nothing a
            // reader couldn't already see (§339).
            let caption = AgentPanelFigures.busiestWindow(marks)
                ?? String(localized: "when things land")
            out.append(card("cross.dial", String(localized: "Your week, by the hour"),
                            caption, .dial(marks)))
        }
        let bands = AgentPanelFigures.river(entries)
        if bands.count >= 2 {
            out.append(card("cross.river", String(localized: "What you keep circling"),
                            String(localized: "ten weeks"), .river(bands)))
        }
        // The semantic map — the third §337 figure, and the only one on this
        // surface that draws §282's embeddings, which have served retrieval
        // invisibly since the day they shipped.
        //
        // Built from its OWN pass rather than from `entries` above — see
        // `semanticEntries` for how its rows are found, and `buildPanel` for
        // why the projection is already running by the time we get here. On a
        // device with no embeddings this yields nothing and the map simply
        // doesn't appear, which is the honest state.
        let map = await semanticMap.value
        if !map.dots.isEmpty, !map.clusters.isEmpty {
            out.append(card("cross.scatter", String(localized: "Your things, by meaning"),
                            String(localized: "what sits near what"),
                            .scatter(dots: map.dots, clusters: map.clusters)))
        }
        return out
    }

    /// How many vectors the semantic map projects.
    ///
    /// `AgentPanelFigures.scatter` caps at 300 of its own; this is tighter
    /// because the projection is the one piece of real arithmetic the panel
    /// does on open — power iteration over N × 512 — and the open is
    /// synchronous by design (§334: the alternative shows a frame of empty
    /// panel every time). 150 points already saturate a tile visually, so the
    /// extra 150 buy nothing a person can see.
    private static let scatterCap = 150

    /// What a room would LEAD with, as a figure.
    ///
    /// The chain mirrors `FeedScreen.shapedSections` exactly — topic map,
    /// leaderboard, distribution, mosaic, heatmap — so the tile shows the same
    /// reading the room itself shows. That is the whole contract of the panel:
    /// it is a window onto the room, and a tile that previewed a DIFFERENT
    /// figure than the room draws would be worse than no tile, because you'd
    /// tap it looking for what you just saw. **Change the order there, change
    /// it here** (the `-roomInsightProbe` rule).
    ///
    /// Rooms whose hero is text (Stripe's rail, PostHog's readings, the
    /// approvals card) are deliberately absent: §334 says a card earns its slot
    /// by drawing something.
    @MainActor
    private func roomFigure(source: String, things: [Thing]) -> AgentPanel.Card? {
        func card(_ title: String, _ caption: String,
                  _ figure: AgentPanel.Figure) -> AgentPanel.Card {
            AgentPanel.Card(source: source, key: source, title: title,
                            caption: AgentPanel.clamp(caption), figure: figure,
                            affinity: ChipMemory.weight(for: source),
                            reading: nil, rising: nil)
        }
        // The per-source heads OUTRANK everything below in the room itself, and
        // all but one of them are text heroes §334 excludes on purpose. X is
        // the exception (2026-08-13, prd §375): its head is a FIGURE — the
        // years of an archive — so leaving it out would make this tile preview
        // the topic treemap while the room draws a year strip, which is the
        // exact drift this chain's contract forbids.
        //
        // Drawn as bars rather than a pulse: the room's own rows are the top
        // years ranked, a tile fits four, and a year is a label a person reads.
        if let room = XRoomSource.compose(things: things), source == XRoomSource.source {
            return card(XRoom.headline(room), XRoom.note(room),
                        .bars(XRoom.rows(room).prefix(4).map {
                            AgentPanel.Bar(label: String($0.year), value: $0.posts,
                                           detail: $0.posts.formatted())
                        }))
        }
        if let map = FeedInsight.topicMap(source: source, things: things) {
            // Four rows, not six: the inventory of small forms is explicit that
            // a six-cell map's last slot is one grid unit wide and its label
            // collapses to two clipped characters at tile scale.
            return card(map.title, map.subtitle,
                        .treemap(map.cells.prefix(4).map {
                            AgentPanel.Cell(label: $0.label, weight: $0.count)
                        }))
        }
        if let board = FeedInsight.leaderboard(source: source, things: things) {
            return card(board.title, board.subtitle,
                        .bars(board.rows.prefix(4).map {
                            AgentPanel.Bar(label: $0.label, value: $0.value, detail: $0.detail)
                        }))
        }
        if let split = FeedInsight.distribution(source: source, things: things) {
            let total = max(1, split.segments.reduce(0) { $0 + $1.count })
            return card(split.title, split.subtitle,
                        .rail(split.segments.map {
                            AgentPanel.Segment(label: $0.label,
                                               share: Double($0.count) / Double(total),
                                               tone: toneIndex($0.tone),
                                               count: $0.count)
                        }))
        }
        if let wall = FeedInsight.mosaic(source: source, things: things) {
            // `Mosaic.Tile` carries no per-item title, so every tile shares
            // the room's own mosaic title as its loading/failed label (spec
            // item 4) — "Your pins" while a Pinterest thumbnail is still
            // fetching reads as content; a bare gray box reads as broken.
            return card(wall.title, wall.subtitle,
                        .wall(wall.tiles.prefix(4).map {
                            AgentPanel.WallTile(url: $0.url, label: wall.title)
                        }))
        }
        if let label = FeedHeatmap.label(for: source) {
            // Only a HABIT earns the pulse tile (user, 2026-08-14, prd §386:
            // the casts/screenshots/posts grids were "kinda useless"). The
            // grid is a consistency-over-time reading, which is a real answer
            // where the acts are YOURS — journaling, writing, training,
            // chatting — and noise where the room is content that merely
            // arrived: three identical activity smudges saying "when" about
            // rooms whose whole point is WHO and WHAT. A content room whose
            // better figures (topic map, leaderboard, mosaic) all declined
            // now composes NO tile — an absent tile beats a tile that
            // answers nothing — while its FEED keeps the year heatmap as the
            // documented fallback (§247's chain, unchanged).
            guard Self.pulseWorthy.contains(source) else { return nil }
            let counted = FeedHeatmap.counted(things, label: label)
            // Twelve weeks, not the room's 53. A full year at tile scale is
            // ~2.7pt cells — unreadable — while the windowed grid the social
            // rooms already draw reads fine.
            return card(label.title, label.units, .pulse(dailyCounts(counted, days: 7 * 12)))
        }
        return nil
    }

    /// The rooms whose panel tile may be the activity pulse — the subset of
    /// `FeedHeatmap.labels` where the counted acts are the person's own habit
    /// (see the guard above). Spelled here rather than as a flag on the
    /// heatmap registry because the FEED's fallback rightly keeps drawing the
    /// year grid for every registered room; only the tile declines.
    private static let pulseWorthy: Set<String> = [
        "Day One", "Apple Journal", "Obsidian", "Notion",
        "Apple Health", "Strava", "ChatGPT", "Claude", "Gemini",
    ]

    /// `FeedInsight.Tone` as the plain index `AgentPanel` carries, so the model
    /// layer stays free of SwiftUI's Color.
    private func toneIndex(_ tone: FeedInsight.Tone) -> Int {
        switch tone {
        case .positive: return 1
        case .negative: return 2
        default:        return 0
        }
    }

    /// Per-day counts over the last `days`, oldest first.
    private func dailyCounts(_ things: [Thing], days: Int) -> [Int] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var buckets = Array(repeating: 0, count: days)
        for thing in things {
            let d = cal.dateComponents([.day], from: cal.startOfDay(for: thing.capturedAt),
                                       to: today).day ?? -1
            guard d >= 0, d < days else { continue }
            buckets[days - 1 - d] += 1
        }
        return buckets
    }

    /// The wallet's own curve — the one figure with no room registry behind it,
    /// because the wallet's hero is a balance line rather than a count of rows.
    /// Reads the samples already recorded on this device; nil until enough
    /// aligned points exist, which is the honest state for a new wallet.
    @MainActor
    private func walletCurve() -> AgentPanel.Card? {
        // A TIME window, not a sample count (prd §341, user: "last 24 hours is
        // what someone is looking for naturally").
        //
        // It read the newest 24 SAMPLES, and `recordSample` throttles to one
        // every four hours — so the hero's percentage was silently spanning
        // about four days while sitting beside a Wallet room labelling its own
        // range. Worse, a sample-count window means a DIFFERENT span depending
        // on how often the app was opened, so the same number meant something
        // different week to week.
        let all = WalletStore.shared.combinedValueSamples()
        let dayAgo = Date.now.addingTimeInterval(-24 * 3600)
        let recent = all.filter { $0.at >= dayAgo }
        // Under the curve's own floor the day says nothing, so it widens — and
        // SAYS SO. A curve labelled "today" that isn't is the §83 failure this
        // whole change exists to close.
        let useDay = recent.count >= 3
        let window = useDay ? recent : Array(all.suffix(6))
        let samples = window.map(\.usd)
        guard samples.count >= 3 else { return nil }
        let windowLabel: String = {
            if useDay { return String(localized: "today") }
            guard let first = window.first?.at else { return "" }
            let days = max(1, Calendar.current.dateComponents([.day],
                                                              from: first, to: .now).day ?? 1)
            return String(localized: "\(days)d")
        }()
        // (Already windowed above.)
        // The hero's ONE reading — the balance with its move, which is a
        // reading and not a tally (§213 bans counting things; a number the
        // room already says about itself is not a count).
        let first = samples.first ?? 0, last = samples.last ?? 0
        let pct = first > 0 ? (last - first) / first * 100 : 0
        // §83's flat rule: a change that rounds to zero has no direction, so
        // it gets no sign, no colour and no pill.
        let flat = abs(pct) < 0.05
        let reading = flat
            ? AgentPanel.compactUSD(last)
            : AgentPanel.compactUSD(last) + String(format: " · %+.1f%%", pct)
        // "a lot of space for a simple sparkline" → "treemap of holdings is
        // useful there i think no?" (spec item 2, 2026-08-07). The hero
        // already gets double height for one line and one curve; the newest
        // CACHED per-wallet holdings (recorded at each wallet's own normal
        // sync, never a fresh read here — the panel spends nothing) fill the
        // other half with what the balance is actually made of.
        //
        // NOT read off `window`/`samples` — `combinedValueSamples()` builds
        // each merged point as `ValueSample(at:usd:)` with no third argument,
        // so `holdings` is always its struct default (nil) on every combined
        // sample; reading `window.last?.holdings` here always found an empty
        // dict and `.worth` could never fire, caught only by an
        // `-agentOpenProbe` reading `curve(6)` where a real corpus should
        // have said `worth(...)`. `holdingsDeltas` has the same shape for the
        // same reason: per-wallet symbol breakdowns only ever survive on the
        // RAW per-address samples, so each watched wallet's newest
        // holdings-bearing sample is read directly and summed by symbol.
        var mergedHoldings: [String: Double] = [:]
        for entry in WalletStore.shared.addresses {
            guard let holdings = WalletStore.shared.valueSamples(forAddress: entry.address)
                .last(where: { $0.holdings != nil })?.holdings else { continue }
            for (symbol, usd) in holdings { mergedHoldings[symbol, default: 0] += usd }
        }
        // `treemapWeight` is the same sqrt-scaled function the real Wallet
        // room's own treemap uses, so the two never disagree about
        // proportion the way §341 found them disagreeing about the number
        // itself.
        let cells: [AgentPanel.Cell] = mergedHoldings
            .sorted { $0.value > $1.value }
            .prefix(4)
            .map { AgentPanel.Cell(label: $0.key, weight: WalletIngest.treemapWeight($0.value)) }
        let figure: AgentPanel.Figure = cells.count >= 2
            ? .worth(curve: samples, cells: cells)
            : .curve(samples)
        return AgentPanel.Card(source: "Wallet", key: "wallet.curve",
                               title: String(localized: "Your balance"),
                               caption: windowLabel,
                               figure: figure,
                               affinity: ChipMemory.weight(for: "Wallet"),
                               reading: reading,
                               rising: flat ? nil : pct > 0)
    }

    /// Deleted in favour of `AgentPanel.compactUSD` (§341) — this one stopped
    /// at K, so a watched wallet holding $7.26M rendered "$7258k" beside a
    /// Wallet room saying "$7.0M".

    /// The wallet's flow band — the second Wallet card, under its own key.
    ///
    /// The window is the last 30 days rather than the feed's own selectable
    /// range: the panel has no range control (a tile is a glance, not a
    /// screen), and a fixed window keeps two opens comparable. Tapping lands
    /// in the Wallet room, where the real band carries its window chips.
    @MainActor
    private func walletFlow(corpus: [Thing]) -> AgentPanel.Card? {
        let since = Calendar.current.date(byAdding: .day, value: -30, to: .now)
        guard let band = WalletFlowSource.band(from: corpus, since: since) else { return nil }
        func lanes(_ lanes: [WalletFlow.Lane]) -> [AgentPanel.FlowLane] {
            lanes.map { AgentPanel.FlowLane(name: $0.name, usd: $0.usd, count: $0.count) }
        }
        return AgentPanel.Card(source: "Wallet", key: "wallet.flow",
                               title: String(localized: "Where money moved"),
                               caption: "",
                               figure: .flow(inLanes: lanes(band.inLanes),
                                             outLanes: lanes(band.outLanes)),
                               affinity: ChipMemory.weight(for: "Wallet"),
                               reading: nil, rising: nil)
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


    /// The cycling placeholder's pool for THIS open — the static invitations
    /// plus real-corpus examples that teach the widened vocabulary by naming
    /// things that exist and would answer (2026-07-22). A busy publisher
    /// earns "Synthesize my <feed> feed"; a watched token earns a
    /// per-token ask. Honest by construction: every added line names a real
    /// entity the answer path resolves.
    ///
    /// Takes the newest Tokens row's TITLE rather than the corpus (PERF
    /// 2026-08-11): the old form did its own `all.first(where:)`, which
    /// short-circuits for someone who watches tokens and walks every row for
    /// everyone who doesn't. `CorpusScan` already saw it on the one walk.
    private func computeInvitationPool(tokenTitle: String?,
                                       busy: (handle: String, count: Int)?) -> [String] {
        var pool = invitations
        if let busy {
            pool.append(String(localized: "Synthesize my \(shortPublisher(busy.handle)) feed"))
        }
        if let tokenTitle {
            // `TokensAsk.symbol(of:)` — the one parser of the "Name · $TICKER"
            // watch-title format (a bare space-split grabs the NAME's first
            // word, so "Wrapped Bitcoin · $WBTC" would read "Wrapped").
            pool.append(String(localized: "How's \(TokensAsk.symbol(of: tokenTitle)) doing?"))
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
                                // The capsule's words travel here (prd §167 item 1)
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
                            .dsHover()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                    .dsTooltip(String(localized: "Close"))
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
                // The greeting (docs/agent-brief.md ruling 4, built
                // 2026-07-20): the day and its moment, "Saturday morning."
                // ONE line since 2026-07-31 — the corpus stat that used to
                // follow it ("2,481 things, across 14 apps."), the milestone
                // ("1,000 things banked.") and the anniversary ("3 years
                // since your first thing.") are all gone, and for ONE reason
                // rather than three (user: "casberi is about insight and
                // management, over tons of stuff, seeing numbers is just
                // annoyance"): each was a FACT ABOUT THE PILE, a scoreboard
                // for having saved things, sitting on the surface whose whole
                // job is to say what the pile MEANS. The day's own sentence
                // (`dayCard`) is the room's lead now — insight, not inventory.
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
                // The pairing line — teaches the sheet's dual nature (ask a
                // question, or write a fact and send it out) and keeps the
                // greeting from reading as an orphan label.
                // Hidden once the board is up (§332): the pairing line teaches
                // an empty room what it is for, and a room already full of
                // answers has taught it. Kept for the empty case, which is
                // exactly the room that still needs the sentence.
                if !boardShowing {
                    Text("Ask, or write and send it out.")
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s2)
                        .settleIn(delay: 0.1)
                }
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
                                                            toolRounds: turn.toolRounds,
                                                            found: turn.found)
                                        }
                                    }
                                }
                                // Each turn wears the cap ITS doc earns
                                // (§274): a front-page doc gets the wide
                                // column its two-column layout needs, prose
                                // keeps the reading column — 1040pt lines
                                // are bad typography, and most answers are
                                // prose. `GenFrontPage.qualifies` is the
                                // same test the renderer's own column split
                                // consults, so the cap and the layout can't
                                // disagree.
                                .dsAdaptiveContentWidth(
                                    GenFrontPage.qualifies(turn.els) ? .wide : .reading)
                            }
                            if answering {
                                convoTurn(question: currentQuestion, animateIn: true) {
                                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                                        // The wait, drawn as the SHAPE of the
                                        // answer coming (2026-07-31). A
                                        // breathing berry stood here from
                                        // 2026-07-13 — and the brief takes
                                        // several real seconds to assemble
                                        // (measured: the on-device model read
                                        // alone is ~2.1s), which made this the
                                        // longest, most visible logo moment in
                                        // the app, inside the one screen the
                                        // user ruled it out of ("i like our
                                        // logo in the search / whisper bar,
                                        // but not inside the daily brief
                                        // itself"). Skeleton rows are the
                                        // app's own loading grammar
                                        // (`GenSkeletonRow`, what a streaming
                                        // module already shows before its line
                                        // lands), so the wait now says "an
                                        // answer is arriving, here's its
                                        // shape" instead of "a brand is
                                        // thinking" — which is also what the
                                        // build brief asked for all along: no
                                        // thinking indicators, agency renders
                                        // as results.
                                        //
                                        // THREE shapes, not one (2026-08-09,
                                        // user: "i'd rather see it look like
                                        // generative UI preparing to
                                        // populate") — a short lede-shaped
                                        // line, a tall hero-shaped block, then
                                        // note-shaped rows, echoing the real
                                        // brief's own layout (`DayLede` →
                                        // `MoneyHero`/`TagMap` → `DayNotes`)
                                        // rather than one undifferentiated
                                        // rectangle. Each pulses on its own
                                        // clock (`GenSkeletonPulse`), so the
                                        // group breathes like something is
                                        // actually assembling.
                                        //
                                        // Gated on an EMPTY stream, not on
                                        // `inFlight` alone (2026-08-14).
                                        // `inFlight` is only cleared at the
                                        // settle, while the brief paints its
                                        // corpus half seconds earlier — so
                                        // the skeleton went on standing ABOVE
                                        // a document that had already
                                        // arrived, pushing the real lede down
                                        // the screen behind four pulsing
                                        // placeholders for whatever was still
                                        // out. The skeleton is the shape of
                                        // an answer that hasn't come; the
                                        // moment any of it has, it has done
                                        // its job and the content speaks for
                                        // itself.
                                        if inFlight, answerStream.els.isEmpty {
                                            VStack(alignment: .leading, spacing: DS.Space.s2) {
                                                GenSkeletonBlock(minHeight: 26)
                                                GenSkeletonBlock(minHeight: 120)
                                                GenSkeletonRow()
                                                GenSkeletonRow()
                                            }
                                            .transition(.opacity)
                                            .accessibilityLabel("Working")
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
                                                            toolRounds: keyedToolRounds,
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
                                                            chrome.flash("Kept — I'll keep it fresh.",
                                                                         tone: .success)
                                                        } else {
                                                            chrome.flash("Kept — it'll stay fresh.",
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
                                                        // and the proactive "Asked often"
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
                                                                   ? "Asked often — keep it?"
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
                                                    keyedVerb(action: askWithKey) {
                                                        // The row's one consequential verb wears
                                                        // its weight (design pass 2026-07-21):
                                                        // it sends the question and its matched
                                                        // things off this iPhone and spends the
                                                        // person's own key. It read as the
                                                        // QUIETEST chip in the row while two
                                                        // routine saves shouted.
                                                        Chip(text: askProvider.map {
                                                                String(localized: "Try with \($0.agent)")
                                                             } ?? String(localized: "Try with your key"),
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
                                // Same per-turn cap as the settled turns
                                // above (§274). Live, this flips reading→wide
                                // the moment the root line's chapters parse —
                                // which is the doc's first line, so it lands
                                // before any module has content to move.
                                .dsAdaptiveContentWidth(
                                    GenFrontPage.qualifies(answerStream.els) ? .wide : .reading)
                            }
                            // THE PANEL DOCKS UNDER THE BRIEF (2026-08-14, prd
                            // §386d). The other half of the §336 reversal one
                            // file over: a bare bar tap now seeds the brief,
                            // so without this the panel would again be
                            // unreachable on a normal open — which is exactly
                            // the bug §336 fixed by refusing to seed.
                            //
                            // INSIDE this scroll rather than beside it: the
                            // rest-screen mount below carries its own
                            // `ScrollView`, and two sibling scrolls in one
                            // column is the layout that has no good answer.
                            // Here the brief and the figures are one surface —
                            // read the day, keep scrolling, land in the rooms.
                            //
                            // Gated on the SETTLED landing (`briefLanding`
                            // waits on `answerStream.completed`), so the
                            // figures never slide in under a document that is
                            // still painting.
                            if briefLanding, !composition.isEmpty {
                                AgentOpenBoard(composition: composition,
                                               onOpenRoom: { source in
                                                   ChipMemory.visited(source)
                                                   filter.source = source
                                                   filter.tag = "All"
                                                   close()
                                               })
                                    .padding(.top, DS.Space.s6)
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
                    // …except on Mac (2026-07-31), where the reason doesn't
                    // hold. Bottom-anchoring is a THUMB argument: it puts the
                    // answer's verbs within reach of the hand that just typed
                    // the question. A Mac has no thumb and a much taller
                    // surface — the same anchor there starts a fresh answer at
                    // the bottom edge of a 760pt+ window with a void above it,
                    // which is a document read from its own footer. A brief
                    // opens at its masthead instead; a long conversation
                    // scrolls exactly as before either way.
                    //
                    // …and the brief anchors to its top on EVERY platform
                    // (2026-08-03, user: "when it finishes, it leaves you at
                    // the bottom of the page. It should keep you at the top").
                    // The Mac comment above already had the argument; it was
                    // scoped to the wrong axis. Bottom-anchoring is a REPLY
                    // argument, not a Mac-vs-phone one — it puts a conversational
                    // answer's verbs under the thumb that just typed the
                    // question. The brief isn't a reply: it's a composed
                    // document with a masthead, an eyebrow naming its window,
                    // and a money hero as its crown, and a document read from
                    // its own footer is the same mistake on a phone as on a
                    // Mac. Every other answer keeps the thumb rule exactly.
                    .defaultScrollAnchor(DS.isMac || briefInView ? .top : .bottom)
                    // `.wide` is the CONTAINER's cap, not any turn's (§274):
                    // each turn caps itself just above — prose at the reading
                    // column, a front-page doc at the wide one — so this
                    // outer bound only has to be as wide as the widest turn
                    // can ever be. Leaving it at `.reading` would clamp the
                    // front page back to one column with extra steps.
                    .dsAdaptiveContentWidth(.wide)
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
                    // Follow the typewriter down as prose arrives — so a long
                    // answer keeps its newest line in view instead of writing
                    // itself off the bottom of the screen.
                    //
                    // NOT for the brief (2026-08-03). The anchor above is only
                    // half the fix: a top anchor sets where the document STARTS,
                    // and this handler then dragged the reader away from it on
                    // every tick, so the brief scrolled itself past its own
                    // masthead, hero and themes map and parked at the last thing
                    // it composed. Following the cursor is right for a reply
                    // being written to you and wrong for a document being
                    // assembled for you — the brief is read top-down, and the
                    // modules that arrive last are the least important ones
                    // (that's the compose order). It stays put now; scrolling
                    // down through it is the reader's own gesture.
                    // A keyboard over an answer must always have a way out
                    // (2026-08-11). The re-focus rule at settle decides whether
                    // one APPEARS — a typed ask keeps it, a tapped chip no
                    // longer raises it — but a keyboard raised any other way (a
                    // typed ask whose answer is longer than the space left, a
                    // tap on the field before the answer lands) would still sit
                    // over the document with nothing to dismiss it: this scroll
                    // view had no dismissal at all, and the composer's only
                    // tap-to-unfocus is on a different surface. Dragging the
                    // answer now clears it, which is the gesture a person
                    // already makes when they are trying to read past it.
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: answerStream.progress) { _, _ in
                        guard !briefInView else { return }
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

            // The rest screen settles at the BOTTOM (2026-07-31) — the same
            // ruling the conversation already keeps ("the answer rises out of
            // the composer it was asked from and its verbs land within
            // reach"). At rest there was no expanding element at all, so the
            // greeting, the chips and the bar floated as one block with the
            // whole lower screen empty beneath them, and the input bar — whose
            // own doc has said "pinned to the bottom" since it hugged a sheet
            // — was nowhere near it. Only at rest: once an answer exists the
            // conversation's own scroll is the expanding element.
            // The rest screen settles at the BOTTOM (2026-07-31) — but not
            // under the panel, which is a full surface of its own and needs no
            // pushing down. Left in, it opened a ~300pt hole between the
            // greeting and the first tile (seen on the sim, §336).
            if restChrome(keepBrief: false), !boardShowing, !panelLoading {
                Spacer(minLength: DS.Space.s4)
            }
            // The panel's own loading state (2026-08-09) — a bento-shaped
            // skeleton, hero tile plus a pair of smalls, echoing
            // `AgentPanelGrid`'s own `double`/`unit` sizing so the eventual
            // swap-in doesn't jump. Fills the exact gap `AgentOpenBoard`
            // leaves: `boardShowing` requires `!composition.isEmpty`, so
            // nothing below could ever show anything while the panel is
            // still computing.
            else if restChrome(keepBrief: false), panelLoading {
                VStack(spacing: DS.Space.s2) {
                    GenSkeletonTile(minHeight: 236)
                    HStack(spacing: DS.Space.s2) {
                        GenSkeletonTile(minHeight: 118)
                        GenSkeletonTile(minHeight: 118)
                    }
                }
                .padding(.horizontal, DS.Space.s4)
                .padding(.top, DS.Space.s3)
                .accessibilityLabel("Working")
            }
            // The room, answered (prd §332). Leads everything below it: the
            // noticing, the kept asks wearing their readings, the window
            // threaded, the fold. Shows only at rest and only when it has
            // something — an empty composition falls through to `dayCard` and
            // the chips, which is the rest screen exactly as it was.
            if boardShowing {
                // The panel SCROLLS (§337). The composer sizes to itself so
                // the sheet can hug it, which was right when the rest state
                // was a greeting and two chip rows — but with the cap lifted
                // past twenty figures the board is taller than the sheet, and
                // the overflow ran the greeting up under the status bar and
                // pushed the input bar off the bottom. Capped and scrollable:
                // the bar stays reachable and the greeting stays put.
                ScrollView {
                AgentOpenBoard(composition: composition,
                               onOpenRoom: { source in
                                   // Switch the feed to that room and lower the
                                   // agent — the panel is a window onto the
                                   // room, so the tap should land you in it.
                                   ChipMemory.visited(source)
                                   filter.source = source
                                   filter.tag = "All"
                                   close()
                               })
                }
                // FILLS the space it is given (§340). §339 capped this at a
                // whole number of card rows to stop a figure being sliced at
                // the fold — which fixed the slice and introduced a worse
                // problem: a fixed 502pt knows nothing about the device, so on
                // a real phone the panel stopped half way down and the input
                // bar floated in the middle of a black screen. The sheet
                // already knows how much room there is; taking all of it lets
                // the scroll end where the screen does, which is the only
                // place a scroll edge never looks broken.
                .frame(maxHeight: .infinity)
                .scrollIndicators(.hidden)
            }
            // The day, as the room's lead — the FALLBACK now (§332). It stood
            // in for a synthesis the open couldn't show; the board is that
            // synthesis, so the two never appear together.
            dayCard
            // The kept-ask pills LEFT the rest surface (user ruling
            // 2026-08-14, prd §386c: "remove climate links and hows my
            // watchlist" — the two pills the mockup showed). The FEATURE is
            // untouched: Keep still mints a standing ask, the store still
            // refreshes digests, the widget's kept-ask tile still reads it,
            // and a kept question still re-answers typed. What died is the
            // pills row at rest — the same chips-to-have-chips reading the
            // suggestion row got in the same session. `keptAskPills` stays
            // compiled but unmounted (dormant-not-deleted).
            // Chips sit right by the input — asks/commands you can fire from
            // where you compose (moved down 2026-07-12). The two bands are
            // mutually exclusive: askChips while the field is empty, takeChips
            // once there's typed text to carry out.
            askChips
            takeChips
            // The scope pickers (scoped-brief-spec.md) — "under the input",
            // the last band before it, always offered rather than competing
            // with `askChips`'/`takeChips`' own ranked/typed rows.
            categoryChipsRow
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
                // Flip BEFORE the heavy synchronous work, then yield once —
                // guarantees SwiftUI gets one real render pass with the
                // skeleton board visible before `computeSuggestions()`
                // occupies the main actor for ~700ms+ with no yield point of
                // its own (2026-08-09). Without the yield, the state flip and
                // the expensive call are back-to-back in the same run-loop
                // turn and nothing paints in between — the exact "black
                // screen, then everything at once" this exists to fix.
                // The skeleton is for a board that has never been built, not
                // for one being refreshed (PERF 2026-08-11). `composition` is
                // `@State` on a view that lives for the whole session, so on
                // every open after the first it still holds the last board —
                // and tearing that down to show a skeleton meant the panel's
                // full rebuild cost (measured 2.3s of a 3.0s open on a
                // 12,000-row corpus) was paid as BLANK time on every single
                // open, including the ones a second apart.
                //
                // Now: first open skeletons, every later open shows the board
                // instantly and swaps it when the fresh one lands — the
                // "kick async, repaint on arrival" shape `HomeInsightStore`
                // already uses. Honest, because a panel figure is a reading of
                // a room rather than a live claim, and the refresh always
                // lands: nothing here can leave a stale board up permanently.
                panelLoading = composition.isEmpty
                await Task.yield()
                await computeSuggestions()
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
                //
                // Reuses the corpus `computeSuggestions()` just fetched rather
                // than fetching the whole store again (PERF 2026-08-11) — this
                // was the THIRD full-corpus materialisation of a single
                // composer open. `.live` at the hand-off, since this array was
                // read before `buildPanel`'s awaits and a foreground heal can
                // delete in that window (corollary 6); `compose` re-filters at
                // its own door for the per-kind suspensions after that.
                // Reset then reveal so the ask chips stagger in on each open.
                // BEFORE the board, since 2026-08-12 — the chips are ready in
                // a fraction of the board's time and used to sit behind it.
                chipsAppeared = false
                try? await Task.sleep(for: .milliseconds(90))
                chipsAppeared = true
                // …and the board fills in behind them. `panelLoading` stays
                // true across this, so a FIRST open still shows the bento
                // skeleton in the board's slot rather than a hole; a later
                // open keeps the previous board up (see `panelLoading`'s
                // assignment above) and swaps it when this lands.
                let corpus = await composeBoard()
                panelLoading = false
                // The kept pills' signal dots, off the board's own fetch —
                // this used to be a THIRD full-corpus read, and before that it
                // sat on the chip path where its per-kind composers (wallet
                // and watchlist are network-backed) delayed the reveal.
                // `.live` at the hand-off: the array was read before
                // `buildPanel`'s awaits and a foreground heal can delete in
                // that window (corollary 6); `compose` re-filters at its own
                // door for the per-kind suspensions after that.
                Task { @MainActor [corpus] in
                    await KeptAskStore.shared.refreshDigests(things: corpus.live,
                                                             context: modelContext)
                }
                // Raised by the bar's magnifier (2026-07-30): the field takes
                // focus and nothing else happens — no brief, no ask. Cleared
                // on read so an ordinary later open doesn't inherit it.
                if chrome.focusDraftOnOpen {
                    chrome.focusDraftOnOpen = false
                    fieldFocused = true
                }
                // Raised by HOLDING the magnifier (prd §384): the mic is
                // already live when the surface lands. Same verb as the mic
                // button — `voice.start()` and stop-and-keep — just reached
                // in one gesture. Cleared on read for the same reason
                // `focusDraftOnOpen` is: no later open may inherit a live mic.
                if chrome.voiceOnOpen {
                    chrome.voiceOnOpen = false
                    Task { await voice.start() }
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
        // A surface that asked for a KEYED answer (a thing sheet's "Ask about
        // this") gets the same arc a tap on the verb gives: the free
        // on-device answer runs first and the keyed one fires itself the
        // moment it settles. Read and cleared together with the query, so a
        // later plain ask can never inherit it. Only honoured when a key is
        // actually configured — otherwise it would arm a follow-up that has
        // nothing to run on.
        if chrome.askWithKey {
            pendingKeyedFollowUp = AgentKey.isConfigured
            chrome.askWithKey = false
        }
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
        keyedToolRounds = 0
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
    /// What the draft WOULD find, before you commit to finding it — the match
    /// count and, more importantly, the filters the engine resolved out of
    /// your sentence (2026-08-13).
    ///
    /// The chips are the point and the count is the confirmation. Five hard
    /// filters can silently remove things (`Retriever.Scope`), and until now
    /// the only way to discover one had fired wrongly was to read a result
    /// that made no sense. Showing them BEFORE the tap is strictly better than
    /// after: the query is still in the field, so correcting is dropping a
    /// chip rather than re-deriving what you meant.
    ///
    /// Debounced and cancellable, and it writes NOTHING when superseded — a
    /// count from two keystrokes ago is worse than no count. Skipped entirely
    /// above `liveReadCeiling`; see that constant for the measurement.
    private func scheduleLiveRead(immediate: Bool = false) {
        liveReadTask?.cancel()
        let query = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        // A paste is a capture on its way to being kept, not a phrase to
        // search for — `takeChips` already withholds Find for one, so a live
        // read would be work nothing displays.
        guard !query.isEmpty, !pasted else {
            liveScopes = []
            liveCount = nil
            droppedScopes = []
            return
        }
        let dropped = droppedKinds
        liveReadTask = Task { @MainActor in
            if !immediate {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
            }
            // The COUNT first, which SQLite answers without materializing a
            // single row — so an oversized corpus costs one cheap query
            // rather than the fetch it is too big for.
            let total = (try? modelContext.fetchCount(FetchDescriptor<Thing>())) ?? 0
            guard total > 0, total <= Self.liveReadCeiling else {
                liveScopes = []
                liveCount = nil
                return
            }
            let things = ((try? modelContext.fetch(FetchDescriptor<Thing>(
                sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
            ))) ?? []).live
            guard !Task.isCancelled else { return }
            let outcome = Retriever.find(query, in: things, dropping: dropped)
            guard !Task.isCancelled else { return }
            liveScopes = outcome.scopes
            liveCount = outcome.hits.count
        }
    }

    private func runFind() {
        let query = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !inFlight else { return }
        DSHaptic.selection()
        let things = ((try? modelContext.fetch(FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        ))) ?? []).live
        guard let result = KeptAskComposers.search(query, things: things,
                                                   dropping: droppedKinds) else { return }

        withAnimation(DS.Motion.standard) {
            // A find lands mid-conversation like any other turn — the one
            // already live settles first, exactly as `commit()` does.
            if answering {
                turns.append(ConvoTurn(question: currentQuestion, els: answerStream.els,
                                       keyed: keyedCurrent, searchedWeb: keyedSearchedWeb,
                                       imagesSeen: keyedImagesSeen, toolRounds: keyedToolRounds,
                                       failed: answerFailed,
                                       found: foundCurrent))
            }
            answering = true
            currentQuestion = query
            keptCurrent = false
            currentStreamed = false
            keyedCurrent = false
            keyedSearchedWeb = false
            keyedImagesSeen = 0
            keyedToolRounds = 0
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
        // THE DRAFT SURVIVES A FIND, unlike a committed ask (2026-08-13).
        // An ask BECOMES the question, so clearing the field is right there.
        // A search is refined, not asked once: keeping the words means the
        // band — Find, the match count, and the scope chips — stays up, so
        // narrowing is dropping a chip or editing a word rather than
        // reconstructing the whole query from the transcript. This is the
        // whole of the refinement story; there is no second mechanism.
        answerStream.paint(result.doc)
        lastFindDoc = result.doc
        // The pass that just ran is the authority on what it filtered, so the
        // chips come from it rather than from the debounced live read — which
        // above `liveReadCeiling` never runs at all. This is the only way a
        // large-corpus search ever gets droppable chips.
        if let report = result.find {
            liveReadTask?.cancel()
            liveScopes = report.scopes
            liveCount = report.total
        }
        // Keepable as a standing search — the kind `KeptAskComposers` already
        // serves, so the Keep pill's whole path exists.
        keepableAskKind = "search:\(query)"
        // COUNTED ONCE PER QUERY, not once per tap. `AskMemory.asked` feeds the
        // mint threshold behind "You ask this a lot — keep it?", and now that
        // the draft survives a find, refining one search is several taps of the
        // same words — which would trip that prompt after a single session and
        // make an offer the person never earned (§95's counter, prd §83's rule).
        if query != lastFoundQuery {
            lastFoundQuery = query
            AskMemory.asked("search:\(query)")
        }
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
                                 imagesSeen: Int = 0, toolRounds: Int = 0,
                                 found: Bool = false) -> some View {
        var parts: [String] = []
        // Searching your own things leads, because it is the one part of this
        // list that describes work done on the corpus rather than away from
        // it — and it is the only visible sign that the agent went looking
        // instead of summarizing what it was handed.
        if toolRounds == 1 {
            parts.append(String(localized: "searched your things"))
        } else if toolRounds > 1 {
            parts.append(String(localized: "searched your things \(toolRounds) times"))
        }
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
                .dsGlyph(10, weight: .regular)
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

    /// The keyed verb, wearing a provider picker when there is a choice to
    /// make (2026-08-06). A plain tap is unchanged — it asks whichever agent
    /// the label names — and a long press offers every configured one.
    ///
    /// A `Menu` with a `primaryAction` rather than a separate chevron control:
    /// the row is already the busiest in the app, and a second control for
    /// something most people will never touch would cost more than it buys.
    /// With one key configured there is nothing to choose, so it stays exactly
    /// the Button it always was — a menu offering a single item is a dead
    /// control wearing an affordance.
    @ViewBuilder
    private func keyedVerb<Content: View>(action: @escaping () -> Void,
                                         @ViewBuilder label: () -> Content) -> some View {
        let configured = AgentKey.configured
        if configured.count > 1 {
            Menu {
                ForEach(configured) { provider in
                    Button {
                        askProvider = provider
                        action()
                    } label: {
                        // The active one is named as such rather than just
                        // ticked: "Claude" and "Claude (usual)" answer
                        // different questions, and the second is the one
                        // somebody scanning this menu is actually asking.
                        if provider == (askProvider ?? AgentKey.active) {
                            Label(String(localized: "\(provider.agent) (usual)"),
                                  systemImage: "checkmark")
                        } else {
                            Text(provider.agent)
                        }
                    }
                }
            } label: {
                label()
            } primaryAction: {
                action()
            }
        } else {
            Button(action: action) { label() }
        }
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
                                       imagesSeen: keyedImagesSeen, toolRounds: keyedToolRounds,
                                       failed: answerFailed,
                                       found: foundCurrent))
            }
            answering = true
            inFlight = true
            keyedCurrent = true
            keptCurrent = false
            currentStreamed = false
            keyedSearchedWeb = false   // observed per answer, never carried over
            keyedImagesSeen = 0
            keyedToolRounds = 0
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
            ? "Asking Bankr — this can take a minute."
            : "Asking with your key…"
        answerStream.paint(["root = Stack([w])", "w = Insight(\"\(waitLine)\")"])
        Task { @MainActor in
            // Prose arrives live over the network now (2026-07-21) — paint
            // each growing snapshot the same way the on-device path does
            // (commit()'s onProseDoc), with the same stale-ask guard.
            var streamed = false
            let outcome = await answerWithKey(q, askProvider) { partialDoc in
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
                keyedToolRounds = answer.toolRounds
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

    // MARK: - The day (the room's lead)

    /// The day's own sentence, as the rest screen's one card (2026-07-31,
    /// user: "how if at all would you make the agent more visually
    /// appealing").
    ///
    /// The agent was the only room in the app that led with nothing — every
    /// other one opens on a treemap, a grid, a balance or a face, while this
    /// one opened on four lines of shrinking gray text above two rows of gray
    /// pills. The brief's ranked lede already exists and is already published
    /// to the Lock Screen widget on every foreground; the room that composes
    /// it was the one surface not showing it. What you got instead was a chip
    /// reading "What's going on?" — a tap you had to spend to find out whether
    /// it was worth spending.
    ///
    /// **No mark on it** (user ruling 2026-07-31: "i like our logo in the
    /// search / whisper bar, but not inside the daily brief itself"). The
    /// tinted surface alone carries the agent's voice — the same grammar
    /// `DayNotes` and every `Insight` already use, where ink cards are your
    /// things and a tint wash is the agent talking.
    ///
    /// Tapping it asks the canonical question, exactly as the kept pill and
    /// the whisper capsule do — one composer, three doors (§132). Which is
    /// also why the `today` pill and the today CHIP drop out of the rows below
    /// while this shows: three controls opening one screen, stacked, is the
    /// duplication the brief itself just stopped doing.
    /// On screen when the room is at rest and the day has something to say.
    /// The board is on screen — at rest, with something composed.
    private var boardShowing: Bool {
        restChrome(keepBrief: false) && !composition.isEmpty
    }

    /// The day card stands in only where the board doesn't reach: an empty
    /// composition (a new install, a corpus with nothing in the window). Both
    /// at once would be the same day said twice, the duplication §248 already
    /// took out of the brief.
    private var dayCardShowing: Bool {
        restChrome(keepBrief: false) && !dayLede.isEmpty && composition.isEmpty
    }

    /// The kept kinds as actually docked — minus `today` while the card above
    /// is already that ask's door. Its pill and the card open the identical
    /// screen, and two controls for one screen, stacked, is the duplication
    /// §248 just took out of the brief itself. It comes straight back the
    /// moment the card isn't showing (an empty day, or mid-conversation), so
    /// nothing is ever unreachable.
    private var keptKinds: [String] {
        let order = KeptAskStore.shared.order
        // §334 removed the answer TILES, so there is nothing here to suppress
        // any more: the panel draws figures and the kept pills carry the
        // standing questions, which are different surfaces doing different
        // jobs. Only the `today` rule survives, and only while its card shows.
        return order.filter { $0 != "today" || !dayCardShowing }
    }

    @ViewBuilder
    private var dayCard: some View {
        if dayCardShowing {
            Button {
                DSHaptic.selection()
                AskMemory.tapped("today")
                // The card stands in for the kept pill while it shows, so it
                // owes the same stamp — otherwise reading the day here would
                // leave the pill's changed-dot lit for a day already read.
                // Harmless when `today` isn't kept: the key is per-kind.
                let store = KeptAskStore.shared
                store.markSeen("today", digest: store.currentDigests["today"] ?? "")
                draft = TodayBrief.title
                commit()
            } label: {
                HStack(alignment: .top, spacing: DS.Space.s3) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(DayBrief.title())
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textSecondary)
                        Text(dayLede)
                            .dsText(.heading17)
                            .foregroundStyle(DS.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: DS.Space.s2)
                    Image(systemName: "chevron.right")
                        .dsGlyph(12)
                        .foregroundStyle(DS.textTertiary)
                        .padding(.top, 4)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.s4)
                .background(DS.tintDim,
                            in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .dsHover()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s3)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens your day")
            .settleIn(delay: 0.06)
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
        // Hidden while the panel is up (§336): "one intro sentence and the rest
        // ONLY visualizations" — a row of text pills under the figures is
        // exactly the non-visualization the ruling removes. They return the
        // moment the panel has nothing to draw, which is the state they were
        // designed for.
        if restChrome(keepBrief: true), !boardShowing, !keptKinds.isEmpty {
            let sorted = keptKinds.sorted { a, b in
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
                        //
                        // A PIN leads each one since 2026-07-31. The two docked
                        // rows were the same shape, size, radius and fill, so
                        // the questions YOU kept and the ones the app is
                        // merely proposing read as one undifferentiated set —
                        // and the kept ones actually looked plainer, since
                        // only the suggestions carry a glyph. The pin is the
                        // verb that made them ("Keep" wears `pin.fill` in the
                        // answer's verb row), so the row now says whose
                        // questions these are in the vocabulary that already
                        // exists. An outline would have read better still and
                        // was drawn first — design law §8 forbids it ("no
                        // hairlines, zero exceptions"), so it's a glyph.
                        //
                        // No digest number (user ruling 2026-07-31: "i don't
                        // want to see a count of 'things'"). The digest is
                        // still computed and still decides the dot — a plain
                        // string compare, `KeptAskStore.changed` — it just
                        // isn't printed. The dot says something moved; the
                        // answer says what.
                        HStack(spacing: DS.Space.s2) {
                            if changed {
                                Circle().fill(DS.tint).frame(width: 7, height: 7)
                            } else {
                                Image(systemName: "pin.fill")
                                    .dsGlyph(12)
                                    .foregroundStyle(DS.tint)
                                    .accessibilityHidden(true)
                            }
                            Text(title)
                                .dsText(.callout15)
                                .foregroundStyle(changed ? DS.textPrimary : DS.textSecondary)
                        }
                        .opacity(neglected ? 0.55 : 1)
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.vertical, DS.Space.s3)
                        .background(changed ? AnyShapeStyle(DS.tintDim) : AnyShapeStyle(DS.gray100),
                                    in: RoundedRectangle(cornerRadius: DS.Radius.control,
                                                         style: .continuous))
                        .dsHover()
                    }
                    .buttonStyle(.plain)
                    // Keeping was ONE-WAY until now (2026-08-10, user: "how
                    // does someone remove it"). `KeptAskStore.remove` has
                    // existed since the store did, and its only callers were a
                    // DEBUG clear-all and the demo teardown — so a pill kept by
                    // mistake, or one whose question stopped mattering, stayed
                    // on the rest screen for the life of the install. That is
                    // the honesty rule's own shape inverted: not a dead
                    // control, but a live one with no undo.
                    //
                    // A context menu rather than a swipe or an × : these pills
                    // sit in a HORIZONTAL scroller, where a swipe is the scroll
                    // gesture (the 2026-07-08 arbitration lesson), and an ×
                    // on every pill would put a destructive control permanently
                    // beside a routine one. Long-press is also what the feed's
                    // own rows already use for their secondary verbs.
                    .contextMenu {
                        Button(role: .destructive) {
                            DSHaptic.selection()
                            KeptAskStore.shared.remove(kind)
                        } label: {
                            Label("Stop keeping this", systemImage: "pin.slash")
                        }
                    }
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
        if restChrome(keepBrief: true), !boardShowing, !dockedSuggestions.isEmpty {
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
                                    .dsGlyph(13)
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
                            // The trailing "· 12" is gone (user ruling
                            // 2026-07-31: "i don't want to see a count of
                            // 'things', that's an annoyance to the user").
                            // It was parity with the kept pills, and both
                            // sides lost it in the same pass — a chip is a
                            // question, and prefixing the answer with how many
                            // rows it will contain is the tally §213 already
                            // ruled isn't news. `AskOption.signal` still feeds
                            // the timely dot's own gate.
                        }
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.vertical, DS.Space.s3)
                        // Timely chips wear the same tintDim wash a changed
                        // kept pill does, so a live moment reads as filled
                        // against the steady gray of the evergreen chips.
                        .background(ask.timely ? AnyShapeStyle(DS.tintDim) : AnyShapeStyle(DS.gray100),
                                    in: RoundedRectangle(cornerRadius: DS.Radius.control,
                                                         style: .continuous))
                        .dsHover()
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

    /// Category chips (scoped-brief-spec.md) — "How's my Money stuff?",
    /// "How's my Work stuff?", "How's my Life stuff?", one per BRIEF SCOPE
    /// the corpus holds a connected app in. No "Everything" chip (user,
    /// 2026-08-08) — that brief is already the default and reachable via the
    /// whisper capsule or the kept "today" pill. Deliberately a SEPARATE,
    /// always-offered row from `askChips` above: those rank, decay and
    /// compete for one of 7 slots (tap-learning, §95), while these are scope
    /// pickers under the input a person reaches for repeatedly — decaying
    /// "Work" behind an unrelated chip because it went untapped for a while
    /// would be exactly the wrong lesson for a control whose job is to
    /// always be there.
    ///
    /// A LABELED two-row band (user ruling, 2026-08-08) — "What's going on"
    /// as a section label, every chip in a row beneath it, both always
    /// visible together. No expand step, no tap-to-reveal, no typing: three
    /// parent verbs now sit in the composer — Find and Send-to in the typed-
    /// draft band (`takeChips`, needs `hasDraft`), What's-going-on here in
    /// the REST band (needs `!hasDraft`) — because unlike Find/Send-to, which
    /// act on text you've already typed, asking what's going on needs no
    /// typed input at all; that's the point of a chip. The two bands are
    /// mutually exclusive by construction (`restChrome`'s `!hasDraft` vs.
    /// `takeChips`' `hasDraft`), so they never compete for the same line.
    ///
    /// Tapping a chip runs the query IMMEDIATELY (spec: "Do not prefill the
    /// input and wait for send") — the same `draft = …; commit()` mechanism
    /// `askChips` already uses, minus `AskMemory.tapped`: a fixed scope
    /// picker isn't part of the decaying-suggestion vocabulary that counter
    /// tracks.
    ///
    /// NOT gated on `!boardShowing` (user, 2026-08-08) — that exclusion
    /// predates this row and belonged to the instrument panel alone. For
    /// anyone with a real corpus the panel almost always has something to
    /// draw, so inheriting its gate made this row nearly invisible in
    /// practice: exactly the corpus where "what's going on with Work?" is
    /// worth asking. The panel is a visualization; this is a control —
    /// a control shouldn't disappear because a visualization is present.
    /// The scope chips as actually offered, plus the DAY itself whenever a
    /// scoped brief is what's on screen (2026-08-13, user: "presumably back to
    /// the day").
    ///
    /// This does not reopen the 2026-08-08 "no Everything chip" ruling, it
    /// honours its reasoning. That ruling rests on the unscoped brief being
    /// "the default you get by asking nothing in particular" — true at the
    /// agent's own root, and false the moment a scope brief is the thing you
    /// are standing in: from there the day is not the default, it is somewhere
    /// else, and the two doors that ruling named as sufficient are both gone
    /// (the whisper capsule lives above the lowered agent, and the kept "today"
    /// pill only exists for someone who has kept that ask). So the chip appears
    /// exactly where the row would otherwise be a one-way trip, and nowhere
    /// else — at the root the row is still the three tight choices it was.
    private var shownCategoryChips: [CategoryChip] {
        // The scoped-answer special case (prepending a "The day" chip) died
        // with the scope chips (prd §386): the one chip left IS the day, so
        // the prepend would mint a duplicate id. A typed scoped ask still
        // shows this row — the door back out to the whole overview.
        categoryChips
    }

    @ViewBuilder
    private var categoryChipsRow: some View {
        if restChrome(keepBrief: true), !shownCategoryChips.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                // The little "What's going on" header died with the scope
                // chips (prd §386) — the one chip left says those exact words
                // itself, and a label repeating the button under it is the
                // §213 restatement in miniature.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.s2) {
                        ForEach(shownCategoryChips) { chip in
                            Button {
                                DSHaptic.selection()
                                draft = chip.query
                                commit()
                            } label: {
                                Text(chip.title)
                                    .dsText(.callout15)
                                    .foregroundStyle(DS.textPrimary)
                                    .lineLimit(1)
                                    .padding(.horizontal, DS.Space.s4)
                                    .padding(.vertical, DS.Space.s3)
                                    .background(DS.gray100,
                                                in: RoundedRectangle(cornerRadius: DS.Radius.control,
                                                                     style: .continuous))
                                    .dsHover()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, DS.Space.s4)
                }
            }
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
                    .dsGlyph(16)
                    .foregroundStyle(DS.textTertiary)
                    .frame(width: 32, height: 36)
                    .dsTapTarget()
                    .dsHover()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Lower")
            .dsTooltip(String(localized: "Lower"))

            Button {
                if isRecording { commit() }   // the live mic is STOP + keep
                else { DSHaptic.tap(); Task { await voice.start() } }
            } label: {
                Image(systemName: isRecording ? "stop.circle.fill" : "mic")
                    .dsGlyph(17, weight: .regular)
                    .foregroundStyle(isRecording ? DS.destructive : DS.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(DS.fillFaint, in: Circle())
                    // After the background, so the drawn circle stays 36 and
                    // only the target grows.
                    .dsTapTarget(Circle())
                    .dsHover()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRecording ? "Stop and keep" : "Record a voice note")
            // The glyph swaps mid-recording and so must the name — the same
            // ternary as the label above, so the two can't drift.
            .dsTooltip(isRecording ? String(localized: "Stop and keep")
                                   : String(localized: "Record a voice note"))

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
                        .contentTransition(.opacity)
                        .animation(reduceMotion ? nil : DS.Motion.standard,
                                   value: placeholderIndex)
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
                    scheduleLiveRead()
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
                .dsHover()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(hasDraft && !isRecording ? "Ask" : "Send")
            .modifier(SendTooltip(glyphOnly: !(hasDraft && !isRecording)))
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
    /// The filters the engine resolved out of the draft, each one droppable —
    /// and each dropped one offered back (2026-08-13, see `Retriever.Scope`).
    ///
    /// Sits ABOVE the verb row on purpose: it describes what the Find beneath
    /// it will do, and reading it after tapping is the situation this replaces.
    /// Deliberately quieter than the verbs — tint on tintDim at 28pt against
    /// their 40pt — because these are a report you may act on, not the action.
    @ViewBuilder
    private var scopeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s2) {
                ForEach(liveScopes, id: \.kind) { scope in
                    Button {
                        DSHaptic.selection()
                        droppedScopes.append(scope)
                        scheduleLiveRead(immediate: true)
                    } label: {
                        scopeCapsule(scope.label, glyph: "xmark", on: true)
                    }
                    .buttonStyle(PressSpring())
                    .accessibilityLabel("Searching only \(scope.label). Tap to search everything.")
                }
                ForEach(droppedScopes, id: \.kind) { scope in
                    Button {
                        DSHaptic.selection()
                        droppedScopes.removeAll { $0.kind == scope.kind }
                        scheduleLiveRead(immediate: true)
                    } label: {
                        scopeCapsule(scope.label, glyph: "plus", on: false)
                    }
                    .buttonStyle(PressSpring())
                    .accessibilityLabel("Not searching only \(scope.label). Tap to narrow to it.")
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func scopeCapsule(_ label: String, glyph: String, on: Bool) -> some View {
        HStack(spacing: DS.Space.s1) {
            Text(label).dsText(.label12).fontWeight(.medium).lineLimit(1)
            Image(systemName: glyph).dsGlyph(9, weight: .semibold).accessibilityHidden(true)
        }
        .foregroundStyle(on ? DS.tint : DS.textTertiary)
        .padding(.horizontal, DS.Space.s2 + 2)
        .frame(height: 28)
        .background(on ? DS.tintDim : DS.gray100, in: Capsule(style: .continuous))
        .dsHover()
    }

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
                if offerFind && !liveScopes.isEmpty { scopeChips }
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
                                    .dsGlyph(14)
                                Text("Find")
                                    .dsText(.callout15).fontWeight(.semibold)
                                // The count, when it is known — the chip says
                                // whether the tap is worth taking, and with
                                // the scope chips beside it, WHY it isn't. It
                                // is simply absent otherwise (a big corpus, a
                                // pass still in flight): a stale or guessed
                                // number here would be worse than none.
                                if let liveCount {
                                    Text("\(liveCount)")
                                        .dsText(.callout15)
                                        .foregroundStyle(.white.opacity(0.7))
                                        .contentTransition(.numericText())
                                }
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, DS.Space.s3 + 2)
                            .frame(height: 40)
                            .background(DS.tint, in: Capsule(style: .continuous))
                            .dsHover()
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
                        keyedVerb(action: askDirectly) {
                            HStack(spacing: DS.Space.s2) {
                                Image(systemName: "key.fill")
                                    .accessibilityHidden(true)
                                    .dsGlyph(14, weight: .medium)
                                Text("Ask \(askProvider?.agent ?? AgentKey.active?.agent ?? "your key")")
                                    .dsText(.callout15).fontWeight(.semibold)
                            }
                            .foregroundStyle(DS.tint)
                            .padding(.horizontal, DS.Space.s3 + 2)
                            .frame(height: 40)
                            .background(DS.tintDim, in: Capsule(style: .continuous))
                            .dsHover()
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
                            ForEach(TakeTool.offered) { tool in
                                Button { runTake(tool) } label: {
                                    HStack(spacing: DS.Space.s2) {
                                        Image(systemName: tool.glyph)
                                            .accessibilityHidden(true)
                                            .dsGlyph(14, weight: .medium)
                                            .foregroundStyle(DS.tint)
                                        Text(tool.label)
                                            .dsText(.callout15).fontWeight(.semibold)
                                            .foregroundStyle(DS.textPrimary)
                                    }
                                    .padding(.horizontal, DS.Space.s3 + 2)
                                    .frame(height: 40)
                                    .background(DS.gray100, in: Capsule(style: .continuous))
                                    .dsHover()
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
            DSPasteboard.copy(text)
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
            //
            // EXCEPT brief → brief (2026-08-13, user: "if i click what's going
            // on in money, once i land, i should still be able to click what's
            // going on in life or work, and presumably back to the day.
            // basically all the chips should still be there"). Moving between
            // scopes is changing which brief you are LOOKING AT, not asking a
            // follow-up about the one you just read — and the difference is not
            // cosmetic, because `turns` is what ends the landing: the moment it
            // grows, `briefLanding` is false forever, every docked chip retires
            // (§181's own rule) and the scope row that put you here disappears
            // with them. So the agent opened onto the day, one tap on "Money"
            // took you to Money, and there was no second tap available — no
            // Work, no Life, no way back to the day, with nothing on screen
            // saying why. Replacing the landing keeps `turns` empty, so the
            // chips stay exactly as they were and the row stays live.
            //
            // Deliberately NOT `briefLanding` as the test: that waits on
            // `answerStream.completed`, so a second scope tapped while the
            // first is still painting would still stack a half-drawn brief into
            // the thread. `briefInView` is the same question without the settle
            // requirement, which is what this needs.
            let movingBetweenBriefs = briefInView && TodayBrief.matchesAny(draft)
            if answering, !movingBetweenBriefs {
                turns.append(ConvoTurn(question: currentQuestion, els: answerStream.els,
                                       keyed: keyedCurrent, searchedWeb: keyedSearchedWeb,
                                       imagesSeen: keyedImagesSeen, toolRounds: keyedToolRounds,
                                       failed: answerFailed,
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
                keyedToolRounds = 0
                answerFailed = false
                foundCurrent = false       // this is an ANSWER, not a find
                inFlight = true
            }
            keepableAskKind = nil   // recomputed at settle, for THIS question
            nextAsk = nil           // same — the prior answer's follow-up is stale
            askGeneration += 1
            let gen = askGeneration
            let q = draft
            // Was the person TYPING when this ask went out? Captured here,
            // before the field is cleared, because it decides whether the
            // keyboard comes back at settle (see the re-focus below).
            let askedByTyping = fieldFocused
            draft = ""              // clear the field so a follow-up is ready
            // No placeholder doc while in flight (fix 2026-07-20): the old
            // `Insight("Thinking…")` painted the answer card's full tintDim
            // chrome around a word — an empty-looking navy card. The
            // breathing berry beside the question header (rendered whenever
            // `inFlight`, just above the GenRender) is the whole loading
            // state now; the first real content to appear IS the answer.
            answerStream.paint([])
            Task { @MainActor in
                // One guaranteed render pass with the skeleton visible
                // before any of `answer(q:)`'s own synchronous work runs
                // (2026-08-09) — `answering`/`inFlight` just flipped above,
                // but without this yield the state change and the heavy
                // call sit in the same run-loop turn, so nothing paints in
                // between on a corpus large enough for that work to take
                // real time.
                await Task.yield()
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
                // A DOCUMENT snapshot rather than streamed prose — the Today
                // brief's corpus half, painted while its live reads are still
                // out. `proseStreaming` so the settle below doesn't
                // typewriter-reveal a document the person is already reading;
                // deliberately NOT `currentStreamed`, which would offer the
                // Keep-this-text button over an answer that keeps as an ask.
                //
                // `painted` is what the settle actually reads (2026-08-14).
                // The line above claimed `proseStreaming` did that job, and it
                // never could: `proseStreaming` is reset to false in the
                // settle's own `withAnimation` BEFORE the reveal branch runs,
                // and that branch does not consult it in any case. So every
                // brief took the `stream(finalDoc)` arm — which starts by
                // clearing `els` — and the document the person had been
                // reading for several seconds BLANKED and re-typewrote itself
                // from zero. That is the "it streams for 20-25s and looks
                // broken" report, and it is a reveal bug, not a compose one.
                //
                // Deliberately its own flag rather than reusing `streamed`:
                // that one means "a live prose synthesis painted its way in",
                // which also marks the answer keepable as text. A document
                // snapshot is neither, and one name for both reads as a bug.
                var painted = false
                let paintDocument: ([String]) -> Void = { partialDoc in
                    guard gen == askGeneration else { return }
                    painted = true
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
                    switch await answerWithKey(q, askProvider, paintPartial) {
                    case .success(let keyed):
                        keyedSearchedWeb = keyed.searchedWeb
                        keyedImagesSeen = keyed.imagesSeen
                        keyedToolRounds = keyed.toolRounds
                        finalDoc = keyed.doc
                    case .failure:
                        // The agent didn't answer, so the on-device model
                        // does — and the badge correctly reads "on this
                        // iPhone", because that's who actually answered.
                        keyedCurrent = false
                        finalDoc = await answer(q, paintPartial, paintDocument)
                    }
                } else {
                    finalDoc = await answer(q, paintPartial, paintDocument)
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
                // The settle haptic is keyed to honesty (delight, 2026-07-21):
                // real content earns the tick, the "nothing matches" fallback
                // earns nothing — celebrating a miss would violate the
                // honesty rule. (A large away haul used to earn a berry
                // shower here too — retired 2026-08-11, user ruling: the
                // rain is pull-to-refresh's payoff alone.)
                if !docHasFallback(finalDoc) {
                    DSHaptic.success()
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
                //
                // The berry SHOWER it used to deal is gone (2026-07-31): those
                // are the logo's own berries raining over the brief, and the
                // ruling is that the mark belongs to the bar and the whisper,
                // not to this screen. The toast still marks the moment — it
                // says the thing worth saying, which the rain never did.
                if TodayBrief.matches(q), !docHasFallback(finalDoc),
                   !UserDefaults.standard.bool(forKey: "today.firstBriefShown") {
                    UserDefaults.standard.set(true, forKey: "today.firstBriefShown")
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
                // `painted` joins them (2026-08-14): a document already on
                // screen is SWAPPED for its finished self, never re-revealed.
                if streamed || painted { answerStream.paint(finalDoc) }
                else if isInstantDoc(finalDoc) { answerStream.paint(finalDoc) }
                else { answerStream.stream(finalDoc) }
                // A TYPED ask readies the field for a follow-up. A TAPPED one
                // does not (2026-08-11, reported: "i open the agent and click
                // on what's going on w my money, the keyboard pops up and i
                // can't see the entire screen or dismiss keyboard").
                //
                // This generalizes the carve-out below it rather than adding a
                // second one. §181 already exempted the brief landing on the
                // grounds that it is "a screen to take in, not a prompt to
                // answer" — and that is equally true of every chip ask. The
                // money/work/life chips each return a document to read, and
                // popping a keyboard over one buries the answer the tap was
                // for, having asked the person to dismiss something they never
                // opened. Someone who was typing has the keyboard up already
                // and expects to keep it; someone who tapped never asked for
                // it, which is exactly the difference `askedByTyping` records.
                //
                // The escape hatch is separate and unconditional — the answer
                // scroll view dismisses the keyboard interactively — because a
                // keyboard with no way out is a trap however it got there, and
                // this rule can only ever decide whether one APPEARS.
                //
                // `q`, not `currentQuestion`: a newer ask could have overtaken,
                // but this closure already guarded `gen` above.
                if askedByTyping && !(turns.isEmpty && TodayBrief.matches(q)) {
                    fieldFocused = true
                }
                // Everything past here is the VERB ROW's bookkeeping, and it
                // runs after the answer is on screen (PERF 2026-08-13).
                //
                // It opens with an unbounded, fully-hydrated fetch of the whole
                // store on the main actor, and it used to sit ABOVE the paint —
                // so on a corpus carrying a bulk import the answer was finished
                // and simply not yet drawn while this ran. That is the second
                // half of a chip tap's felt latency; the first half was
                // `answerDocument`'s own `fullCorpus()`, now scoped per kind
                // (`RootShell.keptCorpus`). Neither was visible to the nightly
                // perf pass, which times launch, RSS and answer LATENCY — and
                // this work lands after the answer is computed, so it never
                // showed up in that number.
                //
                // What it feeds is the Keep pill and the follow-up chip BELOW
                // the answer, neither of which is what the tap was for. They
                // arrive a beat later; both were cleared at commit, so the gap
                // shows nothing rather than something stale.
                await Task.yield()
                // Re-guarded, and this is load-bearing rather than caution: the
                // yield is a real suspension, so a newer ask can begin inside
                // it — and without this, that newer answer would wear THIS
                // question's Keep pill and follow-up chip.
                guard gen == askGeneration else { return }
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
            }
        }
    }
}

/// The send button's pointer tooltip, present only in its GLYPH-ONLY states —
/// empty field, or a live recording. With a draft the capsule already wears
/// the word "Ask", and a tooltip repeating a word that's on screen is noise.
/// A modifier rather than a ternary because `dsTooltip` takes a String: the
/// alternative is naming an empty one, which on Mac is a blank tooltip.
private struct SendTooltip: ViewModifier {
    let glyphOnly: Bool
    func body(content: Content) -> some View {
        if glyphOnly {
            content.dsTooltip(String(localized: "Send"))
        } else {
            content
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

/// A pill chip — the composer's and shell's smallest interactive unit.
struct Chip: View {
    enum Style { case tint, neutral }
    let text: String
    var style: Style = .neutral
    var glyph: String? = nil

    var body: some View {
        HStack(spacing: DS.Space.s1) {
            if let glyph {
                Image(systemName: glyph).dsGlyph(12, weight: .regular)
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
        // Folded in HERE rather than at each call site, the same reasoning
        // `dsListCardRow` states: every Chip but `ParseCard`'s status badge is
        // the label of a Button, so a screen that reaches for one gets Mac
        // hover with no separate decision. No tooltip — a chip is a word.
        .dsHover()
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
