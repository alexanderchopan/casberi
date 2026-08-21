import SwiftUI

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
    /// Present on GLASS instead of the opaque `surfaceSheet` (2026-08-16, user).
    ///
    /// The one tray that takes it is `SourcesTray`, and it takes it because its
    /// cells lost their opaque cards the same day: marks floating on an opaque
    /// sheet are the bare 2026-08-06 grid, marks floating on a panel of glass
    /// are a shelf. Everywhere else the opaque sheet stays right — a tray that
    /// carries text you READ has nothing to gain from a live backdrop and a
    /// contrast floor to lose.
    ///
    /// Deliberately NOT the default, and deliberately not `dsGlass`: that
    /// modifier is for the floating layer (composer, FAB, toasts) and carries a
    /// stroke, a shadow and a corner radius of its own — all three wrong for a
    /// surface the system already rounds, shadows and clips for us.
    var glass: Bool = false
    /// The detent set. Defaults to the single computed `height` every other
    /// tray already ships — pass a wider set (e.g. `[.height(height), .large]`)
    /// to let a tray with unpredictable content length be dragged open past
    /// its natural size instead of clipping at a hard ceiling.
    var detents: Set<PresentationDetent>?
    @ViewBuilder var content: () -> Content

    var body: some View {
        let tray = VStack(alignment: .leading, spacing: DS.Space.s4) {
            // The title doubles as its own catalog key — a title that isn't a
            // key just renders verbatim, so dynamic titles stay safe.
            Text(LocalizedStringKey(title))
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
            content()
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
        .presentationDetents(detents ?? [.height(height)])
        // …and the Mac twin of that line, because the line above does NOTHING
        // there (2026-08-20). See `dsMacSheetSize`.
        .dsMacSheetSize(height)
        .presentationDragIndicator(.visible)
        // THE SHEET'S OWN DIM, which nothing here had ever touched (2026-08-16).
        //
        // iOS draws a scrim BETWEEN the presenting content and a sheet. For an
        // opaque tray that is invisible and correct. For a glass one it is the
        // whole problem: the panel is not sampling the feed, it is sampling the
        // feed already darkened, so every point of transparency bought by
        // fading the material is spent again by a layer we never asked for and
        // never saw. `.enabled(upThrough:)` is the only public way to drop it —
        // UIKit's `largestUndimmedDetentIdentifier` under a SwiftUI name.
        //
        // Scoped to the resting detent, not `.large`: dragged to full height
        // this really is a modal surface covering its page, and dimming is then
        // the honest reading. Scoped to GLASS trays alone, so the 30-odd opaque
        // trays keep the behaviour they were designed with.
        //
        // KNOWN COST, stated rather than discovered later: undimmed means
        // INTERACTIVE — a tap lands on the feed behind instead of being
        // swallowed. That is what Maps' sheet does and it suits a picker that
        // is a lens over the room, but it is a real behaviour change and not a
        // side effect of a colour tweak.
        .presentationBackgroundInteraction(glass ? .enabled(upThrough: .height(height))
                                                 : .automatic)
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
        } else if glass {
            tray.presentationBackground { DSGlassSheet() }.dsColorScheme()
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
enum DSMacSheet {
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
    func dsMacSheetSize(_ height: CGFloat,
                        width: CGFloat = DSMacSheet.macSheetWidth) -> some View {
        #if targetEnvironment(macCatalyst)
        presentationSizing(DSMacSheet.Sizing(width: width, height: height))
        #else
        self
        #endif
    }
}

/// The sheet as a PANEL of glass rather than a blurred rectangle.
///
/// The material alone reads as FOG — measured against four alternatives in
/// `prototype/sources-tray-glass-v1.html`. What makes it read as a pane is the
/// SHEEN: a fall-off from the top-leading corner, i.e. the light the panel is
/// under. The mock also carried a 1pt lit rim along the top edge, which is the
/// single strongest cue of the two and is NOT here on purpose — brief §8's
/// no-hairlines rule has zero exceptions, and a lit rim is a hairline no matter
/// what it is standing in for. The gradient carries the same idea with no line.
///
/// # The sheen was a WASH, and the reach was the bigger half (2026-08-16, user)
///
/// Reported as "a little too gray" the day it shipped. The first cut ran the
/// sheen to `0.46` — so a 12% white gradient covered the top HALF of the sheet,
/// which is the half the eye lands on first: the title, the first category, the
/// brightest marks. That is not a highlight, it is a veil, and a veil is
/// achromatic by construction — it spends whatever the blur just pulled through
/// from the feed and gives back grey.
///
/// Two changes, compared as rendered pixels over a real feed AND over an
/// edge-to-edge bright one in `prototype/sources-tray-glass-v2.html`:
///
/// - **The reach**, `0.22/0.46` → `0.12/0.30`. This is the fix. The pane cue is
///   a FALL-OFF, not a flood — it survives at a third of the distance, and it
///   stops reaching the grid at all.
/// - **The dose**, stepped back in the token itself.
///
/// **`glassDepth` is the other half, and it is what actually removes grey.**
/// Lightening and deepening are not symmetric over a blur: white pulls the
/// hues behind the sheet toward grey, black pulls them toward themselves. So
/// the panel now falls off INTO its own depth rather than into nothing.
///
/// # The material itself is faded, and the mock could not have said so (2026-08-16, user)
///
/// The first degray pass trimmed only OUR additions and shipped the material at
/// full strength, on the prototype's evidence — and the prototype models the
/// material as a CSS backdrop blur with `saturate(1.8)`, a boost Apple's dark
/// material does not perform. On device `.ultraThinMaterial`'s own dark plate
/// is the dominant grey, so the build stayed fog while the mock read as glass
/// ("the actual build is still not transparent like it is in the picture").
/// `.opacity()` is the one public knob a `Material` has, and the earlier note
/// here refusing it was reasoning about the MOCK's fill — on the real material
/// the blur keeps owning the backdrop far below where the CSS model dissolves.
/// Walked down 0.82 → 0.72 → 0.62 → **0.55** against simulator screenshots
/// over the demo feed (`scratchpad` shots tray-dark-1…4, 2026-08-16): at 0.82
/// the plate still won and the panel read as the same grey slab; at 0.55 the
/// feed's colour reads through both themes and a dark feed reads DEEP rather
/// than grey, which is the whole complaint. The floor under legibility is
/// `glassDepth`, which is also why the depth overlay sits OUTSIDE the faded
/// fill: the panel's own shading must not fade with the plate it compensates
/// for.
///
/// **0.55 → 0.45, same day, judged ON DEVICE this time** (user: "still a bit
/// gray … I want it to really look like the transparent glass apple does").
///
/// # …so use what Apple uses (user, 2026-08-16) — and the recipe stays anyway
///
/// Asked directly: "why not just use what apple does?" The right answer, and
/// the walk above was the wrong instrument. **Fading a material does not make
/// it transparent, it makes it WEAK** — `.opacity()` takes the frosting down
/// alongside the grey, so every step buys clarity by spending the exact
/// contrast the chip names stand on. There is a real transparent material and
/// we were approximating it by thinning an opaque one.
///
/// So on iOS 26 this is `glassEffect(.clear)` — the system's own Liquid Glass,
/// with its refraction, its specular edge and its adaptation to what's behind
/// it, none of which a gradient can imitate.
///
/// **The recipe below is NOT deleted, and that is the honest answer to "just
/// use Apple's":** this app deploys to **iOS 18**, and `glassEffect` is 26+.
/// Liquid Glass cannot be the only implementation while a supported device
/// can't draw it — so the two are a pair, not a replacement, exactly as
/// `dsGlass` has always been shaped.
///
/// Two things the system path does NOT inherit from the recipe:
///   • **the sheen is dropped.** It exists to fake the light a pane sits
///     under; real glass draws its own specular highlight, and laying ours
///     over it is the doubling that read as a wash in the first place.
///   • **the depth scrim is kept.** It is not decoration and not an imitation
///     of anything the system does — it is the legibility floor under 12pt
///     `textSecondary` chip names when the feed behind is edge-to-edge
///     pictures, which is precisely the contrast `.clear` withholds by design
///     (`DSGlassVariant`'s own rule). Lighter than the recipe's, since the
///     system material is already doing more of the work.
///
/// **UNVERIFIED on a device, and structurally so** — no simulator renders
/// Liquid Glass the way hardware does, so the one question that matters here
/// (do the chip names survive over a bright feed?) cannot be answered from
/// this host. `-trayGlass material` forces the recipe on an iOS 26 build so
/// both can be compared in ONE build on the real device, rather than shipping
/// a guess and waiting for a report.
///
/// No shape of its own: `presentationBackground` is already clipped to the
/// sheet, and an inner `RoundedRectangle` would draw its own corners inside the
/// system's — two radii, one of which is a guess at what iOS is doing this year.
private struct DSGlassSheet: View {
    var body: some View {
        if #available(iOS 26.0, *), DSTrayGlass.useSystem {
            systemGlass
        } else {
            recipe
        }
    }

    // MARK: - Why the material is the DEFAULT again (2026-08-16, device report)
    //
    // `glassEffect(.clear)` shipped as the default in build 343 on the
    // reasoning that fading a material is not the same as transparency. That
    // reasoning still holds for a BAR. It appears to be false for a SHEET.
    //
    // Measured by report, not by theory: the material walk 0.55 → 0.45 was
    // "way better than before" ON DEVICE, i.e. it was visibly sampling the
    // feed. The very next build swapped in Liquid Glass and the same person
    // reported "it still looks gray … and it's not see through either", while
    // the SIMULATOR renders that same build with the feed's red card clearly
    // showing through the panel. A sim/device split that large is not a tuning
    // problem — it says `glassEffect` is not sampling a presented sheet's
    // backdrop on hardware, and is falling back to a flat tinted fill.
    //
    // That is consistent with what Apple actually does: Liquid Glass is for
    // the functional layer that floats INSIDE a view hierarchy — bars,
    // controls, the App Store tab bar the report compared us against — and
    // Apple's own sheets are materials. `.ultraThinMaterial` is documented to
    // work in `presentationBackground`; `glassEffect` never claimed to.
    //
    // So the default is the material again, and the system path stays behind
    // `-trayGlass system` rather than being deleted: it is right the moment
    // this tray stops being a sheet, and the flag is how that gets re-measured
    // without another ship.

    /// The real thing (iOS 26+). See the type doc for why the sheen is dropped
    /// and the depth kept.
    @available(iOS 26.0, *)
    private var systemGlass: some View {
        Color.clear
            .glassEffect(.clear, in: Rectangle())
            .overlay { depth(DS.glassDepth.opacity(0.6)) }
            .ignoresSafeArea()
    }

    /// The pre-26 recipe — a material, plus the light and shading a pane needs
    /// to read as a pane. Not a fallback in the apologetic sense: it is what
    /// every device below iOS 26 draws, which today is most of them.
    private var recipe: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            // The plate fade — see the doc. Before the overlays on purpose:
            // the sheen and depth are the panel's own light and shading and
            // must render at full strength over the faded material.
            //
            // 0.45 → 0.35 (2026-08-16). 0.45 was reported "way better than
            // before" and still grey, and the two builds that followed spent
            // their transparency budget on `glassEffect` instead of on this
            // number — which turned out to sample nothing on a sheet. This is
            // the walk resumed where the evidence actually was. The floor is
            // legibility over a BRIGHT feed, which `glassDepth` carries and
            // no screenshot on this host can test.
            .opacity(0.35)
            .overlay {
                // The light the panel is under. Short on purpose — see the doc.
                LinearGradient(
                    stops: [
                        .init(color: DS.glassSheen, location: 0),
                        .init(color: DS.glassSheen.opacity(0.25), location: 0.12),
                        .init(color: .clear, location: 0.30)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottom
                )
            }
            .overlay { depth(DS.glassDepth) }
            .ignoresSafeArea()
    }

    /// The depth the panel sits in. Straight down rather than from the corner:
    /// the sheen is a light SOURCE and has a direction, this is the panel's own
    /// body and has none — leaning it would read as a second light coming up
    /// from the floor.
    private func depth(_ color: Color) -> some View {
        LinearGradient(
            stops: [.init(color: .clear, location: 0.32), .init(color: color, location: 1)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Which glass the tray draws, and the DEBUG door to the other one.
///
/// The comparison this exists for cannot be made on this host: no simulator
/// renders Liquid Glass the way hardware does, and the question that decides
/// between them — whether 12pt `textSecondary` chip names survive over an
/// edge-to-edge picture feed — is exactly the one only a device can answer.
/// `-trayGlass material` forces the pre-26 recipe on an iOS 26 build, so both
/// treatments are reachable from ONE build on the real device.
enum DSTrayGlass {
    /// FALSE by default since 2026-08-16 — see `DSGlassSheet`'s note. The
    /// material is what provably samples a sheet's backdrop on hardware; the
    /// system path is kept behind `-trayGlass system` because it becomes right
    /// the day this tray stops being a sheet, and a flag is how that gets
    /// re-measured without another ship.
    static var useSystem: Bool {
        #if DEBUG
        UserDefaults.standard.string(forKey: "trayGlass") == "system"
        #else
        false
        #endif
    }
}
