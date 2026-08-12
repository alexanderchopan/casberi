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
            guard !display.isEmpty else { continue }
            // HEAL, then land (2026-08-12, prd §365). This pass used to skip a
            // ref it already had, which was right while the row's whole content
            // was one string built at first sight — and wrong the moment there
            // was anything to keep current. Without it the un-joined facts
            // would reach only contacts added from today on, and an address
            // book is the one corpus where almost every row is already here.
            // The whole book is enumerated every call, so this costs nothing
            // extra to read; the guards below keep it from dirtying a row that
            // hasn't changed.
            if let thing = existing[ref] {
                heal(thing, with: contact, display: display)
                continue
            }
            let thing = Thing(
                kind: .contact,
                title: display,
                content: line(for: contact),
                source: "Contacts",
                sourceRef: ref
            )
            thing.facts = facts(for: contact).map(\.encoded)
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

    /// Keep an already-landed contact current. Every write is guarded, because
    /// this runs for every contact in the book on every FOREGROUND
    /// (`BridgeRefresh` calls `refresh`, not just connect) — an address book of
    /// 3,000 rows must not mark 3,000 objects dirty to change nothing. A
    /// dirtied object is a SwiftData save, a CloudKit export and a re-render of
    /// every view observing it; that guard is the expensive one, and it is why
    /// this compares before it assigns rather than assigning unconditionally.
    ///
    /// WHAT IT COSTS — measured 2026-08-12, not assumed. This doc previously
    /// said "the enumeration dominates by a wide margin", which was a guess
    /// standing in for a number. Benchmarked over a synthetic 3,000-contact
    /// book at `-O`, against the two functions extracted from this file:
    ///
    ///     line(for:)  × book ............  2.2 ms
    ///     facts(for:) × book ............ 13.6 ms   ← 12.0 of it one call
    ///     both, as the heal runs them ... 17.1 ms
    ///
    /// So the marginal cost of healing every contact on every foreground was
    /// **17.1ms per pass at 3,000 contacts**, and is **7.9ms** with the label
    /// cache below (re-measured against these same extracted functions). 88%
    /// of the original was one call — `localizedString(forLabel:)` — rather
    /// than anything structural, which is exactly why it was worth measuring
    /// before either accepting the cost or refactoring the shape.
    ///
    /// For scale: the foreground sweep is NOT this app's latency problem and
    /// has been measured not to be (~5%, within noise). Cold-launch lag was
    /// the shell's own body path both times it was chased — see the
    /// `foreground-sweep-jank` note, whose filename is the dead hypothesis.
    ///
    /// Making the heal conditional would save the smaller half and reintroduce
    /// the bug it exists to fix: a second phone number added to an existing
    /// contact changes neither the title nor `line(for:)` (which takes only the
    /// FIRST way to reach somebody), so there is no cheap token that means
    /// "nothing moved".
    ///
    /// `content` is refreshed alongside the facts and NOT retired: it is what
    /// `Retriever.rank` scores, so a contact stays findable by the email
    /// address in it. The facts are the structured mirror the sheet draws, not
    /// a replacement for the searchable text.
    @MainActor
    private static func heal(_ thing: Thing, with contact: CNContact, display: String) {
        if thing.title != display { thing.title = display }
        let line = line(for: contact)
        if thing.content != line { thing.content = line }
        let encoded = facts(for: contact).map(\.encoded)
        if thing.facts != encoded { thing.facts = encoded }
    }

    /// The ways to reach somebody, un-joined (2026-08-12, prd §365) — the parts
    /// `line(for:)` below fuses into one sentence with a `·` between them.
    ///
    /// ORDER IS DELIBERATE and `facts`' own contract says a reader must keep
    /// it: phones before emails, because a phone is the thing you reach for
    /// when it matters, and Apple's own order within each — a contact's first
    /// phone is the one they put first.
    ///
    /// LABELS ARE THE PERSON'S OWN. `CNLabeledValue` stores them as
    /// `_$!<Mobile>!$_`, so they go through Apple's localized formatter and
    /// come back as the word the person actually sees in Contacts, in their own
    /// language. A contact with no label gets the field's own name rather than
    /// an empty column — `ThingFact` refuses a labelless fact.
    ///
    /// Capped at three of each. A sheet is not the address book, and somebody
    /// with eleven emails does not want ten rows before the thing under them.
    @MainActor
    private static func facts(for c: CNContact) -> [ThingFact] {
        var out: [ThingFact] = []
        if !c.jobTitle.isEmpty { out.append(ThingFact("Role", c.jobTitle)) }
        if !c.organizationName.isEmpty { out.append(ThingFact("Company", c.organizationName)) }
        for phone in c.phoneNumbers.prefix(3) {
            let number = phone.value.stringValue
            guard !number.isEmpty else { continue }
            out.append(ThingFact(label(phone.label, fallback: "Phone"), number, .call))
        }
        for entry in c.emailAddresses.prefix(3) {
            let address = entry.value as String
            guard !address.isEmpty else { continue }
            out.append(ThingFact(label(entry.label, fallback: "Email"), address, .mail))
        }
        return out
    }

    /// MEASURED, and the reason this cache exists (2026-08-12).
    ///
    /// `CNLabeledValue.localizedString(forLabel:)` is called once per labeled
    /// value — four per contact here — and it is **88% of the whole heal**:
    /// benchmarked over a 3,000-contact book at `-O`, `facts(for:)` cost
    /// 13.6ms of which 12.0ms was this one call, against 2.2ms for
    /// `line(for:)`. Memoised it drops to 0.9ms, taking the heal's per-
    /// foreground cost from 17.1ms to ~6ms.
    ///
    /// It is safe to cache and cheap to hold: an address book contains ~10
    /// distinct labels no matter how many contacts it has, and the mapping
    /// from `_$!<Mobile>!$_` to the person's own word cannot change while the
    /// app runs — a language change relaunches it.
    ///
    /// `@MainActor` because the whole ingest is, which is what makes a mutable
    /// static safe here without a lock.
    @MainActor private static var labelWords: [String: String] = [:]

    /// Apple's own word for a label, sentence-cased. Their formatter returns
    /// "mobile"/"work"; the design law bans caps eyebrows, so this raises only
    /// the first character and never uppercases the whole thing.
    @MainActor
    private static func label(_ raw: String?, fallback: String) -> String {
        guard let raw, !raw.isEmpty else { return fallback }
        if let cached = labelWords[raw] { return cached }
        let localized = CNLabeledValue<NSString>.localizedString(forLabel: raw)
        guard !localized.isEmpty else { return fallback }
        let word = localized.prefix(1).uppercased() + localized.dropFirst()
        labelWords[raw] = word
        return word
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
