import SwiftUI

/// THE LIVE MIC, as one band (prd §970, 2026-09-28): a pulsing dot, the
/// clock, "Listening", and the transcript as it grows. Drawn above the foot
/// of the composer and above the band of the note sheet — one shape, so a
/// person who has spoken to the agent knows what speaking to a note looks
/// like, and a fix here reaches both (§720's class: a shape drawn by hand in
/// two places is fixed in one).
///
/// It reads two values, never the `VoiceCapture` itself, so the sheet and
/// the composer each keep their own mic.
struct VoiceListeningBand: View {
    let elapsed: TimeInterval
    let transcript: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s2) {
                Circle().fill(DS.destructive).frame(width: 8, height: 8)
                    .opacity(0.4 + 0.6 * abs(sin(elapsed * 2)))
                Text(String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60))
                    .dsText(.label12).foregroundStyle(DS.textSecondary)
                    // Tabular, because it rolls — see `LiveTimeText` (prd §586).
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("Listening")
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                Spacer()
            }
            if !transcript.isEmpty {
                Text(transcript)
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .lineLimit(4)
            }
        }
        .padding(DS.Space.s3)
        .dsWell()
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s3)
        .animation(DS.Motion.standard, value: elapsed)
    }
}
