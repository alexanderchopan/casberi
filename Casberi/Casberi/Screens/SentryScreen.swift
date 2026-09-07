import SwiftUI
import SwiftData

/// Sentry, connected — paste a scoped token, pick an organization, done.
///
/// Two states, one at a time, for `PostHogScreen`'s reason: a setup form that
/// renders its later steps greyed-out reads as broken (the §83 corollary about
/// disabled controls that still paint a live background). No org → the token
/// field; an org → the connected state.
///
/// Unlike PostHog there is no third step: Sentry needs no watch list. An
/// organization's unresolved issues ARE the read, so once the org is picked the
/// screen has nothing left to ask for.
struct SentryScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Environment(\.openURL) private var openURL

    @State private var hostField = SentryAccount.host
    @State private var tokenField = ""
    /// Bumped whenever the token or org changes, so the derived reads below
    /// re-evaluate. The STORES stay the source of truth — mirroring them into
    /// @State meant hand-kept assignments that could disagree with the
    /// Keychain (PostHog's lesson).
    @State private var accountVersion = 0

    @State private var orgs: [SentryFetch.Org] = []
    @State private var resolving = false
    @State private var syncing = false
    @State private var result: BridgeProof?
    /// The delight pass's coin-flip on the header, fired the moment the
    /// connection really goes live.
    /// Whether the mint door has been tapped — the only observable fact about
    /// step one, since everything after it happens on Sentry's website.
    @State private var doorTapped = false

    private var hasToken: Bool {
        _ = accountVersion
        return TokenBridge.sentry.connected
    }
    private var org: String {
        _ = accountVersion
        return SentryAccount.org
    }
    private var configured: Bool { hasToken && !org.isEmpty }

    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: "Sentry", seatID: TokenBridge.sentry.bridgeID, source: "Sentry",
            state: AccountPageState.of(name: "Sentry", seatID: TokenBridge.sentry.bridgeID,
                                       connected: configured, store: store),
            mode: .pasteKey,
            keyed: true,
            teardown: {
                SentryAccount.clear()
                TokenVault.delete(TokenBridge.sentry.tokenKey)
                accountVersion += 1
            },
            sheet: $sheet,
            act: {
                if configured {
                    // Which org this token reads, and what the read is doing.
                    // The token form and the org picker are the "Your key"
                    // sheet now — one block, reached from the row that says
                    // where the key lives.
                    connectedBlock
                } else {
                    tokenBlock
                    if hasToken, !orgs.isEmpty { orgBlock }
                }
            },
            more: { EmptyView() },
            keySheet: {
                tokenBlock
                if hasToken, !orgs.isEmpty { orgBlock }
            }
        )
        .onAppear {
            // Opening the page doesn't connect — a stored token and a picked
            // org do. Viewing is not consent.
            if configured { Task { await sync() } }
        }
    }


    // MARK: - Step one: the token

    /// The connect form — steps whole, furniture gone (prd §218). It is the
    /// act field with no key, and the "Your key" sheet once there is one, so a
    /// key is replaced by exactly the path it was pasted.
    @ViewBuilder private var tokenBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            // Unnumbered since 2026-08-14 (the door did step one; a "2"
            // under it read as a missing-1 riddle); `acknowledges` keeps
            // the confirm-green check when a step provably lands.
            BridgeSetupCard(steps: [TokenBridge.sentry.steps[0]], startingAt: 2,
                            numbered: false, acknowledges: true,
                            doneThrough: stepsDone) {
                if let url = TokenBridge.sentry.setupURL {
                    // Step one, doing itself (prd §218) — verb over address,
                    // the 2026-08-14 anatomy.
                    DSSlabButton(title: TokenBridge.sentry.doorTitle,
                                 detail: TokenBridge.sentry.doorHost,
                                 systemImage: "arrow.up.right") {
                        DSHaptic.tap()
                        doorTapped = true
                        openURL(url)
                    }
                }
            }
            // The scopes are the honest ask, and they are why this
            // bridge's read-only promise is STRUCTURAL rather than kept by
            // conduct: a token minted with these three physically cannot
            // resolve an issue or change a project, whatever this app
            // does. The list IS the promise, so no gray note restates it.
            DSCheckList(lines: ["org:read", "project:read", "event:read"])
            BridgeStepLines(steps: [TokenBridge.sentry.steps[1]], startingAt: 3,
                            numbered: false, acknowledges: true,
                            doneThrough: stepsDone)
            // The host has no verb of its own — SAVE below commits both.
            // An empty-verb field still paints its capsule, so a pre-filled
            // host would read as a live, tinted, inert button (§83's
            // disabled-control corollary) if it carried a label.
            DSSlabField(placeholder: SentryAccount.defaultHost, text: $hostField,
                        actionLabel: "", keyboard: .URL, action: { })
            DSSlabField(placeholder: TokenBridge.sentry.placeholder,
                        text: $tokenField, actionLabel: "Save", secure: true,
                        action: saveToken)
            BridgeSyncStatusRows(syncing: resolving,
                                 syncingLine: String(localized: "Checking the token…"),
                                 proof: result)
            // Named because the failure is otherwise a bare 401 that reads
            // exactly like a bad token — the one setup mistake here that
            // has nothing to do with what you pasted.
            DSSlabNote(text: "EU region? Use de.sentry.io. Self-hosted? Use your own domain.",
                       plain: true)
        }
    }

    /// Only OBSERVABLE facts count (the delight pass's rule): the door really
    /// being tapped, and text really arriving in the field. Nothing here infers
    /// that someone finished a step on Sentry's website.
    private var stepsDone: Int {
        if !tokenField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return 3 }
        if doorTapped { return 1 }
        return 0
    }

    // MARK: - Step two: the organization

    @ViewBuilder private var orgBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text("Which organization should I read?")
                .dsText(.body17).foregroundStyle(DS.textPrimary)
            ForEach(orgs, id: \.slug) { org in
                BridgeSearchResultRow(
                    imageURL: nil, fallbackIcon: "Sentry",
                    title: org.name,
                    subtitle: "\(SentryAccount.host)/\(org.slug)",
                    action: { pick(org) })
            }
        }
    }

    // MARK: - Connected

    @ViewBuilder private var connectedBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s3) {
                // Square, not round — an organization is a topic, not a
                // person (the mark grammar ruling, prd §184).
                BridgeIcon(name: "Sentry", size: DS.Mark.list, circular: false)
                VStack(alignment: .leading, spacing: 1) {
                    Text(SentryAccount.orgName.isEmpty ? org : SentryAccount.orgName)
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text("\(SentryAccount.host)/\(org)")
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            BridgeSyncStatusRows(syncing: syncing,
                                 syncingLine: String(localized: "Reading your issues…"),
                                 proof: result)
        }
    }


    // MARK: - Actions

    private func saveToken() {
        let token = tokenField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        SentryAccount.host = hostField
        resolving = true
        result = nil
        Task {
            defer { resolving = false }
            guard let found = await SentryFetch.organizations(
                host: SentryAccount.host, token: token) else {
                // Four failures, and the two recoverable ones must not read as
                // a typo (the Stripe four-sentences ruling). The probe splits
                // 401 from 403; here the one sentence has to carry both, so it
                // names the host as well as the token.
                result = .failed(String(localized: "Sentry refused that. Check the token — and the host, if your org is on the EU region or self-hosted."))
                return
            }
            TokenVault.set(token, for: TokenBridge.sentry.tokenKey)
            tokenField = ""
            orgs = found
            accountVersion += 1
            DSHaptic.tap()
            if found.count == 1 {
                // One organization is not a choice. Picking it for them skips
                // a screen that would only ever have one row on it.
                pick(found[0])
            } else if found.isEmpty {
                result = .failed(String(localized: "That token works but can't see any organizations — it may be missing org:read."))
            } else {
                result = nil
            }
        }
    }

    private func pick(_ org: SentryFetch.Org) {
        SentryAccount.org = org.slug
        SentryAccount.orgName = org.name
        accountVersion += 1
        DSHaptic.tap()
        Task { await sync() }
    }

    /// Fetch + land; the bridge's status line carries the proof.
    private func sync() async {
        guard configured else { return }
        if syncing { return }
        syncing = true
        defer { syncing = false }
        let added = await SentryIngest.refresh(context: modelContext)
        guard configured else { return }
        if let added {
            result = added > 0 ? .landed(added) : TokenBridge.sentry.emptyReadNote.map(BridgeProof.says) ?? .upToDate
            let proof = added > 0
                ? String(localized: "\(added) in")
                : String(localized: "Synced just now")
            store.registerConnected(id: TokenBridge.sentry.bridgeID, name: "Sentry",
                                    proof: proof,
                                    can: [TokenBridge.sentry.canLine])
        } else {
            result = .failed(String(localized: "Couldn't reach Sentry — check your connection."))
        }
    }

}
