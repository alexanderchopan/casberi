import Foundation
import Testing
@testable import Casberi

/// **Every demo row leaves with the demo** (2026-10-15). Exit removes the
/// demo's rows by their `sourceRef` prefix (`DemoSeedAll.refPrefixes`), and a
/// row poured under a prefix missing from that list outlives Exit on a real
/// person's Feed. Found walking a first run: the Instagram, TikTok and Threads
/// demo notices ("tomas replied…") stood on the Feed of someone who had only
/// connected Bluesky.
struct DemoTeardownTests {

    @Test func everyDemoRowWearsAPrefixExitRemoves() {
        let stray = DemoSeedAll.rooms()
            .filter { thing in
                guard let ref = thing.sourceRef else { return true }
                return !DemoSeedAll.refPrefixes.contains { ref.hasPrefix($0) }
            }
            .map { "\($0.source): \($0.sourceRef ?? "no ref") — \($0.title)" }
        #expect(stray.isEmpty, "demo rows Exit would leave behind:\n\(stray.prefix(20).joined(separator: "\n"))")
    }
}
