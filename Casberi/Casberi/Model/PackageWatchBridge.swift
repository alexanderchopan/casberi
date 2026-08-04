import Foundation
import Observation
import SwiftData

/// The package-registry bridges (2026-08-04) — npm and PyPI, one file, two
/// seats. Name the packages you depend on and their releases land in your feed.
///
/// Keyless, accountless, nothing to mint: every endpoint below answers
/// anonymously. That puts these in the Hugging Face / GeckoTerminal tier, and
/// they are the cheapest bridges in the catalog to run — there is no token, so
/// there is nothing a leak could spend.
///
/// ## What lands, and the count that doesn't
///
/// A registry is a counter dressed as a database: downloads per day, per week,
/// dependents, stars. **None of it lands.** "requests was downloaded 4.1
/// million times this week" is the purest tally there is (the PostHog ruling),
/// and npm even serves it from a different host, which this file never touches.
///
/// Two shapes are events:
///
///   • **A new version.** The package you depend on published something. This
///     is the whole feature.
///   • **A deprecation** (npm) — the maintainer marked the package dead, with
///     a message saying what to use instead. Rare, permanent, and exactly the
///     kind of thing you find out about six months late.
///
/// **PyPI gets no deprecation row, and the copy must not imply parity.** PyPI's
/// equivalent is a per-release "yank", which is not in the release feed this
/// bridge reads and would cost a 190KB fetch per package per pass to see (see
/// the measurements below). npm's deprecation flag rides a response we already
/// need.
///
/// ## The measurements are the whole design here — do not "simplify" the
/// ## endpoints without re-running them
///
/// Measured 2026-08-04, by hand, against the live registries:
///
///   • `registry.npmjs.org/<pkg>` — the obvious endpoint — is **6.8 MB** for
///     `react`. It carries every version's full manifest and the readme. It is
///     completely disqualified for a per-foreground mobile read, and it is the
///     first thing anyone will reach for.
///   • The abbreviated form (`Accept: application/vnd.npm.install-v1+json`) is
///     **2.8 MB** and drops the `time` map, so it costs a fortune AND loses the
///     dates. Also disqualified.
///   • `registry.npmjs.org/<pkg>/latest` is **2 KB** and carries `version`,
///     `description`, `homepage` and `deprecated` — but **no date at all**.
///   • `registry.npmjs.org/-/v1/search?text=<pkg>` is **1 KB** and DOES carry
///     the publish `date`. It is a SEARCH, not a lookup: `name:` qualifiers
///     return zero results (measured), and `text=react` ranks `react-is`,
///     `react-smooth` and `react-router` right behind the exact match. So the
///     result must be matched on the name the ANSWER carries, never the one
///     asked for — the Jupiter lesson, in a second registry.
///   • `pypi.org/pypi/<pkg>/json` is **190 KB**. `pypi.org/rss/project/<pkg>/
///     releases.xml` is **10 KB**, holds 40 releases newest-first, and carries
///     the version as `<title>` and the real publish time as `<pubDate>`. The
///     RSS feed is strictly better for this purpose and is the whole PyPI read.
///   • Both registries 404 cleanly for a package that doesn't exist, so a typo
///     is distinguishable from an outage.
///
/// Which gives the cost shape this bridge is built around: **steady state is
/// one small request per watched package.** npm's date lookup fires only when
/// there is actually something to land, so the expensive half is proportional
/// to news rather than to time.
///
/// ## First sight
///
/// The Hugging Face split, for its reason: the person just typed a package
/// name and is owed proof the watch works, so the CURRENT version lands
/// immediately — stamped with its real publish date, so a package last released
/// in 2019 sorts back to 2019 and cannot fake today's urgency.
///
/// The one case that seeds SILENTLY is npm when the date lookup failed to find
/// an exact-name match. A row with no date would have to be stamped `.now`,
/// which would claim a release happened today when we have no idea when it
/// happened — so nothing lands, the version is recorded, and the next real
/// release lands normally. Being silent is recoverable; being wrong isn't.
enum PackageRegistry: String, CaseIterable, Identifiable, Codable {
    case npm
    case pypi

