import Foundation
import AVFoundation
import Speech
import Observation
#if !targetEnvironment(macCatalyst)
import ActivityKit
#endif

/// Voice capture (M6, local half) — the mic records to a file, speech
/// recognition writes the transcript live, and Save lands a voice thing whose
/// sourceRef names the audio file. The permission asks arrive on first use,
/// in context (the same law as Photos).
///
/// @MainActor is load-bearing: `start()` is async, and without isolation its
/// body resumed on a background executor after the permission awaits — so the
/// `Timer.scheduledTimer` below was added to a thread with no running run loop
/// and never fired (the clock froze at 0:00), and the recorder/engine were
/// spun up off-main. Pinning the whole capture to the main actor keeps the
/// timer live and the state transitions ordered.
@Observable
@MainActor
final class VoiceCapture: NSObject {

    enum Phase: Equatable {
        case idle
        case recording
        case denied          // mic or speech declined — the UI states the route
    }

    private(set) var phase: Phase = .idle
    private(set) var transcript = ""
    private(set) var elapsed: TimeInterval = 0
    /// The system took the microphone mid-recording — a call, an alarm, Siri
    /// (prd §972). Capture has STOPPED when this turns true; the caller keeps
    /// what was recorded rather than leaving a clock that runs over nothing.
    private(set) var interrupted = false

    /// The recognizer handed over its last words (prd §972). Set by the final
    /// result, or by the recognizer ending on an error; read by `settle`.
    @ObservationIgnored private var recognitionDone = false
    @ObservationIgnored private var settling = false
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?

    private var recorder: AVAudioRecorder?
    private var recognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var audioEngine: AVAudioEngine?
    private var timer: Timer?
    private var fileID = UUID()
    #if !targetEnvironment(macCatalyst)
    private var activity: Activity<VoiceRecordingAttributes>?
    #endif
    /// The iOS 26 SpeechAnalyzer path, boxed untyped: `VoiceCapture` itself
    /// must compile and run below iOS 26 (deployment target 18), so it can't
    /// carry a directly-typed `ModernSpeechSession?` stored property — that
    /// would bake iOS-26-only type metadata into the class layout
    /// unconditionally. Cast back to `ModernSpeechSession` only inside
    /// `if #available(iOS 26.0, *)` blocks.
    private var modernSession: Any?

