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
    @State private var result: String?
    @State private var resultIsError = false

    /// GitHub's device flow (prd §67 goal ②) — sign in on github.com instead
    /// of hunting a token. Only GitHub has a public-client flow; the other
    /// bridges stay paste-only, honestly.
    private enum DevicePhase { case idle, requesting, waiting(GitHubDeviceFlow.Code) }
    @State private var devicePhase: DevicePhase = .idle
    @State private var pollTask: Task<Void, Never>?
    private var deviceFlowOffered: Bool {
        bridge == .github && GitHubDeviceFlow.isAvailable
    }

    /// This bridge's things — cached per appearance and after each sync, rather
    /// than re-fetched twice on every body pass. The source is per-bridge, so
    /// this is the cache path rather than a static @Query.
    @State private var recent: [Thing] = []

    private func loadRecent() {
        recent = recentBridgeThings(source: bridge.rawValue, context: modelContext)
    }

    var body: some View {
        List {
            BridgeSetupHeader(name: bridge.rawValue)
            if deviceFlowOffered { signInSection }
            stepsSection
            tokenSection
            if !recent.isEmpty {
                PinToHomeButton(source: bridge.rawValue, inSection: true)
                RecentThingsSection(header: "Landed", things: recent)
            }
            if bridge.connected { removeSection }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle(bridge.rawValue)
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            loadRecent()
            if bridge.connected {
                Task { await sync() }
            }
        }
        .onDisappear { cancelDeviceFlow() }
    }

    /// The sign-in path — GitHub shows a short code here, you approve it on
    /// github.com, and the token arrives on its own. One row, three phases.
    private var signInSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                switch devicePhase {
                case .idle:
                    Button(action: startDeviceFlow) {
                        HStack(spacing: DS.Space.s2) {
                            Image(systemName: "person.badge.key")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Sign in with GitHub")
                                .dsText(.callout15).fontWeight(.semibold)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(DS.tint, in: Capsule(style: .continuous))
                        .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                case .requesting:
                    HStack(spacing: DS.Space.s2) {
                        ProgressView()
                        Text("Asking GitHub for a code…")
                            .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    }
                case .waiting(let code):
                    // The code is the whole moment — big, spaced by GitHub's
                    // own hyphen, one tap to copy in case Safari loses it.
                    Text(code.userCode)
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .foregroundStyle(DS.textPrimary)
                        .frame(maxWidth: .infinity)
                        .onTapGesture {
                            UIPasteboard.general.string = code.userCode
                            DSHaptic.tap()
                        }
                    Text("Enter this code on GitHub — approval lands the token here by itself.")
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        openURL(code.verificationURL)
                    } label: {
                        Text("Open github.com/login/device")
                            .dsText(.callout15).fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(DS.tint, in: Capsule(style: .continuous))
                            .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
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
            }
            .dsListCardRow()
        } header: {
            Text("Sign in").dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        } footer: {
            Text("Sign-in grants GitHub's standard repo scope — the smallest that reaches private issues and pull requests. Casberi only reads; any future write will ask first, every time.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

    private func startDeviceFlow() {
        DSHaptic.tap()
        devicePhase = .requesting
        result = nil
        pollTask = Task { @MainActor in
            guard let code = await GitHubDeviceFlow.start() else {
                finishDeviceFlow(error: String(localized: "GitHub didn't answer — try again, or paste a token below."))
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

    private var stepsSection: some View {
        // One list row holding the whole numbered list — a Section of ForEach
        // rows draws a separator between them that survives row-level
        // .listRowSeparator(.hidden) (SwiftUI won't suppress the first
        // post-header separator); collapsing to a single row means no inter-row
        // separator can exist. Design law: no hairlines, zero exceptions.
        Section {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(bridge.steps.enumerated()), id: \.offset) { i, text in
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
                        Text("\(i + 1)")
                            .dsText(.body17).fontWeight(.bold)
                            .foregroundStyle(DS.tint)
                            .frame(width: 20)
                        Text(LocalizedStringKey(text))
                            .dsText(.body17).foregroundStyle(DS.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, DS.Space.s1)
                }
            }
            .dsListCardRow()
        } header: {
            // With sign-in above, the token hunt reads as the fallback it is.
            Text(deviceFlowOffered ? "Or get a token by hand" : "Get your token")
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        }
    }

    private var tokenSection: some View {
        // Field + status in ONE list row (a VStack) — a headed Section of two
        // rows leaks a hairline between them that row-level
        // .listRowSeparator(.hidden) won't suppress (SwiftUI first-post-header
        // separator). Design law: no hairlines, zero exceptions.
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                BridgeFieldRow(placeholder: bridge.placeholder, text: $tokenField,
                               buttonLabel: bridge.connected ? "Update" : "Connect",
                               secure: true, action: connect)
                BridgeSyncStatusRows(syncing: syncing,
                                     syncingLine: String(localized: "Fetching your \(bridge.noun)…"),
                                     result: result, resultIsError: resultIsError)
            }
            .dsListCardRow()
        } header: {
            Text("Token").dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        } footer: {
            Text("The token stays in this iPhone's Keychain and goes only to \(bridge.rawValue) itself. Read-only.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

    private var removeSection: some View {
        Section {
            Button("Remove token", role: .destructive) {
                TokenVault.delete(bridge.tokenKey)
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
        TokenVault.set(token, for: bridge.tokenKey)
        tokenField = ""
        DSHaptic.tap()
        Task { await sync(justConnected: true) }
    }

    private func sync(justConnected: Bool = false) async {
        guard !syncing else { return }
        syncing = true
        let added = await TokenIngest.refresh(bridge, context: modelContext)
        syncing = false
        loadRecent()
        guard let added else {
            if justConnected {
                // A fresh paste that fails doesn't stay: keeping it would show
                // "Update"/"Remove token" for a connection that never worked and
                // retry a dead token on every foreground.
                TokenVault.delete(bridge.tokenKey)
                result = String(localized: "That token didn't work — check it (and your connection) and paste again.")
            } else {
                // A background re-sync of an already-connected bridge failed. The
                // user didn't just paste anything, so don't accuse the empty field
                // — say what actually happened: the saved token or the network.
                result = String(localized: "Couldn't refresh \(bridge.rawValue) just now — your saved token may need renewing.")
            }
            resultIsError = true
            return
        }
        resultIsError = false
        result = added > 0 ? String(localized: "\(added) \(bridge.noun) in") : String(localized: "Up to date")
        let proof = added > 0 ? "\(added) \(bridge.noun) in" : "Synced just now"
        if store.registerConnected(id: bridge.bridgeID, name: bridge.rawValue,
                                   proof: proof, can: [bridge.canLine]) {
            DSHaptic.success()
        }
    }
}
