import SwiftUI

/// A seller in the Circle x402 room (2026-08-06).
///
/// The room shipped with no `Shape` case at all, so it fell to `.plain` and drew
/// a `BandRow` per row: an icon, `titleLine`'s 80-character clamp, and a
/// timestamp — twenty-two of them wearing the same Circle glyph and the same
/// minute. Exactly §313's X-room defect, and for the same reason: the facts that
/// distinguish these rows were already in the store and on no screen. **What a
/// call costs is this room's whole differentiating fact** and it lived on
/// `summary`, visible only if you opened the sheet.
///
/// Four fields, all of which already existed — no new `Thing` property, so no
/// CloudKit deploy:
///
///   • `authorHandle`  the seller's name, leading (stamped at land, healed onto
///                     older rows on the dedupe hit)
///   • `title`         "Name · pitch", from which the pitch is taken
///   • `summary`       "12 services · $0.01–$0.03 a call"
///   • `tags`          the lanes, of which the first rides the trailing slot
///
/// **The trailing slot is the lane, not the time**, and that is the same
/// judgement the social rows make when they show "/design" or "Liked" instead of
/// a handle. Here it is close to forced: every row in this room shares one
/// timestamp, so a time in that slot is a column of identical text — it costs a
/// reader a glance and tells them nothing.
struct CircleX402Row: View {
    let thing: Thing
    /// The biggest seller in its lane. Earns a larger face and one more line of
    /// pitch — a landmark per shelf, so a run of rows has something to read
    /// down FROM. Deliberately the whole difference: a background, a border or
    /// a card would make it a different component, and this room has one row.
    var lead: Bool = false

    private var faceSize: CGFloat { lead ? 44 : 26 }

    /// Liveness guard (build 188, corollary 5) — SwiftUI re-evaluates a LEAF
    /// view's body on the model's own observation, independent of the parent
    /// that built it, so a guard upstream cannot protect a row already in the
    /// tree.
    var body: some View {
        if thing.isLive { liveBody }
    }

    /// The seller's name, or nil for a row that predates the field and hasn't
    /// been healed yet (it falls back to the whole title, which is what the
    /// room drew before this shape existed — a graceful floor, not a blank).
    private var seller: String? {
        guard let handle = thing.authorHandle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !handle.isEmpty else { return nil }
        return handle
    }

    /// What they do, taken off the title by removing the "Name · " the ingest
    /// composed it with. Nil when the title is the bare name (a seller whose
    /// directory entry carries no description).
    private var pitch: String? {
        let title = thing.title
        guard let seller else { return title.isEmpty ? nil : title }
        let prefix = seller + " · "
        guard title.hasPrefix(prefix) else {
            return title == seller ? nil : title
        }
        let rest = String(title.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? nil : rest
    }

    /// The lane, off the tags the ingest stamped. `"x402"` is the room's own
    /// marker and names no lane, so it is skipped; the first real tag wins.
    private var lane: String? {
        thing.tags.first { $0.caseInsensitiveCompare("x402") != .orderedSame }
    }

    @ViewBuilder private var liveBody: some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            // A real face when the seller's own page gave us one, else the
            // Circle mark — never a placeholder that implies a logo we don't
            // have.
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(seller ?? thing.title)
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                if let pitch {
                    Text(pitch)
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                        .lineLimit(lead ? 3 : 2)
                }
                // The price. Tinted rather than tertiary-grey because it is the
                // reason to read this room at all.
                if let facts = thing.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !facts.isEmpty {
                    Text(facts)
                        .dsText(.label12)
                        .foregroundStyle(DS.brandHue(for: X402Ingest.source) ?? DS.textSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .padding(.top, 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let lane {
                Text(lane)
                    .dsText(.label11)
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 82, alignment: .trailing)
            }
        }
        .padding(.vertical, DS.Space.s2)
    }

    @ViewBuilder private var leading: some View {
        if let url = thing.previewImageURL, let parsed = URL(string: url) {
            AsyncImage(url: parsed) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    BridgeIcon(name: X402Ingest.source, size: faceSize)
                }
            }
            .frame(width: faceSize, height: faceSize)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.appIcon(faceSize),
                                        style: .continuous))
        } else {
            BridgeIcon(name: X402Ingest.source, size: faceSize)
        }
    }
}
