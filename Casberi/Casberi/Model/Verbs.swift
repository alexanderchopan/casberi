import SwiftUI
import UIKit
import EventKit

/// Verb derivation — verbs derive; menus die (brief §12). A thing's verbs come
/// from kind × source × bridge state, capped at three. "Open shortcut" died
/// with the platform call; App Intents hand-offs replace it (rung 2: the
/// hand-off IS the write, gated by ask-before-acting).
struct Verb: Identifiable {
    enum Action {
        case openURL(URL)             // read hand-off: opens the source app
        case addToCalendar            // write: EKEvent (confirms first)
        case addToReminders           // write: EKReminder (confirms first)
        case copyText                 // write to pasteboard
        case markDone                 // rung 1 mark
        case approve                  // S10: the person's yes — IS the consent
        case deny                     // S10: the person's no
        case translate                // read: system Translation sheet over the thing's own text
        case viewImage                // read: the picture itself, full screen and zoomable
        case showInFiles              // read hand-off: the Files app, at the folder this file is in
        /// The address card for one of YOUR watched wallets (prd §736) — the
        /// only destination in this enum that never leaves the app, and the
        /// reason it is a case rather than a `.openURL`: the place a wallet
        /// row comes from is a screen Casberi draws, not a page anyone
        /// publishes.
        case openAddress(String)
    }
    let label: String
    let icon: String
    let action: Action
    /// Nothing in this app writes into another app any more (2026-08-02 — see
    /// `HandOff`), so every verb is a read or a hand-off and none of them needs
    /// a confirmation. Kept as a constant rather than deleted: the gate it
    /// feeds is the thing that made "ask before acting" mechanical, and a verb
    /// that ever DID write again should have to flip this deliberately.
    var isWrite: Bool { false }
    /// Compact form for swipe buttons.
    var shortLabel: String {
        switch action {
        case .openURL:        return "Open"
        case .addToCalendar:  return "Calendar"
        case .addToReminders: return "Remind"
        case .copyText:       return "Copy"
        case .markDone:       return "Done"
        case .approve:        return "Approve"
        case .deny:           return "Deny"
        case .translate:      return "Translate"
        case .viewImage:      return "Zoom"
        case .showInFiles:    return "Files"
        case .openAddress:    return "Wallet"
        }
    }
    var id: String { label }
}

enum VerbDerivation {

