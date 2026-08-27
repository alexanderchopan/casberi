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
                // where "2 accounts · 1 you don't watch yet" was clipped
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
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    ForEach(Array(drawn.enumerated()), id: \.element.id) { index, node in
                        row(node)
                            .chartArrival(index: index, reduceMotion: reduceMotion)
                    }
                    if web.nodes.count > VibenetAccountWeb.nodesShown {
                        Text(String(localized: "and \(web.nodes.count - VibenetAccountWeb.nodesShown) more"))
                            .dsText(.label12).foregroundStyle(DS.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, DS.Space.s3)
        }
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