    var id: String { rawValue }

    /// The catalog seat name, and the `Thing.source` every row wears.
    var displayName: String {
        switch self {
        case .npm:  "npm"
        case .pypi: "PyPI"
        }
    }

    var bridgeID: String { rawValue }

    /// What a row's trailing clause calls the thing that shipped.
    var releaseNoun: String {
        switch self {
        case .npm:  String(localized: "npm")
        case .pypi: String(localized: "PyPI")
        }
    }

    /// The package's own page, for the row's permalink.
    func pageURL(_ name: String) -> String {
        switch self {
        case .npm:  "https://www.npmjs.com/package/\(name)"
        case .pypi: "https://pypi.org/project/\(name)/"
        }
    }

    /// What a person types. npm names are lowercase by rule and may carry a
    /// scope (`@vercel/og`); PyPI names normalise per PEP 503 (case-insensitive,
    /// with `-`, `_` and `.` all equivalent) but the site accepts any spelling,
    /// so this only lowercases and trims rather than rewriting separators —
    /// rewriting them would make the row's title disagree with what the person
    /// typed for no gain.
    func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://"] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
        }
        // Accept a pasted package page, which is how a lot of people will
        // arrive. npm's path is `/package/<name>`, PyPI's is `/project/<name>`.
        for host in ["www.npmjs.com/package/", "npmjs.com/package/",
                     "pypi.org/project/", "www.pypi.org/project/"]
        where s.lowercased().hasPrefix(host) {
            s = String(s.dropFirst(host.count))
        }
        s = s.split(separator: "?").first.map(String.init) ?? s
        // A scoped npm name is `@scope/name` — two components, both kept. Any
        // other trailing path component (a version, `/releases`) is dropped.
        if s.hasPrefix("@") {
            let parts = s.split(separator: "/").prefix(2)
            s = parts.joined(separator: "/")
        } else {
            s = s.split(separator: "/").first.map(String.init) ?? s
        }
        return self == .npm ? s.lowercased() : s
    }
}

// MARK: - Store

@Observable
final class PackageStore {
    static let shared = PackageStore()

    private static func watchKey(_ r: PackageRegistry) -> String { "pkg.\(r.rawValue).watch.v1" }
    private static let versionsKey = "pkg.versions.v1"
    private static let deprecatedKey = "pkg.deprecated.v1"

    private(set) var watched: [PackageRegistry: [String]] = [:]

    private init() {
        for registry in PackageRegistry.allCases {
            watched[registry] = Self.load(Self.watchKey(registry))
        }
    }

    func list(_ registry: PackageRegistry) -> [String] { watched[registry] ?? [] }

    func connected(_ registry: PackageRegistry) -> Bool { !list(registry).isEmpty }

    func isWatching(_ registry: PackageRegistry, _ name: String) -> Bool {
        list(registry).contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    @discardableResult
    func add(_ registry: PackageRegistry, _ raw: String) -> Bool {
        let name = registry.normalize(raw)
        guard !name.isEmpty, !isWatching(registry, name) else { return false }
        var list = self.list(registry)
        list.append(name)
        watched[registry] = list
        persist(list, Self.watchKey(registry))
        return true
    }

    func remove(_ registry: PackageRegistry, _ name: String) {
        var list = self.list(registry)
        list.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
        watched[registry] = list
        persist(list, Self.watchKey(registry))
        setVersion(registry, name, nil)
    }

    func disconnect(_ registry: PackageRegistry) {
        for name in list(registry) { setVersion(registry, name, nil) }
        watched[registry] = []
        persist([], Self.watchKey(registry))
    }

    // MARK: The version ledger

    /// The last version this bridge saw for a package.
    ///
    /// nil means "never looked", which is what makes first sight distinguishable
    /// from "the package has no releases". Keyed `registry:name` so the two
    /// registries can hold a package of the same name without colliding — which
    /// they routinely do (`requests`, `click`, `attrs` all exist on both).
    func version(_ registry: PackageRegistry, _ name: String) -> String? {
        map(Self.versionsKey)[key(registry, name)]
    }

    func setVersion(_ registry: PackageRegistry, _ name: String, _ version: String?) {
        var m = map(Self.versionsKey)
        m[key(registry, name)] = version
        write(m, Self.versionsKey)
    }

    /// Whether a deprecation has already been announced for this package, so
    /// it lands once rather than every pass forever. A deprecation is
    /// permanent, so this never needs clearing except on unwatch.
    func announcedDeprecation(_ registry: PackageRegistry, _ name: String) -> Bool {
        map(Self.deprecatedKey)[key(registry, name)] != nil
    }

    func markDeprecated(_ registry: PackageRegistry, _ name: String) {
        var m = map(Self.deprecatedKey)
        m[key(registry, name)] = "1"
        write(m, Self.deprecatedKey)
    }

    // MARK: Storage

    private func key(_ r: PackageRegistry, _ name: String) -> String {
        "\(r.rawValue):\(name.lowercased())"
    }

    private func map(_ key: String) -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let m = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return m
    }

