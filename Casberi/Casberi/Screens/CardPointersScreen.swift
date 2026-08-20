import SwiftUI
import SwiftData

/// CardPointers' setup — RFC 8628 device flow, so nobody ever mints, copies or
/// pastes a token, and no password is typed anywhere near this app (prd §420).
///
/// **The screen's one unusual move: a successful sign-in is not necessarily a
/// connection.** Every read here needs CardPointers+, and the sign-in response
/// says whether this account has it (`is_pro`) — so a free account signs in,
/// is told plainly what it can and cannot do, and the seat is NOT registered.
/// Registering it would put a room in the catalog that can never fill, which is
/// the §83 dead control wearing a green checkmark. The token is kept either
/// way, so the day somebody subscribes it simply starts working.
struct CardPointersScreen: View {
    @Environment(BridgeStore.self) private var store
    @Environment(\.openURL) private var openURL

    @State private var flow: Task<Void, Never>?
    @State private var pending: CardPointersWire.DeviceCode?
    @State private var result: String?
    @State private var resultIsError = false
    @State private var needsPlus = false
    @State private var upgradeURL: String?
    @State private var flipTrigger = 0
    @State private var codeCopied = false

    private var connected: Bool { CardPointersAuth.isConnected && CardPointersAuth.isPro }

    var body: some View {
        List {
            if connected {
                BridgeConnectedState(
                    bridgeID: CardPointersAuth.seatKey,
                    name: "CardPointers",
                    identity: String(localized: "CardPointers+"),
                    connectionNote: String(localized: "Signed in on \(DS.device)"),
                    capabilitiesFallback: ["Reads your cards and their offers.",
                                           "Read-only — every tool they publish is a read."],
                    openConnection: { disconnect() }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                BridgeSetupHeader(
                    name: "CardPointers",
                    mode: .signIn,
                    intro: "Sign in on CardPointers' own page and the offers sitting unused on your cards keep arriving, each with the date it expires.",
                    flipTrigger: flipTrigger)
                connectSection.listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "CardPointers")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("CardPointers")
        .onDisappear { flow?.cancel() }
    }

    @ViewBuilder
    private var connectSection: some View {
        Section {
            if let pending {
                // The code is shown even though `verification_uri_complete`
                // already carries it: a browser that opens to a signed-out
                // session sends them through a sign-in first, and the code has
                // to survive that trip.
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    Text("Your code")
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    // `monoCode34` is the ramp's own device-flow rung, and the
                    // explicit Copy button is a lesson already paid for twice:
                    // GitHub's identical step shipped as bare tap-to-copy and
                    // went unnoticed (user, 2026-07-15), and Twitch's screen
                    // repeated it until the 2026-07-31 audit. Third time, on
                    // purpose, rather than a fourth report.
                    HStack(spacing: DS.Space.s3) {
                        Text(pending.userCode)
                            .dsText(.monoCode34)
                            .foregroundStyle(DS.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Button(action: { copyCode(pending.userCode) }) {
                            HStack(spacing: DS.Space.s1) {
                                Image(systemName: codeCopied ? "checkmark" : "doc.on.doc")
                                    .dsGlyph(13)
                                Text(codeCopied ? "Copied" : "Copy")
                                    .dsText(.subhead13).fontWeight(.semibold)
                            }
                            .foregroundStyle(codeCopied ? DS.confirm : DS.tint)
                            .padding(.horizontal, DS.Space.s3)
                            .frame(height: 34)
                            .background(DS.gray100, in: Capsule(style: .continuous))
                            .contentShape(Capsule(style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    HStack(spacing: DS.Space.s2) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for you to approve…")
                            .dsText(.callout15).foregroundStyle(DS.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsListCardRow()
                DSSlabButton(title: "Open the approval page",
                             systemImage: "safari",
                             action: { open(pending.verificationURLComplete) })
            } else if needsPlus {
                // A real answer with a real door, not a failure. This account
                // signed in fine; it simply cannot read anything.
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text("This account doesn't have CardPointers+")
                        .dsText(.callout15)
                    Text("Their offer tools need the subscription. Nothing was connected.")
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsListCardRow()
                if let upgradeURL {
                    DSSlabButton(title: "See CardPointers+",
                                 systemImage: "arrow.up.forward",
                                 action: { open(upgradeURL) })
                }
            } else {
                DSSlabButton(title: "Connect CardPointers",
                             systemImage: "person.badge.key",
                             action: connect)
            }

            BridgeSyncStatusRows(syncing: false, syncingLine: "",
                                 result: result, resultIsError: resultIsError)
            DSSlabNote(text: "Requires CardPointers+ — a free account can't read its offers.")
        }
        .dsSlabSection()
    }

    // MARK: - Flow

    private func connect() {
        result = nil; resultIsError = false; needsPlus = false
        flow?.cancel()
        flow = Task {
            guard let code = await CardPointersAuth.startDeviceFlow() else {
                await MainActor.run {
                    result = String(localized: "Couldn't reach CardPointers.")
                    resultIsError = true
                }
                return
            }
            await MainActor.run { pending = code }
            open(code.verificationURLComplete)
            await waitForApproval(code)
        }
    }

    /// The poll loop lives on the screen, not in the bridge, so leaving the
    /// screen stops it — a loop owned by the bridge would outlive the view that
    /// started it and keep asking their host about a code nobody is waiting on.
    private func waitForApproval(_ code: CardPointersWire.DeviceCode) async {
        let deadline = Date().addingTimeInterval(TimeInterval(code.expiresIn))
        while !Task.isCancelled && Date() < deadline {
            try? await Task.sleep(for: .seconds(code.interval))
            if Task.isCancelled { return }
            switch await CardPointersAuth.pollOnce(deviceCode: code.deviceCode) {
            case .pending:
                continue
            case .granted(let token):
                await MainActor.run { land(token) }
                return
            case .denied:
                await MainActor.run { fail(String(localized: "You declined the request.")) }
                return
            case .expired:
                await MainActor.run { fail(String(localized: "The code expired. Try again.")) }
                return
            case .unreadable:
                await MainActor.run { fail(String(localized: "CardPointers gave an answer we couldn't read.")) }
                return
            }
        }
        if !Task.isCancelled {
            await MainActor.run { fail(String(localized: "The code expired. Try again.")) }
        }
    }

    @MainActor
    private func land(_ token: CardPointersWire.Token) {
        CardPointersAuth.store(token)
        pending = nil
        guard token.isPro else {
            // Signed in, and deliberately NOT connected. See the type comment.
            needsPlus = true
            upgradeURL = "https://cardpointers.com/plus"
            return
        }
        flipTrigger += 1
        _ = store.registerConnected(id: CardPointersAuth.seatKey,
                                    name: "CardPointers",
                                    proof: String(localized: "Signed in on \(DS.device)"),
                                    can: ["Reads your cards and their offers.",
                                          "Read-only — every tool they publish is a read."])
        result = String(localized: "Connected.")
        resultIsError = false
    }

    @MainActor
    private func fail(_ message: String) {
        pending = nil
        result = message
        resultIsError = true
    }

    private func disconnect() {
        CardPointersAuth.disconnect()
        needsPlus = false
        result = nil
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

    private func open(_ raw: String) {
        guard let url = URL(string: raw) else { return }
        openURL(url)
    }
}
