import Foundation
import SwiftData

/// The Gemini bridge (2026-07-14) — a one-time import, the same grade as
/// ChatGPT and Claude: Google offers no live read of your Gemini history, so
/// the person's own Takeout export is the sanctioned way in. Takeout's
/// `MyActivity.json` is a flat array of activity records — one per PROMPT,
/// not per conversation (Google exports no thread structure) — so each
/// prompt lands as one chat thing, titled by what you asked, dated when you
/// asked it. Re-imports dedupe on the record's timestamp + a stable hash of
/// the prompt.
enum GeminiImport {

    struct Summary {
        var imported = 0
        var skipped = 0
        var failed = false
    }

    /// Parses a `MyActivity.json` (Google Takeout, "My Activity" → Gemini
    /// Apps, JSON format) and lands each prompt as one chat thing. Caps at
    /// the newest 500 — a years-deep export shouldn't flood the corpus in
    /// one tap.
    @MainActor
    static func run(data: Data, context: ModelContext) -> Summary {
        guard let root = try? JSONSerialization.jsonObject(with: data),
              let records = root as? [[String: Any]] else {
            return Summary(failed: true)
        }

        let existing = IngestSupport.existingSourceRefs(context, source: "Gemini")

        // Newest first, cap 500.
        let sorted = records.sorted {
            (stamp($0) ?? .distantPast) > (stamp($1) ?? .distantPast)
        }.prefix(500)

        var summary = Summary()
        for record in sorted {
            let title = promptTitle(record)
            guard !title.isEmpty else { summary.skipped += 1; continue }

            let when = stamp(record)
            // Takeout records carry no id — timestamp + a stable hash of the
            // ask names one durably (String.hashValue is per-launch seeded,
            // so it can't).
            let ref = "gemini:\(when?.timeIntervalSince1970 ?? 0)-\(fnv1a(title))"
            guard !existing.contains(ref) else { summary.skipped += 1; continue }

            let thing = Thing(
                kind: .chat,
                title: title,
                content: "",
                source: "Gemini",
                capturedAt: when ?? .now,
                sourceRef: ref
            )
            context.insert(thing)
            SpotlightIndex.index([thing])
            summary.imported += 1
        }
        if summary.imported > 0 { context.saveHonestly() }
        return summary
    }

    /// The ask as the title — Takeout writes "Prompted <text>"; strip the
    /// verb, keep the ask. "Used Gemini…" app-open records carry no ask and
    /// skip; a title in another export language passes through whole rather
    /// than losing the chat.
    private static func promptTitle(_ record: [String: Any]) -> String {
        guard var title = (record["title"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty
        else { return "" }
        if title.hasPrefix("Prompted ") {
            title = String(title.dropFirst("Prompted ".count))
        } else if title.hasPrefix("Used ") {
            return ""
        }
        return title.count > 200 ? String(title.prefix(200)) + "…" : title
    }

    /// Takeout's `time` is ISO-8601 with milliseconds — the same tolerant
    /// path Claude's export needed handles it.
    private static func stamp(_ record: [String: Any]) -> Date? {
        ClaudeImport.parseDate(record["time"] as? String)
    }

    /// FNV-1a over the prompt text — stable across launches, unlike
    /// `hashValue`.
    private static func fnv1a(_ s: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return String(hash, radix: 16)
    }
}
