import SwiftUI

/// One provider's key-connect UI (prd §67, store entries 2026-07-14) — the
/// List sections a provider's app page embeds: status, paste field, remove.
/// Claude and ChatGPT's import screens append this under their import; Gemini
/// and Venice's whole setup screen IS this (they have nothing to import).
/// Connect/disconnect go through AIKey's one shared path, which validates
/// before saving (no dead key, honesty rule) and seats/unseats the app in
/// BridgeStore so the catalog tile always tells the truth.
struct AIKeySection: View {
    let provider: AIProvider
    @Environment(BridgeStore.self) private var store
    @State private var keyField = ""
    @State private var checking = false
    @State private var result: String?
    @State private var resultIsError = false
    /// The saved key's hint ("…3kQA"), nil when no key — mirrored state, not
    /// a per-render Keychain read (typing in the field re-renders per
    /// keystroke). Refreshed on appear so a removal made in Settings while
    /// this page sits in the nav stack can't leave stale connected copy.
    @State private var hint: String?

    private var connected: Bool { hint != nil }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                HStack(spacing: DS.Space.s3) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(connected ? DS.confirm : DS.textTertiary)
                    Text(connected
                            ? "Key connected \(hint ?? "") — answers offer \"Try with \(provider.label)\""
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
        .onAppear { refresh() }
        if connected {
            Section {
                Button("Remove key", role: .destructive) {
                    AIKey.disconnect(provider, store: store)
                    refresh()
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

    private func refresh() {
        hint = AIKey.isConnected(provider) ? AIKey.hint(provider) : nil
    }

    /// Connect through the one shared path — validated by the provider (the
    /// page names it, so Venice's prefix-less keys need no shape-guessing),
    /// saved, and seated in BridgeStore.
    private func connect() {
        let candidate = keyField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, !checking else { return }
        checking = true
        result = nil
        Task { @MainActor in
            let outcome = await AIKey.connect(candidate, provider: provider, store: store)
            checking = false
            switch outcome {
            case .accepted:
                keyField = ""
                refresh()
                resultIsError = false
                result = String(localized: "Connected — answers now offer \"Try with \(provider.label)\".")
                DSHaptic.success()
            case .rejected:
                resultIsError = true
                result = String(localized: "\(provider.offerName) didn't accept that key — check it and try again.")
            case .unreachable:
                resultIsError = true
                result = String(localized: "Couldn't reach \(provider.offerName) — check your connection and try again.")
            }
        }
    }
}

/// The whole setup screen for a provider with nothing to import (Gemini,
/// Venice) — the shared product-page header (the catalog's own words) over
/// the key section, same List grammar as every other setup screen.
struct AIKeySetupScreen: View {
    let provider: AIProvider

    var body: some View {
        List {
            BridgeSetupHeader(name: provider.offerName)
            AIKeySection(provider: provider)
                .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle(provider.offerName)
        .navigationBarTitleDisplayMode(.large)
    }
}
