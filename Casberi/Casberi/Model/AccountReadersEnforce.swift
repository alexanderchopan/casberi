import Foundation
import SwiftData

/// The half of `AccountReaders` that needs the app (prd §639): which readers
/// THIS device actually has, and the filter every model-bound corpus passes
/// through. Split from the Foundation-only file so the harness can compile
/// the storage and the caption without a store, a model or a Keychain.
extension AccountReaders {

    /// The readers the page draws, in the order it draws them: the on-device
    /// model when this device can run it, then every agent key that is
    /// actually stored, then a paired MCP client once the transport exists.
    /// **Only readers that EXIST.** A mark for a model this device cannot run
    /// is a toggle governing nothing — the §83 dead control — so the row on a
    /// phone with no keys and no Apple Intelligence is empty and the caption
    /// says the default.
    static func available() -> [Reader] {
        var out: [Reader] = []
        if OnDeviceModel.isAvailable {
            out.append(Reader(id: ID.device, name: String(localized: "On-device"), mark: nil))
        }
        for provider in AgentKey.configured {
            out.append(Reader(id: ID.agent(provider.rawValue), name: provider.agent,
                              mark: provider.agent))
        }
        if MCPPairing.transportReady {
            out.append(Reader(id: ID.mcp, name: String(localized: "Paired agents"), mark: "Cursor"))
        }
        return out
    }

    /// The reader id of the agent that answers a keyed ask right now.
    static var activeAgentID: String? {
        AgentKey.active.map { ID.agent($0.rawValue) }
    }

    /// What a reader may be handed. The ONE subtraction the answer path and
    /// the MCP door make before a thing reaches a model — a source shut out
    /// of this reader simply is not in the corpus it sees. Cheap when nothing
    /// is denied (one dictionary read, no filter pass), which is every
    /// install that never touched the row.
    static func readable(_ things: [Thing], by reader: String) -> [Thing] {
        let denied = deniedSources(for: reader)
        guard !denied.isEmpty else { return things }
        return things.filter { !denied.contains($0.source) }
    }
}