    /// Where voice audio lives — one file per thing, named by its id.
    /// `nonisolated`: a pure filesystem path, read from main and background
    /// alike (the store mirror, the account sheet's cleanup), so it must not
    /// inherit the class's main-actor isolation.
    nonisolated static var folder: URL {
        let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("voice", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    nonisolated static func audioURL(for ref: String) -> URL? {
        guard ref.hasPrefix("voice:") else { return nil }
        return folder.appendingPathComponent(String(ref.dropFirst(6)))
    }

    // MARK: - Session

    func start() async {
        // Both asks, in order, in context.
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard micOK else { phase = .denied; return }
        let speechStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard speechStatus == .authorized else { phase = .denied; return }

        fileID = UUID()
        transcript = ""
        elapsed = 0
        interrupted = false
        recognitionDone = false

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        // The file — what the thing will keep.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        recorder = try? AVAudioRecorder(
            url: Self.folder.appendingPathComponent("\(fileID.uuidString).m4a"),
            settings: settings)
        recorder?.record()

        // The live transcript — the engine taps the mic in parallel. iOS 26
        // prefers SpeechAnalyzer/SpeechTranscriber (faster, more accurate,
        // on-device); SFSpeechRecognizer is the fallback below it and on
        // older OSes. The modern path only engages when its model is
        // ALREADY installed (`AssetInventory.status`) — never triggers a
        // download mid-recording, so "record" always starts instantly
        // regardless of which path answers.
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        var usingModern = false
        if #available(iOS 26.0, *) {
            usingModern = await startModernTranscription()
        }

        if usingModern {
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                if #available(iOS 26.0, *) {
                    (self?.modernSession as? ModernSpeechSession)?.append(buffer)
                }
            }
        } else {
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            recognizer = SFSpeechRecognizer()
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            recognitionRequest = request
            recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                // Pull the plain String out here so nothing non-Sendable crosses
                // the hop back to the main actor. The final result and an error
                // both END the recognition, and `settle` waits on that (prd
                // §972) — carried in the same hop as the words, so the flag can
                // never land before the text it vouches for.
                let text = result?.bestTranscription.formattedString
                let ended = (result?.isFinal ?? false) || error != nil
                guard text != nil || ended else { return }
                Task { @MainActor in
                    if let text { self?.transcript = text }
                    if ended { self?.recognitionDone = true }
                }
            }
        }

        engine.prepare()
        try? engine.start()
        audioEngine = engine

        phase = .recording
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.elapsed += 0.5
        }

        // A call or an alarm takes the microphone and capture stops under us
        // (prd §972). Say so, so the caller keeps what was recorded instead of
        // drawing a live clock — and a Live Activity — over silence.
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            MainActor.assumeIsolated { self?.interrupted = true }
        }

        // The Live Activity (§15): recording state only — the lock screen
        // and Dynamic Island get the timer, never the words. Unavailable on
        // Mac Catalyst (no Dynamic Island/lock screen there).
        #if !targetEnvironment(macCatalyst)
        if ActivityAuthorizationInfo().areActivitiesEnabled {
            activity = try? Activity.request(
                attributes: VoiceRecordingAttributes(),
                content: .init(state: .init(startedAt: .now), staleDate: nil))
        }
        #endif
    }

    /// End the INPUT and give the recognizer a bounded moment to hand over its
    /// final words (prd §972), before `stop` reads them.
    ///
    /// `stop` alone takes whatever partial result exists at that instant: the
    /// legacy task is cancelled before its final result arrives, and the iOS 26
    /// analyzer finalizes after the words were already read. With no review
    /// step between Stop and a kept voice note, the clipped last words became
    /// the title. The wait is capped (a second by default) so a recognizer that
    /// never answers can only cost that second, never hang the Stop key.
    ///
    /// Returns false when there was nothing to settle (not recording) or a
    /// settle is already running — a second Stop tap must not race the first
    /// into `stop` and read the unfinished words.
    @discardableResult
    func settle(within timeout: TimeInterval = 1.0) async -> Bool {
        guard phase == .recording, !settling else { return false }
        settling = true
        defer { settling = false }
        timer?.invalidate(); timer = nil
        recorder?.stop()                    // finalizes the file
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil                   // `stop` must not remove the tap twice
        if #available(iOS 26.0, *), let session = modernSession as? ModernSpeechSession {
            modernSession = nil             // `stop` must not finish it twice
            Task { await session.finishInput() }
        } else if let request = recognitionRequest {
            request.endAudio()
        } else {
            return true
        }
        let deadline = Date().addingTimeInterval(timeout)
        while !recognitionDone, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    /// Stops and returns the finished piece: transcript + the audio file ref.
    /// Discard (`keep: false`) removes the file.
    @discardableResult
    func stop(keep: Bool = true) -> (transcript: String, sourceRef: String)? {
        timer?.invalidate(); timer = nil
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        #if !targetEnvironment(macCatalyst)
        if let activity {
            let done = activity
            Task { await done.end(nil, dismissalPolicy: .immediate) }
            self.activity = nil
        }
        #endif
        recorder?.stop()
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        if #available(iOS 26.0, *), let session = modernSession as? ModernSpeechSession {
            Task { await session.finish() }
            modernSession = nil
        } else {
            recognitionRequest?.endAudio()
            recognitionTask?.cancel()
        }
        audioEngine = nil; recognitionRequest = nil; recognitionTask = nil; recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        defer { phase = .idle; transcript = ""; elapsed = 0 }
        guard keep else {
            try? FileManager.default.removeItem(
                at: Self.folder.appendingPathComponent("\(fileID.uuidString).m4a"))
            return nil
        }
        return (transcript, "voice:\(fileID.uuidString).m4a")
    }

    /// Tries the iOS 26 path. Bounded to what's already installed
    /// (`AssetInventory.status`) — never kicks off a model download here, so
    /// a fresh device with no on-device speech model yet falls back to
    /// `SFSpeechRecognizer` for that session rather than stalling "record"
    /// on a fetch. Returns false on ANY setup failure, in which case `start()`
    /// falls straight through to the legacy path — the two never both run.
    @available(iOS 26.0, *)
    private func startModernTranscription() async -> Bool {
        let transcriber = SpeechTranscriber(locale: .current, preset: .progressiveTranscription)
        let status = await AssetInventory.status(forModules: [transcriber])
        guard status == .installed else {
            NSLog("VoiceCapture: SpeechAnalyzer model not installed (status=%@) — using SFSpeechRecognizer this session",
                  String(describing: status))
            return false
        }
        do {
            let session = try await ModernSpeechSession(transcriber: transcriber) { [weak self] text in
                Task { @MainActor in self?.transcript = text }
            } onEnded: { [weak self] text in
                // The last words and the flag in ONE hop (prd §972): two
                // separate main-actor tasks carry no ordering promise.
                Task { @MainActor in
                    if !text.isEmpty { self?.transcript = text }
                    self?.recognitionDone = true
                }
            }
            modernSession = session
            NSLog("VoiceCapture: SpeechAnalyzer path engaged")
            return true
        } catch {
            return false
        }
    }
}

