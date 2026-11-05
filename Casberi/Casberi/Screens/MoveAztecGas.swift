import SwiftUI

/// **MOVE AZTEC TO YOUR AZTEC ACCOUNT FOR GAS (prd §1700e item 2).** Picked
/// from Send's recipients ("Your Aztec account"); its own sentence, as Lend's
/// and a fresh Receive's are. Your Safe sends AZTEC into Aztec's own Fee Juice
/// portal (`AztecGas`), open and unchecked; minutes later the engine claims it
/// and Holdings shows Fee Juice. Fee Juice is gas only — the line says so.
struct MoveAztecGasSentence<Head: View>: View {
    var inTray = false
    var leave: () -> Void = {}
    @ViewBuilder let head: () -> Head

    enum Stage: Equatable { case ready, working(String), sent, failed(String) }

    @State private var amount = 10
    @State private var stage: Stage = .ready
    private let amounts = [5, 10, 25]
    private var store: AztecAccountStore { .shared }
    private var waiting: Int { (store.snapshot.gas ?? []).filter { !$0.claimed }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                MoveFlow {
                    head()
                    MovePhrase("\(amount) AZTEC", ink: DS.pickInk)
                    MovePhrase(String(localized: "to your Aztec account"), glue: String(localized: "to"))
                    MovePhrase(String(localized: "for gas."))
                }
                HStack(spacing: DS.Space.s2) {
                    ForEach(amounts, id: \.self) { a in
                        Button { withAnimation(DS.Motion.standard) { amount = a } } label: {
                            Chip(text: "\(a) AZTEC", selected: a == amount)
                        }
                        .buttonStyle(PressSpring())
                        .disabled(stage != .ready)
                    }
                }
                .padding(.top, DS.Space.s4)
                Text(line)
                    .dsText(.subhead12)
                    .foregroundStyle(lineInk)
                    .padding(.top, DS.Space.s3)
                HStack(spacing: DS.Space.s1) {
                    ProtocolInlineMark(mark: "aztec")
                    Text("Powered by Aztec").dsText(.subhead12).foregroundStyle(DS.textSecondary)
                }
                .padding(.top, DS.Space.s2)
            }
            .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
            .padding(.top, inTray ? DS.Space.s2 : DS.Space.s6)
            .padding(.bottom, DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { foot }
        .task {
            // A deposit Aztec has carried is claimed while the sentence shows.
            while !Task.isCancelled {
                if waiting > 0 { await AztecGas.settle() }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private var line: String {
        switch stage {
        case .ready:
            waiting > 0
                ? String(localized: "Gas on its way: Aztec carries it in minutes, then it is yours.")
                : String(localized: "Gas pays for what your Aztec account does. It cannot be sent to anyone.")
        case .working(let words): words
        case .sent: String(localized: "Sent. Aztec carries it in minutes; Holdings shows it when it lands.")
        case .failed(let why): why
        }
    }

    private var lineInk: Color {
        if case .failed = stage { return DS.destructiveInk }
        return DS.textSecondary
    }

    private var foot: some View {
        HStack(alignment: .firstTextBaseline) {
            Button { leave() } label: {
                Text("Back").dsText(.heading24).foregroundStyle(DS.textSecondary).frame(minHeight: 48)
            }
            .buttonStyle(RowPress())
            Spacer(minLength: DS.Space.s3)
            Button { Task { await send() } } label: {
                Text(footWord).dsText(.heading34).foregroundStyle(stage == .ready ? DS.pickInk : DS.textSecondary)
                    .frame(minHeight: 48, alignment: .trailing)
            }
            .buttonStyle(RowPress())
            .disabled(stage != .ready || DemoMode.isActive)
        }
        .padding(.horizontal, DSRoomChassis.leadInset)
        .padding(.vertical, DS.Space.s2)
    }

    private var footWord: LocalizedStringKey {
        switch stage {
        case .ready: DemoMode.isActive ? "Not in the demo" : "Send"
        case .working: "Sending…"
        case .sent: "Sent"
        case .failed: "Try again"
        }
    }

    @MainActor
    private func send() async {
        let units = String(amount) + String(repeating: "0", count: 18)
        stage = .working(String(localized: "Checking…"))
        do {
            _ = try await AztecGas.send(units: units) { s in
                await MainActor.run {
                    stage = .working(s == .signing ? String(localized: "Confirm with Face ID") : String(localized: "Sending…"))
                }
            }
            stage = .sent
            DSHaptic.success()
        } catch {
            stage = .failed(error.localizedDescription)
            try? await Task.sleep(for: .seconds(3))
            if case .failed = stage { stage = .ready }
        }
    }
}
