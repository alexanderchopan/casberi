import Foundation
import SwiftData

/// The ChatGPT bridge (2026-07-07) — a one-time import, exactly as the offer
/// has always said: OpenAI offers no live read, so the person's own data
/// export is the sanctioned way in. The export's `conversations.json` parses
/// into chat things — one per conversation, titled as the person titled it,
/// dated when it last moved. Re-imports dedupe on the conversation id.
enum ChatGPTImport {

    struct Summary {
        var imported = 0
        var skipped = 0
        var failed = false
    }

    /// Parses a `conversations.json` (or a JSON export fragment) and lands
    /// each conversation as one chat thing. Caps at the newest 500 — a
    /// years-deep export shouldn't flood the corpus in one tap.
    @MainActor
    static func run(data: Data, context: ModelContext) -> Summary {
        guard let root = try? JSONSerialization.jsonObject(with: data),
              let conversations = root as? [[String: Any]] else {
            return Summary(failed: true)
        }

        let existing = IngestSupport.existingSourceRefs(context, source: "ChatGPT")

        // Newest first, cap 500.
        let sorted = conversations.sorted {
            (($0["update_time"] as? Double) ?? ($0["create_time"] as? Double) ?? 0)
            > (($1["update_time"] as? Double) ?? ($1["create_time"] as? Double) ?? 0)
        }.prefix(500)

        var summary = Summary()
        for convo in sorted {
            let title = (convo["title"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else { summary.skipped += 1; continue }

            let stamp = (convo["update_time"] as? Double)
                ?? (convo["create_time"] as? Double)
            let id = (convo["id"] as? String)
                ?? (convo["conversation_id"] as? String)
                ?? "\(title)-\(stamp ?? 0)"
            let ref = "chatgpt:\(id)"
            guard !existing.contains(ref) else { summary.skipped += 1; continue }

            let thing = Thing(
                kind: .chat,
                title: title,
                content: firstUserLine(convo),
                source: "ChatGPT",
                capturedAt: stamp.map { Date(timeIntervalSince1970: $0) } ?? .now,
                sourceRef: ref
            )
            context.insert(thing)
            SpotlightIndex.index([thing])
            summary.imported += 1
        }
        if summary.imported > 0 { context.saveHonestly() }
        return summary
    }

    /// The opening ask — the one line that reminds you what the chat was.
    private static func firstUserLine(_ convo: [String: Any]) -> String {
        guard let mapping = convo["mapping"] as? [String: [String: Any]] else { return "" }
        var earliest: (time: Double, text: String)?
        for node in mapping.values {
            guard let message = node["message"] as? [String: Any],
                  let author = message["author"] as? [String: Any],
                  author["role"] as? String == "user",
                  let content = message["content"] as? [String: Any],
                  let parts = content["parts"] as? [Any],
                  let text = parts.first as? String,
                  !text.isEmpty else { continue }
            let time = (message["create_time"] as? Double) ?? .greatestFiniteMagnitude
            if earliest == nil || time < earliest!.time {
                earliest = (time, text)
            }
        }
        guard var line = earliest?.text else { return "" }
        line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.count > 200 ? String(line.prefix(200)) + "…" : line
    }
}