    private func write(_ m: [String: String], _ key: String) {
        if let data = try? JSONEncoder().encode(m) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func load(_ key: String) -> [String] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return saved
    }

    private func persist(_ list: [String], _ key: String) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Pure shaping (harness-tested — see scripts/packages-selftest.sh)

enum PackageShape {

    /// `"react 19.2.8"`, or `"Deprecated · request"`.
    ///
    /// The version TRAILS here, unlike every outcome clause elsewhere in this
    /// app, and that is deliberate rather than an oversight: a package name and
    /// a semver are both short, so `titleLine`'s 80-character clamp is not in
    /// play, and "react 19.2.8" is how a person says it. A deprecation DOES
    /// lead, because that one is an outcome and it is the word that must
    /// survive if anything is cut.
    static func releaseTitle(name: String, version: String) -> String {
        "\(name) \(version)"
    }

    static func deprecationTitle(name: String) -> String {
        String(localized: "Deprecated · \(name)")
    }

    static func releaseRef(_ registry: PackageRegistry, name: String, version: String) -> String {
        "\(registry.rawValue):release:\(name.lowercased()):\(version)"
    }

    static func deprecationRef(_ registry: PackageRegistry, name: String) -> String {
        "\(registry.rawValue):deprecated:\(name.lowercased())"
    }

    /// Whether a search result really IS the package that was asked for.
    ///
    /// The one guard that makes npm's date lookup safe. `text=react` ranks
    /// `react-is` and `react-router` immediately behind the exact match
    /// (measured), and npm supports no exact-name qualifier at all — so
    /// trusting position would date `react`'s release from `react-is`'s, which
    /// is a wrong number that renders perfectly. Compared case-insensitively
    /// because npm lowercases names but old scoped names can carry mixed case.
    static func matches(asked: String, answered: String?) -> Bool {
        guard let answered else { return false }
        return asked.caseInsensitiveCompare(answered) == .orderedSame
    }
}

// MARK: - Reads

enum PackageFetch {

    struct Release {
        let version: String
        /// nil when the registry didn't tell us. npm's cheap endpoint carries
        /// no date, so this is genuinely unknown rather than defaulted — see
        /// the file note on why a defaulted date would be worse than none.
        let published: Date?
        /// npm's deprecation message. Non-nil means the maintainer marked this
        /// version dead and said what to do instead.
        let deprecated: String?
    }

    // MARK: npm

    /// The current version of an npm package, plus whether it's deprecated.
    /// **2 KB** — see the file note. Nil on any failure (404 for a typo'd name,
    /// which is why the setup screen can say "we couldn't find that package").
    static func npmLatest(_ name: String) async -> Release? {
        guard let escaped = escapePackage(name) else { return nil }
        guard let root = await IngestSupport.getJSON(
            "https://registry.npmjs.org/\(escaped)/latest") as? [String: Any],
              let version = nonEmpty(root["version"]) else { return nil }
        return Release(version: version, published: nil,
                       deprecated: nonEmpty(root["deprecated"]))
    }

