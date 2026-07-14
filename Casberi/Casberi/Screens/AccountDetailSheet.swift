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
    /// Your AI (prd §67) — draft, outcome line, and a mirrored connected list
    /// with each key's hint (AIKey isn't observable, and the sheet re-renders
    /// per keystroke in the paste field — Keychain reads can't sit in body).
    @State private var keyDraft = ""
    @State private var keyResult: String?
    /// A rejected key must READ as a failure — same muted gray as success
    /// would look like it saved (honesty rule).
    @State private var keyResultIsError = false
    @State private var keyChecking = false
    @State private var connectedKeys: [(provider: AIProvider, hint: String)] =
        AIKey.connected.map { ($0, AIKey.hint($0)) }

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
        case .key: "Your AI"
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
        // One connected provider fits the base; each further one adds a row.
        case .key: 460 + CGFloat(max(connectedKeys.count - 1, 0)) * 60
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

    /// Your AI (prd §67) — the overview of every connected key, stated
    /// honestly: answers run on this iPhone by default; each connected
    /// provider adds its own "Try with <name>" you tap per answer. One paste
    /// field connects a detectable key from here (the shape picks the
    /// provider, no menu); each provider's app page in Apps carries the same
    /// connect. Keys go to the Keychain and each to its own provider — never
    /// to us (there is no us to send them to).
    private var keyCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            if connectedKeys.isEmpty {
                aliveRow("key.fill", DS.textSecondary,
                         "Your AI keys",
                         "Answers run on this iPhone until you add one")
            } else {
                ForEach(connectedKeys, id: \.provider.rawValue) { entry in
                    HStack(spacing: DS.Space.s3) {
                        aliveRow("key.fill", DS.confirm,
                                 entry.provider.label,
                                 "In the Keychain \(entry.hint)")
                        Spacer(minLength: 0)
                        Button {
                            DSHaptic.tap()
                            // The shared disconnect — the key goes AND the
                            // app's seat stops claiming it (honesty rule).
                            AIKey.disconnect(entry.provider, store: store)
                            refreshKeys()
                            keyResultIsError = false
                            keyResult = "\(entry.provider.label) removed — answers stay on this iPhone."
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(DS.destructive)
                                .frame(width: 44, height: 44)
                                .background(DS.gray100, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text("Bring a key from Claude, GPT, Gemini, or Venice and every answer offers a \"Try with\" chip naming it — the question and the few matched things go straight from this iPhone to that provider, only when you tap. Each bills your key directly.")
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Space.s3) {
                SecureField("sk-ant-…, sk-…, or AIza…", text: $keyDraft)
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
            if let keyResult {
                Text(keyResult)
                    .dsText(.callout15)
                    .foregroundStyle(keyResultIsError ? DS.attention : DS.textSecondary)
                    .settleIn()
            }
            Text("Keys live in this iPhone's Keychain, each going only to its own provider. A Venice key has no tell-tale shape — connect it from Venice's page in Apps.")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Re-reads the connected keys after any action — the one mirror the
    /// whole card renders from.
    private func refreshKeys() {
        connectedKeys = AIKey.connected.map { ($0, AIKey.hint($0)) }
    }

    /// The settings paste path — detect the provider from the key's shape (a
    /// shape nobody claims is rejected up front, never guessed at; Venice's
    /// shapeless keys connect from its app page, where the provider is
    /// known), then the SAME shared connect the app pages use: validated by
    /// the provider, saved, and seated in BridgeStore — so the Apps tile and
    /// this sheet never disagree about the same key.
    private func saveKey() {
        let candidate = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }
        guard let provider = AIProvider.detect(candidate) else {
            keyResultIsError = true
            keyResult = "That doesn't look like a Claude, GPT, or Gemini key — check it, or connect Venice from its page in Apps."
            return
        }
        keyChecking = true
        keyResult = nil
        Task { @MainActor in
            let outcome = await AIKey.connect(candidate, provider: provider, store: store)
            keyChecking = false
            switch outcome {
            case .accepted:
                refreshKeys()
                keyDraft = ""
                DSHaptic.success()
                keyResultIsError = false
                keyResult = "Saved — answers now offer \"Try with \(provider.label)\"."
            case .rejected:
                keyResultIsError = true
                keyResult = "\(provider.label) didn't accept that key — check it and try again."
            case .unreachable:
                keyResultIsError = true
                keyResult = "Couldn't reach \(provider.offerName) — check your connection and try again."
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
        try? modelContext.save()
        SpotlightIndex.index(added)
        DSHaptic.success()
        importResult = added.isEmpty
            ? "Nothing new — everything in that file is already here."
            : "\(added.count) thing\(added.count == 1 ? "" : "s") came back."
    }

    private func deleteEverything() {
        let things = (try? modelContext.fetch(FetchDescriptor<Thing>())) ?? []
        for thing in things { modelContext.delete(thing) }
        try? modelContext.save()
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
        MCPPairing.reset()
        let credentialBacked = Set(
            TokenBridge.allCases.map(\.bridgeID)
            + ["steam", "twitch", "gmail", "icloudmail"]
            // The AI-key seats (2026-07-14) — their keys just left the vault,
            // so their tiles stop claiming a connection they no longer have.
            + AIProvider.allCases.map(\.seatID)
        )
        store.bridges.removeAll { credentialBacked.contains($0.id) }
        refreshKeys()
        HandOffState.refresh(connected: Set(
            store.bridges.filter { $0.status == .connected }
                .map { $0.name.lowercased() }))
        DSHaptic.success()
        deleteResult = "Access removed — every token and key. Your things stayed."
    }
}
