import SwiftUI
import UIKit

/// The one tray scaffold — the design-system rule for every bottom sheet.
///
/// RULE (brief §8): trays are not hand-rolled. A tray is `DSTray(title:height:)`
/// wrapping its content. It owns:
///   • the grabber (drag indicator),
///   • a left-aligned `heading22` title with top clearance so it never crowds
///     the grabber or "flows over" the top edge,
///   • uniform horizontal + bottom padding,
///   • the sheet surface, the height detent, and the color scheme.
/// Content flows below the title; the caller attaches its own `.onAppear`,
/// `.fileImporter`, `.confirmationDialog`, etc. to the `DSTray`.
struct DSTray<Content: View>: View {
    let title: String
    let height: CGFloat
    /// Paint `dsInk()` (pure black, forced dark) instead of the theme-
    /// adaptive default — for a tray that IS or precedes a black "detail"
    /// surface (`SocialProfileCard`, `WalletWorthALookTray`), so it reads as
    /// one continuous ink sheet instead of a shade off beside it. See
    /// `dsInk()` in `ThemeStore.swift` for the full rationale.
    var ink: Bool = false
    /// The detent set. Defaults to the single computed `height` every other
    /// tray already ships — pass a wider set (e.g. `[.height(height), .large]`)
    /// to let a tray with unpredictable content length be dragged open past
    /// its natural size instead of clipping at a hard ceiling.
    var detents: Set<PresentationDetent>?
    @ViewBuilder var content: () -> Content

    /// **A TITLE WRAPS, IT DOES NOT TRUNCATE** (2026-09-02, user: "in hegota we
    /// have sheets w/ titles that are clipped now that we use bigger font").
    ///
    /// `heading34` is 40pt heavy, so a perfectly ordinary tray title — "Into the
    /// UTXO vault", "This phone's account", "Keys and permissions" — no longer
    /// fits one phone line, and the head rung is exactly where a lost word costs
    /// most: "Into the UTXO va…" is the sheet failing to say what it is about.
    /// `DSSheetHead` has carried the `fixedSize` guard since it was written and
    /// the tray title never took it; this is that same line, one component over.
    ///
    /// The measurement is the other half. Every caller sizes its tray from the
    /// model this component documents — "pad, title, gap, content, pad" — with
    /// ONE line of title in it, so a title that grows to two would silently
    /// spend a content line, and a deficit clips. `titleOverflow` hands those
    /// points back to the sheet rather than making 27 callers each remember a
    /// term for a wrap they cannot see from where they sit.
    @State private var titleHeight: CGFloat = 0

    /// One line of `heading34` (its own `lineHeight`), scaled the way `dsText`
    /// scales it — `@ScaledMetric(relativeTo:)` and `UIFontMetrics` are the same
    /// table, so the two can't drift apart at an accessibility size.
    @ScaledMetric(relativeTo: .largeTitle) private var titleLine: CGFloat = 40

    /// What the title took BEYOND the one line every caller's arithmetic
    /// budgeted for. Zero for the ~20 short titles, so nothing moves for them.
    private var titleOverflow: CGFloat { max(0, titleHeight - titleLine) }

