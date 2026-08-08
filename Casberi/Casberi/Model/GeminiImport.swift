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
        /// Prompts already here that gained their full text and message count
        /// on this pass — see `ChatGPTImport.Summary.healed`. It matters more
        /// here than anywhere: a Gemini row's `content` is EMPTY, so before
        /// this a prompt over 200 characters existed in the corpus only as its
        /// own truncated first 200.
        var healed = 0
        /// Prompts the cap refused (§307/§309).
        var dropped = 0
        /// Prompts whose text hit `ChatTranscript.cap`.
        var clamped = 0
        var failed = false
    }

    /// The newest N prompts — `ChatGPTImport.conversationCap`'s number and its
    /// reasoning. The unit is smaller here (one row per PROMPT, not per
    /// conversation, since Google exports no thread structure), so this cap
    /// bites sooner than the other two; `dropped` is what says so.
    static let promptCap = 500

    /// Parses a `MyActivity.json` (Google Takeout, "My Activity" → Gemini
    /// Apps, JSON format) and lands each prompt as one chat thing.
    @MainActor
    static func run(data: Data, context: ModelContext) -> Summary {
        guard let root = try? JSONSerialization.jsonObject(with: data),
              let records = root as? [[String: Any]] else {
            return Summary(failed: true)
        }

        // A dictionary, not a ref set — a prompt already here is repaired
        // rather than skipped (2026-08-08).
        let existing = IngestSupport.thingsByRef(context, source: "Gemini")

        // Newest first, capped.
        let sorted = records.sorted {
            (stamp($0) ?? .distantPast) > (stamp($1) ?? .distantPast)
        }.prefix(promptCap)

        var summary = Summary()
        summary.dropped = max(0, records.count - promptCap)
        for record in sorted {
            let title = promptTitle(record)
            guard !title.isEmpty else { summary.skipped += 1; continue }

            let when = stamp(record)
            // Takeout records carry no id — timestamp + a stable hash of the
            // ask names one durably (String.hashValue is per-launch seeded,
            // so it can't). Hashed on the CLAMPED title, unchanged: the ref
            // has to keep naming the same row across builds, so it cannot be
            // moved onto the full text this pass started keeping.
            let ref = "gemini:\(when?.timeIntervalSince1970 ?? 0)-\(fnv1a(title))"

            let script = transcript(record)
            if script.clamped { summary.clamped += 1 }

            if let already = existing[ref] {
                // A held `Thing` — liveness before any stored read.
                guard already.isLive else { summary.skipped += 1; continue }
                if ChatImportLanding.apply(script, to: already) {
                    summary.healed += 1
                } else {
                    summary.skipped += 1
                }
                continue
            }

            let thing = Thing(
                kind: .chat,
                title: title,
                // Still empty, deliberately: the title IS the ask, so an
                // excerpt below it would be the same words twice. The ask's
                // full text — the part the title's 200-character clamp cuts —
                // lands on `enrichedText`, which nothing draws.
                content: "",
                source: "Gemini",
                capturedAt: when ?? .now,
                sourceRef: ref
            )
            context.insert(thing)
            ChatImportLanding.apply(script, to: thing)
            SpotlightIndex.index([thing])
            summary.imported += 1
        }
        if summary.imported > 0 || summary.healed > 0 { context.saveHonestly() }
        return summary
    }

    // MARK: - The prompt itself

    /// What was said, in order — which here is one turn, and that is not a
    /// gap in this parser.
    ///
    /// **Takeout's JSON carries the ask and nothing else.** A Gemini activity
    /// record is `title` ("Prompted …"), `titleUrl`, `time` and an app
    /// attribution; there is no field anywhere in it holding the model's
    /// answer (the HTML export renders one, the JSON does not), and Google
    /// exports no thread structure at all, so one record is one prompt and
    /// prompts that belonged to the same conversation arrive unlinked. So the
    /// transcript here is genuinely one line — a real, whole reading of what
    /// the export gives, not a placeholder for a half we failed to parse. What
    /// it adds over the title is the part the title's clamp cuts: a 900-word
    /// prompt was findable by its first 200 characters and is now findable by
    /// all of it.
    static func turns(_ record: [String: Any]) -> [(speaker: String, text: String)] {
        let ask = promptText(record)
        return ask.isEmpty ? [] : [(speaker: "You", text: ask)]
    }

    /// The prompt, whole and unclamped.
    static func transcript(_ record: [String: Any]) -> ChatTranscript {
        ChatTranscript.make(turns(record))
    }

    /// The ask — Takeout writes "Prompted <text>"; strip the verb, keep the
    /// ask. "Used Gemini…" app-open records carry no ask and skip; a title in
    /// another export language passes through whole rather than losing the
    /// chat.
    static func promptText(_ record: [String: Any]) -> String {
        guard var title = (record["title"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty
        else { return "" }
        if title.hasPrefix("Prompted ") {
            title = String(title.dropFirst("Prompted ".count))
        } else if title.hasPrefix("Used ") {
            return ""
        }
        return title
    }

    /// The ask as the ROW'S TITLE — the same reading, clamped for display.
    /// Unchanged in behaviour: the trim happens before the cut, exactly as it
    /// did when this function did both jobs, so no existing row's title or
    /// `sourceRef` moves.
    private static func promptTitle(_ record: [String: Any]) -> String {
        let ask = promptText(record)
        return ask.count > 200 ? String(ask.prefix(200)) + "…" : ask
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
