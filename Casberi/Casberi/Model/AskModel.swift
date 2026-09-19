import Foundation
import os
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Which Apple model answers the composer (prd §833): the one on this iPhone,
/// or the same family on Apple's Private Cloud Compute when the person turned
/// the Apple Intelligence seat on.
///
/// **ONE CHOICE, READ AT EVERY ASK-PATH SESSION.** The composer's answer is
/// several model calls — the grounded compose, the streamed synthesis, the
/// tool-calling agent — and each used to build `LanguageModelSession` itself.
/// A seat that switched only one of them would answer a question half on the
/// phone and half off it, and the badge could honestly name neither. So every
/// ask-path session comes from `session(tools:instructions:)`, and only those:
/// query expansion, the router, screenshot naming, cluster names, the day
/// read and Home's line are the
/// librarian's background work, not a conversation the person started, and
/// they stay on the phone whatever this says.
///
/// **A turn names what ANSWERED it, not what was asked for.** Private Cloud
/// Compute can refuse a call (no network, the quota, the service), and the
/// caller then answers on the phone — so `markAnswered(cloud:)` records the
/// model that actually produced the words, and the composer's badge reads it.
/// The failure this prevents is the one §67 names for keys: a fallback
/// wearing the badge of the thing that failed.
///
/// **Off unless chosen.** Private Cloud Compute is a network call, which the
/// on-device answer never was; it happens only after the person turned the
/// seat on, and the seat says so before they do.
enum AskModel {

    /// The seat's switch. Written by `AppleIntelligenceScreen` only.
    static let enabledKey = "appleIntelligence.enabled"

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// **The managed entitlement, and why this build knows it only as a
    /// constant (prd §838).** Apple's `availability` answers about the DEVICE
    /// and the SYSTEM — its cases are `.available`, `.deviceNotEligible`,
    /// `.systemNotReady` — and says NOTHING about whether this build may call
    /// Private Cloud Compute. So an unentitled build on an Apple Intelligence
    /// phone reads `.available`, the seat draws, the person turns it on, and
    /// the first question KILLS THE APP. §833 recorded the opposite ("shipped
    /// dark, not dead") on the strength of the doc comment below, which
    /// described an entitlement check that was never written: `cloudAvailable`
    /// asked `isAvailable` and nothing else, so nothing was ever dark.
    ///
    /// Measured in production on 2026-09-19 (build 633, the user's own phone):
    /// the seat was in the catalogue, turned on, and the crash landed AFTER
    /// the question was sent, never on the tap — i.e. at the point the ask
    /// path first uses the cloud session, not where it builds one. The ask
    /// path's cloud fallback is a `catch` (`OnDeviceModel.compose`), which
    /// answers a THROWN refusal on the phone; it cannot answer the process
    /// going away, so the fallback §833 describes has never once run.
    ///
    /// There is no key to read. The entitlement is MANAGED — granted per
    /// account at developer.apple.com/contact/request/private-cloud-compute —
    /// and its key is not in the SDK, so nothing can be guessed into the
    /// entitlements file and nothing at runtime can ask whether it is held.
    /// What this build knows about itself is exactly this constant. Flip it in
    /// the SAME commit that adds the granted entitlement to the app's
    /// `.entitlements`, and never before.
    static let entitled = false

    /// Whether Private Cloud Compute can answer on this device right now:
    /// iOS 27, an Apple Intelligence device with it on, and `entitled`. Any
    /// one missing reads false.
    ///
    /// Read by `BridgeCatalog.offers`, which runs in bodies, so the answer is
    /// held for `ttl` rather than asked of the framework on every pass —
    /// availability moves (a model still getting ready), but not per frame.
    static var cloudAvailable: Bool {
        let now = Date()
        return cache.withLock { held in
            if let held = held, now.timeIntervalSince(held.at) < ttl { return held.value }
            let value = readCloudAvailable()
            held = (value, now)
            return value
        }
    }

    private static let ttl: TimeInterval = 30
    private static let cache = OSAllocatedUnfairLock<(value: Bool, at: Date)?>(initialState: nil)

