import SwiftUI

/// **MOVE'S THREE ROWS WHILE A SEND WORKS (prd §1700w, the canvas's B).**
/// Under the sentence: what is done, what is running and what is next, each
/// with its own seconds. A row that is done wears the confirm check, the one
/// running the spinner, the next an empty circle. Seconds count from the
/// step's start, read off the engine's own signals (`AztecSendSteps`).
struct AztecStepRows: View {
    let run: AztecSendSteps.Run

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                row(.checking, now: context.date)
                row(.proving, now: context.date)
                row(.sent, now: context.date)
            }
        }
    }

    private enum Phase { case done, now, next }

    private func phase(_ step: AztecSendSteps.Step) -> Phase {
        step.rawValue < run.step.rawValue ? .done : step == run.step ? .now : .next
    }

    static func words(_ step: AztecSendSteps.Step, done: Bool, running: Bool) -> String {
        switch step {
        case .checking: done ? String(localized: "Checked") : String(localized: "Checking")
        case .proving: done ? String(localized: "Proved on your phone") : String(localized: "Proving on your phone")
        case .sent: running ? String(localized: "Sending to Aztec") : String(localized: "Sent to Aztec")
        }
    }

    /// When a step began and ended, as far as the engine has said.
    private func span(_ step: AztecSendSteps.Step) -> (start: Date?, end: Date?) {
        switch step {
        case .checking: (run.started, run.provingAt ?? run.sentAt ?? run.ended)
        case .proving: (run.provingAt, run.sentAt ?? run.ended)
        case .sent: (run.sentAt, run.ended)
        }
    }

    static func seconds(_ from: Date, _ to: Date) -> String {
        String(localized: "\(max(0, Int(to.timeIntervalSince(from).rounded()))) s")
    }

    @ViewBuilder private func row(_ step: AztecSendSteps.Step, now: Date) -> some View {
        let phase = phase(step)
        let span = span(step)
        let time: String? = switch phase {
        case .done: span.start.flatMap { s in span.end.map { Self.seconds(s, $0) } }
        case .now: span.start.map { Self.seconds($0, now) }
        case .next: nil
        }
        HStack(spacing: DS.Space.s3) {
            Group {
                switch phase {
                case .done:
                    Image(systemName: "checkmark.circle.fill").dsGlyph(.body).foregroundStyle(DS.confirm)
                case .now:
                    DSSpinner(size: .small)
                case .next:
                    Image(systemName: "circle").dsGlyph(.body, weight: .regular).foregroundStyle(DS.textTertiary)
                }
            }
            .frame(width: 24)
            Text(verbatim: Self.words(step, done: phase == .done, running: phase == .now))
                .dsText(.heading17)
                .foregroundStyle(phase == .now ? DS.textPrimary : phase == .done ? DS.textSecondary : DS.textTertiary)
                .lineLimit(1)
            Spacer(minLength: DS.Space.s2)
            if let time {
                Text(verbatim: time).dsText(.body17).foregroundStyle(DS.textSecondary).monospacedDigit()
            }
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .combine)
    }
}

/// **THE BROWSER'S CAPSULE (prd §1700w, the canvas's C).** After Approve the
/// sheet goes and the app's page waits on Casberi; this floats above the
/// page's foot while the transaction is checked, proved and handed to Aztec,
/// says "Sent to Aztec" with its seconds, and goes two seconds later. A
/// failure stays until tapped. A call that never needs a second (an
/// authorisation, no proof) never draws it. Glass: it is the floating layer.
struct AztecStepCapsule: View {
    @State private var steps = AztecSendSteps.shared

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

    /// An app's send, once it has taken a second or reached a proof; its
    /// success for two seconds after; its failure until put away.
    static func shows(_ run: AztecSendSteps.Run, at now: Date) -> Bool {
        guard run.kind == .app else { return false }
        guard let ended = run.ended else {
            return run.step != .checking || now.timeIntervalSince(run.started) >= 1
        }
        if run.ok == false { return true }
        return run.reachedAztec && now.timeIntervalSince(ended) < 2
    }

    @ViewBuilder private func capsule(_ run: AztecSendSteps.Run, now: Date) -> some View {
        let failed = run.ok == false
        let label = HStack(spacing: DS.Space.s2) {
            if failed {
                Image(systemName: "exclamationmark.circle.fill").dsGlyph(.body).foregroundStyle(DS.destructive)
            } else if run.ended != nil {
                Image(systemName: "checkmark.circle.fill").dsGlyph(.body).foregroundStyle(DS.confirm)
            } else {
                DSSpinner(size: .small)
            }
            Text(verbatim: failed ? String(localized: "Not sent")
                 : AztecStepRows.words(run.step, done: false, running: run.ended == nil))
                .dsText(.body17).foregroundStyle(DS.textPrimary).lineLimit(1)
            if !failed {
                Text(verbatim: "· " + AztecStepRows.seconds(run.started, run.ended ?? now))
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
