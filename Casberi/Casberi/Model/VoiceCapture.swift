import Foundation
import AVFoundation
import Speech
import Observation
import ActivityKit

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
    private var activity: Activity<VoiceRecordingAttributes>?

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

        // The live transcript — the engine taps the mic in parallel.
        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognizer = SFSpeechRecognizer()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        try? engine.start()
        audioEngine = engine
        recognitionRequest = request
        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, _ in
            // Pull the plain String out here so nothing non-Sendable crosses
            // the hop back to the main actor.
            guard let text = result?.bestTranscription.formattedString else { return }
            Task { @MainActor in self?.transcript = text }
        }

        phase = .recording
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.elapsed += 0.5
        }

        // The Live Activity (§15): recording state only — the lock screen
        // and Dynamic Island get the timer, never the words.
        if ActivityAuthorizationInfo().areActivitiesEnabled {
            activity = try? Activity.request(
                attributes: VoiceRecordingAttributes(),
                content: .init(state: .init(startedAt: .now), staleDate: nil))
        }
    }

    /// Stops and returns the finished piece: transcript + the audio file ref.
    /// Discard (`keep: false`) removes the file.
    @discardableResult
    func stop(keep: Bool = true) -> (transcript: String, sourceRef: String)? {
        timer?.invalidate(); timer = nil
        if let activity {
            let done = activity
            Task { await done.end(nil, dismissalPolicy: .immediate) }
            self.activity = nil
        }
        recorder?.stop()
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
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
}
