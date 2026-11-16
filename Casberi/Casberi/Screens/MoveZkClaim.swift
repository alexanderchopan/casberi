import SwiftUI
import UIKit

/// **CLAIM A ZK.MONEY LINK FROM RECEIVE (prd §1824).** Someone sends you a
/// zk.money "Pay anyone" link; it arrives in Messages, not in Casberi, so
/// Receive takes it: "From a zk.money link ›" under the public account opens
///
///     Claim a zk.money link to your public account on Ethereum.
///
/// with the link a grey blank and Paste the act: the page asks for the link,
/// so nobody has to know to copy it first (user: "how in 2 do you know they
/// need to copy it?"). Pasted, the act is Claim: your public address is
/// copied and zk.money's own claim page opens with it named above, ready to
/// paste where the page asks for an Ethereum address. The link pays out on
/// Ethereum only, so the sentence says where before anything happens.
///
/// Why not claim it here: every move of zk.money's dollar needs zk.money's
/// own enclave to sign (measured 2026-11-16, `zkmoney-measured`), so a
/// native claim would be a zk.money client inside Casberi. The link is a
/// bearer secret: it lives in this view's memory only, is never logged,
/// kept or synced, and goes nowhere but zk.money's page.
struct MoveZkClaim<Head: View>: View {
    let account: String
    var inTray = false
    var leave: () -> Void = {}
    @ViewBuilder let head: () -> Head

    @State private var link: URL?
    @State private var refused = false
    @State private var claiming = false
    @State private var demoNote = false
    @Environment(ShellChrome.self) private var chrome

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                head()
                    .allowsHitTesting(false)
                MoveChoiceRows(rows: rows, open: .constant(nil)) { _ in EmptyView() }
                    .padding(.top, DS.Space.s4)
                if demoNote {
                    Text(verbatim: YourAccountDemo.actsLater)
                        .dsText(.body17).foregroundStyle(DS.attentionInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DS.Space.s3)
                }
            }
            .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
            .padding(.top, inTray ? DS.Space.s2 : DS.Space.s6)
            .padding(.bottom, DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { foot }
        .onAppear {
            chrome.moveTall = true
            #if DEBUG
            if let sample = UserDefaults.standard.string(forKey: "zkClaimSample"), sample.hasPrefix("http") { take(sample) }
            #endif
        }
        .sheet(isPresented: $claiming) {
            if let link {
                AztecBrowserView(url: link, aztec: false, above: AnyView(ZkClaimAddressBand(account: account)))
            }
        }
    }

    private var rows: [MoveChoiceRow] {
        [
            MoveChoiceRow(id: "from", name: String(localized: "From"),
                          value: link != nil ? String(localized: "zk.money link")
                              : refused ? String(localized: "Not a zk.money link")
                              : String(localized: "Paste a zk.money link"),
                          // Its own words, never Move's "Choose": the row asks for a link.
                          ink: link != nil ? nil : refused ? DS.attentionInk : DS.pickInk) { paste() },
            MoveChoiceRow(id: "to", name: String(localized: "To"), value: String(localized: "Your public account"),
                          fixed: true) {},
            MoveChoiceRow(id: "network", name: String(localized: "Network"), value: "Ethereum",
                          mark: MoveSentence.networkMark(chainId: 1).map { MoveRowMark(network: $0) }, fixed: true) {},
        ]
    }

    private func paste() {
        take(UIPasteboard.general.string ?? "")
    }

    private func take(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard case .payment? = ZkMoneyLink.link(text), let url = URL(string: text) else {
            DSHaptic.failure()
            withAnimation(DS.Motion.standard) { refused = true; link = nil }
            NSLog("[Casberi] zkClaim| refused")
            return
        }
        DSHaptic.snap()
        withAnimation(DS.Motion.standard) { refused = false; link = url }
        NSLog("[Casberi] zkClaim| pasted")
    }

    private func claim() {
        guard link != nil else { return }
        if DemoMode.isActive || YourAccountDemo.isDemo(account) {
            withAnimation(DS.Motion.standard) { demoNote = true }
            return
        }
        DSPasteboard.copy(account)
        DSHaptic.tap()
        claiming = true
        NSLog("[Casberi] zkClaim| page opened")
    }

    /// The sentence over the button, then Back and the one act: Paste until
    /// a link is in, then Claim.
    private var foot: some View {
        VStack(spacing: 0) {
            MoveFlow {
                MoveWord(String(localized: "Claim"), ink: DS.textPrimary)
                MovePhrase(String(localized: "a zk.money link"), ink: link != nil ? DS.textPrimary : DS.textTertiary)
                MovePhrase(String(localized: "your public account"), glue: String(localized: "to"), ink: DS.textPrimary)
                MovePhrase("Ethereum.", glue: String(localized: "on"))
            }
            // The sentence is no control (prd §1781).
            .allowsHitTesting(false)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, DS.Space.s3)
            HStack(alignment: .center, spacing: DS.Space.s2) {
                MoveBackCard(act: leave)
                if link == nil {
                    Button { paste() } label: { MoveSentence.actCard(String(localized: "Paste"), on: true) }
                        .buttonStyle(PressSpring())
                } else {
                    Button { claim() } label: { MoveSentence.actCard(String(localized: "Claim"), on: true) }
                        .buttonStyle(PressSpring())
                }
            }
        }
        .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
        .padding(.bottom, DS.Space.s2)
        .background { if inTray { DS.surfaceSheet } else { DSPageBackground() } }
    }
}

/// Above zk.money's claim page (prd §1824): the address it should pay, said
/// copied, with Copy again for a clipboard the page's own field overwrote.
struct ZkClaimAddressBand: View {
    let account: String
    @State private var copiedAgain = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your public account").dsText(.body17).foregroundStyle(DS.textSecondary)
                Spacer(minLength: DS.Space.s2)
                Text("Copied").dsText(.heading17).foregroundStyle(DS.confirmInk)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: AddressTail.short(account)).dsText(.heading24).foregroundStyle(DS.textPrimary)
                Spacer(minLength: DS.Space.s2)
                Button {
                    DSPasteboard.copy(account)
                    DSHaptic.tap()
                    copiedAgain = true
                } label: {
                    (copiedAgain ? Text("Copied") : Text("Copy")).dsText(.heading17).foregroundStyle(DS.pickInk)
                }
                .buttonStyle(RowPress())
            }
        }
        .padding(.horizontal, DSRoomChassis.leadInset)
        .padding(.vertical, DS.Space.s3)
    }
}
