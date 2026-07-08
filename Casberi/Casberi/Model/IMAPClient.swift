import Foundation
import Network

/// A minimal, read-only IMAP client (2026-07-08) — enough to log in with an
/// app-specific password, select the inbox, and read recent message envelopes
/// (subject, from, date). No writing, no deleting; mail is a read bridge. Used
/// by both the iCloud Mail and Gmail bridges (their only difference is the
/// host), so the IMAP protocol is written once here.
///
/// Apple provides no modern mail API — IMAP is the sanctioned door, and an
/// app-specific password keeps the real account password out of it entirely.
enum IMAPClient {

    struct Message {
        let uid: String
        let subject: String
        let from: String
        let date: Date?
    }

    enum IMAPError: Error { case connect, login, select, timeout }

    /// Connects, logs in, and returns the newest `limit` messages' envelopes.
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
        return lines.compactMap(EnvelopeParser.parse).reversed()   // newest first
    }
}

// MARK: - The connection (NWConnection + async request/response)

private final class Session {
    private let conn: NWConnection
    private var buffer = Data()
    private var tag = 0

    private init(_ conn: NWConnection) { self.conn = conn }

    static func open(host: String) async throws -> Session {
        let params = NWParameters(tls: .init(), tcp: .init())
        let c = NWConnection(host: .init(host), port: 993, using: params)
        let session = Session(c)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            c.stateUpdateHandler = { state in
                switch state {
                case .ready: cont.resume()
                case .failed, .cancelled: cont.resume(throwing: IMAPClient.IMAPError.connect)
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

    /// Returns the number of messages in the inbox (the EXISTS count).
    func selectInbox() async throws -> Int {
        let t = nextTag()
        send(line: "\(t) SELECT INBOX")
        let resp = try await readUntilTagged(t)
        guard resp.ok else { throw IMAPClient.IMAPError.select }
        for line in resp.lines {
            // "* 1234 EXISTS"
            let parts = line.split(separator: " ")
            if parts.count >= 3, parts[0] == "*", parts[2] == "EXISTS",
               let n = Int(parts[1]) { return n }
        }
        return 0
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
        let items = topLevelItems(env)   // [date, subject, from, …]
        guard items.count >= 3 else { return nil }
        let date = MailDate.parse(unquote(items[0]))
        let subject = decodeWord(unquote(items[1]))
        let from = firstFrom(items[2])
        return IMAPClient.Message(uid: uid,
                                  subject: subject.isEmpty ? "(no subject)" : subject,
                                  from: from, date: date)
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
    private static func decodeWord(_ s: String) -> String {
        guard s.contains("=?") else { return s }
        var result = s
        let pattern = "=\\?([^?]+)\\?([BbQq])\\?([^?]*)\\?="
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
            guard let full = Range(m.range, in: s),
                  let encR = Range(m.range(at: 2), in: s),
                  let txtR = Range(m.range(at: 3), in: s) else { continue }
            let enc = s[encR].uppercased(), txt = String(s[txtR])
            var decoded = txt
            if enc == "B", let d = Data(base64Encoded: txt) {
                decoded = String(decoding: d, as: UTF8.self)
            } else if enc == "Q" {
                decoded = qDecode(txt)
            }
            result.replaceSubrange(full, with: decoded)
        }
        return result
    }

    private static func qDecode(_ s: String) -> String {
        var out = "", i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "_" { out.append(" ") }
            else if c == "=", let n1 = s.index(i, offsetBy: 1, limitedBy: s.endIndex),
                    let n2 = s.index(i, offsetBy: 2, limitedBy: s.endIndex), n2 < s.endIndex,
                    let byte = UInt8(s[n1...n2], radix: 16) {
                out.append(Character(UnicodeScalar(byte)))
                i = s.index(i, offsetBy: 3); continue
            } else { out.append(c) }
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
