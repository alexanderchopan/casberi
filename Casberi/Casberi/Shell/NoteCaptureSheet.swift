import SwiftUI
import SwiftData

/// THE NOTE CAPTURE SHEET (prd §969, 2026-09-28) — the one place in the app you WRITE.
///
/// §26 ruled that Casberi does not author: typed composer text never saves,
/// content is never editable, "if a real quick-jot itch emerges, it becomes a
/// deliberate capture path later — never an editor". This is that capture
/// path. It is the composer's own shape with the ask's parts gone — no model
/// chip, no ask chips, no answer — and it is not an editor: a note is
/// captured whole when the sheet closes and is never opened for editing
/// again (the sheet under a note draws its words; content is the record).
///
/// **Two verbs, one outcome.** Pulling the sheet down or pressing Done KEEPS
/// the note — it lands under `You` as a note thing, the same row a note
/// shared in from Apple Notes gets (§230a), so it stands in the Notes room.
/// Share hands the same words to the system share sheet, where Apple Notes'
/// extension (the only real door into Notes — it has no compose URL),
/// Messages, Mail and Obsidian take them; the note is kept regardless, so
/// nothing here is a silent blank jump. An empty sheet dismissed lands
/// nothing: saving is an outcome the toast reports, never a verb.
///
/// The typed-text-never-saves rule is UNTOUCHED for the ask surface: that
/// field asks, this one keeps, and the two are different sheets.
///
/// **Dictation is Apple's, and the band's mic is a VOICE NOTE (prd §971,
/// superseding §970's dictation).** The field is focused on appear, so the
/// keyboard's own mic key dictates into it on the phone, and the Mac's
/// system dictation types into the same field; nothing here draws a second
/// dictation door. The wide key follows the composer's foot rule — one
/// capsule, the one verb available: Record with nothing written, Stop while
/// recording, Done once there are words. Stop KEEPS a voice thing under
/// `You` — the audio and its transcript — and closes: one tap in, one tap
/// out, no review state, because a note is never edited after capture and
/// the audio is the record. A written sheet keeps words, an empty sheet
/// records; no sheet holds both. Holding the room's New tile lands here
/// recording (`ShellChrome.noteVoiceOnOpen`).
struct NoteCaptureSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Close the sheet; the words, if any, have already been kept.
    let onClose: () -> Void
    /// The kept note, for the shell's own landing (toast, flight).
    let onLand: (Thing) -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool
    /// The sheet's own mic (prd §971), never the composer's.
    @State private var voice = VoiceCapture()

    private var hasDraft: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var isRecording: Bool { voice.phase == .recording }

    /// The one explaining line (prd §748): what happens to the words, or,
    /// with the mic refused, the route to allowing it — the composer's own
    /// line, folded into the footnote so the screen keeps one sentence.
    private var footnote: Text {
        if voice.phase == .denied {
            return Text("No mic access. Allow Casberi in \(DS.settingsAppName)")
        }
        if isRecording { return Text("Stop, and it is kept in Notes") }
        return hasDraft
            ? Text("Kept in Notes · share it anywhere")
            : Text("Kept in Notes when you close this")
    }

    var body: some View {
        VStack(spacing: 0) {
            // The composer's own way out (a visible control AND the swipe),
            // at the top-left where the composer draws it.
            HStack(spacing: 0) {
                Button {
                    DSHaptic.tap()
                    keepAndClose()
                } label: {
                    Image(systemName: "chevron.down")
                        .dsGlyph(.body, weight: .semibold)
                        .foregroundStyle(DS.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(DS.fillFaint, in: Circle())
                        .dsTapTarget(Circle())
                        .dsHover()
                }
                .buttonStyle(PressSpring())
                .accessibilityLabel(hasDraft ? Text("Keep the note and go back") : Text("Back to your things"))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s3)

            Spacer(minLength: 0)

            // THE WELL: the words at the head rung, as on the ask surface
            // (prd §577 — the sentence being written is the subject of the
            // screen for as long as it is being written).
            ZStack(alignment: .topLeading) {
                if !hasDraft {
                    Text("Note")
                        .dsText(.heading34)
                        .foregroundStyle(DS.textTertiary)
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.vertical, DS.Space.s4)
                        .allowsHitTesting(false)
                }
                TextField("", text: $draft, axis: .vertical)
                    .dsText(.heading34)
                    .foregroundStyle(DS.textPrimary)
                    .tint(DS.tint)
                    .focused($focused)
                    .lineLimit(1...8)
                    .textFieldStyle(.plain)
                    .submitLabel(.return)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.vertical, DS.Space.s4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
            .padding(.horizontal, DS.Space.s4)

            // One explaining line (prd §748): what happens to the words.
            DSFootnote(footnote)
                .padding(.horizontal, DS.Space.s4 + DS.Space.s1)
                .padding(.top, DS.Space.s3)

            // The live mic, the composer's own band (prd §970).
            if isRecording {
                VoiceListeningBand(elapsed: voice.elapsed, transcript: voice.transcript)
            }

            // THE BAND: Share in the composer's tint disc, and the composer's
            // wide slot carrying the one verb available (prd §971).
            HStack(spacing: DS.Space.s3) {
                ShareLink(item: draft) {
                    Image(systemName: "square.and.arrow.up")
                        .dsGlyph(.feature, weight: .regular)
                        .foregroundStyle(hasDraft ? Color.white : DS.textTertiary)
                        .frame(width: AgentDestinationKeys.side, height: AgentDestinationKeys.side)
                        .background(hasDraft ? DS.tint : DS.surfaceRaised, in: Circle())
                        .contentShape(Circle())
                        .dsHover()
                }
                .buttonStyle(PressSpring())
                // A share of nothing is §83's dead control: the disc stays,
                // greyed, and does not open.
                .disabled(!hasDraft)
                .accessibilityLabel(Text("Share the note"))
                wideKey
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s4)
            .padding(.bottom, DS.Space.s4)
        }
        .background(DS.page.ignoresSafeArea())
        .onAppear {
            // Held New (prd §970): recording when the sheet lands, keyboard
            // down. Consumed on read, so a later tap of New arrives typing,
            // as it should.
            var record = chrome.noteVoiceOnOpen
            chrome.noteVoiceOnOpen = false
            #if DEBUG
            // `-noteVoice YES` — land recording, for the screen sweep. The
            // simulator has no microphone, so a pass shows the band and the
            // Stop key, never a transcript.
            if UserDefaults.standard.bool(forKey: "noteVoice") {
                NSLog("[Casberi] noteVoice: raised")
                record = true
            }
            #endif
            if record { startRecording() } else { focused = true }
        }
        // The swipe down the composer also has: keep, then go.
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard value.translation.height > 80,
                          abs(value.translation.width) < value.translation.height else { return }
                    keepAndClose()
                }
        )
    }

    /// The one verb available (prd §971), the composer's foot rule applied to
    /// the note: Stop while recording, Done once there are words, else
    /// Record — the voice kind's own waveform, so the key says what it makes.
    /// A quiet Done over an empty field was §83's dead control — it closed and
    /// kept nothing, which the chevron already does.
    @ViewBuilder
    private var wideKey: some View {
        if isRecording {
            AgentWideKey(title: String(localized: "Stop"), glyph: "stop.fill", tone: .tint) {
                DSHaptic.tap()
                keepVoiceAndClose()
            }
        } else if hasDraft {
            AgentWideKey(title: String(localized: "Done"), tone: .ink) {
                DSHaptic.tap()
                keepAndClose()
            }
        } else {
            AgentWideKey(glyph: "waveform", tone: .ink) {
                DSHaptic.tap()
                startRecording()
            }
        }
    }

    // MARK: - Recording

    /// Start recording. The keyboard goes down first: the band draws where
    /// the field stood, and a keyboard over a live mic is two ways to write
    /// at once. The permission asks arrive here, in context.
    private func startRecording() {
        focused = false
        Task { await voice.start() }
    }

    /// Stop, and keep what was recorded as a VOICE thing under `You` — the
    /// transcript as its words, the first line as its title, the audio in
    /// the thing's synced field and its file reference for the local player
    /// — then close. Nothing heard and nothing said lands nothing.
    ///
    /// `stop(keep: true)` returns the transcript and the file reference
    /// together; the file is read for its bytes right after, once, so the
    /// note follows the person to their other devices (a voice note on one
    /// phone only is half a feature).
    private func keepVoiceAndClose() {
        defer { onClose() }
        guard let piece = voice.stop(keep: true) else { return }
        let words = piece.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let bytes = VoiceCapture.audioURL(for: piece.sourceRef).flatMap { try? Data(contentsOf: $0) }
        guard !words.isEmpty || (bytes?.count ?? 0) > 0 else {
            if let url = VoiceCapture.audioURL(for: piece.sourceRef) {
                try? FileManager.default.removeItem(at: url)
            }
            return
        }
        let thing = Thing(
            kind: .voice,
            title: words.isEmpty ? String(localized: "Voice note") : IngestSupport.titleLine(words),
            content: words,
            source: "You",
            sourceRef: piece.sourceRef)
        thing.audio = bytes
        modelContext.insert(thing)
        modelContext.saveHonestly()
        SpotlightIndex.index([thing])
        onLand(thing)
    }

    // MARK: - Keeping

    /// Keep the words as a note thing — `Capture.thing`'s own shape (a URL is
    /// a link, everything else a note), under the person's own source — then
    /// close. Empty words close and keep nothing.
    private func keepAndClose() {
        // Pulled down mid-recording: the recording is kept, as typed words
        // are — dismiss keeps (§969).
        if isRecording { keepVoiceAndClose(); return }
        defer { onClose() }
        guard hasDraft, let thing = Capture.thing(from: draft) else { return }
        // A note is a note even when it holds a link: `Capture.thing` turns a
        // URL into a link thing for the paste chip's sake, and a link thing
        // would stand outside this room's membership (`Pinboard.isNote`).
        thing.kind = .note
        modelContext.insert(thing)
        modelContext.saveHonestly()
        SpotlightIndex.index([thing])
        onLand(thing)
    }
}

/// The note sheet's two triggers on `RootShell` (prd §969): the Notes room's
/// New tile (`ShellChrome.newNote`, a counter that is the tap) and the
/// `-openNote YES` hook at mount. One modifier, because `RootShell`'s body
/// chain is at the type-checker's edge and two more modifiers tipped it.
struct NoteSheetHooks: ViewModifier {
    @Binding var noteOpen: Bool
    let newNote: Int

    func body(content: Content) -> some View {
        content
            .onChange(of: newNote) { _, _ in
                withAnimation(DS.Motion.standard) { noteOpen = true }
            }
            .onAppear {
                if UserDefaults.standard.bool(forKey: "openNote") {
                    NSLog("[Casberi] openNote: raised")
                    noteOpen = true
                }
            }
    }
}
