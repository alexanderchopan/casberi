import SwiftUI

/// Every source at once (2026-07-31, user) — the long-press half of the agent
/// bar's two gestures: tap raises the agent, hold opens your places.
///
/// It exists because the strip can only ever show FOUR. Measured on a 402pt
/// phone: the two fixed doors plus the leading fade eat 135pt before the first
/// chip, and each chip is a 68pt pitch — four and a peek, out of a corpus that
/// routinely runs past twenty. Everything past the fourth cost a horizontal
/// scroll through icons with no names on them.
///
/// The two shapes considered and rejected first, so they aren't re-proposed:
/// a VERTICAL rail on the phone shows ~8 instead of 4 but costs 88pt of
/// permanent width (22% of the screen, against 8% of an iPad's — which is why
/// `SourceChips.verticalRail` is right THERE and wrong here), and it points the
/// wrong way besides: the feed is a `TabView(.page)` over these very labels, so
/// the strip is the map of a HORIZONTAL swipe. Stacked full-width rows are the
/// retired Home board wearing new clothes — a screen between you and the
/// content. This costs zero permanent chrome and shows all of them, not eight.
///
/// It carries the one thing the strip gave up: NAMES. Labels were dropped from
/// the chips on 2026-07-09 because they made the row scroll — true of a row,
/// free in a grid, so the icon-only strip finally has somewhere to send anyone
/// who doesn't recognise a mark.
///
/// # The tray is a PANEL OF GLASS, and the marks float on it (2026-08-16, user)
///
/// **Superseded 2026-08-28 (user: "make it ink or black … get rid of the
/// glass") — the panel `SourcesOverlay` hosts this content in is opaque
/// `DS.surfaceSheet` ink now, not glass; see that file's `glass` property.**
/// Everything below about NOT stacking a second container/tint/carve on the
/// panel still holds — a filled slab was refused for reading as SEEN rather
/// than READ, independent of what sits under it — so the layout is unchanged
/// even though the material argument that first shipped it (an opaque slab
/// being the one thing glass "cannot do") no longer applies to this surface.
///
/// The grid has been grouped by `BridgeCatalog.categories` since 2026-08-06.
/// From 2026-08-10 to 2026-08-16 each category was a filled opaque card, which
/// was the right answer to "it still looks like just a bunch of icons" — a
/// filled container is SEEN rather than read — on an OPAQUE sheet. The sheet is
/// glass now (`DSTray(glass:)`), and on glass an opaque slab is the one thing
/// the material cannot do; see the "Where the card used to be" note below for
/// what it cost, measured. Seven treatments were compared as rendered pixels in
/// `prototype/sources-tray-glass-v1.html` — the marks floating directly on the
/// panel won.
///
/// **The grouping is carried by the eyebrow's INK — and, since later the same
/// day, by its SIZE.** With no container the eyebrow is the only thing doing
/// that job, so it first moved `textTertiary` → `textPrimary` at the same size
/// (`prototype/sources-tray-eyebrow-v1.html`), with 12pt refused on the theory
/// that ink AND size makes the grid read as eight lists. The user looked at
/// the shipped tray and overturned that: `subhead13` bold now (2026-08-16,
/// "make the eyebrows bold and larger") — on the more transparent panel the
/// 11pt ink alone was not holding the groups, and a heading that has to carry
/// structure by itself is allowed to look like a heading. The one consequence
/// kept from the first ruling: the eyebrow still sits well under the 22pt
/// title, so the tray reads as one surface with sections, not eight lists.
///
/// **It is still NOT tinted** (ruled 2026-08-11, re-asked and re-ruled
/// 2026-08-16). One of the original two reasons expired with the card — tinting
/// lost to the card, and there is no card — but the load-bearing one did not:
/// `DS.tint` means SELECTION in this tray (the active chip's ring), so eight
/// blue category names put selection's colour on eight unselected things. It
/// would also add a ninth hue to a tray that is already twenty saturated brand
/// marks. Colour is identity, state, or magnitude (brief §8); a heading is none
/// of the three.
///
/// **A group is still placed WHOLE, and rows alone are packed.** The card is
/// gone but its layout rule outlives it, for the reason that was never about the
/// fill: a group running past column five arrives on the next row as chips with
/// no name above them, and you have to look up and diagonally back to learn what
/// they are. There is no continuation, therefore no nameless run, therefore
/// nothing to explain.
///
/// # The grouping is CARVED, and the columns never move (2026-08-16, user)
///
/// Two reports, one evening, and the second overturned the first cut of the
/// fix for the first. Read them together, because the second is the ruling.
///
/// **The complaint:** "it kinda still looks funky and like rows aren't even".
/// The diagnosis taken first was that the grid was five EQUAL slots, so the
/// gap between two groups sharing a row was byte-identical to the gap between
/// two chips inside one — proximity saying "one row of five icons" while the
/// eyebrows said "two groups", and a gap is SEEN where a word is READ. That
/// half is true and still stands.
///
/// **The fix that shipped in build 343 was wrong anyway.** It bought the
/// boundary with WHITESPACE: chips at a fixed pitch, packed from the left, so
/// a wide gap could open between groups. The only way whitespace can widen
/// that gap is by MOVING the chips — and the column a chip lands in then
/// depends on how many chips preceded it IN ITS OWN ROW. On the reporter's
/// own tray, rows 1 and 3 were `2|2|1` and agreed, while row 2 was `4|1` and
/// put its third and fourth chips **53px left of the ones directly above and
/// below them**. Five circles per row, one row off-grid: "basically the same
/// as it has been, except more janky for the groups".
///
/// **So the ruling: ALIGNMENT OUTRANKS THE BOUNDARY, and "rows aren't even"
/// meant it literally.** A grid whose columns agree reads as deliberate even
/// when its boundaries are subtle; a grid whose columns disagree reads as
/// broken however well its groups are separated. The gap ratio 343 bought was
/// real (~34pt between groups against 8pt inside) and it was not worth this.
///
/// The five equal columns are back — `columnWidth` is computed once per row
/// from the SAME width every row is handed, so a chip sits on the same
/// vertical in every row of the tray — and the boundary is drawn by something
/// that moves nothing: a **carve**, a translucent recess behind each group
/// (`DS.glassCarve`). This was §391's own documented runner-up, passed over
/// that morning in favour of whitespace. It is NOT the opaque card §391
/// deleted — translucent, so the blur underneath survives and the panel still
/// reads as one sheet — and it is BLACK rather than a white lift, for
/// `glassDepth`'s reason: white would bound the groups by spending the very
/// backdrop colour the same session was trying to buy back.
///
/// Compared as rendered pixels against the reporter's real tray in
/// `prototype/sources-tray-align-v1.html`, which draws column guides so the
/// misalignment is a measurement rather than an impression.
///
/// # The packing order: CATALOG WHEN IT'S FREE, biggest first when it pays
///
/// The bin packing itself lives in `SourceRowPacking` (see its doc for the
/// 39,237-corpus measurement). Until 2026-08-16 the order was pure biggest
/// first — optimal on height, but its cost was order churn in the one tray
/// whose job is teaching positions: connecting a single source could reorder
/// every group between opens. The same measurement bounds that cost: catalog
/// order TIES the optimum on ~92% of corpora, so both orders are packed and
/// catalog wins every tie. Most corpora keep the stable catalog order the
/// tray taught before the sort existed; the sort now runs only when it
/// genuinely saves a row. The strip's frozen order still survives inside
/// every group, exactly as `ShellChrome.chipOrder` hands it over.
///
/// **Alphabetising was considered and refused** (2026-08-06, still standing).
/// It would hold the height, but this tray is the STRIP's map — its whole job
/// is teaching the positions of an icon-only row that has no labels, and an
/// alphabetical tray teaches positions the strip does not have.
///
/// **"All" has no cell** (user, 2026-08-06), and the cost that ruling stated
/// is PAID since 2026-08-18 — see `SourcesOverlay.allChip`. It still belongs
/// to no category, so it is still never a cell in this grid: a grouped grid
/// could only hold it as an ungrouped orphan taking a whole row. It is a word
/// capsule in the panel's HEADER instead, which costs the grid nothing and
/// costs the packer nothing.
struct SourcesTray: View {
    /// The strip's own ordered labels — "All" first, then sources.
    let labels: [String]
    let active: String
    let onPick: (String) -> Void

