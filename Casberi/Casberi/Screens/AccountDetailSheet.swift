import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CloudKit

/// Account detail sheets — one pattern for all of them: the facts stated
/// plainly (live numbers where the system can answer), one control cluster
/// when a real control exists, a footnote naming what's coming. Every line
/// is honest about the current build: nothing claims sync, telemetry, or
/// pricing that doesn't exist yet.
enum AccountDetail: String, Identifiable {
    case data
    case key
    var id: String { rawValue }
}

struct AccountDetailSheet: View {
    let detail: AccountDetail
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @AppStorage("privacy.hidePreviews") private var hidePreviews = true
    /// The person's iCloud-sync choice. Off by default — things stay on this
    /// iPhone. This is the real setting the CloudKit engine reads at M1; it
    /// drives the guarantee copy today, and will drive the sync then.
    @AppStorage("icloud.sync") private var icloudSync = false
    @State private var exportURL: URL?
    @State private var confirmDelete = false
    @State private var confirmDeleteAccess = false
    @State private var importing = false
    @State private var importResult: String?
    @State private var deleteResult: String?
    /// Your key (prd §67) — draft, outcome line, and a mirrored configured
    /// flag (AgentKey isn't observable; actions refresh it by hand). The
    /// picker chooses which agent the key belongs to (ruling 2026-07-14:
    /// it's an agent key — Claude, ChatGPT, Gemini, or Venice).
    @State private var keyDraft = ""
    @State private var keyResult: String?
    /// A rejected key must READ as a failure — same muted gray as success
    /// would look like it saved (honesty rule).
    @State private var keyResultIsError = false
    @State private var keyChecking = false
    @State private var keyProvider: AgentProvider = AgentKey.active ?? .anthropic
    @State private var keyConfigured = AgentKey.isConfigured(AgentKey.active ?? .anthropic)

