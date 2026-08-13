import SwiftUI
import Photos
import UIKit

/// The screenshot itself, full screen and zoomable (2026-08-02).
///
/// Why this exists: the thing sheet's only screenshot verb used to be "Open in
/// Photos", and it could never do what its name promised. iOS publishes no URL
/// that opens a SPECIFIC asset — `photos-redirect://` lands on the Photos app's
/// root at best — and when nothing claims that scheme the tap does nothing at
/// all, silently, because neither `UIApplication.open`'s completion nor
/// SwiftUI's `openURL` reports a refusal (the blindness the WalletConnect `wc:`
/// read already paid for). A disc that reads live and is inert is exactly the
/// dead control the honesty rule bans. The app already holds the pixels, so the
/// photo opens HERE, where it cannot fail.
///
/// Takes plain values, never the `Thing` — nothing to keep alive, so none of
/// the `isLive` guard chain (`ThingRowKeying.swift`) applies to it, and a heal
/// deleting the row under an open viewer just leaves the picture on screen.
struct PhotoViewer: View {
    /// The `PHAsset` localIdentifier (or a `sample:` demo ref).
    let assetRef: String?
    /// The corpus's own healed copy — shown INSTANTLY so the viewer never
    /// opens on a spinner, then replaced by the full-resolution asset.
    let stored: Data?
    let title: String

    @Environment(\.dismiss) private var dismiss
    /// The shell redacts itself on background (`RootShell.redactNow`, driven by
    /// privacy.hidePreviews). `.redacted(.placeholder)` blanks Text and shapes
    /// but NOT Image, and a full-screen screenshot is the largest leak this app
    /// could put in the app-switcher snapshot — so, like `PhotoWell`, it opts
    /// out by hand rather than trusting the modifier.
    @Environment(\.redactionReasons) private var redaction

    @State private var image: UIImage?
    /// Set only once every route to a picture has been tried and none answered
    /// — the viewer then says so instead of holding an empty black screen.
    @State private var missing = false

    var body: some View {
        ZStack {
            // Black on purpose in BOTH themes: pixels recess into the dark, and
            // an adaptive ground would put a light-mode screenshot on white
            // with white chrome over it. Nothing here uses adaptive tokens.
            Color.black.ignoresSafeArea()
            if !redaction.isEmpty {
                EmptyView()
            } else if let image {
                ZoomableImage(image: image)
                    .ignoresSafeArea()
                    .accessibilityLabel(Text(title))
            } else if missing {
                // The honest end (no fake status): the row survives its Photos
                // original being deleted, but the picture doesn't.
                VStack(spacing: DS.Space.s2) {
                    Image(systemName: "photo")
                        .accessibilityHidden(true)
                        .dsGlyph(26, weight: .regular)
                    Text("This photo isn't in your library anymore")
                        .dsText(.subhead13)
                }
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, DS.Space.s6)
                .multilineTextAlignment(.center)
            }
        }
        .overlay(alignment: .topTrailing) { closeButton }
        .task { await load() }
    }

    /// Glass, and legitimately so: this is the floating layer over content,
    /// the one place the design law allows it.
    ///
    /// CLEAR glass, and this is the app's only screen that earns it
    /// (2026-08-06): every other floating element here sits over rows and words,
    /// where the frosting IS the legibility. Here it sits over a photograph
    /// shown full-bleed on black — the brightest, busiest thing the app ever
    /// draws — and a frosted disc over that reads as a smudge on the picture
    /// instead of a control above it. The glyph is white and semibold on a dark
    /// ground either way, so nothing legible was traded for it.
    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .dsGlyph(15)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                // The glass moved INSIDE the label on 2026-08-13 so the target
                // could grow without the disc growing with it. A `contentShape`
                // wrapped around the Button would not have worked: it sizes the
                // container, not the button's own interaction region, so the
                // frame has to be in the label — and with `dsGlass` still on the
                // Button, a 44pt label would have drawn a 44pt squircle at
                // radius 18 instead of this 36pt circle. Same pixels, bigger
                // target, on the one screen where the only control is a bare
                // glyph over a full-bleed photograph.
                .dsGlass(cornerRadius: 18, variant: .clear)
                .dsTapTarget(Circle())
        }
        .buttonStyle(.plain)
        .dsHover()
        .padding(DS.Space.s4)
        .accessibilityLabel(Text("Close"))
        // The only control on the screen, and it's a bare glyph — on Mac the
        // cursor gets the same word VoiceOver reads.
        .dsTooltip(String(localized: "Close"))
    }

    /// Same load ORDER as `PhotoWell` and `ThingShareLink` — a fourth copy of
    /// the ladder, but each has a different target size and a different
    /// fallback, and the one place that skipped a rung (`ScreenshotContent`)
    /// is exactly where the sheet went blank while the row behind it drew fine.
    ///
    /// The difference here: the stored thumbnail is not the ANSWER, it's the
    /// first paint. A zoomable viewer wants real pixels, so the asset read runs
    /// even when the corpus copy already showed something, and swaps in when it
    /// lands. That keeps the viewer off a spinner without settling for a
    /// ~480pt image under a 6× zoom.
    private func load() async {
        if let stored, let saved = UIImage(data: stored) { image = saved }
        guard let ref = assetRef else {
            missing = image == nil
            return
        }
        if ref.hasPrefix("sample:") {
            if let sample = UIImage.demoSample(for: ref) { image = sample }
            missing = image == nil
            return
        }

        let assetID = ref.replacingOccurrences(of: "phasset:", with: "")
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
            .firstObject else {
            missing = image == nil
            return
        }
        let opts = PHImageRequestOptions()
        opts.isNetworkAccessAllowed = true   // iCloud-optimized originals
        opts.deliveryMode = .highQualityFormat
        opts.resizeMode = .none
        let full: UIImage? = await withCheckedContinuation { cont in
            var reported = false
            PHImageManager.default().requestImage(
                for: asset,
                // The original's own pixels — this is the one surface in the
                // app you can zoom into, and every other loader here is
                // deliberately bounded for a thumbnail. Safe at this size
                // because the assets are screenshots: phone-screen bounded,
                // never a 100MP panorama.
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: opts
            ) { img, info in
                // Network-backed assets call back twice: a degraded
                // placeholder first, the real image second — waiting past the
                // placeholder so the download isn't discarded (the same fix
                // GenCover / PhotoWell / ThingShareLink each carry).
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if degraded { return }
                guard !reported else { return }
                reported = true
                cont.resume(returning: img)
            }
        }
        if let full {
            image = full
        } else if image == nil {
            missing = true
        }
    }
}

