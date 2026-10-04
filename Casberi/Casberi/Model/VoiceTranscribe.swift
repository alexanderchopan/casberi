import Foundation
import AVFoundation
import Speech
import SwiftData

/// A KEPT RECORDING, READ BACK OFF ITS FILE (prd §987) — the words and when
/// each was said. `VoiceCapture` transcribes live, off the microphone, a chunk
/// at a time; this reads the whole file once it exists, with the whole
/// recording as context, and carries a time for every word.
///
/// ON THE DEVICE ONLY, and iOS 26 only: `SpeechAnalyzer` is on-device by
/// design, and this runs in the background over recordings nobody just asked
/// to send anywhere, so the older recognizer — whose live path may use
/// Apple's server — is never asked. It asks for no permission either.
enum VoiceTranscribe {

    /// The analyzer's transcriber for this device's language, asked for word
    /// times.
    @available(iOS 26.0, *)
    private static func transcriber() async -> SpeechTranscriber {
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) ?? .current
        return SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                 reportingOptions: [], attributeOptions: [.audioTimeRange])
    }

    /// Is the iOS 26 model on this device? `VoiceCapture` falls back to the
    /// older recognizer for a whole recording when it is not.
    static func analyzerInstalled() async -> Bool {
        guard #available(iOS 26.0, *) else { return false }
        return await AssetInventory.status(forModules: [await transcriber()]) == .installed
    }

    /// Ask the system for the iOS 26 model (prd §987). Only from the heal, and
    /// only when there is a voice note to read with it: `VoiceCapture` never
    /// downloads mid-recording, so without this a phone that recorded its
    /// first note on the older recognizer could stay on it. Once installed,
    /// the next recording takes the newer path too.
    static func installAnalyzer() async -> Bool {
        guard #available(iOS 26.0, *) else { return false }
        let modules: [any SpeechModule] = [await transcriber()]
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                try await request.downloadAndInstall()
            }
        } catch {
            NSLog("VoiceTranscribe: model install failed — %@", String(describing: error))
            return false
        }
        return await AssetInventory.status(forModules: modules) == .installed
    }

    /// The recording's words and their times, or nil when this device has
    /// no iOS 26 model (or it heard nothing). The older recognizer is not
    /// asked: its on-device reading would seldom match the words the live
    /// path kept, and a time is only worth drawing over the words it times.
    static func timeline(file url: URL) async -> VoiceTimeline? {
        guard #available(iOS 26.0, *), await analyzerInstalled() else { return nil }
        return await analyzerTimeline(file: url)
    }

    @available(iOS 26.0, *)
    private static func analyzerTimeline(file url: URL) async -> VoiceTimeline? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let transcriber = await transcriber()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        // The results are read from before the file starts, so nothing the
        // analyzer finalizes early is missed.
        let reader = Task { () -> [(text: String, start: Double?, end: Double?)] in
            var runs: [(text: String, start: Double?, end: Double?)] = []
            do {
                for try await result in transcriber.results where result.isFinal {
                    let text = result.text
                    for run in text.runs {
                        let range = run[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self]
                        runs.append((String(text[run.range].characters),
                                     range.map { $0.start.seconds },
                                     range.map { $0.end.seconds }))
                    }
                }
            } catch {
                // A torn-down sequence ends the read with what it had.
            }
            return runs
        }
        do {
            try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        } catch {
            reader.cancel()
            return nil
        }
        return VoiceTimeline.build(runs: await reader.value)
    }

    /// A recording's length off its bytes.
    static func length(of data: Data) -> Double? {
        guard let player = try? AVAudioPlayer(data: data), player.duration > 0 else { return nil }
        return player.duration
    }
}

/// THE VOICE NOTE, SETTLED (prd §987): its length stamped as a span
/// (`capturedAt`…`endAt`, the pair an event already uses for when it runs),
/// its words and their times read back off the audio, and — once per note per
/// device — the live words replaced by the analyzer's reading of the whole
/// file, which hears each sentence with the whole recording as context.
///
/// Runs for a note the moment it is kept, and at launch for the notes that
/// came before (or arrived from another device), a few at a time.
@MainActor
enum VoiceHeal {

    /// The tag a voice note carries once its words were corrected by hand on
    /// its page (prd §1099). A tag, because it syncs with the note and no
    /// surface draws tags.
    static let handEditedTag = "voice-edited"

    struct Outcome { var lengths = 0, timed = 0, rewritten = 0 }

