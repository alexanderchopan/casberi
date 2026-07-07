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
    var id: String { rawValue }
}

struct AccountDetailSheet: View {
    let detail: AccountDetail
    @Environment(\.modelContext) private var modelContext
    @AppStorage("privacy.hidePreviews") private var hidePreviews = true
    /// The person's iCloud-sync choice. Off by default — things stay on this
    /// iPhone. This is the real setting the CloudKit engine reads at M1; it
    /// drives the guarantee copy today, and will drive the sync then.
    @AppStorage("icloud.sync") private var icloudSync = false
    @State private var exportURL: URL?
    @State private var confirmDelete = false
    @State private var importing = false
    @State private var importResult: String?
    @State private var deleteResult: String?

    var body: some View {
        DSTray(title: title, height: sheetHeight) {
            dataCard
            controls
        }
        .onAppear { exportURL = buildExport() }
        // The export's other half — the file comes back in whole (dedupe by id).
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { importThings(from: url) }
        }
        .confirmationDialog("Delete all your things?",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete \(thingCount) things", role: .destructive) { deleteEverything() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your things, voice recordings, and photo — all on this iPhone. No undo.")
        }
    }

    private var title: String { "Data" }

    /// The actions row — Export / Import / Delete. The settings (sync, hide
    /// previews) live in the card as toggle rows; only actions live here.
    private var controls: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(spacing: DS.Space.s2) {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        pill("Export", icon: "square.and.arrow.up", tint: true)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { DSHaptic.tap() })
                }
                Button { importing = true } label: {
                    pill("Import", icon: "square.and.arrow.down", tint: false)
                }
                .buttonStyle(.plain)
                Button { confirmDelete = true } label: {
                    Text("Delete everything")
                        .dsText(.label12).foregroundStyle(DS.destructive)
                        .padding(.horizontal, DS.Space.s3).frame(height: 28)
                        .background(DS.gray100, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            if let importResult {
                Text(importResult)
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
            }
            if let deleteResult {
                Text(deleteResult)
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
            }
        }
    }

    private var sheetHeight: CGFloat { 430 }

    // MARK: - Pieces

    /// Data's tray, stat-led — the two numbers tell the story up top (it IS
    /// data), then each privacy guarantee in its own solid green. Plain "Data"
    /// title like every tray; the confidence lives in the body, not a banner.
    private var dataCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(spacing: DS.Space.s2) {
                dataStat("\(thingCount)", "things")
                dataStat(storeSize, "storage")
            }
            // One plain line for the whole on-device story.
            aliveRow("sparkles", DS.confirm, "Private", "Answers run on this iPhone")
            // iCloud sync: the badge shows where things live — green lock here,
            // blue cloud when synced.
            toggleRow(icloudSync ? "icloud.fill" : "lock.iphone",
                      icloudSync ? DS.tint : DS.confirm,
                      "iCloud sync",
                      icloudSync ? "Synced to your iCloud" : "Stays on this iPhone",
                      Binding(get: { icloudSync }, set: { icloudSync = $0; DSHaptic.tap() }))
            toggleRow(hidePreviews ? "eye.slash.fill" : "eye",
                      hidePreviews ? DS.confirm : DS.textSecondary,
                      "Hide previews", "Blur your things in the app switcher",
                      Binding(get: { hidePreviews }, set: { hidePreviews = $0; DSHaptic.tap() }))
        }
    }

    /// A story number — big and bold, with its plain label beneath. Tabular
    /// digits so counts don't jitter as they change.
    private func dataStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).dsText(.heading22).foregroundStyle(DS.textPrimary)
                .monospacedDigit()
            Text(label).dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
        .padding(DS.Space.s3)
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

    private func pill(_ label: String, icon: String, tint: Bool) -> some View {
        HStack(spacing: DS.Space.s1) {
            Image(systemName: icon).font(.system(size: 12, weight: .medium))
            Text(label).dsText(.label12)
        }
        .foregroundStyle(tint ? DS.tint : DS.textSecondary)
        .padding(.horizontal, DS.Space.s3).frame(height: 28)
        .background(tint ? DS.tintDim : DS.gray100, in: Capsule(style: .continuous))
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
        let things = ((try? modelContext.fetch(FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        ))) ?? []).filter { !$0.isSample }   // samples are never yours to export
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
                "pinned": t.pinned,
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
                pinned: item["pinned"] as? Bool ?? false,
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
                        deleteResult = "Deleted — this iPhone and iCloud."
                    }
                }
            }
        } else {
            deleteResult = "Deleted from this iPhone."
        }
        DSHaptic.success()
    }
}
