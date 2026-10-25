import SwiftUI

/// **THE MONTHLY RECOVERY CHECK, ON SCREEN (prd §1509 item 4, §1515,
/// canvas figures 12 and 13).** A row in the Wallet's Needs you when it is
/// due, and the Recovery key page it opens: the check runs there, behind the
/// device owner's Face ID, and says in one sentence whether the key works
/// and where, one row per network, and the fix for a network without it.
@MainActor @Observable
final class RecoveryCheckState {
    static let shared = RecoveryCheckState()
    /// Due for a check: read off the Keychain and the last good check by
    /// `refresh()`, never in a body.
    private(set) var due = false
    /// The last check this launch, for the page.
    var last: YourAccountRecoveryCheck.Result?
    var running = false

    /// After each foreground sweep, and when the Wallet opens.
    func refresh() {
        if YourAccountDemo.isOn { due = YourAccountDemo.recoveryCheckDue && last == nil; return }
        #if DEBUG
        if let forced = UserDefaults.standard.string(forKey: "recoveryCheck"), forced == "due" || forced == "fail" {
            due = last == nil; return
        }
        #endif
        guard let account = YourAccountKey.address else { due = false; return }
        due = YourAccountRecovery.checkDue(account)
    }

    /// Run the check; the demo's comes off its table, never Face ID or a node.
    func run(_ account: String) async {
        guard !running else { return }
        running = true
        defer { running = false }
        #if DEBUG
        if UserDefaults.standard.string(forKey: "recoveryCheck") == "fail" {
            last = YourAccountDemo.recoveryResult(failing: true)
            due = false
            NSLog("recoveryCheck| fail (preview): %@", YourAccountRecoveryCheck.sentence(last!).text)
            return
        }
        #endif
        if YourAccountDemo.isDemo(account) {
            try? await Task.sleep(for: .milliseconds(400))
            last = YourAccountDemo.recoveryResult(failing: false)
        } else {
            guard let result = await YourAccountRecovery.check(account, reason: String(localized: "Check your recovery key")) else { return }
            last = result
        }
        if last?.works == true { due = false }
        #if DEBUG
        if let last {
            NSLog("recoveryCheck| %@ | %@", YourAccountRecoveryCheck.sentence(last).text,
                  last.networks.map { "\($0.name)=\($0.standing.words)" }.joined(separator: ", "))
        }
        #endif
    }
}

/// The row in Needs you: one line, no badge, no notification (§1490).
struct RecoveryCheckNudge: View {
    @Environment(ShellChrome.self) private var chrome

    static var shown: Bool { RecoveryCheckState.shared.due }

    var body: some View {
        Button {
            DSHaptic.selection()
            chrome.walletSection = .recoveryKey
        } label: {
            DSFeedRow(name: String(localized: "Check your recovery key"),
                      line: Text("A month since it was last checked. No fee, nothing sent.")) {
                if let address = YourAccountDemo.shownAddress {
                    WalletFace(address: address, size: DS.Face.seat, circular: true)
                }
            } trailing: {
                EmptyView()
            } below: {
                EmptyView()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .accessibilityHint(Text("Opens the recovery key's check"))
    }

    var listRow: some View { self.walletListRow() }
}

/// The page's box: the sentence, "works" in green or the failure in red.
struct RecoveryCheckFigure: View {
    let state = RecoveryCheckState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if let last = state.last {
                let said = YourAccountRecoveryCheck.sentence(last)
                Text(verbatim: said.text)
                    .dsText(.heading24)
                    .foregroundStyle(said.works ? DS.confirmInk : DS.destructiveInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: String(localized: "In iCloud Keychain. Checked \(last.at.formatted(.relative(presentation: .named))) with Face ID."))
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(state.running ? "Checking your recovery key" : "Check your recovery key")
                    .dsText(.heading24).foregroundStyle(DS.textPrimary)
                Text("Face ID unlocks it, it signs a test message on this device, and each network says whether it still accepts it. No fee, nothing sent.")
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The page's list: a row per network, the fix door, then Check or Done.
struct RecoveryCheckRows: View {
    let state = RecoveryCheckState.shared
    @Environment(ShellChrome.self) private var chrome

    var body: some View {
        Section {
            if let last = state.last {
                ForEach(last.networks, id: \.chainId) { net in
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: net.name).dsText(.body17).foregroundStyle(DS.textPrimary)
                        Spacer(minLength: DS.Space.s2)
                        Text(verbatim: net.standing.words).dsText(.body17)
                            .foregroundStyle(net.standing == .notOwner ? DS.destructiveInk : DS.textSecondary)
                    }
                    .walletRowPitch()
                    .walletListRow()
                }
                // The existing fix: Security's recovery row puts the key on.
                ForEach(YourAccountRecoveryCheck.fixable(last), id: \.chainId) { net in
                    DSDoorRow(icon: "key.horizontal", title: Text("Put it on \(net.name)")) {
                        chrome.openYourAccount(at: FeedScreen.SecurityAnchor.account.id)
                    }
                    .walletListRow()
                }
                DSDoorRow(icon: "checkmark", title: Text("Done")) {
                    chrome.walletSection = .yourAccount
                }
                .walletListRow()
            } else if let account = YourAccountDemo.shownAddress {
                DSDoorRow(icon: "faceid", title: Text(state.running ? "Checking…" : "Check with Face ID")) {
                    Task { await state.run(account) }
                }
                .disabled(state.running)
                .walletListRow()
            }
        }
        .task {
            #if DEBUG
            // `-recoveryCheck run|fail`: the check, run as the page opens.
            if let mode = UserDefaults.standard.string(forKey: "recoveryCheck"), mode == "run" || mode == "fail",
               state.last == nil, let account = YourAccountDemo.shownAddress {
                await state.run(account)
            }
            #endif
        }
    }
}
