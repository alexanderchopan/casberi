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

    /// Whether Private Cloud Compute can answer on this device right now:
    /// iOS 27, an Apple Intelligence device with it on, and the managed
    /// entitlement on this build. Any one missing reads false — the seat is
    /// then hidden from the catalogue (`BridgeCatalog.offers`), because a
    /// seat that can never connect is a dead control (§83).
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
        // entitlement), so its page can be looked at. Every ask it routes
        // then fails in the cloud and answers on the phone — which is the
        // fallback path, exercised.
        if UserDefaults.standard.bool(forKey: "appleIntelligenceSeat") { return true }
        #endif
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
    static var usesCloud: Bool { enabled && cloudAvailable }

    /// What answered the LAST ask-path turn — set by the session's caller once
    /// it knows, read by the composer when the answer settles.
    @MainActor private(set) static var lastAnsweredInCloud = false

    @MainActor static func markAnswered(cloud: Bool) { lastAnsweredInCloud = cloud }

    #if DEBUG
    /// `-appleIntelligenceProbe` (RootShell): what this device says, and one
    /// call made straight to Private Cloud Compute. Lines, never a value from
    /// the corpus — the prompt is the probe's own unless one is passed.
    static func probe(prompt: String?) async -> [String] {
        var lines = ["availability = \(availabilityLine)",
                     "seat on = \(enabled)", "answers in cloud = \(usesCloud)"]
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