    /// Closes the overlay. A closure rather than `@Environment(\.dismiss)`
    /// because this is no longer presented — `dismiss` in an overlay resolves
    /// to whatever sheet or stack happens to enclose the shell, which is
    /// either nothing or the wrong thing.
    let onDismiss: () -> Void

    /// The catalog door, for the EMPTY tray only (2026-08-18).
    ///
    /// A closure for the same reason `onPick` is one: the route is per-window
    /// state on `SceneState`, and this view is a ZStack layer that must not
    /// know which window it is in. `RootShell` closes the panel and pushes
    /// `.apps` — the same door the strip's own catalogue button opens, so
    /// there is one catalog and one way to reach it.
    let onOpenCatalog: () -> Void

    @Environment(BridgeStore.self) private var bridges

    /// Mirrors `SourceRowPacking.columns` — the view needs it to wrap an
    /// oversized group's chips, and a drift guard in
    /// `source-packing-selftest.sh` ties the two.
    fileprivate static let columns = SourceRowPacking.columns
    /// The chip's icon; the slot around it leaves room for the ring, exactly
    /// as `SourceChips` does at its own scale.
    private static let iconSize: CGFloat = 44
    private static let chipSize: CGFloat = 52
    /// One column of the tray's grid, from the width the row is handed.
    ///
    /// The SAME arithmetic on every row is what keeps every chip in the tray
    /// on a shared vertical — the property build 343 gave up and was reported
    /// for the same evening. A block spans `span` of these plus the gaps
    /// between them, so a group's width is always a whole number of columns
    /// and never a pitch of its own.
    fileprivate static func columnWidth(_ width: CGFloat) -> CGFloat {
        (width - CGFloat(columns - 1) * DS.Space.s2) / CGFloat(columns)
    }