    var body: some View {
        let tray = VStack(alignment: .leading, spacing: DS.Space.s4) {
            // The title doubles as its own catalog key — a title that isn't a
            // key just renders verbatim, so dynamic titles stay safe.
            Text(LocalizedStringKey(title))
                // THE HEAD RUNG (prd §532) — a tray is a place, and at the
                // card-title rung it read as a taller card. 40 against the
                // 12pt caption inside it is 3.3×.
                .dsText(.heading34)
                .foregroundStyle(DS.textPrimary)
                .multilineTextAlignment(.leading)
                // …and therefore it WRAPS. See `titleHeight` above.
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    titleHeight = $0
                }
            // **THE TRAY HAS SPENT THE HEAD RUNG, AND SAYS SO** (2026-09-02).
            // Read by `DSSheetHead`, which takes the next rung down rather than
            // drawing a second `heading34` four points under this one — see its
            // `title` for why that stopped being a fair reading of §560.
            //
            // Declared HERE rather than passed by every caller: five of the six
            // `DSSheetHead`s in the app are inside a tray, so a flag would be
            // remembered five times and forgotten on the sixth. The tray is the
            // only thing that knows it is a tray.
            content().environment(\.dsSurfaceHasHead, true)
        }
        // Top-aligned by FRAME, not by a trailing `Spacer(minLength: 0)`
        // (2026-08-11). A Spacer is a view, so the stack's own `spacing` was
        // inserted BEFORE it as well as before the content — every tray paid
        // `DS.Space.s4` twice while its caller's height arithmetic counted it
        // once.
        //
        // Reported as clipping in the sources tray: cards with no bottom edge.
        // `SourcesTray.chromeHeight` is `s6 + title + s4 + s6`, and it snaps
        // the resting height DOWN to a whole number of cards precisely so a
        // card is never cut in half — but the sheet was 15pt shorter than that
        // arithmetic believed, so the last card lost its 6pt of bottom padding
        // and a slice of its name row. The label survived and the card's
        // rounded bottom did not, which is why it read as a clipping bug
        // rather than as a height being wrong.
        //
        // Fixed HERE rather than by adding 15pt to the one tray that noticed:
        // every caller computes its height from the same "pad, title, gap,
        // content, pad" model this component documents, so the phantom gap was
        // wrong for all of them and merely invisible in trays with slack. A
        // deficit clips; slack does not, so this can only turn clipped trays
        // into correct ones.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, DS.Space.s4)
        // The title clears the grabber — this is the fix for titles crowding
        // the top edge; every tray inherits it.
        .padding(.top, DS.Space.s6)
        .padding(.bottom, DS.Space.s6)
        // The overflow is paid ONLY where this component owns the number.
        // A caller that passes its own set has already put `.large` in it —
        // every one of the eight does — so a second line there costs a shorter
        // resting viewport on a body that scrolls, never a dead end; adding a
        // detent of our own to somebody else's set would leave the sheet
        // choosing between two nearly-equal heights on open.
        .presentationDetents(detents ?? [.height(height + titleOverflow)])
        // …and the Mac twin of that line, because the line above does NOTHING
        // there (2026-08-20). See `dsSizedSheet`.
        .dsSizedSheet(height + titleOverflow)
        .presentationDragIndicator(.visible)
        // THE CORNER UIKIT DRAWS FOR US (prd §560, 2026-09-01). `DS.Radius`'s
        // own `presentedSheet` doc argues this for "the most-opened surface in
        // the app" and it had reached exactly three sheets — the reading
        // three, which spell it by hand — while all 26 trays took whatever the
        // system gave. On iOS 26 the token is nil, so this is the system's
        // concentric corner and nothing changes; below 26 it pins the same 16
        // every drawn surface in this app already uses. A tray is a presented
        // sheet like any other and had no reason to be the exception.
        .dsSheetCorner()
        // A tray with a SECOND, larger detent (the Hegotá key/send sheets'
        // own scroll-past-clipping fix) defaults to `.automatic` content
        // interaction — which on a sheet with more than one detent resizes
        // the SHEET on a content drag rather than scrolling it, until the
        // sheet is already at its largest detent. That is exactly why the
        // `ScrollView` those trays added still read as clipped (user: "the
        // send tray open, clipped stuff is below the fold at the bottom") —
        // a swipe on the body moved the tray, not the list, so a person had
        // to already be at `.large` before scrolling did anything at all.
        // `.scrolls` makes a drag on the content always scroll it; the
        // grabber (`.presentationDragIndicator` above) is still there to
        // resize the sheet itself. Scoped to multi-detent trays only — a
        // single-height tray has nothing to scroll past, so it keeps
        // `.automatic` (unchanged behaviour for the ~30 other trays).
        .presentationContentInteraction(detents != nil ? .scrolls : .automatic)
        // Feel, re-declared for this presentation (2026-08-01, user: the
        // sources tray's cells were silent). `DSHaptic` is a counter bump on a
        // shared bus, and the mapping from counter to feedback is a VIEW
        // modifier — so it plays only where it is attached. It was attached in
        // exactly one place, `RootShell`'s body, and a sheet covers that: every
        // haptic fired from inside a tray bumped its counter and nothing was
        // listening. A tray is its own hosting environment, the same reason
        // `RootShell.rootPresented` has to re-inject the shell's environment
        // objects rather than let a sheet inherit them.
        //
        // It cannot double up with the root's copy — that copy is precisely
        // what doesn't fire under a sheet, which is the bug. And it belongs
        // HERE rather than at each call site because design law already says
        // every tray in this app is a `DSTray`, so one line covers all of them
        // and a tray built tomorrow can't be born silent.
        .dsSensoryFeedback()

