import SwiftUI
import Photos

/// Shaped Feed rows (docs/handoff-shaped-feeds.md) — when one source is in
/// force the feed takes that source's native shape; "All" renders kind-aware
/// rows that borrow a whisper of their source's shape. These are the row
/// views; FeedScreen dispatches them and keeps day groups, swipes, pins, the
/// sheet, and the write-confirm ruling intact around them.
///
/// Discipline (the doc's rule 2): rows keep height and rhythm. Only
/// `.approval` breaks rhythm — the consent card.

// MARK: - The band row (B2b ruling 2026-07-06)

/// THE feed row: one line on a field of its kind's color. The icon says
/// where it came from, the wash says what it is, the right stack carries
/// time over the project name — plain tinted text, never a chip (a chip
/// means tappable; this is a label). Every kind, same anatomy.
struct BandRow: View {
    let thing: Thing
    var emphasized: Bool = false
    @Environment(\.colorScheme) private var scheme

    private var done: Bool { thing.mark == .done }

    private var project: String? {
        thing.tags.first { ThingKind.from(typeTag: $0) == nil }
    }

    /// Events carry their clock time inline — the left time column died.
    private var titleText: String {
        thing.kind == .event
            ? "\(thing.title) · \(thing.capturedAt.formatted(date: .omitted, time: .shortened))"
            : thing.title
    }

    /// The project writes in ITS color (V3b): stable per name, same hue on
    /// every surface. Light mode pulls it toward black for contrast.
    private var projectInk: Color {
        guard let project else { return DS.textTertiary }
        let base = ProjectHue.color(for: project)
        return scheme == .light ? base.mix(with: .black, by: 0.35) : base
    }

    private var countdown: String? {
        guard emphasized else { return nil }
        let mins = Int(thing.capturedAt.timeIntervalSinceNow / 60)
        guard mins >= 0 else { return nil }
        return mins < 60 ? "in \(max(1, mins)) min" : "in \(mins / 60)h"
    }

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            BridgeIcon(name: thing.source, size: 26)
            Text(titleText)
                .dsText(.body17)
                .fontWeight(emphasized ? .semibold : .regular)
                .foregroundStyle(done ? DS.textTertiary : DS.textPrimary)
                .strikethrough(done, color: DS.textTertiary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 1) {
                if let countdown {
                    Text(countdown).dsText(.label12).foregroundStyle(DS.tint)
                } else {
                    LiveTimeText(date: thing.capturedAt)
                }
                if let project {
                    Text(project)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(projectInk)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, DS.Space.s2)
    }
}


// MARK: - All: kind-aware row (now the band, uniformly)


// MARK: - Approval — the consent card (the ONE rhythm-breaker)

/// An agent's ask as a card: provenance eyebrow, the ask, Approve/Deny pills.
/// The card IS the consent surface (S10) — tapping commits, no extra dialog.
struct ApprovalCard: View {
    let thing: Thing
    var onApprove: () -> Void
    var onDeny: () -> Void

