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

// MARK: - All: kind-aware row (mock A2)

/// One row, kind whispers: time-led events, verb-led transactions, thumb-led
/// photos, snippet mail — everything else is the universal FeedRow.
struct KindAwareRow: View {
    let thing: Thing

    var body: some View {
        switch thing.kind {
        case .event:       AgendaRow(thing: thing, emphasized: false)
        case .transaction: TxRow(thing: thing)
        case .screenshot:  ThumbRow(thing: thing)
        case .mail:        MailRow(thing: thing)
        default:           FeedRow(thing: thing)
        }
    }
}

// MARK: - Approval — the consent card (the ONE rhythm-breaker)

/// An agent's ask as a card: provenance eyebrow, the ask, Approve/Deny pills.
/// The card IS the consent surface (S10) — tapping commits, no extra dialog.
struct ApprovalCard: View {
    let thing: Thing
    var onApprove: () -> Void
    var onDeny: () -> Void

    private var eyebrow: String {
        [thing.provenance.app, thing.provenance.agent, thing.provenance.machine]
            .compactMap { $0 }.joined(separator: " · ").uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(eyebrow)
                .dsText(.label12).kerning(1)
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

// MARK: - Calendar: agenda row (mock C2 — no hero; the next row is emphasized)

struct AgendaRow: View {
    let thing: Thing
    var emphasized: Bool

    private var isPast: Bool { thing.capturedAt < .now }
    private var timeText: String {
        thing.capturedAt.formatted(date: .omitted, time: .shortened)
    }
    private var countdown: String? {
        guard emphasized else { return nil }
        let mins = Int(thing.capturedAt.timeIntervalSinceNow / 60)
        guard mins >= 0 else { return nil }
        return mins < 60 ? "in \(max(1, mins)) min" : "in \(mins / 60)h"
    }

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            Text(timeText)
                .dsText(.subhead13).monospacedDigit()
                .fontWeight(emphasized ? .bold : .regular)
                .foregroundStyle(isPast ? DS.textTertiary : DS.textPrimary)
                .frame(width: 58, alignment: .trailing)
            Capsule(style: .continuous)
                .fill(emphasized ? DS.tint : (isPast ? DS.gray300 : DS.gray200))
                .frame(width: 3, height: emphasized ? 34 : 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(thing.title)
                    .dsText(.body17)
                    .fontWeight(emphasized ? .semibold : .regular)
                    .foregroundStyle(isPast ? DS.textTertiary : DS.textPrimary)
                    .strikethrough(isPast && thing.mark == .done, color: DS.textTertiary)
                    .lineLimit(1)
                if !thing.content.isEmpty {
                    Text(thing.content)
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let countdown {
                Text(countdown).dsText(.label12).foregroundStyle(DS.tint)
            } else {
                if let project = thing.tags.first(where: { ThingKind.from(typeTag: $0) == nil }) {
                    TagPill(project)
                }
            }
        }
        .padding(.vertical, DS.Space.s1)
    }
}

// MARK: - Zerion: transaction row (verb leads — mock Z1)

struct TxRow: View {
    let thing: Thing

    /// "Swapped 0.5 ETH → 1,240 USDC" → verb "Swapped", amount the rest.
    private var parts: (verb: String, amount: String) {
        let words = thing.title.split(separator: " ", maxSplits: 1)
        guard words.count == 2 else { return ("", thing.title) }
        return (String(words[0]), String(words[1]))
    }

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            Text(parts.verb)
                .dsText(.subhead13)
                .foregroundStyle(parts.verb == "Received" ? DS.confirm : DS.textSecondary)
                .frame(width: 70, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(parts.amount)
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                if !thing.content.isEmpty {
                    Text(thing.content)
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            LiveTimeText(date: thing.capturedAt)
        }
        .padding(.vertical, DS.Space.s1)
    }
}

// MARK: - Gmail: subject + snippet (mock G1)

struct MailRow: View {
    let thing: Thing

    private var handled: Bool { thing.mark == .done }

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            KindGlyph(kind: thing.kind, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(thing.title)
                    .dsText(.body17)
                    .foregroundStyle(handled ? DS.textSecondary : DS.textPrimary)
                    .lineLimit(1)
                if !thing.content.isEmpty {
                    Text(thing.content)
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let project = thing.tags.first(where: { ThingKind.from(typeTag: $0) == nil }) {
                TagPill(project)
            }
            LiveTimeText(date: thing.capturedAt)
        }
        .padding(.vertical, DS.Space.s1)
    }
}

// MARK: - Photos: thumb-led row (All) and grid cell (Photos shape)

/// The All-feed whisper: a 44pt thumbnail well where the glyph would sit.
struct ThumbRow: View {
    let thing: Thing

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            PhotoWell(thing: thing, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(thing.title)
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Text(thing.source)
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            }
            Spacer()
            if let project = thing.tags.first(where: { ThingKind.from(typeTag: $0) == nil }) {
                TagPill(project)
            }
            LiveTimeText(date: thing.capturedAt)
        }
        .padding(.vertical, DS.Space.s1)
    }
}

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
        let assetID = ref.replacingOccurrences(of: "phasset:", with: "")
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = assets.firstObject else { return }
        let side = (size ?? 300) * 3
        image = await withCheckedContinuation { cont in
            var reported = false
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: side, height: side),
                contentMode: .aspectFill, options: nil
            ) { img, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !degraded, !reported { reported = true; cont.resume(returning: img) }
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
                Text((project ?? thing.source).uppercased())
                    .dsText(.label12).kerning(1)
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

    private var done: Bool { thing.mark == .done }

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
            Spacer()
            if let project = thing.tags.first(where: { ThingKind.from(typeTag: $0) == nil }) {
                TagPill(project)
            }
            LiveTimeText(date: thing.capturedAt)
        }
        .padding(.vertical, DS.Space.s1)
    }
}