    private static func readCloudAvailable() -> Bool {
        #if DEBUG
        // `-appleIntelligenceSeat YES` shows the seat where Private Cloud
        // Compute cannot answer (the simulator, a build without the
        // entitlement), so its page can be looked at. It moves the CATALOGUE
        // only: `usesCloud` reads `entitled` separately, so a flagged build
        // still answers on the phone. It used to claim it exercised the cloud
        // fallback, which was never true — an unentitled cloud call does not
        // fail, it takes the process with it (`entitled`).
        if UserDefaults.standard.bool(forKey: "appleIntelligenceSeat") { return true }
        #endif
        guard entitled else { return false }
        #if canImport(FoundationModels)
        if #available(iOS 27.0, *) {
            return PrivateCloudComputeLanguageModel().isAvailable
        }
        #endif
        return false
    }

    /// One line for the seat page and `-appleIntelligenceProbe`.
    static var availabilityLine: String {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, *) {
            switch PrivateCloudComputeLanguageModel().availability {
            case .available:
                return String(localized: "Available")
            case .unavailable(.deviceNotEligible):
                return String(localized: "This device can't use it")
            case .unavailable(.systemNotReady):
                return String(localized: "Not ready — check Apple Intelligence in Settings")
            case .unavailable:
                return String(localized: "Unavailable")
            }
        }
        #endif
        return String(localized: "Needs iOS 27")
    }

    /// True when the next ask should go to Private Cloud Compute.
    ///
    /// `entitled` is read HERE as well as inside `cloudAvailable`, and the
    /// repetition is the point: `cloudAvailable` is what the catalogue asks
    /// and a DEBUG flag can move it, while this is what builds a session. The
    /// two questions have different answers on a flagged build, and the one
    /// that crashes the app must never be the one a launch argument can turn
    /// on (prd §838).
    static var usesCloud: Bool { enabled && entitled && cloudAvailable }

    /// What answered the LAST ask-path turn — set by the session's caller once
    /// it knows, read by the composer when the answer settles.
    @MainActor private(set) static var lastAnsweredInCloud = false

    @MainActor static func markAnswered(cloud: Bool) { lastAnsweredInCloud = cloud }

    #if DEBUG
    /// `-appleIntelligenceProbe` (RootShell): what this device says, and one
    /// call made straight to Private Cloud Compute. Lines, never a value from
    /// the corpus — the prompt is the probe's own unless one is passed.
    ///
    /// **The call is made only when `entitled`.** A probe that ends the
    /// process is not a reading — the `catch` below can report a refusal and
    /// cannot report a kill (prd §838) — so an unentitled build prints what it
    /// knows and stops. It does not read `usesCloud`: the seat being off is no
    /// reason to refuse a measurement, and the entitlement is.
    static func probe(prompt: String?) async -> [String] {
        var lines = ["availability = \(availabilityLine)",
                     "seat on = \(enabled)", "entitled = \(entitled)",
                     "answers in cloud = \(usesCloud)"]
        guard entitled else {
            lines.append("no call made — this build holds no Private Cloud Compute entitlement")
            return lines
        }
        #if canImport(FoundationModels)
        if #available(iOS 27.0, *) {
            let model = PrivateCloudComputeLanguageModel()
            lines.append("quota = \(String(describing: model.quotaUsage.status))")
            if let size = try? await model.contextSize { lines.append("context = \(size) tokens") }
            do {
                let session = LanguageModelSession(model: model)
                let reply = try await session.respond(to: prompt ?? "Reply with the single word: ready")
                lines.append("reply = \(reply.content.prefix(200))")
            } catch {
                lines.append("refused = \(String(describing: error))")
            }
        }
        #endif
        return lines
    }
    #endif

    #if canImport(FoundationModels)
    /// A session for the composer's answer, and whether it runs in the cloud.
    /// `forceDevice` is the fallback: after a cloud call failed, the caller
    /// asks again for the phone's own model.
    @available(iOS 26.0, *)
    static func session(tools: [any Tool] = [], instructions: String,
                        forceDevice: Bool = false) -> (session: LanguageModelSession, cloud: Bool) {
        if !forceDevice, usesCloud, #available(iOS 27.0, *) {
            return (LanguageModelSession(model: PrivateCloudComputeLanguageModel(),
                                         tools: tools, instructions: instructions), true)
        }
        return (LanguageModelSession(tools: tools, instructions: instructions), false)
    }
    #endif
}