    /// How wide a block is: its own columns, plus the gaps it swallows.
    fileprivate static func blockWidth(span: Int, column: CGFloat) -> CGFloat {
        CGFloat(span) * column + CGFloat(max(0, span - 1)) * DS.Space.s2
    }
    /// Two lines of `label12` plus its own leading — the same fixed name box
    /// `AppsScreen.appTile` uses, so a one-word and a two-word name sit on the
    /// same baseline instead of the row jittering per cell.
    private static let nameHeight: CGFloat = 28
    /// The label's own margin inside its column (2026-08-16, user: "we need to
    /// put privacy pools on two rows so it doesn't touch the edge of the
    /// container").
    ///
    /// It does two jobs with one number, and the second is the reason it is
    /// not simply padding on the carve. A chip's ICON is 52pt centred in a
    /// ~68pt column, so it can never reach the edge; its NAME is given the
    /// whole column, so a wide one runs flush into the carve at a group's
    /// first or last chip. Padding the carve instead would move the chips off
    /// the shared column grid — the §392a defect, reintroduced.
    ///
    /// Narrowing the text box also decides WRAP vs SHRINK: with the full
    /// column available, `minimumScaleFactor` could squeeze "Privacy Pools"
    /// onto one line rather than breaking it, which is what put it against
    /// the edge in the first place. Below the column width it no longer fits
    /// at any allowed scale, so it takes its second line — which is what the
    /// two-line box was reserved for all along.
    private static let nameGutter: CGFloat = 4
    /// One line of `subhead13` (its own `lineHeight`), and the gap under it.
    ///
    /// 15 → 21 on 2026-08-16 (user: "make the eyebrows bold and larger") —
    /// the eyebrow stepped `label11` semibold → `subhead13` bold. This
    /// OVERTURNS the same-day ruling below that refused a size bump: that
    /// ruling weighed ink-plus-size against the grid reading as eight lists,
    /// and the user looked at the shipped tray and ruled the other way — with
    /// no card and a more transparent panel, the ink alone was not holding.
    private static let overlineHeight: CGFloat = 21
    private static let overlineGap: CGFloat = 5
    /// Aligns the category name's first character with the left edge of the
    /// chip ring beneath it — the chip is `chipSize` centred in a `slotWidth`
    /// slot, so this is half that difference (was 7 when the slot was a
    /// flexible fifth). Deliberately a constant rather than a measured inset:
    /// it is a nudge, not a layout.
    private static let overlineInset: CGFloat = 5
    /// A group's own top and bottom air — the card's padding, kept after the
    /// card (2026-08-16). Tuned against the resting cap, not chosen: every
    /// point here is a point closer to a scroll the packing exists to prevent
    /// (the running four-row total lives on `rowGap`'s doc). 10/8 was measured
    /// in `prototype/sources-tray-glass-v2.html` and refused — it spent cap
    /// budget on air inside the group, where `rowGap` buys separation between
    /// them, which is the axis that was actually short.
    private static let cardPadTop: CGFloat = 8
    private static let cardPadBottom: CGFloat = 6

