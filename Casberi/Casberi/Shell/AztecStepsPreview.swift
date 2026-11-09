import SwiftUI

#if DEBUG
/// `-aztecStepsPreview move|app` (prd §1700w): plays one send's steps on a
/// timeline (checking 2 s, proving 9 s, handed to Aztec 8 s, then done) over
/// the shell, through the real `AztecSendSteps` and the views Move and the
/// browser draw: Move's rows under a sample sentence, or the browser's
/// capsule over a blank page. No engine, no money: the sim cannot prove a
/// mainnet send, and this is how the drawing is seen. NSLogs each step.
struct AztecStepsPreview: View {
    private let kind = UserDefaults.standard.string(forKey: "aztecStepsPreview")
        .flatMap(AztecSendSteps.Kind.init(rawValue:))
    @State private var steps = AztecSendSteps.shared

    var body: some View {
        if let kind {
            ZStack(alignment: .bottom) {
                DS.surfaceSheet.ignoresSafeArea()
                if kind == .move {
                    VStack(alignment: .leading, spacing: DS.Space.s4) {
                        Text(verbatim: steps.run?.ended == nil ? "Send 20 USDC to ...a91c on Aztec." : "Sent 20 USDC to ...a91c on Aztec.")
                            .dsText(.heading34).foregroundStyle(DS.textPrimary)
                        if let run = steps.run, run.ended == nil {
                            AztecStepRows(run: run)
                        } else if let total = steps.run?.total {
                            Text(verbatim: String(localized: "Sent privately · \(total) s"))
                                .dsText(.body17).foregroundStyle(DS.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, DSRoomChassis.leadInset)
                    .padding(.top, 80)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    AztecStepCapsule().padding(.bottom, 120)
                }
            }
            .task { await play(kind) }
        }
    }

    private func play(_ kind: AztecSendSteps.Kind) async {
        let s = AztecSendSteps.shared
        func say(_ step: String, after seconds: Double, sent: Bool = true) async {
            try? await Task.sleep(for: .seconds(seconds))
            s.received(["step": step, "kind": kind.rawValue, "sent": sent])
            NSLog("aztecStepsPreview| %@ | %@", kind.rawValue, step)
        }
        try? await Task.sleep(for: .seconds(4))
        if kind == .move { s.begin(.move) }
        await say("checking", after: 0)
        await say("proving", after: 2)
        await say("sent", after: 9)
        await say("done", after: 8)
    }
}
#endif
