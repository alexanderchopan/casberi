import Foundation
import Testing
@testable import Casberi

/// **Whose refusal a 401/403 is** (prd §1163).
///
/// `BridgeHealth` files a refusal under the seat `NetworkReach` names, and
/// every reader asks by the catalog name. A wrong answer renders as nothing at
/// all: a refused Stripe key reading "Reading", or a working X sign-in reading
/// "Needs reconnecting" because an avatar CDN said 403.
@Suite(.serialized)
struct BridgeHealthAttributionTests {

    private static let seats = ["Stripe", "Cloudflare", "Instagram", "TikTok", "X", "Snapchat"]

    private func clean() {
        (Self.seats + ["stripe", "instagram", "x"]).forEach(BridgeHealth.forget)
    }

    @Test func anIdSpelledBridgeIsFiledUnderItsCatalogName() {
        clean(); defer { clean() }
        BridgeHealth.record(host: "api.stripe.com", status: 401, named: nil)
        BridgeHealth.record(host: "api.cloudflare.com", status: 403, named: nil)
        #expect(BridgeHealth.needsReconnect("Stripe") != nil)
        #expect(BridgeHealth.needsReconnect("Cloudflare") != nil)
        #expect(BridgeHealth.needsReconnect("stripe") == nil)
    }

    @Test func aKeylessRiderIsNeverTheSeatsRefusal() {
        clean(); defer { clean() }
        BridgeHealth.record(host: "pbs.twimg.com", status: 403, named: nil)
        BridgeHealth.record(host: "www.instagram.com", status: 403, named: nil)
        BridgeHealth.record(host: "www.tiktok.com", status: 403, named: nil)
        for seat in ["X", "Instagram", "TikTok"] {
            #expect(BridgeHealth.needsReconnect(seat) == nil, "\(seat)")
        }
    }

    @Test func aLiveDoorsClaimSettlesASharedHost() {
        clean(); defer { clean() }
        BridgeHealth.record(host: "www.instagram.com", status: 401, named: "Instagram live")
        BridgeHealth.record(host: "www.tiktok.com", status: 401, named: "TikTok live")
        #expect(BridgeHealth.needsReconnect("Instagram") != nil)
        #expect(BridgeHealth.needsReconnect("TikTok") != nil)
    }

    @Test func aClaimTheRegistryDoesNotConfirmIsNotBelieved() {
        clean(); defer { clean() }
        // "Instagram live" does not list the avatar CDN, so the host's own
        // answer — a keyless rider — stands.
        BridgeHealth.record(host: "pbs.twimg.com", status: 403, named: "Instagram live")
        #expect(BridgeHealth.needsReconnect("Instagram") == nil)
        #expect(BridgeHealth.needsReconnect("X") == nil)
    }

    @Test func oldIdRecordsMoveAndTheNameWins() {
        clean(); defer { clean() }
        BridgeHealth.record(host: "api.stripe.com", status: 200, named: nil)
        BridgeHealth.rename("Stripe", to: "stripe")   // as a pre-§1163 build filed it
        BridgeHealth.adoptCatalogNames(["stripe": "Stripe"])
        #expect(BridgeHealth.record(for: "Stripe")?.lastOK != nil)
        #expect(BridgeHealth.record(for: "stripe") == nil)

        BridgeHealth.record(host: "api.stripe.com", status: 401, named: nil)
        BridgeHealth.record(host: "api.stripe.com", status: 200, named: nil)
        BridgeHealth.rename("Stripe", to: "stripe")
        BridgeHealth.record(host: "api.stripe.com", status: 401, named: nil)
        BridgeHealth.adoptCatalogNames(["stripe": "Stripe"])
        // The name's own record stood; the stray was dropped.
        #expect(BridgeHealth.needsReconnect("Stripe") != nil)
        #expect(BridgeHealth.record(for: "stripe") == nil)
    }
}
