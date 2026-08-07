import SwiftUI

/// The agent's room on a plain open (prd §334, layout B) — the panel, whole.
///
/// One intro sentence and then only figures, by the user's ruling. The intro
/// sentence is the greeting the composer already draws ("Thursday morning."),
/// so this view adds NO text of its own: §334's first cut led with a claim
/// card and evidence chips, and it lasted a day — a model-written sentence in
/// the hero slot is text synthesis wearing a chart's clothes. The composed
/// line keeps its other homes (the Noticed chip, the brief); this surface
/// stopped being one of them.
///
/// Reads only value types (`AgentPanel.*`), never a `Thing`, so the whole
/// liveness-corollary family is structurally unreachable here.
struct AgentOpenBoard: View {
    let composition: AgentPanel.Composition
    /// Open a room — the composer switches the feed and lowers the agent.
    let onOpenRoom: (String) -> Void

    var body: some View {
        if !composition.cards.isEmpty {
            AgentPanelGrid(cards: composition.cards, onOpen: onOpenRoom)
        }
    }
}
