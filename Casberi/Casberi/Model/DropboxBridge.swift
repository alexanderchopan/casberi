import Foundation
import AuthenticationServices
import CryptoKit
import SwiftData

/// The Dropbox bridge (2026-07-27) — a first-class seat beside Files/Obsidian,
/// but reading Dropbox's own API instead of a local folder bookmark: OAuth
/// with PKCE, run entirely by this iPhone (no server holds a secret), scoped
/// read-only (`files.metadata.read` + `files.content.read`), and synced with
/// Dropbox's own delta cursor (`list_folder` once, then `list_folder/continue`
/// forever after) — the cheapest possible read, and the one that turns a
/// delete into news for free instead of something a re-walk has to infer.
///
/// Deliberately scoped to your OWN folders — the setup screen's folder field,
/// never "shared with me" or a shared link. That is the whole pitch: your
/// Dropbox, without the notifications. A stranger sharing something with you
/// can never make it appear here, because nothing outside the folder you
/// named is ever read.
///
/// ACTIVE (2026-07-27): the app key below is the user's registered "Scoped
/// App" (Full Dropbox access, not the sandboxed "App Folder" mode Dropbox
/// defaults new apps to — that would confine every read to one
/// Dropbox-managed folder, breaking the setup screen's arbitrary folder
/// field; the first app registered came up App Folder, so this is the
/// replacement). An app key is not a secret — PKCE needs nothing else.
/// `redirectURI` below is confirmed accepted verbatim in Dropbox's Redirect
/// URIs field — no custom-scheme rejection, no forwarding-page trick needed
/// (unlike `RedditAuth`'s form). Permissions must still be granted on THIS
/// app in its Permissions tab: `files.metadata.read` + `files.content.read`
/// checked, nothing else.
enum DropboxAuth {

    /// From dropbox.com/developers/apps — empty means the bridge is off.
    static let clientID = "15eqq1oif17407x"
    static let redirectURI = "casberi://dropbox-auth"
    static var ready: Bool { !clientID.isEmpty }

    private static let tokenKey = "token.dropbox"          // access token
    private static let refreshKey = "token.dropbox.refresh"
    private static let expiryKey = "dropbox.token.expiry"

    static var connected: Bool { TokenVault.get(refreshKey) != nil }

    static func disconnect() {
        TokenVault.delete(tokenKey)
        TokenVault.delete(refreshKey)
        UserDefaults.standard.removeObject(forKey: expiryKey)
    }

    // MARK: - Sign in (PKCE: verifier stays here, challenge goes out)

    @MainActor
    static func signIn() async -> Bool {
        guard ready else { return false }
        let verifier = randomVerifier()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64URLEncoded()

        var auth = URLComponents(string: "https://www.dropbox.com/oauth2/authorize")!
        auth.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            // Offline access is what earns a refresh token — otherwise the
            // access token expires in 4h with no way to renew it silently.
            URLQueryItem(name: "token_access_type", value: "offline"),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
        ]
        guard let url = auth.url,
              let callback = await presentAuth(url: url) else { return false }

        guard let comps = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              let code = comps.queryItems?.first(where: { $0.name == "code" })?.value
        else { return false }

        return await exchange(form: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ])
    }

    /// A live access token — refreshed through the stored refresh token when
    /// the current one has expired.
    static func accessToken() async -> String? {
        let expiry = UserDefaults.standard.double(forKey: expiryKey)
        if let token = TokenVault.get(tokenKey),
           Date.now.timeIntervalSince1970 < expiry - 60 {
            return token
        }
        guard let refresh = TokenVault.get(refreshKey) else { return nil }
        let ok = await exchange(form: [
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": clientID,
        ])
        return ok ? TokenVault.get(tokenKey) : nil
    }

    private static func exchange(form: [String: String]) async -> Bool {
        var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String else { return false }
        TokenVault.set(access, for: tokenKey)
        if let refresh = json["refresh_token"] as? String {
            TokenVault.set(refresh, for: refreshKey)
        }
        let lifetime = (json["expires_in"] as? Double) ?? 14400
        UserDefaults.standard.set(Date.now.timeIntervalSince1970 + lifetime,
                                  forKey: expiryKey)
        return true
    }

    @MainActor
    private static func presentAuth(url: URL) async -> URL? {
        await withCheckedContinuation { cont in
            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: "casberi"
            ) { callback, _ in
                cont.resume(returning: callback)
            }
            session.presentationContextProvider = DropboxAuthPresenter.shared
            if !session.start() { cont.resume(returning: nil) }
        }
    }

    private static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }
}

private final class DropboxAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = DropboxAuthPresenter()
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}

private extension Data {
    /// Base64url, the OAuth flavor — no padding, URL-safe alphabet.
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Folder scope + sync cursor

/// The folder this seat reads, and Dropbox's own delta cursor for it. A
/// changed folder invalidates the cursor — it was scoped to the OLD
/// `list_folder` call, so a new one must start fresh from the new path.
@Observable
final class DropboxStore {
    static let shared = DropboxStore()
    private static let folderKey = "dropbox.folder"
    private static let cursorKey = "dropbox.cursor"

    /// Dropbox's own root is `""`, not `"/"` — an empty field means "read
    /// everything," stated honestly in the setup screen rather than defaulted
    /// silently, since "everything" is a real, load-bearing choice here (the
    /// whole reason this bridge stays quiet is that it only ever reads
    /// folders you named).
    var folderPath: String {
        didSet { UserDefaults.standard.set(folderPath, forKey: Self.folderKey) }
    }

    private init() {
        folderPath = UserDefaults.standard.string(forKey: Self.folderKey) ?? ""
    }