    /// One packed row: whole blocks totalling at most `columns` slots.
    ///
    /// The packing itself lives in `SourceRowPacking` — Foundation-only, so
    /// `scripts/source-packing-selftest.sh` can compile it whole and check it
    /// against an exact optimiser. This wrapper adds only what a view needs: a
    /// stable identity for `ForEach`.
    fileprivate struct PackedRow: Identifiable {
        let id: Int
        let blocks: [SourceRowPacking.Block]
        var chipRows: Int { blocks.map(\.chipRows).max() ?? 1 }
    }

    /// Group the labels by catalog category, then pack whole categories into
    /// rows — biggest first, ties by catalog position.
    ///
    /// Pure and self-contained on purpose: the whole layout is decided here and
    /// the body just draws it, so the packing can be reasoned about (and one
    /// day tested against the DP that proved it optimal) without mounting a
    /// view.
    ///
    /// A source the catalog can't place keeps its cell rather than vanishing:
    /// unplaceable labels collect in a trailing "Other" block. A tray that
    /// silently dropped a source would be the worst possible failure here,
    /// since this is the one screen that claims to show every source.
    fileprivate var packed: [PackedRow] {
        // "All" is the strip's, not the grid's — see the type doc.
        let sources = labels.filter { $0 != "All" }

        var byCategory: [String: [String]] = [:]
        var unplaced: [String] = []
        for label in sources {
            if let category = BridgeCatalog.category(forSource: label) {
                byCategory[category, default: []].append(label)
            } else {
                unplaced.append(label)
            }
        }

        // Catalog order first, so the size sort has a stable tiebreak; inside a
        // category the strip's frozen order, which `sources` already carries.
        var catalog: [SourceRowPacking.Block] = BridgeCatalog.categories
            .compactMap { category in
                guard let members = byCategory[category.name], !members.isEmpty else { return nil }
                return SourceRowPacking.Block(name: category.name, members: members)
            }
        if !unplaced.isEmpty {
            catalog.append(SourceRowPacking.Block(name: "Other", members: unplaced))
        }

        return SourceRowPacking.pack(catalog)
            .enumerated()
            .map { PackedRow(id: $0.offset, blocks: $0.element) }
    }

    /// A row's height, which varies: an oversized category wraps to two chip
    /// rows.
    fileprivate static func rowHeight(chipRows: Int) -> CGFloat {
        let unit = chipSize + DS.Space.s1 + nameHeight
        return cardPadTop + overlineHeight + overlineGap
            + CGFloat(chipRows) * unit
            + CGFloat(max(0, chipRows - 1)) * DS.Space.s2
            + cardPadBottom
    }

    /// Between rows. Tighter than the 2026-08-06 bare grid's `s4` because each
    /// group carries its own padding (`cardPadTop`/`Bottom`).
    ///
    /// **s2 → s3 on 2026-08-16** (user: "perhaps we can space the icons
    /// better"), and the interesting part is that the grid was never uniformly
    /// tight — it was tight in ONE axis. Measured on a 402pt phone: the content
    /// is 366pt over five flexible slots, so a 44pt mark sits in a ~65pt slot
    /// and the clear gap between two marks is **~31pt**. Vertically the same
    /// grid paid 8 + 6 of group padding and 10 between rows, i.e. 24pt from a
    /// name row to the next eyebrow — noticeably less than the air across, on a
    /// layout whose whole job is to read as groups.
    ///
    /// s3 is the ceiling here, not a first guess: the next variant
    /// (`prototype/sources-tray-glass-v2.html`, rail 2) also raised the group
    /// pads to 10/8 and looked marginally better, and it puts a four-row tray at
    /// **626pt against a 620 `restingCap`** — so it buys a little air by
    /// snapping a whole category off the resting height, which is the opposite
    /// of the trade. Loosening the chip's own icon→name gap was refused for a
    /// different reason: it detaches a name from its mark and reads as a caption
    /// rather than a label, while costing height in every chip row.
    ///
    /// Budget, since every point here is spent against that cap: four rows went
    /// **598 → 610pt** with this change, then **634** when the eyebrow stepped
    /// to `subhead13` the same day — which is what moved `restingCap` to 660.
    /// The row count that fits at rest is unchanged throughout: four rows rest,
    /// five (772) scroll.
    private static let rowGap: CGFloat = DS.Space.s3

