import Foundation
import Network

/// A minimal, read-only IMAP client (2026-07-08) — enough to log in with an
/// app-specific password, select the inbox, and read recent message envelopes
/// (subject, from, date, recipients and the threading headers). No writing, no
/// deleting; mail is a read bridge. Used by both the iCloud Mail and Gmail
/// bridges (their only difference is the host), so the IMAP protocol is written
/// once here.
///
/// Apple provides no modern mail API — IMAP is the sanctioned door, and an
/// app-specific password keeps the real account password out of it entirely.
enum IMAPClient {

    struct Message {
        let uid: String
        let subject: String
        let from: String
        let date: Date?
        /// The plain-text body, best-effort (2026-07-23) — nil when the
        /// second FETCH pass fails, or MIME decoding finds nothing readable.
        /// A mail thing with no body reads exactly as it did before this
        /// existed (sender only), so a failure here never breaks ingest.
        let body: String?
        /// Who else was on it (2026-08-06). Both ride the ENVELOPE this client
        /// already fetches — they are fields 5 and 6 of the same response that
        /// carries the subject and the sender (RFC 3501 §7.4.2), so nothing
        /// here costs a request; they were simply parsed past. Until now a mail
        /// arrived knowing only who sent it, so "the mail where I cc'd Ana" was
        /// unanswerable from a corpus that held the answer.
        ///
        /// Each entry is `Name <box@host>` when the envelope names both, else
        /// whichever half it has — recipients feed retrieval, and a name with
        /// no address is half a search term.
        let to: [String]
        let cc: [String]
        /// The threading headers, also already in the ENVELOPE (fields 8 and
        /// 9). CARRIED, NOT USED (2026-08-06): nothing in the app groups mail
        /// into threads yet, and grouping is a feature with its own shape
        /// questions — this is the data that feature needs, parsed at the one
        /// point it is free, so building it later costs no new round trip and
        /// no re-fetch of mail already landed. nil when the header is absent
        /// (`NIL`), which is normal for a message that starts a thread.
        let messageID: String?
        let inReplyTo: String?
        /// What came attached, by NAME (2026-08-14) — read out of the same
        /// raw bytes the body pass already fetched, so it costs no request.
        /// Empty for a message with no attachments AND for one whose body
        /// fetch failed; the two are the same from here, which is why nothing
        /// downstream may phrase an empty list as "no attachments".
        var attachments: [String] = []
    }

    /// `fetch` is distinct from `select` on purpose (2026-08-02): the heal's
    /// presence check fails AFTER a successful SELECT, and logging that as
    /// "select" would point at the wrong command in the one place this is
    /// read — the log line that says why a delete-sync did nothing.
    enum IMAPError: Error { case connect, login, select, fetch, timeout }

    /// RFC 2047 encoded-word decoding, for callers outside the envelope parser
    /// (2026-08-14). `MailMIME.attachmentNames` needs exactly what a subject
    /// needs — a filename from a non-English sender arrives encoded the same
    /// way — and a second copy of an RFC 2047 decoder is one that drifts, then
    /// gets the next fix late. A forwarder rather than opening `EnvelopeParser`
    /// up, so the parser stays private and this is the one door.
    static func decodeHeaderWord(_ s: String) -> String { EnvelopeParser.decodeWord(s) }

    /// The raw bytes fetched per message for the body pass — enough for
    /// nearly every real message's readable text (plain or the first HTML
    /// alternative), bounded so one attachment-heavy message can't stall a
    /// foreground refresh.
    private static let bodyByteCap = 65536

