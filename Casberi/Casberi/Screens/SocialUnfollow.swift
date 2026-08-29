import SwiftUI
import SwiftData

/// UNFOLLOWING, FROM THE BOOK (2026-08-29, prd §511).
///
/// **The hole this fills.** §498 made the address book the app's one people
/// surface and gave it the social half as EPHEMERAL rows — nothing written to
/// the ledger, nothing synced, so a forty-person starter pack cannot dump forty
/// entries into anybody's book. That rule is right and stands. What it left
/// behind is the mirror problem, reported as *"if someone follows the farcaster
/// starterpack, should all those people go into the address book? that would be
/// really annoying"*: because `AddressBook.entry(for:)` answers nil for these
/// keys, `isInBook` is false, and rename, note, group and remove are ALL gated
/// off by construction. So the book listed forty people whose posts were
/// already filling the feed and offered no verb for any of them — §83's dead
/// row, forty times.
///
/// **Why they are listed at all.** `BlueskyStarterPacks.followAll` calls
/// `BlueskyStore.add(contentsOf:)`, so a pack does not merely note forty names,
/// it WATCHES them: their posts are in the feed from that moment. Hiding the
/// rows would leave no screen in the app answering "who did that pack add", and
/// no way to prune it. The row is not clutter standing for nothing; it is the
/// roster.
///
/// **One act, not two.** The row IS the watch — there is no second fact to
/// keep — so unfollowing drops the watch, which drops the row, which drops the
/// posts. Anything else rebuilds the two-lists problem §511 exists to remove
/// one population over: a "remove from book" that leaves the feed alone would
/// be the same delete-that-failed reading the wallet roster was reported for.
@MainActor
enum SocialUnfollow {

    /// Stop following every social account this row stands for.
    ///
    /// **The prune is `HandleBridge.removeName`, never a copy of it.** That is
    /// §286's path — "if you unfollow something it shouldn't show in your
    /// corpus" — and it carries three things a second implementation would get
    /// subtly wrong: Nostr's identity is resolved to its pubkey BEFORE the
    /// store mutates, the remaining topics are read so a post explained by a
    /// channel you still follow survives, and `SocialTopics.pruneAuthor` keeps
    /// the `socialContext` exemption that stops a liked stranger's post being
    /// taken as collateral.
    ///
    /// A folded person can carry several accounts (§498), so this acts on all
    /// of them and the sentence says how many when it is more than one.
    static func perform(_ entry: AddressBook.Entry,
                        context: ModelContext,
                        chrome: ShellChrome) {
        let pairs = AddressBookPeople.unfollowable(entry)
        guard !pairs.isEmpty else { return }
        DSHaptic.tap()
        for pair in pairs {
            HandleBridge(rawValue: pair.source)?.removeName(pair.handle, context: context)
        }
        let name = entry.name
        chrome.flash(pairs.count == 1
                     ? String(localized: "Unfollowed \(name) · their posts are out of your feed")
                     : String(localized: "Unfollowed \(name) on \(pairs.count) networks"),
                     action: .init(label: String(localized: "Undo")) {
                         undo(pairs)
                     },
                     seconds: 4)
    }

    /// Follows them again.
    ///
    /// It restores the WATCH and not the posts: the prune deleted rows out of
    /// the corpus, and the next sweep goes and gets them back from the network
    /// they came from. Nothing here claims otherwise — the same honesty
    /// `WalletUnwatch.undo` owes.
    static func undo(_ pairs: [(source: String, handle: String)]) {
        for pair in pairs {
            HandleBridge(rawValue: pair.source)?.addName(pair.handle)
        }
        DSHaptic.success()
    }
}
