import SwiftUI
import SwiftData

/// A company from the index that you don't watch yet (prd §1082): what it
/// is, the apps it makes, its line where one can be drawn, and Watch. A
/// company you watch opens its own page instead, with its alerts.
struct CompanySheet: View {
    let company: CompanyPacks.Company
    @Environment(\.modelContext) private var modelContext
    @Environment(ShellChrome.self) private var chrome: ShellChrome?
    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var watched = false
    @State private var failure: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                HStack(spacing: DS.Space.s3) {
                    BridgeIcon(name: company.seats.first ?? company.name, size: DS.Face.rowCircle)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: company.name).dsText(.heading20).foregroundStyle(DS.textPrimary)
                        if let ticker = company.listing.ticker {
                            Text(verbatim: "$\(ticker)").dsText(.subhead12).foregroundStyle(DS.textTertiary)
                        }
                    }
                }
                chart
                Text("Makes \(company.seats.joined(separator: ", "))")
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
                watchButton
                if let failure {
                    DSFootnote(Text(verbatim: failure))
                }
            }
            .padding(DS.Space.s4)
        }
        .dsReadSheet()
        .onAppear { watched = MarketsWatch.watchedThing(company, context: modelContext) != nil }
    }

    @ViewBuilder private var chart: some View {
        switch company.listing {
        case .stock(let ticker):
            TokenChartView(memoryKey: "stock.range.\(ticker)",
                           fetch: { (range: StockRange) in
                               DemoMode.isActive ? nil : await StockChart.fetch(ticker: ticker, range: range)
                           },
                           hero: true, object: (name: company.name, symbol: ticker)) {
                EmptyView()
            }
        case .token, .unlisted:
            if let quote = CompanyQuotes.shared.quote(company.listing) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(TokenChartStyle.priceText(quote.price))
                        .dsText(.price40).monospacedDigit().foregroundStyle(DS.textPrimary)
                    if let change = quote.change {
                        Text("\(TokenChartStyle.changeText(change)) today")
                            .dsText(.body17)
                            .foregroundStyle(change >= 0 ? DS.confirmInk : DS.destructiveInk)
                    }
                }
            }
        }
    }

    @ViewBuilder private var watchButton: some View {
        if company.listing == .unlisted {
            EmptyView()
        } else if watched {
            DSStamp(word: String(localized: "Following"), weight: .good, glyph: "star.fill")
                .frame(maxWidth: .infinity, minHeight: DSSlab.height)
        } else {
            DSSlabButton(title: String(localized: "Follow \(company.name)"), systemImage: "star") {
                guard !working else { return }
                working = true
                Task {
                    let result = await MarketsWatch.watch(company, context: modelContext)
                    working = false
                    switch result {
                    case .success:
                        watched = true
                        DSHaptic.success()
                        chrome?.flash(String(localized: "Following \(company.name)"))
                    case .failure(let why):
                        failure = why.message
                        DSHaptic.failure()
                    }
                }
            }
        }
    }
}
