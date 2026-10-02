import SwiftUI
import SwiftData

// The empty and quiet states, and the empty feed's pile, split out of
// FeedScreen.swift (prd §718). Nothing here changed but the file it lives
// in and, where another file reads a member, its access level.
extension FeedScreen {
    // MARK: - Pieces

    /// Empty Feed — the rain come to rest (2026-07-16, replacing the quiet
    /// line + skeleton rows: skeletons mean "loading" everywhere, so an
    /// empty state wearing them forever read as stuck, not promising). The
    /// headline speaks in the display tier (the Home cover's voice), one
    /// door opens the catalog, and the settled pile is the onboarding rain
    /// landed HERE — every tile a real offer that opens its own product
    /// page, so the pile is honest by construction. Rendered FLAT (plain
    /// stacks, no Widget/Row path) — this sits in the eager feed body,
    /// where tree depth is the launch-crash class.
    /// This room's own quiet words, or nil to use the generic invitation
    /// (prd §299). Maps the seat's SwiftUI-side status onto `RoomQuiet.Seat`,
    /// which is the only place the two vocabularies meet.
    private var quietWords: RoomQuiet.Words? {
        guard source != "All" else { return nil }
        // Through the catalog — see `activeSourceBridge`. A bare `==` resolved
        // the wallet-riding rooms to no seat at all, so `.none` won the switch
        // below and they fell back to the generic "connect an app" invitation:
        // §299's own failure, in the rooms it was written for.
        let seatName = BridgeCatalog.seatName(forSource: source)
        let seat = bridges.bridges.first { $0.name == seatName }
        let mapped: RoomQuiet.Seat = switch seat?.status {
        case .connected: .connected
        case .attention: .attention
        case .paused:    .paused
        case nil:        .none
        }
        return RoomQuiet.words(source: source, seat: mapped,
                               statusLine: seat?.statusLine ?? "",
                               emptyRead: TokenBridge(rawValue: source)?.emptyReadNote)
    }

    /// The empty room.
    ///
    /// A connected room says so and stops inviting you to connect it; a paused
    /// one names the state you chose; a BROKEN one says it's broken, which the
    /// generic copy hid behind a cheerful invitation (prd §299). Everything
    /// else — All, and any room with no seat — keeps the original.
    @ViewBuilder
    var emptyState: some View {
        if let words = quietWords {
            quietState(words)
        } else {
            invitationState
        }
    }

