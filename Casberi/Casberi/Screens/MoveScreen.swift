import SwiftData
import SwiftUI
import UIKit

/// **MOVE (prd §1422): your account's page** — the Apple pass of the
/// 2026-10-18 canvas (docs/safe-wallet-spec.md, section 2a). Centred head: your
/// account's face, its name, its address. Then the modules, bare on the page
/// (§1382, §1393), a 32pt seam between them (§1386).
///
/// **Move is the acts alone (prd §1436)**, and since §1438 one sentence you
/// fill in (`MoveSentence`): Swap · Send · Receive. Security's rows went to
/// the Wallet's Security tile (`MoveSecurity`, §1427). The head stands only
/// before the account exists.
/// **MOVE IS A TRAY (prd §1442)**, raised from its tab over wherever you
/// are (user, 2026-10-20: "why not make the move button be a tray or sheet
/// or whatever and not a page?"): an act, not a place. It is one height,
/// the full sheet, and never changes shape (§1442a, user: "it is very
/// jittery. needs to be stable"): the sentence stands at its foot and rises
/// as a blank's choices open under it. Untitled, because the verbs are its
/// head.
struct MoveTray: View {
    var body: some View {
        DSTray(title: "Move", height: 600, detents: [.large], titled: false) {
            MoveScreen(inTray: true)
        }
    }
}

/// Raises `MoveTray` when the Move tab asks (`ShellChrome.moveTray`), with
/// the shell's environment re-injected: a sheet is built in its own host and
/// inherits none of it (the 2.1(a) crash `rootPresented` exists for).
struct MoveTrayPresenter: ViewModifier {
    let chrome: ShellChrome
    let route: HomeRoute
    let bridges: BridgeStore
    let context: ModelContext

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(get: { chrome.moveTray }, set: { chrome.moveTray = $0 })) {
            MoveTray()
                .environment(chrome)
                .environment(route)
                .environment(bridges)
                .environment(\.modelContext, context)
                .environment(\.locale, LanguageStore.shared.locale)
        }
    }
}

struct MoveScreen: View {
    /// Drawn in `MoveTray` rather than as a page.
    var inTray = false
    @Environment(ShellChrome.self) private var chrome
    @State private var address: String? = YourAccountKey.address
    @State private var creating = false
    /// What setting up said, under its verb: a toast draws under the tray
    /// (§1442c), so the page says it in place.
    @State private var note: (text: String, failure: Bool)?
    /// An account whose recovery key this phone's iCloud Keychain holds,
    /// when this phone has none of its own yet (prd §1427).
    @State private var recoverable: (address: String, origin: String)?
    /// Made or brought here in this tray: the sentence finishes itself
    /// ("Your account" → "Created …3416", §1442j).
    @State private var arrival: MoveSentence.Arrival?

    #if DEBUG
    /// `-movePreview create|recover|created|ready` (DEBUG): draw a screen
    /// of §1442j over a phone that already has an account, without touching
    /// its key — create and recover are inert here, so the preview can never
    /// make or move an account.
    private var preview: String? { UserDefaults.standard.string(forKey: "movePreview") }
    #endif

    var body: some View {
        Group {
            #if DEBUG
            if let preview, preview == "create" || preview == "recover" {
                before
                    .task {
                        if preview == "recover" {
                            recoverable = (address ?? "0xb91a38aA11C903bf5A465326b9c0cf8680F43416", "preview")
                        }
                        NSLog("movePreview: %@", preview)
                    }
            } else if let preview, let address, preview == "created" || preview == "ready" {
                MoveSentence(account: address, inTray: inTray, arrival: preview == "ready" ? .broughtHere : .created)
            } else {
                shown
            }
            #else
            shown
            #endif
        }
        .background { if !inTray { DSPageBackground() } }
        .task {
            if address == nil { recoverable = YourAccountRecovery.accounts().first } else { YourAccountKey.ensureRecord() }
        }
    }

    @ViewBuilder private var shown: some View {
        Group {
            if let address {
                // The account exists: the page is the sentence (prd §1438),
                // no head — it is this phone's account, there is no other.
                MoveSentence(account: address, inTray: inTray, arrival: arrival)
                    .transition(.opacity)
            } else {
                before
            }
        }
    }

    // MARK: Before the account exists

