import Foundation

/// The one thing an import asks you before it runs (2026-08-05, prd §310).
///
/// PRIVATE MESSAGES ARE IN EVERY ONE OF THESE EXPORTS, and in every one of them
/// they are the largest body of prose in the file. §245 declined them, and the
/// wording of that decline is what this file implements rather than overturns:
///
///   > whether years of private conversation belong in a searchable index is a
///   > decision the person makes deliberately, not a side effect of tapping
///   > Import.
///
/// That is an argument for asking, and until now there was no way to answer.
/// The ruling has been read as "never" for three importers' lifetimes, which
/// made it a decision the app took on the person's behalf — the opposite of
/// what it says.
///
/// SO: OFF BY DEFAULT, and off is the whole safety property. Nothing here
/// changes unless someone reaches into a setup screen and turns it on, which
/// means every existing install and every unattended import behaves exactly as
/// it did. There is no migration, no prompt, and no clever default.
///
/// IT IS ALSO NOT A PROMISE TO IMPORT THEM. `SnapchatImport` needs nothing from
/// this — its whole corpus already IS the saved conversations, which is what
/// Snapchat's export gives instead of a message archive — and TikTok's DM path
/// is the least grounded of the four (see prd §310), so it is deliberately not
/// wired. A toggle that quietly does nothing for a source would be its own
/// small lie, which is why the screens that show it are the ones that honour
/// it.
enum ImportOptions {

    private static let messagesKey = "import.includeMessages"

    /// Whether an import should land private messages. False unless the person
    /// has said otherwise, on this device.
    static var includeMessages: Bool {
        get { UserDefaults.standard.bool(forKey: messagesKey) }
        set { UserDefaults.standard.set(newValue, forKey: messagesKey) }
    }

    /// The `@AppStorage` key, for the toggle to bind to directly rather than a
    /// screen mirroring the value into its own state and drifting from it.
    static var messagesStorageKey: String { messagesKey }

    /// What the toggle says about itself. One definition, so four screens can
    /// never describe the same switch differently.
    static let messagesTitle = String(localized: "Include private messages")
    static let messagesNote = String(localized: "Off by default. Your DMs are the largest thing in most exports and the most personal — they only come in if you ask, and they're searchable like everything else once they do. Turning this off later doesn't remove what already landed; use Remove for that.")
}