    /// Connects, logs in, and returns the newest `limit` messages' envelopes
    /// (plus a best-effort plain-text body for each).
    static func fetchRecent(host: String, user: String, password: String,
                            limit: Int = 20) async throws -> [Message] {
        let conn = try await Session.open(host: host)
        defer { conn.close() }

        try await conn.greeting()
        try await conn.login(user: user, password: password)
        let total = try await conn.selectInbox()
        guard total > 0 else { return [] }

        let start = max(1, total - limit + 1)
        let lines = try await conn.fetchEnvelopes(from: start, to: total)
        let parsed = lines.compactMap(EnvelopeParser.parse)
        // A second FETCH pass, best-effort: a failure here (a server that
        // balks at partial fetch, a network hiccup) degrades every message
        // to body-less rather than failing the whole refresh — the pre-body
        // behavior, not a regression.
        let rawBodies = (try? await conn.fetchBodies(
            uids: parsed.map(\.uid), maxBytes: bodyByteCap)) ?? [:]
        let withBodies = parsed.map { m in
            let raw = rawBodies[m.uid]
            return Message(uid: m.uid, subject: m.subject, from: m.from, date: m.date,
                           body: raw.flatMap(MailMIME.plainText),
                           to: m.to, cc: m.cc, messageID: m.messageID, inReplyTo: m.inReplyTo,
                           // Same bytes the body was decoded from — no second
                           // fetch, and no request at all when the body pass
                           // above already failed.
                           attachments: raw.map(MailMIME.attachmentNames) ?? [])
        }
        #if DEBUG
        NSLog("IMAP %@: %d fetched, %d parsed, %d bodies", host, lines.count, parsed.count,
              withBodies.filter { $0.body != nil }.count)
        #endif
        return withBodies.reversed()   // newest first
    }

    /// Which of the given UIDs the server still has, for the delete-sync
    /// heal pass — a message expunged since we landed it isn't an IMAP
    /// error, it's simply absent from the FETCH response (RFC 3501 §6.4.8),
    /// so "asked for but not returned" IS the deleted set. Also hands back
    /// the mailbox's UIDVALIDITY: if that ever changes, every UID we hold
    /// was renumbered out from under us and a mass "not found" would be a
    /// false positive, not real deletions — the caller must check it before
    /// trusting `present`.
    /// `exists` is the mailbox's own EXISTS count — what makes an empty
    /// `present` READABLE. Without it the caller cannot tell "none of the
    /// UIDs we hold survive" (a real mass deletion, which an emptied mailbox
    /// genuinely is) from "the fetch told us nothing" — and it used to
    /// resolve that ambiguity by never deleting, which left an emptied
    /// mailbox showing stale rows forever. nil means the server never
    /// reported one; the caller must treat that as unknown, never as zero.
    struct PresenceResult { let uidValidity: Int?; let present: Set<String>; let exists: Int? }

    static func stillPresent(host: String, user: String, password: String,
                             uids: [String]) async throws -> PresenceResult {
        let conn = try await Session.open(host: host)
        defer { conn.close() }
        try await conn.greeting()
        try await conn.login(user: user, password: password)
        _ = try await conn.selectInbox()

        var present = Set<String>()
        var i = 0
        while i < uids.count {
            let chunk = Array(uids[i..<min(i + 400, uids.count)])
            present.formUnion(try await conn.uidFetchPresence(chunk))
            i += 400
        }
        return PresenceResult(uidValidity: conn.uidValidity, present: present,
                              exists: conn.messageCount)
    }
}

// MARK: - The connection (NWConnection + async request/response)

private final class Session {
    private let conn: NWConnection
    private var buffer = Data()
    private var tag = 0
    /// Consecutive `receiveMore()` calls that returned no data with no error
    /// and no EOF — a server that keeps handing back empty, non-final chunks
    /// (misbehaving or actively hostile) would otherwise loop `readLine()`
    /// forever with no bound. Reset the moment real bytes arrive.
    private var consecutiveEmptyReceives = 0
    private static let maxConsecutiveEmptyReceives = 50

    private init(_ conn: NWConnection) { self.conn = conn }

