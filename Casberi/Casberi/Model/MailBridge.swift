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
        } catch { return nil }

        let existing = IngestSupport.existingSourceRefs(context)
        var added = 0
        for m in messages {
            let ref = "mail:\(provider.bridgeID):\(m.uid)"
            guard !existing.contains(ref) else { continue }
            let thing = Thing(
                kind: .mail,
                title: m.subject,
                content: "From \(m.from)",
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
        if added > 0 { try? context.save() }
        return added
    }
}
