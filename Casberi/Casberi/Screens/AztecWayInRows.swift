import SwiftUI

/// **THE WAY INTO AZTEC, AS STEPS (prd §1820).** Under Move's sentence when
/// Shield will not take the deposit yet: Add a co-signer, Reach a score of
/// 20, Send through Shield. A step done wears the confirm check and its
/// fact; the next one Aztec's ink; the rest wait in grey. The rows of a
/// send's steps (`PrivateStepRows`), so a way in reads as a send does.
struct AztecWayInRows: View {
    let coSigner: String?
    let score: Int
    let threshold: Int
    let maxUSD: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ForEach(AztecWayIn.Step.allCases, id: \.self) { step in
                row(step, phase: AztecWayIn.phase(step, coSigner: coSigner, score: score, threshold: threshold))
            }
        }
    }

    private func title(_ step: AztecWayIn.Step, done: Bool) -> String {
        switch step {
        case .coSigner: done ? String(localized: "Co-signer added") : String(localized: "Add a co-signer")
        case .score: done ? String(localized: "Score \(score)") : String(localized: "Reach a score of \(threshold)")
        case .send: String(localized: "Send through Shield")
        }
    }

    private func fact(_ step: AztecWayIn.Step) -> String? {
        switch step {
        case .coSigner: coSigner.map { AddressTail.short($0) } ?? String(localized: "Like MetaMask")
        // No co-signer yet: no score to show, and the title fits whole.
        case .score: coSigner == nil ? nil : AztecWayIn.progress(score, of: threshold)
        case .send: maxUSD.map { String(localized: "Up to \($0.formatted(.currency(code: "USD").precision(.fractionLength(0))))") }
        }
    }

    @ViewBuilder private func row(_ step: AztecWayIn.Step, phase: AztecWayIn.Phase) -> some View {
        HStack(spacing: DS.Space.s3) {
            Group {
                switch phase {
                case .done:
                    Image(systemName: "checkmark.circle.fill").dsGlyph(.body).foregroundStyle(DS.confirm)
                case .next:
                    Image(systemName: "\(step.rawValue + 1).circle").dsGlyph(.body).foregroundStyle(DS.aztecInk)
                case .later:
                    Image(systemName: "\(step.rawValue + 1).circle").dsGlyph(.body, weight: .regular).foregroundStyle(DS.textTertiary)
                }
            }
            .frame(width: 24)
            Text(verbatim: title(step, done: phase == .done))
                .dsText(.heading17)
                .foregroundStyle(phase == .next ? DS.textPrimary : phase == .done ? DS.textSecondary : DS.textTertiary)
                .lineLimit(1)
            Spacer(minLength: DS.Space.s2)
            if let fact = fact(step) {
                Text(verbatim: fact).dsText(.body17).foregroundStyle(DS.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .frame(minHeight: DSFeed.headHeight)
        .accessibilityElement(children: .combine)
    }
}

/// **YOUR SCORE, UNDER HUMAN PASSPORT'S PAGE (prd §1820).** While the page
/// is open, Shield is asked for your co-signer's score every few seconds
/// (its public eligibility read, the one Move already asks), so you know
/// when to stop: "12 of 20" in the attention ink, then the confirm ink and
/// "Back to send". Says nothing until Shield first answers.
struct PassportScoreBand: View {
    let address: String
    let threshold: Int
    let back: () -> Void
    @State private var score: Int?

    private var reached: Bool { (score ?? 0) >= threshold }

    var body: some View {
        VStack(spacing: DS.Space.s3) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text("Your co-signer's score").dsText(.body17).foregroundStyle(DS.textSecondary)
                Spacer(minLength: DS.Space.s2)
                if let score {
                    Text(verbatim: AztecWayIn.progress(score, of: threshold))
                        .dsText(.heading24).monospacedDigit()
                        .foregroundStyle(reached ? DS.confirmInk : DS.attentionInk)
                        .contentTransition(.numericText())
                } else {
                    DSSpinner(size: .small)
                }
            }
            if reached {
                Button(action: back) {
                    MoveSentence.actCard(String(localized: "Back to send"), on: true, fill: DS.aztecInk, ink: .black)
                }
                .buttonStyle(PressSpring())
                .transition(.opacity)
            }
        }
        .padding(.horizontal, DSRoomChassis.leadInset)
        .padding(.vertical, DS.Space.s3)
        .animation(DS.Motion.standard, value: score)
        .task(id: address) { await watch() }
    }

    private func watch() async {
        #if DEBUG
        // The way-in sample counts up by itself, asking nobody (prd §1820).
        if let sample = UserDefaults.standard.string(forKey: "aztecWayInSample"), let start = Int(sample) {
            score = start
            while !Task.isCancelled, (score ?? 0) < threshold {
                try? await Task.sleep(for: .seconds(3))
                score = min(threshold + 4, (score ?? 0) + 4)
                NSLog("[Casberi] aztecWayIn| score | %d", score ?? 0)
            }
            return
        }
        #endif
        while !Task.isCancelled {
            if let standing = await ShieldBridge.eligibility(address) { score = Int(standing.score) }
            try? await Task.sleep(for: .seconds(Double(AztecWayIn.pollSeconds)))
        }
    }
}
