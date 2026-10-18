import SwiftUI
import SwiftData

// The empty and quiet states, split out of
// FeedScreen.swift (prd §718). Nothing here changed but the file it lives
// in and, where another file reads a member, its access level.
extension FeedScreen {
    // MARK: - Pieces

    /// This room's own quiet words, or nil to use the generic invitation
    /// (prd §299). Maps the seat's SwiftUI-side status onto `RoomQuiet.Seat`,
    /// which is the only place the two vocabularies meet.
    private var quietWords: RoomQuiet.Words? {
        guard source != "All" else { return nil }
        let seat = quietSeat
        let seatName = seat?.name ?? source
        let mapped: RoomQuiet.Seat = switch seat?.status {
        case .connected: .connected
        case .attention: .attention
        case .paused:    .paused
        case nil:        .none
        }
        return RoomQuiet.words(source: seatName, seat: mapped,
                               statusLine: seat?.statusLine ?? "",
                               emptyRead: TokenBridge(rawValue: seatName)?.emptyReadNote)
    }

    /// The seat an empty screen speaks for (prd §1162).
    ///
    /// Through the catalog — see `activeSourceBridge`. A bare `==` resolved
    /// the wallet-riding rooms to no seat at all, so `.none` won the switch
    /// and they fell back to the generic "connect an app" invitation: §299's
    /// own failure, in the rooms it was written for.
    ///
    /// **And through the picked app in a merged room.** Work, Day and the rest
    /// are not seats, so the catalog lookup found none there either — and a
    /// first connect LANDS in that room with its app picked (§1029,
    /// `chrome.pickSeat`). Someone who had just connected GitHub was shown
    /// "One inbox for all your apps" and Browse apps, the screen for having
    /// connected nothing.
    private var quietSeat: BridgeApp? {
        if let picked = selectedSeat?.name,
           let seat = bridges.bridges.first(where: { $0.name == picked }) {
            return seat
        }
        let seatName = BridgeCatalog.seatName(forSource: source)
        return bridges.bridges.first { $0.name == seatName }
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
            if words.offersDoor, let seat = quietSeat {
                emptyDoor(String(localized: "Open \(seat.name)"), glyph: "slider.horizontal.3") {
                    route.openAccount(BridgeRouter.destination(forID: seat.id))
                }
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
    /// The invitation's door is the CATALOG. A broken or paused screen's door
    /// is that app's own page (prd §1162): until then it was the catalog too,
    /// under the words "Open <app>" — and the catalog hides an app you have
    /// already added, so the one fix this screen offered led somewhere the
    /// broken app was not listed.
    private func emptyDoor(_ title: String, glyph: String = "square.grid.2x2",
                           action: (() -> Void)? = nil) -> some View {
        DSActVerb(title: title, glyph: glyph) {
            if let action { action() } else { route.present(.apps) }
        }
        .padding(.top, DS.Space.s4)
        .settleIn(delay: 0.1)
    }

    /// An empty page with no app of its own to speak for (prd §1420, user,
    /// 2026-10-18, of "One inbox for all your apps" and its pile of apps:
    /// "it should not exist why does it always come up"). That start screen
    /// replaced ANY page that had no rows and no exception of its own (Today,
    /// Day, the Wallet's pages, Notes, agents, Logos, Aztec…), so every new
    /// or quiet page fell into it, Testnets the latest. An empty page now
    /// says so in the house template and keeps nothing else: no headline about
    /// the app, no catalogue door, no pile.
    private var invitationState: some View {
        DSEmptyState(headline: DSProse.text("Nothing here yet"),
                     words: Text("What its apps bring in lands here."),
                     scale: .list(rows: 3))
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s6)
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
        // Markets' "Follow ETH" left with its room (prd §1337): the Wallet's
        // Markets tile never draws this empty state (§1167).
        if source == "RSS" {
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
            case .folders:
                return chrome.notesFolder == nil
                    ? String(localized: "\(DS.secondaryGesture) anything in All to move it into a folder.")
                    : String(localized: "\(DS.secondaryGesture) anything in All to move it here.")
            case .voice:
                return String(localized: "Nothing recorded yet. Hold New to record.")
            case .all, .new:
                return String(localized: "Write or record a note.")
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
