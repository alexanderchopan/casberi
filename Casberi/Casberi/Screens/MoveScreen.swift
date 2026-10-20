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

    var body: some View {
        Group {
            if let address {
                // The account exists: the page is the sentence (prd §1438),
                // no head — it is this phone's account, there is no other.
                MoveSentence(account: address, inTray: inTray)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        head
                        if let recoverable {
                            recoverRow(recoverable)
                                .padding(.top, DSRoomChassis.sectionGap)
                        } else {
                            createRow
                                .padding(.top, DSRoomChassis.sectionGap)
                        }
                        if let note {
                            Text(verbatim: note.text)
                                .dsText(.body17)
                                .foregroundStyle(note.failure ? DS.attentionInk : DS.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.top, DS.Space.s3)
                        }
                    }
                    .padding(.horizontal, DSRoomChassis.leadInset)
                    .padding(.top, DS.Space.s6)
                    .padding(.bottom, DS.Space.s8 * 3)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background { if !inTray { DSPageBackground() } }
        .task {
            if address == nil { recoverable = YourAccountRecovery.accounts().first } else { YourAccountKey.ensureRecord() }
        }
    }

    // MARK: The head

    /// Before the account exists: the move mark, centred, and its name.
    private var head: some View {
        VStack(spacing: DS.Space.s2) {
            Image(systemName: ScopeTileGlyph.move)
                .dsGlyph(.title, weight: .semibold)
                .foregroundStyle(DS.brandInk)
                .frame(width: DS.Face.sheet, height: DS.Face.sheet)
                .accessibilityHidden(true)
            Text("Your account")
                .dsText(.heading24)
                .foregroundStyle(DS.headInk)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Before the account exists

    private var createRow: some View {
        VStack(spacing: DS.Space.s3) {
            DSFootnote("A wallet only you control. Its key never leaves this iPhone, and it can receive before its first send.", centered: true)
            Button {
                create()
            } label: {
                Text(creating ? "Creating…" : "Create your account")
                    .dsText(.heading17)
                    .foregroundStyle(DS.pickInk)
                    .frame(minHeight: 44)
            }
            .buttonStyle(RowPress())
            .disabled(creating)
        }
        .frame(maxWidth: .infinity)
    }

    /// A phone with no account of its own, whose iCloud Keychain holds one's
    /// recovery key: the account, and one verb that brings it here.
    private func recoverRow(_ found: (address: String, origin: String)) -> some View {
        VStack(spacing: DS.Space.s3) {
            Text(verbatim: found.address)
                .dsText(.mono12)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            // What a person needs (prd §1434, user: "nobody will understand
            // that"): their account is here; say yes and it works on this
            // device. The one consequence worth saying is the real one.
            Button {
                recover(found)
            } label: {
                Text(verbatim: creating ? String(localized: "Setting up…") : ThisDevice.use)
                    .dsText(.heading17)
                    .foregroundStyle(DS.pickInk)
                    .frame(minHeight: 44)
            }
            .buttonStyle(RowPress())
            .disabled(creating)
            DSFootnote("Your other device won't be able to send from it anymore.", centered: true)
        }
        .frame(maxWidth: .infinity)
    }

    /// Take the account onto this phone: a new key here, then the recovery
    /// key moves each network the account is on to it.
    private func recover(_ found: (address: String, origin: String)) {
        guard !creating else { return }
        creating = true
        Task {
            do {
                // This phone's own account, reinstalled: its keys already sign.
                guard let index = try YourAccountKey.adopt(address: found.address, origin: found.origin) else {
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
        creating = true
        do {
            let made = try YourAccountKey.create()
            // Followed in the Wallet from the start, so its balance and moves
            // land where every account's do.
            WalletStore.shared.add(made, label: String(localized: "Your account"))
            withAnimation(DS.Motion.standard) { address = made }
            DSHaptic.success()
        } catch {
            note = (String(localized: "Couldn't create the account on this device"), true)
        }
        creating = false
    }
}
