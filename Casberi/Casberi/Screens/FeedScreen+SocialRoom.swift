import SwiftUI

// MARK: - Social (prd §1068, §1079; tiles §1086)

extension FeedScreen {
    /// Your own handles on the networks that read your inbound half: the
    /// accounts you marked as yours (§804), lower-cased, no `@`.
    var socialMyHandles: Set<String> {
        var out = Set<String>()
        for a in BlueskyStore.shared.accounts where a.mine { out.insert(SocialToYou.normalized(a.handle)) }
        return out
    }

    static func toYouRow(_ thing: Thing) -> SocialToYou.Row {
        SocialToYou.Row(source: thing.source, socialContext: thing.socialContext,
                        sourceRef: thing.sourceRef, title: thing.title, text: thing.postText)
    }

    /// The Social room: the newest thing in the box, All · You · Follow, the
    /// faces, then — in All — what is to you this week, then the days.
    ///
    /// **What is to you never drowns** (user: "if i follow the starterpack and
    /// also myself, i see all the things together so there may be lots of
    /// posts from people before i see the notifications"). All leads with the
    /// week's newest three rows addressed to you (`SocialToYou`), lifted out
    /// of their days so each stands once; To you is only those, every network.
    @ViewBuilder
    func socialRoomSections(_ visible: [Thing], nextEventID: UUID?, heroShown: Bool) -> some View {
        let mine = socialMyHandles
        let you = chrome.socialScope == .toYou
        let live = visible.live
        let toYou: [Thing] = you
            ? live.filter { SocialToYou.isToYou(Self.toYouRow($0), myHandles: mine) }
            : SocialToYou.leading(live.map { (Self.toYouRow($0), $0.capturedAt) },
                                  myHandles: mine, now: .now).map { live[$0] }
        let leadIDs = Set(toYou.map(\.id))
        // Threads fold before the days (prd §1079): a person's own run of
        // replies stands as one card.
        let folded: (heads: [Thing], byHeadID: [String: [Thing]]) =
            you ? (toYou, [:]) : foldThreadReplies(live.filter { !leadIDs.contains($0.id) })
        let heads = folded.heads
        let replies = folded.byHeadID
        let days = chronoDays(heads)
        let cover: Thing? = {
            guard !heroShown else { return nil }
            if you { return toYou.first }
            // The box is the newest thing (every room's rule): a row to you
            // that is newer than every post takes it, and leaves the list.
            let newest = live.first
            if let newest, leadIDs.contains(newest.id) { return newest }
            guard let id = ledeThingID(in: days) else { return nil }
            return heads.first { $0.id == id }
        }()
        if let cover {
            Section { ledeListRow(cover) }
        } else if !heroShown {
            Section {
                if you {
                    emptyLeadRow(headline: DSProse.text("Nothing to you yet"),
                                 words: Text("Replies, mentions and new followers land here"))
                } else {
                    emptyLeadRow(headline: DSProse.text("Nothing yet"),
                                 words: Text("Posts from the people you follow land here"))
                }
            }
        }
        Section {
            DSScopeTiles(sections: SocialScope.allCases, active: chrome.socialScope,
                         attention: [], verbs: [.follow]) { picked in
                if picked.isVerb {
                    feedSheet = .socialFollow
                    return
                }
                withAnimation(DS.Motion.standard) { chrome.socialScope = picked }
            }
            .feedRowBackground()
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.inset,
                                      bottom: DSRoomChassis.leadGap,
                                      trailing: DSRoomChassis.inset))
            #if DEBUG
            .task { socialProbe() }
            #endif
        }
        roomScopeSection
        if you {
            groupedSections(liftingCover(days, id: cover?.id), nextEventID: nextEventID)
        } else {
            let leading = toYou.filter { $0.id != cover?.id }
            if !leading.isEmpty {
                // Named by what it is, not by a time (prd §740).
                groupedSections([(String(localized: "To you"), leading)],
                                nextEventID: nextEventID, dated: false)
            }
            groupedSections(liftingCover(days, id: cover?.id), nextEventID: nextEventID,
                            boundary: boundaryThingID(in: days), replies: replies)
        }
    }

    #if DEBUG
    /// `-socialScope toYou|follow` — land on To you, or raise Follow, at mount
    /// (prd §1086; NSLogs `socialScope:`). Once per launch.
    private func socialProbe() {
        guard !Self.socialProbed,
              let raw = UserDefaults.standard.string(forKey: "socialScope"),
              let scope = SocialScope(rawValue: raw) else { return }
        Self.socialProbed = true
        NSLog("[Casberi] socialScope: %@", raw)
        if scope.isVerb { feedSheet = .socialFollow } else { chrome.socialScope = scope }
    }
    #endif
}
