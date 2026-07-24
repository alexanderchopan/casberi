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

    var steps: [String] {
        switch self {
        case .icloud: [
            "Sign in at appleid.apple.com → Sign-In and Security → App-Specific Passwords.",
            "Generate one, name it \u{201C}Casberi\u{201D}, and copy it.",
            "Enter your @icloud.com address and paste the password below."]
        case .gmail: [
            "Turn on 2-Step Verification, then open myaccount.google.com/apppasswords.",
            "Create an app password named \u{201C}Casberi\u{201D} and copy it.",
            "Enter your Gmail address and paste the password below."]
        }
    }

    var footer: String {
        "Casberi reads your inbox over IMAP with this app-specific password — your real password is never shared, and mail is read-only."
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
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        if added > 0 { context.saveHonestly() }
        return added
    }

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