    /// When a specific npm package was published, via the search index.
    ///
    /// Fired only when something is about to land — see the file note on cost
    /// shape. Returns nil rather than a guess when no result carries the exact
    /// name, and the caller treats that as "seed silently".
    static func npmPublishDate(_ name: String) async -> Date? {
        guard let query = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        guard let root = await IngestSupport.getJSON(
            "https://registry.npmjs.org/-/v1/search?text=\(query)&size=5") as? [String: Any],
              let objects = root["objects"] as? [[String: Any]] else { return nil }
        for object in objects {
            let pkg = object["package"] as? [String: Any] ?? [:]
            // Matched on the name the ANSWER carries — never position, never
            // the name asked for. See `PackageShape.matches`.
            guard PackageShape.matches(asked: name, answered: pkg["name"] as? String)
            else { continue }
            return IngestSupport.isoDate(pkg["date"])
        }
        return nil
    }

    // MARK: PyPI

    /// The newest PyPI release, from the project's own RSS feed. **10 KB**,
    /// 40 items, newest first, each carrying the version and its real publish
    /// time — the whole PyPI read in one request.
    static func pypiLatest(_ name: String) async -> Release? {
        guard let escaped = escapePackage(name),
              let url = URL(string: "https://pypi.org/rss/project/\(escaped)/releases.xml")
        else { return nil }
        NetworkLedger.shared.record(url, as: "PyPI")
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let parsed = FeedParser.parse(data)
        // The feed is newest-first (measured), and the item title IS the bare
        // version string — PyPI writes no prose there.
        guard let newest = parsed.items.first,
              case let version = newest.title.trimmingCharacters(in: .whitespacesAndNewlines),
              !version.isEmpty else { return nil }
        // PyPI has no deprecation concept in this feed — see the file note.
        return Release(version: version, published: newest.date, deprecated: nil)
    }

    // MARK: Shared

    /// A scoped npm name (`@vercel/og`) carries a slash that must survive into
    /// the path, so this escapes the components and rejoins rather than
    /// percent-encoding the separator into `%2F` — which npm's registry serves
    /// a 404 for.
    static func escapePackage(_ name: String) -> String? {
        let allowed = CharacterSet.urlPathAllowed
        let parts = name.split(separator: "/").map(String.init)
        let escaped = parts.compactMap { $0.addingPercentEncoding(withAllowedCharacters: allowed) }
        guard escaped.count == parts.count, !escaped.isEmpty else { return nil }
        return escaped.joined(separator: "/")
    }

