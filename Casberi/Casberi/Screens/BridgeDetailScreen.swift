import SwiftUI
import SwiftData

/// A bridge's detail — the app, what it can do (sentences), its recent things,
/// and its controls: Reconnect when broken, Pause/Resume, Remove with
/// keep-or-purge. No "ask before acting" switch: every bridge is read-only
/// today (nothing writes back to a source), so a writes toggle would be a
/// dead control — it returns, gated to a real write, when agent writes ship.
struct BridgeDetailScreen: View {
    let bridgeID: String
    @Environment(BridgeStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmRemove = false
    @State private var sheetThing: Thing?

    private var bridge: BridgeApp? {
        store.bridges.first { $0.id == bridgeID }
    }
    /// This bridge's three most recent things — cached on appearance rather than
    /// re-fetched twice on every body pass. The predicate is per-bridge, so this
    /// is the cache path rather than a static @Query.
    @State private var recent: [Thing] = []

    private func loadRecent(source name: String) {
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == name },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 3
        recent = (try? modelContext.fetch(descriptor)) ?? []
    }

    var body: some View {
        if let bridge {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    header(bridge)

                    if bridge.status == .attention {
                        Button {
                            store.reconnect(bridge.id)
                            DSHaptic.success()
                        } label: {
                            Text("Reconnect")
                                .dsText(.body17).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .dsGlassProminent(tint: DS.tint, cornerRadius: DS.Radius.pill)
                        }
                        .buttonStyle(.plain)
                    }

                    // Capabilities — sentences, not scopes. They arrive one
                    // after another (the consent rail is worth a beat).
                    section("Can") {
                        ForEach(Array(bridge.can.enumerated()), id: \.element) { i, sentence in
                            Text(sentence)
                                .dsText(.body17).foregroundStyle(DS.textPrimary)
                                .padding(.horizontal, DS.Space.s4)
                                .padding(.vertical, DS.Space.s3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .staggerIn(index: i)
                        }
                    }

                    // Recent = EVIDENCE, not content: three receipts that the
                    // bridge delivers (connect ends in proof). The rows open;
                    // the full record is one hop away in Feed.
                    if !recent.isEmpty {
                        section("Recent") {
                            ForEach(recent) { thing in
                                Button {
                                    sheetThing = thing
                                } label: {
                                    HStack(spacing: DS.Space.s3) {
                                        KindGlyph(kind: thing.kind, size: 24)
                                        Text(thing.title)
                                            .dsText(.body17).foregroundStyle(DS.textPrimary)
                                            .lineLimit(1)
                                        Spacer()
                                        // The time is what makes a receipt.
                                        Text(ProjectDetailScreen.shortTime(thing.capturedAt))
                                            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                                    }
                                    .padding(.horizontal, DS.Space.s4)
                                    .padding(.vertical, DS.Space.s3)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            Button {
                                FeedFilter.shared.source = bridge.name
                                FeedFilter.shared.tag = "All"
                                if let url = URL(string: "casberi://feed") { openURL(url) }
                            } label: {
                                Text("All in Feed")
                                    .dsText(.subhead13).foregroundStyle(DS.tint)
                                    .padding(.horizontal, DS.Space.s4)
                                    .padding(.vertical, DS.Space.s3)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Controls — words say what happens.
                    HStack(spacing: DS.Space.s3) {
                        Button(bridge.status == .paused ? "Resume" : "Pause") {
                            store.togglePause(bridge.id)
                            DSHaptic.tap()
                        }
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(DS.gray100, in: Capsule(style: .continuous))
                        .buttonStyle(.plain)

                        Button("Remove") { confirmRemove = true }
                            .dsText(.body17).foregroundStyle(DS.destructive)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(DS.gray100, in: Capsule(style: .continuous))
                            .buttonStyle(.plain)
                    }
                }
                .padding(DS.Space.s4)
                .padding(.bottom, ShellMetrics.bottomInset)
            }
            .scrollIndicators(.hidden)
            .dsPageBackground()
            .onAppear { loadRecent(source: bridge.name) }
            .navigationTitle(bridge.name)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $sheetThing) { thing in
                ThingSheetView(thing: thing)
            }
            .confirmationDialog("Remove \(bridge.name)?",
                                isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Keep its things") {
                    store.remove(bridge.id); dismiss()
                }
                Button("Remove its things too", role: .destructive) {
                    purgeThings(from: bridge.name)
                    store.remove(bridge.id); dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func header(_ bridge: BridgeApp) -> some View {
        HStack(spacing: DS.Space.s3) {
            RoundedRectangle(cornerRadius: DS.Radius.appIcon(56), style: .continuous)
                .fill(DS.fillFaint)
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: BridgeGlyph.symbol(for: bridge.name))
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(DS.textSecondary)
                )
                .padding(3)
                .overlay(Circle().strokeBorder(bridge.status.color, lineWidth: 2))
            VStack(alignment: .leading, spacing: 2) {
                Text(bridge.name).dsText(.heading22).foregroundStyle(DS.textPrimary)
                Text(bridge.statusLine)
                    .dsText(.subhead13)
                    .foregroundStyle(bridge.status == .connected ? DS.textSecondary : bridge.status.color)
            }
            Spacer()
        }
    }

    private func section(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(label)
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
            VStack(spacing: 0) { content() }
                .background(DS.fillFaint,
                            in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
    }

    private func purgeThings(from source: String) {
        let all = (try? modelContext.fetch(FetchDescriptor<Thing>())) ?? []
        let purged = all.filter { $0.source == source }
        SpotlightIndex.remove(ids: purged.map(\.id))
        for thing in purged {
            modelContext.delete(thing)
        }
        try? modelContext.save()
    }
}
