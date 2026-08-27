import SwiftUI

/// ACCOUNTS YOU CAN ACT FOR — the Accounts scope's drawing (prd §491).
///
/// Every judgement is `VibenetAccountWeb`'s; this is its shape. Bare on the
/// page like every other scope's lead (§483).
struct VibenetAccountWebCard: View {
    let web: VibenetAccountWeb.Web
    /// Name an address the way the roster above does — handed in rather than
    /// resolved here, so this figure can never name an account differently
    /// from the rail one row up.
    let name: (String) -> String
    /// Offer to watch an account you can act for but do not follow. nil
    /// leaves the row a plain read: §83's rule, and the reason the unwatched
    /// node is the only one that can carry a verb at all.
    var onWatch: ((String) -> Void)? = nil
    let reduceMotion: Bool

    /// The most air allowed between two nodes once the web is filling its
    /// box — see the `Spacer`s in `body`.
    private static let maxSpread: CGFloat = 34

    private var drawn: [VibenetAccountWeb.Node] {
        Array(web.nodes.prefix(VibenetAccountWeb.nodesShown))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(VibenetAccountWeb.headline(web))
                .dsText(.stat24)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                // CLEARS THE GEAR. The room's settings button is an overlay on
                // the trailing edge of this whole block, so a headline that
                // takes the full width runs under it — measured on the device,
                // where the headline was clipped
                // mid-word by a control sitting on top of it.
                .padding(.trailing, DS.Face.shelf + DS.Space.s3)
            HStack(alignment: .top, spacing: DS.Space.s3) {
                // The owner, once, on the left — the account every node here
                // hangs off. Drawn at `shelf` rather than `row` so the
                // asymmetry states which side is the subject without a label
                // saying so.
                VStack(spacing: DS.Space.s1) {
                    WalletFace(address: web.owner, size: DS.Face.shelf, circular: true)
                    Text(name(web.owner))
                        .dsText(.label11)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
                .padding(.top, DS.Space.s2)
                // **THE ROWS SPREAD TO FILL THE SLOT** (user, 2026-08-26:
                // *"on accounts too much space between the charts and the
                // account row"*). Same reasoning as the Activity band: the
                // slot's height is reserved whether or not the figure spends
                // it, so a two-node web drew ~80pt of picture and left ~120pt
                // of black above the account rail.
                //
                // `Spacer`s between the rows rather than a computed row
                // height, because unlike the flow band these rows have no
                // geometry of their own to stretch — nothing is positioned
                // against an index, so the layout can simply be told to use
                // the room. `maxSpread` is what stops two nodes drifting to
                // opposite ends of the box and reading as a drawing that lost
                // its middle.
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    ForEach(Array(drawn.enumerated()), id: \.element.id) { index, node in
                        if index > 0 { Spacer(minLength: 0).frame(maxHeight: Self.maxSpread) }
                        row(node)
                            .chartArrival(index: index, reduceMotion: reduceMotion)
                    }
                    if web.nodes.count > VibenetAccountWeb.nodesShown {
                        Spacer(minLength: 0).frame(maxHeight: Self.maxSpread)
                        Text(String(localized: "and \(web.nodes.count - VibenetAccountWeb.nodesShown) more"))
                            .dsText(.label12).foregroundStyle(DS.textTertiary)
                    }
                    // Anything the rows and their spreads did not take sits
                    // BELOW them, so a single node stays at the top of the box
                    // beside the owner it hangs off rather than floating in
                    // the middle of it.
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                Spacer(minLength: 0)
            }
            .padding(.top, DS.Space.s3)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        // One spoken sentence (§299): a web of faces and dashes reads as
        // nothing, and the ORDER — unwatched first — is the claim.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(VibenetAccountWeb.spoken(web)))
    }

    /// One account you can act for.
    ///
    /// **The unwatched one is drawn as an outline and is the only row with a
    /// verb.** A watched sub-account is already on screen elsewhere in this
    /// room; an unwatched one is an account you control and may not know
    /// about, which is the whole reason this drawing beat the delegate spine.
    @ViewBuilder
    private func row(_ node: VibenetAccountWeb.Node) -> some View {
        let body = HStack(spacing: DS.Space.s2) {
            if node.watched {
                WalletFace(address: node.address, size: DS.Face.rowCircle, circular: true)
            } else {
                // NOT a face: a portrait would say this account is one of
                // yours on screen, which is exactly the question the row is
                // asking. An outline is the honest shape for "known to exist,
                // not being followed".
                Circle()
                    .strokeBorder(DS.fillStrong, style: StrokeStyle(lineWidth: 1.4, dash: [3, 3]))
                    .frame(width: DS.Face.rowCircle, height: DS.Face.rowCircle)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(name(node.address))
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                if node.watched {
                    Text(String(localized: "Watching"))
                        .dsText(.label11).foregroundStyle(DS.textTertiary)
                } else if onWatch != nil {
                    Text(String(localized: "Not watched · Watch it"))
                        .dsText(.label11).foregroundStyle(DS.tint)
                } else {
                    Text(String(localized: "Not watched"))
                        .dsText(.label11).foregroundStyle(DS.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        if !node.watched, let onWatch {
            Button {
                DSHaptic.selection()
                onWatch(node.address)
            } label: { body.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .dsHover()
                // The combined element above carries the speech; a label here
                // would be written and never read.
                .accessibilityHidden(true)
        } else {
            body
        }
    }
}