    static func open(host: String) async throws -> Session {
        let params = NWParameters(tls: .init(), tcp: .init())
        let c = NWConnection(host: .init(host), port: 993, using: params)
        let session = Session(c)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            // The handler must resume the continuation exactly once — clear it
            // on the first terminal state, or the later cancel() in close()
            // would resume a second time (a fatal error).
            c.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    c.stateUpdateHandler = nil
                    cont.resume()
                case .failed, .cancelled:
                    c.stateUpdateHandler = nil
                    cont.resume(throwing: IMAPClient.IMAPError.connect)
                default: break
                }
            }
            c.start(queue: .global(qos: .userInitiated))
        }
        return session
    }

    func close() { send(line: "\(nextTag()) LOGOUT"); conn.cancel() }

    // Read the server greeting ("* OK ...").
    func greeting() async throws { _ = try await readUntilLine(prefix: "* ") }

    func login(user: String, password: String) async throws {
        let t = nextTag()
        send(line: "\(t) LOGIN \(quote(user)) \(quote(password))")
        guard try await readUntilTagged(t).ok else { throw IMAPClient.IMAPError.login }
    }

    /// The SELECT response's `[UIDVALIDITY n]` — set once per session by
    /// `selectInbox()`, read back by `stillPresent` to detect a renumbered
    /// mailbox before trusting a presence check's absences as real deletes.
    private(set) var uidValidity: Int?

    /// The SELECT response's `* n EXISTS` — how many messages the mailbox
    /// actually holds, kept here (rather than only returned) so
    /// `stillPresent` can report it too. OPTIONAL on purpose, and the
    /// optionality is the safety property: nil means the server never sent an
    /// EXISTS line, which must not be confused with a mailbox that really
    /// holds zero. `heal` deletes on a verified zero, so a defaulted 0 would
    /// be a mass delete on a malformed response. RFC 3501 §6.3.1 requires the
    /// line; this does not take the requirement on trust.
    private(set) var messageCount: Int?

    /// Returns the number of messages in the inbox (the EXISTS count).
    func selectInbox() async throws -> Int {
        let t = nextTag()
        send(line: "\(t) SELECT INBOX")
        let resp = try await readUntilTagged(t)
        guard resp.ok else { throw IMAPClient.IMAPError.select }
        var total = 0
        for line in resp.lines {
            // "* 1234 EXISTS"
            let parts = line.split(separator: " ")
            if parts.count >= 3, parts[0] == "*", parts[2] == "EXISTS",
               let n = Int(parts[1]) { total = n; messageCount = n }
            // "* OK [UIDVALIDITY 1234567890] UIDs valid"
            if let r = line.range(of: "UIDVALIDITY ") {
                let digits = line[r.upperBound...].prefix { $0.isNumber }
                if !digits.isEmpty { uidValidity = Int(digits) }
            }
        }
        return total
    }

    /// `UID FETCH <set> (UID)` — the server answers only for UIDs it still
    /// has; an expunged one is simply missing from the response, not an
    /// error (RFC 3501 §6.4.8).
    func uidFetchPresence(_ uids: [String]) async throws -> Set<String> {
        let t = nextTag()
        send(line: "\(t) UID FETCH \(uids.joined(separator: ",")) (UID)")
        let resp = try await readUntilTagged(t)
        // A NO/BAD completion must THROW, never read as "none of them
        // survive" (2026-08-02). This was the silent path behind the
        // 2026-07-24 "mail connected but gone" report: the tagged result was
        // parsed for lines but its `ok` was dropped, so a server that balked
        // at the fetch — a set too long, a transient NO — handed back an
        // empty set that is byte-identical to "every one of these was
        // deleted". `MailIngest.heal` then had no way to tell a failure from
        // a mass deletion, and the blanket "empty means hiccup" guard it grew
        // in response is what made a genuinely emptied mailbox impossible to
        // reconcile ever again. Fixing the lie at the source is what lets
        // that guard narrow to the one case it should have covered.
        guard resp.ok else { throw IMAPClient.IMAPError.fetch }
        var present = Set<String>()
        for line in resp.lines {
            // "* 12 FETCH (UID 1234)"
            guard let r = line.range(of: "UID ") else { continue }
            let digits = line[r.upperBound...].prefix { $0.isNumber }
            if !digits.isEmpty { present.insert(String(digits)) }
        }
        return present
    }

    /// One raw "* n FETCH (...)" string per message.
    func fetchEnvelopes(from: Int, to: Int) async throws -> [String] {
        let t = nextTag()
        send(line: "\(t) FETCH \(from):\(to) (UID ENVELOPE)")
        let resp = try await readUntilTagged(t)
        // Re-stitch: a FETCH response can span lines; join the untagged block.
        var out: [String] = []
        var current = ""
        for line in resp.lines {
            if line.hasPrefix("* ") && line.contains(" FETCH ") {
                if !current.isEmpty { out.append(current) }
                current = line
            } else if !current.isEmpty {
                current += " " + line
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// `UID FETCH <uids> (UID BODY.PEEK[]<0.maxBytes>)` — the raw top-level
    /// message bytes (RFC 822 headers + body), capped at `maxBytes`. `.PEEK`
    /// never marks the message read (RFC 3501 §6.4.5) — the read-only
    /// promise in `MailProvider.footer` depends on it. Unlike ENVELOPE, the
    /// server hands the payload back as an IMAP LITERAL (`{n}` then exactly
    /// `n` raw bytes, which may contain embedded CR/LF) rather than a plain
    /// line — `fetchEnvelopes`'s line-by-line reader would corrupt that, so
    /// this reads each literal by byte count instead.
    func fetchBodies(uids: [String], maxBytes: Int) async throws -> [String: Data] {
        guard !uids.isEmpty else { return [:] }
        var out: [String: Data] = [:]
        var i = 0
        // Batched (40 UIDs/round trip): a single command line for hundreds of
        // UIDs risks the server's own command-length limit, mirrored from the
        // 400-per-batch cap `stillPresent` already uses for UID FETCH.
        while i < uids.count {
            let chunk = Array(uids[i..<min(i + 40, uids.count)])
            let t = nextTag()
            send(line: "\(t) UID FETCH \(chunk.joined(separator: ",")) (UID BODY.PEEK[]<0.\(maxBytes)>)")
            while true {
                let line = try await readLine()
                if line.hasPrefix(t + " ") { break }
                guard line.hasPrefix("* "), line.contains(" FETCH ") else { continue }
                guard let uid = Self.digits(after: "UID ", in: line),
                      let literalLen = Self.literalLength(atEndOf: line) else { continue }
                out[uid] = try await readExact(literalLen)
                // The literal's bytes are followed, on the SAME logical
                // line, by whatever closes this FETCH (usually just ")") —
                // read it out so the next readLine() starts clean at the
                // next untagged response.
                _ = try? await readLine()
            }
            i += 40
        }
        return out
    }

    /// Reads exactly `n` raw bytes — an IMAP literal's payload. Must never go
    /// through `readLine()`: the bytes can contain CR/LF that isn't a line
    /// break, and a line-based read would split (and lose) content there.
    private func readExact(_ n: Int) async throws -> Data {
        while buffer.count < n { try await receiveMore() }
        let end = buffer.index(buffer.startIndex, offsetBy: n)
        let data = buffer.subdata(in: buffer.startIndex..<end)
        buffer.removeSubrange(buffer.startIndex..<end)
        return data
    }

    private static func digits(after key: String, in s: String) -> String? {
        guard let r = s.range(of: key) else { return nil }
        let digits = s[r.upperBound...].prefix { $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }

    /// A literal marker ("{2048}") is always the LAST token on the response
    /// line that declares it, immediately before the CRLF that precedes its
    /// raw bytes (RFC 3501 §4.3) — so this only ever looks at the line's tail.
    private static func literalLength(atEndOf line: String) -> Int? {
        guard line.hasSuffix("}"), let open = line.lastIndex(of: "{") else { return nil }
        return Int(line[line.index(after: open)..<line.index(before: line.endIndex)])
    }

    // MARK: low-level

    private func nextTag() -> String { tag += 1; return "a\(tag)" }
    private func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private func send(line: String) {
        conn.send(content: (line + "\r\n").data(using: .utf8), completion: .idempotent)
    }

    struct Response { let ok: Bool; let lines: [String] }

    /// Reads until a line beginning with `tag ` (the tagged completion).
    private func readUntilTagged(_ tag: String) async throws -> Response {
        var lines: [String] = []
        while true {
            let line = try await readLine()
            if line.hasPrefix(tag + " ") {
                return Response(ok: line.uppercased().contains(" OK"), lines: lines)
            }
            lines.append(line)
        }
    }

    private func readUntilLine(prefix: String) async throws -> String {
        while true {
            let line = try await readLine()
            if line.hasPrefix(prefix) { return line }
        }
    }

    /// One CRLF-delimited line, reading more from the socket as needed.
    private func readLine() async throws -> String {
        while true {
            if let range = buffer.range(of: Data([13, 10])) {   // CRLF
                let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                return String(decoding: lineData, as: UTF8.self)
            }
            try await receiveMore()
        }
    }

    private func receiveMore() async throws {
        let chunk: Data = try await withCheckedThrowingContinuation { cont in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isDone, error in
                if let error { cont.resume(throwing: error); return }
                if let data, !data.isEmpty { cont.resume(returning: data) }
                else if isDone { cont.resume(throwing: IMAPClient.IMAPError.timeout) }
                else { cont.resume(returning: Data()) }
            }
        }
        if chunk.isEmpty {
            consecutiveEmptyReceives += 1
            guard consecutiveEmptyReceives < Self.maxConsecutiveEmptyReceives else {
                throw IMAPClient.IMAPError.timeout
            }
        } else {
            consecutiveEmptyReceives = 0
        }
        buffer.append(chunk)
    }
}

// MARK: - ENVELOPE parsing (tolerant; falls back rather than failing)

private enum EnvelopeParser {
    /// Parses a "* n FETCH (UID u ENVELOPE (date subj (from) …))" line.
    static func parse(_ raw: String) -> IMAPClient.Message? {
        guard let uid = value(after: "UID ", in: raw),
              let envRange = raw.range(of: "ENVELOPE (") else { return nil }
        let env = String(raw[envRange.upperBound...])
        // RFC 3501 §7.4.2's fixed order: date, subject, from, sender, reply-to,
        // to, cc, bcc, in-reply-to, message-id. Everything past `from` is read
        // by INDEX and only when the list is long enough — a short envelope
        // (a server that truncates, a malformed response) degrades to the
        // three fields this parser has always required rather than failing,
        // which is the same tolerance every other read here has.
        let items = topLevelItems(env)   // [date, subject, from, …]
        guard items.count >= 3 else { return nil }
        let date = MailDate.parse(unquote(items[0]))
        let subject = decodeWord(unquote(items[1]))
        let from = firstFrom(items[2])
        // Bcc (field 7) is deliberately not read: the copy WE received names
        // us in it and nobody else, so landing it would add a recipient list
        // that is either us or empty.
        let to = items.count > 5 ? addresses(items[5]) : []
        let cc = items.count > 6 ? addresses(items[6]) : []
        let inReplyTo = items.count > 8 ? header(items[8]) : nil
        let messageID = items.count > 9 ? header(items[9]) : nil
        return IMAPClient.Message(uid: uid,
                                  subject: subject.isEmpty ? "(no subject)" : subject,
                                  from: from, date: date, body: nil,
                                  to: to, cc: cc,
                                  messageID: messageID, inReplyTo: inReplyTo)
    }

    /// A bare envelope header string (`"<abc@host>"`, or `NIL`) — nil when the
    /// field is absent or empty, never an empty string, so a caller can't
    /// mistake "no In-Reply-To" for "an In-Reply-To of nothing".
    private static func header(_ raw: String) -> String? {
        let s = unquote(raw).trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? nil : s
    }

    /// Every address in an envelope address-list: `(("Ana" NIL "ana" "x.com"))`
    /// → `["Ana <ana@x.com>"]`. Both halves when the envelope carries both —
    /// this feeds RETRIEVAL, where a name without its address (or the reverse)
    /// is half a search term, which is why it differs from `firstFrom` below,
    /// whose job is one display identity.
    ///
    /// An absent list is the atom `NIL`, not a group, and a group is required
    /// here — so `NIL` and anything else unparseable yield an empty list
    /// rather than the garbage a blind `dropFirst().dropLast()` would make of
    /// a three-letter atom.
    private static func addresses(_ group: String) -> [String] {
        guard group.hasPrefix("("), group.hasSuffix(")") else { return [] }
        return topLevelItems(String(group.dropFirst().dropLast())).compactMap { entry in
            guard entry.hasPrefix("("), entry.hasSuffix(")") else { return nil }
            let addr = topLevelItems(String(entry.dropFirst().dropLast()))
            guard addr.count >= 4 else { return nil }
            let name = decodeWord(unquote(addr[0]))
            let mailbox = unquote(addr[2]), hostPart = unquote(addr[3])
            let email = mailbox.isEmpty ? "" : "\(mailbox)@\(hostPart)"
            if !name.isEmpty, !email.isEmpty { return "\(name) <\(email)>" }
            if !name.isEmpty { return name }
            return email.isEmpty ? nil : email
        }
    }

    private static func value(after key: String, in s: String) -> String? {
        guard let r = s.range(of: key) else { return nil }
        let rest = s[r.upperBound...]
        return rest.prefix { $0.isNumber }.isEmpty ? nil : String(rest.prefix { $0.isNumber })
    }

    /// Splits the top-level space-separated items of an envelope body, treating
    /// quoted strings and (nested) parenthesised groups as single items.
    private static func topLevelItems(_ s: String) -> [String] {
        var items: [String] = []
        var depth = 0, inQuote = false, cur = "", started = false
        var it = s.makeIterator()
        var prev: Character = " "
        while let c = it.next() {
            if depth == 0 && !inQuote && c == ")" && !started { break }   // end of ENVELOPE
            if inQuote {
                cur.append(c)
                if c == "\"" && prev != "\\" { inQuote = false; items.append(cur); cur = ""; started = false }
            } else if c == "\"" {
                inQuote = true; started = true; cur = "\""
            } else if c == "(" {
                depth += 1; started = true; cur.append(c)
            } else if c == ")" {
                if depth == 0 { break }
                depth -= 1; cur.append(c)
                if depth == 0 { items.append(cur); cur = ""; started = false }
            } else if c == " " && depth == 0 {
                if started { items.append(cur); cur = ""; started = false }
            } else {
                started = true; cur.append(c)
            }
            prev = c
        }
        if started && !cur.isEmpty { items.append(cur) }
        return items
    }

    /// From `(("Name" NIL "mailbox" "host"))` → "Name" or "mailbox@host".
    private static func firstFrom(_ group: String) -> String {
        let inner = topLevelItems(String(group.dropFirst().dropLast()))   // strip outer ()
        guard let first = inner.first else { return "" }
        let addr = topLevelItems(String(first.dropFirst().dropLast()))
        guard addr.count >= 4 else { return "" }
        let name = decodeWord(unquote(addr[0]))
        if !name.isEmpty { return name }
        let mailbox = unquote(addr[2]), hostPart = unquote(addr[3])
        return mailbox.isEmpty ? "" : "\(mailbox)@\(hostPart)"
    }

    private static func unquote(_ s: String) -> String {
        if s == "NIL" { return "" }
        var t = s
        if t.hasPrefix("\"") && t.hasSuffix("\"") && t.count >= 2 { t = String(t.dropFirst().dropLast()) }
        return t.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// Decodes RFC 2047 encoded-words (=?charset?B/Q?text?=) enough for subjects.
    /// Words decode to BYTES first and adjacent words merge before the charset
    /// decode — a multi-byte character (an emoji, a curly quote) may straddle
    /// the word boundary, and decoding each word alone shatters it.
    ///
    /// Internal rather than private since 2026-08-14: `MailMIME.attachmentNames`
    /// needs exactly this — a filename is encoded the same way a subject is, and
    /// a mail from anywhere but an English-speaking sender routinely carries one.
    /// SHARED rather than copied, because two RFC 2047 decoders drift and the
    /// second one is always the one that gets the fix late.
    static func decodeWord(_ s: String) -> String {
        guard s.contains("=?") else { return s }
        // Whitespace between adjacent encoded-words is not content (RFC 2047 §6.2).
        let joined = s.replacingOccurrences(
            of: "\\?=\\s+=\\?", with: "?==?", options: .regularExpression)
        let pattern = "=\\?([^?]+)\\?([BbQq])\\?([^?]*)\\?="
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }

        var result = "", pending = Data(), pendingCharset = ""
        var last = joined.startIndex
        func flush() {
            guard !pending.isEmpty else { return }
            result += decode(pending, charset: pendingCharset)
            pending = Data()
        }
        for m in re.matches(in: joined, range: NSRange(joined.startIndex..., in: joined)) {
            guard let full = Range(m.range, in: joined),
                  let chR = Range(m.range(at: 1), in: joined),
                  let encR = Range(m.range(at: 2), in: joined),
                  let txtR = Range(m.range(at: 3), in: joined) else { continue }
            if last < full.lowerBound {
                flush()
                result += joined[last..<full.lowerBound]
            }
            // Charset may carry an RFC 2231 language tag ("utf-8*en") — drop it.
            let charset = joined[chR].split(separator: "*").first.map(String.init) ?? ""
            let enc = joined[encR].uppercased(), txt = String(joined[txtR])
            if charset.lowercased() != pendingCharset.lowercased() { flush(); pendingCharset = charset }
            if enc == "B" { pending.append(Data(base64Encoded: txt) ?? Data(txt.utf8)) }
            else { pending.append(qDecodeBytes(txt)) }
            last = full.upperBound
        }
        flush()
        result += joined[last...]
        return result
    }

    private static func decode(_ data: Data, charset: String) -> String {
        let cs = charset.lowercased()
        if cs.contains("1252") || cs.contains("windows") {
            return String(data: data, encoding: .windowsCP1252)
                ?? String(decoding: data, as: UTF8.self)
        }
        if cs.hasPrefix("iso-8859") || cs.contains("latin") {
            return String(data: data, encoding: .isoLatin1)
                ?? String(decoding: data, as: UTF8.self)
        }
        // utf-8, us-ascii, unknown: UTF-8 first, Latin-1 as the salvage path.
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    private static func qDecodeBytes(_ s: String) -> Data {
        var out = Data(), i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "_" { out.append(0x20) }
            else if c == "=", let n1 = s.index(i, offsetBy: 1, limitedBy: s.endIndex),
                    let n2 = s.index(i, offsetBy: 2, limitedBy: s.endIndex), n2 < s.endIndex,
                    let byte = UInt8(s[n1...n2], radix: 16) {
                out.append(byte)
                i = s.index(i, offsetBy: 3); continue
            } else { out.append(contentsOf: Array(String(c).utf8)) }
            i = s.index(after: i)
        }
        return out
    }
}

private enum MailDate {
    private static let rfc: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()
    static func parse(_ s: String) -> Date? {
        rfc.date(from: s) ?? rfc.date(from: s.replacingOccurrences(
            of: #"\s*\([^)]*\)\s*$"#, with: "", options: .regularExpression))
    }
}
