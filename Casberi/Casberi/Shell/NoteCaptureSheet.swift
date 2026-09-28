import SwiftUI
import SwiftData
import PhotosUI

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
///
/// **Kept whole (prd §972).** Stop waits up to a second for the recognizer's
/// last words, the audio is stored once, and a call that takes the mic or a
/// sheet closed by another path keeps what was recorded. A voice note's
/// source is `You`, like every note here; there is no "Voice" room.
///
/// **A note can hold ONE picture (prd §974).** The band's photo disc opens
/// the system picker; the picked picture is drawn above the words, in the
/// lead's well, the way the sheet under the note draws it (`NoteEntryPhoto`).
/// It is stored on the note in `previewImageData` at the app's one stored
/// size — the 480pt / q0.7 JPEG every screenshot, folder image and journal
/// photograph already is — so the room's row, the lede's cover and the
/// sheet draw it with nothing new. Tapping the picture asks Change or
/// Remove, the profile photo's own dialog. A picture with no words keeps a
/// note titled "Photo"; a picture is words' company, never a recording's —
/// with one attached the wide key says Done, and while recording the disc
/// is greyed, because a voice note is its audio.
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
    /// Stop was pressed and the recording is being kept (prd §972): the
    /// recognizer gets up to a second for its last words, and a second tap in
    /// that second must not keep the recording twice.
    @State private var stopping = false
    /// Bumped when Record meets a refused microphone (prd §973): the key
    /// shakes and the phone says so, the app's feel for a failure you caused.
    @State private var refusals = 0
    /// The note's one picture (prd §974): the bytes the note will store and
    /// the bitmap the well draws, decoded once at pick time.
    @State private var picture: NotePicture?
    @State private var pickerOpen = false
    @State private var pickerItem: PhotosPickerItem?
    /// Change or Remove, over a picture already attached.
    @State private var pictureDialogOpen = false

    private var hasDraft: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    /// Something to keep: words, or a picture alone (prd §974).
    private var hasContent: Bool { hasDraft || picture != nil }
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
                .accessibilityLabel(hasContent ? Text("Keep the note and go back") : Text("Back to your things"))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s3)

            Spacer(minLength: 0)

            // THE PICTURE (prd §974): above the words, in the lead's well —
            // the order the sheet under the note keeps (`NoteEntryPhoto`),
            // so what you see here is what you will open.
            if let picture {
                pictureWell(picture)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.bottom, DS.Space.s3)
                    .transition(.opacity)
            }

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

            // The live mic, the composer's own band (prd §970), which settles
            // in as recording starts (prd §973).
            if isRecording {
                VoiceListeningBand(voice: voice, word: String(localized: "Recording"))
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
                        // Waking, the app's way (prd §973): the fill crossfades
                        // (§966) and the disc gives the armed pop the other
                        // sheets give a button that comes alive with the
                        // field's first character.
                        .animation(DS.Motion.standard, value: hasDraft)
                        .armedPop(hasDraft)
                        .dsHover()
                }
                .buttonStyle(PressSpring())
                // A share of nothing is §83's dead control: the disc stays,
                // greyed, and does not open.
                .disabled(!hasDraft)
                .accessibilityLabel(Text("Share the note"))
                photoDisc
                wideKey
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s4)
            .padding(.bottom, DS.Space.s4)
        }
        .background(DS.page.ignoresSafeArea())
        // The band arriving and leaving moves the rows above it; that move
        // eases with the rest of the sheet's changes (prd §973).
        .animation(reduceMotion ? nil : DS.Motion.standard, value: isRecording)
        .animation(reduceMotion ? nil : DS.Motion.standard, value: picture != nil)
        // The system picker (prd §974), the profile photo's own door.
        .photosPicker(isPresented: $pickerOpen, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { @MainActor in
                if let raw = try? await item.loadTransferable(type: Data.self),
                   let attached = await NotePicture.prepared(raw) {
                    picture = attached
                }
                pickerItem = nil
            }
        }
        // A set picture can come off, not just be replaced — the profile
        // photo's dialog, word for word.
        .confirmationDialog("Your photo", isPresented: $pictureDialogOpen) {
            Button("Change photo") { DSHaptic.tap(); pickerOpen = true }
            Button("Remove photo", role: .destructive) { DSHaptic.tap(); picture = nil }
            Button("Cancel", role: .cancel) {}
        }
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
            // `-notePicture YES` — land with a picture attached (prd §974),
            // for the screen sweep: the simulator's photo library needs a
            // hand to pick from, so the hook draws one and attaches it the
            // way the picker would.
            if UserDefaults.standard.bool(forKey: "notePicture"),
               let drawn = NotePicture.drawnSample() {
                NSLog("[Casberi] notePicture: attached %d bytes", drawn.bytes.count)
                picture = drawn
            }
            #endif
            if record { startRecording() } else { focused = true }
        }
        // A call or an alarm took the microphone (prd §972): capture stopped,
        // so keep what was recorded and close, rather than leave a clock
        // running over nothing.
        .onChange(of: voice.interrupted) { _, now in
            if now { stopAndKeep() }
        }
        // The sheet went away by some path that is not its own (prd §972):
        // never leave the mic live behind it. What was recorded is kept, as a
        // pull-down keeps it.
        .onDisappear {
            if isRecording { stopAndKeep(closing: false) }
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

    /// What the wide key says right now (prd §971, §973).
    private enum KeyVerb: Equatable { case record, stop, keeping, done }

    private var keyVerb: KeyVerb {
        if stopping { return .keeping }
        if isRecording { return .stop }
        return hasContent ? .done : .record
    }

    // MARK: - The picture (prd §974)

    /// The band's photo disc: the composer's disc anatomy in ink, live
    /// whenever the note could take a picture. With one attached it raises
    /// Change / Remove rather than a second picker over the first. Greyed
    /// while recording, as Share is over nothing: a voice note is its audio,
    /// and a disc that did nothing would be §83's dead control.
    private var photoDisc: some View {
        let live = !isRecording && !stopping
        return Button {
            DSHaptic.tap()
            if picture == nil { pickerOpen = true } else { pictureDialogOpen = true }
        } label: {
            Image(systemName: "photo")
                .dsGlyph(.feature, weight: .regular)
                .foregroundStyle(live ? DS.textPrimary : DS.textTertiary)
                .frame(width: AgentDestinationKeys.side, height: AgentDestinationKeys.side)
                .background(DS.surfaceRaised, in: Circle())
                .dsTapTarget(Circle())
                .animation(DS.Motion.standard, value: live)
                .dsHover()
        }
        .buttonStyle(PressSpring())
        .disabled(!live)
        .accessibilityLabel(picture == nil ? Text("Add a photo") : Text("Photo on this note"))
    }

    /// The picked picture, pinned to the lead's height and clipped — never
    /// left to report its own size upward (the `scaledToFill`-in-a-ZStack
    /// trap). A tile, so it presses (`PressSpring`) and its tap asks Change or
    /// Remove.
    private func pictureWell(_ picture: NotePicture) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous)
        return Button {
            DSHaptic.selection()
            pictureDialogOpen = true
        } label: {
            Color.clear
                .frame(height: DSRoomChassis.leadHeight)
                .frame(maxWidth: .infinity)
                .overlay {
                    Image(uiImage: picture.image)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
                .clipShape(shape)
                .contentShape(shape)
                .dsHover()
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(Text("Photo on this note"))
    }

    /// The one verb available (prd §971), the composer's foot rule applied to
    /// the note: Stop while recording, Done once there are words, else
    /// Record — the voice kind's own waveform, so the key says what it makes.
    /// A quiet Done over an empty field was §83's dead control — it closed and
    /// kept nothing, which the chevron already does.
    ///
    /// **ONE key, never four (prd §973).** The verb changes and the key stays,
    /// so waveform MORPHS to stop (§867's rule for a glyph that changes), and
    /// while Stop keeps — up to a second, the recognizer settling — stop
    /// morphs to a check: the mark a copy leaves on its own disc, here the
    /// mark of a note kept. The toast then says where it went.
    private var wideKey: some View {
        let verb = keyVerb
        let title: String? = switch verb {
            case .stop:     String(localized: "Stop")
            case .done:     String(localized: "Done")
            case .record, .keeping: nil
        }
        let glyph: String? = switch verb {
            case .record:  "waveform"
            case .stop:    "stop.fill"
            case .keeping: "checkmark"
            case .done:    nil
        }
        let spoken: String? = switch verb {
            case .record:  String(localized: "Record a voice note")
            case .keeping: String(localized: "Keeping the voice note")
            case .stop, .done: nil
        }
        return AgentWideKey(title: title, glyph: glyph,
                            tone: (verb == .stop || verb == .keeping) ? .tint : .ink,
                            spoken: spoken) {
            switch verb {
            case .record:  DSHaptic.tap(); startRecording()
            case .stop:    DSHaptic.tap(); stopAndKeep()
            case .done:    DSHaptic.tap(); keepAndClose()
            case .keeping: break   // already keeping; the check says so
            }
        }
        .shake(on: refusals)
        .animation(DS.Motion.standard, value: verb)
    }

    // MARK: - Recording

    /// Start recording. The keyboard goes down first: the band draws where
    /// the field stood, and a keyboard over a live mic is two ways to write
    /// at once. The permission asks arrive here, in context.
    private func startRecording() {
        focused = false
        let capture = voice
        Task { @MainActor in
            await capture.start()
            // Refused — now or on an earlier ask, which iOS does not repeat
            // (prd §973). Without this the tap did nothing you could see or
            // feel; the footnote already names the way to allow it. A shake
            // with its failure buzz, as the connect screens do for a failed
            // proof.
            if capture.phase == .denied {
                refusals += 1
                DSHaptic.failure()
            }
        }
    }

    /// Stop, and keep what was recorded as a VOICE thing under `You`, then
    /// close (or not, when the sheet is already gone).
    ///
    /// Everything the work needs is captured BEFORE the task starts — the
    /// recorder, the store, the two closures — because the disappear path runs
    /// it after the view has left the hierarchy, where reading `@State` hands
    /// back a fresh, idle recorder instead of the live one.
    private func stopAndKeep(closing: Bool = true) {
        guard !stopping else { return }
        stopping = true
        let capture = voice, context = modelContext, land = onLand, close = onClose
        Task { @MainActor in
            if let thing = await Self.keepRecording(capture, in: context) { land(thing) }
            if closing { close() }
        }
    }

    /// The recording, kept: the recognizer settles first (its last words,
    /// bounded to a second, prd §972), then `stop(keep: true)` hands over the
    /// transcript and the file. The thing carries the transcript as its words,
    /// the first line as its title, and the audio in its synced field — a
    /// voice note on one phone only is half a feature.
    ///
    /// **The audio is stored ONCE (prd §972).** The store has held voice audio
    /// since the 2026-07-07 move, which read each loose file in and deleted
    /// it; keeping the file as well left a second copy the move never runs
    /// again to clear, and it outlived the note when the note was deleted. The
    /// file goes once its bytes are in the store, and stays only if they could
    /// not be read, so the local player still has something to play.
    ///
    /// Nothing heard and nothing recorded lands nothing.
    @MainActor
    private static func keepRecording(_ voice: VoiceCapture, in context: ModelContext) async -> Thing? {
        await voice.settle()
        guard let piece = voice.stop(keep: true) else { return nil }
        let words = piece.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = VoiceCapture.audioURL(for: piece.sourceRef)
        let bytes = url.flatMap { try? Data(contentsOf: $0) }
        if bytes != nil, let url { try? FileManager.default.removeItem(at: url) }
        guard !words.isEmpty || (bytes?.isEmpty == false) else {
            if let url { try? FileManager.default.removeItem(at: url) }
            return nil
        }
        let thing = Thing(
            kind: .voice,
            title: words.isEmpty ? String(localized: "Voice note") : IngestSupport.titleLine(words),
            content: words,
            source: NoteSheetSource.keptSource,
            sourceRef: piece.sourceRef)
        thing.audio = bytes
        context.insert(thing)
        context.saveHonestly()
        SpotlightIndex.index([thing])
        return thing
    }

    // MARK: - Keeping

    /// Keep the words as a note thing — `Capture.thing`'s own shape (a URL is
    /// a link, everything else a note), under the person's own source — then
    /// close. Empty words close and keep nothing.
    private func keepAndClose() {
        // Pulled down mid-recording: the recording is kept, as typed words
        // are — dismiss keeps (§969).
        if isRecording { stopAndKeep(); return }
        defer { onClose() }
        guard let thing = keptThing() else { return }
        thing.previewImageData = picture?.bytes
        modelContext.insert(thing)
        modelContext.saveHonestly()
        SpotlightIndex.index([thing])
        onLand(thing)
    }

    /// The note the words make, or the note a picture alone makes (prd
    /// §974): a picture with nothing written keeps a note titled "Photo",
    /// which is the lede a row needs and nothing the picture does not say.
    /// Nothing written and nothing attached keeps nothing.
    private func keptThing() -> Thing? {
        if hasDraft, let thing = Capture.thing(from: draft) {
            // A note is a note even when it holds a link: `Capture.thing`
            // turns a URL into a link thing for the paste chip's sake, and a
            // link thing would stand outside this room's membership
            // (`Pinboard.isNote`).
            thing.kind = .note
            return thing
        }
        guard picture != nil else { return nil }
        return Thing(kind: .note, title: String(localized: "Photo"),
                     source: NoteSheetSource.keptSource)
    }
}

