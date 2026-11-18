import SwiftUI

/// **RECEIVE TO YOUR PRIVATE BALANCE ON AZTEC (prd §1719).** Picked as
/// "Your private balance · Aztec" in Receive's "on" list, the sentence
///
///     Receive to your private balance on Aztec at …596a.
///
/// ("your private balance" goes back to the list; the tail copies), then
/// your Aztec address in one quiet line, as every Receive draws one (a tap
/// copies the whole, no QR), and the foot: "Copy" grey at the leading edge,
/// "Share" pink at the trailing. It is your account's one address, the same
/// every time; anyone on Aztec pays it privately.
///
/// **AZTEC TO AZTEC ONLY, SAID (prd §1779; user: "they may see their aztec
/// address and send to it", "whenever there is an aztec in view it should
/// be totally clear only aztec to aztec").** An Aztec address is not an
/// Ethereum one: a wallet or an exchange on Ethereum refuses it, and nothing
/// here said why. One line over the address says it, in Aztec's own ink,
/// the same words wherever the address stands; one row under it is the way
/// in for money on Ethereum: Send's own sentence to your private account.
struct MoveAztecReceive<Head: View>: View {
    var inTray = false
    /// "your private balance" tapped: back to Receive's "on" list.
    var leave: () -> Void = {}
    /// Money on Ethereum comes in through Send (prd §1779).
    var addMoney: () -> Void = {}
    @ViewBuilder let head: () -> Head

    @State private var copied = false
    @Environment(ShellChrome.self) private var chrome

    private var address: String? { AztecAccountStore.shared.shown.address }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                // **MOVE'S LAYOUT (prd §1803, as §1794, §1801):** the verb is
                // the title, the rows and the address under it, the sentence
                // over the button.
                head()
                    .allowsHitTesting(false)
                // In view wherever the Aztec address is (prd §1779).
                Text("Aztec to Aztec only.")
                    .dsText(.heading17)
                    .foregroundStyle(DS.aztecInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s2)
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    // Its one network, said as a row and fixed (prd §1802).
                    MoveChoiceRows(rows: [MoveChoiceRow(id: "network", name: String(localized: "Network"),
                                                        value: String(localized: "Aztec"),
                                                        mark: MoveRowMark(network: "brand-aztec"), fixed: true) {}],
                                   open: .constant(nil)) { _ in EmptyView() }
                    if let address {
                        VStack(alignment: .leading, spacing: DS.Space.s2) {
                            Text("Aztec address").dsText(.body17).foregroundStyle(DS.textSecondary)
                            Button { copy(address) } label: { Self.grid(address) }
                                .buttonStyle(RowPress())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityLabel(Text(verbatim: address))
                                .accessibilityHint(Text("Copies the address"))
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            ShareLink(item: address) {
                                MoveVerbRowLabel(title: String(localized: "Share"), glyph: "square.and.arrow.up")
                            }
                            .buttonStyle(RowPress())
                            // The way in for money on Ethereum (prd §1779).
                            Button {
                                DSHaptic.selection()
                                addMoney()
                            } label: { MoveVerbRowLabel(title: String(localized: "Add money from Ethereum"), glyph: "plus") }
                                .buttonStyle(RowPress())
                        }
                    }
                }
                .padding(.top, DS.Space.s4)
            }
            .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
            .padding(.top, inTray ? DS.Space.s2 : DS.Space.s6)
            .padding(.bottom, DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { foot }
        // The rows, the address and the sentence need the tall sheet.
        .onAppear { chrome.moveTall = true }
    }

    /// Your Aztec address as every Receive draws one: one quiet line
    /// (`AddressLine`, prd §1884).
    static func grid(_ address: String) -> some View { AddressLine(address: address) }

    private func copy(_ address: String) {
        DSPasteboard.copy(address)
        DSHaptic.tap()
        withAnimation(DS.Motion.standard) { copied = true }
    }

    /// The sentence over the button (prd §1794, §1803), then Back and the
    /// one act in Aztec's own ink; "Share" is a row above.
    private var foot: some View {
        VStack(spacing: 0) {
            MoveFlow {
                MoveWord(String(localized: "Receive"), ink: DS.textPrimary)
                MovePhrase(String(localized: "your private account"), glue: String(localized: "to"), ink: DS.aztecInk)
                MovePhrase("Aztec", glue: String(localized: "on"))
                if let address {
                    MovePhrase(AddressTail.short(address) + ".", glue: String(localized: "at"), ink: DS.textPrimary)
                }
            }
            // The sentence is no control (prd §1781).
            .allowsHitTesting(false)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, DS.Space.s3)
            HStack(alignment: .center, spacing: DS.Space.s2) {
                // Back to where it was picked, never Move's menu (prd §1803).
                MoveBackCard(act: leave)
                if let address {
                    Button { copy(address) } label: {
                        MoveSentence.actCard(copied ? String(localized: "Copied") : String(localized: "Copy address"), on: true,
                                             fill: DS.aztecInk, ink: .black)
                    }
                    .buttonStyle(PressSpring())
                } else {
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
        .padding(.bottom, DS.Space.s2)
        .background { if inTray { DS.surfaceSheet } else { DSPageBackground() } }
    }
}
