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
            recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, _ in
                // Pull the plain String out here so nothing non-Sendable crosses
                // the hop back to the main actor.
                guard let text = result?.bestTranscription.formattedString else { return }
                Task { @MainActor in self?.transcript = text }
            }
        }

        engine.prepare()
        try? engine.start()
        audioEngine = engine

        phase = .recording
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.elapsed += 0.5
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

    /// Stops and returns the finished piece: transcript + the audio file ref.
    /// Discard (`keep: false`) removes the file.
    @discardableResult
    func stop(keep: Bool = true) -> (transcript: String, sourceRef: String)? {
        timer?.invalidate(); timer = nil
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

    init(transcriber: SpeechTranscriber, onTranscript: @escaping (String) -> Void) async throws {
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
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        finalized += text
                        onTranscript(finalized)
                    } else {
                        onTranscript(finalized + text)
                    }
                }
            } catch {
                // A finalize/cancel tears the results sequence down — the
                // same quiet-stop shape as the legacy task's cancel().
            }
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
}