/// A picture attached to a note being written (prd §974): the bytes the note
/// stores and the bitmap the sheet draws, made once when the picker answers.
struct NotePicture: Equatable {
    let bytes: Data
    let image: UIImage

    /// The picker's bytes, brought to the app's ONE stored picture size —
    /// `ImportMedia.thumbnail(data:)`, the 480pt / q0.7 JPEG every other
    /// `previewImageData` writer makes — decoded off the main actor. A
    /// picture that will not decode attaches nothing.
    static func prepared(_ raw: Data) async -> NotePicture? {
        guard let bytes = await ImportMedia.thumbnail(data: raw),
              let image = UIImage(data: bytes) else { return nil }
        return NotePicture(bytes: bytes, image: image)
    }

    #if DEBUG
    /// A drawn picture for `-notePicture YES`: a two-colour gradient at the
    /// stored size, so the sweep sees the well, the disc's state and the kept
    /// note's row without a photo library to pick from.
    static func drawnSample() -> NotePicture? {
        let size = CGSize(width: 480, height: 320)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let colors = [UIColor.systemPink.cgColor, UIColor.systemIndigo.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(
                    gradient, start: .zero,
                    end: CGPoint(x: size.width, y: size.height), options: [])
            }
        }
        guard let bytes = image.jpegData(compressionQuality: 0.7) else { return nil }
        return NotePicture(bytes: bytes, image: image)
    }
    #endif
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