    /// `NSDataDetector` loads linguistic data on construction, so building one
    /// per call is expensive — and `verbs(for:)` runs twice per visible feed
    /// row (leading + trailing swipeActions) and once per Home child. Built
    /// once and reused; the detectors are thread-safe for concurrent matching.
    private static let addressDetector =
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue)
    private static let phoneDetector =
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue)

    /// The cap-three rule: primary kind verb, then the source hand-off, then
    /// one utility. Reads pass; writes confirm.
    static func verbs(for thing: Thing) -> [Verb] {
        var out: [Verb] = []

        // 1 — the kind's primary verb.
        switch thing.kind {
        case .approval:
            // The thing IS the ask (S10) — its verbs are the answer. No
            // confirm dialog rides these: approving is the consent.
            return [Verb(label: "Approve", icon: "checkmark.circle", action: .approve),
                    Verb(label: "Deny", icon: "xmark.circle", action: .deny)]
        case .event:
            if thing.source == "Calendar" {
                // Gated 2026-08-14 (App Store review 2.1(a), Mac build: "your
                // app does not provide further action after we click on
                // Calendar button"). `calshow:` is always answerable on iOS
                // because Calendar ships with it, so this read was true there
                // and only there; on Mac Catalyst nothing claims the scheme
                // and the disc did nothing at all. An event ALREADY in
                // Calendar gets no fallback — "Send to Calendar" would write
                // a second copy of the event we read from it — so the verb
                // drops and the row keeps its other discs.
                if HandOffState.installedSchemes.contains("calshow") {
                    out.append(Verb(label: "Open in Calendar", icon: "calendar",
                                    action: .openURL(URL(string: "calshow://")!)))
                }
            } else if thing.source != VibenetIdentity.source, thing.source != PrivyHomeFeed.source,
                      thing.source != SplitsShape.source {
                // Not a hand-off — EventKit writes into the local store, which
                // works with no Calendar app present. Ungated on purpose for
                // every OTHER `.event` source (a workout, a HomeKit-scheduled
                // moment) — those are real-world moments a calendar entry
                // legitimately describes. A key authorized or revoked on a
                // devnet address is not: "Send to Calendar" would write a
                // blockchain state change into the person's real calendar as
                // though it were an appointment (2026-08-23, reported
                // alongside the "on your calendar" copy bug above — same
                // root cause, this file's `.event` default written for a
                // real calendar and never re-checked against a source that
                // borrowed the kind for its clock alone).
                out.append(Verb(label: "Send to Calendar", icon: "calendar.badge.plus",
                                action: .addToCalendar))
            }
            if thing.source == VibenetIdentity.source,
               // `content` is non-optional on `Thing` — one bare `URL(string:)`
               // (fixed in passing by the §462 session; the optional bind was a
               // compile error).
               let url = URL(string: thing.content),
               url.scheme == "https" {
                // The one door this row has always deserved. Every vibenet
                // event stamps its explorer permalink on `content` at landing
                // time, and NOTHING could reach it: `ThingContentView`'s bare
                // link body is scoped to `.transaction`, the `hasSite` spec
                // row wants a `.link` kind, and `walletVerbs` requires a money
                // receipt — so the app stored a URL for every key change on
                // chain and offered no way to open it. A read, so it needs no
                // consent; the same hand-off an approval already makes to
                // Revoke.cash.
                out.append(Verb(label: "Open in the explorer", icon: "arrow.up.forward.app",
                                action: .openURL(url)))
            }
        case .reminder:
            // A real reminder (Reminders source) is READ-ONLY (ruling
            // 2026-07-25): its done-state mirrors the real list, so we never
            // offer to complete it here — a local mark would drift, then get
            // reverted by the authoritative refresh (the "fake status" the
            // design law bans). Completing it is a hand-off to Reminders,
            // added by the source-hand-off step below. A reminder captured
            // elsewhere can still be added to the real list.
            if thing.source != "Reminders" {
                out.append(Verb(label: "Send to Reminders", icon: "checklist",
                                action: .addToReminders))
            }
            if let v = externalVerb(for: thing, apps: [.todoist]) { out.append(v) }
        case .link:
            // Music rows open the exact track in their app — the stored content
            // is a music.apple.com / open.spotify.com universal link. Named and
            // iconed by the app (like "Open in Calendar"), with the app scheme
            // as a fallback for a library play that carries no per-track URL, so
            // every music row can hand off the way events and items do (user,
            // 2026-07-13).
            if thing.source == "Apple Music" {
                if let url = Capture.detectURL(in: thing.content) ?? sourceURL(thing.source) {
                    out.append(Verb(label: "Open in \(thing.source)",
                                    icon: "music.note", action: .openURL(url)))
                }
            } else if thing.source == "YouTube",
                      let video = YouTubeShorts.videoID(in: thing.content),
                      HandOffState.installedSchemes.contains("youtube"),
                      let app = URL(string: "youtube://www.youtube.com/watch?v=\(video)") {
                // Watch it in the app rather than the browser (2026-08-06).
                //
                // Gated on the scheme, so it is never a disc that does
                // nothing — the screenshot verb's rule, and for the same
                // reason: an unclaimed scheme is refused ASYNCHRONOUSLY by
                // LaunchServices and neither `UIApplication.open`'s completion
                // nor SwiftUI's `openURL` reports it (measured 2026-07-16 for
                // `wc:`). Without the app installed the row keeps "Open link"
                // below, which is the right door then.
                //
                // The PATH grammar is unmeasured — no device here has the
                // YouTube app — and it fails safe: YouTube claims the scheme
                // (that is what the gate proves), so the worst case is its
                // home screen instead of this video, which is exactly the
                // promise the label makes and no more. The video id is
                // validated to YouTube's own 11-character shape before it is
                // interpolated.
                out.append(Verb(label: "Open in YouTube", icon: "play.rectangle",
                                action: .openURL(app)))
                if let web = Capture.detectURL(in: thing.content) {
                    out.append(Verb(label: "Open link", icon: "safari", action: .openURL(web)))
                }
            } else if let url = Capture.detectURL(in: thing.content.isEmpty ? thing.title : thing.content) {
                out.append(Verb(label: "Open link", icon: "safari", action: .openURL(url)))
            }
        case .product:
            // A product opens on the store's own page — the permalink stored in
            // content. Read-only hand-off: Casberi never checks out.
            if let url = Capture.detectURL(in: thing.content.isEmpty ? thing.title : thing.content) {
                out.append(Verb(label: "Open in store", icon: "bag", action: .openURL(url)))
            }
        case .transaction:
            // The block explorer — the record's own public page (2026-08-12).
            //
            // Every onchain seat stores that permalink as the row's `content`,
            // and until now only the STAGE layout offered it (`walletVerbs` on
            // a Sent/Received/Moved/Swapped sheet). Every other wallet row — a
            // mint, a card spend, a DeFi move — printed the 66-character URL
            // as its body and had no door at all: the one thing you can do
            // with a transaction was the one thing the sheet didn't offer
            // (user, 2026-08-12).
            //
            // "Explorer", not "Open" — the disc's glyph already says it opens
            // something; the word's job is to say WHERE you land (the same
            // ruling `walletVerbs` took on 2026-08-04). It says that word only
            // when the link really is an explorer, matched against the same
            // measured prefixes this app WROTE the link from — a
            // `.transaction` from a seat whose permalink points elsewhere gets
            // the `.link` kind's honest "Open link" rather than a word naming
            // a place it doesn't go.
            //
            // A token approval is a `.transaction` too, and its permalink is
            // NOT an explorer — `WalletApprovals` stores the wallet's
            // Revoke.cash page, the place you go to take the grant back. So it
            // says that (2026-08-12, user ruling), which is the same
            // where-you-land rule one step more specific. It names the
            // DESTINATION, never the outcome: "Revoke" would claim this app
            // revokes something, and it does not — the sheet's prepare card
            // (prd §112) reads and previews, and the signature always happens
            // elsewhere.
            if let url = Capture.detectURL(in: thing.content) {
                let isExplorer = WalletIngest.chainName(forContent: thing.content) != nil
                let host = url.host()?.lowercased() ?? ""
                let isRevoke = host == "revoke.cash" || host.hasSuffix(".revoke.cash")
                // Hegotá's devnet explorer isn't in `WalletIngest.allChains`
                // — that table drives the Zerion/Alchemy pipelines a devnet
                // rides none of — so `isExplorer` above reads false for it
                // and every Hegotá receipt (a send, a faucet claim) named its
                // own permalink the generic "Open link". Matched against the
                // exact prefix `HegotaSend.landReceipt` wrote the link from,
                // the same discipline `chainName(forContent:)` uses for
                // every other chain (user: "better if we write hegota
                // explorer as the link").
                let isHegota = thing.content.hasPrefix(HegotaIdentity.explorer)
                let label = isRevoke ? "Revoke.cash"
                    : isHegota ? "Hegotá Explorer"
                    : isExplorer ? "Explorer" : "Open link"
                out.append(Verb(label: label,
                                icon: isExplorer || isRevoke || isHegota ? "arrow.up.right" : "safari",
                                action: .openURL(url)))
            }
            // A World ID grant's door is where you claim the next one (prd
            // §792) — World App's grants screen, named by where it lands.
            // Gated on the counterparty World's own grant contract names as its
            // holder (so no other WLD row grows it) AND on World App answering
            // its scheme here, because an unclaimed scheme opens nothing.
            if thing.source == "Wallet",
               WalletIngest.isWorldGrantHolder(thing.counterpartyAddress),
               HandOffState.installedSchemes.contains("worldapp") {
                out.append(Verb(label: "World App", icon: "arrow.up.right",
                                action: .openURL(WalletIngest.worldAppGrantsLink)))
            }
            // WHICH WALLET THIS CAME OUT OF, as a door (2026-09-15, prd §736).
            //
            // It replaces the spec table's "From — in Main". That row was the
            // last one in the table still saying something true about THIS
            // thing rather than about the app, and it was a label: a person
            // watching several wallets could read which one a card spend or a
            // DeFi move belonged to and had no way to go there. The stage
            // sheets have had that door since §369 (the receipt's subject face
            // opens the address card); a mint, a spend or a DeFi move gets no
            // stage, so it had the fact and no door — which is the §408 shape
            // exactly, one kind over.
            //
            // The WORD is the wallet's own name, following `walletVerbs`'
            // "Explorer" ruling (2026-08-04): the glyph says it opens
            // something, the word's job is to say where you land. So the
            // sentence the deleted row made — "this came from Main" — is now
            // the button that goes to Main.
            //
            // `displayName(forStored:)` is the gate as well as the word: it
            // carries the ENS/SNS-vs-hex matching (a name-watched wallet lands
            // its things stamped with the resolved hex, so a raw compare
            // misses every one) and answers nil for an address that is not a
            // watched wallet or a row from before `walletAddress` existed —
            // so an unnamed stranger's transaction grows no disc rather than
            // one onto a card about nobody.
            //
            // A store read inside this function, which runs off the main actor
            // in GenUI composition: the `ObsidianStore.shared.vaultName`
            // precedent below, and the same grade — an in-memory scan of a
            // watch list capped in the single digits, never the disk read the
            // Files arm's own comment refuses.
            if let stored = thing.walletAddress,
               let name = WalletStore.shared.displayName(forStored: stored) {
                out.append(Verb(label: WalletStore.isAutoName(name, for: stored)
                                    ? "Wallet \(name)" : name,
                                icon: "wallet.bifold",
                                action: .openAddress(stored)))
            }
        case .screenshot:
            // The picture itself, full screen and zoomable, IN the app
            // (2026-08-02 — user: tapping Photos "doesn't go to the Photos app
            // or actual photo").
            //
            // "Open in Photos" was the only verb here, and it could never do
            // what its name promised. iOS publishes no URL that opens a
            // SPECIFIC asset, so `photos-redirect://` lands on the Photos app's
            // root at best; and when nothing claims that scheme the tap does
            // nothing at all, silently, because neither `UIApplication.open`'s
            // completion nor SwiftUI's `openURL` reports a refusal (the same
            // blindness the WalletConnect `wc:` read paid for — see the
            // measured note in CLAUDE.md). A disc that reads live and is inert
            // is the dead control the honesty rule bans.
            //
            // The app already holds the pixels — the corpus's own healed copy
            // and the asset behind it — so the photo opens where it cannot
            // fail. `sourceRef` is the cheap gate: it's a plain string column
            // every real screenshot carries, and reading `previewImageData`
            // here instead would fault an externalStorage blob per row, in a
            // function the feed already calls from a non-escaping context-menu
            // builder (prd §260).
            if thing.sourceRef != nil {
                out.append(Verb(label: "Zoom", icon: "arrow.up.left.and.arrow.down.right",
                                action: .viewImage))
            }
            // The hand-off stays for the people who want the library — but only
            // when something actually claims the scheme, so it can't be a disc
            // that does nothing. It opens the Photos app, never this photo, and
            // its label promises only that.
            if HandOffState.installedSchemes.contains("photos-redirect"),
               let url = URL(string: "photos-redirect://") {
                out.append(Verb(label: "Open in Photos", icon: "photo", action: .openURL(url)))
            }
        case .file:
            // A folder-picked image gets the same Zoom the screenshot above
            // does (2026-08-12, prd §365). It had NO case here at all, so a
            // Files/Dropbox picture drew its pixels in the sheet and nothing
            // in the app could open them — the same bytes as a screenshot,
            // one bridge over, behaving differently.
            //
            // The gate is a string test on the ref, deliberately: this
            // function runs off the main actor inside GenUI composition and is
            // called per row by the feed's context-menu builder (prd §260), so
            // reading `previewImageData` here would fault an externalStorage
            // blob per row. `FilesIngest.isStoredPicture` says the same thing
            // the screenshot branch's `sourceRef != nil` says, one level more
            // precisely — and the viewer falls back to the stored bytes when
            // the ref names no asset, so an image whose heal hasn't produced a
            // thumbnail yet opens to the loader rather than to nothing.
            if FilesIngest.isStoredPicture(thing.sourceRef) {
                out.append(Verb(label: "Zoom", icon: "arrow.up.left.and.arrow.down.right",
                                action: .viewImage))
            }
            // The folder it is saved in, in the Files app (2026-08-19, prd
            // §408 — user: "would be great to be able to press here and it
            // takes you to folder where the file is saved").
            //
            // A folder-picked file had NO door at all: the corpus held the
            // row, the sheet drew it, and the file itself — sitting in a
            // folder the person picked, two taps away in another app — was
            // reachable from Casberi only by remembering where it was. Every
            // other bridge in this app whose rows exist somewhere else offers
            // that door (a cast's thread, a note's vault, a transaction's
            // explorer); this was the one that didn't.
            //
            // Scoped to the Files source, not to the kind: Dropbox lands
            // `.file` rows too and its bytes are not on this device, so the
            // Files app has nothing to show for one. Gated on the scheme so it
            // is never a disc that does nothing — the screenshot verb's rule,
            // and the reason is the same measured one: an unclaimed scheme is
            // refused ASYNCHRONOUSLY by LaunchServices and neither
            // `UIApplication.open`'s completion nor SwiftUI's `openURL`
            // reports it. On Mac Catalyst nothing claims it, so the verb
            // simply isn't there.
            //
            // The URL is built at TAP time, not here: this function runs off
            // the main actor inside GenUI composition and is called per row by
            // the feed's context-menu builder (prd §260), while resolving the
            // bookmark is a `FilesStore` read. The gate is three string tests
            // and a set lookup, which is what that context can afford.
            //
            // THE WORD IS THE FOLDER since 2026-09-15 (prd §736): "Show in
            // Receipts", not "Show in Files". `walletVerbs`' "Explorer" ruling
            // (2026-08-04) one step more specific — the glyph says it opens
            // something, the word says where you land — and it is what lets
            // the spec table's "From — in Receipts" row be deleted rather than
            // merely wired up: the fact that row carried is the only thing it
            // had, and the button now carries it.
            //
            // `FilesStore.shared.folderName` is an in-memory string (the
            // `ObsidianStore.shared.vaultName` read below is the precedent),
            // never `folderURL()` — resolving the bookmark is the disk read
            // this function's own comment above refuses. It falls back to the
            // app's name when the folder has none, so the disc always says a
            // real destination.
            if thing.source == "Files",
               FilesLocation.components(ref: thing.sourceRef) != nil,
               HandOffState.installedSchemes.contains(FilesLocation.revealScheme) {
                let folder = FilesLocation.folderName(
                    ref: thing.sourceRef, connectedFolder: FilesStore.shared.folderName)
                out.append(Verb(label: folder.map { "Show in \($0)" } ?? "Show in Files",
                                icon: "folder", action: .showInFiles))
            }
        case .note:
            // A note's next action: it becomes a reminder (S4 — captures
            // become outcomes). The write confirms; copy follows.
            //
            // NOT FOR AN IMPORTED POST (2026-08-06). S4's premise was that
            // every `.note` in the corpus is something the person typed,
            // pasted or dictated — a capture, waiting to become an outcome.
            // The import rooms retired that premise without anyone noticing:
            // X posts and replies, Instagram captions and comments, TikTok
            // comments all land as `.note`, and none of them is a capture.
            // They are published writing, most of it years old and some of it
            // somebody else's, so "what will you do about this" is the wrong
            // question to put first — reported against an X post from an
            // archive ("why is a Reminders button on a Twitter thing sheet?").
            //
            // Scoped to `bulkImportSources` rather than to a kind or a source
            // list of its own: that set already means exactly "rows that came
            // in by the archive-load door", and it is what every other
            // aggregate over these rooms narrows by.
            // A vault note opens in the app that OWNS it (2026-08-06).
            //
            // Obsidian is the one source in this app whose rows the person also
            // has an editor for, and the corpus was a dead end: a note found
            // here could be read here and nowhere else, with the app that owns
            // it one tap away. Both halves of the URL are already stored — the
            // vault's folder name and the note's path inside it — so this
            // costs no field and no request.
            //
            // FIRST among this kind's verbs, because for a note it is the
            // strongest thing you can do with it, and gated on the scheme so
            // it is never a disc that does nothing (the screenshot verb's
            // rule: an unclaimed scheme is refused ASYNCHRONOUSLY by
            // LaunchServices and neither `UIApplication.open`'s completion nor
            // SwiftUI's `openURL` reports it). Without Obsidian installed the
            // note keeps the verbs below, which is the right set then.
            if thing.source == "Obsidian",
               HandOffState.installedSchemes.contains("obsidian"),
               let vault = ObsidianLink.openURL(vault: ObsidianStore.shared.vaultName,
                                                sourceRef: thing.sourceRef) {
                out.append(Verb(label: "Open in Obsidian", icon: "book.closed",
                                action: .openURL(vault)))
            }
            if !Corpus.bulkImportSources.contains(thing.source) {
                out.append(Verb(label: "Send to Reminders", icon: "checklist",
                                action: .addToReminders))
            }
            if let v = externalVerb(for: thing, apps: [.todoist]) { out.append(v) }
            out.append(Verb(label: "Copy text", icon: "doc.on.doc", action: .copyText))
            if !(thing.postText ?? thing.content).isEmpty {
                out.append(Verb(label: "Translate", icon: "character.bubble", action: .translate))
            }
        case .chat, .mail, .file, .voice:
            // A social post opens its own thread on the network — the specific
            // permalink (thing.content), so it lands on the cast, not the
            // network's front door. Prepended, so it survives the cap and the
            // generic "Open in <source>" hand-off below stands down.
            if thing.kind == .chat, SocialThread.isSocial(thing.source),
               let url = URL(string: thing.content), url.scheme?.hasPrefix("http") == true {
                out.append(Verb(label: "Open thread", icon: "bubble.left.and.bubble.right",
                                action: .openURL(url)))
            }
            out.append(Verb(label: "Copy text", icon: "doc.on.doc", action: .copyText))
            // The full body — a post's own words (postText), else whatever
            // the kind carries as its text (a transcript, a mail body).
            //
            // Mail defers its Translate to the very end of derivation (see
            // below) so the cap eats it first. Every other kind keeps it here.
            if thing.kind != .mail, !(thing.postText ?? thing.content).isEmpty {
                out.append(Verb(label: "Translate", icon: "character.bubble", action: .translate))
            }
        default:
            break
        }

        // 1b — a place leads with Directions. When the thing carries an
        // address or a maps link, routing to it is the most useful move —
        // prepend so it survives the cap. Apple Maps over the web URL, so it
        // opens even if the Maps app was removed (never a dead hand-off).
        // READ, never detect (PERF 2026-08-01, prd §260). These two were
        // `NSDataDetector` passes over the row's full text, run from a
        // non-escaping `.contextMenu` builder — i.e. per row, per render, in
        // every room, and ~21% of busy main-thread time while swiping. They are
        // stamped once by `VerbDetection.backfill` now and simply read here.
        // A thing not yet scanned (`detectedAt == nil`) offers neither verb
        // rather than scanning inline: a verb arriving a beat late is honest,
        // where a per-render scan was merely invisible.
        if let maps = thing.detectedPlace.flatMap(URL.init(string:)) {
            out.insert(Verb(label: "Directions", icon: "map", action: .openURL(maps)), at: 0)
        }

        // 1c — reach a person: call a detected number, email a detected address.
        if let tel = thing.detectedTel.flatMap(URL.init(string:)) {
            out.append(Verb(label: "Call", icon: "phone", action: .openURL(tel)))
        }
        if let mail = thing.detectedMailto.flatMap(URL.init(string:)) {
            out.append(Verb(label: thing.kind == .mail ? "Reply" : "Email",
                            icon: "envelope", action: .openURL(mail)))
        }

        // 2 — the source hand-off, when the source has an address.
        //
        // Gmail is the one source that offers it EVEN when a hand-off is
        // already present (user, 2026-08-02: "do it for gmail"). Every other
        // source stands down because its first hand-off opens the thing
        // itself — a cast's own thread, a track, a store page — so a second
        // one pointing at the app's front door adds nothing. Mail is the
        // opposite: the hand-off it usually gets is Reply, which opens a
        // COMPOSER, and the person who wants to read the mail where it lives
        // is left with no door at all. Which of the two a Gmail row happened
        // to get was decided by whether the sender header carried a bare
        // address or a display name (`mailtoURL`) — a coin flip, not a
        // ruling.
        //
        // 2a — THE MESSAGE, not the app (2026-09-15, prd §735).
        //
        // This block used to be a paragraph explaining why it could not exist:
        // "no iOS URL opens a specific email (`message://<Message-ID>` is
        // macOS Mail's, undocumented here, and mail things key on the IMAP UID
        // anyway)", and iCloud Mail therefore got no hand-off at all. Only the
        // last clause was true, and it was the work rather than the obstacle —
        // the UID is mailbox-local, so the door needed the `Message-ID`, which
        // `Thing.mailMessageID` now keeps. `MailLocation` carries the rest and
        // states what each half is measured to.
        //
        // Placed BEFORE `handsOffAlready` is read, so a mail that has this
        // door doesn't also get the front-door one below: two discs a
        // millimetre apart, one landing on the message and one on the inbox,
        // is the menu brief §12 bans — and the Gmail exception exists to
        // guarantee a door, which this already is.
        let mailDoor: URL? = thing.kind == .mail
            ? MailLocation.messageURL(source: thing.source,
                                      messageID: thing.mailMessageID,
                                      schemes: HandOffState.installedSchemes)
            : nil
        if let mailDoor, let app = MailLocation.appName(source: thing.source) {
            out.append(Verb(label: "Open in \(app)", icon: "envelope.open",
                            action: .openURL(mailDoor)))
        }

        // The front door, for everything else — and for a mail whose envelope
        // never carried a usable `Message-ID`. "Open in Gmail" is the whole
        // promise there, the same one "Open in Calendar" makes. iCloud Mail
        // still gets nothing on that path, because Apple publishes no scheme
        // that opens Mail's INBOX — `message:` opens a message or nothing, and
        // `mailto:` is a composer, so a disc that opens a blank draft while
        // claiming to open your mail would be the dead control §83 bans.
        let handsOffAlready = out.contains(where: {
            if case .openURL = $0.action { return true } else { return false }
        })
        if let url = sourceURL(thing.source),
           !handsOffAlready || (thing.source == "Gmail" && mailDoor == nil) {
            out.append(Verb(label: "Open in \(thing.source)", icon: "arrow.up.right",
                            action: .openURL(url)))
        }

        // 3 — a task verb for marked things. Reminders are excluded: their
        // done-state is read-only, mirrored from the real list (ruling
        // 2026-07-25), so "Mark done" would mark locally then get reverted.
        if thing.mark == .todo || thing.mark == .doing,
           thing.source != "Reminders",
           !out.contains(where: { $0.label == "Mark done" }) {
            out.append(Verb(label: "Mark done", icon: "checkmark.circle", action: .markDone))
        }

        // 4 — mail's Translate, last on purpose (2026-08-02). Mail is the one
        // kind that can carry five candidates — Directions off a signature's
        // street address, Copy, Reply, Open in Gmail, Translate — and the cap
        // takes four, so one of them has to lose. It's this one: Reply and
        // Open in Gmail are the two moves only THIS row can make, and a mail
        // with an address in its footer is exactly a mail from a real
        // correspondent, i.e. the case where reaching them matters most.
        // Translating is a generic utility over text the person can still
        // Copy, so it yields rather than costing them the door to their mail.
        if thing.kind == .mail, !(thing.postText ?? thing.content).isEmpty {
            out.append(Verb(label: "Translate", icon: "character.bubble", action: .translate))
        }

        // The cap (was three): a place-y or contactful thing can earn a fourth
        // hand-off, but no thing becomes a menu (brief §12).
        return Array(out.prefix(4))
    }

    /// Everything the three scans below read off a thing, as PLAIN VALUES.
    ///
    /// The scans never needed a `Thing` — they need text — but taking one
    /// pinned them to the main actor, which is where a SwiftData model has to
    /// be read. Pulling the reads out into this lets the expensive half run
    /// anywhere (2026-08-06, the same structural fix as
    /// `ScreenshotTopics.extract`, and for the same reason: these are the two
    /// `NSDataDetector` passes a device profile put at ~21% of busy
    /// main-thread time).
    struct Input: Sendable {
        /// What the address and phone scans read: the body, else the title.
        let text: String
        /// The mailto compose subject.
        let title: String
        /// A mail thing reads its sender and NEVER its body — the one place
        /// `mailtoURL` diverges from `text` (see its doc below). Both fields
        /// are needed: a mail thing whose envelope carried no address must
        /// answer nil, not fall through to scanning the body.
        let isMail: Bool
        let mailFrom: String?

        @MainActor init(_ thing: Thing) {
            text = thing.content.isEmpty ? thing.title : thing.content
            title = thing.title
            isMail = thing.kind == .mail
            mailFrom = thing.authorHandle
        }
    }

    /// What one pass over an `Input` found. Strings, not `URL`s, because that
    /// is what `Thing` stores and what crosses back.
    struct Detected: Sendable {
        let place: String?
        let tel: String?
        let mailto: String?
    }

    /// Scan a batch OFF the main actor — the whole point of `Input` existing.
    ///
    /// Batched rather than one row at a time so the hop is paid per batch, and
    /// returns a parallel array so the caller can `zip` it back onto the rows
    /// it came from — no `Thing`, and nothing else non-`Sendable`, crosses.
    /// The detectors are thread-safe for concurrent matching (see above).
    nonisolated static func detect(_ inputs: [Input]) async -> [Detected] {
        await Task.detached(priority: .utility) {
            inputs.map {
                Detected(place: placeURL(in: $0)?.absoluteString,
                         tel: telURL(in: $0)?.absoluteString,
                         mailto: mailtoURL(in: $0)?.absoluteString)
            }
        }.value
    }

    /// A place the thing points at, as an Apple Maps directions URL — or nil
    /// when there's no address to route to (the verb drops; no dead control).
    /// A maps/geo link passes straight through; otherwise a detected street
    /// address becomes the destination query.
    nonisolated static func placeURL(in input: Input) -> URL? {
        let text = input.text

        if let url = Capture.detectURL(in: text) {
            let host = url.host()?.lowercased() ?? ""
            if url.scheme == "geo"
                || host.contains("maps.apple.com")
                || host.contains("google.com/maps")
                || host.contains("maps.google")
                || host.contains("goo.gl/maps") {
                return url
            }
        }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = addressDetector?.firstMatch(in: text, range: range),
              let r = Range(match.range, in: text) else { return nil }
        var comps = URLComponents(string: "https://maps.apple.com/")
        comps?.queryItems = [URLQueryItem(name: "daddr", value: String(text[r]))]
        return comps?.url
    }

    /// A phone number in the thing → a tel: URL, else nil (the verb drops).
    nonisolated static func telURL(in input: Input) -> URL? {
        let text = input.text
        let range = NSRange(text.startIndex..., in: text)
        guard let number = phoneDetector?.firstMatch(in: text, range: range)?.phoneNumber else { return nil }
        let dialable = number.filter { $0.isNumber || $0 == "+" }
        return dialable.isEmpty ? nil : URL(string: "tel:\(dialable)")
    }

    /// An email address in the thing → a mailto: compose URL, else nil. Only
    /// fires when there's a real address to reach — never a blank composer.
    ///
    /// A mail thing's `content` is body text (2026-07-23), which rarely
    /// repeats the sender's own address — scanning it would either find
    /// nothing or (worse) latch onto some OTHER address mentioned in the
    /// body and offer to "reply" to the wrong person. `authorHandle` is the
    /// real sender, but the ENVELOPE parse prefers a display name over the
    /// raw address when the header carries one ("Jane Appleseed", no "@") —
    /// so this only fires for the addresses it can already see, same as
    /// before body text existed; it never guesses.
    nonisolated static func mailtoURL(in input: Input) -> URL? {
        let text: String
        if input.isMail {
            // A mail thing whose sender the envelope never carried answers
            // nil; scanning the body instead is the wrong-person guess above.
            guard let from = input.mailFrom else { return nil }
            text = from
        } else {
            text = input.text
        }
        guard let r = text.range(of: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
                                 options: [.regularExpression, .caseInsensitive]) else { return nil }
        var comps = URLComponents()
        comps.scheme = "mailto"
        comps.path = String(text[r])
        comps.queryItems = [URLQueryItem(name: "subject", value: input.title)]
        return comps.url
    }

    /// A third-party app a task-shaped thing can hand off to. The rule (user,
    /// 2026-07-12): ONLY apps the person already connected as a Casberi bridge
    /// — never an arbitrary popular app — and each must carry a documented
    /// create URL. Todoist is the one that qualifies today; the table grows as
    /// more connected bridges gain schemes.
    private enum ExternalApp {
        case todoist

        /// The catalog/bridge name, lowercased — matched against connected seats.
        var bridgeName: String { switch self { case .todoist: "todoist" } }
        var scheme: String { switch self { case .todoist: "todoist" } }
        var label: String { switch self { case .todoist: "Todoist" } }
        var icon: String { switch self { case .todoist: "checklist" } }

        func url(for thing: Thing) -> URL? {
            switch self {
            case .todoist:
                var c = URLComponents(string: "todoist://addtask")
                c?.queryItems = [URLQueryItem(name: "content", value: thing.title)]
                return c?.url
            }
        }
    }

    /// An "Add to …" hand-off for the first app that is BOTH a connected bridge
    /// and installed — else nil, so the verb only shows what the person chose
    /// and can actually reach. Reads cached snapshots (no UIApplication /
    /// BridgeStore here) so derivation runs off-main inside GenUI.
    private static func externalVerb(for thing: Thing, apps: [ExternalApp]) -> Verb? {
        for app in apps
        where HandOffState.connectedBridges.contains(app.bridgeName)
           && HandOffState.installedSchemes.contains(app.scheme) {
            guard let url = app.url(for: thing) else { continue }
            return Verb(label: "Add to \(app.label)", icon: app.icon, action: .openURL(url))
        }
        return nil
    }

    /// Where a source can be opened. Nil = no hand-off; the verb drops.
    private static func sourceURL(_ source: String) -> URL? {
        switch source.lowercased() {
        // Gated like every other hand-off here (2026-08-14, App Store review
        // 2.1(a) on the Mac build). Both schemes are always answerable on iOS
        // because Calendar and Reminders ship with it — which is exactly why
        // these two were the last left ungated — but on Mac Catalyst nothing
        // answers, so the disc appeared and did nothing at all.
        case "calendar":
            return HandOffState.installedSchemes.contains("calshow")
                ? URL(string: "calshow://") : nil
        case "reminders":
            return HandOffState.installedSchemes.contains("x-apple-reminderkit")
                ? URL(string: "x-apple-reminderkit://") : nil
        // Gated like the screenshot verb above (2026-08-02): an unclaimed
        // scheme opens nothing and reports nothing back, so this hand-off only
        // exists while something answers for it.
        case "photos":
            return HandOffState.installedSchemes.contains("photos-redirect")
                ? URL(string: "photos-redirect://") : nil
        // Gated like the screenshot verb (2026-08-02). It was ungated while it
        // only appeared for the rare Gmail row that had no Reply verb; now that
        // every Gmail row offers it, an ungated read would put a disc that
        // silently does nothing on every mail in the corpus for anyone reading
        // Gmail over IMAP without the Gmail app — which is most of them, since
        // the bridge signs in with an app-specific password, not the app.
        case "gmail":
            return HandOffState.installedSchemes.contains("googlegmail")
                ? URL(string: "googlegmail://") : nil
        // Gated 2026-08-14, with Calendar and for the same reason — these were
        // the last three ungated hand-offs, and all three are reachable from
        // the FURNISHED DEMO (it seeds ChatGPT, Spotify and Apple Music rows),
        // i.e. from exactly the walk an App Store reviewer takes. `chatgpt`
        // was already declared in LSApplicationQueriesSchemes but absent from
        // `candidates`, so it could never have been gated as written; the
        // other two were declared nowhere at all.
        case "chatgpt":
            return HandOffState.installedSchemes.contains("chatgpt")
                ? URL(string: "chatgpt://") : nil
        // Music apps — the per-track universal link opens the exact song; this
        // is the fallback that still opens the app for a URL-less library play.
        // A fallback that opens nothing is worse than no fallback: the row
        // keeps its other discs instead.
        case "apple music":
            return HandOffState.installedSchemes.contains("music")
                ? URL(string: "music://") : nil
        case "spotify":
            return HandOffState.installedSchemes.contains("spotify")
                ? URL(string: "spotify://") : nil
        // A practice day has no permalink — Duolingo publishes no page for
        // one — so the app itself is the whole hand-off, and gated like every
        // other: an unclaimed scheme is refused asynchronously while
        // reporting success, which renders as a disc that does nothing.
        case "duolingo":
            return HandOffState.installedSchemes.contains("duolingo")
                ? URL(string: "duolingo://") : nil
        case "safari":    return nil   // links open directly via Open link
        default:          return nil
        }
    }
}

