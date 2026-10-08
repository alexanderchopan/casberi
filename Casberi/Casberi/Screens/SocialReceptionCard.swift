import SwiftUI

/// HOW IT LANDED — the block that replaced the spec table on a social sheet
/// (prd §363, 2026-08-12).
///
/// The spec table's whole contribution to a social post was one row reading
/// `From — saved by you`, in its own card, behind an 80pt label column. This
/// says the same thing in a sentence and puts beside it the two readings the
/// record already held: what the network reported, and WHO liked it.
///
/// ## The form, and what is deliberately not in it
///
/// - **No hue.** Nothing here is a gain or a loss; it is a reading. The
///   approvals card's ruling (§292: "no hue on the amounts, and no green/red
///   anywhere") applies for the identical reason one room over.
/// - **No glyphs on the numbers.** The old engagement line led each count with
///   a heart / arrows / bubble at `label12`, which is a hairline's worth of
///   ink doing a word's job; here the noun is written out under the number,
///   where it also reads correctly at any Dynamic Type size.
/// - **No bars, no trend, no delta.** A reading, never news (§223). The
///   tripwire: the moment this block grows a "+12 since yesterday" line it has
///   become the tally the module doctrine bans, and should be cut back.
/// - **An absent count has no cell.** Unchanged from the line it replaces, and
///   the only reason any number here can be trusted.
///
/// FLAT BY LAW like its siblings — a plain VStack, no generic `Widget`/`Row`
/// mount (the render-depth lesson, paid three times).
///
/// Liveness: stores no `Thing`, only the value type out of `SocialReception`,
/// so corollary 5 has nothing to guard here.
struct SocialReceptionCard: View {
    let reception: SocialReception

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if !reception.readings.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s6) {
                    ForEach(reception.readings, id: \.noun) { reading in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(reading.text)
                                .dsText(.heading24)
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
            // Names, never a bare number (§239). Second, under the counts,
            // because the counts are what the eye lands on and this is what
            // the counts are ABOUT.
            if let likers = reception.likers {
                Text(likers)
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let ceiling = reception.ceiling {
                Text(ceiling)
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The two quiet lines last, in the type tier the spec table's own
            // labels used — they are the footnote, not the reading.
            if let provenance = reception.provenance {
                Text(provenance)
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let recorded = reception.recorded {
                Text(recorded)
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // On no plate (prd §782): air separates it from the blocks around it.
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// THE POST THIS ONE ANSWERS, as a card (prd §363).
///
/// It was a label — "Replying to @jessepollak" — which names a person and
/// withholds the sentence, so a reply in the corpus read as a non sequitur
/// unless you already remembered the conversation. The parent's words are in
/// the record on every source that has a parent at all (`Thing.parent` carries
/// a `SocialCard`), and this draws them.
///
/// Two lines, clamped: it is CONTEXT, not the point. The tap walks into it, so
/// the rest is one gesture away — which is also why this stays a sheet-only
/// view and the feed row keeps its label (`ReplyingToRow`): a row must not
/// carry a presentation of its own, the bug that shipped in the 2026-07-27
/// pass and took the whole thing sheet down with it.
///
/// A parent with no words (X's archive names a handle and nothing more) falls
/// back to the line it replaces rather than drawing an empty card — the honest
/// reading of "we know who, not what".
struct ReplyingToCard: View {
    let parent: SocialCard
    let source: String
    var onOpen: () -> Void

    private var words: String {
        parent.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: DS.Space.s3) {
                // A rail, not a hairline: it is a 2pt shape marking a quoted
                // block — the no-hairlines law is about DIVIDERS, and this
                // divides nothing.
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(DS.fillFaint)
                    .frame(width: 2)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: DS.Space.s2) {
                        if let avatar = parent.avatarURL, !avatar.isEmpty {
                            RemoteThumb(urlString: avatar, size: DS.Face.badge,
                                        fallback: source, circular: true)
                        }
                        Text("Replying to @\(SocialThread.shortHandle(parent.handle))")
                            .dsText(.label12).foregroundStyle(DS.textTertiary)
                        Spacer(minLength: 0)
                    }
                    if !words.isEmpty {
                        Text(words)
                            .dsText(.body17).foregroundStyle(DS.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
        .accessibilityLabel(Text("Replying to \(parent.handle). Opens the post."))
    }
}

/// A PERSON, not a link to one (prd §363), in the room's frame since prd
/// §1187: the face leads, centred, like a contact poster, the handle under
/// the name, and how you know them in the stamps. The box is a DOOR to their
/// profile (`SocialProfileCard`); what of theirs you already have is the
/// sheet's list under the tiles.
struct SocialPersonBox: View {
    let handle: String
    let displayName: String?
    let avatarURL: String?
    let source: String
    /// When they came to you: a follow's day.
    let since: Date
    /// You follow them back (`SocialPeople.isWatched`).
    let following: Bool
    var onOpenProfile: () -> Void

    var body: some View {
        Button(action: onOpenProfile) {
            VStack(spacing: DS.Space.s2) {
                Group {
                    if let avatarURL, !avatarURL.isEmpty {
                        RemoteThumb(urlString: avatarURL, size: DS.Face.profile,
                                    fallback: source, circular: true)
                    } else {
                        BridgeIcon(name: source, size: DS.Face.profile, circular: true)
                    }
                }
                .padding(.top, DS.Space.s1)
                if let displayName, !displayName.isEmpty {
                    Text(verbatim: displayName)
                        .dsText(.heading20)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                }
                Text(verbatim: "@\(SocialThread.shortHandle(handle))")
                    .dsText(displayName?.isEmpty == false ? .subhead12 : .heading20)
                    .foregroundStyle(displayName?.isEmpty == false ? DS.textSecondary : DS.textPrimary)
                    .lineLimit(1)
                Text(verbatim: source)
                    .dsText(.subhead12)
                    .foregroundStyle(DS.textSecondary)
                Spacer(minLength: 0)
                HStack(spacing: DS.Space.s2) {
                    DSStamp(word: String(localized: "Followed you \(FeedScreen.dayWord(since))"))
                    if following { DSStamp(word: String(localized: "You follow them")) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressSpring())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken))
        .accessibilityHint(Text("Opens their profile"))
    }

    private var spoken: String {
        let who = [displayName, "\(SocialThread.shortHandle(handle)) on \(source)"]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        var line = "\(who). " + String(localized: "Followed you \(FeedScreen.dayWord(since))")
        if following { line += ". " + String(localized: "You follow them") }
        return line
    }
}
