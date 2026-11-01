import SwiftUI

/// What a Telegram CHANNEL post's sheet reads off its row (prd §1637): the
/// channel's handle off the ref, whose post a forward repeats, and the page's
/// own words for its views and the channel's subscribers (rule 7 of
/// `TelegramChannel`: words, never numbers).
///
/// Liveness: every member takes a `Thing` the caller has already guarded.
enum TelegramPost {
    /// A followed channel's post, not a chat or a saved link.
    static func isChannelPost(_ thing: Thing) -> Bool {
        thing.source == TelegramChannel.source
            && thing.sourceRef?.hasPrefix(TelegramChannel.refPrefix) == true
    }

    /// The channel's handle, off `telegram:post:<channel>/<id>`. The demo's
    /// channels carry a `demo-` marker inside the ref (so teardown is exact),
    /// which is not part of the name.
    static func handle(_ thing: Thing) -> String? {
        guard isChannelPost(thing), let ref = thing.sourceRef else { return nil }
        let tail = ref.dropFirst(TelegramChannel.refPrefix.count)
        guard let slash = tail.firstIndex(of: "/") else { return nil }
        var name = String(tail[..<slash])
        if name.hasPrefix("demo-") { name.removeFirst("demo-".count) }
        return TelegramChannel.isValidHandle(name) ? name : nil
    }

    /// Whose post this repeats: the feed landing keeps a forward's source on
    /// `postAuthor` and tags the row Forwarded.
    static func forwardedFrom(_ thing: Thing) -> String? {
        guard isChannelPost(thing), thing.tags.contains("Forwarded") else { return nil }
        let name = (thing.postAuthor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// The channel's own name — the row's feed identity, never the forward's.
    static func channelName(_ thing: Thing) -> String? {
        guard isChannelPost(thing) else { return nil }
        let name = (thing.authorHandle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    static func views(_ thing: Thing) -> String? {
        thing.factList.first { $0.action == .views }?.value
    }

    static func subscribers(_ thing: Thing) -> String? {
        thing.factList.first { $0.action == .subscribers }?.value
    }
}

/// "Forwarded from Tram 28 Notes" over a forwarded post's words.
struct TelegramForwardLine: View {
    let name: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Image(systemName: "arrowshape.turn.up.right")
                .dsGlyph(.caption)
                .foregroundStyle(DS.textSecondary)
                .accessibilityHidden(true)
            Text("Forwarded from \(Text(verbatim: name).foregroundStyle(DS.textPrimary))")
                .dsText(.subhead12)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// How many saw a channel post, as the page worded it ("1.63M views").
struct TelegramViewsLine: View {
    let views: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Image(systemName: "eye")
                .dsGlyph(.caption)
                .accessibilityHidden(true)
            Text("\(views) views")
                .dsText(.subhead12)
        }
        .foregroundStyle(DS.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
