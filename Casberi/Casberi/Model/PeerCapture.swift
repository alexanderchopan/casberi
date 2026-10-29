import Foundation

/// What Deposit captures from a payment app's own web page, and how it is
/// turned into the session Peer's enclave reads (prd §1598 item 2, §1606,
/// §1607). Pure: the sheet (`Screens/PeerCaptureSheet.swift`) hands it what
/// the page sent, and this decides what that was.
///
/// The template is Peer's (`api.zkp2p.xyz/providers/<platform>/<action>.json`),
/// read fresh for every Deposit: it names the page the person signs in on,
/// the one request whose answer lists their payments, and where in that
/// answer each payment's fields are. Cash App's (§1606), the one platform these tables hold so far: sign in at
/// `cash.app/account/activity`, and the page's own
/// `POST cash.app/cash-app/activity/v1.0/page` is captured as it is made.
///
/// What is captured is a credential. It is held in memory, sealed to the
/// enclave (`PeerSessionEnvelope`) and sent once; never stored, never
/// logged. Only the NAMES of what was captured are ever reported.
enum PeerCapture {

    struct Template: Equatable {
        var platform: String
        var actionType: String
        var authLink: URL
        var method: String
        var urlPattern: String
        var userAgent: String?
        var listPath: String
        var fields: [String: String]
        var paramNames: [String]
        var paramPaths: [String]
        var payLink: String?
    }

    /// Peer's template, refused unless every part Deposit relies on is
    /// there and the sign-in page is on the platform's own https host.
    static func template(json: [String: Any]) -> Template? {
        guard let platform = (json["metadata"] as? [String: Any])?["platform"] as? String,
              let actionType = json["actionType"] as? String,
              let auth = (json["authLink"] as? String).flatMap(URL.init(string:)), auth.scheme == "https",
              let host = auth.host(), onHost(host, hosts[platform]),
              let meta = json["metadata"] as? [String: Any],
              let method = (meta["method"] as? String ?? json["method"] as? String)?.uppercased(),
              let pattern = meta["urlRegex"] as? String, (try? NSRegularExpression(pattern: pattern)) != nil,
              let extraction = meta["transactionsExtraction"] as? [String: Any],
              let listPath = extraction["transactionJsonPathListSelector"] as? String,
              let fields = extraction["transactionJsonPathSelectors"] as? [String: String]
        else { return nil }
        let names = json["paramNames"] as? [String] ?? []
        let paths = (json["paramSelectors"] as? [[String: Any]] ?? []).compactMap { $0["value"] as? String }
        guard names.count == paths.count else { return nil }
        let mobile = json["mobile"] as? [String: Any]
        return Template(platform: platform, actionType: actionType, authLink: auth, method: method,
                        urlPattern: pattern,
                        userAgent: (mobile?["userAgent"] as? [String: String])?["ios"],
                        listPath: listPath, fields: fields, paramNames: names, paramPaths: paths,
                        payLink: (mobile?["external"] as? [String: Any])?["actionLink"] as? String)
    }

    /// The hosts each platform's sign-in may be on: a template pointing
    /// anywhere else is refused, since what is captured there is sealed and
    /// sent as that platform's session.
    static let hosts: [String: String] = ["cashapp": "cash.app"]
    /// Where each platform's pay link may go: its own app's web door.
    static let payHosts: [String: String] = ["cashapp": "cash.app"]

    static func onHost(_ host: String, _ declared: String?) -> Bool {
        guard let declared else { return false }
        let h = host.lowercased()
        return h == declared || h.hasSuffix("." + declared)
    }

    /// The request the template names: its method, and its whole URL
    /// against the pattern (anchored at both ends).
    static func isTarget(_ t: Template, method: String, url: String) -> Bool {
        guard method.uppercased() == t.method,
              let re = try? NSRegularExpression(pattern: "^(?:" + t.urlPattern + ")$") else { return false }
        return re.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil
    }

    /// What the enclave must find in a session, by platform, from
    /// `@zkp2p/zkp2p-attestation` 3.1.0's README ("Buyer TEE platform
    /// matrix"). Case is ignored: headers arrive as the page spelled them.
    static let required: [String: [String]] = [
        "cashapp": ["Cookie", "x-csrf-token", "x-device-name", "x-request-signature", "x-request-uuid",
                    "cash-web-request", "x-web-device-info", "x-web-context", "x-bt-id"],
    ]

