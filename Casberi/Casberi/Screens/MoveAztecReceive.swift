import SwiftUI

/// **RECEIVE TO YOUR PRIVATE BALANCE ON AZTEC (prd §1719).** Picked as
/// "Your private balance · Aztec" in Receive's "on" list, the sentence
///
///     Receive to your private balance on Aztec at …596a.
///
/// ("your private balance" goes back to the list; the tail copies), then
/// your Aztec address in eight groups, as public Receive groups yours (a tap
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

    private var address: String? { AztecAccountStore.shared.shown.address }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                MoveFlow {
                    head()
                    MoveWordsClause(glue: String(localized: "to"), words: String(localized: "your private account"),
                                    ink: DS.aztecInk, action: leave, hint: Text("Picks where it lands"))
                    MovePhrase("Aztec", glue: String(localized: "on"))
                    if let address {
                        MoveClause(glue: String(localized: "at")) {
                            Button { copy(address) } label: {
                                MoveWord(copied ? String(localized: "Copied") : AddressTail.short(address) + ".", ink: DS.textPrimary)
                            }
                            .buttonStyle(RowPress())
                            .accessibilityLabel(Text("Your Aztec address, \(address)"))
                            .accessibilityHint(Text("Copies the address"))
                        }
                    }
                }
                // The sentence is no control (prd §1781): the address under
                // it and the foot copy, and the foot's back leaves.
                .allowsHitTesting(false)
                if let address {
                    // Over the address, where it is seen before the copy.
                    Text("Aztec to Aztec only.")
                        .dsText(.heading17)
                        .foregroundStyle(DS.aztecInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DS.Space.s2)
                    Button { copy(address) } label: { Self.grid(address) }
                        .buttonStyle(RowPress())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, DS.Space.s4)
                        .accessibilityLabel(Text(verbatim: address))
                        .accessibilityHint(Text("Copies the address"))
                    DSDoorRow(icon: "plus", label: "Add money from Ethereum") {
                        DSHaptic.selection()
                        addMoney()
                    }
                    .aztecDoor()
                    .padding(.top, DS.Space.s4)
                }
            }
            .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
            .padding(.top, inTray ? DS.Space.s2 : DS.Space.s6)
            .padding(.bottom, DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { foot }
    }

    /// An Aztec address's 64 hex digits in eight groups of eight, two rows,
    /// the first and last group in the primary ink — the shape public
    /// Receive gives an Ethereum address (`AddressGroupsGrid`).
    static func groups(_ address: String) -> [String] {
        let hex = Array(address.lowercased().hasPrefix("0x") ? address.dropFirst(2) : Substring(address))
        guard hex.count == 64 else { return [] }
        return stride(from: 0, to: 64, by: 8).map { String(hex[$0..<$0 + 8]) }
    }

    @ViewBuilder static func grid(_ address: String) -> some View {
        let groups = groups(address)
        if groups.count == 8 {
            Grid(alignment: .leading, horizontalSpacing: DS.Space.s3, verticalSpacing: DS.Space.s1) {
                ForEach(0..<2, id: \.self) { row in
                    GridRow {
                        Text(verbatim: row == 0 ? "0x" : "").foregroundStyle(DS.textSecondary)
                        ForEach(0..<4, id: \.self) { col in
                            let n = row * 4 + col
                            Text(verbatim: groups[n]).foregroundStyle(n == 0 || n == 7 ? DS.textPrimary : DS.textSecondary)
                        }
                    }
                }
            }
            .dsText(.mono17)
            .minimumScaleFactor(0.7)
            .lineLimit(1)
        } else {
            Text(verbatim: address).dsText(.mono17).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func copy(_ address: String) {
        DSPasteboard.copy(address)
        DSHaptic.tap()
        withAnimation(DS.Motion.standard) { copied = true }
    }

    /// "Copy" grey, leading; "Share" pink, trailing.
    private var foot: some View {
        HStack(alignment: .center, spacing: DS.Space.s2) {
            MoveBackCard()
            if let address {
                Button { copy(address) } label: {
                    Text(copied ? "Copied" : "Copy for Aztec").dsText(.heading24).foregroundStyle(DS.textSecondary).frame(minHeight: 48)
                }
                .buttonStyle(RowPress())
                Spacer(minLength: DS.Space.s3)
                ShareLink(item: address) {
                    Text("Share")
                        .dsText(.heading34)
                        .foregroundStyle(DS.aztecInk)
                        .frame(minHeight: 48, alignment: .trailing)
                }
                .buttonStyle(RowPress())
            }
        }
        .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
        .padding(.bottom, DS.Space.s2)
        .background { if inTray { DS.surfaceSheet } else { DSPageBackground() } }
    }
}
