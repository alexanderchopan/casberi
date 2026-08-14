import Foundation

/// A minimal, read-only MIME decoder (2026-07-23) — enough to pull the
/// readable plain-text body out of a real inbox message for the mail thing
/// sheet. Not a general MIME library: best-effort only, and a failure at any
/// step degrades to nil (a mail thing with no body reads exactly as it did
/// before this existed — sender only — so nothing here is load-bearing).
enum MailMIME {

    /// `raw` is the top-level RFC 822 bytes `IMAPClient` fetched via
    /// `BODY.PEEK[]<0.N>` — headers AND body, possibly truncated at N bytes
    /// (a large attachment cut off mid-stream is fine; only the readable
    /// text near the top is ever wanted).
    static func plainText(from raw: Data) -> String? {
        guard let (headers, body) = splitHeaderBody(raw) else {
            return clean(decodedString(raw, charset: "utf-8"))
        }
        let contentType = headerValue("content-type", in: headers) ?? "text/plain"
        let charset = parameter("charset", in: contentType) ?? "utf-8"
        let text: String?
        if contentType.lowercased().contains("multipart"),
           let boundary = parameter("boundary", in: contentType) {
            text = firstReadablePart(in: body, boundary: boundary)
        } else {
            let cte = headerValue("content-transfer-encoding", in: headers) ?? "7bit"
            let decoded = decodeBody(body, encoding: cte, charset: charset)
            text = contentType.lowercased().contains("text/html") ? htmlToPlainText(decoded) : decoded
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let cleaned = clean(text)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// What came ATTACHED to a message (2026-08-14).
    ///
    /// The decoder already walked every one of these parts and threw them away
    /// — `firstReadablePart`'s own comment says so ("Anything else (an
    /// attachment, an image) is skipped"). It was skipping the CONTENT, which
    /// is right; it was also skipping the NAME, which meant "the mail with the
    /// contract" could not be answered from a corpus that had fetched the
    /// contract's filename and dropped it.
    ///
    /// Names only, never bytes. This app does not store other people's
    /// attachments, and the whole point of the `BODY.PEEK[]<0.N>` cap is that a
    /// large one is cut off mid-stream — but a filename lives in the part's
    /// HEADERS, which arrive before the bytes do, so a truncated fetch still
    /// yields the name of the attachment it truncated.
    ///
    /// Best-effort like everything else here: an empty array on any failure.
    static func attachmentNames(from raw: Data) -> [String] {
        guard let (headers, body) = splitHeaderBody(raw) else { return [] }
        let contentType = headerValue("content-type", in: headers) ?? "text/plain"
        guard contentType.lowercased().contains("multipart"),
              let boundary = parameter("boundary", in: contentType) else { return [] }
        var names: [String] = []
        collectAttachments(in: body, boundary: boundary, into: &names, depth: 0)
        // Deduped, order preserved: a `multipart/related` inline image can be
        // referenced twice, and the same name twice reads as two files.
        var seen = Set<String>()
        return names.filter { seen.insert($0.lowercased()).inserted }
            .prefix(attachmentCap).map { $0 }
    }

    /// A mail is allowed to say it carries a lot of things; a row is not
    /// allowed to be a file listing.
    private static let attachmentCap = 8

    /// Mirrors `firstReadablePart`'s walk, including its recursion into nested
    /// multiparts — the attachment normally sits in the `mixed` alongside the
    /// `alternative` that holds the text, so a non-recursive scan finds the
    /// text every time and the file only sometimes.
    ///
    /// `depth` is a fuse, not a feature: `boundary` comes from a header a
    /// stranger controls, and a part whose boundary equals its parent's makes
    /// the walk re-enter the same bytes forever.
    private static func collectAttachments(in data: Data, boundary: String,
                                           into names: inout [String], depth: Int) {
        guard depth < 6, names.count < attachmentCap else { return }
        guard let markerData = "--\(boundary)".data(using: .utf8) else { return }
        for part in split(data, on: markerData) {
            guard let (partHeaders, partBody) = splitHeaderBody(part) else { continue }
            let partType = headerValue("content-type", in: partHeaders) ?? ""
            if partType.lowercased().contains("multipart"),
               let nested = parameter("boundary", in: partType), nested != boundary {
                collectAttachments(in: partBody, boundary: nested, into: &names, depth: depth + 1)
                continue
            }
            guard let name = attachmentName(headers: partHeaders, contentType: partType)
            else { continue }
            names.append(name)
            if names.count >= attachmentCap { return }
        }
    }

    /// The part's filename, or nil when the part isn't a file.
    ///
    /// Two places carry it and BOTH are checked: `Content-Disposition`'s
    /// `filename` is the modern spelling, `Content-Type`'s `name` the older one
    /// that plenty of senders still use alone.
    ///
    /// A part is a FILE when it says `attachment`, or when it names a file at
    /// all while not being readable text. That second clause is what catches
    /// the sender whose `Content-Disposition` is `inline` for a PDF — common,
    /// and indistinguishable from an attachment to the person who received it.
    /// The text/multipart exclusion is what keeps a `text/plain; name="body"`
    /// from reading as a file you were sent.
    private static func attachmentName(headers: String, contentType: String) -> String? {
        let disposition = headerValue("content-disposition", in: headers) ?? ""
        let lowerType = contentType.lowercased()
        let raw = parameter("filename", in: disposition) ?? parameter("name", in: contentType)
        guard let raw, !raw.isEmpty else { return nil }
        let isAttachment = disposition.lowercased().contains("attachment")
        let isText = lowerType.contains("text/") || lowerType.contains("multipart")
        guard isAttachment || !isText else { return nil }
        // A filename is encoded exactly the way a subject is, so it goes
        // through the SAME decoder rather than a second copy of one.
        let decoded = IMAPClient.decodeHeaderWord(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !decoded.isEmpty else { return nil }
        // A path separator in a filename is a header a stranger wrote reaching
        // for somewhere it has no business being. Nothing here writes a file,
        // so this cannot become a path traversal — but the name is DISPLAYED,
        // and "../../etc/passwd" drawn as an attachment is a lie about what
        // arrived. Keep the last component and nothing else.
        let leaf = decoded.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last
        guard let leaf, !leaf.isEmpty else { return nil }
        return String(leaf.prefix(nameCap))
    }

    /// Long enough for any real filename, short enough that a hostile one
    /// can't push the rest of a row off the screen.
    private static let nameCap = 120

    // MARK: - Structure

    private static func splitHeaderBody(_ data: Data) -> (String, Data)? {
        let crlfcrlf = Data([13, 10, 13, 10])
        let lflf = Data([10, 10])
        guard let sep = data.range(of: crlfcrlf) ?? data.range(of: lflf) else { return nil }
        return (String(decoding: data[..<sep.lowerBound], as: UTF8.self), data[sep.upperBound...])
    }

    /// Recurses into nested multipart (an `alternative` inside a `mixed`, the
    /// common shape with an attachment) preferring `text/plain`; a bare
    /// `text/html` part is stripped down to text as the fallback, never left
    /// raw. Returns nil when every part is an attachment or unreadable.
    private static func firstReadablePart(in data: Data, boundary: String) -> String? {
        guard let markerData = "--\(boundary)".data(using: .utf8) else { return nil }
        var htmlFallback: String?
        for part in split(data, on: markerData) {
            guard let (partHeaders, partBody) = splitHeaderBody(part) else { continue }
            let partType = headerValue("content-type", in: partHeaders) ?? "text/plain"
            let partCTE = headerValue("content-transfer-encoding", in: partHeaders) ?? "7bit"
            let partCharset = parameter("charset", in: partType) ?? "utf-8"
            let lowerType = partType.lowercased()
            if lowerType.contains("multipart"), let nested = parameter("boundary", in: partType) {
                if let found = firstReadablePart(in: partBody, boundary: nested) { return found }
                continue
            }
            if lowerType.contains("text/plain") {
                let decoded = decodeBody(partBody, encoding: partCTE, charset: partCharset)
                if !decoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return decoded }
            } else if lowerType.contains("text/html"), htmlFallback == nil {
                htmlFallback = htmlToPlainText(decodeBody(partBody, encoding: partCTE, charset: partCharset))
            }
            // Anything else (an attachment, an image) is skipped — never
            // decoded, never shown.
        }
        return htmlFallback
    }

    /// Splits on a MIME boundary marker, dropping the preamble and stopping
    /// at the `--boundary--` terminator.
    private static func split(_ data: Data, on marker: Data) -> [Data] {
        var parts: [Data] = []
        var search = data[...]
        while let r = search.range(of: marker) {
            let after = search[r.upperBound...]
            if after.first == UInt8(ascii: "-") { break }   // "--boundary--"
            guard let lineEnd = after.range(of: Data([13, 10]))?.upperBound
                ?? after.range(of: Data([10]))?.upperBound else { break }
            let rest = after[lineEnd...]
            if let next = rest.range(of: marker) {
                parts.append(Data(rest[..<next.lowerBound]))
                search = rest[next.lowerBound...]
            } else {
                parts.append(Data(rest))
                break
            }
        }
        return parts
    }

    // MARK: - Header parsing

    /// Unfolds RFC 822 header continuation lines (a value wrapped onto the
    /// next line with leading whitespace) before scanning — a folded
    /// Content-Type's boundary parameter otherwise reads as truncated.
    private static func headerValue(_ name: String, in headers: String) -> String? {
        let unfolded = headers.replacingOccurrences(
            of: "\r?\n[ \t]+", with: " ", options: .regularExpression)
        // NOT `split(separator: "\n")`: Swift's `Character` fuses "\r\n" into
        // ONE grapheme cluster, distinct from a lone "\n" — so splitting on
        // the Character "\n" never breaks a CRLF-terminated header block at
        // all, and every header here comes from `crlf`-joined IMAP text.
        // `isNewline` recognizes "\r\n"/"\n"/"\r" alike (caught by a
        // standalone MIME-decoder test harness, 2026-07-23 — every
        // header-keyed lookup silently returned the WHOLE remaining header
        // block instead of one line, so Content-Transfer-Encoding always
        // read as absent and every encoded body decoded as raw garbage).
        for line in unfolded.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = trimmed[..<colon].trimmingCharacters(in: .whitespaces)
            if key.caseInsensitiveCompare(name) == .orderedSame {
                return trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static func parameter(_ name: String, in headerValue: String) -> String? {
        guard let range = headerValue.range(
            of: "\(name)\\s*=\\s*\"?([^\";]+)\"?", options: [.regularExpression, .caseInsensitive]
        ) else { return nil }
        let match = String(headerValue[range])
        guard let eq = match.firstIndex(of: "=") else { return nil }
        return match[match.index(after: eq)...].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
    }

    // MARK: - Decoding

    private static func decodeBody(_ data: Data, encoding: String, charset: String) -> String {
        let raw: Data
        switch encoding.lowercased().trimmingCharacters(in: .whitespaces) {
        case "base64":
            let compact = String(decoding: data, as: UTF8.self).filter { !$0.isWhitespace }
            raw = Data(base64Encoded: compact) ?? data
        case "quoted-printable":
            raw = quotedPrintableDecode(data)
        default:
            raw = data
        }
        return decodedString(raw, charset: charset)
    }

    /// A soft line break ("=\r\n") is invisible in the decoded output; any
    /// other "=XX" is a hex-escaped byte. A trailing "=" with fewer than two
    /// hex digits left in the buffer (a truncated fetch cut a part mid-code)
    /// is dropped rather than mis-decoded.
    private static func quotedPrintableDecode(_ data: Data) -> Data {
        var out = Data()
        var i = data.startIndex
        while i < data.endIndex {
            let byte = data[i]
            if byte == UInt8(ascii: "="),
               let n1 = data.index(i, offsetBy: 1, limitedBy: data.endIndex), n1 < data.endIndex {
                if data[n1] == 13 || data[n1] == 10 {
                    // "=\r\n" or a bare "=\n" soft break.
                    let skip = (data[n1] == 13 && data.index(after: n1) < data.endIndex
                                && data[data.index(after: n1)] == 10) ? 3 : 2
                    i = data.index(i, offsetBy: skip, limitedBy: data.endIndex) ?? data.endIndex
                    continue
                }
                if let n2 = data.index(i, offsetBy: 2, limitedBy: data.endIndex), n2 < data.endIndex,
                   let hex = String(bytes: [data[n1], data[n2]], encoding: .ascii),
                   let value = UInt8(hex, radix: 16) {
                    out.append(value)
                    i = data.index(i, offsetBy: 3)
                    continue
                }
            }
            out.append(byte)
            i = data.index(after: i)
        }
        return out
    }

    private static func decodedString(_ data: Data, charset: String) -> String {
        let cs = charset.lowercased()
        if cs.contains("1252") || cs.contains("windows") {
            return String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
        }
        if cs.hasPrefix("iso-8859") || cs.contains("latin") {
            return String(data: data, encoding: .isoLatin1) ?? String(decoding: data, as: UTF8.self)
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? String(decoding: data, as: UTF8.self)
    }

    // MARK: - HTML fallback

    /// A crude tag strip, not a parser — good enough for "readable excerpt,"
    /// which is all the sheet needs. Block-level tags become newlines so
    /// paragraphs don't run together; everything else is dropped, then
    /// entities decode through the same table the rest of ingest already
    /// uses (RSS descriptions hit the identical shape).
    private static func htmlToPlainText(_ html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: "(?is)<(script|style)[^>]*>.*?</\\1>", with: "",
                                   options: .regularExpression)
        s = s.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?i)</p>|</div>|</li>|</tr>", with: "\n",
                                   options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return IngestSupport.decodeHTMLEntities(s)
    }

    // MARK: - Readability trim

    /// Strips a quoted-reply chain and a signature — the parts of an email
    /// nobody wants re-reading in a feed sheet. Best effort: a message with
    /// none of these markers is returned untouched (past a length cap, since
    /// a truncated fetch can still hand back tens of KB of unstructured
    /// text).
    private static func clean(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "\r\n", with: "\n")

        // A quoted reply chain — Mail/Gmail/Outlook all lead it with some
        // variant of "On <date>, <name> wrote:" right before the first
        // ">" line.
        if let r = s.range(of: "\\nOn .{0,160} wrote:\\n", options: [.regularExpression]) {
            s = String(s[..<r.lowerBound])
        }
        // The RFC 3676 signature delimiter — "-- " alone on its own line.
        if let r = s.range(of: "\\n-- ?\\n", options: [.regularExpression]) {
            s = String(s[..<r.lowerBound])
        }
        // A run into "> " quoted lines — cut at the first one rather than
        // showing a thread's worth of history under today's message.
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
        if let firstQuote = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(">") }) {
            s = lines[..<firstQuote].joined(separator: "\n")
        }

        s = s.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(s.prefix(4000))
    }
}
