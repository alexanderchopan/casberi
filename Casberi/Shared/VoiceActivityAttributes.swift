import Foundation

extension Notification.Name {
    /// The Live Activity's Stop, pressed (`StopVoiceRecordingIntent`): the
    /// surface recording keeps what it has and stops, as its own Stop does.
    static let voiceRecordingStopRequested = Notification.Name("casberi.voiceRecordingStopRequested")
}

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
import AppIntents

/// The voice-recording Live Activity (§15 polish): recording state only —
/// the start time drives the timer. The transcript never rides the lock
/// screen (privacy default, goal 6).
struct VoiceRecordingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startedAt: Date
    }
}

/// **THE STOP ON THE LOCK SCREEN STOPS (2026-10-16, user: "i was able to stop
/// the live activity recording by swiping to clear, but not by clicking the
/// stop button").** The glyph was a picture over a band that opened the app,
/// §83's dead control. A `LiveActivityIntent` runs in the app's process: it
/// tells the recording surface to keep and stop, then ends every recording
/// activity itself, so one a crash left standing ends too.
struct StopVoiceRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop recording"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(name: .voiceRecordingStopRequested, object: nil)
        }
        for activity in Activity<VoiceRecordingAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        return .result()
    }
}
#endif
