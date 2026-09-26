import SwiftUI

/// **THE DEVNETS' PERMISSIONS CROWN IS THE WALLET'S (prd §951): who holds a
/// permission, mark by mark.** One number over one noun — Frames' share of gas
/// sponsored, UTXO's nonce keys, Privacy's spend keys used, Vibenet's keys —
/// and under it one mark per holder with its name, a red ring only on a
/// holder with no limit (`WalletPermissionsCard`, §944). §936's bars are
/// deleted here as they were in the Wallet: one bar per class read as the
/// same length on every devnet, a chart that said nothing. The marks are a
/// picture, not a control; the rows below are the doors.
struct RoomPermissionsFigure: View {
    struct Holder: Identifiable {
        let id: String
        /// The word under the mark.
        let name: String
        let mark: WalletRowMark
        /// No limit — the one thing the crown's red says.
        var unbounded = false
    }

    let number: String
    let caption: String
    let holders: [Holder]

    static let shown = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSFigureReading(number: number, caption: caption)
            Spacer(minLength: DS.Space.s3)
            HStack(alignment: .top, spacing: 0) {
                ForEach(holders.prefix(Self.shown)) { holder in
                    mark(holder).frame(maxWidth: .infinity)
                }
                // Fewer than five stand where five would: a lone sponsor is
                // not stretched across the width.
                ForEach(0..<max(0, Self.shown - holders.count), id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private func mark(_ holder: Holder) -> some View {
        VStack(spacing: DS.Space.s1) {
            WalletMarkView(mark: holder.mark, size: 48)
                .overlay {
                    if holder.unbounded {
                        Circle()
                            .strokeBorder(DS.destructive, lineWidth: 2)
                            .padding(-4)
                    }
                }
                .padding(4)
            Text(holder.name)
                .dsText(.label12)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(holder.name))
    }
}

/// **TWO KINDS OF ROW, SAID TO BE TWO** (user, 2026-09-02, on Frames' sponsor
/// list: *"sponsors list also is messy"*). A person and a grant have different
/// anatomies, and stacked under one caption at one spacing they read as a
/// single list that keeps changing shape. Each block names its kind; `s6`
/// between blocks is the gap the app already uses for "these are different
/// things".
struct RoomListBlock<Content: View>: View {
    let caption: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            // The group header (prd §951): the Wallet's `DSGroupHeader` words,
            // stepped back to the tiles' edge from the rows' column like
            // `DSDayHeader`.
            Text(caption)
                .dsText(.heading24)
                .foregroundStyle(DS.textPrimary)
                .padding(.leading, DSRoomChassis.inset - DSRoomChassis.rowInset(forMark: DS.Face.list))
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}