/// Cached hand-off state, refreshed on the main actor each foreground.
/// `VerbDerivation` reads it off any thread — it's only ever written on main,
/// and a stale read just hides or shows one optional verb — so derivation
/// stays free of UIApplication / BridgeStore isolation and can run inside
/// off-main GenUI composition.
enum HandOffState {
    /// `nonisolated(unsafe)` previously let these Sets be written on the main
    /// actor while read from off-main GenUI composition with no protection at
    /// all — a genuine data race (Swift's `Set` isn't thread-safe), found in a
    /// 2026-07-21 audit. A lock is enough: writes are rare (once per
    /// foreground) and reads are simple `.contains` checks.
    private static let lock = NSLock()

    /// Custom URL schemes (from `LSApplicationQueriesSchemes`) that resolve to
    /// an installed app. A scheme not listed in Info.plist always reads absent,
    /// so the two must move together.
    private static var _installedSchemes: Set<String> = []
    static var installedSchemes: Set<String> {
        lock.lock(); defer { lock.unlock() }
        return _installedSchemes
    }
    /// Lowercased names of the bridges the person has connected — the gate for
    /// "Add to <app>" hand-offs (user ruling: bridge-tied, never arbitrary).
    private static var _connectedBridges: Set<String> = []
    static var connectedBridges: Set<String> {
        lock.lock(); defer { lock.unlock() }
        return _connectedBridges
    }

