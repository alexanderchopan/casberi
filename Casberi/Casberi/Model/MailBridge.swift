import Foundation
import SwiftData

/// The mail bridges (2026-07-08) — iCloud Mail and Gmail, both read-only over
/// IMAP with an app-specific password (the real account password never enters
/// Casberi). One IMAPClient serves both; only the host and the where-to-make-a-
/// password steps differ, so this enum carries the differences the way
/// TokenBridge does for the token screens.
enum MailProvider: String, CaseIterable, Identifiable {
    case icloud = "iCloud Mail"
    case gmail  = "Gmail"

    var id: String { rawValue }

    var bridgeID: String { self == .icloud ? "icloudmail" : "gmail" }
    var source: String { rawValue }
    var host: String { self == .icloud ? "imap.mail.me.com" : "imap.gmail.com" }

    /// The app-specific password lives in the Keychain; the address in prefs.
    private var addressKey: String { "mail.\(bridgeID).address" }
    var passwordKey: String { "mail.\(bridgeID).password" }
    /// The mailbox's last-seen UIDVALIDITY (`MailIngest.heal`) — a change
    /// means every UID we hold was renumbered, so a stale value here is what
    /// tells heal to learn the new baseline instead of mass-deleting.
    var uidValidityKey: String { "mail.\(bridgeID).uidvalidity" }
    /// When `MailIngest.heal` last actually ran for this provider — heal is
    /// a real network round trip (unlike Photos' local-only heal), so it's
    /// throttled independently of the foreground sweep's own 45s cooldown.
    var lastHealKey: String { "mail.\(bridgeID).lastHeal" }

    var address: String {
        get { UserDefaults.standard.string(forKey: addressKey) ?? "" }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: addressKey) }
    }
    var connected: Bool { !address.isEmpty && TokenVault.get(passwordKey) != nil }

    var addressPlaceholder: String {
        self == .icloud ? "you@icloud.com" : "you@gmail.com"
    }
    var passwordPlaceholder: String { "App-specific password" }

    /// Step one, as a door (prd §218, 2026-07-25) — the page the copy already
    /// named, opened for you instead of retyped by you. Apple's own manage
    /// page is behind its bot filter for curl (403, not 404), so this is the
    /// root the step named; the nav path stays in step two.
    var setupURL: URL? {
        switch self {
        case .icloud: URL(string: "https://appleid.apple.com")
        case .gmail:  URL(string: "https://myaccount.google.com/apppasswords")
        }
    }

    /// The door's verb + the address under it (`DSSlabButton` detail) — the
    /// 2026-08-14 anatomy: big words stay short, the host stays checkable
    /// against the address bar the door opens.
    var doorTitle: String { String(localized: "Get an app password") }
    var doorHost: String {
        switch self {
        case .icloud: "appleid.apple.com"
        case .gmail:  "myaccount.google.com"
        }
    }

    /// What's left after the door — ONE line, so `MailScreen` renders it
    /// unnumbered (§220's boundary: one instruction is not a sequence).
    ///
    /// The second step was deleted, not shortened (audit, 2026-07-31). It said
    /// "enter your address and paste the password below" over two fields
    /// placeheld `you@icloud.com` and `App-specific password` — §220's Kraken
    /// finding word for word, on the screen that was missed when it was fixed.
    var steps: [String] {
        switch self {
        case .icloud: [
            "Go to Sign-In and Security → App-Specific Passwords, generate one named \u{201C}Casberi\u{201D}, and copy it."]
        case .gmail: [
            "Turn on 2-Step Verification first if it asks, then create an app password named \u{201C}Casberi\u{201D} and copy it."]
        }
    }

    /// Says what LANDS before what's safe (audit, 2026-07-31) — this named the
    /// app password, IMAP and the read-only promise, and never once said what a
    /// mail becomes once it's here.
    var footer: String {
        "Your recent mail lands in your feed, findable by sender and subject. The inbox is read over IMAP with this app-specific password — your real password is never shared, and mail is read-only."
    }
}

enum MailIngest {

    @MainActor private static var running: Set<MailProvider> = []

    /// The IMAP failure behind the last nil `refresh` — the generic "couldn't
    /// sign in" UI message otherwise can't tell a rejected login apart from an
    /// unreachable server, which point the user in different directions.
    @MainActor private(set) static var lastError: IMAPClient.IMAPError?

