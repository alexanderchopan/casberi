import Foundation
import SwiftData

/// The token bridges (2026-07-07) — Readwise, GitHub, Todoist, Raindrop.
/// Each of these apps hands its users a personal access token in settings;
/// pasting it here is the sanctioned client-side way in — no OAuth server,
/// no secrets of ours to hold. The token goes to the Keychain (TokenVault)
/// and every fetch goes straight from this iPhone to the app's own API.
enum TokenBridge: String, CaseIterable, Identifiable {
    case readwise = "Readwise"
    case github   = "GitHub"
    case todoist  = "Todoist"
    case raindrop = "Raindrop"
    case calcom   = "Cal.com"
    case calendly = "Calendly"
    case notion   = "Notion"
    case linear   = "Linear"
    case bitrefill = "Bitrefill"
    case privacy  = "Privacy"
    case oneclaw  = "1Claw"

    var id: String { rawValue }

    /// BridgeStore id, and the connected-strip route.
    var bridgeID: String {
        switch self {
        case .readwise: "readwise"
        case .github:   "github"
        case .todoist:  "todoist"
        case .raindrop: "raindrop"
        case .calcom:   "calcom"
        case .calendly: "calendly"
        case .notion:   "notion"
        case .linear:   "linear"
        case .bitrefill: "bitrefill"
        case .privacy:  "privacy"
        case .oneclaw:  "oneclaw"
        }
    }

    var tokenKey: String { "token.\(bridgeID)" }
    var connected: Bool { TokenVault.get(tokenKey) != nil }

    /// Where the person finds their token — stated plainly, step by step.
    var steps: [String] {
        switch self {
        case .readwise: [
            "Open readwise.io/access_token in a browser.",
            "Sign in if asked — the token appears on the page.",
            "Copy it and paste it below."]
        case .github: [
            "Open github.com → Settings → Developer settings → Personal access tokens.",
            "Generate a token with read-only access to your repositories, gists, and profile — enough for every feed.",
            "Copy it and paste it below."]
        case .todoist: [
            "Open Todoist → Settings → Integrations → Developer.",
            "Copy the API token shown there.",
            "Paste it below."]
        case .raindrop: [
            "Open app.raindrop.io → Settings → Integrations → For Developers.",
            "Create an app, then copy its Test token.",
            "Paste it below."]
        case .calcom: [
            "Open app.cal.com → Settings → Developer → API keys.",
            "Add a new key — it starts with cal_live_.",
            "Copy it and paste it below."]
        case .calendly: [
            "Open Calendly → Integrations → API & Webhooks.",
            "Generate a personal access token.",
            "Copy it and paste it below."]
        case .notion: [
            "Open notion.so/my-integrations and create an internal integration.",
            "Copy its Internal Integration Secret and paste it below.",
            "In Notion, open each page you want here → ⋯ → Connections → add your integration. Only connected pages land."]
        case .linear: [
            "Open Linear → Settings → Security & access → Personal API keys.",
            "Create a key — read access is enough.",
            "Copy it and paste it below."]
        case .bitrefill: [
            "Open bitrefill.com/account/developers in a browser.",
            "In the API Keys tab, create a key — any name works.",
            "Copy it and paste it below."]
        case .privacy: [
            "Open privacy.com → account → API (a paid Privacy plan is required).",
            "Generate an API key.",
            "Copy it and paste it below."]
        case .oneclaw: [
            "Open 1claw.xyz in a browser and sign in.",
            "Create an agent (or open one) and copy its API key — it starts with ocv_.",
            "Paste it below."]
        }
    }

    var placeholder: String {
        switch self {
        case .readwise: "Access token"
        case .github:   "github_pat_…"
        case .todoist:  "API token"
        case .raindrop: "Test token"
        case .calcom:   "cal_live_…"
        case .calendly: "Personal access token"
        case .notion:   "ntn_…"
        case .linear:   "lin_api_…"
        case .bitrefill: "API key"
        case .privacy:  "API key"
        case .oneclaw:  "ocv_…"
        }
    }