    /// `photos-redirect` joined the probe list on 2026-08-02: the Photos
    /// hand-off is the one verb here that is NOT tied to a connected bridge, so
    /// nothing else could tell whether it would open anything.
    /// `youtube` joined 2026-08-06, for the same reason as `photos-redirect`:
    /// the "Open in YouTube" verb is not tied to a connected bridge in the
    /// `externalVerb` sense (following a channel doesn't mean the app is
    /// installed), so nothing else could tell whether it would open anything.
    /// `obsidian` joined 2026-08-06. Same reason as the two above: connecting
    /// a vault means the person has a FOLDER, which on iOS says nothing about
    /// whether the Obsidian app is on this device — a vault synced from a Mac
    /// through iCloud Drive reads identically either way — so the bridge being
    /// connected could never have answered this.
    /// `calshow` and `x-apple-reminderkit` joined the list 2026-08-14, after
    /// App Store review rejected the Mac build under 2.1(a): "your app does
    /// not provide further action after we click on Calendar button". They
    /// were the last two hand-offs left ungated — every other one here was
    /// gated the day it was found to be a disc that does nothing, and these
    /// two were missed because Calendar and Reminders ship with iOS, so the
    /// scheme is always answerable THERE. Mac Catalyst is where that stops
    /// being true, and the reviewer's Mac is where it surfaced.
    /// `shareddocuments` joined 2026-08-19 with the Files hand-off (prd
    /// §408). Same reason as `obsidian`: connecting a folder says the person
    /// has a FOLDER, which says nothing about whether the Files app is on this
    /// device — and on Mac Catalyst nothing claims the scheme at all, which is
    /// the platform that turned the Calendar miss above into an App Store
    /// rejection.
    /// `message` joined 2026-09-15 with the mail door (prd §735), and is the
    /// `shareddocuments` case exactly: connecting a mailbox over IMAP says the
    /// person has an ADDRESS, which says nothing about whether Apple Mail is
    /// set up on this device — reading iCloud Mail entirely on the web is an
    /// ordinary way to live — and an unclaimed scheme is refused
    /// asynchronously while reporting success.
    /// `worldapp` joined 2026-09-16 with the World ID grant door (prd §792):
    /// watching a World App wallet says nothing about whether World App is on
    /// THIS phone — it may be somebody else's wallet, or read on a Mac.
    private static let candidates = ["todoist", "googlegmail", "photos-redirect",
                                     "youtube", "obsidian",
                                     "calshow", "x-apple-reminderkit",
                                     "chatgpt", "music", "spotify", "mobilenotes",
                                     "shareddocuments", "message", "duolingo",
                                     "worldapp"]

