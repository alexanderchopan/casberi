import SwiftUI

/// **AN ORDER WAITING, IN NEEDS YOU (prd §1673 item 7).** One row per limit
/// order this phone placed that CoW has not filled: the amber clock, "1 ETH
/// for USDC at $2,400", "Since 2:14 PM · until Nov 9 · Cancel". It leaves
/// when CoW fills it, it expires, or it is cancelled; Cancel is
/// `invalidateOrder`, one Face ID, after a dialog that says nothing moves.
struct WalletOrderAsks: View {
    @Environment(ShellChrome.self) private var chrome
    @State private var confirming: YourAccountOrders.Placed?
    @State private var cancelling: String?
    /// Bumped when CoW's word changed a row, so the list draws again.
    @State private var read = 0

    var body: some View {
        let orders = YourAccountOrders.open
        if !orders.isEmpty {
            Section {
                ForEach(orders) { order in row(order) }
            }
            .id(read)
            .task(id: orders.map(\.uid)) {
                // CoW is asked again while a row stands (spaced 30 s).
                while !YourAccountOrders.open.isEmpty, !Task.isCancelled {
                    let before = YourAccountOrders.open.map(\.uid)
                    await YourAccountChain.refreshOrders()
                    if YourAccountOrders.open.map(\.uid) != before {
                        read += 1
                        chrome.refreshRooms()
                    }
                    try? await Task.sleep(for: .seconds(30))
                }
            }
            .confirmationDialog(confirming.map { Text("Cancel \(YourAccountOrders.title($0))?") } ?? Text(verbatim: ""),
                                isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                                titleVisibility: .visible, presenting: confirming) { order in
                Button(String(localized: "Cancel order"), role: .destructive) { cancel(order) }
                Button(String(localized: "Keep it"), role: .cancel) {}
            } message: { _ in
                Text("Nothing has been swapped. CoW stops filling it once the cancel lands.")
            }
        }
    }

    private func row(_ order: YourAccountOrders.Placed) -> some View {
        let working = cancelling == order.uid
        let until = order.expires.formatted(.dateTime.month(.abbreviated).day())
        let line = Text(verbatim: PrivateMoney.since(order.placedAt, now: .now) + " · " + String(localized: "until \(until)") + " · ")
            + Text("Cancel").foregroundStyle(DS.pickInk)
        return DSPushRow(title: Text(verbatim: YourAccountOrders.title(order)),
                         subtitle: working ? Text("Cancelling…") : line,
                         subtitleTone: DS.textSecondary, busy: working, opens: false) {
            guard !working else { return }
            confirming = order
        } leading: {
            ZStack {
                Color.clear.frame(width: DS.Face.row, height: DS.Face.row)
                Image(systemName: "clock")
                    .dsGlyph(.body, weight: .semibold)
                    .foregroundStyle(DS.attention)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityHint(Text("Cancels the order"))
        .walletListRow()
    }

    private func cancel(_ order: YourAccountOrders.Placed) {
        cancelling = order.uid
        Task {
            defer { cancelling = nil }
            do {
                let sent = try await YourAccountChain.cancelOrder(order, reason: String(localized: "Cancel your order: \(YourAccountOrders.title(order))")) { _ in }
                if case .landed = sent.outcome {
                    DSHaptic.success()
                    chrome.flash(String(localized: "Order cancelled"), tone: .success)
                } else {
                    chrome.flash(String(localized: "Cancel sent, not yet seen"))
                }
                read += 1
                chrome.refreshRooms()
            } catch let failure as YourAccountChain.Failure {
                DSHaptic.failure()
                chrome.flash(failure.message)
            } catch {
                chrome.flash(String(localized: "Not cancelled"))
            }
        }
    }
}
