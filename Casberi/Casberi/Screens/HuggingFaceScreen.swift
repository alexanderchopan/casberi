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
    @State private var lastResult: BridgeProof?
    @FocusState private var fieldFocused: Bool

    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?
    /// This week's rows per watched author, for the roster's subline and its
    /// active/quiet split.
    @State private var weekly: [String: (week: Int, new: Bool)] = [:]

    var body: some View {
        AccountPage(
            name: "Hugging Face", seatID: "huggingface", source: "Hugging Face",
            state: AccountPageState.of(name: "Hugging Face", seatID: "huggingface",
                                       connected: hf.connected, store: store),
            intro: "New models, datasets and Spaces from the people you follow. Downloads and likes are counts, not news.",
            mode: .noAccount,
            rows: rows,
            query: authorField,
            onRemoveRow: unwatch,
            teardown: { HuggingFaceStore.shared.disconnect() },
            sheet: $sheet,
            act: { addBlock },
            more: { papersBlock },
            keySheet: { EmptyView() }
        )
        .onAppear {
            countWeek()
            // Opening the page doesn't connect — watching an author or
            // switching papers on does. Viewing is not consent.
            if hf.connected { Task { await sync() } }
        }
        .onChange(of: hf.authors) { _, _ in countWeek() }
    }

    // MARK: - The roster

    /// One row per watched author. The square-marked "Watching N" list with
    /// its own Remove is the chassis's now — the subline says what the author
    /// published this week rather than repeating the URL the name already is.
    private var rows: [AccountPageShape.Row] {
        hf.authors.map { author in
            let counted = weekly[author.lowercased()] ?? (week: 0, new: false)
            return AccountPageShape.Row(
                id: author, title: author,
                subline: AccountPageShape.subline(nouns: String(localized: "models, datasets, Spaces"),
                                                  weekCount: counted.week),
                weekCount: counted.week, hasNew: counted.new,
                isYou: false, avatarURL: nil)
        }
    }

    /// This week's rows per author — `HuggingFaceIngest` stamps the owner as
    /// the thing's `authorHandle`.
    private func countWeek() {
        weekly = AccountWeek.counts(source: "Hugging Face", seatID: "huggingface",
                                    context: modelContext) { $0.authorHandle }
    }


    // MARK: - Sections

    @ViewBuilder private var addBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            DSSlabField(placeholder: hf.connected
                            ? AccountPageShape.findPlaceholder(String(localized: "an org or person"))
                            : String(localized: "Org or username"),
                        text: $authorField, actionLabel: String(localized: "Watch"),
                        focus: $fieldFocused, action: watch)
            BridgeSyncStatusRows(syncing: syncing,
                                 syncingLine: String(localized: "Reading the hub…"),
                                 proof: lastResult)
            // Names the accepted shapes, because pasting a model page is
            // how most people will arrive (`normalize` takes the owner).
            DSSlabNote(text: "A name like meta-llama, or any Hugging Face link.", plain: true)
        }
    }

    /// Daily Papers is its own switch, not a watched author — it follows
    /// Hugging Face's curation rather than anyone's output, and we NAME whose
    /// ranking it is (the GeckoTerminal honesty rule).
    @ViewBuilder private var papersBlock: some View {
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
            DSSlabNote(text: "Hugging Face's own daily pick — each lands with its abstract.", plain: true)
        }
    }


    // MARK: - Actions

    private func watch() {
        let name = HuggingFaceStore.normalize(authorField)
        guard !name.isEmpty else { return }
        guard hf.add(name) else {
            lastResult = .says(String(localized: "Already watching \(name)."))
            authorField = ""
            return
        }
        authorField = ""
        fieldFocused = false
        DSHaptic.tap()
        countWeek()
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
                lastResult = .landed(added)
                let proof = added > 0
            ? String(localized: "\(added) in")
            : String(localized: "Synced just now")
                store.registerConnected(id: "huggingface", name: "Hugging Face", proof: proof,
                                        can: ["Reads new models, datasets and Spaces from the authors you watch.",
                                              "Read-only — never publishes, stars, or downloads weights."])
            } else {
                lastResult = .failed(String(localized: "Couldn't reach Hugging Face — check your connection."))
            }
        } while syncPending && hf.connected
    }
}
