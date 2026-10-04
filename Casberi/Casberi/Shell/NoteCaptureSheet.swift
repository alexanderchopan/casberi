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
///
/// **A note of yours EDITS (prd §981, superseding §969's "never opened for
/// editing again").** The sheet's Edit disc (`Verb.Action.edit`) raises this
/// sheet over the note it came from: its words in the field, its picture in
/// the well. Closing it writes the change onto the SAME thing — its day, its
/// folder, its pin and its id stay — so the row keeps its place and nothing
/// lands twice. An edit emptied to nothing keeps the note as it was: deleting
/// is the long press's verb, confirmed, and a cleared field is not a delete.
/// The wide key never offers Record while editing, because a recording is a
/// new note and this sheet is changing an old one.
///
/// **A checklist, a scan and a link (prd §982).** The band's checklist key
/// turns the last line into an item (`○ `) or back, Return continues the
/// list and Return on an empty item ends it (`NoteChecklist`); the note keeps
/// items as `- [ ]`, which its sheet draws as circles you tick. The photo
/// disc became the attach disc: Choose a photo, Scan a document (Apple's
/// document camera — its first page is the picture, every page's words are
/// kept with the note), and Link something you keep, which writes
/// `[[its title]]` into the words.
///
/// **A note is ONE PAGE (prd §1099, superseding §983 item 4's page with three
/// keys).** A tap on a note of yours opens it here, not on a reading sheet
/// whose Edit then opened here: the note stands as its page — the title, the
/// words, a list's circles you tick — and a tap on the words brings the
/// keyboard. While nothing has the keyboard the words draw as a page
/// (`readBody`), so a circle is a key and a link is a link; the long press's
/// Edit lands typing. A VOICE NOTE opens here too: the player over its words,
/// which you can correct, and no title line, because its title is its first
/// words. Pin, Move, Lock, Share and Delete stay the long press's.
struct NoteCaptureSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Close the sheet; the words, if any, have already been kept.
    let onClose: () -> Void
    /// The kept note, for the shell's own landing (toast, flight).
    let onLand: (Thing) -> Void

    @State private var draft = ""
    /// Which line has the keyboard (prd §983): the title, or the words
    /// under it. Two fields over ONE `draft` — see `titleText`.
    @FocusState private var field: NoteField?
    private enum NoteField: Hashable { case title, body }
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
    /// The note being edited (prd §981), or nil for a new one. Read once, on
    /// appear, from `chrome.noteToEdit`.
    @State private var editing: Thing?
    /// The edited note's own picture has been read into the well. Until it
    /// has, a close keeps the stored picture rather than clearing it.
    @State private var editPictureRead = false
    /// The note opened to be READ first (prd §1099): from a row's tap, so no
    /// keyboard rises until a tap on the words asks for one. Read once, on
    /// appear, from `chrome.noteFocusOnOpen`.
    @State private var openedToRead = false
    /// The page has been asked for the keyboard (prd §1099). Focus cannot
    /// reach a field that is not drawn yet, so a tap on the read page first
    /// draws the fields, then focuses on the next pass (`write(_:)`); the
    /// keyboard going away draws the page again.
    @State private var typing = false
    /// The words as the page opened on them (prd §1099). A kept note is
    /// written back only when its words moved from these: opening and
    /// closing writes nothing, so a recording's full read or a sync landing
    /// while the page stood is never overwritten by the copy it opened with,
    /// and a note's own spelling (`* x`, `+ [X]`) is not normalised by a look.
    @State private var openedDraft: String?
    /// The document camera, and the words a scan read (prd §982) — kept with
    /// the note under what was typed, never poured into the field, where a
    /// page of receipt at the head rung would bury the sentence being written.
    @State private var scanOpen = false
    @State private var scanText: String?
    /// The sketch canvas (prd §1023): a drawing kept as the note's one picture.
    @State private var sketchOpen = false
    /// The link picker (prd §982).
    @State private var linkPickerOpen = false
    #if DEBUG
    /// The launch hooks have drafted their one note (see `onAppear`).
    private static var hooksSpent = false
    #endif

    /// Words to keep — with the checklist's bare circles taken out, so an
    /// item with nothing after it is not a note (prd §982).
    private var hasDraft: Bool {
        !NoteChecklist.stored(draft).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    /// Something to keep: words, or a picture alone (prd §974).
    private var hasContent: Bool { hasDraft || picture != nil }

    /// THE PAGE'S TWO LINES (prd §983), over one `draft`. Apple Notes sets
    /// the first line as the title and the rest as the note; a `TextField`
    /// sets one style, so the page is two fields — the title on one line,
    /// the words under it — and the draft is still one string, so keeping,
    /// sharing, the checklist and editing read it exactly as before.
    private var titleText: Binding<String> {
        Binding(get: { Self.split(draft).title },
                set: { new in draft = Self.join(new.replacingOccurrences(of: "\n", with: " "),
                                                Self.split(draft).body) })
    }
    private var bodyText: Binding<String> {
        Binding(get: { Self.split(draft).body },
                set: { new in draft = Self.join(Self.split(draft).title, new) })
    }
    static func split(_ draft: String) -> (title: String, body: String) {
        guard let cut = draft.firstIndex(of: "\n") else { return (draft, "") }
        return (String(draft[..<cut]), String(draft[draft.index(after: cut)...]))
    }
    static func join(_ title: String, _ body: String) -> String {
        body.isEmpty ? title : title + "\n" + body
    }

    /// The keyboard to the line being written: the title on a blank page,
    /// else the words.
    private func focusWords() {
        field = draft.isEmpty && !isVoiceNote ? .title : .body
    }

    /// The page is a voice note's (prd §1099): the player over its words, and
    /// no title line — a voice note's title is its first words.
    private var isVoiceNote: Bool { editing.map { $0.isLive && $0.kind == .voice } ?? false }

    /// The words draw as a page, not fields (prd §1099): a kept note while
    /// nothing has the keyboard. A new note is always being written.
    private var showsReadBody: Bool { editing != nil && !typing && field == nil && !isRecording }

    /// A tap on the read page: draw the fields, then give one the keyboard.
    private func write(_ target: NoteField) {
        typing = true
        Task { @MainActor in
            // A frame for the fields to be drawn, measured enough; a yield
            // alone can run before the swap lands.
            try? await Task.sleep(for: .milliseconds(50))
            field = target
        }
    }

    /// "28 September 2026 at 9:14 PM" — when the note was written, over the
    /// page, as Apple Notes dates it (prd §983). An edit keeps its own day.
    private var dateLine: String {
        let edited = editing.flatMap { $0.isLive ? $0.capturedAt : nil }
        return (edited ?? openedAt).formatted(date: .long, time: .shortened)
    }
    @State private var openedAt = Date.now
    private var isRecording: Bool { voice.phase == .recording }

    /// The one explaining line (prd §748): what happens to the words, or,
    /// with the mic refused, the route to allowing it — the composer's own
    /// line, folded into the footnote so the screen keeps one sentence.
    private var footnote: Text {
        if voice.phase == .denied {
            return Text("No mic access. Allow Casberi in \(DS.settingsAppName)")
        }
        if isRecording { return Text("Kept in Notes when you stop") }
        if scanText != nil { return Text("Kept in Notes with the words on the page") }
        return Text("Kept in Notes when you close this")
    }

    /// The page draws its footnote only when it says what nothing else on the
    /// page does (prd §983, §748): the mic refused, a recording that keeps on
    /// Stop, a scan's words kept unseen. A blank page says nothing — it is a
    /// page.
    private var footnoteShown: Bool {
        voice.phase == .denied || isRecording || scanText != nil
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
            .overlay {
                // The page's date (prd §983) — a fact, not a control.
                Text(dateLine)
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
                    .padding(.horizontal, 56)
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s3)

            // THE PAGE (prd §983, superseding §969's heading-34 well): the
            // picture, the title on one line, the words under it — no box,
            // because the note is the page and not a card on it.
            page

            if footnoteShown {
                DSFootnote(footnote)
                    .padding(.horizontal, DS.Space.s4 + DS.Space.s1)
                    .padding(.bottom, DS.Space.s2)
            }

            // The live mic, the composer's own band (prd §970), which settles
            // in as recording starts (prd §973).
            if isRecording {
                VoiceListeningBand(voice: voice, word: String(localized: "Recording"))
            }

            // THE BAR (prd §983): the page's four tools on one capsule —
            // Checklist, Attach, Link, Share — and the wide key beside it
            // carrying the one verb available (Record, Stop, Done, §971). It
            // stands over the keyboard, where Apple Notes keeps its tools.
            toolBar
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
                    // A photo in place of a scanned page: the page's words
                    // leave with it.
                    scanText = nil
                }
                pickerItem = nil
            }
        }
        // A set picture can come off, not just be replaced — the profile
        // photo's dialog, word for word. A scan's words go with its page.
        .confirmationDialog("Your photo", isPresented: $pictureDialogOpen) {
            Button("Change photo") { DSHaptic.tap(); pickerOpen = true }
            if DocumentScan.isSupported {
                Button("Scan a document") { DSHaptic.tap(); scanOpen = true }
            }
            Button("Sketch over it") { DSHaptic.tap(); sketchOpen = true }
            Button("Remove photo", role: .destructive) {
                DSHaptic.tap(); picture = nil; scanText = nil
            }
            Button("Cancel", role: .cancel) {}
        }
        // The keyboard went away: the page draws as a page again (prd §1099).
        .onChange(of: field) { _, now in
            if now == nil { typing = false }
        }
        // Return inside a list continues it; Return on an empty item ends it.
        .onChange(of: draft) { old, new in
            // A dash on the title line stays a dash: bullets are the words'.
            let inWords = isVoiceNote || new.contains("\n")
            if let next = NoteChecklist.continued(old: old, new: new)
                ?? (inWords ? NoteChecklist.bulleted(old: old, new: new) : nil) { draft = next }
        }
        .sheet(isPresented: $linkPickerOpen) {
            NoteLinkPicker { title in insertLink(title) }
        }
        // The canvas (prd §1023). Closing keeps: the drawing, flattened over
        // the page and whatever picture was under it, becomes the note's
        // picture through the one path a photo and a scan take.
        .sheet(isPresented: $sketchOpen) {
            NoteSketchSheet(over: picture?.image) { image in
                guard let image, let raw = image.jpegData(compressionQuality: 0.9) else { return }
                Task { @MainActor in
                    if let drawn = await NotePicture.prepared(raw) {
                        picture = drawn
                        scanText = nil
                        DSHaptic.success()
                    }
                }
            }
        }
        #if !targetEnvironment(macCatalyst)
        .fullScreenCover(isPresented: $scanOpen) {
            DocumentScannerView(onScan: { scan in
                scanOpen = false
                Task { @MainActor in
                    let read = await DocumentScan.read(scan)
                    if let page = read.picture { picture = page }
                    scanText = read.text
                    if read.picture != nil { DSHaptic.success() }
                }
            }, onCancel: { scanOpen = false })
            .ignoresSafeArea()
        }
        #endif
        .onAppear {
            // Held New (prd §970): recording when the sheet lands, keyboard
            // down. Consumed on read, so a later tap of New arrives typing,
            // as it should.
            var record = chrome.noteVoiceOnOpen
            chrome.noteVoiceOnOpen = false
            // The Edit disc (prd §981): open ON the note, consumed on read so
            // the next New arrives empty.
            let focusOnOpen = chrome.noteFocusOnOpen
            chrome.noteFocusOnOpen = true
            if let id = chrome.noteToEdit {
                chrome.noteToEdit = nil
                if let note = Self.note(id, in: modelContext) {
                    editing = note
                    openedToRead = !focusOnOpen
                    // A kept list opens as circles (prd §982).
                    draft = NoteChecklist.editable(note.content)
                    openedDraft = draft
                    // The picture through the one off-main decode, never a
                    // bitmap made here (`row-cost-audit.py`).
                    Task { @MainActor in
                        if picture == nil,
                           let pixels = await StoredPixels.prepared(for: note),
                           note.isLive, let bytes = note.previewImageData {
                            picture = NotePicture(bytes: bytes, image: pixels.image)
                        }
                        editPictureRead = true
                    }
                    record = false
                }
            }
            #if DEBUG
            // The hooks draft the FIRST new note of the launch. A launch
            // argument stays set for the whole process, so unguarded every
            // Edit opened on the hook's words and kept them over the note,
            // and every later New arrived pre-filled.
            if editing == nil, !Self.hooksSpent {
                Self.hooksSpent = true
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
                // `-noteDraft "<text>"` — land with words already written (prd
                // §982), `○ ` items included, because a simulator booted by
                // `simctl` draws no keyboard to type them with.
                if let words = UserDefaults.standard.string(forKey: "noteDraft"), !words.isEmpty {
                    NSLog("[Casberi] noteDraft: %d characters", words.count)
                    draft = words.replacingOccurrences(of: "\\n", with: "\n")
                }
                if UserDefaults.standard.bool(forKey: "notePicture"),
                   let drawn = NotePicture.drawnSample() {
                    NSLog("[Casberi] notePicture: attached %d bytes", drawn.bytes.count)
                    picture = drawn
                }
            }
            #endif
            if record {
                startRecording()
            } else if openedToRead {
                // Opened from its row (prd §1099): the page, read; the
                // keyboard waits for a tap on the words.
            } else if editing != nil {
                // The long press's Edit lands typing: the fields first (focus
                // cannot reach a field not drawn), and the thing sheet is
                // still leaving when this lands — a field focused under a
                // presented sheet raises no keyboard.
                typing = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    focusWords()
                }
            } else {
                focusWords()
            }
        }
        #if DEBUG
        // `-noteType "…"` — type the note character by character, then keep
        // and close, for a screen recording of the whole capture (the
        // composer's `-composerType`, on the sheet that keeps).
        .task {
            guard let text = UserDefaults.standard.string(forKey: "noteType") else { return }
            try? await Task.sleep(for: .milliseconds(900))
            for ch in text {
                draft.append(ch)
                try? await Task.sleep(for: .milliseconds(ch == " " ? 90 : 60))
            }
            try? await Task.sleep(for: .milliseconds(1100))
            NSLog("[Casberi] noteType: kept %d characters", draft.count)
            DSHaptic.tap()
            keepAndClose()
        }
        #endif
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
        return hasContent || editing != nil ? .done : .record
    }

    // MARK: - The picture (prd §974)

    /// The page (prd §983): the picture, the title, the words.
    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                // THE PICTURE (prd §974): above the words, in the lead's
                // well — the order the sheet under the note keeps.
                if let picture {
                    pictureWell(picture)
                        .padding(.bottom, DS.Space.s1)
                        .transition(.opacity)
                }
                if isVoiceNote, let editing, editing.isLive {
                    NoteVoicePlayer(thing: editing)
                        .padding(.horizontal, -DS.Space.s4)
                }
                if showsReadBody {
                    readBody
                } else {
                    if !isVoiceNote {
                        TextField(String(localized: "Title"), text: titleText)
                            .dsText(.heading34)
                            .foregroundStyle(DS.textPrimary)
                            .tint(DS.tint)
                            .focused($field, equals: .title)
                            .textFieldStyle(.plain)
                            .submitLabel(.next)
                            // Return on the title goes to the words, as in Notes.
                            .onSubmit { field = .body }
                    }
                    TextField(String(localized: "Note"), text: isVoiceNote ? $draft : bodyText, axis: .vertical)
                        .dsText(.reading17)
                        .foregroundStyle(DS.textPrimary)
                        .tint(DS.tint)
                        .focused($field, equals: .body)
                        .textFieldStyle(.plain)
                        .submitLabel(.return)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, DSRoomChassis.leadInset)
            .padding(.top, DS.Space.s4)
            .padding(.bottom, DS.Space.s6)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// THE PAGE, READ (prd §1099): the note as it stands — the title, then
    /// each line of the words, an item as a circle you tick. A tap anywhere
    /// on the words gives them the keyboard; a tap on the title, the title.
    /// The same rungs the fields draw at, so the page does not jump when the
    /// keyboard comes.
    private var readBody: some View {
        let parts = Self.split(draft)
        let words = isVoiceNote ? draft : parts.body
        var ordinal = -1
        let lines: [(id: Int, text: String, item: Int?)] = words.components(separatedBy: "\n")
            .enumerated().map { i, line in
                let trimmed = line.drop(while: { $0 == " " })
                if trimmed.hasPrefix(NoteChecklist.editorMark) || trimmed.hasPrefix(NoteChecklist.doneEditorMark) {
                    ordinal += 1
                    return (i, line, ordinal)
                }
                return (i, line, nil)
            }
        return VStack(alignment: .leading, spacing: DS.Space.s4) {
            if !isVoiceNote {
                Text(verbatim: parts.title.isEmpty ? String(localized: "Title") : parts.title)
                    .dsText(.heading34)
                    .foregroundStyle(parts.title.isEmpty ? DS.textTertiary : DS.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { write(.title) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(Text("Edit the title"))
            }
            // THE PAGE'S RHYTHM (prd §1099): one line of words is its own
            // `Text`, so the gap between two is the rung's own leading
            // (`lineSpacing`) — 27pt a line, as the field draws them, where
            // `s1` stood them 24pt apart and the page read packed. An item
            // takes a little more, its circle being a key.
            VStack(alignment: .leading, spacing: DSTextStyle.reading17.lineSpacing) {
                if words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Note")
                        .dsText(.reading17)
                        .foregroundStyle(DS.textTertiary)
                } else {
                    ForEach(lines, id: \.id) { line in
                        if let item = line.item {
                            readItem(line.text, ordinal: item)
                                .padding(.vertical, DS.Space.s1)
                        } else if let words = NoteChecklist.bullet(line.text) {
                            readMarked("\u{2022}", words, indent: line.text.prefix(while: { $0 == " " }).count)
                        } else if let item = NoteChecklist.numbered(line.text) {
                            readMarked("\(item.number).", item.text,
                                       indent: line.text.prefix(while: { $0 == " " }).count)
                        } else if line.text.trimmingCharacters(in: .whitespaces).isEmpty {
                            Color.clear.frame(height: DS.Space.s2)
                        } else {
                            Text(ProseLinks.rendered(line.text))
                                .dsText(.reading17)
                                .foregroundStyle(DS.textPrimary)
                                .tint(DS.tint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture { write(.body) }
            // One stop for VoiceOver, the circles surviving as its actions.
            .dsTapCard()
            .accessibilityHint(Text("Edit the note"))
        }
    }

    /// A bullet or a numbered line on the read page (prd §1099): the mark in
    /// the column a circle takes, the words hanging beside it, so a wrapped
    /// line starts under its words and not under its dot.
    private func readMarked(_ mark: String, _ words: String, indent: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Text(verbatim: mark)
                .dsText(.reading17)
                .foregroundStyle(DS.textSecondary)
                .monospacedDigit()
                .frame(minWidth: 22, alignment: .center)
            Text(ProseLinks.rendered(words))
                .dsText(.reading17)
                .foregroundStyle(DS.textPrimary)
                .tint(DS.tint)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(min(indent, 8)) * 4)
    }

    /// One item on the read page: the circle is a key that ticks it (the one
    /// write a kept note always took, §982), the words beside it. A ticked
    /// item fades, as Apple Notes fades it.
    private func readItem(_ line: String, ordinal: Int) -> some View {
        let trimmed = line.drop(while: { $0 == " " })
        let done = trimmed.hasPrefix(NoteChecklist.doneEditorMark)
        let text = String(trimmed.dropFirst(NoteChecklist.editorMark.count))
        return HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Button {
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) {
                    if isVoiceNote {
                        draft = NoteChecklist.toggledEditor(draft, ordinal: ordinal)
                    } else {
                        bodyText.wrappedValue = NoteChecklist.toggledEditor(bodyText.wrappedValue,
                                                                            ordinal: ordinal)
                    }
                }
                // A tick is kept as it is made, as the box's is: the page
                // closing by any path must not be what saves it.
                if let editing { saveEdit(editing, quiet: true) }
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .dsSymbolSwap(done)
                    .dsGlyph(.body, weight: .regular)
                    .foregroundStyle(done ? DS.tint : DS.textSecondary)
                    // The circle stands in the words' column at their size,
                    // as the field's `○` did, so the page does not jump when
                    // the keyboard comes; the hand gets 44pt around it.
                    .frame(width: 22, height: 22)
                    .dsTapTarget(Circle())
                    .padding(-11)
            }
            .buttonStyle(PressSpring())
            .accessibilityLabel(Text(verbatim: text))
            .accessibilityValue(done ? Text("Done") : Text("Not done"))
            Text(ProseLinks.rendered(text))
                .dsText(.reading17)
                .foregroundStyle(done ? DS.textTertiary : DS.textPrimary)
                .strikethrough(done, color: DS.textTertiary)
                .tint(DS.tint)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The bar (prd §983): four tools on a capsule and the wide key.
    private var toolBar: some View {
        HStack(spacing: DS.Space.s2) {
            HStack(spacing: 0) {
                checklistDisc
                photoDisc
                linkKey
                shareKey
            }
            .padding(.horizontal, DS.Space.s1)
            .frame(height: AgentDestinationKeys.side)
            // The floating layer's glass (§8: glass on the floating layer
            // only) — the bar floats over the keyboard, as Notes' does.
            .dsGlass(cornerRadius: AgentDestinationKeys.side / 2)
            wideKey
        }
        .padding(.horizontal, DS.Space.s3)
        .padding(.top, DS.Space.s2)
        .padding(.bottom, DS.Space.s3)
    }

    /// Whether the bar's tools take a hand: not while recording, and not
    /// while Stop keeps — a voice note is its audio, and a key that did
    /// nothing would be §83's dead control.
    private var toolsLive: Bool { !isRecording && !stopping }

    /// One of the bar's tools (prd §983): a glyph on the bar's capsule, the
    /// 44pt target, ink when it acts, tertiary when it cannot, the tint when
    /// it is on.
    private func barGlyph(_ name: String, lit: Bool = false, live: Bool) -> some View {
        Image(systemName: name)
            .dsGlyph(.title, weight: .regular)
            .foregroundStyle(!live ? DS.textTertiary : lit ? DS.tint : DS.textPrimary)
            .frame(width: 48, height: AgentDestinationKeys.side)
            .contentShape(Rectangle())
            .animation(DS.Motion.standard, value: lit)
            .animation(DS.Motion.standard, value: live)
            .dsHover()
    }

    /// ATTACH (prd §983, was §982's attach disc): Choose a photo, and Scan a
    /// document where the device has a document camera. Link has its own
    /// key now. With a picture attached, Photo raises Change / Remove rather
    /// than a second picker over the first.
    private var photoDisc: some View {
        Menu {
            Button {
                DSHaptic.tap()
                if picture == nil { pickerOpen = true } else { pictureDialogOpen = true }
            } label: {
                Label(picture == nil ? "Choose a photo" : "Photo on this note",
                      systemImage: "photo")
            }
            if DocumentScan.isSupported {
                Button {
                    DSHaptic.tap()
                    scanOpen = true
                } label: {
                    Label("Scan a document", systemImage: "doc.viewfinder")
                }
            }
            Button {
                DSHaptic.tap()
                sketchOpen = true
            } label: {
                Label(picture == nil ? "Sketch" : "Sketch over it", systemImage: "pencil.and.outline")
            }
        } label: {
            barGlyph("paperclip", live: toolsLive && !isVoiceNote)
        }
        .menuStyle(.button)
        .buttonStyle(PressSpring())
        // A voice note is its audio (§974): no picture joins it.
        .disabled(!toolsLive || isVoiceNote)
        .accessibilityLabel(Text("Attach"))
    }

    /// LINK SOMETHING (prd §982), its own key since §983.
    private var linkKey: some View {
        Button {
            DSHaptic.tap()
            linkPickerOpen = true
        } label: {
            barGlyph("link", live: toolsLive)
        }
        .buttonStyle(PressSpring())
        .disabled(!toolsLive)
        .accessibilityLabel(Text("Link something"))
    }

    /// SHARE — the words to the system share sheet, where Apple Notes'
    /// extension is the one real door into Notes (§969). Greyed with nothing
    /// written: a share of nothing is §83's dead control.
    private var shareKey: some View {
        ShareLink(item: draft) {
            barGlyph("square.and.arrow.up", live: hasDraft && toolsLive)
        }
        .buttonStyle(PressSpring())
        .disabled(!hasDraft || !toolsLive)
        .accessibilityLabel(Text("Share the note"))
    }

    /// The CHECKLIST key (prd §982): the words' last line becomes an item,
    /// or stops being one — its glyph in the tint while the line being
    /// written is an item. It acts on the words under the title (§983).
    private var checklistDisc: some View {
        let words = isVoiceNote ? draft : Self.split(draft).body
        let lit = NoteChecklist.endsInItem(words)
        return Button {
            DSHaptic.selection()
            if isVoiceNote { draft = NoteChecklist.toggleLastLine(words) }
            else { bodyText.wrappedValue = NoteChecklist.toggleLastLine(words) }
            write(.body)
        } label: {
            barGlyph("checklist", lit: lit, live: toolsLive)
        }
        .buttonStyle(PressSpring())
        .disabled(!toolsLive)
        .accessibilityLabel(Text("Checklist"))
        .accessibilityAddTraits(lit ? [.isSelected] : [])
    }

    /// A picked link, written where the words end: `[[title]]`, with a space
    /// before it when the words need one — the title line on a blank page.
    private func insertLink(_ title: String) {
        let link = "[[\(title)]]"
        let parts = Self.split(draft)
        if parts.title.isEmpty && parts.body.isEmpty {
            titleText.wrappedValue = link
            write(.body)
            return
        }
        let words = parts.body
        if words.isEmpty || words.hasSuffix(" ") || words.hasSuffix("\n")
            || words.hasSuffix(NoteChecklist.editorMark) {
            bodyText.wrappedValue = words + link
        } else {
            bodyText.wrappedValue = words + " " + link
        }
        write(.body)
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
        field = nil
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
        let folder = filingFolder
        Task { @MainActor in
            if let thing = await Self.keepRecording(capture, in: context, folder: folder) { land(thing) }
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
    private static func keepRecording(_ voice: VoiceCapture, in context: ModelContext,
                                      folder: String?) async -> Thing? {
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
        thing.folder = folder
        // THE SPAN (prd §987): the note starts when the recording did and ends
        // now, so its length is `endAt − capturedAt` — the pair an event uses
        // for when it runs — and the row can say "0:42" with nothing decoded.
        if let bytes, let length = VoiceTranscribe.length(of: bytes) {
            let end = Date.now
            thing.capturedAt = end.addingTimeInterval(-length)
            thing.endAt = end
        }
        context.insert(thing)
        context.saveHonestly()
        SpotlightIndex.index([thing])
        // Its words, read back off the whole file with a time for each
        // (prd §987) — after it lands, so Stop never waits on it.
        Task { @MainActor in await VoiceHeal.settle(thing, in: context) }
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
        if let editing {
            saveEdit(editing)
            return
        }
        guard let thing = keptThing() else { return }
        thing.previewImageData = picture?.bytes
        thing.folder = filingFolder
        // What the note links (prd §982), so the thing it names shows it
        // under "Points at this".
        thing.wikilinks = NoteLinks.extract(from: thing.content)
        modelContext.insert(thing)
        modelContext.saveHonestly()
        SpotlightIndex.index([thing])
        onLand(thing)
    }

    /// Write the sheet onto the note it opened on (prd §981): the words the
    /// way a new note takes them (`Capture.thing`'s title and tags), the
    /// picture as it now stands. Its day, folder, pin and id are untouched.
    /// Nothing changed saves nothing; nothing left keeps the note as it was.
    private func saveEdit(_ note: Thing, quiet: Bool = false) {
        guard note.isLive else { return }
        let bytes = picture?.bytes ?? (editPictureRead ? nil : note.previewImageData)
        // The checklist's circles back to `- [ ]`, and a scan's words under
        // what was typed (prd §982) — the same body a new note keeps.
        let scanned = scanText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text = [NoteChecklist.stored(draft).trimmingCharacters(in: .whitespacesAndNewlines), scanned]
            .filter { !$0.isEmpty }.joined(separator: "\n\n")
        guard !text.isEmpty || bytes != nil else { return }
        let wordsMoved = draft != openedDraft || scanText != nil
        guard wordsMoved || bytes != note.previewImageData else { return }
        let sameWords = text == note.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sameWords || bytes != note.previewImageData else { return }
        if note.kind == .voice {
            // A voice note's words, corrected (prd §1099): its title follows
            // its first words, as a recording's does, and the mark keeps the
            // first full read (`VoiceHeal.rewrite`) from putting the
            // recognizer's words back over yours.
            guard !text.isEmpty else { return }
            note.content = text
            note.title = Self.titled(IngestSupport.titleLine(NoteChecklist.plain(
                text.components(separatedBy: "\n").first ?? text)), body: text)
            note.wikilinks = NoteLinks.extract(from: text)
            if !note.tags.contains(VoiceHeal.handEditedTag) { note.tags.append(VoiceHeal.handEditedTag) }
            note.embedding = nil
        } else if text.isEmpty {
            note.title = String(localized: "Photo")
            note.content = ""
        } else if let made = Capture.thing(from: text) {
            note.title = Self.titled(made.title, body: text)
            note.content = made.content
            note.wikilinks = NoteLinks.extract(from: made.content)
            for tag in made.tags where !note.tags.contains(tag) { note.tags.append(tag) }
        }
        if bytes != note.previewImageData {
            note.previewImageData = bytes
            StoredPixels.forget(note.id)
        }
        modelContext.saveHonestly()
        openedDraft = draft
        SpotlightIndex.index([note])
        CorpusSignal.shared.bump()
        if !quiet { chrome.flash(String(localized: "Saved"), tone: .success) }
    }

    /// The note an Edit disc named, if it is still here and still a note of
    /// yours — a sync may have deleted it between the tap and the raise.
    private static func note(_ id: UUID, in context: ModelContext) -> Thing? {
        var d = FetchDescriptor<Thing>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        guard let found = ((try? context.fetch(d)) ?? []).live.first,
              found.source == NoteSheetSource.keptSource,
              found.kind == .note || found.kind == .voice
        else { return nil }
        return found
    }

    /// The folder a note made now is filed in: the one standing open in the
    /// Notes room (prd §980), read when the note is KEPT — New tapped inside
    /// a folder makes a note in it.
    private var filingFolder: String? {
        chrome.notesScope == .folders ? chrome.notesFolder : nil
    }

    /// The note the words make, or the note a picture alone makes (prd
    /// §974): a picture with nothing written keeps a note titled "Photo",
    /// which is the lede a row needs and nothing the picture does not say.
    /// Nothing written and nothing attached keeps nothing.
    private func keptThing() -> Thing? {
        // The checklist's circles become `- [ ]` (prd §982), and a scan's
        // words go under what was typed.
        let words = NoteChecklist.stored(draft).trimmingCharacters(in: .whitespacesAndNewlines)
        let scanned = scanText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let body = [words, scanned].filter { !$0.isEmpty }.joined(separator: "\n\n")
        if !body.isEmpty, let thing = Capture.thing(from: body) {
            // A note is a note even when it holds a link: `Capture.thing`
            // turns a URL into a link thing for the paste chip's sake, and a
            // link thing would stand outside this room's membership
            // (`Pinboard.isNote`).
            thing.kind = .note
            thing.title = Self.titled(thing.title, body: body)
            return thing
        }
        guard picture != nil else { return nil }
        return Thing(kind: .note, title: String(localized: "Photo"),
                     source: NoteSheetSource.keptSource)
    }
}

extension NoteCaptureSheet {
    /// The title a body makes (prd §982): a list's first item names the note
    /// without its box, and a link in the first line names its thing, not
    /// its brackets.
    static func titled(_ title: String, body: String) -> String {
        var out = title
        let opening = body.components(separatedBy: "\n").first ?? ""
        if NoteChecklist.task(opening) != nil || NoteChecklist.bullet(opening) != nil {
            out = IngestSupport.titleLine(NoteChecklist.plain(opening))
        }
        return out.replacingOccurrences(of: "[[", with: "")
            .replacingOccurrences(of: "]]", with: "")
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
    /// Handed in: this sits above the `.environment(chrome)` RootShell's
    /// children get.
    let chrome: ShellChrome

    func body(content: Content) -> some View {
        content
            .onChange(of: newNote) { _, _ in
                // A page already up is not rebuilt, so its `onAppear` would
                // never consume a second request — and the next New would
                // open that note (prd §1099). The page standing keeps the hand.
                guard !noteOpen else {
                    chrome.noteToEdit = nil
                    chrome.noteFocusOnOpen = true
                    chrome.noteVoiceOnOpen = false
                    return
                }
                withAnimation(DS.Motion.standard) { noteOpen = true }
            }
            #if DEBUG
            // `-noteType "…"` raises the sheet after `-noteTypeDelay` seconds
            // (default 2.5), so a recording opens on the room first.
            .task {
                guard UserDefaults.standard.string(forKey: "noteType") != nil else { return }
                let set = UserDefaults.standard.double(forKey: "noteTypeDelay")
                let delay = set > 0 ? set : 2.5
                try? await Task.sleep(for: .seconds(delay))
                withAnimation(DS.Motion.standard) { noteOpen = true }
            }
            #endif
            .onAppear {
                if UserDefaults.standard.bool(forKey: "openNote") {
                    NSLog("[Casberi] openNote: raised")
                    noteOpen = true
                }
            }
    }
}