    #if DEBUG
    /// The same list, for `-photoVerbProbe`'s census. Exposed rather than
    /// duplicated so a scheme added above is covered by the probe the day it
    /// lands (the registry-drift rule this file's own hooks are held to).
    static var probeCandidates: [String] { candidates }
    #endif

    @MainActor static func refresh(connected: Set<String>) {
        let schemes = Set(candidates.filter {
            guard let url = URL(string: "\($0)://") else { return false }
            return UIApplication.shared.canOpenURL(url)
        })
        lock.lock()
        _installedSchemes = schemes
        _connectedBridges = connected
        lock.unlock()
    }
}

/// Hand-offs. Casberi COPIES and OPENS — it never writes into another app
/// (user ruling, restated 2026-08-02: "we shouldn't write to reminders it
/// should copy and open there"; originally 2026-07-16, "no matter what we
/// should jump, we don't write").
///
/// These two used to be the exception, and it was never a deliberate one. The
/// composer's Send-to chips have honoured the ruling since the day it was made
/// — copy where a URL can't carry the text, jump, and say so in the flash —
/// while the thing sheet's dial quietly built an `EKReminder`/`EKEvent` and
/// `store.save(…, commit: true)`'d it into the person's real list. Two
/// surfaces, opposite behaviour, one of them wrong. It surfaced from the far
/// end: the disc read "Reminders", a bare noun among Copy/Translate/Share, and
/// no honest word existed for it because the thing it did was the problem.
///
/// The permissions follow, and were checked rather than assumed:
/// `NSCalendarsWriteOnlyAccessUsageDescription` is DELETED, because after this
/// no code path requests calendar write access at all. The two FULL-access
/// keys stay — `ScheduleIngest` needs them to READ your events and reminders
/// in, which is the whole Calendar/Reminders bridge — but the Reminders string
/// was rewritten: it said "Casberi adds reminders to your list when you ask",
/// which as of today is a promise the app makes to the system and then
/// doesn't keep.
enum HandOff {

