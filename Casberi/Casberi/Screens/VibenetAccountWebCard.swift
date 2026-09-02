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

    /// HOLD AN ACCOUNT TO SEE WHAT IT REACHES (prd §501) — the node under the
    /// finger, or nil at rest.
    ///
    /// **The web answers "who can do what" all at once**, which was §482's own
    /// complaint about this relationship (*"with two accounts its hard to tell
    /// who can do what"*) and is the reason this drawing replaced the spine.
    /// Holding one node answers it for that one account: everything it does
    /// not touch drops back, for exactly as long as you hold.
    ///
    /// **`@GestureState`, so it cannot latch on.** It resets itself when the
    /// finger lifts, when the press is cancelled by a scroll, and when the
    /// view is torn down mid-press — the three cases a hand-rolled `@State`
    /// flag gets wrong, and the same reason `HoldToPeek` is built this way.
    ///
    /// §295's same-weight ruling survives intact: this is a transient answer
    /// to a gesture, never a standing claim that one relationship matters more
    /// than another. Nothing is written and nothing is remembered.
    @GestureState private var held: String?

    /// How far a node the held one does not touch falls back. Far enough to
    /// read as "not this", near enough to stay legible — a dimmed row is still
    /// part of the drawing, not removed from it.
    private static let dimmed: Double = 0.18

    /// The most air allowed between two nodes once the web is filling its
    /// box — see the `Spacer`s in `body`.
    private static let maxSpread: CGFloat = 34

    private var drawn: [VibenetAccountWeb.Node] {
        Array(web.nodes.prefix(VibenetAccountWeb.nodesShown))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: DS.Space.s3) {
                // The owner, once, on the left — the account every node here
                // hangs off. Drawn at `shelf` rather than `row` so the
                // asymmetry states which side is the subject without a label
                // saying so.
                // **THE OWNER'S NAME WAS THE SMALLEST TEXT ON THE CARD
                // (prd §566).** It sat at `label11`/tertiary under a 56pt face
                // while every sub-account hanging off it was drawn at
                // `subhead13`/primary — so the subject of the figure was
                // quieter than its dependents, which is the inversion §563 and
                // §564 both fix elsewhere. It takes `price16`, the rung the
                // roster rows next door use for the same job.
                //
                // The face ASYMMETRY is deliberate and stays: shelf against
                // rowCircle is what states which side is the subject without a
                // label saying so, and the mockup that proposed one size for
                // both did not know that ruling was here.
                VStack(spacing: DS.Space.s1) {
                    WalletFace(address: web.owner, size: DS.Face.shelf, circular: true)
                    Text(name(web.owner))
                        .dsText(.price16)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: DS.Face.shelf + DS.Space.s3)
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
        // Every node hangs off the ONE owner, so the set a held node touches
        // is itself and the owner — there are no node-to-node links in this
        // web to follow. Stated rather than computed, because computing it
        // would imply a graph this drawing does not have.
        let dim = held != nil && held != node.id
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
                // **"Watching" is what the SOLID face already says** — the
                // unwatched node is drawn as a dashed outline right beside it,
                // so the word restated the drawing for the majority case and
                // pushed two tiers of text under every row (prd §566). The
                // unwatched line stays: it is not a restatement, it is the act.
                if node.watched {
                    EmptyView()
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
        Group {
            if !node.watched, let onWatch {
                Button {
                    DSHaptic.selection()
                    onWatch(node.address)
                } label: { body.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .dsHover()
                    // The combined element above carries the speech; a label
                    // here would be written and never read.
                    .accessibilityHidden(true)
            } else {
                body
            }
        }
        .opacity(dim ? Self.dimmed : 1)
        // The dim itself is NOT dropped under Reduce Motion — it is the
        // ANSWER to the gesture, not a flourish on top of one. Only its fade
        // is, which is the line that preference actually draws
        // (`ChartEntrance`: render the final frame immediately, never a slower
        // version of the move).
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: dim)
        // A hit area first: a `Text` and a face have holes between them, and a
        // press that lands in one of those does nothing, which reads as the
        // hold being unreliable rather than as a miss.
        .contentShape(Rectangle())
        .gesture(
            LongPressGesture(minimumDuration: 0.18, maximumDistance: 12)
                .updating($held) { _, state, _ in state = node.id }
        )
    }
}