// MARK: - Safari / Notes / You / agents — the derived pattern

/// Safari: the link IS the row — bold title, domain subline; read dims.
struct LinkRow: View {
    let thing: Thing

    private var domain: String? {
        Capture.detectURL(in: thing.content.isEmpty ? thing.title : thing.content)?
            .host()?.replacingOccurrences(of: "www.", with: "")
    }

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(thing.title)
                    .dsText(.body17).fontWeight(.semibold)
                    .foregroundStyle(thing.mark == .done ? DS.textSecondary : DS.textPrimary)
                    .lineLimit(2)
                if let domain {
                    Text(domain).dsText(.subhead13).foregroundStyle(DS.textTertiary)
                }
            }
            Spacer()
            LiveTimeText(date: thing.capturedAt)
        }
        .padding(.vertical, DS.Space.s1)
    }
}

/// Notes: the content is the row — no glyph ceremony.
struct NoteRow: View {
    let thing: Thing

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(thing.title)
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                if !thing.content.isEmpty, thing.content != thing.title {
                    Text(thing.content)
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let project = thing.tags.first(where: { ThingKind.from(typeTag: $0) == nil }) {
                TagPill(project)
            }
            LiveTimeText(date: thing.capturedAt)
        }
        .padding(.vertical, DS.Space.s1)
    }
}

/// You: a voice note leads with its waveform.
struct VoiceRow: View {
    let thing: Thing

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            HStack(spacing: 2) {
                ForEach(Array([10, 16, 22, 14, 18, 9].enumerated()), id: \.offset) { _, h in
                    Capsule().fill(DS.tint).frame(width: 3, height: CGFloat(h))
                }
            }
            .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(thing.title)
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Text("Voice note")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            }
            Spacer()
            LiveTimeText(date: thing.capturedAt)
        }
        .padding(.vertical, DS.Space.s1)
    }
}

/// OpenClaw / Bankr: a run/job/output with a status tick; approvals render as
/// the consent card above the groups.
struct StatusTickRow: View {
    let thing: Thing

    private var subline: String {
        [thing.provenance.machine, thing.provenance.agent, thing.provenance.run]
            .compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            KindGlyph(kind: thing.kind, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(thing.title)
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                if !subline.isEmpty {
                    Text(subline)
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if thing.mark == .done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(DS.confirm)
            } else {
                Circle().fill(DS.tint).frame(width: 8, height: 8)
            }
            LiveTimeText(date: thing.capturedAt)
        }
        .padding(.vertical, DS.Space.s1)
    }
}
