import SwiftUI
import UIKit

/// **MOVE (prd §1422): your account's page** — the Apple pass of the
/// 2026-10-18 canvas (docs/safe-wallet-spec.md, section 2a). Centred head: your
/// account's face, its name, its address. Then the modules, bare on the page
/// (§1382, §1393), a 32pt seam between them (§1386).
///
/// **Move is the acts alone (prd §1436)**: Send · Swap (`MoveSend`, §1424,
/// §1430) and Receive, each under the Wallet's own section head
/// (`SectionPanelName`: a pink glyph, `heading28`), so a scan reads two
/// places and never one form. Security's rows went to the Wallet's Security
/// tile (`MoveSecurity`, §1427). No balance: the Wallet shows it.
struct MoveScreen: View {
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.openURL) private var openURL
    @State private var address: String? = YourAccountKey.address
    @State private var creating = false
    /// An account whose recovery key this phone's iCloud Keychain holds,
    /// when this phone has none of its own yet (prd §1427).
    @State private var recoverable: (address: String, origin: String)?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                head
                if let address {
                    MoveSend(account: address)
                        .padding(.top, DSRoomChassis.sectionGap)
                    receive(address)
                        .padding(.top, DSRoomChassis.sectionGap)
                } else if let recoverable {
                    recoverRow(recoverable)
                        .padding(.top, DSRoomChassis.sectionGap)
                } else {
                    createRow
                        .padding(.top, DSRoomChassis.sectionGap)
                }
            }
            .padding(.horizontal, DSRoomChassis.leadInset)
            .padding(.top, DS.Space.s6)
            .padding(.bottom, DS.Space.s8 * 3)
        }
        .scrollContentBackground(.hidden)
        // The address fields wrap (§1428), so a drag is how a keyboard goes.
        .scrollDismissesKeyboard(.interactively)
        .dsPageBackground()
        .task {
            if address == nil { recoverable = YourAccountRecovery.accounts().first } else { YourAccountKey.ensureRecord() }
        }
    }

    // MARK: The head

    /// Centred, as every sheet's head is since prd §1397: the face, the name,
    /// the address in grey; before the account exists, the move mark.
    private var head: some View {
        VStack(spacing: DS.Space.s2) {
            Group {
                if let address {
                    WalletFace(address: address, size: DS.Face.sheet, circular: true)
                } else {
                    Image(systemName: ScopeTileGlyph.move)
                        .dsGlyph(.title, weight: .semibold)
                        .foregroundStyle(DS.brandInk)
                        .frame(width: DS.Face.sheet, height: DS.Face.sheet)
                }
            }
            .accessibilityHidden(true)
            Text("Your account")
                .dsText(.heading24)
                .foregroundStyle(DS.headInk)
            if let address {
                // The whole address, always (user, 2026-10-19: "show entire
                // address here so user can always see and copy it"): one
                // line of mono, and a tap copies it.
                Button { copy(address) } label: {
                    Text(verbatim: address)
                        .dsText(.mono12)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .buttonStyle(RowPress())
                .accessibilityLabel(Text("Address \(address)"))
                .accessibilityHint(Text("Copies your address"))
                Text("Secured by Safe")
                    .dsText(.subhead12)
                    .foregroundStyle(DS.textTertiary)
            }
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
                    chrome.flash(ThisDevice.ready, tone: .success)
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
                    chrome.flash(ThisDevice.ready, tone: .success)
                } else {
                    chrome.flash(failed.joined(separator: " · "), tone: .failure, seconds: 6)
                }
            } catch {
                chrome.flash(String(localized: "Couldn't make a key on this device"), tone: .failure)
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
            chrome.flash(String(localized: "Couldn't create the account on this device"), tone: .failure)
        }
        creating = false
    }

    // MARK: Receive

    /// Money coming in (prd §1425): from an exchange, or to your address.
    /// Send's Add is the page's one Add — it batches.
    private func receive(_ address: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionPanelName(name: String(localized: "Receive"), glyph: ScopeTileGlyph.receive, inset: 0) { EmptyView() }
                .frame(minHeight: 44, alignment: .leading)
            Menu {
                Button { addFrom("https://www.coinbase.com", address) } label: { Text(verbatim: "Coinbase") }
                Button { addFrom("https://www.kraken.com", address) } label: { Text(verbatim: "Kraken") }
                Button("Another wallet") { copy(address) }
            } label: {
                row(title: "From an exchange", line: "Coinbase, Kraken or another wallet")
            }
            .buttonStyle(RowPress())
            HStack(spacing: DS.Space.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your address").dsText(.body17).foregroundStyle(DS.textPrimary)
                    Text(verbatim: YourAccount.short(address) + " · Base · Ethereum")
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textSecondary)
                }
                Spacer(minLength: DS.Space.s2)
                Button("Copy") { copy(address) }
                    .dsText(.body17)
                    .foregroundStyle(DS.pickInk)
                    .buttonStyle(RowPress())
                    .frame(minHeight: 44)
            }
            .frame(minHeight: 60)
        }
    }

    private func row(title: LocalizedStringKey, line: LocalizedStringKey) -> some View {
        HStack(spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).dsText(.body17).foregroundStyle(DS.textPrimary)
                Text(line).dsText(.subhead12).foregroundStyle(DS.textSecondary)
            }
            Spacer(minLength: DS.Space.s2)
            Image(systemName: "chevron.right")
                .dsGlyph(.caption, weight: .semibold)
                .foregroundStyle(DS.textTertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 60)
        .contentShape(Rectangle())
    }

    private func copy(_ address: String) {
        UIPasteboard.general.string = address
        DSHaptic.tap()
        chrome.flash(String(localized: "Address copied"))
    }

    /// The address on the clipboard, then the exchange: paste it as the
    /// destination of a withdrawal there, on Base or Ethereum.
    private func addFrom(_ site: String, _ address: String) {
        copy(address)
        if let url = URL(string: site) { openURL(url) }
    }
}
