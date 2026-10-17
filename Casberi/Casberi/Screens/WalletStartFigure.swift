import SwiftUI

/// **A WALLET WITH NO ACCOUNT IS WHERE THE FIRST ONE STARTS (prd §1364, user:
/// "we need to give user a way to add wallet or something so they don't
/// fail", of B: "perfect!").** Home's box holds the follow field itself:
/// the statement, one sentence, `WalletWatchField` (the ONE way to watch,
/// §466) with its peek, and the line the balance will draw, dotted in the
/// brand hue. Connecting a wallet app stays on the Wallet's account page.
/// "Start with any address", never "Watch a wallet", under the title Wallet.
struct WalletStartFigure: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text("Start with any address")
                .dsText(.heading24)
                .foregroundStyle(DS.textPrimary)
            Text("Holdings and activity will appear here.")
                .dsText(.body17)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            WalletWatchField(onWatched: {}, showsPeekChip: true, showsConnect: false,
                             onConnectFound: { _ in })
                .padding(.top, DS.Space.s3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(alignment: .bottom) {
            StartLine()
                .stroke(DS.brandInk.opacity(0.35),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [1, 7]))
                .frame(height: 100)
                .accessibilityHidden(true)
        }
    }
}

/// The skeleton's curve (`DSSkeleton.Figure.line`), flattened into the box's
/// foot so the field above stands clear of it.
private struct StartLine: Shape {
    func path(in r: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: r.minX + x / 300 * r.width, y: r.minY + y / 100 * r.height)
        }
        var path = Path()
        path.move(to: p(0, 78))
        path.addCurve(to: p(95, 64), control1: p(40, 72), control2: p(60, 58))
        path.addCurve(to: p(185, 46), control1: p(130, 70), control2: p(150, 40))
        path.addCurve(to: p(300, 22), control1: p(220, 52), control2: p(245, 18))
        return path
    }
}
