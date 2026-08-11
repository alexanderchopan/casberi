import SwiftUI
import SwiftData

/// One screen for every paste-a-token bridge — the steps to find the token,
/// a field that sends it straight to the Keychain, and proof when things
/// land. The same shape as RSS and Bluesky: state the way in plainly, then
/// show it working.
struct TokenSetupScreen: View {
    let bridge: TokenBridge

    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var tokenField = ""
    @State private var syncing = false
    /// A feed toggle (or paste) during an in-flight sync sets this so the
    /// running pass loops once more instead of dropping the request.
    @State private var syncPending = false
    @State private var result: String?
    @State private var resultIsError = false

    /// GitHub only — watching a repo directly, privately (2026-07-16): unlike
    /// a star or subscribe, it never touches the GitHub account.
    @State private var watchField = ""
    @State private var watching = false
    @State private var watchResult: String?
    @State private var watchResultIsError = false

    /// GitHub's feed selection — one connection, several streams the person
    /// turns on (the wallet's holdings/NFTs idea, generalized). Only read on
    /// the GitHub branch; harmless to bind for every bridge.
    @Bindable private var githubFeeds = GitHubFeeds.shared

    /// GitHub's device flow (prd §67 goal ②) — sign in on github.com instead
    /// of hunting a token. Only GitHub has a public-client flow; the other
    /// bridges stay paste-only, honestly.
    private enum DevicePhase { case idle, requesting, waiting(GitHubDeviceFlow.Code) }
    @State private var devicePhase: DevicePhase = .idle
    @State private var pollTask: Task<Void, Never>?
    /// Bumped when the device code is copied — the copy button briefly reads
    /// "Copied" so the tap is acknowledged.
    @State private var codeCopied = false
    private var deviceFlowOffered: Bool {
        bridge == .github && GitHubDeviceFlow.isAvailable
    }
    /// The manual token path, folded behind a disclosure when sign-in is
    /// offered — it's the fallback, and two full-weight paths made the screen
    /// a wall (mock review 2026-07-16). Paste-only bridges show it plainly.
    @State private var manualPathOpen = false

    /// The credentials door, open (prd §186).
    @State private var showConnection = false

    /// Whether the "Open <page>" door has been tapped this visit — step one,
    /// observed rather than assumed (see `tokenStepsDone`). Not persisted: a
    /// step ticked from a previous session would be a claim about a form the
    /// person is looking at fresh.
    @State private var doorOpened = false
    /// Bumped on a successful connect so the header's icon coin-flips to
    /// acknowledge the handshake. Wired 2026-08-04: five smaller setup screens
    /// (Stripe, Bankr, Grok, OpenRouter, Venice) already did this, and the
    /// screen serving the LARGEST family of bridges — every paste-a-token seat
    /// — was the one that didn't, so the flagship path had the quietest
    /// success in the catalog.
    @State private var flipTrigger = 0

    /// Trello only — the API-key stage (2026-08-03). Trello is the one bridge
    /// on this screen whose API takes TWO values on every request, so its form
    /// is two stages: paste the key that names a Power-Up, then authorize a
    /// token against it. Mirrored into `@State` rather than read from the
    /// Keychain inside `body`, so storing it actually re-renders the form.
    @State private var trelloKeyField = ""
    @State private var trelloKey: String? = TrelloAuth.storedKey

    /// Jira only — stage one (2026-08-08): the site and email a token gets
    /// minted for, Trello's two-stage shape one field longer. Mirrored into
    /// `@State` for the same reason Trello's key is: storing to the Keychain
    /// doesn't itself re-render the form.
    @State private var jiraDomainField = ""
    @State private var jiraEmailField = ""
    @State private var jiraSite: String? = JiraAuth.storedDomain

    var body: some View {
        List {
            if bridge.connected {
                connectedState
            } else {
                connectForm
            }
            if bridge == .github && bridge.connected {
                feedsSection
                watchSection
            }
            // The ghost preview retired 2026-07-25 (prd §218): it was the
            // SAME card the product page shows, and Connect now raises this
            // form over that page — so the preview it duplicates is literally
            // still on screen behind the sheet.
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: bridge.rawValue)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle(bridge.rawValue)
        .sheet(isPresented: $showConnection) {
            BridgeConnectionSheet(title: bridge.rawValue) {
                connectForm
                removeSection
            }
        }
        .onAppear {
            if bridge.connected {
                Task { await sync() }
            }
        }
        .onDisappear { cancelDeviceFlow() }
    }