    /// The session: every header the page sent, trimmed, the page's own
    /// User-Agent, every cookie the web view holds for the host (HttpOnly
    /// included) when the page's headers carried none, and the body.
    static func session(headers: [String: String], body: String?, cookies: [(name: String, value: String)],
                        userAgent: String) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in headers {
            let name = k.trimmingCharacters(in: .whitespaces), value = v.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { out[name] = value }
        }
        if !out.keys.contains(where: { $0.caseInsensitiveCompare("User-Agent") == .orderedSame }) {
            out["User-Agent"] = userAgent
        }
        if !out.keys.contains(where: { $0.caseInsensitiveCompare("Cookie") == .orderedSame }), !cookies.isEmpty {
            out["Cookie"] = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        }
        if let body, !body.isEmpty { out["body"] = body }
        return out
    }

    /// What the enclave requires that the session lacks — names only.
    static func missing(_ session: [String: String], platform: String) -> [String] {
        (required[platform] ?? []).filter { need in
            !session.keys.contains { $0.caseInsensitiveCompare(need) == .orderedSame }
        }
    }

    // MARK: - The payments the page listed

    struct Payment: Equatable {
        var index: Int
        var recipient: String?
        var amount: String?
        var date: String?
        var paymentId: String?
        var currency: String?
        var state: String?
    }

    static func payments(_ t: Template, in response: Any) -> [Payment] {
        guard let rows = value(at: t.listPath, in: response) as? [Any] else { return [] }
        return rows.enumerated().map { i, row in
            func field(_ name: String) -> String? {
                guard let path = t.fields[name], let v = value(at: path, in: row) else { return nil }
                if let s = v as? String { return s }
                if let n = v as? NSNumber { return n.stringValue }
                return nil
            }
            return Payment(index: i, recipient: field("recipient"), amount: field("amount"),
                           date: field("date"), paymentId: field("paymentId"),
                           currency: field("currency"), state: field("state"))
        }
    }

    /// The public params the verify call takes for the payment at `index`:
    /// each template param read at that row, and `index` itself.
    static func params(_ t: Template, in response: Any, index: Int) -> [String: String]? {
        var out = ["index": String(index)]
        for (name, path) in zip(t.paramNames, t.paramPaths) {
            let concrete = path.replacingOccurrences(of: "{{INDEX}}", with: String(index))
            guard let v = value(at: concrete, in: response) else { return nil }
            if let s = v as? String { out[name] = s }
            else if let n = v as? NSNumber { out[name] = n.stringValue }
            else { return nil }
        }
        return out
    }

    /// The JSONPath the templates use, and nothing more: `$`, `.key` and
    /// `[n]`. Anything else is no value, never a guess.
    static func value(at path: String, in root: Any) -> Any? {
        guard path.hasPrefix("$") else { return nil }
        var node: Any? = root
        var rest = Substring(path.dropFirst())
        while !rest.isEmpty, let current = node {
            if rest.hasPrefix(".") {
                rest = rest.dropFirst()
                let key = rest.prefix { $0 != "." && $0 != "[" }
                guard !key.isEmpty else { return nil }
                node = (current as? [String: Any])?[String(key)]
                rest = rest.dropFirst(key.count)
            } else if rest.hasPrefix("[") {
                guard let close = rest.firstIndex(of: "]"),
                      let n = Int(rest[rest.index(after: rest.startIndex)..<close]), n >= 0,
                      let list = current as? [Any], n < list.count
                else { return nil }
                node = list[n]
                rest = rest[rest.index(after: close)...]
            } else {
                return nil
            }
        }
        return rest.isEmpty ? node : nil
    }

    /// The page in the payment app that pays the seller, from the
    /// template's link: Cash App's `cash.app/{cashtag}/{amount}`.
    static func payURL(_ t: Template, recipient: String, amount: String) -> URL? {
        guard let link = t.payLink,
              let r = recipient.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let a = amount.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: link.replacingOccurrences(of: "{{RECIPIENT_ID}}", with: r)
                                       .replacingOccurrences(of: "{{AMOUNT}}", with: a)),
              url.scheme == "https", let host = url.host(),
              onHost(host, payHosts[t.platform])
        else { return nil }
        return url
    }
}
