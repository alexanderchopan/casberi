#if DEBUG
import Foundation

/// `-agentOpenProbe YES` — what the agent's room composed on this open (prd
/// §332), part by part.
///
/// It exists because **an empty board has six causes and only two are bugs**,
/// and all six render as the same fallback greeting:
///
///   1. nothing in the away window and nothing today — correct, and common;
///   2. no kept asks — correct, most people keep none;
///   3. kept asks whose deltas haven't been read yet this launch
///      (`refreshDigests` is foreground-gated, so a cold open beats it) —
///      correct, and self-healing on the next foreground;
///   4. no Apple Intelligence and no cross-source echo to stand in — correct;
///   5. a window that grouped into nothing because every term was stoplisted —
///      a BUG, and invisible from outside;
///   6. deltas present but every tile dropped by `face(for:)` — a BUG, and the
///      one most likely to follow a composer changing its `delta` wording.
///
/// So it prints the INPUTS beside the outputs: window size and kept count are
/// what separate "nothing to say" from "said nothing about something".
///
/// One NSLog per line — a joined multi-line message gets truncated by the log
/// reader mid-document (the `-todayProbe` lesson, paid for twice).
enum AgentOpenProbe {
    static func log(_ c: AgentOpen.Composition) {
        guard UserDefaults.standard.string(forKey: "agentOpenProbe")?.isEmpty == false else { return }
        NSLog("[Casberi] agentOpen| empty=%@ notice=%@ tiles=%d threads=%d fold=%@ quiet=%@",
              c.isEmpty ? "YES" : "NO",
              c.notice == nil ? "none" : (c.notice!.deterministic ? "deterministic" : "model"),
              c.tiles.count, c.threads.count,
              c.fold.map { "\($0.count)" } ?? "none",
              c.quiet == nil ? "none" : "yes")
        if let n = c.notice {
            NSLog("[Casberi] agentOpenNotice| evidence=%d claim=%@", n.evidence.count, n.claim)
            for e in n.evidence {
                NSLog("[Casberi] agentOpenEvidence| %@ · %@", e.source, e.title)
            }
        }
        // Tiles print their SOURCE strings beside the face so a wrong reduction
        // is separable from a wrong reading — the two look identical on screen.
        for t in c.tiles {
            NSLog("[Casberi] agentOpenTile| %@ · %@ / %@ changed=%@",
                  t.kind, t.headline, t.sub ?? "—", t.changed ? "YES" : "NO")
        }
        for th in c.threads {
            NSLog("[Casberi] agentOpenThread| %@ streak=%@ rows=%d loose=%@",
                  th.name, th.streak ?? "—", th.rows.count, th.loose ? "YES" : "NO")
            // The margin is the half no screenshot can check at a glance: a nil
            // margin and a wrong one both just look like a row.
            for r in th.rows {
                NSLog("[Casberi] agentOpenRow| %@ | margin=%@ signal=%@",
                      r.item.title, r.margin ?? "—", r.marginIsSignal ? "YES" : "NO")
            }
        }
        if let q = c.quiet { NSLog("[Casberi] agentOpenQuiet| %@", q) }
    }
}
#endif
