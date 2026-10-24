import Foundation

/// Your own model (prd §1478, 2026-10-23): the person's own OpenAI-compatible
/// server — Ollama, LM Studio, llama.cpp, vLLM, Open WebUI — as an agent in
/// the composer, the same way Claude, ChatGPT and OpenRouter are. Asked for by
/// a user: "Just a base URL, an optional API key, and a model name. I run my
/// own model at home."
///
/// This file is the seat's PURE half — the address rule, what is stored where,
/// the tool-less memory and every sentence — so `scripts/own-model-selftest.sh`
/// can compile it whole against Foundation alone. The network (the connect
/// check, the models list, the request) lives beside the other providers in
/// `AgentAnswer.swift` and `AgentModels.swift`.
///
/// **"Configured" means an address is saved, not a key** (`AgentKey` reads
/// `address` for this seat). The key is optional: Ollama on a home network
/// asks for none (MEASURED 2026-10-23: `/v1/models` answers 200 with no header
/// and 200 with a bogus bearer), and a server behind a proxy may want one.
///
/// **Never "stays on your device."** The server is somebody's computer. The
/// honesty rule (prd §83) forbids the claim, so every line here says "the
/// address you gave" and nothing about where that is.
enum OwnModel {
    /// The catalogue name, the seat's `Thing.source`, the ledger's attribution.
    static let name = "Your own model"
    static let seatID = "ownmodel"

    static let addressKey = "ownmodel.address"
    /// `address|model` pairs the server refused `tools` for. A plain array in
    /// `UserDefaults`, keyed by address AND model id: the same model behind a
    /// different address is a different server build, and Ollama's refusal is
    /// per model (`gemma3:1b does not support tools`, `qwen2.5:1.5b` takes
    /// them — both MEASURED 2026-10-23).
    static let toollessKey = "ownmodel.toolless"

    /// The capability line, the one the connect page and the catalogue read
    /// (`AgentProvider.capabilityLine`).
    static let capabilityLine =
        "Answers on your own server. Remembers this chat's answers so far — screenshots and web search stay off."

    /// Where a question goes, wherever the other agents say it.
    static let privacyLine = "Goes to the address you gave. Casberi can't see what that server keeps."

    /// Under an `http` address, one line: plain text on the wire.
    static let httpLine = "Not encrypted. Anyone on your Wi-Fi could read what's sent."

    /// The address field's placeholder — Ollama's own port, on the host the
    /// simplest setup has: the same Mac, or a box on the home network.
    static func placeholder(isMac: Bool) -> String {
        isMac ? "localhost:11434" : "192.168.1.20:11434"
    }

    // MARK: - The address rule

    enum Address: Equatable {
        /// A usable base URL, no trailing slash, `/v1` appended when no path
        /// was typed.
        case ok(URL)
        case empty
        /// `user:pass@` — a credential belongs in the Key field, in the
        /// Keychain, never in a URL that is written to `UserDefaults`.
        case credentialInURL
        /// A scheme that is not `http` or `https`.
        case badScheme
        /// `http://` to a host outside the home network. Apple's ATS would
        /// refuse it anyway; refusing at the field says why before a question
        /// fails.
        case publicHTTP
        case invalid

        var url: URL? { if case .ok(let url) = self { return url } else { return nil } }

        /// The field's own sentence for a refusal; nil when it is fine or
        /// merely empty.
        var refusal: String? {
            switch self {
            case .ok, .empty:        nil
            case .credentialInURL:   "Put the key in the Key field, not in the address."
            case .badScheme:         "The address starts with http:// or https://."
            case .publicHTTP:        "Use https for an address outside your home network."
            case .invalid:           "That's not an address. Try host:port, like 192.168.1.20:11434."
            }
        }
    }