    static func nonEmpty(_ raw: Any?) -> String? {
        guard let s = (raw as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    static func latest(_ registry: PackageRegistry, _ name: String) async -> Release? {
        switch registry {
        case .npm:  await npmLatest(name)
        case .pypi: await pypiLatest(name)
        }
    }
}

// MARK: - Ingest

enum PackageIngest {

    @MainActor private static var running: Set<PackageRegistry> = []

    /// Reads every watched package in one registry and lands what's new.
    /// Returns the number of new things, 0 when up to date, nil when nothing
    /// was reachable.
    @MainActor
    static func refresh(_ registry: PackageRegistry, context: ModelContext) async -> Int? {
        let store = PackageStore.shared
        let names = store.list(registry)
        guard !names.isEmpty, !running.contains(registry) else {
            return running.contains(registry) ? 0 : nil
        }
        running.insert(registry)
        defer { running.remove(registry) }

        // Modestly bounded. Neither registry publishes an anonymous rate limit
        // and both are CDN-fronted, but firing a whole watch list at once is
        // the shape that got Farcaster's graph walk truncated (§87).
        let results = await IngestSupport.boundedGather(names, maxConcurrent: 4) { name in
            (name, await PackageFetch.latest(registry, name))
        }

        var existing = IngestSupport.existingSourceRefs(context, source: registry.displayName)
        var added = 0
        var reachedAny = false

        for (name, release) in results {
            guard let release else { continue }
            reachedAny = true
            let known = store.version(registry, name)
            let firstSight = known == nil

            // A deprecation is announced once, ever, and independently of
            // whether the version moved — a package is usually deprecated
            // without a new release.
            if let message = release.deprecated, !store.announcedDeprecation(registry, name) {
                let ref = PackageShape.deprecationRef(registry, name: name)
                if !existing.contains(ref) {
                    let thing = Thing(
                        kind: .link,
                        title: IngestSupport.titleLine(PackageShape.deprecationTitle(name: name)),
                        content: registry.pageURL(name),
                        source: registry.displayName,
                        // Stamped now: the registry doesn't say when it was
                        // deprecated, and this is the moment we learned. Unlike
                        // a release date, there is no truer number available.
                        capturedAt: .now,
                        tags: ["Deprecated"],
                        sourceRef: ref
                    )
                    // The maintainer's own message — what to use instead. This
                    // is the entire value of the row, so it is display copy
                    // (the Trello card-back rule), never `enrichedText`.
                    thing.summary = message
                    context.insert(thing)
                    existing.insert(ref)
                    SpotlightIndex.index([thing])
                    added += 1
                }
                store.markDeprecated(registry, name)
            }

            guard known != release.version else { continue }

            // The date. On npm this is the second request, and it fires only
            // here — when something is actually about to land.
            var published = release.published
            if published == nil, registry == .npm {
                published = await PackageFetch.npmPublishDate(name)
            }

            // First sight with no knowable date seeds SILENTLY rather than
            // landing a row stamped `.now`, which would claim a release
            // happened today when we have no idea when it happened. See the
            // file note.
            if firstSight, published == nil {
                store.setVersion(registry, name, release.version)
                continue
            }

            let ref = PackageShape.releaseRef(registry, name: name, version: release.version)
            if !existing.contains(ref) {
                let thing = Thing(
                    kind: .link,
                    title: IngestSupport.titleLine(
                        PackageShape.releaseTitle(name: name, version: release.version)),
                    content: registry.pageURL(name),
                    source: registry.displayName,
                    // The REAL publish time when we know it. A version change
                    // detected on a pass with no date is one we watched happen,
                    // so `.now` is honest there — that case only arises after
                    // first sight, where the version was already recorded.
                    capturedAt: published ?? .now,
                    tags: ["Release"],
                    sourceRef: ref
                )
                context.insert(thing)
                existing.insert(ref)
                SpotlightIndex.index([thing])
                added += 1
            }
            store.setVersion(registry, name, release.version)
        }

        if added > 0 { context.saveHonestly() }
        return reachedAny ? added : nil
    }

    // MARK: - Probe

    /// `-packageProbe <npm|pypi>` — one line per watched package.
    ///
    /// An empty package room has FIVE causes rendering as one silence: nothing
    /// watched, a typo'd name (a clean 404 at both registries), a package that
    /// simply hasn't released since you added it — the healthy and by far most
    /// common case — an npm date lookup that matched nothing so first sight
    /// seeded silently by design, and shape drift. Only the last is a bug, and
    /// the `date=` field is what separates it from the fourth.
    @MainActor
    static func diagnose(_ registry: PackageRegistry, context: ModelContext) async {
        let store = PackageStore.shared
        let names = store.list(registry)
        NSLog("[Casberi] package| registry=%@ watching=%d: %@", registry.displayName,
              names.count, names.joined(separator: ","))
        guard !names.isEmpty else {
            NSLog("[Casberi] package| nothing watched — add one with -packageWatch \"%@:<name>\"",
                  registry.rawValue)
            return
        }
        for name in names {
            guard let release = await PackageFetch.latest(registry, name) else {
                NSLog("[Casberi] packageRow| %@ UNREADABLE — a 404 means the name is wrong, anything else means unreachable",
                      name)
                continue
            }
            var date = release.published
            if date == nil, registry == .npm { date = await PackageFetch.npmPublishDate(name) }
            NSLog("[Casberi] packageRow| %@ latest=%@ known=%@ date=%@ deprecated=%@",
                  name, release.version, store.version(registry, name) ?? "(never looked)",
                  date.map { ISO8601DateFormatter().string(from: $0) } ?? "UNKNOWN",
                  release.deprecated != nil ? "YES" : "no")
        }
        let added = await refresh(registry, context: context)
        NSLog("[Casberi] package| refresh landed %@",
              added.map(String.init) ?? "nil (unreachable)")
    }
}
