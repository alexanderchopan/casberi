import Foundation
import Contacts
import SwiftData

/// The Contacts bridge (2026-07-12) — a system read bridge, like Photos and
/// Calendar: the permission ask arrives in context, connect ends in proof.
/// Contacts land as SEARCH-ONLY person things (kind `.contact`): they ride the
/// corpus for lookup, Spotlight, and the answer path, but the feed filters
/// them out so a big address book never buries the day's real captures
/// (ruling 2026-07-12). Everything stays on this iPhone — CNContactStore never
/// touches a server. Read-only.
enum ContactsIngest {

    @MainActor private static var running = false

    /// Requests Contacts access and lands each contact. Returns the number
    /// added, or nil when access is denied — the connect path words that.
    static func connectAndIngest(context: ModelContext) async -> Int? {
        let store = CNContactStore()
        let granted: Bool = await withCheckedContinuation { cont in
            store.requestAccess(for: .contacts) { ok, _ in cont.resume(returning: ok) }
        }
        guard granted else { return nil }
        return await ingest(context: context)
    }

    /// The bare re-scan foreground refresh calls — runs only when access is
    /// already granted, so it never re-presents the permission dialog.
    static func refresh(context: ModelContext) async -> Int? {
        // iOS 18 added `.limited` — requestAccess grants it as true, so the
        // re-scan must accept it too or new contacts never re-ingest.
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited: return await ingest(context: context)
        default: return nil
        }
    }

    @MainActor
    private static func ingest(context: ModelContext) async -> Int? {
        guard !running else { return 0 }
        running = true
        defer { running = false }

        let store = CNContactStore()
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey,
                    CNContactJobTitleKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)

        var fetched: [CNContact] = []
        do {
            try store.enumerateContacts(with: request) { contact, _ in fetched.append(contact) }
        } catch {
            return nil
        }

        let existing = IngestSupport.thingsByRef(context, source: "Contacts")
        // An address book runs to thousands — collect the new things and index
        // Spotlight once at the end, rather than a call per contact.
        var landed: [Thing] = []
        var seen = Set<String>()
        for contact in fetched {
            // Marked seen BEFORE the display-name check: a contact edited
            // down to no name still exists (just anonymized) and must not
            // read as deleted below.
            let ref = "contact:\(contact.identifier)"
            seen.insert(ref)
            let name = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }.joined(separator: " ")
            let display = name.isEmpty ? contact.organizationName : name
            guard !display.isEmpty, existing[ref] == nil else { continue }
            let thing = Thing(
                kind: .contact,
                title: display,
                content: line(for: contact),
                source: "Contacts",
                sourceRef: ref
            )
            context.insert(thing)
            landed.append(thing)
        }
        // RECONCILE: `enumerateContacts` walks the WHOLE address book every
        // call (no window), so a ref this pass never saw was deleted or
        // merged away, not just outside some range.
        var removedIDs: [UUID] = []
        for (ref, thing) in existing where !seen.contains(ref) {
            removedIDs.append(thing.id)
            context.delete(thing)
        }
        if !landed.isEmpty { SpotlightIndex.index(landed) }
        if !removedIDs.isEmpty { SpotlightIndex.remove(ids: removedIDs) }
        if !landed.isEmpty || !removedIDs.isEmpty { context.saveHonestly() }
        return landed.count
    }

    /// A one-line subtitle — job/org, then the first way to reach them.
    private static func line(for c: CNContact) -> String {
        var parts: [String] = []
        if !c.jobTitle.isEmpty { parts.append(c.jobTitle) }
        if !c.organizationName.isEmpty { parts.append(c.organizationName) }
        if let email = c.emailAddresses.first?.value as String? {
            parts.append(email)
        } else if let phone = c.phoneNumbers.first?.value.stringValue {
            parts.append(phone)
        }
        return parts.joined(separator: " · ")
    }
}
