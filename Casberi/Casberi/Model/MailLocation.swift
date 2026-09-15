import Foundation

/// The door from a mail thing to THE MESSAGE — not to the mail app's front
/// page (2026-09-15, prd §735).
///
/// The request that started it, pointed at the sheet's "From — in your inbox"
/// row: "can we make it so that if you tap it, it takes the user to the email
/// in the inbox". It is `FilesLocation`'s shape one bridge over, and for the
/// same reason: a row that STATES a place is the row a person presses trying
/// to GO there.
///
/// **The ruling this reverses, and the fact that reverses it.** `Verbs.swift`
/// said, in a comment, "no iOS URL opens a specific email (`message://
/// <Message-ID>` is macOS Mail's, undocumented here, and mail things key on
/// the IMAP UID anyway)", and iCloud Mail therefore got no hand-off at all.
/// Two of those three clauses are wrong. The `message:` scheme has been
/// MobileMail's since iPhone OS 1 — it predates the Mac's copy of it — and
/// its one real limit is that the message must already be downloaded and in
/// the INBOX, which is exactly and only what this bridge lands
/// (`IMAPClient.fetchRecent` reads recent inbox messages). The third clause
/// was true and is the work: the UID is a mailbox-local number that means
/// nothing to another app, so the door needs the RFC 5322 `Message-ID`, which
/// the envelope has always carried and which `Thing.mailMessageID` now keeps.
///
/// Gmail's is not a scheme at all. `rfc822msgid:` is a documented Gmail search
/// operator, so the ordinary web URL for that search lands on the one message
/// — and the Gmail app claims `mail.google.com` as a universal link, so it
/// opens there when it is installed and in the browser when it is not.
///
/// Foundation-only BY DESIGN, like `FilesLocation`: every function here is
/// compiled whole and unmodified by `scripts/mail-location-selftest.sh`, so
/// the assertions are about the bytes the app runs. Nothing here reads
/// `HandOffState` — the caller passes the scheme set in, which is what lets
/// the harness drive the gate both ways.
enum MailLocation {

    /// Apple Mail's own scheme, on both platforms this app ships to.
    ///
    /// UNMEASURED HERE, and stated at the grade it deserves — the same grade
    /// `FilesLocation.revealScheme` gets one file over. It is documented by
    /// Apple only in an archived URL-scheme reference, so it is gated on
    /// `canOpenURL` and never offered unless something really claims it:
    /// an unclaimed scheme is refused asynchronously and reports success,
    /// which is the dead control §83 bans. Measure it with `-mailOpenProbe`.
    static let openScheme = "message"

    /// Gmail's search page. The Gmail iOS app claims this host, so the same
    /// URL is an app hand-off where the app exists and a browser one where it
    /// doesn't — one string, never a dead one.
    static let gmailHost = "mail.google.com"

    /// The bare `Message-ID`, or nil when what we hold is not one.
    ///
    /// A FENCE, not a trim, for `FilesLocation.components`' reason: this value
    /// came off a third party's `ENVELOPE`, went through a `Thing` and a
    /// CloudKit round trip, and is handed to another app as a URL. Angle
    /// brackets come off (the envelope keeps them, `rfc822msgid:` refuses
    /// them); everything else must look like the `local@domain` RFC 5322
    /// §3.6.4 requires, because a door built on a truncated envelope or a
    /// stray atom opens nothing while claiming to. Nil rather than a best
    /// effort — the caller draws a door, and a door onto nowhere is worse
    /// than no door at all.
    static func normalizedID(_ raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else { return nil }
        if s.hasPrefix("<"), s.hasSuffix(">"), s.count >= 3 {
            s = String(s.dropFirst().dropLast())
        }
        // One `@`, something on each side, and nothing that would end the URL
        // early or start a second one. 998 is RFC 5322's line-length ceiling,
        // so anything longer is not a header field we were handed whole.
        let halves = s.split(separator: "@", omittingEmptySubsequences: false)
        guard halves.count == 2, !halves[0].isEmpty, !halves[1].isEmpty,
              s.count <= 998,
              s.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              s.rangeOfCharacter(from: .controlCharacters) == nil,
              !s.contains("<"), !s.contains(">") else { return nil }
        return s
    }

    /// Where pressing "From — in your inbox" lands, or nil when there is
    /// nowhere honest to send them.
    ///
    /// `schemes` is `HandOffState.installedSchemes` at every real call site.
    /// Gmail's arm ignores it on purpose: an `https` URL always opens
    /// something, so it is the one door here that cannot silently do nothing,
    /// and gating it on the Gmail APP would delete the door for everyone
    /// reading Gmail over IMAP without that app installed — which is most of
    /// this bridge's users, since it signs in with an app-specific password.
    static func messageURL(source: String, messageID: String?,
                           schemes: Set<String>) -> URL? {
        guard let id = normalizedID(messageID) else { return nil }
        switch source.lowercased() {
        case "gmail":
            guard let q = id.addingPercentEncoding(withAllowedCharacters: idAllowed)
            else { return nil }
            // `/u/0/` is the first signed-in account, which is the only one
            // this bridge could be reading — it holds one address.
            return URL(string: "https://\(gmailHost)/mail/u/0/#search/rfc822msgid:\(q)")
        case "icloud mail":
            guard schemes.contains(openScheme),
                  let q = "<\(id)>".addingPercentEncoding(withAllowedCharacters: idAllowed)
            else { return nil }
            // Opaque (`message:`), never `message://`: the encoded brackets
            // would be read as an authority, and a percent-encoded host is
            // not a host.
            return URL(string: "\(openScheme):\(q)")
        default:
            return nil
        }
    }

    /// The APP the door opens, for the verb's own words. "Open in Mail", never
    /// "Open in iCloud Mail" — the second names a service, and the person is
    /// about to be looking at the first.
    static func appName(source: String) -> String? {
        switch source.lowercased() {
        case "gmail":       return "Gmail"
        case "icloud mail": return "Mail"
        default:            return nil
        }
    }

    /// Unreserved characters only (RFC 3986 §2.3). Deliberately harsher than
    /// `.urlFragmentAllowed`: a Message-ID may hold `/`, `+`, `?` or `#`, and
    /// each of those means something to Gmail's own hash router or to
    /// `URL(string:)` — an unencoded `/` silently turns one search into a
    /// path, which is a door that opens the wrong page rather than none.
    private static let idAllowed = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}
