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
/// ## THE CONFIRMATION READS BACK YOUR WORDS, IN THE THREAD
///
/// Bankr replies in sentences, so nothing here can state what a job WILL do
/// before it does it. A sheet reading "1.0 ETH → 3,200 USDC" would be a number
/// this app invented. It shows the instruction as typed and says plainly that
/// Bankr decides the rest — which is the honest ceiling until `-bankrProbe`
/// measures whether the job envelope carries anything structured.
///
/// It is drawn INLINE, where the answer will land, and NOT as a
/// `confirmationDialog` (user, 2026-08-31: "i don't know why a sheet popups up
/// in 'tell bankr'. all of this could be done on the screen"). A system dialog
/// covers the conversation the instruction refers to — the one thing worth
/// re-reading before you spend money — and it arrives in the OS's voice rather
/// than this app's.
///
/// ## THE TURNS ARE A DOCUMENT, NOT BUBBLES
///
/// Flat on ink, the composer's own grammar (§532's ramp): your instruction is a
/// heading, Bankr's reply is body, and provenance is the caption beneath it.
/// They wore `.ultraThinMaterial` until 2026-08-31, which is glass on CONTENT —
/// banned by the design law, which keeps glass to the floating layer.
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var draft = ""
    @State private var turns: [Turn] = []
    @State private var inFlight = false
    @State private var canAct = BankrAgent.canAct
    @State private var pending: String?
    /// Seconds into the current poll — the only progress an async job has to
    /// show, since there's no partial text to stream. Reset per send.
    @State private var elapsedSeconds = 0
    /// Drives the mark's breathe while a job runs. Off under Reduce Motion.
    @State private var breathing = false

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
                    if let p = pending { confirmBlock(p).id(confirmAnchor) }
                    if inFlight { thinking }
                }
                .padding(.horizontal, DS.Space.s4)
                .padding(.vertical, DS.Space.s4)
            }
            .onChange(of: turns.count) {
                guard let last = turns.last else { return }
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            // The confirm lands below the fold on a long thread, and an offer
            // you cannot see is the dead control §83 bans.
            .onChange(of: pending) {
                guard pending != nil else { return }
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(confirmAnchor, anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Bankr")
    }

    private var confirmAnchor: String { "bankr.confirm" }

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

    /// Flat on ink. Your instruction is the heading, Bankr's reply is the body,
    /// and who answered is the caption underneath — the composer's own anatomy,
    /// so the two conversation surfaces in this app read as one product.
    @ViewBuilder private func bubble(_ turn: Turn) -> some View {
        switch turn.voice {
        case .you:
            VStack(alignment: .leading, spacing: 2) {
                // An act is marked on the turn itself: a transcript where an
                // instruction and a question look the same cannot be audited
                // afterwards.
                if turn.acted {
                    Text("You told Bankr to do this")
                        .dsText(.label12).foregroundStyle(DS.attention)
                }
                Text(turn.text)
                    .dsText(.heading17)
                    .foregroundStyle(DS.textPrimary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .bankr:
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(turn.text)
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .textSelection(.enabled)
                provenance(acted: turn.acted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .trouble:
            Text(turn.text)
                .dsText(.body17)
                .foregroundStyle(DS.attention)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The composer's badge, worded for this screen. An act says what it DID,
    /// because a receipt landed for it and an answer leaves nothing behind.
    private func provenance(acted: Bool) -> some View {
        HStack(spacing: DS.Space.s1) {
            Image(systemName: acted ? "checkmark.seal" : "key.fill")
                .dsGlyph(10, weight: .regular)
            Text(acted ? "Bankr ran this with your key — kept in your things"
                       : "Answered with your key · via Bankr")
        }
        .dsText(.label12)
        .foregroundStyle(DS.textTertiary)
    }

    /// THE MARK CARRIES THE LIVENESS (user, 2026-08-31: "are we to have bankr
    /// logo next to 'working' b/c that looks cool"). The brand mark breathes
    /// while the job runs, so the logo IS the status light and there is no
    /// second blinking dot beside it — one indicator, not two.
    ///
    /// The elapsed count is the only progress an async job has to show: there
    /// is no partial text to stream, and a poll that says nothing for ninety
    /// seconds reads as a hang.
    private var thinking: some View {
        HStack(spacing: DS.Space.s2) {
            ZStack {
                Circle()
                    .fill(DS.fillFaint)
                    .frame(width: DS.Face.row + 8, height: DS.Face.row + 8)
                    .scaleEffect(breathing ? 1 : 0.82)
                    .opacity(breathing ? 0.9 : 0.35)
                BridgeIcon(name: "Bankr", size: DS.Face.row, circular: true)
            }
            .frame(width: DS.Face.row + 8, height: DS.Face.row + 8)
            .animation(reduceMotion ? nil
                       : .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                       value: breathing)
            .onAppear { breathing = true }
            .onDisappear { breathing = false }
            .accessibilityHidden(true)

            Text("Bankr is working")
                .dsText(.heading17)
                .foregroundStyle(DS.textPrimary)
            Spacer(minLength: 0)
            if elapsedSeconds > 0 {
                Text(elapsed)
                    .dsText(.heading17)
                    .monospacedDigit()
                    .foregroundStyle(DS.textPrimary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(elapsedSeconds > 0
                            ? Text("Bankr is working, \(elapsedSeconds) seconds")
                            : Text("Bankr is working"))
    }

    /// m:ss — a bare seconds count past a minute reads as an error code.
    private var elapsed: String {
        String(format: "%d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
    }

    // MARK: - The confirm, in the thread

    /// Drawn where the answer will land, never as a system dialog. It reads
    /// back the instruction AS TYPED and states the ceiling: Bankr decides what
    /// it does, and neither half of that can be checked here beforehand.
    private func confirmBlock(_ instruction: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text("Do it?")
                .dsText(.heading17)
                .foregroundStyle(DS.textPrimary)
            Text(instruction)
                .dsText(.body17)
                .foregroundStyle(DS.textPrimary)
                .textSelection(.enabled)
            Text("Sent as written. Bankr decides what it does — Casberi can't check it first, or undo it.")
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
            HStack(spacing: DS.Space.s2) {
                confirmVerb("Send it", filled: true) {
                    pending = nil
                    send(instruction, acting: true)
                }
                confirmVerb("Not now", filled: false) { pending = nil }
            }
            .padding(.top, DS.Space.s1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func confirmVerb(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            DSHaptic.tap()
            action()
        } label: {
            Text(title)
                .dsText(.heading17)
                .foregroundStyle(filled ? DS.inkGround : DS.textPrimary)
                .padding(.horizontal, DS.Space.s4)
                .frame(minHeight: 40)
                .background(Capsule(style: .continuous)
                    .fill(filled ? DS.textPrimary : DS.fillStrong))
        }
        .buttonStyle(.plain)
    }

    // MARK: - The composer

    private var composer: some View {
        VStack(spacing: DS.Space.s2) {
            TextField("Ask, or tell Bankr what to do", text: $draft, axis: .vertical)
                .dsText(.callout15)
                .lineLimit(1...4)
                .padding(DS.Space.s3)
                .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .fill(DS.fillFaint))
            HStack(spacing: DS.Space.s2) {
                verb("Ask", tint: DS.tint) { send(draft, acting: false) }
                // Do never sends: it raises the confirm IN THE THREAD, and the
                // draft is deliberately left in the field so "Not now" costs
                // nothing to recover from.
                if canAct {
                    verb("Do", tint: DS.attention) {
                        pending = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
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

    /// This screen's own turns, threaded into the next ASK so "the other
    /// one" still means something (2026-08-31) — never into a Do: an act's
    /// confirmation reads back exactly what you typed, and folding hidden
    /// context into that prompt would make "these are your words" a little
    /// less true. Only Q/A pairs from a real Ask count — a Do doesn't answer
    /// a question, and a turn that never got a reply has nothing to pair.
    private var askHistory: String {
        var lines: [String] = []
        var pendingQuestion: String?
        for turn in turns {
            switch turn.voice {
            case .you where !turn.acted: pendingQuestion = turn.text
            case .bankr:
                if let q = pendingQuestion {
                    lines.append("Q: \(q)\nA: \(turn.text)")
                }
                pendingQuestion = nil
            default: pendingQuestion = nil
            }
        }
        return lines.suffix(6).joined(separator: "\n\n")
    }

    private func send(_ text: String, acting: Bool) {
        let instruction = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty, !inFlight else { return }
        let history = askHistory
        let extra = history.isEmpty ? "" : """
        This chat's prior turns, oldest first — "it"/"that"/"those" in the \
        question below may refer back to one of these:
        \(history)
        """
        draft = ""
        inFlight = true
        elapsedSeconds = 0
        turns.append(Turn(voice: .you, text: instruction, acted: acting))
        let onTick: (Int) -> Void = { seconds in
            Task { @MainActor in elapsedSeconds = seconds }
        }
        Task { @MainActor in
            let outcome = acting ? await BankrAgent.act(instruction, onTick: onTick)
                                 : await BankrAgent.ask(instruction, extra: extra, onTick: onTick)
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
