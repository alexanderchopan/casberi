import Foundation

/// What the Data tray says about iCloud sync — the DECISION, apart from the
/// CoreData observation that feeds it (prd §607).
///
/// Foundation-only by design, so `scripts/cloud-sync-selftest.sh` compiles it
/// WHOLE and unmodified. That harness is the only proof these sentences are
/// right: **every failure here renders as a perfectly ordinary settings row**
/// — a tray that says "Synced just now" over a mirror that has never carried a
/// row, one that says "Stays on this Mac" about a choice the person did not
/// make, or one that tells a Mac user to do something they believe they have
/// already done. None of that is visible to a build, to a screenshot, or to
/// `verify-mac.sh`, which launches every run with `-storeScratch YES` and so
/// has never opened the mirror at all.
enum CloudSyncReading {

    /// Everything the sentence is decided from. A value type rather than four
    /// arguments so the harness can state a case in one line and so a new
    /// input cannot be added at one call site and forgotten at the other.
    struct State {
        /// The toggle's own position — what the person asked for.
        var wantsSync: Bool
        /// Whether THIS process is actually mirroring. The container binds
        /// once at launch, so this and `wantsSync` legitimately disagree for
        /// the rest of a session after a flip, and that disagreement is the
        /// single most important thing this file exists to say out loud.
        var engaged: Bool
        var hasLiveError: Bool
        /// A row arrived FROM iCloud.
        var lastImport: Date?
        /// A row was SENT to iCloud.
        var lastExport: Date?
        /// The mirror connected. Proves the account and container are
        /// reachable and NOTHING about whether a row ever moved.
        var lastSetup: Date?
    }

    /// Ordered by what the reader is asking, trouble first.
    ///
    /// **The rule that shapes all of it: never report a direction that has not
    /// happened.** `.setup`, `.import` and `.export` are all "succeeded"
    /// events, so the shipped line — which read any success — said "Synced" the
    /// moment CloudKit connected, over a mirror that had exchanged nothing.
    /// The question somebody opens this tray to ask is "is the thing I saved
    /// on my phone here", and only an `.import` answers it.
    static func line(state: State, deviceName: String, macIdiom: Bool) -> String {
        guard state.wantsSync else {
            // Turning it OFF is also a next-launch change: this process keeps
            // mirroring until it is replaced, so claiming it has stopped is
            // the same lie in the other direction.
            return state.engaged
                ? relaunchLine("Stops syncing", macIdiom: macIdiom)
                : String(localized: "Stays on \(deviceName)")
        }
        guard state.engaged else { return relaunchLine("Syncs", macIdiom: macIdiom) }
        // An error outranks every timestamp below it: a mirror that received
        // an hour ago and is failing now is failing, and leading with the hour
        // reads as health.
        if state.hasLiveError { return String(localized: "Couldn't sync — will keep retrying") }
        if let received = state.lastImport {
            return String(localized: "Received \(relative(received))")
        }
        // Engaged, no error, nothing has ever ARRIVED — and the two ways that
        // happens are different enough to be worth separate sentences. A
        // mirror that has only ever sent is working perfectly for somebody
        // with one device; reading "Synced" there teaches them to expect an
        // exchange that has not occurred, and then to read its absence as a
        // bug in the app.
        if let sent = state.lastExport {
            return String(localized: "Sent \(relative(sent)) — nothing received yet")
        }
        if state.lastSetup != nil { return String(localized: "Connected — nothing exchanged yet") }
        return String(localized: "Connecting to iCloud…")
    }

    /// **The Mac needs its own next-launch sentence, and that is the whole
    /// reason `macIdiom` is threaded this far down.** On a Mac, closing the
    /// window is not quitting: somebody who flips this toggle, closes the
    /// window and reopens it has done nothing at all — the process never died,
    /// so the container never rebound and the mirror never engaged. "From your
    /// next launch" is a phrase a Mac user reasonably believes they have
    /// already satisfied, which turns a setting that is merely waiting into
    /// one that appears broken. Naming the key is the difference.
    static func relaunchLine(_ verb: String, macIdiom: Bool) -> String {
        macIdiom
            ? String(localized: "\(verb) after you quit and reopen Casberi (⌘Q)")
            : String(localized: "\(verb) from your next launch")
    }

    private static func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named))
    }

    /// The sentence for a sync the GUARD turned off (prd §607).
    ///
    /// `SharedStore.containerWithFallback` can disable sync on its own after
    /// two consecutive launches that never proved they survived CloudKit
    /// setup. The only notice was a four-second flash, after which the tray
    /// read "Stays on \(deviceName)" — **the same sentence it shows for a
    /// choice the person actually made**. So the app silently stopped doing
    /// the thing they asked for and then described it as their preference.
    /// This is stated until they act on it.
    static func guardNotice(deviceName: String) -> String {
        String(localized: "Sync turned itself off after two launches that didn't finish connecting. Nothing was lost — it's all on \(deviceName).")
    }
}
