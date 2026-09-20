import SwiftUI
import SwiftData

/// The live half of an agent's room (prd §840, reshaped §841) — the Chat tile.
///
/// **It is TWO pieces in the room's own slots, not one block that replaces
/// them** (user, 2026-09-19: *"if you toggle chat the composer row opens below
/// it, and the header card is where the responses or thread is"*, and
/// *"i don't want buttons at the top of the screen"*). §840's first build drew
/// the whole surface where the list goes and dropped the cover, which put the
/// tiles at the top of the screen on Chat and at 316pt on All — furniture that
/// walks, and a control at the top edge, which is the one thing §752 bans
/// outright. So:
///
///   `AgentChatThread` fills the LEAD slot, where the cover sits on All.
///   the tiles, unmoved, in the same place they are in every room.
///   `AgentChatEntry` below them, where the list would be.
///
/// Nothing is duplicated and nothing shifts: the thread IS the room's lead
/// while you are chatting, and the cover is its lead while you are reading.
///
/// **Both render from the CORPUS and hold no answer state.** A keyed answer
/// lands as a `Thing` (§839), so the entry asks, the ask path lands the
/// exchange, and the `@Query` the thread draws updates. What is on screen is
/// what is in the store — the same record the All tile lists and the thing
/// sheet opens. One record, three readers.
///
/// **Neither can call the model.** `keyedAnswerDocument` is private to
/// `RootShell` and is the one funnel every ask goes through, so the entry
/// posts `ShellChrome.roomAsk` and the shell serves it (§377's lesson about a
/// second door that drifts from the first).

/// The conversation so far, in the room's lead slot.
struct AgentChatThread: View {
    let source: String

    @Environment(ShellChrome.self) private var chrome
    @Query private var live: [Thing]
    @State private var turns: [AgentSheet.Turn] = []
    /// The ref of a conversation ENDED from here (§841) — it stays the newest
    /// row until the next answer lands, so without this the parse would bring
    /// it straight back.
    @State private var closed: String?

