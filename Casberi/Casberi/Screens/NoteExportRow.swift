import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// EXPORT NOTES (the note-export ruling, 2026-09-29) — the Notes room's
/// folder list ends with it: every note you wrote, as a folder of Markdown
/// saved wherever Files can reach (`NoteExport` plans it). A verb, so no
/// chevron; the system's folder exporter picks the place.
///
/// Self-contained — its state and its `.fileExporter` — so `FeedScreen`'s
/// body, already at the type-checker's edge, gains one row and nothing more.
struct NoteExportRow: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ShellChrome.self) private var chrome
    @State private var document: NoteExportDocument?
    @State private var exporting = false

    var body: some View {
        DSPushRow(title: Text("Export notes"), opens: false, action: prepare) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: DS.Mark.row * 0.54, weight: .regular))
                .foregroundStyle(DS.textSecondary)
                .frame(width: DS.Mark.row, height: DS.Mark.row)
                .accessibilityHidden(true)
        }
        .fileExporter(isPresented: $exporting, document: document,
                      contentType: .folder,
                      defaultFilename: String(localized: "Casberi Notes")) { result in
            finished(result)
        }
    }

    /// Read the notes into values, then raise the exporter. Nothing to
    /// export says so rather than saving an empty folder.
    private func prepare() {
        let made = NoteExportDocument.make(in: modelContext)
        guard made.noteCount > 0 else {
            chrome.flash(made.plan.lockedLeftOut > 0
                         ? String(localized: "Locked notes stay in Casberi")
                         : String(localized: "No notes to export yet"))
            return
        }
        document = made
        exporting = true
    }

    private func finished(_ result: Result<URL, Error>) {
        guard let document else { return }
        switch result {
        case .success:
            let count = document.noteCount
            let words = count == 1
                ? String(localized: "Exported 1 note")
                : String(localized: "Exported \(count) notes")
            // One sentence (§748): what left, and what did not.
            chrome.flash(document.plan.lockedLeftOut > 0
                         ? words + String(localized: ". Locked notes stayed.")
                         : words, tone: .success)
        case .failure(let error):
            // Cancelled is not a failure anybody needs told about.
            if (error as? CocoaError)?.code != .userCancelled {
                chrome.flash(String(localized: "Couldn't export"), tone: .failure)
            }
        }
        self.document = nil
    }
}

/// The export as a folder `fileExporter` can write: the plan's files with
/// the pictures' and recordings' bytes joined in. Values only — built on the
/// main actor from the store, never holding a model.
struct NoteExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }

    let plan: NoteExport.Plan
    /// Each note's pictures, first first.
    let pictures: [Int: [Data]]
    let audio: [Int: Data]

    /// How many notes the folder holds (their `.md` files).
    var noteCount: Int {
        plan.files.filter { if case .markdown = $0.body { return true } else { return false } }.count
    }

    init(plan: NoteExport.Plan, pictures: [Int: [Data]], audio: [Int: Data]) {
        self.plan = plan
        self.pictures = pictures
        self.audio = audio
    }

    init(configuration: ReadConfiguration) throws {
        // Written, never read: the app does not import its own export.
        throw CocoaError(.featureUnsupported)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let root = FileWrapper(directoryWithFileWrappers: [:])
        var directories: [String: FileWrapper] = [:]
        for file in plan.files {
            let data: Data?
            switch file.body {
            case .markdown(let text): data = Data(text.utf8)
            case .picture(let note, let index):
                data = pictures[note].flatMap { $0.indices.contains(index) ? $0[index] : nil }
            case .audio(let note):    data = audio[note]
            }
            guard let data, let name = file.path.last else { continue }
            let leaf = FileWrapper(regularFileWithContents: data)
            leaf.preferredFilename = name
            if file.path.count > 1 {
                let folder = file.path[0]
                let directory = directories[folder] ?? {
                    let made = FileWrapper(directoryWithFileWrappers: [:])
                    made.preferredFilename = folder
                    root.addFileWrapper(made)
                    return made
                }()
                directories[folder] = directory
                directory.addFileWrapper(leaf)
            } else {
                root.addFileWrapper(leaf)
            }
        }
        return root
    }

    /// Every note of yours, newest first, read into values.
    @MainActor
    static func make(in context: ModelContext) -> NoteExportDocument {
        let source = NoteSheetSource.keptSource
        let descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate<Thing> { $0.source == source },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        let mine = ((try? context.fetch(descriptor)) ?? []).live.filter(Pinboard.isNote)
        var notes: [NoteExport.Note] = []
        var pictures: [Int: [Data]] = [:]
        var audio: [Int: Data] = [:]
        for thing in mine {
            let locked = NoteLock.isLocked(thing)
            let index = notes.count
            let all = locked ? [] : NotePictures.all(first: thing.previewImageData,
                                                     rest: thing.notePictures)
            let sound = (locked || thing.kind != .voice) ? nil : thing.audio
            if !all.isEmpty { pictures[index] = all }
            if let sound { audio[index] = sound }
            notes.append(NoteExport.Note(
                title: thing.title, content: locked ? "" : thing.content,
                folder: thing.folder, created: thing.capturedAt,
                isVoice: thing.kind == .voice, isLocked: locked,
                hasPicture: !all.isEmpty, hasAudio: sound != nil,
                morePictures: max(0, all.count - 1)))
        }
        return NoteExportDocument(plan: NoteExport.plan(notes), pictures: pictures, audio: audio)
    }
}
