import SwiftUI

/// WHAT AN x402 SELLER ACTUALLY SELLS (2026-08-06) — the thing sheet's content
/// for a Circle x402 row.
///
/// The sheet used to be a title and a link. Everything below was already
/// fetched, on the device, and drawn nowhere: the endpoint list with its own
/// per-call prices, the chains a call settles on, the seller's docs. A row can
/// only say "12 services · $0.01–$0.03 a call"; "what ARE they" is the question
/// somebody opens the sheet to answer.
///
/// **It shipped as dead code first, and that is worth recording.** The earlier
/// pass put the exception in `ThingContent`'s `default:` branch — but these
/// rows are `.link`, which has its own branch, so the condition could never be
/// reached. The build was green, the harness guard (`grep` for the source name
/// in that file) passed, and the feature did nothing. The guard proved the
/// words were present, not that they were on the path. This view replaces that
/// with a branch on the route the rows actually take.
///
/// ## Liveness
///
/// Stores a `Thing`, so it guards its OWN body (corollary 5, build 188).
/// Everything else it draws is value types out of `X402State`.
struct X402SellerContent: View {
    let thing: Thing

    var body: some View {
        if thing.isLive { liveBody }
    }

    private var seller: X402State.Seller? { X402State.seller(forRef: thing.sourceRef) }

    /// The page preview is NOT drawn here — `ThingContent` draws it just above,
    /// with the face `X402Faces` stamped, using its own private
    /// `LinkPreviewCard`. Keeping that split means this file owns exactly one
    /// idea (what the seller sells) and no private component has to be widened
    /// to reach it.
    @ViewBuilder private var liveBody: some View {
        if let seller {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                catalog(seller)
                settlement(seller)
                docs(seller)
            }
            .padding(.bottom, DS.Space.s3)
        }
    }

    // MARK: - What they sell

    @ViewBuilder private func catalog(_ seller: X402State.Seller) -> some View {
        if !seller.detail.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(String(localized: "What they sell"))
                    .dsText(.label12).fontWeight(.semibold)
                    .foregroundStyle(DS.textTertiary)
                ForEach(seller.detail) { service in
                    row(service)
                }
                // §307: the cap is NAMED, never silent. Orthogonal lists 310
                // endpoints and a sheet is not a directory — but a card showing
                // twelve of them with no note reads as a company that sells
                // twelve things.
                if seller.services > seller.detail.count {
                    Text(String(localized: "Showing \(seller.detail.count) of \(seller.services)"))
                        .dsText(.label11).foregroundStyle(DS.textTertiary)
                }
            }
            .padding(.horizontal, DS.Space.s4)
        }
    }

    private func row(_ service: X402State.Service) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            // GET or POST — it says whether a call is a lookup or a job you
            // hand work to, which is the difference between browsing and
            // buying.
            Text(service.method)
                .dsText(.label11).fontWeight(.semibold)
                .foregroundStyle(DS.textTertiary)
                .frame(width: 34, alignment: .leading)
            Text(service.what)
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Quirk 4 at endpoint scale: a free operation says "Free" rather
            // than rendering as a price of zero.
            if let price = service.price {
                Text(X402Ingest.usd(price))
                    .dsText(.label12).monospacedDigit()
                    .foregroundStyle(DS.brandHue(for: X402Ingest.source) ?? DS.textSecondary)
            } else if service.free {
                Text(String(localized: "Free"))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
            }
        }
    }

    // MARK: - Where it settles

    @ViewBuilder private func settlement(_ seller: X402State.Seller) -> some View {
        if let line = X402Networks.line(seller.networks, unknown: seller.unknownNetworks) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Settles on"))
                    .dsText(.label12).fontWeight(.semibold)
                    .foregroundStyle(DS.textTertiary)
                Text(line)
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, DS.Space.s4)
        }
    }

    /// A second door, and only when the directory named one — gated so it can
    /// never be a control that goes nowhere.
    @ViewBuilder private func docs(_ seller: X402State.Seller) -> some View {
        if let docs = seller.docsURL, let url = URL(string: docs) {
            Link(destination: url) {
                HStack(spacing: DS.Space.s1) {
                    Image(systemName: "book").font(.system(size: 12, weight: .semibold))
                    Text(String(localized: "Read their docs")).dsText(.callout15)
                }
                .foregroundStyle(DS.tint)
            }
            .padding(.horizontal, DS.Space.s4)
        }
    }
}