    /// What lands, for proof lines: "12 highlights in".
    var noun: String {
        switch self {
        case .readwise: "highlights"
        case .github:   "items"
        case .todoist:  "tasks"
        case .raindrop: "bookmarks"
        case .calcom:   "bookings"
        case .calendly: "meetings"
        case .notion:   "pages"
        case .linear:   "issues"
        case .bitrefill: "orders"
        case .privacy:  "purchases"
        case .oneclaw:  "grants"
        }
    }

    var canLine: String {
        switch self {
        case .readwise: "Reads your highlights."
        case .github:   "Reads the GitHub feeds you pick — issues, notifications, stars, releases, gists, contributions, watched repos — plus any repos you watch privately, never touching your GitHub account."
        case .todoist:  "Reads your open tasks."
        case .raindrop: "Reads your bookmarks."
        case .calcom:   "Reads your bookings."
        case .calendly: "Reads your scheduled meetings."
        case .notion:   "Reads the pages you connect."
        case .linear:   "Reads issues assigned to you."
        case .bitrefill: "Reads your orders, refills, and balance — nothing here ever buys, pays, or spends."
        case .privacy:  "Reads your card transactions only. Privacy's key isn't scoped read-only — it could also manage cards on your account — so Casberi keeps the read-only promise by conduct: it never creates, closes, or funds a card."
        case .oneclaw:  "Reads which vaults and secret paths the key can reach — names and permissions only. Nothing here ever reads a secret's value, signs, or spends."
        }
    }

    /// Bridge-specific teardown beyond the token itself — a hook the remove
    /// path calls so a bridge that caches non-thing state (a reading, not a
    /// Thing) drops it when disconnected, and a reconnected DIFFERENT account
    /// never wears the prior one's cache. Most bridges hold nothing extra.
    func onRemove() {
        switch self {
        case .bitrefill: BitrefillBalance.clear()
        case .oneclaw:   OneClawAccess.clear()
        default:         break
        }
    }
}

enum TokenIngest {

    @MainActor private static var running: Set<TokenBridge> = []

    /// Fetches with the stored token and lands new things. Returns the new
    /// count, or nil when there's no token, the token is rejected, or the
    /// network fails — callers word that as "check the token".
    @MainActor
    static func refresh(_ bridge: TokenBridge, context: ModelContext) async -> Int? {
        guard let token = TokenVault.get(bridge.tokenKey), !running.contains(bridge) else {
            return running.contains(bridge) ? 0 : nil
        }
        running.insert(bridge)
        defer { running.remove(bridge) }

        guard let incoming = await fetch(bridge, token: token, context: context) else { return nil }

        // Linear's issue state is the one field here that CHANGES after
        // landing (2026-07-22) — an issue closed in Linear must stop reading
        // as open in the feed. Runs before the dedupe below, which by design
        // never revisits a known ref.
        if bridge == .linear { reconcileLinear(incoming, context: context) }

        var existing = IngestSupport.existingSourceRefs(context)
        // One backfill per source string the items actually carry — no
        // assumption that a fetch is single-source, and the lazy artless
        // fetch never runs for the bridges that don't set images.
        var backfills: [String: ArtlessBackfill] = [:]
        var added = 0
        for item in incoming {
            guard let ref = item.sourceRef else { continue }
            if existing.contains(ref) {
                let backfill = backfills[item.source]
                    ?? ArtlessBackfill(context, source: item.source)
                backfills[item.source] = backfill
                backfill.patch(ref, image: item.previewImageURL)
                continue
            }
            context.insert(item)
            existing.insert(ref)
            SpotlightIndex.index([item])
            added += 1
        }
        if added > 0 || backfills.values.contains(where: \.any) { context.saveHonestly() }
        return added
    }

    // MARK: - Per-app fetches (each is one or two GETs against the app's own API)

