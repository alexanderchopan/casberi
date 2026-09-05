import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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
/// THE FILE IS THE THING SOMEBODY HAS (report, 2026-08-14: *"it asks to paste
/// the contents of the .p8 file but where am i supposed to put it… you need to
/// open it on desktop in a text editor, but none of this is clear"*). Apple
/// hands over a DOWNLOAD, and until this screen read one, every route from
/// there to a text field ran through a desktop text editor — on a bridge whose
/// whole point is watching a release from your phone. The picker reads the
/// `.p8` where it landed, and the filename Apple chose (`AuthKey_<KEYID>.p8`)
/// fills the second field for free, so three fields became one act and a typed
/// ten-character ID. Pasting still works and is still offered; it is the
/// fallback now rather than the only door.
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

    @State private var showConnection = false
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
    @State private var result: BridgeProof?

    @State private var recent: [Thing] = []
    @State private var standings: [ASCStanding] = []

    /// The file picker, and the one observable fact the staging below rests on.
    /// Not persisted — the screen stays mounted across the hop to Safari, and a
    /// remembered tap from last week would put the form in a state its owner
    /// never chose.
    @State private var pickingKey = false
    @State private var doorTapped = false
    /// The file that was read, shown on the row that read it. A key in a secure
    /// field is dots either way, so this is the only place the screen can say
    /// WHICH file it holds — and on a screen with three credentials that all
    /// look alike, that is the difference between proof and a hope.
    @State private var pickedName = ""

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
        BridgeSetupPage(name: "App Store Connect") {
            if hasKey {
                // Connected (prd §186): the credential form retires behind one
                // door, and identity, live proof and what this can do take the
                // screen. This bridge stores only the secret — in the Keychain
                // — so it leads with its own name over a truthful note about
                // HOW it is connected, never an account name we would guess.
                BridgeConnectedState(
                    bridgeID: bridge.bridgeID,
                    name: "App Store Connect",
                    connectionNote: String(localized: "Your \(bridge.credentialNoun) · stored in \(DS.device)'s Keychain"),
                    capabilitiesFallback: [bridge.canLine],
                    openConnection: { showConnection = true })
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                BridgeSetupHeader(
                    name: "App Store Connect",
                    mode: .pasteKey,
                    // Trimmed 2026-08-06: the first cut listed the three shapes
                    // here AND the four reads in the checklist below — two lists of
                    // nearly the same thing, twenty words apart. The intro sells,
                    // the checklist bounds.
                    intro: "Add a key and Apple's verdicts, your customer reviews and expiring builds keep arriving. Apple has no read-only role, so this only reads.",
                    connected: hasKey)
            }
            // The way back to your things (§460).
            if hasKey {
                RoomDoor(name: "App Store Connect", source: ASCShape.source)
                    .listRowSeparator(.hidden)
            }
            if hasKey {
                appsSection.listRowSeparator(.hidden)
                if !recent.isEmpty {
                    RecentThingsSection(header: "Landed", things: recent.live)
                }
            } else {
                keySection.listRowSeparator(.hidden)
            }
        }
        // `.data` rather than a `.p8` type: the extension is registered with
        // nobody, so a UTType built from it is a dynamic type no file on disk
        // conforms to — the picker would open with every file grayed out and
        // the fix would read as a broken button.
        .fileImporter(isPresented: $pickingKey, allowedContentTypes: [.data]) { outcome in
            guard case .success(let url) = outcome else { return }
            Task { await readKeyFile(url) }
        }
        .sheet(isPresented: $showConnection) {
            BridgeConnectionSheet(title: "App Store Connect") {
                keySection
                removeSection
            }
        }
        .onAppear {
            load()
            if hasKey { Task { await sync() } }
        }
    }

    /// The pick leads once the door has been tapped and there is still no key —
    /// the one stretch where choosing the file is genuinely the next act.
    private var pickLeads: Bool { doorTapped && keyField.isEmpty }

    /// How many steps are PROVABLY done, counted in the numbering the lines
    /// wear (`startingAt: 2`) even though they no longer SHOW it: a key in the
    /// field proves it was generated AND downloaded; a Key ID proves the page
    /// was read. Opening the door proves none of them — it is not a step in
    /// this list.
    private var stepsDone: Int {
        if keyField.isEmpty { return 0 }
        return keyIDField.isEmpty ? 3 : 4
    }

    private func openDoor(_ url: URL) {
        doorTapped = true
        openURL(url)
    }

    /// Read the `.p8` where it landed. The security-scoped read is the same
    /// shape every import screen uses; what is different is the size guard —
    /// this is a 250-byte file, and a picker that will happily open anything
    /// must not slurp a 2GB video into a text field before deciding it is not a
    /// key.
    private func readKeyFile(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent
        guard let data = await SecurityScopedFileReader.readData(at: url),
              data.count <= 64_000,
              let text = String(data: data, encoding: .utf8),
              ASCJWT.normalizedPEM(text) != nil else {
            fail(String(localized: "That file isn't a private key. Choose the AuthKey_….p8 Apple gave you when you created the key."))
            return
        }
        keyField = text
        pickedName = name
        result = nil
        // Apple's own filename carries the Key ID, so the second field answers
        // itself. Never overwrites something already typed — a person who
        // corrected it knows something we don't.
        if keyIDField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let id = ASCJWT.keyID(fromFilename: name) {
            keyIDField = id
        }
        DSHaptic.tap()
    }

    // MARK: - Not connected: the three fields

    private var keySection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if let url = bridge.setupURL {
                    // Step one, doing itself (prd §218) — and it hands the
                    // filled slab over to the pick once it has been tapped, the
                    // import family's `pickLeads` staging (§314). One filled
                    // block at a time, and it is always the next thing to do.
                    if doorTapped {
                        DSSlabDoor(title: bridge.doorTitle,
                                   detail: bridge.doorHost,
                                   systemImage: "arrow.up.right") { openDoor(url) }
                    } else {
                        // Verb over address, the 2026-08-14 anatomy.
                        DSSlabButton(title: bridge.doorTitle,
                                     detail: bridge.doorHost,
                                     systemImage: "arrow.up.right") {
                            DSHaptic.tap()
                            openDoor(url)
                        }
                    }
                }
                // All three steps together. They used to be split around the
                // checklist — step 2, a list of four, then steps 3 and 4 —
                // which broke the one sequence on the screen in half and read
                // as more text than it was. Unnumbered (ruling 2026-08-14):
                // the door did step one; `acknowledges` keeps the green check.
                BridgeStepLines(steps: bridge.steps, startingAt: 2,
                                numbered: false, acknowledges: true,
                                doneThrough: stepsDone)
                // The READ BOUNDARY, and the only place it can be stated before
                // somebody decides to paste. Unlike Stripe's and PostHog's
                // checklists this is NOT a set of boxes to tick — Apple grants
                // a ROLE — so it says what the role lets this app see and what
                // it will never do, which is the whole substitute for a scope
                // this API doesn't offer. TWO lines, not the four it shipped
                // with: each pair said one thing across two lines, and on a
                // screen already carrying a door, three steps and three fields
                // the halving is the difference between a promise and a wall.
                DSCheckList(lines: ["Reads review status, reviews and builds",
                                    "Never submits, releases, replies or sells"])
                // THE FILE ITSELF (report, 2026-08-14). Apple hands you a
                // download, and every path from there to a text field runs
                // through a desktop text editor — which is what the one person
                // who got this far actually did. The picker is the answer: the
                // `.p8` is read where it landed, on the device it landed on,
                // and its own filename answers the Key ID field below.
                if pickLeads {
                    DSSlabButton(title: "Choose the .p8 file",
                                 systemImage: "doc.badge.arrow.up") {
                        DSHaptic.tap()
                        pickingKey = true
                    }
                } else {
                    DSSlabDoor(title: "Choose the .p8 file",
                               detail: pickedName.isEmpty
                                   ? String(localized: "Already downloaded?")
                                   : pickedName,
                               systemImage: "doc.badge.arrow.up") { pickingKey = true }
                }
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
                            text: $issuerField, actionLabel: "Save",
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
                                     proof: result)
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
                if standings.isEmpty {
                    Text("Reading your apps…")
                        .dsText(.callout15).foregroundStyle(DS.textTertiary)
                } else {
                    // The NAME ALONE proved reach and said nothing (2026-08-06).
                    // A role-based credential leaves one question open — not
                    // "did the key work" but "does it reach the app I meant,
                    // and where is that app" — and the state was the one thing
                    // this screen held and never showed. Same standings the
                    // room head reads, so the two can't disagree.
                    ForEach(standings, id: \.appID) { standing in
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                            Text(standing.app.isEmpty ? standing.appID : standing.app)
                                .dsText(.body17).foregroundStyle(DS.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: DS.Space.s2)
                            Text(stateLine(standing))
                                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                BridgeSyncStatusRows(syncing: syncing,
                                     syncingLine: String(localized: "Reading App Store Connect…"),
                                     proof: result)
                DSSlabNote(text: "Verdicts, reviews and expiring builds land on their own.")
            }
        }
        .dsSlabSection()
    }

    // MARK: - Actions

    private func load() {
        recent = recentBridgeThings(source: ASCShape.source, context: modelContext)
        standings = ASCState.standing.values.sorted {
            ($0.app.isEmpty ? $0.appID : $0.app) < ($1.app.isEmpty ? $1.appID : $1.app)
        }
    }

    /// "In review · 2 days", or the state alone when this device never watched
    /// it arrive — `ASCRoom`'s own wording and its own honest-duration rule, so
    /// this screen and the room head can never phrase the same fact differently.
    private func stateLine(_ standing: ASCStanding) -> String {
        let state = ASCVersionState(rawValue: standing.state)
        var line = ASCRoom.stateLabel(state)
        if standing.observed,
           let wait = ASCRoom.waitLabel(days: ASCRoom.days(from: standing.since, to: .now)) {
            line += " · \(wait)"
        }
        return line
    }

    /// All three at once. The key and its ID are both required; the issuer is
    /// optional BY MEANING (see the screen's note), so an empty one is saved
    /// as empty rather than rejected.
    private func save() {
        guard let pem = ASCJWT.normalizedPEM(keyField) else {
            fail(keyField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                 ? String(localized: "Choose the .p8 file Apple gave you, or paste its contents.")
                 : String(localized: "That doesn't look like a .p8 private key. Choose the file itself, or paste all of it including the BEGIN and END lines."))
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
                keyField = ""; keyIDField = ""; issuerField = ""; pickedName = ""
                credentialVersion += 1
                result = count == 1 ? .connected(String(localized: "1 app")) : .connected(String(localized: "\(count) apps"))
                DSHaptic.success()
                ASCWatch.registerBridge(store: store)
                load()
                await sync()
            // Four failures, four sentences — the `StripeFetch.validate` rule.
            // The issuer one matters most: it is the likeliest mistake here and
            // is completely invisible from a 401, which is why it gets named
            // rather than folded into "check the key".
            case .unreadableKey:
                undo(String(localized: "Apple couldn't read that key. Check it's the .p8 this Key ID names, and that it arrived whole."))
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
        result = .failed(message)
    }

    private func sync() async {
        guard !syncing, hasKey else { return }
        syncing = true
        defer { syncing = false }
        let added = await ASCIngest.refresh(context: modelContext)
        load()
        ASCWatch.registerBridge(store: store)
        if let added {
            result = added > 0 ? .landed(added) : bridge.emptyReadNote.map(BridgeProof.says) ?? .upToDate
        } else {
            result = .failed(String(localized: "Couldn't reach App Store Connect — check your connection."))
        }
        // An approval says nothing here — it lands in the feed, which is where
        // arrivals live (2026-08-19). A rejection still answers on the screen
        // you are standing on, because the bad kind of news has to say what it
        // is rather than waiting to be scrolled past (the Stripe split). Only ever on a sync the
        // person is present for; the background pass stays silent and lets the
        // feed row do the telling.
        if let alarm = ASCIngest.lastPassAlarm {
            chrome.flash(alarm, tone: .failure, seconds: 3.5)
        }
    }

    /// The way out — the shared row, behind the Connection door with the form
    /// it belongs to (prd §186/§608).
    private var removeSection: some View {
        BridgeDisconnectSection(bridgeID: bridge.bridgeID,
                                name: "App Store Connect",
                                teardown: {
                                    TokenVault.delete(ASCAuth.keyVaultKey)
                                    ASCAuth.clear()
                                    credentialVersion += 1
                                    load()
                                })
    }

}
