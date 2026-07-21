import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Model-planned query routing (2026-07-15) — the on-device model reads an ask
/// and says whether it wants a LOOKUP (find/list specific things → a Widget of
/// real things) or a SYNTHESIS (reflect/summarize across things → streamed
/// prose). It replaces the hand-maintained cue lists in `answerMode`, which can
/// only ever match phrasings someone thought to enumerate ("what's my week",
/// "catch me up", …) and silently mis-route everything else.
///
/// It's an UPGRADE, never a requirement: the arithmetic asks (tags, counts,
/// watchlist, status) still claim their queries first — always-correct, no
/// model — and when the model is unavailable or declines, the caller falls back
/// to the keyword `answerMode` heuristic. So this only ever sharpens the
/// routing decision; it never gates an answer.
///
/// File-scope `@Generable` (nesting one breaks its generated keypaths —
/// CLAUDE.md), gated to iOS 26 where FoundationModels exists.
enum QueryPlan {

    /// The routing decision. `synthesis == false` means lookup.
    struct Plan {
        let synthesis: Bool
    }

    /// The model's read of the ask, or nil when the model is unavailable,
    /// declines, or errors — the caller then uses its keyword heuristic.
    static func make(_ query: String) async -> Plan? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await QueryPlanModel.make(query)
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
import FoundationModels

/// What the model returns for a routing decision — one word. File-scope so the
/// `@Generable` macro's generated schema/keypaths resolve cleanly.
@available(iOS 26.0, *)
@Generable
struct QueryRouteLayout {
    @Guide(description: "Exactly one of: lookup, synthesis. Use 'lookup' when the person wants to FIND or LIST specific saved things (find X, show my Y, which ones, what did I save about Z). Use 'synthesis' when they want you to REFLECT or SUMMARIZE across things (what's my week, catch me up, how was my month, the gist, what have I been up to).")
    var intent: String
}

@available(iOS 26.0, *)
enum QueryPlanModel {
    static func make(_ query: String) async -> QueryPlan.Plan? {
        guard OnDeviceModel.isAvailable else { return nil }
        let instructions = """
        You route a question about someone's saved things to one of two answer \
        shapes. Answer with only the routing word — never answer the question \
        itself. A LOOKUP finds or lists specific things. A SYNTHESIS reflects \
        or summarizes across many things. When unsure, choose lookup — a list \
        is the safer default.
        """
        do {
            let session = LanguageModelSession(instructions: instructions)
            let intent = try await session.respond(
                to: "Question: \"\(query)\"",
                generating: QueryRouteLayout.self
            ).content.intent.lowercased()
            // Only "synthesis" flips to prose; anything else (including a
            // hallucinated word) stays the safe lookup default.
            return QueryPlan.Plan(synthesis: intent.contains("synth"))
        } catch {
            return nil
        }
    }
}
#endif
