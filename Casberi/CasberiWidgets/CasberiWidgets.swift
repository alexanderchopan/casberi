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
/// Two widgets since prd §877 (2026-09-22). Today is one list — what needs
/// you, who replied, what landed — where "Your day" and "Needs you" were two
/// tiles, one showing a single line and the other usually empty. The wallet
/// draws the line the balance card draws. Plus one Control Center button
/// (capture) and the Live Activities below.
@main
struct CasberiWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        // `KeptAskWidget` is GONE from the bundle (prd §697b, 2026-09-11):
        // every tile on it opened an ask, so with the ask deprecated the
        // whole widget is a wall of doors onto nothing. A placed one goes to
        // the system's "unable to load" placeholder, which is the cost the
        // user took knowingly ("get rid of it. i doubt any user is using
        // it"). The file stays in the target and stays compiling, so the
        // widget returns with the flag.
        WalletWidget()
        ComposeControl()
        // `BriefControl` — the Control Center button onto the daily brief —
        // is GONE with the ask (prd §697b). `ComposeControl` stays: it opens
        // the CAPTURE surface, which outlives the ask.
        #if !targetEnvironment(macCatalyst)
        VoiceRecordingActivity()
        ImportActivity()
        MoneyActivity()
        VibenetUnlockActivity()
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
        .description("Opens the composer from Control Center.")
    }
}

/// The READING half of the same pair (2026-08-14). Capture had a button
/// anywhere on the device and the brief — the app's one composed answer to
/// "what's going on" — could only be reached by opening the app and tapping.
///
/// It reuses `"brief.request"`, the flag the Home Screen quick action already
/// writes and `RootShell.openBriefIfRequested` already reads (§377). One door,
/// so a second entrance can't drift into a second behaviour — and notably that
/// door is the one whose delivery half was broken for eleven days, which is
/// another reason not to invent a third.
struct OpenBriefIntent: AppIntent {
    static let title: LocalizedStringResource = "What's going on"
    static let description = IntentDescription("Opens Casberi's daily brief.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: SharedStore.appGroup)?
            .set(true, forKey: "brief.request")
        return .result()
    }
}

struct BriefControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "casberi.brief") {
            ControlWidgetButton(action: OpenBriefIntent()) {
                Label("What's going on", systemImage: "sparkles")
            }
        }
        .displayName("Casberi brief")
        .description("Opens your day from Control Center.")
    }
}
