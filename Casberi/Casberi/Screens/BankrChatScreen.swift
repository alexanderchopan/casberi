import SwiftUI
import SwiftData

/// THE BANKR CONVERSATION (prd §529, 2026-08-29) — the one screen in this app
/// where a sentence you type can cause something to happen with real money,
/// and the only screen whose composer has two send buttons.
///
/// ## WHY TWO BUTTONS
///
/// "Show me my automations" is a read. "Do a limit order for XYZ" is a write.
/// On the wire they are the same thing — free text to a remote agent — and the
/// classification happens inside Bankr's model, AFTER we have sent it. So this
/// app cannot tell them apart, and a screen that pretended to would be the §83
/// fake status in the one place believing it costs money.
///
/// The person classifies instead, exactly as `Find` and `Ask` split the
/// composer (§215): **Ask** carries the answer-only prefix and sends straight
/// away; **Do** drops it and confirms first. Which verb you tap is a fact you
/// know and we do not.
///
/// ## THE CONFIRMATION READS BACK YOUR WORDS
///
/// Bankr replies in sentences, so nothing here can state what a job WILL do
/// before it does it. A sheet reading "1.0 ETH → 3,200 USDC" would be a number
/// this app invented. It shows the instruction as typed and says plainly that
/// Bankr decides the rest — which is the honest ceiling until `-bankrProbe`
/// measures whether the job envelope carries anything structured.
///
/// ## AN ACT LEAVES A RECEIPT, AN ANSWER DOES NOT
///
/// A successful **Do** lands a `.run` thing (the kind declared in `Thing.swift`
/// for exactly this — "unused until bridges prove writes"), keyed
/// `bankr:job:<id>`, carrying the instruction as its title and Bankr's own
/// report as its content. No new stored property, so **no CloudKit deploy**.
/// An **Ask** lands nothing: an answer is an answer, and the corpus is for
/// things that happened.
struct BankrChatScreen: View {
    @Environment(\.modelContext) private var context

    @State private var draft = ""
    @State private var turns: [Turn] = []
    @State private var inFlight = false
    @State private var canAct = BankrAgent.canAct
    @State private var pending: String?

    private var configured: Bool { AgentKey.isConfigured(.bankr) }
    private var armed: Bool {
        !inFlight && !draft.trimmingCharacters(in: .whitespaces).isEmpty && configured
    }

    // MARK: - A turn