    /// WHO is asking leads; the route it came through reads as a route
    /// ("CLAUDE-CODE · VIA OPENCLAW"), and the machine name stays in the
    /// sheet — three flat brand names explained nothing (ruling 2026-07-06).
    private var eyebrow: String {
        let asker = thing.provenance.agent ?? thing.provenance.app
        var parts = [asker]
        if thing.provenance.app.lowercased() != asker.lowercased() {
            parts.append("via \(thing.provenance.app)")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(eyebrow)
                .dsText(.label12)
                .foregroundStyle(DS.textSecondary)
            Text(thing.title)
                .dsText(.heading17).foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !thing.content.isEmpty {
                Text(thing.content)
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .lineLimit(2)
            }
            HStack(spacing: DS.Space.s2) {
                Button(action: onApprove) {
                    Text("Approve").dsText(.label12).foregroundStyle(.black)
                        .padding(.horizontal, DS.Space.s4).frame(height: 32)
                        .background(DS.confirm, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                Button(action: onDeny) {
                    Text("Deny").dsText(.label12).foregroundStyle(DS.textPrimary)
                        .padding(.horizontal, DS.Space.s4).frame(height: 32)
                        .background(DS.fillFaint, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                Spacer()
                LiveTimeText(date: thing.capturedAt)
            }
            .padding(.top, DS.Space.s1)
        }
        .padding(.vertical, DS.Space.s2)
    }
}




// MARK: - Photos: thumb-led row (All) and grid cell (Photos shape)


/// One grid cell (mock P1): the image, title riding the bottom edge over a
/// scrim, day pill on the first photo of each day.
struct PhotoCell: View {
    let thing: Thing
    var dayPill: String?

    var body: some View {
        PhotoWell(thing: thing, size: nil)
            .frame(maxWidth: .infinity)
            .frame(height: 148)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                LinearGradient(colors: [.clear, .black.opacity(0.65)],
                               startPoint: .center, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(thing.title)
                        .dsText(.subhead13).foregroundStyle(.white)
                        .lineLimit(1)
                    if let project = thing.tags.first(where: { ThingKind.from(typeTag: $0) == nil }) {
                        Text(project).dsText(.label12).foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(DS.Space.s2)
            }
            .overlay(alignment: .topLeading) {
                if let dayPill {
                    Text(dayPill)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, DS.Space.s2).frame(height: 22)
                        .background(Color.black.opacity(0.5), in: Capsule(style: .continuous))
                        .padding(DS.Space.s2)
                }
            }
    }
}

/// Loads the PHAsset behind a screenshot thing; honest fallback is the kind's
/// own hue field (demo things carry no asset).
struct PhotoWell: View {
    let thing: Thing
    var size: CGFloat?   // nil = fill available
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable().scaledToFill()
            } else {
                ZStack {
                    thing.kind.hue.opacity(0.22)
                    Image(systemName: "photo")
                        .font(.system(size: (size ?? 100) * 0.34, weight: .medium))
                        .foregroundStyle(thing.kind.hue)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size != nil ? DS.Radius.appIcon(size!) : 0,
                                    style: .continuous))
        .task(id: thing.sourceRef) { await load() }
    }

    private func load() async {
        guard image == nil, let ref = thing.sourceRef else { return }
        // Sample things carry the bundled photo — the demo shows a real
        // image, never a gray well.
        if ref.hasPrefix("sample:") {
            image = UIImage.demoSample(for: ref)
            return
        }
        let assetID = ref.replacingOccurrences(of: "phasset:", with: "")
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = assets.firstObject else { return }
        let side = (size ?? 300) * 3
        image = await withCheckedContinuation { cont in
            let opts = PHImageRequestOptions()
            opts.isNetworkAccessAllowed = true   // iCloud-optimized originals
            opts.deliveryMode = .highQualityFormat
            var reported = false
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: side, height: side),
                contentMode: .aspectFill, options: opts
            ) { img, _ in
                if !reported { reported = true; cont.resume(returning: img) }
            }
        }
    }
}

// MARK: - ChatGPT / Claude: the earned takeaway card

/// Pinned or in-motion chats earn a card — the saved synthesis line IS the
/// content. No buttons (verbs live in the sheet and swipes).
struct TakeawayCard: View {
    let thing: Thing

    private var project: String? {
        thing.tags.first { ThingKind.from(typeTag: $0) == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s2) {
                Text((project ?? thing.source))
                    .dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
                Spacer()
                LiveTimeText(date: thing.capturedAt)
                if thing.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.tint)
                        .frame(width: 24, height: 24)
                }
            }
            Text(thing.title)
                .dsText(.heading17).foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !thing.content.isEmpty {
                Text(thing.content)
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, DS.Space.s2)
    }
}

// MARK: - Reminders: the check row (the lightest write, consent inline)

struct CheckRow: View {
    let thing: Thing
    var onToggle: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var done: Bool { thing.mark == .done }

    private var project: String? {
        thing.tags.first { ThingKind.from(typeTag: $0) == nil }
    }

    private var projectInk: Color {
        guard let project else { return DS.textTertiary }
        let base = ProjectHue.color(for: project)
        return scheme == .light ? base.mix(with: .black, by: 0.35) : base
    }

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .strokeBorder(done ? DS.tint : DS.gray300, lineWidth: 1.5)
                        .background(Circle().fill(done ? DS.tint : .clear))
                        .frame(width: 24, height: 24)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(DS.Space.s1)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? "Mark not done" : "Mark done")
            Text(thing.title)
                .dsText(.body17)
                .foregroundStyle(done ? DS.textTertiary : DS.textPrimary)
                .strikethrough(done, color: DS.textTertiary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 1) {
                LiveTimeText(date: thing.capturedAt)
                if let project {
                    Text(project)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(projectInk)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, DS.Space.s1)
    }
}

// MARK: - Safari / Notes / You / agents — the derived pattern