    init(source: String) {
        self.source = source
        // FENCED TO CONVERSATIONS HAD HERE. An IMPORTED conversation carries
        // the same `source` — a Claude export lands under "Claude" exactly as
        // a keyed Claude chat does (§839, one agent one room, deliberately) —
        // so "newest row for this source" would show last week's export as the
        // conversation you are in until a live exchange outdated it.
        let mine = AgentConversationLanding.refPrefix
        var d = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == source
                && ($0.sourceRef?.starts(with: mine) ?? false) },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        d.fetchLimit = 1
        _live = Query(d)
    }

    /// What makes the parse stale, and nothing else — read ONCE per body pass
    /// (§646: one body pass, one `@Query` read). `messageCount` moves on every
    /// upsert (§839) so it catches an answer landing; the id catches the
    /// conversation being replaced. Deliberately not the transcript itself:
    /// comparing 8,000 characters every pass is the cost this avoids.
    private var key: String {
        guard let thing = live.first, thing.isLive else { return "" }
        return "\(thing.id)-\(thing.messageCount ?? 0)"
    }

    var body: some View {
        // The lead slot's own well and height, so Chat and All are the same
        // shape (`DSRoomChassis.leadHeight`, §766).
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                if turns.isEmpty && chrome.roomAskSource != source {
                    DSEmptyState(headline: Text("Nothing asked yet"),
                                 words: Text("Your conversation with \(source) appears here"),
                                 scale: .list(rows: 3))
                } else {
                    AgentTurnsView(turns: turns, source: source)
                    // The only way to END a conversation from a room (§841).
                    // Without it every ask upserts onto one ever-growing row
                    // and the whole transcript goes back as history each turn;
                    // the composer's own door is the only other one, and §697b
                    // took the composer off every surface but this.
                    //
                    // It draws only over a conversation that exists, so it is
                    // never a control that does nothing (§83).
                    Button {
                        DSHaptic.tap()
                        chrome.roomNewConversation += 1
                        // The row we walked away from is REMEMBERED, not just
                        // cleared: it is still the newest one until the next
                        // answer lands, so a bare `turns = []` would be undone
                        // by the next `onAppear` — switch to All and back and
                        // the conversation you ended is on screen again.
                        closed = live.first?.sourceRef
                        turns = []
                    } label: {
                        Text("Start a new conversation")
                            .dsText(.subhead12)
                            .foregroundStyle(DS.tint)
                    }
                    .buttonStyle(.plain)
                    // The pending state is keyed to THIS room (§841): a global
                    // flag drew "Asking Claude…" in Claude's room for a
                    // question Bankr was answering.
                    if chrome.roomAskSource == source {
                        HStack(spacing: DS.Space.s2) {
                            DSSpinner()
                            Text("Asking \(source)…")
                                .dsText(.subhead12)
                                .foregroundStyle(DS.textSecondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, DS.Space.s4)
        }
        .frame(height: DSRoomChassis.leadHeight)
        .dsRoomHeadBlock()
        .onAppear(perform: reparse)
        .onChange(of: key) { _, _ in reparse() }
    }

    /// Held rather than computed: the entry field below owns a draft, and a
    /// computed `turns` would re-parse the whole stored transcript on every
    /// keystroke — build 525's class. Parsed by `AgentSheet.turns`, the thing
    /// sheet's own reader, never a second one (§418).
    private func reparse() {
        guard let thing = live.first, thing.isLive,
              thing.sourceRef != closed,
              let body = thing.enrichedText,
              let assistant = AgentSheet.assistant(for: source)
        else { turns = []; return }
        turns = AgentSheet.turns(body, assistant: assistant)
    }
}

/// The composer row, below the tiles.
struct AgentChatEntry: View {
    let source: String
    /// Who answers. The room's own agent, never `AgentKey.active`: standing in
    /// Bankr's room and being answered by whichever key happens to be active
    /// is the §83 failure this whole section exists to end.
    let provider: AgentProvider

    @Environment(ShellChrome.self) private var chrome
    @State private var draft = ""
    /// The question in flight, kept so a FAILED ask can give it back (§841).
    /// §840 cleared the draft and discarded the `Result`, so a question asked
    /// in airplane mode vanished with no message anywhere — the surface simply
    /// snapped back to the turns it already had.
    @State private var sent = ""

    private var pending: Bool { chrome.roomAskSource == source }

    var body: some View {
        HStack(alignment: .bottom, spacing: DS.Space.s2) {
            TextField(String(localized: "Ask \(source)"), text: $draft, axis: .vertical)
                .dsText(.body17)
                .foregroundStyle(DS.textPrimary)
                .tint(DS.tint)
                .lineLimit(1...6)
                .textInputAutocapitalization(.sentences)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    // `.feature` (28), not a frozen `.system(size: 26)` — §762:
                    // a glyph takes a rung so it scales with the field beside
                    // it. A send button pinned at 26 stays 26 while the text
                    // it sits next to grows with Dynamic Type, which is the
                    // one reader that change is for (§206).
                    .dsGlyph(.feature)
                    // A hand-painted control swaps its face when it cannot act
                    // (§83) — it never just ignores the tap.
                    .foregroundStyle(canSend ? DS.tint : DS.textTertiary)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel(String(localized: "Send"))
        }
        .dsWell()
        // A refused ask hands the question back rather than eating it.
        .onChange(of: chrome.roomAskFailed) { _, failed in
            guard failed == source, !sent.isEmpty else { return }
            if draft.isEmpty { draft = sent }
            sent = ""
            chrome.roomAskFailed = nil
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !pending
    }

    private func send() {
        let q = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !pending else { return }
        DSHaptic.tap()
        sent = q
        draft = ""
        chrome.roomAsk = ShellChrome.RoomAsk(question: q, provider: provider, source: source)
    }
}
