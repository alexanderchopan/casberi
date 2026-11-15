import SwiftUI

/// **AN EMPTY HOME LEADS WITH YOUR ACCOUNT (prd §1809, amending §1364's
/// "Start with any address").** Nobody is shown the demo any more, so this
/// is the first screen every new person sees, and it led with following
/// someone else's wallet. Casberi is a wallet: the lead is yours. With no
/// account, making one; with one and nothing in it, putting money in. Either
/// is one row into Move, where both are done. Watching an address is still
/// here, second, in the one field that watches (§466).
///
/// No sentence under the statement: the row says the act and the field says
/// what it takes. The dotted line is the balance's, waiting.
struct WalletStartFigure: View {
    @Environment(ShellChrome.self) private var chrome
    /// Your account exists and holds nothing yet.
    var made = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(made ? "Your account is ready" : "Make your account")
                .dsText(.heading24)
                .foregroundStyle(DS.textPrimary)
            DSDoorRow(icon: made ? "plus" : WalletSection.yourAccount.glyph,
                      title: Text(made ? "Add money" : "Create account")) {
                DSHaptic.selection()
                chrome.moveTray = true
            }
            WalletWatchField(onWatched: {}, showsPeekChip: true, showsConnect: false,
                             onConnectFound: { _ in })
                .padding(.top, DS.Space.s2)
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
