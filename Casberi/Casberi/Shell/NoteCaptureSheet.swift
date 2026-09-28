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
/// **Speaking a note (prd §970).** The band's wide key follows the composer's
/// foot rule — one capsule, the one verb available: the mic with nothing
/// written, Stop while listening, Done once there are words. Stop puts the
/// transcript IN THE FIELD, never straight into a saved note: a transcript
/// is the one input you have not read yet (§581c's reasoning, which holds
/// for a note as it does for an ask), so you read it, fix a word, and Done
/// keeps it. The audio is dropped — a note is words. Holding the room's New
/// tile lands here with the mic already live (`ShellChrome.noteVoiceOnOpen`).
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
    /// The sheet's own mic (prd §970), never the composer's.
    @State private var voice = VoiceCapture()

    private var hasDraft: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var isListening: Bool { voice.phase == .recording }

    /// The one explaining line (prd §748): what happens to the words, or,
    /// with the mic refused, the route to allowing it — the composer's own
    /// line, folded into the footnote so the screen keeps one sentence.
    private var footnote: Text {
        if voice.phase == .denied {
            return Text("No mic access. Allow Casberi in \(DS.settingsAppName)")
        }
        if isListening { return Text("Stop, and the words land here to read") }
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
            if isListening {
                VoiceListeningBand(elapsed: voice.elapsed, transcript: voice.transcript)
            }

            // THE BAND: Share in the composer's tint disc, and the composer's
            // wide slot carrying the one verb available (prd §970).
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
            // Held New (prd §970): the mic is live when the sheet lands and
            // the keyboard stays down. Consumed on read, so a later tap of
            // New arrives typing, as it should.
            var speak = chrome.noteVoiceOnOpen
            chrome.noteVoiceOnOpen = false
            #if DEBUG
            // `-noteVoice YES` — land speaking, for the screen sweep. The
            // simulator has no microphone, so a pass shows the band and the
            // Stop key, never a transcript.
            if UserDefaults.standard.bool(forKey: "noteVoice") {
                NSLog("[Casberi] noteVoice: raised")
                speak = true
            }
            #endif
            if speak { startListening() } else { focused = true }
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

    /// The one verb available (prd §970), the composer's foot rule applied to
    /// the note: Stop while listening, Done once there are words, else the
    /// mic. A quiet Done over an empty field was §83's dead control — it
    /// closed and kept nothing, which the chevron already does.
    @ViewBuilder
    private var wideKey: some View {
        if isListening {
            AgentWideKey(title: String(localized: "Stop"), glyph: "stop.fill", tone: .tint) {
                DSHaptic.tap()
                endDictation()
            }
        } else if hasDraft {
            AgentWideKey(title: String(localized: "Done"), tone: .ink) {
                DSHaptic.tap()
                keepAndClose()
            }
        } else {
            AgentWideKey(glyph: "mic", tone: .ink, spoken: String(localized: "Speak a note")) {
                DSHaptic.tap()
                startListening()
            }
        }
    }

    // MARK: - Speaking

    /// Start listening. The keyboard goes down first: the band draws where
    /// the field's words will land, and a keyboard over a live mic is two
    /// ways to write at once.
    private func startListening() {
        focused = false
        Task { await voice.start() }
    }

    /// End a dictation: the words go to the field and the keyboard rises
    /// over them. READ THE TRANSCRIPT FIRST — `VoiceCapture.stop` clears it
    /// in a `defer` and returns nil under `keep: false` (the composer's own
    /// near-miss, §581c). Spoken words are added after anything typed, so a
    /// note begun by hand and finished aloud keeps both.
    private func endDictation() {
        let spoken = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = voice.stop(keep: false)
        guard !spoken.isEmpty else { return }
        draft = hasDraft ? draft.trimmingCharacters(in: .whitespacesAndNewlines) + " " + spoken : spoken
        focused = true
    }

    // MARK: - Keeping

    /// Keep the words as a note thing — `Capture.thing`'s own shape (a URL is
    /// a link, everything else a note), under the person's own source — then
    /// close. Empty words close and keep nothing.
    private func keepAndClose() {
        // Pulled down mid-sentence: what was heard is kept, as what was typed
        // is — dismiss keeps (§969), and the band showed every word as it
        // landed.
        if isListening { endDictation() }
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