    @MainActor
    private static func fetch(_ bridge: TokenBridge, token: String, context: ModelContext) async -> [Thing]? {
        switch bridge {
        case .readwise: await readwise(token)
        case .github:   await github(token, context: context)
        case .todoist:  await todoist(token)
        case .raindrop: await raindrop(token)
        case .calcom:   await calcom(token)
        case .calendly: await calendly(token)
        case .notion:   await notion(token)
        case .linear:   await linear(token)
        case .bitrefill: await BitrefillFetch.things(token: token)
        case .privacy:  await PrivacyFetch.things(token: token)
        case .oneclaw:  await OneClawFetch.things(token: token, context: context)
        }
    }

    /// Readwise export API — books with nested highlights. Newest 30 land.
    private static func readwise(_ token: String) async -> [Thing]? {
        guard let root = await IngestSupport.getJSON("https://readwise.io/api/v2/export/",
                                   auth: "Token \(token)") as? [String: Any],
              let books = root["results"] as? [[String: Any]] else { return nil }
        var all: [(Date, Thing)] = []
        for book in books {
            let source = [book["title"] as? String, book["author"] as? String]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
            // The book's cover leads every one of its highlights — scrolling
            // groups them visually by what you were reading.
            let cover = IngestSupport.imageURL(book["cover_image_url"] as? String)
            for h in (book["highlights"] as? [[String: Any]]) ?? [] {
                guard let id = h["id"], let text = h["text"] as? String, !text.isEmpty
                else { continue }
                let when = IngestSupport.isoDate(h["highlighted_at"]) ?? .now
                let thing = Thing(
                    kind: .note,
                    title: IngestSupport.titleLine(text),
                    content: source,
                    source: "Readwise",
                    capturedAt: when,
                    sourceRef: "readwise:\(id)"
                )
                thing.previewImageURL = cover
                all.append((when, thing))
            }
        }
        return all.sorted { $0.0 > $1.0 }.prefix(30).map(\.1)
    }

    /// GitHub — the feeds the person turned on (Stars, New releases, Gists,
    /// Contributions, Watched repos, Notifications, and the original Issues &
    /// PRs), plus any repos watched directly (`GitHubRepoWatch`). Each is a
    /// GET or two against GitHub's own API; `GitHubFeedFetch` builds the things.
    @MainActor
    private static func github(_ token: String, context: ModelContext) async -> [Thing]? {
        await GitHubFeedFetch.all(token: token, context: context)
    }

    /// Todoist — open tasks, newest 30.
    private static func todoist(_ token: String) async -> [Thing]? {
        // The unified v1 API (2026-07-13: REST v2 answers 410 Gone for
        // everything now — the write probe caught it). v1 wraps lists in
        // `results`, renamed `created_at` → `added_at`, and dropped the
        // task `url` field (built from the id instead).
        guard let root = await IngestSupport.getJSON("https://api.todoist.com/api/v1/tasks",
                                    auth: "Bearer \(token)") as? [String: Any],
              let tasks = root["results"] as? [[String: Any]]
        else { return nil }
        let sorted = tasks.sorted {
            (($0["added_at"] as? String) ?? "") > (($1["added_at"] as? String) ?? "")
        }
        return sorted.prefix(30).compactMap { task in
            guard let id = task["id"] as? String,
                  let content = task["content"] as? String, !content.isEmpty
            else { return nil }
            return Thing(
                kind: .reminder,
                title: content,
                content: "https://app.todoist.com/app/task/\(id)",
                source: "Todoist",
                capturedAt: IngestSupport.isoDate(task["added_at"] ?? task["created_at"]) ?? .now,
                sourceRef: "todoist:\(id)"
            )
        }
    }

