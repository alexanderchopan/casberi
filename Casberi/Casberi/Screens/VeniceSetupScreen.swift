import SwiftUI
import SwiftData

/// Venice, connected — by key (2026-07-14). Venice keeps chats on your own
/// device by design, so there is nothing to read IN; its seat powers answers
/// OUT: a Venice key makes "Try with your key" run on Venice's private API,
/// straight from this iPhone, only on the tap. The key is checked with
/// Venice before it saves (no dead key claiming a capability — honesty
/// rule), lands in the Keychain via the same vault every agent key uses,
/// and appears in Settings → Your key alongside the rest.
struct VeniceSetupScreen: View {
    @Environment(BridgeStore.self) private var store
    @State private var keyDraft = ""
    @State private var checking = false
    @State private var result: String?
    @State private var resultIsError = false
    @State private var configured = AgentKey.isConfigured(.venice)

    var body: some View {
        List {
            stepsSection.listRowSeparator(.hidden)
            connectSection.listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftTopEdge()
        .navigationTitle("Venice")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Steps (the key comes from Venice's side — say so plainly)

    private var stepsSection: some View {
        Section {
            step(1, "At venice.ai, sign in and open Settings → API keys.")
            step(2, "Create a key and copy it.")
            step(3, "Paste it below — it's checked with Venice before it saves.")
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
                SecureField(AgentProvider.venice.placeholder, text: $keyDraft)
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
            Text("Nothing reads in — Venice keeps chats on your device by design. Your key powers \"Try with your key\": any answer re-runs on Venice, straight from this iPhone, only when you tap. The key lives in the Keychain, goes only to Venice itself, and Venice bills you directly. It also appears in Settings → Your key.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
        }
    }

    /// Connects only after Venice accepts the key — the seat registers with
    /// what it can actually do, nothing more.
    private func connect() {
        let candidate = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }
        checking = true
        result = nil
        Task { @MainActor in
            let ok = await AgentAnswer.validate(candidate, provider: .venice)
            checking = false
            if ok {
                AgentKey.set(candidate, for: .venice)
                configured = true
                keyDraft = ""
                DSHaptic.success()
                resultIsError = false
                result = String(localized: "Connected — answers now offer \"Try with your key\" on Venice.")
                store.registerConnected(id: "venice", name: "Venice",
                                        proof: String(localized: "Key in the Keychain"),
                                        can: ["Answers with your key — only when you tap."])
            } else {
                resultIsError = true
                result = String(localized: "Venice didn't accept that key — check it and try again.")
            }
        }
    }
}
