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
        content.sheet(isPresented: Binding(get: { chrome.moveTray }, set: { chrome.moveTray = $0 }),
                      onDismiss: { chrome.movePrivately = nil; chrome.moveFreshReceive = false }) {
            MoveTray()
                .environment(chrome)
                .environment(route)
                .environment(bridges)
                .environment(\.modelContext, context)
                .environment(\.locale, LanguageStore.shared.locale)
        }
        #if DEBUG
        // `-openMove YES`: raise Move at mount, no tap (prd §1473), so a
        // drafted sentence can be photographed on a simctl-booted simulator.
        .task {
            guard UserDefaults.standard.bool(forKey: "openMove") else { return }
            try? await Task.sleep(for: .seconds(1))
            NSLog("[Casberi] openMove: raised")
            chrome.moveTray = true
        }
        // `-moveToPrivate YES` raises Send to your private balance, as
        // Holdings' Private header does; `-movePrivateSend YES` raises Send
        // with the Private switch on, as a private row does (prd §1554).
        .task {
            let mode: PrivateMove.Mode? = UserDefaults.standard.bool(forKey: "movePrivateSend") ? .send
                : UserDefaults.standard.bool(forKey: "moveToPrivate") ? .deposit : nil
            guard let mode else { return }
            try? await Task.sleep(for: .seconds(1))
            NSLog("[Casberi] movePrivately: raised %@", mode == .send ? "send" : "deposit")
            chrome.movePrivately = mode
            chrome.moveTray = true
        }
        // `-moveFreshReceive YES` raises Receive with its Private switch on: a
        // fresh address (prd §1560).
        .task {
            guard UserDefaults.standard.bool(forKey: "moveFreshReceive") else { return }
            try? await Task.sleep(for: .seconds(1))
            NSLog("[Casberi] moveFreshReceive: raised")
            chrome.moveFreshReceive = true
            chrome.moveTray = true
        }
        #endif
    }
}

struct MoveScreen: View {
    /// Drawn in `MoveTray` rather than as a page.
    var inTray = false
    @Environment(ShellChrome.self) private var chrome
    /// The demo's own account in the demo (prd §1475), else this phone's.
    @State private var address: String? = YourAccountDemo.shownAddress
    @State private var creating = false
    /// What setting up said, under its verb: a toast draws under the tray
    /// (§1442c), so the page says it in place.
    @State private var note: (text: String, failure: Bool)?
    /// An account whose recovery key this phone's iCloud Keychain holds,
    /// when this phone has none of its own yet (prd §1427).
    @State private var recoverable: (address: String, origin: String)?
    /// Brought here in this tray: the sentence finishes itself ("Your
    /// account" → "Ready …3416", §1442j). A made account ends on the walk's
    /// own Created page instead (prd §1501).
    @State private var arrival: MoveSentence.Arrival?
    /// The walk ended on Receive (prd §1501): Move opens there.
    @State private var opening: MoveSentence.Verb?
    /// Just created: the walk (prd §1457, §1501), which ends on Created.
    @State private var walking = false
    #if DEBUG
    /// `-keysWalk YES` (DEBUG): the walk again for this phone's account, at
    /// `-keysStep`, keeping what it chose — for a step a relaunch cut off.
    private static var walkAgain: Bool { UserDefaults.standard.bool(forKey: "keysWalk") }
    #endif
    /// Recovering: the networks the recovery key can bring it to (§1442k).
    @State private var recoverableOn: [YourAccountOp.Network]?
    /// To private with no account on this phone (prd §1554): the test
    /// sender sends it, so the sentence stands without one.
    @State private var privateMove = PrivateMove(mode: .deposit)

