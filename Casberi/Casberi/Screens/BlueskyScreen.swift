import SwiftUI
import SwiftData

/// Bluesky, connected — by handle alone. Your posts are public on the AT
/// Protocol, so this bridge reads them with no password and nothing stored
/// but the name. Likes arrive later with an app-password sign-in.
struct BlueskyScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var handleField = ""
    @State private var syncing = false
    @State private var result: String?
    @State private var resultIsError = false

    private var bluesky: BlueskyStore { BlueskyStore.shared }

    private var recent: [Thing] {
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Bluesky" },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 12
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    var body: some View {
        List {
            handleSection
            if !recent.isEmpty { recentSection }
            footerSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle("Bluesky")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            handleField = bluesky.handle
            if !bluesky.handle.isEmpty {
                Task { await sync() }
            }
        }
    }

    private var handleSection: some View {
        Section {
            HStack(spacing: DS.Space.s2) {
                TextField("you.bsky.social", text: $handleField)
                    .dsText(.callout15)
                    .foregroundStyle(DS.textPrimary)
                    .tint(DS.tint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(connect)
                Button(bluesky.handle.isEmpty ? "Connect" : "Update", action: connect)
                    .dsText(.label12)
                    .foregroundStyle(handleField.isEmpty ? DS.textTertiary : .white)
                    .padding(.horizontal, DS.Space.s3)
                    .frame(height: 28)
                    .background(handleField.isEmpty ? AnyShapeStyle(DS.gray200) : AnyShapeStyle(DS.tint),
                                in: Capsule(style: .continuous))
                    .disabled(handleField.isEmpty)
                    .buttonStyle(.plain)
            }
            .listRowBackground(DS.surfaceSheet)
            if syncing {
                HStack(spacing: DS.Space.s2) {
                    ProgressView().controlSize(.small)
                    Text("Fetching your posts…")
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
            Text("YOUR HANDLE").dsText(.label12).kerning(0.7)
                .foregroundStyle(DS.textTertiary)
        } footer: {
            Text("Just the handle — your posts are public, so there's no password to give.")
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
            Text("YOUR POSTS").dsText(.label12).kerning(0.7)
                .foregroundStyle(DS.textTertiary)
        }
    }

    private var footerSection: some View {
        Section {
            Text("Read-only, public data only. Likes arrive with sign-in, later.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .listRowBackground(Color.clear)
        }
    }

    private func connect() {
        let handle = BlueskyStore.normalize(handleField)
        guard !handle.isEmpty else { return }
        bluesky.handle = handle
        handleField = handle
        DSHaptic.tap()
        Task { await sync() }
    }

    private func sync() async {
        guard !syncing else { return }
        syncing = true
        let added = await BlueskyIngest.refresh(context: modelContext)
        syncing = false
        guard let added else {
            result = "Couldn't find that handle — check the spelling."
            resultIsError = true
            return
        }
        resultIsError = false
        result = added > 0 ? "\(added) posts in" : "Up to date"
        let proof = added > 0 ? "\(added) posts in" : "Synced just now"
        if let existing = store.bridges.first(where: { $0.name == "Bluesky" }) {
            store.reconnect(existing.id, proof: proof)
        } else {
            store.bridges.append(BridgeApp(
                id: "bsky", name: "Bluesky", status: .connected,
                statusLine: proof, can: ["Reads your public posts."]
            ))
            DSHaptic.success()
        }
    }
}
