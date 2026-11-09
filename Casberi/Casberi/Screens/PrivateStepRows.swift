import SwiftUI

/// **A PRIVATE SEND'S STEPS AS ROWS (prd §1700w, §1700x).** One view for every
/// private balance (Aztec's and Railgun's), so the two read the same: a step
/// that is done wears the confirm check and its own seconds, the one running
/// the spinner and its seconds so far, the next an empty circle. A failed run
/// draws its reason on the step it failed at, in attention ink (Try again is
/// the caller's act). It takes no place on screen of its own: the caller
/// puts it under the sentence or in the foot.
///
/// `confirmed` leads with a done row that has no seconds, for what the person
/// did before the clock started ("Confirmed with Face ID").
struct PrivateStepRows: View {
    let run: PrivateSendSteps.Run
    var confirmed: String? = nil

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if let confirmed {
                    line(.done, words: confirmed, time: nil)
                }
                ForEach(run.plan.steps.indices, id: \.self) { i in
                    row(i, now: context.date)
                }
            }
        }
    }

    enum Phase { case done, now, next, failed }

    static func phase(_ i: Int, of run: PrivateSendSteps.Run) -> Phase {
        let current = run.currentIndex
        if run.ok == true { return .done }
        if run.ok == false, i == current { return .failed }
        return i < current ? .done : i == current && run.isRunning ? .now : .next
    }

    static func seconds(_ from: Date, _ to: Date) -> String {
        String(localized: "\(max(0, Int(to.timeIntervalSince(from).rounded()))) s")
    }

    @ViewBuilder private func row(_ i: Int, now: Date) -> some View {
        let step = run.plan.steps[i]
        let phase = Self.phase(i, of: run)
        let span = run.span(i)
        let time: String? = switch phase {
        case .done: span.start.flatMap { s in span.end.map { Self.seconds(s, $0) } }
        case .now: span.start.map { Self.seconds($0, now) }
        case .next, .failed: nil
        }
        let words = switch phase {
        case .done: step.done
        case .failed: run.reason ?? String(localized: "Not sent")
        case .now, .next: step.running
        }
        line(phase, words: words, time: time)
    }

    @ViewBuilder private func line(_ phase: Phase, words: String, time: String?) -> some View {
        HStack(spacing: DS.Space.s3) {
            Group {
                switch phase {
                case .done:
                    Image(systemName: "checkmark.circle.fill").dsGlyph(.body).foregroundStyle(DS.confirm)
                case .now:
                    DSSpinner(size: .small)
                case .next:
                    Image(systemName: "circle").dsGlyph(.body, weight: .regular).foregroundStyle(DS.textTertiary)
                case .failed:
                    Image(systemName: "exclamationmark.circle.fill").dsGlyph(.body).foregroundStyle(DS.attention)
                }
            }
            .frame(width: 24)
            Text(verbatim: words)
                .dsText(.heading17)
                .foregroundStyle(phase == .now ? DS.textPrimary : phase == .done ? DS.textSecondary
                                 : phase == .failed ? DS.attentionInk : DS.textTertiary)
                .lineLimit(phase == .failed ? 3 : 1)
                .fixedSize(horizontal: false, vertical: phase == .failed)
            Spacer(minLength: DS.Space.s2)
            if let time {
                Text(verbatim: time).dsText(.body17).foregroundStyle(DS.textSecondary).monospacedDigit()
            }
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .combine)
    }
}

/// **THE AZTEC BROWSER'S CAPSULE (prd §1700w, the canvas's C).** After Approve
/// the sheet goes and the app's page waits on Casberi; this floats above the
/// page's foot while the transaction is checked, proved and handed to Aztec,
/// says "Sent to Aztec" with its seconds, and goes two seconds later. A
/// failure stays until tapped. A call that never needs a second (an
/// authorisation, no proof) never draws it. Glass: it is the floating layer.
struct AztecStepCapsule: View {
    @State private var steps = PrivateSendSteps.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let run = steps.run
            let shown = run.map { Self.shows($0, at: context.date) } ?? false
            ZStack {
                if shown, let run {
                    capsule(run, now: context.date)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(DS.Motion.standard, value: shown)
        }
    }

    /// An app's send, once it has taken a second or passed its first step;
    /// its success for two seconds after; its failure until put away.
    static func shows(_ run: PrivateSendSteps.Run, at now: Date) -> Bool {
        guard run.kind == .app else { return false }
        guard let ended = run.ended else {
            return run.currentIndex > 0 || now.timeIntervalSince(run.started) >= 1
        }
        if run.ok == false { return true }
        return run.reachedNetwork && now.timeIntervalSince(ended) < 2
    }

    @ViewBuilder private func capsule(_ run: PrivateSendSteps.Run, now: Date) -> some View {
        let failed = run.ok == false
        let step = run.plan.steps[run.currentIndex]
        let label = HStack(spacing: DS.Space.s2) {
            if failed {
                Image(systemName: "exclamationmark.circle.fill").dsGlyph(.body).foregroundStyle(DS.destructive)
            } else if run.ended != nil {
                Image(systemName: "checkmark.circle.fill").dsGlyph(.body).foregroundStyle(DS.confirm)
            } else {
                DSSpinner(size: .small)
            }
            Text(verbatim: failed ? String(localized: "Not sent") : run.ended == nil ? step.running : step.done)
                .dsText(.body17).foregroundStyle(DS.textPrimary).lineLimit(1)
            if !failed {
                Text(verbatim: "· " + PrivateStepRows.seconds(run.started, run.ended ?? now))
                    .dsText(.body17).foregroundStyle(DS.textSecondary).monospacedDigit()
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s2)
        .dsGlass(cornerRadius: DS.Radius.widget)
        .accessibilityElement(children: .combine)
        if failed {
            Button { withAnimation(DS.Motion.standard) { steps.clear() } } label: { label }
                .buttonStyle(PressSpring())
                .accessibilityHint(Text("Dismisses"))
        } else {
            label.allowsHitTesting(false)
        }
    }
}
