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
        if run.ok == false {
            Button { withAnimation(DS.Motion.standard) { steps.clear() } } label: { StepCapsuleLabel(run: run, now: now) }
                .buttonStyle(PressSpring())
                .accessibilityHint(Text("Dismisses"))
        } else {
            StepCapsuleLabel(run: run, now: now).allowsHitTesting(false)
        }
    }
}

/// The capsule's one line, for both its callers: the spinner and the step
/// under way with its seconds, the check and "Sent" with the send's whole
/// seconds, or "Not sent". Glass: it is the floating layer.
struct StepCapsuleLabel: View {
    let run: PrivateSendSteps.Run
    let now: Date

    var body: some View {
        let failed = run.ok == false
        let step = run.plan.steps[run.currentIndex]
        HStack(spacing: DS.Space.s2) {
            if failed {
                Image(systemName: "exclamationmark.circle.fill").dsGlyph(.body).foregroundStyle(DS.destructive)
            } else if run.ended != nil {
                Image(systemName: "checkmark.circle.fill").dsGlyph(.body).foregroundStyle(DS.confirm)
            } else {
                DSSpinner(size: .small)
            }
            // A send on Aztec wears its ink (prd §1779); one on Ethereum
            // and a failure keep the page's (prd §1806).
            Text(verbatim: failed ? String(localized: "Not sent") : run.ended == nil ? step.running : step.done)
                .dsText(.body17).foregroundStyle(failed || !run.plan.isAztec ? DS.textPrimary : DS.aztecInk).lineLimit(1)
            if !failed {
                Text(verbatim: "· " + PrivateStepRows.seconds(run.started, run.ended ?? now))
                    .dsText(.body17).foregroundStyle(DS.textSecondary).monospacedDigit()
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s2)
        .dsGlass(cornerRadius: DS.Radius.widget)
        .accessibilityElement(children: .combine)
    }
}

/// **MOVE'S SEND, BEHIND ITS SHEET (prd §1777; user, after a send within
/// Aztec took 34 s to prove and 75 s to send: "would be good if checking and
/// proving and then sending is in the background").** Once Face ID and the
/// co-signer have answered, the sheet closes and this floats over the tab
/// bar: the step under way and its seconds. Landed, it goes and the app's
/// own toast says so (prd §1806; user: "we need to have toasts when these
/// background actions complete"). A failure stays, and its tap opens the
/// sentence again with the reason on its step and Try again.
/// Mounted on the shell, and it ticks only while there is a send to draw.
struct MoveStepCapsule: View {
    @State private var steps = PrivateSendSteps.shared
    @Environment(ShellChrome.self) private var chrome

    var body: some View {
        ZStack {
            if let run = steps.away, run.ok != true {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    capsule(run, now: context.date)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(DS.Motion.standard, value: steps.away.map { $0.ok != true } ?? false)
        // Landed: the capsule goes and the toast says it (prd §1806). The
        // move's own code already felt the success, so the toast is quiet.
        .onChange(of: steps.away?.ok) { _, ok in
            guard ok == true, let run = steps.away else { return }
            let words = steps.awayLanded ?? run.plan.steps[run.currentIndex].done
            steps.clearAway()
            chrome.flash(words)
            NSLog("moveStepCapsule| landed | %@", words)
        }
    }
    /// Clear of the tab bar (62 pt and its gap), under the toast's line.
    static let overBand: CGFloat = 84

    @ViewBuilder private func capsule(_ run: PrivateSendSteps.Run, now: Date) -> some View {
        if run.ok == false {
            Button {
                // The sentence it came from, with its reason and Try again;
                // with no sentence kept, there is only the word to put away.
                if AztecMove.kept != nil, steps.awayFrom == .aztec {
                    chrome.moveAztec = .send
                    chrome.moveTray = true
                } else if let kept = RailgunMove.kept, steps.awayFrom == .railgun {
                    chrome.moveRailgun = .init(contract: kept.wanted, takeBack: true, recipient: kept.recipient)
                    chrome.moveTray = true
                } else {
                    withAnimation(DS.Motion.standard) { steps.clearAway() }
                }
            } label: { StepCapsuleLabel(run: run, now: now) }
                .buttonStyle(PressSpring())
                .accessibilityHint(Text("Opens the send"))
        } else {
            StepCapsuleLabel(run: run, now: now).allowsHitTesting(false)
        }
    }
}