/// Pinch, pan and double-tap over one image.
///
/// A `UIScrollView` rather than SwiftUI gestures, deliberately: zoom-and-pan is
/// precisely the scroll-vs-gesture arbitration this codebase has lost before
/// (the retired `BoardDragDriver`, and the standing "never a custom swipe
/// DragGesture in scroll content" rule). `UIScrollView` has done it correctly
/// since 2007 — rubber-banding, momentum, zoom bounce and all — for free.
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ZoomScrollView {
        let scroll = ZoomScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 6
        scroll.bouncesZoom = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.backgroundColor = .black
        scroll.contentInsetAdjustmentBehavior = .never

        let view = UIImageView(image: image)
        view.contentMode = .scaleAspectFit
        view.isUserInteractionEnabled = true
        scroll.addSubview(view)
        context.coordinator.imageView = view

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)

        // Laying out from the scroll view's OWN `layoutSubviews` rather than
        // `updateUIView`: SwiftUI does not call the latter on every bounds
        // change (rotation, the cover settling in), and a viewer that never
        // re-fits reads as a broken image rather than a missed layout pass.
        scroll.onLayout = { [weak scroll, weak coordinator = context.coordinator] in
            guard let scroll, let coordinator else { return }
            coordinator.layout(scroll)
        }
        return scroll
    }

    func updateUIView(_ scroll: ZoomScrollView, context: Context) {
        // The full-resolution image replacing the corpus thumbnail mid-view.
        // Identity, not equality — `UIImage` has no cheap `==`, and the swap
        // only ever happens once.
        guard context.coordinator.imageView?.image !== image else { return }
        context.coordinator.imageView?.image = image
        scroll.setZoomScale(1, animated: false)
        context.coordinator.layout(scroll)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?
        /// Re-fitting only when the size REALLY changed. Writing `frame` from
        /// inside a layout pass otherwise re-enters it, and doing so mid-zoom
        /// fights the transform `UIScrollView` is applying.
        private var lastSize: CGSize = .zero

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { center(scrollView) }

        func layout(_ scroll: UIScrollView) {
            guard let imageView else { return }
            let size = scroll.bounds.size
            guard size.width > 0, size.height > 0 else { return }
            if size != lastSize {
                lastSize = size
                scroll.setZoomScale(1, animated: false)
                imageView.frame = CGRect(origin: .zero, size: size)
                scroll.contentSize = size
            }
            center(scroll)
        }

        /// Keeps a zoomed-out image in the middle of the screen: the scroll
        /// view pins content to the top-left otherwise, which reads as the
        /// picture sliding off as you pinch back out.
        private func center(_ scroll: UIScrollView) {
            let content = scroll.contentSize
            let bounds = scroll.bounds.size
            let x = max(0, (bounds.width - content.width) / 2)
            let y = max(0, (bounds.height - content.height) / 2)
            scroll.contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            if scroll.zoomScale > scroll.minimumZoomScale {
                scroll.setZoomScale(scroll.minimumZoomScale, animated: true)
                return
            }
            // Zoom AT the tap, not at the middle — double-tapping a line of
            // text in a screenshot should bring that line closer.
            let scale = min(scroll.maximumZoomScale, 3)
            let point = gesture.location(in: imageView)
            let size = CGSize(width: scroll.bounds.width / scale,
                              height: scroll.bounds.height / scale)
            scroll.zoom(to: CGRect(x: point.x - size.width / 2,
                                   y: point.y - size.height / 2,
                                   width: size.width, height: size.height),
                        animated: true)
        }
    }
}

/// A `UIScrollView` that reports its own layout passes — see `makeUIView`.
private final class ZoomScrollView: UIScrollView {
    var onLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}
