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
        // What the enumeration carries (widened 2026-08-14). Every key here is
        // filled by the SAME walk — the six this started with were not a budget,
        // they were simply the ones anyone had asked for, so an address book's
        // addresses, birthdays and websites were being enumerated past.
        //
        // `imageDataAvailable` is a Bool and costs nothing; the PIXELS are
        // deliberately not in this list. Including
        // `CNContactThumbnailImageDataKey` would load a thumbnail for every
        // contact in the book on every foreground — this file's own measured
        // budget is 7.9ms per pass at 3,000 contacts, and image bytes are a
        // different cost class entirely. The photo rides a bounded second pass
        // (`healPhotos`) instead, the shape `ScreenshotIngest.heal` already
        // uses: a little each foreground, self-terminating once the book is
        // covered.
        //
        // `CNContactNoteKey` is absent and will stay absent: since iOS 13 it
        // needs `com.apple.developer.contacts.notes`, an entitlement Apple
        // grants by request, and asking for one to read people's private notes
        // is not a trade this app should make.
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey,
                    CNContactJobTitleKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey,
                    CNContactPostalAddressesKey, CNContactBirthdayKey, CNContactUrlAddressesKey,
                    CNContactNicknameKey, CNContactSocialProfilesKey,
                    CNContactInstantMessageAddressesKey,
                    CNContactImageDataAvailableKey] as [CNKeyDescriptor]
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
            thing.enrichedText = retrievalText(for: contact)
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
        // The photos, a few at a time, AFTER the rows exist. Its own save, so a
        // pass that lands nothing new still makes progress on the faces.
        healPhotos(store: store, contacts: fetched, context: context)
        return landed.count
    }

    /// A contact's own photo, fetched a little at a time (2026-08-14).
    ///
    /// Contacts is the one Life bridge whose rows are PEOPLE, and every one of
    /// them drew a grey circle with initials in it while the real picture sat
    /// in the address book. The photo is the single most recognizable thing
    /// about a person and the cheapest possible way to make the sheet feel like
    /// theirs.
    ///
    /// BOUNDED, and that is the whole design. `CNContactThumbnailImageDataKey`
    /// is deliberately not in the main enumeration's key list — asking for it
    /// there loads a thumbnail for every contact in the book on every
    /// foreground, and this file's measured budget is 7.9ms per pass at 3,000
    /// contacts. So this asks for `photoBatch` contacts per pass, by
    /// identifier, only for people who HAVE a photo and whose row lacks one. It
    /// is self-terminating: once the book is covered it fetches nothing at all,
    /// forever, and the `imageDataAvailable` Bool that decides it rides the
    /// enumeration for free.
    ///
    /// THE THUMBNAIL, never `imageData`. The full image is a camera-resolution
    /// photograph; the thumbnail is the small square Contacts itself draws.
    /// This lands in `previewImageData`, which is `.externalStorage` and
    /// therefore a CloudKit asset per contact — the difference between the two
    /// is the difference between a few megabytes across a large book and a few
    /// hundred.
    @MainActor
    private static func healPhotos(store: CNContactStore, contacts: [CNContact],
                                   context: ModelContext) {
        let things = IngestSupport.thingsByRef(context, source: "Contacts")
        // `imageDataAvailable` is why this is nearly free on a settled book:
        // most contacts have no photo, and none of them are ever asked about.
        let wanted = contacts.lazy
            .filter(\.imageDataAvailable)
            .compactMap { contact -> (String, Thing)? in
                guard let thing = things["contact:\(contact.identifier)"],
                      thing.previewImageData == nil else { return nil }
                return (contact.identifier, thing)
            }
            .prefix(photoBatch)
        guard !wanted.isEmpty else { return }

        var patched = 0
        for (identifier, thing) in wanted {
            // One contact at a time, by identifier — the only way to ask for
            // image bytes without asking for the whole book's.
            guard let full = try? store.unifiedContact(
                withIdentifier: identifier,
                keysToFetch: [CNContactThumbnailImageDataKey as CNKeyDescriptor]),
                  let data = full.thumbnailImageData, !data.isEmpty
            else { continue }
            thing.previewImageData = data
            patched += 1
        }
        if patched > 0 { context.saveHonestly() }
    }

    /// How many photos one foreground pass will fetch. Small on purpose: a
    /// large book converges over a handful of opens rather than spending one
    /// of them on image decoding, and each photo is a CloudKit asset to
    /// export.
    private static let photoBatch = 25

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
        // The vector is dropped when the text really moved, for the reason
        // `ScheduleIngest.setSummary` states: `EmbeddingIndex` composes what it
        // embeds from the title and `enrichedText`, so a contact that gains a
        // nickname today would stay unfindable by it forever otherwise.
        let enriched = retrievalText(for: contact)
        if thing.enrichedText != enriched {
            thing.enrichedText = enriched
            thing.embedding = nil
        }
        // A contact who REMOVED their photo loses it here. Cheap — this reads a
        // Bool the enumeration already carries, never image bytes.
        if !contact.imageDataAvailable, thing.previewImageData != nil {
            thing.previewImageData = nil
        }
    }

    /// What a contact is findable BY, beyond the name and the first way to
    /// reach them (2026-08-14). Retrieval-only by the 2026-07-15 ruling —
    /// nothing draws it — which is exactly right for these: they are search
    /// terms, not things to look at.
    ///
    /// The nickname is the one that answers a question the corpus could not:
    /// a book that stores "Robert Smith" cannot be searched for "Bob", and
    /// "Bob" is what you would type. Social and IM handles are the join key
    /// between an address book and the social rooms — the corpus holds
    /// `@ana.bsky.social` in both places and, until now, could not tell that
    /// they were the same person.
    ///
    /// The postal address is here rather than in `line(for:)` on purpose:
    /// `line` is a display sentence that takes only the first way to reach
    /// somebody, and a street address is a search term, not a way to reach
    /// anyone. It is drawn as a fact instead.
    @MainActor
    private static func retrievalText(for c: CNContact) -> String? {
        var parts: [String] = []
        if !c.nickname.isEmpty { parts.append(c.nickname) }
        for address in c.postalAddresses.prefix(2) {
            let text = postalText(address.value)
            if !text.isEmpty { parts.append(text) }
        }
        // `service` as well as the handle: "Ana on Telegram" is how somebody
        // would ask, and the service name is half of that question.
        for profile in c.socialProfiles.prefix(4) {
            let handle = profile.value.username
            guard !handle.isEmpty else { continue }
            let service = profile.value.service
            parts.append(service.isEmpty ? handle : "\(service): \(handle)")
        }
        for im in c.instantMessageAddresses.prefix(4) {
            let handle = im.value.username
            guard !handle.isEmpty else { continue }
            let service = im.value.service
            parts.append(service.isEmpty ? handle : "\(service): \(handle)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
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
        // Below the ways to REACH somebody, the things that are true about
        // them (2026-08-14). All three ride the same enumeration and were
        // being walked past.
        //
        // The address is `.map` — the calendar's "Where" ruling, and the
        // stronger case of the two: an event's location is often a room name
        // Maps can't find, while a contact's address is an address.
        for address in c.postalAddresses.prefix(2) {
            let text = postalText(address.value)
            guard !text.isEmpty else { continue }
            out.append(ThingFact(label(address.label, fallback: "Address"), text, .map))
        }
        // A DATE and not a countdown: the birthday reaching "Coming up" would
        // be a second row for something the Birthdays calendar already lands
        // through `ScheduleIngest`, which is why this stays a fact and never
        // touches `dueAt`.
        if let birthday = birthdayText(c) {
            out.append(ThingFact(String(localized: "Birthday"), birthday))
        }
        for entry in c.urlAddresses.prefix(2) {
            let raw = (entry.value as String).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }
            // `.web` refuses anything without an http(s) scheme, so a bare
            // `ana.example` would render as a dead-looking row. Give it one —
            // this is a URL field, so a scheme-less value means the person
            // typed a host, not that they meant a different protocol.
            let normalized = raw.contains("://") ? raw : "https://\(raw)"
            out.append(ThingFact(label(entry.label, fallback: "Website"), normalized, .web))
        }
        return out
    }

    /// A postal address on ONE line — Apple's own formatter, in the reader's
    /// locale, so a Japanese address is ordered the way Japan orders one.
    ///
    /// The formatter is held STATIC, and that is this file's own measured
    /// lesson rather than a habit: `facts(for:)` runs for every contact on
    /// every foreground, and allocating a formatter per contact is exactly the
    /// per-call cost that made `localizedString(forLabel:)` 88% of the heal.
    ///
    /// Newlines collapse to commas because `ThingFact` draws two lines at most
    /// and a four-line address would be silently cut mid-street.
    @MainActor
    private static func postalText(_ address: CNPostalAddress) -> String {
        postalFormatter.string(from: address)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    @MainActor
    private static let postalFormatter: CNPostalAddressFormatter = {
        let f = CNPostalAddressFormatter()
        f.style = .mailingAddress
        return f
    }()

    /// A birthday in words, with or without a year.
    ///
    /// MOST BIRTHDAYS CARRY NO YEAR — people record the day and skip the
    /// year — so the yearless form is the common path, not the edge case. It
    /// gets its own formatter (`MMMMd`), because feeding a fabricated year to
    /// a normal date style prints that fabrication: "14 March 2000" for a
    /// person whose age nobody stored is the §83 fake fact, on a date somebody
    /// might act on.
    @MainActor
    private static func birthdayText(_ c: CNContact) -> String? {
        guard let parts = c.birthday, let month = parts.month, let day = parts.day,
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        var comps = DateComponents()
        comps.month = month
        comps.day = day
        // A placeholder year only so `Calendar` can make a Date at all; the
        // yearless formatter never prints it. A leap day needs a leap year, or
        // 29 February resolves to 1 March.
        comps.year = parts.year ?? 2000
        guard let date = Calendar.current.date(from: comps) else { return nil }
        return (parts.year == nil ? dayMonthFormatter : fullDateFormatter).string(from: date)
    }

    @MainActor
    private static let dayMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("MMMMd")
        return f
    }()

    @MainActor
    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()

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
