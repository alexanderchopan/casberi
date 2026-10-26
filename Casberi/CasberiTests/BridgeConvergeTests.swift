import Foundation
import Testing
@testable import Casberi

/// **A renamed app's records converge to ONE row under its current name**
/// (prd §1147): two "Frames Devnet" records drew as two rows in Settings ›
/// Apps after the seat became Hegotá Frames. That seat is deleted (prd
/// §1206), and Markets' deletion (prd §1529) emptied `Corpus.renamedSources`,
/// so the cases seed a rename of their own. Pure: `BridgeStore.converged`,
/// never a store, whose write would replace the simulator's saved records.
struct BridgeConvergeTests {

    private static func app(_ name: String, _ status: BridgeApp.Status = .connected) -> BridgeApp {
        BridgeApp(id: "x", name: name, status: status, statusLine: "", can: [])
    }

    private static func renamed(_ name: String) -> String { name == "Old" ? "New" : name }

    @Test func twinsUnderAnOldNameBecomeOneUnderTheNewName() throws {
        let out = try #require(BridgeStore.converged(
            [Self.app("Old"), Self.app("Old"), Self.app("GitHub")],
            current: Self.renamed))
        #expect(out.map(\.name) == ["New", "GitHub"])
    }

    @Test func aLiveTwinWinsOverAPausedOne() throws {
        let out = try #require(BridgeStore.converged(
            [Self.app("New", .paused), Self.app("Old")],
            current: Self.renamed))
        #expect(out.count == 1)
        #expect(out.first?.status == .connected)
    }

    @Test func nothingToDoIsNil() {
        #expect(BridgeStore.converged([Self.app("GitHub")], current: Corpus.canonicalSource)?.count == nil)
    }
}