    static func addToCalendar(_ thing: Thing) async throws {
        // Build 256: a detached Task runs LATER than it was created, so this
        // row can already be deleted by the time this line does (prd §297).
        guard thing.isLive else { return }
        // The event's own time where it has one, so Calendar opens ON that day
        // rather than today — the same `calshow:` trick the composer's chip
        // uses, and the reason this passes a date at all.
        let date = thing.kind == .event ? thing.capturedAt : thing.dueAt
        let url = date.map { URL(string: "calshow:\(Int($0.timeIntervalSinceReferenceDate))") }
            ?? URL(string: "calshow://")
        try await jump(thing, to: url)
    }

    static func addToReminders(_ thing: Thing) async throws {
        try await jump(thing, to: URL(string: "x-apple-reminderkit://"))
    }

    /// Open the Files app at the folder a folder-picked file is saved in
    /// (2026-08-19, prd §408).
    ///
    /// NOT `jump`: that copies the thing's words first, because neither
    /// Calendar's nor Reminders' scheme can carry text and the clipboard is
    /// what makes those hops useful. Here the destination IS the whole verb —
    /// the folder is what was asked for — and quietly replacing the person's
    /// clipboard on the way is a side effect nothing on screen promised.
    ///
    /// The failure is worth a sentence rather than a silence: an unreachable
    /// folder means the bookmark stopped resolving (the folder was moved,
    /// renamed or unshared), which is a real thing the person can act on, and
    /// it is indistinguishable from a tap that did nothing.
    @MainActor
    static func showInFiles(_ thing: Thing) async throws {
        // Build 256: a detached Task runs LATER than it was created, so this
        // row can already be deleted by the time this line does (prd §297).
        guard thing.isLive else { return }
        guard let url = FilesIngest.revealURL(for: thing.sourceRef),
              UIApplication.shared.canOpenURL(url) else {
            throw HandOffError.folderUnreachable
        }
        guard await UIApplication.shared.open(url) else {
            throw HandOffError.folderUnreachable
        }
    }

