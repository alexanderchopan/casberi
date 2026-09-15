import SwiftUI

/// The All feed's day name and its one clause (prd §767).
///
/// "Today" at 24pt with "mostly Work" stacked under it was the tallest object
/// between two runs of rows, and the loudest type on the feed. A room's divider
/// already set its clause (the count) on the name's baseline; this is that
/// shape, falling back to the stack only when the clause is too long to share
/// the line.
///
/// The name wears the brand ink (prd §740, §742: the day is the app's own
/// voice). The tail cools one weight step (prd §254): size and weight are the
/// only hierarchy this app has, and a size step down would land on the row
/// titles beneath it.
struct FeedDayDivider<Clause: View>: View {
    let label: String
    var weight: Font.Weight = .bold
    @ViewBuilder var clause: Clause

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                name
                clause
            }
            VStack(alignment: .leading, spacing: 1) {
                name
                clause
            }
        }
    }

    private var name: some View {
        Text(label)
            .dsText(.heading24)
            .fontWeight(weight)
            .foregroundStyle(DS.brandInk)
    }
}
