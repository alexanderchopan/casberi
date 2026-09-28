import SwiftUI

/// THE LIVE MIC, as one band (prd §970, §973): a breathing dot, the clock, a
/// word, the live level strip, and the transcript as it grows. Drawn above the
/// foot of the composer and above the band of the note sheet — one shape, so a
/// person who has spoken to the agent knows what recording a note looks like,
/// and a fix here reaches both (§720's class: a shape drawn by hand in two
/// places is fixed in one).
///
/// It takes the host's own `VoiceCapture` and reads it HERE, so the clock and
/// the level — ten changes a second — re-render this band and nothing above
/// it. The composer's body is large; it read `elapsed` itself until §973.
///
/// **The motion is the app's own, and every piece of it honours Reduce Motion
/// (prd §973).** The dot `breathing()` — the one loop the app keeps for
/// something real in progress — where it used to step its opacity off the
/// clock with no guard. The band arrives with `settleIn()`. The strip rides a
/// short linear tween between samples, and the clock rolls its digits; under
/// Reduce Motion both simply change.
struct VoiceListeningBand: View {
    let voice: VoiceCapture
    /// "Listening" where the words become a question (the composer),
    /// "Recording" where they become a kept voice note (the note sheet).
    var word: String = String(localized: "Listening")

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s2) {
                Circle().fill(DS.destructive).frame(width: 8, height: 8)
                    .breathing()
                Text(String(format: "%d:%02d", Int(voice.elapsed) / 60, Int(voice.elapsed) % 60))
                    .dsText(.label12).foregroundStyle(DS.textSecondary)
                    // Tabular, because it rolls — see `LiveTimeText` (prd §586).
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(reduceMotion ? nil : DS.Motion.standard, value: Int(voice.elapsed))
                Text(word)
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                Spacer(minLength: DS.Space.s2)
                levelStrip
            }
            if !voice.transcript.isEmpty {
                Text(voice.transcript)
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .lineLimit(4)
            }
        }
        .padding(DS.Space.s3)
        .dsWell()
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s3)
        .settleIn()
        .accessibilityElement(children: .combine)
    }

    /// The live level, in the PLAYER's bar anatomy (`VoiceContent`: 3pt tint
    /// capsules, 2pt apart, 6...22pt tall) — so the shape you watch while
    /// recording is the shape the kept note plays back with. Flat at the
    /// start, the player's own even placeholder, filling from the trailing
    /// edge.
    private var levelStrip: some View {
        HStack(spacing: 2) {
            ForEach(Array(voice.levels.enumerated()), id: \.offset) { _, level in
                Capsule().fill(DS.tint).frame(width: 3, height: 6 + level * 16)
            }
        }
        .frame(height: 22)
        .animation(reduceMotion ? nil : .linear(duration: 0.1), value: voice.levels)
        .accessibilityHidden(true)
    }
}
