import SwiftUI

/// The share card's drawing (docs/social-spec.md §2). Four zones, top to
/// bottom: the seat or the author, the picture if there is one, the words,
/// and a foot pinned to the bottom that carries the mark and the app's name
/// in the brand ink — the one place the brand hue lands on the card, because
/// the foot is the app's voice and the words above are the thing's (§742).
///
/// No rail, bar or stripe on any edge: emphasis is ink (the infographic rule,
/// general since 2026-09-07). Nothing counts anything. The type is pinned to
/// `.large` so a person's accessibility size does not change what they send.
///
/// Drawn ONLY through `ShareCard.render` — the colours arrive resolved in
/// `ink`, never read from `DS` here (see `ShareCard`'s type doc).
struct ShareCardView: View {
    let model: ShareCard.Model
    let ink: ShareCard.Ink

    private let pad: CGFloat = 24
    private var hasPicture: Bool { model.picture != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            head
            if let picture = model.picture {
                // Cropped from the TOP, the room's shape for a screenshot
                // (prd §910): the head of a page is what it is about.
                Image(uiImage: picture)
                    .resizable()
                    .scaledToFill()
                    .frame(width: ShareCard.size.width - pad * 2, height: 200, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
            }
            words
            Spacer(minLength: 0)
            foot
        }
        .padding(pad)
        .frame(width: ShareCard.size.width, height: ShareCard.size.height, alignment: .topLeading)
        .background(ink.ground)
        .dynamicTypeSize(.large)
        .environment(\.colorScheme, .dark)
    }

    /// The seat's mark and name, or — for a post — the author's face and
    /// handle, because a post's row leads with the person (prd §756).
    private var head: some View {
        HStack(spacing: 10) {
            if let author = model.author {
                face(for: author)
                VStack(alignment: .leading, spacing: 1) {
                    Text(author).dsText(.label12).foregroundStyle(ink.primary).lineLimit(1)
                    Text("\(model.sourceName) · \(model.day)")
                        .dsText(.subhead12).foregroundStyle(ink.tertiary).lineLimit(1)
                }
            } else {
                BridgeIcon(name: model.source, size: DS.Mark.row, circular: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.sourceName).dsText(.label12).foregroundStyle(ink.primary).lineLimit(1)
                    Text(model.day).dsText(.subhead12).foregroundStyle(ink.tertiary).lineLimit(1)
                }
            }
        }
    }

    /// A face with no picture is the handle's first letter in a circle (§753).
    @ViewBuilder private func face(for author: String) -> some View {
        if let face = model.face {
            Image(uiImage: face)
                .resizable()
                .scaledToFill()
                .frame(width: DS.Mark.row, height: DS.Mark.row)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(ink.fill)
                .frame(width: DS.Mark.row, height: DS.Mark.row)
                .overlay {
                    Text(String(author.drop(while: { $0 == "@" }).prefix(1)).uppercased())
                        .dsText(.label12)
                        .foregroundStyle(ink.secondary)
                }
        }
    }

    /// The statement and the body. A post has no separate title — its words
    /// ARE the statement, at the head rung. The rung is the fit's: a short
    /// title with no picture takes `heading40`, everything else `heading24`,
    /// and the body takes what room is left.
    private var words: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.title.isEmpty {
                Text(model.words)
                    .dsText(!hasPicture && model.words.count <= 60 ? .heading40 : .heading24)
                    .foregroundStyle(ink.primary)
                    .lineLimit(hasPicture ? 4 : 8)
            } else {
                Text(model.title)
                    .dsText(!hasPicture && model.title.count <= 40 ? .heading40 : .heading24)
                    .foregroundStyle(ink.primary)
                    .lineLimit(hasPicture ? 2 : 3)
                if !model.words.isEmpty {
                    Text(model.words)
                        .dsText(.body17)
                        .foregroundStyle(ink.secondary)
                        .lineLimit(hasPicture ? 3 : 7)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var foot: some View {
        HStack(spacing: 8) {
            CasberiMark(size: 20)
            Text(verbatim: "Casberi")
                .dsText(.label12)
                .foregroundStyle(ink.brand)
        }
    }
}
