import Foundation

/// GitHub's device flow (prd §67 goal ②) — OAuth with no secret and no
/// server: the app asks GitHub for a short code, the person approves it on
/// github.com in their own browser, and GitHub hands the token straight to
/// this iPhone. The client id is public by design (it names the app; it
/// unlocks nothing without the person's approval), so embedding it stays
/// honest — there is no secret to ship and no relay to run.
///
/// The token lands in the SAME Keychain slot the paste flow uses
/// (`token.github`), so sync, proof, and removal are unchanged.
enum GitHubDeviceFlow {

    /// The Casberi OAuth app's public client id (user-created 2026-07-14).
    /// Created at github.com → Settings → Developer settings → OAuth Apps
    /// (enable Device Flow), then pasted here. Empty = the setup screen
    /// shows the paste path only (honesty rule: no dead sign-in button).
    private static let shippedClientID = "Ov23liTnjAf9SSH0Pw9J"

    static var clientID: String {
        #if DEBUG
        // `-ghClientID <id>` tests the real flow before the id ships in code.
        if let override = UserDefaults.standard.string(forKey: "ghClientID"),
           !override.isEmpty { return override }
        #endif
        return shippedClientID
    }

    static var isAvailable: Bool { !clientID.isEmpty }

    /// `repo` because GitHub's classic OAuth has no read-only repo scope —
    /// it's the smallest scope that reaches private issues/PRs. Casberi never
    /// uses the write half of it: there is no write-back verb anywhere in the
    /// app (ruling 2026-07-15 — prd §67 goal ③ dropped; see BridgeWrites'
    /// removal). `gist` reaches your secret gists (the Gists feed), `read:user`
    /// your profile and events. The setup copy states this plainly.
    static let scope = "repo read:user gist"

    struct Code {
        let userCode: String
        let verificationURL: URL
        let deviceCode: String
        /// Seconds GitHub asks us to wait between polls.
        let interval: Int
        let expiresAt: Date
    }

    /// One poll's outcome. `pending` and `slowDown` keep the loop alive;
    /// everything else ends it.
    enum Poll {
        case token(String)
        case pending
        case slowDown
        case denied
        case expired
        case failed
    }

    /// Asks GitHub for a device code. nil on network failure or a rejected
    /// client id — the caller words it plainly.
    static func start() async -> Code? {
        guard isAvailable else { return nil }
        guard let root = await post("https://github.com/login/device/code",
                                    form: ["client_id": clientID, "scope": scope]),
              let userCode = root["user_code"] as? String,
              let device = root["device_code"] as? String,
              let uri = (root["verification_uri"] as? String).flatMap(URL.init(string:))
        else {
            NSLog("[Casberi] GitHubDeviceFlow: start failed")
            return nil
        }
        let interval = root["interval"] as? Int ?? 5
        let expires = root["expires_in"] as? Int ?? 900
        return Code(userCode: userCode, verificationURL: uri, deviceCode: device,
                    interval: interval, expiresAt: .now.addingTimeInterval(Double(expires)))
    }

    /// One poll against the token endpoint. The caller loops on the code's
    /// interval (plus GitHub's slow-down nudges) until a terminal outcome.
    static func poll(_ code: Code) async -> Poll {
        guard Date.now < code.expiresAt else { return .expired }
        guard let root = await post("https://github.com/login/oauth/access_token",
                                    form: ["client_id": clientID,
                                           "device_code": code.deviceCode,
                                           "grant_type": "urn:ietf:params:oauth:grant-type:device_code"])
        else { return .failed }
        if let token = root["access_token"] as? String, !token.isEmpty {
            return .token(token)
        }
        switch root["error"] as? String {
        case "authorization_pending": return .pending
        case "slow_down": return .slowDown
        case "expired_token": return .expired
        case "access_denied": return .denied
        default:
            NSLog("[Casberi] GitHubDeviceFlow: poll error %@",
                  (root["error"] as? String) ?? "unknown")
            return .failed
        }
    }

    /// Form-encoded POST with a JSON reply — the shape both endpoints speak.
    private static func post(_ url: String, form: [String: String]) async -> [String: Any]? {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        request.timeoutInterval = 30
        NetworkLedger.shared.record(request)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return root
    }
}