    /// A room that is working, paused or broken — and empty. Same anatomy as
    /// the invitation below (heading, sentence, one door) so the two read as
    /// one screen in two states rather than two screens, which is the shape
    /// `CloudflareRunwayCard` settled on for the same problem.
    private func quietState(_ words: RoomQuiet.Words) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(words.headline)
                .dsText(.heading40)
                .foregroundStyle(DS.textPrimary)
                .settleIn()
            Text(words.detail)
                .dsText(.body17).foregroundStyle(DS.textSecondary)
                .padding(.top, DS.Space.s2)
                .settleIn(delay: 0.05)
            if words.offersDoor {
                emptyDoor(String(localized: "Open \(source)"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s6)
    }

    /// The one act an empty room offers, at the head rung (prd §563).
    ///
    /// **Both empty states shared one shape: a control set SMALLER than the
    /// prose above it** — `heading40`, then `body17`, then a `body17`
    /// capsule — so the only thing a person could DO on the screen was the
    /// quietest thing on it. §559 made a verb at `price40` the house treatment
    /// for a surface that exists to do one thing, and an empty room is exactly
    /// that: there is nothing here to read, so the act is the content.
    ///
    /// **ONE call site for both states, deliberately.** §299 already rules that
    /// the quiet room and the invitation are "one screen in two states rather
    /// than two screens", and a shared door is that ruling as code rather than
    /// as a comment — the two cannot drift into different verbs at different
    /// rungs. It is also what keeps `hero-tint-audit.py`'s one-tile-per-file
    /// rule true of the file that draws both.
    ///
    /// The destination is unchanged and is the CATALOG in both states, which is
    /// what `route.present(.apps)` has always done here — including under the
    /// "Open \(source)" wording, whose door has never gone to that source.
    private func emptyDoor(_ title: String) -> some View {
        DSActVerb(title: title, glyph: "square.grid.2x2") {
            route.present(.apps)
        }
        .padding(.top, DS.Space.s4)
        .settleIn(delay: 0.1)
    }

    private var invitationState: some View {
        VStack(alignment: .leading, spacing: 0) {
            // THE INBOX FRAME (user ruling 2026-09-06, arrived via the deck:
            // "manager" was dropped as forced — "we aren't changing passwords
            // or account details" — for "one inbox for all your accounts").
            // The headline says what the empty screen BECOMES, in the app's
            // own noun, rather than naming the container it already is.
            Text("One inbox for all your apps.")
                .dsText(.heading40)
                .foregroundStyle(DS.textPrimary)
                .settleIn()
            // THE SENTENCE STANDS DOWN (prd §563). It read "Connect an app and
            // things start landing on their own" — which is the headline's
            // goal, the tile's verb and the pile's own contents said a third
            // time, in the tier §554 rules on. What replaces it is not shorter
            // copy, it is the tile below saying it at the head rung.
            //
            // A quiet room's `detail` is DELIBERATELY NOT treated this way: it
            // carries §299's diagnosis (a broken room says it is broken), which
            // no verb can state. A sentence that RESTATES the door goes; a
            // sentence that DIAGNOSES stays.
            emptyDoor(String(localized: "Browse apps"))
            // The "or paste a link, share in, snap a screenshot" line is
            // DELETED (user, 2026-08-07). It was added to teach the capture
            // verbs the headline only claimed, but it teaches them to someone
            // who has nothing yet and no reason to care which door they use —
            // and it sits above the pile of real apps, which is the actual
            // answer to an empty feed. Every one of those verbs is discovered
            // in the moment it is wanted (the share sheet is the system's, the
            // composer's paste chip appears when there is something on the
            // clipboard); a screen that has to list them is padding the one
            // moment that should be shortest.
            Spacer(minLength: DS.Space.s6)
            EmptyFeedPile()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s6)
        // The pile rests at the FOOT of the screen (the rain lands where the
        // floor is): the row takes a fixed drop and the Spacer above hands
        // the slack to the pile. A plain minHeight, not
        // `containerRelativeFrame` — inside this List that modifier reported
        // a container shorter than the viewport and always floored (measured
        // 2026-07-16). On an oversized-type layout the Spacer collapses and
        // the row grows past the minimum instead of crowding.
        .frame(minHeight: 540, alignment: .top)
    }

    /// A filter with no matches: the filtered app's own icon, a plain line,
    /// and one way back. Never a bare "Nothing matches."
    var filteredEmptyState: some View {
        VStack(spacing: DS.Space.s3) {
            if source != "All" {
                BridgeIcon(name: source, size: DS.Mark.tile)
            } else if let kind = ThingKind.from(typeTag: filter.tag) {
                KindGlyph(kind: kind, size: 44)
            }
            Text(emptyLine)
                .dsText(.body17)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
            // The one way back, as a row sized to its words (prd §746).
            DSDoorRow(icon: "line.3.horizontal.decrease.circle", label: "Show everything") {
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) {
                    filter.source = "All"
                    filter.tag = "All"
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            tryItChip
            // The empty room previews its own shape (2026-07-13) — the
            // all-feed empty state already does this with skeleton rows;
            // a shaped empty shows what ITS rows will look like: a grid
            // for Photos, rows for everything else.
            if source != "All" {
                emptyShapePreview
                    .padding(.top, DS.Space.s6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s6)
    }

    /// One tap demos a source that otherwise needs a first pick to mean
    /// anything — the Wallet screen's "Peek at vitalik.eth" (prd §79),
    /// generalized to every empty room that's just a search field with
    /// nothing in it (delight pass 2026-07-21). Retires the moment anything
    /// is watched — the empty state itself stops rendering.
    @ViewBuilder private var tryItChip: some View {
        if shape == .tokens {
            tryItButton(label: "Watch ETH") {
                guard let resolved = await TokenWatch.resolve("ETH") else { return }
                TokenWatch.add(resolved, context: modelContext)
                TokenWatch.registerBridge(store: bridges, context: modelContext)
            }
        } else if source == "RSS" {
            tryItButton(label: "Follow NASA's feed") {
                guard RSSStore.shared.add("https://www.nasa.gov/feed/") else { return }
                let added = await RSSIngest.refresh(context: modelContext,
                                                    waitForInFlight: true)
                bridges.registerConnected(id: "rss", name: "RSS",
                    proof: (added ?? 0) > 0
                        ? String(localized: "\(added ?? 0) posts in")
                        : String(localized: "Synced just now"),
                    can: ["Reads the feeds you follow."])
            }
        }
    }

    /// One anatomy for every try-it — a door row (prd §746; it was a tint
    /// `Chip`, a verb wearing a choice's shape). Sized to its words, because it
    /// stands in a centred empty state rather than a list.
    private func tryItButton(label: String, action: @escaping () async -> Void) -> some View {
        DSDoorRow(icon: "sparkles", title: Text(LocalizedStringKey(label))) {
            DSHaptic.tap()
            Task { await action() }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.top, DS.Space.s2)
    }

    @ViewBuilder private var emptyShapePreview: some View {
        switch shape {
        case .photos:
            HStack(spacing: DS.Space.s3) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .fill(DS.gray100)
                        .frame(height: 90)
                        .staggerIn(index: i + 3)
                }
            }
        case .wallet:
            // A skeleton treemap mosaic — echoes the Wallet feed's real
            // holdings treemap (uneven tile sizes, not a uniform grid).
            RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous)
                .fill(DS.surfaceSheet)
                .frame(height: 160)
                .overlay {
                    HStack(spacing: DS.Space.s2) {
                        VStack(spacing: DS.Space.s2) {
                            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                                .fill(DS.gray100).frame(height: 88)
                            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                                .fill(DS.gray100)
                        }
                        VStack(spacing: DS.Space.s2) {
                            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                                .fill(DS.gray100)
                            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                                .fill(DS.gray100).frame(height: 56)
                        }
                        .frame(width: 72)
                    }
                    .padding(DS.Space.s3)
                }
                .staggerIn(index: 3)
        case .calendar:
            // A skeleton agenda band — each row a tinted strip, echoing
            // BandRow's own field-of-color shape.
            VStack(spacing: DS.Space.s2) {
                ForEach(0..<3, id: \.self) { i in
                    HStack(spacing: DS.Space.s3) {
                        Circle().fill(DS.gray100).frame(width: 24, height: 24)
                        Capsule().fill(DS.gray100).frame(height: 12)
                        Spacer(minLength: DS.Space.s2)
                        Capsule().fill(DS.gray100).frame(width: 40, height: 12)
                    }
                    .padding(.horizontal, DS.Space.s3)
                    .padding(.vertical, DS.Space.s3)
                    .background(DS.gray100.opacity(0.4),
                                in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    .staggerIn(index: i + 3)
                }
            }
        default:
            VStack(spacing: DS.Space.s2) {
                ForEach(0..<3, id: \.self) { i in
                    GenSkeletonRow()
                        .staggerIn(index: i + 3)
                }
            }
        }
    }

    var emptyLine: String {
        let tagLabel = ThingKind.from(typeTag: filter.tag)?.typeTagPlural ?? filter.tag
        // The Notes room is reachable while empty — its door is always drawn
        // (prd §969) — so this line is the first thing a person sees there.
        // It says what the two verbs are rather than that the room is empty,
        // because unlike every other room nothing will ever arrive here on
        // its own.
        if Pinboard.isPinnedRoom(source) {
            switch chrome.notesScope {
            case .pinned:
                // `DS.secondaryGesture`, not a literal (prd §607): pinning
                // lives in a `contextMenu`, which is a right-click under a
                // pointer, so the Mac was told to perform a gesture it does
                // not have.
                return String(localized: "Nothing pinned. \(DS.secondaryGesture) anything to pin it.")
            case .folders:
                return chrome.notesFolder == nil
                    ? String(localized: "\(DS.secondaryGesture) anything in All to move it into a folder.")
                    : String(localized: "\(DS.secondaryGesture) anything in All to move it here.")
            case .all, .new:
                return String(localized: "Write or record a note, or \(DS.secondaryGesture) anything to pin it here.")
            }
        }
        // A merged room narrowed to one app names the app, not the room.
        let from = selectedSeat?.name ?? source
        switch (source != "All", filter.tag != "All") {
        case (true, true):   return "Nothing from \(from) under \(tagLabel) yet."
        case (true, false):  return "Nothing from \(from) yet."
        case (false, true):  return "No \(tagLabel.lowercased()) yet."
        default:             return "Nothing here yet."
        }
    }
}

// MARK: - Empty-feed pile (the rain come to rest)

/// The settled pile of app tiles at the foot of the empty feed — the
/// onboarding rain's third act (HowItWorksSheet rains them past, its step-1
/// strip shows them settled; here they rest where things will land). On
/// first appearance the tiles fall in and settle — gravity is an ease-IN,
/// the house rule — then the caption fades up. Every tile is a door to that
/// offer's product page in the catalog (no dead controls), routed through
/// HomeRoute.openOffer so the push survives the .apps hop.
private struct EmptyFeedPile: View {
    /// Hand-curated subset of the catalog — every name MUST resolve to a
    /// real BridgeCatalog offer (scripts/catalog-sync.sh checks this array
    /// by name, like the other decorative marquees). First six are the back
    /// row; the last six draw over them as the front row. Wallet sits LAST
    /// in the front row (2026-07-29, user: "wallet should definitely be one
    /// of them") — a flagship feature belongs fully unobstructed, not in the
    /// back row where the front row's -10pt overlap clips its bottom edge.
    /// Swapped places with YouTube, which moved back.
    // RSS and Files in place of ChatGPT and Claude (user, 2026-09-05: "please
    // replace claude and chatgpt with rss and folder picker") — the two
    // doors that need no account and land rows in one tap.
    static let pileApps = ["Notion", "Strava", "RSS", "Photos",
                           "YouTube", "Substack",
                           "Gmail", "GitHub", "Farcaster", "Bluesky",
                           "Files", "Wallet"]

    /// Deterministic per-tile jitter — no randomness in a view body; the
    /// same pile settles identically every launch (and the screen sweep
    /// sees one design).
    private static let tilt:  [Double]  = [-5, 3, -2, 6, -4, 2,
                                           -6, 4, -3, 5, -2, 3]
    private static let restY: [CGFloat] = [3, -2, 4, 0, 2, -1,
                                           3, 1, -2, 2, 0, 3]

    /// How far above their rest the tiles wait — past the top of the screen
    /// from the pile's mid-page seat, so the fall crosses the headline the
    /// way the onboarding rain crosses the steps (no clip window: a clipped
    /// fall showed only its last inches, and the window's headroom read as
    /// a dead gap under the caption).
    private static let fallFrom: CGFloat = 700

    /// False = the tiles wait above the screen · true = they have landed.
    @State private var fell = false
    /// prd 43h: Reduce Motion is law — under it the pile is simply there,
    /// settled, no 700pt fall (nil animation makes the flip instant).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // This window's stack (per-window since `SceneState`).
    @Environment(HomeRoute.self) private var route

    var body: some View {
        VStack(spacing: DS.Space.s3) {
            // "Tap any app to add it" alone read as "this pile of 12 is what
            // you get" (user, 2026-07-29) — the real catalog door sits a
            // whole screen-height above this settled pile, easy to miss once
            // your eye has landed on the tiles. Named again, right here.
            Text("Tap any app to add it")
                .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                .opacity(fell ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3).delay(1.5),
                           value: fell)
            // Two rows nestled brick-wise: the back row smaller and shifted
            // half a pitch — depth and irregularity, a pile not a grid.
            VStack(spacing: -10) {
                row(0..<6, size: 44).offset(x: 24)
                row(6..<12, size: 52)
            }
        }
        .onAppear {
            fell = true
            #if DEBUG
            // `-pileTap "<Offer name>"` — fire a tile's tap after the fall,
            // the headless check of the tile → product-page arc.
            if let name = UserDefaults.standard.string(forKey: "pileTap") {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.5))
                    NSLog("pileTap: \(name)")
                    route.openOffer = name
                    route.present(.apps)
                }
            }
            #endif
        }
    }

    private func row(_ range: Range<Int>, size: CGFloat) -> some View {
        HStack(spacing: DS.Space.s2) {
            ForEach(range, id: \.self) { i in
                tile(Self.pileApps[i], index: i, size: size)
            }
        }
    }

    private func tile(_ name: String, index i: Int, size: CGFloat) -> some View {
        Button {
            DSHaptic.selection()
            route.openOffer = name
            route.present(.apps)
        } label: {
            BridgeIcon(name: name, size: size)
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(Text(name))
        .rotationEffect(.degrees(fell ? Self.tilt[i] : Self.tilt[i] * 0.4))
        .offset(y: fell ? Self.restY[i] : -Self.fallFrom)
        .animation(reduceMotion ? nil
                                : .easeIn(duration: 0.55).delay(0.35 + Double(i) * 0.05),
                   value: fell)
    }
}