    /// Reads recent inbox messages and lands new ones as mail things. Returns
    /// the new count, or nil when login/connection fails (bad password, offline).
    @MainActor
    static func refresh(_ provider: MailProvider, context: ModelContext) async -> Int? {
        guard provider.connected, !running.contains(provider) else {
            return running.contains(provider) ? 0 : nil
        }
        running.insert(provider)
        defer { running.remove(provider) }

        guard let password = TokenVault.get(provider.passwordKey) else { return nil }
        let messages: [IMAPClient.Message]
        do {
            messages = try await IMAPClient.fetchRecent(
                host: provider.host, user: provider.address, password: password, limit: 20)
            lastError = nil
        } catch let error as IMAPClient.IMAPError {
            lastError = error
            NSLog("Mail sign-in failed (%@): %@", provider.rawValue, String(describing: error))
            return nil
        } catch {
            lastError = .connect
            NSLog("Mail sign-in failed (%@): %@", provider.rawValue, String(describing: error))
            return nil
        }

        let existing = IngestSupport.existingSourceRefs(context, source: provider.source)
        var added = 0
        for m in messages {
            let ref = "mail:\(provider.bridgeID):\(m.uid)"
            guard !existing.contains(ref) else { continue }
            let thing = Thing(
                kind: .mail,
                title: m.subject,
                // The plain-text body when the second FETCH pass resolved
                // one (2026-07-23) — MailContentView already renders real
                // body text when content isn't just a "From …" line, so this
                // needed no sheet changes. Falls back to the old "From …"
                // line when the body couldn't be read (a MIME shape this
                // decoder doesn't handle, a truncated fetch) — the row still
                // gets its sender-circle identity from `authorHandle` either
                // way, never from parsing this string.
                content: m.body ?? "From \(m.from)",
                source: provider.source,
                capturedAt: m.date ?? .now,
                sourceRef: ref
            )
            // The sender is the row's identity — the feed draws an initial
            // circle from it (an email carries no avatar; a letter is what
            // we honestly have, 2026-07-10). Older rows parse it from the
            // "From …" content at render, so no migration.
            thing.authorHandle = m.from
            // Who else was on it, for RETRIEVAL only (2026-07-15 ruling) —
            // `enrichedText`, so nothing renders it and the sheet is unchanged.
            // A mail used to land knowing only its sender, which made "the mail
            // where I cc'd Ana" unanswerable over a corpus that held the
            // answer. It costs no request: `to`/`cc` ride the same ENVELOPE
            // the subject does. nil, never an empty string, when a message
            // names nobody — an empty enrichment and no enrichment are
            // different facts, and only nil says the second one.
            //
            // NEW ROWS ONLY. This pass skips a UID it has already landed (the
            // `existing.contains(ref)` guard above), so mail landed before
            // 2026-08-06 keeps no recipients — reaching those needs the fuller
            // `thingsByRef` fetch on every foreground that `heal` already pays
            // hourly, which is a cost this sweep shouldn't take on unasked.
            thing.enrichedText = recipientText(m)
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        if added > 0 { context.saveHonestly() }
        return added
    }

    /// The recipient lines a mail carries into retrieval, or nil when it names
    /// nobody but its sender.
    ///
    /// Bounded on both axes because a mailing list is unbounded on both: at
    /// most `recipientCap` names per line, and the whole block clamped, so one
    /// announcement to four hundred people can't dominate the embedding window
    /// (`EmbeddingIndex.indexText` reads the first 800 characters) or the
    /// content scan. The overflow is COUNTED rather than dropped silently —
    /// "and 380 more" is true, and a list that reads as twenty-five recipients
    /// when it had four hundred is not.
    ///
    /// Labelled in plain English rather than localized: nothing displays this
    /// string, and the part somebody searches for is a person's name.
    private static func recipientText(_ m: IMAPClient.Message) -> String? {
        func line(_ label: String, _ names: [String]) -> String? {
            guard !names.isEmpty else { return nil }
            let shown = names.prefix(recipientCap).joined(separator: ", ")
            let extra = names.count - min(names.count, recipientCap)
            return "\(label): \(shown)" + (extra > 0 ? ", and \(extra) more" : "")
        }
        let block = [line("To", m.to), line("Cc", m.cc)]
            .compactMap { $0 }.joined(separator: "\n")
        guard !block.isEmpty else { return nil }
        return block.count > recipientTextCap
            ? String(block.prefix(recipientTextCap)) + "…" : block
    }

    private static let recipientCap = 25
    private static let recipientTextCap = 2000

    @MainActor private static var healRunning: Set<MailProvider> = []
    private static let healInterval: TimeInterval = 3600

    /// Reconciles Casberi's copy against what the server still has. Deleting
    /// an email — in Mail, on any device, or server-side — never tells
    /// Casberi; the only way to notice is to ask whether each UID we landed
    /// is still there. `UID FETCH` answers only for UIDs it still has (RFC
    /// 3501 §6.4.8), so the asked-for-but-not-returned set IS what "deleted
    /// from Mail" looks like over IMAP. Mirrors `ScreenshotIngest.heal`'s
    /// RECONCILE step for Photos. Returns the number removed.
    @MainActor
    static func heal(_ provider: MailProvider, context: ModelContext, force: Bool = false) async -> Int {
        guard provider.connected, !healRunning.contains(provider) else { return 0 }
        if !force, let last = UserDefaults.standard.object(forKey: provider.lastHealKey) as? Date,
           Date.now.timeIntervalSince(last) < healInterval { return 0 }
        healRunning.insert(provider)
        defer { healRunning.remove(provider) }
        UserDefaults.standard.set(Date.now, forKey: provider.lastHealKey)

        let prefix = "mail:\(provider.bridgeID):"
        var uidToThing: [String: Thing] = [:]
        for (ref, thing) in IngestSupport.thingsByRef(context, source: provider.source)
        where ref.hasPrefix(prefix) {
            uidToThing[String(ref.dropFirst(prefix.count))] = thing
        }
        guard !uidToThing.isEmpty, let password = TokenVault.get(provider.passwordKey) else { return 0 }

        let result: IMAPClient.PresenceResult
        do {
            result = try await IMAPClient.stillPresent(
                host: provider.host, user: provider.address, password: password,
                uids: Array(uidToThing.keys))
        } catch {
            NSLog("Mail heal failed (%@): %@", provider.rawValue, String(describing: error))
            return 0
        }

        // A changed UIDVALIDITY means the mailbox was renumbered (or
        // recreated) — every UID we hold is meaningless against the new
        // numbering, so a mass "not found" here would be a false positive,
        // not real deletions. Learn the new baseline and skip removal this
        // pass; real per-message deletes surface again on the next heal
        // once the baseline is settled.
        let validityKey = provider.uidValidityKey
        if let validity = result.uidValidity {
            let stored = UserDefaults.standard.object(forKey: validityKey) as? Int
            if stored != validity {
                UserDefaults.standard.set(validity, forKey: validityKey)
                if stored != nil { return 0 }
            }
        }

        // An empty presence answer used to skip removal UNCONDITIONALLY —
        // "almost never every email at once, so treat it as a fetch that
        // didn't parse" (reported 2026-07-24: "mail connected but gone").
        // That was right about the danger and wrong about the remedy: it made
        // an emptied mailbox permanently unreconcilable, because zero-present
        // is exactly what an empty mailbox looks like too. Reported
        // 2026-08-02 as "showing me 5 emails when I have none" — pulling to
        // refresh did run, and correctly did nothing, forever.
        //
        // Two fixes let this narrow. `IMAPClient.uidFetchPresence` now THROWS
        // on a NO/BAD completion instead of returning an empty set (the
        // actual silent failure behind the original report — we never reach
        // here on a balked fetch now), and the presence check carries the
        // mailbox's own EXISTS count. So an empty answer is now readable:
        //
        //   exists == 0   the mailbox is verifiably empty — every held UID
        //                 really is gone, and this is the case that was stuck.
        //   exists > 0    it holds mail, yet none of OURS came back. Real when
        //                 you delete everything we'd landed and receive new
        //                 mail we haven't; but indistinguishable from a server
        //                 quirk, so still skipped — and self-correcting, since
        //                 the paired `refresh` lands the new mail and the next
        //                 pass sees a non-empty `present`.
        //   nil           no EXISTS line at all. Unknown, never assumed zero.
        if result.present.isEmpty, result.exists != 0 {
            NSLog("Mail heal (%@): empty presence for %d held UIDs, mailbox reports %@ — skipping delete",
                  provider.rawValue, uidToThing.count,
                  result.exists.map { "\($0) message(s)" } ?? "no EXISTS line")
            return 0
        }

        var removedIDs: [UUID] = []
        for (uid, thing) in uidToThing where !result.present.contains(uid) {
            removedIDs.append(thing.id)
            context.delete(thing)
        }
        guard !removedIDs.isEmpty else { return 0 }
        context.saveHonestly()
        SpotlightIndex.remove(ids: removedIDs)
        return removedIDs.count
    }
}
