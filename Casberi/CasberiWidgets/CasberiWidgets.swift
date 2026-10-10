import WidgetKit
import SwiftUI
import SwiftData
import AppIntents
#if !targetEnvironment(macCatalyst)
import ActivityKit
#endif

/// Casberi's tiles (P8: awareness lands; the corpus speaks without being
/// asked). Every one of them reads the shared store or the app group — none
/// computes anything, none reaches the network, and none can (see
/// `WidgetPayload`).
///
/// Four widgets, each a small tile (prd §1210, §1223): your newest notes, the
/// wallet drawing the line the balance card draws, the Feed's contents in Feed
/// order, and your Markets watchlist. The Today widget (§877) went with the
/// ask (2026-10-01) and the Category widget with §1210. Plus two Control
/// Center buttons (capture and a Quick Note) and the Live Activities below.
@main
struct CasberiWidgets: WidgetBundle {
    var body: some Widget {
        NotesWidget()
        WalletWidget()
        FeedWidget()
        WatchlistWidget()
        ComposeControl()
        // A QUICK NOTE from anywhere (prd §982): Control Center, the Lock
        // Screen and the Action button, onto the note sheet.
        NoteControl()
        #if !targetEnvironment(macCatalyst)
        VoiceRecordingActivity()
        ImportActivity()
        MoneyActivity()
        #endif
    }
}

/// While a voice note records, the lock screen and Dynamic Island show the
/// recording state — waveform, elapsed time — and tapping returns to the
/// composer. Recording state only; the words stay in the app (goal 6).
/// Unavailable on Mac Catalyst (no Live Activities/Dynamic Island there).
#if !targetEnvironment(macCatalyst)
struct VoiceRecordingActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VoiceRecordingAttributes.self) { context in
            // Lock screen band.
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .dsGlyph(.title, weight: .medium)
                    .foregroundStyle(WidgetChrome.recording)
                Text("Recording")
                    .dsText(.widgetChrome15)
                Spacer()
                Text(timerInterval: context.state.startedAt...Date(
                    timeInterval: 60 * 60, since: context.state.startedAt))
                    .dsText(.widgetChrome15)
                    .monospacedDigit()
                    .frame(maxWidth: 56)
                Image(systemName: "stop.circle.fill")
                    .dsGlyph(.title)
                    .foregroundStyle(WidgetChrome.recording)
            }
            .padding(14)
            .activityBackgroundTint(.black.opacity(0.8))
            .widgetURL(URL(string: "casberi://home"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "waveform")
                        .dsGlyph(.title, weight: .medium)
                        .foregroundStyle(WidgetChrome.recording)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.startedAt...Date(
                        timeInterval: 60 * 60, since: context.state.startedAt))
                        .dsText(.heading17)
                        .monospacedDigit()
                        .frame(maxWidth: 60)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("Recording")
                        .dsText(.widgetChrome15)
                }
            } compactLeading: {
                Image(systemName: "waveform")
                    .foregroundStyle(WidgetChrome.recording)
            } compactTrailing: {
                Text(timerInterval: context.state.startedAt...Date(
                    timeInterval: 60 * 60, since: context.state.startedAt))
                    .dsText(.widgetTimer13)
                    .monospacedDigit()
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "waveform")
                    .foregroundStyle(WidgetChrome.recording)
            }
            .widgetURL(URL(string: "casberi://home"))
        }
    }
}
#endif

/// Control Center's capture button — one press anywhere, the composer opens.
/// The intent leaves a flag in the app group; the shell reads it on activation.
struct OpenComposerIntent: AppIntent {
    static let title: LocalizedStringResource = "Save a thing"
    static let description = IntentDescription("Opens Casberi's composer.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: SharedStore.appGroup)?
            .set(true, forKey: "compose.request")
        return .result()
    }
}

struct ComposeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "casberi.compose") {
            ControlWidgetButton(action: OpenComposerIntent()) {
                Label("Save a thing", systemImage: "plus.circle.fill")
            }
        }
        .displayName("Save to Casberi")
        .description("Opens the composer.")
    }
}

/// A QUICK NOTE (prd §982) — Apple Notes' Quick Note, for Casberi: one press
/// in Control Center, on the Lock Screen or on the Action button, and the note
/// sheet is up with the keyboard. The same flag-and-activation door as
/// `OpenComposerIntent` (`note.request`, drained by `RootShell` on
/// activation), because a control's intent cannot reach the running shell
/// directly and a cold launch has no shell yet.
struct NewNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "New note"
    static let description = IntentDescription("Opens a new note in Casberi.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: SharedStore.appGroup)?
            .set(true, forKey: "note.request")
        return .result()
    }
}

struct NoteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "casberi.note") {
            ControlWidgetButton(action: NewNoteIntent()) {
                Label("New note", systemImage: "square.and.pencil")
            }
        }
        .displayName("Casberi note")
        .description("Writes a new note from anywhere.")
    }
}
