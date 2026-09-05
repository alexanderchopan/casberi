import SwiftUI
import SwiftData

/// AWS, connected (2026-08-30) — three fields, then what needs attention.
///
/// Trello's/App Store Connect's shape: every field is required for the first
/// two, and all three save TOGETHER, because the only way to validate an AWS
/// key pair is a real signed request (`sts:GetCallerIdentity`). Region is
/// plain text with a sane default, not a picker — AWS adds regions faster
/// than a hand-kept list could track, and a typo there fails the very next
/// request with an honest "couldn't reach" rather than a wrong answer.
struct AWSScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.openURL) private var openURL

    @State private var showConnection = false
    @State private var accessKeyIDField = ""
    @State private var secretKeyField = ""
    @State private var regionField = AWSAuth.defaultRegion

    @State private var credentialVersion = 0
    @State private var connecting = false
    @State private var syncing = false
    @State private var result: BridgeProof?
    @State private var doorTapped = false

    @State private var recent: [Thing] = []
    @State private var standing: AWSStanding?

    private var hasKey: Bool {
        _ = credentialVersion
        return AWSAuth.configured
    }

    private var bridge: TokenBridge { .aws }

    private var hasBothRequired: Bool {
        !accessKeyIDField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !secretKeyField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        BridgeSetupPage(name: "AWS") {
            if hasKey {
                // Connected (prd §186): the credential form retires behind one
                // door, and identity, live proof and what this can do take the
                // screen. This bridge stores only the secret — in the Keychain
                // — so it leads with its own name over a truthful note about
                // HOW it is connected, never an account name we would guess.
                BridgeConnectedState(
                    bridgeID: bridge.bridgeID,
                    name: "AWS",
                    connectionNote: String(localized: "Your \(bridge.credentialNoun) · stored in \(DS.device)'s Keychain"),
                    capabilitiesFallback: [bridge.canLine],
                    openConnection: { showConnection = true })
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                BridgeSetupHeader(
                    name: "AWS",
                    mode: .pasteKey,
                    intro: "Add a read-only key pair and what needs you keeps arriving — a firing alarm, a failed deploy, a spend anomaly. This only ever reads.",
                    connected: hasKey)
            }
            if hasKey {
                RoomDoor(name: "AWS", source: AWSShape.source)
                    .listRowSeparator(.hidden)
            }
            if hasKey {
                standingSection.listRowSeparator(.hidden)
                if !recent.isEmpty {
                    RecentThingsSection(header: "Landed", things: recent.live)
                }
            } else {
                keySection.listRowSeparator(.hidden)
            }
        }
        .sheet(isPresented: $showConnection) {
            BridgeConnectionSheet(title: "AWS") {
                keySection
                removeSection
            }
        }
        .onAppear {
            load()
            if hasKey { Task { await sync() } }
        }
    }

    private func openDoor(_ url: URL) {
        doorTapped = true
        openURL(url)
    }

    // MARK: - Not connected: the three fields

    private var keySection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if let url = bridge.setupURL {
                    if doorTapped {
                        DSSlabDoor(title: bridge.doorTitle,
                                   detail: bridge.doorHost,
                                   systemImage: "arrow.up.right") { openDoor(url) }
                    } else {
                        DSSlabButton(title: bridge.doorTitle,
                                     detail: bridge.doorHost,
                                     systemImage: "arrow.up.right") {
                            DSHaptic.tap()
                            openDoor(url)
                        }
                    }
                }
                BridgeStepLines(steps: bridge.steps, startingAt: 2,
                                numbered: false, acknowledges: true,
                                doneThrough: hasBothRequired ? 4 : 0)
                DSCheckList(lines: ["Reads alarms, deploys, cost, and a resource count",
                                    "Never creates, changes, or deletes anything"])
                DSSlabField(placeholder: "Access Key ID (AKIA…)",
                            text: $accessKeyIDField, actionLabel: "",
                            action: {})
                DSSlabField(placeholder: bridge.placeholder,
                            text: $secretKeyField, actionLabel: "", secure: true,
                            action: {})
                // Region is armed by the other two, not by its own value — a
                // typed default is already a real answer.
                DSSlabField(placeholder: "Region (e.g. us-east-1)",
                            text: $regionField, actionLabel: "Save",
                            isArmed: hasBothRequired,
                            action: save)
                DSSlabNote(text: "Cost Explorer always reads from us-east-1 — AWS's own rule, not a mistake here. Every other read uses the region above.")
                BridgeSyncStatusRows(syncing: connecting,
                                     syncingLine: String(localized: "Checking the key pair…"),
                                     proof: result)
            }
        }
        .dsSlabSection()
    }

    // MARK: - Connected: what's standing

    private var standingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if let standing {
                    Text(AWSRoom.headline(standing))
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                    if let resources = AWSRoom.resourceLine(standing) {
                        Text(resources)
                            .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    }
                    Text(standing.region)
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                } else {
                    Text("Reading your account…")
                        .dsText(.callout15).foregroundStyle(DS.textTertiary)
                }
                BridgeSyncStatusRows(syncing: syncing,
                                     syncingLine: String(localized: "Reading AWS…"),
                                     proof: result)
                DSSlabNote(text: "Alarms, deploys and a spend anomaly land on their own.")
            }
        }
        .dsSlabSection()
    }

    // MARK: - Actions

    private func load() {
        recent = recentBridgeThings(source: AWSShape.source, context: modelContext)
        standing = AWSRoomSource.compose()
    }

    private enum Outcome { case ok(String, String), refused, unreachable }

    /// One signed GET — `sts:GetCallerIdentity`, the free, keyless-of-policy
    /// check every AWS principal can answer, so there is no way to validate a
    /// key pair except by using it exactly like this.
    private func validate(accessKeyID: String, secretKey: String) async -> Outcome {
        let identity = await AWSFetch.callerIdentity(accessKeyID: accessKeyID, secretKey: secretKey)
        if identity.status == 200 { return .ok(identity.account, identity.arn) }
        if identity.status == 0 { return .unreachable }
        return .refused
    }

    private func save() {
        let accessKeyID = accessKeyIDField.trimmingCharacters(in: .whitespacesAndNewlines)
        let secretKey = secretKeyField.trimmingCharacters(in: .whitespacesAndNewlines)
        let region = regionField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessKeyID.isEmpty, !secretKey.isEmpty else {
            fail(String(localized: "Both the Access Key ID and the Secret Access Key are needed."))
            return
        }
        connecting = true
        result = nil
        // Stored BEFORE the check, ASC's exact reason: the check IS a real
        // signed request, and there is no other way to validate an AWS key
        // pair. Torn back out on failure below.
        TokenVault.set(secretKey, for: AWSAuth.secretVaultKey)
        AWSAuth.setAccessKeyID(accessKeyID)
        AWSAuth.region = region.isEmpty ? AWSAuth.defaultRegion : region

        Task {
            let outcome = await validate(accessKeyID: accessKeyID, secretKey: secretKey)
            connecting = false
            switch outcome {
            case .ok(let account, _):
                accessKeyIDField = ""; secretKeyField = ""
                credentialVersion += 1
                // One shape for one event (§608): `.connected` renders
                // "Connected" or "Connected — <what>", so the account name
                // is the detail rather than a second sentence.
                result = .connected(account.isEmpty ? nil : account)
                DSHaptic.success()
                AWSWatch.registerBridge(store: store)
                load()
                await sync()
            case .refused:
                undo(String(localized: "AWS refused that key pair. Check both values, and that the region above is spelled the way AWS spells it."))
            case .unreachable:
                undo(String(localized: "Couldn't reach AWS — check your connection."))
            }
        }
    }

    private func undo(_ message: String) {
        AWSAuth.clear()
        credentialVersion += 1
        fail(message)
    }

    private func fail(_ message: String) {
        result = .failed(message)
    }

    private func sync() async {
        guard !syncing, hasKey else { return }
        syncing = true
        defer { syncing = false }
        let added = await AWSIngest.refresh(context: modelContext)
        load()
        AWSWatch.registerBridge(store: store)
        if let added {
            result = added > 0 ? .landed(added) : bridge.emptyReadNote.map(BridgeProof.says) ?? .upToDate
        } else {
            result = .failed(String(localized: "Couldn't reach AWS — check your connection."))
        }
        if let alarm = AWSIngest.lastPassAlarm {
            chrome.flash(alarm, tone: .failure, seconds: 3.5)
        }
    }

    /// The way out — the shared row, behind the Connection door with the form
    /// it belongs to (prd §186/§608).
    private var removeSection: some View {
        BridgeDisconnectSection(bridgeID: bridge.bridgeID,
                                name: "AWS",
                                teardown: {
                                    AWSAuth.clear()
                                    credentialVersion += 1
                                    load()
                                })
    }

}