    /// Your voice notes. `audio` is NOT read here: it is external storage,
    /// and reading it for every note to filter would load every recording
    /// at every launch. Each pass below reads it only for the notes it acts on.
    private static func candidates(in context: ModelContext) -> [Thing] {
        let source = NoteSheetSource.keptSource
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == source })
        return ((try? context.fetch(descriptor)) ?? []).filter { $0.isLive && $0.kind == .voice }
    }

    /// The launch pass. Every missing length (cheap: a header read), then at
    /// most `limit` notes' words, and only when something here can read them.
    /// The demo reaches nothing and has no recordings, so it is skipped.
    @discardableResult
    static func run(context: ModelContext, limit: Int = 6) async -> Outcome {
        var outcome = Outcome()
        guard !DemoMode.isActive else { return outcome }
        await GestureGate.idle()
        let notes = candidates(in: context)
        for thing in notes where thing.endAt == nil {
            if stampLength(thing) { outcome.lengths += 1 }
        }
        if outcome.lengths > 0 { _ = context.saveHonestly() }

        // Unread here, with audio to read (a demo note or one whose bytes
        // never arrived has none, and must not take a slot below).
        let unread = notes.filter { $0.isLive && !VoiceTimeline.isCached($0.id) && $0.audio != nil }
        guard !unread.isEmpty else { return outcome }
        if !(await VoiceTranscribe.analyzerInstalled()) { _ = await VoiceTranscribe.installAnalyzer() }
        guard await VoiceTranscribe.analyzerInstalled() else { return outcome }
        for thing in unread.prefix(limit) {
            await GestureGate.idle()
            let step = await settle(thing, in: context)
            outcome.timed += step.timed
            outcome.rewritten += step.rewritten
        }
        return outcome
    }

    /// One note: its length, then its words. Called right after a recording
    /// is kept, and by `run`.
    @discardableResult
    static func settle(_ thing: Thing, in context: ModelContext) async -> Outcome {
        var outcome = Outcome()
        guard thing.isLive, thing.kind == .voice, let bytes = thing.audio else { return outcome }
        if thing.endAt == nil, stampLength(thing) { outcome.lengths = 1 }
        let id = thing.id
        let firstRead = !VoiceTimeline.isCached(id)
        guard firstRead else {
            if outcome.lengths > 0 { _ = context.saveHonestly() }
            return outcome
        }
        let read: VoiceTimeline? = await Task.detached(priority: .utility) {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("voice-read-\(id.uuidString).m4a")
            defer { try? FileManager.default.removeItem(at: url) }
            guard (try? bytes.write(to: url)) != nil else { return nil }
            return await VoiceTranscribe.timeline(file: url)
        }.value
        guard let read, thing.isLive else {
            if outcome.lengths > 0, thing.isLive { _ = context.saveHonestly() }
            return outcome
        }
        VoiceTimeline.store(read, for: id)
        outcome.timed = 1
        if rewrite(thing, with: read.text) { outcome.rewritten = 1 }
        if outcome.lengths + outcome.rewritten > 0 { _ = context.saveHonestly() }
        if outcome.rewritten > 0 { SpotlightIndex.index([thing]) }
        return outcome
    }

    /// The span, off the bytes. A note kept by this build has it already.
    private static func stampLength(_ thing: Thing) -> Bool {
        guard let bytes = thing.audio, let length = VoiceTranscribe.length(of: bytes) else { return false }
        thing.endAt = thing.capturedAt.addingTimeInterval(length)
        return true
    }

    /// The analyzer's reading of the whole file replaces the live, chunked
    /// one — ONCE, on the first read this device makes (the cache is the
    /// ledger), so two devices can each write at most once and converge.
    /// `VoiceTimeline.replaces` says when (never for fewer than half as many
    /// words). The title follows only when it was made from the old words.
    static func rewrite(_ thing: Thing, with words: String) -> Bool {
        // Words you corrected on the note's page (prd §1099) are yours: the
        // recognizer never writes over them, on this device or another.
        guard !thing.tags.contains(handEditedTag) else { return false }
        let old = thing.content
        guard VoiceTimeline.replaces(old, with: words) else { return false }
        let new = words.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleWasWords = old.isEmpty
            || thing.title == IngestSupport.titleLine(old)
            || thing.title == String(localized: "Voice note")
        thing.content = new
        if titleWasWords { thing.title = IngestSupport.titleLine(new) }
        thing.embedding = nil          // the index reads the new words
        return true
    }
}
