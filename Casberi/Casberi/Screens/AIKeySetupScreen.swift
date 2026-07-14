import SwiftUI

/// One provider's key-connect UI (prd §67, store entries 2026-07-14) — the
/// List sections a provider's app page embeds: status, paste field, remove.
/// Claude and ChatGPT's import screens append this under their import; Gemini
/// and Venice's whole setup screen IS this (they have nothing to import).
/// Validates against the provider before saving (no dead key, honesty rule)
/// and seats the app in BridgeStore so the catalog tile wears its state.
struct AIKeySection: View {
    let provider: AIProvider
    @Environment(BridgeStore.self) private var store
    @State private var keyField = ""
    @State private var checking = false
    @State private var result: String?
    @State private var resultIsError = false
    @State private var connected: Bool

    init(provider: AIProvider) {
        self.provider = provider
        _connected = State(initialValue: AIKey.isConnected(provider))
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                HStack(spacing: DS.Space.s3) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(connected ? DS.confirm : DS.textTertiary)
                    Text(connected
                            ? "Key connected \(AIKey.hint(provider)) — answers offer \"Try with \(provider.label)\""
                            : "Answers run on this iPhone until you add one")
                        .dsText(.subhead13)
                        .foregroundStyle(connected ? DS.textPrimary : DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                BridgeFieldRow(placeholder: "API key", text: $keyField,
                               buttonLabel: checking ? "Checking…"
                                          : (connected ? "Update" : "Connect"),
                               secure: true, action: connect)
                BridgeSyncStatusRows(result: result, resultIsError: resultIsError)
            }
            .dsListCardRow()
        } header: {
            Text("Power answers with your key").dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        } footer: {
            Text("Get a key at \(provider.console). Every answer then offers \"Try with \(provider.label)\" — the question and the few matched things go straight from this iPhone to \(provider.offerName)'s API, only when you tap, billed to your key. It stays in this iPhone's Keychain.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
        if connected {
            Section {
                Button("Remove key", role: .destructive) {
                    AIKey.clear(provider)
                    connected = false
                    result = String(localized: "Removed — answers stay on this iPhone.")
                    resultIsError = false
                    DSHaptic.tap()
                }
                .dsText(.callout15)
                .dsListCardRow()
            } footer: {
                Text("Removing the key keeps everything else — it only retires \"Try with \(provider.label)\".")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            }
        }
    }

    /// Saves only after the provider accepts the key — checked here, where the
    /// provider is KNOWN from the page you're on (no shape-guessing needed, so
    /// Venice's prefix-less keys work like anyone's).
    private func connect() {
        let candidate = keyField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, !checking else { return }
        checking = true
        result = nil
        Task { @MainActor in
            let ok = await AIAnswer.validate(candidate, provider: provider)
            checking = false
            if ok {
                AIKey.set(candidate, provider: provider)
                keyField = ""
                connected = true
                resultIsError = false
                result = String(localized: "Connected — answers now offer \"Try with \(provider.label)\".")
                DSHaptic.success()
                store.registerConnected(
                    id: provider.seatID, name: provider.offerName,
                    proof: String(localized: "Key connected — powers answers"),
                    can: ["Answers \"Try with \(provider.label)\" on your tap — device→\(provider.offerName) direct, billed to your key."])
            } else {
                resultIsError = true
                result = String(localized: "\(provider.offerName) didn't accept that key — check it and try again.")
            }
        }
    }
}

/// The whole setup screen for a provider with nothing to import (Gemini,
/// Venice) — the key section under a plain explainer, same List grammar as
/// every other setup screen.
struct AIKeySetupScreen: View {
    let provider: AIProvider

    var body: some View {
        List {
            Section {
                Text(explainer)
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .dsListCardRow()
            }
            AIKeySection(provider: provider)
                .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle(provider.offerName)
        .navigationBarTitleDisplayMode(.large)
    }

    private var explainer: String {
        switch provider {
        case .venice:
            String(localized: "Venice keeps chats on your own device by design, so there's nothing to read in — instead, your Venice key can power Casberi's answers. Private by both sides' rules.")
        default:
            String(localized: "Your \(provider.offerName) account has nothing for Casberi to read in — instead, your key can power Casberi's answers with \(provider.label).")
        }
    }
}