/// The iOS 26 transcription session — one `SpeechAnalyzer` fed by an
/// `AsyncStream` the audio tap yields buffers into, its `SpeechTranscriber`
/// results consumed on a background `Task` that hops the plain `String` text
/// back to `VoiceCapture` on the main actor (same shape as the legacy
/// `SFSpeechRecognitionTask` callback it replaces).
@available(iOS 26.0, *)
private final class ModernSpeechSession {
    private let analyzer: SpeechAnalyzer
    private let inputContinuation: AsyncStream<AnalyzerInput>.Continuation
    private var resultsTask: Task<Void, Never>?

    init(transcriber: SpeechTranscriber, onTranscript: @escaping (String) -> Void,
         onEnded: @escaping (String) -> Void) async throws {
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputContinuation = continuation
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        try await analyzer.start(inputSequence: stream)
        resultsTask = Task {
            // `.progressiveTranscription` reports a stream of chunk-scoped
            // results (each carries its own `range`/`resultsFinalizationTime`,
            // not the whole-so-far transcript the legacy
            // SFSpeechRecognitionResult.bestTranscription always was) — so a
            // final result's text is APPENDED to what's already finalized,
            // never used to overwrite it, or the saved note would end up
            // holding only the last spoken chunk. A non-final (volatile)
            // result previews on top without being committed.
            var finalized = ""
            // What the person last SAW — finalized plus any volatile tail — so
            // a torn-down sequence never hands `onEnded` fewer words than the
            // band was showing.
            var latest = ""
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        finalized += text
                        latest = finalized
                    } else {
                        latest = finalized + text
                    }
                    onTranscript(latest)
                }
            } catch {
                // A finalize/cancel tears the results sequence down — the
                // same quiet-stop shape as the legacy task's cancel().
            }
            // The sequence ended — finalized through the end of input, or torn
            // down. Either way these are the last words (prd §972).
            onEnded(latest)
        }
    }

    /// Called from the audio tap's callback (an arbitrary, non-main thread)
    /// — `AsyncStream.Continuation.yield` is safe to call concurrently from
    /// any thread, same contract the legacy path's `request.append` relied on.
    func append(_ buffer: AVAudioPCMBuffer) {
        inputContinuation.yield(AnalyzerInput(buffer: buffer))
    }

    func finish() async {
        inputContinuation.finish()
        resultsTask?.cancel()
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
    }

    /// End the input and let the analyzer finalize what it heard, WITHOUT
    /// cancelling the results loop (prd §972) — so the final result reaches
    /// `onEnded` instead of being torn down with the sequence, as `finish`
    /// does for a discard.
    func finishInput() async {
        inputContinuation.finish()
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
    }
}
