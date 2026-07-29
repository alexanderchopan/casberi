import Foundation
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit

/// The voice-recording Live Activity (§15 polish): recording state only —
/// the start time drives the timer. The transcript never rides the lock
/// screen (privacy default, goal 6).
struct VoiceRecordingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startedAt: Date
    }
}
#endif
