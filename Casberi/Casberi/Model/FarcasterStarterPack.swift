import Foundation

/// A hand-picked Farcaster follow list, followed in one tap (2026-08-08) —
/// the Farcaster analog of `BlueskyStarterPacks`, and unlike it, PINNED in
/// code rather than fetched. Measured 2026-08-08: Farcaster's client API
/// starter-pack endpoints (browse/search/discover) all answered "Authentication
/// required" keylessly, and a by-id read had no real pack id to verify the
/// member payload shape against — so there's no honest way to mirror
/// Bluesky's search-a-pack flow. What's keyless and proven is what
/// `FarcasterIngest` already rides everywhere else: `userNameProofByName`
/// (name → fid) and `userDataByFid` (fid → face/name/bio) against the public
/// Snapchain node. A pinned list needs neither a browse endpoint nor an
/// account — it's this app's own curated set, offered the same way a Bluesky
/// pack is: see the faces, follow them all, one tap.
///
/// Every fid below was resolved live against `snap.farcaster.xyz:3381` on
/// 2026-08-08 (140/140 resolved, zero failures) — pinning the fid alongside
/// the username saves the first sync's per-account name→fid lookup, the same
/// saving `SocialBridge.watch(_:source:)` banks for a follow-graph import. A
/// username that later renames or deletes just fails its `profile(fid:)`
/// read at display time and drops out of the face grid silently — the same
/// fail-safe rule every keyless bridge in this codebase follows; nothing
/// here can 400 or crash on a stale entry.
enum FarcasterStarterPack {
    /// (username, fid) — username is what lands in `FarcasterStore`, fid is
    /// what skips the resolve. Both required for `add(contentsOf:)`, which
    /// takes `fid: Int?` but is never handed nil here.
    static let people: [(username: String, fid: Int)] = [
        ("jihad", 114),
        ("rish", 194),
        ("markus", 276),
        ("vrypan.eth", 280),
        ("corbin.eth", 358),
        ("brianjckim", 426),
        ("j4ck.eth", 431),
        ("dfern.eth", 453),
        ("cameron", 617),
        ("ivy", 1137),
        ("triumph", 1180),
        ("july", 1287),
        ("cassie", 1325),
        ("avichalp.eth", 1349),
        ("bias", 1355),
        ("stephancill", 1689),
        ("jayce", 1890),
        ("boscolo.eth", 1898),
        ("thatalexpalmer.eth", 1996),
        ("jacopo.eth", 2007),
        ("rubinovitz", 2112),
        ("kenny", 2210),
        ("commstark", 2211),
        ("4484.eth", 2420),
        ("grunt", 2441),
        ("depatchedmode", 2600),
        ("stevedv.eth", 2745),
        ("michaelx404.eth", 2755),
        ("18kgoldsouvenir.eth", 2785),
        ("garrett", 2802),
        ("ghostlinkz.eth", 3115),
        ("haole", 3346),
        ("horsefacts.eth", 3621),
        ("androidsixteen.eth", 3635),
        ("darrylyeo", 3854),
        ("seb", 3973),
        ("awkquarian", 4027),
        ("kmacb.eth", 4163),
        ("maurelian.eth", 4179),
        ("m0nt0y4", 4275),
        ("tricil.eth", 4294),
        ("amado", 4368),
        ("resipsa", 4375),
        ("gigamesh", 4378),
        ("keccers.eth", 4407),
        ("deployer", 4482),
        ("geoffgolberg", 4528),
        ("bytebot", 4703),
        ("logonaut.eth", 4715),
        ("trish", 4877),
        ("mc", 4904),
        ("mxjxn", 4905),
        ("robhardy.eth", 5467),
        ("shazow.eth", 5694),
        ("timdaub.eth", 5708),
        ("flick", 6097),
        ("typeof.eth", 6162),
        ("mattlee", 6591),
        ("king", 6596),
        ("frdysk", 6622),
        ("aviationdoctor.eth", 7237),
        ("riotgoools", 7258),
        ("pierrepauze", 7692),
        ("royalaid", 7715),
        ("klusya", 7992),
        ("ahn.eth", 8004),
        ("jamco.eth", 8173),
        ("eriks", 8447),
        ("ellis", 8911),
        ("tomato.eth", 8949),
        ("tinyrainboot", 9218),
        ("ispeaknerd.eth", 9391),
        ("katekornish", 10081),
        ("zoo", 10215),
        ("ds8", 11124),
        ("yesyes", 11448),
        ("jrf", 11528),
        ("mjc716", 11599),
        ("adam-", 11770),
        ("ilannnnnnnnkatin", 12400),
        ("sadtrombone.eth", 12457),
        ("pjc", 12567),
        ("naomiii", 13077),
        ("rev-morwen.eth", 13437),
        ("phimarhal", 13577),
        ("entropybender", 13659),
        ("sayo", 14176),
        ("purp", 14364),
        ("eirrann.eth", 14885),
        ("jpfraneto", 16098),
        ("netopwibby.eth", 16152),
        ("metaend.eth", 17940),
        ("fairygodmother", 18843),
        ("sinaver", 19129),
        ("itsbasil", 20384),
        ("topocount.eth", 20603),
        ("gramajo.eth", 21431),
        ("polymutex.eth", 188665),
        ("ruminations", 190000),
        ("greyseymour", 195091),
        ("smokingfrog.eth", 199989),
        ("jarrettr", 204221),
        ("blankspace", 210698),
        ("hamud", 212233),
        ("grit", 227886),
        ("sinusoidalsnail", 236727),
        ("downshift.eth", 243719),
        ("sartocrates", 248216),
        ("agust", 253127),
        ("catch0x22.eth", 256931),
        ("swim", 268455),
        ("nickysap", 269091),
        ("knny", 271142),
        ("hyp", 271878),
        ("jonathanmccallum", 276695),
        ("alinaferry", 282672),
        ("reneecampbell", 283144),
        ("terrybain", 308588),
        ("capn", 318589),
        ("maryams.eth", 326765),
        ("trupty", 347050),
        ("joshisdead.eth", 350139),
        ("chasesommer", 375245),
        ("nfthreat.eth", 378176),
        ("lovejoy", 380950),
        ("arseniy.eth", 386390),
        ("olystuart", 436728),
        ("zeni.eth", 446697),
        ("quantum-co", 461587),
        ("swampnet", 471228),
        ("catfacts.eth", 477126),
        ("patriciaxlee.eth", 719715),
        ("kentb", 861700),
        ("bertwurst.eth", 864405),
        ("fireog", 939438),
        ("rbthreek.base.eth", 1006215),
        ("ich-bin-abe", 1019113),
        ("jeff-xyz", 1045847),
        ("xr0am-", 1085549),
        ("y8t", 1093617),
    ]