    struct Turn: Identifiable, Equatable {
        enum Voice: Equatable { case you, bankr, trouble }
        let id = UUID()
        let voice: Voice
        let text: String
        /// Whether the turn you sent was an ACT. Drawn on the turn itself,
        /// because a transcript where an instruction and a question look the
        /// same is a transcript that cannot be audited afterwards.
        var acted = false
    }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Space.s3) {
                    intro
                    ForEach(turns) { turn in
                        bubble(turn).id(turn.id)
                    }
                    if inFlight { thinking }
                }
                .padding(.horizontal, DS.Space.s4)
                .padding(.vertical, DS.Space.s4)
            }
            .onChange(of: turns.count) {
                guard let last = turns.last else { return }
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Bankr")
        .confirmationDialog("Let Bankr do this?",
                            isPresented: Binding(get: { pending != nil },
                                                 set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible) {
            Button("Send it", role: .destructive) { if let p = pending { pending = nil; send(p, acting: true) } }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            // The instruction as typed, then the ceiling. Never a parsed
            // amount — see the type's own doc comment.
            Text(verbatim: "\(pending ?? "")\n\n") +
            Text("Bankr acts on this with your key. Casberi can't check what it will do first, and can't undo it.")
        }
    }

    // MARK: - The head

    @ViewBuilder private var intro: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(canAct
                 ? "Ask about your wallet, or tell Bankr to do something. Do asks you first."
                 : "Ask about your wallets and live markets. Bankr can't act — turn that on in its setup screen.")
                .dsText(.callout15).foregroundStyle(DS.textSecondary)
            if !configured {
                Text("No Bankr key yet — paste one on its setup screen.")
                    .dsText(.subhead13).foregroundStyle(DS.attention)
            }
        }
        .padding(.bottom, DS.Space.s2)
    }

    // MARK: - Turns

    private func bubble(_ turn: Turn) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(spacing: DS.Space.s2) {
                Text(label(for: turn)).dsText(.subhead13).fontWeight(.semibold)
                    .foregroundStyle(tint(for: turn))
                Spacer(minLength: 0)
            }
            Text(turn.text)
                .dsText(.callout15)
                .foregroundStyle(turn.voice == .trouble ? DS.attention : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DS.Space.s3)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
            .fill(.ultraThinMaterial))
    }

    private func label(for turn: Turn) -> String {
        switch turn.voice {
        case .you:     turn.acted ? String(localized: "You asked Bankr to do this")
                                  : String(localized: "You")
        case .bankr:   turn.acted ? String(localized: "Bankr — what it did")
                                  : String(localized: "Bankr")
        case .trouble: String(localized: "Didn't go through")
        }
    }

    private func tint(for turn: Turn) -> Color {
        switch turn.voice {
        case .you:     turn.acted ? DS.attention : DS.textTertiary
        case .bankr:   DS.textTertiary
        case .trouble: DS.attention
        }
    }

    private var thinking: some View {
        Text("Working…").dsText(.subhead13).foregroundStyle(DS.textTertiary)
    }

    // MARK: - The composer

    private var composer: some View {
        VStack(spacing: DS.Space.s2) {
            TextField("Ask, or tell Bankr what to do", text: $draft, axis: .vertical)
                .dsText(.callout15)
                .lineLimit(1...4)
                .padding(DS.Space.s3)
                .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .fill(.ultraThinMaterial))
            HStack(spacing: DS.Space.s2) {
                verb("Ask", tint: DS.tint) { send(draft, acting: false) }
                if canAct { verb("Do", tint: DS.attention) { pending = draft.trimmingCharacters(in: .whitespacesAndNewlines) } }
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s3)
        .background(.ultraThinMaterial)
    }

    private func verb(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            DSHaptic.tap()
            action()
        } label: {
            Text(title)
                .dsText(.subhead13).fontWeight(.semibold)
                .foregroundStyle(armed ? Color.white : DS.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.s3)
                .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    // A hand-rolled button paints its own background, so it
                    // must swap that background when inert — `.disabled` only
                    // dims a plain-style label (§83's first corollary).
                    .fill(armed ? tint : DS.textQuaternary.opacity(0.18)))
        }
        .buttonStyle(.plain)
        .disabled(!armed)
    }

    // MARK: - Sending

    private func send(_ text: String, acting: Bool) {
        let instruction = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty, !inFlight else { return }
        draft = ""
        inFlight = true
        turns.append(Turn(voice: .you, text: instruction, acted: acting))
        Task { @MainActor in
            let outcome = acting ? await BankrAgent.act(instruction)
                                 : await BankrAgent.ask(instruction)
            inFlight = false
            switch outcome {
            case .success(let reply):
                turns.append(Turn(voice: .bankr, text: reply.text, acted: acting))
                if acting {
                    land(instruction: instruction, report: reply.text, jobID: reply.jobID)
                    DSHaptic.success()
                }
            case .failure(let failure):
                turns.append(Turn(voice: .trouble, text: line(for: failure), acted: acting))
            }
        }
    }

    /// The receipt. Only an ACT lands one — see the type's doc comment.
    private func land(instruction: String, report: String, jobID: String) {
        let thing = Thing(kind: .run,
                          title: IngestSupport.titleLine(instruction),
                          content: report,
                          source: "Bankr",
                          tags: ["Agent run"],
                          sourceRef: "bankr:job:\(jobID)")
        context.insert(thing)
        try? context.save()
    }

    /// Every failure gets its own sentence. A refusal by Bankr, a key it
    /// rejected and a job still running are three different situations, and
    /// one shared "something went wrong" sends people to re-paste a key that
    /// was never the problem.
    private func line(for failure: BankrAgent.Failure) -> String {
        switch failure {
        case .noKey:            String(localized: "No Bankr key saved.")
        case .actingOff:        String(localized: "Bankr isn't allowed to act. Turn it on in its setup screen.")
        case .emptyInstruction: String(localized: "Nothing to send.")
        case .rejectedKey:      String(localized: "Bankr wouldn't accept that key.")
        case .rateLimited:      String(localized: "Bankr is rate-limiting this key. Try again shortly.")
        case .refused(let why): why.isEmpty ? String(localized: "Bankr declined this one.")
                                            : String(localized: "Bankr declined: \(why)")
        case .empty:            String(localized: "Bankr answered with nothing.")
        case .unreachable:      String(localized: "Couldn't reach Bankr.")
        // NOT "it failed" — the job may still be running on Bankr's side, and
        // telling somebody their order didn't happen when we merely stopped
        // watching is the worse of the two wrong answers.
        case .timedOut:         String(localized: "Still running on Bankr after 90 seconds — check Bankr for the outcome.")
        case .providerError(let status): String(localized: "Bankr answered with an error (\(status)).")
        }
    }
}
