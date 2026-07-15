import Foundation

/// Write-backs (prd §67 goal ③) — closing the loop on a thing without
/// leaving Casberi, device→API direct with the token the bridge already
/// holds. The law (brief + prd §67): writes live in the SHEET, behind the
/// ask-before-acting confirm; a verb appears only when its bridge is
/// connected AND the thing carries the reference the API needs — never a
/// dead control. Bluesky writes wait on an authenticated read bridge
/// (a handle-only follow can't like).
enum BridgeWrite {
    /// Todoist: close the task the thing mirrors (`sourceRef` "todoist:<id>").
    case todoistComplete(taskID: String)
    /// GitHub: close the issue/PR the thing links (parsed from its html_url).
    case githubClose(owner: String, repo: String, number: Int)
}

enum BridgeWrites {

    /// The write verb a thing has earned, or nil. Reads only the cached
    /// connected-bridge snapshot (HandOffState) and the thing itself, so
    /// derivation stays safe off the main actor.
    static func write(for thing: Thing) -> BridgeWrite? {
        switch thing.source {
        case "Todoist":
            // A completed thing offers nothing — no dead re-complete.
            guard thing.mark != .done,
                  HandOffState.connectedBridges.contains("todoist"),
                  let ref = thing.sourceRef, ref.hasPrefix("todoist:") else { return nil }
            return .todoistComplete(taskID: String(ref.dropFirst("todoist:".count)))
        case "GitHub":
            guard thing.mark != .done,
                  HandOffState.connectedBridges.contains("github"),
                  let target = githubTarget(in: thing.content) else { return nil }
            return .githubClose(owner: target.owner, repo: target.repo, number: target.number)
        default:
            return nil
        }
    }

    /// The verb face a write wears in the sheet.
    static func label(for write: BridgeWrite) -> (label: String, icon: String) {
        switch write {
        case .todoistComplete: ("Complete in Todoist", "checkmark.circle")
        case .githubClose:     ("Close on GitHub", "checkmark.seal")
        }
    }

    /// Performs the write with the bridge's stored token. Returns the honest
    /// outcome line either way — the API's no is reported, never dressed up.
    static func perform(_ write: BridgeWrite) async -> (ok: Bool, line: String) {
        switch write {
        case .todoistComplete(let id):
            guard let token = TokenVault.get(TokenBridge.todoist.tokenKey) else {
                return (false, String(localized: "Todoist isn't connected anymore."))
            }
            let status = await send("POST",
                                    "https://api.todoist.com/api/v1/tasks/\(id)/close",
                                    token: token, body: nil)
            return status == 204
                ? (true, String(localized: "Completed in Todoist"))
                : (false, String(localized: "Todoist said no — the task may be gone, or the token can't write."))
        case .githubClose(let owner, let repo, let number):
            guard let token = TokenVault.get(TokenBridge.github.tokenKey) else {
                return (false, String(localized: "GitHub isn't connected anymore."))
            }
            let status = await send("PATCH",
                                    "https://api.github.com/repos/\(owner)/\(repo)/issues/\(number)",
                                    token: token, body: ["state": "closed"])
            return status == 200
                ? (true, String(localized: "Closed on GitHub"))
                : (false, String(localized: "GitHub said no — your token may be read-only, or the issue isn't yours to close."))
        }
    }

    /// owner/repo/number out of a github.com issue or pull-request link —
    /// the reference the REST API wants (the issues endpoint closes PRs too).
    static func githubTarget(in text: String) -> (owner: String, repo: String, number: Int)? {
        guard let url = Capture.detectURL(in: text),
              url.host()?.lowercased().hasSuffix("github.com") == true else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 4, parts[2] == "issues" || parts[2] == "pull",
              let number = Int(parts[3]) else { return nil }
        return (parts[0], parts[1], number)
    }

    private static func send(_ method: String, _ url: String,
                             token: String, body: [String: Any]?) async -> Int {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        request.timeoutInterval = 30
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            NSLog("[Casberi] BridgeWrites: network failure on %@", url)
            return -1
        }
        if !(200...299).contains(http.statusCode) {
            NSLog("[Casberi] BridgeWrites: HTTP %d on %@", http.statusCode, url)
        }
        return http.statusCode
    }
}