    struct Member: Identifiable, Equatable {
        let username: String
        var id: String { username }
        let fid: Int
        let displayName: String?
        let avatarURL: String?
    }

    /// Hydrates every pinned entry's face — `FarcasterIngest.profile(fid:)`
    /// a few at a time, the same `maxConcurrent` shape `prefetchProfiles`
    /// already uses for a batch of authors. A profile read that fails
    /// (deleted account, an unreachable node) still returns a Member — the
    /// username and fid are pinned, only the face is best-effort — so the
    /// grid never loses someone over a flaky read the way it would if a nil
    /// profile were treated as a nil Member.
    @MainActor
    static func members() async -> [Member] {
        await IngestSupport.boundedGather(people, maxConcurrent: 6) { person in
            let profile = await FarcasterIngest.profile(fid: person.fid)
            return Member(username: person.username, fid: person.fid,
                          displayName: profile?.displayName, avatarURL: profile?.avatarURL)
        }
    }

    /// Follows every pinned person at once — `FarcasterStore.add(contentsOf:)`,
    /// the same batched-persist-once path the full follow-graph import uses.
    /// Returns how many were new (picking a pack you'd already partly
    /// followed only reports the delta, the follow-import's own rule).
    ///
    /// Fires a delight moment (the `BlueskyStarterPacks.followAll` pattern)
    /// only when at least one person was actually new — re-opening a pack
    /// you've already followed says nothing.
    @discardableResult
    @MainActor
    static func followAll() -> Int {
        let n = FarcasterStore.shared.add(contentsOf: people.map { ($0.username, $0.fid) })
        if n > 0 {
            SourceMoments.shared.fire(String(localized: "Followed \(n) on Farcaster"), source: "Farcaster")
        }
        return n
    }
}
