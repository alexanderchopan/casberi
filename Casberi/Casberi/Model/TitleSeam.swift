import Foundation

/// **A TITLE CARRIES NO SEPARATORS (prd §915).** A thing's title names its
/// OBJECT; anything the bridge knows beside the object — the verb, the kind,
/// the board, the ticker, the game — is a QUALIFIER, and the row draws it on
/// the line under the name, never inside the name with a dash or a dot.
///
/// The seam is ` — `, the mark `MusicRow` has split "Nightcall — Kavinsky" on
/// since the first music room, generalised: every row (`BandRow`), the cover
/// (`FeedLedeCard`), the media well and the sheet split a stored title at its
/// LAST seam and draw the two halves in the anatomy's two slots. A bridge
/// composes with `join`, which clamps the OBJECT so the qualifier survives the
/// 80-character title line — the §303 ruling ("the verdict leads, or the clamp
/// eats it") kept the other way round, because the verdict is now the half
/// the clamp never reaches.
///
/// **Why the last seam.** The ingest appends the qualifier last, so a title
/// whose object itself holds a dash ("Human Interface Guidelines — Materials"
/// written by hand) still splits where the reader expects; an object with two
/// dashes keeps its first one. Known and accepted: a hand-typed title with a
/// dash and no qualifier splits too — undetectable without a stored field,
/// and the halves are still the person's own words in the right order.
///
/// Foundation-only, so every bridge harness can compile it beside the shape it
/// tests. `title-seam-audit.py` fails a bridge that composes a title with
/// ` · ` instead.
enum TitleSeam {
    /// The one mark between an object and its qualifier.
    static let mark = " — "

    /// The title line's ceiling, `IngestSupport.titleLine`'s own number.
    static let cap = 80

    /// `object — qualifier`, the object clamped so the qualifier is whole.
    /// An empty or nil qualifier is the object alone; an empty object is the
    /// qualifier alone, never a leading seam.
    static func join(_ object: String, _ qualifier: String?, cap: Int = cap) -> String {
        let object = object.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        let qualifier = (qualifier ?? "").replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !qualifier.isEmpty else { return clamp(object, to: cap) }
        guard !object.isEmpty else { return clamp(qualifier, to: cap) }
        let room = max(8, cap - mark.count - qualifier.count)
        return clamp(object, to: room) + mark + qualifier
    }

    /// The two halves a row draws: the name, and the line under it (nil when
    /// the title has no seam).
    static func split(_ title: String) -> (name: String, line: String?) {
        let parts = title.components(separatedBy: mark)
        guard parts.count > 1, let last = parts.last,
              !last.trimmingCharacters(in: .whitespaces).isEmpty else { return (title, nil) }
        let name = parts.dropLast().joined(separator: mark)
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return (title, nil) }
        return (name, last)
    }

    /// The name alone — what a surface with one slot draws.
    static func name(_ title: String) -> String { split(title).name }

    /// At most `cap` characters, the ellipsis counted — so a joined title is
    /// never longer than the title line and `IngestSupport.titleLine` has
    /// nothing left to eat.
    private static func clamp(_ text: String, to cap: Int) -> String {
        text.count > cap ? String(text.prefix(max(1, cap - 1))) + "…" : text
    }
}
