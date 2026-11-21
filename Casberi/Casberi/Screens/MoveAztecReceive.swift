import SwiftUI

/// **RECEIVE TO YOUR PRIVATE BALANCE ON AZTEC (prd §1719).** Picked as
/// "Your private balance · Aztec" in Receive's "on" list, the sentence
///
///     Receive to your private balance on Aztec at …596a.
///
/// ("your private balance" goes back to the list; the tail copies), then
/// your Aztec address in groups of four on the deck (a tap copies the
/// whole, no QR), and the foot: Share and Copy address (prd §1928). It is your account's one address, the same
/// every time; anyone on Aztec pays it privately.
///
/// **AZTEC TO AZTEC ONLY, SAID (prd §1779; user: "they may see their aztec
/// address and send to it", "whenever there is an aztec in view it should
/// be totally clear only aztec to aztec").** An Aztec address is not an
/// Ethereum one: a wallet or an exchange on Ethereum refuses it, and nothing
/// here said why. One line over the address says it, in Aztec's own ink,
/// the same words wherever the address stands. Money on Ethereum comes in
/// through Send's own sentence to your private account (prd §1928).
struct MoveAztecReceive<Head: View>: View {
    var inTray = false
    /// "your private balance" tapped: back to Receive's "on" list.
    var leave: () -> Void = {}
    @ViewBuilder let head: () -> Head

    @State private var copied = false
    @Environment(ShellChrome.self) private var chrome

    private var address: String? { AztecAccountStore.shared.shown.address }

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ScrollView {
            // **THE SENTENCE ON TOP, THE DECK UNDER IT (prd §1928, as Move's
            // other pages, §1927).** The sentence names the place; the plate
            // holds the address and its one rule.
            MoveFlow {
                MoveWord(String(localized: "Receive"), ink: DS.textPrimary)
                MovePhrase(String(localized: "your private account"), glue: String(localized: "to"), ink: DS.aztecInk)
                MovePhrase("Aztec.", glue: String(localized: "on"))
            }
            .allowsHitTesting(false)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MoveSentence.sideInset(inTray))
            .padding(.top, inTray ? DS.Space.s2 : DS.Space.s6)
            .padding(.bottom, DS.Space.s4)
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { deck }
        .onAppear { chrome.moveTall = true }
    }

    /// The address in groups of four and its rule in Aztec's ink (prd §1779,
    /// §1924); Share beside Copy address in the foot. Money on Ethereum comes
    /// in through Send (prd §1928: Add money left Receive).
    private var deck: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if let address {
                    Button { copy(address) } label: { AddressGroups(address: address) }
                        .buttonStyle(RowPress())
                        .accessibilityLabel(Text(verbatim: address))
                        .accessibilityHint(Text("Copies the address"))
                    // In view wherever the Aztec address is (prd §1779).
                    Text(verbatim: MoveSentence.aztecRule).dsText(.body17).foregroundStyle(DS.aztecInk)
                } else {
                    DSSpinner()
                }
            }
            .padding(.top, DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: MoveDeck.bodyHeight + MoveDeck.stepsHeight + MoveDeck.footHeight
                   + MoveFootClearance.bar(inTray: inTray, sizeClass: sizeClass, chrome: chrome)
                   + MoveFootClearance.gained(inTray: inTray), alignment: .top)
            MoveDeckFoot(back: leave) {
                if let address {
                    HStack(spacing: DS.Space.s3) {
                        if !DemoMode.isActive { MoveShareDisc(item: address) }
                        MoveFootWord(word: copied ? String(localized: "Copied") : String(localized: "Copy address"),
                                     ink: DS.aztecInk) { copy(address) }
                    }
                }
            }
        }
        .padding(.horizontal, MoveSentence.sideInset(inTray))
        .padding(.top, HomePanelMetrics.cap)
        .modifier(MoveFootClearance(inTray: inTray, intoBody: true))
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                Group { if inTray { DS.surfaceSheet } else { DSPageBackground() } }
                HomePanelSurface()
            }
            .padding(.horizontal, inTray ? -DS.Space.s4 : 0)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    /// Your Aztec address as every Receive draws one: one quiet line
    /// (`AddressLine`, prd §1884).
    static func grid(_ address: String) -> some View { AddressLine(address: address) }

    private func copy(_ address: String) {
        DSPasteboard.copy(address)
        DSHaptic.tap()
        withAnimation(DS.Motion.standard) { copied = true }
    }
}