    /// **CREATE AND RECOVER IN THE SENTENCE (§1442j, user: "should we look at
    /// the account create recover etc flows now"; "build it").** One shape
    /// for both: "Your account [ …3416 ] / on <the networks>." No verbs yet,
    /// because none can be tapped; one line of small print; one act at the
    /// foot, where Swap, Send and Share stand.
    private var before: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                line(nil) {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                        Text("Your account")
                            .dsText(MoveSentence.size).foregroundStyle(DS.textPrimary)
                        if let recoverable {
                            Text(verbatim: YourAccount.short(recoverable.address))
                                .dsText(MoveSentence.size).foregroundStyle(DS.pickInk)
                        }
                    }
                }
                line(String(localized: "on")) {
                    Text(verbatim: YourAccountOp.networks.filter { !$0.isTest }.map(\.name).formatted(.list(type: .and)) + ".")
                        .dsText(MoveSentence.size).foregroundStyle(DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    if let recoverable {
                        Text(verbatim: recoverable.address)
                            .dsText(.mono12)
                            .foregroundStyle(DS.textSecondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        // What a person needs (prd §1434): it is theirs, it is
                        // here, and the one real consequence.
                        Text("Found in your iCloud Keychain. Your other \(ThisDevice.name) stops sending from it.")
                            .dsText(.body17).foregroundStyle(DS.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        // The one fact that decides the tap (§1442j); the rest
                        // is said once the account exists.
                        Text("Face ID signs. No seed phrase.")
                            .dsText(.body17).foregroundStyle(DS.textSecondary)
                    }
                    if let note {
                        Text(verbatim: note.text)
                            .dsText(.body17)
                            .foregroundStyle(note.failure ? DS.attentionInk : DS.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, MoveSentence.gutter + DS.Space.s2)
                .padding(.top, DS.Space.s4)
            }
            .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
            .padding(.top, inTray ? DS.Space.s8 : DS.Space.s6 + DS.Space.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { beforeFoot }
    }

    /// A line in the sentence's gutter grammar (§1442f).
    private func line<Value: View>(_ glue: String?, @ViewBuilder _ value: () -> Value) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Text(verbatim: glue ?? " ")
                .dsText(.heading17)
                .foregroundStyle(DS.textPrimary)
                .frame(width: MoveSentence.gutter, alignment: .leading)
            value()
        }
    }

    /// The one act, at the trailing edge; recovering, a quiet choice beside it.
    private var beforeFoot: some View {
        HStack(alignment: .firstTextBaseline) {
            if recoverable != nil {
                Button { create() } label: {
                    Text("New account")
                        .dsText(.heading17)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(minHeight: 48)
                }
                .buttonStyle(RowPress())
                .disabled(creating)
            }
            Spacer(minLength: DS.Space.s3)
            Button {
                if let recoverable { recover(recoverable) } else { create() }
            } label: {
                Text(verbatim: creating
                     ? (recoverable == nil ? String(localized: "Creating…") : String(localized: "Setting up…"))
                     : (recoverable == nil ? String(localized: "Create") : ThisDevice.use))
                    .dsText(.heading28)
                    .foregroundStyle(creating ? DS.textTertiary : DS.pickInk)
                    // One line, as every foot verb is.
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(minHeight: 48, alignment: .trailing)
            }
            .buttonStyle(RowPress())
            .disabled(creating)
        }
        .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
        .padding(.bottom, DS.Space.s2)
        .background { if inTray { DS.surfaceSheet } else { DSPageBackground() } }
    }

    /// Take the account onto this phone: a new key here, then the recovery
    /// key moves each network the account is on to it.
    private func recover(_ found: (address: String, origin: String)) {
        #if DEBUG
        if preview != nil { NSLog("movePreview: recover is inert"); return }
        #endif
        guard !creating else { return }
        creating = true
        Task {
            do {
                // This phone's own account, reinstalled: its keys already sign.
                guard let index = try YourAccountKey.adopt(address: found.address, origin: found.origin) else {
                    arrival = .broughtHere
                    withAnimation(DS.Motion.standard) { address = found.address }
                    note = (ThisDevice.ready, false)
                    creating = false
                    return
                }
                var targets: [YourAccountOp.Network] = []
                var failed: [String] = []
                for net in YourAccountOp.networks {
                    do {
                        if try await YourAccountChain.isDeployed(net, found.address) { targets.append(net) }
                    } catch {
                        failed.append(String(localized: "\(net.name) did not answer"))
                    }
                }
                failed += await MoveRecovery.move(targets, to: index)
                WalletStore.shared.add(found.address, label: String(localized: "Your account"))
                arrival = .broughtHere
                    withAnimation(DS.Motion.standard) { address = found.address }
                if failed.isEmpty {
                    note = (ThisDevice.ready, false)
                } else {
                    note = (failed.joined(separator: " · "), true)
                }
            } catch {
                note = (String(localized: "Couldn't make a key on this device"), true)
            }
            creating = false
        }
    }

    private func create() {
        #if DEBUG
        if preview != nil { NSLog("movePreview: create is inert"); return }
        #endif
        creating = true
        do {
            let made = try YourAccountKey.create()
            // Followed in the Wallet from the start, so its balance and moves
            // land where every account's do.
            WalletStore.shared.add(made, label: String(localized: "Your account"))
            arrival = .created
            withAnimation(DS.Motion.standard) { address = made }
            DSHaptic.success()
        } catch {
            note = (String(localized: "Couldn't create the account on this device"), true)
        }
        creating = false
    }
}