        if ink {
            tray.dsInk()
        } else {
            tray.presentationBackground(DS.surfaceSheet).dsColorScheme()
        }
    }
}

// MARK: - The Mac's sheet sizing

/// **Every `presentationDetents` line in this app is a no-op on Mac
/// (2026-08-20, user: "some of the mac design looks like it was made for
/// mobile").**
///
/// Catalyst has no sheet detents, no drag indicator and no background
/// interaction — a modal with no explicit sizing presents as a **form sheet**,
/// a fixed ~540×620 card centred in the window whatever the window's real size
/// is. So the ~14 trays and the 10 `BridgeConnectionSheet`s all rendered at one
/// borrowed size, each one computed for a phone: `DSTray`'s whole contract is
/// that a tray STATES its height (and `AccountDetailSheet`'s own comment notes
/// that "DSTray clips at a fixed detent, so the tallest reachable state must be
/// sized for") — and on Mac that number was being thrown away.
///
/// `presentationSizing` (iOS 18+, which is this app's floor) is the supported
/// lever and it does bind on Catalyst. Two things about it worth knowing before
/// changing this:
///
///   • **`PresentationSizingContext` is an EMPTY struct** in the SDK — it
///     carries no container size — so a custom sizing cannot clamp itself
///     against the window. It proposes; the presentation clamps.
///   • That clamping is therefore load-bearing, and it is the SAME behaviour
///     these trays already rely on for touch: `privacyHeight` reaches ~900pt
///     and an iPhone SE is 568 tall, so a tray taller than its container is an
///     established, tolerated state rather than a new risk this introduces.
///     `PadLayout.macMinWindowSize`'s height is set so the common trays clear
///     it outright.
///
/// The WIDTH is the real gain. A tray's content was laid out for a phone column
/// and the form sheet gave it ~540 minus padding; `macSheetWidth` gives it a
/// proper dialog without letting it become a page — a language picker has no
/// business filling a desktop window, which is why this is a stated width and
/// not `.page`.
/// # A POPOVER was the obvious Mac answer, and it is declined (2026-08-20)
///
/// On macOS a picker anchored to the control that opened it is the native
/// shape, and several of these trays are pickers — a language list, an NFT
/// chooser, a wallet tile's drill-down. So `.popover` was the first proposal.
///
/// It is refused because of where these presentations LIVE. A popover anchors
/// to the view it is attached to, and every `.sheet` in this app is attached
/// to its SCREEN ROOT, never to the row or button that triggers it. That is
/// not an accident to be tidied up: it is the standing rule this codebase paid
/// for three times ("a feed ROW never carries a presentation of its own — one
/// screen, one `.sheet`"), because a `.sheet` attached inside a `List` row
/// resolves to the same presenting controller as the row's tap and tears its
/// own presentation down mid-transition — the "opens half way and closes"
/// report. Converting these in place would anchor every popover to the whole
/// screen's bounds, which is not anchoring at all; converting them properly
/// means moving presentations back onto rows, which is the bug class by name.
///
/// The honest middle path exists and is NOT built here: hoist the trigger's
/// frame with an anchor preference and hand it to a root-level popover as
/// `attachmentAnchor: .rect(...)`. That keeps one presentation per screen AND
/// anchors correctly. It is a real design pass across ~14 call sites with a
/// per-site judgement about whether each tray is a picker (popover) or a task
/// (sheet), and it wants to be its own session rather than a rider on a sizing
/// fix — so what ships is every tray correctly SIZED for a window, which is
/// the half that was actually broken.
enum DSSheetSize {
    /// **Where a sheet is a BOX rather than the bottom of the screen.**
    ///
    /// This is the one `userInterfaceIdiom` check in the app, and the reason it
    /// has to be the idiom rather than the size class is the trap this whole
    /// file exists for: a presented form sheet reports a **COMPACT** horizontal
    /// size class to its own content, whatever the window behind it. So the
    /// usual gate (`horizontalSizeClass == .regular`, which every other
    /// adaptation here uses) reads `false` inside the very sheet it would be
    /// asked to size, and is worse than useless — it is confidently wrong.
    ///
    /// iPhone is excluded on purpose: there a sheet is already full width and
    /// its detents are real, so a sizing proposal has nothing to fix and could
    /// only fight them.
    static var sizesSheets: Bool {
        switch UIDevice.current.userInterfaceIdiom {
        case .pad, .mac: true
        default: false
        }
    }

