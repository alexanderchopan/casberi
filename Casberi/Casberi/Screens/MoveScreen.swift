import SwiftUI
import UIKit

/// The Move tab ships in DEBUG builds only until your account can send and
/// recover (prd §1422): before then a release build would hand out an
/// address money could reach and nothing could move.
enum MoveTab {
    static var enabled: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

/// **MOVE (prd §1422): your account's page** — the Apple pass of the
/// 2026-10-18 canvas (docs/safe-wallet-spec.md, section 2a). Centred head: your
/// account's face, its name, its address. Then the modules, bare on the page
/// (§1382, §1393), a 32pt seam between them (§1386).
///
/// **Built so far: create and receive.** Send · Swap and Security are not
/// drawn until they work (§83: no dead controls). No balance: the Wallet,
/// where the account is followed from the moment it exists, shows it.
struct MoveScreen: View {
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.openURL) private var openURL
    @State private var address: String? = YourAccountKey.address
    @State private var creating = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                head
                if let address {
                    receive(address)
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
        .dsPageBackground()
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
                Text(verbatim: YourAccount.short(address))
                    .dsText(.mono17)
                    .foregroundStyle(DS.textSecondary)
                    .accessibilityLabel(Text("Address \(address)"))
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

    // MARK: Add · Receive

    private func receive(_ address: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add · Receive")
                .dsText(.heading20)
                .foregroundStyle(DS.headInk)
                .frame(minHeight: 44, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Menu {
                Button { addFrom("https://www.coinbase.com", address) } label: { Text(verbatim: "Coinbase") }
                Button { addFrom("https://www.kraken.com", address) } label: { Text(verbatim: "Kraken") }
                Button("Another wallet") { copy(address) }
            } label: {
                row(title: "Add", line: "From an exchange or another wallet")
            }
            .buttonStyle(RowPress())
            HStack(spacing: DS.Space.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Receive").dsText(.body17).foregroundStyle(DS.textPrimary)
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
