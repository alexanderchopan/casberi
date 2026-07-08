import Foundation
import SwiftData

/// The shared plumbing of every remote ingest (fetch → parse → dedupe →
/// things): the dedupe set, ISO 8601 dates with and without fractional
/// seconds, the one-line title clamp, and the JSON calls.
enum IngestSupport {

    /// Every sourceRef already in the corpus — the set incoming items
    /// dedupe against. Runs on the caller's context, like the fetches it
    /// replaced. A partial fetch: the predicate skips the many rows with no
    /// ref (notes, approvals), and propertiesToFetch faults in only the
    /// sourceRef column, so a refresh no longer hydrates the whole corpus.
    static func existingSourceRefs(_ context: ModelContext) -> Set<String> {
        var descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef != nil })
        descriptor.propertiesToFetch = [\.sourceRef]
        return Set(((try? context.fetch(descriptor)) ?? []).compactMap(\.sourceRef))
    }

    // MARK: - Dates

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Some APIs (Readwise, Bluesky) send fractional seconds.
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func isoDate(_ raw: Any?) -> Date? {
        guard let s = raw as? String else { return nil }
        return iso.date(from: s) ?? isoFractional.date(from: s)
    }

    // MARK: - Titles

    /// Thing titles are one line: newlines flatten and 80 chars is the cap.
    static func titleLine(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.count > 80 ? String(flat.prefix(80)) + "…" : flat
    }

    // MARK: - JSON over HTTP (200 with a JSON body, or nil)

    static func getJSON(_ url: String, auth: String? = nil,
                        headers: [String: String] = [:]) async -> Any? {
        guard let u = URL(string: url) else { return nil }
        return await getJSON(u, auth: auth, headers: headers)
    }

    static func getJSON(_ url: URL, auth: String? = nil,
                        headers: [String: String] = [:]) async -> Any? {
        var request = URLRequest(url: url)
        apply(auth: auth, headers: headers, to: &request)
        return await run(request)
    }

    static func postJSON(_ url: String, auth: String? = nil, body: [String: Any],
                         headers: [String: String] = [:]) async -> Any? {
        guard let u = URL(string: url),
              let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var request = URLRequest(url: u)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        apply(auth: auth, headers: headers, to: &request)
        return await run(request)
    }

    private static func apply(auth: String?, headers: [String: String],
                              to request: inout URLRequest) {
        if let auth { request.setValue(auth, forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
    }

    private static func run(_ request: URLRequest) async -> Any? {
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}