    /// Cal.com — your bookings, newest first. The v2 API dates its schema
    /// with a required header.
    private static func calcom(_ token: String) async -> [Thing]? {
        guard let root = await IngestSupport.getJSON("https://api.cal.com/v2/bookings?sortStart=desc&limit=30",
                                   auth: "Bearer \(token)",
                                   headers: ["cal-api-version": "2026-05-01"]) as? [String: Any],
              let bookings = root["data"] as? [[String: Any]] else { return nil }
        return bookings.compactMap { booking in
            guard let uid = booking["uid"] as? String,
                  let title = booking["title"] as? String,
                  (booking["status"] as? String) != "cancelled" else { return nil }
            return Thing(
                kind: .event,
                title: title,
                content: "https://app.cal.com/booking/\(uid)",
                source: "Cal.com",
                capturedAt: IngestSupport.isoDate(booking["start"]) ?? .now,
                sourceRef: "calcom:\(uid)"
            )
        }
    }

    /// Calendly — who you are first, then your scheduled meetings.
    private static func calendly(_ token: String) async -> [Thing]? {
        guard let me = await IngestSupport.getJSON("https://api.calendly.com/users/me",
                                 auth: "Bearer \(token)") as? [String: Any],
              let userURI = (me["resource"] as? [String: Any])?["uri"] as? String
        else { return nil }
        guard let root = await IngestSupport.getJSON(
            "https://api.calendly.com/scheduled_events?user=\(userURI)&count=30&sort=start_time:desc",
            auth: "Bearer \(token)") as? [String: Any],
              let events = root["collection"] as? [[String: Any]] else { return nil }
        return events.compactMap { event in
            guard let uri = event["uri"] as? String,
                  let name = event["name"] as? String,
                  (event["status"] as? String) != "canceled" else { return nil }
            let id = uri.split(separator: "/").last.map(String.init) ?? uri
            let join = (event["location"] as? [String: Any])?["join_url"] as? String
            return Thing(
                kind: .event,
                title: name,
                content: join ?? "",
                source: "Calendly",
                capturedAt: IngestSupport.isoDate(event["start_time"]) ?? .now,
                sourceRef: "calendly:\(id)"
            )
        }
    }

    /// Notion — the pages connected to your integration, newest edits first.
    /// Pages only, by ruling — databases stay behind.
    private static func notion(_ token: String) async -> [Thing]? {
        guard let root = await IngestSupport.postJSON("https://api.notion.com/v1/search",
                                    auth: "Bearer \(token)",
                                    body: ["filter": ["value": "page", "property": "object"],
                                           "sort": ["direction": "descending",
                                                    "timestamp": "last_edited_time"],
                                           "page_size": 30],
                                    headers: ["Notion-Version": "2022-06-28"]) as? [String: Any],
              let results = root["results"] as? [[String: Any]] else { return nil }
        return results.compactMap { page in
            guard page["object"] as? String == "page",
                  (page["archived"] as? Bool) != true,
                  (page["in_trash"] as? Bool) != true,
                  let id = page["id"] as? String,
                  let url = page["url"] as? String else { return nil }
            // The title lives in whichever property carries the title type.
            let props = (page["properties"] as? [String: Any]) ?? [:]
            var title = ""
            for prop in props.values {
                guard let p = prop as? [String: Any], p["type"] as? String == "title",
                      let parts = p["title"] as? [[String: Any]] else { continue }
                title = parts.compactMap { $0["plain_text"] as? String }.joined()
                break
            }
            guard !title.isEmpty else { return nil }
            return Thing(
                kind: .note,
                title: title,
                content: url,
                source: "Notion",
                capturedAt: IngestSupport.isoDate(page["last_edited_time"]) ?? .now,
                sourceRef: "notion:\(id)"
            )
        }
    }

