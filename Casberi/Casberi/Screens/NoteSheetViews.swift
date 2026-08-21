import SwiftUI

/// THE NOTE SHEET'S THREE ANATOMIES (prd §366, 2026-08-12).
///
/// Every view here is FLAT BY LAW — plain stacks, no generic `Widget`/`Row`
/// mount (the first-frame render-depth lesson, paid three times).
///
/// Liveness: each of these stores VALUES, never a `Thing`, except where a
/// shelf must walk into one — and there the row is a `KeyedThing` re-checked
/// inside the `ForEach` closure (corollary 3). So corollary 5 has nothing to
/// guard in this file.

// MARK: - Entry: the date is the identity

/// The hero of a dated piece of writing.
///
/// A journal entry's title was cut out of its own first line, so leading with
/// it printed that line twice and named nothing — while the entry's date, the
/// one fact that actually identifies it and the only fact every source in this
/// category carries, appeared nowhere on the sheet at all beyond the eyebrow's
/// "3y ago".
///
/// The day is the headline; the year, the act and the time are the quiet line
/// under it. The year drops out when it is this one (`NoteSheet.dateline`) —
/// stating "2026" over something written this morning is the obvious said in
/// the loudest slot on the screen.
struct NoteDateline: View {
    let dateline: NoteSheet.Dateline

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(dateline.headline)
                .dsText(.heading28)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Text(dateline.detail)
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        }
        // The day and its clause are one fact; read apart they are a bare
        // date and a loose fragment.
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - The body

/// A note's own words, at the tier writing is read in.
///
/// Every body in this category drew at `callout15` in `textSecondary` — the
/// tier the design system uses for a footnote UNDER a fact — and four of six
/// sources clamped it at twelve lines with no "more" and nothing to scroll.
/// On these sources the body is not an annotation of the thing, it IS the
/// thing.
///
/// So: `reading20`, primary ink, and **no line limit at all past the fold**.
/// The clamp is replaced by a real disclosure — a long entry shows its opening
/// and says how much more there is, which is a promise the twelve-line cut
/// never made and never kept.
struct NoteProse: View {
    let text: String
    /// `false` for a passage: somebody else's marked sentence is set in the
    /// same tier but is never long enough to fold, and a "Read more" under a
    /// quotation would be a control that does nothing.
    var foldable: Bool = true
    /// Is this body really markdown? A per-source FACT — see
    /// `NoteSheetSource.markdownSources`. False draws one paragraph exactly as
    /// this view always has.
    var markdown: Bool = false
    /// Does `[[this]]` mean something here? Obsidian only.
    var wikilinks: Bool = false
    /// Walks an inline wikilink. nil leaves them drawn but inert, which is why
    /// the sheet always passes one — a tinted word that does nothing is the
    /// dead control the honesty law bans.
    var onWikilink: ((String) -> Void)?
    /// The tier the body is set in (2026-08-20).
    ///
    /// `reading20` is this view's own ruling and stays the default: on a note
    /// the body is not an annotation of the thing, it IS the thing. An agent
    /// TURN is the exception — it sits inside a bubble beside a speaker label,
    /// where the sheet's hero is the conversation rather than any one message,
    /// so it is set at `callout15` like the bubble it lives in.
    ///
    /// Parameterised rather than forked: the alternative was a second block
    /// renderer beside this one, and two renderers over one splitter is how a
    /// code fence starts drawing correctly in one room and as prose in the
    /// other.
    var tier: DSTextStyle = .reading20
    /// The ink the prose is set in (2026-08-21).
    ///
    /// `textPrimary` is this view's own ruling and stays the default, for the
    /// same reason `reading20` is: on a note the body IS the thing. The generic
    /// thing sheet is the exception — there the body really is an annotation
    /// under a fact (a reminder's note, a contact's detail), which is why that
    /// branch has always drawn it secondary, and borrowing the fold must not
    /// silently re-rank the whole category's type.
    ///
    /// Parameterised for the reason `tier` was: one splitter, one renderer.
    var ink: Color = DS.textPrimary

    @State private var expanded = false

    private var blocks: [NoteSheet.Block] {
        NoteSheet.blocks(text, markdown: markdown)
    }

    private var shown: [NoteSheet.Block] {
        guard foldable, !expanded else { return blocks }
        return NoteSheet.folded(blocks)
    }