    /// A Mac dialog, not a phone column and not a page. Comfortably under
    /// `PadLayout.macMinWindowSize.width` so it can never be the thing that
    /// makes a sheet wider than the window it sits in.
    static let macSheetWidth: CGFloat = 620

    /// Proposes an absolute size. See the type doc for why it cannot consult
    /// the container.
    struct Sizing: PresentationSizing {
        let width: CGFloat
        let height: CGFloat
        func proposedSize(for root: PresentationSizingRoot,
                          context: PresentationSizingContext) -> ProposedViewSize {
            ProposedViewSize(width: width, height: height)
        }
    }
}

extension View {
    /// The Mac twin of `presentationDetents(.height(h))` — a no-op on touch,
    /// where the detent is real and this would fight it.
    @ViewBuilder
    func dsSizedSheet(_ height: CGFloat,
                        width: CGFloat = DSSheetSize.macSheetWidth) -> some View {
        if DSSheetSize.sizesSheets {
            presentationSizing(DSSheetSize.Sizing(width: width, height: height))
        } else {
            self
        }
    }

    /// The Mac twin of `presentationDetents([.medium, .large])` — a READING
    /// sheet rather than a tray.
    ///
    /// `.page` rather than a stated size, and the distinction is the whole
    /// reason there are two helpers. A tray STATES its height because its
    /// content is a known number of rows; a reading sheet (a thing, a profile,
    /// a token card) holds whatever it holds, and `[.medium, .large]` is
    /// exactly the caller saying "size this to the screen, and let me drag it".
    /// `.page` is the system's own answer to that on a window — proportional
    /// to the container, clamped by it, and needing no arithmetic of ours that
    /// could outgrow a small window.
    ///
    /// A no-op on touch, where the detents are real and this would fight them.
    @ViewBuilder
    func dsPageSheet() -> some View {
        if DSSheetSize.sizesSheets {
            presentationSizing(.page)
        } else {
            self
        }
    }
}

/// **HAS THIS SURFACE ALREADY SPENT THE HEAD RUNG?** (2026-09-02)
///
/// One `heading34` per surface, which is `heading34`'s own doc ("the head of a
/// tray, a sheet or a room — the rung that says WHERE YOU ARE") read for what
/// it says: you are only in one place. `DSTray` sets this on its content;
/// `DSSheetHead` reads it and takes the next rung down.
///
/// **The pair was drawing two heads on five sheets and nothing could see it**,
/// because each is right on its own. §532 gave the tray title the head rung (a
/// tray is a place); §560 raised `DSSheetHead` to the same rung on the
/// reasoning that "a `DSSheetHead` has no amount, so its title is the largest
/// thing on the paper". Inside a tray that premise is simply false — the tray's
/// own title is the same size, four points above — and the result was 120pt of
/// headline before the first fact, which on `VibenetCreateSheet` pushed the new
/// account's address under the pinned action and cut it through the middle.
///
/// Environment rather than a parameter for the reason `DSTray` states at the
/// call site: the tray is the only view that knows it is a tray, and a flag
/// five callers must remember is a flag the sixth forgets.
private struct DSSurfaceHasHeadKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var dsSurfaceHasHead: Bool {
        get { self[DSSurfaceHasHeadKey.self] }
        set { self[DSSurfaceHasHeadKey.self] = newValue }
    }
}