    var body: some View {
        DSTray(title: title, height: sheetHeight) {
            switch detail {
            case .data:
                dataCard
                controls
            case .key:
                keyCard
            }
        }
        .onAppear { if detail == .data { exportURL = buildExport() } }
        // The export's other half — the file comes back in whole (dedupe by id).
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { importThings(from: url) }
        }
        // Two wipes, two verbs (user ruling 2026-07-13): THINGS is your data;
        // ACCESS is the credentials Casberi holds. Each confirm states exactly
        // what goes and what stays — the old single "Delete everything"
        // quietly left every token behind while claiming everything.
        .confirmationDialog("Delete your things?",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete \(thingCount) things", role: .destructive) { deleteEverything() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your things, voice recordings, and photo — this iPhone and iCloud. Your app connections and keys stay. No undo.")
        }
        .confirmationDialog("Delete Casberi's access?",
                            isPresented: $confirmDeleteAccess, titleVisibility: .visible) {
            Button("Delete every token and key", role: .destructive) { deleteAccess() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every token, key, and mail password Casberi holds — connected apps stop syncing and paired clients disconnect. Your things stay. Photos and Calendar access is iOS's; revoke those in Settings. No undo.")
        }
    }

    private var title: String {
        switch detail {
        case .data: "Data"
        case .key: "Your key"
        }
    }

    /// The actions — Export / Import as real buttons on one row, Delete on
    /// its own full-width row (destructive stands alone). The settings (sync,
    /// hide previews) live in the card as toggle rows; only actions live here.
    private var controls: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(spacing: DS.Space.s3) {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        actionLabel("Export", icon: "square.and.arrow.up",
                                    fg: .white, bg: DS.tint)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { DSHaptic.tap() })
                }
                Button { importing = true } label: {
                    actionLabel("Import", icon: "square.and.arrow.down",
                                fg: DS.textPrimary, bg: DS.gray100)
                }
                .buttonStyle(.plain)
            }
            Button { confirmDelete = true } label: {
                actionLabel("Delete things", icon: "trash",
                            fg: DS.destructive, bg: DS.gray100)
            }
            .buttonStyle(.plain)
            Button { confirmDeleteAccess = true } label: {
                actionLabel("Delete access", icon: "key.slash",
                            fg: DS.destructive, bg: DS.gray100)
            }
            .buttonStyle(.plain)
            // Outcome lines arrive with the settle beat — a result, not a flicker.
            if let importResult {
                Text(importResult)
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .settleIn()
            }
            if let deleteResult {
                Text(deleteResult)
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .settleIn()
            }
        }
    }

    /// One action button face — full-height capsule, icon + word.
    private func actionLabel(_ title: String, icon: String,
                             fg: Color, bg: Color) -> some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold))
            Text(title).dsText(.callout15).fontWeight(.semibold)
        }
        .foregroundStyle(fg)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(bg, in: Capsule(style: .continuous))
        .contentShape(Capsule(style: .continuous))
    }

    private var sheetHeight: CGFloat {
        switch detail {
        case .data: 530   // two wipes now — things and access, one row each
        case .key: 500   // +40 for the per-agent capability line (2026-07-21)
        }
    }

    // MARK: - Pieces

    /// Data's tray, stat-led — the two numbers tell the story up top (it IS
    /// data), then each privacy guarantee in its own solid green. Plain "Data"
    /// title like every tray; the confidence lives in the body, not a banner.
    private var dataCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            HStack(spacing: DS.Space.s3) {
                dataStat("\(thingCount)", "things")
                dataStat(storeSize, "storage")
            }
            // One plain line for the whole on-device story.
            aliveRow("sparkles", DS.confirm, "Private", "Answers run on this iPhone")
            // iCloud sync: the badge shows where things live — green lock here,
            // blue cloud when synced. The container binds at launch, so a
            // fresh flip says WHEN it goes live instead of pretending it is.
            toggleRow(icloudSync ? "icloud.fill" : "lock.iphone",
                      icloudSync ? DS.tint : DS.confirm,
                      "iCloud sync",
                      icloudSync
                        ? (SharedStore.cloudSyncActive ? "Synced to your iCloud"
                                                       : "Syncs from your next launch")
                        : (SharedStore.cloudSyncActive ? "Stops syncing from your next launch"
                                                       : "Stays on this iPhone"),
                      Binding(get: { icloudSync }, set: { icloudSync = $0; DSHaptic.tap() }))
            toggleRow(hidePreviews ? "eye.slash.fill" : "eye",
                      hidePreviews ? DS.confirm : DS.textSecondary,
                      "Hide previews", "Blur your things in the app switcher",
                      Binding(get: { hidePreviews }, set: { hidePreviews = $0; DSHaptic.tap() }))
        }
    }

    /// Your key (prd §67) — the BYO escape hatch, stated honestly: answers run
    /// on this iPhone by default; your own agent key adds a "Try with your
    /// key" you tap per answer. The key goes to the Keychain and to the
    /// provider itself — never to us (there is no us to send it to). It's an
    /// AGENT key (ruling 2026-07-14): Claude, ChatGPT, Gemini, Venice, or
    /// Bankr — the picker names the agent, the small print names the company.
    /// Bankr's key could also trade (it's a wallet agent) — the small print
    /// says to mint it read-only, and the answer path prompts "answer only"
    /// regardless (2026-07-16).
    private var keyCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            aliveRow("key.fill", keyConfigured ? DS.confirm : DS.textSecondary,
                     "Agent API key",
                     keyConfigured ? "\(keyProvider.agent) saved in the Keychain \(AgentKey.hint(keyProvider))"
                                   : "Answers run on this iPhone until you add one")
            Text("With your key saved, every answer offers \"Try with your key\" — the question and the few matched things go straight from this iPhone to the agent's provider, only when you tap. They bill your key directly.")
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // What THIS agent adds beyond a plain text answer — changes with
            // the picker below it, so the choice is informed before a key is
            // even saved (honesty rule: capability copy per agent, not one
            // line pretending they're all the same).
            if let capability = keyProvider.capabilityLine {
                Text(capability)
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Picker("Agent", selection: $keyProvider) {
                ForEach(AgentProvider.allCases) { provider in
                    Text(provider.agent).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: keyProvider) {
                keyConfigured = AgentKey.isConfigured(keyProvider)
                keyResult = nil
                keyDraft = ""
            }
            HStack(spacing: DS.Space.s3) {
                SecureField(keyProvider.placeholder, text: $keyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .dsText(.callout15)
                    .padding(.horizontal, DS.Space.s3)
                    .frame(height: 44)
                    .background(DS.fillFaint, in: Capsule(style: .continuous))
                Button { saveKey() } label: {
                    Text(keyChecking ? "Checking…" : "Save")
                        .dsText(.callout15).fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, DS.Space.s4)
                        .frame(height: 44)
                        .background(DS.tint, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(keyChecking || keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if keyConfigured {
                Button {
                    DSHaptic.tap()
                    AgentKey.clear(keyProvider)
                    keyConfigured = false
                    keyResultIsError = false
                    keyResult = AgentKey.isConfigured
                        ? "Removed — answers run on \(AgentKey.active?.agent ?? "") now."
                        : "Removed — answers stay on this iPhone."
                } label: {
                    actionLabel("Remove key", icon: "trash",
                                fg: DS.destructive, bg: DS.gray100)
                }
                .buttonStyle(.plain)
            }
            if let keyResult {
                Text(keyResult)
                    .dsText(.callout15)
                    .foregroundStyle(keyResultIsError ? DS.attention : DS.textSecondary)
                    .settleIn()
            }
            Text("Get a key from the agent's own console — console.anthropic.com (Claude), platform.openai.com (ChatGPT), aistudio.google.com (Gemini), venice.ai (Venice), or bankr.bot/api-keys (Bankr — make it a read-only key; answers never trade). It stays in this iPhone's Keychain and goes only to the provider you chose.")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Saves the key only after its provider accepts it — no dead key sitting
    /// in the Keychain claiming a capability it can't deliver (honesty rule).
    private func saveKey() {
        let candidate = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }
        keyChecking = true
        keyResult = nil
        Task { @MainActor in
            let ok = await AgentAnswer.validate(candidate, provider: keyProvider)
            keyChecking = false
            if ok {
                AgentKey.set(candidate, for: keyProvider)
                keyConfigured = true
                keyDraft = ""
                DSHaptic.success()
                keyResultIsError = false
                keyResult = "Saved — answers now offer \"Try with your key\" on \(keyProvider.agent)."
            } else {
                keyResultIsError = true
                keyResult = "\(keyProvider.company) didn't accept that key — check it and try again."
            }
        }
    }

    /// A story number — big and bold, with its plain label beneath. Tabular
    /// digits so counts don't jitter as they change.
    private func dataStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).dsText(.heading34).foregroundStyle(DS.textPrimary)
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).dsText(.callout15).foregroundStyle(DS.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .padding(DS.Space.s4)
        .background(DS.fillFaint,
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }

    /// The colored squircle badge — the Apps-page glyph in a solid tone. Shared
    /// by every alive row and toggle row.
    private func badge(_ glyph: String, _ tone: Color) -> some View {
        RoundedRectangle(cornerRadius: DS.Radius.appIcon(38), style: .continuous)
            .fill(tone)
            .frame(width: 38, height: 38)
            .overlay(
                Image(systemName: glyph)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }

    /// An alive row — badge + title + live value. The Apps-page grammar, shared
    /// by every dressed-up Account sheet.
    private func aliveRow(_ glyph: String, _ tone: Color, _ title: String, _ value: String) -> some View {
        HStack(spacing: DS.Space.s3) {
            badge(glyph, tone)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).dsText(.body17).foregroundStyle(DS.textPrimary)
                Text(value).dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    /// An alive row that also toggles — badge + title/subtitle + a switch, in
    /// the same row grammar.
    private func toggleRow(_ glyph: String, _ tone: Color, _ title: String,
                           _ subtitle: String, _ isOn: Binding<Bool>) -> some View {
        HStack(spacing: DS.Space.s3) {
            badge(glyph, tone)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).dsText(.body17).foregroundStyle(DS.textPrimary)
                Text(subtitle).dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: isOn).labelsHidden().tint(DS.tint)
        }
    }


    // MARK: - Live facts

    private var thingCount: Int {
        (try? modelContext.fetchCount(FetchDescriptor<Thing>())) ?? 0
    }

    /// The real on-disk total: the SwiftData store (group container's
    /// default.store + its -wal/-shm sidecars) PLUS the sidecars the store
    /// doesn't own — voice recordings and the background photo (both in the
    /// app's own Application Support) and the avatar (in UserDefaults). Counting
    /// the DB alone understated what "Storage" claims.
    private var storeSize: String {
        var bytes: Int64 = 0
        // 1. The SwiftData store and its SQLite sidecars.
        let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        for folder in [base.appendingPathComponent("Library/Application Support"), base] {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            for file in files where file.hasPrefix("default.store") {
                bytes += fileSize(folder.appendingPathComponent(file))
            }
        }
        // 2. Voice recordings.
        let voice = (try? FileManager.default.contentsOfDirectory(
            at: VoiceCapture.folder, includingPropertiesForKeys: nil)) ?? []
        for url in voice { bytes += fileSize(url) }
        // 3. The background photo, and the avatar riding UserDefaults.
        bytes += fileSize(ThemeStore.photoFileURL)
        bytes += Int64(UserDefaults.standard.data(forKey: "profile.avatar")?.count ?? 0)

        guard bytes > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Byte size of one file, 0 if it isn't there.
    private func fileSize(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path))
            .flatMap { $0[.size] as? Int64 } ?? 0
    }

    // MARK: - Controls

    /// Everything as one JSON file — the person's things are the person's.
    private func buildExport() -> URL? {
        let things = (try? modelContext.fetch(FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        ))) ?? []
        let iso = ISO8601DateFormatter()
        let payload: [[String: Any]] = things.map { t in
            var prov: [String: Any] = ["app": t.provenance.app]
            if let a = t.provenance.agent { prov["agent"] = a }
            if let r = t.provenance.run { prov["run"] = r }
            if let m = t.provenance.machine { prov["machine"] = m }
            var dict: [String: Any] = [
                "id": t.id.uuidString,
                "kind": t.kind.rawValue,
                "title": t.title,
                "content": t.content,
                "source": t.source,
                "tags": t.tags,
                "mark": t.mark.rawValue,
                "provenance": prov,
                "createdAt": iso.string(from: t.createdAt),
                "capturedAt": iso.string(from: t.capturedAt),
            ]
            // Only real things carry a source reference (screenshot asset,
            // message id, voice file) — keep it so dedupe survives round-trips.
            if let ref = t.sourceRef { dict["sourceRef"] = ref }
            // Voice audio lives in the store now — it rides the export too,
            // or "everything" wouldn't be true.
            if let audio = t.audio { dict["audio"] = audio.base64EncodedString() }
            return dict
        }
        guard let data = try? JSONSerialization.data(
            withJSONObject: ["things": payload, "exported": iso.string(from: .now)],
            options: [.prettyPrinted, .sortedKeys]) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("casberi-things.json")
        try? data.write(to: url, options: .atomic)
        return url
    }

    /// Reads a Casberi export back in. Things already present (same id) stay
    /// untouched; everything else lands as it was.
    private func importThings(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["things"] as? [[String: Any]] else {
            importResult = "That file isn't a Casberi export."
            return
        }
        let existing = Set(((try? modelContext.fetch(FetchDescriptor<Thing>())) ?? []).map(\.id))
        let iso = ISO8601DateFormatter()
        var added: [Thing] = []
        for item in items {
            guard let idString = item["id"] as? String,
                  let id = UUID(uuidString: idString),
                  !existing.contains(id),
                  let kindRaw = item["kind"] as? String,
                  let kind = ThingKind(rawValue: kindRaw),
                  let title = item["title"] as? String else { continue }
            let source = item["source"] as? String ?? "You"
            let mark = (item["mark"] as? String).flatMap(Mark.init(rawValue:)) ?? .none
            let provenance = (item["provenance"] as? [String: Any]).map {
                Provenance(app: $0["app"] as? String ?? source,
                           agent: $0["agent"] as? String,
                           run: $0["run"] as? String,
                           machine: $0["machine"] as? String)
            }
            let thing = Thing(
                id: id,
                kind: kind,
                title: title,
                content: item["content"] as? String ?? "",
                source: source,
                createdAt: (item["createdAt"] as? String).flatMap { iso.date(from: $0) } ?? .now,
                capturedAt: (item["capturedAt"] as? String).flatMap { iso.date(from: $0) } ?? .now,
                mark: mark,
                tags: item["tags"] as? [String] ?? [],
                provenance: provenance,
                sourceRef: item["sourceRef"] as? String
            )
            if let b64 = item["audio"] as? String,
               let audio = Data(base64Encoded: b64) {
                thing.audio = audio
            }
            modelContext.insert(thing)
            added.append(thing)
        }
        modelContext.saveHonestly()
        SpotlightIndex.index(added)
        DSHaptic.success()
        importResult = added.isEmpty
            ? "Nothing new — everything in that file is already here."
            : "\(added.count) thing\(added.count == 1 ? "" : "s") came back."
    }

    private func deleteEverything() {
        let things = (try? modelContext.fetch(FetchDescriptor<Thing>())) ?? []
        for thing in things { modelContext.delete(thing) }
        modelContext.saveHonestly()
        SpotlightIndex.removeAll()
        // The store doesn't own the sidecars — clear them by hand so
        // "everything" is literally true: voice audio, the background photo,
        // and the avatar. Setting the stores' properties to nil removes the
        // files (or defaults) and refreshes the UI.
        let voice = (try? FileManager.default.contentsOfDirectory(
            at: VoiceCapture.folder, includingPropertiesForKeys: nil)) ?? []
        for url in voice { try? FileManager.default.removeItem(at: url) }
        ThemeStore.shared.backgroundPhoto = nil
        ProfileStore.shared.avatar = nil
        // The iCloud copy goes too — mirroring propagates the deletes, but a
        // zone purge is the definitive clear (it also covers things synced
        // before the toggle was last turned off). Outcome surfaces honestly.
        if SharedStore.cloudKitReady {
            let db = CKContainer(identifier: SharedStore.cloudContainerID).privateCloudDatabase
            let zone = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone")
            db.delete(withRecordZoneID: zone) { _, error in
                Task { @MainActor in
                    if let error, (error as? CKError)?.code != .zoneNotFound {
                        deleteResult = "Deleted here. The iCloud copy couldn't be cleared — check your connection and try again."
                    } else {
                        deleteResult = "Things deleted — this iPhone and iCloud. Your connections and keys stayed."
                    }
                }
            }
        } else {
            deleteResult = "Things deleted from this iPhone. Your connections and keys stayed."
        }
        DSHaptic.success()
    }

    /// The other wipe (user ruling 2026-07-13): every credential Casberi
    /// holds, gone in one move — the vault (bridge tokens, the Steam key,
    /// Twitch tokens, mail passwords, the Anthropic key) and the MCP pairing
    /// token (paired clients lose their way in). The bridges those
    /// credentials powered unregister so nothing claims a connection it no
    /// longer has. Things stay untouched.
    private func deleteAccess() {
        TokenVault.deleteAll()
        TokenBridge.allCases.forEach { $0.onRemove() }   // drop any cached non-thing state too
        MCPPairing.reset()
        let credentialBacked = Set(
            TokenBridge.allCases.map(\.bridgeID)
            + ["steam", "twitch", "gmail", "icloudmail"]
        )
        store.bridges.removeAll { credentialBacked.contains($0.id) }
        HandOffState.refresh(connected: Set(
            store.bridges.filter { $0.status == .connected }
                .map { $0.name.lowercased() }))
        DSHaptic.success()
        deleteResult = "Access removed — every token and key. Your things stayed."
    }
}