    /// Chrome this view still owns: the bottom pad, and nothing else.
    ///
    /// The grabber, the top clearance and the title all moved to
    /// `SourcesOverlay.headerHeight` when the header became the drag region.
    /// The two sum to exactly what this constant used to be plus the grabber,
    /// so no resting height moved.
    ///
    /// No lane is reserved for the agent bar, because the bar is HIDDEN while
    /// this panel is up — see `RootShell`'s floating cluster. A reserve was
    /// written and deleted within the hour: it cost 76pt of resting height
    /// (about a whole row) to protect chips from a control that no longer
    /// overlaps them.
    private static let chromeHeight: CGFloat = DS.Space.s6

    /// The empty tray's own height (2026-08-18) — a sentence, a gap, and the
    /// catalog door, plus the bottom pad every other height already carries.
    ///
    /// It has to be spelled, because the arithmetic above cannot reach it:
    /// `height(of:rows:)` sums PACKED ROWS, and an empty corpus has none, so
    /// the panel resolved to `chromeHeight` alone — 24pt. That was survivable
    /// while the branch drew one line of text (which simply overflowed a frame
    /// nobody could see the edge of) and is not survivable now that it draws a
    /// 48pt control: a door squeezed into 24pt is a door you cannot press,
    /// which is the dead control §83 bans, in the one state where the tray has
    /// nothing else to offer.
    ///
    /// Summed from the pieces rather than measured, so it cannot drift when
    /// the type ramp moves: `subhead13`'s own line, `s4`, the button, the pad.
    private static let emptyLine: CGFloat = 21     // subhead13.lineHeight
    private static let emptyDoorHeight: CGFloat = 48
    private static let emptyHeight: CGFloat =
        emptyLine + DS.Space.s4 + emptyDoorHeight + chromeHeight
    /// 620 → 660 on 2026-08-16, alongside the eyebrow's step to `subhead13`:
    /// four rows went 610 → 634pt, and a cap of 620 would have answered the
    /// user's "make the eyebrows larger" by snapping a whole category off the
    /// resting height. 660 keeps the same semantics on real corpora — anything
    /// from four rows (634) up to five (772) still rests at four — and a
    /// 660pt sheet leaves over 200pt of feed above it on the smallest phone
    /// this app targets.
    private static let restingCap: CGFloat = 660

    /// Natural height, capped — the cap SNAPS DOWN to a whole number of rows.
    /// A raw `min(…, cap)` cuts wherever the arithmetic lands, and the worst
    /// cut is the likeliest one: through a group, between its name and the
    /// chips it names. Measured on a 25-source corpus the tray rested showing
    /// three category names with NOTHING underneath them — which reads as a
    /// rendering bug, not as "there is more below". Snapping means the last
    /// visible group is always whole and the next fully hidden; the grabber
    /// and the `.large` detent carry the "there's more" signal.
    ///
    /// Also what decides whether the active source rests visible — see
    /// `revealActive`.
    private func restingRows(_ rows: [PackedRow]) -> Int {
        guard Self.height(of: rows.count, rows: rows) > Self.restingCap else { return rows.count }
        var fit = 1
        while fit < rows.count, Self.height(of: fit + 1, rows: rows) <= Self.restingCap { fit += 1 }
        return fit
    }

    private static func height(of n: Int, rows: [PackedRow]) -> CGFloat {
        // No rows means an EMPTY CORPUS, not a zero-height panel — the branch
        // below draws a sentence and a door. See `emptyHeight`.
        guard n > 0 else { return emptyHeight }
        let body = rows.prefix(n).reduce(CGFloat.zero) { $0 + rowHeight(chipRows: $1.chipRows) }
        return body + CGFloat(n - 1) * rowGap + chromeHeight
    }

    /// Past the cap the grid scrolls and `.large` is draggable — a 40-source
    /// corpus must not clip silently (the "Worth a look" tray's 2026-07-24
    /// lesson).
    private var trayHeight: CGFloat {
        let rows = packed
        return Self.height(of: restingRows(rows), rows: rows)
    }

    /// The panel's RESTING height, read by `SourcesOverlay` — which owns the
    /// presentation now, so the height has to leave the view rather than be
    /// consumed by a `DSTray` inside it. Snapped down to a whole number of
    /// rows under `restingCap`.
    var panelHeight: CGFloat { trayHeight }

    /// Every row, uncapped — what the panel grows to when dragged up
    /// (2026-08-16, user: "will the tray drag up when there are more apps in
    /// it? … it scrolls within the panel instead of the panel moving"). The
    /// overlay clamps this to the screen, so a 40-source corpus still scrolls
    /// at full height rather than running off the top.
    var naturalPanelHeight: CGFloat {
        let rows = packed
        return Self.height(of: rows.count, rows: rows)
    }