    /// Open Calendar ON a date read out of a thing's own text — the hand-off
    /// half of `ScreenshotFacts` (prd §282, 2026-08-02). Same contract as
    /// `addToCalendar`: the words go on the clipboard FIRST and
    /// unconditionally, then Calendar opens on the day, and the person writes
    /// the event. Nothing here creates one — "We don't write" still holds, and
    /// a date read off a picture is exactly the input that shouldn't get an
    /// exception.
    @MainActor
    static func openCalendar(at date: Date, copying text: String) async throws {
        DSPasteboard.copy(text)
        let url = URL(string: "calshow:\(Int(date.timeIntervalSinceReferenceDate))")
        guard let url, UIApplication.shared.canOpenURL(url),
              await UIApplication.shared.open(url) else {
            throw HandOffError.unavailable
        }
    }

    /// Copy the thing's own words, then open the app. The copy happens FIRST
    /// and unconditionally: neither scheme can carry text, so the clipboard is
    /// the only thing that makes the jump useful, and a jump that succeeded
    /// with an empty clipboard would be the worse failure — the person lands in
    /// Reminders with nothing to paste and no way to know why.
    @MainActor
    private static func jump(_ thing: Thing, to url: URL?) async throws {
        // Build 256: a detached Task runs LATER than it was created, so this
        // row can already be deleted by the time this line does (prd §297).
        guard thing.isLive else { return }
        let text = thing.content.isEmpty ? thing.title : thing.content
        DSPasteboard.copy(text)
        guard let url, UIApplication.shared.canOpenURL(url) else {
            throw HandOffError.unavailable
        }
        guard await UIApplication.shared.open(url) else {
            throw HandOffError.unavailable
        }
    }