    var connected: Bool { DropboxAuth.connected }

    var cursor: String? {
        get { UserDefaults.standard.string(forKey: Self.cursorKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.cursorKey) }
    }

    /// Points the seat at a new folder — clears the cursor, since a delta
    /// cursor from the old scope can't answer for the new one.
    func setFolder(_ path: String) {
        folderPath = path
        cursor = nil
    }

    func disconnect() {
        DropboxAuth.disconnect()
        UserDefaults.standard.removeObject(forKey: Self.cursorKey)
        folderPath = ""
    }
}

// MARK: - Ingest

enum DropboxIngest {

    @MainActor private static var running = false

    /// Same short list `FilesIngest` reads as text for a preview — everything
    /// else lands with just its size, since a binary's bytes aren't a useful
    /// preview and misdecoding them isn't worth the risk.
    private static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "csv", "tsv", "json", "log", "yaml", "yml",
        "xml", "html", "htm", "rtf", "swift", "py", "js", "ts", "css",
    ]

    /// Drains at most this many `/continue` pages in one foreground pass — a
    /// bulk upstream change (a big folder move) shouldn't turn one refresh
    /// into an unbounded loop; the cursor picks back up next time.
    private static let maxContinuePages = 10

    /// Syncs the connected folder: `list_folder` the first time (newest-ish
    /// 100, one page — a bounded seed, not a full recursive mirror), then
    /// Dropbox's own delta cursor (`list_folder/continue`) every time after,
    /// which is the whole reason this bridge is cheap: a `continue` call
    /// returns ONLY what changed, deletes included. Deletes drive the same
    /// delete-sync every other heal runs — reading a delta stream just means
    /// the deletion arrives with everything else instead of needing its own
    /// separate reconcile pass.
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        let store = DropboxStore.shared
        guard store.connected, !running else { return store.connected ? 0 : nil }
        running = true
        defer { running = false }

        guard let token = await DropboxAuth.accessToken() else { return nil }

        var entries: [[String: Any]] = []
        if let cursor = store.cursor {
            var current = cursor
            var pages = 0
            while pages < maxContinuePages {
                guard let root = await IngestSupport.postJSON(
                    "https://api.dropboxapi.com/2/files/list_folder/continue",
                    auth: "Bearer \(token)", body: ["cursor": current]) as? [String: Any]
                else { break }
                entries += (root["entries"] as? [[String: Any]]) ?? []
                if let newCursor = root["cursor"] as? String {
                    current = newCursor
                    store.cursor = current
                }
                pages += 1
                if (root["has_more"] as? Bool) != true { break }
            }
        } else {
            guard let root = await IngestSupport.postJSON(
                "https://api.dropboxapi.com/2/files/list_folder",
                auth: "Bearer \(token)",
                body: ["path": store.folderPath, "recursive": true, "limit": 100]
            ) as? [String: Any] else { return nil }
            entries = (root["entries"] as? [[String: Any]]) ?? []
            if let newCursor = root["cursor"] as? String { store.cursor = newCursor }
        }

        let existing = IngestSupport.existingSourceRefs(context, source: "Dropbox")
        var toDelete: [String: Thing]?
        var added = 0
        var removed = 0

        for entry in entries {
            guard let tag = entry[".tag"] as? String,
                  let pathLower = entry["path_lower"] as? String else { continue }
            let ref = "dropbox:\(pathLower)"

            if tag == "deleted" {
                if toDelete == nil { toDelete = IngestSupport.thingsByRef(context, source: "Dropbox") }
                if let thing = toDelete?[ref] {
                    context.delete(thing)
                    removed += 1
                }
                continue
            }
            guard tag == "file", let id = entry["id"] as? String,
                  !existing.contains(ref) else { continue }

            let name = (entry["name"] as? String) ?? (pathLower as NSString).lastPathComponent
            let size = (entry["size"] as? Int64) ?? Int64((entry["size"] as? Int) ?? 0)
            let modified = IngestSupport.isoDate(entry["client_modified"]) ?? .now
            let preview = await preview(id: id, name: name, size: size, token: token)

            let thing = Thing(
                kind: .file,
                title: name,
                content: preview,
                source: "Dropbox",
                capturedAt: modified,
                sourceRef: ref
            )
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        if added > 0 || removed > 0 { context.saveHonestly() }
        return added
    }

    /// A short line describing a landed file — its text (readable formats,
    /// first 300 chars of a RANGED download so a large file costs one small
    /// request, never a full fetch) or just its size, exactly like `FilesIngest`'s
    /// local equivalent.
    private static func preview(id: String, name: String, size: Int64, token: String) async -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        guard textExtensions.contains(ext),
              let text = await downloadRange(id: id, token: token) else {
            return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
        return String(text.prefix(300))
    }

    /// The first ~2KB of a file's bytes, decoded as UTF8 — enough for a
    /// three-line preview without paying for the whole file. Targets the
    /// Dropbox file ID rather than its path in the `Dropbox-API-Arg` header:
    /// an id is always plain ASCII, so it sidesteps the header's non-ASCII
    /// escaping rules a path with unicode/spaces would otherwise need.
    private static func downloadRange(id: String, token: String) async -> String? {
        guard let arg = try? JSONSerialization.data(withJSONObject: ["path": id]),
              let argString = String(data: arg, encoding: .utf8) else { return nil }
        var request = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/download")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(argString, forHTTPHeaderField: "Dropbox-API-Arg")
        request.setValue("bytes=0-2047", forHTTPHeaderField: "Range")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...206).contains(http.statusCode) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
