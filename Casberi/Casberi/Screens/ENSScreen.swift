import SwiftUI
import SwiftData

/// ENS, connected — follow a name and know where it stands (prd §534).
///
/// The screen's whole act is typing a name, which is what makes this a seat
/// rather than another wallet-detected protocol (§515a). Keyless: ENS's own
/// metadata service, one GET per name, no account and no key.
///
/// Two things it deliberately does NOT do. It never registers or renews —
/// that is somebody's money and this app's standing promise is that a
/// signature happens elsewhere (§112) — and it never claims a name is
/// available off a failed read: only an explicit 404 from the registrar's own
/// metadata means nobody holds it.
struct ENSScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store

    @State private var field = ""
    @State private var working = false
    @State private var result: String?
    @State private var resultIsError = false
    @State private var syncing = false
    /// The follow rows — one per name, the follow itself.
    @State private var followed: [Thing] = []
    /// Names the wallet already found and this seat doesn't follow yet.
    @State private var suggestions: [String] = []
    /// The readings behind each row's standing line. Read from `ENSState`
    /// rather than parsed back out of a row's title (prd §363's rule).
    @State private var readings: [String: ENSState.Reading] = [:]
    @State private var openThing: Thing?
    @FocusState private var fieldFocused: Bool

    /// What the typed text would actually follow — nil while it isn't a name
    /// this seat can stand behind, which is what arms the verb. The field
    /// accepts a bare label and an `app.ens.domains` link, so the normalized
    /// form is also what the preview line shows: the app showing its working
    /// before you commit (§511's own reason for the address preview).
    private var candidate: String? { ENSName.normalized(field) }

    var body: some View {
        List {
            BridgeSetupHeader(
                name: "ENS",
                mode: .noAccount,
                intro: "Follow a name below and it says when it expires — including the ninety days after, when only its owner can still renew it.",
                connected: !followed.isEmpty)
            if !followed.isEmpty {
                RoomDoor(name: "ENS", source: ENSWatch.source)
                    .listRowSeparator(.hidden)
            }
            addSection.listRowSeparator(.hidden)
            if !suggestions.isEmpty { suggestionsSection }
            if !followed.isEmpty { followedSection }
            if !followed.isEmpty {
                BridgeDisconnectSection(bridgeID: ENSWatch.seatID, name: ENSWatch.source,
                                        teardown: {
                                            ENSWatch.unfollowAll(context: modelContext)
                                            load()
                                        })
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "ENS")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("ENS")
        .sheet(item: $openThing) { thing in
            ThingSheetView(thing: thing)
        }
        .onAppear {
            load()
            // Opening the screen doesn't connect — following a name does.
            if !followed.isEmpty { Task { await sync() } }
        }
    }

    // MARK: - Sections

    private var addSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSSlabField(placeholder: String(localized: "A name, or one you're waiting on"),
                            text: $field,
                            actionLabel: String(localized: "Follow"),
                            focus: $fieldFocused,
                            isArmed: candidate != nil,
                            action: followTyped)
                if let candidate, candidate != field.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                    // Only when the two differ: echoing back exactly what was
                    // typed is a line that says nothing, and this exists to
                    // show the ONE thing the person can't see — that `vitalik`
                    // and a pasted link both resolve to the same name.
                    Text(candidate)
                        .dsText(.callout15).foregroundStyle(DS.textSecondary)
                }
                BridgeSyncStatusRows(syncing: working || syncing,
                                     syncingLine: working
                                        ? String(localized: "Following…")
                                        : String(localized: "Reading the registrar…"),
                                     result: result, resultIsError: resultIsError)
                // The screen's one note, and it carries the honesty fact rather
                // than the pitch: `.eth` is the only thing with a registrar
                // expiry to read, so a `.com` or a subname is refused at the
                // field instead of following into a row that can never speak.
                DSSlabNote(text: "Second-level .eth names only — a subname's lifetime belongs to its parent, and an imported .com expires in DNS where no ENS read can see it.")
            }
        }
        .dsSlabSection()
    }

    /// Names the wallet already found. One tap each — never followed on our
    /// own (§515a: a seat must not light up for work nobody asked for).
    private var suggestionsSection: some View {
        Section {
            ForEach(suggestions, id: \.self) { name in
                BridgeSearchResultRow(
                    imageURL: nil, fallbackIcon: "ENS",
                    title: name,
                    subtitle: String(localized: "Found on a wallet you watch"),
                    action: { follow(name) })
            }
        } header: {
            Text("From your wallets").dsText(.callout15).foregroundStyle(DS.textSecondary)
        }
    }

    private var followedSection: some View {
        Section {
            ForEach(followed.keyed) { row in
                // Corollary 3 (build 176) — see `ThingRowKeying`.
                if let thing = row.live { followRow(thing) }
            }
        } header: {
            Text(followed.count == 1
                 ? String(localized: "1 name")
                 : String(localized: "\(followed.count) names"))
                .dsText(.callout15).foregroundStyle(DS.textSecondary)
        }
    }

    private func followRow(_ thing: Thing) -> some View {
        let name = rowName(thing)
        return Button {
            DSHaptic.tap()
            openThing = thing
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).dsText(.body17).foregroundStyle(DS.textPrimary)
                if let line = standing(for: name) {
                    Text(line).dsText(.callout15).foregroundStyle(DS.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { unfollow(name) } label: {
                Label("Unfollow", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive) { unfollow(name) } label: {
                Label("Unfollow", systemImage: "trash")
            }
        }
    }

    /// The row's second line — where the name stands, from the stored reading.
    /// Silent until the first read answers: "expires —" with nothing after it
    /// would be a fact we don't have yet dressed as one we do.
    private func standing(for name: String) -> String? {
        guard let reading = readings[name] else { return nil }
        if reading.unregistered { return String(localized: "Nobody has registered it") }
        guard let expiry = reading.expiry else { return nil }
        switch ENSName.stage(expiry: expiry) {
        case .active, .expiring:
            return String(localized: "Expires \(ENSName.dateWord(expiry))")
        case .grace:
            guard let end = ENSName.graceEnd(expiry: expiry) else { return nil }
            return String(localized: "Expired — the owner can renew until \(ENSName.dateWord(end))")
        case .premium, .released:
            return String(localized: "Released — anyone can register it")
        case .unregistered:
            return String(localized: "Nobody has registered it")
        }
    }

    private func rowName(_ thing: Thing) -> String {
        thing.authorHandle ?? thing.sourceRef.flatMap(ENSName.name(fromRef:)) ?? thing.title
    }

    // MARK: - Acts

    private func followTyped() {
        guard let name = candidate else {
            result = String(localized: "That isn't a .eth name this can follow.")
            resultIsError = true
            return
        }
        follow(name)
    }

    private func follow(_ raw: String) {
        working = true
        resultIsError = false
        result = nil
        switch ENSWatch.follow(raw, context: modelContext) {
        case .invalid:
            result = String(localized: "That isn't a .eth name this can follow.")
            resultIsError = true
        case .already:
            result = String(localized: "Already following that name.")
        case .followed(let thing), .adopted(let thing):
            field = ""
            fieldFocused = false
            result = String(localized: "Following \(rowName(thing)).")
        }
        working = false
        ENSWatch.registerBridge(store: store, context: modelContext)
        load()
        Task { await sync() }
    }

    private func unfollow(_ name: String) {
        DSHaptic.tap()
        ENSWatch.unfollow(name, context: modelContext)
        ENSWatch.registerBridge(store: store, context: modelContext)
        load()
    }

    private func load() {
        followed = ENSWatch.rows(context: modelContext)
        suggestions = ENSWatch.suggestions(context: modelContext)
        readings = ENSState.all()
    }

    private func sync() async {
        guard !syncing else { return }
        syncing = true
        _ = await ENSIngest.refresh(context: modelContext)
        syncing = false
        load()
    }
}