    /// Linear — issues assigned to you, via its GraphQL API. Personal keys
    /// ride the Authorization header bare, no Bearer.
    private static func linear(_ token: String) async -> [Thing]? {
        // `state { type }` rides along (2026-07-22) so a Linear row can SHOW
        // whether it's open — until now a closed issue looked identical to an
        // active one — and so the feed head can state where the work sits.
        // `type` not `name`: names are per-team and user-renameable ("In
        // Review", "Shipping"), the type enum is Linear's own fixed
        // vocabulary, so the mapping can't drift with someone's workflow.
        let query = """
        { viewer { assignedIssues(first: 30, orderBy: updatedAt) \
        { nodes { id identifier title url updatedAt state { type } } } } }
        """
        guard let root = await IngestSupport.postJSON("https://api.linear.app/graphql",
                                    auth: token,
                                    body: ["query": query]) as? [String: Any],
              let data = root["data"] as? [String: Any],
              let viewer = data["viewer"] as? [String: Any],
              let assigned = viewer["assignedIssues"] as? [String: Any],
              let nodes = assigned["nodes"] as? [[String: Any]] else { return nil }
        return nodes.compactMap { node in
            guard let id = node["id"] as? String,
                  let title = node["title"] as? String,
                  let url = node["url"] as? String else { return nil }
            let ident = node["identifier"] as? String
            let thing = Thing(
                kind: .link,
                title: ident.map { "\($0) · \(title)" } ?? title,
                content: url,
                source: "Linear",
                capturedAt: IngestSupport.isoDate(node["updatedAt"]) ?? .now,
                sourceRef: "linear:\(id)"
            )
            thing.mark = linearMark((node["state"] as? [String: Any])?["type"] as? String)
            return thing
        }
    }

    /// Linear's own state vocabulary → the corpus's mark. An unknown type
    /// (Linear adding one, or the field absent on an older sync) stays
    /// `.none` — a mark we can't justify is worse than no mark, and the row
    /// simply reads as it did before.
    ///
    /// The seven types are not guessed: Linear's schema states them on the
    /// field itself, read by introspection 2026-07-22 — "One of triage,
    /// backlog, unstarted, started, completed, canceled, duplicate". That
    /// read is what caught `duplicate`, which an intuition-written table
    /// would have dropped into `.none` and left reading as open forever.
    ///
    /// `canceled` and `duplicate` map to `.done` deliberately: all three
    /// closing types mean the issue left your plate, which is what the row's
    /// strikethrough and the "Done" segment claim. Calling either "todo"
    /// would keep it in your open count for good.
    private static func linearMark(_ type: String?) -> Mark {
        switch type {
        case "backlog", "unstarted", "triage":       return .todo
        case "started":                              return .doing
        case "completed", "canceled", "duplicate":   return .done
        default:                                     return .none
        }
    }

    /// Re-marks Linear things already in the corpus on every sync — an issue
    /// you closed elsewhere has to stop reading as open here. Dedupe skips
    /// re-landing a known `sourceRef`, so without this the state stamped at
    /// first sight would be frozen forever (the same reconciliation
    /// `ScheduleIngest` does for a reminder completed in the Reminders app).
    @MainActor
    static func reconcileLinear(_ fresh: [Thing], context: ModelContext) {
        let byRef = Dictionary(fresh.map { ($0.sourceRef ?? "", $0) },
                               uniquingKeysWith: { a, _ in a })
        guard !byRef.isEmpty else { return }
        let existing = (try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Linear" }))) ?? []
        var changed = false
        for thing in existing {
            guard let ref = thing.sourceRef, let now = byRef[ref],
                  now.mark != thing.mark else { continue }
            thing.mark = now.mark
            changed = true
        }
        if changed { context.saveHonestly() }
    }

    /// Raindrop — newest 30 bookmarks across all collections.
    private static func raindrop(_ token: String) async -> [Thing]? {
        guard let root = await IngestSupport.getJSON("https://api.raindrop.io/rest/v1/raindrops/0?perpage=30",
                                   auth: "Bearer \(token)") as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { return nil }
        return items.compactMap { item in
            guard let id = item["_id"], let link = item["link"] as? String else { return nil }
            let title = (item["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? link
            let thing = Thing(
                kind: .link,
                title: title,
                content: link,
                source: "Raindrop",
                capturedAt: IngestSupport.isoDate(item["created"]) ?? .now,
                sourceRef: "raindrop:\(id)"
            )
            // Raindrop's cover is the bookmark's og:image — the pin pattern.
            thing.previewImageURL = IngestSupport.imageURL(item["cover"] as? String)
            return thing
        }
    }
}
