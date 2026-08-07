import SwiftUI
import SwiftData

/// App Store Connect, connected (prd §323) — three fields, then what Apple can
/// see of your apps.
///
/// It is the longest connect form in the app, and every field is load-bearing:
/// Apple's API takes a private key, the ten-character ID that names it, and an
/// issuer ID, and a token signed without any one of them is refused with a 401
/// indistinguishable from a wrong key. Trello needed two credentials and got a
/// two-stage screen; this needs three and takes them **together, in one save**,
/// because unlike Trello's the second value is not minted using the first —
/// all three are printed on the same page of App Store Connect, and asking for
/// them one at a time would be three round trips to the same tab.
///
/// The issuer ID is the one field that may legitimately be left EMPTY, and the
/// note beside it says so: empty is how Apple distinguishes an INDIVIDUAL key
/// from a team key, and it changes which claim gets signed (see
/// `ASCJWT.payloadJSON`). It is a real choice, not an omission, so it sits on
/// the control it governs rather than in a footer.
///
/// Two states, one at a time (the §83 corollary about disabled controls that
/// still paint a live background): nothing stored → the three fields; a key →
/// what it can see, what has landed, and Disconnect.
struct AppStoreConnectScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.openURL) private var openURL

    @State private var keyField = ""
    @State private var keyIDField = ""
    @State private var issuerField = ""

    /// Bumped whenever the credentials change, so the derived reads below
    /// re-evaluate. The Keychain stays the source of truth — mirroring it into
    /// @State meant hand-kept assignments that could disagree with it (the
    /// PostHog contract).
    @State private var credentialVersion = 0

    @State private var connecting = false
    @State private var syncing = false
    @State private var result: String?
    @State private var resultIsError = false
    @State private var flipTrigger = 0

    @State private var recent: [Thing] = []
    @State private var apps: [String] = []

    private var hasKey: Bool {
        _ = credentialVersion
        return ASCAuth.configured
    }

    private var bridge: TokenBridge { .appStoreConnect }

    /// The two fields that are genuinely required. The issuer is not one of
    /// them — see the screen's note.
    private var hasBothRequired: Bool {
        !keyField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !keyIDField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        List {
            BridgeSetupHeader(
                name: "App Store Connect",
                mode: .pasteKey,
                intro: "Add a key and what happens to your apps keeps arriving: a review verdict, a customer review, a build about to expire. Apple has no read-only role, so the promise is ours — Casberi only ever reads.",
                connected: hasKey,
                flipTrigger: flipTrigger)
            if hasKey {
                appsSection.listRowSeparator(.hidden)
                if !recent.isEmpty {
                    RecentThingsSection(header: "Landed", things: recent.live)
                }
                BridgeDisconnectSection(bridgeID: bridge.bridgeID,
                                        name: "App Store Connect",
                                        teardown: {
                                            TokenVault.delete(ASCAuth.keyVaultKey)
                                            ASCAuth.clear()
                                            credentialVersion += 1
                                            load()
                                        })
                    .listRowSeparator(.hidden)
            } else {
                keySection.listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "App Store Connect")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("App Store Connect")
        .onAppear {
            load()
            if hasKey { Task { await sync() } }
        }
    }

    // MARK: - Not connected: the three fields

    private var keySection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if let url = bridge.setupURL {
                    // Step one, doing itself (prd §218).
                    DSSlabButton(title: "Open \(bridge.setupURLLabel)",
                                 systemImage: "arrow.up.right") {
                        DSHaptic.tap()
                        openURL(url)
                    }
                }
                BridgeStepLines(steps: [bridge.steps[0]], startingAt: 2)
                // The four reads, as the honest ask. Unlike Stripe's and
                // PostHog's checklists this is NOT a set of boxes to tick —
                // Apple grants a ROLE, and the list is what that role will let
                // this app see. Naming them here is the only way somebody can
                // check afterwards that nothing else was read, which is the
                // whole substitute for a scope this API doesn't offer.
                DSCheckList(lines: ["Your apps, and their review status",
                                    "Your customer reviews",
                                    "Your builds, and when they expire",
                                    "Nothing else — no sales, no analytics"])
                BridgeStepLines(steps: Array(bridge.steps.dropFirst()), startingAt: 3)
                // Three slabs, ONE verb — `DSSlabField`'s empty-`actionLabel`
                // form, which exists for exactly this (Steam's profile beside
                // its key, Mail's address beside its app password). A NEXT on
                // each would be two dead controls and read as three ways to
                // connect; the verb belongs to the last field, where the act
                // completes.
                DSSlabField(placeholder: bridge.placeholder,
                            text: $keyField, actionLabel: "", secure: true,
                            action: {})
                DSSlabField(placeholder: "Key ID",
                            text: $keyIDField, actionLabel: "",
                            action: {})
                // SAVE is armed by the OTHER two fields, not by its own — this
                // is the field that may legitimately stay empty, so the
                // default "text isn't empty" rule would leave the verb dark on
                // a form that is complete (§83's other half: a control that is
                // inert while everything it needs is present).
                DSSlabField(placeholder: "Issuer ID",
                            text: $issuerField, actionLabel: "SAVE",
                            isArmed: hasBothRequired,
                            action: save)
                // The one piece of fine print on this screen, and it sits on
                // the control it governs (§315): an empty issuer is a real
                // choice Apple's own token spec defines, and somebody with an
                // individual key who feels obliged to invent a value here gets
                // a 401 they cannot diagnose.
                DSSlabNote(text: "Leave the Issuer ID empty if your key is an individual key rather than a team's.")
                BridgeSyncStatusRows(syncing: connecting,
                                     syncingLine: String(localized: "Checking the key…"),
                                     result: result, resultIsError: resultIsError)
            }
        }
        .dsSlabSection()
    }

    // MARK: - Connected: what Apple can see

    /// The apps this key reaches — the connected state's proof, and the answer
    /// to the one question a role-based credential leaves open: not "did the
    /// key work" but "does it reach the app I meant".
    ///
    /// There is deliberately NO star rating here. App Store Connect's API
    /// publishes individual customer reviews and no aggregate — so any number
    /// this screen showed would be the mean of the twenty reviews we happened
    /// to read, presented as your app's rating. That is the §83 fake status in
    /// the one place a developer would believe it instantly.
    private var appsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if apps.isEmpty {
                    Text("Reading your apps…")
                        .dsText(.callout15).foregroundStyle(DS.textTertiary)
                } else {
                    ForEach(apps, id: \.self) { name in
                        Text(name)
                            .dsText(.body17).foregroundStyle(DS.textPrimary)
                    }
                }
                BridgeSyncStatusRows(syncing: syncing,
                                     syncingLine: String(localized: "Reading App Store Connect…"),
                                     result: result, resultIsError: resultIsError)
                DSSlabNote(text: "Verdicts, reviews and expiring builds land on their own.")
            }
        }
        .dsSlabSection()
    }

    // MARK: - Actions

    private func load() {
        recent = recentBridgeThings(source: ASCShape.source, context: modelContext)
        apps = ASCState.apps.values.filter { !$0.isEmpty }.sorted()
    }

    /// All three at once. The key and its ID are both required; the issuer is
    /// optional BY MEANING (see the screen's note), so an empty one is saved
    /// as empty rather than rejected.
    private func save() {
        guard let pem = ASCJWT.normalizedPEM(keyField) else {
            fail(keyField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                 ? String(localized: "Paste the contents of the .p8 file Apple gave you.")
                 : String(localized: "That doesn't look like a .p8 private key. Paste the whole file, including the BEGIN and END lines."))
            return
        }
        let keyID = keyIDField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyID.isEmpty else {
            fail(String(localized: "Apple needs the Key ID too — it's the ten characters printed beside the key you downloaded."))
            return
        }
        connecting = true
        result = nil
        // Stored BEFORE the check, because the check IS a real request signed
        // with them — there is no way to validate an App Store Connect key
        // except by using it. A failure below tears all three back out, so a
        // refused paste never leaves a half-connected bridge behind.
        TokenVault.set(pem, for: ASCAuth.keyVaultKey)
        ASCAuth.setKeyID(keyID)
        ASCAuth.setIssuer(issuerField.trimmingCharacters(in: .whitespacesAndNewlines))
        ASCAuth.forgetToken()

        Task {
            let outcome = await validate()
            connecting = false
            switch outcome {
            case .ok(let count):
                keyField = ""; keyIDField = ""; issuerField = ""
                credentialVersion += 1
                resultIsError = false
                result = count == 1 ? String(localized: "Connected — 1 app")
                                    : String(localized: "Connected — \(count) apps")
                flipTrigger += 1
                DSHaptic.success()
                ASCWatch.registerBridge(store: store)
                load()
                await sync()
            // Four failures, four sentences — the `StripeFetch.validate` rule.
            // The issuer one matters most: it is the likeliest mistake here and
            // is completely invisible from a 401, which is why it gets named
            // rather than folded into "check the key".
            case .unreadableKey:
                undo(String(localized: "Apple couldn't read that key. Check you pasted the whole .p8 file, and that it's the one this Key ID names."))
            case .refused:
                undo(issuerField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? String(localized: "Apple refused that key. If it belongs to a team rather than to you personally, it needs the Issuer ID from the same page.")
                     : String(localized: "Apple refused that key. Check the Key ID and Issuer ID — and if this is an individual key rather than a team's, leave the Issuer ID empty."))
            case .noApps:
                undo(String(localized: "That key works, but it can't see any apps. Give it a role with access to yours — Developer is enough."))
            case .unreachable:
                undo(String(localized: "Couldn't reach App Store Connect — check your connection."))
            }
        }
    }

    private enum Outcome { case ok(Int), unreadableKey, refused, noApps, unreachable }

    /// One signed GET. `/v1/apps` rather than a dedicated identity endpoint,
    /// because it is the read this bridge cannot work without — a key that
    /// authenticates but reaches no app is a connection that will never land
    /// anything, and saying so now is better than a silent room later.
    private func validate() async -> Outcome {
        guard case .success(let token) = ASCAuth.token() else { return .unreadableKey }
        let (json, status) = await IngestSupport.getJSONStatus(
            "\(ASCFetch.base)/apps?limit=200", auth: ASCAuth.header(token))
        if status == 401 || status == 403 { return .refused }
        guard status == 200, let root = json as? [String: Any],
              let rows = root["data"] as? [[String: Any]] else { return .unreachable }
        return rows.isEmpty ? .noApps : .ok(rows.count)
    }

    /// A refused paste leaves NOTHING behind. Without this the bridge would
    /// read `configured` on a credential Apple just rejected, register a seat,
    /// and 401 on every foreground sweep forever — the fake status §83 bans,
    /// arrived at by way of a helpful-looking error message.
    private func undo(_ message: String) {
        TokenVault.delete(ASCAuth.keyVaultKey)
        ASCAuth.clear()
        credentialVersion += 1
        fail(message)
    }

    private func fail(_ message: String) {
        resultIsError = true
        result = message
    }

    private func sync() async {
        guard !syncing, hasKey else { return }
        syncing = true
        defer { syncing = false }
        let added = await ASCIngest.refresh(context: modelContext)
        load()
        ASCWatch.registerBridge(store: store)
        if let added {
            result = added > 0 ? String(localized: "\(added) new")
                               : (bridge.emptyReadNote ?? String(localized: "Up to date"))
            resultIsError = false
        } else {
            result = String(localized: "Couldn't reach App Store Connect — check your connection.")
            resultIsError = true
        }
        // An approval already rains, via `SourceMoments` from the sweep itself.
        // A rejection must never rain — so the two kinds of news answer in
        // different registers, and the bad kind says what it is rather than
        // buzzing anonymously (the Stripe split). Only ever on a sync the
        // person is present for; the background pass stays silent and lets the
        // feed row do the telling.
        if let alarm = ASCIngest.lastPassAlarm {
            chrome.flash(alarm, tone: .failure, seconds: 3.5)
        }
    }
}
