import SwiftUI
import SwiftData

/// Hugging Face, connected — what the AI world shipped today. Watch an org or
/// a person and their new models, datasets and Spaces land as links; switch on
/// Daily Papers and Hugging Face's own curated list lands with abstracts and
/// cover images.
///
/// No account, no key: every read is the hub's public API, fetched straight by
/// this device. Read-only — nothing here publishes, stars, or downloads
/// weights.
struct HuggingFaceScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Bindable private var hf = HuggingFaceStore.shared
    @State private var authorField = ""
    @State private var syncing = false
    /// An author added while a sync is mid-flight requeues it, so the new
    /// watch lands now rather than next visit (the GeckoTerminal lesson).
    @State private var syncPending = false
    @State private var lastResult: String?
    @State private var lastResultIsError = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        List {
            BridgeSetupHeader(
                name: "Hugging Face",
                mode: .noAccount,
                intro: "Name the people and orgs you follow below, and their new models, datasets and Spaces arrive. Downloads and likes are counts, not news.",
                connected: hf.connected)
            // The door leads the connected page, never trails it — see
            // `RoomDoor`. Below a watchlist that grows with every author
            // you add, the one control saying "your things are through here"
            // is the one you have to scroll to find.
            if hf.connected {
                RoomDoor(name: "Hugging Face", source: "Hugging Face")
                    .listRowSeparator(.hidden)
            }
            addSection.listRowSeparator(.hidden)
            papersSection.listRowSeparator(.hidden)
            if !hf.authors.isEmpty {
                watchlistSection
            }
            if hf.connected {
                BridgeDisconnectSection(
                    bridgeID: "huggingface", name: "Hugging Face",
                    teardown: { HuggingFaceStore.shared.disconnect() }
                ).listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Hugging Face")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Hugging Face")
        .onAppear {
            // Opening the screen doesn't connect — watching an author or
            // switching papers on does. Viewing is not consent.
            if hf.connected { Task { await sync() } }
        }
    }

    // MARK: - Sections

    private var addSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSSlabField(placeholder: String(localized: "Org or username"),
                            text: $authorField, actionLabel: String(localized: "Watch"),
                            focus: $fieldFocused, action: watch)
                BridgeSyncStatusRows(syncing: syncing,
                                     syncingLine: String(localized: "Reading the hub…"),
                                     result: lastResult, resultIsError: lastResultIsError)
                // Names the accepted shapes, because pasting a model page is
                // how most people will arrive (`normalize` takes the owner).
                DSSlabNote(text: "A name like meta-llama, or any Hugging Face link.")
            }
        }
        .dsSlabSection()
    }

    /// Daily Papers is its own switch, not a watched author — it follows
    /// Hugging Face's curation rather than anyone's output, and we NAME whose
    /// ranking it is (the GeckoTerminal honesty rule).
    private var papersSection: some View {
        Section {
            VStack(spacing: DS.Space.s2) {
                DSSlabSwitch(title: String(localized: "Daily Papers"), isOn: Binding(
                    get: { hf.dailyPapers },
                    // Guard on the committed value: a same-value commit must
                    // not invert the switch behind it.
                    set: { on in
                        guard on != hf.dailyPapers else { return }
                        togglePapers(on)
                    }
                ))
                DSSlabNote(text: "Hugging Face's own daily pick — each lands with its abstract.")
            }
        }
        .dsSlabSection()
    }

    private var watchlistSection: some View {
        Section {
            ForEach(hf.authors, id: \.self) { author in
                HStack(spacing: DS.Space.s3) {
                    // Square, not round — an org publishing models is a topic,
                    // not a person (the mark grammar ruling, prd §184).
                    BridgeIcon(name: "Hugging Face", size: DS.Mark.list, circular: false)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(author)
                            .dsText(.body17).foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        Text("huggingface.co/\(author)")
                            .dsText(.label12).foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .dsListCardRow()
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { unwatch(author) } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
                // A swipe has no Mac-mouse equivalent — right-click mirrors it
                // (Mac polish, 2026-07-28).
                .contextMenu {
                    Button(role: .destructive) { unwatch(author) } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text(hf.authors.count == 1 ? "Watching" : "Watching \(hf.authors.count)")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
        }
    }


    // MARK: - Actions

    private func watch() {
        let name = HuggingFaceStore.normalize(authorField)
        guard !name.isEmpty else { return }
        guard hf.add(name) else {
            lastResult = String(localized: "Already watching \(name).")
            lastResultIsError = false
            authorField = ""
            return
        }
        authorField = ""
        fieldFocused = false
        DSHaptic.tap()
        Task { await sync() }
    }

    private func unwatch(_ author: String) {
        hf.remove(author)
        // Its rows leave with it (prd §286). Every release ref carries the
        // owner as its `id`'s prefix — matched on `authorHandle`, which the
        // ingest stamps, rather than by parsing the ref back apart. Papers
        // are Hugging Face's list, not this author's, so they stay.
        FollowPrune.remove(source: "Hugging Face", context: modelContext) {
            $0.authorHandle?.caseInsensitiveCompare(author) == .orderedSame
        }
        DSHaptic.tap()
        Task { await sync() }
    }

    private func togglePapers(_ on: Bool) {
        hf.dailyPapers = on
        if !on {
            FollowPrune.remove(source: "Hugging Face", context: modelContext) {
                $0.sourceRef?.hasPrefix("hf:paper:") == true
            }
        }
        DSHaptic.tap()
        Task { await sync() }
    }

    /// Fetch + land; the bridge's status line carries the proof.
    private func sync() async {
        guard hf.connected else {
            // Unwatching the last author with papers off leaves nothing to
            // sync — clear the seat rather than leave a dead one.
            store.remove("huggingface")
            return
        }
        if syncing { syncPending = true; return }
        syncing = true
        defer { syncing = false }
        repeat {
            syncPending = false
            let added = await HuggingFaceIngest.refresh(context: modelContext)
            // Disconnected mid-sync (teardown ran while this awaited) — don't
            // resurrect the seat the person just removed.
            guard hf.connected else { store.remove("huggingface"); return }
            if let added {
                lastResult = added > 0 ? String(localized: "\(added) new") : String(localized: "Up to date")
                lastResultIsError = false
                let proof = added > 0
            ? String(localized: "\(added) in")
            : String(localized: "Synced just now")
                store.registerConnected(id: "huggingface", name: "Hugging Face", proof: proof,
                                        can: ["Reads new models, datasets and Spaces from the authors you watch.",
                                              "Read-only — never publishes, stars, or downloads weights."])
            } else {
                lastResult = String(localized: "Couldn't reach Hugging Face — check your connection.")
                lastResultIsError = true
            }
        } while syncPending && hf.connected
    }
}