    #if DEBUG
    /// `-movePreview create|recover|keys|ready` (DEBUG): draw a screen
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
            } else if let preview, let address, preview == "keys" {
                // `-keysStep 1…4` opens on a step; inert, nothing is kept.
                let n = UserDefaults.standard.integer(forKey: "keysStep")
                MoveKeysWalk(account: address, inTray: inTray, inert: true,
                             step: MoveKeysWalk.Step(rawValue: n) ?? .recovery) { ending in
                    NSLog("movePreview: keys done, %@", ending == .close ? "close" : "receive")
                }
            } else if let preview, let address, preview == "ready" {
                MoveSentence(account: address, inTray: inTray, arrival: .broughtHere)
            } else {
                shown
            }
            #else
            shown
            #endif
        }
        .background { if !inTray { DSPageBackground() } }
        .task {
            if YourAccountDemo.isOn { return }
            if address == nil { recoverable = YourAccountRecovery.accounts().first } else { YourAccountKey.ensureRecord() }
        }
        .task(id: recoverable?.address) {
            guard let found = recoverable?.address else { return }
            recoverableOn = await YourAccountReach.recoverable(found)
        }
    }

    @ViewBuilder private var shown: some View {
        Group {
            if let address, walking || walkAgainNow {
                MoveKeysWalk(account: address, inTray: inTray, step: walkStep) { ending in
                    walkAgainDone = true
                    // Done closes Move — it rose over wherever you were —
                    // and Receive opens it there (prd §1501).
                    opening = ending == .receive ? .receive : nil
                    withAnimation(DS.Motion.standard) { walking = false }
                    if ending == .close, inTray { chrome.moveTray = false }
                }
                .transition(.opacity)
            } else if let address {
                // The account exists: the page is the sentence (prd §1438),
                // no head — it is this phone's account, there is no other.
                MoveSentence(account: address, inTray: inTray, arrival: arrival, opening: opening,
                             privately: chrome.movePrivately, receivePrivately: chrome.moveFreshReceive)
                    .transition(.opacity)
            } else if let mode = chrome.movePrivately, PrivateMove.available {
                // No account yet, so no other verb can be tapped: Send's
                // private sentence under its one word. With no public send
                // here, the switch off is the deposit, and picking someone
                // else is the switch on.
                MovePrivateSentence(move: privateMove, inTray: inTray, leave: { why in
                    privateMove.mode = why == .switchOff ? .deposit : .send
                }) {
                    Text("Send")
                        .dsText(.heading24)
                        .foregroundStyle(DS.textPrimary)
                        .frame(minHeight: 44, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                }
                .onAppear { privateMove.mode = mode }
            } else if chrome.moveFreshReceive, PrivateMove.freshAvailable {
                // No account yet: Receive's fresh address under its one
                // word (prd §1560). It never needs your account.
                MoveFreshSentence(inTray: inTray, leave: { chrome.moveFreshReceive = false }) {
                    Text("Receive")
                        .dsText(.heading24)
                        .foregroundStyle(DS.textPrimary)
                        .frame(minHeight: 44, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                }
            } else {
                before
            }
        }
    }

    @State private var walkAgainDone = false
    private var walkAgainNow: Bool {
        #if DEBUG
        return Self.walkAgain && !walkAgainDone
        #else
        return false
        #endif
    }
    private var walkStep: MoveKeysWalk.Step {
        #if DEBUG
        if walkAgainNow { return MoveKeysWalk.Step(rawValue: UserDefaults.standard.integer(forKey: "keysStep")) ?? .recovery }
        #endif
        return .recovery
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
                // The sentence as one flow of clauses (§1466): the account,
                // then "on" the networks, wrapping between them.
                MoveFlow {
                    MoveClause {
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                            MoveWord(String(localized: "Your account"))
                            if let recoverable {
                                MoveWord(YourAccount.short(recoverable.address), ink: DS.pickInk)
                            }
                        }
                    }
                    // Creating, every network; recovering, only where the
                    // recovery key can bring it (§1442k).
                    MovePhrase(recoverable == nil
                               ? YourAccountReach.words(YourAccountOp.networks.filter { !$0.isTest })
                               : recoverableOn.map(YourAccountReach.words) ?? "…",
                               glue: String(localized: "on"),
                               ink: recoverable != nil && recoverableOn == nil ? DS.textTertiary : DS.textPrimary)
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
                        // is said once the account exists. "Approves every
                        // move", not "signs": signing is crypto's word, and a
                        // move is the app's — swap, send, buy, a key or a
                        // limit changed (prd §1500).
                        Text("Face ID approves every move.")
                            .dsText(.body17).foregroundStyle(DS.textSecondary)
                    }
                    if let note {
                        Text(verbatim: note.text)
                            .dsText(.body17)
                            .foregroundStyle(note.failure ? DS.attentionInk : DS.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, DS.Space.s4)
            }
            .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
            .padding(.top, inTray ? DS.Space.s8 : DS.Space.s6 + DS.Space.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { beforeFoot }
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
                    .dsText(.heading34)
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
                WalletStore.shared.add(found.address, label: WalletStore.yourAccountName)
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
            WalletStore.shared.add(made, label: WalletStore.yourAccountName)
            walking = true
            withAnimation(DS.Motion.standard) { address = made }
            DSHaptic.success()
        } catch {
            #if DEBUG
            NSLog("moveCreate| failed: %@", String(describing: error))
            #endif
            note = (String(localized: "Couldn't create the account on this device"), true)
        }
        creating = false
    }
}