    /// Connected (prd §186) — identity, live proof, what it can do, and the
    /// one door back to the form. A keyed bridge stores no account name (only
    /// the secret, in the Keychain), so this leads with the app's own name
    /// over a truthful note about HOW it's connected rather than a display
    /// name we'd have to invent.
    private var connectedState: some View {
        BridgeConnectedState(
            bridgeID: bridge.bridgeID,
            name: bridge.rawValue,
            connectionNote: String(localized: "Your \(bridge.credentialNoun) · stored in \(DS.device)'s Keychain"),
            capabilitiesFallback: [bridge.canLine],
            openConnection: { showConnection = true }
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// The connect form. **The steps are still whole** — §186's ruling ("it's
    /// important to know what the steps are") stands, and nothing is folded
    /// behind a disclosure. What left in the §218 pass is the FURNITURE around
    /// them: two gray section labels above each control, a gray paragraph
    /// under each, and a numbered card set in body type. Every control is now
    /// a slab, the way §190 already made every other manage page — this screen
    /// was frozen when that pass ran, and stayed a Settings page while the
    /// rest of the app moved on.
    ///
    /// It leads the screen before connecting, and lives behind the Connection
    /// door after — same sections either way, never rewritten.
    @ViewBuilder private var connectForm: some View {
        BridgeSetupHeader(name: bridge.rawValue,
                          mode: deviceFlowOffered ? .signIn : .pasteKey,
                          intro: bridge.setupIntro,
                          connected: bridge.connected, flipTrigger: flipTrigger)
        if deviceFlowOffered {
            // Sign-in is THE path; the token hunt folds away behind a
            // disclosure so the screen leads with one action instead of
            // two competing ones (mock review 2026-07-16). The proof and
            // error rows surface beside sign-in while the manual path —
            // whose card normally carries them — is folded.
            signInSection
            if !manualPathOpen { statusSection }
            manualPathToggleSection
        }
        // Trello's two stages. The token stage only appears once a key is
        // stored, because its door — the authorize link — cannot be built
        // without one, and a door that goes nowhere is a dead control.
        if bridge == .trello {
            trelloKeySection
            if trelloKey != nil { setupSection }
        // Jira's two stages — Trello's shape, though for a different reason:
        // the door below doesn't depend on the site or email at all (it's a
        // fixed page, `TokenBridge.jira.setupURL`), but a token pasted before
        // either is stored would authenticate against nobody knows which
        // site. Staying two stages keeps the "what does this connect to"
        // question answered before the credential that proves it.
        } else if bridge == .jira {
            jiraSiteSection
            if jiraSite != nil { setupSection }
        } else if manualPathOpen || !deviceFlowOffered {
            setupSection
        }
    }

    /// Trello only — stage one. The key names a Power-Up, not a person: it is
    /// public by design (it ships in the client-side JavaScript of every
    /// Trello Power-Up), which is exactly why it can be pasted here and then
    /// used to build a `scope=read` authorize link on your behalf.
    private var trelloKeySection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if let url = bridge.setupURL {
                    DSSlabButton(title: "Open \(bridge.setupURLLabel)",
                                 systemImage: "arrow.up.right") {
                        DSHaptic.tap()
                        openURL(url)
                    }
                }
                BridgeStepLines(steps: [
                    String(localized: "Create a Power-Up — name it Casberi. Its API key is on the page."),
                    String(localized: "Paste the key below."),
                ], startingAt: 2)
                DSSlabField(placeholder: String(localized: "API key"),
                            text: $trelloKeyField,
                            actionLabel: trelloKey == nil
                                ? String(localized: "NEXT") : String(localized: "REPLACE"),
                            action: saveTrelloKey)
                DSSlabNote(text: "It names the Power-Up, not you — public by design. The token below is what reads your cards.")
            }
        }
        .dsSlabSection()
    }

    private func saveTrelloKey() {
        let key = trelloKeyField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        // A token is minted AGAINST a key, so a different key invalidates the
        // one already stored. Retiring it here is what keeps the screen
        // honest: leaving a connected state up over a token that can no longer
        // authenticate would fail silently on the next foreground instead.
        if key != trelloKey, bridge.connected {
            TokenVault.delete(bridge.tokenKey)
            store.bridges.removeAll { $0.id == bridge.bridgeID }
            result = String(localized: "New key stored — authorize again below to finish.")
            resultIsError = false
        }
        TrelloAuth.setKey(key)
        trelloKey = key
        trelloKeyField = ""
        DSHaptic.tap()
    }

    /// Jira only — stage one. Two fields, not one: Jira's REST API has no
    /// bearer secret that alone names a site or an account, so a token means
    /// nothing until both are stored (see `JiraAuth`). Unlike Trello's key,
    /// neither value is minted from the other — they're just two things the
    /// person already knows — so this is one section with two fields and one
    /// verb, the ASC "three slabs, one verb" shape a field shorter.
    private var jiraSiteSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSSlabField(placeholder: String(localized: "yourteam.atlassian.net"),
                            text: $jiraDomainField, actionLabel: "",
                            keyboard: .URL, action: {})
                DSSlabField(placeholder: String(localized: "you@company.com"),
                            text: $jiraEmailField,
                            actionLabel: jiraSite == nil
                                ? String(localized: "NEXT") : String(localized: "REPLACE"),
                            keyboard: .emailAddress,
                            isArmed: !jiraDomainField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                && !jiraEmailField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                            action: saveJiraSite)
                DSSlabNote(text: "Your site, and the email the token below gets minted for — Jira needs both to know whose issues \"assigned to you\" means.")
            }
        }
        .dsSlabSection()
    }

    private func saveJiraSite() {
        let domain = JiraAuth.normalizedDomain(jiraDomainField)
        let email = jiraEmailField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !domain.isEmpty, !email.isEmpty else { return }
        // A token is minted against a site AND an email, so changing either
        // invalidates the one already stored — Trello's key reasoning,
        // applied to two fields instead of one.
        if (domain != jiraSite || email != JiraAuth.storedEmail), bridge.connected {
            TokenVault.delete(bridge.tokenKey)
            store.bridges.removeAll { $0.id == bridge.bridgeID }
            result = String(localized: "New site stored — paste a token minted for it below to finish.")
            resultIsError = false
        }
        JiraAuth.setDomain(domain)
        JiraAuth.setEmail(email)
        jiraSite = domain
        jiraDomainField = ""
        jiraEmailField = ""
        DSHaptic.tap()
    }

    /// The door above the token field. Every bridge but Trello has one fixed
    /// page; Trello's is built here from the key stored a stage earlier, which
    /// is what lets Casberi pin `scope=read` rather than ask someone to tick
    /// read-only on somebody else's settings page.
    private var doorURL: URL? {
        if bridge == .trello { return trelloKey.flatMap(TrelloAuth.authorizeURL) }
        return bridge.setupURL
    }

    private var doorLabel: String {
        bridge == .trello
            ? String(localized: "Authorize read-only access")
            : bridge.setupURLLabel
    }

    /// Door, steps, field, proof, one sentence — in that order, because that
    /// is the order the person does them in.
    private var setupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if let url = doorURL {
                    // Step one, doing itself (prd §218). This screen used to
                    // say "Open readwise.io/access_token" in body text and
                    // then leave you to retype it — an instruction the app
                    // could have followed on your behalf the whole time.
                    DSSlabButton(title: bridge == .trello
                                    ? doorLabel : String(localized: "Open \(doorLabel)"),
                                 systemImage: "arrow.up.right") {
                        DSHaptic.tap()
                        doorOpened = true
                        openURL(url)
                    }
                }
                BridgeStepLines(steps: bridge.steps,
                                startingAt: doorURL == nil ? 1 : 2,
                                doneThrough: tokenStepsDone)
                DSSlabField(placeholder: bridge.placeholder, text: $tokenField,
                            actionLabel: bridge.connected ? "UPDATE" : "CONNECT",
                            secure: true, action: connect)
                BridgeSyncStatusRows(syncing: syncing,
                                     syncingLine: String(localized: "Fetching your \(bridge.noun)…"),
                                     result: result, resultIsError: resultIsError)
                DSSlabNote(text: keychainNote)
            }
        }
        .dsSlabSection()
    }

    /// How far through the token steps we can PROVE someone is (2026-08-04).
    /// Two observable facts and no inference: the door was tapped, and the
    /// field carries text. Everything between them happens on somebody else's
    /// website, so it is deliberately not counted — the middle step ticks only
    /// when the paste arrives, because that's the first moment we know it
    /// happened. Every token bridge's `steps` ends in "paste it below", so
    /// text in the field really does finish the list.
    private var tokenStepsDone: Int {
        guard doorURL != nil else { return tokenField.isEmpty ? 0 : bridge.steps.count }
        if !tokenField.isEmpty { return bridge.steps.count + 1 }
        return doorOpened ? 1 : 0
    }

    /// The screen's one gray sentence (§190's companion rule, finally applied
    /// here). Three footers used to say this — the Keychain, the recipient,
    /// and the read-only promise — which is one fact wearing three paragraphs.
    private var keychainNote: String {
        String(localized: "Your \(bridge.credentialNoun) stays in \(DS.device)'s Keychain, goes only to \(bridge.rawValue), and only to read.")
    }

    /// The sign-in path — GitHub shows a short code here, you approve it on
    /// github.com, and the token arrives on its own. One row, three phases.
    private var signInSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                switch devicePhase {
                case .idle:
                    DSSlabButton(title: "Sign in with GitHub",
                                 systemImage: "person.badge.key",
                                 action: startDeviceFlow)
                case .requesting:
                    HStack(spacing: DS.Space.s2) {
                        ProgressView()
                        Text("Asking GitHub for a code…")
                            .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    }
                case .waiting(let code):
                    // The code is the whole moment — big, spaced by GitHub's
                    // own hyphen, sitting in a well with an explicit Copy button
                    // so it plainly reads as "copy this and paste it on GitHub"
                    // (the bare tap-to-copy went unnoticed; user, 2026-07-15).
                    HStack(spacing: DS.Space.s3) {
                        Text(code.userCode)
                            .dsText(.monoCode34)
                            .foregroundStyle(DS.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Button(action: { copyCode(code.userCode) }) {
                            HStack(spacing: DS.Space.s1) {
                                Image(systemName: codeCopied ? "checkmark" : "doc.on.doc")
                                    .dsGlyph(13)
                                Text(codeCopied ? "Copied" : "Copy").dsText(.subhead13).fontWeight(.semibold)
                            }
                            .foregroundStyle(codeCopied ? DS.confirm : DS.tint)
                            .padding(.horizontal, DS.Space.s3)
                            .frame(height: 34)
                            .background(DS.gray100, in: Capsule(style: .continuous))
                            .contentShape(Capsule(style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(DS.Space.s3)
                    .frame(maxWidth: .infinity)
                    .background(DS.surfaceWell, in: DSSlab.shape)
                    Text("Enter this code on GitHub — approval lands the token here by itself.")
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    DSSlabButton(title: "Open github.com/login/device",
                                 systemImage: "arrow.up.right") {
                        DSHaptic.tap()
                        openURL(code.verificationURL)
                    }
                    HStack(spacing: DS.Space.s2) {
                        ProgressView()
                        Text("Waiting for your approval…")
                            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        Spacer()
                        Button("Cancel") { cancelDeviceFlow() }
                            .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                            .buttonStyle(.plain)
                    }
                }
                // The sign-in path's one sentence — the scope, which is the
                // only fact worth a gray line on a screen about trust. The
                // "Sign in" header went with the furniture: the button says
                // what it does (§190).
                DSSlabNote(text: "GitHub's smallest scope that reaches private issues and PRs.")
            }
        }
        .dsSlabSection()
    }

    private func startDeviceFlow() {
        DSHaptic.tap()
        devicePhase = .requesting
        result = nil
        pollTask = Task { @MainActor in
            guard let code = await GitHubDeviceFlow.start() else {
                finishDeviceFlow(error: String(localized: "GitHub didn't answer — try again, or get a token by hand."))
                return
            }
            withAnimation(DS.Motion.standard) { devicePhase = .waiting(code) }
            var interval = code.interval
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                switch await GitHubDeviceFlow.poll(code) {
                case .pending:
                    continue
                case .slowDown:
                    interval += 5   // GitHub's own backoff nudge
                case .token(let token):
                    TokenVault.set(token, for: bridge.tokenKey)
                    withAnimation(DS.Motion.standard) { devicePhase = .idle }
                    DSHaptic.success()
                    await sync(justConnected: true)
                    return
                case .denied:
                    finishDeviceFlow(error: String(localized: "You declined on GitHub — nothing was connected."))
                    return
                case .expired:
                    finishDeviceFlow(error: String(localized: "That code expired — sign in again for a fresh one."))
                    return
                case .failed:
                    finishDeviceFlow(error: String(localized: "GitHub didn't answer — check your connection and try again."))
                    return
                }
            }
        }
    }

    private func copyCode(_ code: String) {
        DSPasteboard.copySensitive(code)
        DSHaptic.tap()
        withAnimation(DS.Motion.standard) { codeCopied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation(DS.Motion.standard) { codeCopied = false }
        }
    }

    private func finishDeviceFlow(error: String) {
        withAnimation(DS.Motion.standard) { devicePhase = .idle }
        result = error
        resultIsError = true
    }

    private func cancelDeviceFlow() {
        pollTask?.cancel()
        pollTask = nil
        if case .idle = devicePhase {} else {
            withAnimation(DS.Motion.standard) { devicePhase = .idle }
        }
    }

    /// The sync proof and honest failures, surfaced beside sign-in while the
    /// manual path (whose card normally carries these rows) is folded away.
    private var statusSection: some View {
        Section {
            BridgeSyncStatusRows(syncing: syncing,
                                 syncingLine: String(localized: "Fetching your \(bridge.noun)…"),
                                 result: result, resultIsError: resultIsError)
        }
        .dsSlabSection()
    }

    /// The fold: one quiet row that opens the token-by-hand path. Not a slab —
    /// it's a disclosure over an alternate route, not a control that does
    /// anything, and giving it a slab would put it on level with Sign in.
    private var manualPathToggleSection: some View {
        Section {
            Button {
                withAnimation(DS.Motion.standard) { manualPathOpen.toggle() }
            } label: {
                HStack(spacing: DS.Space.s2) {
                    Text("Prefer a token by hand?")
                        .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    Image(systemName: "chevron.down")
                        .dsGlyph(11)
                        .foregroundStyle(DS.textTertiary)
                        .rotationEffect(.degrees(manualPathOpen ? 180 : 0))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .dsSlabSection()
    }

    /// GitHub only — the feed picker. One connection, several streams the
    /// person each turns on; toggling re-syncs so a newly-chosen feed lands
    /// now, not next foreground.
    private var feedsSection: some View {
        // Switch slabs (§190's picker-page shape): each row IS this
        // connection's verb for one lane, the same as a chain on OpenSea, so
        // it earns a full block instead of a line in a stacked toggle list.
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ForEach(GitHubFeed.allCases) { feed in
                    DSSlabSwitch(title: feed.title, detail: feed.blurb,
                                 isOn: Binding(
                                    get: { githubFeeds.isOn(feed) },
                                    set: { _ in
                                        githubFeeds.toggle(feed)
                                        DSHaptic.tap()
                                        Task { await sync() }
                                    }))
                }
                DSSlabNote(text: "All of it lands under GitHub.")
            }
        }
        .dsSlabSection()
    }

    /// GitHub only — watch a repo without starring or subscribing to it on
    /// GitHub itself (2026-07-16). The watch lands as a thing immediately;
    /// deleting it in the sheet unwatches it (feed swipes stay read-only).
    private var watchSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSSlabField(placeholder: String(localized: "owner/repo or a GitHub URL"),
                            text: $watchField, actionLabel: String(localized: "WATCH"),
                            action: watchRepo)
                BridgeSyncStatusRows(syncing: watching,
                                     syncingLine: String(localized: "Looking it up…"),
                                     result: watchResult, resultIsError: watchResultIsError)
                DSSlabNote(text: "Private to \(DS.device) — it never touches your GitHub account.")
            }
        }
        .dsSlabSection()
    }

    private func watchRepo() {
        let q = watchField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !watching, let token = TokenVault.get(bridge.tokenKey) else { return }
        DSHaptic.tap()
        watching = true
        watchResultIsError = false
        Task {
            let resolved = await GitHubRepoWatch.resolve(q, token: token)
            watching = false
            guard let resolved else {
                watchResult = String(localized: "Couldn't find that repo on GitHub.")
                watchResultIsError = true
                return
            }
            guard let thing = GitHubRepoWatch.add(resolved, context: modelContext) else {
                watchResult = String(localized: "\(resolved.fullName) is already watched.")
                watchResultIsError = true
                return
            }
            watchField = ""
            watchResult = String(localized: "Watching \(thing.title)")
            await sync()
        }
    }

    private var removeSection: some View {
        Section {
            Button("Remove token", role: .destructive) {
                TokenVault.delete(bridge.tokenKey)
                bridge.onRemove()
                trelloKey = nil   // Trello's key goes with it (see `onRemove`)
                store.bridges.removeAll { $0.id == bridge.bridgeID }
                result = String(localized: "Token removed — your things stay.")
                resultIsError = false
                DSHaptic.tap()
            }
            .dsText(.callout15)
            .dsListCardRow()
        } footer: {
            Text("Removing the token stops syncing. What already landed stays yours.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
        }
    }

    private func connect() {
        let token = tokenField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        // Pasting over an existing token is a reconnect: drop the prior key's
        // cached readings (balance, vault reach) BEFORE storing, or a paste
        // whose first sync fails leaves the new key wearing the old key's
        // numbers as if they were its own. `reconnecting` spares the one piece
        // of state the paste itself depends on — Trello's API key, which the
        // token being pasted was minted against.
        bridge.onRemove(reconnecting: true)
        TokenVault.set(token, for: bridge.tokenKey)
        tokenField = ""
        DSHaptic.tap()
        Task { await sync(justConnected: true) }
    }

    /// The empty-read explanation (`TokenBridge.emptyReadNote`), but only when
    /// this bridge has genuinely never landed anything. Gated on the CORPUS,
    /// not on this pass: a sync that adds 0 is the normal case for a connected
    /// bridge with no news, and showing "no cards are assigned to you" to
    /// someone whose forty cards are already in their feed would be a lie the
    /// screen tells every single sync.
    private func emptyReadNote() -> String? {
        guard let note = bridge.emptyReadNote else { return nil }
        let source = bridge.rawValue
        let landed = (try? modelContext.fetchCount(
            FetchDescriptor<Thing>(predicate: #Predicate { $0.source == source })))
            // A fetch that failed is not evidence of an empty account — stay
            // quiet and let the ordinary "Up to date" stand.
            ?? 1
        return landed == 0 ? note : nil
    }

    private func sync(justConnected: Bool = false) async {
        // A feed toggled (or a paste) while a sync is mid-flight requeues rather
        // than being dropped — the running pass loops once more, re-reading the
        // selection, so a newly-chosen GitHub feed lands now, not next
        // foreground (the OpenSea pattern).
        if syncing { syncPending = true; return }
        syncing = true
        defer { syncing = false }
        // Only the FIRST attempt of a fresh paste may retire the token; once a
        // pass has succeeded, a requeued pass that hits a network blip must not
        // discard a token we just proved works.
        var connecting = justConnected
        repeat {
            syncPending = false
            let added = await TokenIngest.refresh(bridge, context: modelContext)
            guard let added else {
                if connecting {
                    // A fresh paste that fails doesn't stay: keeping it would show
                    // "Update"/"Remove token" for a connection that never worked and
                    // retry a dead token on every foreground.
                    TokenVault.delete(bridge.tokenKey)
                    result = String(localized: "That token didn't work — check it (and your connection) and paste again.")
                    // "Paste again" must point at a visible field — if the
                    // manual path is folded (a device-flow connect that failed
                    // on its first sync), unfold it so the error and the field
                    // share the screen (review 2026-07-16).
                    withAnimation(DS.Motion.standard) { manualPathOpen = true }
                } else {
                    // A background re-sync of an already-connected bridge failed. The
                    // user didn't just paste anything, so don't accuse the empty field
                    // — say what actually happened: the saved token or the network.
                    result = String(localized: "Couldn't refresh \(bridge.rawValue) just now — your saved token may need renewing.")
                }
                resultIsError = true
                return
            }
            connecting = false
            resultIsError = false
            result = added > 0
                ? String(localized: "\(added) \(bridge.noun) in")
                : (emptyReadNote() ?? String(localized: "Up to date"))
            let proof = added > 0
                ? String(localized: "\(added) \(bridge.noun) in")
                : String(localized: "Synced just now")
            if store.registerConnected(id: bridge.bridgeID, name: bridge.rawValue,
                                       proof: proof, can: [bridge.canLine]) {
                DSHaptic.success()
                // The handshake, acknowledged: the icon coin-flips in time with
                // the haptic. Gated on `registerConnected` returning true — the
                // seat really changed — so a routine re-sync of a live bridge
                // never celebrates.
                flipTrigger += 1
            }
        } while syncPending
    }
}
