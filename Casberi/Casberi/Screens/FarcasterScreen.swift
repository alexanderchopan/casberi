import SwiftUI
import SwiftData

/// Farcaster, connected — by username alone. Casts are public on the open
/// protocol, so there's no password and nothing stored but the name (and the
/// resolved fid). Same shape as Bluesky's screen.
struct FarcasterScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var nameField = ""
    @State private var syncing = false
    @State private var result: String?
    @State private var resultIsError = false

    private var farcaster: FarcasterStore { FarcasterStore.shared }

    private var recent: [Thing] {
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Farcaster" },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 12
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    var body: some View {
        List {
            nameSection
            if !recent.isEmpty { recentSection }
            footerSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle("Farcaster")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            nameField = farcaster.username
            if !farcaster.username.isEmpty {
                Task { await sync() }
            }
        }
    }

    private var nameSection: some View {
        Section {
            HStack(spacing: DS.Space.s2) {
                TextField("yourname", text: $nameField)
                    .dsText(.callout15)
                    .foregroundStyle(DS.textPrimary)
                    .tint(DS.tint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(connect)
                Button(farcaster.username.isEmpty ? "Connect" : "Update", action: connect)
                    .dsText(.label12)
                    .foregroundStyle(nameField.isEmpty ? DS.textTertiary : .white)
                    .padding(.horizontal, DS.Space.s3)
                    .frame(height: 28)
                    .background(nameField.isEmpty ? AnyShapeStyle(DS.gray200) : AnyShapeStyle(DS.tint),
                                in: Capsule(style: .continuous))
                    .disabled(nameField.isEmpty)
                    .buttonStyle(.plain)
            }
            .listRowBackground(DS.surfaceSheet)
            if syncing {
                HStack(spacing: DS.Space.s2) {
                    ProgressView().controlSize(.small)
                    Text("Fetching your casts…")
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                }
                .listRowBackground(DS.surfaceSheet)
            } else if let result {
                Text(result)
                    .dsText(.subhead13)
                    .foregroundStyle(resultIsError ? DS.attention : DS.confirm)
                    .listRowBackground(DS.surfaceSheet)
            }
        } header: {
            Text("YOUR USERNAME").dsText(.label12).kerning(0.7)
                .foregroundStyle(DS.textTertiary)
        } footer: {
            Text("Just the username — casts are public on the open protocol, so there's no password to give.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
        }
    }

    private var recentSection: some View {
        Section {
            ForEach(recent) { thing in
                VStack(alignment: .leading, spacing: 2) {
                    Text(thing.title)
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                        .lineLimit(2)
                    Text(LiveTimeText.short(thing.capturedAt))
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                }
                .listRowBackground(DS.surfaceSheet)
            }
        } header: {
            Text("YOUR CASTS").dsText(.label12).kerning(0.7)
                .foregroundStyle(DS.textTertiary)
        }
    }

    private var footerSection: some View {
        Section {
            Text("Read-only, public data only — served by the Farcaster team's own public node.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .listRowBackground(Color.clear)
        }
    }

    private func connect() {
        let name = FarcasterStore.normalize(nameField)
        guard !name.isEmpty else { return }
        farcaster.username = name
        nameField = name
        DSHaptic.tap()
        Task { await sync() }
    }

    private func sync() async {
        guard !syncing else { return }
        syncing = true
        let added = await FarcasterIngest.refresh(context: modelContext)
        syncing = false
        guard let added else {
            result = "Couldn't find that username — check the spelling."
            resultIsError = true
            return
        }
        resultIsError = false
        result = added > 0 ? "\(added) casts in" : "Up to date"
        let proof = added > 0 ? "\(added) casts in" : "Synced just now"
        if let existing = store.bridges.first(where: { $0.name == "Farcaster" }) {
            store.reconnect(existing.id, proof: proof)
        } else {
            store.bridges.append(BridgeApp(
                id: "fc", name: "Farcaster", status: .connected,
                statusLine: proof, can: ["Reads your public casts."]
            ))
            DSHaptic.success()
        }
    }
}
