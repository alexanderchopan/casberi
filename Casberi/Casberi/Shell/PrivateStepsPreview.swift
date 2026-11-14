import SwiftUI

#if DEBUG
/// `-privateStepsPreview move|app|fail|signed|away|awayfail|ask` (prd §1700w, §1700x, §1777): plays one
/// private send's steps on a timeline over the shell, through the real
/// `PrivateSendSteps` and the views Move and the Aztec browser draw.
///   - `move`: an Aztec send (checking 2 s, proving 9 s, sent 8 s, done),
///     Move's rows under a sample sentence, then "Sent privately · 19 s".
///   - `app`: the same in the browser's capsule over a blank page.
///   - `fail`: an Aztec send whose proof fails, its reason on the row.
///   - `signed`: a move-in (Railgun's, or a Shield deposit), Checking ·
///     Signing · Sent on Ethereum; a send's rows lead with "Confirmed with
///     Face ID", a move-in's do not (it signs inside its clock).
///   - `away`, `awayfail`: Move's send behind its sheet, drawn by the
///     shell's own capsule over the tab bar (`MoveStepCapsule`); this view
///     draws nothing and only plays the steps.
///   - `ask`: an Aztec app's Connect sheet over a sample host, to see the
///     act in Aztec's own fill (prd §1779). Nothing is connected.
/// No engine, no money: a simulator cannot prove a mainnet send, and this is
/// how the drawing is seen. NSLogs `privateStepsPreview| <mode> | <step>`.
struct PrivateStepsPreview: View {
    private let mode = UserDefaults.standard.string(forKey: "privateStepsPreview")
        .flatMap { ["move", "app", "fail", "signed", "away", "awayfail", "ask"].contains($0) ? $0 : nil }
    @State private var steps = PrivateSendSteps.shared

    var body: some View {
        if mode == "ask" {
            ZStack(alignment: .bottom) {
                DS.surfaceSheet.ignoresSafeArea()
                AztecAskSheet(ask: .connect(requestId: "preview", host: "app.example"), answer: { _ in })
            }
        } else if let mode, mode.hasPrefix("away") {
            Color.clear.allowsHitTesting(false).task { await play(mode) }
        } else if let mode {
            ZStack(alignment: .bottom) {
                DS.surfaceSheet.ignoresSafeArea()
                if mode == "app" {
                    AztecStepCapsule().padding(.bottom, 120)
                } else {
                    // Move's layout (prd §1700x): the sentence alone on top, the
                    // rows in the foot above the act.
                    VStack(alignment: .leading, spacing: DS.Space.s4) {
                        Text(verbatim: sentence(mode)).dsText(.heading34).foregroundStyle(DS.textPrimary)
                        if let total = steps.run?.total, steps.run?.ok == true {
                            Text(verbatim: String(localized: "Sent privately · \(total) s"))
                                .dsText(.body17).foregroundStyle(DS.textSecondary)
                        }
                        Spacer()
                        if let run = steps.run {
                            PrivateStepRows(run: run, confirmed: mode == "signed" ? nil : String(localized: "Confirmed with Face ID"))
                            HStack {
                                Spacer()
                                Text(verbatim: run.isRunning ? String(localized: "Sending…") : run.ok == true ? String(localized: "Done") : String(localized: "Try again"))
                                    .dsText(.heading34)
                                    .foregroundStyle(run.isRunning ? DS.textTertiary : DS.pickInk)
                            }
                            .padding(.bottom, DS.Space.s6)
                        }
                    }
                    .padding(.horizontal, DSRoomChassis.leadInset)
                    .padding(.top, 80)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .task { await play(mode) }
        }
    }

    private func sentence(_ mode: String) -> String {
        let done = steps.run?.ok == true
        return mode == "signed"
            ? (done ? "Sent 25 DAI to your private balance on Ethereum." : "Send 25 DAI to your private balance on Ethereum.")
            : (done ? "Sent 20 USDC to ...a91c on Aztec." : "Send 20 USDC to ...a91c on Aztec.")
    }

    private func play(_ mode: String) async {
        let s = PrivateSendSteps.shared
        let kind: PrivateSendSteps.Kind = mode == "app" ? .app : .move
        let plan: PrivateSendSteps.Plan = mode == "signed" ? .signed(.ethereum) : .send(.aztec)
        func say(_ step: String, after seconds: Double, extra: [String: Any] = [:]) async {
            try? await Task.sleep(for: .seconds(seconds))
            s.received(["step": step, "kind": kind.rawValue, "sent": step == "done"].merging(extra) { $1 }, plan: plan)
            NSLog("privateStepsPreview| %@ | %@", mode, step)
        }
        try? await Task.sleep(for: .seconds(4))
        if kind == .move { s.begin(.move, plan: plan) }
        if mode.hasPrefix("away") { s.sendAway() }
        await say("checking", after: 0)
        switch mode {
        case "fail", "awayfail":
            await say("proving", after: 2)
            await say("failed", after: 6, extra: ["reason": "Aztec's node did not answer. Nothing was sent."])
        case "signed":
            await say("signing", after: 2)
            await say("sent", after: 4)
            await say("done", after: 12)
        default:
            await say("proving", after: 2)
            await say("sent", after: 9)
            await say("done", after: 8)
        }
    }
}
#endif
