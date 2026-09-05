import Foundation

/// The Ethrex Privacy room's MOMENTS (prd §598) — what it marks, once, and
/// everything it refuses to mark.
///
/// Foundation-only by design so `scripts/privacy-selftest.sh` compiles it WHOLE
/// and unmodified, and every store is injectable for the same reason: a once-
/// ever flag whose only proof is "it did not fire again on my phone" is not
/// proven at all.
///
/// ## Why this room had none
///
/// Frames fires "Your first transaction landed" the first time a send this
/// phone signed turns out to be real; Hegotá and vibenet each flash their own
/// writes. This seat had **no moment of any kind** — not one `chrome.flash`,
/// not one first-sight animation, in the room whose subject is the rarest
/// thing on any of the four chains. It read as a very careful instrument that
/// never once said "look at this".
///
/// ## The three rules every moment here is held to
///
/// 1. **NEVER RETROACTIVE.** A fact that was already true before this build
///    existed is seeded silently. Firing "your first" over a week-old account
///    is the §83 claim in its most personal form.
/// 2. **NEVER A CELEBRATION OF SOMEBODY ELSE'S ACT.** This chain's pool is an
///    application contract whose ABI we do not have (§593), so this phone can
///    never spend a one-time key — every nullifier the room will ever show
///    belongs to a stranger. So the pool moment is worded as a DISCOVERY, and
///    the room says what appeared rather than congratulating anybody.
/// 3. **SILENT WHERE SILENCE IS THE ANSWER.** A snapshot leaving the window
///    is drawn and never announced: §593 ruled nothing is lost when it goes
///    and nothing can be done before it does, and a toast on a deadline
///    nobody can act on is chrome wearing urgency.
enum PrivacyDevnetMoments {

    // MARK: - Has this device ever finished a read

    private static let readOnceKey = "privacydevnet.moments.readOnce.v1"

