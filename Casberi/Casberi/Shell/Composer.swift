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
    var onKeepAnswer: (String) -> Void = { _ in }
    /// The shell's glass namespace — pill and bubble share one glass identity,
    /// so open/close is a morph of the same substance, not a swap.
    var glassNamespace: Namespace.ID? = nil

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
        "Ask anything. Organize everything.",
        "What did I save this week?",
        "Find that thing I pasted.",
        "Recap my month.",
        "Tag everything from an app.",
    ]
    /// Flips true just after the bubble opens so the ask chips stagger in
    /// rather than snapping (delight, 2026-07-12).
    @State private var chipsAppeared = false
    /// The tool tile currently launching — pops it up and fades it as its app
    /// takes over, so the hand-off reads physical (delight, 2026-07-12).
    @State private var launchingTool: String?

    @FocusState private var fieldFocused: Bool
    @State private var answerStream = GenStream()
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

    /// The keepable text of a synthesis answer — a synthesis is one Insight
    /// carrying the prose (RootShell's proseDoc). Only that shape is worth
    /// keeping: a lookup answer IS the things, which already live in the feed;
    /// a short status line or "Thinking…" isn't a recap. nil otherwise.
    private func keepableText(_ els: GenEls) -> String? {
        guard let insight = els.values.first(where: { $0.comp == "Insight" }) else { return nil }
        let text = insight.str(0)
        return text.count >= 40 ? text : nil
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
    /// asks the corpus can actually answer right now).
    @State private var suggestions: [String] = []
    /// The tag list, snapshotted once per open — tagCandidates() walks the
    /// whole store, and computed-per-keystroke it made typing pay a corpus
    /// fetch per character (review 2026-07-08).
    @State private var tagPool: [String] = []

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

    /// A tool tile's press: it gives under the finger and springs back —
    /// the app-icon feel (delight, 2026-07-12).
    private struct TilePress: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.90 : 1)
                .animation(.spring(response: 0.28, dampingFraction: 0.6),
                           value: configuration.isPressed)
        }
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
        tagPool = tagCandidates()   // one corpus walk per open, not per keystroke
        var out: [String] = []
        // One plain fetch, filtered in memory — a #Predicate can't compare
        // the Codable ThingKind enum (it throws at runtime, and try? made
        // the miss silent).
        let all = (try? modelContext.fetch(FetchDescriptor<Thing>())) ?? []
        // Context-aware lead (2026-07-12): if you opened the composer while
        // looking at one source's feed, its recap leads the chips — the
        // composer meets you where you are. Only when that source actually has
        // things to synthesize (honesty rule: a chip must answer).
        if let src = contextSource(), all.contains(where: { $0.source == src }) {
            out.append("What's new in \(src)?")
        }
        let dayStart = Calendar.current.startOfDay(for: .now)
        // The feeds' pulse (2026-07-11): "What's going on?" synthesizes the
        // recent window across every source. Gated on the SAME computation
        // that will answer it — the chip can't drift from the ask it
        // teaches — and it needs two things to say anything. When it shows,
        // "What landed today?" sits out (near-duplicate recency asks would
        // crowd out the chips that teach counting and pinning).
        let pulseChip = StatusAsk.pulse("what's going on", things: all)
            .map { $0.pool.count >= 2 } ?? false
        if pulseChip {
            out.append("What's going on?")
        } else if all.contains(where: { $0.capturedAt >= dayStart }) {
            out.append("What landed today?")
        }
        // The chips teach what the composer can DO (2026-07-10) — counting
        // stayed a secret power until the chips showed it. Only asks the corpus
        // can honestly answer right now. (Pinning left the composer 2026-07-12:
        // it's per-APP now, placed from the app's own screen, not a phrase.)
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? dayStart
        if all.contains(where: { $0.kind == .link && $0.capturedAt >= weekStart }) {
            out.append("How many links this week?")
        }
        if let top = tagPool.first {
            out.append("Show \(top)")
        }
        if !all.isEmpty {
            out.append("What's this week?")
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
        suggestions = Array(out.prefix(organizeHint == nil ? 3 : 2))
    }

    /// One conversation turn — the muted question, then its answer.
    @ViewBuilder
    private func convoTurn<Content: View>(question: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            if !question.isEmpty {
                Text(question)
                    .dsText(.subhead13).fontWeight(.semibold)
                    .foregroundStyle(DS.textSecondary)
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
        // At rest the composer is the FAB on the tab bar's axis (amendment:
        // the full-width rest pill died — simpler shell, more reading room).
        // Engaged, it takes the surface: same glass, morphed.
        Group {
            if isOpen { openBubble }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Opens UNFOCUSED (2026-07-12): the tray leads with the field's
        // invitation, the ask chips, and the tool grid all visible — tapping
        // the field is what raises the keyboard to ask. Auto-focusing hid the
        // tools behind the keyboard, biasing the surface toward "ask" when it's
        // now "ask OR jump to a tool".
    }

    // MARK: - Open

    private var openBubble: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The greeting (embedded sheet only) — frames the whole surface as
            // one question the tools and the field both answer, and gives the
            // sheet its warmth (design pass 2026-07-12, "B: greeting-led").
            // Hidden once a conversation is underway: the answer is the header.
            if embedded, turns.isEmpty, !answering, proposal == nil {
                Text("What now?")
                    .dsText(.heading22)
                    .foregroundStyle(DS.textPrimary)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s2)
                    .settleIn()
                // The pairing line — teaches the sheet's dual nature (jump OR
                // ask) and keeps the greeting from reading as an orphan label.
                Text("Jump to a tool, or ask below.")
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, 2)
                    .settleIn(delay: 0.06)
            }
            // The content sizes to ITSELF (no filling scroll) so the sheet can
            // hug it — no stranded empty space. The answer conversation carries
            // its own capped scroll, so nothing overflows. (2026-07-12)
              VStack(alignment: .leading, spacing: 0) {

            // Ask chips moved DOWN to sit by the input (2026-07-12) — rendered
            // as `askChips` just above the bottom bar, near where you compose.

            // The finite tool launcher — a fixed grid of jumps to the person's
            // OWN tools, shown while the field is empty (the "ask OR jump"
            // surface). Hidden the moment you start composing.
            if isOpen && !hasDraft && !answering && !isRecording, proposal == nil {
                toolGrid
            }

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
                                        if turn.keyed { keyedBadge }
                                    }
                                }
                            }
                            if answering {
                                convoTurn(question: currentQuestion) {
                                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                                        GenRender(id: "root", els: answerStream.els)
                                            .environment(\.genProseStreaming, proseStreaming)
                                        // A keyed answer says so, always — the
                                        // badge is the honesty rule applied to
                                        // where the answer was made.
                                        if keyedCurrent, !inFlight { keyedBadge }
                                        if !proseStreaming, !inFlight {
                                            HStack(spacing: DS.Space.s2) {
                                                // Keep a settled synthesis (2026-07-12):
                                                // lands the recap as a note so it isn't
                                                // ephemeral. The consent tap IS the keep,
                                                // like the parse card's save-on-send.
                                                if !keptCurrent, currentStreamed,
                                                   let text = keepableText(answerStream.els) {
                                                    Button {
                                                        DSHaptic.tap()
                                                        keptCurrent = true
                                                        onKeepAnswer(text)
                                                    } label: {
                                                        Chip(text: "Keep this", style: .tint,
                                                             glyph: "tray.and.arrow.down")
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                                // The BYO-key retry (prd §67) — a verb,
                                                // never a fallback: the question and its
                                                // matched things leave this iPhone only
                                                // on this tap, straight to Anthropic.
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
                                        }
                                    }
                                }
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 300)
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

            // Chips sit right by the input — asks/commands you can fire from
            // where you compose (moved down 2026-07-12).
            askChips
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
        .task(id: isOpen) {
            if isOpen {
                computeSuggestions()
                // Reset then reveal so the ask chips stagger in on each open.
                chipsAppeared = false
                try? await Task.sleep(for: .milliseconds(90))
                chipsAppeared = true
            }
            await consumeAskRequest()
            await autoSendIfProbed()
        }
        // The empty invitation cycles while the field is genuinely idle.
        .task(id: cyclingActive) {
            guard cyclingActive else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                if Task.isCancelled { break }
                placeholderIndex = (placeholderIndex + 1) % invitations.count
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
    /// Anthropic key. The on-device answer settles into the thread first, so
    /// the two sit side by side — the tap is the consent, the badge is the
    /// receipt, and a failure is worded plainly (never faked).
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
        }
        askGeneration += 1
        let gen = askGeneration
        answerStream.paint(["root = Stack([w])", "w = Insight(\"Asking with your key…\")"])
        Task { @MainActor in
            let doc = await answerWithKey(q)
            // Closed, or a newer ask overtook this one — retire silently.
            guard isOpen, gen == askGeneration else { return }
            inFlight = false
            keyAvailable = ClaudeKey.isConfigured
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

    // MARK: - Ask chips + input bar (chat grammar: by the bottom)

    /// The ask chips — asks the corpus can answer now, plus the organize invite
    /// — shown while the field is empty, right above the input.
    @ViewBuilder
    private var askChips: some View {
        if isOpen && !hasDraft && !answering && !isRecording,
           proposal == nil, !suggestions.isEmpty || organizeHint != nil {
            let hintLead = organizeHint != nil ? 1 : 0
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s2) {
                    if let hint = organizeHint {
                        Button {
                            DSHaptic.selection()
                            fillDraft("tag \(hint.source.lowercased()) as ")
                            fieldFocused = true
                        } label: {
                            Chip(text: "Tag your \(hint.count) \(hint.source) things",
                                 style: .tint, glyph: "tag")
                        }
                        .buttonStyle(.plain)
                        .modifier(ChipEntrance(index: 0, shown: chipsAppeared, reduceMotion: reduceMotion))
                    }
                    // Two suggestions, no more — the chips whisper "you could
                    // ask" beside the field; a wall of them fought the tiles
                    // for attention (v2 pass, 2026-07-12).
                    ForEach(Array(suggestions.prefix(2).enumerated()), id: \.offset) { i, ask in
                        Button {
                            DSHaptic.selection()
                            draft = ask
                            commit()
                        } label: {
                            Chip(text: ask, style: .neutral, glyph: "sparkle")
                        }
                        .buttonStyle(.plain)
                        .modifier(ChipEntrance(index: i + hintLead, shown: chipsAppeared, reduceMotion: reduceMotion))
                    }
                }
                .padding(.horizontal, DS.Space.s4)
            }
            // A soft trailing fade so a clipped chip reads as "more to scroll",
            // not cut off mid-word.
            .mask(
                LinearGradient(stops: [.init(color: .black, location: 0),
                                       .init(color: .black, location: 0.88),
                                       .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            )
            // Clear air between the tool card and the chips — the chips are a
            // separate band (ask), not stuck to the tools (jump).
            .padding(.top, DS.Space.s4)
            .padding(.bottom, DS.Space.s2)
        }
    }

    // MARK: - Input bar (chat grammar: pinned to the bottom)

    /// The mic, the ask field, and a send button that appears once there's
    /// something to send — a soft rounded bar so the surface feels inviting.
    private var inputBar: some View {
        HStack(spacing: DS.Space.s2) {
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
                .placeholder(when: !hasDraft) {
                    Text("Ask, or say what to do")
                        .dsText(.body17).foregroundStyle(DS.textTertiary)
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
                }
                .lineLimit(1...5)

            // The send dot is ALWAYS present — grey and waiting when the field
            // is empty (tap = focus the field), springing to tint the moment
            // there's something to send. A visible affordance beats a control
            // that pops out of nowhere (v2 pass, 2026-07-12).
            Button {
                if hasDraft || isRecording { commit() } else { fieldFocused = true }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(hasDraft || isRecording ? .white : DS.textTertiary)
                    .frame(width: 32, height: 32)
                    .background(hasDraft || isRecording ? AnyShapeStyle(DS.tint)
                                                        : AnyShapeStyle(DS.fillFaint),
                                in: Circle())
                    .symbolEffect(.bounce, value: hasDraft || isRecording)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Send")
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

    // MARK: - Tool launcher (jumps to the person's own tools)

    /// The tiles to show — a `probe` tile (ChatGPT/Claude) only appears when its
    /// app is installed, so a tile never opens a website instead of the app.
    private var visibleTools: [QuickTool] {
        #if DEBUG
        // `-forceTools YES` shows probe-gated tiles in the simulator, where
        // third-party apps can't be installed (screenshot/video staging only).
        if UserDefaults.standard.bool(forKey: "forceTools") { return QuickTool.all }
        #endif
        return QuickTool.all.filter { !$0.probe || UIApplication.shared.canOpenURL($0.url) }
    }

    private var toolGrid: some View {
        // No label — the tiles are self-evident (the "Your tools" caption was
        // an orphan). Columns adapt to the count so no row is ever ragged:
        // 6 tools (no AI apps) → 3×2, 8 (both installed) → 4×2; only the rare
        // 7 leaves a short second row. The grid sits on an ELEVATED card —
        // depth by tone and shadow, never by line (the ladder, 2026-07-12) —
        // and the tiles rise in with the ask chips' stagger.
        let tools = visibleTools
        let cols = tools.count <= 6 ? 3 : 4
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2), count: cols),
            spacing: DS.Space.s4
        ) {
            ForEach(Array(tools.enumerated()), id: \.element.id) { i, tool in
                Button { runTool(tool) } label: {
                    VStack(spacing: DS.Space.s2) {
                        toolIcon(tool)
                            // The launch pop — the tapped tile springs up and
                            // fades as its app takes over the screen.
                            .scaleEffect(launchingTool == tool.id ? 1.22 : 1)
                            .opacity(launchingTool == tool.id ? 0.55 : 1)
                        Text(LocalizedStringKey(tool.label))
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(TilePress())
                .modifier(ChipEntrance(index: i, shown: chipsAppeared, reduceMotion: reduceMotion))
            }
        }
        .padding(.vertical, DS.Space.s4)
        .padding(.horizontal, DS.Space.s2)
        .background(DS.background100,
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .shadow(color: DS.cardShadow, radius: 18, x: 0, y: 6)
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s4)
    }

    /// A tool's face: the real brand mark when one is bundled (ChatGPT, Claude
    /// — they coin-flip in, the bridge icons' own delight), else the app-icon
    /// treatment — a solid brand-color squircle, white glyph, a whisper of top
    /// sheen. The washy tint fills died with the v2 pass (2026-07-12): solid
    /// reads as an app, tint read as a stain, worst in dark.
    @ViewBuilder
    private func toolIcon(_ tool: QuickTool) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.appIcon(50), style: .continuous)
        if let ui = UIImage(named: "brand-\(tool.id)") {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(width: 50, height: 50)
                .clipShape(shape)
                .coinFlip(trigger: chipsAppeared)
        } else {
            shape
                .fill(tool.tint)
                .overlay(
                    shape.fill(LinearGradient(colors: [.white.opacity(0.16), .clear],
                                              startPoint: .top, endPoint: .center))
                )
                .overlay(
                    Image(systemName: tool.symbol)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.white)
                )
                .frame(width: 50, height: 50)
        }
    }

    /// A tool tile jumps out to that app and closes the composer — nothing
    /// lands in Casberi (the ruling: people create in their own tools).
    private func runTool(_ tool: QuickTool) {
        // The hand-off is physical: the tile POPS like a home-screen icon
        // opening — a heavier tap and a spring-up mask the app switch, so
        // jumping to your tool reads as a deliberate throw, not a silent
        // close (delight, 2026-07-12). Reduce Motion takes the instant path.
        guard !reduceMotion else { DSHaptic.tap(); openURL(tool.url); close(); return }
        DSHaptic.tap()
        withAnimation(.spring(response: 0.24, dampingFraction: 0.5)) {
            launchingTool = tool.id
        }
        Task {
            try? await Task.sleep(for: .milliseconds(170))
            openURL(tool.url)
            close()
        }
    }

    private func applyProposal(_ proposal: OrganizeProposal) {
        guard proposal.canApply else { return }
        let (summary, undo) = Organize.apply(proposal, context: modelContext)
        DSHaptic.success()
        chrome.flash(summary, action: .init(label: "Undo", run: undo))
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
            inFlight = true
            askGeneration += 1
            let gen = askGeneration
            let q = draft
            draft = ""              // clear the field so a follow-up is ready
            answerStream.paint(OnDeviceModel.isAvailable
                               ? ["root = Stack([w])", "w = Insight(\"Thinking…\")"]
                               : [])
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
                keyAvailable = ClaudeKey.isConfigured   // one read per settle
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

/// The composer at rest — a glass circle on the tab bar's axis. Tap and the
/// same glass morphs into the bubble (shared glassEffectID). The ask glyph,
/// no menu: one tap, one surface.
struct ComposerFAB: View {
    var glassNamespace: Namespace.ID?
    var action: () -> Void
    @Environment(ShellChrome.self) private var chrome
    /// The tap bounces the plus (Telegram grammar, same as the tab icons).
    @State private var bounce = 0

    var body: some View {
        let side: CGFloat = chrome.minimized ? 48 : 56
        Button {
            bounce += 1
            action()
        } label: {
            // Plus, not a magnifier: the button's job is the capture habit
            // (Journal's glass + is the system precedent). The bubble teaches
            // ask once open.
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .medium))
                .symbolEffect(.bounce, value: bounce)
                .foregroundStyle(DS.textPrimary)
                .frame(width: side, height: side)
                .contentShape(Circle())
        }
        .buttonStyle(FABPress())
        .dsGlass(cornerRadius: DS.Radius.pill, glassID: "composer", in: glassNamespace)
        .accessibilityLabel("Ask or save")
    }
}

/// The FAB's press (2026-07-10): `.plain` had NO down-state — the button was
/// dead under the finger until release. Now it squishes and the plus tilts
/// 45° toward the × it's about to become as the glass morphs into the
/// composer; dragging off springs it back untouched.
private struct FABPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .rotationEffect(.degrees(configuration.isPressed ? 45 : 0))
            .animation(.spring(duration: 0.3, bounce: 0.55),
                       value: configuration.isPressed)
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
