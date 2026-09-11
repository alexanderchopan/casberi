import SwiftUI
import SwiftData

/// One screen for every paste-a-token bridge — the steps to find the token,
/// a field that sends it straight to the Keychain, and proof when things
/// land. ON THE ACCOUNT PAGE since prd §639 (2026-09-06): the header, the
/// plain rows, the readers row, the roster and the exits are `AccountPage`'s;
/// this file keeps what is GitHub's or Trello's or Jira's — the door, the
/// steps, the device flow, the two-stage keys, the watch verbs — and hands
/// them to the chassis as the act field, the second acts and the key sheet.
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
    @State private var result: BridgeProof?

    /// GitHub only — watching a repo directly, privately (2026-07-16): unlike
    /// a star or subscribe, it never touches the GitHub account.
    @State private var watchField = ""
    @State private var watching = false
    @State private var watchResult: BridgeProof?

    /// GitHub only — watching a PERSON, the same way (prd §519, 2026-08-29).
    /// Its own field and its own in-flight flag, but it SHARES the result
    /// above: `connect-shape-audit`'s rule is that the sync result reports at
    /// the END of its block, because it appears and disappears on its own and
    /// anything under it is shoved down by a background event — so a second
    /// status row between the two fields would make a repo error read as the
    /// person field being broken. One result is also unambiguous, since each
    /// sentence names its own subject.
    @State private var personField = ""
    @State private var watchingPerson = false
    /// The face of whoever just landed — proof that reads "this person
    /// arrived", not "a row arrived". `BridgeSyncStatusRows.faces` has existed
    /// since 2026-07-14 with NO caller anywhere in the app; this is its first.
    /// Its `faceFallback` is a BRIDGE name for `BridgeIcon`, not an SF Symbol
    /// — a dead avatar URL falls back to GitHub's own mark, never a glyph.
    @State private var watchFaces: [String] = []

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

    /// The page's one presentation (`AccountPage.sheet`): the reach sheet,
    /// the key sheet, or a profile.
    @State private var sheet: AccountPageSheet?

    /// GitHub only — the watched repos and people as the chassis draws them,
    /// read on appearance and after every watch or remove (a fetch belongs
    /// in `.task`, never in a body — prd §628).
    @State private var rows: [AccountPageShape.Row] = []
    /// GitHub only — the ONE watch field's text: a repo slug or URL, or a
    /// person. `looksLikeRepo` decides which verb it is.
    @State private var watchQuery = ""

    /// Whether the "Open <page>" door has been tapped this visit — step one,
    /// observed rather than assumed (see `tokenStepsDone`). Not persisted: a
    /// step ticked from a previous session would be a claim about a form the
    /// person is looking at fresh.
    @State private var doorOpened = false

    /// GitHub only — the contribution year, which LEFT THE ROOM on 2026-09-11
    /// (user: *"i also really don't think the year in code matters as much does
    /// it? it's kind of a static thing"*, and then the ruling that made the room
    /// one plain feed with no head).
    ///
    /// It is a fact about the ACCOUNT — how much you wrote this year — not about
    /// what moved, so it belongs on the page that holds the account's other
    /// facts rather than above a feed opened to see what needs you. Same store
    /// it always used; `refreshIfStale` self-guards and refuses to reach
    /// anything in demo mode.
    @State private var githubGraph = GitHubGraphStore.shared
    /// Bumped on a successful connect so the header's icon coin-flips to
    /// acknowledge the handshake. Wired 2026-08-04: five smaller setup screens
    /// (Stripe, Bankr, Grok, OpenRouter, Venice) already did this, and the
    /// screen serving the LARGEST family of bridges — every paste-a-token seat
    /// — was the one that didn't, so the flagship path had the quietest
    /// success in the catalog.

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
        AccountPage(
            name: bridge.rawValue, seatID: bridge.bridgeID, source: bridge.source,
            state: AccountPageState.of(name: bridge.rawValue, seatID: bridge.bridgeID,
                                       connected: bridge.connected, store: store),
            // The §315 mode, back on the page it left with §639: "Not
            // connected" says nothing about what connecting will ask of you,
            // and this seat's answer changes with the bridge (GitHub offers a
            // sign-in, the other twenty-three take a pasted token).
            mode: deviceFlowOffered ? .signIn : .pasteKey,
            keyed: true,
            rows: rows,
            query: bridge == .github ? watchQuery : "",
            onRemoveRow: removeWatch,
            onOpenRow: bridge == .github ? openWatch : nil,
            teardown: {
                TokenVault.delete(bridge.tokenKey)
                bridge.onRemove()
                trelloKey = nil   // Trello's key goes with it (see `onRemove`)
            },
            sheet: $sheet,
            act: { actField },
            more: {
                if bridge == .github && bridge.connected {
                    githubYearSection
                    feedsSection
                }
            },
            keySheet: { tokenForm }
        )
        .onAppear {
            if bridge.connected {
                Task { await sync() }
                // The contribution year, seeded from the one always-present
                // spot on this page — the section that draws it is
                // conditionally empty, so its own `.task` would not fire until
                // a year had already landed (chicken-and-egg).
                if bridge == .github {
                    Task { await githubGraph.refreshIfStale() }
                }
            }
        }
        .task(id: "\(bridge.rawValue)\(bridge.connected)") { readRows() }
        .onDisappear { cancelDeviceFlow() }
    }

    /// The act field, always first (prd §639). Not connected: the connect
    /// form itself. Needs reconnecting: a new token. Connected: what this
    /// account can ADD — GitHub watches a repo or a person; every other
    /// keyed bridge has nothing to add, so its field replaces the key.
    @ViewBuilder private var actField: some View {
        if !bridge.connected || BridgeHealth.needsReconnect(bridge.rawValue) != nil {
            connectForm
        } else if bridge == .github {
            DSSlabField(placeholder: AccountPageShape.findPlaceholder(
                            String(localized: "a repo or person")),
                        text: $watchQuery, actionLabel: String(localized: "Watch"),
                        busy: watching || watchingPerson, action: watchEither)
            BridgeSyncStatusRows(syncing: watching || watchingPerson,
                                 syncingLine: watchingPerson
                                    ? String(localized: "Looking them up…")
                                    : String(localized: "Looking it up…"),
                                 proof: watchResult,
                                 faces: watchFaces, faceFallback: bridge.rawValue)
            DSSlabNote(text: "Private to \(DS.device) — nobody is followed or notified, and nothing shows on your GitHub account.")
        } else {
            DSSlabField(placeholder: String(localized: "Paste a new token"), text: $tokenField,
                        actionLabel: String(localized: "Replace"),
                        secure: true, action: connect)
            BridgeSyncStatusRows(syncing: syncing,
                                 syncingLine: String(localized: "Fetching your \(bridge.noun)…"),
                                 proof: result)
        }
    }

    /// The "Your key" sheet's content — the token by hand, whole: the door,
    /// the steps, the field. The same block the not-connected act field
    /// draws, so a key is replaced through exactly the path it was pasted.
    @ViewBuilder private var tokenForm: some View {
        if bridge == .trello {
            trelloKeyBlock
            if trelloKey != nil { setupBlock }
        } else if bridge == .jira {
            jiraSiteBlock
            if jiraSite != nil { setupBlock }
        } else {
            setupBlock
        }
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
    /// It is the act field before connecting (and again when the key is
    /// refused), and the Your key sheet after — the same blocks either way,
    /// never rewritten (prd §639).
    @ViewBuilder private var connectForm: some View {
        if deviceFlowOffered {
            // Sign-in is THE path; the token hunt folds away behind a
            // disclosure so the screen leads with one action instead of
            // two competing ones (mock review 2026-07-16). The proof and
            // error rows surface beside sign-in while the manual path —
            // whose block normally carries them — is folded.
            signInBlock
            if !manualPathOpen { statusRows }
            manualPathToggle
        }
        // Trello's two stages. The token stage only appears once a key is
        // stored, because its door — the authorize link — cannot be built
        // without one, and a door that goes nowhere is a dead control.
        if bridge == .trello {
            trelloKeyBlock
            if trelloKey != nil { setupBlock }
        // Jira's two stages — Trello's shape, though for a different reason:
        // the door below doesn't depend on the site or email at all (it's a
        // fixed page, `TokenBridge.jira.setupURL`), but a token pasted before
        // either is stored would authenticate against nobody knows which
        // site. Staying two stages keeps the "what does this connect to"
        // question answered before the credential that proves it.
        } else if bridge == .jira {
            jiraSiteBlock
            if jiraSite != nil { setupBlock }
        } else if manualPathOpen || !deviceFlowOffered {
            setupBlock
        }
    }

    /// Trello only — stage one. The key names a Power-Up, not a person: it is
    /// public by design (it ships in the client-side JavaScript of every
    /// Trello Power-Up), which is exactly why it can be pasted here and then
    /// used to build a `scope=read` authorize link on your behalf.
    private var trelloKeyBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            BridgeSetupCard(steps: [
                String(localized: "Create a Power-Up named Casberi"),
                String(localized: "Paste the key below."),
            ], numbered: false) {
                if let url = bridge.setupURL {
                    DSSlabButton(title: bridge.doorTitle,
                                 detail: bridge.doorHost,
                                 systemImage: "arrow.up.right", url: url)
                }
            }
            DSSlabField(placeholder: String(localized: "API key"),
                        text: $trelloKeyField,
                        actionLabel: trelloKey == nil
                            ? String(localized: "Next") : String(localized: "Replace"),
                        action: saveTrelloKey)
            DSSlabNote(text: "It names the Power-Up, not you. The token below is what reads your cards.")
        }
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
            result = .says(String(localized: "New key stored — authorize again below to finish."))
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
    private var jiraSiteBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            DSSlabField(placeholder: String(localized: "yourteam.atlassian.net"),
                        text: $jiraDomainField, actionLabel: "",
                        keyboard: .URL, action: {})
            DSSlabField(placeholder: String(localized: "you@company.com"),
                        text: $jiraEmailField,
                        actionLabel: jiraSite == nil
                            ? String(localized: "Next") : String(localized: "Replace"),
                        keyboard: .emailAddress,
                        isArmed: !jiraDomainField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            && !jiraEmailField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        action: saveJiraSite)
            DSSlabNote(text: "Jira needs both to know whose issues \"assigned to you\" means.")
        }
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
            result = .says(String(localized: "New site stored — paste a token minted for it below to finish."))
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

    private var doorTitle: String {
        bridge == .trello
            ? String(localized: "Authorize read-only access")
            : bridge.doorTitle
    }

    /// Door, steps, field, proof, one sentence — in that order, because that
    /// is the order the person does them in.
    private var setupBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            // Numbered only when there is NO door — then the list really
            // does start at 1. Under a door, numerals starting at 2 sent
            // the eye hunting for a missing 1 (ruling 2026-08-14).
            BridgeSetupCard(steps: bridge.steps,
                            startingAt: doorURL == nil ? 1 : 2,
                            numbered: doorURL == nil,
                            acknowledges: true,
                            doneThrough: tokenStepsDone) {
                if let url = doorURL {
                    // Step one, doing itself (prd §218). This screen used to
                    // say "Open readwise.io/access_token" in body text and
                    // then leave you to retype it — an instruction the app
                    // could have followed on your behalf the whole time. The
                    // verb+address anatomy (2026-08-14): the big words stay
                    // short, the host sits beneath them, and the route trail
                    // lives in the steps.
                    DSSlabButton(title: doorTitle,
                                 detail: bridge.doorHost,
                                 systemImage: "arrow.up.right", url: url,
                                 onOpen: { doorOpened = true })
                }
            }
            DSSlabField(placeholder: bridge.placeholder, text: $tokenField,
                        actionLabel: bridge.connected ? "Replace" : "Connect",
                        secure: true, action: connect)
            BridgeSyncStatusRows(syncing: syncing,
                                 syncingLine: String(localized: "Fetching your \(bridge.noun)…"),
                                 proof: result)
        }
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

    /// `keychainNote` is GONE (prd §639): "stays in the Keychain, goes only
    /// to X, and only to read" is said by the Your key row (where it lives)
    /// and the What it reaches row (where it goes) — as facts on rows, not a
    /// gray sentence under a field.

    /// The sign-in path — GitHub shows a short code here, you approve it on
    /// github.com, and the token arrives on its own. One row, three phases.
    private var signInBlock: some View {
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
                                .dsSymbolSwap(codeCopied)
                                .dsGlyph(13)
                            Text(codeCopied ? "Copied" : "Copy").dsText(.subhead13).fontWeight(.semibold)
                        }
                        .foregroundStyle(codeCopied ? DS.confirm : DS.tint)
                        .padding(.horizontal, DS.Space.s3)
                        .frame(minHeight: 34)
                        .background(DS.gray100, in: Capsule(style: .continuous))
                        .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(PressSpring())
                }
                .padding(DS.Space.s3)
                .frame(maxWidth: .infinity)
                .background(DS.surfaceWell, in: DSSlab.shape)
                Text("Enter this code on GitHub — approval lands the token here by itself.")
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                // Verb over address, the 2026-08-14 anatomy.
                // In-app (§653) — the code to type sits on the page behind,
                // readable at the half detent, where Safari would hide it.
                DSSlabButton(title: "Enter it on GitHub",
                             detail: "github.com/login/device",
                             systemImage: "arrow.up.right",
                             url: code.verificationURL)
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
        result = .failed(error)
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
    private var statusRows: some View {
        BridgeSyncStatusRows(syncing: syncing,
                             syncingLine: String(localized: "Fetching your \(bridge.noun)…"),
                             proof: result)
    }

    /// The fold: one quiet row that opens the token-by-hand path. Not a slab —
    /// it's a disclosure over an alternate route, not a control that does
    /// anything, and giving it a slab would put it on level with Sign in.
    private var manualPathToggle: some View {
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

    /// GitHub only — the contribution year (2026-09-11). Paints only once a
    /// real year with contributions has landed: an empty grid is a skeleton, not
    /// content, and this page already says everything else it knows in words.
    @ViewBuilder private var githubYearSection: some View {
        if let year = githubGraph.year, year.total > 0 {
            CalendarHeatmapHero(title: String(localized: "Your year in code"),
                                subtitle: String(localized: "\(year.total.formatted()) contributions"),
                                year: year)
        }
    }

    /// GitHub only — the feed picker. One connection, several streams the
    /// person each turns on; toggling re-syncs so a newly-chosen feed lands
    /// now, not next foreground.
    private var feedsSection: some View {
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

    /// GitHub only — ONE field watches a repo or a person (prd §639; the
    /// repo half is 2026-07-16, the person half prd §519). The shape of what
    /// was pasted decides the verb: a path with an owner AND a name is a
    /// repo, anything else is an account. Neither verb touches the GitHub
    /// account — nothing is starred, subscribed or followed.
    private func watchEither() {
        let q = watchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        if TokenSetupScreen.looksLikeRepo(q) {
            watchField = q
            watchRepo()
        } else {
            personField = q
            watchPerson()
        }
    }

    /// "owner/repo", or a github.com URL with two path segments. A bare
    /// login, an `@login` or a profile URL (one segment) is a person.
    static func looksLikeRepo(_ q: String) -> Bool {
        var path = q
        if let range = path.range(of: "github.com/") {
            path = String(path[range.upperBound...])
        }
        let parts = path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        return parts.count >= 2
    }

    /// The watched repos and people as roster rows. Every watch is a `Thing`
    /// under GitHub with a `sourceRef`, so the corpus IS the store; the ring
    /// reads the watch row's own `capturedAt` against the last visit.
    private func readRows() {
        guard bridge == .github, bridge.connected else { rows = []; return }
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "GitHub" && $0.sourceRef != nil },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.fetchLimit = 200
        let lastLooked = AccountVisits.lastLooked(bridge.bridgeID)
        let landed = (try? modelContext.fetch(descriptor)) ?? []
        // **WHAT EACH WATCH ACTUALLY LANDED THIS WEEK** (2026-09-11). Every
        // row here passed `weekCount: 0` until now, which meant
        // `AccountPageShape.split` filed every watch under "Quiet" — the page
        // had an active-first sort and nothing to sort by, so a repo that
        // shipped twice today read exactly like one nobody has touched since
        // spring.
        //
        // ONE walk of the rows already fetched, bucketed by the same
        // `GitHubRowTag.matches` the room's rail uses — so a watch is "active"
        // here precisely when picking its face in the room shows you something,
        // and the two can never disagree about what belongs to whom.
        let weekStart = Date.now.addingTimeInterval(-7 * 86_400)
        var counts: [String: Int] = [:]
        for thing in landed where thing.isLive && thing.capturedAt >= weekStart {
            let ref = thing.sourceRef
            // The watch row itself is not news about the watch.
            guard !(ref?.hasPrefix("gh:watchrepo:") ?? false),
                  ref.flatMap(GitHubLinks.personLogin(fromRef:)) == nil else { continue }
            for watch in landed where watch.isLive {
                guard let scope = watch.sourceRef,
                      scope.hasPrefix("gh:watchrepo:")
                        || GitHubLinks.personLogin(fromRef: scope) != nil else { continue }
                if GitHubRowTag.matches(scope: scope, ref: ref, url: thing.content,
                                        authorHandle: thing.authorHandle) {
                    counts[scope, default: 0] += 1
                }
            }
        }
        rows = landed.compactMap { thing in
            guard thing.isLive, let ref = thing.sourceRef else { return nil }
            let isPerson = GitHubLinks.personLogin(fromRef: ref) != nil
            let isRepo = ref.hasPrefix("gh:watchrepo:")
            guard isPerson || isRepo else { return nil }
            let new = lastLooked.map { thing.capturedAt > $0 } ?? false
            let week = counts[ref] ?? 0
            return AccountPageShape.Row(
                id: ref, title: thing.title,
                subline: watchSubline(thing, isPerson: isPerson, week: week),
                weekCount: week, hasNew: new, isYou: false,
                avatarURL: thing.authorAvatarURL ?? thing.previewImageURL)
        }
    }

    /// What a watch row says under its name.
    ///
    /// A repo names its LANGUAGE and star count, which is the fact the feed row
    /// stopped carrying when the type tag took that slot (2026-09-11) — the
    /// right trade in both places: on a feed row it was true of every row from
    /// that repo and therefore not distinguishing, and here it is the one line
    /// telling two watched repos apart. A person names their login, because the
    /// title above is a display name and two people called Alex are otherwise
    /// the same row.
    private func watchSubline(_ thing: Thing, isPerson: Bool, week: Int) -> String {
        var parts: [String] = []
        if isPerson {
            if let handle = thing.authorHandle, !handle.isEmpty { parts.append("@\(handle)") }
            else { parts.append(String(localized: "person")) }
        } else {
            if let language = thing.repoLanguage, !language.isEmpty { parts.append(language) }
            if let stars = thing.starCount, stars > 0 {
                parts.append("★\(GitHubStarContent.compact(stars))")
            }
            if parts.isEmpty { parts.append(String(localized: "repo")) }
        }
        // NO "nothing this week" (§83's honesty rule read the other way round):
        // a count of zero is already said by the row sitting under Quiet, and
        // printing it twice makes the quiet half of the list noisier than the
        // active one.
        if week > 0 { parts.append(String(localized: "\(week) this week")) }
        return parts.joined(separator: " · ")
    }

    /// Removing a watch deletes its row — the watch IS the thing.
    private func removeWatch(_ ref: String) {
        let r = ref
        let doomed = (try? modelContext.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.sourceRef == r }))) ?? []
        SpotlightIndex.remove(ids: doomed.map(\.id))
        for thing in doomed { modelContext.delete(thing) }
        modelContext.saveHonestly()
        readRows()
    }

    /// A watched repo or person opens on GitHub — its page is the profile.
    private func openWatch(_ ref: String) {
        let r = ref
        guard let thing = (try? modelContext.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.sourceRef == r })))?.first, thing.isLive,
              let url = URL(string: thing.content.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.hasPrefix("http") == true
        else { return }
        openURL(url)
    }

    private func watchRepo() {
        let q = watchField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !watching, let token = TokenVault.get(bridge.tokenKey) else { return }
        DSHaptic.tap()
        watching = true
        watchFaces = []
        Task {
            let resolved = await GitHubRepoWatch.resolve(q, token: token)
            watching = false
            guard let resolved else {
                watchResult = .failed(String(localized: "Couldn't find that repo on GitHub."))
                return
            }
            guard let thing = GitHubRepoWatch.add(resolved, context: modelContext) else {
                watchResult = .failed(String(localized: "\(resolved.fullName) is already watched."))
                return
            }
            watchField = ""
            watchQuery = ""
            watchResult = .says(String(localized: "Watching \(thing.title)"))
            readRows()
            await sync()
        }
    }

    /// Watch a person (prd §519). The repo verb's shape exactly, with two
    /// differences that are both about honesty: the failure sentence names the
    /// two ways a paste can fail here (a profile URL and a REPO URL look
    /// alike, and `GitHubLinks.personLogin` refuses the second rather than
    /// quietly watching its owner), and the success carries their face.
    private func watchPerson() {
        let q = personField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !watchingPerson, let token = TokenVault.get(bridge.tokenKey) else { return }
        DSHaptic.tap()
        watchingPerson = true
        watchFaces = []
        Task {
            let resolved = await GitHubPersonWatch.resolve(q, token: token)
            watchingPerson = false
            guard let resolved else {
                watchResult = .failed(String(localized: "No such account on GitHub — a username, or a link to a profile."))
                return
            }
            guard let thing = GitHubPersonWatch.add(resolved, context: modelContext) else {
                watchResult = .failed(String(localized: "\(resolved.login) is already watched."))
                return
            }
            personField = ""
            watchQuery = ""
            watchFaces = [resolved.avatarURL].compactMap { $0 }
            watchResult = .says(String(localized: "Watching \(thing.title)"))
            readRows()
            await sync()
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
        sheet = nil
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
                    result = .says(String(localized: "That token didn't work — check it (and your connection) and paste again."))
                    // "Paste again" must point at a visible field — if the
                    // manual path is folded (a device-flow connect that failed
                    // on its first sync), unfold it so the error and the field
                    // share the screen (review 2026-07-16).
                    withAnimation(DS.Motion.standard) { manualPathOpen = true }
                } else {
                    // A background re-sync of an already-connected bridge failed. The
                    // user didn't just paste anything, so don't accuse the empty field
                    // — say what actually happened: the saved token or the network.
                    result = .says(String(localized: "Couldn't refresh \(bridge.rawValue) just now — your saved token may need renewing."))
                }
                return
            }
            connecting = false
            result = added > 0 ? .says(String(localized: "\(added) \(bridge.noun) in")) : emptyReadNote().map(BridgeProof.says) ?? .upToDate
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
            }
        } while syncPending
    }
}