    /// Whether the sweep about to run is this install's FIRST.
    ///
    /// It is the whole of rule 1 and it is a fact about the DEVICE rather than
    /// about any moment, which is why it is one flag rather than one per
    /// moment: on a first read everything the chain reports is history, and
    /// firing over history is the retroactive claim §83 bans.
    static func isFirstRead(_ defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: readOnceKey)
    }

    /// Called once a sweep has actually landed answers.
    static func markRead(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: readOnceKey)
    }

    // MARK: - The first one

    private static let firstSettleKey = "privacydevnet.firstSettle.celebrated.v1"
    private static let poolSightKey = "privacydevnet.poolSight.celebrated.v1"
    private static let seenKeysKey = "privacydevnet.seenNullifiers.v1"

    /// How many spent keys the seen-ledger remembers.
    ///
    /// A bound rather than a limit: 18 transactions exist chain-wide today. It
    /// exists so a chain that grows cannot turn a UserDefaults read into a
    /// page fault, and it drops the OLDEST, so the keys most likely to be
    /// on screen are the ones kept.
    static let seenCap = 400

    /// Whether the first-settle moment is still owed.
    static func firstSettleOwed(_ defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: firstSettleKey)
    }

    /// **THE NONCE IS THE SIGNAL, and it is the only one this seat has.**
    ///
    /// Frames watches a pending row become a landed one; this seat keeps no
    /// pending list, and building one to feed a toast would be a machine
    /// bigger than the moment. The account's nonce is incremented by the chain
    /// when a transaction it signed is INCLUDED — so 0 → non-zero is precisely
    /// "a transaction this phone signed turned out to be real", read from the
    /// same `eth_getTransactionCount` the room already makes.
    ///
    /// `seeding` is the first read of the install and is the whole of rule 1:
    /// a non-zero nonce there means the first send happened before anything
    /// was watching, so the moment is spent in silence rather than fired over
    /// history. Returns true only for a transition this device WATCHED.
    static func noteNonce(_ nonce: UInt64?, seeding: Bool,
                          _ defaults: UserDefaults = .standard) -> Bool {
        guard let nonce, firstSettleOwed(defaults) else { return false }
        guard nonce > 0 else { return false }
        if seeding {
            defaults.set(true, forKey: firstSettleKey)
            return false
        }
        return true
    }

    /// Called by the room once it has actually drawn the moment.
    ///
    /// **Spent HERE and not at the read** — Frames' own ruling: a celebration
    /// nobody was present for is not a celebration, and this room is one chip
    /// away from three others and may not have been open.
    static func spendFirstSettle(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: firstSettleKey)
    }

    // MARK: - The first spend key this room ever showed

    static func poolSightOwed(_ defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: poolSightKey)
    }

    /// Whether the room has just become able to show a one-time spend key for
    /// the first time.
    ///
    /// **A DISCOVERY, NEVER AN ACHIEVEMENT** (rule 2). The person did cause
    /// it — they chose the address — but they did not spend the key, and copy
    /// that congratulates them for a stranger's transaction is a claim about
    /// authorship. It is worth marking because on this chain it is rare: most
    /// transactions carry no nullifier at all (measured, §593), so a watched
    /// address turning out to have used the pool is the moment the room's own
    /// subject arrives.
    ///
    /// **Seeded silently on the first read**, same as the settle: an address
    /// already watched before this build existed brings its keys with it.
    static func notePoolSight(hasKeys: Bool, seeding: Bool,
                              _ defaults: UserDefaults = .standard) -> Bool {
        guard hasKeys, poolSightOwed(defaults) else { return false }
        if seeding {
            defaults.set(true, forKey: poolSightKey)
            return false
        }
        return true
    }

    static func spendPoolSight(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: poolSightKey)
    }

    // MARK: - Keys this device has already seen

    /// Which of these keys are new to this device.
    ///
    /// Drives the ring that SEALS on first sight — the shape's own claim
    /// (used once, never again) played once, then remembered. Deliberately in
    /// `UserDefaults` rather than a `Thing`: "have you looked at this" is a
    /// fact about THIS DEVICE'S SCREEN, which is `AddressConnectionsSeen`'s
    /// own ruling and needs no CloudKit deploy.
    static func unseen(_ keys: [Data], _ defaults: UserDefaults = .standard) -> Set<String> {
        let known = Set(defaults.stringArray(forKey: seenKeysKey) ?? [])
        return Set(keys.map(hex).filter { !known.contains($0) })
    }

    /// Take a set as seen. **First sight SEEDS SILENTLY** — the caller decides
    /// whether to animate before calling this, and on the very first read of an
    /// install every key is new, so animating all of them would be a room that
    /// seals forty rings at once on the day somebody arrives.
    static func markSeen(_ keys: [Data], _ defaults: UserDefaults = .standard) {
        var known = defaults.stringArray(forKey: seenKeysKey) ?? []
        let have = Set(known)
        for key in keys.map(hex) where !have.contains(key) { known.append(key) }
        if known.count > seenCap { known.removeFirst(known.count - seenCap) }
        defaults.set(known, forKey: seenKeysKey)
    }

    /// Whether this device has ever recorded a key at all — which is what
    /// separates "everything is new because you just arrived" from "one new
    /// key landed".
    static func hasSeenAnyKey(_ defaults: UserDefaults = .standard) -> Bool {
        !(defaults.stringArray(forKey: seenKeysKey) ?? []).isEmpty
    }

    /// Undone BY NAME, never a blanket wipe — the demo's teardown door, and a
    /// dev install may hold real moments under a neighbouring key.
    static func forgetAll(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: firstSettleKey)
        defaults.removeObject(forKey: poolSightKey)
        defaults.removeObject(forKey: seenKeysKey)
        defaults.removeObject(forKey: readOnceKey)
    }

    static func hex(_ d: Data) -> String {
        d.map { String(format: "%02x", $0) }.joined()
    }
}
