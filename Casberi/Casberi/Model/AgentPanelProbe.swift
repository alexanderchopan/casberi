#if DEBUG
import Foundation

/// `-agentOpenProbe YES` — what the agent's room composed on this open
/// (prd §334), part by part.
///
/// It exists because **an empty panel has six causes and only two are bugs**,
/// and all six render as the same fallback greeting:
///
///   1. no connected rooms with enough in them — correct, and the new-install
///      state;
///   2. rooms that are connected but whose hero is TEXT (Stripe, PostHog, the
///      approvals card) — correct by §334, and easy to mistake for a miss;
///   3. every room below its registry's own floor (a leaderboard needs ≥3
///      things in ≥2 groups, a topic map ≥6 things carrying terms) — correct;
///   4. no Apple Intelligence and no cross-source echo, so no lead — correct;
///   5. a room whose registry answered but whose figure came back EMPTY, so
///      `rank` dropped it — a BUG, and invisible from outside;
///   6. `roomFigure`'s chain drifting out of step with
///      `FeedScreen.shapedSections`, so a tile previews a different figure than
///      the room draws — a BUG, and the one that makes the panel actively
///      misleading rather than merely sparse.
///
/// So it prints the INPUTS beside the outputs: the source count and each
/// room's chosen figure are what separate "nothing to draw" from "drew
/// nothing about something".
///
/// One NSLog per line — a joined multi-line message gets truncated by the log
/// reader mid-document (the `-todayProbe` lesson, paid for twice).
enum AgentPanelProbe {
    static func log(_ c: AgentPanel.Composition) {
        guard UserDefaults.standard.string(forKey: "agentOpenProbe")?.isEmpty == false else { return }
        NSLog("[Casberi] agentPanel| empty=%@ cards=%d",
              c.isEmpty ? "YES" : "NO", c.cards.count)
        // The FIGURE KIND is the field that matters: a room drawing bars where
        // its own screen draws a treemap is the drift this probe exists for,
        // and both render as a perfectly good-looking tile.
        for card in c.cards {
            NSLog("[Casberi] agentPanelCard| %@ · %@ · %@ · affinity=%d",
                  card.source, kind(card.figure), card.title, card.affinity)
        }
    }

    private static func kind(_ figure: AgentPanel.Figure) -> String {
        switch figure {
        case .treemap(let c): return "treemap(\(c.count))"
        case .bars(let b):    return "bars(\(b.count))"
        case .rail(let s):    return "rail(\(s.count))"
        // Live days, not length: every registered grid is the same width, so
        // the raw count says nothing about whether the wall has anything in it.
        case .pulse(let p):   return "pulse(\(p.filter { $0 > 0 }.count) live of \(p.count))"
        case .curve(let v):   return "curve(\(v.count))"
        case .wall(let u):    return "wall(\(u.count))"
        case .flow(let i, let o): return "flow(\(i.count) in, \(o.count) out)"
        // Live HOURS and BANDS, not raw counts: a dial of 300 marks all at 9am
        // and one spread across the day look identical in a total.
        case .dial(let m):    return "dial(\(Set(m.map { Int($0.hour) }).count) hours of \(m.count))"
        case .river(let b):   return "river(\(b.count) bands x \(b.first?.weeks.count ?? 0)w)"
        case .scatter(let d, let c): return "scatter(\(d.count) dots, \(c.count) clusters)"
        }
    }
}
#endif
