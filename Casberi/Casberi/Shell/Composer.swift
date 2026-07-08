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
    /// Commit carries the parse card's chosen tags (M6: save writes to us).
    var onCommit: ([String]) -> Void
    /// A finished voice note: transcript + the audio file's sourceRef.
    var onCommitVoice: (String, String) -> Void = { _, _ in }
    /// Answers a query, returning the final AnswerStream document (engine
    /// grammar). While a synthesis answer streams, it calls `onProseDoc` with
    /// each growing doc so prose renders live; lookups and the non-AI fallback
    /// never call it and just return the doc to reveal at once.
    var answer: (_ query: String, _ onProseDoc: @escaping ([String]) -> Void) async -> [String] = { _, _ in [] }
    /// Candidate project tags for the parse card, from the corpus.
    var tagCandidates: () -> [String] = { [] }
    /// The shell's glass namespace — pill and bubble share one glass identity,
    /// so open/close is a morph of the same substance, not a swap.
    var glassNamespace: Namespace.ID? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(ShellChrome.self) private var chrome

    @FocusState private var fieldFocused: Bool
    @State private var answerStream = GenStream()
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

    private var isRecording: Bool { voice.phase == .recording }
    private var hasDraft: Bool { !draft.trimmingCharacters(in: .whitespaces).isEmpty }

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
        .onChange(of: isOpen) { _, open in
            if open { fieldFocused = true }
        }
    }

    // MARK: - Open

    private var openBubble: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: DS.Space.s2) {
                // When a proposal is up, the input phase is over — the field
                // (and its blinking cursor over the placeholder) hides, so the
                // proposal's own headline reads as the statement, uncontested.
                if proposal == nil {
                    TextField("", text: $draft, axis: .vertical)
                        .placeholder(when: !hasDraft) {
                            Text("Ask anything. Organize everything.")
                                .dsText(.heading22)
                                .foregroundStyle(DS.textTertiary)
                        }
                        .dsText(.heading22)
                        .foregroundStyle(DS.textPrimary)
                        .tint(DS.tint)
                        .focused($fieldFocused)
                        // A paste-sized insertion marks the draft as a capture
                        // (the Paste chip died; the flag lives on) — pasted
                        // content still previews in the parse card and saves.
                        .onChange(of: draft) { old, new in
                            if new.count - old.count > 8 { pasted = true }
                            if new.isEmpty { pasted = false }
                        }
                        .lineLimit(1...6)
                } else {
                    Spacer(minLength: 0)
                }

                Button(action: close) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DS.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(DS.gray100, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s3)

            // The action chips ("Open app" / "Open shortcut") left with the
            // Save button: dead controls don't ride the hero surface. They
            // return when the parse can actually run them (Goal 3).

            // The suggestion chips DIED (ruling 2026-07-06 — "no need"): the
            // open composer is just the field. Paste capture survives without
            // its chip — a paste-sized insertion into the field sets the
            // `pasted` flag below, so pasted content still saves on send.
            // AnswerStream — search intent streams a composition (engine law:
            // any prefix renders).
            if answering {
                ScrollView {
                    GenRender(id: "root", els: answerStream.els)
                        .environment(\.genProseStreaming, proseStreaming)
                }
                .frame(maxHeight: 240)
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
                ParseCard(draft: draft, candidates: tagCandidates(),
                          chosen: $chosenTags)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s3)
            }

            // Bottom bar: mic + primary action.
            HStack(spacing: DS.Space.s2) {
                Button {
                    if isRecording { return }
                    DSHaptic.tap()
                    Task { await voice.start() }
                } label: {
                    Image(systemName: isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 18))
                        .foregroundStyle(isRecording ? DS.destructive : DS.textTertiary)
                        .padding(DS.Space.s1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isRecording ? "Recording" : "Record a voice note")

                Button(action: commit) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(hasDraft || isRecording ? .white : DS.textTertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .dsGlassProminent(tint: hasDraft || isRecording ? DS.tint : DS.gray100,
                                          cornerRadius: DS.Radius.pill)
                }
                .buttonStyle(.plain)
                .disabled(!hasDraft && !isRecording)
                .animation(DS.Motion.standard, value: hasDraft || isRecording)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, DS.Space.s3)
            .padding(.top, DS.Space.s3)
            .padding(.bottom, DS.Space.s3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsGlass(cornerRadius: 24, glassID: "composer", in: glassNamespace)
        .clipShape(bubbleShape)
        .scaleEffect(isOpen ? 1 : 0.3, anchor: .bottomTrailing)
        .task(id: isOpen) { await autoSendIfProbed() }
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
            draft = d
            pasted = false
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
        draft = q
        try? await Task.sleep(for: .milliseconds(500))
        // The one-shot draft set reads as a paste to the heuristic above;
        // the probe is an utterance — answer, never save.
        pasted = false
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
        } else if pasted {
            // Paste is a capture path — send keeps what came in.
            onCommit(Array(chosenTags))
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
            // Typed words are an utterance — the answer streams. On devices
            // whose model writes the answer there's a beat of composing; show
            // it plainly. Devices that fall back to the scoring engine answer
            // without a suspend, so no placeholder ever flashes for them.
            answering = true
            if OnDeviceModel.isAvailable {
                answerStream.paint(["root = Stack([w])", "w = Insight(\"Thinking…\")"])
            }
            let q = draft
            Task { @MainActor in
                var streamed = false
                let finalDoc = await answer(q) { partialDoc in
                    // Prose arriving live — paint each growing snapshot; the
                    // Insight breathes its dot while this fires (§2).
                    streamed = true
                    proseStreaming = true
                    answerStream.paint(partialDoc)
                }
                // Prose already painted its way in; settle on the final text.
                // A lookup or the fallback never streamed, so reveal it with
                // the typewriter (unchanged behaviour).
                proseStreaming = false
                if streamed { answerStream.paint(finalDoc) }
                else { answerStream.stream(finalDoc) }
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
                            Chip(text: tag, style: active ? .tint : .neutral)
                                .onTapGesture {
                                    if active { chosen.remove(tag) } else { chosen.insert(tag) }
                                }
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

    var body: some View {
        let side: CGFloat = chrome.minimized ? 48 : 56
        Button(action: action) {
            // Plus, not a magnifier: the button's job is the capture habit
            // (Journal's glass + is the system precedent). The bubble teaches
            // ask once open.
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(DS.textPrimary)
                .frame(width: side, height: side)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .dsGlass(cornerRadius: DS.Radius.pill, glassID: "composer", in: glassNamespace)
        .accessibilityLabel("Ask or save")
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
