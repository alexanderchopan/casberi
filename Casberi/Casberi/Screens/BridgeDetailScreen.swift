import SwiftUI
import SwiftData
import Photos

/// A bridge's detail — the app, what it can do (sentences), a one-line proof
/// it's delivering, and its controls: Reconnect when broken, Pause/Resume, Remove with
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

    private var bridge: BridgeApp? {
        store.bridges.first { $0.id == bridgeID }
    }
    /// This bridge's single most recent thing — a receipt, not content (the
    /// feed already holds the full record, one "All in Feed" tap away). Was
    /// three full rows; from the feed's own "Manage" capsule that read as a
    /// second, worse copy of the feed you'd just scrolled (user, 2026-07-21).
    /// Cached on appearance rather than re-fetched twice on every body pass.
    @State private var recent: Thing?

    private func loadRecent(source name: String) {
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == name },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        recent = (try? modelContext.fetch(descriptor))?.first
    }

    var body: some View {
        if let bridge {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    header(bridge)

                    if bridge.status == .attention {
                        // Photos on LIMITED access isn't broken and can't be
                        // reconnected out of — the app is seeing exactly the
                        // photos it was given. The remedy is the system's own
                        // picker (widen the set) or Settings (full access), so
                        // that is what this button does instead of a Reconnect
                        // that would change nothing (honesty rule: no control
                        // that doesn't do what it says).
                        if bridge.id == "pho", ScreenshotIngest.accessIsLimited {
                            photosLimitedRemedy
                        } else {
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

                    // Recent = a receipt, not content: proof the bridge is
                    // actually delivering (connect ends in proof), never a
                    // second copy of the feed. Tapping goes straight to the
                    // real record — this page is about the connection, not
                    // the things.
                    if let recent {
                        section("Recent") {
                            Button {
                                FeedFilter.shared.source = bridge.name
                                FeedFilter.shared.tag = "All"
                                if let url = URL(string: "casberi://feed") { openURL(url) }
                            } label: {
                                HStack(spacing: DS.Space.s3) {
                                    KindGlyph(kind: recent.kind, size: 24)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("Last delivered")
                                            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                                        Text(recent.title)
                                            .dsText(.body17).foregroundStyle(DS.textPrimary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(DS.textTertiary)
                                }
                                .padding(.horizontal, DS.Space.s4)
                                .padding(.vertical, DS.Space.s3)
                                .contentShape(Rectangle())
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
            .dsAdaptiveContentWidth()
            .dsPageBackground()
            .dsSoftScrollEdges()
            .onAppear { loadRecent(source: bridge.name) }
            .navigationTitle(bridge.name)
            .navigationBarTitleDisplayMode(.inline)
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

    /// Both ways out of limited access, stated plainly: widen the picked set
    /// here, or hand Photos full access in Settings.
    @ViewBuilder
    private var photosLimitedRemedy: some View {
        VStack(spacing: DS.Space.s2) {
            Text("Casberi can only see the photos you picked, so new screenshots don't arrive on their own.")
                .dsText(.callout15).foregroundStyle(DS.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                DSHaptic.tap()
                presentLimitedPicker()
            } label: {
                Text("Choose more photos")
                    .dsText(.body17).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .dsGlassProminent(tint: DS.tint, cornerRadius: DS.Radius.pill)
            }
            .buttonStyle(.plain)
            Button {
                DSHaptic.tap()
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Text("Allow all photos in Settings")
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(DS.gray100, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    /// The system's own "select more photos" sheet. Needs a presenting
    /// controller, which SwiftUI doesn't hand out — the key window's root is
    /// the same anchor `RedditBridge`/`SpotifyBridge` use for their web auth.
    private func presentLimitedPicker() {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
            .first?.rootViewController
        else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top) { _ in
            Task { @MainActor in
                // Photos just widened what we can see — anything newly visible
                // is OLDER than the walk's cursor, and the walk may already
                // have reported itself finished. Start it over so the newly
                // picked screenshots actually land.
                ScreenshotIngest.resetBackfill()
                _ = ScreenshotIngest.ingest(context: modelContext)
                ScreenshotIngest.backfill(context: modelContext)
            }
        }
    }

    private func header(_ bridge: BridgeApp) -> some View {
        HStack(spacing: DS.Space.s3) {
            BridgeIcon(name: bridge.name, size: 56, circular: true)
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
        modelContext.saveHonestly()
    }
}
