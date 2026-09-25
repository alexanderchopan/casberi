import SwiftUI

/// A screenshot's sheet shows the picture BIG (prd §885).
///
/// The feed draws a screenshot as a 148pt tile and Photos as a thumbnail, so
/// the sheet is the one place it can be seen at size — and it drew it at
/// `maxHeight: 280`, aspect-fit and flush left, which made a phone screenshot
/// a 130pt-wide sliver. It spans the column now at its own shape, up to
/// `tallest`; a taller one keeps its TOP (where a screen's point usually is)
/// and the tap or Zoom has the whole of it.
///
/// **The shape is known before the pixels.** `SheetPictureFrame` takes the
/// picture's aspect — a Photos asset's own pixel size, read with the fetch,
/// before the image arrives — so the frame never jumps from one shape to
/// another while the sheet is open.
struct SheetPicture: View {
    let image: UIImage?
    /// Height over width. nil until something has said what shape it is.
    let aspect: CGFloat?

    /// The most a picture may take before the head under it leaves the first
    /// screen: the eyebrow, a two-line title and the dial still fit beneath
    /// 560pt on a 6.1-inch phone.
    static let tallest: CGFloat = 560

    var body: some View {
        SheetPictureFrame(aspect: aspect ?? 1, cap: Self.tallest) {
            Color.clear
                .overlay(alignment: .top) {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        DS.fillFaint
                    }
                }
                .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
    }
}

/// The column's width, the picture's own height for it, capped. A `Layout`
/// rather than a `GeometryReader` or a width held in `@State`, because the
/// height is a function of the width it is PROPOSED — decided in one pass, so
/// a first frame can never draw it at a placeholder size (docs/gotchas.md,
/// prd §805).
struct SheetPictureFrame: Layout {
    let aspect: CGFloat
    let cap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        return CGSize(width: width, height: min(width * aspect, cap))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

/// What sits under a big picture (prd §885): what it is and the day, then its
/// title — the article and post heads' order (§882, §884), with the picture
/// in the lead's place.
///
/// **The day is the divider's word** (`FeedScreen.dayWord`, §882), the head's
/// only brand ink (`day-divider-audit.py` check 5).
struct PictureSheetHead: View {
    let thing: Thing
    /// The eyebrow's door to the source's room — nil where it has none.
    var onSource: (() -> Void)? = nil

    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
        // The title's seam (prd §915): "Saturday's match — our view" is the
        // name at the head rung and its tail on the line under it.
        let seam = TitleSeam.split(thing.title)
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            eyebrow
            Text(seam.name)
                .dsText(.heading24)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let line = seam.line {
                Text(verbatim: line)
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, DSRoomChassis.leadInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var eyebrow: some View {
        if let onSource {
            Button {
                DSHaptic.tap()
                onSource()
            } label: {
                eyebrowLine.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsHover()
        } else {
            eyebrowLine
        }
    }

    private var eyebrowLine: some View {
        HStack(spacing: DS.Space.s2) {
            BridgeIcon(name: thing.source, size: DS.Face.row, circular: true)
                .coinFlip(trigger: thing.id)
            Text(thing.kind.typeTag)
                .dsText(.label12)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
            Spacer(minLength: DS.Space.s2)
            Text(FeedScreen.dayWord(thing.capturedAt))
                .dsText(.label12)
                .foregroundStyle(DS.brandInk)
                .lineLimit(1)
        }
    }
}
