import SwiftUI
import SwiftData

/// The live half of an agent's room (prd §840) — the Chat tile's surface.
///
/// **It renders from the CORPUS, not from answer state of its own.** A keyed
/// answer lands as a `Thing` (`AgentConversationLanding`), so this view asks a
/// question, the ask path lands the exchange, and the row it is already
/// drawing updates. That is why there is no answer binding here, no partial
/// text, no result to thread: the conversation on screen is the conversation
/// in the store, which is also the one the All tile lists and the one the
/// thing sheet opens. One record, three readers.
///
/// **The newest conversation is the one you are having.** `capturedAt` moves
/// to the latest exchange on every upsert, so the newest chat row for this
/// source IS the live one and needs no id passed in from the shell. Starting a
/// fresh conversation is a deliberate act (`newConversation`) rather than a
/// timeout, because an agent you came back to an hour later is usually one you
/// are still talking to — and the wrong guess in that direction silently drops
/// the context the next answer needed.
///
/// **It does not wait.** The ask goes to `ShellChrome.roomAsk`, which
/// `RootShell` serves, because `keyedAnswerDocument` is private to the shell
/// and is the one funnel every ask goes through — a screen calling the model
/// directly would be a second one. `roomAskPending` is the only state that
/// comes back, and it says the question is in flight and nothing else.
struct AgentChatView: View {
    /// The room's source — "Bankr", "Claude", the `Thing.source` these land
    /// under.
    let source: String
    /// Who answers. The room's own agent, never `AgentKey.active`: standing in
    /// Bankr's room and being answered by whichever key happens to be active
    /// is the §83 failure this whole section exists to end.
    let provider: AgentProvider

    @Environment(ShellChrome.self) private var chrome
    @Environment(\.modelContext) private var modelContext
    @State private var draft = ""
    @FocusState private var writing: Bool

    /// The live conversation, newest first, bounded to one. A `@Query` rather
    /// than a fetch so the view redraws when the ask path upserts it — which
    /// is the entire mechanism by which an answer appears.
    @Query private var live: [Thing]

    init(source: String, provider: AgentProvider) {
        self.source = source
        self.provider = provider
        // FENCED TO CONVERSATIONS HAD HERE, and the fence is the whole
        // correctness of this view. An IMPORTED conversation carries the same
        // `source` — a Claude export lands under "Claude" exactly as a keyed
        // Claude chat does (§839, one agent one room, deliberately) — so
        // "newest row for this source" selects an export's conversation until
        // the first live exchange outdates it, and the Chat tile would open
        // showing last Tuesday's imported chat as the one you are having.
        // `AgentConversationLanding` stamps `agentchat:`; the importers stamp
        // `chatgpt:` / `claude:` / `claudecode:` / `gemini:`.
        let mine = AgentConversationLanding.refPrefix
        var d = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == source
                && ($0.sourceRef?.starts(with: mine) ?? false) },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        d.fetchLimit = 1
        _live = Query(d)
    }

    /// The turns on screen, parsed ONCE per change of the conversation.
    ///
    /// **Held rather than computed, and that is a perf fix not a style.** This
    /// view owns `draft`, so every character typed re-evaluates its body — and
    /// a computed `turns` would re-parse the whole stored transcript, up to
    /// `ChatTranscript.cap` (8,000 characters), on each keystroke. That is the
    /// build-525 class exactly: real work in a body, invisible until somebody
    /// types a long question into a long conversation.
    ///
    /// The parse itself is `AgentSheet.turns` — the thing sheet's own reader,
    /// never a second one (§418), so a conversation reads identically wherever
    /// it is opened.
    @State private var turns: [AgentSheet.Turn] = []

    /// What makes the parse stale, and nothing else. `messageCount` moves on
    /// every upsert (§839), so it catches an answer landing; the id catches
    /// the conversation being replaced by a newer one. Deliberately NOT the
    /// transcript itself — comparing 8,000 characters each body pass is the
    /// cost this exists to avoid, smaller but the same shape.
    private var parseKey: String {
        guard let thing = live.first, thing.isLive else { return "" }
        return "\(thing.id)-\(thing.messageCount ?? 0)"
    }

    private func reparse() {
        guard let thing = live.first, thing.isLive,
              let body = thing.enrichedText,
              let assistant = AgentSheet.assistant(for: source)
        else { turns = []; return }
        turns = AgentSheet.turns(body, assistant: assistant)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if turns.isEmpty && !chrome.roomAskPending {
                // The list skeleton, not a room figure: what fills this is
                // turns, and turns are rows (§769 — draw what would fill it).
                // `words` is VoiceOver's alone since §799, so the one clause
                // is written for a listener, and the headline is what is seen.
                DSEmptyState(headline: Text("Nothing asked yet"),
                             words: Text("Your conversation with \(source) appears here"),
                             scale: .list(rows: 3))
            } else {
                AgentTurnsView(turns: turns, source: source)
                if chrome.roomAskPending {
                    HStack(spacing: DS.Space.s2) {
                        DSSpinner()
                        Text("Asking \(source)…")
                            .dsText(.subhead12)
                            .foregroundStyle(DS.textSecondary)
                    }
                }
            }
            entry
        }
        // `onAppear` for the conversation already there when the tile is
        // picked; `onChange` for an answer landing while it is open. Both, and
        // not `.task(id:)`: the parse is synchronous and main-actor work that
        // must be on screen in the same pass, not a frame later.
        .onAppear(perform: reparse)
        .onChange(of: parseKey) { _, _ in reparse() }
    }

    /// The one entry well on the page (`dsWell` holds an entry field, §782).
    /// The send verb is a row's, not a floating control, because nothing in
    /// this app puts a control at the top or floats one over content that is
    /// not the composer itself (§752).
    private var entry: some View {
        HStack(alignment: .bottom, spacing: DS.Space.s2) {
            TextField(String(localized: "Ask \(source)"), text: $draft, axis: .vertical)
                .dsText(.body17)
                .foregroundStyle(DS.textPrimary)
                .tint(DS.tint)
                .lineLimit(1...6)
                .textInputAutocapitalization(.sentences)
                .focused($writing)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26))
                    // A hand-painted control swaps its background when it
                    // cannot act (§83) — it never just ignores the tap.
                    .foregroundStyle(canSend ? DS.tint : DS.textTertiary)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel(String(localized: "Send"))
        }
        .dsWell()
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chrome.roomAskPending
    }

    private func send() {
        let q = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !chrome.roomAskPending else { return }
        DSHaptic.tap()
        draft = ""
        chrome.roomAsk = ShellChrome.RoomAsk(question: q, provider: provider)
    }
}
