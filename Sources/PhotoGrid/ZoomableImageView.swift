import SwiftUI
import UIKit

/// A `UIScrollView` + `UIImageView` wrapped for SwiftUI — pinch, momentum
/// scrolling, rubber-banding and double-tap-to-zoom come for free and
/// correct from UIKit; hand-rolled gesture recognizers would just reinvent
/// this, worse. Layout follows Apple's own PhotoScroller pattern: the image
/// view's frame is the image's own full pixel size, and `zoomScale` is what
/// actually resizes it on screen.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage?

    func makeUIView(context: Context) -> ZoomScrollView {
        let scrollView = ZoomScrollView()
        scrollView.delegate = context.coordinator
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)

        context.coordinator.scrollView = scrollView
        context.coordinator.imageView = imageView
        scrollView.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.boundsChanged()
        }

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        imageView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: ZoomScrollView, context: Context) {
        context.coordinator.apply(image: image)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Plain `UIScrollView` subclass just to observe `layoutSubviews` —
    /// SwiftUI's `updateUIView` can run before Auto Layout has given the
    /// scroll view its real on-screen bounds, and fitting the image needs
    /// those real bounds, not a zero-size guess.
    final class ZoomScrollView: UIScrollView {
        var onLayout: (() -> Void)?
        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?()
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: ZoomScrollView?
        weak var imageView: UIImageView?
        private var currentImage: UIImage?
        private var lastBoundsSize: CGSize = .zero

        func apply(image: UIImage?) {
            guard image !== currentImage else { return }
            currentImage = image
            imageView?.image = image
            lastBoundsSize = .zero // force a re-fit for the new image
            guard let image else { return }
            imageView?.frame = CGRect(origin: .zero, size: image.size)
            scrollView?.contentSize = image.size
            boundsChanged()
        }

        /// Re-fits the image to the scroll view's current bounds. Only
        /// actually recomputes when the bounds size changed, so a layout
        /// pass mid-pinch doesn't reset the user's zoom.
        func boundsChanged() {
            guard let scrollView, let imageView, let image = currentImage else { return }
            let boundsSize = scrollView.bounds.size
            guard boundsSize.width > 1, boundsSize.height > 1, boundsSize != lastBoundsSize else { return }
            lastBoundsSize = boundsSize
            guard image.size.width > 0, image.size.height > 0 else { return }

            let widthScale = boundsSize.width / image.size.width
            let heightScale = boundsSize.height / image.size.height
            let minScale = min(widthScale, heightScale)
            guard minScale.isFinite, minScale > 0 else { return }

            // Let the user zoom past "fit the screen" up to real pixel
            // resolution and a bit beyond — never below what's needed just
            // to fit the photo, so even a tiny or low-quality image stays
            // inspectable.
            scrollView.minimumZoomScale = minScale
            scrollView.maximumZoomScale = max(minScale * 4, 1)
            imageView.frame = CGRect(origin: .zero, size: image.size)
            scrollView.zoomScale = minScale
            centerImage()
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }

        /// The actual centering math: after a zoom, `imageView.frame` is
        /// resized by the scroll view itself to `imageSize * zoomScale`.
        /// Whenever that's smaller than the scroll view's own bounds on an
        /// axis, center it on that axis instead of pinning it to the
        /// corner — this is what keeps the photo dead-center at every zoom
        /// level, not just at the extremes.
        private func centerImage() {
            guard let scrollView, let imageView else { return }
            let boundsSize = scrollView.bounds.size
            var frame = imageView.frame
            frame.origin.x = frame.width < boundsSize.width ? (boundsSize.width - frame.width) / 2 : 0
            frame.origin.y = frame.height < boundsSize.height ? (boundsSize.height - frame.height) / 2 : 0
            imageView.frame = frame
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale + 0.001 {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let targetScale = min(scrollView.maximumZoomScale, scrollView.minimumZoomScale * 3)
                let size = CGSize(
                    width: scrollView.bounds.width / targetScale,
                    height: scrollView.bounds.height / targetScale
                )
                let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
                scrollView.zoom(to: CGRect(origin: origin, size: size), animated: true)
            }
        }
    }
}