    enum HandOffError: LocalizedError {
        case unavailable
        case folderUnreachable
        var errorDescription: String? {
            switch self {
            case .unavailable:
                // The copy DID happen — say so, because it's the half the
                // person can still use.
                return String(localized: "Copied — couldn't open the app")
            case .folderUnreachable:
                // Nothing was copied on this path, so the sentence claims
                // nothing beyond what failed.
                return String(localized: "Couldn't open the folder in Files")
            }
        }
    }
}

// `PlaceWords` was HERE and is DELETED (2026-09-15, prd §736).
//
// It composed the thing sheet's "From — in your inbox" row: one place phrase
// per kind, behind an 80pt label column. §634 had already deleted four of its
// arms for saying something true of every row in the corpus ("saved by you",
// "written by you", "recorded by you", "banked by you"), and kept the rest on
// the test that they "name a real place". Applied to the survivors, that test
// takes almost all of them too: "in your photos" is true of every screenshot,
// "in your contacts" of every contact, "in your home" of every accessory,
// "from your machines" of every run; "awaiting your call" is a state wearing
// the label "From"; and `.mail` and `.file` shared one arm, so every Dropbox
// file in the corpus said it arrived in your inbox.
//
// Two arms passed — "in Receipts" and "in Main", the only two that said WHICH
// one — and both are now the word on a button that goes there (`Show in
// Receipts`, and the wallet's own name on `.openAddress`), following
// `walletVerbs`' 2026-08-04 ruling that a disc's word names its destination.
// Everything else the row could say, the dial already said with a door under
// it, so the row was the same fact twice with the weaker half on top.
//
// Deleted from the model, not just the surface (prd §723): nothing composes a
// place phrase anywhere now. `WalletStore.isAutoName`'s doc names this file's
// "wallet-place clause" as a caller — that is the `.transaction` arm of
// `VerbDerivation.verbs(for:)` now, which still needs to tell a name the
// person typed from a placeholder this app generated.

