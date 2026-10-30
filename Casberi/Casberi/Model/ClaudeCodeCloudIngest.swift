import Foundation
import SwiftData

/// Lands your Claude Code cloud sessions (`ClaudeCodeCloud`, prd §1625) with
/// the claude.ai sign-in Claude's seat already holds. The read runs INSIDE
/// claude.ai's own page (`ClaudeWeb`), so the cookies stay WebKit's and the
/// organization header is the page's own fetch; only the list comes back.
///
/// Read-only: nothing here starts, steers or archives a session.
enum ClaudeCodeCloudIngest {

    /// The page's read: the organization that can chat, then one page of
    /// sessions. Answers the body, or a small `{status}` saying why not.
    static let readJS = """
        const orgs = await fetch('/api/organizations', { credentials: 'include' })
          .then(r => r.status === 200 ? r.json() : null).catch(() => null);
        if (!Array.isArray(orgs)) return JSON.stringify({ casberi: 'signedOut' });
        const org = orgs.find(o => (o.capabilities || []).includes('chat'));
        if (!org) return JSON.stringify({ casberi: 'noOrganization' });
        const r = await fetch('/v1/code/sessions', { credentials: 'include',
          headers: { 'x-organization-uuid': org.uuid, 'anthropic-version': '2023-06-01' } });
        if (r.status !== 200) return JSON.stringify({ casberi: 'status' + r.status });
        return await r.text();
        """

    /// Why the last read landed nothing, for the account page; nil after a
    /// good read.
    @MainActor private(set) static var lastFailure: String?

    /// Lands new sessions and moves changed ones. nil = could not read;
    /// otherwise how many are new.
    @MainActor
    @discardableResult
    static func refresh(context: ModelContext) async -> Int? {
        guard WebSession.signedIn(.claude) else { lastFailure = "signedOut"; return nil }
        // The demo reaches nothing (§483).
        guard !DemoMode.isActive else { return nil }
        guard let text = await ClaudeWeb.shared.read(readJS) as? String,
              let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) else {
            lastFailure = "unreachable"
            return nil
        }
        if let why = (json as? [String: Any])?["casberi"] as? String {
            lastFailure = why
            return nil
        }
        guard let sessions = ClaudeCodeCloud.sessions(json) else {
            lastFailure = "drifted"
            return nil
        }
        lastFailure = nil
        return land(sessions, context: context)
    }

    @MainActor
    private static func land(_ sessions: [ClaudeCodeCloud.Session], context: ModelContext) -> Int {
        var existing = IngestSupport.thingsByRef(context, source: ClaudeCodeCloud.source)
        var added = 0
        var touched = false
        var indexed: [Thing] = []
        for session in sessions {
            let title = IngestSupport.titleLine(session.title)
            if let thing = existing[session.ref] {
                guard thing.isLive, thing.title != title || thing.content != session.line
                        || thing.tags != session.tags else { continue }
                thing.title = title
                thing.content = session.line
                thing.tags = session.tags
                thing.embedding = nil
                indexed.append(thing)
                touched = true
                continue
            }
            // Dated when the session started, as the folder import dates its
            // sessions: a session that moved does not jump the feed.
            let thing = Thing(kind: .chat,
                              title: title,
                              content: session.line,
                              source: ClaudeCodeCloud.source,
                              capturedAt: session.created ?? session.updated ?? .now,
                              tags: session.tags,
                              sourceRef: session.ref)
            thing.externalLink = session.link
            context.insert(thing)
            existing[session.ref] = thing
            indexed.append(thing)
            added += 1
        }
        SpotlightIndex.index(indexed.filter(\.isLive))
        if added > 0 || touched { context.saveHonestly() }
        return added
    }
}