    /// CONTENT ONLY since 2026-08-16 — no `DSTray`, no `.sheet`.
    ///
    /// The tray stopped being a sheet because a sheet is the one thing that
    /// cannot look like glass: it presents in its own context, and every
    /// measurement this session says `glassEffect` does not sample across
    /// that boundary (§393a). `SourcesOverlay` hosts this in the shell's own
    /// ZStack instead, beside the agent bar, where the material has the live
    /// feed behind it. See that file for what the move cost.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The title lives in `SourcesOverlay`'s HEADER now, not here — it
            // is part of the drag region (2026-08-16, user: "the grabber
            // doesn't work to pull it down"). A 24pt strip is not a handle you
            // can find with a thumb.
            ScrollViewReader { proxy in
                ScrollView {
                    let rows = packed
                    if rows.isEmpty {
                        // Reachable on a brand-new install: the hold gesture works
                        // before anything is connected, and with All in the header
                        // rather than the grid this would otherwise be a blank
                        // sheet with a title.
                        emptyState
                    } else {
                        VStack(alignment: .leading, spacing: Self.rowGap) {
                            ForEach(rows) { row in
                                rowView(row).id(row.id)
                            }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .onAppear { revealActive(proxy) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s6)
        // A tray was its own hosting environment and re-declared this; an
        // overlay is inside the shell's tree, so the shell's own copy fires.
    }

    /// The empty tray: the sentence, and a door (2026-08-18).
    ///
    /// **The sentence alone was a dead end.** Somebody who finds the hold
    /// gesture on a fresh install got told where things WILL land and given no
    /// way to make that happen — you dismiss the panel and go hunting for the
    /// catalogue button in the strip you just covered up. This is the one
    /// state where the tray has nothing to show and therefore nothing a verb
    /// could compete with, so the verb is free here in a way it is nowhere
    /// else in this panel.
    ///
    /// **ONE door, not a choice.** The onboarding fork's own §217 ruling — a
    /// fork you answer in a second beats a wall you have to survey — is why
    /// this does not offer three ways in. It is also why the door is the
    /// catalog rather than the fork: somebody holding the agent bar to open
    /// "your sources" has already decided they want a source, and the fork
    /// asks a question they have answered.
    ///
    /// **The only filled control this tray will ever draw**, and it exists
    /// only in the state where the grid is empty — the moment anything
    /// connects, this branch is gone and the tray is chips again. That is what
    /// keeps it from being the fourth container this tray has tried; a
    /// container behind groups was refused three times (§391, §392a, the card)
    /// and none of those arguments reach a control that is alone on the panel.
    /// `dsGlassProminent` is the app's own primary-action-on-glass treatment
    /// (the composer's Save), so it is a grammar this surface already speaks,
    /// not a new one.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            Text("Connect an app and it lands here.")
                .dsText(.subhead13)
                .foregroundStyle(DS.textSecondary)
            Button {
                DSHaptic.tap()
                onOpenCatalog()
            } label: {
                Text("Open the catalog")
                    .dsText(.body17)
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.Space.s6)
                    .frame(height: Self.emptyDoorHeight)
                    // Glass INSIDE the label, so the Button owns the whole hit
                    // region — interactive glass applied OUTSIDE a button eats
                    // taps for its own press deformation (2026-07-17, "takes
                    // several taps"). `HowItWorksSheet`'s pattern, verbatim.
                    .dsGlassProminent(tint: DS.tint, cornerRadius: DS.Radius.pill)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .dsHover()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The tray is the strip's map, and on a big corpus the snap-down cap can
    /// rest the one cell wearing the selection ring below the fold — you open
    /// "where am I?" and the answer is hidden with nothing saying so
    /// (2026-08-16). If the active source's row isn't among the resting rows,
    /// jump the scroll to it on mount. A JUMP, not an animation: the content
    /// simply appears already positioned, so there is no appear-triggered
    /// motion for Reduce Motion to honour.
    private func revealActive(_ proxy: ScrollViewProxy) {
        let rows = packed
        guard let index = rows.firstIndex(where: { row in
            row.blocks.contains { $0.members.contains(active) }
        }), index >= restingRows(rows) else { return }
        proxy.scrollTo(rows[index].id, anchor: .center)
    }

    /// One packed row. Blocks sit side by side on the tray's shared column
    /// grid, each exactly as wide as the columns it owns.
    ///
    /// The `GeometryReader` is a real layout measurement, unlike the one
    /// `overlineInset` refuses — a column width cannot be a constant when the
    /// tray is drawn on both a 375pt phone and an iPad. It is safe here
    /// because the row's height is already a computed constant, so the
    /// reader's fill-all-space behaviour is bounded on both axes.
    private func rowView(_ row: PackedRow) -> some View {
        GeometryReader { geo in
            let column = Self.columnWidth(geo.size.width)
            HStack(alignment: .top, spacing: DS.Space.s2) {
                ForEach(Array(row.blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block, column: column, chipRows: row.chipRows)
                }
                // A row that doesn't fill the grid leaves its remainder on the
                // right rather than stretching the blocks — stretching is what
                // would take a chip off its column.
                Spacer(minLength: 0)
            }
        }
        .frame(height: Self.rowHeight(chipRows: row.chipRows), alignment: .top)
    }

    /// One category: the carve, holding its name and its chips.
    ///
    /// Every block in a row is drawn the full row height so the recesses share
    /// a top and a bottom edge — a carve sized to its own content would step
    /// up and down across a row and reintroduce the raggedness this pass
    /// exists to remove. An oversized category wraps inside its own carve;
    /// it is packed alone in its row, so the wrap never collides with anyone.
    private func blockView(_ block: SourceRowPacking.Block,
                           column: CGFloat, chipRows: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            nameBand(block, column: column)
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ForEach(Array(stride(from: 0, to: block.members.count, by: Self.columns)),
                        id: \.self) { start in
                    HStack(spacing: DS.Space.s2) {
                        ForEach(block.members[start..<min(start + Self.columns, block.members.count)],
                                id: \.self) { label in
                            cell(label: label, category: block.name, column: column)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Self.cardPadTop)
        .padding(.bottom, Self.cardPadBottom)
        .frame(width: Self.blockWidth(span: block.span, column: column),
               height: Self.rowHeight(chipRows: chipRows),
               alignment: .topLeading)
        // NO CONTAINER. The carve that briefly lived here was deleted the
        // evening it shipped (2026-08-16, user: "i don't like those cards
        // behind the icons it makes it amateur") — the third container this
        // tray has tried and the third to lose. The boundary is the skipped
        // column in `rowView`, which is the only form that costs the panel
        // nothing: no fill to darken the glass, and no chip moved off the grid.
    }

    // MARK: - Where the card used to be

    /// Nothing. The category CARD was deleted on 2026-08-16 (user ruling) and
    /// this note is here so the deletion is a decision rather than a gap.
    ///
    /// From 2026-08-10 a category was a filled, raised, opaque card — the fix
    /// for "it still looks like just a bunch of icons", where a filled
    /// container is SEEN rather than read. That reasoning is intact and the
    /// card still lost, because the sheet under it changed: on a panel of glass
    /// an opaque slab is the one thing the material cannot do. It masked the
    /// blur over ~85% of the tray (so the glass survived only in the gutters,
    /// arriving as coloured stains from whatever row was behind), and worse,
    /// the sheet's local value now VARIES with the feed, so the same raised
    /// card read raised over a dark row and recessed over a bright one — a lift
    /// that is a property of somebody's feed is not a lift.
    ///
    /// The grouping is carried by the eyebrow's INK instead (see `nameBand`).
    /// Four treatments were compared as rendered pixels in
    /// `prototype/sources-tray-eyebrow-v1.html`; a carved recess in the glass
    /// (`t-carve` in `sources-tray-glass-v1.html`) was the runner-up and stays
    /// available if the ink alone stops holding at a larger corpus.

    // MARK: - Names and chips

    /// The category's name, sitting on its own cluster.
    ///
    /// Sized to the cluster's first chip row rather than left free: a name
    /// wider than its chips would widen the whole block and squeeze the group
    /// gap the layout exists to protect. The scale floor absorbs the loss —
    /// names never truncate (prd §201, the app-tile rule), and the longest
    /// catalog name over a single chip ("Shopping") lands around 0.93, which
    /// the eye doesn't register as a different size.
    private func nameBand(_ block: SourceRowPacking.Block, column: CGFloat) -> some View {
        Text(block.name)
            .dsText(.subhead13)
            .fontWeight(.bold)
            // textPrimary since 2026-08-16 — this ink and the cluster gap ARE
            // the grouping. See the type doc for why not tint.
            .foregroundStyle(DS.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.leading, Self.overlineInset)
            .frame(width: Self.blockWidth(span: block.span, column: column),
                   height: Self.overlineHeight,
                   alignment: .bottomLeading)
            .padding(.bottom, Self.overlineGap)
            // The name sits on the cluster it names; VoiceOver reads each
            // chip's own category on the cell instead, so this is decoration
            // to it.
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func cell(label: String, category: String, column: CGFloat) -> some View {
        let isActive = label == active
        // Same read as the strip's: one ring, two exclusive states. Solid tint
        // is selection; DASHED orange is "this connection needs you" (the
        // 2026-07-21 ruling — the two must not be the same ring in two hues).
        //
        // Resolved through the catalog rather than compared to the label
        // directly: a source name is not always its seat's name ("Privacy
        // Pools" against the "0xBow Privacy Pools" seat), and a bare `==` meant
        // that family could never show the ring at all. Falls back to the label
        // for a source the catalog has never heard of, which is what every
        // exactly-named seat already resolved to — so this changes nothing for
        // the seats that already worked.
        let seat = BridgeCatalog.offer(forSource: label)?.name ?? label
        let broken = bridges.bridges.contains {
            $0.name == seat && $0.status == .attention
        }
        Button {
            DSHaptic.selection()
            onPick(label)
            onDismiss()
        } label: {
            VStack(spacing: DS.Space.s1) {
                ZStack {
                    BridgeIcon(name: label, size: Self.iconSize, circular: true)
                }
                .frame(width: Self.iconSize, height: Self.iconSize)
                .padding(2.5)
                .overlay {
                    if isActive {
                        Circle().strokeBorder(DS.tint, lineWidth: 2.5)
                    } else if broken {
                        Circle().strokeBorder(DS.attention,
                                              style: StrokeStyle(lineWidth: 2.5, dash: [3, 3]))
                    }
                }
                .frame(width: Self.chipSize, height: Self.chipSize)

                Text(label)
                    .dsText(.label12)
                    .fontWeight(isActive ? .semibold : .medium)
                    .foregroundStyle(isActive ? DS.textPrimary : DS.textSecondary)
                    .multilineTextAlignment(.center)
                    // Names never truncate (prd §201) — the app-tile rule,
                    // which is the whole reason this grid can carry names the
                    // strip couldn't.
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .frame(height: Self.nameHeight, alignment: .top)
                    // Keeps the widest names off the carve's edge, and is what
                    // makes them wrap rather than shrink — see `nameGutter`.
                    .padding(.horizontal, Self.nameGutter)
            }
            // One column of the tray's shared grid — the same width in every
            // row, which is what puts every chip in the tray on a common
            // vertical. Never a flexible width: a block that stretched to fill
            // would take its chips off those columns, which is exactly what
            // build 343 was reported for.
            .frame(width: column)
            .contentShape(Rectangle())
            .dsHover()
        }
        .buttonStyle(PressSpring())
        // THE SAME PEEK THE STRIP'S CHIPS ANSWER WITH (2026-08-18, §384's
        // modifier, reused rather than rebuilt).
        //
        // This tray's own doc calls it "the strip's map", and a map whose
        // marks answer a gesture differently from the things they map is a
        // map you have to learn twice: press to wonder, release to stay, tap
        // through to commit was true of a chip and silently untrue of the
        // cell standing for that same room. It is also the surface where the
        // peek is worth MORE than it is on the strip — the strip shows four
        // marks you have probably learned, while this shows every room you
        // have, including the ones you opened once and cannot picture.
        //
        // `venues: []` is correct rather than lazy: the tray draws
        // `ShellChrome.sourceOrder`, which is the UNFOLDED list, so every
        // label here is a real seat and `CategoryFold.isCategory` is false
        // for all of them — the fold branch that reads `venues` is
        // unreachable from this call site. If a source ever shares a
        // category's name it degrades safely, since `landing` returns nil for
        // an empty member list and the modifier then draws no peek at all.
        //
        // `enabled` restates the "All" guard even though `packed` already
        // filtered it out of the grid: a guard that mirrors the strip's own
        // is worth more than one that trusts a filter three functions away,
        // and "All" previewing the entire feed is the thing §384 refused.
        .modifier(ChipPeekModifier(label: label, venues: [],
                                   enabled: label != "All",
                                   onOpen: {
                                       onPick(label)
                                       onDismiss()
                                   }))
        // The grouping is drawn, so it must also be SPOKEN — a name band
        // hidden from VoiceOver would otherwise take the category away from
        // the one reader who can't see the layout that carries it.
        .accessibilityLabel(label + ", \(category)"
            + (broken ? String(localized: ", needs reconnecting") : ""))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