    /// Parses what is typed, in this order (the spec's rule):
    /// - no scheme → `http` for a local host, else `https`;
    /// - no path → `/v1` appended (Ollama, LM Studio, llama.cpp and vLLM all
    ///   serve the OpenAI shape there; MEASURED on Ollama: `/models` without
    ///   `/v1` is a 404); a typed path is kept as typed;
    /// - no port → the scheme's default, never a guessed 11434;
    /// - `user:pass@` refused; anything but http/https refused;
    /// - `http` only for a local host.
    static func parse(_ raw: String) -> Address {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .empty }
        guard !text.contains(" ") else { return .invalid }
        while text.hasSuffix("/") { text.removeLast() }
        let lower = text.lowercased()
        let hadScheme: Bool
        if let range = lower.range(of: "://") {
            let scheme = String(lower[..<range.lowerBound])
            guard scheme == "http" || scheme == "https" else { return .badScheme }
            hadScheme = true
        } else {
            // A bare `scheme:` with no slashes (`mailto:x`) has no host part
            // we could read; a `host:port` does. Tell them apart by whether
            // what follows the first colon is a port.
            hadScheme = false
        }
        // Parse with a stand-in scheme first so the host is readable before
        // the local-or-not decision picks the real one.
        let candidate = hadScheme ? text : "http://" + text
        guard let components = URLComponents(string: candidate),
              let host = components.host, !host.isEmpty
        else { return .invalid }
        if components.user != nil || components.password != nil { return .credentialInURL }
        // `host:port` where the port is not a number parses with a nil host
        // or fails above; a dotless word with a colon and letters is nonsense.
        if !hadScheme, text.contains(":"), components.port == nil,
           !text.lowercased().hasPrefix("[") { return .invalid }
        let local = isLocal(host: host)
        var out = components
        if hadScheme {
            if out.scheme?.lowercased() == "http", !local { return .publicHTTP }
        } else {
            out.scheme = local ? "http" : "https"
        }
        out.scheme = out.scheme?.lowercased()
        out.host = out.host?.lowercased()
        if out.path.isEmpty || out.path == "/" { out.path = "/v1" }
        out.query = nil
        out.fragment = nil
        guard let url = out.url else { return .invalid }
        return .ok(url)
    }

    /// Whether `http` is allowed to this host: `localhost`, loopback, `::1`,
    /// a `.local` name, a name with no dot (`nixbox`), and the private ranges
    /// `10/8`, `172.16/12`, `192.168/16`, `169.254/16` and Tailscale's
    /// `100.64/10`. Anything else is the public internet.
    static func isLocal(host rawHost: String) -> Bool {
        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host == "localhost" || host == "::1" { return true }
        if host.hasSuffix(".local") { return true }
        if let v4 = ipv4(host) {
            let (a, b) = (v4[0], v4[1])
            if a == 127 { return true }
            if a == 10 { return true }
            if a == 172, (16...31).contains(b) { return true }
            if a == 192, b == 168 { return true }
            if a == 169, b == 254 { return true }
            if a == 100, (64...127).contains(b) { return true }
            return false
        }
        // An IPv6 literal other than ::1 — link-local and unique-local are
        // private, the rest is not.
        if host.contains(":") {
            // The first group, compared whole: fe80::/10 link-local and
            // fc00::/7 unique-local.
            let group = host.split(separator: ":", omittingEmptySubsequences: false).first ?? ""
            return group == "fe80" || group.hasPrefix("fc") || group.hasPrefix("fd")
        }
        // A name with no dot resolves only on the local network (mDNS, a
        // router's own DNS, a Tailscale MagicDNS short name).
        return !host.contains(".")
    }

    private static func ipv4(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let bytes = parts.compactMap { Int($0) }
        guard bytes.count == 4, bytes.allSatisfy({ (0...255).contains($0) }) else { return nil }
        return bytes
    }

    /// The host (and port, when not the scheme's own) as the page states it:
    /// "192.168.1.20:11434", "localhost:11434", "models.example.org".
    static func hostLine(_ url: URL) -> String {
        guard let host = url.host() else { return url.absoluteString }
        if let port = url.port { return "\(host):\(port)" }
        return host
    }

    /// Whether the address is `http://` — the footnote's condition.
    static func isPlainHTTP(_ url: URL) -> Bool { url.scheme?.lowercased() == "http" }

    // MARK: - What is stored

    /// The saved address, as typed, or nil when none — which is the seat's
    /// "not configured". A plain `UserDefaults` read: a string, never a key.
    static var address: String? {
        let value = UserDefaults.standard.string(forKey: addressKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty ?? true) ? nil : value
    }

    /// The saved address, parsed. nil when none is saved or the saved one no
    /// longer parses (the rule tightened after it was saved).
    static var base: URL? { address.flatMap { parse($0).url } }

    /// Saves an address (nil removes it). A plain `UserDefaults` write from
    /// the page's own action, under no lock — the shape `AgentModelStore.set`
    /// has always had, and the one `defaults-lock-audit.py` (prd §721) allows;
    /// `DefaultsWrite` is for a write made while a lock is held, and none is.
    /// Bumps the vault generation so `AgentKey.configured`'s memo re-reads.
    static func setAddress(_ raw: String?) {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.isEmpty {
            UserDefaults.standard.removeObject(forKey: addressKey)
        } else {
            UserDefaults.standard.set(value, forKey: addressKey)
        }
        TokenVault.noteArrivals()
    }

    /// Everything this seat alone stores: the address and the tool memory.
    /// The key and the model choice go through `AgentKey.clear`'s shared path.
    static func forget() {
        UserDefaults.standard.removeObject(forKey: addressKey)
        UserDefaults.standard.removeObject(forKey: toollessKey)
        TokenVault.noteArrivals()
    }

    // MARK: - The tool-less memory

    /// Whether this model, at this address, refused a request carrying
    /// `tools` before — so later questions skip the failed round.
    static func isToolless(address: String, model: String) -> Bool {
        toolless.contains(toollessEntry(address: address, model: model))
    }

    static func rememberToolless(address: String, model: String) {
        var set = toolless
        set.insert(toollessEntry(address: address, model: model))
        UserDefaults.standard.set(Array(set).sorted(), forKey: toollessKey)
    }

    static func forgetToolless() { UserDefaults.standard.removeObject(forKey: toollessKey) }

    private static var toolless: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: toollessKey) ?? [])
    }

    static func toollessEntry(address: String, model: String) -> String {
        "\(address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(model)"
    }

    /// Whether a 400's body is the tool refusal. MEASURED (Ollama 0.40.9,
    /// 2026-10-23): HTTP **400** with `{"error":{"message":"registry.ollama.ai/
    /// library/gemma3:1b does not support tools","type":
    /// "invalid_request_error"}}`. Read off the body, never the status alone:
    /// a 400 for any other reason (a prompt past the context window) must not
    /// cost a tool-capable model its tools for good. llama.cpp and vLLM word
    /// it differently ("tools are not supported", "tool use is not
    /// supported"), so the test is "tool" beside "support", case-blind.
    static func namesToolRefusal(_ body: Data) -> Bool {
        let text = String(decoding: body, as: UTF8.self).lowercased()
        return text.contains("tool") && text.contains("support")
    }

    // MARK: - The connect check's sentences

    /// What the check found. `connected(models:)` carries the server's list
    /// (`/v1/models`, the OpenAI envelope — MEASURED on Ollama), empty when
    /// the server has no list (404) and the person typed a model.
    enum Check: Equatable {
        case connected(models: [String])
        /// 404 on `/models` and no model typed: the server has no list to
        /// fill the picker from, so the page needs a name.
        case needsModel
        /// 200 with an empty list and no model typed: the server runs but has
        /// no model yet (a fresh `ollama serve` before any pull).
        case noModels
        /// 401 with no key set.
        case wantsKey
        /// 401/403 with a key set.
        case keyRefused
        case unreachable
        /// 200 whose body is HTML: a web UI at that address (Open WebUI, a
        /// reverse proxy's landing page), its API on another port or path.
        /// MEASURED in the field (2026-10-24): a Tailscale-served host
        /// answered the envelope on `:8443` and a page on `443`.
        case webPage
        case other(Int)

        var line: String? {
            switch self {
            case .connected:       nil
            case .needsModel:      "That server lists no models. Type the model's name."
            case .noModels:        "That server has no models yet. Pull one, or type its name."
            case .wantsKey:        "That server wants a key."
            case .keyRefused:      "That key was refused."
            case .unreachable:     nil   // worded with the host, below
            case .webPage:
                "That address serves a web page, not the API. Ollama answers on its own port (host:11434); Open WebUI's API is under /api."
            // A 200 that is JSON but not the envelope: an API of some other
            // shape, or a base one path off.
            case .other(200):
                "That server answered, but not with a model list. Is the address the API's base, like host:11434/v1?"
            case .other(let code): "That server answered HTTP \(code). Is it an OpenAI-compatible server?"
            }
        }

        /// The unreachable sentence names the host: "Is it on, and are you on
        /// its network?" is the fix nine times in ten.
        static func unreachableLine(host: String) -> String {
            "Couldn't reach \(host). Is it on, and are you on its network?"
        }
    }

    /// Reads a models-list response into a `Check`, the one place the status
    /// codes are interpreted. `typedModel` decides whether a 404 is fine.
    static func check(status: Int?, data: Data?, hasKey: Bool, typedModel: String) -> Check {
        guard let status else { return .unreachable }
        switch status {
        case 200:
            let ids = modelIDs(data)
            // A 200 that is not the OpenAI envelope is not a connected
            // server: a web page says so by name, anything else by shape.
            guard let ids else { return looksLikeHTML(data) ? .webPage : .other(200) }
            if ids.isEmpty, typedModel.trimmingCharacters(in: .whitespaces).isEmpty { return .noModels }
            return .connected(models: ids)
        case 404:
            return typedModel.trimmingCharacters(in: .whitespaces).isEmpty
                ? .needsModel : .connected(models: [])
        case 401: return hasKey ? .keyRefused : .wantsKey
        case 403: return hasKey ? .keyRefused : .wantsKey
        default:  return .other(status)
        }
    }

    /// Whether a body is a web page: its first non-blank bytes open a tag
    /// (`<!doctype html>`, `<html`, `<!--`). Read off the body, never a
    /// Content-Type header, so a proxy that labels its page `text/plain`
    /// still says what it is.
    static func looksLikeHTML(_ data: Data?) -> Bool {
        guard let data else { return false }
        let head = String(decoding: data.prefix(256), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return head.hasPrefix("<")
    }

    /// `{ data: [ { id } ] }` → the ids, in the server's order; nil when the
    /// body is not that envelope.
    static func modelIDs(_ data: Data?) -> [String]? {
        guard let data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["data"] as? [[String: Any]]
        else { return nil }
        return entries.compactMap { $0["id"] as? String }
    }
}
