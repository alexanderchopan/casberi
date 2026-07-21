import SwiftUI
import SwiftData

/// Bankr, connected — by key (2026-07-16, prd §82). Bankr is an agent with a
/// wallet, so unlike the other key seats its answers can weigh what you hold
/// and what the market is doing, not only what you saved — nothing reads IN,
/// the seat powers answers OUT. The key is checked with Bankr before it saves
/// (no dead key claiming a capability — honesty rule), lands in the Keychain
/// via the same vault every agent key uses, and appears in Settings → Your
/// key alongside the rest.
///
/// The read-only ask is the point of step 2: the same key that answers could
/// also trade. Every question Casberi sends is hard-prefixed "answer only",
/// and a read-only key makes that structural rather than a promise.
struct BankrSetupScreen: View {
    @Environment(BridgeStore.self) private var store
    @State private var keyDraft = ""
    @State private var checking = false
    @State private var result: String?
    @State private var resultIsError = false
    @State private var configured = AgentKey.isConfigured(.bankr)

    var body: some View {
        List {
            stepsSection.listRowSeparator(.hidden)
            connectSection.listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .navigationTitle("Bankr")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Steps (the key comes from Bankr's side — say so plainly)

    private var stepsSection: some View {
        Section {
            step(1, "At bankr.bot/api-keys, sign in and create a key.")
            step(2, "Make it read-only, and enable agent access. Answers never trade — a read-only key keeps it that way.")
            step(3, "Paste it below — it's checked with Bankr before it saves.")
        } header: {
            Text("Get your key").dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
            Text("\(n)")
                .dsText(.subhead13).fontWeight(.bold)
                .foregroundStyle(DS.tint)
                .frame(width: 16)
            Text(LocalizedStringKey(text))
                .dsText(.callout15).foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .dsListCardRow()
    }

    // MARK: - Connect

    private var connectSection: some View {
        Section {
            HStack(spacing: DS.Space.s3) {
                SecureField(AgentProvider.bankr.placeholder, text: $keyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .dsText(.callout15)
                    .padding(.horizontal, DS.Space.s3)
                    .frame(height: 44)
                    .background(DS.fillFaint, in: Capsule(style: .continuous))
                // A plain-style button with its own background gets no dimming
                // from `.disabled` — it has to wear the off state itself, the
                // way BridgeFieldRow does, or it reads live while inert.
                let armed = !checking && !keyDraft.trimmingCharacters(in: .whitespaces).isEmpty
                Button { connect() } label: {
                    Text(checking ? "Checking…" : (configured ? "Update" : "Connect"))
                        .dsText(.callout15).fontWeight(.semibold)
                        .foregroundStyle(armed ? AnyShapeStyle(.white) : AnyShapeStyle(DS.textTertiary))
                        .padding(.horizontal, DS.Space.s4)
                        .frame(height: 44)
                        .background(armed ? AnyShapeStyle(DS.tint) : AnyShapeStyle(DS.gray200),
                                    in: Capsule(style: .continuous))
                        .animation(DS.Motion.standard, value: armed)
                }
                .buttonStyle(.plain)
                .disabled(!armed)
            }
            .dsListCardRow()
            BridgeSyncStatusRows(result: result, resultIsError: resultIsError)
        } footer: {
            Text("Nothing reads in. Your key powers \"Try with your key\": any answer re-runs on Bankr — which can weigh your wallet and live markets, not just your things — straight from this iPhone, only when you tap. Every question says answer only: nothing here trades, sends, or swaps. The key lives in the Keychain, goes only to Bankr itself, and Bankr bills you directly. It also appears in Settings → Your key.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
        }
    }

    /// Connects only after Bankr accepts the key — the seat registers with
    /// what it can actually do, nothing more. Validation spends nothing: a
    /// bogus job id 404s on a good key, 401s on a bad one.
    private func connect() {
        let candidate = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }
        checking = true
        result = nil
        Task { @MainActor in
            let ok = await AgentAnswer.validate(candidate, provider: .bankr)
            checking = false
            if ok {
                AgentKey.set(candidate, for: .bankr)
                configured = true
                keyDraft = ""
                DSHaptic.success()
                resultIsError = false
                result = String(localized: "Connected — answers now offer \"Try with your key\" on Bankr.")
                store.registerConnected(id: "bankr", name: "Bankr",
                                        proof: String(localized: "Key in the Keychain"),
                                        can: ["Answers with your key — only when you tap.",
                                              "Reads your wallet and live markets to answer.",
                                              "Never trades, sends, or swaps."])
            } else {
                resultIsError = true
                result = String(localized: "Bankr didn't accept that key — check it and try again.")
            }
        }
    }
}