    private var folds: Bool { foldable && !expanded && shown.count < blocks.count }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
            if folds {
                Button {
                    withAnimation(DS.Motion.standard) { expanded = true }
                } label: {
                    // Says HOW MUCH more, not just "more" — the whole failure
                    // this replaces was a silent cut, and a disclosure that
                    // won't say what it is hiding repeats it politely.
                    Text("Read the rest — \(NoteSheet.words(in: text).formatted(.number)) words")
                        .dsText(.callout15)
                        .foregroundStyle(DS.tint)
                }
                .buttonStyle(.plain)
                .dsHover()
            }
        }
        // ONE handler for the whole body rather than one per block: an
        // `OpenURLAction` is an environment value, so installing it here covers
        // every link in every block and cannot be forgotten on a new case.
        // Anything that is not ours falls through to the system untouched —
        // a real URL somebody wrote in their note still opens their browser.
        .environment(\.openURL, OpenURLAction { url in
            guard let target = NoteSheet.wikiTarget(url) else { return .systemAction }
            onWikilink?(target)
            return .handled
        })
    }

    /// The four shapes, each at the tier it is read in.
    ///
    /// A heading is `heading17` at every level rather than a ramp per level:
    /// this is a note inside a sheet, not a document, and six type sizes inside
    /// a body would out-shout the sheet's own hero. The LEVEL still shows, as
    /// the indent — which is what a level means.
    @ViewBuilder
    private func view(for block: NoteSheet.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            prose(text)
                .dsText(.heading17)
                .foregroundStyle(DS.textPrimary)
                .padding(.leading, CGFloat(min(level, 3) - 1) * DS.Space.s3)
        case .bullet(let text):
            marked("•", prose(text))
        case .numbered(let index, let text):
            marked("\(index).", prose(text))
        case .quote(let text):
            // The rail is a 2pt shape marking a quoted block, not a divider:
            // the no-hairlines law is about DIVIDERS, and this divides nothing
            // (`NotePassageContent`'s rail, one shape over).
            HStack(alignment: .top, spacing: DS.Space.s3) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(DS.fillFaint)
                    .frame(width: 2)
                prose(text)
                    .dsText(tier)
                    .foregroundStyle(DS.textSecondary)
            }
        case .paragraph(let text):
            prose(text)
                .dsText(tier)
                .foregroundStyle(ink)
                // Words are what people copy a phrase out of, and until §366 no
                // note body in this app allowed it.
                .textSelection(.enabled)
        case .code(let language, let text):
            // VERBATIM, and monospaced — the two things that make code code.
            // `Text(verbatim:)` rather than `prose`, because every step `prose`
            // takes is wrong here: an inline markdown parse would eat the
            // asterisks in `a * b`, the linkifier would turn a URL in a comment
            // into a tappable control inside a program, and a wikilink rewrite
            // would claim `[[i]]` was a note.
            VStack(alignment: .leading, spacing: 4) {
                if let language {
                    Text(verbatim: language)
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                }
                // Scrolls in its own container rather than wrapping: a wrapped
                // line of code silently changes the shape of the program, and
                // the page itself must never scroll sideways.
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(verbatim: text)
                        .dsText(.callout15)
                        .monospaced()
                        .foregroundStyle(DS.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: true)
                }
            }
            .padding(DS.Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.fillFaint,
                        in: RoundedRectangle(cornerRadius: DS.Radius.widget,
                                             style: .continuous))
        }
    }

    /// A list item: its mark and its words, the words wrapping under
    /// themselves rather than under the mark.
    private func marked(_ mark: String, _ content: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Text(verbatim: mark)
                .dsText(tier)
                .foregroundStyle(DS.textTertiary)
                .monospacedDigit()
            content
                .dsText(tier)
                .foregroundStyle(DS.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One block's words: wikilinks rewritten, then inline markdown, then the
    /// plain-URL linkifier the sheet has always run.
    ///
    /// The ORDER is load-bearing. Wikilinks become markdown links, so they must
    /// be rewritten BEFORE the markdown parse; and the parse is
    /// `inlineOnlyPreservingWhitespace`, because this view has already split the
    /// blocks and letting the parser do it again would collapse the line breaks
    /// `NoteSheet.blocks` deliberately kept.
    private func prose(_ text: String) -> Text {
        var body = text
        if wikilinks { body = NoteSheet.markdownWithWikilinks(body) }
        guard markdown else {
            return Text(ProseLinks.rendered(body))
        }
        // A body is somebody's own writing and may hold anything; a parse that
        // throws leaves the words exactly as they were rather than losing them.
        guard var attributed = try? AttributedString(
            markdown: body,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        else { return Text(ProseLinks.rendered(text)) }
        for run in attributed.runs where run.link != nil {
            attributed[run.range].foregroundColor = DS.tint
        }
        return Text(attributed)
    }
}

/// The person's own tags, drawn.
///
/// Obsidian lands frontmatter and inline tags and Day One lands the export's
/// own; the filter could reach them and no note sheet rendered `thing.tags` at
/// all. The app's own kind tag is filtered out at the source layer — putting
/// "Note" beside "#legibility" would present a machine's label as a choice the
/// person made.
///
/// Not chips-as-controls: these are what the note SAYS it is about. Tapping
/// one is the tag filter's job and the tag filter is the agent's (§269), so
/// nothing here is a button and nothing here is dead.
struct NoteTagRow: View {
    let tags: [String]

    var body: some View {
        FlowLayout(spacing: DS.Space.s2) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
                    .padding(.horizontal, DS.Space.s2)
                    .padding(.vertical, 4)
                    .background(DS.fillFaint,
                                in: Capsule(style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Passage: somebody else's words

/// A marked passage, and the work it came from.
///
/// The record had these two the wrong way round — the (truncated) passage in
/// the title slot and the book's name as the body — so the sheet drew a
/// quotation at display size as though it were a headline. The passage is the
/// hero here and the work is the identity beneath it, which is also the order
/// a person would write a quotation down in.
///
/// The rail is a 2pt shape marking a quoted block, not a divider: the
/// no-hairlines law is about DIVIDERS, and this divides nothing (the same
/// reasoning `ReplyingToCard`'s rail already carries).
struct NotePassageContent: View {
    let passage: String
    /// "Piranesi — Susanna Clarke", exactly as the clippings file wrote it.
    let citation: String
    /// "page 42" / "location 611-612", or nil on a file we can't read a
    /// locator out of.
    let locator: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            HStack(alignment: .top, spacing: DS.Space.s3) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(DS.fillFaint)
                    .frame(width: 2)
                NoteProse(text: passage, foldable: false)
            }
            HStack(spacing: DS.Space.s3) {
                KindGlyph(kind: .note, size: DS.Face.list)
                VStack(alignment: .leading, spacing: 2) {
                    Text(citation)
                        .dsText(.heading17)
                        .foregroundStyle(DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let locator, !locator.isEmpty {
                        Text(locator)
                            .dsText(.label12)
                            .foregroundStyle(DS.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// The other passages you marked in the same work.
///
/// This is what makes ONE highlight worth opening. A marked sentence out of
/// context is a fragment; the eleven others from the same book are already in
/// the corpus, and no Kindle screen will ever show them to you together.
///
/// The rows are the passages themselves, not their titles — the title is a
/// clamp of the same words, and a list of clamped versions of a thing you can
/// already read is a list of nothing.
struct NoteSiblingList: View {
    let rows: [KeyedThing]
    var onOpen: (Thing) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // `.live` INSIDE the closure (corollary 3): the array this
            // `ForEach` holds was filtered when the view value was made, which
            // is before any delete that lands while the sheet is open.
            ForEach(rows) { row in
                if let thing = row.live {
                    Button { onOpen(thing) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(NoteSheetSource.passage(for: thing))
                                .dsText(.callout15)
                                .foregroundStyle(DS.textSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(sublineText(thing))
                                .dsText(.label12)
                                .foregroundStyle(DS.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, DS.Space.s2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .dsHover()
                }
            }
        }
    }

    /// "page 88 · 11 days ago", or just the age where the file named no page.
    private func sublineText(_ thing: Thing) -> String {
        let age = NoteSheet.relative(thing.capturedAt, now: .now)
        guard let locator = thing.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
              !locator.isEmpty else { return age }
        return "\(locator) · \(age)"
    }
}

// MARK: - The vault graph

/// How this note sits among the others.
///
/// Both halves already existed and both were a plain list at the very bottom
/// of the sheet, under everything: `NoteLinks` has resolved a vault's own
/// `[[wikilinks]]` since 2026-07-28 and `ThingLinks` has answered the inverse
/// since §340. Counted and led with, they are a READING — this note is a hub,
/// or this note is a leaf — which is a thing you can act on; listed at the
/// end, they were two more rows.
///
/// The two counts stay SEPARATE and are never summed: a note that both links
/// to and is linked from another would otherwise be counted twice, and the
/// directions are the whole information (`backlinksSection`'s standing rule).
struct NoteGraphCounts: View {
    let linksOut: Int
    let linkedFrom: Int

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            cell(linksOut, String(localized: "links out"))
            cell(linkedFrom, String(localized: "notes link here"))
        }
    }

    private func cell(_ value: Int, _ noun: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value.formatted(.number))
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
                .monospacedDigit()
            Text(noun)
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.s3)
        .background(DS.fillFaint,
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - That day

/// Everything else the corpus holds from the day an entry describes.
///
/// The single strongest argument that a journal entry belongs in a corpus
/// rather than in a journal app: the day you wrote about is a day this app
/// already holds photographs, movements, captures and money for, and no
/// journal app can show you any of them. One bounded predicate, not a walk.
///
/// A tile shows the thing's own picture where it has one and its kind's glyph
/// where it doesn't — never a generic placeholder pretending to be an image.
struct NoteSameDayShelf: View {
    let rows: [KeyedThing]
    var onOpen: (Thing) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.Space.s2) {
                ForEach(rows) { row in
                    if let thing = row.live {
                        tile(thing)
                    }
                }
            }
            .padding(.horizontal, DS.Space.s4)
        }
        // The shelf bleeds to the sheet's edges on purpose — a horizontal run
        // that stops short of the margin reads as a list that has ended.
        .padding(.horizontal, -DS.Space.s4)
    }

    private func tile(_ thing: Thing) -> some View {
        Button { onOpen(thing) } label: {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                thumb(thing)
                    .frame(width: 92, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card,
                                                style: .continuous))
                Text(thing.title)
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: 92, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsHover()
        .accessibilityLabel(Text("\(thing.title), from \(thing.source)"))
    }

    @ViewBuilder private func thumb(_ thing: Thing) -> some View {
        if let data = thing.previewImageData, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
        } else if let url = thing.previewImageURL, !url.isEmpty {
            RemoteThumb(urlString: url, size: 92, fallback: thing.source)
        } else {
            ZStack {
                Rectangle().fill(DS.fillFaint)
                KindGlyph(kind: thing.kind, size: 26)
            }
        }
    }
}

// MARK: - How it landed

/// The block that replaced the spec table on a note sheet (prd §366).
///
/// The table's whole contribution to a note was one row reading `From —
/// written by you`, in its own card, behind an 80pt label column. It said less
/// than the eyebrow directly above it, which already names the source. This
/// says where the thing came from in a sentence, and puts beside it the
/// readings the record already held.
///
/// ## The form, and what is deliberately not in it
///
/// - **No hue.** Nothing here is a gain or a loss; it is a reading (§292's
///   ruling, one category over).
/// - **No glyphs on the numbers.** The noun is written out under each, where
///   it reads correctly at any Dynamic Type size.
/// - **No bars, no trend, no delta.** A reading, never news (§223). The
///   tripwire: the moment this grows a "+120 words since Tuesday" line it has
///   become the tally the module doctrine bans.
/// - **A measurement we cannot make has no cell**, and one we can only bound
///   wears a `+` (`SocialCount`'s "97+" valve). A word count taken over a
///   clamped body understates a real note by thousands while looking exactly
///   like a measurement — that is the failure this rule exists for.
struct NoteReceptionCard: View {
    let reception: NoteReception

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if !reception.readings.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s6) {
                    ForEach(reception.readings, id: \.noun) { reading in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(reading.text)
                                .dsText(.heading22)
                                .foregroundStyle(DS.textPrimary)
                                .monospacedDigit()
                            Text(reading.noun)
                                .dsText(.label12)
                                .foregroundStyle(DS.textTertiary)
                        }
                        // The number and its noun are one fact; read apart
                        // they are a bare digit and a loose word.
                        .accessibilityElement(children: .combine)
                    }
                    Spacer(minLength: 0)
                }
            }
            if let ceiling = reception.ceiling {
                Text(ceiling)
                    .dsText(.callout15)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The quiet line last, in the tier the spec table's own labels
            // used — it is the footnote, not the reading.
            if let provenance = reception.provenance {
                Text(provenance)
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.fillFaint,
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}

// MARK: - The entry's own photograph

/// A journal entry's picture (prd §399, 2026-08-17).
///
/// §398 landed the two journal exports' photographs — Day One's `photos/`,
/// Apple Journal's `Resources/` — as the same `previewImageData` thumbnail
/// every other picture in this app is. And nothing drew them. An entry's own
/// photograph appeared in exactly one place in the whole app: as a 92pt tile on
/// a DIFFERENT entry's "That day" shelf. The sheet for the entry that owns it
/// showed a date and some words.
///
/// It sits BELOW the dateline and above the prose, which is the order the entry
/// itself has: the date identifies it, and the photograph is part of what it
/// says rather than a heading over it.
///
/// Liveness: stores a `Thing`, so it guards its own body (corollary 5) — and
/// `PhotoWell` inside it guards again, which is not redundant, since SwiftUI
/// re-runs a leaf on the model's own observation independently of this one.
struct NoteEntryPhoto: View {
    let thing: Thing
    var onZoom: () -> Void

    var body: some View {
        if thing.isLive, thing.previewImageData != nil {
            Button {
                DSHaptic.selection()
                onZoom()
            } label: {
                // `PhotoWell` and not a hand-rolled `Image`: it decodes ONCE
                // into its own state instead of re-decoding on every body
                // evaluation, and it is the one image view in this app that
                // honours `redactionReasons` — a private photograph at this size
                // surviving into the app-switcher snapshot is exactly the leak
                // that guard exists to stop.
                PhotoWell(thing: thing, size: nil)
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card,
                                                style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card,
                                                   style: .continuous))
            }
            .buttonStyle(DSTileButtonStyle())
            .accessibilityLabel(Text("Photograph from this entry. Opens it full screen."))
        }
    }
}

// MARK: - The same date, in other years

/// What you wrote on this date in the other years you kept this journal
/// (prd §399).
///
/// The room's anniversary answers TODAY's date; this answers the ENTRY's, which
/// is the reading a journal is opened for. A year leads each row because the
/// year is the whole finding — the day and month are the same on every one of
/// them, and repeating them would be the label-for-a-label failure.
///
/// The line beneath is the entry's own opening, never its title: for these
/// sources the title IS the opening line, so drawing both would print it twice
/// (the §398 `ExcerptRow` defect, one screen over).
struct NoteOtherYearsList: View {
    let rows: [KeyedThing]
    var onOpen: (Thing) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // `.live` INSIDE the closure (corollary 3): the array this `ForEach`
            // holds was filtered when the view value was made, which is before
            // any delete that lands while the sheet is open.
            ForEach(rows) { row in
                if let thing = row.live {
                    Button { onOpen(thing) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
                            Text(verbatim: String(
                                Calendar.current.component(.year, from: thing.capturedAt)))
                                .dsText(.heading17)
                                .foregroundStyle(DS.textPrimary)
                                .monospacedDigit()
                            Text(thing.title)
                                .dsText(.callout15)
                                .foregroundStyle(DS.textSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, DS.Space.s2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .dsHover()
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

// MARK: - The entry before, and the entry after

/// The two doors that make a journal readable AS a journal (prd §399).
///
/// A journal is a sequence and the sheet dead-ended, so reading three
/// consecutive days meant sheet, close, scroll, sheet, three times over. These
/// are the same walk the sibling passages and the day shelf already use.
///
/// **Older on the left, newer on the right** — the direction the writing went,
/// not the direction the feed scrolls. And each door names its entry's DATE
/// rather than saying "Previous": a door that says where it goes is worth more
/// than one that says which way, and the date is what identifies an entry here.
///
/// A missing neighbour draws NOTHING rather than a disabled control: the first
/// entry in a journal really has nothing before it, and greying out a door onto
/// a thing that does not exist is furniture.
struct NoteNeighbourDoors: View {
    let previous: KeyedThing?
    let next: KeyedThing?
    var onOpen: (Thing) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s2) {
            door(previous, systemImage: "chevron.left", trailing: false)
            door(next, systemImage: "chevron.right", trailing: true)
        }
    }

    @ViewBuilder
    private func door(_ row: KeyedThing?, systemImage: String, trailing: Bool) -> some View {
        // Liveness re-checked HERE and not only where the value was made: a heal
        // can delete the neighbour while this sheet is open (corollary 3).
        if let thing = row?.live {
            Button {
                DSHaptic.selection()
                onOpen(thing)
            } label: {
                HStack(spacing: DS.Space.s2) {
                    if !trailing { chevron(systemImage) }
                    VStack(alignment: trailing ? .trailing : .leading, spacing: 1) {
                        Text(thing.capturedAt.formatted(.dateTime.day().month(.abbreviated)))
                            .dsText(.callout15)
                            .foregroundStyle(DS.textPrimary)
                        Text(thing.title)
                            .dsText(.label12)
                            .foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
                    if trailing { chevron(systemImage) }
                }
                .padding(DS.Space.s3)
                .frame(maxWidth: .infinity)
                .background(DS.fillFaint,
                            in: RoundedRectangle(cornerRadius: DS.Radius.card,
                                                 style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsHover()
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(trailing
                ? "The entry after this one, \(thing.title)"
                : "The entry before this one, \(thing.title)"))
        } else {
            // Holds the other door's width so a lone neighbour doesn't stretch
            // across the sheet and read as the only thing there is.
            Color.clear.frame(maxWidth: .infinity).frame(height: 0)
        }
    }

    private func chevron(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .dsGlyph(13, weight: .semibold)
            .foregroundStyle(DS.textTertiary)
    }
}
